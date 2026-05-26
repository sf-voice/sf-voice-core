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
  sfVoice: {
    get apiKey() {
      return required("SF_VOICE_API_KEY");
    },
    baseUrl: optional("SF_VOICE_BASE_URL", "https://api.sf-voice.com"),
    sampleMediaUrl: optional("SAMPLE_MEDIA_URL", ""),
  },
  server: {
    port: optionalNumber("PORT", 3000),
  },
};
