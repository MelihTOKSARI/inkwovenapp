// Security regressions: trusted-proxy IP, route gating, body/media validation,
// digest integrity, the credit-minting exploit, and the attestation seam.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';
import { createStores } from '../src/stores.js';
import { createAttestationVerifier, AttestationError } from '../src/attest.js';
import { keyPart } from '../src/keys.js';
import { LIMITS } from '../src/config.js';
import { PNG_BYTES, PNG_BASE64, digestOf } from './helpers.js';

const USER = { 'x-ink-user': 'user-1', 'content-type': 'application/json' };

/** Wraps the in-memory store so a test can see which rate keys were counted. */
function recordingStores() {
  const inner = createStores();
  const keys = [];
  return {
    keys,
    stores: {
      ...inner,
      allow(key, limit) {
        keys.push(key);
        return inner.allow(key, limit);
      },
    },
  };
}

// -- trustProxy --------------------------------------------------------------

test('the IP rate bucket keys on the real client, not the Fly edge', async () => {
  const { stores, keys } = recordingStores();
  const app = build({ stores, echoDelayMS: 0 });
  await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: { ...USER, 'x-forwarded-for': '9.9.9.9, 5.5.5.5' },
    payload: { bookID: 'oracle' },
  });
  // Fly APPENDS the true client address, so the rightmost entry is the one to
  // trust. The leftmost (9.9.9.9) is entirely client-supplied.
  assert.ok(keys.includes(`ip:${keyPart('5.5.5.5')}`), 'rightmost forwarded hop');
  assert.ok(!keys.includes(`ip:${keyPart('9.9.9.9')}`), 'never the spoofable leftmost hop');
  assert.ok(!keys.includes(`ip:${keyPart('127.0.0.1')}`), 'never the socket peer');
  await app.close();
});

test('rate keys are hashed, so a token containing ":" cannot enter another namespace', async () => {
  const { stores, keys } = recordingStores();
  const app = build({ stores, echoDelayMS: 0 });
  await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: { 'x-ink-user': 'victim:reserve', 'content-type': 'application/json' },
    payload: { bookID: 'oracle' },
  });
  assert.ok(keys.includes(`user:${keyPart('victim:reserve')}`));
  assert.ok(!keys.some((k) => k.split(':').length > 2), 'every key has exactly two segments');
  await app.close();
});

// -- credit wallet -----------------------------------------------------------

test('a negative reserve amount is rejected, not minted into a balance', async () => {
  const app = build();
  const res = await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': 'exploit' },
    payload: { amount: -100 },
  });
  assert.equal(res.statusCode, 400, 'the schema refuses it before the wallet sees it');

  // And the balance is untouched: the old path created a -100 hold, so
  // available became balance - (-100) = 101, and settling pushed +100 in.
  const wallet = await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.equal(wallet.json().balance, 0);
  assert.equal(wallet.json().available, 0);
  await app.close();
});

test('the wallet itself refuses a bad amount, independent of the schema', async () => {
  const stores = createStores();
  stores.grant('u', 1);
  for (const amount of [-100, 0, 1.5, '1', NaN, Infinity, Number.MAX_SAFE_INTEGER]) {
    assert.deepEqual(await stores.reserve('u', amount), { error: 'invalid_amount' }, `${amount}`);
  }
  assert.deepEqual(await stores.walletView('u'), { balance: 1, available: 1 });
});

test('an oversized reserve is capped', async () => {
  const app = build();
  const res = await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': 'big' },
    payload: { amount: LIMITS.maxReservationAmount + 1 },
  });
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('GET /v1/credits is read-only: reading with a fresh token mints nothing', async () => {
  const stores = createStores();
  const app = build({ stores });
  for (let i = 0; i < 5; i += 1) {
    await app.inject({
      method: 'GET',
      url: '/v1/credits',
      headers: { 'x-ink-user': `farmed-${i}` },
    });
  }
  // A rotating token accumulates nothing: reading writes no wallet, and since
  // task J8 there is no install-time grant for it to project either. Free
  // clips are counted per user server-side, never handed to the wallet.
  assert.deepEqual(await stores.walletView('farmed-0'), { balance: 0, available: 0 });
  assert.deepEqual(await stores.reserve('farmed-0', 1), {
    error: 'insufficient_credits',
    available: 0,
  });
  await app.close();
});

test('a failed reserve is not replayed for the key’s lifetime', async () => {
  const stores = createStores();
  stores.grant('user-1', 1);
  const app = build({ stores });
  await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': 'spend' },
    payload: { amount: 1 },
  });
  const broke = await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': 'retry' },
    payload: { amount: 1 },
  });
  assert.equal(broke.statusCode, 402);

  // The user buys credits; the correct retry reuses the same key.
  stores.grant('user-1', 1);
  const { reservationID } = JSON.parse(
    (
      await app.inject({
        method: 'POST',
        url: '/v1/credits/reserve',
        headers: { ...USER, 'idempotency-key': 'spend' },
        payload: { amount: 1 },
      })
    ).payload,
  );
  await app.inject({
    method: 'POST',
    url: '/v1/credits/release',
    headers: { ...USER, 'idempotency-key': 'undo' },
    payload: { reservationID },
  });
  const afterTopUp = await app.inject({
    method: 'POST',
    url: '/v1/credits/reserve',
    headers: { ...USER, 'idempotency-key': 'retry' },
    payload: { amount: 1 },
  });
  assert.equal(afterTopUp.statusCode, 200, 'the cached 402 did not brick the key');
  await app.close();
});

// -- route gating ------------------------------------------------------------

test('preupload and the credit routes are rate limited, not ungated', async () => {
  const { stores, keys } = recordingStores();
  const app = build({ stores });
  await app.inject({
    method: 'POST',
    url: '/v1/preupload',
    headers: { ...USER, 'x-ink-digest': digestOf(PNG_BYTES), 'content-type': 'application/octet-stream' },
    payload: PNG_BYTES,
  });
  assert.ok(keys.length >= 2, 'preupload counted a user and an ip bucket');
  keys.length = 0;
  await app.inject({ method: 'GET', url: '/v1/credits', headers: USER });
  assert.ok(keys.length >= 2, 'the wallet read counted too');
  await app.close();
});

test('/health answers without a token so hardening auth cannot kill the machine', async () => {
  const app = build();
  const live = await app.inject({ method: 'GET', url: '/health' });
  assert.equal(live.statusCode, 200);
  assert.equal(live.json().ok, true);

  const ready = await app.inject({ method: 'GET', url: '/health/ready' });
  assert.equal(ready.statusCode, 200);

  // Readiness must actually touch the stores, or an outage reads as healthy.
  const broken = build({
    stores: {
      ...createStores(),
      walletView() {
        throw new Error('redis down');
      },
    },
  });
  const sick = await broken.inject({ method: 'GET', url: '/health/ready' });
  assert.equal(sick.statusCode, 503);
  await app.close();
  await broken.close();
});

// -- snapshot validation -----------------------------------------------------

test('preupload verifies the digest the client committed to', async () => {
  const app = build();
  const res = await app.inject({
    method: 'POST',
    url: '/v1/preupload',
    headers: { ...USER, 'x-ink-digest': 'a'.repeat(64), 'content-type': 'application/octet-stream' },
    payload: PNG_BYTES,
  });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'digest_mismatch');
  await app.close();
});

test('preupload refuses anything that is not an image', async () => {
  const bytes = Buffer.from('this is not a page snapshot, it is just text');
  const app = build();
  const res = await app.inject({
    method: 'POST',
    url: '/v1/preupload',
    headers: { ...USER, 'x-ink-digest': digestOf(bytes), 'content-type': 'application/octet-stream' },
    payload: bytes,
  });
  assert.equal(res.statusCode, 415);
  await app.close();
});

test('preupload refuses a body past the snapshot ceiling', async () => {
  const app = build();
  const oversized = Buffer.concat([PNG_BYTES, Buffer.alloc(LIMITS.preuploadBodyLimit, 0)]);
  const res = await app.inject({
    method: 'POST',
    url: '/v1/preupload',
    headers: { ...USER, 'x-ink-digest': digestOf(oversized), 'content-type': 'application/octet-stream' },
    payload: oversized,
  });
  assert.equal(res.statusCode, 413);
  await app.close();
});

test('an exchange snapshot that is not an image is refused, not mislabelled as jpeg', async () => {
  const app = build({ echoDelayMS: 0 });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: USER,
    payload: { bookID: 'oracle', snapshotBase64: Buffer.from('not an image at all').toString('base64') },
  });
  assert.equal(res.statusCode, 415);
  await app.close();
});

test('an oversized base64 snapshot is refused by the schema', async () => {
  const app = build({ echoDelayMS: 0 });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: USER,
    payload: { bookID: 'oracle', snapshotBase64: PNG_BASE64.repeat(9000).slice(0, LIMITS.maxSnapshotBase64Chars + 4) },
  });
  assert.ok(res.statusCode === 400 || res.statusCode === 413, `got ${res.statusCode}`);
  await app.close();
});

// -- kill-switches -----------------------------------------------------------

test('flags.ink rests a Book’s text without taking the whole Book down', async () => {
  const app = build({ echoDelayMS: 0 });
  const { findBook } = await import('../src/books.js');
  const keeper = findBook('keeper');
  keeper.flags.ink = false;
  try {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/exchange',
      headers: USER,
      payload: { bookID: 'keeper' },
    });
    assert.equal(res.statusCode, 503);
    assert.equal(res.json().error, 'ink_resting');
    assert.equal(keeper.flags.enabled, true, 'the Book itself is still enabled');
  } finally {
    keeper.flags.ink = true;
    await app.close();
  }
});

test('flags is the only policy structure the client is served', async () => {
  const app = build();
  const res = await app.inject({ method: 'GET', url: '/v1/books', headers: USER });
  for (const book of res.json().books) {
    assert.equal(book.modalityPolicy, undefined, `${book.id} ships no dead parallel policy`);
    assert.equal(typeof book.flags.ink, 'boolean');
    assert.equal(typeof book.flags.image, 'boolean');
    assert.equal(typeof book.flags.video, 'boolean');
  }
  await app.close();
});

// -- attestation seam --------------------------------------------------------

test('the attestation seam fails closed: production with no verifier rejects everyone', async () => {
  const app = build({ env: { NODE_ENV: 'production' } });
  assert.equal(app.attestationMode, 'required');
  const res = await app.inject({ method: 'GET', url: '/v1/books', headers: USER });
  assert.equal(res.statusCode, 401);
  assert.equal(res.json().error, 'attestation_required');
  // Liveness must survive it, or Fly restarts the machine into the failure.
  assert.equal((await app.inject({ method: 'GET', url: '/health' })).statusCode, 200);
  await app.close();
});

test('pass-through identity must be opted into explicitly', () => {
  assert.equal(createAttestationVerifier({ NODE_ENV: 'production' }).mode, 'required');
  assert.equal(
    createAttestationVerifier({ NODE_ENV: 'production', INK_ATTESTATION_MODE: 'anonymous' }).mode,
    'anonymous',
  );
  assert.equal(createAttestationVerifier({}).mode, 'anonymous', 'dev default');
});

test('a bound verifier mints the identity; the client’s own string is never it', async () => {
  const app = build({
    attestation: {
      mode: 'bound',
      async verify({ token }) {
        if (token !== 'good-assertion') throw new AttestationError('bad_assertion', 401);
        return { userID: 'server-minted-42' };
      },
    },
  });
  const rejected = await app.inject({
    method: 'GET',
    url: '/v1/credits',
    headers: { 'x-ink-user': 'i-picked-this-myself' },
  });
  assert.equal(rejected.statusCode, 401);
  assert.equal(rejected.json().error, 'bad_assertion');

  const accepted = await app.inject({
    method: 'GET',
    url: '/v1/credits',
    headers: { 'x-ink-user': 'good-assertion' },
  });
  assert.equal(accepted.statusCode, 200);
  await app.close();
});
