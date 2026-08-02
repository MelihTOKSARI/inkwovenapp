// Inkwoven proxy (task A5). Endpoints per development.md §10. Echo mode is the
// build-order step-4 target: a real SSE exchange with no model keys, so the
// client pipeline (InkNet → assembler → renderers) runs end-to-end on device.
//
// Auth: the x-ink-user token is resolved to an identity by the verification
// seam in attest.js, which fails CLOSED — see that file for what a human must
// still supply before App Attest is real.
import Fastify from 'fastify';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { BOOKS, findBook, publicBook } from './books.js';
import { CONFIG, LIMITS, createPricing } from './config.js';
import { createStores } from './stores.js';
import { createAttestationVerifier, AttestationError } from './attest.js';
import { keyPart } from './keys.js';
import {
  createTextProviderFactory,
  createImageProviderFactory,
  composeSystemPrompt,
  sniffImageMime,
  sniffImageMimeBase64,
  ProviderError,
  CRISIS_SENTINEL,
  CRISIS_PAYLOAD,
} from './models.js';

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
  const stores = options.stores ?? createStores();
  const echoDelayMS = options.echoDelayMS ?? Number(process.env.ECHO_DELAY_MS ?? 40);
  const textProviderFor = options.textProviderFactory ?? createTextProviderFactory();
  const imageProviderFor = options.imageProviderFactory ?? createImageProviderFactory();
  const attestation = options.attestation ?? createAttestationVerifier(options.env ?? process.env);
  const priceFor = options.priceFor ?? createPricing(options.env ?? process.env);
  // Overridable so the tests can exercise the deadline and the heartbeat
  // without waiting out the production intervals.
  const streamDeadlineMS = options.streamDeadlineMS ?? LIMITS.streamDeadlineMS;
  const heartbeatMS = options.heartbeatMS ?? LIMITS.heartbeatIntervalMS;

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

  // -- auth hook -------------------------------------------------------------
  app.addHook('onRequest', async (request, reply) => {
    if (HEALTH_ROUTES.has(request.url.split('?')[0])) return;
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
      const cost =
        (CONFIG.exchangeCosts.ink ?? 0) + (willDevelop ? CONFIG.exchangeCosts.image ?? 0 : 0);

      let reservationID = null;
      if (cost > 0) {
        const held = await stores.reserve(request.userID, cost);
        if (held.error === 'insufficient_credits') {
          return reply.code(402).send(held);
        }
        if (held.error) return reply.code(409).send(held);
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
      // One controller per exchange, aborted by a client disconnect or by the
      // stream deadline. Without it a user swiping away left the upstream
      // generation running to completion at full cost, delivered to nobody.
      const abort = new AbortController();
      let clientGone = false;
      let heartbeat = null;
      const giveUp = () => {
        if (!clientGone) {
          clientGone = true;
          abort.abort();
        }
      };
      const deadline = setTimeout(giveUp, streamDeadlineMS);
      const cleanup = () => {
        clearTimeout(deadline);
        if (heartbeat) clearInterval(heartbeat);
      };
      // Writes to a socket the peer already dropped must never surface as an
      // unhandled 'error' event.
      reply.raw.on('error', giveUp);
      // The RESPONSE's 'close' is the reliable peer-went-away signal: the
      // request stream has already been consumed by the body parser by the
      // time a handler runs, so its own 'close' has usually fired and can
      // never be observed here. writableFinished separates a premature
      // disconnect from our own end().
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
        // between backpressure and queueing a whole generation in process
        // memory for a client that has stopped reading.
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
      const send = (event, data) => writeRaw(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

      // -- crisis gate -------------------------------------------------------
      // The safety override (models.js) makes the model OPEN with
      // CRISIS_SENTINEL when the writer's page reads as genuine self-harm
      // risk. The sentinel can arrive split across deltas, so ink is held
      // back until the head of the reply either provably is not the sentinel
      // (flush, stream normally) or completes it — then ONE `crisis` event
      // goes out and the rest of the generation is discarded. Only the very
      // start of the reply is checked; echo mode never passes through here.
      let crisisServed = false;
      let gateOpen = false; // once true, deltas stream straight through
      let gateHeld = '';

      /** Routes one ink delta through the gate. Returns false once the exchange must stop. */
      const sendInk = async (text) => {
        if (gateOpen) {
          await send('ink_delta', { text });
          return true;
        }
        gateHeld += text;
        const head = gateHeld.trimStart(); // models often lead with whitespace
        if (head.startsWith(CRISIS_SENTINEL)) {
          crisisServed = true;
          await send('crisis', CRISIS_PAYLOAD);
          return false;
        }
        if (CRISIS_SENTINEL.startsWith(head)) return true; // still ambiguous — keep holding
        gateOpen = true;
        const held = gateHeld;
        gateHeld = '';
        await send('ink_delta', { text: held });
        return true;
      };

      /**
       * The stream ended while the gate was still holding. A held head is by
       * construction a strict prefix of the sentinel; if it got as far as the
       * opening brackets, the model was mid-sentinel when the stream died, and
       * safety fails CLOSED — the card, not a garbled "[[CRIS" fragment.
       * Anything shorter is flushed as ordinary ink.
       */
      const flushInk = async () => {
        if (gateOpen || crisisServed || !gateHeld) return;
        if (gateHeld.trimStart().startsWith('[[')) {
          crisisServed = true;
          await send('crisis', CRISIS_PAYLOAD);
          return;
        }
        gateOpen = true;
        const held = gateHeld;
        gateHeld = '';
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
      // failures degrade in-fiction. hijack() hands the socket over
      // explicitly; without it Fastify still believes it owns the response.
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

      try {
        if (iterator) {
          let flowing = true;
          if (firstDelta) flowing = await sendInk(firstDelta);
          try {
            while (flowing && !abort.signal.aborted && !clientGone) {
              const next = await iterator.next();
              if (next.done) break;
              flowing = await sendInk(next.value);
            }
          } catch (error) {
            request.log?.warn?.({ route: 'exchange', book: book.id, error: String(error) });
            if (!clientGone && !crisisServed) {
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
            if (abort.signal.aborted || clientGone) break;
            await send('ink_delta', { text: `${word} ` });
            if (echoDelayMS > 0) await sleep(echoDelayMS);
          }
        }

        // Develop pass (Artist): the sketch itself is the image input; the
        // finished picture must land BEFORE `done` — done ends the exchange.
        // A failed develop never fails the exchange; the ink already answered,
        // but the intent MUST be resolved either way or the client keeps an
        // empty plate forever. A crisis preempts the develop entirely: the
        // client is tearing the fiction down, so no image should follow.
        if (willDevelop && !crisisServed && !clientGone && !abort.signal.aborted) {
          const imageID = randomUUID();
          await send('image_intent', { id: imageID, expectsPreview: false });
          try {
            const url = await imageProvider({
              prompt: book.imagePrompt,
              imageBase64: snapshotBase64,
              imageMime: snapshotMime,
              signal: abort.signal,
            });
            if (url) await send('image_final', { id: imageID, url });
            else await send('image_error', { id: imageID, reason: 'no_image' });
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

        if (!clientGone) {
          await send('done', {
            modelID: servedModel,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
          });
        }
        // A disconnect is not a delivered moment: refund rather than charge.
        // A crisis is never charged either — the writer got a safety card,
        // not the moment they paid for.
        await resolveHold(clientGone || crisisServed ? 'release' : 'settle');
      } catch (error) {
        request.log?.error?.({ route: 'exchange', book: book.id, error: String(error) });
        await resolveHold('release');
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
          credits_spent: clientGone || crisisServed ? 0 : cost,
          developed: willDevelop && !crisisServed,
          crisis: crisisServed,
          client_gone: clientGone,
          duration_ms: Date.now() - t0,
        });
        if (!reply.raw.writableEnded) reply.raw.end();
      }
    },
  );

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
    // minted an onboarding grant per rotation.
    return stores.walletView(request.userID);
  });

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
      return result;
    },
  );

  return app;
}
