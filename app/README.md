# Inkwoven — app workspace

Core engineering per `../development.md`. Prime directive: every subsystem is a
pure-logic module with unit tests; the UI binds to it, never the reverse.

## Layout

```
app/
├── App/                         # SwiftUI entry, DI, echo-mode harness (thin; replaced by design handoff)
├── project.yml                  # XcodeGen spec for the app target (xcodegen generate)
├── Packages/InkwovenCore/       # one SPM package, seven module targets + test targets
│   ├── InkCore                  # BookID/Modality/ReplyChunk, IdleSendMachine, SnapshotProcessor, ReplyAssembler, MemoryInjection
│   ├── InkData                  # SwiftData models (CloudKit-ready), InkStore
│   ├── InkNet                   # SSEParser, ChunkDecoder, ProxyClient, RetryPolicy, ExchangeTimer (ttfs)
│   ├── InkRender                # GlyphStrokeScheduler, GlyphPathExtractor (CoreText), WordStreamPaginator, DevelopFrameDriver, VideoLoopDriver
│   ├── InkMoney                 # SendGate (paywall/cooldown order), CreditLedger, ProductIDs, EntitlementProviding
│   ├── InkSafety                # CrisisInterceptor/CrisisGuard, MomentBilling, DeclineMapper
│   └── InkAnalytics             # typed event schema + sink adapter
└── proxy/                       # Node 20 + Fastify serverless proxy (echo mode)
```

Module boundaries are enforced as SPM targets inside one package (identical
import isolation to separate packages, single `swift test` run). `InkCore`
imports Foundation/CoreGraphics only; nothing imports `App`.

## Commands

```sh
# Swift core (all seven modules)
cd Packages/InkwovenCore && swift test

# Proxy
cd proxy && npm install && npm test
cd proxy && npm start                      # echo mode on :8787

# App project (needs xcodegen; or create in Xcode and add App/ + the package)
xcodegen generate && open Inkwoven.xcodeproj
```

## Wire format (proxy ↔ InkNet)

SSE events on `POST /v1/exchange`: `ink_delta {text}`, `image_intent {id,
expectsPreview}`, `image_preview {base64}`, `image_final {url}`, `video_intent
{id}`, `video_final {url}`, `crisis {message, resources}`, `done {modelID,
inputTokens, outputTokens}`. Unknown events are dropped client-side (forward
compat with Book drops). Errors: 422 → moderated (never auto-retried), 429 →
rate limited, 503 `book_resting` → kill-switch.

## Status vs development.md §11

Done (tests green): packages scaffold (1) · InkData models (2) · IdleSendMachine
+ SnapshotProcessor (3) · proxy skeleton + echo `/v1/exchange` (4) · InkNet SSE
client (5) · ReplyAssembler dispatch (6) · render drivers logic (7) · InkMoney
gates + wallet (8) · InkSafety preemption (9) · analytics adapter (10).

Also done: git repo + GitHub Actions CI (A1) · Xcode project via XcodeGen
(`project.yml`) · PencilKit canvas + `PKDrawingRasterizer` + `PageInteractor`
shell glue (B1) · **end-to-end UI test on iPad Air simulator** (stroke → 3s
rest → speculative upload → commit → streamed echo reply; `xcodebuild test`
with the proxy running) · real model routing scaffold in the proxy (C1):
Gemini + OpenAI-compatible streaming providers, Book prompt + memory composed
server-side, echo fallback when no keys, provider failures degrade in-fiction.

Still open for core-done: RevenueCat SDK + live adapter behind
`EntitlementProviding` (A4 — needs a RevenueCat account/API key), CloudKit
mirroring config + conflict tests (D3), Vision OCR indexer (D2), crisis
classifier + moderation calls in the proxy (F1/F2 server half), image/video
provider routing via fal.ai (C4/C5 server half), App Attest on the auth hook,
proxy Redis/Postgres stores for prod, glyph-render spike on device (A6
go/no-go).
