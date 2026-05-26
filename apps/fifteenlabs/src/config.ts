// env-driven config. accessors throw on first read when a required var
/**
 * Retrieve an environment variable and fail fast if it is missing or empty.
 *
 * @param name - The name of the environment variable to read
 * @returns The value of the environment variable
 * @throws Error if the environment variable is missing or an empty string; message is `required env var missing: ${name}`
 */

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(`required env var missing: ${name}`);
  }
  return v;
}

/**
 * Retrieve an environment variable by name, returning a fallback when the variable is missing or empty.
 *
 * @param name - The environment variable name to read from process.env
 * @param fallback - The value to return if the environment variable is missing or an empty string
 * @returns The environment variable's value if present and has length > 0, otherwise `fallback`
 */
function optional(name: string, fallback: string): string {
  const v = process.env[name];
  return v && v.length > 0 ? v : fallback;
}

/**
 * Parse an environment variable as a finite number or return a fallback.
 *
 * @param name - The environment variable name to read
 * @param fallback - Value returned when the variable is missing, empty, or not a finite number
 * @returns The finite numeric value parsed from the environment variable, or `fallback`
 */
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
