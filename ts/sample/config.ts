const required = (name: string): string => {
  const val = process.env[name];
  if (!val) throw new Error(`missing required env var: ${name}`);
  return val;
};

const port = Number(process.env.PORT ?? 3000);

export const config = {
  sfVoice: {
    apiKey: required("SF_VOICE_API_KEY"),
    baseUrl: process.env.SF_VOICE_BASE_URL ?? "http://localhost:8080",
  },
  port,
  // url that the sf-voice backend can reach to pull uploaded/downloaded media.
  // must be reachable from wherever SF_VOICE_BASE_URL is running.
  selfUrl: process.env.SELF_URL ?? `http://localhost:${port}`,
};
