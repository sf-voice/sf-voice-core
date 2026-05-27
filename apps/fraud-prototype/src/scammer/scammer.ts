import { config } from "../config.ts";
import * as Store from "../store/calls.ts";
import * as Telnyx from "../telnyx/client.ts";
import { webhookUrl } from "../telnyx/paths.ts";
import { getScript, type ScriptId } from "./scripts.ts";

export async function dial(to: string, script: ScriptId): Promise<string> {
   const { ccid } = await Telnyx.dial(to, config.telnyx.fromNumber, webhookUrl());
   Store.markScammerLeg(ccid, script);
   return ccid;
}

export async function speakOpening(ccid: string, script: ScriptId): Promise<void> {
   await Telnyx.speak(ccid, getScript(script).opening);
}
