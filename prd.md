# PRD: Inkwoven (MVP) — the paper engine + 8 launch Books, all-in

**Status:** Draft v3 (all-in launch) · **PM:** Maxime · **Build:** Claude Design (screens) + Claude Code (implementation)
**Target ship date:** submit to App Review by **2026-07-12** (this week) · **Last updated:** 2026-07-06

> **Scope decision (v3):** founder call — everything ships in the MVP. All former P1/P2 items, the three first-drop Books (8 Books total), moving pictures + credits, cross-page memory, the cosmetics/content store, and the iPhone companion are now launch scope, built AI-first in one week. This deliberately overrides the vision doc's "5 sharp Books" launch-discipline rule; the mitigations are in §8. The brand story stays the engine: *paper that answers.*

---

## 0. Pricing Model

| Tier | Price | What's included |
|---|---|---|
| Free | $0 | All 8 Books · 5 magic moments/day (ink replies; ~1 image/day within them) · 30-day page archive · Face ID lock |
| Inkwoven Plus | **$4.99/wk (3-day trial) or $9.99/mo** | Unlimited ink replies · **8 images/day soft cap — past it, in-fiction slowdown ("the ink must rest") with growing cooldowns, never a hard error; a real server-side ledger, unit-tested, tunable without release** · full archive · **cross-page memory (the notebook remembers you)** · all hands/inks · unlimited notebooks |
| **Moving-picture credits (the Vials)** | 3 / 8 / 20 at $4.99 / $10.99 / $24.99 | **LAUNCH-BLOCKING — the hero feature.** Consumable; never bundled unlimited (real unit cost ~$0.46/clip delivered). **2 free clips per user, ever**, so everyone reaches the hero moment; global monthly spend ceiling enforced server-side. |
| Content IAP (the Bindery) | — | **Cut from v1.** Ships as a try-on room with no SKUs; a storefront where nothing can be bought is a 2.1 rejection. |

- **Paywall trigger:** 6th magic moment of a day, reopening a >30-day page, or invoking memory ("the notebook wants to remember this…") — always after a value moment, never at onboarding.
- **Soft vs hard:** soft — free stays genuinely magical daily.
- **Platform:** **StoreKit 2 direct** in v1 (RevenueCat deferred to the server-side entitlement gate); enrol in the Small Business Program for 15%.
- **Rationale:** weekly is the low-commitment entry and the only price that survives the worst-case image user; monthly is the value plan at a 54% saving and must be shown as such. All 8 Books free maximizes shelf discovery; we monetize volume (moments), memory, modality (video credits), and cosmetics — not doors.

## 1. Context & Problem

**Why now:** vision LLMs read handwriting off a canvas snapshot; image generation feels like a photo developing; video generation is now viable per-unit-priced; the open-source Riddle project proved fascination with the mechanic; no pen-first AI product exists. **New:** Claude Design + Claude Code collapse the build cost — a scope that was 12 weeks for 1–2 devs is now a one-week AI-assisted build, which is why the all-in launch is even on the table.
**Problem:** AI lives in cold chat windows; Pencil owners have world-class ink but dumb paper; the demand pools (reflection, creativity, solo play, learning, correspondence) are served by typing-first single verticals.
**Wedge:** one enchanted object, pen-first, multi-Book.

## 2. Goals

| Metric | Baseline | Target | Timeframe |
|---|---|---|---|
| Activation (first answered page) | 0 | 65% of installs | Launch +4 wk |
| ≥2 Books opened in week 1 | 0 | 50% of activated | Launch +4 wk |
| D7 / D30 retention | 0 | 30% / 20% | Launch +8 wk |
| Free→paid conversion | 0 | 4% | Launch +8 wk |
| Credit-pack attach rate (payers) | 0 | 15% | Launch +8 wk |
| NSM: weekly magic moments / active user | 0 | ≥6 | Launch +8 wk |

**Planning discipline:** budget infra and any spend against the conservative case (~25–30k installs / 12k MAU at 12 mo); 100k installs is the stretch headline, never a cost assumption. No ad spend until organic CAC/LTV data exists (~launch +8 wk, via app-analytics).

**Non-goals (MVP):** Android, typed input, voice of the page, sealed letters, printed yearbook, creator-published Books, social features, localization (English only), therapy/clinical or education-curriculum claims.

## 3. Users

**Primary:** "Maya," 29, iPad Air + Pencil, AI-curious, journals sporadically, plays story games, shares delightful app moments.
**Secondary:** "Dev," 34, solo-RPG player seeking a game master; "Sam," 38, parent conjuring illustrated bedtime stories; "Leo," 16, wants worked math solutions in ink; "June," 41, writes letters to Austen and gets answers.

**Key user stories (additions in bold):**
1. As a new user, I want to write on the page and watch it drink my ink and answer, so that I feel the magic inside 90 seconds.
2. As a curious user, I want to switch among 8 Books from a shelf, so the same notebook becomes diary, storyteller, game, artist, oracle, **pen-pal, tutor, or parlor**.
3. As a doodler, I want my sketch to develop into finished art, so I can create beyond my skill.
4. As a solo player, I want the page to run my adventure and illustrate key moments.
5. As a private writer, I want the Keeper locked behind Face ID with local pages, so I can be honest.
6. **As a subscriber, I want the notebook to remember earlier pages, so the Keeper and Game Master feel alive across sessions.**
7. **As a delight-seeker, I want a moving picture to bloom on the page (credits), so I have something no other app can show.**
8. **As a collector, I want covers, inks, and seasonal papers from the Bindery, so my notebook feels mine.**
9. **As an iPhone user, I want a read-only companion (plus the Oracle), so my notebook is with me between iPad sessions.**

## 4. Requirements — all P0 (deliberate all-in launch; see §8)

**The paper engine:**
- PencilKit canvas: pressure ink, palm rejection, portrait/landscape; paper texture per Book. **Pencil recommended, not required — finger drawing works everywhere (widens the funnel to the full iPad base; nothing gates on Pencil detection).**
- Idle-send state machine (**2s pen rest** → snapshot → send; new stroke cancels); **speculative upload at 1s (cancel on new stroke) so network cost is pre-paid at send-commit**; ink-absorption animation **starts the instant the send commits — 1s of in-fiction theater the model runs behind**.
- **One surface gesture, no rest-window chrome.** The concept is disappearing and appearing: ink goes under, an answer comes up, through the same paper. Both directions read from a single token (`InkMotion.Surface`) — 1s travel, 8pt of depth, mirrored curve — so ink, ink replies, developed pictures and moving pictures all cross the surface the same way. Nothing narrates the wait: no settle dots, no cancel button, no "the ink drinks into the page…" banner. The disappearance IS the feedback, and a writer learns the 2s beat in one page. The affordances survive behind an off switch (`RestWindowAffordances`), not a deletion; VoiceOver still announces every status, since a blank page tells a blind writer nothing.
- Vision-LLM pipeline via thin serverless proxy (key custody, Book prompt injection, rate limits); **streaming-first: first ink strokes render from first tokens, never from a completed reply**. Snapshots downscaled hard; send only the region with new strokes since last exchange.
- **Latency budget: first ink stroke ≤4s after send (p95, throttled-network test profile); image development starts ≤8s; violating this kills the fiction — treat as a launch-blocking bug. Instrument p50/p95 time-to-first-stroke.**
- **Reply modality router + convertibility signal (LAUNCH-BLOCKING):** the model decides ink / image per page context and, on every reply, returns a **convertibility verdict** — is this reply a scene with visual life, or is it a riddle, a correction, a worked equation? The verdict is advisory data on the reply, never an auto-generation. Client renders all three modalities.
- **Video is never auto-generated.** Where the verdict is positive, the response area carries an affordance — *make this move* — and a clip is requested only when the user taps it. This is the same user-triggered principle as reporting: the page never spends the user's money or the user's privacy on their behalf.
- Ink renderer: streamed cursive (Core Text glyph paths + stroke animation), per-Book hand/ink.
- Image renderer: develops on-page like a darkroom photo, **preview-first — low-res/progressive preview begins developing immediately while full-res generates (the darkroom fiction is built for this)**; doodle-conditioning (image-to-image) for the Artist.
- **Moving-picture renderer (LAUNCH-BLOCKING, the hero feature): user taps → credit reserve → fal `kling-video/v3` → develop-on-page bloom → looping player.** Refund-on-failure via reserve/settle/release; the user is never charged for a clip that didn't arrive.
- **Immersive playback: tap the clip and it expands past the page to fill the screen** — looping, no chrome, no controls, dismiss by tap or swipe down. The page is a window; tapping goes through it. This is the Riddle-diary moment and the single most shareable thing the product does.
- **The Keeper requires its own consent for video.** It is a Face ID-locked private diary; converting a Keeper page means transmitting it. Explicit, page-level consent before the first Keeper clip — never a silent tap.
- **Free-clip accounting:** 2 free clips per user lifetime, server-authoritative, plus a global monthly ceiling on free-clip spend so a viral week cannot produce an unbudgeted bill.
- **Exchange lifecycle (tested, not implied):** on reply completion → user strokes archived to the page record and REMOVED from the live canvas (absorption ends in removal, never minimum-opacity ghosting); on send failure → strokes retained with in-fiction retry. Canvas is always ready for the next exchange after a successful reply.
- **Canvas tool tray (in-fiction, top corner, dormant while pen moves):** undo, eraser (+ Pencil double-tap), **hold ("the page waits" — pauses idle-send for long writing/drawing)**, cancel send, turn page. Never grows into a toolbar.
- **Pen-first input everywhere, onboarding included:** name and all onboarding responses written in ink; a keyboard appearing on iPad is a launch-blocking bug.
- **Occlusion rule:** no informative UI (status, errors, cards, banners) in the bottom region of the page — the writing hand covers it. All status renders as top-margin marginalia; placement flips with left-handed mode.
- In-fiction offline/error states; retry.

**The 8 Books (content modules on the engine):**
- Book framework: definition schema (prompt, hand, ink, paper, modality policy, starter page), shelf UI, switching; definitions served remotely.
- **Shelf curation (MVP = hide/show only): hide/show Books (never uninstall — hidden Books restorable from a "closed cabinet" affordance); shelf arrangement adapts automatically to visible-Book count (8 = full shelves, 2 = desk pair). No user-facing layout setting. Drag-to-reorder = future.**
- The Storyteller · The Artist · The Game Master (session state on-page) · The Oracle · The Keeper (Face ID-gated, private-by-default) · **The Correspondent** (letters answered by historical/fictional hands — original or public-domain figures only) · **The Tutor** (worked solutions and corrections in ink; no curriculum claims) · **Parlor Games** (riddles, 20 questions, draw-and-guess).

**Memory & pages:**
- Remembered Pages: all pages persisted (SwiftData), on-device handwriting search (Vision), timeline per Book; CloudKit sync.
- **Cross-page memory (Plus): per-Book memory summaries (Keeper reflections, GM campaign state) injected into context; user-visible and erasable ("tear out the memory").**

**Safety & compliance:**
- Crisis classifier on all Books (break character, care, resources — red-teamed, incl. Tutor frustration and GM dark scenarios).
- Image AND video moderation (prompt + output) — App Review requirement.
- User-triggered reporting of any AI reply (long-press → report sheet → server store, 90-day retention) + published support contact in the Drawer — App Review requirement (guideline 1.2). Nothing reports automatically; content leaves the device only on send.
- Optional Sign in with Apple, in-app account deletion, export/delete-all, privacy labels, AI disclosure, subscription + credit terms, 13+ rating.

**Monetization:**
- RevenueCat paywall, purchase/restore, entitlement gating (daily moments, image allotment, archive window, memory).
- **Credit wallet: buy/spend/refund-on-failure for moving pictures.**
- **The Bindery: content IAP storefront (covers, inks, papers) — StoreKit products, no AI cost.**

**Ritual & polish (former P1/P2, now launch scope):**
- Onboarding vignette (the notebook introduces itself in ink); first answered page ≤90s.
- Notification ritual per Book + quiet hours; reply length/tone settings; left-handed mode.
- Haptics/sound on absorption & development; share-card export of a finished page (watermarked).

**iPhone companion:**
- Read-only Remembered Pages + full Oracle (finger or typed sigil — the one sanctioned non-Pencil surface); same binary, adaptive layout.

**Analytics:** one SDK; NSM + funnel (install → first stroke → first answered page → second Book → D1 → paywall → purchase) + per-Book engagement + credit funnel + **unit-economics guardrail: model cost per subscriber per month, alert when p95 user exceeds 30% of $9.99** + p50/p95 time-to-first-stroke.

## 5. Out of Scope (MVP)

Voice of the page, sealed letters, printed yearbook, creator Books/marketplace, Android, typed input on iPad, localization, social features, shelf drag-to-reorder. Book definitions remain server-side so future drops ship without app review where possible.

## 6. Design & UX

**Workflow:** Claude Design generates the full screen inventory from this PRD (shelf ×8, page, paywall, Bindery, credit wallet, memory view, iPhone companion, onboarding); Claude Code implements against those specs in SwiftUI.
Core flows: (1) onboarding vignette → first answered page ≤90s; (2) the page — write → rest → absorb → answer (ink flows / picture develops / moving picture blooms); zero chrome while writing; (3) the shelf — 8 Books, distinct paper/hand/ritual; (4) Remembered Pages — timeline + search + memory view; (5) paywall in-fiction ("bind the notebook to you"); (6) the Bindery; (7) iPhone companion.
Tone: candlelit stationery, parchment grain, iron-gall ink; every animation serves the fiction.

## 7. Technical Considerations

Native **SwiftUI + PencilKit** (ink latency, glyph animation, and Pencil interaction *are* the product), implemented by **Claude Code**; iPad + iPhone (companion mode), iOS 17+. Local-first SwiftData + CloudKit. Serverless proxy: model routing per the table below (choice lives in the server-side Book definition — swappable without app release), remote Book definitions, per-user rate limits. RevenueCat/StoreKit 2 incl. consumables.

**Model routing (July 2026 picks — costs verified, revisit monthly):**

| Job | Model | Cost | Why |
|---|---|---|---|
| Ink replies, default (Oracle, Keeper, Storyteller, Artist, Correspondent, Parlor) | Gemini Flash-Lite class | ~$0.001–0.002/page | Top small-model handwriting accuracy; sub-second TTFT streamed |
| Ink replies, heavy (Game Master, Tutor) | GPT-5 Mini / Gemini 3 Flash | ~$0.005–0.01/page | Best handwriting + reasoning at small-model price |
| Images, default illustrations | Z-Image Turbo via fal.ai | ~$0.01/img, ~1s @1024² | Speed inside the develop animation; free-tier viable |
| Images, Artist doodle img2img | FLUX.2 via fal.ai | ~$0.03–0.055/img | Quality where it's the whole point; fal = lowest prod latency |
| **Moving pictures (5s loop)** | **fal `fal-ai/kling-video/v3/standard/*`** | **$0.42/clip** ($0.084/s, audio off); $0.46 effective at 8% failure | Verified Aug 2026. **Use the fully-qualified fal route** — the short-form model name is not an endpoint and 404s. Pro tier $0.56, audio adds ~50%. Credit must sell ≥$1.00 for real margin |
| Crisis + moderation | deterministic in-process screen (`textSignalsCrisis`) + the reply model's `[[CRISIS]]` sentinel | zero | The screen runs on the writer's context before the provider call and on the assembled reply after; no model in the loop, so a provider swap cannot remove it. The sentinel is the fast path, scanned at any offset |

Heavy-user math (re-verified Aug 2026 against published rates): typical Plus user ≈ $1.05/mo, heavy ≈ $3.21/mo. At the old 20-image cap the worst case was **$16.16/mo** — a loss against the monthly plan — because flux-2 bills input **and** output megapixels (~$0.024/image, not the $0.03–0.055 assumed here). **Cap lowered to 8/day**, server-tunable. Video is metered separately by credits and never bundled. If heavy users hurt margins, sell image top-up credits (wallet already exists) before ever raising price. Unit-test targets (Claude Code writes tests alongside): idle-send machine, modality router, entitlement + credit math, memory injection, crisis routing. Data model: Notebook, Book, Page, StrokeData, Reply{ink|image|video}, Memory, Entitlement, CreditWallet.

## 8. Risks & Open Questions

| Risk | L | I | Mitigation |
|---|---|---|---|
| **One-week all-in launch: compressed QA, no real beta, 8 surfaces to break** | H | H | Claude Code writes tests with every feature; day-5 red-team + device matrix; day-6 friends TestFlight; kill-switch flags per Book and per modality so anything broken can be disabled server-side without resubmission |
| **App Review latency/rejection (AI images + video + credits all at once)** | M | H | Submit day 6; expedited-review request; conservative styles, no photoreal people; complete AI disclosure + credit terms; fallback: launch whenever approved, marketing holds |
| Eight doors dilute the launch story | H | H | Brand = the engine; one hero demo; listing leads with "paper that answers"; per-Book videos roll out post-launch as the drip instead |
| Latency breaks the fiction | M | H | §4 latency budget is launch-blocking; small/fast models, streaming, aggressive caching |
| Video unit cost / moderation failure | M | H | Credits only, never unlimited; **user-triggered generation only** (nothing spends without a tap); refund-on-failure; 2 free clips capped by a global monthly ceiling; strictest moderation on video |
| **Video is launch-blocking and unbuilt as of Aug 1** | H | H | No provider is bound on the proxy today. This is the critical path — everything else in the launch waits on it |
| Cursive/development animations underwhelm | M | H | Day-1 spikes with go/no-go; ink and image can slip to a flag-off state. **Video cannot — it is the launch** |
| Crisis mishandled in any of 8 Books | M | H | Engine-level classifier; red-team incl. Tutor + GM scenarios |
| Correspondent IP exposure | M | M | Public-domain/original figures only at launch; zero trademarked references |
| Image costs at free tier | M | H | ~1 image/day free, caching, downscaled outputs |

Open questions: (Eng) video model pick — cost/speed/loop quality; (Design) 8 distinct paper/hand directions in Claude Design without blending together; (PM) hero demo = engine ink moment or Artist doodle.

## 9. Rollout Plan (this week)

- **Day 1–4 — Build:** per tasks.md; engine → Books → money/safety → companion/polish.
- **Day 5 — Alpha + red-team:** internal on-device pass (iPad mini/Air/Pro + iPhone), prompt tuning across 8 Books, crisis/image/video red-team, latency audit.
- **Day 6 — TestFlight + submit:** friends-and-family smoke test; fix; submit to App Review with expedited request. Store listing: hero engine video + screenshots (per-Book videos become post-launch content). **Prepare and send the App Store featuring pitch + press kit — a Pencil-native PencilKit showcase is exactly what editorial features, and one feature outperforms months of organic.**
- **Day 7+ — Launch on approval:** worldwide, English. ASO: "AI notebook," "Apple Pencil AI," "paper that answers." Post-launch: per-Book videos ship one per week — the drop cadence becomes a marketing cadence even though the Books are already in.

## 10. Launch Checklist

- [ ] **Moving pictures work end to end: convertibility verdict → tap → clip blooms → immersive full-screen loop** · [ ] **Credit reserve/settle/release + refund-on-failure verified** · [ ] **2-free-clip accounting + global ceiling verified server-side** · [ ] Latency budget met on iPad Air (ink ≤4s, image ≤8s) · [ ] QA iPad mini/Air/Pro + iPhone, both orientations · [ ] All 8 Books answer correctly with distinct voices · [ ] Analytics funnel + per-Book + credit events verified · [ ] Paywall/restore/trial + credit purchase/refund tested · [ ] Crisis + image + video moderation red-team pass · [ ] Kill-switch flags verified per Book/modality · [ ] Store listing + hero video · [ ] Privacy labels, AI disclosure, account deletion verified
