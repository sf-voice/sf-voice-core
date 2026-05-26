// in-memory per-call state, replacing the Elixir ETS tables.
// single-process prototype — no need for anything fancier.
//
// internal state stays private to this module; readers only get
// immutable views so external code can't mutate transcripts behind the
// store's back.

import type { ScriptId } from "../scammer/scripts.ts";

export type Role = "user" | "assistant";

export interface TranscriptTurn {
  readonly role: Role;
  readonly text: string;
  readonly at: Date;
}

interface InternalCallState {
  ccid: string;
  scammerScript?: ScriptId;
  alert?: { summary: string; scammerCcid: string };
  detectorFired?: Date;
  transcript: TranscriptTurn[];
}

const STATE = new Map<string, InternalCallState>();

function ensure(ccid: string): InternalCallState {
  let s = STATE.get(ccid);
  if (!s) {
    s = { ccid, transcript: [] };
    STATE.set(ccid, s);
  }
  return s;
}

export function drop(ccid: string): void {
  STATE.delete(ccid);
}

export function markScammer(ccid: string, scriptId: ScriptId): void {
  ensure(ccid).scammerScript = scriptId;
}

export function unmarkScammer(ccid: string): void {
  const s = STATE.get(ccid);
  if (s) delete s.scammerScript;
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

/** consume-once read for alert info — clears the entry so webhook retries
 *  don't replay the speak action and the in-memory entry doesn't leak. */
export function takeAlertInfo(
  ccid: string,
): { summary: string; scammerCcid: string } | undefined {
  const s = STATE.get(ccid);
  if (!s?.alert) return undefined;
  const info = s.alert;
  delete s.alert;
  return info;
}

export function appendTurn(ccid: string, role: Role, text: string): TranscriptTurn {
  const s = ensure(ccid);
  const turn: TranscriptTurn = { role, text, at: new Date() };
  s.transcript.push(turn);
  return turn;
}

/** returns a readonly snapshot of the transcript — external code cannot
 *  push/splice/edit through this reference. */
export function transcript(ccid: string): ReadonlyArray<TranscriptTurn> {
  const t = STATE.get(ccid)?.transcript;
  return t ? t.slice() : [];
}

export function alreadyFired(ccid: string): boolean {
  return !!STATE.get(ccid)?.detectorFired;
}

export function markFired(ccid: string): void {
  ensure(ccid).detectorFired = new Date();
}

export function unmarkFired(ccid: string): void {
  const s = STATE.get(ccid);
  if (s) delete s.detectorFired;
}
