import { build } from './server.js';
import { createStores } from './stores.js';
import { createRedisStores } from './stores-redis.js';

const production = process.env.NODE_ENV === 'production';

// A missing or typo'd Fly secret used to produce a fully-booting,
// health-check-passing machine running the DEV stores: the credit ledger in a
// JS Map, wiped on every deploy, rate-limit counters per machine, tickets
// unreachable from the machine that didn't issue them. Refuse to listen
// instead — a machine that won't start is a page; a machine that silently
// loses purchased credits is not.
if (production) {
  const missing = ['REDIS_URL', 'DATABASE_URL'].filter((name) => !process.env[name]);
  if (missing.length) {
    console.error(`fatal: production boot requires ${missing.join(', ')}`);
    process.exit(1);
  }
}

// Durable stores when the fly secrets are present; in-memory for local dev.
const stores = process.env.REDIS_URL
  ? await createRedisStores({
      redisUrl: process.env.REDIS_URL,
      databaseUrl: process.env.DATABASE_URL,
    })
  : createStores();

const app = build({ logger: true, stores });
const port = Number(process.env.PORT ?? 8787);

app.listen({ port, host: '0.0.0.0' }).then(() => {
  app.log.info(`inkwoven proxy listening on :${port} (echo mode)`);
  // Identity is the loudest thing about this process's security posture, so
  // it says so at boot. 'anonymous' means the x-ink-user header IS the
  // identity — correct for dev, never for production.
  app.log[app.attestationMode === 'anonymous' && production ? 'error' : 'info'](
    `attestation mode: ${app.attestationMode}`,
  );
});
