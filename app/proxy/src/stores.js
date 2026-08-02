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
  const freeClipMonths = new Map(); // 'YYYY-MM' → open count (held + settled)

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
    return [...w.holds.values()].reduce((sum, amount) => sum + amount, 0);
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
      return { balance: balance(w), available: balance(w) - held(w) };
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
      const available = balance(w) - held(w);
      if (available < amount) return { error: 'insufficient_credits', available };
      const id = randomUUID();
      w.holds.set(id, amount);
      return { reservationID: id, amount };
    },

    settle(userID, reservationID) {
      const w = wallet(userID);
      if (w.resolved.get(reservationID) === 'settled') return { settled: true };
      const amount = w.holds.get(reservationID);
      if (amount === undefined) return { error: 'unknown_reservation' };
      w.holds.delete(reservationID);
      w.resolved.set(reservationID, 'settled');
      w.entries.push({ delta: -amount, reason: 'video_spend', at: Date.now() });
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

    reserveFreeClip(userID, now = Date.now()) {
      const account = freeClipAccount(userID);
      if (account.settled + account.holds.size >= CONFIG.video.freeClipsPerUser) {
        return { error: 'free_exhausted' };
      }
      const month = monthKey(now);
      const monthCount = freeClipMonths.get(month) ?? 0;
      if (monthCount >= CONFIG.video.freeClipMonthlyCeiling) {
        return { error: 'free_ceiling' };
      }
      const id = randomUUID();
      account.holds.set(id, month);
      freeClipMonths.set(month, monthCount + 1);
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
      const month = account.holds.get(holdID);
      if (month === undefined) return { error: 'unknown_hold' };
      account.holds.delete(holdID);
      account.resolved.set(holdID, 'released');
      // The release reopens the month's ceiling — the clip never happened.
      freeClipMonths.set(month, Math.max(0, (freeClipMonths.get(month) ?? 1) - 1));
      return { released: true };
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
  };
}
