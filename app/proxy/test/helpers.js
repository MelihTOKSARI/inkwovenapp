// Shared fixtures. The routes sniff snapshot magic bytes and verify the
// SHA-256 the client committed to, so tests need real image bytes and a real
// digest rather than the placeholder strings they used before.
import { createHash } from 'node:crypto';

/** A valid 1×1 PNG — the natural format for ink line art with transparency. */
export const PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

export const PNG_BYTES = Buffer.from(PNG_BASE64, 'base64');

/** A minimal JFIF header — enough for the sniffer, never decoded. */
export const JPEG_BYTES = Buffer.concat([
  Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]),
  Buffer.from('JFIF\0', 'latin1'),
  Buffer.alloc(32, 0x20),
]);
export const JPEG_BASE64 = JPEG_BYTES.toString('base64');

/** Lowercase SHA-256 hex, matching InkCore/Snapshot.swift. */
export const digestOf = (buffer) => createHash('sha256').update(buffer).digest('hex');
