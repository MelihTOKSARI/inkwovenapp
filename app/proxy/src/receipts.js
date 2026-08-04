// StoreKit 2 receipt verification (task J10 / finding S2).
//
// WHY THIS EXISTS. `POST /v1/credits/grant` credits the server-side wallet
// from a transaction the client forwards. The first cut decoded the JWS and
// trusted its claims because "StoreKit already verified it on device" — which
// is true of the real app and worthless as a control, since under anonymous
// attestation the client is whatever speaks HTTP. Three base64url segments and
// any signature bought 20 credits, repeatable with a fresh transaction id.
// Credits buy clips, and clips cost real money at fal.
//
// WHAT THIS DOES. Verifies the JWS the way Apple documents it:
//   1. the x5c header carries leaf → intermediate → root, DER base64
//   2. the chain is checked link by link, and the root must be the anchor the
//      operator configured — not merely self-signed, or any self-signed cert
//      would do
//   3. every certificate is checked for validity dates
//   4. the ES256 signature is verified over `header.payload` with the leaf key
//   5. only then are the claims read, and they must match what the caller
//      asserted and the bundle we ship
//
// REQUIRES A HUMAN (do not stub): `INK_APPLE_ROOT_CA` must hold Apple's Root
// CA - G3 certificate in PEM, and `INK_BUNDLE_ID` the app's bundle id. Apple
// publishes the root at https://www.apple.com/certificateauthority/ — it is
// not reproduced here, because a certificate pasted from memory is not a trust
// anchor. With either missing, verification FAILS CLOSED and the route
// refuses to grant, exactly like attest.js.
import { createPublicKey, createVerify, X509Certificate } from 'node:crypto';

export class ReceiptError extends Error {
  constructor(code) {
    super(code);
    this.name = 'ReceiptError';
    this.code = code;
  }
}

function decodeSegment(segment) {
  return Buffer.from(segment, 'base64url');
}

function parseJSONSegment(segment) {
  try {
    return JSON.parse(decodeSegment(segment).toString('utf8'));
  } catch {
    throw new ReceiptError('malformed_receipt');
  }
}

/**
 * The chain walk + signature check shared by every Apple-signed JWS this
 * process reads — a transaction receipt or a server-notification envelope.
 * Returns the payload claims WITHOUT any bundle assertion; each caller
 * checks the bundle where its schema puts it.
 */
function verifyAppleJWS(jws, anchor, now) {
  const parts = typeof jws === 'string' ? jws.split('.') : [];
  if (parts.length !== 3) throw new ReceiptError('malformed_receipt');
  const [headerSegment, payloadSegment, signatureSegment] = parts;

  const header = parseJSONSegment(headerSegment);
  if (header.alg !== 'ES256') throw new ReceiptError('unsupported_alg');
  const chain = Array.isArray(header.x5c) ? header.x5c : [];
  if (chain.length < 2) throw new ReceiptError('missing_chain');

  let certs;
  try {
    certs = chain.map((der) => new X509Certificate(Buffer.from(der, 'base64')));
  } catch {
    throw new ReceiptError('malformed_chain');
  }

  // Validity dates, every link. An expired leaf is a replayed receipt.
  for (const cert of certs) {
    if (new Date(cert.validFrom) > now || new Date(cert.validTo) < now) {
      throw new ReceiptError('certificate_expired');
    }
  }

  // Each certificate must be issued and signed by the next one up.
  for (let i = 0; i < certs.length - 1; i += 1) {
    const child = certs[i];
    const parent = certs[i + 1];
    if (!child.checkIssued(parent) || !child.verify(parent.publicKey)) {
      throw new ReceiptError('broken_chain');
    }
  }

  // The top of the presented chain must BE our anchor. Comparing the raw
  // DER is what stops a self-signed chain minted by anyone: without this,
  // every check above would pass for a chain an attacker generated.
  const presentedRoot = certs[certs.length - 1];
  if (!presentedRoot.raw.equals(anchor.raw)) {
    throw new ReceiptError('untrusted_root');
  }

  // ES256 signatures are raw r||s; Node needs to be told that rather than
  // expecting DER.
  const signingInput = `${headerSegment}.${payloadSegment}`;
  const verifier = createVerify('sha256');
  verifier.update(signingInput);
  verifier.end();
  const ok = verifier.verify(
    { key: createPublicKey(certs[0].publicKey), dsaEncoding: 'ieee-p1363' },
    decodeSegment(signatureSegment),
  );
  if (!ok) throw new ReceiptError('bad_signature');

  return parseJSONSegment(payloadSegment);
}

function loadAnchor(env) {
  const rootPEM = env.INK_APPLE_ROOT_CA;
  const bundleID = env.INK_BUNDLE_ID;
  if (!rootPEM || !bundleID) return null;
  try {
    // A malformed anchor is a misconfiguration, not a reason to trust anything.
    return { anchor: new X509Certificate(rootPEM), bundleID };
  } catch {
    return null;
  }
}

/**
 * Builds the verifier the grant route consults.
 *
 * Returns null when no trust anchor is configured — the caller MUST treat that
 * as "cannot verify" and refuse, never as "verified".
 */
export function createReceiptVerifier(env = process.env) {
  const trust = loadAnchor(env);
  if (!trust) return null;

  /**
   * Verifies one StoreKit 2 signed transaction.
   * Returns its claims; throws ReceiptError on any failure.
   */
  return function verifyTransaction(jws, { now = new Date() } = {}) {
    const claims = verifyAppleJWS(jws, trust.anchor, now);
    if (claims.bundleId !== trust.bundleID) throw new ReceiptError('wrong_bundle');
    return claims;
  };
}

/**
 * Verifies an App Store Server Notification V2 envelope (audit M-4): the
 * same chain walk against the same anchor, but the bundle lives inside
 * `data.bundleId` rather than at the top level. Returns the envelope claims
 * ({ notificationType, subtype, data: { signedTransactionInfo, ... } }).
 * Null when unconfigured — the route answers 501, never trusts.
 */
export function createNotificationVerifier(env = process.env) {
  const trust = loadAnchor(env);
  if (!trust) return null;

  return function verifyNotification(signedPayload, { now = new Date() } = {}) {
    const envelope = verifyAppleJWS(signedPayload, trust.anchor, now);
    if (envelope?.data?.bundleId !== trust.bundleID) throw new ReceiptError('wrong_bundle');
    return envelope;
  };
}
