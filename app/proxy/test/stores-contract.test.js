// Contract suite: every store implementation must satisfy these. Always runs
// against the in-memory store; runs against Redis+Postgres only when
// TEST_REDIS_URL and TEST_DATABASE_URL point at real services (Upstash/Neon).
// Users and keys are random per test so reruns against real services stay clean.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createStores } from '../src/stores.js';
import { createRedisStores } from '../src/stores-redis.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** A minimal valid report body, as the route hands it to the store. */
function reportFixture(overrides = {}) {
  return {
    reportID: randomUUID(),
    replyID: randomUUID(),
    pageID: randomUUID(),
    bookID: 'oracle',
    reason: 'disturbing',
    replyKind: 'ink',
    replyText: 'The reply under report.',
    modelID: '',
    snapshotDigest: 'a'.repeat(64),
    snapshotBase64: 'c25hcHNob3Q=',
    createdAt: new Date().toISOString(),
    submittedAt: new Date().toISOString(),
    ...overrides,
  };
}

function contractSuite(name, makeStores, { skip = false } = {}) {
  const t = (title, fn, storeOptions = {}) =>
    test(`${name}: ${title}`, { skip }, async () => {
      const stores = await makeStores(storeOptions);
      try {
        await fn(stores);
      } finally {
        await stores.close?.();
      }
    });

  t('ticket: owner takes it exactly once; wrong user gets null', async (stores) => {
    const user = randomUUID();
    const { id } = await stores.createTicket(user, 'digest-1');
    assert.equal(await stores.takeTicket(id, 'someone-else'), null);
    const ticket = await stores.takeTicket(id, user);
    assert.equal(ticket.digest, 'digest-1', 'a foreign take must not consume the ticket');
    assert.equal(await stores.takeTicket(id, user), null, 'take consumes');
  });

  t('ticket: delete is a no-op for non-owners', async (stores) => {
    const user = randomUUID();
    const first = await stores.createTicket(user, 'd');
    await stores.deleteTicket(first.id, 'someone-else');
    assert.ok(await stores.takeTicket(first.id, user), 'foreign delete left it alone');
    const second = await stores.createTicket(user, 'd');
    await stores.deleteTicket(second.id, user);
    assert.equal(await stores.takeTicket(second.id, user), null);
  });

  t(
    'ticket: expires after its TTL',
    async (stores) => {
      const user = randomUUID();
      const { id } = await stores.createTicket(user, 'd');
      await sleep(600);
      assert.equal(await stores.takeTicket(id, user), null);
    },
    { ticketTTLms: 300 },
  );

  t('rate limit: fixed window counts per key', async (stores) => {
    const key = `k-${randomUUID()}`;
    assert.equal(await stores.allow(key, 2), true);
    assert.equal(await stores.allow(key, 2), true);
    assert.equal(await stores.allow(key, 2), false);
    assert.equal(await stores.allow(`other-${randomUUID()}`, 2), true, 'keys are independent');
  });

  t('idempotency: first writer wins, replay returns the stored response', async (stores) => {
    const user = randomUUID();
    let calls = 0;
    const produce = () => ({ n: (calls += 1) });
    assert.deepEqual(await stores.idempotent(user, 'op:1', produce), { n: 1 });
    assert.deepEqual(await stores.idempotent(user, 'op:1', produce), { n: 1 });
    assert.equal(calls, 1, 'produce ran once');
    assert.deepEqual(await stores.idempotent(user, 'op:2', produce), { n: 2 });
  });

  t('idempotency: CONCURRENT calls on one key run produce exactly once', async (stores) => {
    // The production store used to GET → produce() → SET NX, which
    // de-duplicated the cached response but not the SIDE EFFECT: two
    // concurrent retries of a reserve both inserted a hold, and the loser's
    // reservationID was thrown away — a phantom hold against the balance
    // forever. The in-memory store could never reproduce it (it was
    // synchronous) and this suite only ever called idempotent() sequentially,
    // so the drift was invisible. Both implementations must claim first.
    const user = randomUUID();
    let calls = 0;
    const produce = async () => {
      calls += 1;
      await sleep(30); // a real reserve is a round trip
      return { hold: calls };
    };
    const [a, b] = await Promise.all([
      stores.idempotent(user, 'op:concurrent', produce),
      stores.idempotent(user, 'op:concurrent', produce),
    ]);
    assert.equal(calls, 1, 'produce ran exactly once across both callers');
    assert.deepEqual(a, { hold: 1 });
    assert.deepEqual(b, { hold: 1 }, 'the loser replayed the winner, it did not re-produce');
  });

  t('idempotency: a failed outcome is not replayed forever', async (stores) => {
    // Caching {error:'insufficient_credits'} for a day means a user who buys
    // credits and retries correctly (same key) can never spend them.
    const user = randomUUID();
    let attempt = 0;
    const produce = async () => {
      attempt += 1;
      return attempt === 1 ? { error: 'insufficient_credits', available: 0 } : { ok: true };
    };
    assert.deepEqual(await stores.idempotent(user, 'op:flaky', produce), {
      error: 'insufficient_credits',
      available: 0,
    });
    assert.deepEqual(
      await stores.idempotent(user, 'op:flaky', produce),
      { ok: true },
      'the key was re-evaluated once the state changed',
    );
  });

  t('idempotency: a throwing produce leaves the key claimable', async (stores) => {
    const user = randomUUID();
    await assert.rejects(
      stores.idempotent(user, 'op:throws', async () => {
        throw new Error('upstream down');
      }),
    );
    assert.deepEqual(await stores.idempotent(user, 'op:throws', async () => ({ ok: true })), {
      ok: true,
    });
  });

  t('wallet: a non-positive or non-integer amount can never mint credits', async (stores) => {
    // reserve(-100) used to pass `available < amount` (1 < -100 is false),
    // create a -100 hold, and settle() then pushed delta:+100 into the
    // append-only ledger. Any caller could mint an unbounded balance.
    const user = randomUUID();
    await stores.grant(user, 1);
    for (const amount of [-100, 0, 1.5, '1', null, undefined]) {
      assert.deepEqual(await stores.reserve(user, amount), { error: 'invalid_amount' }, `${amount}`);
    }
    assert.deepEqual(await stores.walletView(user), { balance: 1, available: 1 });
  });

  t('wallet: an untouched wallet is empty and reading never seeds one', async (stores) => {
    // Wallets start EMPTY: free clips (task J8) replaced the install-time
    // grant that a rotating token could once farm by reading. Only a verified
    // purchase puts a credit in a wallet.
    const user = randomUUID();
    assert.deepEqual(await stores.walletView(user), { balance: 0, available: 0 });
    assert.deepEqual(await stores.reserve(user, 1), { error: 'insufficient_credits', available: 0 });
    await stores.grant(user, 1);
    const { amount } = await stores.reserve(user, 1);
    assert.equal(amount, 1, 'the purchased credit is there when it is spent');
    assert.deepEqual(await stores.walletView(user), { balance: 1, available: 0 });
  });

  t('wallet: grant → reserve → settle; double-settle is idempotent', async (stores) => {
    const user = randomUUID();
    await stores.grant(user, 1);
    assert.deepEqual(await stores.walletView(user), { balance: 1, available: 1 });
    const { reservationID, amount } = await stores.reserve(user, 1);
    assert.equal(amount, 1);
    assert.deepEqual(await stores.walletView(user), { balance: 1, available: 0 });
    assert.deepEqual(await stores.settle(user, reservationID), { settled: true });
    assert.deepEqual(await stores.settle(user, reservationID), { settled: true });
    assert.deepEqual(await stores.walletView(user), { balance: 0, available: 0 });
  });

  t('wallet: insufficient reserve reports what is available', async (stores) => {
    const user = randomUUID();
    await stores.grant(user, 1);
    assert.deepEqual(await stores.reserve(user, 5), {
      error: 'insufficient_credits',
      available: 1,
    });
  });

  t('wallet: release refunds; settled-after-release and unknown are rejected', async (stores) => {
    const user = randomUUID();
    await stores.grant(user, 1);
    const { reservationID } = await stores.reserve(user, 1);
    assert.deepEqual(await stores.release(user, reservationID), { released: true });
    assert.deepEqual(await stores.release(user, reservationID), { released: true });
    assert.deepEqual(await stores.walletView(user), { balance: 1, available: 1 });
    assert.deepEqual(await stores.settle(user, reservationID), { error: 'unknown_reservation' });
    assert.deepEqual(await stores.settle(user, randomUUID()), { error: 'unknown_reservation' });
    assert.deepEqual(await stores.release(user, randomUUID()), { error: 'unknown_reservation' });
  });

  t('reports: filing acks; a duplicate reportID never files twice', async (stores) => {
    const user = randomUUID();
    const report = reportFixture();
    assert.deepEqual(await stores.fileReport(user, report), { received: true });
    assert.deepEqual(await stores.fileReport(user, report), { received: true });
    assert.equal(await stores.reportCount(user), 1, 'a double-tap is one report');
    await stores.fileReport(user, reportFixture());
    assert.equal(await stores.reportCount(user), 2);
  });

  t('reports: a junk reportID is rejected before it reaches storage', async (stores) => {
    const user = randomUUID();
    assert.deepEqual(await stores.fileReport(user, reportFixture({ reportID: 'not-a-uuid' })), {
      error: 'invalid_report',
    });
    assert.equal(await stores.reportCount(user), 0);
  });

  t('reports: the sweep deletes past 90 days and spares anything newer', async (stores) => {
    const user = randomUUID();
    await stores.fileReport(user, reportFixture());
    const day = 24 * 60 * 60 * 1000;
    // Counts are asserted per-user: on a shared test database another run's
    // reports may fall to the same sweep, so the removed total is only
    // checked for "at least ours."
    await stores.sweepExpiredReports(Date.now() + 89 * day);
    assert.equal(await stores.reportCount(user), 1, '89 days in, the report still stands');
    const removed = await stores.sweepExpiredReports(Date.now() + 91 * day);
    assert.ok(removed >= 1, 'the sweep reports what it deleted');
    assert.equal(await stores.reportCount(user), 0, '91 days in, the report is gone');
  });
}

contractSuite('in-memory', (options) => createStores(options));

const redisUrl = process.env.TEST_REDIS_URL;
const databaseUrl = process.env.TEST_DATABASE_URL;
contractSuite(
  'redis+postgres',
  (options) => createRedisStores({ redisUrl, databaseUrl, ...options }),
  { skip: (!redisUrl || !databaseUrl) && 'set TEST_REDIS_URL and TEST_DATABASE_URL to run' },
);
