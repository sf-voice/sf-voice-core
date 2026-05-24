// minimal structured logger. swap for pino later if needed — for a
// prototype the goal is readable timestamps + ccid context, nothing more.

type Level = "debug" | "info" | "warn" | "error";

function emit(level: Level, msg: string, ctx?: Record<string, unknown>): void {
  const ts = new Date().toISOString();
  const ctxStr = ctx
    ? " " +
      Object.entries(ctx)
        .map(([k, v]) => `${k}=${formatValue(v)}`)
        .join(" ")
    : "";
  // eslint-disable-next-line no-console
  console.log(`${ts} [${level}] ${msg}${ctxStr}`);
}

function formatValue(v: unknown): string {
  if (v === null) return "null";
  if (v === undefined) return "undefined";
  if (typeof v === "string") return v.includes(" ") ? JSON.stringify(v) : v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

export const log = {
  debug: (msg: string, ctx?: Record<string, unknown>) => {
    if (process.env.LOG_LEVEL === "debug") emit("debug", msg, ctx);
  },
  info: (msg: string, ctx?: Record<string, unknown>) => emit("info", msg, ctx),
  warn: (msg: string, ctx?: Record<string, unknown>) => emit("warn", msg, ctx),
  error: (msg: string, ctx?: Record<string, unknown>) => emit("error", msg, ctx),
};
