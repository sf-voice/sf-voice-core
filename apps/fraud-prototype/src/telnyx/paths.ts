// shared URL paths Telnyx hits + we generate. centralised so the
// webhook handler, the responder (alert dial), and the scammer (outbound
// dial) cannot drift.

import { config } from "../config.ts";

export const WEBHOOK_PATH = "/telnyx/webhook";
export const MEDIA_STREAMING_PATH = "/telnyx/media-streaming";

export function webhookUrl(): string {
  return `${config.publicUrl.replace(/\/$/, "")}${WEBHOOK_PATH}`;
}

export function mediaStreamingUrl(): string {
  const base = config.publicUrl
    .replace(/^https:\/\//, "wss://")
    .replace(/^http:\/\//, "ws://")
    .replace(/\/$/, "");
  return `${base}${MEDIA_STREAMING_PATH}`;
}
