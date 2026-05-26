// third-party AI side-listener for scammer/victim conversations.
//
// runs per finalized transcript turn (both roles), combines a regex
// heuristic score with an LLM classifier score, fires the responder
// once per ccid when the combined score crosses threshold.
//
// scoped to scammer legs only — normal callers don't pay LLM cost.

import { config } from "../config.ts";
import { log } from "../log.ts";
import * as Heuristics from "./heuristics.ts";
import { classify } from "./llm.ts";
import { trigger } from "./responder.ts";
import * as Store from "../store/calls.ts";

export async function analyze(ccid: string, latestText: string): Promise<void> {
  if (!Store.isScammerLeg(ccid)) return;
  if (Store.alreadyFired(ccid)) return;

  const turns = Store.transcript(ccid);

  // STOP TEST is a hard override — bypass the LLM, fire immediately.
  if (Heuristics.isStopTest(latestText)) {
    log.warn("fraud detector: STOP TEST detected", { ccid });
    await fire(ccid, "Operator stop received — call ended.");
    return;
  }

  const heur = Heuristics.score(turns);
  const llm = await classify(turns);

  const signals: Array<{ name: string; score: number }> = [
    { name: "heuristics", score: heur.score },
  ];
  if (llm) signals.push({ name: "llm", score: llm.score });

  const winner = signals.reduce((a, b) => (b.score > a.score ? b : a));

  if (winner.score >= config.fraud.threshold) {
    const summary = buildSummary(winner, heur.labels, llm);
    log.warn("fraud detector: threshold breached", {
      ccid,
      score: winner.score,
      signal: winner.name,
    });
    await fire(ccid, summary);
  } else {
    log.debug("fraud detector: below threshold", {
      ccid,
      heuristics: heur.score,
      llm: llm?.score,
    });
  }
}

// mark fired BEFORE the await so concurrent analyze() calls on the same
// ccid don't both reach `trigger`. on alert-dial failure, unmark so a
// later turn can retry the escalation.
async function fire(ccid: string, summary: string): Promise<void> {
  // second guard: two concurrent analyze() runs that both passed the
  // early check could otherwise both reach markFired + trigger.
  if (Store.alreadyFired(ccid)) return;
  Store.markFired(ccid);
  let result;
  try {
    result = await trigger(ccid, summary);
  } catch (err) {
    log.error("fraud detector: trigger threw", { ccid, err: (err as Error).message });
    Store.unmarkFired(ccid);
    return;
  }
  if (!result.alertQueued) {
    Store.unmarkFired(ccid);
  }
}

function buildSummary(
  winner: { name: string; score: number },
  labels: ReadonlyArray<string>,
  llm: { score: number; reason: string } | null,
): string {
  const labelsStr = labels.length === 0 ? "(none)" : labels.join(", ");
  const base = `Fraud score ${winner.score.toFixed(2)} (${winner.name}). Heuristics: ${labelsStr}.`;
  return llm?.reason ? `${base} Reason: ${llm.reason}` : base;
}
