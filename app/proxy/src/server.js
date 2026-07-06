// Inkbound proxy (task A5). Endpoints per development.md §10. Echo mode is the
// build-order step-4 target: a real SSE exchange with no model keys, so the
// client pipeline (InkNet → assembler → renderers) runs end-to-end on device.
//
// Auth: anonymous user token in x-ink-user; App Attest assertion verification
// is a launch TODO on this same hook (Sign in with Apple upgrades the token).
import Fastify from 'fastify';
import { BOOKS, findBook, publicBook } from './books.js';
import { CONFIG } from './config.js';
import { createStores } from './stores.js';
import { createTextProviderFactory, composeSystemPrompt } from './models.js';

const ECHO_REPLY =
  'The page drinks your ink and stirs. Ask again when the real models are bound; for now this echo proves the stream.';

export function build(options = {}) {
  const app = Fastify({ logger: options.logger ?? false });
  const stores = createStores();
  const echoDelayMS = options.echoDelayMS ?? Number(process.env.ECHO_DELAY_MS ?? 40);
  const textProviderFor = options.textProviderFactory ?? createTextProviderFactory();

  app.decorate('stores', stores);

  // Speculative uploads arrive as raw snapshot bytes.
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (req, body, done) => {
    done(null, body);
  });

  // -- auth hook -------------------------------------------------------------
  app.addHook('onRequest', async (request, reply) => {
    const userID = request.headers['x-ink-user'];
    if (!userID || typeof userID !== 'string') {
      return reply.code(401).send({ error: 'missing_user_token' });
    }
    request.userID = userID;
  });

  // -- GET /v1/books: definitions minus prompts; kill-switches live here -----
  app.get('/v1/books', async () => ({ books: BOOKS.map(publicBook) }));

  // -- GET /v1/config: server-tunable knobs ----------------------------------
  app.get('/v1/config', async () => CONFIG);

  // -- speculative upload ----------------------------------------------------
  app.post('/v1/preupload', async (request, reply) => {
    const digest = request.headers['x-ink-digest'];
    if (!digest) return reply.code(400).send({ error: 'missing_digest' });
    return stores.createTicket(request.userID, digest);
  });

  app.delete('/v1/preupload/:id', async (request, reply) => {
    stores.deleteTicket(request.params.id, request.userID);
    // Aborting an unknown/expired ticket is fine — it was never billable.
    return reply.code(204).send();
  });

  // -- POST /v1/exchange: snapshot + book + context → SSE stream -------------
  app.post('/v1/exchange', async (request, reply) => {
    const { bookID, ticketID } = request.body ?? {};

    const book = findBook(bookID);
    if (!book) return reply.code(404).send({ error: 'unknown_book' });
    if (!book.flags.enabled) {
      // Kill-switch: the client renders this as the Book "resting."
      return reply.code(503).send({ error: 'book_resting' });
    }

    if (
      !stores.allow(`user:${request.userID}`, CONFIG.rateLimits.exchangesPerUserPerMinute) ||
      !stores.allow(`ip:${request.ip}`, CONFIG.rateLimits.exchangesPerIPPerMinute)
    ) {
      return reply.code(429).header('retry-after', '60').send({ error: 'rate_limited' });
    }

    // A committed ticket consumes the speculative upload; only now is the
    // exchange billable. Uncommitted tickets simply expire.
    if (ticketID) stores.takeTicket(ticketID, request.userID);

    reply.raw.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    });

    const send = (event, data) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    const t0 = Date.now();
    const provider = textProviderFor(book);
    let servedModel = `echo(${book.models.text})`;

    if (provider) {
      // Real routing: Book prompt + Plus memory injected server-side; the
      // snapshot travels as the user turn. TODO(F1/F2): crisis classifier in
      // parallel + moderation before image/video jobs.
      servedModel = book.models.text;
      try {
        const stream = provider({
          system: composeSystemPrompt(book, request.body?.context),
          imageBase64: request.body?.snapshotBase64,
        });
        for await (const delta of stream) {
          send('ink_delta', { text: delta });
        }
      } catch (error) {
        request.log?.warn?.({ route: 'exchange', book: book.id, error: String(error) });
        send('ink_delta', { text: 'The ink hesitates — ask again in a moment. ' });
      }
    } else {
      // Echo mode: stream word-by-word so streaming-first is real from day one.
      for (const word of ECHO_REPLY.split(' ')) {
        send('ink_delta', { text: `${word} ` });
        if (echoDelayMS > 0) await sleep(echoDelayMS);
      }
    }
    send('done', { modelID: servedModel, inputTokens: 0, outputTokens: 0 });

    // Structured cost log per exchange → the 30%-of-sub guardrail job.
    request.log?.info?.({
      route: 'exchange',
      book: book.id,
      model: book.models.text,
      tokens: 0,
      unit_cost: 0,
      duration_ms: Date.now() - t0,
    });

    reply.raw.end();
    return reply;
  });

  // -- credit wallet: idempotency keys required on mutations -----------------
  app.post('/v1/credits/reserve', async (request, reply) => {
    const key = request.headers['idempotency-key'];
    if (!key) return reply.code(400).send({ error: 'missing_idempotency_key' });
    const amount = request.body?.amount ?? 1;
    const result = stores.idempotent(request.userID, `reserve:${key}`, () =>
      stores.reserve(request.userID, amount),
    );
    if (result.error === 'insufficient_credits') return reply.code(402).send(result);
    return result;
  });

  app.post('/v1/credits/settle', async (request, reply) => {
    const key = request.headers['idempotency-key'];
    if (!key) return reply.code(400).send({ error: 'missing_idempotency_key' });
    const { reservationID } = request.body ?? {};
    const result = stores.idempotent(request.userID, `settle:${key}`, () =>
      stores.settle(request.userID, reservationID),
    );
    if (result.error) return reply.code(409).send(result);
    return result;
  });

  app.post('/v1/credits/release', async (request, reply) => {
    const key = request.headers['idempotency-key'];
    if (!key) return reply.code(400).send({ error: 'missing_idempotency_key' });
    const { reservationID } = request.body ?? {};
    const result = stores.idempotent(request.userID, `release:${key}`, () =>
      stores.release(request.userID, reservationID),
    );
    if (result.error) return reply.code(409).send(result);
    return result;
  });

  app.get('/v1/credits', async (request) => stores.walletView(request.userID));

  return app;
}
