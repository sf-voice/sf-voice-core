// OpenAI Realtime API client. one WebSocket per call leg.
//
// the API streams audio in both directions (G.711 μ-law in/out so the
// bytes pass straight through to Telnyx) plus structured events for
// transcript finalization and session lifecycle.

import { WebSocket as WS } from "ws";
import { config } from "../config.ts";
import { log } from "../log.ts";

const REALTIME_URL = "wss://api.openai.com/v1/realtime";

export interface RealtimeOptions {
  ccid: string;
  systemPrompt: string;
  voice?: string;
  onUserTranscript: (text: string) => void;
  onAssistantTranscript: (text: string) => void;
  onAudioOut: (mulawB64: string) => void;
  onClose: () => void;
}

export interface RealtimeSession {
  pushAudio(mulawB64: string): void;
  close(): void;
}

export function start(opts: RealtimeOptions): RealtimeSession {
  const url = `${REALTIME_URL}?model=${encodeURIComponent(config.openai.realtimeModel)}`;
  const ws = new WS(url, {
    headers: {
      Authorization: `Bearer ${config.openai.apiKey}`,
      "OpenAI-Beta": "realtime=v1",
    },
  });

  let opened = false;

  ws.on("open", () => {
    opened = true;
    log.info("realtime: ws open", { ccid: opts.ccid });
    sendSessionUpdate(ws, opts);
    // kick off the first response so the scammer speaks first when the
    // user picks up.
    send(ws, { type: "response.create" });
  });

  ws.on("message", (raw: Buffer | string) => {
    let evt: RealtimeEvent;
    try {
      evt = JSON.parse(raw.toString()) as RealtimeEvent;
    } catch {
      return;
    }
    handleEvent(evt, opts);
  });

  ws.on("close", () => {
    log.info("realtime: ws close", { ccid: opts.ccid });
    opts.onClose();
  });

  ws.on("error", (err: Error) => {
    log.warn("realtime: ws error", { ccid: opts.ccid, err: err.message });
  });

  return {
    pushAudio(mulawB64: string): void {
      if (!opened || ws.readyState !== WS.OPEN) return;
      send(ws, { type: "input_audio_buffer.append", audio: mulawB64 });
    },
    close(): void {
      if (ws.readyState === WS.OPEN || ws.readyState === WS.CONNECTING) {
        ws.close();
      }
    },
  };
}

function sendSessionUpdate(ws: WS, opts: RealtimeOptions): void {
  send(ws, {
    type: "session.update",
    session: {
      instructions: opts.systemPrompt,
      voice: opts.voice ?? config.openai.realtimeVoice,
      modalities: ["audio", "text"],
      input_audio_format: "g711_ulaw",
      output_audio_format: "g711_ulaw",
      input_audio_transcription: { model: "whisper-1" },
      turn_detection: {
        type: "server_vad",
        threshold: 0.5,
        prefix_padding_ms: 300,
        silence_duration_ms: 500,
      },
    },
  });
}

function send(ws: WS, payload: Record<string, unknown>): void {
  if (ws.readyState !== WS.OPEN) return;
  ws.send(JSON.stringify(payload));
}

// minimal shape for the events we care about. Realtime sends many more.
interface RealtimeEvent {
  type: string;
  transcript?: string;
  delta?: string;
  audio?: string;
}

function handleEvent(evt: RealtimeEvent, opts: RealtimeOptions): void {
  switch (evt.type) {
    case "session.updated":
      log.debug("realtime: session.updated", { ccid: opts.ccid });
      break;

    case "response.audio.delta":
      if (typeof evt.delta === "string") opts.onAudioOut(evt.delta);
      break;

    case "response.audio_transcript.done":
      if (typeof evt.transcript === "string" && evt.transcript.length > 0) {
        opts.onAssistantTranscript(evt.transcript);
      }
      break;

    case "conversation.item.input_audio_transcription.completed":
      if (typeof evt.transcript === "string" && evt.transcript.length > 0) {
        opts.onUserTranscript(evt.transcript);
      }
      break;

    case "error":
      log.warn("realtime: server error event", { ccid: opts.ccid, evt });
      break;

    default:
      // many lifecycle events are noise — keep at debug.
      log.debug("realtime: event", { ccid: opts.ccid, type: evt.type });
  }
}
