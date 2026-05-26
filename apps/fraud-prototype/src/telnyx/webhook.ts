// Telnyx webhook handler. routes `call.answered` based on whether the
// leg is a scammer leg (start media-streaming) or an alert leg (speak
// summary). drops per-call state on hangup so the in-memory store
// doesn't grow without bound.

import { log } from "../log.ts";
import * as Store from "../store/calls.ts";
import * as Telnyx from "./client.ts";
import { mediaStreamingUrl } from "./paths.ts";
import { onAlertAnswered } from "../fraud/responder.ts";

interface WebhookPayload {
   data?: {
      event_type?: string;
      payload?: {
         call_control_id?: string;
         hangup_cause?: string;
         hangup_source?: string;
         direction?: string;
         state?: string;
      };
   };
}

export async function handle(body: WebhookPayload): Promise<void> {
   const event = body.data?.event_type;
   const ccid = body.data?.payload?.call_control_id;
   if (!event || !ccid) {
      log.warn("webhook: unexpected shape");
      return;
   }

   log.info("webhook event", { body, ccid });

   switch (event) {
      case "call.answered":
         if (Store.isAlertLeg(ccid)) {
            await onAlertAnswered(ccid);
         } else if (Store.isScammerLeg(ccid)) {
            try {
               await Telnyx.streamingStart(ccid, mediaStreamingUrl());
            } catch (err) {
               log.error("webhook: streaming_start failed", {
                  ccid,
                  err: (err as Error).message,
               });
            }
         } else {
            log.debug("webhook: call.answered for unknown leg — ignoring", {
               ccid,
            });
         }
         break;

      case "call.hangup":
         log.info("webhook: call.hangup", {
            ccid,
            data: body.data,
         });
         Store.drop(ccid);
         break;

      default:
         log.debug("webhook: ignoring event", { event, ccid });
   }
}
