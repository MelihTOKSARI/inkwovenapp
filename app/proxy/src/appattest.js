// App Attest verification (audit T3/M-3) — the real implementation behind the
// seam attest.js always promised.
//
// WHAT THIS DOES. Verifies Apple's attestation object the way Apple documents
// it (Establishing your app's integrity, DeviceCheck):
//   1. decode the CBOR envelope { fmt: 'apple-appattest', attStmt: { x5c,
//      receipt }, authData }
//   2. walk the x5c chain link by link to the operator-configured Apple App
//      Attestation Root CA — raw-DER equality against the anchor, exactly as
//      receipts.js does for StoreKit, so an attacker-minted self-signed chain
//      buys nothing
//   3. nonce: SHA256(authData || SHA256(challenge)) must equal the nonce
//      Apple embedded in the leaf certificate (OID 1.2.840.113635.100.8.2)
//   4. rpIdHash (authData[0..32]) must equal SHA256("<teamID>.<bundleID>")
//   5. the attestation's counter must be 0, and the attested credentialId
//      must equal both the presented keyID and SHA256(leaf public key)
//
// Later requests don't repeat attestation: the key trades it once for a
// short-lived HS256 session token (issued by the caller, see attest.js), and
// renews by ASSERTION — a signature over SHA256(authenticatorData ||
// SHA256(challenge)) with the stored public key, its counter strictly
// increasing so a captured assertion cannot be replayed.
//
// REQUIRES A HUMAN (operator-supplied, never stubbed):
//   INK_APPATTEST_ROOT_CA — Apple App Attestation Root CA, PEM, from
//     https://www.apple.com/certificateauthority/ (a certificate pasted from
//     memory is not a trust anchor)
//   INK_TEAM_ID + INK_BUNDLE_ID — the app's real identifiers
//   INK_SESSION_SECRET — ≥32 bytes of entropy for the session tokens
import { createHash, createHmac, createPublicKey, createVerify, randomUUID, timingSafeEqual, X509Certificate } from 'node:crypto';

export class AppAttestError extends Error {
  constructor(code) {
    super(code);
    this.name = 'AppAttestError';
    this.code = code;
  }
}

// -- minimal CBOR (RFC 8949) -------------------------------------------------
// Only what an Apple attestation/assertion actually uses: definite-length
// maps, arrays, byte strings, text strings and unsigned integers. Anything
// else in the input is malformed by construction and fails closed.

function decodeCBOR(buffer) {
  const view = { buffer, offset: 0 };
  const value = readItem(view);
  return value;
}

function readItem(view) {
  if (view.offset >= view.buffer.length) throw new AppAttestError('malformed_cbor');
  const initial = view.buffer[view.offset];
  view.offset += 1;
  const major = initial >> 5;
  const info = initial & 0x1f;

  const length = readLength(view, info);
  switch (major) {
    case 0: // unsigned int
      return length;
    case 2: { // byte string
      const bytes = view.buffer.subarray(view.offset, view.offset + length);
      if (bytes.length !== length) throw new AppAttestError('malformed_cbor');
      view.offset += length;
      return Buffer.from(bytes);
    }
    case 3: { // text string
      const bytes = view.buffer.subarray(view.offset, view.offset + length);
      if (bytes.length !== length) throw new AppAttestError('malformed_cbor');
      view.offset += length;
      return bytes.toString('utf8');
    }
    case 4: { // array
      const array = [];
      for (let i = 0; i < length; i += 1) array.push(readItem(view));
      return array;
    }
    case 5: { // map
      const map = {};
      for (let i = 0; i < length; i += 1) {
        const key = readItem(view);
        const value = readItem(view);
        if (typeof key !== 'string') throw new AppAttestError('malformed_cbor');
        map[key] = value;
      }
      return map;
    }
    default:
      throw new AppAttestError('malformed_cbor');
  }
}

function readLength(view, info) {
  if (info < 24) return info;
  const widths = { 24: 1, 25: 2, 26: 4 };
  const width = widths[info];
  if (!width) throw new AppAttestError('malformed_cbor'); // 8-byte lengths have no business here
  if (view.offset + width > view.buffer.length) throw new AppAttestError('malformed_cbor');
  let value = 0;
  for (let i = 0; i < width; i += 1) {
    value = value * 256 + view.buffer[view.offset + i];
  }
  view.offset += width;
  return value;
}

// -- pieces ------------------------------------------------------------------

/** authData layout (WebAuthn §6.1): rpIdHash(32) flags(1) signCount(4) [attested credential data]. */
function parseAuthData(authData) {
  if (!Buffer.isBuffer(authData) || authData.length < 37) throw new AppAttestError('malformed_authdata');
  const rpIdHash = authData.subarray(0, 32);
  const signCount = authData.readUInt32BE(33);
  let credentialID = null;
  if (authData.length >= 55) {
    const credIDLength = authData.readUInt16BE(53);
    credentialID = authData.subarray(55, 55 + credIDLength);
    if (credentialID.length !== credIDLength) throw new AppAttestError('malformed_authdata');
  }
  return { rpIdHash, signCount, credentialID };
}

// DER bytes of OID 1.2.840.113635.100.8.2 — the extension Apple stamps the
// expected nonce into on the attestation leaf.
const NONCE_OID_DER = Buffer.from([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]);

/**
 * Pulls the 32-byte nonce out of the leaf certificate's Apple extension.
 * The extension value is a small DER SEQUENCE wrapping a single OCTET
 * STRING of exactly 32 bytes; rather than a full ASN.1 parser, this locates
 * the extension by its OID bytes and takes the 04 20 (OCTET STRING, len 32)
 * that follows — the only 32-byte octet string inside that extension.
 */
function nonceFromLeaf(leaf) {
  const der = leaf.raw;
  const at = der.indexOf(NONCE_OID_DER);
  if (at === -1) throw new AppAttestError('missing_nonce');
  // Search a bounded window after the OID for the octet-string header.
  const window = der.subarray(at, at + 64);
  for (let i = NONCE_OID_DER.length; i < window.length - 1; i += 1) {
    if (window[i] === 0x04 && window[i + 1] === 0x20) {
      const start = at + i + 2;
      const nonce = der.subarray(start, start + 32);
      if (nonce.length === 32) return Buffer.from(nonce);
    }
  }
  throw new AppAttestError('missing_nonce');
}

function verifyChainToAnchor(certs, anchor, now = new Date()) {
  if (certs.length < 2) throw new AppAttestError('missing_chain');
  for (const cert of certs) {
    if (new Date(cert.validFrom) > now || new Date(cert.validTo) < now) {
      throw new AppAttestError('certificate_expired');
    }
  }
  for (let i = 0; i < certs.length - 1; i += 1) {
    if (!certs[i].checkIssued(certs[i + 1]) || !certs[i].verify(certs[i + 1].publicKey)) {
      throw new AppAttestError('broken_chain');
    }
  }
  const top = certs[certs.length - 1];
  if (top.raw.equals(anchor.raw)) return;
  // Apple serves a 2-cert chain (leaf, intermediate) whose intermediate is
  // ISSUED by the root rather than being it — accept that exact shape by
  // verifying the top against the anchor.
  if (top.checkIssued(anchor) && top.verify(anchor.publicKey)) return;
  throw new AppAttestError('untrusted_root');
}

/** SHA-256 of the uncompressed EC point — Apple's key identifier. */
function keyIDOfPublicKey(publicKey) {
  const raw = publicKey.export({ format: 'der', type: 'spki' });
  // The uncompressed point is the last 65 bytes of a P-256 SPKI (0x04 || X || Y).
  const point = raw.subarray(raw.length - 65);
  if (point[0] !== 0x04) throw new AppAttestError('malformed_key');
  return createHash('sha256').update(point).digest();
}

// -- the verifier ------------------------------------------------------------

/**
 * Builds the App Attest verifier, or null when the operator has not supplied
 * the pieces — the caller must treat null as "cannot verify" and refuse.
 */
export function createAppAttestVerifier(env = process.env) {
  const rootPEM = env.INK_APPATTEST_ROOT_CA;
  const teamID = env.INK_TEAM_ID;
  const bundleID = env.INK_BUNDLE_ID;
  if (!rootPEM || !teamID || !bundleID) return null;

  let anchor;
  try {
    anchor = new X509Certificate(rootPEM);
  } catch {
    return null; // a malformed anchor is misconfiguration, never trust
  }

  const appIDHash = createHash('sha256').update(`${teamID}.${bundleID}`).digest();

  return {
    /**
     * Verifies a first-time attestation. Returns the attested public key
     * (PEM) on success; throws AppAttestError on any failure.
     */
    verifyAttestation({ attestationBase64, keyIDBase64, challenge }) {
      let decoded;
      try {
        decoded = decodeCBOR(Buffer.from(attestationBase64, 'base64'));
      } catch {
        throw new AppAttestError('malformed_attestation');
      }
      if (decoded?.fmt !== 'apple-appattest') throw new AppAttestError('wrong_format');
      const x5c = decoded?.attStmt?.x5c;
      const authData = decoded?.authData;
      if (!Array.isArray(x5c) || !Buffer.isBuffer(authData)) {
        throw new AppAttestError('malformed_attestation');
      }

      let certs;
      try {
        certs = x5c.map((der) => new X509Certificate(der));
      } catch {
        throw new AppAttestError('malformed_chain');
      }
      verifyChainToAnchor(certs, anchor);

      // Nonce: this attestation answers OUR challenge, freshly.
      const clientDataHash = createHash('sha256').update(challenge).digest();
      const expectedNonce = createHash('sha256')
        .update(Buffer.concat([authData, clientDataHash]))
        .digest();
      const leafNonce = nonceFromLeaf(certs[0]);
      if (!timingSafeEqual(expectedNonce, leafNonce)) throw new AppAttestError('bad_nonce');

      const { rpIdHash, signCount, credentialID } = parseAuthData(authData);
      if (!timingSafeEqual(rpIdHash, appIDHash)) throw new AppAttestError('wrong_app');
      if (signCount !== 0) throw new AppAttestError('bad_counter');

      const keyID = Buffer.from(keyIDBase64, 'base64');
      const publicKey = createPublicKey(certs[0].publicKey);
      const derivedKeyID = keyIDOfPublicKey(publicKey);
      if (
        !credentialID ||
        credentialID.length !== keyID.length ||
        !timingSafeEqual(credentialID, keyID) ||
        !timingSafeEqual(derivedKeyID, keyID)
      ) {
        throw new AppAttestError('key_mismatch');
      }

      return { publicKeyPEM: publicKey.export({ format: 'pem', type: 'spki' }).toString() };
    },

    /**
     * Verifies a renewal assertion against the stored key. Returns the new
     * counter; throws AppAttestError on any failure, including a counter
     * that does not strictly increase (a replayed assertion).
     */
    verifyAssertion({ assertionBase64, publicKeyPEM, previousCounter, challenge }) {
      let decoded;
      try {
        decoded = decodeCBOR(Buffer.from(assertionBase64, 'base64'));
      } catch {
        throw new AppAttestError('malformed_assertion');
      }
      const { signature, authenticatorData } = decoded ?? {};
      if (!Buffer.isBuffer(signature) || !Buffer.isBuffer(authenticatorData)) {
        throw new AppAttestError('malformed_assertion');
      }

      const clientDataHash = createHash('sha256').update(challenge).digest();
      const nonce = createHash('sha256')
        .update(Buffer.concat([authenticatorData, clientDataHash]))
        .digest();

      const verifier = createVerify('sha256');
      verifier.update(nonce);
      verifier.end();
      const ok = verifier.verify(createPublicKey(publicKeyPEM), signature);
      if (!ok) throw new AppAttestError('bad_signature');

      const { rpIdHash, signCount } = parseAuthData(authenticatorData);
      if (!timingSafeEqual(rpIdHash, appIDHash)) throw new AppAttestError('wrong_app');
      if (!(signCount > previousCounter)) throw new AppAttestError('replayed_assertion');
      return { counter: signCount };
    },
  };
}

// -- session tokens ----------------------------------------------------------
// A compact HS256 JWT, hand-rolled over node:crypto: three dependencies is
// this proxy's whole supply chain, and a signed 100-byte token does not
// justify a fourth.

function b64url(buffer) {
  return Buffer.from(buffer).toString('base64url');
}

export const SESSION_TOKEN_TTL_S = 3600;

/**
 * Builds the session-token mint/verify pair, or null without a secret.
 * The token is what replaces the raw x-ink-user identity: short-lived,
 * server-minted, and signed — a fabricated value verifies nothing.
 */
export function createSessionTokens(env = process.env) {
  const secret = env.INK_SESSION_SECRET;
  if (!secret || secret.length < 32) return null;

  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));

  return {
    mint(userID, { now = Date.now(), ttlSeconds = SESSION_TOKEN_TTL_S } = {}) {
      const exp = Math.floor(now / 1000) + ttlSeconds;
      const payload = b64url(JSON.stringify({ sub: userID, exp }));
      const signature = createHmac('sha256', secret).update(`${header}.${payload}`).digest();
      return { token: `${header}.${payload}.${b64url(signature)}`, expiresAt: exp * 1000 };
    },

    verify(token, { now = Date.now() } = {}) {
      const parts = typeof token === 'string' ? token.split('.') : [];
      if (parts.length !== 3) throw new AppAttestError('bad_token');
      const expected = createHmac('sha256', secret).update(`${parts[0]}.${parts[1]}`).digest();
      const presented = Buffer.from(parts[2], 'base64url');
      if (presented.length !== expected.length || !timingSafeEqual(presented, expected)) {
        throw new AppAttestError('bad_token');
      }
      let payload;
      try {
        payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
      } catch {
        throw new AppAttestError('bad_token');
      }
      if (typeof payload.sub !== 'string' || !payload.sub) throw new AppAttestError('bad_token');
      if (typeof payload.exp !== 'number' || payload.exp * 1000 <= now) {
        throw new AppAttestError('expired_token');
      }
      return { userID: payload.sub };
    },
  };
}
