// Client disconnect and server-authoritative metering, exercised against a
// REAL socket — app.inject() short-circuits the socket lifecycle, so it can
// never prove that dropping the connection stops the upstream generation.
// That gap is the whole cost leak: a user swiping away used to leave the
// provider generating to completion, billed, delivered to nobody.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { build } from '../src/server.js';
import { createStores } from '../src/stores.js';
import { CONFIG } from '../src/config.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Opens an exchange, reads until `afterMS`, then destroys the socket. */
function exchangeThenHangUp(port, payload, afterMS) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const req = http.request(
      {
        port,
        method: 'POST',
        path: '/v1/exchange',
        headers: {
          'x-ink-user': 'user-1',
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let received = '';
        res.on('data', (chunk) => {
          received += chunk;
        });
        setTimeout(() => {
          req.destroy();
          resolve({ status: res.statusCode, received });
        }, afterMS);
      },
    );
    req.on('error', () => {}); // the destroy we asked for
    req.setTimeout(5_000, () => reject(new Error('timeout')));
    req.end(body);
  });
}

test('a client disconnect aborts the upstream generation instead of burning it', async () => {
  let ticks = 0;
  const app = build({
    textProviderFactory: () =>
      async function* endless({ signal }) {
        while (!signal.aborted) {
          ticks += 1;
          yield 'on and ';
          await new Promise((resolve) => setTimeout(resolve, 20));
        }
      },
  });
  await app.listen({ port: 0, host: '127.0.0.1' });
  const { port } = app.server.address();

  const { status, received } = await exchangeThenHangUp(port, { bookID: 'oracle' }, 150);
  assert.equal(status, 200);
  assert.match(received, /event: ink_delta/);
  const atHangUp = ticks;

  // The old behaviour kept generating for the full reply after the socket
  // died; every one of those tokens was billed.
  await sleep(300);
  assert.ok(
    ticks - atHangUp <= 1,
    `generation stopped at the disconnect (${atHangUp} → ${ticks} ticks)`,
  );
  await app.close();
});

test('a disconnect releases the credit hold rather than settling it', async () => {
  const stores = createStores();
  const original = CONFIG.exchangeCosts.ink;
  CONFIG.exchangeCosts.ink = 1; // meter ink, so the exchange must hold a credit
  const app = build({
    stores,
    textProviderFactory: () =>
      async function* slow({ signal }) {
        while (!signal.aborted) {
          yield 'ink ';
          await new Promise((resolve) => setTimeout(resolve, 20));
        }
      },
  });
  try {
    await app.listen({ port: 0, host: '127.0.0.1' });
    await exchangeThenHangUp(app.server.address().port, { bookID: 'oracle' }, 120);
    await sleep(150);
    assert.deepEqual(
      await stores.walletView('user-1'),
      { balance: 1, available: 1 },
      'the hold was refunded, not spent, and no phantom hold remains',
    );
  } finally {
    CONFIG.exchangeCosts.ink = original;
    await app.close();
  }
});

test('a metered exchange reserves before generating and settles on success', async () => {
  const stores = createStores();
  const original = CONFIG.exchangeCosts.ink;
  CONFIG.exchangeCosts.ink = 1;
  const app = build({
    stores,
    textProviderFactory: () =>
      async function* fine() {
        yield 'Three of swords.';
      },
  });
  try {
    const spent = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { 'x-ink-user': 'user-1', 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    assert.equal(spent.statusCode, 200);
    assert.deepEqual(await stores.walletView('user-1'), { balance: 0, available: 0 });

    // Out of credits: the server refuses BEFORE any model is called, and the
    // refusal is a status, not a 200 stream.
    const broke = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { 'x-ink-user': 'user-1', 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    assert.equal(broke.statusCode, 402);
    assert.equal(broke.json().error, 'insufficient_credits');
  } finally {
    CONFIG.exchangeCosts.ink = original;
    await app.close();
  }
});

test('a pre-stream provider failure releases the hold — a blocked exchange is never charged', async () => {
  const stores = createStores();
  const original = CONFIG.exchangeCosts.ink;
  CONFIG.exchangeCosts.ink = 1;
  const app = build({
    stores,
    textProviderFactory: () =>
      // eslint-disable-next-line require-yield
      async function* broken() {
        throw new Error('upstream 500');
      },
  });
  try {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { 'x-ink-user': 'user-1', 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    assert.equal(res.statusCode, 503);
    assert.deepEqual(await stores.walletView('user-1'), { balance: 1, available: 1 });
  } finally {
    CONFIG.exchangeCosts.ink = original;
    await app.close();
  }
});

test('ink and images are unmetered by default, so today’s behaviour is unchanged', async () => {
  const stores = createStores();
  const app = build({ echoDelayMS: 0, stores });
  for (let i = 0; i < 3; i += 1) {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: { 'x-ink-user': 'user-1', 'content-type': 'application/json' },
      payload: { bookID: 'oracle' },
    });
    assert.equal(res.statusCode, 200);
  }
  assert.deepEqual(await stores.walletView('user-1'), { balance: 1, available: 1 });
  await app.close();
});
