// outbound scammer-AI dialer. places a Telnyx call to the operator,
// stamps the leg as a scammer leg with a chosen script, and lets the
// webhook + bridge stack do the rest when the user picks up.

import { config } from "../config.ts";
import { log } from "../log.ts";
import * as Telnyx from "../telnyx/client.ts";
import * as Store from "../store/calls.ts";
import * as Scripts from "./scripts.ts";

const WEBHOOK_PATH = "/telnyx/webhook";

export async function dial(to: string, scriptId: Scripts.ScriptId): Promise<string> {
  const script = Scripts.fetchScript(scriptId);
  ensureBackendAvailable(script);

  const webhookUrl = `${config.publicUrl.replace(/\/$/, "")}${WEBHOOK_PATH}`;
  const { ccid } = await Telnyx.dial(to, config.telnyx.fromNumber, webhookUrl);
  Store.markScammer(ccid, scriptId);

  log.info("scammer dial started", {
    ccid,
    to,
    script: scriptId,
    backend: script.backend,
  });

  return ccid;
}

function ensureBackendAvailable(script: Scripts.Script): void {
  if (script.backend === "modular") {
    throw new Error(
      `script "${script.id}" uses :modular backend; not implemented in v1 (KugelAudio/ElevenLabs/Anthropic stubs only)`,
    );
  }
}
