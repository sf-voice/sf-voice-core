import { config } from "../config.ts";
import * as Store from "../store/calls.ts";
import * as Telnyx from "../telnyx/client.ts";

export async function onAlertAnswered(ccid: string): Promise<void> {
   const script = Store.getScript(ccid) ?? "unknown";
   await Telnyx.speak(
      ccid,
      `fraud alert. the detector matched script ${script}. review the call now.`,
      { voice: config.openai.realtimeVoice },
   );
}
