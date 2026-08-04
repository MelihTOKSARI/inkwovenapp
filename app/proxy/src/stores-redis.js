// Production stores (deployment.md §5.3): Redis/Upstash for tickets, rate
// limits, and idempotency; Postgres/Neon for the credit ledger. Same interface
// as stores.js — route handlers await either implementation and can't tell.
import { randomBytes, randomUUID } from 'node:crypto';
import Redis from 'ioredis';
import pg from 'pg';
import { CONFIG, LIMITS } from './config.js';
import { keyPart } from './keys.js';
import { dayKey, isErrorResponse, monthKey, validAmount } from './stores.js';

const TICKET_TTL_MS = 60_000;
const IDEMPOTENCY_TTL_S = 86_400;
// Failures are transient state, not outcomes: replaying a 402 for a day means
// a user who buys credits and retries with the same key can never spend them.
const IDEMPOTENCY_ERROR_TTL_S = 60;
// How long a claim may sit unresolved before another caller may re-run it.
const IDEMPOTENCY_CLAIM_TTL_S = 60;
// Plain text on purpose. This was '\x00pending', whose NUL byte made git treat
// the credit ledger as binary — `git show` rendered every change to the money
// code as "Bin 20099 -> 22043 bytes" with no reviewable diff. A stored response
// is always a JSON object, so it can never begin with a letter; the sentinel
// stays unambiguous without the NUL.
const CLAIM_SENTINEL = 'pending';
const CLAIM_POLL_MS = 40;
const CLAIM_WAIT_MS = 2_000;
// User-triggered reports (guideline 1.2): the privacy policy promises 90-day
// deletion, so the sweep below is a correctness requirement, not housekeeping.
const REPORT_RETENTION_MS = LIMITS.reportRetentionDays * 24 * 60 * 60 * 1000;
const REPORT_SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;
// Stranded credit holds are money the user cannot spend, so this runs far more
// often than the report sweep — and on boot, which is when the process that
// stranded them is being replaced.
const HOLD_RECLAIM_INTERVAL_MS = 5 * 60 * 1000;

// Take must be one round trip: a bare GETDEL would destroy another user's
// ticket before we could check ownership, so the check lives in the script.
// Redis TTL is the expiry check — an expired key is simply gone.
const TAKE_TICKET_LUA = `
local v = redis.call('GET', KEYS[1])
if not v then return false end
if cjson.decode(v).userID ~= ARGV[1] then return false end
redis.call('DEL', KEYS[1])
return v
`;

// Fixed window: EXPIRE must ride the first INCR atomically, or a crash
// between the two leaves an immortal counter that rate-limits forever.
const RATE_ALLOW_LUA = `
local n = redis.call('INCR', KEYS[1])
if n == 1 then redis.call('EXPIRE', KEYS[1], 60) end
return n
`;

// Daily quotas (audit M-2): same INCR+EXPIRE atomicity as RATE_ALLOW_LUA.
// The key already names its UTC day, so the TTL only has to outlive it.
const DAILY_ALLOW_LUA = `
local n = redis.call('INCR', KEYS[1])
if n == 1 then redis.call('EXPIRE', KEYS[1], 172800) end
return n
`;

// Refund floors at zero IN the script: a bare DECR on a missing or exhausted
// key goes negative, which is minted capacity.
const DAILY_REFUND_LUA = `
local v = redis.call('GET', KEYS[1])
if not v then return 0 end
if tonumber(v) <= 0 then return 0 end
return redis.call('DECR', KEYS[1])
`;

// Append-only ledger + holds; balance is always derived, never stored.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS credit_entries (
  id uuid PRIMARY KEY,
  user_id text NOT NULL,
  delta int NOT NULL,
  reason text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS credit_holds (
  id uuid PRIMARY KEY,
  user_id text NOT NULL,
  amount int NOT NULL,
  state text NOT NULL DEFAULT 'held',
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS credit_entries_user_idx ON credit_entries (user_id);
CREATE INDEX IF NOT EXISTS credit_holds_user_idx ON credit_holds (user_id);
CREATE TABLE IF NOT EXISTS reports (
  id uuid PRIMARY KEY,
  user_id text NOT NULL,
  book_id text NOT NULL,
  reason text NOT NULL,
  payload jsonb NOT NULL,
  snapshot bytea NOT NULL,
  filed_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS reports_expires_idx ON reports (expires_at);
CREATE INDEX IF NOT EXISTS reports_user_idx ON reports (user_id);
CREATE TABLE IF NOT EXISTS free_clips (
  id uuid PRIMARY KEY,
  user_id text NOT NULL,
  state text NOT NULL DEFAULT 'held',
  month text NOT NULL,
  day text,
  ip_key text,
  at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE free_clips ADD COLUMN IF NOT EXISTS day text;
ALTER TABLE free_clips ADD COLUMN IF NOT EXISTS ip_key text;
CREATE INDEX IF NOT EXISTS free_clips_user_idx ON free_clips (user_id);
CREATE INDEX IF NOT EXISTS free_clips_month_idx ON free_clips (month);
CREATE INDEX IF NOT EXISTS free_clips_ip_day_idx ON free_clips (ip_key, day);
CREATE TABLE IF NOT EXISTS redeemed_transactions (
  transaction_id text PRIMARY KEY,
  user_id text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS attest_keys (
  key_id text PRIMARY KEY,
  user_id text NOT NULL,
  public_key text NOT NULL,
  counter bigint NOT NULL DEFAULT 0,
  at timestamptz NOT NULL DEFAULT now()
);
`;

// The last line of defence behind validAmount(): a hold can never be negative,
// so no code path can turn settle()'s `-amount` into a credit mint. NOT VALID
// keeps migrate-on-boot safe against rows written before the constraint —
// it applies to every new row, which is where the exploit lived.
const CONSTRAINTS = `
DO $$ BEGIN
  ALTER TABLE credit_holds ADD CONSTRAINT credit_holds_amount_positive CHECK (amount > 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
`;

// Client-supplied reservation IDs hit a uuid column; reject junk before
// Postgres turns the failed cast into a 500.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function createRedisStores({ redisUrl, databaseUrl, ticketTTLms = TICKET_TTL_MS }) {
  const redis = new Redis(redisUrl); // rediss:// turns TLS on by itself
  redis.defineCommand('takeTicketAtomic', { numberOfKeys: 1, lua: TAKE_TICKET_LUA });
  redis.defineCommand('rateAllow', { numberOfKeys: 1, lua: RATE_ALLOW_LUA });
  redis.defineCommand('dailyAllow', { numberOfKeys: 1, lua: DAILY_ALLOW_LUA });
  redis.defineCommand('dailyRefund', { numberOfKeys: 1, lua: DAILY_REFUND_LUA });

  const pool = new pg.Pool({ connectionString: databaseUrl });
  await migrate(pool);

  /** Deletes reports past retention; returns how many went. */
  async function sweepReports(nowMs = Date.now()) {
    const { rowCount } = await pool.query(
      'DELETE FROM reports WHERE expires_at <= to_timestamp($1 / 1000.0)',
      [nowMs],
    );
    return rowCount;
  }

  // The 90-day promise is kept in code: sweep at boot, then on an interval
  // for as long as the process lives. fileReport() sweeps on every write
  // too, so a busy store never waits on the timer. unref() keeps the timer
  // from pinning a process that is otherwise done (tests, drain).
  await sweepReports();
  const reportSweepTimer = setInterval(() => {
    sweepReports().catch(() => {});
  }, REPORT_SWEEP_INTERVAL_MS);
  reportSweepTimer.unref?.();

  // Reclaim on boot — the process that died mid-generation is exactly the one
  // being replaced right now — and then on an interval for anything that dies
  // later. A stranded hold is a credit the user paid for and cannot spend.
  await reclaimStaleHolds();
  const holdReclaimTimer = setInterval(() => {
    reclaimStaleHolds().catch(() => {});
  }, HOLD_RECLAIM_INTERVAL_MS);
  holdReclaimTimer.unref?.();

  // Every wallet operation runs in one transaction under a per-user advisory
  // lock — the serialization the in-memory Maps got for free. Wallets start
  // empty: the onboarding grant this used to seed is replaced by the
  // free-clip accounting below (task J8).
  async function withWallet(userID, fn) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [userID]);
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async function view(client, userID) {
    const { rows } = await client.query(
      `SELECT COALESCE((SELECT SUM(delta) FROM credit_entries WHERE user_id = $1), 0) AS balance,
              COALESCE((SELECT SUM(amount) FROM credit_holds WHERE user_id = $1 AND state = 'held'), 0) AS held`,
      [userID],
    );
    const balance = Number(rows[0].balance);
    return { balance, available: balance - Number(rows[0].held) };
  }

  /**
   * Releases holds too old for any live request to still own them.
   *
   * A hold outlives its request only when the process died between reserve and
   * settle — a deploy or a crash mid-generation, and video generations run for
   * minutes. In Postgres such a hold is permanent: it silently subtracts from
   * `available` forever and the user simply finds a credit missing. The cutoff
   * is four times the longest legitimate hold (config.js), so this can never
   * refund a clip that is still being made.
   */
  async function reclaimStaleHolds(nowMs = Date.now()) {
    const cutoff = nowMs - LIMITS.staleHoldReclaimMS;
    const [holds, free] = await Promise.all([
      pool.query(
        `UPDATE credit_holds SET state = 'released'
         WHERE state = 'held' AND at <= to_timestamp($1 / 1000.0)`,
        [cutoff],
      ),
      pool.query(
        `UPDATE free_clips SET state = 'released'
         WHERE state = 'held' AND at <= to_timestamp($1 / 1000.0)`,
        [cutoff],
      ),
    ]);
    return holds.rowCount + free.rowCount;
  }

  return {
    async createTicket(userID, digest, snapshotBase64 = null) {
      const id = randomUUID();
      // Snapshot rides the ticket (60s TTL) so a committed exchange can
      // recover the image the client already uploaded.
      await redis.set(
        `ticket:${id}`,
        JSON.stringify({ userID, digest, snapshotBase64 }),
        'PX',
        ticketTTLms,
      );
      return { id, expiresAt: new Date(Date.now() + ticketTTLms).toISOString() };
    },

    async takeTicket(id, userID) {
      const raw = await redis.takeTicketAtomic(`ticket:${id}`, userID);
      return raw ? JSON.parse(raw) : null;
    },

    async deleteTicket(id, userID) {
      // Same ownership-checked delete as takeTicket, result discarded.
      await redis.takeTicketAtomic(`ticket:${id}`, userID);
    },

    /** Read-only: a wallet with no entries reads as empty, never seeded. */
    async walletView(userID) {
      const client = await pool.connect();
      try {
        const { rows } = await client.query(
          `SELECT COALESCE((SELECT SUM(delta) FROM credit_entries WHERE user_id = $1), 0) AS balance,
                  COALESCE((SELECT SUM(amount) FROM credit_holds WHERE user_id = $1 AND state = 'held'), 0) AS held`,
          [userID],
        );
        const balance = Number(rows[0].balance);
        return { balance, available: balance - Number(rows[0].held) };
      } finally {
        client.release();
      }
    },

    /**
     * Binds a StoreKit transaction to the FIRST identity that redeems it —
     * the primary key makes the claim global and atomic (audit M-1). Same
     * user again claims through (honest retry); a different user presenting
     * the same transaction is a replayed receipt and is refused.
     */
    async claimTransaction(transactionID, userID) {
      const { rows } = await pool.query(
        `INSERT INTO redeemed_transactions (transaction_id, user_id)
         VALUES ($1, $2)
         ON CONFLICT (transaction_id) DO NOTHING
         RETURNING user_id`,
        [transactionID, userID],
      );
      if (rows.length > 0) return { claimed: true };
      const { rows: existing } = await pool.query(
        'SELECT user_id FROM redeemed_transactions WHERE transaction_id = $1',
        [transactionID],
      );
      if (existing[0]?.user_id === userID) return { claimed: true };
      return { error: 'receipt_already_redeemed' };
    },

    /** Who redeemed this transaction — the refund path's routing (audit M-4). */
    async transactionOwner(transactionID) {
      const { rows } = await pool.query(
        'SELECT user_id FROM redeemed_transactions WHERE transaction_id = $1',
        [transactionID],
      );
      return rows[0]?.user_id ?? null;
    },

    /**
     * Debits a refunded purchase (audit M-4). The delta is negative and the
     * balance MAY go negative: the credits were spent on real provider
     * compute before Apple gave the money back, and a negative balance is
     * what stops the same wallet spending them twice.
     */
    async revoke(userID, amount, reason = 'refund') {
      if (!validAmount(amount)) return { error: 'invalid_amount' };
      return withWallet(userID, async (client) => {
        await client.query(
          'INSERT INTO credit_entries (id, user_id, delta, reason) VALUES ($1, $2, $3, $4)',
          [randomUUID(), userID, -amount, reason],
        );
        const { balance } = await view(client, userID);
        return { revoked: amount, balance };
      });
    },

    /** Credits a verified vial purchase; amount comes from the server-side product map. */
    async grant(userID, amount, reason = 'purchase') {
      if (!validAmount(amount)) return { error: 'invalid_amount' };
      return withWallet(userID, async (client) => {
        await client.query(
          'INSERT INTO credit_entries (id, user_id, delta, reason) VALUES ($1, $2, $3, $4)',
          [randomUUID(), userID, amount, reason],
        );
        const { balance } = await view(client, userID);
        return { granted: amount, balance };
      });
    },

    async reserve(userID, amount) {
      if (!validAmount(amount)) return { error: 'invalid_amount' };
      return withWallet(userID, async (client) => {
        const { available } = await view(client, userID);
        if (available < amount) return { error: 'insufficient_credits', available };
        const id = randomUUID();
        await client.query('INSERT INTO credit_holds (id, user_id, amount) VALUES ($1, $2, $3)', [
          id,
          userID,
          amount,
        ]);
        return { reservationID: id, amount };
      });
    },

    async settle(userID, reservationID) {
      if (!UUID_RE.test(reservationID ?? '')) return { error: 'unknown_reservation' };
      return withWallet(userID, async (client) => {
        const { rows } = await client.query(
          'SELECT amount, state FROM credit_holds WHERE id = $1 AND user_id = $2 FOR UPDATE',
          [reservationID, userID],
        );
        const hold = rows[0];
        if (hold?.state === 'settled') return { settled: true };
        if (!hold || hold.state !== 'held') return { error: 'unknown_reservation' };
        await client.query("UPDATE credit_holds SET state = 'settled' WHERE id = $1", [
          reservationID,
        ]);
        await client.query(
          'INSERT INTO credit_entries (id, user_id, delta, reason) VALUES ($1, $2, $3, $4)',
          [randomUUID(), userID, -hold.amount, 'video_spend'],
        );
        return { settled: true };
      });
    },

    async release(userID, reservationID) {
      if (!UUID_RE.test(reservationID ?? '')) return { error: 'unknown_reservation' };
      return withWallet(userID, async (client) => {
        const { rows } = await client.query(
          'SELECT state FROM credit_holds WHERE id = $1 AND user_id = $2 FOR UPDATE',
          [reservationID, userID],
        );
        const hold = rows[0];
        if (hold?.state === 'released') return { released: true };
        if (!hold || hold.state !== 'held') return { error: 'unknown_reservation' };
        await client.query("UPDATE credit_holds SET state = 'released' WHERE id = $1", [
          reservationID,
        ]);
        return { released: true };
      });
    },

    /**
     * Idempotency: CLAIM first, then produce.
     *
     * The old order was GET → produce() → SET NX, which de-duplicated the
     * cached RESPONSE but not the side effect: two concurrent retries of one
     * reserve both saw an empty cache, both inserted a hold, and the loser's
     * reservationID was discarded — a permanent phantom hold against the
     * user's balance. Claiming the key before produce() runs makes the side
     * effect single-shot; losers wait for the winner's answer.
     */
    async idempotent(userID, key, produce) {
      if (!key) return produce();
      // keyPart() removes the ':' ambiguity between the two components.
      const redisKey = `idem:${keyPart(userID)}:${keyPart(key)}`;

      // Runs produce() under a claim we already hold, then publishes the
      // outcome. Failures get a short TTL: replaying a 402 for a day means a
      // user who buys credits and retries with the same key can never spend.
      const runClaimed = async () => {
        let response;
        try {
          response = await produce();
        } catch (error) {
          // Never leave the key stuck pending for the claim's whole TTL.
          await redis.del(redisKey);
          throw error;
        }
        const ttl = isErrorResponse(response) ? IDEMPOTENCY_ERROR_TTL_S : IDEMPOTENCY_TTL_S;
        await redis.set(redisKey, JSON.stringify(response), 'EX', ttl);
        return response;
      };

      const deadline = Date.now() + CLAIM_WAIT_MS;
      for (;;) {
        const cached = await redis.get(redisKey);
        if (cached !== null && cached !== CLAIM_SENTINEL) return JSON.parse(cached);
        if (cached === null) {
          const claimed = await redis.set(
            redisKey,
            CLAIM_SENTINEL,
            'EX',
            IDEMPOTENCY_CLAIM_TTL_S,
            'NX',
          );
          if (claimed) return runClaimed();
        }
        // Someone else holds the claim: wait for their answer rather than
        // running produce() a second time. Giving up is a 409, never a
        // duplicate side effect.
        if (Date.now() >= deadline) return { error: 'idempotency_in_flight' };
        await new Promise((resolve) => setTimeout(resolve, CLAIM_POLL_MS));
      }
    },

    /** Fixed-window rate limit; returns true when the call is allowed. */
    async allow(key, limitPerMinute) {
      const count = await redis.rateAllow(`rate:${keyPart(key)}`);
      return count <= limitPerMinute;
    },

    // -- daily quotas + tier (audit M-2) ------------------------------------

    /** Counts one attempt against a per-UTC-day window; allowed while <= limit. */
    async allowDaily(key, limit, now = Date.now()) {
      const count = await redis.dailyAllow(`daily:${dayKey(now)}:${keyPart(key)}`);
      return { allowed: count <= limit, count };
    },

    /**
     * Gives one attempt back — the quota analogue of releasing a wallet hold.
     * Floors at zero in the Lua script; a rolled day is simply a missing key.
     */
    async refundDaily(key, now = Date.now()) {
      await redis.dailyRefund(`daily:${dayKey(now)}:${keyPart(key)}`);
    },

    /** Records a proved subscription tier until the receipt's own expiry. */
    async setTier(userID, tier, expiresAtMs, originalTransactionID = null) {
      if (expiresAtMs <= Date.now()) return { error: 'expired' };
      // PXAT ties the record's life to the receipt's own expiry — a lapsed
      // subscription demotes itself with no sweeper to run.
      await redis.set(`tier:${keyPart(userID)}`, tier, 'PXAT', Math.floor(expiresAtMs));
      if (originalTransactionID) {
        // How a REFUND/REVOKE notification finds the tier to drop — Apple
        // names the transaction, never our identity (audit M-4).
        await redis.set(
          `tiertxn:${keyPart(String(originalTransactionID))}`,
          userID,
          'PXAT',
          Math.floor(expiresAtMs),
        );
      }
      return { tier, expiresAt: expiresAtMs };
    },

    /** The tier this identity proved, or 'free' once the proof has expired. */
    async tierOf(userID) {
      return (await redis.get(`tier:${keyPart(userID)}`)) ?? 'free';
    },

    /** Drops a proved tier — the refund/revocation path (audit M-4). */
    async clearTier(userID) {
      await redis.del(`tier:${keyPart(userID)}`);
    },

    // -- App Attest (audit T3) ----------------------------------------------
    // Challenges live in Redis (one-time, TTL does the sweeping); the
    // attested-key table is identity — it lives in Postgres, durably.

    async issueChallenge() {
      const value = randomBytes(32).toString('base64');
      await redis.set(`challenge:${keyPart(value)}`, '1', 'EX', 300);
      return value;
    },

    /** Consumes a challenge; false when unknown, expired, or already used. */
    async takeChallenge(value) {
      if (typeof value !== 'string' || !value) return false;
      const taken = await redis.getdel(`challenge:${keyPart(value)}`);
      return taken !== null;
    },

    /**
     * Binds an attested key to an identity the SERVER mints. Re-attesting a
     * known key returns its existing identity — the key is the account, and
     * a reinstall must find its wallet again.
     */
    async registerAttestKey(keyID, publicKeyPEM) {
      const userID = randomUUID();
      const { rows } = await pool.query(
        `INSERT INTO attest_keys (key_id, user_id, public_key)
         VALUES ($1, $2, $3)
         ON CONFLICT (key_id) DO NOTHING
         RETURNING user_id`,
        [keyID, userID, publicKeyPEM],
      );
      if (rows.length > 0) return { userID: rows[0].user_id };
      const { rows: existing } = await pool.query(
        'SELECT user_id FROM attest_keys WHERE key_id = $1',
        [keyID],
      );
      return { userID: existing[0].user_id };
    },

    async attestKeyRecord(keyID) {
      const { rows } = await pool.query(
        'SELECT user_id, public_key, counter FROM attest_keys WHERE key_id = $1',
        [keyID],
      );
      if (!rows[0]) return null;
      return {
        userID: rows[0].user_id,
        publicKeyPEM: rows[0].public_key,
        counter: Number(rows[0].counter),
      };
    },

    /** Advances the assertion counter; only ever forward. */
    async bumpAttestCounter(keyID, counter) {
      await pool.query(
        'UPDATE attest_keys SET counter = $2 WHERE key_id = $1 AND counter < $2',
        [keyID, counter],
      );
    },

    /**
     * Drops the tier bound to a subscription transaction (audit M-4).
     * Returns the identity it belonged to, or null when unknown here.
     */
    async clearTierByTransaction(originalTransactionID) {
      const userID = await redis.get(`tiertxn:${keyPart(String(originalTransactionID))}`);
      if (userID) await redis.del(`tier:${keyPart(userID)}`);
      return userID ?? null;
    },

    /**
     * Files a user-triggered report (guideline 1.2). Reports outlive a
     * restart — they are the paper trail behind a moderation promise — so
     * they live in Postgres, never Redis. The snapshot is stored as bytes,
     * not base64, and ON CONFLICT keeps a duplicate reportID from filing
     * twice even if the idempotency cache has lapsed.
     */
    async fileReport(userID, report) {
      if (!UUID_RE.test(report?.reportID ?? '')) return { error: 'invalid_report' };
      await sweepReports();
      const { snapshotBase64, ...rest } = report;
      await pool.query(
        `INSERT INTO reports (id, user_id, book_id, reason, payload, snapshot, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7 / 1000.0))
         ON CONFLICT (id) DO NOTHING`,
        [
          report.reportID,
          userID,
          report.bookID,
          report.reason,
          JSON.stringify(rest),
          Buffer.from(snapshotBase64 ?? '', 'base64'),
          Date.now() + REPORT_RETENTION_MS,
        ],
      );
      return { received: true };
    },

    /** How many un-expired reports stand — for one user, or all of them. */
    async reportCount(userID) {
      const { rows } =
        userID === undefined
          ? await pool.query('SELECT COUNT(*) AS n FROM reports WHERE expires_at > now()')
          : await pool.query(
              'SELECT COUNT(*) AS n FROM reports WHERE user_id = $1 AND expires_at > now()',
              [userID],
            );
      return Number(rows[0].n);
    },

    /**
     * Un-expired reports for triage (audit S-7), newest first. This is what
     * the operator route reads — before it existed the table had no reader
     * at all, and rows were swept unread at ninety days.
     */
    async listReports(limit = 200) {
      const { rows } = await pool.query(
        `SELECT id, user_id, book_id, reason, payload, filed_at,
                encode(snapshot, 'base64') AS snapshot_base64
         FROM reports WHERE expires_at > now()
         ORDER BY filed_at DESC LIMIT $1`,
        [limit],
      );
      return rows.map((row) => ({
        userID: row.user_id,
        reportID: row.id,
        bookID: row.book_id,
        reason: row.reason,
        filedAt: row.filed_at,
        snapshotBase64: row.snapshot_base64,
        ...row.payload,
      }));
    },

    /** The retention sweep, callable with a clock so tests can exercise it. */
    async sweepExpiredReports(now = Date.now()) {
      return sweepReports(now);
    },

    // -- verdict briefs (tasks J2/J4): Redis, TTL does the sweeping ---------

    async createBrief(userID, brief) {
      const id = randomUUID();
      await redis.set(
        `brief:${id}`,
        JSON.stringify({ userID, brief }),
        'PX',
        LIMITS.videoBriefTTLms,
      );
      return { id, expiresAt: new Date(Date.now() + LIMITS.videoBriefTTLms).toISOString() };
    },

    async getBrief(id, userID) {
      const raw = await redis.get(`brief:${id}`);
      if (!raw) return null;
      const entry = JSON.parse(raw);
      return entry.userID === userID ? entry.brief : null;
    },

    // -- video job claims (task J4): claim-first, like idempotency ----------

    async claimVideoJob(userID, videoID) {
      const key = `videojob:${keyPart(userID)}:${keyPart(videoID)}`;
      const claimed = await redis.set(key, CLAIM_SENTINEL, 'EX', 600, 'NX');
      if (claimed) return { fresh: true };
      const existing = await redis.get(key);
      if (existing === null) {
        // The claim lapsed between SET NX and GET; take it now.
        const retaken = await redis.set(key, CLAIM_SENTINEL, 'EX', 600, 'NX');
        return retaken ? { fresh: true } : { inFlight: true };
      }
      if (existing === CLAIM_SENTINEL) return { inFlight: true };
      return { delivered: true, url: JSON.parse(existing).url };
    },

    async completeVideoJob(userID, videoID, url) {
      const key = `videojob:${keyPart(userID)}:${keyPart(videoID)}`;
      await redis.set(key, JSON.stringify({ url }), 'EX', 3_600);
    },

    async failVideoJob(userID, videoID) {
      await redis.del(`videojob:${keyPart(userID)}:${keyPart(videoID)}`);
    },

    // -- free clips (task J8): Postgres — this is money-adjacent state ------
    // The per-user count and the global monthly ceiling are both checked
    // under one global advisory lock: free-clip reserves are rare and short,
    // and a serialized check is what makes the ceiling a ceiling.

    async freeClipView(userID, now = Date.now()) {
      // `used` excludes released rows — a clip that failed is given back to
      // the reader. `month_count` counts EVERY row, because the ceiling bounds
      // what we spend at fal and a failed attempt was still paid for.
      const { rows } = await pool.query(
        `SELECT (SELECT COUNT(*) FROM free_clips WHERE user_id = $1 AND state IN ('held','settled')) AS used,
                (SELECT COUNT(*) FROM free_clips WHERE month = $2) AS month_count`,
        [userID, monthKey(now)],
      );
      return {
        remaining: Math.max(0, CONFIG.video.freeClipsPerUser - Number(rows[0].used)),
        ceilingOpen: Number(rows[0].month_count) < CONFIG.video.freeClipMonthlyCeiling,
      };
    },

    async reserveFreeClip(userID, { now = Date.now(), ipKey = null } = {}) {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query("SELECT pg_advisory_xact_lock(hashtext('free-clip-ceiling'))");
        const month = monthKey(now);
        const day = dayKey(now);
        const { rows } = await client.query(
          `SELECT (SELECT COUNT(*) FROM free_clips WHERE user_id = $1 AND state IN ('held','settled')) AS used,
                  (SELECT COUNT(*) FROM free_clips WHERE month = $2) AS month_count,
                  (SELECT COUNT(*) FROM free_clips WHERE ip_key = $3 AND day = $4) AS ip_count`,
          [userID, month, ipKey, day],
        );
        if (Number(rows[0].used) >= CONFIG.video.freeClipsPerUser) {
          await client.query('ROLLBACK');
          return { error: 'free_exhausted' };
        }
        // Every row counts here, released included: the ceiling bounds spend,
        // and an abandoned generation was still billed by fal. Counting only
        // settlements made the ceiling unbounded — drop the connection
        // mid-clip and the spend erased itself.
        if (Number(rows[0].month_count) >= CONFIG.video.freeClipMonthlyCeiling) {
          await client.query('ROLLBACK');
          return { error: 'free_ceiling' };
        }
        // A token is free to mint under anonymous attestation, so the address
        // behind the tokens is what actually bounds an exhaustion run.
        if (ipKey && Number(rows[0].ip_count) >= CONFIG.video.freeClipsPerIPPerDay) {
          await client.query('ROLLBACK');
          return { error: 'free_ceiling' };
        }
        const id = randomUUID();
        await client.query(
          'INSERT INTO free_clips (id, user_id, month, day, ip_key) VALUES ($1, $2, $3, $4, $5)',
          [id, userID, month, day, ipKey],
        );
        await client.query('COMMIT');
        return { holdID: id };
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },

    async settleFreeClip(userID, holdID) {
      if (!UUID_RE.test(holdID ?? '')) return { error: 'unknown_hold' };
      const { rows } = await pool.query(
        'SELECT state FROM free_clips WHERE id = $1 AND user_id = $2',
        [holdID, userID],
      );
      if (rows[0]?.state === 'settled') return { settled: true };
      if (!rows[0] || rows[0].state !== 'held') return { error: 'unknown_hold' };
      await pool.query("UPDATE free_clips SET state = 'settled' WHERE id = $1", [holdID]);
      return { settled: true };
    },

    async releaseFreeClip(userID, holdID) {
      if (!UUID_RE.test(holdID ?? '')) return { error: 'unknown_hold' };
      const { rows } = await pool.query(
        'SELECT state FROM free_clips WHERE id = $1 AND user_id = $2',
        [holdID, userID],
      );
      if (rows[0]?.state === 'released') return { released: true };
      if (!rows[0] || rows[0].state !== 'held') return { error: 'unknown_hold' };
      // The reader gets their free clip back. The month's ceiling does not
      // move: the row stays counted because the attempt was paid for.
      await pool.query("UPDATE free_clips SET state = 'released' WHERE id = $1", [holdID]);
      return { released: true };
    },

    /** The stale-hold reclaim, callable with a clock so it can be exercised. */
    async reclaimStaleHolds(now = Date.now()) {
      return reclaimStaleHolds(now);
    },

    async close() {
      clearInterval(reportSweepTimer);
      clearInterval(holdReclaimTimer);
      await redis.quit();
      await pool.end();
    },
  };
}

// Migrate-on-boot: every statement is IF NOT EXISTS, so reruns are free.
async function migrate(pool) {
  await pool.query(SCHEMA);
  await pool.query(CONSTRAINTS);
}
