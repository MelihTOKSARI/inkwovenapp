import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';
import { createStores } from '../src/stores.js';

const USER = { 'x-ink-user': 'user-1', 'content-type': 'application/json' };

/** A wallet with credits in it. Wallets start EMPTY since free clips replaced
 *  the onboarding grant (task J8), so every spend test funds itself. */
function buildFunded(amount = 1, user = 'user-1') {
  const stores = createStores();
  stores.grant(user, amount);
  return build({ stores });
}

function reserve(app, key, amount = 1) {
  return app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': key },
    payload: { amount },
  });
}

test('a granted credit is reserved → settled and spent exactly once', async () => {
  const app = buildFunded();

  const balance = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.deepEqual(balance.json(), {
    balance: 1,
    available: 1,
    freeClipsRemaining: 2,
    freeClipsOpen: true,
  });

  const reserved = await reserve(app, 'k1');
  assert.equal(reserved.statusCode, 200);
  const { reservationID } = reserved.json();

  const settled = await app.inject({
    method: 'POST',
    url: '/v1/credits/settle',
    headers: { ...USER, 'idempotency-key': 's1' },
    payload: { reservationID },
  });
  assert.equal(settled.statusCode, 200);

  const after = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.equal(after.json().balance, 0);
  assert.equal(after.json().available, 0);
  await app.close();
});

test('release refunds the hold (refund-on-failure)', async () => {
  const app = buildFunded();
  const { reservationID } = (await reserve(app, 'k1')).json();

  const released = await app.inject({
    method: 'POST',
    url: '/v1/credits/release',
    headers: { ...USER, 'idempotency-key': 'r1' },
    payload: { reservationID },
  });
  assert.equal(released.statusCode, 200);

  const after = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.equal(after.json().balance, 1);
  assert.equal(after.json().available, 1);
  await app.close();
});

test('reserve beyond available → 402 insufficient_credits', async () => {
  const app = buildFunded();
  await reserve(app, 'k1');
  const second = await reserve(app, 'k2');
  assert.equal(second.statusCode, 402);
  assert.equal(second.json().error, 'insufficient_credits');
  await app.close();
});

test('idempotency: replaying the same key returns the same reservation, no double hold', async () => {
  const app = buildFunded();
  const first = (await reserve(app, 'same-key')).json();
  const replay = (await reserve(app, 'same-key')).json();
  assert.deepEqual(first, replay);

  const after = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.equal(after.json().available, 0, 'exactly one hold exists');
  await app.close();
});

test('missing idempotency key is rejected', async () => {
  const app = build();
  const res = await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: USER,
    payload: { amount: 1 },
  });
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('wallets are per-user', async () => {
  const app = buildFunded();
  await reserve(app, 'k1'); // user-1 holds their only credit
  const other = await app.inject({
    method: 'GET',
    url: '/v1/credits',
    headers: { 'x-ink-user': 'user-2' },
  });
  // user-2 was never granted anything, and user-1's hold is not theirs.
  assert.equal(other.json().balance, 0);
  assert.equal(other.json().available, 0);
  await app.close();
});
