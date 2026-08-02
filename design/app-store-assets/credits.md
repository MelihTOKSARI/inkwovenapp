# Inkwoven — Moving-picture credits ("the Vials")

**Status: LAUNCH SCOPE.** Moving pictures are the hero feature and v1 does not ship without
them (`vision.md`, `prd.md` §0/§4, `tasks.md` Epic J). These three consumables go into App
Store Connect alongside the two subscriptions.

Companion to `subscriptions.md`. That file covers what ships now; this one covers the
consumable layer and, more importantly, records why the prices currently sitting in
`app/Inkwoven.storekit` must not be used.

---

## 1. State of the build

**Epic J landed on 2026-08-02.** The provider is bound (`createVideoProviderFactory` in
`proxy/src/models.js`, fal's queue API against
`fal-ai/kling-video/v3/standard/{text,image}-to-video`), `POST /v1/video` reserves before
generating and releases on every failure, the convertibility verdict rides every reply, and
the client offers only what the reader taps. `PageInteractor.releaseVideoCredit()` is
implemented rather than a stub. The short-form endpoint identifier that 404ed is gone.

**What is still open before these products may be created in App Store Connect:**

- The physical-iPad pass in `tasks.md`'s Definition of Done — verdict → tap → clip →
  immersive loop, plus killing the app mid-generation and seeing the credit return.
- The fal budget cap (`deployment.md` §9). Video is the only modality that can run a real
  bill on its own.
- `INK_VIDEO_PRICING`, `INK_APPLE_ROOT_CA` and `INK_BUNDLE_ID` set in production
  (`deployment.md` §6.7–6.8). Without the last two, receipt verification is unbound and
  every purchase 501s *after* the user has paid.

Selling a currency for a modality that cannot execute is a guideline **2.1** rejection, so
these are created and attached in the same submission that ships video — once the list
above is closed, not before.

**Images are not part of this.** `proxy/src/config.js` sets
`exchangeCosts: { ink: 0, image: 0, video: 1 }` — images cost zero credits and are covered
by the subscription. Video is the only metered modality, by design.

---

## 2. Why the original ladder lost money

Kept as the reasoning behind §3, not as a description of the catalog: `Inkwoven.storekit`
was regenerated with the §3 products on 2026-08-02. The old entries were `credits_10` at
$4.99, `credits_30` at $11.99 and `credits_100` at $29.99, costed against the real fal
rates for Kling v3 (the PRD assumed $0.15–0.35 per clip; the published rate is $0.42–0.98):

| Pack | Price | Net @ 15% | Per credit | vs $0.42 cost |
|---|---|---|---|---|
| 10 vials | $4.99 | $4.24 | $0.424 | **+$0.004** — 1.0% |
| 30 vials | $11.99 | $10.19 | $0.340 | **−$0.080** — −24% |
| 100 vials | $29.99 | $25.49 | $0.255 | **−$0.165** — −65% |

$0.42 is the *cheapest possible* clip — standard tier, audio off. With audio, or on pro,
every tier loses money. A user who burns a full 100-pack costs **$16.50 more than they
paid**.

The bulk discount is doing exactly what a bulk discount does; the problem is that the base
price was already at cost, so the discount runs straight past it.

### Two costs the old model missed

**Failure is not free.** `refund-on-failure` returns the credit to the user, but fal has
already run the job and billed you. Moderation rejections, provider errors and timeouts
all land in this bucket. At an assumed **8% failure rate** the effective cost per
*delivered* clip is:

| Tier | Raw | Effective @ 8% failure |
|---|---|---|
| standard / audio off | $0.42 | **$0.457** |
| pro / audio off | $0.56 | **$0.609** |
| standard / audio on | $0.63 | **$0.685** |
| pro / audio on | $0.84 | **$0.913** |

Instrument the real rate before launch and re-run this table — 8% is an assumption, not a
measurement.

**A free clip is a per-install cost.** The `onboardingCreditGrant: 1` this replaced handed
every new user a clip before they had shown any intent to pay:

| Installs | Video cost | Revenue |
|---|---|---|
| 10,000 | $4,200 | $0 |
| 25,000 | $10,500 | $0 |
| 100,000 | $42,000 | $0 |

---

## 3. Recommended ladder

Priced so the **cheapest tier clears 55%+ margin** and the ladder stays profitable even if
you later switch to pro-with-audio — because the tier decision and the price decision get
made months apart, by which time the prices are permanent.

| Product ID | Credits | Price | Net @ 15% | Per credit |
|---|---|---|---|---|
| `vials_small` | 3 | **$4.99** | $4.24 | $1.414 |
| `vials_medium` | 8 | **$10.99** | $9.34 | $1.168 |
| `vials_large` | 20 | **$24.99** | $21.24 | $1.062 |

### Margin by video tier (failure absorbed)

| Product | std / audio off | pro / audio off | std / audio on | pro / audio on |
|---|---|---|---|---|
| `vials_small` | 67.7% | 56.9% | 51.6% | 35.4% |
| `vials_medium` | 60.9% | 47.9% | 41.4% | 21.8% |
| `vials_large` | 57.0% | 42.7% | 35.5% | **14.0%** |

Every cell is positive. The worst realistic case — a user burning a full 20-pack on
pro-with-audio — still returns **$21.24 against $18.26 of cost**. Compare that with the
current catalog, where the same user loses you $16.50.

The bulk discount is deliberately modest: **17% off** at medium, **25%** at large. Enough
to reward commitment, not enough to reach cost.

### Product ID naming

Name them `vials_small / medium / large`, **not** by quantity or price. Consumable IDs are
as permanent as subscription IDs, and `credits_10` becomes a lie the first time a pack
changes from 10 credits to 8. Decoupling the ID from both quantity and price means you can
retune either without the identifier rotting.

(This is the same lesson as `plus_monthly_9_99` — see `subscriptions.md` §2. Worth getting
right once.)

### Display names and descriptions

30 / 45 character limits, same as any IAP. Keep the fiction here — unlike subscriptions,
consumables don't appear in iOS Settings months later, so there's no recognition problem
to solve:

| Product | Display name | Description |
|---|---|---|
| `vials_small` | `Three Vials` | `Three moving pictures, sealed in wax.` |
| `vials_medium` | `Eight Vials` | `Eight moving pictures, sealed in wax.` |
| `vials_large` | `Twenty Vials` | `Twenty moving pictures, and the best rate.` |

---

## 4. Free clips — decided

**Every user gets 2 free clips, ever.** Not per day, not per month — two, lifetime.

The reasoning: this is the hero feature, so everyone must reach it; but at $0.457 effective
per delivered clip, generosity is a real budget line.

| Free clips | Cost per install | At 25,000 installs |
|---|---|---|
| 1 | $0.46 | $11,400 |
| **2** | **$0.91** | **$22,850** |
| 3 | $1.37 | $34,275 |

Those are worst cases — they assume every install burns every free clip. Real spend scales
with activation.

Two guards, both required:

1. **Server-authoritative count.** The client never grants a free clip; the proxy does.
2. **A global monthly ceiling on free-clip spend**, enforced server-side, that fails closed
   *in fiction* ("the ink must rest") rather than erroring. A viral week must not be able to
   produce a bill nobody agreed to.

Both are server-tunable — the count and the ceiling change without a release. Replaces
`onboardingCreditGrant: 1`, which granted at install before any intent to pay.

---

## 5. Rules that don't change

- **Never bundle unlimited video.** The PRD is right about this and it stays right — video
  has a real marginal cost that no subscription price can safely absorb.
- **Refund on failure**, always. Already implemented via `reserve` → `settle` / `release`.
  The user must never pay for a clip that didn't arrive, even though you did.
- **Reserve before generating, settle after.** The existing idempotent path is correct;
  don't let a retry mint or burn credits twice.
- **Strictest moderation on video**, prompt and output. Cost per failure is highest here
  and the reputational cost of a bad clip is higher still.
- **Credits never expire.** Consumables that expire invite refund disputes for no
  meaningful gain.

---

## 6. Launch checklist

- [ ] `tasks.md` Epic J complete — J1 (provider) through J8 (free-clip accounting)
- [ ] Endpoint identifier fixed: `fal-ai/kling-video/v3/standard/...`, **not** `kling-3`
- [ ] Tier chosen deliberately — standard/audio-off $0.42 vs pro/audio-on $0.84 is a 2×
      swing that changes every number above. Ship standard/audio-off unless the quality
      difference is visible in a side-by-side
- [ ] Real failure rate instrumented; §2 re-run with the measured value, not 8%
- [ ] Free-clip count (2), the global monthly ceiling and the per-address daily cap all
      live and server-tunable — see §7 for why the last one exists
- [ ] `INK_APPLE_ROOT_CA` + `INK_BUNDLE_ID` set, and one sandbox pack bought end to end:
      unset, receipt verification is unbound and every purchase 501s after the charge
- [ ] Provider budget caps set at fal before a single clip is generated
- [ ] Three consumables created in App Store Connect with the §3 IDs, **attached to the
      same version** as the subscriptions
- [ ] Video kill-switch flag on per Book
- [ ] `listing.md` description carries the moving-picture line and the credit terms
- [ ] `review-notes.md` carries the video moderation story — this is the highest-scrutiny
      modality in the submission and boilerplate will not survive it
- [ ] A screenshot slot shows the immersive full-screen clip

---

## 7. Red-team record (task J10)

Adversarial pass over the video path on 2026-08-02, after Epic J landed: prompt
injection, cost exhaustion, credit stranding, moderation bypass, abuse and minors.
Everything below was found by reading and executing the shipped code, not by
reasoning about the design. All of it is fixed; the residual risks are named at the
end because they are the ones that need a human decision rather than a patch.

### Fixed

**The spend ceiling counted deliveries, not spend.** Releasing a free clip dropped
its row out of the monthly count, so opening a request, letting fal run for two
minutes, and dropping the socket refunded the reader *and* un-counted the money.
The ceiling never advanced and never closed — the ~$915/month bound in §4 was
asserted by a comment and enforced by nothing, at roughly $150/hour from one
address. The month now counts every **attempt**, because every attempt is billed;
a release returns the clip to the reader only.

**A forged receipt minted unlimited credits.** `POST /v1/credits/grant` decoded the
StoreKit JWS and trusted its claims, on the reasoning that StoreKit had already
verified it on-device. That is worthless when the client is whatever speaks HTTP:
three base64url segments bought 20 credits, repeatable with a fresh transaction id,
and credits have no ceiling at all. Receipts are now verified properly — x5c chain,
validity dates, chain signatures, ES256 over the payload, bundle id, revocation —
against an Apple root the operator supplies. **Without that anchor the route
refuses**, which is why `deployment.md` §6.8 is a launch-blocking step: unset, every
purchase 501s after the user has paid.

**Two free clips per user was two per header value.** Identity is the `x-ink-user`
token and attestation is anonymous, so a token costs nothing to mint. One address
could exhaust the global ceiling in an afternoon — and then every legitimate user
gets "the ink must rest" until the month rolls over, which is a denial of the launch
feature, not just a bill. Free clips are now also capped per address per day.

**Both prompt-injection fences were forgeable.** The scrubber stripped only runs of
three or more angle brackets, so `<< <END REPLY> >>` reproduced a fence exactly, and
its zero-width list missed U+2060 and U+00AD, so brackets separated by invisible
characters passed too. It now strips every Unicode control and format character and
removes angle brackets outright. Separately, the verdict parser was dotall — a
multi-line answer smuggled instructions into the brief — and the fal prompt put the
brief *first* with the safety clause last, handing position and recency to the one
part of the string that traces back to the reader's page. The brief is one line, and
the rules now bracket it on both sides.

**The moderator failed open, and lost its real-person check exactly where it
mattered.** An unexpected 200 envelope yielded `Boolean(undefined)` — a silent allow
in the strictest gate in the app. And the "no real people" rule lived only on the
Gemini fallback, so it disappeared in the configuration we actually ship. Both
fixed: unreadable verdicts block, and the app's own policy gate always runs
alongside the categorical one.

**The Artist path animated an image nobody moderated.** On image-to-video the clip's
real subject is the developed picture, while the moderated text can be as innocuous
as "gentle wind stirs the cloth". The image is now moderated too.

**Stranded holds.** A hold outlives its request when the process dies between reserve
and settle — for video that is a minutes-long window, and a stranded hold silently
destroys a purchased vial or one of the two lifetime free clips, with no way for the
user to ask for it back. Both stores now reclaim holds after 30 minutes (four times
the longest legitimate hold), at boot and on a timer.

**Instrumentation that would have lied.** fal rejects with wording like "NSFW content
detected", which the moderation regex did not match — output rejections logged as
generic outages, so the measured moderation rate in §2 would have read as zero. Also
fixed: a reader who walks away mid-generation is logged as `client_gone`, not as a
failure, so abandonment does not inflate the failure rate this section depends on.

### Residual risks — accepted, with the reason

**Anonymous attestation is the root of the cost model.** Every per-user limit is a
per-token limit until App Attest is bound (`app/proxy/src/attest.js` lists what a
human must supply). The per-address cap and the global ceiling bound the damage;
they do not make identity real. This is the single highest-value hardening left, and
it is a pre-launch item on `deployment.md` §9 for that reason.

**Photorealistic real people are reachable in principle.** The control stack is a
style clause positioned first and restated last, an instruction to the classifier, a
policy gate, and Kling's own filter — four probabilistic layers and no deterministic
one, because there is no reliable deterministic test for "is this a real person".
The Correspondent and Storyteller are *built* to write vividly about historical
figures, so this is the feature's inherent press and App Review risk rather than a
bug with a fix. Worth a spot check on the Correspondent before submission.

**Output moderation is the provider's.** We moderate the prompt and the source
image; the clip itself is filtered by Kling. `review-notes.md` says exactly that
rather than claiming our own output gate.

**A brief is reusable for 30 minutes.** Deliberate — a failed clip must be
retryable — and no longer a spend lever now that attempts are counted.

---

## 8. Where the numbers came from

Published rates, 1 August 2026:

- fal `fal-ai/kling-video/v3/standard/*` — $0.084/sec audio off, $0.126/sec audio on
- fal `fal-ai/kling-video/v3/pro/*` — $0.112/sec audio off, $0.168/sec audio on
- 5-second clip assumed throughout
- Apple commission 15% (Small Business Program — **enrol**, or every figure drops to 30%)
- Failure rate 8%, assumed, not measured

Re-verify provider pricing before committing: these rates have moved more than once, and
the last set of assumptions in `prd.md` §7 was off by roughly 2×.
