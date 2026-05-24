// thin HTTP client for the Telnyx call-control API. Uses global `fetch`
// (Node 22+). retries are not implemented — for a prototype, the bash
// of a failed request bubbles to the caller.

import { config } from "../config.ts";
import { log } from "../log.ts";

interface PostActionResult {
  ok: boolean;
  status: number;
  body: unknown;
}

async function postAction(
  ccid: string,
  action: string,
  body: Record<string, unknown> = {},
): Promise<PostActionResult> {
  const url = `${config.telnyx.baseUrl}/v2/calls/${ccid}/actions/${action}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.telnyx.apiKey}`,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = JSON.parse(text);
  } catch {
    // text response, fine
  }
  if (!res.ok) {
    log.warn("telnyx action returned non-2xx", { action, ccid, status: res.status, body: parsed });
  }
  return { ok: res.ok, status: res.status, body: parsed };
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
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${config.telnyx.apiKey}`,
    },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as { data?: { call_control_id?: string } };
  if (!res.ok || !json.data?.call_control_id) {
    throw new Error(`telnyx dial failed (${res.status}): ${JSON.stringify(json)}`);
  }
  return { ccid: json.data.call_control_id };
}
