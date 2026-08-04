// In-memory stores for local dev and tests. Production swaps these for Redis
// (rate-limit counters, tickets, idempotency) and Postgres (credit ledger) —
// the route handlers only touch this interface.
import { randomUUID } from 'node:crypto';
import { CONFIG, LIMITS } from './config.js';

const TICKET_TTL_MS = 60_000;
const REPORT_RETENTION_MS = LIMITS.reportRetentionDays * 24 * 60 * 60 * 1000;

/** Client-supplied report IDs key the reports map; reject junk early. */
const REPORT_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A reservation amount is client-supplied. Anything but a whole number in
 * [1, maxReservationAmount] is rejected: `reserve(-100)` used to sail past the
 * `available < amount` guard and MINT credits, because 1 < -100 is false and
 * settle() then pushed `-amount` (a positive delta) into the ledger.
 */
export function validAmount(amount) {
  return (
    typeof amount === 'number' &&
    Number.isSafeInteger(amount) &&
    amount >= 1 &&
    amount <= LIMITS.maxReservationAmount
  );
}

/** Error responses are state, not outcomes — never worth replaying for a day. */
export function isErrorResponse(response) {
  return Boolean(response && typeof response === 'object' && response.error);
}

/** Calendar month key for the global free-clip ceiling. */
export function monthKey(now = Date.now()) {
  return new Date(now).toISOString().slice(0, 7); // YYYY-MM
}

/** Calendar day key for the per-address free-clip ceiling. */
export function dayKey(now = Date.now()) {
  return new Date(now).toISOString().slice(0, 10); // YYYY-MM-DD
}

// ticketTTLms is overridable so the contract tests can exercise expiry.
export function createStores({ ticketTTLms = TICKET_TTL_MS } = {}) {
  const tickets = new Map(); // id → { userID, digest, snapshotBase64, expiresAt }
  const wallets = new Map(); // userID → { entries: [{delta, reason, at}], holds: Map<id, amount>, resolved: Map<id, 'settled'|'released'> }
  const idempotency = new Map(); // `${userID}:${key}` → Promise<response>
  const rateBuckets = new Map(); // key → { count, windowStart }
  const reports = new Map(); // reportID → { userID, report, expiresAt }
  const briefs = new Map(); // briefID → { userID, brief, expiresAt }
  const videoJobs = new Map(); // `${userID}:${videoID}` → { state: 'pending'|'delivered', url, expiresAt }
  // Free clips (task J8): per-user lifetime holds/uses + the global monthly
  // count. A hold counts against both until it resolves, so two concurrent
  // taps can never slip a third free clip through.
  const freeClips = new Map(); // userID → { holds: Map<id, month>, resolved: Map<id, 'settled'|'released'>, settled: number }
  // 'YYYY-MM' → clips ATTEMPTED this month. Never decremented: a release
  // refunds the reader, not the bill we already ran at fal.
  const freeClipMonths = new Map();
  const freeClipIPs = new Map(); // ipKey → { day, count }
  // transactionID → userID, forever. The GLOBAL redemption record behind
  // /v1/credits/grant (audit M-1): per-user idempotency alone scoped the
  // replay check to `${userID}:grant:${txn}`, so one captured receipt JWS
  // replayed under rotated identities credited every one of them afresh.
  const redeemedTransactions = new Map();
  // userID → { tier, expiresAt }: what /v1/entitlement proved from a verified
  // subscription receipt. Expiry is the receipt's own; past it the identity
  // reads as free again until the client re-proves.
  const tiers = new Map();
  // `${dayKey}:${key}` → count. The per-identity and global daily exchange
  // quotas (audit M-2). Fixed-window by UTC day, refundable on the same
  // conditions that release a wallet hold.
  const dailyCounters = new Map();

  /** Deletes reports past retention; returns how many went. */
  function sweepReports(now) {
    let removed = 0;
    for (const [id, entry] of reports) {
      if (entry.expiresAt <= now) {
        reports.delete(id);
        removed += 1;
      }
    }
    return removed;
  }

  function wallet(userID) {
    let w = wallets.get(userID);
    if (!w) {
      // Wallets start EMPTY. The onboarding grant this used to seed is
      // replaced by the free-clip accounting below (task J8): 2 free clips
      // per user lifetime, counted server-side — never a wallet credit
      // handed out at install.
      w = { entries: [], holds: new Map(), resolved: new Map() };
      wallets.set(userID, w);
    }
    return w;
  }

  function freeClipAccount(userID) {
    let account = freeClips.get(userID);
    if (!account) {
      account = { holds: new Map(), resolved: new Map(), settled: 0 };
      freeClips.set(userID, account);
    }
    return account;
  }

  function balance(w) {
    return w.entries.reduce((sum, e) => sum + e.delta, 0);
  }

  function held(w) {
    return [...w.holds.values()].reduce((sum, hold) => sum + hold.amount, 0);
  }

  /**
   * Drops holds old enough that no live request can still own them. A hold
   * outlives its request only when the process died between reserve and settle
   * — a deploy mid-generation — and such a hold is invisible to the user while
   * permanently subtracting from `available`. Runs before every wallet read.
   */
  function reclaimStale(w, now = Date.now()) {
    for (const [id, hold] of w.holds) {
      if (now - hold.at >= LIMITS.staleHoldReclaimMS) {
        w.holds.delete(id);
        w.resolved.set(id, 'released');
      }
    }
  }

  return {
    createTicket(userID, digest, snapshotBase64 = null) {
      const id = randomUUID();
      tickets.set(id, { userID, digest, snapshotBase64, expiresAt: Date.now() + ticketTTLms });
      return { id, expiresAt: new Date(Date.now() + ticketTTLms).toISOString() };
    },

    takeTicket(id, userID) {
      const ticket = tickets.get(id);
      if (!ticket) return null;
      // An expired ticket must be dropped, not just refused: uncommitted
      // tickets are the NORMAL case, and each one holds its snapshot string.
      // Returning early here leaked every one of them for the process's life.
      if (ticket.expiresAt < Date.now()) {
        tickets.delete(id);
        return null;
      }
      if (ticket.userID !== userID) return null;
      tickets.delete(id);
      return ticket;
    },

    deleteTicket(id, userID) {
      const ticket = tickets.get(id);
      if (ticket && ticket.userID === userID) tickets.delete(id);
    },

    /** Read-only: an unseeded wallet is projected, never written. */
    walletView(userID) {
      const w = wallets.get(userID);
      if (!w) return { balance: 0, available: 0 };
      reclaimStale(w);
      return { balance: balance(w), available: balance(w) - held(w) };
    },

    /**
     * Binds a StoreKit transaction to the FIRST identity that redeems it,
     * globally. Same user again → { claimed: true } (an honest double-tap or
     * a retry after a crash; the per-user idempotency wrapper replays the
     * response). A DIFFERENT user presenting the same transaction is a
     * captured receipt replayed under a rotated token — refused with its own
     * error code so the client can treat it as terminal, not a receipt bug.
     */
    claimTransaction(transactionID, userID) {
      const owner = redeemedTransactions.get(transactionID);
      if (owner === undefined) {
        redeemedTransactions.set(transactionID, userID);
        return { claimed: true };
      }
      if (owner === userID) return { claimed: true };
      return { error: 'receipt_already_redeemed' };
    },

    /**
     * Credits a verified vial purchase. The amount comes from the server-side
     * product map, never the client; idempotency (by transactionID) is the
     * route's job via `idempotent`.
     */
    grant(userID, amount, reason = 'purchase') {
      if (!validAmount(amount)) return { error: 'invalid_amount' };
      const w = wallet(userID);
      w.entries.push({ delta: amount, reason, at: Date.now() });
      return { granted: amount, balance: balance(w) };
    },

    reserve(userID, amount) {
      if (!validAmount(amount)) return { error: 'invalid_amount' };
      const w = wallet(userID);
      reclaimStale(w);
      const available = balance(w) - held(w);
      if (available < amount) return { error: 'insufficient_credits', available };
      const id = randomUUID();
      w.holds.set(id, { amount, at: Date.now() });
      return { reservationID: id, amount };
    },

    settle(userID, reservationID) {
      const w = wallet(userID);
      if (w.resolved.get(reservationID) === 'settled') return { settled: true };
      const hold = w.holds.get(reservationID);
      if (hold === undefined) return { error: 'unknown_reservation' };
      w.holds.delete(reservationID);
      w.resolved.set(reservationID, 'settled');
      w.entries.push({ delta: -hold.amount, reason: 'video_spend', at: Date.now() });
      return { settled: true };
    },

    release(userID, reservationID) {
      const w = wallet(userID);
      if (w.resolved.get(reservationID) === 'released') return { released: true };
      if (!w.holds.has(reservationID)) return { error: 'unknown_reservation' };
      w.holds.delete(reservationID);
      w.resolved.set(reservationID, 'released');
      return { released: true };
    },

    /**
     * Idempotency: replay the stored response for a repeated key.
     *
     * The in-flight PROMISE is what gets stored, not the settled value, so two
     * concurrent calls on one key share a single produce() — the same claim-
     * first guarantee stores-redis.js makes. Without it the dev store could
     * never reproduce the production double-spend, and the drift stayed
     * invisible because the contract test only called this sequentially.
     */
    async idempotent(userID, key, produce) {
      if (!key) return produce();
      const mapKey = `${userID}:${key}`;
      const existing = idempotency.get(mapKey);
      if (existing) return existing;
      const inflight = (async () => produce())();
      idempotency.set(mapKey, inflight);
      let response;
      try {
        response = await inflight;
      } catch (error) {
        idempotency.delete(mapKey); // a throw is never a replayable outcome
        throw error;
      }
      // Don't cache failures: a 402 from an empty wallet would otherwise be
      // replayed for the key's whole life, so a user who buys credits and
      // retries correctly (same key) can never spend them.
      if (isErrorResponse(response)) idempotency.delete(mapKey);
      return response;
    },

    /** Diagnostics for the dev store only; Redis reclaims by TTL instead. */
    ticketCount() {
      return tickets.size;
    },

    /**
     * Files a user-triggered report of a reply (guideline 1.2). Retention is
     * enforced on every write — the dev store has no timer to wait on — and
     * a duplicate reportID never files twice, so the route's idempotency
     * wrapper and this store agree on what a double-tap means.
     */
    fileReport(userID, report) {
      if (!REPORT_UUID_RE.test(report?.reportID ?? '')) return { error: 'invalid_report' };
      sweepReports(Date.now());
      if (!reports.has(report.reportID)) {
        reports.set(report.reportID, {
          userID,
          report,
          expiresAt: Date.now() + REPORT_RETENTION_MS,
        });
      }
      return { received: true };
    },

    /** How many un-expired reports stand — for one user, or all of them. */
    reportCount(userID) {
      sweepReports(Date.now());
      let count = 0;
      for (const entry of reports.values()) {
        if (userID === undefined || entry.userID === userID) count += 1;
      }
      return count;
    },

    /** The retention sweep, callable with a clock so tests can exercise it. */
    sweepExpiredReports(now = Date.now()) {
      return sweepReports(now);
    },

    // -- verdict briefs (tasks J2/J4) ---------------------------------------
    // A brief is the server-stored generation intent behind one positive
    // verdict: the client can only point at one, never supply prompt text.

    createBrief(userID, brief) {
      const id = randomUUID();
      const expiresAt = Date.now() + LIMITS.videoBriefTTLms;
      // Expired briefs are the normal case (most offers are never tapped);
      // sweep opportunistically so they don't accumulate for the process's life.
      for (const [key, entry] of briefs) {
        if (entry.expiresAt <= Date.now()) briefs.delete(key);
      }
      briefs.set(id, { userID, brief, expiresAt });
      return { id, expiresAt: new Date(expiresAt).toISOString() };
    },

    /** Non-consuming read — a failed generation may be retried on the same brief. */
    getBrief(id, userID) {
      const entry = briefs.get(id);
      if (!entry) return null;
      if (entry.expiresAt <= Date.now()) {
        briefs.delete(id);
        return null;
      }
      if (entry.userID !== userID) return null;
      return entry.brief;
    },

    // -- video job claims (task J4 idempotency) -----------------------------
    // One videoID, one generation: a double-tap or a network retry claims the
    // same job and either waits (pending) or replays the delivered clip free
    // of charge. Only an explicit failure reopens the claim.

    claimVideoJob(userID, videoID) {
      const key = `${userID}:${videoID}`;
      const existing = videoJobs.get(key);
      if (existing && existing.expiresAt > Date.now()) {
        if (existing.state === 'delivered') return { delivered: true, url: existing.url };
        return { inFlight: true };
      }
      videoJobs.set(key, { state: 'pending', url: null, expiresAt: Date.now() + 10 * 60_000 });
      return { fresh: true };
    },

    completeVideoJob(userID, videoID, url) {
      videoJobs.set(`${userID}:${videoID}`, {
        state: 'delivered',
        url,
        expiresAt: Date.now() + 60 * 60_000,
      });
    },

    failVideoJob(userID, videoID) {
      videoJobs.delete(`${userID}:${videoID}`);
    },

    // -- free clips (task J8) -----------------------------------------------
    // Server-authoritative: 2 per user LIFETIME, plus a global monthly
    // ceiling on free-clip spend. Reserve/settle/release mirrors the wallet:
    // a failed generation never consumes a free clip.

    freeClipView(userID, now = Date.now()) {
      const account = freeClips.get(userID);
      const used = account ? account.settled + account.holds.size : 0;
      const open = (freeClipMonths.get(monthKey(now)) ?? 0) < CONFIG.video.freeClipMonthlyCeiling;
      return {
        remaining: Math.max(0, CONFIG.video.freeClipsPerUser - used),
        ceilingOpen: open,
      };
    },

    /** How many free clips this address has started today (task J10). */
    freeClipIPCount(ipKey, now = Date.now()) {
      const entry = freeClipIPs.get(ipKey);
      if (!entry || entry.day !== dayKey(now)) return 0;
      return entry.count;
    },

    reserveFreeClip(userID, { now = Date.now(), ipKey = null } = {}) {
      const account = freeClipAccount(userID);
      if (account.settled + account.holds.size >= CONFIG.video.freeClipsPerUser) {
        return { error: 'free_exhausted' };
      }
      const month = monthKey(now);
      const monthCount = freeClipMonths.get(month) ?? 0;
      if (monthCount >= CONFIG.video.freeClipMonthlyCeiling) {
        return { error: 'free_ceiling' };
      }
      // Free clips are per token, and in anonymous attestation a token is free
      // to mint — so the address behind them is what actually bounds an
      // exhaustion run (task J10, config.js freeClipsPerIPPerDay).
      const day = dayKey(now);
      const ipEntry = ipKey ? freeClipIPs.get(ipKey) : null;
      const ipCount = ipEntry && ipEntry.day === day ? ipEntry.count : 0;
      if (ipKey && ipCount >= CONFIG.video.freeClipsPerIPPerDay) {
        return { error: 'free_ceiling' };
      }
      const id = randomUUID();
      account.holds.set(id, { month, at: now });
      // The month counter counts ATTEMPTS, not deliveries: releasing gives the
      // clip back to the READER, but fal has already been paid for the attempt.
      // Decrementing here would make the ceiling unbounded — abandon a
      // connection mid-generation and the spend un-counts itself.
      freeClipMonths.set(month, monthCount + 1);
      if (ipKey) freeClipIPs.set(ipKey, { day, count: ipCount + 1 });
      return { holdID: id };
    },

    settleFreeClip(userID, holdID) {
      const account = freeClipAccount(userID);
      if (account.resolved.get(holdID) === 'settled') return { settled: true };
      if (!account.holds.has(holdID)) return { error: 'unknown_hold' };
      account.holds.delete(holdID);
      account.resolved.set(holdID, 'settled');
      account.settled += 1;
      return { settled: true };
    },

    releaseFreeClip(userID, holdID) {
      const account = freeClipAccount(userID);
      if (account.resolved.get(holdID) === 'released') return { released: true };
      const hold = account.holds.get(holdID);
      if (hold === undefined) return { error: 'unknown_hold' };
      account.holds.delete(holdID);
      account.resolved.set(holdID, 'released');
      // The READER gets their free clip back — but the month's counter does
      // NOT move: we paid for the attempt whether or not it arrived, and the
      // ceiling exists to bound what we pay.
      return { released: true };
    },

    /**
     * Releases holds too old for any live request to own them — the durable
     * store runs this on a timer and at boot (stores-redis.js). Here the maps
     * die with the process, so a stale hold cannot outlive it; the method
     * exists so both stores answer the same interface.
     */
    reclaimStaleHolds(now = Date.now()) {
      let reclaimed = 0;
      for (const w of wallets.values()) {
        const before = w.holds.size;
        reclaimStale(w, now);
        reclaimed += before - w.holds.size;
      }
      // Free-clip holds strand exactly as wallet holds do — one of a reader's
      // two lifetime clips, gone with no way to ask for it back. The durable
      // store sweeps both; so must this one, or the two answer different
      // contracts.
      for (const account of freeClips.values()) {
        for (const [id, hold] of account.holds) {
          if (now - hold.at >= LIMITS.staleHoldReclaimMS) {
            account.holds.delete(id);
            account.resolved.set(id, 'released');
            reclaimed += 1;
          }
        }
      }
      return reclaimed;
    },

    /** Fixed-window rate limit; returns true when the call is allowed. */
    allow(key, limitPerMinute) {
      const now = Date.now();
      let bucket = rateBuckets.get(key);
      if (!bucket || now - bucket.windowStart >= 60_000) {
        bucket = { count: 0, windowStart: now };
        rateBuckets.set(key, bucket);
      }
      bucket.count += 1;
      return bucket.count <= limitPerMinute;
    },

    // -- daily quotas + tier (audit M-2) ------------------------------------
    // The exchange route consults these BEFORE the provider handshake. The
    // counter increments first and compares second (same shape as `allow`),
    // so two concurrent requests can never both slip under the ceiling.

    /** Counts one attempt against a per-UTC-day window; allowed while <= limit. */
    allowDaily(key, limit, now = Date.now()) {
      // Yesterday's windows are garbage the moment the day rolls; sweep them
      // so a long-lived dev process doesn't hold every day it ever counted.
      const today = dayKey(now);
      for (const stored of dailyCounters.keys()) {
        if (!stored.startsWith(`${today}:`)) dailyCounters.delete(stored);
      }
      const mapKey = `${today}:${key}`;
      const count = (dailyCounters.get(mapKey) ?? 0) + 1;
      dailyCounters.set(mapKey, count);
      return { allowed: count <= limit, count };
    },

    /**
     * Gives one attempt back — the quota analogue of releasing a wallet hold,
     * called on the same conditions (crisis, client gone, pre-stream
     * failure). A rolled day makes this a no-op: yesterday's window is gone
     * and today's was never charged.
     */
    refundDaily(key, now = Date.now()) {
      const mapKey = `${dayKey(now)}:${key}`;
      const count = dailyCounters.get(mapKey);
      if (count === undefined) return;
      if (count <= 1) dailyCounters.delete(mapKey);
      else dailyCounters.set(mapKey, count - 1);
    },

    /** Records a proved subscription tier until the receipt's own expiry. */
    setTier(userID, tier, expiresAtMs) {
      if (expiresAtMs <= Date.now()) return { error: 'expired' };
      tiers.set(userID, { tier, expiresAt: expiresAtMs });
      return { tier, expiresAt: expiresAtMs };
    },

    /** The tier this identity proved, or 'free' once the proof has expired. */
    tierOf(userID, now = Date.now()) {
      const entry = tiers.get(userID);
      if (!entry || entry.expiresAt <= now) {
        tiers.delete(userID);
        return 'free';
      }
      return entry.tier;
    },

    /** Drops a proved tier — the refund/revocation path (audit M-4). */
    clearTier(userID) {
      tiers.delete(userID);
    },
  };
}
