// CLI entry. usage:
//   pnpm run scammer -- --script irs
//   pnpm run scammer -- --script gift_cards_grandparent --to +15551234567

import { parseArgs } from "node:util";
import { config } from "../config.ts";
import { log } from "../log.ts";
import * as Scammer from "../scammer/scammer.ts";
import { ids, isScriptId } from "../scammer/scripts.ts";

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      script: { type: "string", short: "s" },
      to: { type: "string", short: "t" },
    },
    allowPositionals: false,
  });

  const scriptArg = values.script;
  if (!scriptArg) {
    console.error(`--script is required. available: ${ids().join(", ")}`);
    process.exit(2);
  }

  if (!isScriptId(scriptArg)) {
    console.error(`unknown script: "${scriptArg}". available: ${ids().join(", ")}`);
    process.exit(2);
  }

  const to = values.to ?? config.fraud.alertPhone;

  try {
    const ccid = await Scammer.dial(to, scriptArg);
    log.info("scammer dial dispatched", { ccid, to, script: scriptArg });
    console.log(`✓ dialed ccid=${ccid} to=${to} script=${scriptArg}`);
    console.log(`  say "STOP TEST" on the call to abort.`);
  } catch (err) {
    log.error("scammer dial failed", { err: (err as Error).message });
    console.error(`✗ ${(err as Error).message}`);
    process.exit(1);
  }
}

main();
