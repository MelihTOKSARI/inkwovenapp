// Inkwoven proxy (task A5). Endpoints per development.md §10. Echo mode is the
// build-order step-4 target: a real SSE exchange with no model keys, so the
// client pipeline (InkNet → assembler → renderers) runs end-to-end on device.
//
// Auth: the x-ink-user token is resolved to an identity by the verification
// seam in attest.js, which fails CLOSED — see that file for what a human must
// still supply before App Attest is real.
import Fastify from 'fastify';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { BOOKS, developPrompt, findBook, publicBook } from './books.js';
import { CONFIG, LIMITS, createPricing, createVideoPricing } from './config.js';
import { createStores } from './stores.js';
import { createAttestationVerifier, AttestationError } from './attest.js';
import { AppAttestError, createAppAttestVerifier, createSessionTokens } from './appattest.js';
import { createNotificationVerifier, createReceiptVerifier, ReceiptError } from './receipts.js';
import { keyPart } from './keys.js';
import {
  createTextProviderFactory,
  createImageProviderFactory,
  createVideoProviderFactory,
  createVerdictProviderFactory,
  createPromptModerator,
  composeSystemPrompt,
  composeVideoPrompt,
  sniffImageMime,
  sniffImageMimeBase64,
  ProviderError,
  CRISIS_SENTINEL,
  CRISIS_PAYLOAD,
  textSignalsCrisis,
} from './models.js';

// What each consumable credits, decided HERE — the client names a product,
// never an amount (design/app-store-assets/credits.md §3).
const VIAL_GRANTS = { vials_small: 3, vials_medium: 8, vials_large: 20 };

// The subscriptions /v1/entitlement accepts as proof of Plus. Must match the
// SKUs in app/Inkwoven.storekit and InkMoney/Products.swift.
const PLUS_PRODUCTS = new Set(['plus_weekly', 'plus_monthly']);

const ECHO_REPLY =
  'The page drinks your ink and stirs. Ask again when the real models are bound; for now this echo proves the stream.';

const UUID_PATTERN = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
const SHA256_HEX_PATTERN = /^[0-9a-f]{64}$/;

// -- request schemas ---------------------------------------------------------
// Every mutating route validates its body. Fastify's ajv coerces types and
// strips unknown keys, which is what closes the two worst body bugs: a
// negative or string `amount` on reserve, and an unbounded memorySummaries
// array riding into the system prompt.
const exchangeSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    properties: {
      bookID: { type: 'string', minLength: 1, maxLength: 64 },
      ticketID: { type: ['string', 'null'], pattern: UUID_PATTERN },
      digest: { type: ['string', 'null'], maxLength: 128 },
      snapshotBase64: { type: ['string', 'null'], maxLength: LIMITS.maxSnapshotBase64Chars },
      // The typed hand wrote this page: the snapshot is rendered words, not
      // a sketch. Steers the develop pass only — never billing or gating.
      typed: { type: 'boolean' },
      context: {
        type: 'object',
        additionalProperties: false,
        properties: {
          priorInkText: { type: ['string', 'null'], maxLength: LIMITS.maxSessionSummaryChars },
          sessionSummary: { type: ['string', 'null'], maxLength: LIMITS.maxSessionSummaryChars },
          memorySummaries: {
            type: 'array',
            maxItems: LIMITS.maxMemorySummaries,
            items: { type: ['string', 'null'], maxLength: LIMITS.maxMemorySummaryChars },
          },
        },
      },
    },
  },
};

const reserveSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    properties: {
      amount: { type: 'integer', minimum: 1, maximum: LIMITS.maxReservationAmount },
    },
  },
};

const reservationSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['reservationID'],
    properties: { reservationID: { type: 'string', pattern: UUID_PATTERN } },
  },
};

const ticketParamsSchema = {
  params: {
    type: 'object',
    required: ['id'],
    properties: { id: { type: 'string', pattern: UUID_PATTERN } },
  },
};

// The client points at a server-stored brief and names its own job id; it
// never supplies prompt text. The videoID doubles as the retry key: one id,
// one generation, however many times the request is re-sent.
const videoSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['briefID', 'videoID'],
    properties: {
      briefID: { type: 'string', pattern: UUID_PATTERN },
      videoID: { type: 'string', pattern: UUID_PATTERN },
    },
  },
};

const grantSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['productID', 'transactionID', 'jws'],
    properties: {
      productID: { type: 'string', minLength: 1, maxLength: 64 },
      transactionID: { type: 'string', pattern: '^[A-Za-z0-9._-]{1,64}$' },
      jws: { type: 'string', minLength: 1, maxLength: 12_288 },
    },
  },
};

// /v1/entitlement carries the same three fields as a grant — a StoreKit JWS
// plus what the caller believes it presents — so it shares the shape.
const entitlementSchema = grantSchema;

// App Attest bodies (audit T3). Sizes: a keyID is 32 bytes (44 b64 chars), a
// challenge 32 bytes, an attestation object runs a few KB of CBOR, an
// assertion a few hundred bytes.
const attestSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['keyID', 'attestation', 'challenge'],
    properties: {
      keyID: { type: 'string', minLength: 40, maxLength: 60 },
      attestation: { type: 'string', minLength: 1, maxLength: 16_384 },
      challenge: { type: 'string', minLength: 40, maxLength: 60 },
    },
  },
};

const assertSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: ['keyID', 'assertion', 'challenge'],
    properties: {
      keyID: { type: 'string', minLength: 40, maxLength: 60 },
      assertion: { type: 'string', minLength: 1, maxLength: 4_096 },
      challenge: { type: 'string', minLength: 40, maxLength: 60 },
    },
  },
};


// Loose on purpose: rejects garbage without turning a clock-skewed device's
// report away over a timestamp format.
const ISO_DATE_PATTERN = '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}';

const reportSchema = {
  body: {
    type: 'object',
    additionalProperties: false,
    required: [
      'reportID',
      'replyID',
      'pageID',
      'bookID',
      'reason',
      'replyKind',
      'modelID',
      'snapshotDigest',
      'snapshotBase64',
      'createdAt',
      'submittedAt',
    ],
    properties: {
      reportID: { type: 'string', pattern: UUID_PATTERN },
      replyID: { type: 'string', pattern: UUID_PATTERN },
      pageID: { type: 'string', pattern: UUID_PATTERN },
      bookID: { type: 'string', minLength: 1, maxLength: 64 },
      reason: {
        type: 'string',
        enum: ['disturbing', 'wrong_or_nonsense', 'not_what_i_asked', 'something_else'],
      },
      note: { type: ['string', 'null'], maxLength: LIMITS.maxReportNoteChars },
      replyKind: { type: 'string', enum: ['ink', 'image', 'video'] },
      replyText: { type: ['string', 'null'], maxLength: LIMITS.maxReportReplyChars },
      assetRef: { type: ['string', 'null'], maxLength: 500 },
      modelID: { type: 'string', maxLength: 200 },
      snapshotDigest: { type: 'string', pattern: '^[0-9a-f]{64}$' },
      snapshotBase64: { type: 'string', minLength: 1, maxLength: LIMITS.maxSnapshotBase64Chars },
      createdAt: { type: 'string', maxLength: 40, pattern: ISO_DATE_PATTERN },
      submittedAt: { type: 'string', maxLength: 40, pattern: ISO_DATE_PATTERN },
    },
  },
};

/**
 * SSE plumbing shared by /v1/exchange and /v1/video: one abort controller per
 * stream, tripped by a client disconnect or the deadline; raw writes that
 * honour backpressure and never throw; a heartbeat that keeps intermediaries
 * from idling the connection out mid-generation.
 */
function createStreamChannel(reply, { deadlineMS, heartbeatMS }) {
  const abort = new AbortController();
  let clientGone = false;
  let heartbeat = null;
  const giveUp = () => {
    if (!clientGone) {
      clientGone = true;
      abort.abort();
    }
  };
  const deadline = setTimeout(giveUp, deadlineMS);
  const cleanup = () => {
    clearTimeout(deadline);
    if (heartbeat) clearInterval(heartbeat);
  };
  // Writes to a socket the peer already dropped must never surface as an
  // unhandled 'error' event.
  reply.raw.on('error', giveUp);
  // The RESPONSE's 'close' is the reliable peer-went-away signal: the request
  // stream has already been consumed by the body parser by the time a handler
  // runs, so its own 'close' has usually fired and can never be observed
  // here. writableFinished separates a premature disconnect from our own end().
  reply.raw.on('close', () => {
    if (!reply.raw.writableFinished) giveUp();
  });

  /** Writes to the raw stream, honouring backpressure. Never throws. */
  const writeRaw = async (chunk) => {
    const raw = reply.raw;
    if (clientGone || raw.writableEnded || raw.destroyed) return false;
    try {
      if (raw.write(chunk)) return true;
    } catch {
      giveUp();
      return false;
    }
    // The socket's buffer is full. Waiting for 'drain' is the difference
    // between backpressure and queueing a whole generation in process memory
    // for a client that has stopped reading.
    await new Promise((resolve) => {
      const settle = () => {
        raw.off('drain', settle);
        abort.signal.removeEventListener('abort', settle);
        resolve();
      };
      raw.once('drain', settle);
      abort.signal.addEventListener('abort', settle, { once: true });
    });
    return !clientGone;
  };

  return {
    abort,
    get clientGone() {
      return clientGone;
    },
    cleanup,
    send: (event, data) => writeRaw(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
    /** Commits the 200 + SSE headers and starts the heartbeat. hijack() hands
     * the socket over explicitly; without it Fastify still believes it owns
     * the response. */
    open: () => {
      reply.hijack();
      reply.raw.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
        'x-accel-buffering': 'no',
      });
      // SSE comments: the client drops them, intermediaries keep the
      // connection off their idle timers.
      heartbeat = setInterval(() => {
        writeRaw(': ping\n\n').catch(() => {});
      }, heartbeatMS);
      heartbeat.unref?.();
    },
    end: () => {
      if (!reply.raw.writableEnded) reply.raw.end();
    },
  };
}

/** Pre-stream provider failures still get a real status; see the exchange route. */
function statusForProviderError(error) {
  if (error instanceof ProviderError) {
    if (error.kind === 'moderated') return { status: 422, code: 'moderated' };
    if (error.kind === 'rate_limited') return { status: 429, code: 'upstream_rate_limited' };
  }
  return { status: 503, code: 'upstream_unavailable' };
}

/** Constant-time hex compare; both sides are already length-checked. */
function digestMatches(claimed, actual) {
  if (typeof claimed !== 'string' || !SHA256_HEX_PATTERN.test(claimed)) return false;
  return timingSafeEqual(Buffer.from(claimed, 'hex'), Buffer.from(actual, 'hex'));
}

/** Retry-After for a daily quota: the window reopens at UTC midnight. */
function secondsToUTCMidnight(now = Date.now()) {
  const next = new Date(now);
  next.setUTCHours(24, 0, 0, 0);
  return Math.max(1, Math.ceil((next.getTime() - now) / 1000));
}

/**
 * Notifies a human that a report was filed (audit S-7). Reports used to
 * INSERT into a table nobody read, swept unread at ninety days, while the
 * sheet promised "this page goes to a human hand for review" — and guideline
 * 1.2 obliges acting within 24 hours. The webhook (INK_REPORT_WEBHOOK_URL,
 * Slack-compatible {text}) carries counts and categories ONLY, never report
 * content: the page snapshot and reply stay in the store for the
 * authenticated triage route. Fire-and-forget with a short timeout — a slow
 * webhook must never slow the reporter's 200.
 */
function createReportNotifier(env = process.env) {
  const url = env.INK_REPORT_WEBHOOK_URL;
  if (!url) return null;
  return async function notify({ reason, bookID, openReports }) {
    const text =
      `Inkwoven report filed — reason: ${reason}, book: ${bookID}. ` +
      `${openReports} open report${openReports === 1 ? '' : 's'} awaiting triage (GET /v1/admin/reports).`;
    await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ text }),
      signal: AbortSignal.timeout(3_000),
    });
  };
}

export function build(options = {}) {
  const app = Fastify({
    logger: options.logger ?? false,
    // Fly terminates TLS and APPENDS the real client address to
    // x-forwarded-for, so the true client is the RIGHTMOST entry — which is
    // what trustProxy:1 (trust one hop) reads. `true` would take the LEFTMOST
    // entry, which is entirely client-supplied and therefore spoofable.
    // Without this, request.ip was the Fly edge's internal address: every user
    // in the fleet shared one 60/min bucket, so a single abuser 429'd everyone.
    trustProxy: options.trustProxy ?? 1,
    // Time to RECEIVE a request. SSE responses are unbounded by this; the
    // per-stream deadline below bounds those.
    requestTimeout: LIMITS.requestTimeoutMS,
    // Small by default; the two routes that carry a snapshot opt up.
    bodyLimit: LIMITS.smallBodyLimit,
  });
  // Store calls are awaited throughout: the in-memory stores answer
  // synchronously, the Redis/Postgres ones (stores-redis.js) don't.
  const env = options.env ?? process.env;
  const stores = options.stores ?? createStores();
  const echoDelayMS = options.echoDelayMS ?? Number(process.env.ECHO_DELAY_MS ?? 40);
  const textProviderFor = options.textProviderFactory ?? createTextProviderFactory();
  const imageProviderFor = options.imageProviderFactory ?? createImageProviderFactory();
  const videoProviderFor = options.videoProviderFactory ?? createVideoProviderFactory(env);
  const verdictFor = options.verdictFactory ?? createVerdictProviderFactory(env);
  const moderatePrompt = 'promptModerator' in options ? options.promptModerator : createPromptModerator(env);
  const attestation = options.attestation ?? createAttestationVerifier(env);
  const priceFor = options.priceFor ?? createPricing(env);
  const priceForClip = options.priceForClip ?? createVideoPricing(env);
  // Receipt verification: real, or nothing. Null means no trust anchor is
  // configured (receipts.js REQUIRES A HUMAN), and the grant route refuses
  // rather than crediting a wallet from claims anyone can write.
  const verifyReceipt =
    'verifyReceipt' in options ? options.verifyReceipt : createReceiptVerifier(env);
  // Human alerting for filed reports (audit S-7); null means unconfigured,
  // and the report route still files — alerting is additive, never a gate.
  const notifyReport = 'notifyReport' in options ? options.notifyReport : createReportNotifier(env);
  // App Store Server Notifications V2 (audit M-4): same trust anchor as the
  // receipt verifier; null answers 501 rather than trusting anything.
  const verifyNotification =
    'verifyNotification' in options ? options.verifyNotification : createNotificationVerifier(env);
  // App Attest (audit T3): the attestation verifier and the session-token
  // mint. Null answers 501 on the attest routes — never a fallback identity.
  const appAttest = 'appAttest' in options ? options.appAttest : createAppAttestVerifier(env);
  const sessionTokens =
    'sessionTokens' in options ? options.sessionTokens : createSessionTokens(env);
  // Operator token for the triage route. No default: unset means the route
  // answers 501 rather than trusting anything.
  const adminToken = env.INK_ADMIN_TOKEN ?? null;
  // Overridable so the tests can exercise the deadline and the heartbeat
  // without waiting out the production intervals.
  const streamDeadlineMS = options.streamDeadlineMS ?? LIMITS.streamDeadlineMS;
  const heartbeatMS = options.heartbeatMS ?? LIMITS.heartbeatIntervalMS;
  const videoStreamDeadlineMS = options.videoStreamDeadlineMS ?? LIMITS.videoStreamDeadlineMS;
  // Daily exchange quotas (audit M-2). Overridable for the tests whose
  // subject is a DIFFERENT limit — production always runs the defaults.
  const dailyQuota = {
    free: CONFIG.freeMomentsPerDay,
    plus: LIMITS.plusExchangeDailyCeiling,
    image: LIMITS.plusImageDailyCeiling,
    global: LIMITS.globalDailyExchangeCeiling,
    ...(options.dailyQuota ?? {}),
  };

  app.decorate('stores', stores);
  app.decorate('attestationMode', attestation.mode);

  // Speculative uploads arrive as raw snapshot bytes.
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (req, body, done) => {
    done(null, body);
  });

  // -- health ----------------------------------------------------------------
  // Unauthenticated on purpose: the Fly check must not depend on the auth hook,
  // or hardening auth marks every machine unhealthy and restarts it into the
  // same failure. fly.toml's [checks.health] probes /health/ready — keep the
  // two in step; a path missing from this set is a path the auth hook 401s.
  const HEALTH_ROUTES = new Set(['/health', '/health/ready']);
  app.get('/health', async () => ({ ok: true, attestation: attestation.mode }));

  // Readiness touches the stores, so a Redis/Postgres outage can't leave a
  // machine reporting healthy while every wallet call 500s.
  app.get('/health/ready', async (request, reply) => {
    try {
      await stores.walletView('__healthcheck__');
      return { ok: true };
    } catch (error) {
      request.log?.error?.({ route: 'health', error: String(error) });
      return reply.code(503).send({ ok: false, error: 'stores_unavailable' });
    }
  });

  // The triage route authenticates with the OPERATOR token, not a user
  // identity — in `required` attestation mode no operator could otherwise
  // reach it. The route itself fails closed without INK_ADMIN_TOKEN.
  // /v1/notifications is Apple's servers calling in: its authentication is
  // the signed payload itself, verified against the same root as receipts.
  const ADMIN_ROUTES = new Set(['/v1/admin/reports', '/v1/notifications']);
  // The attest routes run BEFORE identity exists — they are how identity is
  // made (audit T3). Each is 501 when unbound and per-IP rate limited.
  const ATTEST_ROUTES = new Set(['/v1/attest/challenge', '/v1/attest', '/v1/attest/refresh']);

  // -- auth hook -------------------------------------------------------------
  app.addHook('onRequest', async (request, reply) => {
    const path = request.url.split('?')[0];
    if (HEALTH_ROUTES.has(path) || ADMIN_ROUTES.has(path) || ATTEST_ROUTES.has(path)) return;
    const token = request.headers['x-ink-user'];
    if (!token || typeof token !== 'string' || token.length > 256) {
      return reply.code(401).send({ error: 'missing_user_token' });
    }
    try {
      // The verifier — not the header — decides the identity. In 'required'
      // mode nothing gets through until a real one is bound (attest.js).
      const { userID } = await attestation.verify({ token, request });
      request.userID = userID;
    } catch (error) {
      const status = error instanceof AttestationError ? error.status : 401;
      return reply.code(status).send({ error: error?.code ?? 'unauthenticated' });
    }
  });

  /**
   * Fixed-window limits on both the identity and the (now real) client IP.
   * Both key components are hashed so a token containing ':' can't land in
   * another key's namespace. Replies 429 and returns false when limited.
   */
  async function withinLimits(request, reply, userLimit, ipLimit) {
    const allowed =
      (await stores.allow(`user:${keyPart(request.userID)}`, userLimit)) &&
      (await stores.allow(`ip:${keyPart(request.ip)}`, ipLimit));
    if (!allowed) {
      await reply.code(429).header('retry-after', '60').send({ error: 'rate_limited' });
      return false;
    }
    return true;
  }

  /** The two metadata reads share one limit. */
  async function withinMetadataLimits(request, reply) {
    return withinLimits(
      request, reply,
      CONFIG.rateLimits.metadataPerUserPerMinute,
      CONFIG.rateLimits.metadataPerIPPerMinute,
    );
  }

  // -- GET /v1/books: definitions minus prompts; kill-switches live here -----
  app.get('/v1/books', async (request, reply) => {
    if (!(await withinMetadataLimits(request, reply))) return reply;
    return { books: BOOKS.map(publicBook) };
  });

  // -- GET /v1/config: server-tunable knobs ----------------------------------
  app.get('/v1/config', async (request, reply) => {
    if (!(await withinMetadataLimits(request, reply))) return reply;
    return CONFIG;
  });

  // -- speculative upload ----------------------------------------------------
  app.post('/v1/preupload', { bodyLimit: LIMITS.preuploadBodyLimit }, async (request, reply) => {
    // Previously ungated: one token could park unbounded 1MB buffers on a
    // 256MB VM. The limit also caps outstanding tickets, since each expires
    // in 60s.
    if (
      !(await withinLimits(
        request,
        reply,
        CONFIG.rateLimits.preuploadsPerUserPerMinute,
        CONFIG.rateLimits.preuploadsPerIPPerMinute,
      ))
    ) {
      return reply;
    }

    const claimedDigest = request.headers['x-ink-digest'];
    if (!claimedDigest) return reply.code(400).send({ error: 'missing_digest' });
    if (!Buffer.isBuffer(request.body) || request.body.length === 0) {
      return reply.code(400).send({ error: 'missing_snapshot' });
    }
    if (request.body.length > LIMITS.maxSnapshotBytes) {
      return reply.code(413).send({ error: 'snapshot_too_large' });
    }
    // The snapshot must actually be an image: the providers embed it in a data
    // URI, and an unrecognised payload has no honest media type to declare.
    if (!sniffImageMime(request.body)) {
      return reply.code(415).send({ error: 'unsupported_snapshot' });
    }
    // The digest was stored and never checked — integrity theatre. The client
    // sends lowercase SHA-256 hex (InkCore/Snapshot.swift), so verify it.
    const actualDigest = createHash('sha256').update(request.body).digest('hex');
    if (!digestMatches(claimedDigest, actualDigest)) {
      return reply.code(400).send({ error: 'digest_mismatch' });
    }

    // The snapshot bytes ride the ticket: a committed exchange sends only
    // the ticketID, so the image the model reads must be recoverable here.
    return stores.createTicket(request.userID, actualDigest, request.body.toString('base64'));
  });

  app.delete('/v1/preupload/:id', { schema: ticketParamsSchema }, async (request, reply) => {
    await stores.deleteTicket(request.params.id, request.userID);
    // Aborting an unknown/expired ticket is fine — it was never billable.
    return reply.code(204).send();
  });

  // -- POST /v1/exchange: snapshot + book + context → SSE stream -------------
  app.post(
    '/v1/exchange',
    { schema: exchangeSchema, bodyLimit: LIMITS.exchangeBodyLimit },
    async (request, reply) => {
      const { bookID, ticketID } = request.body ?? {};

      const book = findBook(bookID);
      if (!book) return reply.code(404).send({ error: 'unknown_book' });
      if (!book.flags.enabled) {
        // Kill-switch: the client renders this as the Book "resting."
        return reply.code(503).send({ error: 'book_resting' });
      }
      // Per-modality kill-switch. flags.ink was defined on every Book and read
      // nowhere, so the only lever an operator had was taking the whole Book
      // down. Now ink can be rested on its own.
      if (!book.flags.ink) return reply.code(503).send({ error: 'ink_resting' });

      if (
        !(await withinLimits(
          request,
          reply,
          CONFIG.rateLimits.exchangesPerUserPerMinute,
          CONFIG.rateLimits.exchangesPerIPPerMinute,
        ))
      ) {
        return reply;
      }

      // -- independent crisis screen, writer's side (audit S-2) --------------
      // The page itself travels as an image, but every TEXT channel the
      // writer supplies is screened deterministically before any provider
      // sees the exchange — no model in the loop, so a provider swap or a
      // reply-model regression cannot remove this layer. Nothing is counted
      // or charged: the quota block below never runs on this path.
      const writerText = [
        request.body?.context?.priorInkText,
        request.body?.context?.sessionSummary,
        ...(Array.isArray(request.body?.context?.memorySummaries)
          ? request.body.context.memorySummaries
          : []),
      ]
        .filter((part) => typeof part === 'string')
        .join('\n');
      if (textSignalsCrisis(writerText)) {
        const channel = createStreamChannel(reply, { deadlineMS: streamDeadlineMS, heartbeatMS });
        channel.open();
        await channel.send('crisis', CRISIS_PAYLOAD);
        channel.cleanup();
        request.log?.info?.({ route: 'exchange', book: book.id, crisis: true, screen: 'writer' });
        channel.end();
        return;
      }

      // -- daily quotas (audit M-2) ------------------------------------------
      // Checked BEFORE the ticket is consumed and BEFORE any provider call.
      // Ink and images cost 0 from the wallet, so without this the route had
      // no server-side ceiling at all: the free-tier cap lived only in the
      // iOS client's UserDefaults, which a scripted caller never runs. The
      // per-identity limit depends on what the identity has PROVED — a Plus
      // receipt posted to /v1/entitlement widens it; nothing else does.
      const tier = await stores.tierOf(request.userID);
      const quota = { moment: false, image: false, global: false };
      let quotaRefunded = false;
      /** The quota analogue of resolveHold('release') — same conditions. */
      const refundQuota = async () => {
        if (quotaRefunded) return;
        quotaRefunded = true;
        try {
          if (quota.moment) await stores.refundDaily(`exch:${request.userID}`);
          if (quota.image) await stores.refundDaily(`img:${request.userID}`);
          if (quota.global) await stores.refundDaily('global:exchange');
        } catch (error) {
          request.log?.error?.({ route: 'exchange', stage: 'quota_refund', error: String(error) });
        }
      };

      const momentLimit = tier === 'plus' ? dailyQuota.plus : dailyQuota.free;
      const moment = await stores.allowDaily(`exch:${request.userID}`, momentLimit);
      if (!moment.allowed) {
        return reply
          .code(429)
          .header('retry-after', String(secondsToUTCMidnight()))
          .send({ error: 'daily_quota' });
      }
      quota.moment = true;
      const globalDay = await stores.allowDaily('global:exchange', dailyQuota.global);
      if (!globalDay.allowed) {
        // The global ceiling bounds OUR daily spend, not this user's — fail
        // closed in fiction rather than blaming the writer.
        await refundQuota();
        return reply.code(503).send({ error: 'ink_resting' });
      }
      quota.global = true;

      // A committed ticket consumes the speculative upload; only now is the
      // exchange billable. Uncommitted tickets simply expire. The ticket
      // carries the snapshot the client already uploaded — a committed
      // exchange body has no snapshotBase64 of its own.
      let ticketSnapshot = null;
      if (ticketID) {
        const taken = await stores.takeTicket(ticketID, request.userID);
        ticketSnapshot = taken?.snapshotBase64 ?? null;
      }

      const snapshotBase64 = request.body?.snapshotBase64 ?? ticketSnapshot;
      let snapshotMime = null;
      if (snapshotBase64) {
        snapshotMime = sniffImageMimeBase64(snapshotBase64);
        if (!snapshotMime) return reply.code(415).send({ error: 'unsupported_snapshot' });
      }

      // -- metering ----------------------------------------------------------
      // The wallet is server-authoritative: what an exchange costs is decided
      // here, reserved BEFORE anything is generated, settled on success, and
      // released on failure or client disconnect. CONFIG.exchangeCosts prices
      // each modality; ink and images are subscription-covered today and cost
      // 0, so the hold is skipped — turning metering on is a config change,
      // not a code change.
      const imageProvider = book.alwaysDevelop && book.flags.image ? imageProviderFor(book) : null;
      const willDevelop = Boolean(imageProvider && snapshotBase64);
      // Plus identities get a develop-pass ceiling of their own (audit M-2/M-5)
      // — the client's soft cap slows images down past 8, this hard stop
      // bounds what a scripted Plus receipt can spend at fal. Free identities
      // are already bounded by the moment quota above.
      if (willDevelop && tier === 'plus') {
        const image = await stores.allowDaily(`img:${request.userID}`, dailyQuota.image);
        if (!image.allowed) {
          await refundQuota();
          return reply
            .code(429)
            .header('retry-after', String(secondsToUTCMidnight()))
            .send({ error: 'daily_quota' });
        }
        quota.image = true;
      }
      const cost =
        (CONFIG.exchangeCosts.ink ?? 0) + (willDevelop ? CONFIG.exchangeCosts.image ?? 0 : 0);

      let reservationID = null;
      if (cost > 0) {
        const held = await stores.reserve(request.userID, cost);
        if (held.error === 'insufficient_credits') {
          await refundQuota();
          return reply.code(402).send(held);
        }
        if (held.error) {
          await refundQuota();
          return reply.code(409).send(held);
        }
        reservationID = held.reservationID;
      }
      const resolveHold = async (outcome) => {
        if (!reservationID) return;
        const id = reservationID;
        reservationID = null;
        try {
          await stores.idempotent(request.userID, `${outcome}:exchange:${id}`, () =>
            outcome === 'settle' ? stores.settle(request.userID, id) : stores.release(request.userID, id),
          );
        } catch (error) {
          request.log?.error?.({ route: 'exchange', stage: outcome, error: String(error) });
        }
      };

      // -- cancellation ------------------------------------------------------
      // One channel per exchange, aborted by a client disconnect or by the
      // stream deadline. Without it a user swiping away left the upstream
      // generation running to completion at full cost, delivered to nobody.
      const channel = createStreamChannel(reply, {
        deadlineMS: streamDeadlineMS,
        heartbeatMS,
      });
      const { abort, send, cleanup } = channel;
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

      // -- crisis gate -------------------------------------------------------
      // The safety override (models.js) makes the model open with
      // CRISIS_SENTINEL when the writer's page reads as genuine self-harm
      // risk. The old gate matched the sentinel only as an exact prefix of
      // the reply head and then LATCHED open (audit S-3): a model that led
      // with a quote mark streamed the literal "[[CRISIS]]" as ink, and one
      // that recognised danger three sentences in could never escape. This
      // scanner watches the WHOLE stream: the sentinel fires at any offset,
      // is stripped from anything that ships, and the scan never stops. A
      // suffix that could still become the sentinel is held back until the
      // next delta decides it — the client buffers the full reply and only
      // reveals it at `.answered`, so a mid-reply crisis still preempts
      // everything. Echo mode never passes through here.
      let crisisServed = false;
      let heldTail = ''; // suffix that is still a live prefix of the sentinel
      // The full reply as served — the convertibility verdict (task J2) judges
      // it after the stream completes, never on the ttfs-critical path.
      let replyText = '';

      /** Routes one ink delta through the scanner. Returns false once the exchange must stop. */
      const sendInk = async (text) => {
        const combined = heldTail + text;
        if (combined.includes(CRISIS_SENTINEL)) {
          crisisServed = true;
          await send('crisis', CRISIS_PAYLOAD);
          return false;
        }
        // Longest suffix that is a proper prefix of the sentinel stays held —
        // the next delta may complete it. Everything before it ships.
        let hold = 0;
        for (let k = Math.min(CRISIS_SENTINEL.length - 1, combined.length); k > 0; k -= 1) {
          if (combined.endsWith(CRISIS_SENTINEL.slice(0, k))) {
            hold = k;
            break;
          }
        }
        heldTail = hold ? combined.slice(combined.length - hold) : '';
        const ship = hold ? combined.slice(0, combined.length - hold) : combined;
        if (ship) {
          replyText += ship;
          await send('ink_delta', { text: ship });
        }
        return true;
      };

      /**
       * The stream ended while the scanner was still holding a tail. The tail
       * is by construction a strict prefix of the sentinel; if it got as far
       * as the opening brackets, the model was mid-sentinel when the stream
       * died, and safety fails CLOSED — the card, not a garbled "[[CRIS"
       * fragment. Anything shorter is flushed as ordinary ink.
       */
      const flushInk = async () => {
        if (crisisServed || !heldTail) return;
        if (heldTail.startsWith('[[')) {
          crisisServed = true;
          await send('crisis', CRISIS_PAYLOAD);
          return;
        }
        const held = heldTail;
        heldTail = '';
        replyText += held;
        await send('ink_delta', { text: held });
      };

      const t0 = Date.now();
      const usage = { inputTokens: 0, outputTokens: 0 };
      const provider = textProviderFor(book);
      let servedModel = `echo(${book.models.text})`;
      let iterator = null;
      let firstDelta = null;

      // -- provider handshake ------------------------------------------------
      // The 200 + text/event-stream headers used to be written BEFORE the
      // provider ran, so every upstream failure — a content-policy block, an
      // expired key, a 429, a 503 — was flattened into one soft sentence and a
      // normal `done`. Pulling the first token first means a pre-stream
      // failure can still answer with a real status the client can act on.
      if (provider) {
        servedModel = book.models.text;
        try {
          iterator = provider({
            system: composeSystemPrompt(book, request.body?.context),
            imageBase64: snapshotBase64,
            imageMime: snapshotMime,
            signal: abort.signal,
            usage,
          })[Symbol.asyncIterator]();
          const first = await iterator.next();
          firstDelta = first.done ? null : first.value;
        } catch (error) {
          cleanup();
          await resolveHold('release'); // nothing was generated; never charge
          await refundQuota(); // and never count it against the day
          const { status, code } = statusForProviderError(error);
          request.log?.warn?.({
            route: 'exchange',
            book: book.id,
            stage: 'handshake',
            status,
            error: String(error),
          });
          if (status === 429) reply.header('retry-after', '30');
          return reply.code(status).send({ error: code });
        }
      }

      // -- committed ---------------------------------------------------------
      // Past this point bytes are on the wire and no status can change, so
      // failures degrade in-fiction.
      channel.open();

      try {
        if (iterator) {
          let flowing = true;
          if (firstDelta) flowing = await sendInk(firstDelta);
          try {
            while (flowing && !abort.signal.aborted && !channel.clientGone) {
              const next = await iterator.next();
              if (next.done) break;
              flowing = await sendInk(next.value);
            }
          } catch (error) {
            request.log?.warn?.({ route: 'exchange', book: book.id, error: String(error) });
            if (!channel.clientGone && !crisisServed) {
              await flushInk(); // may fail closed into a crisis event
              if (!crisisServed) {
                await send('ink_delta', { text: 'The ink hesitates — ask again in a moment. ' });
              }
            }
          } finally {
            // Closing the generator is what actually cancels the upstream read
            // — on a crisis, that discards the rest of the model's text.
            await iterator.return?.().catch?.(() => {});
          }
          await flushInk();
        } else {
          // Echo mode: stream word-by-word so streaming-first is real from day one.
          for (const word of ECHO_REPLY.split(' ')) {
            if (abort.signal.aborted || channel.clientGone) break;
            await send('ink_delta', { text: `${word} ` });
            if (echoDelayMS > 0) await sleep(echoDelayMS);
          }
        }

        // -- independent crisis screen, reply side (audit S-2) ---------------
        // Runs over the assembled reply on every exchange, whatever the model
        // did with the sentinel. A reply that mirrors the writer's crisis in
        // plain words trips this even from a model that never self-reports;
        // the client buffers the reply and reveals nothing before `.answered`,
        // so the card still preempts everything. The sentinel stays the fast
        // path — this is the layer a regression cannot remove.
        if (!crisisServed && !channel.clientGone && textSignalsCrisis(replyText)) {
          crisisServed = true;
          await send('crisis', CRISIS_PAYLOAD);
          request.log?.info?.({ route: 'exchange', book: book.id, crisis: true, screen: 'reply' });
        }

        // Develop pass (Artist): the sketch itself is the image input; the
        // finished picture must land BEFORE `done` — done ends the exchange.
        // A failed develop never fails the exchange; the ink already answered,
        // but the intent MUST be resolved either way or the client keeps an
        // empty plate forever. A crisis preempts the develop entirely: the
        // client is tearing the fiction down, so no image should follow.
        let developedURL = null;
        if (willDevelop && !crisisServed && !channel.clientGone && !abort.signal.aborted) {
          const imageID = randomUUID();
          await send('image_intent', { id: imageID, expectsPreview: false });
          try {
            // The prompt is grounded in what the Book just said it saw, so
            // each develop paints THIS page — one static style line painted
            // the same picture over and over. A typed page is words, not a
            // sketch: img2img on a picture of words repaints the words, so
            // those develop from the description alone (no image input).
            const typedPage = request.body?.typed === true;
            const url = await imageProvider({
              prompt: developPrompt(book, replyText, { typed: typedPage }),
              imageBase64: typedPage ? null : snapshotBase64,
              imageMime: typedPage ? null : snapshotMime,
              signal: abort.signal,
            });
            if (url) {
              developedURL = url;
              await send('image_final', { id: imageID, url });
            } else {
              await send('image_error', { id: imageID, reason: 'no_image' });
            }
          } catch (error) {
            request.log?.warn?.({
              route: 'exchange',
              book: book.id,
              stage: 'develop',
              error: String(error),
            });
            await send('image_error', { id: imageID, reason: 'develop_failed' });
          }
        }

        // -- convertibility verdict (task J2) --------------------------------
        // Advisory data on the completed reply: is this a scene with visual
        // life? Emitted only when positive — absence means no, so the client's
        // default and every older client agree with the bias toward not
        // offering. Never on a crisis, never below the length floor (a
        // two-word riddle costs no classifier call), and never when the video
        // path couldn't actually generate — an affordance that can't deliver
        // is worse than none.
        const assess =
          book.flags.video && videoProviderFor(book) && !crisisServed && !channel.clientGone
            ? verdictFor(book)
            : null;
        if (assess && replyText.trim().length >= LIMITS.minConvertibleReplyChars) {
          try {
            const verdictTimeout = AbortSignal.timeout(10_000);
            const verdict = await assess({
              replyText,
              signal: AbortSignal.any([abort.signal, verdictTimeout]),
              usage,
            });
            if (verdict.convertible && !channel.clientGone) {
              const created = await stores.createBrief(request.userID, {
                bookID: book.id,
                brief: verdict.brief,
                // The Artist path animates the picture it just developed.
                imageURL: developedURL,
              });
              await send('verdict', { convertible: true, briefID: created.id, expiresAt: created.expiresAt });
            }
          } catch (error) {
            // A verdict failure is a STILL, never a failed exchange.
            request.log?.warn?.({ route: 'exchange', book: book.id, stage: 'verdict', error: String(error) });
          }
        }

        if (!channel.clientGone) {
          await send('done', {
            modelID: servedModel,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
          });
        }
        // A disconnect is not a delivered moment: refund rather than charge.
        // A crisis is never charged either — the writer got a safety card,
        // not the moment they paid for. The daily quota follows the hold.
        if (channel.clientGone || crisisServed) {
          await resolveHold('release');
          await refundQuota();
        } else {
          await resolveHold('settle');
        }
      } catch (error) {
        request.log?.error?.({ route: 'exchange', book: book.id, error: String(error) });
        await resolveHold('release');
        await refundQuota();
      } finally {
        cleanup();
        // Structured cost log per exchange → the 30%-of-sub guardrail job.
        // `model` is the model actually SERVED (echo mode says so), and the
        // token counts are the providers' own — they used to be literal zeros,
        // so the guardrail summed a column of nothing.
        const tokens = usage.inputTokens + usage.outputTokens;
        request.log?.info?.({
          route: 'exchange',
          book: book.id,
          model: servedModel,
          input_tokens: usage.inputTokens,
          output_tokens: usage.outputTokens,
          tokens,
          unit_cost: priceFor(servedModel, usage),
          credits_spent: channel.clientGone || crisisServed ? 0 : cost,
          developed: willDevelop && !crisisServed,
          crisis: crisisServed,
          client_gone: channel.clientGone,
          duration_ms: Date.now() - t0,
        });
        channel.end();
      }
    },
  );

  // -- POST /v1/video: a moving picture, only ever user-triggered (Epic J) ---
  // Tap → reserve → provider → bloom → settle; any failure at any stage
  // releases the reservation, and a client that vanishes mid-generation gets
  // its credit back (kill the app, the vial returns). Payment prefers the two
  // lifetime free clips (task J8) and falls back to the wallet; the response
  // is SSE so the minutes-long generation can heartbeat instead of timing out.
  app.post('/v1/video', { schema: videoSchema }, async (request, reply) => {
    const { briefID, videoID } = request.body;
    if (
      !(await withinLimits(
        request,
        reply,
        CONFIG.rateLimits.videosPerUserPerMinute,
        CONFIG.rateLimits.videosPerIPPerMinute,
      ))
    ) {
      return reply;
    }

    // Only a brief the Book actually produced can be animated — the client
    // never supplies prompt text, so there is no free-form generation surface.
    const brief = await stores.getBrief(briefID, request.userID);
    if (!brief) return reply.code(404).send({ error: 'unknown_brief' });
    const book = findBook(brief.bookID);
    if (!book || !book.flags.enabled || !book.flags.video) {
      return reply.code(503).send({ error: 'video_resting' });
    }
    const videoProvider = videoProviderFor(book);
    if (!videoProvider) return reply.code(503).send({ error: 'video_resting' });

    // Strictest tier (task J7): with no moderator bound, nothing generates.
    if (!moderatePrompt) {
      request.log?.error?.({ route: 'video', book: book.id, error: 'no_moderator_bound' });
      return reply.code(503).send({ error: 'video_resting' });
    }
    const prompt = composeVideoPrompt(brief.brief);
    try {
      const verdict = await moderatePrompt(prompt, {
        // The Artist animates the picture it just developed — the image IS
        // the subject, and a brief describing it can be entirely innocuous.
        imageURL: brief.imageURL ?? null,
        // A hung moderation socket would otherwise hold the request open for
        // the client's whole patience; nothing is reserved yet, so this is
        // liveness rather than money.
        signal: AbortSignal.timeout(15_000),
      });
      if (verdict.flagged) {
        // Nothing was reserved yet, so there is nothing to refund. Every
        // rejection is logged with its reason — the real failure rate has to
        // replace the 8% assumption in credits.md §2.
        request.log?.warn?.({
          route: 'video',
          book: book.id,
          stage: 'moderation',
          reject_reason: verdict.reason ?? 'flagged',
        });
        return reply.code(422).send({ error: 'moderated' });
      }
    } catch (error) {
      const { status, code } = statusForProviderError(error);
      request.log?.warn?.({ route: 'video', book: book.id, stage: 'moderation', error: String(error) });
      if (status === 429) reply.header('retry-after', '30');
      return reply.code(status).send({ error: code });
    }

    // Idempotency (task J4): one videoID, one generation. A double-tap or a
    // network retry lands on the claim — a delivered clip replays free of
    // charge, an in-flight one answers 409, and only an explicit failure
    // reopens the id.
    const claim = await stores.claimVideoJob(request.userID, videoID);
    if (claim.inFlight) {
      return reply.code(409).header('retry-after', '5').send({ error: 'video_in_flight' });
    }

    const clipCost = CONFIG.exchangeCosts.video ?? 0;
    let payment = null; // { kind: 'free', holdID } | { kind: 'credit', reservationID }
    if (!claim.delivered && clipCost > 0) {
      // The address rides along: free clips are per token, and a token costs
      // nothing to mint under anonymous attestation (task J10).
      const free = await stores.reserveFreeClip(request.userID, {
        ipKey: keyPart(request.ip),
      });
      if (free.holdID) {
        payment = { kind: 'free', holdID: free.holdID };
      } else if (free.error === 'free_ceiling') {
        // The global monthly ceiling closed the free path (task J8). A wallet
        // credit still spends; without one this fails closed IN FICTION —
        // "the ink must rest" — never as an error card.
        const held = await stores.reserve(request.userID, clipCost);
        if (held.reservationID) {
          payment = { kind: 'credit', reservationID: held.reservationID };
        } else {
          await stores.failVideoJob(request.userID, videoID);
          return reply.code(429).header('retry-after', '3600').send({ error: 'ink_must_rest' });
        }
      } else {
        const held = await stores.reserve(request.userID, clipCost);
        if (held.reservationID) {
          payment = { kind: 'credit', reservationID: held.reservationID };
        } else if (held.error === 'insufficient_credits') {
          // Both free clips spent and the wallet is empty — the vials.
          await stores.failVideoJob(request.userID, videoID);
          return reply.code(402).send(held);
        } else {
          await stores.failVideoJob(request.userID, videoID);
          return reply.code(409).send(held);
        }
      }
    }

    /** Exactly-once resolution of whichever hold was taken. */
    const resolvePayment = async (outcome) => {
      if (!payment) return;
      const held = payment;
      payment = null;
      const idKey = held.kind === 'free' ? held.holdID : held.reservationID;
      try {
        await stores.idempotent(request.userID, `${outcome}:video:${idKey}`, () => {
          if (held.kind === 'free') {
            return outcome === 'settle'
              ? stores.settleFreeClip(request.userID, held.holdID)
              : stores.releaseFreeClip(request.userID, held.holdID);
          }
          return outcome === 'settle'
            ? stores.settle(request.userID, held.reservationID)
            : stores.release(request.userID, held.reservationID);
        });
      } catch (error) {
        request.log?.error?.({ route: 'video', stage: outcome, error: String(error) });
      }
    };

    const paymentKind = claim.delivered ? 'replay' : payment?.kind ?? 'unmetered';
    const t0 = Date.now();
    const seconds = CONFIG.video.clipSeconds;
    let outcome = 'failed';
    let generated = false;
    let rejectReason = null;

    // Everything past the hold lives inside the try, including opening the
    // stream: a hold taken outside it has no resolver if anything between the
    // reserve and the first `await` throws. The stale-hold reclaim would catch
    // that eventually, but "eventually" is 30 minutes of a credit the reader
    // can see is missing.
    let channel;
    try {
      channel = createStreamChannel(reply, {
        deadlineMS: videoStreamDeadlineMS,
        heartbeatMS,
      });
      channel.open();
      await channel.send('video_intent', { id: videoID });

      let url = claim.delivered ? claim.url : null;
      if (!url) {
        generated = true;
        url = await videoProvider({
          prompt,
          imageURL: brief.imageURL ?? null,
          seconds,
          signal: channel.abort.signal,
        });
      }

      if (channel.clientGone) {
        // The reader left mid-generation: never charge for a clip delivered
        // to nobody. The claim reopens so a relaunch can ask again.
        await resolvePayment('release');
        await stores.failVideoJob(request.userID, videoID);
        outcome = 'client_gone';
      } else {
        await channel.send('video_final', { id: videoID, url });
        await resolvePayment('settle');
        await stores.completeVideoJob(request.userID, videoID, url);
        await channel.send('done', { modelID: book.models.video, inputTokens: 0, outputTokens: 0 });
        outcome = claim.delivered ? 'replayed' : 'delivered';
      }
    } catch (error) {
      // A flagged output is never shown and ALWAYS refunds (task J7); so does
      // every other failure — the user never pays for a clip that didn't
      // arrive, even though we already paid fal for the attempt.
      await resolvePayment('release');
      await stores.failVideoJob(request.userID, videoID);
      const moderated = error instanceof ProviderError && error.kind === 'moderated';
      rejectReason = moderated ? `output_moderated:${error.detail ?? ''}` : String(error?.message ?? error);
      // A reader who walked away is not a failed clip. Counting the abort as a
      // failure would inflate the very number this log exists to measure —
      // the real failure rate that replaces the 8% assumption in credits.md §2.
      if (channel?.clientGone) {
        outcome = 'client_gone';
      } else {
        outcome = moderated ? 'moderated' : 'failed';
        await channel?.send('video_error', {
          id: videoID,
          reason: moderated ? 'moderated' : 'unavailable',
        });
      }
    } finally {
      channel?.cleanup();
      // Cost per clip (task J1): fal bills per second of clip, not per token,
      // so this rides its own rate card (INK_VIDEO_PRICING). Failures cost us
      // too — the attempt is logged either way, with its reason, so the real
      // failure rate can replace the 8% assumption in credits.md §2.
      request.log?.info?.({
        route: 'video',
        book: book.id,
        model: book.models.video,
        clip_seconds: seconds,
        unit_cost: generated ? priceForClip(book.models.video, seconds) : 0,
        payment_kind: paymentKind,
        outcome,
        reject_reason: rejectReason,
        client_gone: Boolean(channel?.clientGone),
        duration_ms: Date.now() - t0,
      });
      channel?.end();
    }
  });

  // -- credit wallet: idempotency keys required on mutations -----------------
  /** Shared preamble: rate limit, then the Idempotency-Key. */
  async function creditPreamble(request, reply) {
    if (!(await withinLimits(request, reply, CONFIG.rateLimits.creditOpsPerUserPerMinute, CONFIG.rateLimits.exchangesPerIPPerMinute))) {
      return null;
    }
    const key = request.headers['idempotency-key'];
    if (!key || typeof key !== 'string' || key.length > 200) {
      await reply.code(400).send({ error: 'missing_idempotency_key' });
      return null;
    }
    return key;
  }

  /** Maps a wallet outcome onto a status. */
  function walletReply(reply, result) {
    if (result.error === 'insufficient_credits') return reply.code(402).send(result);
    if (result.error === 'invalid_amount') return reply.code(400).send(result);
    if (result.error === 'idempotency_in_flight') {
      return reply.code(409).header('retry-after', '1').send(result);
    }
    if (result.error) return reply.code(409).send(result);
    return result;
  }

  app.post('/v1/credits/reserve', { schema: reserveSchema }, async (request, reply) => {
    const key = await creditPreamble(request, reply);
    if (!key) return reply;
    // The schema already rejects <1, non-integer and >max; stores.reserve
    // re-checks, because `amount: -100` used to sail past `available < amount`
    // and MINT credits when settle() pushed -amount into the ledger.
    const amount = request.body?.amount ?? 1;
    const result = await stores.idempotent(request.userID, `reserve:${key}`, () =>
      stores.reserve(request.userID, amount),
    );
    return walletReply(reply, result);
  });

  app.post('/v1/credits/settle', { schema: reservationSchema }, async (request, reply) => {
    const key = await creditPreamble(request, reply);
    if (!key) return reply;
    const { reservationID } = request.body ?? {};
    const result = await stores.idempotent(request.userID, `settle:${key}`, () =>
      stores.settle(request.userID, reservationID),
    );
    return walletReply(reply, result);
  });

  app.post('/v1/credits/release', { schema: reservationSchema }, async (request, reply) => {
    const key = await creditPreamble(request, reply);
    if (!key) return reply;
    const { reservationID } = request.body ?? {};
    const result = await stores.idempotent(request.userID, `release:${key}`, () =>
      stores.release(request.userID, reservationID),
    );
    return walletReply(reply, result);
  });

  app.get('/v1/credits', async (request, reply) => {
    if (!(await withinLimits(request, reply, CONFIG.rateLimits.creditOpsPerUserPerMinute, CONFIG.rateLimits.exchangesPerIPPerMinute))) {
      return reply;
    }
    // Read-only: this used to SEED a wallet, so rotating the token and reading
    // minted an onboarding grant per rotation. Free clips ride along so the
    // affordance can say honestly what a tap will spend (task J3).
    const wallet = await stores.walletView(request.userID);
    const freeClips = await stores.freeClipView(request.userID);
    return {
      ...wallet,
      freeClipsRemaining: freeClips.remaining,
      freeClipsOpen: freeClips.ceilingOpen,
    };
  });

  // -- App Attest (audit T3/M-3) ---------------------------------------------
  // Identity stops being "whatever string the client typed": a device proves
  // itself once (challenge → attestation → server-minted identity → session
  // token) and renews by assertion. All three routes fail closed to 501
  // until the operator supplies the App Attest root, team/bundle ids and the
  // session secret (appattest.js).

  /** Per-IP ceiling for the pre-identity routes. */
  async function withinAttestLimits(request, reply) {
    const allowed = await stores.allow(
      `ip:${keyPart(request.ip)}`,
      CONFIG.rateLimits.attestsPerIPPerMinute,
    );
    if (!allowed) {
      await reply.code(429).header('retry-after', '60').send({ error: 'rate_limited' });
      return false;
    }
    return true;
  }

  app.post('/v1/attest/challenge', async (request, reply) => {
    if (!appAttest || !sessionTokens) {
      return reply.code(501).send({ error: 'attestation_unbound' });
    }
    if (!(await withinAttestLimits(request, reply))) return reply;
    // One-time, five minutes, server-chosen: the nonce the attestation must
    // answer can never be client-picked or replayed.
    const challenge = await stores.issueChallenge();
    return { challenge };
  });

  app.post('/v1/attest', { schema: attestSchema }, async (request, reply) => {
    if (!appAttest || !sessionTokens) {
      return reply.code(501).send({ error: 'attestation_unbound' });
    }
    if (!(await withinAttestLimits(request, reply))) return reply;
    const { keyID, attestation, challenge } = request.body;
    if (!(await stores.takeChallenge(challenge))) {
      return reply.code(401).send({ error: 'bad_challenge' });
    }
    let verified;
    try {
      verified = appAttest.verifyAttestation({
        attestationBase64: attestation,
        keyIDBase64: keyID,
        challenge: Buffer.from(challenge, 'base64'),
      });
    } catch (error) {
      const code = error instanceof AppAttestError ? error.code : 'attestation_rejected';
      request.log?.warn?.({ route: 'attest', reject: code });
      return reply.code(401).send({ error: 'attestation_rejected' });
    }
    // The identity is MINTED here; re-attesting a known key finds the same
    // one, so a reinstall keeps its wallet.
    const { userID } = await stores.registerAttestKey(keyID, verified.publicKeyPEM);
    const minted = sessionTokens.mint(userID);
    request.log?.info?.({ route: 'attest', registered: true });
    return { token: minted.token, expiresAt: new Date(minted.expiresAt).toISOString() };
  });

  app.post('/v1/attest/refresh', { schema: assertSchema }, async (request, reply) => {
    if (!appAttest || !sessionTokens) {
      return reply.code(501).send({ error: 'attestation_unbound' });
    }
    if (!(await withinAttestLimits(request, reply))) return reply;
    const { keyID, assertion, challenge } = request.body;
    const record = await stores.attestKeyRecord(keyID);
    if (!record) return reply.code(401).send({ error: 'unknown_key' });
    if (!(await stores.takeChallenge(challenge))) {
      return reply.code(401).send({ error: 'bad_challenge' });
    }
    let verified;
    try {
      verified = appAttest.verifyAssertion({
        assertionBase64: assertion,
        publicKeyPEM: record.publicKeyPEM,
        previousCounter: record.counter,
        challenge: Buffer.from(challenge, 'base64'),
      });
    } catch (error) {
      const code = error instanceof AppAttestError ? error.code : 'assertion_rejected';
      request.log?.warn?.({ route: 'attest_refresh', reject: code });
      return reply.code(401).send({ error: 'assertion_rejected' });
    }
    await stores.bumpAttestCounter(keyID, verified.counter);
    const minted = sessionTokens.mint(record.userID);
    return { token: minted.token, expiresAt: new Date(minted.expiresAt).toISOString() };
  });

  // -- POST /v1/entitlement: a verified Plus receipt widens the daily quota --
  //
  // The server cannot see StoreKit, so without this every identity meters as
  // free (audit M-2). The client posts its subscription JWS after purchase,
  // restore and every entitlement refresh; verification is the same
  // cryptography as the vial grant, and the record expires with the receipt —
  // a lapsed subscription demotes itself. Failure here never blocks the app:
  // the client's own gate still runs, this only widens the server backstop.
  app.post(
    '/v1/entitlement',
    { schema: entitlementSchema, bodyLimit: LIMITS.grantBodyLimit },
    async (request, reply) => {
      if (!(await withinLimits(request, reply, CONFIG.rateLimits.creditOpsPerUserPerMinute, CONFIG.rateLimits.exchangesPerIPPerMinute))) {
        return reply;
      }
      if (!verifyReceipt) {
        request.log?.error?.({ route: 'entitlement', error: 'receipt_verification_unbound' });
        return reply.code(501).send({ error: 'receipt_verification_unbound' });
      }
      const { productID, transactionID, jws } = request.body;
      if (!PLUS_PRODUCTS.has(productID)) {
        return reply.code(400).send({ error: 'unknown_product' });
      }

      let claims;
      try {
        claims = verifyReceipt(jws);
      } catch (error) {
        const code = error instanceof ReceiptError ? error.code : 'invalid_receipt';
        request.log?.warn?.({ route: 'entitlement', product: productID, reject: code });
        return reply.code(400).send({ error: 'invalid_receipt' });
      }
      if (claims.productId !== productID || String(claims.transactionId) !== transactionID) {
        return reply.code(400).send({ error: 'invalid_receipt' });
      }
      if (claims.revocationDate || claims.revocationReason !== undefined) {
        return reply.code(400).send({ error: 'revoked_receipt' });
      }
      // A subscription proves Plus only while it runs; a receipt with no
      // expiry is not a subscription receipt.
      const expiresAt = Number(claims.expiresDate);
      if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
        return reply.code(400).send({ error: 'expired_receipt' });
      }

      // The original transaction id is what a REFUND/REVOKE notification
      // will name (audit M-4) — bind it so the tier can be found and dropped.
      const result = await stores.setTier(
        request.userID,
        'plus',
        expiresAt,
        claims.originalTransactionId ?? claims.transactionId,
      );
      if (result.error) return reply.code(400).send({ error: 'expired_receipt' });
      request.log?.info?.({ route: 'entitlement', product: productID });
      return { tier: 'plus', expiresAt: new Date(expiresAt).toISOString() };
    },
  );

  // -- POST /v1/notifications: App Store Server Notifications V2 (audit M-4) -
  //
  // Before this route existed the proxy was never told about a refund: a
  // user could buy 20 vials, spend them on real provider compute, refund
  // through Apple, and the wallet was untouched — repeatable. Apple signs
  // the envelope; verification against the pinned root IS the
  // authentication, so the route skips the user-token hook. Answer 2xx
  // fast on everything understood — Apple retries non-2xx with backoff.
  app.post('/v1/notifications', { bodyLimit: LIMITS.grantBodyLimit }, async (request, reply) => {
    if (!verifyNotification || !verifyReceipt) {
      request.log?.error?.({ route: 'notifications', error: 'verification_unbound' });
      return reply.code(501).send({ error: 'verification_unbound' });
    }
    const signedPayload = request.body?.signedPayload;
    if (typeof signedPayload !== 'string' || !signedPayload) {
      return reply.code(400).send({ error: 'missing_payload' });
    }

    let envelope;
    try {
      envelope = verifyNotification(signedPayload);
    } catch (error) {
      const code = error instanceof ReceiptError ? error.code : 'invalid_notification';
      request.log?.warn?.({ route: 'notifications', reject: code });
      return reply.code(401).send({ error: 'invalid_notification' });
    }

    const type = envelope.notificationType;
    if (type !== 'REFUND' && type !== 'REVOKE') {
      // Renewals and expiry need nothing here: the tier record carries the
      // receipt's own expiry, and the client re-proves on refresh.
      request.log?.info?.({ route: 'notifications', type, acted: false });
      return { received: true };
    }

    let txn;
    try {
      txn = verifyReceipt(envelope.data?.signedTransactionInfo);
    } catch (error) {
      const code = error instanceof ReceiptError ? error.code : 'invalid_transaction';
      request.log?.warn?.({ route: 'notifications', type, reject: code });
      return reply.code(401).send({ error: 'invalid_notification' });
    }

    const productID = txn.productId;
    const transactionID = String(txn.transactionId);
    if (VIAL_GRANTS[productID]) {
      // A refunded consumable claws its credits back from whoever redeemed
      // it. Idempotent by key so Apple's retries debit exactly once.
      const owner = await stores.transactionOwner(transactionID);
      if (owner) {
        const result = await stores.idempotent(owner, `refund:${transactionID}`, () =>
          stores.revoke(owner, VIAL_GRANTS[productID], 'refund'),
        );
        request.log?.info?.({
          route: 'notifications', type, product: productID,
          debited: result?.revoked ?? 0,
        });
      } else {
        // Never redeemed here — nothing was granted, nothing to claw back.
        request.log?.info?.({ route: 'notifications', type, product: productID, debited: 0 });
      }
    } else if (PLUS_PRODUCTS.has(productID)) {
      const cleared = await stores.clearTierByTransaction(
        txn.originalTransactionId ?? txn.transactionId,
      );
      request.log?.info?.({
        route: 'notifications', type, product: productID, tierCleared: Boolean(cleared),
      });
    } else {
      request.log?.warn?.({ route: 'notifications', type, product: productID, acted: false });
    }
    return { received: true };
  });

  // -- POST /v1/credits/grant: a verified vial purchase reaches the ledger ---
  //
  // The receipt is verified HERE, cryptographically, against Apple's root
  // (receipts.js). It is not enough that StoreKit verified it on device: the
  // device is whatever speaks HTTP, and credits buy clips that cost real money
  // — an unverified grant is a mint. With no trust anchor configured the route
  // FAILS CLOSED rather than trusting the claims.
  //
  // The amount always comes from the server-side product map, never the body,
  // and the transaction id is the idempotency key, so a replayed receipt
  // credits exactly once.
  app.post(
    '/v1/credits/grant',
    { schema: grantSchema, bodyLimit: LIMITS.grantBodyLimit },
    async (request, reply) => {
      if (!(await withinLimits(request, reply, CONFIG.rateLimits.creditOpsPerUserPerMinute, CONFIG.rateLimits.exchangesPerIPPerMinute))) {
        return reply;
      }
      if (!verifyReceipt) {
        request.log?.error?.({ route: 'grant', error: 'receipt_verification_unbound' });
        return reply.code(501).send({ error: 'receipt_verification_unbound' });
      }
      const { productID, transactionID, jws } = request.body;
      const amount = VIAL_GRANTS[productID];
      if (!amount) return reply.code(400).send({ error: 'unknown_product' });

      let claims;
      try {
        claims = verifyReceipt(jws);
      } catch (error) {
        const code = error instanceof ReceiptError ? error.code : 'invalid_receipt';
        request.log?.warn?.({ route: 'grant', product: productID, reject: code });
        return reply.code(400).send({ error: 'invalid_receipt' });
      }
      // The signed claims are the authority; the body only says which of them
      // the caller believes it is presenting, and must agree.
      if (claims.productId !== productID || String(claims.transactionId) !== transactionID) {
        return reply.code(400).send({ error: 'invalid_receipt' });
      }
      // A refunded or revoked transaction buys nothing.
      if (claims.revocationDate || claims.revocationReason !== undefined) {
        return reply.code(400).send({ error: 'revoked_receipt' });
      }

      // GLOBAL redemption claim (audit M-1): the per-user idempotency below
      // keys as `${userID}:grant:${txn}`, so on its own a captured receipt
      // replayed under rotated identities credited every one of them. The
      // claim binds the transaction to its first redeemer forever; the same
      // user passes through (honest double-tap, retry after a crash), anyone
      // else gets a distinct terminal error — this receipt is real, it is
      // just already spent.
      const claim = await stores.claimTransaction(transactionID, request.userID);
      if (claim.error) {
        request.log?.warn?.({ route: 'grant', product: productID, reject: claim.error });
        return reply.code(409).send({ error: claim.error });
      }

      const result = await stores.idempotent(request.userID, `grant:${transactionID}`, () =>
        stores.grant(request.userID, amount, 'purchase'),
      );
      if (result.error) return walletReply(reply, result);
      request.log?.info?.({ route: 'grant', product: productID, amount });
      return result;
    },
  );

  // -- POST /v1/report: user-triggered report of a reply (guideline 1.2) -----
  // A cold path, fully apart from the exchange machinery: the payload carries
  // the reported page's snapshot and reply, assembled client-side at the
  // moment the user taps send — never before. The snapshot pushes the body
  // past the 4KB default, so the route opts up the way /v1/exchange does.
  // The reportID doubles as the idempotency key: a double-tap files once.
  app.post(
    '/v1/report',
    { schema: reportSchema, bodyLimit: LIMITS.reportBodyLimit },
    async (request, reply) => {
      if (
        !(await withinLimits(
          request,
          reply,
          CONFIG.rateLimits.reportsPerUserPerMinute,
          CONFIG.rateLimits.reportsPerIPPerMinute,
        ))
      ) {
        return reply;
      }

      const body = request.body;
      // A reply is ink (text) or a developed asset; a report naming neither
      // carries nothing a reviewer could look at.
      const content = body.replyKind === 'ink' ? body.replyText : body.assetRef;
      if (!content) return reply.code(400).send({ error: 'invalid_report' });

      const snapshot = Buffer.from(body.snapshotBase64, 'base64');
      if (snapshot.length === 0) return reply.code(400).send({ error: 'missing_snapshot' });
      if (snapshot.length > LIMITS.maxSnapshotBytes) {
        return reply.code(413).send({ error: 'snapshot_too_large' });
      }
      if (!sniffImageMime(snapshot)) {
        return reply.code(415).send({ error: 'unsupported_snapshot' });
      }
      // Same integrity check as /v1/preupload: the digest the client committed
      // to must be the digest of the bytes that arrived.
      const actualDigest = createHash('sha256').update(snapshot).digest('hex');
      if (!digestMatches(body.snapshotDigest, actualDigest)) {
        return reply.code(400).send({ error: 'digest_mismatch' });
      }

      const result = await stores.idempotent(request.userID, `report:${body.reportID}`, () =>
        stores.fileReport(request.userID, body),
      );
      if (result.error) return reply.code(400).send(result);
      // A counter only: the report's content goes to the store, never the log.
      request.log?.info?.({ route: 'report', book: body.bookID, reason: body.reason });
      // A human hears about it (audit S-7). Fire-and-forget: the reporter's
      // ack never waits on the webhook, and a webhook failure is logged, not
      // surfaced — the report itself is already safely filed.
      if (notifyReport) {
        Promise.resolve()
          .then(async () =>
            notifyReport({
              reason: body.reason,
              bookID: body.bookID,
              openReports: await stores.reportCount(),
            }),
          )
          .catch((error) => {
            request.log?.warn?.({ route: 'report', stage: 'notify', error: String(error) });
          });
      }
      return result;
    },
  );

  // -- GET /v1/admin/reports: the triage reader (audit S-7) ------------------
  // Authenticated by the OPERATOR token, never a user identity, so it works
  // under `required` attestation. Fails closed when unconfigured. This is
  // where "this page goes to a human hand for review" becomes true: the
  // webhook says a report exists, this route shows it.
  app.get('/v1/admin/reports', async (request, reply) => {
    if (!adminToken) {
      return reply.code(501).send({ error: 'admin_unconfigured' });
    }
    const presented = request.headers['x-ink-admin'];
    if (
      typeof presented !== 'string' ||
      presented.length !== adminToken.length ||
      !timingSafeEqual(Buffer.from(presented), Buffer.from(adminToken))
    ) {
      return reply.code(401).send({ error: 'unauthorized' });
    }
    const reports = await stores.listReports();
    return { count: reports.length, reports };
  });

  return app;
}
