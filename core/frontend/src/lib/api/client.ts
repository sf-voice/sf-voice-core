// shared http client. every per-domain module talks to the api through
// `request` so credentials, headers, and error shape stay consistent.

const API_BASE_URL = "http://localhost:8080";

export class ApiError extends Error {
   constructor(
      public status: number,
      public statusText: string,
      public path: string,
      message: string,
   ) {
      super(message);
   }
}

export async function request<T>(
   path: string,
   init?: RequestInit & { json?: unknown },
): Promise<T> {
   const headers = new Headers(init?.headers);
   if (init?.json !== undefined) {
      headers.set("content-type", "application/json");
   }
   const res = await fetch(`${API_BASE_URL}${path}`, {
      ...init,
      // include cookies on every request so the session cookie travels
      // from localhost:3000 → :8080 (and prod cross-origin if that ever
      // happens). backend CORS allows credentials for these origins.
      credentials: "include",
      headers,
      body: init?.json !== undefined ? JSON.stringify(init.json) : init?.body,
   });
   if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new ApiError(res.status, res.statusText, path, text || res.statusText);
   }
   // empty body → null. covers explicit 204, plus any 2xx where the
   // backend just set headers (e.g. /api/auth/logout returns 200 with
   // only the logout cookie, no body). previously this branch only
   // handled 204 and `res.json()` threw on the empty body, sending
   // logout etc. into onError silently.
   if (res.status === 204) return null as T;
   const text = await res.text();
   if (!text) return null as T;
   return JSON.parse(text) as T;
}
