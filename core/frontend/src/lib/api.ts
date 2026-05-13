// thin typed client for sf-voice-api. one function per endpoint, no
// global state. when this file gets long, split per-domain (e.g.
// `api/calls.ts`, `api/reservations.ts`) but keep all of them returning
// raw types — no react bindings here.
//
// types are hand-written for now. when the api surface stabilises switch
// to openapi codegen (rust serves openapi.json via utoipa, frontend runs
// openapi-typescript on build) so the types track the server.

// dev: http://localhost:8080 (axum bind). prod: api.sf-voice.sh.
// swap to a build-time env var once we ship to staging.
const API_BASE_URL = "http://localhost:8080";

export type Hello = {
  message: string;
  service: string;
  version: string;
};

export async function getHello(): Promise<Hello> {
  const res = await fetch(`${API_BASE_URL}/api/hello`);
  if (!res.ok) {
    throw new Error(`api error: ${res.status} ${res.statusText}`);
  }
  return (await res.json()) as Hello;
}
