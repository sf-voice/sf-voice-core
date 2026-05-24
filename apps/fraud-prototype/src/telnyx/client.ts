// thin HTTP client for the Telnyx call-control API. Uses global `fetch`
// (Node 22+). every request has an explicit timeout and a status check —
// callers can rely on the action either completing 2xx or throwing.

import { config } from "../config.ts";
import { log } from "../log.ts";

export class TelnyxError extends Error {
  constructor(
    public readonly action: string,
    public readonly status: number,
    public readonly body: unknown,
  ) {
    super(`telnyx ${action} failed (${status}): ${JSON.stringify(body)}`);
    this.name = "TelnyxError";
  }
}

async function fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.telnyx.requestTimeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

async function postAction(
  ccid: string,
  action: string,
  body: Record<string, unknown> = {},
): Promise<void> {
  const url = `${config.telnyx.baseUrl}/v2/calls/${ccid}/actions/${action}`;
  const res = await fetchWithTimeout(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.telnyx.apiKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    let parsed: unknown = text;
    try {
      parsed = JSON.parse(text);
    } catch {
      // keep text
    }
    log.warn("telnyx action non-2xx", { action, ccid, status: res.status });
    throw new TelnyxError(action, res.status, parsed);
  }
}

export async function answer(ccid: string): Promise<void> {
  await postAction(ccid, "answer");
}

export async function hangup(ccid: string): Promise<void> {
  await postAction(ccid, "hangup");
}

export async function streamingStart(ccid: string, streamUrl: string): Promise<void> {
  await postAction(ccid, "streaming_start", {
    stream_url: streamUrl,
    stream_track: "both_tracks",
    stream_bidirectional_codec: "PCMU",
    stream_bidirectional_mode: "rtp",
  });
}

export async function speak(
  ccid: string,
  text: string,
  opts: { voice?: string; language?: string } = {},
): Promise<void> {
  await postAction(ccid, "speak", {
    payload: text,
    voice: opts.voice ?? "Polly.Joanna",
    language: opts.language ?? "en-US",
  });
}

export async function dial(
  to: string,
  from: string,
  webhookUrl: string,
): Promise<{ ccid: string }> {
  const url = `${config.telnyx.baseUrl}/v2/calls`;
  const body = {
    connection_id: config.telnyx.connectionId,
    to,
    from,
    webhook_url: webhookUrl,
  };
  const res = await fetchWithTimeout(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.telnyx.apiKey}`,
    },
    body: JSON.stringify(body),
  });
  const json = (await res.json().catch(() => ({}))) as {
    data?: { call_control_id?: string };
  };
  if (!res.ok || !json.data?.call_control_id) {
    throw new TelnyxError("dial", res.status, json);
  }
  return { ccid: json.data.call_control_id };
}
