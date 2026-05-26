import { config } from "./config.js";
import { buildServer } from "./server.js";

const app = await buildServer();

try {
  await app.listen({ port: config.server.port, host: "0.0.0.0" });
  console.log(`sf-voice demo running at http://localhost:${config.server.port}`);
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
