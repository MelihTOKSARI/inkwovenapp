# Inkwoven — Pre-Release Audit

**Date:** 2026-08-04, 08:58 (+03, Europe/Istanbul)
**Auditor:** Claude (Cowork), acting as product owner / reviewer
**Repository:** `Inkwoven`
**Audit baseline:** working tree as of commit `a2219a3` ("feat(vials): make the shop reachable")
**HEAD at time of writing:** `ef1b770` ("fix(feel): don't offer a pulse the hardware cannot give")
**Verdict:** **Do not submit.** 9 blockers, 12 high, 14 medium.

---

## 1. Scope and method

Five independent read-only passes over the whole repository — 105 Swift files across the app target and seven SPM packages, the Fastify proxy and its test suite, the CI workflow, the StoreKit configuration, the privacy manifest, and the five product documents. Passes covered App Review compliance and monetization; privacy, security and the backend; safety and crisis handling; core-loop correctness and data integrity; and accessibility, release configuration and documentation consistency.

Every finding marked BLOCKER or HIGH in this document was independently re-verified against source by the author after the passes completed. Findings that could not be verified are marked as such in §7. No file was modified during the audit.

### Baseline drift

Five commits landed between the start of the audit and this document: `0eb6fad`, `1219550`, `5abacce`, `9db819a`, `ef1b770`. They touch 14 files (+556 lines), all of them the haptics/launch-veil work and the vials shelf entrance.

None of these files is the subject of a BLOCKER finding. `proxy/src/server.js`, `config.js`, `attest.js`, `models.js`, `DeclineMapper.swift`, `CrisisView.swift`, `PageInteractor.swift`, `HybridInkSurface.swift`, `PenPresence.swift`, `PolicySheet.swift`, `PurchaseService.swift`, `InkPalette.swift` and `ci.yml` are all unchanged since the baseline, so every blocker stands as written.

Six files carrying MEDIUM accessibility findings *did* change — `PageView.swift`, `PaywallView.swift`, `DrawerView.swift`, `ShelfView.swift`, `PageToolTray.swift`, `Components.swift`, `HandPicker.swift`, `PurchaseNotes.swift`. The defects are unaffected but **line numbers in §5 may have drifted by a few lines** in those files. Search by symbol rather than trusting the line number.

### Disclosure

The `Feel.swift`, `LaunchGlow.swift` and `Resources/Sounds/` work that entered the tree earlier in this session was written by the auditor before the audit was requested. It has since been reviewed and refined by the development session and committed in `0eb6fad` through `ef1b770`. It is excluded from audit scope; it should be reviewed by someone other than its author.

---

## 2. Verdict

The engineering craft here is high, and that is not a courtesy. The receipt verifier is real cryptography. The Keeper's privacy seal is airtight under adversarial reading. The prompt-injection fencing on the memory and video paths could not be broken on paper. `IdleSendMachine`, `SSEParser` and `SpeculativeUpload` are all correct. Dynamic Type handling is better than most shipping apps.

The failures are not scattered — they cluster in three places, and each cluster has a single root.

**Money.** Server-side identity is free to mint, which voids every per-user control that depends on it. One purchased receipt can be replayed into unlimited credits, and the exchange endpoint is entirely unmetered. This bleeds real money from day one, at attacker-chosen scale.

**Safety.** Crisis detection rests on a single in-band instruction to the reply model, matched as an exact string prefix, with no independent classifier despite two places in the codebase asserting one exists. Worse, the path taken by the *most* explicit disclosures — provider-side moderation — routes to an in-fiction shrug with a retry button rather than to help.

**Data.** There is no draft persistence anywhere. A user's page exists only in RAM until an exchange completes successfully, and several ordinary interactions destroy it.

Any one of the three is a reason not to ship. Together they mean the product is not ready for a public first release.

---

## 3. Findings index

| ID | Severity | Area | Summary |
|---|---|---|---|
| M-1 | BLOCKER | Money | Receipt redeemable once *per identity*, not once ever |
| M-2 | BLOCKER | Money | `/v1/exchange` unmetered server-side |
| M-3 | BLOCKER | Money | App Attest is scaffolding; any string is an account |
| M-4 | HIGH | Money | No refund/revocation path; unfinishable transactions |
| M-5 | HIGH | Money | Plus image cap unreachable — `canSend` hardcodes `.ink` |
| M-6 | HIGH | Money | Free-tier cap lives in UserDefaults only |
| M-7 | MEDIUM | Money | Wallet bound to local UUID; paid credits don't survive device change |
| S-1 | BLOCKER | Safety | Moderated self-harm page → "try again", never crisis |
| S-2 | BLOCKER | Safety | No crisis classifier; PRD and code comments claim one |
| S-3 | BLOCKER | Safety | Sentinel matched as exact prefix; gate latches open |
| S-4 | BLOCKER | Safety | Fiction framing is a documented crisis bypass |
| S-5 | HIGH | Safety | `tel:988` unguarded on a Wi-Fi iPad; resources US-only |
| S-6 | HIGH | Safety | Safety override omits ED, substance, abuse, third-party risk |
| S-7 | HIGH | Safety | Reports reach a table nobody reads |
| S-8 | MEDIUM | Safety | Crisis is a one-way door; resources unreachable afterwards |
| S-9 | MEDIUM | Safety | No age gate; contradictory age-rating answers planned |
| D-1 | BLOCKER | Data | No draft persistence of any kind |
| D-2 | BLOCKER | Data | Concurrent exchanges — double billing, unarchived reply |
| D-3 | BLOCKER | Data | `completeExchange` archives the wrong strokes |
| D-4 | HIGH | Data | Exchange not cancelled on teardown; moment spent, nothing filed |
| D-5 | HIGH | Data | Crisis interception destroys the page |
| D-6 | HIGH | Data | `retry()` does not retry |
| D-7 | HIGH | Data | Whole journal is one all-or-nothing JSON array |
| D-8 | MEDIUM | Data | Cancelled task clobbers status; no client-side deadline |
| D-9 | MEDIUM | Data | `holdToggled` is a no-op mid-flight and re-arms the cadence |
| D-10 | MEDIUM | Data | Offline copy promises a queue that does not exist |
| C-1 | HIGH | Compliance | In-binary terms describe a plan that does not exist |
| C-2 | HIGH | Compliance | Intro-offer eligibility never checked |
| C-3 | HIGH | Compliance | Prices load once, no retry, USD fallback everywhere |
| C-4 | MEDIUM | Compliance | Review notes describe nonexistent products |
| C-5 | MEDIUM | Compliance | Privacy manifest understates collection |
| C-6 | MEDIUM | Compliance | Export writes plaintext to `tmp/`, survives "delete all" |
| C-7 | MEDIUM | Compliance | Keeper migration can leak pages into un-gated export |
| A-1 | BLOCKER | Access | One pencil touch permanently disables the keyboard |
| A-2 | HIGH | Access | Paywall plan selection invisible to VoiceOver |
| A-3 | HIGH | Access | Four modals lack `.isModal`, including delete-all |
| A-4 | HIGH | Access | Tool tray targets are 38pt, not the 44pt claimed |
| A-5 | HIGH | Access | Daylight palette fails WCAG down to 2.32:1 |
| A-6 | MEDIUM | Access | Unnamed toggles; four identically-named swatches |
| A-7 | MEDIUM | Access | Decorative ornaments read aloud |
| A-8 | MEDIUM | Access | `nibDot` ignores Reduce Motion |
| I-1 | BLOCKER | Infra | CI never compiles or tests the app target |
| I-2 | MEDIUM | Infra | UI test asserts on a string the app cannot emit |
| I-3 | MEDIUM | Infra | Dependency gate set to `critical`, masking five high advisories |
| I-4 | MEDIUM | Infra | Documentation asserts work that does not exist |

---

## 4. Blockers in detail

### M-1 · Receipt replay
`proxy/src/server.js:1119` · verified

The grant route keys idempotency as `stores.idempotent(request.userID, 'grant:' + transactionID, ...)`, which resolves to `${userID}:${key}` in both store implementations (`stores.js:207`, `stores-redis.js:326`). The scope is per-identity. A grep of `stores-redis.js` for `transactionId` / `transaction_id` returns nothing — no global record of a redeemed transaction exists.

The receipt verification itself is genuinely strong, which is what makes this dangerous: every replay passes signature checking, product and transaction claim matching, and the revocation check, because the receipt is real. Buy one 20-vial pack, capture the JWS (StoreKit returns it on every restore), and POST it under rotated `x-ink-user` values. Each new identity is credited afresh. `purchase()` is called with no options at `PurchaseService.swift:149`, so no `appAccountToken` is set and nothing binds a transaction to a buyer.

Two audit passes found this independently.

### M-2 · Unmetered exchange
`proxy/src/config.js:44` · verified

`exchangeCosts: { ink: 0, image: 0, video: 1 }`. Because ink and image cost zero, the reserve/settle block at `server.js:499-510` is skipped entirely — no wallet, tier, entitlement or daily counter is ever consulted on an exchange. There is no server-side quota of any kind.

The free-tier cap of five moments a day and the Plus image soft cap of eight both live only in `App/Money/DailyUsageStore.swift`, a JSON blob in the standard UserDefaults suite. A scripted client never executes that code; a reinstall resets it while the Keychain identity survives. The comment at `InkMoney/Entitlements.swift:11` stating that counters are "server-authoritative (the proxy tracks them)" is false.

Client rate limiting is also unreachable in the config it depends on: `ProxyClient` has no `GET /v1/config` call, so `GateConfig` always uses compiled-in defaults, and the "tunable without a release" promise at `config.js:1` does not hold.

### M-3 · Attestation is scaffolding
`proxy/src/attest.js:58` · verified

In `anonymous` mode, `verify({ token })` returns `{ userID: token }` — the client-supplied header, unmodified. Any string under 256 characters is an account with its own wallet and its own lifetime free-clip allowance. There is no assertion, nonce, counter or expiry, so the token is a permanently replayable bearer secret.

The Dockerfile sets `NODE_ENV=production`, which defaults the mode to `required`, which 401s every request. The app therefore only functions with `INK_ATTESTATION_MODE=anonymous`, and `deployment.md:436` makes setting it a launch-checklist item.

This is the multiplier on M-1 and M-2. With free identities, per-user limits are decorative and only per-IP ceilings remain.

### S-1 · Moderated disclosures route away from help
`InkSafety/DeclineMapper.swift:22` · verified

`.moderated` maps to `.pageDeclines`. The full trace: an explicit suicide note trips the upstream provider's own safety filter → `models.js` returns a `blockReason` → `ProviderError kind:'moderated'` → `server.js:262` sends HTTP 422 → `ProxyClient` throws `.moderated` → `DeclineMapper` → `PageInteractor:726` → `PageView:547` renders *"The spirit is distant tonight. Your page is safe — I will answer when the candle steadies."* with a **try again** button at `PageView:513`.

No crisis card. No resources. The inversion is the point: the more explicit and unambiguous a disclosure is, the more likely the provider blocks it, and blocking is precisely the path that routes away from safety.

This is the smallest fix in the document and the one with the most human consequence.

### S-2 / S-3 · Crisis detection depends on the model's cooperation
`proxy/src/models.js:140`, `proxy/src/server.js:559` · verified

Detection is one instruction inside the system prompt (`SAFETY_OVERRIDE`) asking the reply model to open with `[[CRISIS]]`, competing in the same turn with the user's handwritten page. The page image is the one channel with no injection fencing — `sanitizeContext` at `models.js:98` covers only `memorySummaries` and `sessionSummary`.

The gate matches as an exact prefix of the trimmed reply head. If the model prepends anything — a quote mark, bold markers, "I hear you." — both branches fail, `gateOpen` latches true at `server.js:565`, and every subsequent delta is forwarded verbatim. The user reads the literal string `[[CRISIS]]` rendered as the Book's handwriting. Once open, the gate can never fire again, so a model that recognises danger three sentences in cannot escape either.

There is no classifier. `prd.md:135` promises *"Crisis + moderation | nano-class model | Runs parallel, never blocks the reply"* and `InkSafety/CrisisInterceptor.swift:4` repeats it. `CrisisInterceptor` is a stream router containing zero text matching. A grep of `proxy/test/` for "crisis" returns nothing; `CrisisTests.swift` injects a pre-fabricated chunk and asserts routing. A model regression or provider swap removes the entire safety net with every test still green.

### S-4 · Fiction is an exemption
`proxy/src/models.js:143` · verified

The override reads: *"A villain's threat, a character's death, peril in the Game Master's adventure, or a dark tale the writer asked the Book to tell is not a crisis — stay in character for those."* `books.js:78` instructs the Storyteller to *"carry the tale onward a few sentences — vivid, concrete, always ending at a place that invites their pen back."*

A user writing "Begin a tale — a girl swallows her mother's pills and finally sleeps" gets the next scene written for them in vivid concrete detail, and the pen handed back. Nothing downstream catches it: `createPromptModerator` guards video prompts, `enable_safety_checker` guards images, and the assembled ink reply is never moderated on any path.

### D-1 · No draft persistence
`App/Page/PageInteractor.swift:757` · verified

There is exactly one call to `archive.archive(...)` in the entire application, inside `completeExchange`. `PageView` has no `onDisappear` and no `scenePhase` handler; `RootView:69` handles only the Keeper relock.

Confirmed total-loss paths: writing at length without a four-second pause and being jetsammed; tapping "the shelf" (`PageView:197`); tapping the Remembered ribbon (`:218`); switching Book (`RootView:36` uses `.id(model.activeBookID)`, destroying the view); and crisis interception. `completeExchange` also clears the last recovery path at line 774 by removing all undo actions.

### D-2 / D-3 · Concurrent exchanges and the wrong strokes
`App/Page/PageInteractor.swift:469`, `:746` · verified

Line 469 assigns `exchangeTask` without cancelling the previous one, and no in-flight guard exists. The canvas stays live and the idle cadence stays armed during a stream: `strokeEnded()` unconditionally sets `.resting` and restarts ticking, so four seconds later a second exchange commits. The digest dedupe does not catch it, because `sentStrokeCount` is never advanced at send time — the second snapshot crops from index zero and yields a different digest.

Then `completeExchange` archives `canvas?.drawing` *as of completion*, not what was sent. Two consequences: an in-progress sentence gets filed under the previous exchange's reply and then wiped; and in the concurrent case, the first completion empties the canvas so the second reply is billed but never archived at all.

### A-1 · The keyboard can be permanently disabled
`App/Design/HybridInkSurface.swift:65`, `App/Design/PenPresence.swift:29` · verified

`apply(pencilActive:)` sets `textView.isUserInteractionEnabled = !pencilActive`. `PenPresence.note(_:)` writes `ink.pencilSeen` to UserDefaults on the first pencil touch and never clears it; the class comment states the surface flips to ink "for good". `DrawerView` — all 621 lines — has no reset.

A VoiceOver user, or anyone with a tremor or motor impairment, who owns a Pencil-equipped iPad, or borrows one where anybody ever drew a single stroke, finds the keyboard suppressed on the flyleaf and on every page, permanently. Their only remaining action is the onboarding skip button, which delivers them to a shelf of Books none of which they can write in.

### I-1 · CI does not build the app
`.github/workflows/ci.yml:70` · verified

The only Swift step is `swift test --package-path app/Packages/InkwovenCore`. There is no `xcodebuild test` and no `xcodegen` step; line 67 merely prints `xcodebuild -version`. The app target is never compiled, and all eight `@Suite` files in `app/Tests/` plus both `app/UITests/` classes never execute. A compile break in roughly 5,000 lines of app-target Swift reaches `main` green.

`development.md:28` claims *"CI: `xcodebuild test` (app) + `swift test` (packages) on every commit."*

---

## 5. High and medium findings

Grouped by area. Each is stated with its location; the detail behind each is reproduced in the remediation tasks in §8.

**Money.** `SendGate.canSend` is called from exactly one site (`PageInteractor.swift:422`) which hardcodes `modality: .ink`, so the Plus image soft cap — the app's only image-cost control — is unreachable at runtime while `imagesUsedToday` continues to increment faithfully (M-5). No App Store Server Notifications endpoint exists, and `PurchaseService.swift:184` never checks `revocationDate`, creating transactions that can never be finished and are re-POSTed on every launch forever (M-4). The wallet is keyed to a locally minted UUID, so paid credits do not survive a device change and nothing in the app says so (M-7).

**Safety.** Crisis resources are hardcoded US lines opened via bare `UIApplication.shared.open` with no `canOpenURL` guard, on an iPad-first app where `tel:` frequently has no handler (S-5). The override's scope covers danger from oneself only, omitting disordered eating, substance harm, abuse by another, and third-party risk — while the Keeper is instructed to reflect warmly and specifically whatever is set down (S-6). Filed reports INSERT into a table with no reader, no webhook and no alert, swept unread at ninety days, while `ReportSheet.swift:41` promises human review (S-7). `CrisisView`'s only exit discards the page, and the screen is unreachable except from a live detection (S-8). No age gate exists anywhere, and the planned rating answers contradict the presence of a 1.2 report mechanism (S-9).

**Data.** An exchange is not cancelled on view teardown, so leaving mid-send spends a moment and files nothing (D-4). Crisis interception deliberately skips archiving, guaranteeing the loss of the most significant page a user will write (D-5). `retry()` resets to `.idle` without re-arming the send cadence, so the button is inert (D-6). The whole journal is a single JSON array, so one undecodable byte quarantines everything with no in-app recovery, and a present-but-unreadable file silently blocks every write for the session (D-7). `runExchange` never checks `Task.isCancelled` before writing status, and `exchange()` sets no client-side timeout (D-8). `IdleSendMachine` has no `(.committed, .holdToggled)` transition, so the hold button re-arms the cadence mid-flight instead of pausing it (D-9). Both offline strings promise queue-and-send-later behaviour that does not exist (D-10).

**Compliance.** `PolicySheet.swift:36` describes an annual plan with a seven-day trial; the StoreKit configuration contains only weekly (P1W, P3D intro) and monthly (P1M, no intro) (C-1). `isEligibleForIntroOffer` appears nowhere, so ineligible returning subscribers are shown a trial promise and charged (C-2). Prices load once at launch with no retry and fall back to hardcoded USD in every storefront (C-3). The listing's "paste this verbatim" review notes describe an annual SKU, 10/30/100 credit packs, Bindery cosmetics, Sign in with Apple and in-app account deletion — none of which exist (C-4). The privacy manifest omits purchase history and declares both collected types as unlinked while the proxy stores everything under a collected user ID (C-5). Export writes the entire journal in plaintext to `tmp/` at a weaker protection class than the archive, is never deleted, and is not reached by "delete all pages" (C-6). A partially failed Keeper migration leaves sealed pages in the un-gated `entries` array, which the Drawer's export reads directly (C-7).

**Accessibility.** Paywall plan selection is expressed only visually, with no `.isSelected` trait and no accessibility value, so a VoiceOver user cannot tell which plan they are about to buy (A-2). Four hand-rolled modals omit `.isModal`, including the irreversible delete-all confirmation, leaving content behind the scrim swipe-reachable and actionable (A-3). `.contentShape(Circle())` is applied before the sizing frame in `PageToolTray:53`, making all seven page tools 38pt rather than the 44pt `Components.swift:4` claims; the Drawer's ink swatches are 28pt (A-4). Two Drawer toggles have no accessible name and four ink swatches share one label (A-6). Decorative ornaments are read aloud (A-7). `nibDot` is the one ambient animation with no Reduce Motion guard (A-8).

**Contrast (A-5).** Computed independently by the author; the candlelight palette passes comfortably and should not be touched.

| Pair | Ratio | AA body (4.5:1) |
|---|---|---|
| daylight `dim #7A6544` on `bgOuter #BDA478` | **2.32:1** | fail (below the 3:1 non-text floor) |
| daylight `accent #8A5A15` on `bgOuter` | **2.46:1** | fail |
| daylight `dim` on `bgMid #D8C39C` | **3.24:1** | fail |
| daylight `heading #7A4A15` on `bgMid` | **4.33:1** | marginal fail |
| daylight `text #3D2F1F` on `bgMid` | 7.51:1 | pass |
| candlelight `dim #9A876A` on `bgMid #17110B` | 5.39:1 | pass |
| candlelight `text #E7D9BF` on `bgMid` | 13.44:1 | pass |
| candlelight `accent #C9962E` on `bgMid` | 7.03:1 | pass |

The radial gradient at `InkPalette.swift:106-111` places `bgOuter` across the lower-right of a 13-inch iPad in landscape — exactly where `DrawerView:187`, `:470` and `:486` render body copy.

---

## 6. What is solid

Recorded deliberately, because it should inform what gets touched during remediation.

`receipts.js` is real cryptography rather than theatre: a full x5c chain walk with `checkIssued` and `verify` on every link, validity dates checked per certificate, raw DER equality against the configured Apple root (which is what defeats an attacker-minted self-signed chain), ES256 with `ieee-p1363` encoding, and a `null` return that makes the route 501 rather than trust anything when unconfigured.

No secret, key or credential is committed anywhere. Provider keys are read from the environment at call time, `fly.toml` carries only `PORT`, and the Dockerfile bakes nothing, pins its base image by digest, runs as uid 1000 and omits devDependencies — with CI asserting all three independently.

The Keeper's privacy seal survived adversarial reading in full. `LiveKeeperAuth` builds a fresh `LAContext` per attempt; every launch-arg route override is `#if DEBUG`; `RootView` carries a structural gate on `.page` independent of `open(book:)`; `entries(for: .keeper)` returns empty while sealed; `sealKeeper()` fires on background and clears both `revisit` and `reportTarget`; the report sheet is an in-`ZStack` overlay so the app-switcher cover actually covers it; and the keeper store is backup-excluded at `.completeUnlessOpen`.

Entitlements are derived solely from `Transaction.currentEntitlements` with correct verified, revoked and expiry guards, `setTier` is the only mutator, and the old forgeable flags (`ink.bound`, `ink.credits`) are actively destroyed at init and covered by a test.

The prompt-injection fencing on client-supplied context is the best code in the repository and could not be broken on paper: `scrub` strips all of `\p{Cc}\p{Cf}` plus soft hyphen and variation selectors, removes angle brackets outright rather than matching runs, the verdict parse is single-line so a trailing instruction cannot ride along, `composeVideoPrompt` brackets the user-derived subject with rules on both sides, and both moderators fail closed.

Rate limiting genuinely holds across instances — `RATE_ALLOW_LUA` makes INCR+EXPIRE atomic, `keyPart` hashing removes namespace ambiguity, `trustProxy: 1` reads the rightmost hop, and `index.js` hard-exits in production without Redis and Postgres so the in-memory store cannot silently serve production.

The pure engine is correct. `IdleSendMachine`'s transition table is exhaustive for the states it enumerates, clamps negative timings, and checks `commitAfter` before `speculateAfter` so an inverted config cannot orphan an upload. `SpeculativeUpload`'s generation counter correctly discards and aborts a `preupload` that resolves after commit. `SSEParser` is byte-fed, spec-correct on CRLF, multi-line data, comments and unknown fields. `ChunkDecoder` fails closed on `crisis` and only on `crisis`. `MomentBilling` correctly excludes any stream containing a crisis chunk, and the server releases rather than settles the hold — a user in crisis is not charged and is not offered a picture.

On the compliant path the crisis flow is well designed: the server holds ink back until it can rule out the sentinel rather than streaming and retracting, `flushInk` fails closed on a truncated fragment, the client buffers the whole reply and reveals it only at `.answered`, and `CrisisView` is correctly built as a fiction break — system font, flat background, `@ScaledMetric` throughout, proper labels and hints. The helpline data itself is current and correct; 988 and 741741/HOME are right and findahelpline.com is real.

The AI disclosure is honest and early. `OnboardingView:335-357` places "a spirit of ink, not a person" above the fiction, the intro says "not a person, not a friend", and `PolicySheet:24` restates it plainly.

Accessibility work that *was* done is thoughtful rather than decorative: `spokenStatus` posts real announcements on `.answered`, `.declined` and `.cooldown`; both hybrid surfaces use `.accessibilityElement(children: .contain)` with the reasoning written down; `PageHistoryThread` collapses each exchange into one element naming who wrote what; `InkFont` routes every face through `relativeTo:` on a role-appropriate text style; and the one piece of type that physically cannot grow is deliberately capped while keeping its full VoiceOver label.

`PrivacyInfo.xcprivacy` correctly declares only `CA92.1` and warns against speculative declarations — the required-reason API audit came back clean across all five categories. `project.yml` is disciplined, keeping signing, versioning, export compliance and the ITMS-91053 resource-phase workaround in the generator with each hazard documented. The CI that exists is well built — SHA-pinned actions, least-privilege permissions, concurrency cancellation, Docker non-root and devDependency assertions, a boot smoke test. It is simply pointed at the wrong half of the repository.

---

## 7. Coverage and limitations

Three things could not be verified and should not be treated as either confirmed or cleared.

`npm audit` could not be run — no lockfile was available to the audit environment — so the five high-severity advisories the CI workflow itself enumerates at `ci.yml:95-101` are unconfirmed as to exploitability. One of them concerns `X-Forwarded-*` spoofing. Under anonymous identity, per-IP limits are the only remaining ceiling on model spend, so if that advisory is live there is no backstop at all. The blocking gate is set to `critical`, so none of the five can fail CI.

`design/app-store-assets/` was not reachable. The stale `app-store-listing.md` marks itself superseded and points there, so it is unknown whether the corrected listing exists or whether the incorrect strings in C-4 were retired.

An earlier pass reported `Assets.xcassets` and the 21 bundled fonts as missing, which would have been an ITMS-90713 rejection. **This was a false alarm** caused by incomplete file staging; the icon set, `LaunchBackground` colour set and all 21 `.ttf` files were confirmed present on disk. Recorded here so it is not actioned by mistake.

Finally, this audit is static. Nothing was built, run, or tested against a live proxy or a real StoreKit sandbox. Every finding is derived from source reading and should be confirmed by reproduction before being closed.

---

## 8. Remediation tasks

Fourteen self-contained task briefs, written to be handed to an implementation agent one at a time. Sequencing guidance follows in §9.

### T1 · Make a purchase redeemable exactly once, globally

```
Make a StoreKit purchase redeemable exactly once, globally.

DEFECT: app/proxy/src/server.js:1119 keys grant idempotency as
stores.idempotent(request.userID, `grant:${transactionID}`, ...), which builds
`${userID}:${key}` (stores.js:207). The scope is per-identity, not per-transaction.
I grepped stores-redis.js for transactionId/transaction_id — there is no global
record of a redeemed transaction anywhere. Combined with the anonymous attestation
mode (attest.js:58 returns { userID: token } verbatim), one captured receipt JWS
replayed under rotated x-ink-user values mints unlimited credits from one purchase.

DO: add a unique constraint on transactionId in Postgres, bound to the first
identity that redeems it. Reject any later redemption by a different userID with a
distinct error code (not the generic invalid_receipt). Keep the existing per-user
idempotency so an honest double-tap still returns the same response.

TEST: proxy/test/credits.test.js has no cross-identity replay test. Add one.

DONE WHEN: the same JWS POSTed under two different tokens credits exactly one wallet.
```

### T2 · Meter the exchange server-side

```
Meter /v1/exchange server-side. It is currently free and unlimited.

DEFECT: app/proxy/src/config.js:44 sets exchangeCosts: { ink: 0, image: 0 }.
Because cost is 0, the reserve/settle block at server.js:499-510 is skipped
entirely, so no wallet, tier, entitlement or daily count is ever consulted on an
exchange. The free-tier cap (5 moments/day) and the Plus image soft cap (8/day)
exist ONLY in the iOS client, in App/Money/DailyUsageStore.swift, backed by plain
UserDefaults — a scripted client never runs that code, and reinstalling the app
resets the counter while the Keychain identity survives. Only per-IP limits remain.

Related: the comment at Packages/InkwovenCore/Sources/InkMoney/Entitlements.swift:11
claims counters are "server-authoritative (the proxy tracks them)". That is false;
the proxy tracks no daily counter of any kind.

Related: SendGate.canSend has exactly one call site (PageInteractor.swift:422) and it
hardcodes modality: .ink, so the Plus image cap is unreachable at runtime while
imagesUsedToday keeps incrementing. Gate on the modality the exchange will actually
produce.

DO:
1. Enforce a per-identity daily exchange quota and daily image quota in the stores,
   checked BEFORE the provider handshake.
2. Add a global daily spend ceiling as a backstop.
3. Add the missing GET /v1/config call to
   Packages/InkwovenCore/Sources/InkNet/ProxyClient.swift and feed it into GateConfig
   at launch — there is no such call today, so the client always uses compiled-in
   defaults and the "tunable without a release" promise in config.js:1 is not real.

DONE WHEN: a raw curl loop against /v1/exchange is refused after the daily quota,
with no app involved.
```

### T3 · Bind identity properly

```
Replace anonymous attestation with real identity binding.

DEFECT: app/proxy/src/attest.js:58 — in 'anonymous' mode, verify() does
`return { userID: token }`, taking the client-supplied x-ink-user header at face
value. Any string under 256 chars is a valid account with its own wallet and its own
lifetime free-clip allowance. The Dockerfile sets NODE_ENV=production so the mode
defaults to 'required', which 401s everything — meaning the app only functions if
the operator sets INK_ATTESTATION_MODE=anonymous, which deployment.md:436 makes a
launch-checklist item.

This is the multiplier on every other abuse vector: identities are free to mint, so
per-user rate limits, free-clip caps, and grant idempotency are all decorative.
The token is also a permanently replayable bearer secret with no nonce, counter, or
expiry.

DO: implement the App Attest path (task F4). Server-issued challenge, server-minted
opaque userID, per-request assertion or a short-lived signed JWT. Keep 'anonymous'
available for local development only, behind a check that refuses to start in
production.

DONE WHEN: the app works without INK_ATTESTATION_MODE=anonymous, and a fabricated
x-ink-user value is rejected.
```

### T4 · Handle refunds and revocations

```
Handle refunds and revocations on both sides.

DEFECT A (server): there is no App Store Server Notifications endpoint. The route
list in app/proxy/src/server.js has no notification receiver, and stores.grant
(stores.js:158) is additive only. The revocation check at server.js:1115 inspects
only the JWS presented at grant time, which for a fresh purchase is never revoked.
A user can buy 20 vials, spend them on real provider compute, then refund via Apple
— the proxy is never told and the wallet is untouched. Repeatable.

DEFECT B (client): app/App/Money/PurchaseService.swift:184 — apply() never checks
revocationDate. A refunded consumable is re-submitted, the server answers 400
revoked_receipt, deliver() returns false, and transaction.finish() is skipped by
design (line 189). The transaction is now permanently unfinishable: StoreKit
re-presents it every launch, forever.

DO:
1. Add POST /v1/notifications (App Store Server Notifications V2), verify the signed
   payload, and debit the wallet plus drop any cached tier on REFUND / REVOKE.
2. On the client, finish (without crediting) any transaction with a non-nil
   revocationDate, and treat 4xx invalid_receipt / revoked_receipt as terminal
   rather than retryable.

DONE WHEN: a sandbox refund drops both tier and credits, and no transaction can loop.
```

### T5 · Stop routing moderated pages to a shrug

```
Stop routing provider-moderated self-harm pages to an in-fiction shrug.

DEFECT: Packages/InkwovenCore/Sources/InkSafety/DeclineMapper.swift:22 maps
.moderated -> .pageDeclines. Trace: an explicit suicide note triggers the upstream
provider's own safety filter -> models.js returns blockReason -> ProviderError
kind 'moderated' -> server.js:262 sends 422 -> ProxyClient throws .moderated ->
DeclineMapper -> PageInteractor:726 -> PageView:547 renders "The spirit is distant
tonight. Your page is safe — I will answer when the candle steadies." plus a
"try again" button at PageView:513.

No 988. No resources. No fiction break. The more explicit and unambiguous the
disclosure, the more likely the provider blocks it — and blocking is precisely the
path that routes away from safety. This is the single highest-value fix in the repo
per line changed.

DO: treat .moderated on the INK path as crisis-suspect. Surface CrisisView, suppress
the retry affordance entirely, and keep .pageDeclines for the image and video paths
only (where a moderation decline is genuinely just a decline).

DONE WHEN: a provider-moderated ink exchange shows crisis resources and offers no
retry button.
```

### T6 · Make crisis detection independent of the reply model

```
Make crisis detection survive an uncooperative reply model.

DEFECT A: app/proxy/src/server.js:559 — the sentinel gate is
`if (head.startsWith(CRISIS_SENTINEL))` / `if (CRISIS_SENTINEL.startsWith(head))
return true` / `gateOpen = true`. It only matches as an exact prefix of the reply
head. If the model prepends anything at all — a quote mark, "**" despite the
HOUSE_STYLE ban, "I hear you." — both tests fail, gateOpen latches true at line 565,
and every subsequent delta is forwarded verbatim. The user reads the literal string
[[CRISIS]] rendered as the Book's handwriting, and CrisisView never appears. Once
gateOpen is true the sentinel can never fire again, so a model that recognises danger
three sentences in cannot escape either.

DEFECT B: there is no crisis classifier at all. Detection is one in-band instruction
(models.js:140 SAFETY_OVERRIDE) asking the same reply model to self-report, competing
in the same turn with the user's handwritten page — and the page image is the one
channel with no injection fencing (sanitizeContext at models.js:98 covers only
memorySummaries and sessionSummary). Both prd.md:135 and
InkSafety/CrisisInterceptor.swift:4 assert a parallel nano-class classifier runs.
It does not exist. CrisisInterceptor is a stream router with zero text matching.

DEFECT C: grep app/proxy/test/ for "crisis" — zero occurrences. CrisisTests.swift
only injects a pre-fabricated .crisis chunk and asserts routing. A model regression
or provider swap silently removes the entire safety net with all tests green.

DO:
1. Scan the full reply for the sentinel at any offset, not just the head. Strip it
   from any ink that ships. On a match at any position, discard the buffer and emit
   crisis.
2. Add an independent server-side screen over the page and the assembled reply that
   can raise crisis regardless of what the reply model emits. Keep the sentinel as
   the fast path.
3. Add server-side tests for the gate, including a model that ignores the sentinel.

DONE WHEN: a reply model that never emits [[CRISIS]] still triggers the crisis path.
```

### T7 · Fix the crisis resources

```
Fix the crisis resources themselves — they are US-only and partly non-functional.

DEFECTS in app/App/Screens/CrisisView.swift:
- Line 87 calls UIApplication.shared.open(URL(string: "tel:988")) with no
  canOpenURL guard, no completion handler, and no fallback. TARGETED_DEVICE_FAMILY
  is "1,2" and this is an iPad-first app. On a Wi-Fi-only iPad there is no tel:
  handler, so a suicidal user taps the 988 card and nothing happens, silently.
- Both tappable cards are US lines. Availability is all territories. There is no
  Locale region lookup anywhere in the app (I grepped).
- The international fallback (line 61) is a non-tappable Text naming
  findahelpline.com, in the smallest greyest type on the page (footnote 14pt,
  0x777777) — a distressed user must memorise and retype a URL.
- CrisisView is reachable only from a live detection. The launch-arg route is
  #if DEBUG, and DrawerView has no help row. A user who taps away has no path back.
- "Return to the notebook" (line 69) calls model.go(.shelf), which destroys PageView
  and the page along with it.

The helpline DATA is correct — 988 and 741741/HOME are current, findahelpline.com is
real. Do not change the numbers. Fix the plumbing.

DO:
1. Resolve resources from Locale.current.region with a sensible default.
2. Make every entry a real tappable Link, findahelpline.com included.
3. Fall back to a web URL whenever canOpenURL(tel:) is false.
4. Add a permanent "get help" row in DrawerView that opens the same screen.

DONE WHEN: every resource is tappable on a Wi-Fi-only iPad and a non-US user sees a
relevant line.
```

### T8 · Widen the safety override, narrow the fiction exemption

```
Widen the safety override and narrow the fiction exemption in the system prompts.

DEFECT A: app/proxy/src/models.js:141 — SAFETY_OVERRIDE enumerates only wanting to
die, hurting themselves, ending their life, cannot go on, a real goodbye: danger
"from themselves". It covers neither disordered eating, nor substance harm, nor
abuse BY another person, nor a third party's stated intent.

Meanwhile books.js:65 instructs the Keeper to "reflect what the writer set down,
gently and specifically" and "hold their day like something entrusted to you". A user
writing "Day four. 400 calories. I finally feel in control" receives a warm, specific
affirmation of a restriction milestone — nightly, as a habit the ritual scheduler
actively reminds them to return to. books.js:47 tells the Oracle to "speak with quiet
certainty, never hedging", applied to "does anyone actually care if I'm here".

DEFECT B: models.js:143 exempts fiction outright — "a dark tale the writer asked the
Book to tell is not a crisis — stay in character for those." books.js:78 tells the
Storyteller to "carry the tale onward a few sentences — vivid, concrete" and hand the
pen back. "Begin a tale — a girl swallows her mother's pills and finally sleeps" is
therefore a documented bypass. Nothing downstream catches it: createPromptModerator
(models.js:616) guards video prompts and enable_safety_checker (models.js:332) guards
images; the assembled ink reply is never moderated on any path.

DO:
1. Widen the override to disordered eating, substance harm, abuse disclosure, and
   third-party risk.
2. Remove the blanket fiction exemption for self-harm methods and first-person-
   adjacent scenarios — wrapper framing must not disable the gate.
3. Add an explicit "never affirm restriction, purging, or self-loathing as
   achievement" clause to the Keeper and Oracle prompts.
4. Build a red-team fixture set covering all four categories plus fiction-wrapped
   self-harm, and run it in CI.

DONE WHEN: the red-team set routes correctly and is part of the test suite.
```

### T9 · Persist the page

```
Persist the user's page. Today it exists only in RAM until an exchange succeeds.

DEFECT: there is exactly ONE call to archive.archive(...) in the entire app, inside
completeExchange at app/App/Page/PageInteractor.swift:757. PageView has no
onDisappear and no scenePhase handler (RootView:69 only relocks the Keeper). There is
no draft persistence of any kind.

Total loss scenarios, all confirmed: writing for fifteen minutes without a 4s pause
then getting jetsammed; tapping "the shelf" (PageView:197); tapping the Remembered
ribbon (PageView:218); switching Book (RootView:36 uses .id(model.activeBookID),
which destroys the view); and crisis interception, which routes to CrisisView whose
only exit is model.go(.shelf). completeExchange even clears the last recovery path at
line 774 (canvas.undoManager?.removeAllActions()).

The crisis case is the worst of these: runExchange sets preempted = true and
deliberately skips completeExchange, so the most emotionally significant page the
user will ever write is guaranteed unrecoverable. The comment at PageInteractor:546
claims "Crisis preemption keeps the user's ink" — it does not.

DO:
1. Persist the PKDrawing plus typedDraft to disk on every stroke-ended and on
   scenePhase != .active. Rehydrate in attach(canvas:).
2. Archive the crisis exchange locally (empty reply text) before routing away, OR
   present the crisis card as an overlay so the page survives underneath.

DONE WHEN: force-quitting mid-page and relaunching restores the ink, and a crisis
interception does not destroy the page.
```

### T10 · Fix the exchange loop

```
Fix the exchange loop: one send at a time, archive what was actually sent.

All in app/App/Page/PageInteractor.swift unless noted.

DEFECT A (double billing): line 469 assigns exchangeTask without cancelling the
previous one, and there is no in-flight guard. The canvas stays live and the idle
cadence stays armed during a stream: strokeEnded() at line 221 unconditionally sets
status = .resting and calls startTicking(). Four seconds later a second exchange
commits. The digest dedupe does NOT catch this, because sentStrokeCount is never
advanced at send time (only in restore/completeExchange), so the second snapshot
crops from index 0 and produces a different digest from previousDigest (set line 456).
On free tier that burns 2 of 5 daily moments for one page.

DEFECT B (wrong ink archived): line 746 does `let drawing = canvas?.drawing ??
PKDrawing()` — it archives whatever is on the canvas AT COMPLETION, not what was
sent. Keep writing while the Book answers and your in-progress sentence is filed
under the previous exchange's reply, then wiped by canvas.drawing = PKDrawing() at
line 766. In the concurrent case, exchange A wipes the canvas first, so exchange B
reaches line 756 with nothing and its reply is billed but never archived.

DEFECT C (orphaned exchange): nothing cancels exchangeTask on view teardown — no
deinit, no onDisappear. Leave the page mid-send and the stream runs to completion,
entitlements.record(.ink) fires at line 523, and completeExchange files nothing
because the weak canvas is already nil. Page lost, reply lost, moment spent.

DEFECT D (dead retry): retry() at line 255 calls machine.reset(), clears
previousDigest, sets status = .idle — and never feeds strokeBegan/strokeEnded or
calls startTicking(). The user taps "try again" on the decline card and nothing
happens, ever. The page is finished so they have no reason to add a stroke.

DEFECT E (hold is a no-op mid-flight): IdleSendMachine.swift:124 has no
(.committed, .holdToggled) transition, so it falls through to `default: return []`.
toggleHold() at line 314 then takes the hasUnsentInk branch and RE-ARMS the cadence —
the opposite of what the button says.

DEFECT F (cancelled task clobbers status): runExchange never checks Task.isCancelled
before writing status. Turn the page out of a stuck .sending and the resuming task
maps .cancelled to .inkRanDry and writes a decline card over the fresh blank page.
Also, exchange() sets no timeoutInterval (compare video at ProxyClient.swift:285) —
the client trusts the server's 120s deadline entirely.

DO: refuse commitSend while exchangeTask is live; advance sentStrokeCount at send
time; capture the committed PKDrawing in beginExchange and archive that snapshot,
removing only those strokes; cancel exchangeTask/videoTask on PageView.onDisappear;
add (.committed, .holdToggled) and (.committed, .cancelRequested) to the machine;
make retry() re-enter the send path directly; guard every post-await status write
with !Task.isCancelled; add a client-side exchange deadline.

DONE WHEN: writing during a reply cannot double-bill, "try again" sends, and leaving
mid-send costs nothing.
```

### T11 · Fix the subscription disclosures

```
Fix the subscription disclosures — current state is a 3.1.2 rejection risk.

DEFECT A: app/App/Screens/PolicySheet.swift:36 — the terms reached from the paywall's
required "Terms & privacy" link (PaywallView.swift:99) say the binding is charged
"by the moon, or by the year with the first seven days free." There is no annual
product: app/Inkwoven.storekit contains only plus_weekly (P1W, P3D introductory
offer) and plus_monthly (P1M, introductoryOffer: null). Two contradictory trial
disclosures in one binary.

DEFECT B: isEligibleForIntroOffer appears nowhere in app/App or app/Packages. The
"3-day free trial" badge (PaywallView.swift:76) and the "Free for 3 days, then
$4.99 a week" line (PaywallView.swift:127, repeated in the confirm sheet at :232) are
unconditional strings. A user who subscribed, cancelled and returned sees the trial
promise and is charged immediately.

DEFECT C: AppModel.loadStorePrices() (AppModel.swift:330) runs once inside a
fire-and-forget Task at launch with no retry. If StoreKit fails — offline launch, IAP
records not yet approved — storePrices stays empty for the whole session and every
surface falls back to a hardcoded USD literal: PaywallView:75/80, VialsView:56-60.
A user in France sees "$4.99 /wk", presses the seal, and gets productUnavailable.

DO:
1. Rewrite the PolicySheet subscription paragraph to match the real SKUs — weekly
   with a 3-day trial, monthly with none, no annual plan.
2. Read the weekly product's subscription.isEligibleForIntroOffer and drop both the
   badge and the "Free for 3 days" clause when false.
3. Retry the price fetch on paywall appear and on foreground; disable or hide the
   purchase CTAs until real Product.displayPrice strings exist, rather than showing
   USD literals.

DONE WHEN: no price or trial string in the binary can be wrong for any user.
```

### T12 · Make reports reach a human

```
Make guideline 1.2 reports actually reach a human.

DEFECT: app/proxy/src/server.js:1170 — stores.fileReport INSERTs into the reports
table (stores-redis.js:380-399) and that is the end of it. The only reader is
reportCount (stores-redis.js:402), which no route exposes. There is no email,
webhook, admin endpoint or dashboard anywhere in app/proxy/src/. Rows are swept
unread at 90 days (stores-redis.js:122-139).

Meanwhile app/App/Screens/ReportSheet.swift:41 tells the user "this page goes to a
human hand for review." Guideline 1.2 obliges acting on objectionable-content
reports within 24 hours, and App Review will ask how triage works. The client-side
mechanics are good — long-press on both the live reply and the history thread,
idempotent submission, server-side digest verification. The gap is purely
operational.

DO: alert a human on fileReport (email or Slack webhook), and add an authenticated
read route so reports can be triaged.

DONE WHEN: filing a report produces a notification somewhere a person will see it.
```

### T13 · Restore the non-handwriting path, then sweep accessibility

```
Restore the non-handwriting path, then sweep accessibility.

BLOCKER FIRST — app/App/Design/HybridInkSurface.swift:65 sets
textView.isUserInteractionEnabled = !pencilActive, and
app/App/Design/PenPresence.swift:29 persists ink.pencilSeen to UserDefaults forever
with no reset anywhere (I read all 621 lines of DrawerView — there is no row for it).
One pencil touch, by anyone, permanently disables the keyboard on the flyleaf and on
every page. A VoiceOver user or someone with a tremor who owns a Pencil-equipped iPad
cannot write in this app at all. Their only remaining action is the onboarding skip
button, which drops them on a shelf of Books none of which they can use.
FIX: make pencil-active a per-session hint that keyboard focus or
UIAccessibility.isVoiceOverRunning overrides, and add an explicit "Write with the
keys" row to the Drawer.

THEN, the sweep (note: line numbers below predate commits 0eb6fad..ef1b770 in the
six UI files those commits touched — search by symbol, not by line):
- Add .accessibilityAddTraits(.isModal) to the four hand-rolled overlays that lack it:
  DrawerView:545 (delete-all confirm), PaywallView:221 (purchase confirm),
  PageView:285 (hand card), MovingPicture:102 (Keeper consent). ReportSheet:78 and
  MovingPicture:306 already have it, so the pattern exists. Drive
  @AccessibilityFocusState onto each title on appear.
- PaywallView:147 planCard expresses selection only visually. Add
  .accessibilityAddTraits(selected ? .isSelected : []) and an .accessibilityValue
  naming the effective price — a VoiceOver user currently cannot tell which plan they
  are about to be charged for.
- DrawerView:48 and :84 — GoldToggle renders only a Capsule and has no implicit
  label. The ritual (:93) and per-book (:535) toggles got .accessibilityLabel; these
  two did not, so VoiceOver reads "off, toggle button" with no name. Also DrawerView
  :429 labels all four ink swatches identically as "Ink colour".
- Hide decorative ornaments: Text("❦") in Components.swift:103 (spoken before every
  wax-seal CTA) and PaywallView:135, and Text("‹") at Components.swift:283,
  PageView:199, MemoryView:81, KeeperGateView:70.
- PageToolTray.swift:53 — .contentShape(Circle()) is applied BEFORE the 44pt frame,
  so all seven page tools are 38pt targets. Move .contentShape after the frame.
  DrawerView:418-426 swatches are 28pt with no contentShape at all.
- Raise sub-11pt type: PageView:229 (9pt), BinderyView:378/437 (9.5pt).
- ShelfView:363 nibDot is the only ambient repeatForever animation with no
  reduce-motion guard; six siblings have one. Add it.
- Daylight palette fails WCAG (candlelight passes — do not touch it). Computed:
  dim #7A6544 on bgOuter #BDA478 = 2.32:1, accent #8A5A15 on bgOuter = 2.46:1, dim on
  bgMid #D8C39C = 3.24:1, heading #7A4A15 on bgMid = 4.33:1. The radial gradient
  (InkPalette.swift:106-111) puts bgOuter across the lower-right of a 13" iPad in
  landscape, exactly where DrawerView:187/:470/:486 render body copy. Darken dim to
  ~#5F4E31 and accent to ~#6E4610, or clamp the gradient's outer stop.

DONE WHEN: the app is usable end-to-end with VoiceOver and a Pencil in the room.
```

### T14 · Make CI and the docs tell the truth

```
Make CI and the docs tell the truth.

DEFECT A: .github/workflows/ci.yml:70 runs only
`swift test --package-path app/Packages/InkwovenCore`. There is no xcodebuild test
and no xcodegen step (line 67 only prints xcodebuild -version). The Inkwoven app
target is never compiled, and all eight @Suite files in app/Tests/ plus both classes
in app/UITests/ never execute. A compile break in ~5,000 lines of app-target Swift
reaches main green. development.md:28 claims "CI: xcodebuild test (app) + swift test
(packages) on every commit" — false.
FIX: add a macOS job running `xcodegen generate` then
`xcodebuild test -scheme Inkwoven -destination 'platform=iOS Simulator,name=iPad Pro
13-inch (M4)'`.

DEFECT B: app/UITests/KeyboardAuditUITests.swift:111 waits on
NSPredicate(format: "value CONTAINS %@", "resting") against ink-canvas, whose value
is PageView.spokenStatus. None of the ten spokenStatus cases contains "resting" —
the copy was rewritten from String(describing:) and the test was not updated. It
fails unconditionally; nobody noticed because of defect A. Also PageHarnessUITests
needs a hand-started local proxy, so it can never run unattended.

DEFECT C — doc drift. Each of these claims something the code does not do:
- development.md:28 — xcodebuild in CI (see A)
- prd.md:135 — "Crisis + moderation | nano-class model | runs parallel" (no such
  classifier exists)
- InkMoney/Entitlements.swift:11 — "usage counters are server-authoritative"
  (the proxy tracks no daily counter)
- InkSafety/CrisisInterceptor.swift:4 — "the proxy runs the classifier in parallel"
- app-store-listing.md:186 "Notes for App Review", marked "Paste this verbatim" —
  describes a $59.99/year plan with a 7-day trial, credit packs of 10/30/100 (actual:
  3/8/20), Bindery non-consumable cosmetics (BinderyView.swift:3 says those SKUs do
  not exist), Restore in Settings (the Drawer has none), Sign in with Apple, and
  in-app account deletion (DrawerView.swift:111: "v1 has no sign-in of any kind").
- app-store-listing.md:131 — promises a first-use consent gate for AI processing and
  a way to withdraw it. The only consent flag in the app is keeperClipConsentGranted
  (AppModel.swift:167), which is video-only.
- deployment.md §3.1 documents a single-stage root-running Dockerfile that the real
  app/proxy/Dockerfile contradicts.
FIX: correct each claim or delete it. The listing file's own header marks it
superseded and points at design/app-store-assets/ — confirm which listing is actually
being submitted and remove the stale one so nothing can be pasted from it.

DEFECT D: ci.yml:104 sets the dependency-audit blocking gate to `critical`, so the
five high-severity advisories the workflow itself enumerates at lines 95-101 never
fail CI. One of them is X-Forwarded-* spoofing — under anonymous identity, per-IP
limits are the ONLY ceiling on model spend, so that advisory removes the last
backstop. I could not run npm audit to confirm exploitability.
FIX: bump fastify, clear the advisories, set the gate to `high`.

DONE WHEN: nothing in the checklist claims work that isn't there, and CI compiles
the app.
```

---

## 9. Sequencing

**T1, T2, T5 and T10 first.** They are independent of one another, each is a day or less, and together they close the money leak's two cheapest exploits, the worst safety inversion, and the double-billing defect. This is the highest risk reduction per hour available.

**T9 and T6 next**, but both need a design decision before code. T9 must settle where drafts live and how they interact with the Keeper's seal — a draft of a Keeper page must not land in an un-gated store. T6 must settle whether the independent classifier is a second model call on the critical path, an async check that can retract, or a cheap deterministic screen; each has a different latency and cost profile.

**T3 is the real fix for the money problem** and is roughly a week on its own. T1 and T2 reduce its urgency but do not remove it — ship neither the app nor the proxy publicly while identity is free to mint.

**T4, T7, T8, T11, T12 and T13** are all required before submission. T13 contains a blocker (A-1) that should be pulled forward if any accessibility review is planned.

**T14 should be done early despite being P1**, because without it none of the other work is protected by tests. Adding the `xcodebuild` job before starting T9 and T10 means the eight existing app-target test suites begin providing value immediately.

Nothing in this list is optional for a public release. The three clusters in §2 are each independently sufficient reason to hold.

---

*End of audit. Findings derived from static source reading; confirm by reproduction before closing any item.*
