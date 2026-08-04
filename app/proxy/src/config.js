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
    // /v1/video holds an SSE stream for minutes and each accepted request
    // costs real dollars at fal. Two a minute lets a genuine "try again"
    // through while making a request loop useless as a cost weapon.
    videosPerUserPerMinute: 2,
    videosPerIPPerMinute: 6,
  },
  // What each modality costs from the credit wallet. Ink and images are
  // covered by the subscription today, so they cost 0 and the reserve/settle
  // path is a no-op for them; video (vials) is the metered modality. Raising
  // a value here turns metering on for that modality with no code change.
  // Zero-cost modalities are NOT unmetered: the daily quotas below
  // (LIMITS.*Daily*, CONFIG.freeMomentsPerDay) bound them server-side.
  exchangeCosts: { ink: 0, image: 0, video: 1 },
  // Moving pictures (tasks J1/J8). Served to the client so the affordance can
  // be honest about what a tap spends, and tunable without a release.
  video: {
    // 2 free clips per user, LIFETIME — replaces onboardingCreditGrant, which
    // handed a credit at install before any intent to pay. The count is
    // server-authoritative: the client never grants a free clip.
    freeClipsPerUser: 2,
    // Global ceiling on free clips per calendar month, counted server-side
    // across all users. When it closes, the free path fails closed in fiction
    // ("the ink must rest") — a viral week must not produce a bill nobody
    // agreed to. 2,000 clips ≈ $915/mo at the $0.457 effective clip cost
    // (design/app-store-assets/credits.md §2/§4).
    freeClipMonthlyCeiling: 2000,
    // Free clips are keyed to the x-ink-user token, and in anonymous
    // attestation mode that token IS the identity — so rotating it mints a
    // fresh pair of free clips. Nothing above stops one machine from spending
    // the whole month's ceiling in an afternoon and denying it to everyone
    // else; only App Attest really closes that, and it is not bound yet.
    //
    // Until then the address pays for the tokens behind it. 20/day is far
    // above any plausible household or small office (10 first-time readers a
    // day behind one NAT) and far below what an exhaustion run needs.
    freeClipsPerIPPerDay: 20,
    clipSeconds: 5,
  },
};

// Server-only ceilings. NOT served to the client.
//
// Snapshot arithmetic against fly.toml (256mb VM, http_service hard_limit 250):
// a preupload holds the raw Buffer plus its base64 string, so peak footprint
// per in-flight request is roughly bytes * (1 + 4/3). At 256KB that is ~600KB,
// and 250 concurrent uploads is ~150MB — survivable on a 256MB VM. The old
// Fastify default of 1MB put the same arithmetic at ~600MB, i.e. an OOM.
export const LIMITS = {
  // -- daily exchange quotas (audit M-2) -------------------------------------
  // /v1/exchange was entirely unmetered server-side: ink and images cost 0
  // from the wallet, so the reserve/settle block never ran and the free-tier
  // cap lived only in the iOS client's UserDefaults — a scripted client never
  // executed it. These ceilings are enforced in the route BEFORE the provider
  // handshake, per identity per UTC day, and refunded on the same conditions
  // that release a wallet hold (crisis, client gone, pre-stream failure).
  //
  // Free identities get CONFIG.freeMomentsPerDay (the number the client's own
  // gate shows). Identities that proved a Plus receipt via /v1/entitlement get
  // this ceiling instead — far above any hand that writes pages one at a
  // time, far below what a script needs to hurt.
  plusExchangeDailyCeiling: 300,
  // Server hard stop on Plus develop passes per day. The client's soft cap is
  // CONFIG.plusImageDailySoftCap (8) with a cooldown curve past it; walking
  // the whole curve for 24h tops out near 30, so 40 never contradicts the
  // client while bounding what a scripted Plus receipt can spend at fal.
  plusImageDailyCeiling: 40,
  // Global backstop across ALL identities: even with minted identities (see
  // attest.js), one UTC day of exchanges cannot exceed this. Fails closed in
  // fiction (ink_resting) rather than billing a viral week nobody agreed to.
  globalDailyExchangeCeiling: 20_000,
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
  // -- moving pictures (Epic J) ---------------------------------------------
  // Video is minutes, not seconds, so it gets its own ceilings rather than
  // inheriting the image path's 90s. The stream deadline outlasts the
  // generation timeout so the client always hears the failure as an event,
  // never as a dead socket.
  videoGenerationTimeoutMS: 360_000,
  videoStreamDeadlineMS: 420_000,
  videoQueuePollMS: 3_000,
  // A verdict brief must outlive the reading of the reply (the user taps when
  // they tap), but not become a permanent free-form generation token.
  videoBriefTTLms: 30 * 60_000,
  maxBriefChars: 600,
  // Replies below this length are never offered as scenes — a two-word Oracle
  // riddle costs no classifier call. Bias toward not offering.
  minConvertibleReplyChars: 80,
  // The reply text is capped before it reaches the verdict classifier.
  maxVerdictReplyChars: 4_000,
  // /v1/credits/grant carries a StoreKit JWS (a few KB of base64).
  grantBodyLimit: 16 * 1024,
  // A hold outlives its request only when the process died between reserve and
  // settle — a deploy or a crash mid-generation. Those holds are invisible to
  // the user and permanently subtract from `available`, so they are reclaimed.
  //
  // Must comfortably exceed videoStreamDeadlineMS (7 min): reclaiming a hold
  // whose generation is still running would hand the credit back AND deliver
  // the clip. 30 minutes is four times the longest legitimate hold.
  staleHoldReclaimMS: 30 * 60_000,
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

/**
 * Video rate card, supplied at deploy time as INK_VIDEO_PRICING:
 *   {"kling-video-v3-standard":{"perSecond":0.084}}
 * fal bills video PER SECOND of clip, not per token, so it cannot ride the
 * token card above (deployment.md §6.6). Same philosophy: with no card the
 * clip log carries a truthful null, never an invented number.
 */
export function createVideoPricing(env = process.env) {
  let card = {};
  try {
    card = env.INK_VIDEO_PRICING ? JSON.parse(env.INK_VIDEO_PRICING) : {};
  } catch {
    card = {};
  }
  return function priceForClip(model, seconds) {
    const rate = card[model];
    if (!rate || typeof rate.perSecond !== 'number') return null;
    return Number((seconds * rate.perSecond).toFixed(8));
  };
}
