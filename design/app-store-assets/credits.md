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
- `INK_VIDEO_PRICING` and `INK_IAP_MODE` set in production (`deployment.md` §6.7–6.8).
  Without the second, every purchase 501s *after* the user has paid.

Selling a currency for a modality that cannot execute is a guideline **2.1** rejection, so
these are created and attached in the same submission that ships video — once the list
above is closed, not before.

**Images are not part of this.** `proxy/src/config.js` sets
`exchangeCosts: { ink: 0, image: 0, video: 1 }` — images cost zero credits and are covered
by the subscription. Video is the only metered modality, by design.

---

## 2. The prices in the test catalog lose money

`Inkwoven.storekit` currently carries `credits_10` at $4.99, `credits_30` at $11.99, and
`credits_100` at $29.99. Costed against the real fal rates for Kling v3 (the PRD assumed
$0.15–0.35 per clip; the published rate is $0.42–0.98):

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

**The free onboarding credit is a per-install cost.** `onboardingCreditGrant: 1` hands
every new user a clip before they have shown any intent to pay:

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
- [ ] Free-clip count (2) and the global monthly ceiling both live and server-tunable
- [ ] Provider budget caps set at fal before a single clip is generated
- [ ] Three consumables created in App Store Connect with the §3 IDs, **attached to the
      same version** as the subscriptions
- [ ] Video kill-switch flag on per Book
- [ ] `listing.md` description carries the moving-picture line and the credit terms
- [ ] `review-notes.md` carries the video moderation story — this is the highest-scrutiny
      modality in the submission and boilerplate will not survive it
- [ ] A screenshot slot shows the immersive full-screen clip

---

## 7. Where the numbers came from

Published rates, 1 August 2026:

- fal `fal-ai/kling-video/v3/standard/*` — $0.084/sec audio off, $0.126/sec audio on
- fal `fal-ai/kling-video/v3/pro/*` — $0.112/sec audio off, $0.168/sec audio on
- 5-second clip assumed throughout
- Apple commission 15% (Small Business Program — **enrol**, or every figure drops to 30%)
- Failure rate 8%, assumed, not measured

Re-verify provider pricing before committing: these rates have moved more than once, and
the last set of assumptions in `prd.md` §7 was off by roughly 2×.
