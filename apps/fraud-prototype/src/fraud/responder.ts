// on a fraud threshold breach:
//   1. hang up the scammer leg immediately,
//   2. dial the configured operator number (env var),
//   3. speak a short summary on the alert leg once it answers.

import { config } from "../config.ts";
import { log } from "../log.ts";
import * as Telnyx from "../telnyx/client.ts";
import * as Store from "../store/calls.ts";

const WEBHOOK_PATH = "/telnyx/webhook";

function webhookUrl(): string {
  return `${config.publicUrl.replace(/\/$/, "")}${WEBHOOK_PATH}`;
}

export async function trigger(scammerCcid: string, summary: string): Promise<void> {
  log.warn("fraud responder triggered", { ccid: scammerCcid, summary });

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
    return;
  }

  Store.markAlert(alertCcid, summary, scammerCcid);
  log.info("fraud responder: alert leg dialing", {
    ccid: scammerCcid,
    alertCcid,
    to: config.fraud.alertPhone,
  });
}

export async function onAlertAnswered(alertCcid: string): Promise<void> {
  const info = Store.alertInfo(alertCcid);
  if (!info) return;
  const text = fullAlertText(info.summary);
  log.info("fraud responder: alert answered, speaking summary", {
    alertCcid,
    scammerCcid: info.scammerCcid,
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
