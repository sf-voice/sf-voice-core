// env-driven config. accessors throw on first read when a required var
// is missing — fail fast at boot, not mid-call.

function required(name: string): string {
   const v = process.env[name];
   if (!v || v.length === 0) {
      throw new Error(`required env var missing: ${name}`);
   }
   return v;
}

function optional(name: string, fallback: string): string {
   const v = process.env[name];
   return v && v.length > 0 ? v : fallback;
}

function optionalNumber(name: string, fallback: number): number {
   const v = process.env[name];
   if (!v || v.length === 0) return fallback;
   const n = Number(v);
   return Number.isFinite(n) ? n : fallback;
}

function clamp01(n: number): number {
   if (!Number.isFinite(n)) return 0;
   if (n < 0) return 0;
   if (n > 1) return 1;
   return n;
}

export const config = {
   telnyx: {
      get apiKey() {
         return required("TELNYX_API_KEY");
      },
      get connectionId() {
         return required("TELNYX_CONNECTION_ID");
      },
      get fromNumber() {
         return required("PHONE_NUMBER");
      },
      baseUrl: optional("TELNYX_BASE_URL", "https://api.telnyx.com"),
      /** base64-encoded 32-byte ED25519 public key from the Telnyx portal.
       *  optional: when unset, signature verification is skipped with a
       *  startup warning (dev convenience). REQUIRED for any production use. */
      publicKey: optional("TELNYX_PUBLIC_KEY", ""),
      /** outbound HTTP request timeout in ms. */
      requestTimeoutMs: optionalNumber("TELNYX_REQUEST_TIMEOUT_MS", 10_000),
   },
   openai: {
      get apiKey() {
         return required("OPENAI_API_KEY");
      },
      realtimeModel: optional(
         "OPENAI_REALTIME_MODEL",
         "gpt-4o-realtime-preview",
      ),
      realtimeVoice: optional("OPENAI_REALTIME_VOICE", "alloy"),
      classifierModel: optional("FRAUD_CLASSIFIER_MODEL", "gpt-4o-mini"),
   },
   fraud: {
      get alertPhone() {
         return required("FRAUD_ALERT_PHONE_E164");
      },
      /** clamped to [0, 1] — misconfig like `2` or `-1` would silently
       *  disable or always-trip the detector without this. */
      threshold: clamp01(optionalNumber("FRAUD_THRESHOLD", 0.7)),
   },
   publicUrl: optional("PUBLIC_URL", "http://localhost:4000"),
   port: optionalNumber("SCAMMER_PORT", 4000),
};
