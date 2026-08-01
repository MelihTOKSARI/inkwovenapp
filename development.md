# Inkwoven — Core Development Spec (engine only)

**Scope:** the engine and platform core per tasks.md Epics A–D, F, G + proxy. **Explicitly excluded:** all UI styling, screens, animations-as-aesthetics, Book content/prompts, store assets — those arrive from the Claude Design handoff and the Book definitions. Everything here must compile and pass tests with placeholder UI.
**Stack:** Swift 5.10+, SwiftUI app shell, iPad-first + iPhone companion, iOS 17+. SwiftData + CloudKit. Serverless proxy in Node/Fastify. RevenueCat.
**Prime directive:** every subsystem below is a pure-logic module with unit tests; the UI binds to it, never the reverse.

---

## 1. Project structure

`Inkwoven.xcodeproj` — app target `Inkwoven` (iPad + iPhone), test target `InkwovenTests`. Core logic lives in local SPM packages so Claude Code can build/test them without simulator UI:

```
Inkwoven/
├── App/                     # SwiftUI entry, DI container, routing shell (thin)
├── Packages/
│   ├── InkCore/             # domain types, idle-send FSM, modality router (pure, no UIKit)
│   ├── InkData/             # SwiftData models, CloudKit sync, migrations
│   ├── InkNet/              # proxy client, SSE streaming, snapshot upload
│   ├── InkRender/           # ink-glyph engine, develop-frame driver, video player driver (logic)
│   ├── InkMoney/            # entitlements, image ledger, credit wallet (RevenueCat adapter)
│   ├── InkSafety/           # crisis routing, moderation gates
│   └── InkAnalytics/        # event schema + SDK adapter
├── proxy/                   # Node 20 + Fastify serverless (separate deploy)
└── InkwovenTests/           # + each package has its own test target
```

Rules: `InkCore` imports Foundation only. No package imports `App`. All cross-package boundaries are protocols; live implementations injected in `App/DI.swift`. CI: `xcodebuild test` (app) + `swift test` (packages) on every commit.

## 2. Data model (InkData, SwiftData — task A2)

```swift
@Model final class Notebook { var id: UUID; var createdAt: Date; var coverID: String; var books: [BookState] }
@Model final class BookState {                 // per-user state of a Book (definition itself is server-side)
    var bookID: String                          // "oracle", "keeper", ...
    var lastOpenedAt: Date?; var isLocked: Bool // Keeper => always true
    var isHidden: Bool                          // shelf curation (MVP): hidden ≠ deleted, synced
    var shelfOrder: Int                         // schema-ready for future drag-to-reorder; MVP uses default order
    var pages: [Page]; var memory: [MemoryEntry]
}
@Model final class Page {
    var id: UUID; var bookID: String; var createdAt: Date
    var strokeData: Data                        // PKDrawing archive
    var snapshotDigest: String                  // dedupe key
    var replies: [Reply]; var searchText: String?   // Vision OCR result, indexed
}
@Model final class Reply {
    var id: UUID; var kind: ReplyKind           // .ink(text) | .image(assetRef) | .video(assetRef, creditTxID)
    var modelID: String; var latencyMS: Int; var createdAt: Date
}
@Model final class MemoryEntry {                // Plus only
    var bookID: String; var summary: String; var updatedAt: Date; var tornOut: Bool
}
@Model final class CreditTransaction { var id: UUID; var delta: Int; var reason: CreditReason; var at: Date }
// Entitlement is NOT persisted here — RevenueCat is source of truth; InkMoney caches a snapshot.
```

CloudKit: private database, automatic SwiftData mirroring; `strokeData` + image/video assets as `CKAsset`. Conflict policy: last-writer-wins per Page, replies append-only (merge by id). Keeper pages: `CKRecord` encrypted fields; local-first always.

## 3. Idle-send state machine (InkCore — tasks B2, B4)

Pure `IdleSendMachine` — no timers inside; the shell feeds it clock + stroke events, making every AC deterministic:

```swift
enum SendState { case idle, inking, resting(since: Date), speculating(since: Date), committed, cancelled, held }
enum SendEvent { case strokeBegan, strokeEnded(at: Date), tick(now: Date), uploadStarted, uploadFinished,
                 holdToggled, cancelRequested }
// Transitions: strokeEnded → resting; tick ≥2.0s → speculating (emit .beginSpeculativeUpload)
// tick ≥3.0s → committed (emit .commitSend); strokeBegan from resting/speculating → cancelled (emit .abortUpload)
// holdToggled → held ("the page waits": no tick transitions until holdToggled again → idle)
// cancelRequested from resting/speculating → cancelled (emit .abortUpload; ink retained)
```

ACs (unit tests): stroke at 2.9s → `.cancelled` + `.abortUpload` emitted, no send billed; rest to 3.0s → exactly one `.commitSend`; double-commit impossible; `.held` never commits at any rest duration; cancel during `.speculating` aborts upload with ink retained.

**Exchange lifecycle (ReplyAssembler contract):** `.done` → emit `.exchangeComplete` → shell archives strokes to `Page.strokeData` and REMOVES them from the live canvas (absorption animation ends in removal — never minimum-opacity ghosting). Any `ProxyError` → `.exchangeFailed` → strokes retained fully visible, in-fiction retry. Both paths unit-tested; the retain-on-error path is deliberate (user words never vanish into a failed send).

**Snapshot pipeline (B4):** `SnapshotProcessor.process(drawing: PKDrawing, previousDigest: String?) -> SnapshotPayload` — crops to bounding box of strokes added since last exchange, grayscale + contrast normalize, downscale (long edge ≤1024px, JPEG q0.7), returns payload + digest. Digest match ⇒ skip send (dedupe re-rolls).

## 4. Proxy client + streaming (InkNet — tasks A5, C1)

- `ProxyClient.send(_ payload: SnapshotPayload, book: BookID, context: PageContext) -> AsyncThrowingStream<ReplyChunk, Error>` over SSE.
- `ReplyChunk`: `.inkDelta(String)` | `.imageIntent(ImageJob)` | `.videoIntent(VideoJob)` | `.imagePreview(Data)` | `.imageFinal(URL)` | `.crisis(CrisisPayload)` | `.done(Usage)`.
- First `inkDelta` must be surfaced to the renderer immediately (streaming-first). Client stamps `t_send` and reports `time_to_first_stroke` with every exchange.
- Speculative upload: `preupload(payload) -> UploadTicket` (called at 2s); `commit(ticket)` attaches the model call; `abort(ticket)` cancels — server never bills an uncommitted ticket.
- Offline/error → typed `ProxyError` mapped by the shell to in-fiction states; exponential retry (2 attempts) on transport only, never on moderation rejections.

## 5. Modality router (InkCore — task C2)

Server decides modality; client dispatches. `ReplyAssembler` consumes the chunk stream and materializes `Reply` rows: ink text accumulates; `imageIntent` opens a `DevelopSlot` (preview-first: render `imagePreview` bytes when they arrive, swap to `imageFinal`); `videoIntent` requires `CreditReservation` (see §7) before the job is acknowledged. Unknown chunk kinds are ignored (forward compatibility with drops).

## 6. Render pipeline drivers (InkRender — tasks C3, C4, C5; logic level only)

- **InkGlyphEngine:** text → `CTLine` glyph runs → `CGPath` per glyph → timed stroke schedule (per-glyph duration ∝ path length, "pen pace" constant per hand). Exposes `AsyncStream<GlyphStrokeFrame>`; consumes `inkDelta` incrementally with word-boundary pagination. Perf AC: schedule generation ≤5ms/word on A14; ≥30fps sustained is the shell's contract.
- **DevelopFrameDriver:** state machine `awaitingPreview → developingPreview → developingFinal → settled | failed(refunded)`; emits staged progress (edges/midtones/detail) as values, agnostic of how the view draws them.
- **VideoLoopDriver:** download → local `AVPlayerLooper` asset; failure at any stage emits `.refund(creditTxID)` upstream. No streaming playback — clips are ≤5s, download-then-loop.

## 7. Entitlements + credits (InkMoney — tasks A4, G1, G3, G4)

- `EntitlementSnapshot` (from RevenueCat listener): `tier` (.free/.plus), `imageLedger`, `momentsUsedToday`, `archiveWindowDays`, `memoryEnabled`.
- **Gate order (must-test):** `canSend()` runs BEFORE any model call: free 6th moment/day → `.paywall(trigger: .moments)`; Plus image #21/day → `.cooldown(duration:)` (curve fetched from server config, in-fiction slowdown, never an error).
- **Ledgers are server-authoritative** (proxy tracks per-user counters; client caches for offline UX and reconciles on next call — client-side clocks never grant capacity).
- **CreditWallet:** `reserve(1) → CreditReservation` before video job; `settle(reservation)` on `.settled`; `release(reservation)` on failure (refund path, task C5). All math in pure `LedgerCalculator` with property tests (no negative balances, idempotent settle/release).
- RevenueCat: monthly `plus_monthly_9_99`, annual `plus_annual_59_99` (7-day trial), consumables `credits_10/30/100`. Restore + refund/expiry/offline edge cases per G3.

## 8. Safety hooks (InkSafety — tasks F1, F2)

- Proxy runs crisis classifier in parallel with the reply model on every exchange; a `.crisis` chunk **preempts** the stream: client must cancel renderers, discard partial fiction, and surface `CrisisPayload` (plain, unbranded — see design system's CrisisCard). `crisis_flow` event fires; the exchange is not billed as a moment.
- Image/video moderation is proxy-side (prompt + output). Client's only job: `ProxyError.moderated` → in-fiction soft decline, never expose category detail, never retry automatically.
- Unit tests: crisis chunk mid-ink-stream → renderer cancelled ≤1 frame later; crisis in every Book context (fixtures for all 8, incl. GM dark scenario and Tutor frustration).

## 9. Analytics (InkAnalytics — task A3)

Single adapter protocol; events (snake_case, typed constants): `install`, `first_stroke`, `page_sent`, `page_answered {book, modality, ttfs_ms}`, `second_book_opened`, `paywall_shown {trigger}`, `purchase {sku}`, `credit_spent`, `credit_refunded`, `crisis_flow`, `cooldown_hit`, `memory_torn`. Derived: NSM (weekly magic moments), p50/p95 `ttfs_ms`, cost-per-subscriber guardrail (proxy-side job, 30%-of-$9.99 alert).

## 10. Serverless proxy (`proxy/`, Node 20 + Fastify — task A5)

Endpoints (all authed via app-attest + anonymous user token; Sign in with Apple upgrades the token):
- `POST /v1/exchange` — snapshot + bookID + context → SSE stream (routes per Book definition: Flash-Lite default; GPT-5 Mini/Gemini 3 Flash for gm/tutor; Z-Image Turbo / FLUX.2 / Kling 3.0 via fal.ai). Injects Book prompt server-side; client never sees prompts or keys.
- `POST /v1/preupload` / `DELETE /v1/preupload/:ticket` — speculative upload.
- `GET /v1/books` — Book definitions (id, modality policy, model routing, starter text, flags). **Kill-switches live here:** per-Book + per-modality booleans; client treats flag-off as "resting."
- `GET /v1/config` — cooldown curve, image caps, rate limits (server-tunable, no release).
- `POST /v1/credits/reserve|settle|release` — wallet, idempotency keys required.
- Rate limits per user + per IP; counters in Redis; structured cost logging per exchange (`model, tokens, unit_cost`) feeding the guardrail alert.

## 11. Build order & test plan (maps to tasks.md D1–D2)

1. Packages scaffold + CI (A1) → 2. InkData models + migrations (A2) → 3. IdleSendMachine + SnapshotProcessor with full test suites (B2, B4) → 4. Proxy skeleton + `/v1/exchange` echo mode (A5) → 5. InkNet SSE client against echo (C1) → 6. ReplyAssembler + modality dispatch (C2) → 7. Render drivers logic (C3–C5) → 8. InkMoney gates + wallet (G1, G4) → 9. InkSafety preemption (F1) → 10. Analytics adapter (A3).

**Definition of core-done:** `swift test` green across all packages; echo-mode end-to-end exchange on device with placeholder UI; ttfs instrumentation reporting; entitlement gate order verified; crisis preemption verified. Only then does the Claude Design UI get bound on top.
