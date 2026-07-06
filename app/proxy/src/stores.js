// In-memory stores for local dev and tests. Production swaps these for Redis
// (rate-limit counters, tickets, idempotency) and Postgres (credit ledger) —
// the route handlers only touch this interface.
import { randomUUID } from 'node:crypto';
import { CONFIG } from './config.js';

const TICKET_TTL_MS = 60_000;

export function createStores() {
  const tickets = new Map(); // id → { userID, digest, expiresAt }
  const wallets = new Map(); // userID → { entries: [{delta, reason, at}], holds: Map<id, amount>, resolved: Map<id, 'settled'|'released'> }
  const idempotency = new Map(); // `${userID}:${key}` → response
  const rateBuckets = new Map(); // key → { count, windowStart }

  function wallet(userID) {
    let w = wallets.get(userID);
    if (!w) {
      // Seed the onboarding grant — 1 free moving-picture credit.
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
    createTicket(userID, digest) {
      const id = randomUUID();
      tickets.set(id, { userID, digest, expiresAt: Date.now() + TICKET_TTL_MS });
      return { id, expiresAt: new Date(Date.now() + TICKET_TTL_MS).toISOString() };
    },

    takeTicket(id, userID) {
      const ticket = tickets.get(id);
      if (!ticket || ticket.userID !== userID || ticket.expiresAt < Date.now()) return null;
      tickets.delete(id);
      return ticket;
    },

    deleteTicket(id, userID) {
      const ticket = tickets.get(id);
      if (ticket && ticket.userID === userID) tickets.delete(id);
    },

    walletView(userID) {
      const w = wallet(userID);
      return { balance: balance(w), available: balance(w) - held(w) };
    },

    reserve(userID, amount) {
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

    /** Idempotency: replay the stored response for a repeated key. */
    idempotent(userID, key, produce) {
      if (!key) return produce();
      const mapKey = `${userID}:${key}`;
      if (idempotency.has(mapKey)) return idempotency.get(mapKey);
      const response = produce();
      idempotency.set(mapKey, response);
      return response;
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
