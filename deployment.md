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

```dockerfile
FROM node:20-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
EXPOSE 8787
CMD ["node", "src/index.js"]
```

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
    path = "/v1/config"         # cheap authenticated-optional GET; see note below
    interval = "30s"
    timeout = "5s"
    headers = { x-ink-user = "healthcheck" }
```

> **Health check note:** every route currently requires `x-ink-user`, so the check sends a dummy token. If you'd rather not, add an unauthenticated `GET /healthz` route and point the check there — cleaner.

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

### 6.1 Google — `GEMINI_API_KEY` (Flash-Lite; default text model, 6/8 Books)

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

### 6.3 fal.ai — `FAL_API_KEY` (z-image-turbo, flux-2, kling-3 — one key for all three)

1. Sign up at [fal.ai](https://fal.ai) (GitHub login works).
2. Dashboard → **Keys** ([fal.ai/dashboard/keys](https://fal.ai/dashboard/keys)) → *Add Key* → name it (`inkwoven-proxy`) → *Create Key*.
3. Copy the key (`fal_sk_…`) — shown once.

- **Cost:** prepaid credits, top up from the dashboard billing page; usage is per-generation (image cents-range, Kling video is the expensive one — which is exactly why video sits behind the credit wallet).
- Set a low auto-top-up ceiling or none at all: a hard stop is safer than a surprise bill for an MVP.

### 6.4 RevenueCat — `REVENUECAT_API_KEY` (entitlement verification — needed at §gate 4, not day one)

1. [app.revenuecat.com](https://app.revenuecat.com) → your project → **API keys**.
2. You want a **secret** key (`sk_…`) for the proxy — the public `appl_…` key is for the iOS SDK only and can't verify subscribers server-side.

Defer this until wiring the server-side entitlement gate; echo mode and text routing don't need it.

### 6.5 Store everything in Fly

**Always single-quote values** — URLs contain `?` and `&`, which zsh otherwise mangles (`no matches found`):

```sh
fly secrets set \
  GEMINI_API_KEY='...' \
  OPENAI_API_KEY='...' \
  FAL_API_KEY='fal_sk_...' \
  REVENUECAT_API_KEY='sk_...' \
  REDIS_URL='rediss://default:...@....upstash.io:6379' \
  DATABASE_URL='postgresql://...?sslmode=require'
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
- [ ] Server-side entitlement gate (daily moment/image counters in Redis) — closes the client-only enforcement gap
- [ ] Model provider keys set; real routing on for one Book; cost logs visible in `fly logs`
- [ ] Budget caps set at Fly + all three model providers
- [ ] App Attest verification on the auth hook
- [ ] CI deploy job green
