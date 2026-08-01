// Identity verification seam (launch blocker F-auth).
//
// WHAT THIS IS: the single choke point every request passes through, and a
// pluggable verifier behind it. WHAT THIS IS NOT: an App Attest
// implementation. No Apple key handling is invented here — binding a real
// verifier needs a human to supply the pieces listed under REQUIRES A HUMAN.
//
// The seam FAILS CLOSED. With no verifier bound, production rejects every
// request; the pass-through 'anonymous' mode must be opted into explicitly by
// INK_ATTESTATION_MODE, so a missing secret can never silently downgrade
// identity to "whatever string the client typed".
//
// REQUIRES A HUMAN (do not stub these):
//   1. A server-issued challenge endpoint, so the nonce is never client-chosen.
//   2. POST /v1/attest taking {keyId, attestationObject, challenge}, verifying
//      the CBOR attestation chain against Apple's App Attest root CA, checking
//      nonce == SHA256(authenticatorData || SHA256(challenge)),
//      rpIdHash == SHA256("<teamID>.<bundleID>"), signCount == 0, and
//      credentialId == SHA256(publicKey). Needs the real team + bundle IDs.
//   3. An identity table mapping keyId → a server-MINTED opaque userID. The
//      server mints it; the client's own string is never trusted as identity.
//   4. Either per-request assertions (client signs SHA256(body||challenge),
//      server verifies signature + strictly-increasing counter) or — cheaper
//      for SSE — trade the attestation once for a short-lived signed bearer
//      JWT whose key lives in Fly secrets, replacing x-ink-user outright.

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
 *   'anonymous' — pass-through: the x-ink-user token IS the identity. Correct
 *                 for local dev and tests; must be set explicitly anywhere else.
 *   'required'  — fail closed. The default in production. Rejects everything
 *                 until a real verifier is bound via `options.verify`.
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

  return {
    mode: 'required',
    async verify() {
      throw new AttestationError('attestation_required', 401);
    },
  };
}
