import { build } from './server.js';

const app = build({ logger: true });
const port = Number(process.env.PORT ?? 8787);

app.listen({ port, host: '0.0.0.0' }).then(() => {
  app.log.info(`inkbound proxy listening on :${port} (echo mode)`);
});
