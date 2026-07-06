import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

const USER = { 'x-ink-user': 'user-1' };

test('exchange streams SSE ink deltas and a done chunk (echo mode)', async () => {
  const app = build({ echoDelayMS: 0 });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: { ...USER, 'content-type': 'application/json' },
    payload: { bookID: 'oracle', digest: 'abc', context: {} },
  });

  assert.equal(res.statusCode, 200);
  assert.match(res.headers['content-type'], /text\/event-stream/);
  assert.match(res.payload, /event: ink_delta/);
  assert.match(res.payload, /event: done/);
  // Streaming-first: the very first event is ink, not a completed reply.
  assert.ok(res.payload.trimStart().startsWith('event: ink_delta'));
  await app.close();
});

test('unknown book → 404, missing auth → 401', async () => {
  const app = build({ echoDelayMS: 0 });
  const unknown = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: { ...USER, 'content-type': 'application/json' },
    payload: { bookID: 'necronomicon' },
  });
  assert.equal(unknown.statusCode, 404);

  const unauthed = await app.inject({ method: 'GET', url: '/v1/books' });
  assert.equal(unauthed.statusCode, 401);
  await app.close();
});

test('kill-switch: a disabled book answers 503 book_resting', async () => {
  const app = build({ echoDelayMS: 0 });
  const { BOOKS } = await import('../src/books.js');
  const oracle = BOOKS.find((b) => b.id === 'oracle');
  oracle.flags.enabled = false;
  try {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { ...USER, 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    assert.equal(res.statusCode, 503);
    assert.equal(res.json().error, 'book_resting');
  } finally {
    oracle.flags.enabled = true;
    await app.close();
  }
});

test('per-user rate limit answers 429 with retry-after', async () => {
  const app = build({ echoDelayMS: 0 });
  let limited;
  for (let i = 0; i < 35; i += 1) {
    limited = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { ...USER, 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    if (limited.statusCode === 429) break;
  }
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.headers['retry-after'], '60');
  await app.close();
});
