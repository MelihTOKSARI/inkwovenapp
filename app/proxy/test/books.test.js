import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';
import { PNG_BYTES, digestOf } from './helpers.js';

const USER = { 'x-ink-user': 'user-1' };

test('GET /v1/books serves all 8 launch books with flags', async () => {
  const app = build();
  const res = await app.inject({ method: 'GET', url: '/v1/books', headers: USER });
  assert.equal(res.statusCode, 200);
  const { books } = res.json();
  assert.equal(books.length, 8);
  const ids = books.map((b) => b.id).sort();
  assert.deepEqual(ids, ['artist', 'correspondent', 'gm', 'keeper', 'oracle', 'parlor', 'storyteller', 'tutor']);
  for (const book of books) {
    assert.ok(book.flags, `${book.id} has kill-switch flags`);
    assert.ok(book.starterText.length > 0);
  }
  await app.close();
});

test('prompts never leak to the client', async () => {
  const app = build();
  const res = await app.inject({ method: 'GET', url: '/v1/books', headers: USER });
  for (const book of res.json().books) {
    assert.equal(book.prompt, undefined, `${book.id} must not expose its prompt`);
  }
  assert.doesNotMatch(res.payload, /You are the/);
  await app.close();
});

test('GET /v1/config exposes the server-tunable knobs', async () => {
  const app = build();
  const res = await app.inject({ method: 'GET', url: '/v1/config', headers: USER });
  const config = res.json();
  assert.equal(config.freeMomentsPerDay, 5);
  assert.equal(config.plusImageDailySoftCap, 20);
  assert.ok(Array.isArray(config.cooldownCurveSeconds));
  await app.close();
});

test('preupload issues a ticket; abort is 204 even when unknown', async () => {
  const app = build();
  const created = await app.inject({
    method: 'POST',
    url: '/v1/preupload',
    headers: {
      ...USER,
      'x-ink-digest': digestOf(PNG_BYTES),
      'content-type': 'application/octet-stream',
    },
    payload: PNG_BYTES,
  });
  assert.equal(created.statusCode, 200);
  const ticket = created.json();
  assert.ok(ticket.id);

  const aborted = await app.inject({ method: 'DELETE', url: `/v1/preupload/${ticket.id}`, headers: USER });
  assert.equal(aborted.statusCode, 204);

  const abortedAgain = await app.inject({ method: 'DELETE', url: `/v1/preupload/${ticket.id}`, headers: USER });
  assert.equal(abortedAgain.statusCode, 204);
  await app.close();
});
