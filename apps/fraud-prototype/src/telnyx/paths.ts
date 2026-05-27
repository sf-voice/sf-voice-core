import { config } from "../config.ts";

export const WEBHOOK_PATH = "/telnyx/webhook";
export const MEDIA_STREAMING_PATH = "/telnyx/media-streaming";

export function mediaStreamingUrl(): string {
   const url = new URL(config.publicUrl);
   url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
   url.pathname = MEDIA_STREAMING_PATH;
   url.search = "";
   url.hash = "";
   return url.toString();
}

export function webhookUrl(): string {
   const url = new URL(config.publicUrl);
   url.pathname = WEBHOOK_PATH;
   url.search = "";
   url.hash = "";
   return url.toString();
}
