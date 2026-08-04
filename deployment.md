# Deployment — Inkwoven proxy on Fly.io

**Decision:** Fly.io for the proxy container, Upstash Redis (free tier) for counters/tickets, Neon Postgres (free tier) for the credit ledger.

**Why Fly.io won** (evaluated July 2026):

| Option | Min cost/mo | SSE streaming | Verdict |
|---|---|---|---|
| **Fly.io** (shared-cpu-1x, 256MB, always-on) | **~$2** | Native, no limits | ✅ picked |
| Railway Hobby | $5 flat + overage | Fine | 2.5× the cost for the same box |
| Render free tier | $0 | Fine | Spins down after idle → 30–60s cold start kills ttfs |
| Vercel/Lambda | ~$0 at MVP scale | Awkward (response streaming caps, timeouts) | SSE is our core transport — no |
| Cloudflare Workers | ~$0–5 | Excellent | Fastify doesn't run there; full server rewrite |

Total infra: **~$2–3/month** + model API usage. Every stateful dependency is on a permanent free tier.

---

## 1. What Fly.io is (60-second primer)

Fly.io runs your app as **Machines** — lightweight Firecracker VMs booted from a Docker image, placed in regions you choose. You interact with it through one CLI: `flyctl` (aliased `fly`). Key concepts:

- **App** — a named unit (ours: `inkwoven-proxy`) with a URL `https://inkwoven-proxy.fly.dev`, TLS included, no config.
- **Machine** — one VM instance of the app. We run exactly one, always-on. Billing is per-second; a `shared-cpu-1x / 256MB` machine ≈ $1.94/mo.
- **`fly.toml`** — the config file at the app root (like `package.json` for deployment). Checked into git.
- **Secrets** — encrypted env vars set via CLI (`fly secrets set KEY=value`), never in `fly.toml` or the image.
- **Deploy** — `fly deploy` builds the Docker image (on Fly's builders — you don't need Docker locally), pushes it, and restarts the Machine with health checks.

Why it fits us specifically: Machines speak plain HTTP with no proxy buffering or timeout on responses, so the long-lived SSE stream from `POST /v1/exchange` just works. And single-region placement near model providers keeps the proxy→model hop short, which lands directly in `time_to_first_stroke`.

**One decision to make consciously:** Fly can auto-stop idle machines (scale-to-zero → ~$0.30/mo storage only), but a cold boot adds ~1–3s to the first exchange after idle. Bad for ttfs, bad for the "living book" illusion. At $2/mo, always-on is the right call. Config below pins `min_machines_running = 1`.

---

## 2. Prerequisites

1. **Install flyctl**
   ```sh
   # macOS
   brew install flyctl
   ```
2. **Sign up / log in** (needs a credit card, but you'll only be billed for usage — no plan fee):
   ```sh
   fly auth signup   # or: fly auth login
   ```
3. Node 20 proxy already exists at `app/proxy/` and listens on `process.env.PORT` (defaults 8787), host `0.0.0.0` — exactly what Fly needs. No code changes required for a first deploy (echo mode).

---

## 3. Files to add

Both files go in `app/proxy/`.

### 3.1 `Dockerfile`

The real file is `app/proxy/Dockerfile` — read it there rather than from a
copy that can drift (this section once showed a single-stage image running as
root, which the actual Dockerfile has never been). What it does, and why CI
asserts each of these independently (`.github/workflows/ci.yml`, `proxy-image`):

- **base image pinned by digest**, not just the `-slim` tag, so two deploys
  from one git SHA produce byte-identical images;
- **multi-stage**: build tooling (`build-essential`, `node-gyp`) stays in a
  throw-away stage and never reaches the runtime image;
- **`npm ci --omit=dev`**, so `@flydotio/dockerfile` — scaffolding, and the
  source of the only advisories left in the tree — cannot ship;
- **runs as uid 1000**, never root;
- `ENV NODE_ENV=production`, which is what makes `INK_ATTESTATION_MODE`
  default to fail-closed (§6.5).

### 3.2 `fly.toml`

```toml
app = "inkwoven-proxy"        # must be globally unique; adjust if taken
primary_region = "iad"        # US East (Ashburn) — close to OpenAI/Google/fal.ai endpoints

[build]
  # uses the Dockerfile in this directory

[env]
  PORT = "8787"

[http_service]
  internal_port = 8787
  force_https = true
  auto_stop_machines = "off"   # never scale to zero — protects ttfs
  auto_start_machines = true
  min_machines_running = 1
  processes = ["app"]

  [http_service.concurrency]
    type = "requests"
    soft_limit = 200            # SSE holds connections open; keep limits high
    hard_limit = 250

[[vm]]
  size = "shared-cpu-1x"
  memory = "256mb"

[checks]
  [checks.health]
    type = "http"
    port = 8787
    path = "/health/ready"      # unauthenticated readiness probe — no header needed
    interval = "30s"
    timeout = "5s"
    grace_period = "10s"        # let ioredis/pg finish their first connect
```

> **Health check note:** `/health` and `/health/ready` are the only unauthenticated routes — `src/server.js` exempts them from the auth hook via its `HEALTH_ROUTES` set, so the check sends no `x-ink-user` header. `/health/ready` touches the stores and answers 503 when Redis/Postgres are unreachable, which is what actually pulls a broken machine from the pool. If you ever change the path, it must both be a registered route **and** appear in `HEALTH_ROUTES`; anything else falls through to the auth hook, which 401s the check and restart-loops every machine once attestation is on. (The checked-in `app/proxy/fly.toml` is the source of truth; this sample mirrors it.)

---

## 4. First deploy (echo mode) — ~10 minutes

### 4.1 `fly launch` — pin every default with flags

Bare `fly launch` auto-detects and proposes its own defaults (generated name, region closest to *you* — e.g. Frankfurt, 1GB RAM). Three of those are wrong for us. Every field in that summary screen maps to a flag, so pin them all and skip the guesswork:

```sh
cd app/proxy

fly launch --no-deploy \
  --name inkwoven-proxy \
  --org personal \
  --region iad \
  --vm-size shared-cpu-1x \
  --vm-memory 256 \
  --ha=false \
  --auto-stop off \
  --no-db --no-redis --no-object-storage \
  --no-github-workflow \
  --copy-config
```

What each flag pins (vs. the summary screen):

| Summary field | Default | Flag | Why we override |
|---|---|---|---|
| Organization | personal org | `--org personal` | fine as-is; flag just makes it explicit (`fly orgs list` to see slugs) |
| Name | `proxy-curious-log-9752` (generated) | `--name inkwoven-proxy` | your app URL: `inkwoven-proxy.fly.dev`; must be globally unique |
| Region | Frankfurt (`fra`) — closest to **you** | `--region iad` | proxy must sit near the **model providers** (US East), not near you — every streamed token crosses proxy↔model, that hop dominates ttfs |
| App Machines | `shared-cpu-1x, 1GB` | `--vm-size shared-cpu-1x --vm-memory 256` | 256MB is plenty for an I/O relay; 1GB quadruples compute cost |
| *(hidden)* HA | **2 machines** | `--ha=false` | "high availability" silently doubles the bill; one machine is the MVP plan |
| *(hidden)* auto-stop | `stop` when idle | `--auto-stop off` | scale-to-zero adds 1–3s cold start to the first exchange after idle — kills ttfs |
| Postgres | none | `--no-db` | we use Neon (free tier) instead of Fly Postgres (paid) |
| Redis | none | `--no-redis` | we use Upstash free tier instead of Fly's Upstash add-on |
| Tigris | none | `--no-object-storage` | no object storage needed — media lives at fal.ai URLs |
| *(hidden)* GitHub workflow | may generate one | `--no-github-workflow` | we add our own deploy job to the existing CI (§7) |
| *(hidden)* fly.toml | regenerated | `--copy-config` | use our hand-written `fly.toml` without prompting |

Two gotchas:

- **`fly launch` edits `fly.toml`.** Even with `--copy-config` it may reconcile fields. After launch, `git diff fly.toml` and re-check the values that matter: `primary_region = "iad"`, `[[vm]]` 256mb, `auto_stop_machines = "off"`, `min_machines_running = 1`.
- **Already launched with wrong defaults?** Pre-deploy the cheapest fix is to delete and relaunch: `fly apps destroy proxy-curious-log-9752 --yes`, then rerun the command above. (Post-deploy you'd fix in place: `fly scale memory 256`, `fly scale count 1`, but region moves are clumsier — destroy/relaunch is cleaner while there's nothing running.)

### 4.2 Deploy and watch

```sh
fly deploy    # builds the Dockerfile on Fly's builders, boots the machine
fly logs      # watch it come up
```

Verify from your machine:

```sh
curl -N -H 'x-ink-user: melih-dev' -H 'content-type: application/json' \
  -d '{"bookID":"<a-book-id>"}' \
  https://inkwoven-proxy.fly.dev/v1/exchange
```

You should see `ink_delta` events streaming word-by-word, then `done`. That's the client's staging endpoint from now on.

Useful daily commands:

```sh
fly logs               # tail live logs (structured cost logs appear here)
fly status             # machine state, region, health
fly ssh console        # shell into the running machine
fly deploy             # redeploy after changes
fly dashboard          # open web UI (billing, metrics, machines)
```

---

## 5. State: Upstash Redis + Neon Postgres

Both are serverless, free-tier, and reachable over TLS from Fly — no VPC work.

### 5.1 Upstash Redis (rate limits, tickets, idempotency, daily counters)

Free tier: 256MB, 500K commands/month — far above MVP traffic (each exchange ≈ 4–6 commands; 500K ≈ ~80K exchanges/mo).

1. Sign up at [upstash.com](https://upstash.com) → Create Database → region **us-east-1** (match `iad`).
2. Copy the `REDIS_URL` (`rediss://…`).
3. `fly secrets set REDIS_URL=rediss://...`

### 5.2 Neon Postgres (credit ledger — money needs durability)

Free tier: 0.5GB storage, 100 compute-hours/mo per project. A ledger of append-only rows won't dent either.

1. Sign up at [neon.com](https://neon.com) → New Project → region **US East**.
2. Copy the connection string (`postgresql://…`).
3. `fly secrets set DATABASE_URL=postgresql://...`

Suggested minimal schema when you wire it up:

```sql
CREATE TABLE credit_entries (
  id UUID PRIMARY KEY, user_id TEXT NOT NULL, delta INT NOT NULL,
  reason TEXT NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE credit_holds (
  id UUID PRIMARY KEY, user_id TEXT NOT NULL, amount INT NOT NULL,
  state TEXT NOT NULL DEFAULT 'held',  -- held | settled | released
  at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON credit_entries (user_id);
CREATE INDEX ON credit_holds (user_id, state);
```

### 5.3 Code change

`stores.js` was built to be swapped: keep the same interface, add a `createRedisStores(redisUrl, dbUrl)` factory (e.g. `ioredis` + `pg`), and select in `index.js`:

```js
const stores = process.env.REDIS_URL
  ? createRedisStores(process.env.REDIS_URL, process.env.DATABASE_URL)
  : createStores(); // in-memory for local dev + tests
```

Tests keep running against the in-memory store; production gets durable counters. **Do this before real users** — the in-memory rate limiter and wallet reset on every deploy/restart.

---

## 6. Secrets — getting each key, then storing them

### 6.1 Google — `GEMINI_API_KEY` (gemini-3.5-flash-lite; default text model, 6/8 Books)

> The Books pin **`gemini-3.5-flash-lite`** explicitly (books.js, 2026-08-01) — never the
> `-latest` alias. Google keeps 2.5 / 3.1 / 3.5 Flash-Lite live at $0.10/$0.40 through
> $0.30/$2.50 per 1M, so a silent alias bump would change unit economics without a
> deploy. Bump the pinned version deliberately, together with the §6.6 rate card.

1. Go to [aistudio.google.com](https://aistudio.google.com), sign in with a Google account.
2. Left sidebar → **Get API key** → **Create API key** (pick/create a Google Cloud project when prompted — the default it offers is fine).
3. Copy the key immediately into a password manager.

- **Cost:** free tier is enough for all development (rate-limited, no card needed). Attach billing to the underlying Cloud project only when going live.
- **⚠ 2026 key migration:** new AI Studio keys are "auth keys"; older *standard* keys stop working during 2026 (unrestricted ones rejected from June, all standard keys ~September). Create a fresh key now and you're fine — just don't reuse an old one from a previous project.
- **Budget cap:** Cloud console → Billing → Budgets & alerts on that project.

### 6.2 OpenAI — `OPENAI_API_KEY` (GPT-5 Mini; 2 Books)

1. Sign in at [platform.openai.com](https://platform.openai.com).
2. **Billing first, key second** — keys don't work with a $0 balance: Settings → Organization → **Billing** → *Add credit* (prepaid; $5 minimum, credits expire after 1 year).
3. Create a **Project** (e.g. `inkwoven-proxy`) under Settings → Projects — set its **Monthly budget limit** right there at creation. Project limits are your real spend guardrail.
4. Settings → **API keys** → *Create new secret key* → scope it to the `inkwoven-proxy` project. Copy immediately — it's shown once.

### 6.3 fal.ai — `FAL_API_KEY` (z-image-turbo, flux-2, kling-video-v3-standard — one key for all three)

1. Sign up at [fal.ai](https://fal.ai) (GitHub login works).
2. Dashboard → **Keys** ([fal.ai/dashboard/keys](https://fal.ai/dashboard/keys)) → *Add Key* → name it (`inkwoven-proxy`) → *Create Key*.
3. Copy the key (`fal_sk_…`) — shown once.

- **Cost:** prepaid credits, top up from the dashboard billing page; usage is per-generation (image cents-range, Kling video is the expensive one — which is exactly why video sits behind the credit wallet).
- Set a low auto-top-up ceiling or none at all: a hard stop is safer than a surprise bill for an MVP.

### 6.4 RevenueCat — `REVENUECAT_API_KEY` (entitlement verification — needed at §gate 4, not day one)

1. [app.revenuecat.com](https://app.revenuecat.com) → your project → **API keys**.
2. You want a **secret** key (`sk_…`) for the proxy — the public `appl_…` key is for the iOS SDK only and can't verify subscribers server-side.

Defer this until wiring the server-side entitlement gate; echo mode and text routing don't need it.

### 6.5 `INK_ATTESTATION_MODE` — identity mode (set it, or production 401s everything)

Not an API key, but it lives with the secrets because it gates all of them. The auth seam (`app/proxy/src/attest.js`) resolves every request's `x-ink-user` header through a pluggable verifier and **fails closed**: with `NODE_ENV=production` (the Dockerfile sets it) and `INK_ATTESTATION_MODE` unset, the mode defaults to `required`, which rejects every request with a 401.

The three modes:

- **`anonymous`** — pass-through: the `x-ink-user` token is taken at face value as the identity. The default outside production, correct for local dev, and **refused in production**: `index.js` exits at boot rather than run with identity anyone can mint, because a free identity voids every per-user control (wallets, free-clip caps, daily quotas, grant idempotency).
- **`appattest`** — the real path (`app/proxy/src/appattest.js`): the device proves a Secure Enclave key against a server-issued challenge, the server mints an opaque identity, and requests carry a short-lived signed session token renewed by assertion. This is what v1 ships.
- **`required`** — fail closed, rejecting everything. The production default until `appattest` is set.

**v1 launch ships with:**

```sh
fly secrets set INK_ATTESTATION_MODE=appattest
fly secrets set INK_APPATTEST_ROOT_CA="$(cat AppleAppAttestationRootCA.pem)"
fly secrets set INK_TEAM_ID=77G7KM4549
fly secrets set INK_SESSION_SECRET="$(openssl rand -base64 48)"
```

`INK_BUNDLE_ID` is already required by receipt verification (§6.8) and is
shared. The App Attest root CA is published at
<https://www.apple.com/certificateauthority/> — download it; a certificate
pasted from memory is not a trust anchor. Provider budget caps (§6.1–6.3, §8)
remain the backstop behind identity, not a substitute for it.

### 6.6 `INK_MODEL_PRICING` — the rate card that makes cost logs real

Without it every exchange logs truthful token counts and `unit_cost: null` —
`createPricing` (config.js) refuses to invent a price for a model it has no rate for.
Set it from the published rates current on 1 Aug 2026:

```sh
fly secrets set INK_MODEL_PRICING='{"gemini-3.5-flash-lite":{"inputPer1M":0.30,"outputPer1M":2.50},"gpt-5.4-mini":{"inputPer1M":0.75,"outputPer1M":4.50}}'
```

- **Keys must match the model IDs pinned in `books.js` character for character** — a
  mismatched key silently prices that model at null. This is half the reason the Books
  pin `gemini-3.5-flash-lite` instead of the floating `-latest` alias (§6.1).
- **Known gap (images):** the card is token-based, but fal bills images **per unit**
  (z-image $0.005/MP, flux-2 $0.012/MP on input + output megapixels) — those costs
  cannot ride this card and the cost log reports null for them. Track them in the fal
  dashboard until per-unit accounting exists; do not fake them as token rates.
- Update the card whenever the pinned model version changes, in the same deploy.

### 6.7 `INK_VIDEO_PRICING` — the per-second card for moving pictures

Video does **not** ride the token card above, because fal bills Kling per second of
clip. It gets its own accounting path (`createVideoPricing` in config.js), and the
`route: 'video'` cost log carries `clip_seconds` and `unit_cost` per clip:

```sh
fly secrets set INK_VIDEO_PRICING='{"kling-video-v3-standard":{"perSecond":0.084}}'
```

- $0.084/sec is **standard tier, audio off** — the tier the proxy requests. Pro is
  $0.112/sec and audio adds ~50%; changing tier means changing this card in the same
  deploy, and re-running every number in `design/app-store-assets/credits.md` §3.
- The key must match `books.js`'s `models.video` character for character.
- Failed clips are logged too, with `outcome` and `reject_reason`. That is the
  instrument: the ratio of `outcome: 'delivered'` to everything else is the real
  failure rate that replaces the assumed 8% in credits.md §2, and `payment_kind`
  separates free clips from paid ones so the free-clip budget line is visible.

### 6.8 `INK_APPLE_ROOT_CA` + `INK_BUNDLE_ID` — receipt verification (set them, or grants 501)

`POST /v1/credits/grant` credits the server-side wallet from a StoreKit 2 signed
transaction. "StoreKit verified it on device" is **not** a control here: under
anonymous attestation the client is whatever speaks HTTP, so an unverified grant
is a credit mint, and credits buy clips that cost real money at fal.

`app/proxy/src/receipts.js` therefore verifies the JWS properly — x5c chain,
validity dates, chain signatures, ES256 signature over the payload, and the
bundle id — anchored to Apple's root. **You must supply the anchor.** It is not
in the repo, because a certificate pasted from memory is not a trust anchor.

1. Download **Apple Root CA - G3** from
   [apple.com/certificateauthority](https://www.apple.com/certificateauthority/)
   and convert to PEM if needed: `openssl x509 -inform der -in AppleRootCA-G3.cer -out AppleRootCA-G3.pem`
2. Set both secrets:

```sh
fly secrets set INK_APPLE_ROOT_CA="$(cat AppleRootCA-G3.pem)" INK_BUNDLE_ID='com.empath.inkwoven'
```

With either missing the verifier is null and **every grant answers 501** — the
user is charged by Apple and receives nothing. Verify with `fly secrets list`
before submission, and buy one sandbox pack end to end.

The amount always comes from the server-side product map (`VIAL_GRANTS` in
server.js), never the request body, and the transaction id is the idempotency
key, so a replayed receipt credits exactly once. A revoked or refunded
transaction is rejected.

### 6.9 Store everything in Fly

**Always single-quote values** — URLs contain `?` and `&`, which zsh otherwise mangles (`no matches found`):

```sh
fly secrets set \
  GEMINI_API_KEY='...' \
  OPENAI_API_KEY='...' \
  FAL_API_KEY='fal_sk_...' \
  REVENUECAT_API_KEY='sk_...' \
  REDIS_URL='rediss://default:...@....upstash.io:6379' \
  DATABASE_URL='postgresql://...?sslmode=require' \
  INK_ATTESTATION_MODE='anonymous' \
  INK_BUNDLE_ID='com.empath.inkwoven' \
  INK_APPLE_ROOT_CA="$(cat AppleRootCA-G3.pem)" \
  INK_MODEL_PRICING='{"gemini-3.5-flash-lite":{"inputPer1M":0.30,"outputPer1M":2.50},"gpt-5.4-mini":{"inputPer1M":0.75,"outputPer1M":4.50}}' \
  INK_VIDEO_PRICING='{"kling-video-v3-standard":{"perSecond":0.084}}'
```

Rules:

- Secrets never appear in `fly.toml`, the Dockerfile, or git. `fly secrets set` restarts the machine automatically; `fly secrets list` shows names + digests only, never values.
- **Two keys per provider** where possible: one local-dev key (in `app/proxy/.env`, gitignored), one prod key that exists only in Fly secrets. A leaked dev key then can't touch the prod budget.
- Set the budget cap in each provider console **before** the first real call — Fly infra is ~$2/mo; the model consoles are where a runaway bill would actually come from.
- Missing keys are safe by design: the provider factory returns null → the Book falls back to echo mode. Keys can land one at a time.

---

## 7. CI deploy (GitHub Actions)

The repo already has CI (`.github/workflows/ci.yml`). Add a deploy job that ships the proxy when its tests pass on `main`:

```yaml
deploy-proxy:
  needs: [proxy-tests]        # match the existing proxy test job name
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: superfly/flyctl-actions/setup-flyctl@master
    - run: flyctl deploy --remote-only
      working-directory: app/proxy
      env:
        FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

Create the token with `fly tokens create deploy -a inkwoven-proxy` and add it as a GitHub repo secret named `FLY_API_TOKEN`.

---

## 8. Cost breakdown & guardrails

| Item | Monthly |
|---|---|
| Fly Machine (shared-cpu-1x, 256MB, always-on, iad) | ~$1.94 |
| Fly egress (SSE text is tiny; images/videos served from fal.ai URLs, not proxied) | ~$0 at MVP scale |
| Upstash Redis | $0 (free tier) |
| Neon Postgres | $0 (free tier) |
| **Infra total** | **~$2–3** |
| Model APIs (Flash-Lite / GPT-5 Mini / fal.ai) | usage-based — the real cost; watched by the 30%-of-$9.99 guardrail |

Guardrails to set on day one:

- **Fly:** dashboard → Billing → set a spend alert (e.g. $10).
- **Upstash:** free tier hard-stops rather than bills — safe by default.
- **Neon:** free tier suspends rather than bills — safe by default.
- **Model providers:** set monthly budget caps in each console (Google AI Studio, OpenAI, fal.ai). This is where a runaway bill would actually come from — which is also why App Attest on the auth hook is a pre-launch item, not a nice-to-have.

Scaling later is one command each: `fly scale memory 512`, `fly scale count 2`, or add a region (`fly regions add fra`). Nothing in this setup needs rearchitecting until well past MVP.

---

## 9. Launch checklist

- [ ] `fly launch --no-deploy` + `fly deploy` — echo mode live at `https://inkwoven-proxy.fly.dev`
- [ ] Client `ProxyClient` staging base URL pointed at the Fly URL; end-to-end echo exchange on device
- [ ] Upstash + Neon provisioned (us-east), secrets set
- [ ] `createRedisStores` swap implemented (rate limits, tickets, idempotency, wallet → durable)
- [ ] Server-side entitlement gate — daily moment/image quotas now enforced in `/v1/exchange` before the provider handshake (`LIMITS.plusExchangeDailyCeiling` &c.); prove it with a raw `curl` loop that gets 429 `daily_quota` with no app involved
- [ ] `INK_ATTESTATION_MODE=appattest` + `INK_APPATTEST_ROOT_CA` + `INK_TEAM_ID` + `INK_SESSION_SECRET` set (§6.5) — without them production 401s every request, and `anonymous` will not boot at all. Prove attestation on a REAL device (the simulator cannot attest) and confirm a fabricated `x-ink-user` is refused
- [ ] `INK_REPORT_WEBHOOK_URL` + `INK_ADMIN_TOKEN` set — guideline 1.2 obliges acting on reports within 24 hours; file one test report and confirm the alert lands and `GET /v1/admin/reports` serves it
- [ ] App Store Server Notifications V2 URL pointed at `POST /v1/notifications` in App Store Connect; run a sandbox refund and confirm the wallet is debited and the tier dropped
- [ ] Model provider keys set; real routing on for one Book; cost logs visible in `fly logs`
- [ ] `fly secrets list` shows GEMINI_API_KEY, OPENAI_API_KEY, and FAL_API_KEY actually present — a missing key silently drops that Book to echo mode
- [ ] `INK_APPLE_ROOT_CA` + `INK_BUNDLE_ID` set (§6.8) — without them every vial purchase 501s after the user has paid; buy one sandbox pack end to end to prove it
- [ ] `INK_VIDEO_PRICING` set (§6.7) — without it every clip logs a null cost and the free-clip budget line is invisible
- [ ] **fal budget cap set before the first clip**: video is the only modality that can run a real bill on its own, and the free-clip ceiling protects the free path only
- [ ] One real moving picture generated end to end from a release build: offer → tap → clip → full screen, and a killed app mid-generation returns the credit
- [ ] Budget caps set at Fly + all three model providers
- [ ] One real exchange verified from a **release build** against the production URL before App Store submission
- [ ] App Attest verification on the auth hook
- [ ] CI deploy job green
