# Inkwoven — Moving-picture credits ("the Vials")

**Status: not in v1.** This is the spec for the day video ships. Nothing here goes into
App Store Connect yet.

Companion to `subscriptions.md`. That file covers what ships now; this one covers the
consumable layer and, more importantly, records why the prices currently sitting in
`app/Inkwoven.storekit` must not be used.

---

## 1. Why credits are dark in v1

The machinery is complete and works: the credit wallet, an idempotent ledger with
`/v1/credits/reserve|settle|release`, `creditGrants()` in `PurchaseService`, and
`VialsView.swift` — the wax-sealed vials shop, already styled.

What does not exist is the thing credits buy. `proxy/src/models.js` contains **no video
route at all**; `PageInteractor.swift:508` records that the path is unbound end to end;
and `VialsView`'s own doc comment says the shop stays behind the curtain for v1.

Selling a currency for a modality that cannot execute is a guideline **2.1**
incomplete-feature rejection. Credits ship when video ships.

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

## 4. The onboarding grant

Three options, in order of preference:

1. **Drop it.** Set `onboardingCreditGrant: 0`. The wow moment is already the ink
   absorption — video is the premium delight, not the hook.
2. **Gate it behind a value moment**, the way the paywall is: grant the first credit after
   a user's first *answered page*, not at install. Same generosity, paid only for people
   who actually engaged, and it cuts the per-install cost by whatever your activation rate
   is short of 100%.
3. **Keep it at install** and treat it as a marketing line item with a hard monthly ceiling
   enforced server-side.

The grant is already server-tunable via config, so this is a number change, not a release.

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

## 6. Before any of this ships

- [ ] Bind a video provider in `proxy/src/models.js` — there is currently none
- [ ] Fix the endpoint identifier: `fal-ai/kling-video/v3/standard/...`, **not** `kling-3`,
      which 404s (it appears in every Book definition in `books.js`)
- [ ] Choose the tier deliberately — standard/audio-off at $0.42 versus pro/audio-on at
      $0.84 is a 2× swing that changes every number above
- [ ] Instrument the real failure rate; re-run §2 with the measured value
- [ ] Decide the onboarding grant (§4)
- [ ] Set provider budget caps before a single credit is sold
- [ ] Create the three consumables in App Store Connect with the IDs in §3
- [ ] Turn the video kill-switch flag on per Book
- [ ] Update `listing.md` — the description currently makes no mention of video, correctly;
      it will need a line, and the App Store description must not promise video before the
      flag is on in production

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
