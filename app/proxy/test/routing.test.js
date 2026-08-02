import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/server.js';
import { composeSystemPrompt, createTextProviderFactory } from '../src/models.js';
import { findBook } from '../src/books.js';
import { PNG_BASE64 } from './helpers.js';

const USER = { 'x-ink-user': 'user-1', 'content-type': 'application/json' };

test('a routed provider streams deltas; prompt is injected server-side', async () => {
  const seen = {};
  const app = build({
    textProviderFactory: (book) =>
      async function* fake({ system, imageBase64, imageMime }) {
        seen.book = book.id;
        seen.system = system;
        seen.imageBase64 = imageBase64;
        seen.imageMime = imageMime;
        yield 'Three ';
        yield 'of swords.';
      },
  });

  const res = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: USER,
    payload: {
      bookID: 'oracle',
      snapshotBase64: PNG_BASE64,
      context: { memorySummaries: ['fears the sea'], sessionSummary: null },
    },
  });

  assert.equal(res.statusCode, 200);
  assert.match(res.payload, /Three /);
  assert.match(res.payload, /of swords\./);
  assert.match(res.payload, /"modelID":"gemini-3.5-flash-lite"/);

  assert.equal(seen.book, 'oracle');
  assert.equal(seen.imageBase64, PNG_BASE64);
  assert.equal(seen.imageMime, 'image/png', 'the real media type, not a hardcoded image/jpeg');
  assert.match(seen.system, /You are the Oracle/, 'Book prompt injected from the server definition');
  assert.match(seen.system, /fears the sea/, 'Plus memory summaries ride in the system block');
  // The prompt must never appear in the response stream.
  assert.doesNotMatch(res.payload, /You are the Oracle/);
  await app.close();
});

test('a failure AFTER the first delta degrades in-fiction, never a raw error', async () => {
  // Once bytes are committed no status can change, so the soft degrade is the
  // only honest ending. Before the first delta, see error-taxonomy.test.js.
  const app = build({
    textProviderFactory: () =>
      async function* brokenMidStream() {
        yield 'The cards ';
        throw new Error('upstream 500');
      },
  });
  const res = await app.inject({
    method: 'POST',
    url: '/v1/exchange',
    headers: USER,
    payload: { bookID: 'oracle' },
  });
  assert.equal(res.statusCode, 200);
  assert.match(res.payload, /The cards /);
  assert.match(res.payload, /The ink hesitates/);
  assert.match(res.payload, /event: done/);
  assert.doesNotMatch(res.payload, /upstream 500/);
  await app.close();
});

test('routing table: gm/tutor get the heavy model, others the default', () => {
  const factory = createTextProviderFactory({ GEMINI_API_KEY: 'g', OPENAI_API_KEY: 'o' });
  assert.ok(factory(findBook('oracle')), 'gemini key routes the default books');
  assert.ok(factory(findBook('gm')), 'openai key routes the heavy books');
  assert.equal(findBook('gm').models.text, 'gpt-5.4-mini');
  assert.equal(findBook('tutor').models.text, 'gpt-5.4-mini');
  assert.equal(findBook('oracle').models.text, 'gemini-3.5-flash-lite');
});

test('no API keys → echo mode (provider factory yields null)', () => {
  const factory = createTextProviderFactory({});
  assert.equal(factory(findBook('oracle')), null);
  assert.equal(factory(findBook('gm')), null);
});

test('composeSystemPrompt omits memory when absent', () => {
  const system = composeSystemPrompt(findBook('keeper'), {});
  assert.match(system, /You are the Keeper/);
  assert.doesNotMatch(system, /The notebook remembers/);
});
