// POST /v1/report (guideline 1.2): user-triggered reporting of a reply.
// A cold path — nothing here touches the exchange machinery. The route must
// ack without echoing content, dedupe on reportID, and reject junk before it
// reaches storage.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { build } from '../src/server.js';
import { createStores } from '../src/stores.js';
import { CONFIG, LIMITS } from '../src/config.js';
import { PNG_BASE64, PNG_BYTES, digestOf } from './helpers.js';

const USER = { 'x-ink-user': 'reporter-1', 'content-type': 'application/json' };

function reportBody(overrides = {}) {
  return {
    reportID: randomUUID(),
    replyID: randomUUID(),
    pageID: randomUUID(),
    bookID: 'oracle',
    reason: 'disturbing',
    note: 'the page unsettled me',
    replyKind: 'ink',
    replyText: 'An unsettling reply.',
    modelID: '',
    snapshotDigest: digestOf(PNG_BYTES),
    snapshotBase64: PNG_BASE64,
    createdAt: new Date().toISOString(),
    submittedAt: new Date().toISOString(),
    ...overrides,
  };
}

const post = (app, payload, headers = USER) =>
  app.inject({ method: 'POST', url: '/v1/report', headers, payload });

test('a report files, acks small, and never echoes content', async () => {
  const stores = createStores();
  const app = build({ stores });
  const res = await post(app, reportBody());
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json(), { received: true }, 'the ack carries no page content');
  assert.equal(stores.reportCount('reporter-1'), 1);
  await app.close();
});

test('auth is required: no token, no report', async () => {
  const app = build();
  const res = await post(app, reportBody(), { 'content-type': 'application/json' });
  assert.equal(res.statusCode, 401);
  await app.close();
});

test('a double-tap on send files exactly one report', async () => {
  const stores = createStores();
  const app = build({ stores });
  const body = reportBody();
  const first = await post(app, body);
  const second = await post(app, body);
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200, 'the replay still acks');
  assert.equal(stores.reportCount('reporter-1'), 1, 'but only one report stands');
  await app.close();
});

test('reports are rate limited, and the ceiling is low', async () => {
  const app = build();
  const perMinute = CONFIG.rateLimits.reportsPerUserPerMinute;
  assert.ok(perMinute <= 10, 'the report ceiling must stay low');
  for (let i = 0; i < perMinute; i += 1) {
    assert.equal((await post(app, reportBody())).statusCode, 200);
  }
  const limited = await post(app, reportBody());
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.headers['retry-after'], '60');
  await app.close();
});

test('a malformed reason is rejected by the schema', async () => {
  const app = build();
  const res = await post(app, reportBody({ reason: 'i-just-dislike-it' }));
  assert.equal(res.statusCode, 400);
  await app.close();
});

test('an ink report with no reply text carries nothing reviewable', async () => {
  const app = build();
  const res = await post(app, reportBody({ replyText: null }));
  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.json(), { error: 'invalid_report' });
  await app.close();
});

test('an oversized body is refused before parsing', async () => {
  const app = build();
  const res = await post(app, reportBody({ snapshotBase64: 'A'.repeat(LIMITS.reportBodyLimit) }));
  assert.equal(res.statusCode, 413);
  await app.close();
});

test('a snapshot that is not an image is refused', async () => {
  const app = build();
  const notAnImage = Buffer.from('plain text, no magic bytes');
  const res = await post(
    app,
    reportBody({
      snapshotBase64: notAnImage.toString('base64'),
      snapshotDigest: digestOf(notAnImage),
    }),
  );
  assert.equal(res.statusCode, 415);
  assert.deepEqual(res.json(), { error: 'unsupported_snapshot' });
  await app.close();
});

test('a digest that does not match the bytes is refused', async () => {
  const app = build();
  const res = await post(app, reportBody({ snapshotDigest: 'b'.repeat(64) }));
  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.json(), { error: 'digest_mismatch' });
  await app.close();
});
