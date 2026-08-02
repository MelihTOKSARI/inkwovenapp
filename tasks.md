# Inkwoven — MVP Tasks & Build Plan (all-in, one week)

**MVP goal:** *A new user opens any of the 8 Books, writes or doodles, and watches the page drink the ink and answer — in flowing script, a developing picture, or a moving picture — within 90 seconds of install.*

> **CRITICAL PATH (2026-08-01): moving pictures are launch-blocking and currently unbuilt.**
> No video provider exists on the proxy (`grep video proxy/src/models.js` → 0 hits).
> Epic J below is the hero feature; the launch does not ship without it. Every "flag-off"
> escape hatch elsewhere in this file applies to ink and image, **never to video**.
**Assumptions:** solo founder driving **Claude Design** (all screens/specs) + **Claude Code** (all implementation + tests); native SwiftUI + PencilKit; iPad-first, iPhone companion; iOS 17+; SwiftData + CloudKit; serverless proxy (model routing + remote Book definitions); RevenueCat incl. consumables.
**Sizes (AI-assisted):** S ≈ 1–2 h · M ≈ half day · L ≈ 1 day. Human time is review/tuning; Claude Code writes tests with every story.
**Architecture rule (unchanged):** the engine knows nothing about specific Books; Books are data + prompts. Kill-switch flag per Book and per modality — anything broken gets disabled server-side, not resubmitted.

## Milestones (days, not weeks)

- **D1 — Foundation + magic spikes:** repo, CI, data model, proxy, analytics, RevenueCat; go/no-go spikes: cursive render, image development, **video develop-on-page**.
- **D2 — Paper engine:** write → absorb → modality-routed answer (ink / image / video), end-to-end on device, inside the latency budget.
- **D3 — The shelf:** Book framework + all 8 Books; Remembered Pages + search; Face ID.
- **D4 — Money, memory, sync:** paywall + entitlements, credit wallet, the Bindery, cross-page memory, CloudKit; iPhone companion.
- **D5 — Safety + alpha:** crisis + image/video moderation, red-team, compliance, latency audit, device matrix, prompt tuning ×8.
- **D6 — TestFlight + submit:** friends smoke test, fixes, store listing + hero video, submit with expedited-review request.
- **D7+ — Launch on approval.**

## Epics → stories

### Epic A — Foundation (D1)
- [ ] A1 Xcode project, SwiftUI shell (iPad + iPhone targets), CI — **M**
- [ ] A2 Data model: Notebook, Book, Page, StrokeData, Reply{ink|image|video}, Memory, Entitlement, CreditWallet (SwiftData, CloudKit-ready) — **M**
- [ ] A3 Analytics SDK + schema (NSM, funnel incl. second-Book + credit events, per-Book engagement, **cost-per-subscriber guardrail with 30%-of-sub alert, p50/p95 time-to-first-stroke**) — **S**
- [ ] A4 RevenueCat + sandbox products (monthly, annual+trial, credit packs 10/30/100, Bindery SKUs) — **M**
- [ ] A5 Proxy: key custody, remote Book definitions, model routing (text/image/video/moderation), per-user rate limits, **kill-switch flags** — **L**
- [ ] A6 **Spike: cursive reply render** — go/no-go — **M**
  - AC: 2-sentence reply draws at handwriting pace, variable weight, ≥30fps on iPad Air.
- [ ] A7 **Spike: image development render** — go/no-go — **S**
- [x] ~~A8 Spike: moving picture~~ — **superseded by Epic J. No longer a go/no-go spike: video ships or the launch doesn't.**

### Epic B — The pen & the page (D2)
- [ ] B1 PencilKit canvas: pressure ink, palm rejection, both orientations, per-Book paper texture; **finger-drawing fallback (Pencil recommended, never required)** — **M**
- [ ] B2 Idle-send state machine (~3s rest → snapshot; stroke cancels) + **speculative upload at ~2s (cancel on new stroke)** + unit tests — **M**
  - AC: stroke at 2.9s → send cancelled AND speculative upload aborted; no model call billed.
- [x] B3 Ink-absorption animation — **ends in stroke removal: strokes archived to Page.strokeData then removed from live canvas; opacity is the animation, never the end state** — **S**
  - AC: after reply completes, zero user strokes remain on canvas at any opacity; archived page shows them in Remembered Pages. On send failure, strokes retained fully visible + in-fiction retry.
- [ ] B4 Snapshot pipeline: crop, contrast, downscale — **S**
- [x] B5 Canvas tool tray (in-fiction, top corner, dormant while pen moves): undo/redo (PKCanvasView undoManager), eraser + Pencil double-tap, **hold ("the page waits" → IdleSendMachine .held state, idle-send paused)**, cancel send, turn page — **M**
  - AC: hold active → no send at any rest duration; release → normal 3s cadence resumes; cancel during .speculating → upload aborted, ink retained.
- [x] B6 Occlusion audit: no informative UI in bottom page region while canvas active; all status/error cards render as top-margin marginalia (QuietBanner); placement flips for left-handed mode — **S**

### Epic C — The page answers (D2)
- [ ] C1 Vision-LLM call via proxy; streaming-first (first ink strokes from first tokens); **latency budget enforced: first ink stroke ≤4s p95 on throttled-network profile, image start ≤8s (launch-blocking); p50/p95 time-to-first-stroke instrumented** — **M**
  - Model routing per PRD §7 table: Gemini Flash-Lite default; GPT-5 Mini/Gemini 3 Flash for GM + Tutor; choice lives in server-side Book definition.
- [ ] C2 Modality router: ink / image / video intent → renderer dispatch — **M**
- [ ] C3 Ink renderer (productionize A6): streaming, per-Book hand/ink, pagination — **L**
- [ ] C4 Image renderer (productionize A7), **preview-first (low-res preview develops while full-res generates)**; doodle conditioning (image-to-image) for the Artist — Z-Image Turbo default, FLUX.2 for Artist, both via fal.ai — **L**
- [x] ~~C5 Video renderer~~ — **superseded by Epic J (J3–J5).**
- [ ] C6 In-fiction offline/error states + retry — **S**
- [ ] C7 Model eval harness: 30 handwriting samples + 15 doodles → legibility/quality scores — **M**

### Epic D — Remembered Pages & memory (D3–D4)
- [ ] D1 Persist pages + replies; per-Book timeline UI — **M**
- [ ] D2 On-device handwriting recognition (Vision) → search index — **M**
- [ ] D3 CloudKit sync + conflict policy — **L**
- [ ] D4 Face ID/passcode gate (app-level; Keeper always-locked) — **S**
- [ ] D5 **Cross-page memory (Plus): per-Book rolling summaries (Keeper, GM campaign) injected into context; memory view; "tear out" to erase — unit-tested** — **L**
  - AC: GIVEN a Plus Keeper user with 5 past entries WHEN writing today THEN the reply references remembered themes; torn-out memories never reappear.

### Epic E — The 8 Books (D3)
- [ ] E1 Book framework: schema (prompt, hand, ink, paper, modality policy, starter page), shelf UI ×8, switching — **L**
- [ ] E1b Shelf curation: hide/show per Book (BookState.isHidden; hidden ≠ deleted; "closed cabinet" restore) + count-responsive shelf arrangement (drag-to-reorder = future) — **S**
  - AC: hiding 6 of 8 Books → shelf renders the 2-Book arrangement; hidden Book's pages remain in Remembered Pages; restore returns it with state intact.
- [ ] E2 The Oracle (validates framework) — **S**
- [ ] E3 The Keeper (private-by-default, reflective) — **S**
- [ ] E4 The Storyteller (continuation + illustration policy) — **S**
- [ ] E5 The Artist (doodle-first, style choices on-page) — **M**
- [ ] E6 The Game Master (rolling on-page summary; session cap; memory-ready) — **M**
- [ ] E7 **The Correspondent (letters answered in period hands; public-domain/original figures only)** — **M**
- [ ] E8 **The Tutor (worked solutions/corrections in ink; no curriculum claims; frustration → encouragement path)** — **M**
- [ ] E9 **Parlor Games (riddles, 20 questions, draw-and-guess; game state on-page)** — **M**
- [ ] E10 Starter pages + prompt tuning pass ×8 — **M**

### Epic F — Safety & compliance (D5, all launch-blocking)
- [x] F1 Engine-level crisis classifier (all 8 Books) → break character, care, resources; routing unit-tested — **L**
- [ ] F2 Image **and video** moderation: prompt + output; conservative styles; no photoreal people — **M**
- [ ] F3 Red-team: crisis, GM dark scenarios, Tutor distress, Correspondent impersonation, image/video abuse, minors — **M**
- [ ] F4 Sign in with Apple (optional) + in-app account deletion — **M**
- [x] F5 Export (PDF/text) + delete-all — **S**
- [x] F6 AI disclosure onboarding; privacy labels; subscription + credit terms — **S**
- [x] F7 Report-a-reply (guideline 1.2): long-press report sheet with Keeper-aware consent, `POST /v1/report` behind auth + low rate limits, 90-day retention enforced by a tested sweep, Drawer "Write to the binder" contact row — **M**

### Epic G — Monetization (D4)

> **Pricing change, 2026-08-01:** v1 sells weekly ($4.99, 3-day free trial) + monthly
> ($9.99, the value plan — 54% less than weekly annualised); annual dropped. Product IDs
> renamed to `plus_weekly` / `plus_monthly` while the rename was still free (nothing live
> in ASC). Image soft cap 20 → 8, from the flux-2 cost model — rationale and unit
> economics in `design/app-store-assets/subscriptions.md`.

- [ ] G1 Entitlement gating: 5 moments/day, **Plus image ledger (8/day soft cap → in-fiction slowdown with growing cooldowns, never a hard error; cap + cooldown curve server-tunable)**, 30-day archive, memory=Plus; unit-tested — **M**
  - AC: free user's 6th moment → paywall before any model call. Plus user's 9th image of the day → "the ink must rest" cooldown path, no error state, event logged.
- [x] G2 In-fiction paywall; purchase, restore, trial messaging — **M**
- [ ] G3 Entitlement sync + edge cases (refund, expiry, offline) — **M**
- [ ] G4 **Credit wallet: buy/spend/balance/refund-on-failure — LAUNCH-BLOCKING (funds Epic J)** — **M**
  - Free-clip model changed: **2 free clips per user lifetime**, server-authoritative, replacing the 1-credit onboarding grant. Global monthly ceiling on free-clip spend.
- [ ] G6 **The Vials storefront live: `vials_small/medium/large` (3/8/20 at $4.99/$10.99/$24.99)** — see `design/app-store-assets/credits.md` — **M**
- [x] ~~G5 The Bindery storefront~~ — **cut from v1.** Ships as a try-on room with no SKUs; a shop where nothing can be bought is a 2.1 rejection.

### Epic J — Moving pictures: the hero feature (LAUNCH-BLOCKING)

*The Tom Riddle diary. A reply becomes a scene you fall into. Nothing here is optional and
nothing here has a flag-off escape hatch. Full build spec in the handover; economics in
`design/app-store-assets/credits.md`.*

- [ ] J1 **Video provider on the proxy** — `fal-ai/kling-video/v3/standard/*` bound in
      `models.js`; there is currently no video code there at all. Fix the `kling-3`
      identifier in `books.js` (it 404s). Timeout, retry, error taxonomy — **L**
- [ ] J2 **Convertibility verdict** — every ink reply returns whether it is a scene worth
      moving. Advisory only; never triggers generation. Tuned per Book — **M**
  - AC: a Storyteller scene returns convertible; a Tutor worked solution does not; a
    two-word Oracle riddle does not.
- [ ] J3 **"Make this move" affordance in the response area** — appears only on a positive
      verdict, in-fiction, obeys the occlusion rule — **M**
- [ ] J4 **Generation flow** — tap → credit reserve → provider → bloom on page → settle;
      any failure releases the reservation. Never charges for a clip that didn't arrive — **L**
- [ ] J5 **Immersive playback** — tap the clip and it expands past the page to fill the
      screen: looping, no chrome, no controls; dismiss by tap or swipe down — **L**
  - AC: 60fps expand on iPad Air; audio session doesn't stop the user's music; rotation held.
- [ ] J6 **Keeper consent gate** — explicit page-level consent before the first Keeper clip
      leaves the device; the Keeper is Face ID-locked and private by default — **S**
- [ ] J7 **Video moderation, strictest tier** — prompt AND output; no photoreal people; a
      flagged output never reaches the page and always refunds — **M**
- [ ] J8 **Free-clip accounting** — 2 per user lifetime, server-authoritative, plus a global
      monthly ceiling on free-clip spend that fails closed in fiction — **M**
- [ ] J9 **Analytics** — `video_offered`, `video_requested`, `video_delivered`,
      `video_failed`, `video_immersive_opened`, plus cost-per-clip logging — **S**
- [ ] J10 **Red-team the video path** — prompt injection into generation, abuse, minors,
      moderation bypass, cost-exhaustion — **M**

### Epic H — Ritual & launch (D5–D6)
- [x] H1 Onboarding vignette: notebook introduces itself in ink; first answered page ≤90s; **fully pen-driven — name written in ink on the flyleaf, zero keyboard on iPad anywhere in onboarding (launch-blocking)** — **M**
- [x] H2 Notification ritual per Book + quiet hours — **M** *(ships as one nightly local reminder in the last-opened Book's voice, opt-in after the first answered page; "quiet hours" is the single on/off toggle plus wrote-today suppression, not a full quiet-hours range)*
- [ ] H3 Settings: hand/ink, reply length, fade timing, left-handed mode — **S**
- [ ] H4 Haptics/sound on absorb & develop; perf pass iPad mini→Pro — **M**
- [ ] H5 Share-card export (watermarked) — **S**
- [ ] H6 Store listing + hero engine video (per-Book videos = post-launch weekly content) + **App Store featuring pitch + press kit (Pencil-native PencilKit showcase angle)** — **M**

### Epic I — iPhone companion (D4)
- [ ] I1 Adaptive layout: read-only Remembered Pages timeline on iPhone — **M**
- [ ] I2 Oracle on iPhone (finger/typed sigil — the one non-Pencil surface) — **M**

## Day-by-day

- **D1:** A1–A8 — foundations live; three magic renders green-lit (or flagged off).
- **D2:** B1–B4, C1–C7 — end-to-end answered page in all live modalities, inside latency budget.
- **D3:** E1–E10, D1–D2, D4 — all 8 Books playable; pages persist and search.
- **D4:** D3, D5, G1–G5, I1–I2 — monetized, remembering, synced; companion works.
- **D5:** F1–F6, H1–H5 + latency audit + device matrix + prompt tuning — alpha.
- **D6:** friends TestFlight, fixes, H6, **submit + expedited-review request**.
- **D7+:** launch on approval; per-Book videos ship weekly as the marketing drip.

## Definition of Done

- [ ] All stories merged with passing tests; friends TestFlight smoke pass on iPad mini/Air/Pro + iPhone
- [ ] Latency budget met (ink ≤4s, image ≤8s) on iPad Air
- [ ] **Moving pictures end to end: verdict → tap → clip → immersive loop, on device**
- [ ] **Credit reserve/settle/release + refund-on-failure + 2-free-clip ceiling verified**
- [ ] All 8 Books answer with distinct voices; kill-switch verified per Book/modality
- [ ] Purchase/restore/trial + credit buy/spend/refund + Bindery tested
- [ ] Crisis + image + video moderation red-team signed off
- [ ] NSM + funnel + credit events verified · no open P0 bugs · listing + hero video delivered

## Out of scope for MVP

Voice of the page, sealed letters, printed yearbook, creator Books/marketplace, Android, typed input on iPad, localization, social features, shelf drag-to-reorder.
