# Binding Inkwoven to RevenueCat

**Date:** 2026-08-10 · **Why now:** Shipaton 2026 requires it, and the seam was built for it.
**Verified against:** purchases-ios 5.83.1 (2026-08-06), revenuecat.com/docs and
revenuecat-shipaton-2026.devpost.com as read on 2026-08-10. Every non-obvious claim below
carries its source in §9.

---

## 0. The one thing that must be decided first

**`video-in-plus.md` v2 is still a proposal, and it changes the prices.** It moves monthly
$9.99 → $12.99 and regrades the vials 3/8/20 → 4/11/28. Nothing in App Store Connect exists
yet, so the numbers are still free to change — but the moment step A3 below is executed they
are effectively permanent (a subscription price change after launch is a user-consent event;
a consumable's credit count is baked into `VIAL_GRANTS`).

Every step in this plan works identically under either pricing. But **do not execute §2 step
A3 until the v2 proposal is accepted or rejected.** That is the only genuine blocker in this
document, and it is a product decision, not an engineering one.

Everything in §1 and §2 steps A1–A2 and B1–B9 can start immediately regardless.

---

## 1. The decision: what actually changes

Inkwoven's commerce has three layers. RevenueCat replaces exactly one of them.

| Layer | Today | After |
|---|---|---|
| **Purchase + entitlement** (`plus_weekly`, `plus_monthly`) | StoreKit 2 direct, `Transaction.currentEntitlements` | **RevenueCat** — Offerings, `CustomerInfo.entitlements.active["plus"]` |
| **Consumable wallet** (vials) | Proxy-owned Redis ledger, reserve/settle/release, Apple-JWS verified | **Unchanged.** RevenueCat records the purchase; the proxy still owns the balance |
| **Refund clawback** | Apple ASSN V2 → `POST /v1/notifications` | **Unchanged**, via RevenueCat's notification forwarding (§2 step B7) |

**Do not adopt RevenueCat Virtual Currencies.** It is a real, shipped feature (public beta,
all plans, 480 req/min) and it would look tempting for the vials. It has no reserve/hold/settle
primitive, no pending state, no TTL release, and no transaction-history read — and it imposes
its own non-configurable deduction priority across grant buckets that your ledger cannot
observe. `/v1/video` depends on two-phase holds and a 30-minute stale-hold sweeper
(`stores-redis.js:213-243`); RC offers balance adjustments, not holds. A deploy mid-clip would
debit a user for a video that never arrived. Keep the Redis wallet.

### The mode question, and why it decides everything else

`Purchases` is configured either as `.revenueCat` (the SDK finishes transactions) or `.myApp`
(you do). It is a **global** setting — there is no per-product mode.

Under `.myApp`, nothing about the current audited pipeline changes: RC becomes a mirror. It is
tempting, and it is the wrong end state. The Shipaton rule says an app must use the SDK "to
power at least one in-app or web purchase"; a mirror does not power anything, and the HAMM
award is judged on "the smartest use of RevenueCat to drive real revenue." Observer mode
concedes both.

**Go to `.revenueCat` (the default).** The cost is one specific property: the SDK will finish a
consumable transaction once *RevenueCat's* backend has recorded it, not once *your* proxy has
credited the wallet. Section 3 replaces that safety net with something equally strong.

### The custom paywall survives intact — this is the good news

The in-fiction paywall does **not** have to become a RevenueCat template. RevenueCat documents
"Custom Paywalls (Manual Implementation)" as a first-class path:

- `Purchases.shared.offerings()` returns the Offering **already resolved** for that customer's
  targeting rule and experiment variant. Your SwiftUI view just renders `availablePackages`.
- Purchasing the `Package` (never a bare `StoreProduct`) carries `presentedOfferingContext`
  along automatically — offering, placement, targeting revision and rule id all attribute
  correctly with zero extra code.
- `Purchases.shared.trackCustomPaywallImpression(.init(paywallId:offering:))` reports the
  impression, which is what makes experiment exposure work for a custom UI.
- `Offering.metadata` lets an experiment vary in-fiction copy, ordering and emphasis **without
  an app release**.

What you give up: the three dashboard paywall charts (Conversion, Encounter, Abandonment)
explicitly exclude custom-code paywalls, and you lose close/cancel/interaction telemetry.
Experiment *results* — trials, conversion, realized LTV, chance-to-win — are computed from
transactions, so they are fully populated. That trade is obviously correct here: the art
direction is the Design Award entry.

---

## 2. Operator steps — everything Melih does by hand

Two dashboards, in this order. App Store Connect first: RevenueCat cannot validate anything
until the Apple side exists.

### Part A — App Store Connect (blocks everything)

- [ ] **A1. Agreements.** App Store Connect → **Business** (formerly Agreements, Tax, and
      Banking) → confirm the **Paid Applications** agreement reads **Active**, and that banking
      and tax are complete. *An unsigned Paid Apps agreement is the single most-cited cause of
      an empty paywall, and it silently breaks RevenueCat product import too.*
- [ ] **A2. App record.** My Apps → **+** → New App. Platform iOS, name **Inkwoven**, primary
      language English (U.S.), Bundle ID `com.empath.inkwoven`, SKU `inkwoven-ios-1`. Record
      the numeric **Apple ID** that appears afterwards — it is not written down anywhere in the
      repo yet, and `asc-checklist.md` step 1 wants it.
- [ ] **A3. Products.** ⚠️ *Blocked on §0.* Follow `design/app-store-assets/subscriptions.md`
      §2 and `credits.md` §3 exactly. Subscription group reference name `Plus`, display name
      `Inkwoven Plus`, holding `plus_weekly` and `plus_monthly`; three consumables
      `vials_small` / `vials_medium` / `vials_large`. **Type every identifier character for
      character** — a single character of drift produces an empty paywall with no error, and a
      product ID can never be reused once submitted. Each product needs a localized display
      name, description, and a review screenshot, or it stalls in Missing Metadata.
- [ ] **A4. Small Business Program.** Enrol (15% vs 30%). Every margin figure in
      `subscriptions.md` §6 assumes 15%. Tell RevenueCat afterwards (§2 step B9) or its
      commission math will be wrong.
- [ ] **A5. In-App Purchase Key — this is the one that breaks everything if missed.**
      Users and Access → **Integrations** tab → in the sidebar under **Keys**, choose
      **In-App Purchase** → **Generate In-App Purchase Key** → name it `RevenueCat` →
      Generate → **Download API Key**.
      - The `.p8` downloads **exactly once**. Put it somewhere you will find it in October.
      - Copy the **Issuer ID** shown at the top of that page.
      - Requires Account Holder or Admin; the Integrations tab is invisible to lesser roles.
      - RevenueCat SDK v5 defaults to StoreKit 2, and **purchases fail outright without this
        key configured.** This is the #1 v5 footgun.
- [ ] **A6. App Store Connect API Key** (separate key, optional but do it — it lets RevenueCat
      import products and push the notification URL for you). Users and Access → Integrations →
      **App Store Connect API** → generate a key with at least **App Manager** access →
      download the `.p8` (once only), note the **Key ID** and **Issuer ID**. Also grab your
      **Vendor number** from **Payments and Financial Reports** (top left).
- [ ] **A7. Skip the App-Specific Shared Secret.** It exists only for StoreKit 1, which Apple
      has deprecated. Leave that field empty in RevenueCat.

### Part B — RevenueCat dashboard

The navigation was redesigned; many doc screenshots are stale. Where the docs say
*Project Settings → Apps*, the live UI says **Platforms**. That single change is what makes
most older tutorials wrong.

- [ ] **B1. Account + Project.** Sign up at **app.revenuecat.com**. Open the **Projects**
      dropdown at the top → **+ Create new project** → name it **Inkwoven**. One project, one
      app inside it. *This alone unlocks Ship Kit milestone 2 (Mobbin, Paddle, Tminus).*
- [ ] **B2. Note the Project ID.** Project Settings → General → **Project ID** (`proj_…`).
      Every `/v2/projects/{id}/…` call needs it. Paste it into `deployment.md` §6.4.
- [ ] **B3. Add the iOS app.** Project Settings → **Platforms** (or Apps) → **Apple App
      Store**. App name `Inkwoven`, **Bundle ID `com.empath.inkwoven`** — exact, including
      case. Save. *If SAVE CHANGES is greyed out, a required field is empty.*
- [ ] **B4. Upload the In-App Purchase Key.** On that app's page open the **In-app purchase
      key configuration** tab → upload the `.p8` from A5 → paste the **Issuer ID** → Save.
- [ ] **B5. Upload the App Store Connect API Key.** Same app, **App Store Connect API** tab →
      upload the `.p8` from A6 → Issuer ID → **Vendor number** → Save.
- [ ] **B6. Copy the public SDK key.** Left nav → **Platforms** → your iOS app → copy the
      public app-specific key (`appl_…`). This is the only RevenueCat key that goes in the app
      binary. **Never** put an `sk_` key in the app; never put the `appl_` key on the server.
- [ ] **B7. Server notifications — read this whole step before clicking anything.**
      Apple allows **one** production URL and **one** sandbox URL. RevenueCat wants that slot,
      and `POST /v1/notifications` is currently the wallet's *only* refund clawback. Losing it
      means a user can buy 20 vials, spend them at fal, refund through Apple, and keep the
      credits — repeatably. So:
      1. In RevenueCat's iOS app settings find **Apple Server to Server notification
         settings**. Before touching it, note that the ASC slots are currently empty (nothing
         is deployed there yet) — nothing to preserve, but check.
      2. Paste `https://inkwoven-proxy.fly.dev/v1/notifications` into RevenueCat's
         **Apple Server Notification Forwarding URL** field. RevenueCat answers Apple with a
         temporary redirect and Apple then delivers the **original, unmodified** payload to the
         proxy — so `receipts.js` signature verification keeps working untouched.
      3. Only then click **Apply in App Store Connect** (needs the A6 key), which sets
         RevenueCat's URL as both Production and Sandbox, Version 2. Manual alternative:
         ASC → your app → App Information → App Store Server Notifications.
      4. **Verify forwarding end to end in both environments before you trust it.** Multiple
         RevenueCat community reports describe forwarding working in sandbox and failing in
         production, and gaps for customers RevenueCat does not recognise. §3 step 5 adds a
         second clawback path precisely because of this.
- [ ] **B8. Products.** Product catalog → **+ New** → **Import Products** (uses the A6 key), or
      **+ New product** and type each identifier by hand. All five: `plus_weekly`,
      `plus_monthly`, `vials_small`, `vials_medium`, `vials_large`.
- [ ] **B9. Entitlement.** Product catalog → **Entitlements** tab → **+ New entitlement** →
      identifier **`plus`** (lowercase; this exact string goes in the Swift code) → **Attach**
      `plus_weekly` and `plus_monthly`. Do **not** attach the vials — they grant credits, not
      Plus. Also tell RevenueCat you are in the Small Business Program so commission maths is
      right.
- [ ] **B10. Offering.** Product catalog → **Offerings** → **+ New** → identifier
      **`default`**, description "The binding". *The offering identifier cannot be changed
      later.* Then **+ Add package** four times:
      | Package identifier | Product |
      |---|---|
      | `$rc_weekly` | `plus_weekly` |
      | `$rc_monthly` | `plus_monthly` |
      | `vials_small` (custom) | `vials_small` |
      | `vials_medium` (custom) | `vials_medium` |
      | `vials_large` (custom) | `vials_large` |
      Consumables belong in an offering — RevenueCat documents this explicitly ("Any product
      can be added to an Offering, even if it's not part of any Entitlement"). Mark this
      offering **current/default**.
- [ ] **B11. Test Store purchase — do this today.** Every new project ships with a **Test
      Store** needing no Apple account. Make one test purchase against it. *Unlocks Ship Kit
      milestone 3: Sentry $100, AppScreens 50%, Asapty, Linearity.*
- [ ] **B12. Webhook.** Integrations → **Webhooks** → **Add new configuration**.
      Name `inkwoven-proxy`; URL `https://inkwoven-proxy.fly.dev/v1/rc/webhook`;
      **Authorization Header** — generate a long random string and set it as the Fly secret
      `INK_RC_WEBHOOK_SECRET`; Environment **both**; App scope: the iOS app.
      RevenueCat expects a `200` within 60s and retries a failure 5 times at 5/10/20/40/80
      minutes, then gives up forever. Delivery is at-least-once — the proxy dedupes on
      transaction id, which it already does.
- [ ] **B13. Secret API key for the proxy.** Project settings → **API keys** → **+ New secret
      API key** → **choose version V2** → name `inkwoven-proxy` → grant
      `customer_information:customers:read`. *A v1 `sk_` key returns 401 against `/v2`
      endpoints — the versions are not interchangeable.* Store as the Fly secret
      `REVENUECAT_API_KEY` (already reserved in `deployment.md` §6.4, currently read by
      nothing).
- [ ] **B14. Judge access.** After launch, for each judge: Manage Customers → find the App
      User ID → **Entitlements** card → **Grant** → `plus` → duration or "Until date" →
      Grant. Granted entitlements carry an `rc_promo` prefix, so entitlement-identifier checks
      work but any product-ID check will not — Inkwoven checks the identifier, so this is safe.
      There is no bulk grant UI; script it with the `sk_` key if there are many judges. Also
      generate App Store promo codes as a fallback.
- [ ] **B15. Sanity.** Project settings → **Sandbox Testing Access** controls whether sandbox
      purchases actually grant entitlements. Note that **Charts are production-only** — sandbox
      purchases will never appear there, which is normal and not a bug.

**Cost:** free. RevenueCat's entry plan is free to $2,500 monthly tracked revenue, then 1% of
tracked revenue (gross, i.e. ~1.43% of net after a 30% commission, ~1.18% at 15%). Paywalls,
Experiments, Targeting and Customer Center are all included. Some doc pages still say
"Pro & Enterprise" for those features; the pricing page supersedes them — verify in the
dashboard rather than trusting either page.

---

## 3. Engineering plan

Nine steps. Steps 1–4 are the SDK swap; 5–7 make the consumable path safe; 8–9 are the
Shipaton-specific upside. Each is independently shippable.

> **Status, 2026-08-10.** Steps 1–3 are **done and running**: purchases-ios 5.83.1 is
> linked, `RevenueCatPurchaseService` is written and compiles, and the SDK configures at
> launch against project `755b3ded` / app `app45d753ea06`, logs the customer in under the
> proxy's own user id, and is answered by RevenueCat's backend. Verified on an iPad Pro 13"
> simulator: no crash, identity accepted, and the only error is the expected
> *"no App Store products registered in the RevenueCat dashboard"* — which §2 B8–B10 fixes.
>
> `LiveCommerce.backend` is still **`.storeKit`**, so RevenueCat runs in `.myApp` mode and
> merely records. **Step 4 (paywall from the Offering) and step 5 (the webhook) are not
> done, and the switch must not be flipped before both are** — see step 5 for why.

### Step 1 — Add the SDK

`app/project.yml`, as a sibling of the existing local package:

```yaml
packages:
  InkwovenCore:
    path: Packages/InkwovenCore
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios-spm.git
    from: 5.83.1
```

and under `targets.Inkwoven.dependencies`, matching the existing plural style:

```yaml
      - package: RevenueCat
        products: [RevenueCat]
```

Then `xcodegen generate` from `app/`.

- Use the **`-spm` mirror**, not the main repo — the docs recommend it and the main repo drags
  test fixtures and snapshots into every checkout. Tags are identical.
- `RevenueCatUI` is a **separate product in the same package**. Skip it for now; add it only if
  Customer Center lands (step 9).
- **Do not add RevenueCat to `Packages/InkwovenCore/Package.swift`.** `InkMoney` is SDK-free by
  design (`Products.swift:63-65` says so), it is what the `swift-core` CI job builds, and
  pulling an SDK into the domain layer breaks the layering rule in `fancyTrendyApps/CLAUDE.md`
  §4. The adapter lives in the app target.

### Step 2 — Configure, in the composition root

In `AppDI.live()` (`app/App/DI.swift:57-95`, resolving the `TODO(A3)` at :86), **before**
anything touches `LiveCommerce.purchases`:

```swift
Purchases.logLevel = .info   // .debug only in Debug builds
Purchases.configure(
    with: Configuration.builder(withAPIKey: "appl_…")
        .with(appUserID: proxyUserID)          // see below — critical
        .build()
)
```

Leave `purchasesAreCompletedBy` and `storeKitVersion` at their defaults (`.revenueCat`,
StoreKit 2). On an iOS 17 iPad target StoreKit 2 is selected — note the SDK's real floor for
SK2 is **iOS 16**, not the iOS 15 its own doc comment claims.

**`appUserID` is the linchpin.** It must equal the proxy's minted `userID` (the App Attest
JWT's `sub`), or RevenueCat webhooks cannot address the right wallet and every customer lands
on a throwaway `$RCAnonymousID:`. Today `POST /v1/attest` returns only `{token, expiresAt}`
(`server.js:1368`). Either return `userID` too, or decode `sub` client-side — both touch
`Packages/InkwovenCore/Sources/InkNet/ProxyClient.swift`. Configure RevenueCat **after**
attestation completes, and never call `logOut()`.

> Known consequence, not a regression: identity is per-install (`randomUUID()` bound to the
> App Attest key). A reinstall mints a new `userID`, hence a new RevenueCat customer. The
> wallet already behaves this way; the subscription recovers through `restorePurchases()`.
> Set Project Settings → **Restore Behavior** deliberately with that in mind.

### Step 3 — Write `RevenueCatPurchaseService`

New file `app/App/Money/RevenueCatPurchaseService.swift`, an **actor** (the protocol is
`Sendable`), implementing the nine members of `PurchaseServicing`. The existing
`StoreKitEntitlementStore` stays in the file next to it until step 6 is verified — nothing
forces a deletion, and CI is unaffected either way because no test ever constructs it.

The semantics that must survive unchanged, because the UI reads each one by name:

| Member | Must preserve |
|---|---|
| `snapshots()` | Yields the **current** snapshot immediately on subscribe. `AppModel.tier` never leaves `.free` otherwise. Multi-observer, UUID-keyed, `onTermination` cleanup. |
| `currentSnapshot()` | `tier` from `customerInfo.entitlements.active["plus"] != nil`; `memoryEnabled == (tier == .plus)`. |
| `restore() -> Bool` | `Purchases.shared.restorePurchases()`, then read tier **off the actor**, never off the stream. The Bool is the whole difference between "The binding holds" and "No binding was found". Map `ErrorCode.purchaseCancelledError` → `CommerceError.cancelled`, `.offlineConnectionError`/network → `.offline`. |
| `products(for:)` | One batched fetch; **omit** ids the storefront did not answer rather than returning placeholders. Keep both `display` and `amount: Decimal` — `PaywallView.swift:162-171` computes the 54% saving from the Decimal and it silently vanishes otherwise. |
| `isEligibleForIntroOffer` | Stays tri-state. `checkTrialOrIntroDiscountEligibility` → `.eligible` = `true`, `.ineligible`/`.noIntroOfferExists` = `false`, **`.unknown` = `nil`**. `false` for unknown strips the trial tag; `true` for unknown is a 3.1.2 rejection. |
| `purchase(_:)` | `.pending` must stay its own case (Ask-to-Buy). Errors must keep landing as `.deliveryPending` / `.deliveryRejected` / `.productUnavailable` — `AppModel.swift:762-771` catches them by name and anything else collapses to generic copy. |

Bridge `Purchases.shared.customerInfoStream` into the observer registry. Expect the Swift 6
work to be the bulk of the time, not the logic: `Purchases` is `@unchecked Sendable` with an
in-source note that it "isn't actually thread-safe" in places, `PurchasesDelegate` carries no
`@MainActor` isolation, and the SDK is still built in Swift 5 language mode. `@preconcurrency
import RevenueCat` is the conventional escape hatch.

### Step 4 — Render the paywall from the Offering

`PaywallView` and `VialsView` keep their art direction entirely. What changes is the source of
prices, and it is small:

1. Fetch once: `let offerings = try await Purchases.shared.offerings()`, keep
   `offerings.current` (or `offerings.currentOffering(forPlacement:)` later).
2. Read prices off `package.storeProduct.localizedPriceString` / `.price` into the existing
   `storePrices` / `storeAmounts` dictionaries. Nothing downstream changes.
3. **Purchase the `Package`, never the `StoreProduct`.** This is the one rule that carries
   offering, placement, targeting revision and experiment variant into every transaction.
   Never hardcode an offering identifier — that silently opts the app out of every experiment.
4. Fire `trackCustomPaywallImpression(.init(paywallId: "inkwoven_bindery_v1", offering:
   offering))` **exactly once per presentation** — guard it behind state, not `onAppear`, which
   fires repeatedly.
5. Move any copy you might want to A/B into `offering.getMetadataValue(for:default:)`.

### Step 5 — Two-path vial grant (this is the safety net replacement)

Today `purchase()` delivers to the proxy **before** `transaction.finish()`, so a failed
delivery leaves the transaction unfinished and StoreKit redelivers it next launch. Under
`.revenueCat` the SDK finishes consumables once *RevenueCat's* backend has recorded them. That
specific guarantee is gone, so replace it with two independent paths that converge:

**Fast path (client, unchanged proxy).** Immediately after `Purchases.shared.purchase(package:)`
returns for a vial, call `StoreKit.Transaction.latest(for: productID)` — this is exactly what
RevenueCat's own `recordPurchase(productID:)` does internally — take `jwsRepresentation` off the
`VerificationResult`, confirm the transaction id matches, and POST to `/v1/credits/grant`
exactly as today. `receipts.js` and the whole Apple-root verification chain stay untouched.

> **Verify this on day one of sandbox testing.** `StoreTransaction.jwsRepresentation` is
> `internal` in the SDK — `sk2Transaction` is public but a bare `StoreKit.Transaction` does not
> carry the JWS. If `Transaction.latest(for:)` does not return a finished consumable's
> `VerificationResult`, the fast path is dead and the webhook below becomes the only grant,
> which means the wallet fills in seconds-to-minutes rather than instantly. Do not discover
> this in October.

**Backstop (webhook, authoritative).** Add `POST /v1/rc/webhook` to `server.js`:

- Register the path in `ADMIN_ROUTES` (`server.js:446`) so the `x-ink-user` hook skips it.
- Authenticate with the Authorization header from step B12 via `timingSafeEqual`, mirroring
  `/v1/admin/reports` (`server.js:1682-1688`). Optionally also verify
  `X-RevenueCat-Webhook-Signature` (`t=<unix>,v1=<hmac_sha256_hex>` over
  `"<timestamp>.<raw_body>"`).
- `NON_RENEWING_PURCHASE` → `stores.claimTransaction` + `stores.grant`, keyed on
  `event.transaction_id`. **Reuse the existing idempotency** — the same key the fast path uses,
  so whichever arrives first wins and the second is a no-op.
- `CANCELLATION` with a refund `cancel_reason` → the same `stores.revoke` clawback
  `/v1/notifications` performs today. There is **no standalone `REFUND` event type**.
- `INITIAL_PURCHASE` / `RENEWAL` / `EXPIRATION` on a `PLUS_PRODUCTS` id → `setTier` /
  `clearTierByTransaction`.
- Always answer `200` fast. Non-2xx costs you 5 retries at 5/10/20/40/80 minutes and then the
  event is gone permanently.
- New env var `INK_RC_WEBHOOK_SECRET`; document it in `deployment.md` §6.4 beside the
  already-reserved `REVENUECAT_API_KEY`.

**Reconciler (cheap insurance).** A periodic sweep comparing RevenueCat's
`GET /v1/subscribers/{app_user_id}` → `non_subscriptions` against `redeemed_transactions`
catches anything lost after the fifth webhook retry. Small, and it closes the last hole.

### Step 6 — Swap the binding

One line: the concrete type at `LiveCommerce.swift:87`. `AppModel.swift:211` and
`PageInteractor.swift:188` follow through their defaults. Guard the RevenueCat path behind a
build flag for the first TestFlight so a rollback is a flag, not a revert.

### Step 7 — `/v1/entitlement` needs no change

Subscriptions still appear in `Transaction.currentEntitlements` with their `VerificationResult`
even when RevenueCat manages them, so the existing Plus attestation keeps working byte for
byte. Only the consumable JWS was ever in question. Once the webhook of step 5 is live and
proven, `/v1/entitlement` becomes redundant belt-and-braces rather than load-bearing — keep it
anyway; it is the offline-tolerant path.

### Step 8 — One experiment (this is the HAMM entry)

Once live: create a second Offering that differs in exactly one thing — trial length, or a
metadata key that changes the paywall's in-fiction framing — and run it as an experiment.
Variants map 1:1 to Offerings (up to 4), minimum 10% enrollment, new-customers-only by default.
Assignment reaches the app through `offerings.current` with **no client change**, which is
precisely why step 4's "never hardcode an offering" rule matters.

This is what upgrades the submission from "uses RevenueCat" to "runs revenue experiments on
it", against HAMM's literal criterion: *"Does the app demonstrate an innovative or unique
approach to monetization that goes beyond standard models?"*

### Step 9 — Optional, post-launch

Customer Center (`RevenueCatUI`, iOS 15+, SDK 5.14.0+) as a Drawer row: cancel, restore, plan
change, and Apple's refund-request sheet in one drop-in. It brings standard chrome, so it
belongs in the Drawer, never on the paywall. It is not an App Review requirement — RevenueCat
does not claim it is — and `DrawerView` already routes bound users to Apple's
`.manageSubscriptionsSheet`. Nice-to-have.

---

## 4. Verification — the only proof that counts

No new tests. The repo forbids growing the suite, and nothing in the existing suite touches the
real purchase path anyway: `CommerceTests` and `RitualTests` only ever construct
`UnboundPurchaseService`, and no proxy test covers `/v1/credits/grant`, `/v1/entitlement`,
`/v1/notifications`, `receipts.js` or `appattest.js`. **CI will stay green through an adapter
that is completely broken at runtime.** Budget for the manual pass instead.

On a physical iPad, sandbox account, Release-style scheme:

1. Paywall paints both prices from the Offering; the 54% saving tag appears.
2. Trial tag appears for a fresh Apple ID and **not** for one that has already trialled.
3. Buy weekly → Plus unlocks → the customer appears in RevenueCat with entitlement `plus`.
4. Buy a vial pack → balance rises → confirm **which** path credited it (check proxy logs for
   `grant:` vs the webhook) — both should be exercised at least once.
5. Kill the app mid-delivery, relaunch → credits arrive, exactly once, never twice.
6. Restore with an entitlement → "The binding holds". Restore without one → "No binding was
   found", not an error.
7. Ask-to-Buy → `.pending` → "The binding waits", and nothing is granted.
8. Refund a sandbox purchase → confirm the clawback fires through **whichever** path B7 left
   live, and check the forwarded notification actually reached `/v1/notifications`.
9. Confirm the **Release** scheme has no StoreKit configuration file selected — `project.yml`
   pins `Inkwoven.storekit` on the scheme, and a local catalog both masks real product-fetch
   failures and prevents purchases reaching RevenueCat at all.

---

## 5. Sequencing against the Shipaton clock

51 days remain as of 2026-08-10. The Grand Prize ($100k) is judged on post-launch traction —
"Early and Effective Release" plus "Growth by numbers" — so **every day between launch and
September 30 is scored evidence.** Shipping late structurally forfeits it.

| When | Do |
|---|---|
| **Today** | §2 A1–A2, B1–B6, B11. Costs an hour, unlocks Ship Kit milestones 2 and 3, and starts RevenueCat's account age. Nothing here needs the pricing decision. |
| **This week** | Settle §0. Then A3–A7, B8–B10, B12–B13. Engineering steps 1–4 in parallel. |
| **Next** | Steps 5–7. Sandbox pass (§4). First real store API call → Ship Kit milestone 4. |
| **Launch** | Step 6 flag on. First real purchase → milestone 5. |
| **After** | Step 8 (the experiment). Post the RevenueCat charts publicly — this is simultaneously the #BuildInPublic entry and the HAMM evidence. |
| **Sep 28–29** | Submit. Never September 30. |

**Hard deadline:** the Submission Period closes **Wednesday 30 September 2026, 11:45pm PDT** —
simultaneously the registration deadline, the submission deadline, and the last day a first
public release may occur. Judging runs Oct 1–13; winners Oct 21.

### Corrections to `shipaton-strategy.md` (2026-08-02)

- **HAMM is "Help Apps Make Money"** — a monetization award. The Hipster/Hustler/Hacker reading
  appears nowhere in the 2026 material. The strategy doc's §2 should be corrected.
- **#BuildInPublic is $30k / $20k / $10k** — the second-largest prize after the Grand Prize,
  and larger than Design or HAMM. It cannot be manufactured on September 29; it needs the
  posting trail. Worth re-ranking the priorities.
- **The SDK requirement's exact wording** is broader than remembered: *"uses the RevenueCat SDK
  to power at least one in-app or web purchase, or that serves ads through RevenueCat Ads."*
- **Submission Period opens July 31, 8:00am PDT** in the formal rules, while the blog and
  overview page say August 1. A release dated August 1 or later is unambiguously safe.
- **21 prize categories, $700k+**, not eight at $490k.
- **Türkiye is not named as excluded.** The clause is sanctions-based (OFAC catch-all), and
  Türkiye is not under comprehensive US sanctions. This is a reading of the clause, not an
  affirmative statement in the rules.
- **No documented SDK-verification step and no RevenueCat project ID field** on the general
  Devpost submission — but milestone detection is automatic, so RevenueCat can see whether the
  account produced a real purchase. The account/entry linkage happens through the
  post-registration participant form, not the Devpost submission.

---

## 6. Risks, named

1. **The consumable JWS.** `StoreTransaction.jwsRepresentation` is internal. The fast path
   depends on `Transaction.latest(for:)` returning a finished consumable's `VerificationResult`.
   Unverified. Test it first; the webhook backstop is why this is a latency risk and not a
   money risk.
2. **The ASSN slot.** One production URL, one sandbox URL. Forwarding is documented and clean,
   but production forwarding failures are a recurring community complaint. Do not decommission
   any clawback path until the replacement has fired in production.
3. **Trust anchor downgrade.** `receipts.js` exists because "StoreKit verified it on device" is
   not a control when the client is whatever speaks HTTP. A webhook path replaces Apple's
   signature chain with "RevenueCat says so, over a bearer token". That is a deliberate
   reduction, not a neutral swap — which is exactly why the fast path keeps the Apple chain and
   the webhook is HMAC-verified.
4. **Swift 6.** `Purchases` is `@unchecked Sendable` with an in-source admission of
   non-thread-safety; the delegate has no actor isolation. Expect concurrency diagnostics to
   dominate the compile-fixing time.
5. **Silent green CI.** Nothing covers this surface. §4 is the only verification.
6. **Product ID permanence.** Five identifiers, typed once, forever. `plus_weekly`,
   `plus_monthly`, `vials_small`, `vials_medium`, `vials_large` — matched character for
   character against `Products.swift:7-16`.
7. **Pre-existing, unrelated, and still launch-blocking:** `/v1/video` never calls `tierOf`
   (`server.js:1015-1252`), so a subscriber is metered exactly like a free user today. Any Plus
   video allowance is unenforceable until that lands. RevenueCat does not fix it.

---

## 7. What this plan deliberately does not do

- Does not adopt RevenueCat Virtual Currencies (§1).
- Does not replace the in-fiction paywall with a RevenueCat template (§1).
- Does not use observer mode as the end state (§1).
- Does not add tests (§4).
- Does not touch `Packages/InkwovenCore` (§3 step 1).
- Does not resolve the `video-in-plus.md` pricing question (§0) — that is Melih's call.

---

## 8. Backlog

`tasks.md` task **A4** was stale — it named the dropped annual plan, the retired
`credits_10/30/100` ladder and cut Bindery SKUs. It has been rewritten and split into Epic G
stories G7–G10 in the same commit as this document.

---

## 9. Sources

Read on 2026-08-10, then adversarially re-verified against the same pages and against
purchases-ios source pinned at tag 5.83.1.

- purchases-ios releases, `Package.swift`, `Configuration.swift`, `StoreKitVersion.swift`,
  `Purchases.swift`, `PurchasesType.swift`, `StoreTransaction.swift`, `TransactionPoster.swift`,
  `StoreKit2ObserverModePurchaseDetector.swift`, and the public `.swiftinterface` files
- revenuecat.com/docs: installation/ios, configuring-sdk, customer-info, entitlements,
  offerings, projects (overview, settings, authentication, connect-a-store), api-v1, api-v2,
  integrations/webhooks (+ event-types-and-fields, sample-events), paywalls (v2 and
  custom-paywalls-index), tools/experiments, tools/targeting, tools/customer-center,
  platform-resources/non-subscriptions, platform-resources/server-notifications/apple,
  service-credentials/in-app-purchase-key-configuration and app-store-connect-api-key,
  migrating-to-revenuecat/sdk-or-not, sdk-guides/ios-native-4x-to-5x-migration, pricing
- revenuecat-shipaton-2026.devpost.com (overview, rules, resources), shipaton.com/ship-kit,
  revenuecat.com/blog/company/announcing-shipaton-2026,
  revenuecat.github.io/codelabs/shipaton-2026-prep
- developer.apple.com/help/app-store-connect (In-App Purchase key generation)

Four claims were refuted during verification and are already corrected above: v2 REST requires
its **own** V2-versioned secret key (a v1 `sk_` key 401s); RevenueCat's StoreKit 2 selection
floor is **iOS 16**, not the iOS 15 its doc comment states; promotional entitlement grant/revoke
exists in **both** v1 and v2; and there is **no** `X-Is-Sandbox` header on the v1 subscriber
lookup.
