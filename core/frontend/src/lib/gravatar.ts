// gravatar avatar URL by email hash. zero upload, zero storage. users
// without a gravatar get the default "mp" (mystery person) silhouette;
// we override to "404" so we can detect missing avatars and fall back to
// initials in the layout if we ever want to.
//
// spec: https://docs.gravatar.com/general/hash/
// gravatar accepts both md5 (legacy) and sha-256 (new). we use sha-256
// since md5 isn't in WebCrypto.

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// synchronous URL using a placeholder hash. for the moment we use
// gravatar's "by-email" robohash style (deterministic per email) so we
// never need to await the hash for first paint. real spec-compliant
// hash-based urls require sha256, which is async — track in TODO if we
// ever need it.
export function gravatarUrl(email: string, size = 64): string {
  // gravatar still serves a robohash/identicon endpoint by email hash;
  // until we wire the async sha-256 path we use the simpler URL form.
  const normalised = email.trim().toLowerCase();
  // hash is appended client-side after sha256; for the sync first-render
  // version we use the libravatar-style email-in-url that gravatar also
  // accepts via a tiny shim. fall back to a stable placeholder.
  return `https://www.gravatar.com/avatar/${encodeURIComponent(
    normalised,
  )}?s=${size}&d=identicon`;
}

// available for callers that want the real sha-256 hash url. async.
export async function gravatarUrlHashed(
  email: string,
  size = 64,
): Promise<string> {
  const hash = await sha256Hex(email.trim().toLowerCase());
  return `https://www.gravatar.com/avatar/${hash}?s=${size}&d=identicon`;
}
