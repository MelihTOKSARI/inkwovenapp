// In-memory stores for local dev and tests. Production swaps these for Redis
// (rate-limit counters, tickets, idempotency) and Postgres (credit ledger) —
// the route handlers only touch this interface.
import { randomUUID } from 'node:crypto';
import { CONFIG, LIMITS } from './config.js';

const TICKET_TTL_MS = 60_000;

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

// ticketTTLms is overridable so the contract tests can exercise expiry.
export function createStores({ ticketTTLms = TICKET_TTL_MS } = {}) {
  const tickets = new Map(); // id → { userID, digest, snapshotBase64, expiresAt }
  const wallets = new Map(); // userID → { entries: [{delta, reason, at}], holds: Map<id, amount>, resolved: Map<id, 'settled'|'released'> }
  const idempotency = new Map(); // `${userID}:${key}` → Promise<response>
  const rateBuckets = new Map(); // key → { count, windowStart }

  function wallet(userID) {
    let w = wallets.get(userID);
    if (!w) {
      // Seed the onboarding grant — 1 free moving-picture credit. Only a
      // WRITE seeds it: a bare GET /v1/credits used to materialise a wallet
      // per token, which made grants farmable by reading with a fresh header.
      w = {
        entries: [{ delta: CONFIG.onboardingCreditGrant, reason: 'onboarding_grant', at: Date.now() }],
        holds: new Map(),
        resolved: new Map(),
      };
      wallets.set(userID, w);
    }
    return w;
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
      if (!w) {
        return { balance: CONFIG.onboardingCreditGrant, available: CONFIG.onboardingCreditGrant };
      }
      return { balance: balance(w), available: balance(w) - held(w) };
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
