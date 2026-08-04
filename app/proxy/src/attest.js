// Identity verification seam (launch blocker F-auth / audit T3).
//
// The single choke point every request passes through. The App Attest
// implementation the earlier REQUIRES-A-HUMAN note demanded now exists in
// appattest.js: server-issued challenges, CBOR attestation verification
// against Apple's App Attest root, a durable keyId → server-minted identity
// table, and short-lived HS256 session tokens that replace the raw
// x-ink-user string. This file decides which verifier the hook consults.
//
// The seam FAILS CLOSED. With no verifier bound, production rejects every
// request; the pass-through 'anonymous' mode must be opted into explicitly by
// INK_ATTESTATION_MODE — and index.js refuses to BOOT production in it — so a
// missing secret can never silently downgrade identity to "whatever string
// the client typed".
import { createSessionTokens } from './appattest.js';

/** Thrown by a verifier to reject a caller; carries the wire status. */
export class AttestationError extends Error {
  constructor(code, status = 401) {
    super(code);
    this.name = 'AttestationError';
    this.code = code;
    this.status = status;
  }
}

/**
 * Builds the verifier the auth hook consults.
 *
 * Modes:
 *   'anonymous' — pass-through: the x-ink-user token IS the identity. Local
 *                 dev and tests ONLY; production refuses to boot in it.
 *   'appattest' — x-ink-user carries a server-minted HS256 session token,
 *                 traded for a verified App Attest attestation (appattest.js)
 *                 and renewed by assertion. A fabricated value verifies
 *                 nothing. Requires INK_SESSION_SECRET; missing or short
 *                 secrets degrade to 'required', never to trust.
 *   'required'  — fail closed. The default in production until the operator
 *                 binds 'appattest'.
 */
export function createAttestationVerifier(env = process.env, options = {}) {
  const mode = env.INK_ATTESTATION_MODE ?? (env.NODE_ENV === 'production' ? 'required' : 'anonymous');

  if (options.verify) {
    return { mode: 'bound', verify: options.verify };
  }

  if (mode === 'anonymous') {
    return {
      mode: 'anonymous',
      // The token is taken at face value. This is the pre-attestation
      // behaviour, kept only behind an explicit opt-in.
      async verify({ token }) {
        return { userID: token };
      },
    };
  }

  if (mode === 'appattest') {
    const sessions = createSessionTokens(env);
    if (sessions) {
      return {
        mode: 'appattest',
        async verify({ token }) {
          try {
            return sessions.verify(token);
          } catch (error) {
            throw new AttestationError(
              error?.code === 'expired_token' ? 'expired_token' : 'invalid_token',
              401,
            );
          }
        },
      };
    }
    // Asked for appattest without a usable secret: fail closed, loudly —
    // never fall through to trusting the header.
  }

  return {
    mode: 'required',
    async verify() {
      throw new AttestationError('attestation_required', 401);
    },
  };
}
