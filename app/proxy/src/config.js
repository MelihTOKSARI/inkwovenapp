// Server-tunable knobs (GET /v1/config): the client fetches these at launch
// and on foreground — cap and cooldown changes ship without an app release.
// Everything in CONFIG is PUBLIC: it is served verbatim to any caller. Limits
// that only the server enforces live in LIMITS below and are never served.
export const CONFIG = {
  freeMomentsPerDay: 5,
  // Set from the flux-2 cost model in design/app-store-assets/subscriptions.md
  // §6: flux-2 bills input + output megapixels, so a worst-case Plus user at
  // 8 Artist images/day costs ~30% of net monthly revenue (at 20 it was
  // $16.16/mo against $8.49 net). Raise it from real usage data, not a hunch.
  plusImageDailySoftCap: 8,
  // Cooldown per image past the soft cap; last entry repeats.
  cooldownCurveSeconds: [60, 300, 900, 3600],
  rateLimits: {
    exchangesPerUserPerMinute: 30,
    exchangesPerIPPerMinute: 60,
    // /v1/preupload and /v1/credits/* were previously ungated entirely.
    // 60 preuploads/min against a 60s ticket TTL caps outstanding tickets
    // (and their snapshots) at ~60 per user — see LIMITS.maxSnapshotBytes.
    preuploadsPerUserPerMinute: 60,
    preuploadsPerIPPerMinute: 120,
    creditOpsPerUserPerMinute: 30,
    // /v1/books and /v1/config are cheap reads, but ungated they are a free
    // amplification target and the only routes an unattested caller can reach
    // for nothing. The client fetches both at launch and on foreground, so a
    // generous ceiling costs a real user nothing.
    metadataPerUserPerMinute: 60,
    metadataPerIPPerMinute: 120,
    // /v1/report carries a full page snapshot and is written by a human
    // deciding something went wrong — a handful a minute is generous, and a
    // low ceiling keeps the reports table from becoming a free upload target.
    reportsPerUserPerMinute: 3,
    reportsPerIPPerMinute: 10,
  },
  onboardingCreditGrant: 1,
  // What each modality costs from the credit wallet. Ink and images are
  // covered by the subscription today, so they cost 0 and the reserve/settle
  // path is a no-op for them; video (vials) is the metered modality. Raising
  // a value here turns metering on for that modality with no code change.
  exchangeCosts: { ink: 0, image: 0, video: 1 },
};

// Server-only ceilings. NOT served to the client.
//
// Snapshot arithmetic against fly.toml (256mb VM, http_service hard_limit 250):
// a preupload holds the raw Buffer plus its base64 string, so peak footprint
// per in-flight request is roughly bytes * (1 + 4/3). At 256KB that is ~600KB,
// and 250 concurrent uploads is ~150MB — survivable on a 256MB VM. The old
// Fastify default of 1MB put the same arithmetic at ~600MB, i.e. an OOM.
export const LIMITS = {
  maxSnapshotBytes: 262_144, // 256KB of image bytes
  // Base64 of maxSnapshotBytes, rounded up to a 4-char group.
  maxSnapshotBase64Chars: Math.ceil(262_144 / 3) * 4, // 349_528
  // JSON bodies: snapshot + context + slack. Octet-stream preupload: bytes only.
  exchangeBodyLimit: 384 * 1024,
  preuploadBodyLimit: 262_144,
  smallBodyLimit: 4 * 1024,
  // JSON body of /v1/report: snapshot + reply text + slack, same arithmetic
  // as the exchange body.
  reportBodyLimit: 384 * 1024,
  maxReportNoteChars: 500,
  maxReportReplyChars: 20_000,
  // User-triggered reports (guideline 1.2) are deleted after this many days —
  // the sweep in both stores enforces it; the privacy policy promises it.
  reportRetentionDays: 90,
  // Per-reservation ceiling; the wallet also rejects non-integers and <1.
  maxReservationAmount: 100,
  // Client-supplied memory context, capped before it reaches a system prompt.
  maxMemorySummaries: 24,
  maxMemorySummaryChars: 240,
  maxSessionSummaryChars: 1_000,
  // A single exchange may not hold a connection (or an upstream generation)
  // open forever; heartbeats keep intermediaries from idling it out first.
  streamDeadlineMS: 120_000,
  heartbeatIntervalMS: 15_000,
  // Time to receive a request; SSE responses are unbounded by this.
  requestTimeoutMS: 30_000,
};

/**
 * Rate card for the cost log, supplied at deploy time as INK_MODEL_PRICING:
 *   {"gemini-3.5-flash-lite":{"inputPer1M":0.30,"outputPer1M":2.50}}
 * Keys must match the model IDs pinned in books.js. The card is token-based,
 * so fal's per-unit image/video costs cannot ride here — see deployment.md §6.
 *
 * Prices are a business input, not a source constant, and inventing one is
 * worse than reporting none — so with no rate card the log carries truthful
 * token counts and a null cost rather than a fabricated number.
 */
export function createPricing(env = process.env) {
  let card = {};
  try {
    card = env.INK_MODEL_PRICING ? JSON.parse(env.INK_MODEL_PRICING) : {};
  } catch {
    card = {};
  }
  return function priceFor(model, usage) {
    const rate = card[model];
    if (!rate) return null;
    const input = ((usage.inputTokens ?? 0) / 1_000_000) * (rate.inputPer1M ?? 0);
    const output = ((usage.outputTokens ?? 0) / 1_000_000) * (rate.outputPer1M ?? 0);
    return Number((input + output).toFixed(8));
  };
}
