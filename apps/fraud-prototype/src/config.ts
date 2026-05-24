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

export const config = {
  telnyx: {
    get apiKey() {
      return required("TELNYX_API_KEY");
    },
    get connectionId() {
      return required("TELNYX_CONNECTION_ID");
    },
    get fromNumber() {
      return required("ELLIE_TELNYX_FROM");
    },
    baseUrl: optional("TELNYX_BASE_URL", "https://api.telnyx.com"),
  },
  openai: {
    get apiKey() {
      return required("OPENAI_API_KEY");
    },
    realtimeModel: optional("OPENAI_REALTIME_MODEL", "gpt-4o-realtime-preview"),
    realtimeVoice: optional("OPENAI_REALTIME_VOICE", "alloy"),
    classifierModel: optional("FRAUD_CLASSIFIER_MODEL", "gpt-4o-mini"),
  },
  fraud: {
    get alertPhone() {
      return required("FRAUD_ALERT_PHONE_E164");
    },
    threshold: optionalNumber("FRAUD_THRESHOLD", 0.7),
  },
  publicUrl: optional("PUBLIC_URL", "http://localhost:4000"),
  port: optionalNumber("PORT", 4000),
};

// websocket URL the media-streaming endpoint advertises to Telnyx.
export function mediaStreamingUrl(): string {
  const base = config.publicUrl
    .replace(/^https:\/\//, "wss://")
    .replace(/^http:\/\//, "ws://");
  return `${base}/telnyx/media-streaming`;
}
