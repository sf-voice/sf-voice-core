import { createPublicKey, verify as verifySignature } from "node:crypto";
import { config } from "../config.ts";

const FIVE_MINUTES_MS = 5 * 60 * 1000;
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

export type VerifyResult =
   | { ok: true }
   | {
        ok: false;
        reason:
           | "no_key"
           | "missing_header"
           | "bad_timestamp"
           | "stale_timestamp"
           | "bad_key"
           | "bad_signature";
     };

export function isVerifyConfigured(): boolean {
   return config.telnyx.publicKey.length > 0;
}

export async function verify(input: {
   signatureB64?: string;
   timestamp?: string;
   rawBody: string;
}): Promise<VerifyResult> {
   if (!isVerifyConfigured()) {
      return { ok: false, reason: "no_key" };
   }

   if (!input.signatureB64 || !input.timestamp) {
      return { ok: false, reason: "missing_header" };
   }

   const timestampMs = Number(input.timestamp) * 1000;
   if (!Number.isFinite(timestampMs)) {
      return { ok: false, reason: "bad_timestamp" };
   }

   if (Math.abs(Date.now() - timestampMs) > FIVE_MINUTES_MS) {
      return { ok: false, reason: "stale_timestamp" };
   }

   let publicKey;
   try {
      const rawKey = Buffer.from(config.telnyx.publicKey, "base64");
      publicKey = createPublicKey({
         key: Buffer.concat([ED25519_SPKI_PREFIX, rawKey]),
         format: "der",
         type: "spki",
      });
   } catch {
      return { ok: false, reason: "bad_key" };
   }

   const signedPayload = Buffer.from(`${input.timestamp}|${input.rawBody}`);
   const signature = Buffer.from(input.signatureB64, "base64");
   const ok = verifySignature(null, signedPayload, publicKey, signature);
   return ok ? { ok: true } : { ok: false, reason: "bad_signature" };
}
