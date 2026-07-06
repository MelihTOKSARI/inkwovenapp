import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';

const USER = { 'x-ink-user': 'user-1', 'content-type': 'application/json' };

function reserve(app, key, amount = 1) {
  return app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': key },
    payload: { amount },
  });
}

test('onboarding grant seeds 1 credit; reserve → settle spends it', async () => {
  const app = build();

  const balance = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.deepEqual(balance.json(), { balance: 1, available: 1 });

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
  assert.deepEqual(after.json(), { balance: 0, available: 0 });
  await app.close();
});

test('release refunds the hold (refund-on-failure)', async () => {
  const app = build();
  const { reservationID } = (await reserve(app, 'k1')).json();

  const released = await app.inject({
    method: 'POST',
    url: '/v1/credits/release',
    headers: { ...USER, 'idempotency-key': 'r1' },
    payload: { reservationID },
  });
  assert.equal(released.statusCode, 200);

  const after = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.deepEqual(after.json(), { balance: 1, available: 1 });
  await app.close();
});

test('reserve beyond available → 402 insufficient_credits', async () => {
  const app = build();
  await reserve(app, 'k1');
  const second = await reserve(app, 'k2');
  assert.equal(second.statusCode, 402);
  assert.equal(second.json().error, 'insufficient_credits');
  await app.close();
});

test('idempotency: replaying the same key returns the same reservation, no double hold', async () => {
  const app = build();
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
  const app = build();
  await reserve(app, 'k1'); // user-1 spends their hold
  const other = await app.inject({
    method: 'GET',
    url: '/v1/credits',
    headers: { 'x-ink-user': 'user-2' },
  });
  assert.deepEqual(other.json(), { balance: 1, available: 1 });
  await app.close();
});
