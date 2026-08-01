// In-memory store internals — the things the shared contract cannot observe
// through the interface, but that decide whether the dev/test path leaks.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStores } from '../src/stores.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test('expired tickets are reclaimed, not merely refused', async () => {
  // Uncommitted tickets are the NORMAL case — the whole preupload design is
  // that they "simply expire" — and each one holds its base64 snapshot. The
  // expiry branch used to return null BEFORE the delete on the next line, so
  // every one leaked for the process's life. At ~350KB a snapshot, roughly
  // 700 of them exhaust a 256MB VM.
  const stores = createStores({ ticketTTLms: 50 });
  const ids = [];
  for (let i = 0; i < 20; i += 1) {
    ids.push((await stores.createTicket(`user-${i}`, 'd', 'c25hcHNob3Q=')).id);
  }
  assert.equal(stores.ticketCount(), 20);

  await sleep(120);
  for (const [i, id] of ids.entries()) {
    assert.equal(await stores.takeTicket(id, `user-${i}`), null);
  }
  assert.equal(stores.ticketCount(), 0, 'every expired ticket released its snapshot');
});

test('a foreign take still cannot consume a live ticket', async () => {
  // The reclamation must not become a way for anyone to destroy a ticket.
  const stores = createStores();
  const { id } = await stores.createTicket('owner', 'd', 'c25hcHNob3Q=');
  assert.equal(await stores.takeTicket(id, 'thief'), null);
  assert.equal(stores.ticketCount(), 1, 'the foreign take left it alone');
  assert.ok(await stores.takeTicket(id, 'owner'));
  assert.equal(stores.ticketCount(), 0);
});
