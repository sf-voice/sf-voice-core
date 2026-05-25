// per-call bridge: forwards μ-law audio between Telnyx's bidirectional
// media-streaming WS and the OpenAI Realtime WS. captures finalized
// transcript turns into the in-memory call store and runs the fraud
// detector on each.

import type { WebSocket } from "ws";
import { log } from "../log.ts";
import { analyze } from "../fraud/detector.ts";
import * as Realtime from "./realtime.ts";
import * as Scripts from "../scammer/scripts.ts";
import * as Store from "../store/calls.ts";

interface BridgeState {
  ccid: string;
  realtime: Realtime.RealtimeSession;
  closed: boolean;
}

const ACTIVE = new Map<string, BridgeState>();

/** called when a Telnyx media-streaming WS connects. resolves the
 *  call's ccid from the first `start` event Telnyx sends, then opens a
 *  Realtime session paired to this socket. */
export function attach(telnyxWs: WebSocket): void {
  let bridge: BridgeState | null = null;

  telnyxWs.on("message", (raw: Buffer | string) => {
    let msg: TelnyxMediaMessage;
    try {
      msg = JSON.parse(raw.toString()) as TelnyxMediaMessage;
    } catch {
      return;
    }

    switch (msg.event) {
      case "start":
        if (!bridge && msg.start?.call_control_id) {
          bridge = open(msg.start.call_control_id, telnyxWs);
        }
        break;

      case "media":
        if (bridge && msg.media?.payload) {
          bridge.realtime.pushAudio(msg.media.payload);
        }
        break;

      case "stop":
        if (bridge) {
          log.info("bridge: telnyx stop event", { ccid: bridge.ccid });
          close(bridge);
          bridge = null;
        }
        break;

      default:
        // connected, mark — fine to ignore
        break;
    }
  });

  telnyxWs.on("close", () => {
    if (bridge) {
      log.info("bridge: telnyx ws close", { ccid: bridge.ccid });
      close(bridge);
      bridge = null;
    }
  });
}

function open(ccid: string, telnyxWs: WebSocket): BridgeState {
  log.info("bridge: opening", { ccid });
  const script = scriptForCcid(ccid);
  if (!script) {
    log.warn("bridge: no scammer script for ccid — closing", { ccid });
    telnyxWs.close();
    return placeholderState(ccid);
  }

  const realtime = Realtime.start({
    ccid,
    systemPrompt: Scripts.bakedPrompt(script),
    voice: script.voice,
    onUserTranscript: (text) => {
      Store.appendTurn(ccid, "user", text);
      log.info("bridge: user turn", { ccid, chars: text.length });
      runDetector(ccid, text);
    },
    onAssistantTranscript: (text) => {
      Store.appendTurn(ccid, "assistant", text);
      log.info("bridge: assistant turn", { ccid, chars: text.length });
      runDetector(ccid, text);
    },
    onAudioOut: (mulawB64) => {
      // ship the AI's TTS bytes back to Telnyx as a media frame so the
      // user hears the scammer speak.
      if (telnyxWs.readyState !== telnyxWs.OPEN) return;
      const out = JSON.stringify({
        event: "media",
        media: { payload: mulawB64 },
      });
      telnyxWs.send(out);
    },
    onClose: () => {
      log.info("bridge: realtime closed", { ccid });
    },
  });

  const state: BridgeState = { ccid, realtime, closed: false };
  ACTIVE.set(ccid, state);
  return state;
}

function close(state: BridgeState): void {
  if (state.closed) return;
  state.closed = true;
  state.realtime.close();
  ACTIVE.delete(state.ccid);
  // we intentionally leave the call state in `Store` so post-call
  // diagnostics (transcript, detector_fired) survive briefly.
}

function scriptForCcid(ccid: string): Scripts.Script | undefined {
  const id = Store.scammerScriptFor(ccid);
  return id ? Scripts.fetchScript(id) : undefined;
}

// fire-and-forget — but with a catch handler so a transient detector
// failure (e.g. OpenAI 5xx in the classifier) doesn't produce an
// unhandled promise rejection that crashes the process.
function runDetector(ccid: string, text: string): void {
  analyze(ccid, text).catch((err: unknown) => {
    log.error("bridge: detector analyze threw", {
      ccid,
      err: err instanceof Error ? err.message : String(err),
    });
  });
}

function placeholderState(ccid: string): BridgeState {
  // construct a no-op so types line up when we bail.
  return {
    ccid,
    realtime: {
      pushAudio: () => {},
      close: () => {},
    },
    closed: true,
  };
}

// ── telnyx wire format ────────────────────────────────────────────────

interface TelnyxMediaMessage {
  event: string;
  start?: { call_control_id?: string };
  media?: { payload?: string };
}
