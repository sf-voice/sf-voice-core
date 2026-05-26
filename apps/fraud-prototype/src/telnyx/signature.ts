// Telnyx webhook signature verification (ED25519).
//
// Telnyx signs the message `<telnyx-timestamp>|<raw_request_body>` with
// its private key; the signature arrives as a base64 string in the
// `telnyx-signature-ed25519` header. we verify it against the public
// key from the Telnyx portal (`TELNYX_PUBLIC_KEY` env, base64 raw 32-byte
// ED25519 public key).
//
// CodeRabbit thread #23 (CRITICAL): without this, any caller can forge
// a webhook and trigger an outbound call via streamingStart/dial.

import { webcrypto } from "node:crypto";
import { config } from "../config.ts";
import { log } from "../log.ts";

type CryptoKey = webcrypto.CryptoKey;

/** allow webhooks signed up to N seconds in the past, to absorb clock skew. */
const FRESHNESS_WINDOW_SEC = 5 * 60;

let cachedKey: CryptoKey | null = null;

async function loadKey(): Promise<CryptoKey | null> {
  if (cachedKey) return cachedKey;
  if (!config.telnyx.publicKey) return null;

  let raw: Uint8Array;
  try {
    raw = Uint8Array.from(Buffer.from(config.telnyx.publicKey, "base64"));
  } catch (err) {
    log.error("telnyx: TELNYX_PUBLIC_KEY is not valid base64", {
      err: (err as Error).message,
    });
    return null;
  }
  if (raw.byteLength !== 32) {
    log.error("telnyx: TELNYX_PUBLIC_KEY must decode to 32 raw bytes", {
      length: raw.byteLength,
    });
    return null;
  }

  cachedKey = await webcrypto.subtle.importKey(
    "raw",
    raw,
    { name: "Ed25519" },
    false,
    ["verify"],
  );
  return cachedKey;
}

export interface VerifyInput {
  signatureB64: string | undefined;
  timestamp: string | undefined;
  rawBody: string;
}

export type VerifyResult =
  | { ok: true }
  | {
      ok: false;
      reason:
        | "missing_signature"
        | "missing_timestamp"
        | "stale"
        | "invalid"
        | "no_key"
        | "invalid_key";
    };

/** verify the headers + raw body against the configured public key.
 *  returns `{ ok: false, reason: "no_key" }` only when no key is configured at
 *  all — the caller decides whether to reject (prod) or warn-and-pass (dev).
 *  if a key is configured but cannot be loaded (bad base64, wrong byte length,
 *  WebCrypto import failure) we return `"invalid_key"` so the server fails
 *  closed instead of silently accepting unsigned traffic. */
export async function verify(input: VerifyInput): Promise<VerifyResult> {
  const key = await loadKey();
  if (!key) {
    // configured-but-broken key material must NOT be treated as "no key" —
    // otherwise a typo in TELNYX_PUBLIC_KEY would silently bypass auth.
    return config.telnyx.publicKey
      ? { ok: false, reason: "invalid_key" }
      : { ok: false, reason: "no_key" };
  }

  if (!input.signatureB64) return { ok: false, reason: "missing_signature" };
  if (!input.timestamp) return { ok: false, reason: "missing_timestamp" };

  const ts = Number(input.timestamp);
  if (!Number.isFinite(ts)) return { ok: false, reason: "missing_timestamp" };
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - ts) > FRESHNESS_WINDOW_SEC) {
    return { ok: false, reason: "stale" };
  }

  let sig: Uint8Array;
  try {
    sig = Uint8Array.from(Buffer.from(input.signatureB64, "base64"));
  } catch {
    return { ok: false, reason: "invalid" };
  }
  if (sig.byteLength !== 64) return { ok: false, reason: "invalid" };

  const message = new TextEncoder().encode(`${input.timestamp}|${input.rawBody}`);

  const ok = await webcrypto.subtle.verify({ name: "Ed25519" }, key, sig, message);
  return ok ? { ok: true } : { ok: false, reason: "invalid" };
}

/** true if the server should accept unverified webhooks (no public key
 *  configured). emits a noisy startup warning the first time. */
export function isVerifyConfigured(): boolean {
  return config.telnyx.publicKey.length > 0;
}
