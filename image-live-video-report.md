# Inkwoven — Image & Living-Page Report

*2026-07-17 · Covers: why generated images look identical, what the image/video pipeline is missing, and what to build for a Riddle-diary-quality experience. No code was changed for this report.*

---

## 1. What's wrong today

**The user's words never reach the image model.** This is the root cause of the "same image every time" bug, and it happens twice over:

- The client rasterizes everything — typed text becomes a JPEG of Caveat handwriting on a white page (`TypedInkRasterizer.swift`), Pencil ink a grayscale crop (`PKDrawingRasterizer.swift`) — and sends **only that image**. `PageContext` has fields for the actual text (`priorInkText`, `memorySummaries`, `sessionSummary`) but both call sites send it empty (`PageInteractor.swift:390`, `EchoExchangeView.swift:48`).
- The proxy then calls fal `flux-2/edit` (img2img) with a **hard-coded, never-changing prompt** (`books.js:60`: "Develop this rough ink sketch… warm candlelit tones on aged paper…") plus the page snapshot. Same style prompt + structurally identical input image (a page of text lines looks the same regardless of the words) + an instruction to "keep the original composition faithfully" = near-identical outputs, by design.

**Only the Artist ever generates an image.** `server.js:141` gates the image pass on `book.alwaysDevelop`. Oracle, Storyteller, GM and Parlor all declare `image: z-image-turbo` in `books.js`, but that model is **never invoked anywhere** — dead configuration.

**img2img is the wrong modality for typed prompts.** Feeding a picture of handwriting into an edit model asks it to repaint the page, not to paint what the words describe. It should only be used for actual sketches.

**No diversity lever exists.** No seed, no guidance, no variation parameter is passed to fal (`models.js:121-135`); nothing on the client can influence it either (`ProxyClient.swift` request body is bookID + snapshot + digest only).

**Video is half a product.** The client is fully built — `videoIntent`/`videoFinal` chunk types, `ReplyAssembler` routing, `VideoLoopDriver` with `AVPlayerLooper` seamless looping, the "make it move · 1 vial" button, credit reserve/settle/refund. The proxy has **zero** video support: no video provider in `models.js`, no `video_*` events ever emitted from `server.js`. Pressing the button today can never produce a clip.

**Safety gap on media.** `server.js:115` carries a TODO: no moderation/crisis pass runs before image (or future video) jobs. Fine in echo mode, not fine the day real generation ships.

---

## 2. What's missing

### Server (the bulk of the work)
1. **Prompt derivation** — turn the page into an image brief: typed text arrives as text (once the client sends it); handwriting/sketches get read by the vision model that already sees the page (Gemini), which emits a one-line subject description. Final image prompt = *user subject* + *per-book style suffix* (the current `imagePrompt` becomes the style half, not the whole).
2. **Text-to-image route** for the non-Artist books via `z-image-turbo`, with a per-request random seed. Keep `flux-2/edit` exclusively for real Pencil sketches.
3. **Video provider** — `kling-3` on fal, image-to-video: source frame = the just-generated image URL, plus a short motion prompt derived from the same brief ("candle flame flickers, smoke drifts, her cloak stirs"). Emit `video_intent` → reserve a vial → `video_final`; refund on failure. The client already handles every one of those events.
4. **A second exchange shape for "make it move"** — the button fires after `done`, so the develop-to-video upgrade needs its own endpoint or a re-exchange carrying the image URL.
5. **Moderation gate** before any image/video job (the TODO at `server.js:115`).
6. **Real token/cost accounting** — `tokens: 0, unit_cost: 0` in the cost log defeats the 30%-of-subscription guardrail it exists for.

### Client (small but essential)
1. **Send the words**: populate `PageContext.priorInkText` with the typed string (and wire the existing-but-orphaned `MemoryInjection`).
2. **Tell the server the input kind**: typed vs. drawn, so it can route text-to-image vs. img2img.
3. **Persist media**: fal URLs expire; downloaded images/clips should land in `PageArchive` so a remembered page stays alive forever — an archived page that loses its living picture breaks the whole fantasy.
4. **Preview states**: `expectsPreview: false` is hard-coded; a fast turbo preview under the develop animation would make waits feel intentional.

---

## 3. What "incredible" looks like — the Riddle-diary bar

The magic of the diary is that the page *responds* and the response *breathes*. Instinct says the experience should be layered so every image feels alive, and vials buy *more* life:

**Layer 0 — the develop ritual (free, already half-built).** Never show a spinner. Ink answers first (streaming already works), then the develop frame opens and the image resolves through the staged reveal (`DevelopFrameDriver`). The wait *is* the theater — a photograph developing in a darkroom. Keep generation under ~8s with turbo models so the ritual never outlasts its charm.

**Layer 1 — ambient life (free).** Every developed image gets the client-side Ken Burns drift + the paper-grain shimmer that's already in `PageView`. Cost: zero. Effect: no image on a page is ever fully still. This is the baseline "diary is alive" feeling and it must not be paywalled.

**Layer 2 — true living picture (1 vial).** "Make it move" upgrades the still to a kling-3 ≤5s seamless loop. The crucial detail is the **transition**: crossfade from the exact still into the video's first frame (ask kling for image-to-video so frame 0 *is* the still), so the picture appears to simply start breathing rather than being replaced. Add a soft haptic when motion begins. This moment is the App Store screenshot.

**Layer 3 — memory.** A living page that gets archived stays living: loop file stored locally, replays when the page is reopened. The diary *remembering* in motion is what no competitor screenshot can convey.

**Voice discipline.** The Books must never say "generating your image" — the fiction is that the page develops it. The house-style ban in `models.js` already covers ink; extend the same discipline to every loading state, error ("the ink refuses this picture — try different words"), and paywall copy.

**Trust details.** Refund the vial automatically on any video failure (client logic exists — server must honor it). Rate-limit gracefully in-fiction ("the page is still drying"). Moderate before spending the user's credit, not after.

---

## 4. Priority order

| P | Work | Why first |
|---|------|-----------|
| P0 | Client sends typed text in `PageContext`; server composes image prompt from *user's words* + book style; seed per request | Fixes the reported bug outright |
| P0 | Route typed input → `z-image-turbo`, sketches → `flux-2/edit` | Right model per modality; unlocks images for all image-books |
| P1 | Persist media locally; archive keeps images/loops | Fal URLs expire; memory is the product |
| P1 | kling-3 video provider + `video_*` events + vial settle/refund server-side | Client is already waiting for it |
| P2 | Moderation gate + real cost logging | Must land before real keys ship |
| P2 | Turbo preview under the develop animation; crossfade still→loop; haptics | The polish that makes it feel supernatural |

**Bottom line:** the client architecture is genuinely good — assembler, develop driver, video looper, and credit economy are all built and tested against a server that only ever echoes. Almost everything wrong lives in ~150 lines of proxy: the prompt never contains the user's words, only one book can develop, and video doesn't exist server-side. Fix the prompt pipeline first; it's the smallest change with the largest visible effect.
