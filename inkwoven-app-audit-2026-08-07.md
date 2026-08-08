# Inkwoven — App-Side Audit

**Date:** 2026-08-07
**Auditor:** Claude (Cowork)
**Baseline:** commit `bd34045` ("feat(auth): the app is entitled to attest"), clean tree
**Scope:** the app side only — the Swift app target (`app/App`), the `InkwovenCore` packages, and `Inkwoven.storekit`. The proxy (`app/proxy`) was not audited; where the app depends on server behavior in a fragile way, that dependency is noted.
**Build state:** the app target compiles clean for the iPad simulator (`xcodebuild build`, exit 0) at baseline.

**Verdict: no blockers.** The core loop's happy path, the StoreKit 2 machinery, the Keeper's privacy discipline, and the crisis routing are all correct and verifiably better than the 2026-08-04 audit found them. What remains clusters in three places: **quiet data-loss edges around the exchange lifecycle** (three HIGHs, all with small local fixes), **copy that makes promises the app can't keep** (prices, gifted credits, dead settings), and **a daylight-theme/accessibility debt** on the newer surfaces. Fix the eleven HIGHs and this is a shippable v1.

> **Remediation, 2026-08-08:** every finding now carries a Status. All 11 HIGHs and 21 of 22 MEDIUMs are **fixed** (commits `c16c46e`, `d66be51`, `8a14b3c`, `698654e`, `5b42729`, `5261454`, `d10eb27`, `cd4aa22`); P-1 is fixed in its launch-adjacent halves' companions but its structural core is **deferred** (see §13). Four LOWs are **accepted** by design, one **deferred**; the other 33 are fixed. Verification: clean build, 136/136 package tests, full app unit bundle green, and a simulator pass over onboarding → shelf → drawer. Details in §13.

---

## 1. Method

Six independent read-only passes over the app side, each reading its files end to end: (1) lifecycle, launch, onboarding, ritual; (2) the core page/exchange loop and streaming pipeline; (3) money and IAP; (4) books, shelf, drawer, and the hidden-feature inventory; (5) safety, crisis, privacy, security; (6) design system, accessibility, performance. Every prior-audit finding touching the app side was re-verified against source rather than trusted from commit messages. Findings reported by two passes independently are marked ×2.

## 2. Prior-audit closure scorecard

Of the 2026-08-04 findings that live app-side, the following are **verified closed** in source:

| Prior ID | Status | Evidence |
|---|---|---|
| D-1 drafts | ✔ closed | `PageDraftStore` wired on stroke/keystroke coalesce, scene-phase, teardown, crisis rollback, rehydrate ([PageInteractor.swift:324](app/App/Page/PageInteractor.swift:324), [PageView.swift:194](app/App/Screens/PageView.swift:194)) — two new edges: L‑1, L‑2 below |
| D-2 concurrent exchanges | ✔ closed | `exchangeInFlight` guard + generation tokens ([PageInteractor.swift:545](app/App/Page/PageInteractor.swift:545), :658) |
| D-3 wrong strokes archived | ✔ closed | `sentDrawing` frozen at commit ([PageInteractor.swift:604](app/App/Page/PageInteractor.swift:604)) — mid-stream-erase edge remains (L‑6) |
| D-4 no teardown cancel | ✔ closed | `pageWillDisappear()` cancels everything ([PageInteractor.swift:787](app/App/Page/PageInteractor.swift:787)) — accounting hole remains (L‑1) |
| D-5 crisis destroys page | ✔ closed | rollback + draft flush before navigation ([PageInteractor.swift:731](app/App/Page/PageInteractor.swift:731)) |
| D-6 inert retry | ✔ closed | digest cleared, real re-commit ([PageInteractor.swift:382](app/App/Page/PageInteractor.swift:382)) |
| D-7 all-or-nothing JSON | ✔ closed for corruption | element-wise salvage + quarantine ([PageArchive.swift:226](app/App/Page/PageArchive.swift:226)); scalability liability remains (P‑1) |
| D-8 no timeout / status clobber | ✔ closed | 150s idle deadline ([ProxyClient.swift:284](app/Packages/InkwovenCore/Sources/InkNet/ProxyClient.swift:284)), generation guard |
| D-9 hold mid-flight | ✔ closed in the machine ([IdleSendMachine.swift:125](app/Packages/InkwovenCore/Sources/InkCore/IdleSendMachine.swift:125)) — the shell defeats it at resolution (M‑1) |
| D-10 offline queue promise | ✔ substantially closed | drafts real, copy softened; banner still overpromises (L‑9) |
| M-4 refunds/revocations | ✔ closed | `Transaction.updates` armed pre-reconcile, revoked finished, terminal-vs-transient delivery split, idempotency key ([PurchaseService.swift:128](app/App/Money/PurchaseService.swift:128), :229) |
| M-5 image cap unreachable | ✔ closed | modality derived from `Book.develops` ([PageInteractor.swift:579](app/App/Page/PageInteractor.swift:579)) |
| C-1/C-2/C-3 disclosures, intro, prices | ✔ closed | PolicySheet matches the storekit config; `isEligibleForIntroOffer` gates trial copy; all prices are `displayPrice` — one literal escaped the sweep (H‑4), one more in MovingPicture (H‑5) |
| S-1 moderated → "try again" | ✔ closed | `.moderated` on ink routes to `.crisisSuspect` → CrisisView, no retry ([DeclineMapper.swift:39](app/Packages/InkwovenCore/Sources/InkSafety/DeclineMapper.swift:39)) |
| S-5 tel:988 unguarded / US-only | ✔ closed | `canOpenURL`-gated with web fallback, region-aware lines (US/CA/GB/IE/AU/NZ + directory), numbers correct as of 2026 ([CrisisView.swift:86](app/App/Screens/CrisisView.swift:86)) |
| S-8 crisis one-way door | ✔ closed | standing Drawer entry + "Return to the notebook" exit ([DrawerView.swift:217](app/App/Screens/DrawerView.swift:217)) |
| C-5/C-6/C-7 privacy manifest, export residue, Keeper leak | ✔ closed | manifest matches actual collection; exports purged on dismiss/delete-all (launch-purge gap: L‑12); stray-Keeper sweep on every launch ([PageArchive.swift:321](app/App/Page/PageArchive.swift:321)) |
| A-1 pencil latch | ✔ closed as designed — session-only, VoiceOver + Drawer overrides ([PenPresence.swift:49](app/App/Design/PenPresence.swift:49)); **upgrade residue reopens it** (M‑12, ×2) |
| A-2 paywall selection | ✔ closed | `.isSelected` + spoken price ([PaywallView.swift:218](app/App/Screens/PaywallView.swift:218)) |
| A-3 modals | ◐ partial | six modals fixed; three newer ones missed (H‑7, ×2) |
| A-4 hit targets | ◐ partial | tray + swatches fixed; pattern not swept app-wide (M‑16) |
| A-5 contrast | ✔ palette verified independently (daylight worst pair 4.87:1) — hardcoded hexes that bypass the palette fail badly (H‑6) |
| A-6/A-7/A-8 | ✔ closed | two ornament leftovers (L‑16) |
| M-6 free cap in UserDefaults | ◐ acceptable | still client-side and reinstall-resettable; clock-back guarded, proxy quota is the real ceiling; `reconcile(with:)` has no caller |
| M-7 device-bound wallet | ✘ not closed on disclosure | see M‑8 |

## 3. Findings index

| ID | Sev | Area | Summary | Status |
|---|---|---|---|---|
| H‑1 | HIGH | Core loop | Teardown/backgrounding mid-exchange strands the page as "sent," permanently inert | ✔ Fixed `c16c46e` |
| H‑2 | HIGH | Core loop | Revisiting a remembered page silently destroys the standing unsent draft | ✔ Fixed `c16c46e` |
| H‑3 | HIGH | Core loop | "Turn the page" files the previous reply against ink it never answered (×2) | ✔ Fixed `c16c46e` |
| H‑4 | HIGH | Money | "save 54% · best" is a hardcoded literal beside storefront-localized prices | ✔ Fixed `5261454` — computed from live `Product.price` |
| H‑5 | HIGH | Money | Hardcoded "$4.99" in the moving-picture offer line | ✔ Fixed `c16c46e` |
| H‑6 | HIGH | Design | Daylight theme: modal body/button text at 1.7–2.1:1 contrast | ✔ Fixed `8a14b3c` — `room.text` everywhere |
| H‑7 | HIGH | A11y | VialsSheet, PolicySheet, PurchaseNoteOverlay lack `.isModal` (×2) | ✔ Fixed `8a14b3c` |
| H‑8 | HIGH | Design | iPhone is a shipping device family with zero compact-layout adaptation | ✔ Fixed `8a14b3c` — **iPad-only for v1** (decision, reversible; see §13) |
| H‑9 | HIGH | Perf | Clip cache keyed on per-launch-randomized `hashValue` — never hits, leaks files (×2) | ✔ Fixed `c16c46e` — SHA-256 keys |
| H‑10 | HIGH | Settings | Drawer "Reply length" is a dead control — nothing reads it | ✔ Fixed `5261454` — removed for v1 (tasks H3 is its future home) |
| H‑11 | HIGH | Onboarding | First-run promises a gifted vial that no longer exists (×2) | ✔ Fixed `d66be51` — verified on-screen |
| M‑1 | MED | Core loop | Hold engaged mid-exchange silently releases when the exchange resolves | ✔ Fixed `c16c46e` |
| M‑2 | MED | Core loop | Ink written while the Book answers never auto-sends | ✔ Fixed `c16c46e` |
| M‑3 | MED | Core loop | Writing during the answer happens on an 18%-opacity canvas | ✔ Fixed `c16c46e` |
| M‑4 | MED | Core loop | Undo/redo bypass the send machine (stale speculation; stuck settle dots) | ✔ Fixed `c16c46e` |
| M‑5 | MED | Core loop | Mixed keyboard+pencil pages absorb ink the Book never saw | ✔ Fixed `c16c46e` |
| M‑6 | MED | Money | Cooldown card upsells Plus to users who already have Plus | ✔ Fixed `5261454` — wait surfaced, honest 429 copy |
| M‑7 | MED | Money | "Restore a binding" ends in silence when there's nothing to restore | ✔ Fixed `5261454` — endings split by cause |
| M‑8 | MED | Money | Device-bound vials never disclosed (prior M-7) | ✔ Fixed `5261454` — PolicySheet + shop |
| M‑9 | MED | Safety | App Attest: a locally invalid key has no recovery path short of reinstall | ✔ Fixed `d10eb27` — `.invalidKey` heals via re-attest |
| M‑10 | MED | Privacy | Keeper never reseals on route-away; unlock is foreground-session-long | ✔ Fixed `d10eb27` — seal follows the visit |
| M‑11 | MED | Lifecycle | `ritualAsked` latches before the permission dialog resolves — toggle can go dead | ✔ Fixed `d66be51` |
| M‑12 | MED | Lifecycle | Legacy persisted `ink.pencilSeen` re-latches A-1 for upgraders (×2) | ✔ Fixed `d66be51` — scrubbed at startup |
| M‑13 | MED | Privacy | Delete-all leaves moving-picture clips on disk — including Keeper-derived ones | ✔ Fixed `c16c46e`+`5261454`+`d10eb27` — purge API, delete-all wiring, sealed clips die with the seal |
| M‑14 | MED | Video | Failed clip download renders as a silent black rectangle (×2) | ✔ Fixed `c16c46e`+`5b42729` — in-fiction line, honest caption/label |
| M‑15 | MED | A11y | GoldToggle's real hit target is 50×29pt — every Drawer toggle | ✔ Fixed `8a14b3c` |
| M‑16 | MED | A11y | Sub-44pt targets across nav pills, segments, onboarding, Bindery, Memory | ✔ Fixed `8a14b3c`+`d66be51`+`5b42729` — full sweep incl. PageView back pill |
| M‑17 | MED | A11y | KeeperGate refusal line 2.48:1; shelf "resting" label 2.83:1; paywall small print 3.65:1 | ✔ Fixed `d66be51`+`8a14b3c` — all recomputed ≥4.5:1 |
| M‑18 | MED | A11y | VoiceOver override in `pencilPreferred` is not reactive mid-session | ✔ Fixed `d66be51` |
| M‑19 | MED | Design | Keyboard can cover the flyleaf signature/typed field | ✔ Fixed `d66be51` |
| M‑20 | MED | Copy | Paywall benefit "Pictures develop freely, page after page" is false for 7 of 8 Books | ✔ Fixed `8a14b3c` |
| M‑21 | MED | Shelf | Hiding the focused book leaves a stale "tap again to open" caption | ✔ Fixed `8a14b3c` |
| P‑1 | MED | Perf | Archive scalability: whole journal decoded sync on main before first frame, resident forever, rewritten whole per exchange (×3) | ▸ **Deferred** — structural per-entry-store rework, tracked as its own task (§13); bounded at v1 volumes |

Lows are grouped in §6, each carrying its status inline.

## 4. HIGH findings in detail

### H‑1 · Mid-exchange teardown strands the page as "sent"
[PageInteractor.swift:608](app/App/Page/PageInteractor.swift:608), :345, :788 — `beginExchange` advances `sentStrokeCount` to the full count; `saveDraftNow` persists that accounting, and both teardown (save runs *before* the cancel; the cancelled task's `isCurrent()` guard skips `rollbackSend`) and the scene-phase save can write the draft while the exchange is in flight. **Scenario:** the user rests, the Book starts answering, the user taps "the shelf" (or backgrounds and is jetsammed). On return the ink rehydrates fully accounted — `hasUnsentInk` is false, the cadence never arms, retry is unreachable. Visible ink, never answered, never archived, permanently inert. **Fix:** in `saveDraftNow`, persist `exchangeInFlight ? sentBase : sentStrokeCount` so an unresolved exchange's ink always rehydrates as unsent.

### H‑2 · Revisit destroys the standing unsent draft
[PageView.swift:238](app/App/Screens/PageView.swift:238), [PageInteractor.swift:235](app/App/Page/PageInteractor.swift:235), :255–270 — `consumeRevisit` fires unconditionally on appear; `revisit` clears `typedDraft`, `restore` replaces the canvas with the archived drawing and then `saveDraftNow` overwrites the draft file with the revisited page, fully accounted. **Scenario:** half a page unsent → wander into Remembered → tap an old card to reread → the unsent ink and typed text are gone, no warning, no archive copy. **Fix:** preserve or archive a non-empty draft before restoring (or show only the reply side when unsent work stands).

### H‑3 · "Turn the page" mispairs old replies with new ink (×2)
[PageInteractor.swift:477](app/App/Page/PageInteractor.swift:477)–498 → :996–1032 — after an exchange, `streamedText` still holds reply R. Fresh unsent ink + Turn Page → `completeExchange` archives `replyText: streamedText` unconditionally: a second entry pairing never-sent ink with the old reply, so R appears twice in Remembered and in exports. The revisit variant archives the *entire restored drawing plus doodle* against the revisited reply (base is 0), duplicating a whole past page. **Fix:** pass the reply into `completeExchange`; `turnPage` passes `""` whenever the standing reply is already filed.

### H‑4 · "save 54% · best" hardcoded on the paywall
[PaywallView.swift:88](app/App/Screens/PaywallView.swift:88) — computed from USD, rendered beside storefront-localized prices. Apple's per-territory tiers don't preserve the USD ratio, so in some storefronts the card states a saving the two displayed prices visibly contradict — a misleading price claim on the purchase screen (3.1.2 risk), same family as the closed C-3. **Fix:** compute from the two fetched `Product.price` decimals, or drop the number.

### H‑5 · "$4.99" literal in the moving-picture offer
[MovingPicture.swift:86](app/App/Screens/MovingPicture.swift:86) — "none left — three from $4.99" renders whenever the purse is empty. Every other surface was purged of USD literals for exactly this reason. **Fix:** drop the price or interpolate `model.storePrices[ProductID.vialsSmall]`.

### H‑6 · Daylight theme: near-invisible modal text
[PurchaseNotes.swift:76](app/App/Design/PurchaseNotes.swift:76), [DrawerView.swift:630](app/App/Screens/DrawerView.swift:630), :641, [PaywallView.swift:281](app/App/Screens/PaywallView.swift:281), :313 — hardcoded candlelight-era hexes (#B8A684 body, #C9B48A secondary buttons) sit on theme-following daylight cards: measured **2.07:1** on cardTop, **1.67:1** on cardBottom, **1.76:1** for "Keep them"/"Not yet". **Scenario:** a daylight user opens "Delete every page?" and cannot read the warning that the ink is unrecoverable. **Fix:** replace four hexes with `room.text`/`room.dim` (≥6.5:1 in daylight, near-identical look in candlelight).

### H‑7 · Three modals still missing `.isModal` (×2)
[VialsView.swift:217](app/App/Screens/VialsView.swift:217)–272 (mid-errand shop over a live page, also no initial focus), [PolicySheet.swift:12](app/App/Screens/PolicySheet.swift:12), [PurchaseNotes.swift:114](app/App/Design/PurchaseNotes.swift:114) (blocking purchase scrim). VoiceOver swipes past the scrim into — and can activate — the live page or paywall behind. The codebase's own A-3 standard is applied on six other modals. **Fix:** `.accessibilityAddTraits(.isModal)` + `@AccessibilityFocusState` landing, matching the delete-confirm pattern.

### H‑8 · iPhone ships with an iPad-only layout
[project.yml:109](app/project.yml:109) sets `TARGETED_DEVICE_FAMILY: "1,2"`, but there is zero size-class/idiom adaptation anywhere (no `horizontalSizeClass`, no `userInterfaceIdiom`). On a 390pt iPhone: PageView's fixed 56pt side insets + 52pt tray padding + a header rail needing ~550pt clips; the shelf squeezes 8 spines into ~28pt columns; Drawer SegmentedPills overflow. **Fix:** either drop to iPad-only for v1 (one line in project.yml) or gate the page header/tray and shelf behind `horizontalSizeClass == .compact` variants. Decide before submission — tasks.md epic I (iPhone adaptive layout) is explicitly unbuilt.

### H‑9 · Clip cache keyed on `String.hashValue` (×2)
[MovingPicture.swift:483](app/App/Screens/MovingPicture.swift:483) — Swift's `hashValue` is seed-randomized per process, so the cache never hits across launches: every relaunch re-downloads every clip (against URLs that expire) and writes a new orphan into `Caches/clips/`, which nothing prunes. **Fix:** key on a stable digest (SHA-256 of the URL string — `SnapshotProcessor.digest` already exists).

### H‑10 · "Reply length" is a dead settings control
[DrawerView.swift:78](app/App/Screens/DrawerView.swift:78)–83 renders Terse/Measured/Full; [AppModel.swift:125](app/App/AppModel.swift:125) persists it — and nothing anywhere reads it. `PageContext` and `ProxyClient.exchange` never see it. A user flips it and every Book answers identically. **Fix:** thread `replyLength` into `PageContext` (and honor it server-side), or remove the row until H3 lands.

### H‑11 · Onboarding promises a gifted vial that no longer exists (×2)
[OnboardingView.swift:312](app/App/Screens/OnboardingView.swift:312)–331 + VoiceOver announcement at :295 — "A first moving-picture credit, gifted. One sealed vial…" But wallets start empty; the server grants **2 lifetime free clips**, which every other surface calls "gifted moments" ([DrawerView.swift:341](app/App/Screens/DrawerView.swift:341), [VialsView.swift:111](app/App/Screens/VialsView.swift:111)). A new user is told they own a vial, then the Drawer shows "Fill the vials." The card is also unconditional client fiction for an entirely server-side grant. **Fix:** reword to the free-clip language ("two gifted moments") or drop the card.

## 5. MEDIUM findings in detail

**M‑1 · Hold silently releases at exchange resolution.** [PageInteractor.swift:761](app/App/Page/PageInteractor.swift:761) — `machine.reset()` unconditionally returns `.held` to `.idle` and status is overwritten with `.answered`; the hold button reads un-pressed and the next rest auto-sends — the exact thing the button promised not to do. Fix: `if machine.state != .held { machine.reset() }`.

**M‑2 · Tail ink never auto-sends.** A rest during a stream is correctly refused ([PageInteractor.swift:550](app/App/Page/PageInteractor.swift:550)), but nothing re-arms at resolution — ink written while the Book answers sits unsent until the writer happens to touch the page. Fix: at resolution, if `hasUnsentInk`, re-feed the machine and `startTicking()`.

**M‑3 · Writing during the answer at 18% opacity.** [PageView.swift:493](app/App/Screens/PageView.swift:493), [PageInteractor.swift:280](app/App/Page/PageInteractor.swift:280) — `canvasAbsorbed` (0.18 + blur) lifts only on a status change, and `strokeBegan` doesn't promote status from `.sending`/`.answering`, so the writer inks near-invisibly for the stream's duration. Fix: lift the veil on `strokeBegan` regardless of status, or make the absorbed canvas non-interactive.

**M‑4 · Undo/redo bypass the send machine.** [PageInteractor.swift:500](app/App/Page/PageInteractor.swift:500) — (a) undo during `.resting`/`.speculating` leaves the speculated payload stale: the commit sends ink the writer just removed while `sentDrawing` archives the post-undo canvas. (b) Undo of the absorb fires `strokeEnded` into `.idle`, which has no transition — settle dots dance forever, nothing sends. Fix: route undo/redo through the machine (cancel pending send, re-arm from the resulting state).

**M‑5 · Mixed-hands pages absorb unseen ink.** [PageInteractor.swift:525](app/App/Page/PageInteractor.swift:525) — when typed text stands, only the typed rendering is sent, yet `completeExchange` archives and absorbs the pencil strokes as part of that exchange. Fix: composite both hands into one snapshot, or leave unsent ink out of the absorb.

**M‑6 · Cooldown card upsells Plus to Plus.** [PageView.swift:653](app/App/Screens/PageView.swift:653), [Entitlements.swift:84](app/Packages/InkwovenCore/Sources/InkMoney/Entitlements.swift:84) — `.cooldown` fires only for `tier == .plus`, yet the CTA is "bind to write without pause" → paywall. The `.cooldown(seconds)` payload is discarded — no countdown shown. Fix: branch the CTA on `model.bound`; surface the wait.

**M‑7 · Restore ends in silence.** [AppModel.swift:585](app/App/AppModel.swift:585) — successful `AppStore.sync()` with no entitlement goes `.purchasing → .idle`: spinner, then nothing. The error copy "No binding was found for this hand." also shows for offline/cancelled auth, where it's untrue. Fix: return whether an entitlement was found; add a distinct "nothing to restore" note; split error copy by cause.

**M‑8 · Device-bound vials undisclosed.** Wallet is keyed to a Keychain/App Attest device identity ([DI.swift:101](app/App/DI.swift:101)); paid vials don't migrate and `restore()` can't recover consumables. No surface says so. A user who changes phones finds an empty purse the fine print never warned about. Fix: one sentence in PolicySheet and/or the shop ("vials stay with the notebook on this device").

**M‑9 · App Attest stuck-key.** [AppAttestIdentity.swift:126](app/App/Security/AppAttestIdentity.swift:126)–140 — re-attest happens only on a server 401. If `generateAssertion` throws locally (DCError `.invalidKey` — SE key gone), the stored keyID is never cleared and every request repeats the failure: permanent decline cards until reinstall. Fix: catch `.invalidKey`, remove the stored keyID, fall through to `attestFresh()`.

**M‑10 · Keeper doesn't reseal on route-away.** [RootView.swift:93](app/App/RootView.swift:93), :126–137 relock only on background; navigating Keeper → shelf leaves it unlocked, and reopening skips re-auth. The gate's own contract says "One unlock buys one visit" ([RootView.swift:122](app/App/RootView.swift:122)) and PageArchive documents sealing "on any route away" — neither ships. Handing over a still-foregrounded device opens the sealed Book with a tap. Fix: seal + clear `keeperUnlocked` when navigation leaves the Keeper's page.

**M‑11 · `ritualAsked` latches before the dialog resolves.** [AppModel.swift:436](app/App/AppModel.swift:436)–445 — persisted *before* `requestAuthorization()`. If the process dies with the system dialog up, authorization stays `.notDetermined` but the app recorded "asked": the Drawer toggle then produces no prompt, no change, no Settings redirect — the notifications feature is permanently dead. Fix: treat `ritualAsked && .notDetermined` as un-asked.

**M‑12 · Legacy `ink.pencilSeen` re-latches A-1 (×2).** [PenPresence.swift:36](app/App/Design/PenPresence.swift:36)–41 reads the persistent plist; a device that ran the pre-fix build upgrades into "pencil seen" on every launch. `AppModel.init` scrubs `ink.bound`/`ink.credits` but not this key. TestFlight-only exposure, but the fix's "never persisted" claim is false on upgraded installs. Fix: `defaults.removeObject(forKey: "ink.pencilSeen")` at startup.

**M‑13 · Delete-all leaves clips on disk.** [DrawerView.swift:650](app/App/Screens/DrawerView.swift:650), [MovingPicture.swift:451](app/App/Screens/MovingPicture.swift:451) — "The ink cannot be recovered," but `Caches/clips/*.mp4` (default protection class) is purged by nothing — not delete-all, not the Keeper reseal. A clip generated from a consented Keeper page persists readable without Face ID. Fix: `ClipCache.purgeAll()` from delete-all (and on `sealKeeper()` for Keeper-derived clips).

**M‑14 · Failed clip = silent black rectangle (×2).** [MovingPicture.swift:360](app/App/Screens/MovingPicture.swift:360)–379 — `failed` is set but never read: cache/download error shows a black frame forever, captioned "tap to fall in", in both the page and the full-screen immersive view. Fix: in-fiction failure line; auto-dismiss the immersive cover on `failed`.

**M‑15 · GoldToggle's real target is 50×29pt.** [Components.swift:328](app/App/Design/Components.swift:328)–348 — the 44pt frame sits outside the Button label with no `contentShape`; only the capsule is tappable. This is every settings toggle. Fix: move the frame + `contentShape` inside the label (tray-button pattern).

**M‑16 · Sub-44pt sweep.** 38pt: RoomNavBar back pill ([Components.swift:292](app/App/Design/Components.swift:292)), SegmentedPills ([Components.swift:377](app/App/Design/Components.swift:377)), PageView back pill (:271). ≤40pt: onboarding "skip" ([OnboardingView.swift:101](app/App/Screens/OnboardingView.swift:101)) and "begin again" (34pt), Drawer export buttons (36pt), Bindery chip (~30pt) and return button (34pt), Remembered search-clear (~20pt), Memory tear yes/no (34pt), KeeperGate "the shelf" (40pt). "Skip" is the only onboarding exit for a user who won't sign. Fix: raise to 44pt minimums.

**M‑17 · Contrast shortfalls beyond H‑6.** KeeperGate refusal line #8C3B2E on #17110B = **2.48:1** — the one line telling a locked-out user what to do ([KeeperGateView.swift:56](app/App/Screens/KeeperGateView.swift:56)); "Use passcode instead" 3.56:1; shelf "resting" caption 2.83:1 on a 0.62-opacity spine ([ShelfView.swift:493](app/App/Screens/ShelfView.swift:493)); paywall renewal-terms small print 3.65:1 at 12.5pt ([PaywallView.swift:97](app/App/Screens/PaywallView.swift:97)). Fix: lighten each to ≥4.5:1.

**M‑18 · VoiceOver override not reactive.** [PenPresence.swift:46](app/App/Design/PenPresence.swift:46) — `UIAccessibility.isVoiceOverRunning` isn't observable; enabling VoiceOver mid-session with a pencil latched leaves the text layer disabled until something else changes. Fix: mirror into observable state via `voiceOverStatusDidChangeNotification`.

**M‑19 · Keyboard can cover the signature field.** [HybridInkSurface.swift:73](app/App/Design/HybridInkSurface.swift:73)–85, [OnboardingView.swift:174](app/App/Screens/OnboardingView.swift:174) — no keyboard-inset handling, and UIKit `becomeFirstResponder` inside a SwiftUI ScrollView doesn't auto-scroll. On iPad landscape the rising keyboard can sit over the line being typed into. Fix: keyboard-safe-area padding or a scroll-to on focus.

**M‑20 · Paywall overstates pictures.** [PaywallView.swift:65](app/App/Screens/PaywallView.swift:65) — "Pictures develop freely, page after page." Only the Artist develops ([Book.swift:52](app/App/Design/Book.swift:52)) and Plus images hit the 8/day cooldown. This is the claim a reviewer or subscriber tests and finds false in 7 of 8 Books. Fix: scope to the Artist or soften "freely".

**M‑21 · Hiding the focused book leaves a stale caption.** [ShelfView.swift:507](app/App/Screens/ShelfView.swift:507), [AppModel.swift:618](app/App/AppModel.swift:618) — `toggleShelf` only mutates `hiddenBooks`; the bottom caption keeps naming the invisible book with "tap again to open". Fix: clear `focusedBookID` when hiding it.

**P‑1 · Archive scalability (×3).** Whole journal decoded synchronously on the main thread during App init — before the first frame, behind nothing the launch veil can mask ([PageArchive.swift:63](app/App/Page/PageArchive.swift:63), [DI.swift:17](app/App/DI.swift:17), [InkwovenApp.swift:5](app/App/InkwovenApp.swift:5)); every entry's `PKDrawing` blob stays resident for the app's lifetime; the entire array is re-encoded and rewritten on the main actor at every `.answered` ([PageArchive.swift:275](app/App/Page/PageArchive.swift:275)). Cost grows without bound with the journal — a year of daily pages is a visible launch hang plus a per-send hitch. Fix (staged): move encode/write off-main now; per-entry files later; async archive load with a Remembered loading state.

## 6. LOW findings (grouped)

**Status legend (2026-08-08):** ✔ fixed · ✳ accepted by design · ▸ deferred. Fixed: L‑1, L‑2 (`c16c46e`); L‑4..L‑8 (`c16c46e`); L‑10, L‑11, L‑13, L‑14, L‑15 (`5261454`); L‑16..L‑22 (`d66be51`, `8a14b3c`); L‑23..L‑25 (`d10eb27`); L‑27 (`5261454`); L‑28..L‑33 (`8a14b3c`, `698654e` completing L‑31); L‑34..L‑38 (`8a14b3c`, `d66be51`, `c16c46e`, `5b42729`); the money-misc lows — paywall-shown undercount (`cd4aa22`), video-moment doc comment, per-use calendar, privacy-policy link (`5261454`). Accepted: L‑3 (server-contract trust; a client workaround would mask real failures), L‑9 (drafts are real; auto-send on reachability stays out of v1), L‑26 (owner-initiated capture is the user's own act), clock-forward rollover (the proxy quota is the backstop). Deferred: L‑12 (`appAccountToken` only matters once the proxy consumes it — pair with the next proxy release).

**Core loop.** L‑1: teardown saves the draft before cancelling the exchange task — race subsumed by H‑1's fix ([PageInteractor.swift:788](app/App/Page/PageInteractor.swift:788)). L‑2: a stroke landed during the gate hop is absorbed without being uploaded (:560 vs :609). L‑3: malformed `done` chunk → fully streamed reply resolves as a failed send; server has billed, client shows decline ([ChunkDecoder.swift:77](app/Packages/InkwovenCore/Sources/InkNet/ChunkDecoder.swift:77)) — server-contract trust. L‑4: `SSEParser` splits only on LF; lone-CR terminators (legal SSE) would break behind a CDN rewrite ([SSEParser.swift:36](app/Packages/InkwovenCore/Sources/InkNet/SSEParser.swift:36)). L‑5: `.pageAnswered` analytics always reports `.ink` even when a picture developed ([PageInteractor.swift:706](app/App/Page/PageInteractor.swift:706)). L‑6: mid-stream erase breaks stroke-count prefix identity — `dropFirst(sentCount)` keeps wrong strokes or wipes fresh ones (:1045). L‑7: `attach`/`restore` mutate observable state inside `makeUIView` on the revisit path ([InkCanvasView.swift:70](app/App/Page/InkCanvasView.swift:70)). L‑8: snapshot rasterization (PKDrawing render + CIFilter + JPEG) on the main actor at every speculation — visible pen-up hitch on a full page (:523). L‑9: offline banner still promises "sends when the way opens" but nothing observes `Reachability` to auto-send ([PageView.swift:639](app/App/Screens/PageView.swift:639)).

**Money.** L‑10: purchase-overlay title "The seal would not take" contradicts the delivery-pending/rejected bodies that say payment succeeded ([PurchaseNotes.swift:59](app/App/Design/PurchaseNotes.swift:59)). L‑11: five sequential one-product StoreKit fetches per refresh, re-issued every foreground (×2 — [AppModel.swift:339](app/App/AppModel.swift:339), [PurchaseService.swift:308](app/App/Money/PurchaseService.swift:308)); batch into one `Product.products(for:)`. L‑12: no `appAccountToken` on purchases — a redelivered grant after an identity change lands in a different wallet ([PurchaseService.swift:180](app/App/Money/PurchaseService.swift:180)). L‑13: paywall has no explicit error/retry state if StoreKit never answers (mitigated by re-fetch on appear/foreground). L‑14: `buyVials` lacks a re-entrancy guard — two rapid taps, two purchase tasks ([AppModel.swift:551](app/App/AppModel.swift:551)). L‑15: `.purchasing` scrim has no timeout — a hung StoreKit call bricks the room until force-quit ([PurchaseNotes.swift:41](app/App/Design/PurchaseNotes.swift:41)). Also: paywall-shown analytics undercounts (ghost-archive tap and cooldown CTA untracked); video never records a daily moment while the InkMoney doc comment says it does ([DailyUsage.swift:55](app/Packages/InkwovenCore/Sources/InkMoney/DailyUsage.swift:55)); clock-forward rolls the local counter (proxy quota is the backstop); `Calendar.current` captured at init so a timezone change rolls on the old zone until relaunch; in-app privacy policy is prose without a hosted URL beside the EULA.

**Lifecycle.** L‑16: two ornament leftovers read aloud — "✦" ([VialsView.swift:187](app/App/Screens/VialsView.swift:187)) and "❦" in MemoryView (off-nav). L‑17: every `RootView.init` builds a throwaway `AppModel` whose `observeCommerce()` streams make it immortal — one App-body dependency away from multiplying live models; no task cancellation anywhere ([RootView.swift:15](app/App/RootView.swift:15), [AppModel.swift:304](app/App/AppModel.swift:304)). L‑18: ritual notification tap routes nowhere — the Book in `userInfo` is read for analytics only ([RitualDelegate.swift:15](app/App/Ritual/RitualDelegate.swift:15)). L‑19: wallet never re-read on foreground; shelf balances can be days-stale after suspension ([RootView.swift:98](app/App/RootView.swift:98)). L‑20: "Use passcode instead" runs the identical biometric-first policy (×2 — [KeeperGateView.swift:47](app/App/Screens/KeeperGateView.swift:47)); drop the button or set `localizedFallbackTitle`. L‑21: overlapping ritual re-arms (benign — date-keyed IDs converge).

**Safety/privacy.** L‑22: export residue survives abnormal termination — no launch purge ([PageExporter.swift:19](app/App/Page/PageExporter.swift:19)). L‑23: closing the report sheet mid-send doesn't cancel the in-flight report — a Keeper page can still be submitted after "Keep it between us" ([ReportSheet.swift:33](app/App/Screens/ReportSheet.swift:33)). L‑24: report consent line omits typed words and the reply text that actually travel ([ReportModel.swift:137](app/App/Page/ReportModel.swift:137)). L‑25: a stray Keeper page can persist in the backed-up open store if the corrective rewrite fails ([PageArchive.swift:354](app/App/Page/PageArchive.swift:354)). L‑26: no `UIScreen.capturedDidChange` handling — screen recording/mirroring shows unlocked Keeper pages (deliberate-decision item). L‑27: PolicySheet identity copy slightly stale ("random install token" vs App-Attest session token, [PolicySheet.swift:28](app/App/Screens/PolicySheet.swift:28)).

**Books/shelf/drawer.** L‑28: Drawer vials row says "Fill the vials" before the wallet has been read — same string as confirmed-empty ([DrawerView.swift:342](app/App/Screens/DrawerView.swift:342)). L‑29: vials shop has no offline state — "—" and disabled buys forever, no explanation ([VialsView.swift:92](app/App/Screens/VialsView.swift:92)). L‑30: delete-all leaves `reportTarget` and the thumbnail NSCache populated ([InkThumbnail.swift:10](app/App/Design/InkThumbnail.swift:10)). L‑31: PDF export renders synchronously on the main actor — UI hitch with no progress state on large journals ([DrawerView.swift:509](app/App/Screens/DrawerView.swift:509)). L‑32: the Oracle is "Suggested tonight" forever — hardcoded `suggested: true` ([Book.swift:66](app/App/Design/Book.swift:66)). L‑33: shelf whisper bubble `fixedSize` can overflow narrow widths ([ShelfView.swift:633](app/App/Screens/ShelfView.swift:633)).

**Design/perf.** L‑34: `DevelopFrame` uses `AsyncImage` with no downsampling — full-res fal image decoded and retained for a ≤420pt frame ([DevelopFrame.swift:76](app/App/Design/DevelopFrame.swift:76)). L‑35: stale doc comment contradicts the A-1 fix ("flips the surface to ink for good", [HybridInkSurface.swift:11](app/App/Design/HybridInkSurface.swift:11)). L‑36: `runDevelop`'s script task isn't cancelled on disappear ([PageView.swift:1011](app/App/Screens/PageView.swift:1011)). L‑37: five bundled font files registered but unused by any code path (bundle dead weight): Caveat-600/700, CormorantGaramond-500, CormorantGaramond-600Italic, EBGaramond-500Italic, Fondamento-400Italic. L‑38: history pill / tray resting contrast ~3.65:1 at 11pt small caps, and while inking they drop to 0.14 opacity yet remain tappable ([PageView.swift:376](app/App/Screens/PageView.swift:376)).

## 7. Closed-roads inventory

| Road | Mechanism | Leaks |
|---|---|---|
| **Memory view** | Off navigation: `.memory` is assigned only in the `#if DEBUG` launch-arg router ([AppModel.swift:230](app/App/AppModel.swift:230)); Release has zero routes in; demo notes removed | Benign riders: the free state pitches a memory feature D5 doesn't deliver even to subscribers (tolerable only while unreachable); `PaywallTrigger.memory`/`SendGate.canUseMemory` have no callers; `memoryEnabled` flows into an always-empty `EmptyMemoryProvider` |
| **Bindery prices** | Structural: no SKUs, no price strings, no buy path; copy says commissions come "with a later edition" ([BinderyView.swift:107](app/App/Screens/BinderyView.swift:107)) | None — cleanest of the roads |
| **Vials/credits shop** | **No longer hidden — deliberately reopened with Epic J**: shelf door back ([ShelfView.swift:94](app/App/Screens/ShelfView.swift:94)), Drawer row live, buys disabled until StoreKit answers | Ops, not code: the deployed proxy is 16 commits behind and 404s `/v1/video` — the shop sells credits for a feature the live backend can't deliver until redeploy. Plus H‑11's stale gifted-vial copy |
| **Video replies** | **Not hidden — live** (Epic J complete): server-side per-reply verdict, tap-to-generate, Keeper consent gate in front | Same deploy drift; `ClipCache`'s replay-from-disk purpose is unreachable (no clip URL stored in archive entries; `revisit()` resets `video = .none`) while its files persist (M‑13, H‑9) |
| **`Book.resting`** | Flag always `false` for all eight; caption/dimming/spoken state are unreachable ornament | None at runtime |
| **InkData (SwiftData) layer** | Entire package dormant — no `ModelContainer` anywhere in the app; shelf hiding lives in UserDefaults, archives in JSON | Docs-vs-code mismatch only (tasks E1b cites `BookState.isHidden`) |
| **InkRender glyph engine** | No app call sites since the d014c72 whole-reply grammar — the reply is plain `Text`; `GlyphPathExtractor`/`GlyphScheduling`/`DevelopFrameDriver` are dormant, kept compiling by the frozen test suite | Zero runtime cost; needs a deliberate keep-or-cut decision |
| **`SendGate.canOpenPage`** | No app caller — Remembered's ghosting re-derives the 30-day rule from `PageArchive.freeFadeAfter`, leaving two sources of truth for one rule ([Entitlements.swift:96](app/Packages/InkwovenCore/Sources/InkMoney/Entitlements.swift:96)) | Route the fade check through the gate or delete the API (mind the test carve-out) |
| **`CreditLedger`** | No app caller — the wallet is server-side | Dead code per house rule |
| **DEBUG launch args** | `-ink.startScreen`/`-ink.startBook`/`-ink.resetOnboarding` all `#if DEBUG`; RootView gates `.page` structurally | None in Release |

## 8. Missing features vs. the app's own promises

Judged against in-binary copy and tasks.md, app-side only:

- **Settings (H3) is half-honest.** Hand ✓ (per-Book + shelf-wide, `setAllHands` correct), ink ✓, left-handed ✓ (flips tray/pill/ribbon/marginalia together). Reply length ✗ (dead control — H‑10). Fade timing ✗ — a fixed "30 days" display row styled in accent like an interactive value ([DrawerView.swift:88](app/App/Screens/DrawerView.swift:88)).
- **H4 polish:** absorb has its haptic; develop has none.
- **H5 share-card export:** absent (PDF/text only). Not promised in-binary — backlog only.
- **Epic I (iPhone):** unbuilt, yet iPhone is in the device family — see H‑8. This is the one place the gap is user-visible rather than backlog.
- **Ritual deep-link:** the notification is written in a Book's voice but never opens that Book (L‑18) — reads as unfinished routing rather than a missing feature.
- E1/E1b/E10 (shelf, curation, starters ×8), H1 (pen-first onboarding), H2 (ritual) are built and match their acceptance criteria.

## 9. Performance summary

The discipline is genuinely good: precomputed typewriter prefixes, static line arrays, hoisted filters, thresholded geometry writes, NSCache'd thumbnails, Lazy containers on all long content, generation-token fencing, and every ambient animation Reduce-Motion-gated. The real costs, in order: **P‑1** (archive decode on the launch path, whole-array rewrite per exchange, all drawings resident), **H‑9** (clip re-downloads + unbounded cache growth), **L‑8** (main-actor snapshot rasterization at every speculation), **L‑31** (synchronous PDF export), **L‑34** (undownsampled develop images). The shelf's ~7 concurrent `repeatForever` ambients deserve one Instruments pass on an iPad mini, nothing more.

## 10. What is genuinely solid

- **StoreKit 2 core**: entitlement derivation, updates-listener-before-reconcile, finish discipline, verification fail-closed, Ask-to-Buy/SCA as `.deferred` with dedicated copy, terminal-vs-transient delivery split with idempotency keys, restore button, manage-subscriptions sheet, family-sharing consistency, purchase scrim against double-press.
- **The Keeper**: structural route gate no navigation can bypass, data-level sealing (sealed store returns zero entries regardless of UI state), background relock purging `revisit`/`reportTarget` and in-memory pages, app-switcher snapshot veil, backup exclusion, stray-page sweep, fail-closed auth with a fresh `LAContext` per attempt. (M‑10 is the one gap in an otherwise airtight design.)
- **Book isolation**: per-book view identity, per-book draft files, frozen `sentDrawing` + generation tokens + digest dedupe — no path for Book A's ink, draft, or context to bleed into Book B.
- **Crisis path**: preemption within one chunk, partial fiction discarded, never billed, ink kept and draft flushed before navigation, no haptic on the transition, region-aware resources with working fallbacks, standing Drawer entry.
- **Privacy hygiene**: manifest matches actual collection; Release analytics is a NullSink; no page text in logs; no pasteboard use; HTTPS to a fixed host with the local override compiled out of Release.
- **Launch**: first frame byte-matches the launch colorset; veil once per process, accessibility-hidden, never delays init; legacy forgeable defaults actively scrubbed with range-validated reads.
- **Fonts/sounds**: all 21 registered faces exist on disk and every PostScript name referenced in code resolves (verified against the TTF name tables); the Feel layer is haptics-only by design, capability-gated, generators warmed exactly where the reply will land.
- **Accessibility craft** on the older surfaces: spoken statuses, answer/decline announcements, one-element history rows, direct-interaction canvases, `@ScaledMetric` crisis layout, dark-mode ink-inversion prevention on both canvases. The gaps (H‑6/H‑7/M‑15..M‑19) stand out precisely because the standard elsewhere is high.

## 11. Server-coupling notes (app-side stance)

- Crisis detection lives entirely on the proxy by design; the client contains no text matching. The `typed` flag ships with every exchange, but the deployed proxy (16 commits behind as of 2026-08-07) predates it — S-2/S-3 and the develop-prompt grounding are **not closed end-to-end until the redeploy**, and the redeploy has a documented boot-order constraint (`INK_ATTESTATION_MODE`).
- The moderated-ink → crisis routing (S-1's fix) assumes the proxy surfaces provider blocks as `.moderated`; a proxy that folded them into generic 5xx would silently degrade the path back to "the spirit is distant."
- The client gate (5 moments/day) is advisory; the proxy quota against the attested identity is the only real ceiling. `DailyUsageStore.reconcile(with:)` awaits a server usage endpoint.
- The vials shop sells credits for clips the live proxy currently cannot deliver (`/v1/video` 404s until redeploy) — H‑9/M‑14 make the failure mode a black rectangle rather than an honest error.

## 12. Suggested fix order (as issued 2026-08-07; executed 2026-08-08 — see §13)

1. **The three quiet data-loss HIGHs** (H‑1, H‑2, H‑3) — small, local, and they defend the product's core promise that the ink is kept.
2. **The two price literals** (H‑4, H‑5) and the paywall/pictures copy (M‑20) — App Review 3.1.2 exposure.
3. **The iPhone decision** (H‑8) — one line to go iPad-only, or real compact layouts; decide before ASC submission.
4. **Onboarding gift copy** (H‑11) + dead reply-length row (H‑10) — first-run honesty.
5. **Daylight modal hexes + the three `.isModal`s** (H‑6, H‑7) — four color constants and two modifiers.
6. **Clip cache key + delete-all purge + failure state** (H‑9, M‑13, M‑14) — one small ClipCache patch covers all three.
7. The remaining mediums as a sweep: exchange-lifecycle UX (M‑1..M‑5), money UX (M‑6..M‑8), Keeper/attest (M‑9, M‑10), latches (M‑11, M‑12), a11y (M‑15..M‑19), and P‑1's off-main write as the first scalability step.

## 13. Remediation record (2026-08-08)

Executed in five wave commits plus three coordinator commits, each building clean before landing:

| Commit | Wave | Closes |
|---|---|---|
| `c16c46e` | Core loop & clips | H‑1/H‑2/H‑3, H‑5, H‑9, M‑1..M‑5, M‑13 (API), M‑14, L‑1/L‑2/L‑4..L‑8, L‑36 |
| `d66be51` | Lifecycle & onboarding | H‑11, M‑11/M‑12, M‑16 (slice), M‑17 (slice), M‑18/M‑19, L‑17..L‑22, L‑35 |
| `8a14b3c` | Design, books, shelf | H‑6/H‑7/H‑8, M‑15..M‑17, M‑20/M‑21, L‑16, L‑28..L‑34, L‑37/L‑38 |
| `698654e` | Coordinator | L‑31 completed (PageExporter off the main actor) |
| `5b42729` | Coordinator | M‑16/L‑38 PageView residuals, M‑14 caption honesty |
| `5261454` | Money | H‑4, H‑10, M‑6..M‑8, M‑13 (delete-all), L‑10/L‑11/L‑13..L‑15, L‑27, money-misc lows |
| `d10eb27` | Keeper & safety | M‑9/M‑10, M‑13 (sealed clips), L‑23..L‑25 |
| `cd4aa22` | Coordinator | paywall-shown undercount (ghosted-archive road) |

**Decisions taken (both reversible):**
- **H‑8 → iPad-only v1.** `TARGETED_DEVICE_FAMILY` is `"2"` in `project.yml`; every pbxproj occurrence updated by hand (no xcodegen run). Note: `project.pbxproj` is **gitignored**, so its half lives on disk only — after any `xcodegen generate` the yml remains the source of truth. Restoring iPhone means shipping tasks.md epic I first.
- **H‑10 → removed, not threaded.** The Reply-length row, its AppModel plumbing, and the persisted `ink.replyLength` key are gone; threading a preference the proxy doesn't yet honor would have kept the control a lie.

**Deferred (tracked):**
- **P‑1 core** — the per-entry-store rework (async launch load with a Remembered loading state, off-main coalesced writes, migration). Deferred deliberately: a bolt-on async write risks a stale background write landing after delete-all — a data-loss class worse than the hitch it removes — and v1 journal volumes keep the current cost invisible. Spawned as its own follow-up task. The adjacent costs named in §9 that *were* safe to take are done: off-main PDF export (`698654e`), off-main snapshot rasterization (`c16c46e` L‑8), downsampled develop images (`8a14b3c` L‑34), stable clip cache (`c16c46e` H‑9).
- **L‑12** — `appAccountToken`; pair with the proxy release that consumes it.

**Verification:** every wave built the app target clean in isolation; final state builds clean, `InkwovenCore` passes 136/136 tests across 22 suites, the frozen `InkwovenTests` bundle passes untouched (the exchange-lifecycle suites exercise the reworked interactor directly), and a fresh-install simulator pass confirmed onboarding (new gifted-moments card live), the shelf, and the Drawer (Reply-length row gone, ritual/hand/theme rows intact). The money wave additionally verified the paywall's computed savings tag, Vials, and PolicySheet on-screen; the design wave hand-verified the pbxproj after font removal with a double build.

**Residual notes for the next session:** the audit's server-coupling caveats (§11) all still stand — nothing here changes the proxy redeploy prerequisite. New-in-remediation behaviors worth knowing: while a revisit is open, a fresh unsent tail lives in RAM only (H‑2's conservative trade); a declined exchange under an engaged hold shows the decline but stays held; sealed clips now live under `Caches/clips/keeper/` and die with the seal.
