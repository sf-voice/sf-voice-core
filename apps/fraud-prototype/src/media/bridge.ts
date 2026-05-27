import type { RawData, WebSocket } from "ws";
import { log } from "../log.ts";

export function attach(socket: WebSocket): void {
   socket.on("message", (data) => {
      log.debug("media-streaming: frame", {
         bytes: rawDataBytes(data),
      });
   });

   socket.on("close", () => {
      log.info("media-streaming: ws closed");
   });

   socket.on("error", (err) => {
      log.warn("media-streaming: ws error", { err: err.message });
   });
}

function rawDataBytes(data: RawData): number {
   if (Array.isArray(data)) {
      return data.reduce((total, chunk) => total + chunk.byteLength, 0);
   }

   return data.byteLength;
}
