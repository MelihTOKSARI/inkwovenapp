# Inkwoven — Subscriptions & In-App Purchase (v1.0)

Everything needed to configure, test, and ship the paid layer. Companion to
`asc-checklist.md` — that file is the running order, this one is the detail behind
its step 3.

**Verified against the shipping build**, not the PRD: `app/App/Money/PurchaseService.swift`,
`Packages/InkwovenCore/Sources/InkMoney/`, and `app/Inkwoven.storekit`. Every character
count below was checked programmatically against App Store Connect's limits.

> **Pricing decision, 2026-08-01.** v1 launches **weekly + monthly**, not monthly +
> annual. Rationale and the unit-economics model are in §6. Product IDs were renamed to
> drop embedded prices while nothing is live and the change is still free — see §2.

---

## 0. What ships, and what deliberately does not

| | v1.0 | Notes |
|---|---|---|
| Auto-renewable subscriptions | **2** | `plus_weekly`, `plus_monthly` |
| **Consumables (the Vials)** | **3** | `vials_small/medium/large` — **launch scope, the hero feature.** Full spec in `credits.md` |
| Non-consumables (the Bindery) | **none** | Bindery ships as a try-on room with no SKUs |
| Purchase framework | **StoreKit 2, direct** | No RevenueCat in v1 — see §11 |
| Server receipt validation | **none** | Entitlement derived on-device from `Transaction.currentEntitlements` |

> **`Inkwoven.storekit` is a local test catalog, not a specification.** It currently
> contains `credits_10 / 30 / 100` and the old annual plan. **Do not mirror those in App
> Store Connect.** A product record whose feature doesn't exist in the binary is a
> guideline 2.1 rejection, and the release scheme ignores the file anyway. The catalog is
> being regenerated to match this document — see the handover report.

### On images vs video

- **Images are never sold separately.** `proxy/src/config.js` sets
  `exchangeCosts: { ink: 0, image: 0, video: 1 }` — images cost zero credits and are
  covered by the subscription (free tier within the daily 5, Plus up to the soft cap).
- **Video is metered by credits and is launch-blocking.** See `credits.md`. Epic J is
  built as of 2026-08-02; the consumables are created in App Store Connect once the
  physical-device pass and the fal budget cap are done (`credits.md` §1), and then they
  ship attached to the same version as the subscriptions. A product for a modality that
  cannot execute is a 2.1 rejection, so the order matters.

---

## 1. Subscription group

One group. Both plans live inside it so a user can move between weekly and monthly
without a second purchase, and so iOS presents them as tiers of one thing.

| Field | Value | Chars |
|---|---|---|
| Reference name (internal, never shown) | `Plus` | 4 |
| Group display name (shown when comparing tiers) | `Inkwoven Plus` | 13 / 30 |

---

## 2. Product IDs — renamed before launch

The previous IDs embedded prices: `plus_monthly_9_99`, `plus_annual_59_99`. **Product IDs
are permanent and can never be reused or renamed once submitted** — so the first time you
change a price, the ID lies forever, and every log, dashboard and support thread inherits
the lie.

Nothing exists in App Store Connect yet, so this is the last moment the rename is free:

| Old | New |
|---|---|
| `plus_monthly_9_99` | **`plus_monthly`** |
| `plus_annual_59_99` | **`plus_weekly`** (annual dropped from v1) |

After the first submission these strings are immutable. Type them once, carefully.

They are looked up by exact string at runtime in
`Packages/InkwovenCore/Sources/InkMoney/Products.swift`. A single character of drift — a
capital, a hyphen, a trailing space — produces an **empty paywall with no error**, because
`Product.products(for:)` simply returns nothing for an ID that doesn't exist.

## 3. Product 1 — Weekly

| Field | Value |
|---|---|
| **Product ID** | `plus_weekly` |
| Reference name | `Plus Weekly` |
| Type | Auto-renewable subscription |
| Duration | 1 week |
| Price | **$4.99 USD** — accept Apple's generated per-territory prices |
| Introductory offer | **Free trial, 3 days, all territories** |
| Family Sharing | Off |
| Display name | `Inkwoven Plus Weekly` (20 / 30) |
| Description | `Unlimited pages, three days free.` (33 / 45) |

**Why 3 days and not 7.** Apple expects trial length to be proportionate to the billing
period. A 7-day trial on a 7-day subscription means the entire first paid cycle is free,
which reviewers read as a disclosure problem and which makes the renewal feel like a
surprise charge. Three days is the standard pairing for weekly.

## 4. Product 2 — Monthly

| Field | Value |
|---|---|
| **Product ID** | `plus_monthly` |
| Reference name | `Plus Monthly` |
| Type | Auto-renewable subscription |
| Duration | 1 month |
| Price | **$12.99 USD** |
| Introductory offer | **none** |
| Family Sharing | Off |
| Display name | `Inkwoven Plus Monthly` (21 / 30) |
| Description | `Unlimited pages and your full archive.` (38 / 45) |

> **Repriced 2026-08-10: $9.99 → $12.99.** At $9.99 the heavy-book full-limit case loses
> $1.06/month once the text ceiling rises to 100/day and Plus carries a bundled video
> allowance — the arithmetic is `video-in-plus.md` §6, and it is the reason for the move.
> The weekly plan is unchanged at $4.99. The margin tables in §6 below still describe
> $9.99 against the pre-video cost model; treat them as the reasoning, not the numbers.

**Monthly is the value plan and should be presented as such.** $4.99/week annualises to
$21.62/month, so monthly is a **40% saving**. Show that comparison plainly on the paywall.
(The paywall computes this from `StorePrice.amount`, never from this sentence — but the
App Store description must agree with what the paywall renders.)

### The weekly-subscription disclosure rule

Weekly plans draw more App Review scrutiny than any other duration — it is the signature of
the scam-app playbook, and 3.1.2 rejections cluster there. Three rules keep you clear:

1. **Never make weekly the pre-selected plan while presenting it as the cheap option.**
   $4.99 looks smaller than $12.99 and costs two-thirds more per month. If weekly is
   pre-selected, the monthly saving must be visible in the same view without scrolling.
2. **State the renewal period next to the price**, every time: "$4.99 / week", never "$4.99".
3. **The trial terms appear before purchase, not after** — "Free for 3 days, then $4.99 a
   week. Renews until cancelled." — on the purchase surface itself.

---

## 5. Localized metadata is mandatory

A subscription sits in **Missing Metadata** and cannot be submitted until each product has
a localized display name *and* description for at least the primary locale. This is the
single most common reason a first submission stalls without an obvious error.

Add an **App Store review screenshot** per product. Technically optional in the API, but
the ASC interface requests it and a reviewer who cannot see the paywall rejects the
purchase flow. Reuse `screenshots/ipad-13in/5-paywall.png` once it shows the new plans.

---

## 6. Unit economics — why these prices

Modelled against published provider rates as of 1 August 2026. Video is excluded because
it does not ship in v1.

### Cost per operation

| Operation | Model | Cost |
|---|---|---|
| Ink reply, 6 of 8 Books | Gemini 3.5 Flash-Lite ($0.30/$2.50 per 1M) | **$0.0010** |
| Ink reply, Game Master + Tutor | gpt-5.4-mini ($0.75/$4.50 per 1M) | **$0.0048** |
| Image, most Books | fal `z-image/turbo`, $0.005/MP | **$0.0050** |
| **Image, the Artist** | fal `flux-2/edit`, $0.012/MP × 2MP | **$0.0240** |
| Video, 5s | fal `kling-video/v3/standard` | $0.42 — **not in v1** |

A handwriting snapshot at ~1024px costs **1,032 input tokens** under Gemini's tiling rule
(4 tiles × 258), not the 258-token flat rate — that only applies below 384px.

> Two corrections to `prd.md` §7: the endpoint is `fal-ai/kling-video/v3/...`, not
> a short-form model name rather than a fal route; and **flux-2 bills input + output megapixels**, so an Artist img2img is
> 2 MP, roughly double what the PRD assumed.

### Cost per user per month

| Profile | Per day | Per month |
|---|---|---|
| Free, typical | $0.005 | **$0.16** |
| Free, maxing 5/day | $0.019 | **$0.56** |
| Plus, typical (8 pages, 2 images) | $0.035 | **$1.05** |
| Plus, heavy (20 pages, 6 images) | $0.107 | **$3.21** |
| Plus, at a **20**/day image cap on Artist | $0.539 | **$16.16** |

### Margin (Apple Small Business Program, 15%)

| Plan | Net / mo | Typical | Heavy | Cap abuser @20 |
|---|---|---|---|---|
| **Weekly $4.99** | $18.38 | +$17.33 (94%) | +$15.17 (83%) | **+$2.22** |
| **Monthly $9.99** | $8.49 | +$7.44 (88%) | +$5.28 (62%) | **−$7.67** |

Weekly at $4.99 is the only price that stays profitable against the worst case. Shorter
billing periods also cap how much damage an expensive user does before they churn or
before you retune the caps.

### The image soft cap must drop from 20 to 8

`plusImageDailySoftCap` is server-tunable via `GET /v1/config` — changeable without an app
release. At 20 it is mispriced against flux-2. To hold worst case under 30% of net revenue:

| Plan | Budget / mo | Artist images/day | z-image/day |
|---|---|---|---|
| Weekly $4.99 | $5.51 | **~8** | ~37 |
| Monthly $9.99 | $2.55 | ~3.5 | ~17 |

**Ship at 8.** No legitimate user makes eight finished Artist pieces a day, and it can be
raised from real data without a submission. This number matters more than the price.

### Fleet view — conservative case from `prd.md` (12,000 MAU)

| Conversion | Payers | Revenue / mo | AI cost / mo | Gross / mo |
|---|---|---|---|---|
| 2% | 240 | $3,225 | $2,162 | $1,062 |
| 4% | 480 | $6,449 | $2,376 | $4,073 |
| 6% | 720 | $9,674 | $2,590 | $7,083 |

Free users cost **$162 per 1,000 MAU per month** regardless of conversion. At 2% you are
barely ahead. The free tier is a marketing budget — treat it as one, and keep the
`INK_MODEL_PRICING` rate card populated so `fly logs` reports real cost rather than null.

**Enrol in the App Store Small Business Program.** Every figure above assumes 15%. At 30%
the monthly plan nets $6.99 and the cap abuser costs you $9.17/month.

---

## 7. What Plus unlocks

Must match the App Store description word for word, or it's a guideline 2.3.1
inaccurate-metadata problem. Verified in `InkMoney/Entitlements.swift`:

| | Free | Plus |
|---|---|---|
| Answered pages per day | **5**, 6th shows the paywall | **Unlimited** ink |
| Images | included within the daily 5 | soft cap **8/day**, then in-fiction cooldown (60s → 5m → 15m → 1h), never a hard error |
| Page archive | **30 days**, older pages trigger the paywall | **Full**, forever |
| Memory | off | flag on |

- **The gate runs before any model call.** `SendGate.canSend` is checked ahead of the
  network, so a free user's 6th page costs nothing. Keep it that way.
- **Do not advertise cross-page memory.** `memoryEnabled` is true for Plus, but the memory
  feature (task D5) is unbuilt in v1. The description correctly claims only the daily limit
  and the archive.
- **Free caps are enforced client-side today.** The server-side gate is still open on
  `deployment.md` §9. Not a review blocker; a revenue leak.

---

## 8. Attaching to the version

**First-ever subscriptions must be submitted together with the app version.** They cannot
be approved standalone beforehand. On the 1.0 version page, attach both products before
submitting.

Forgetting this is the classic first-launch delay: the app is approved, the subscriptions
are not, and the paywall is empty on day one for every user.

---

## 9. What's already built (no purchase code needed)

`app/App/Money/PurchaseService.swift` implements the flow on StoreKit 2:

- **Entitlement** from `Transaction.currentEntitlements` at launch, kept live by a
  `Transaction.updates` listener — refund, cancellation, expiry and family-sharing
  revocation all remove Plus on the next tick. Nothing entitlement-shaped is persisted
  client-side, so there is no forgeable local flag.
- **Unverified receipts grant nothing and are not finished.**
- **`pending` is distinct from success** — an Ask-to-Buy or SCA transaction entitles
  nothing yet. This is what stops a child getting Plus a parent never approved.
- **Restore** is wired to *"Restore a binding"* at the foot of the paywall. App Review
  tests this every time.
- **Prices read from the storefront**, never hardcoded — hardcoded USD literals are a
  misleading-price rejection in every non-USD territory.

What *does* need changing for this pricing decision is listed in the handover report.

---

## 10. Sandbox testing

1. ASC → **Users and Access → Sandbox → Testers** → create one, with an email that has
   **never** been an Apple ID.
2. On a physical iPad: **Settings → App Store → Sandbox Account** → sign in as that tester.
3. **Confirm the Release scheme has no StoreKit configuration file selected.**
   `project.yml` sets `storeKitConfiguration: Inkwoven.storekit` on the scheme — correct
   for development, ignored by Release, but verify on the archive you ship. A build still
   pointed at the local catalog makes every purchase fake.
4. Run all of it:
   - Buy weekly → 3-day trial messaging shows **before** purchase; Plus unlocks
   - Buy monthly → the 54% saving is visible next to the weekly price
   - **Restore a binding** → entitlement returns on a clean install
   - Cancel in sandbox → Plus falls away on the next tick
   - Cross-grade weekly → monthly within the group
   - Offline → paywall degrades in fiction, grants nothing

Sandbox renewals are accelerated (a week ≈ 3 minutes, a month ≈ 5), so trial expiry and
renewal are both testable in one sitting.

---

## 11. Required disclosure

Guideline **3.1.2** and Schedule 2 §3.8(b) require the following **on the purchase screen
itself**, without an extra tap: title and duration, price, what it includes, and links to
Terms of Use and Privacy Policy.

The paywall links Apple's standard EULA (`PolicySheet.swift`). The App Store description
must carry a matching block naming both plans and the trial. Keep the two in agreement — a
description promising something the paywall doesn't show is the most-cited subscription
rejection there is.

---

## 12. RevenueCat — after launch, not before

Not required to ship and not integrated. `deployment.md` §6.4 defers it explicitly, and
`PurchaseService` conforms to `EntitlementProviding` so the adapter drops in later as a
one-line change in `LiveCommerce.swift`.

Add it when you want the **server-side entitlement gate**:

1. RevenueCat project → add iOS app, bundle ID `com.empath.inkwoven`.
2. In ASC generate an **In-App Purchase key** (`.p8`); upload it to RevenueCat.
3. Point **App Store Server Notifications V2** at RevenueCat — this is what makes refunds,
   expiries and billing retries land automatically instead of on next launch.
4. Mirror `plus_weekly` and `plus_monthly`; create entitlement `plus`; attach both.
5. SDK via SPM, `Purchases.configure(withAPIKey:)` with the **public** `appl_` key.
6. Write the `EntitlementProviding` adapter, swap it in `LiveCommerce.swift`.
7. Set `REVENUECAT_API_KEY` (the **secret** `sk_` key) as a Fly secret.

Never put the `sk_` key in the app or the `appl_` key on the server.

---

## 13. Rejection causes specific to the paid layer

| Cause | Guard |
|---|---|
| Paywall empty at review | IDs typed exactly; both attached to the version; Paid Apps agreement **Active** |
| Subscriptions not approved with the app | Attach to version 1.0 — §8 |
| **Weekly plan framed misleadingly** | §4 — period next to price, monthly saving visible, trial terms pre-purchase |
| Restore missing or broken | Implemented; test in sandbox every time |
| Prices hardcoded per territory | Storefront-driven; don't regress |
| Product record for a feature not in the build | No credit packs, no Bindery SKUs — §0 |
| Description claims what the paywall doesn't deliver | §7 is the source of truth |
| Missing localized name/description | §5 — the silent Missing Metadata stall |

---

## 14. Checklist

- [ ] Enrolled in the **App Store Small Business Program** (15% not 30%)
- [ ] Paid Apps agreement **Active** in Agreements, Tax, and Banking
- [ ] Subscription group `Plus` created, display name `Inkwoven Plus`
- [ ] `plus_weekly` — $4.99, 1 week, **3-day free trial**, all territories
- [ ] `plus_monthly` — **$12.99**, 1 month, no intro offer
- [ ] Both IDs verified character for character against `Products.swift`
- [ ] Localized display name + description on both (out of Missing Metadata)
- [ ] Review screenshot attached to both, showing the new two-plan paywall
- [ ] No consumables, no non-consumables created
- [ ] Both attached to version 1.0
- [ ] `plusImageDailySoftCap` shipped at **8** on the proxy
- [ ] `INK_MODEL_PRICING` rate card set as a Fly secret so cost logs are real
- [ ] Sandbox: buy weekly w/ trial, buy monthly, restore, cross-grade, cancel
- [ ] Description's subscription block matches the paywall exactly
