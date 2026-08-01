// Namespaced store keys.
//
// Every key that embeds a caller-influenced string (the x-ink-user token, an
// Idempotency-Key) used to be built by ':' concatenation, so the namespace was
// ambiguous: user 'victim:reserve' with key 'k' produced exactly the same
// Redis key as user 'victim' with key 'reserve:k'. Hashing the caller-supplied
// component makes every part fixed-width and separator-free, so no two
// distinct inputs can ever collide.
import { createHash } from 'node:crypto';

/** Fixed-width, separator-free digest of a caller-supplied key component. */
export function keyPart(value) {
  return createHash('sha256').update(String(value)).digest('hex').slice(0, 32);
}
