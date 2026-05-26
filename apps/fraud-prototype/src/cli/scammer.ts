// CLI entry — delegates to the running server's /scammer/dial endpoint
// so the server owns call state in its own process.
//
// usage:
//   mise run fraud:scammer
//   mise run fraud:scammer -- --script irs --to +15551234567

import { parseArgs } from "node:util";
import { log } from "../log.ts";
import { ids, isScriptId } from "../scammer/scripts.ts";

const DEFAULT_SCRIPT = "gift_cards_grandparent";

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      script: { type: "string", short: "s" },
      to: { type: "string", short: "t" },
    },
    allowPositionals: false,
  });

  const scriptArg = values.script ?? DEFAULT_SCRIPT;
  if (!isScriptId(scriptArg)) {
    console.error(`unknown script: "${scriptArg}". available: ${ids().join(", ")}`);
    process.exit(2);
  }

  const to = values.to ?? process.env.STAFF_PHONE_E164;
  if (!to) {
    console.error("set STAFF_PHONE_E164 in .env or pass --to <number>");
    process.exit(2);
  }

  const port = process.env.SCAMMER_PORT ?? "4000";
  const serverUrl = `http://localhost:${port}`;

  let res: Response;
  try {
    res = await fetch(`${serverUrl}/scammer/dial`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ script: scriptArg, to }),
    });
  } catch {
    console.error(`✗ could not reach server at ${serverUrl} — is fraud:dev running?`);
    process.exit(1);
  }

  const text = await res.text();
  let json: { ccid?: string; error?: string; message?: string } = {};
  try { json = JSON.parse(text); } catch { /* keep empty */ }

  if (!res.ok || !json.ccid) {
    const reason = json.error ?? json.message ?? text ?? "unknown error";
    log.error("scammer dial failed", { status: res.status, reason });
    console.error(`✗ ${reason}`);
    process.exit(1);
  }

  log.info("scammer dial dispatched", { ccid: json.ccid, to, script: scriptArg });
  console.log(`✓ dialed ccid=${json.ccid} to=${to} script=${scriptArg}`);
  console.log(`  say "STOP TEST" on the call to abort.`);
}

main();
