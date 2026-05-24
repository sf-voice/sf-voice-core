// in-memory per-call state, replacing the Elixir ETS tables.
// single-process prototype — no need for anything fancier.

import type { ScriptId } from "../scammer/scripts.ts";

export type Role = "user" | "assistant";

export interface TranscriptTurn {
  role: Role;
  text: string;
  at: Date;
}

export interface CallState {
  ccid: string;
  /** when set, this leg is a scammer leg running the given script. */
  scammerScript?: ScriptId;
  /** when set, this leg is an alert dial-back, carrying the summary
   *  to speak when the operator answers. */
  alert?: { summary: string; scammerCcid: string };
  /** when set, the detector has already triggered for this leg. */
  detectorFired?: Date;
  transcript: TranscriptTurn[];
}

const STATE = new Map<string, CallState>();

export function ensure(ccid: string): CallState {
  let s = STATE.get(ccid);
  if (!s) {
    s = { ccid, transcript: [] };
    STATE.set(ccid, s);
  }
  return s;
}

export function get(ccid: string): CallState | undefined {
  return STATE.get(ccid);
}

export function drop(ccid: string): void {
  STATE.delete(ccid);
}

export function markScammer(ccid: string, scriptId: ScriptId): void {
  ensure(ccid).scammerScript = scriptId;
}

export function isScammerLeg(ccid: string): boolean {
  return !!STATE.get(ccid)?.scammerScript;
}

export function scammerScriptFor(ccid: string): ScriptId | undefined {
  return STATE.get(ccid)?.scammerScript;
}

export function markAlert(
  alertCcid: string,
  summary: string,
  scammerCcid: string,
): void {
  ensure(alertCcid).alert = { summary, scammerCcid };
}

export function isAlertLeg(ccid: string): boolean {
  return !!STATE.get(ccid)?.alert;
}

export function alertInfo(
  ccid: string,
): { summary: string; scammerCcid: string } | undefined {
  return STATE.get(ccid)?.alert;
}

export function appendTurn(ccid: string, role: Role, text: string): TranscriptTurn {
  const s = ensure(ccid);
  const turn: TranscriptTurn = { role, text, at: new Date() };
  s.transcript.push(turn);
  return turn;
}

export function transcript(ccid: string): TranscriptTurn[] {
  return STATE.get(ccid)?.transcript ?? [];
}

export function alreadyFired(ccid: string): boolean {
  return !!STATE.get(ccid)?.detectorFired;
}

export function markFired(ccid: string): void {
  ensure(ccid).detectorFired = new Date();
}
