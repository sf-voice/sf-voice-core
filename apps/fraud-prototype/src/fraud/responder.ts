// on a fraud threshold breach:
//   1. hang up the scammer leg immediately,
//   2. dial the configured operator number (env var),
//   3. speak a short summary on the alert leg once it answers.

import { config } from "../config.ts";
import { log } from "../log.ts";
import * as Telnyx from "../telnyx/client.ts";
import { webhookUrl } from "../telnyx/paths.ts";
import * as Store from "../store/calls.ts";

export interface TriggerResult {
  /** true when the alert leg was successfully dialed; the caller uses
   *  this to decide whether to mark the detector as permanently "fired". */
  alertQueued: boolean;
}

export async function trigger(scammerCcid: string, summary: string): Promise<TriggerResult> {
  // summary can include verbatim conversation snippets — log only length
  // / shape, not the text itself.
  log.warn("fraud responder triggered", {
    ccid: scammerCcid,
    summaryLen: summary.length,
  });

  // 1. drop the scammer leg first so the victim is no longer on a live
  //    scam call. errors are logged but don't block the alert dial.
  try {
    await Telnyx.hangup(scammerCcid);
    log.info("fraud responder: scammer hung up", { ccid: scammerCcid });
  } catch (err) {
    log.warn("fraud responder: hangup failed", {
      ccid: scammerCcid,
      err: (err as Error).message,
    });
  }

  // 2. dial the operator and remember the summary for when they answer.
  let alertCcid: string;
  try {
    const r = await Telnyx.dial(config.fraud.alertPhone, config.telnyx.fromNumber, webhookUrl());
    alertCcid = r.ccid;
  } catch (err) {
    log.error("fraud responder: alert dial failed", { err: (err as Error).message });
    return { alertQueued: false };
  }

  Store.markAlert(alertCcid, summary, scammerCcid);
  log.info("fraud responder: alert leg dialing", {
    ccid: scammerCcid,
    alertCcid,
    to: config.fraud.alertPhone,
  });
  return { alertQueued: true };
}

export async function onAlertAnswered(alertCcid: string): Promise<void> {
  // consume the mapping so retries of the same `call.answered` webhook
  // don't replay the speak action, and so the in-memory entry doesn't
  // leak after the call is done.
  const info = Store.takeAlertInfo(alertCcid);
  if (!info) return;

  const text = fullAlertText(info.summary);
  log.info("fraud responder: alert answered, speaking summary", {
    alertCcid,
    scammerCcid: info.scammerCcid,
    summaryLen: info.summary.length,
  });
  try {
    await Telnyx.speak(alertCcid, text);
  } catch (err) {
    log.warn("fraud responder: speak failed", { alertCcid, err: (err as Error).message });
  }
}

function fullAlertText(summary: string): string {
  return `Fraud detection alert. ${summary} The suspicious call has been ended. End of alert.`;
}
