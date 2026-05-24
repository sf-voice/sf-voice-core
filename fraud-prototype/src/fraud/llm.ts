// fraud-classifier LLM call. uses OpenAI chat completions in JSON mode,
// same shape the Elixir version used via Medium.Chat. cheap model is
// fine — the heuristic catches the obvious cases; the LLM is the
// "smell test" for everything else.

import OpenAI from "openai";
import { config } from "../config.ts";
import { log } from "../log.ts";
import type { Turn } from "./heuristics.ts";

let cached: OpenAI | null = null;
function openai(): OpenAI {
  if (!cached) cached = new OpenAI({ apiKey: config.openai.apiKey });
  return cached;
}

export interface LlmScore {
  score: number;
  reason: string;
}

export async function classify(turns: ReadonlyArray<Turn>): Promise<LlmScore | null> {
  if (turns.length === 0) return null;
  const body = turns.map((t) => `${t.role}: ${t.text}`).join("\n");
  try {
    const r = await openai().chat.completions.create({
      model: config.openai.classifierModel,
      response_format: { type: "json_object" },
      temperature: 0,
      messages: [
        {
          role: "system",
          content: `You are a fraud/scam call classifier. Read the conversation and return ONLY a JSON object:
{"score": <float 0..1>, "reason": "<<=120 chars>"}
- 0.0 means clearly benign (no scam markers)
- 1.0 means clearly a phone scam (impersonation, payment-method tells, urgency, social engineering)
Be cautious — only score >0.5 when there is real evidence in the conversation. No prose outside JSON.`,
        },
        { role: "user", content: body },
      ],
    });
    const content = r.choices[0]?.message?.content;
    if (!content) return null;
    const parsed = JSON.parse(content) as { score?: unknown; reason?: unknown };
    const score = typeof parsed.score === "number" ? clamp(parsed.score) : null;
    if (score === null) return null;
    const reason = typeof parsed.reason === "string" ? parsed.reason : "";
    return { score, reason };
  } catch (err) {
    log.warn("llm classifier failed", { err: (err as Error).message });
    return null;
  }
}

function clamp(n: number): number {
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}
