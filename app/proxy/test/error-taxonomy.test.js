// The SSE error taxonomy (§2) and stream lifecycle (§3).
//
// The 200 + text/event-stream headers used to be written before the provider
// ran, so a content-policy block, an expired key, a 429 and a 503 were all
// indistinguishable: HTTP 200, one soft sentence, `done`. The route now pulls
// the provider's first token BEFORE committing headers, so a pre-stream
// failure can still answer with a status the client can act on. Once a byte is
// on the wire the in-fiction degrade is the only honest ending — that half is
// covered in routing.test.js.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';
import { ProviderError } from '../src/models.js';
import { PNG_BASE64 } from './helpers.js';

const USER = { 'x-ink-user': 'user-1', 'content-type': 'application/json' };

function appThatFailsWith(error) {
  return build({
    textProviderFactory: () =>
      // eslint-disable-next-line require-yield
      async function* failing() {
        throw error;
      },
  });
}

async function exchange(app, payload = { bookID: 'oracle' }) {
  return app.inject({ method: 'POST', url: '/v1/exchange', headers: USER, payload });
}

test('a pre-stream content block answers 422 moderated, not a 200 stream', async () => {
  const app = appThatFailsWith(
    new ProviderError({ provider: 'gemini', kind: 'moderated', status: 400 }),
  );
  const res = await exchange(app);
  assert.equal(res.statusCode, 422);
  assert.equal(res.json().error, 'moderated');
  assert.doesNotMatch(res.headers['content-type'] ?? '', /event-stream/);
  assert.doesNotMatch(res.payload, /event: done/, 'a blocked exchange never reports done');
  await app.close();
});

test('a pre-stream upstream 429 answers 429 with retry-after', async () => {
  const app = appThatFailsWith(
    new ProviderError({ provider: 'gemini', kind: 'rate_limited', status: 429 }),
  );
  const res = await exchange(app);
  assert.equal(res.statusCode, 429);
  assert.equal(res.json().error, 'upstream_rate_limited');
  assert.equal(res.headers['retry-after'], '30');
  await app.close();
});

test('a pre-stream upstream outage answers 503 upstream_unavailable', async () => {
  const app = appThatFailsWith(
    new ProviderError({ provider: 'openai', kind: 'unavailable', status: 503 }),
  );
  const res = await exchange(app);
  assert.equal(res.statusCode, 503);
  assert.equal(res.json().error, 'upstream_unavailable');
  await app.close();
});

test('an unclassified pre-stream throw is 503, and never leaks the upstream text', async () => {
  const app = appThatFailsWith(new Error('sk-live-secret expired for project acme'));
  const res = await exchange(app);
  assert.equal(res.statusCode, 503);
  assert.equal(res.json().error, 'upstream_unavailable');
  assert.doesNotMatch(res.payload, /sk-live-secret/);
  await app.close();
});

test('the success wire format is unchanged: ink_delta first, done last', async () => {
  const app = build({
    textProviderFactory: () =>
      async function* fine() {
        yield 'Three ';
        yield 'of swords.';
      },
  });
  const res = await exchange(app);
  assert.equal(res.statusCode, 200);
  assert.match(res.headers['content-type'], /text\/event-stream/);
  assert.ok(res.payload.trimStart().startsWith('event: ink_delta'));
  const events = [...res.payload.matchAll(/^event: (\w+)$/gm)].map((m) => m[1]);
  assert.deepEqual(events, ['ink_delta', 'ink_delta', 'done']);
  await app.close();
});

test('heartbeats are SSE comments, so they never appear as events', async () => {
  const app = build({
    heartbeatMS: 5,
    textProviderFactory: () =>
      async function* slow() {
        yield 'a ';
        await new Promise((resolve) => setTimeout(resolve, 60));
        yield 'b';
      },
  });
  const res = await exchange(app);
  assert.equal(res.statusCode, 200);
  assert.match(res.payload, /^: ping$/m, 'a comment line kept the connection warm');
  const events = [...res.payload.matchAll(/^event: (\w+)$/gm)].map((m) => m[1]);
  assert.deepEqual(events, ['ink_delta', 'ink_delta', 'done']);
  await app.close();
});

test('the stream deadline aborts a runaway generation', async () => {
  let ticks = 0;
  const app = build({
    streamDeadlineMS: 40,
    textProviderFactory: () =>
      async function* endless({ signal }) {
        while (!signal.aborted) {
          ticks += 1;
          yield 'on ';
          await new Promise((resolve) => setTimeout(resolve, 5));
        }
      },
  });
  const res = await exchange(app);
  assert.equal(res.statusCode, 200);
  assert.ok(ticks > 0 && ticks < 200, `deadline stopped the generation after ${ticks} ticks`);
  await app.close();
});

test('a failed develop resolves its intent with image_error, never a dangling plate', async () => {
  const app = build({
    textProviderFactory: () =>
      async function* ink() {
        yield 'I see a fox.';
      },
    imageProviderFactory: () => async () => {
      throw new Error('fal 500');
    },
  });
  const res = await exchange(app, { bookID: 'artist', snapshotBase64: PNG_BASE64 });
  assert.equal(res.statusCode, 200);
  const events = [...res.payload.matchAll(/^event: (\w+)$/gm)].map((m) => m[1]);
  assert.deepEqual(events, ['ink_delta', 'image_intent', 'image_error', 'done']);
  assert.ok(events.indexOf('image_error') < events.indexOf('done'), 'resolved before done');
  await app.close();
});

test('a develop that resolves to no image also resolves the intent', async () => {
  const app = build({
    textProviderFactory: () =>
      async function* ink() {
        yield 'I see a fox.';
      },
    imageProviderFactory: () => async () => null,
  });
  const res = await exchange(app, { bookID: 'artist', snapshotBase64: PNG_BASE64 });
  const events = [...res.payload.matchAll(/^event: (\w+)$/gm)].map((m) => m[1]);
  assert.deepEqual(events, ['ink_delta', 'image_intent', 'image_error', 'done']);
  await app.close();
});

test('the done chunk carries the provider’s real token counts, not zeros', async () => {
  const app = build({
    textProviderFactory: () =>
      async function* counted({ usage }) {
        yield 'Three ';
        usage.inputTokens = 412;
        usage.outputTokens = 37;
      },
  });
  const res = await exchange(app);
  const done = JSON.parse(res.payload.match(/event: done\ndata: (.*)/)[1]);
  assert.equal(done.inputTokens, 412);
  assert.equal(done.outputTokens, 37);
  await app.close();
});
