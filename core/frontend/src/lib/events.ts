// EventSource-based hook for job step streams. native browser API, no
// library. server emits one of four event names per step:
//   step.pending | step.running | step.done | step.failed
// the data payload is a StepEvent json blob.

import { useEffect, useRef, useState } from "react";

const API_BASE_URL = "http://localhost:8080";

export type StepStatus = "pending" | "running" | "done" | "failed";

export type StepEvent = {
  step: string;
  status: StepStatus;
  ts: string;
  detail?: string;
};

const STATUS_NAMES: StepStatus[] = ["pending", "running", "done", "failed"];

export function useJobEvents(jobId: string | null) {
  const [events, setEvents] = useState<StepEvent[]>([]);
  const [error, setError] = useState<Event | null>(null);
  const sourceRef = useRef<EventSource | null>(null);

  useEffect(() => {
    if (!jobId) {
      setEvents([]);
      return;
    }
    setEvents([]);
    setError(null);

    const es = new EventSource(`${API_BASE_URL}/api/jobs/${jobId}/events`);
    sourceRef.current = es;

    const onMessage = (e: MessageEvent) => {
      try {
        const ev: StepEvent = JSON.parse(e.data);
        setEvents((prev) => [...prev, ev]);
      } catch {
        // ignore — keepalive comments parse as empty data.
      }
    };

    for (const name of STATUS_NAMES) {
      es.addEventListener(`step.${name}`, onMessage);
    }
    es.onerror = (ev) => setError(ev);

    return () => {
      for (const name of STATUS_NAMES) {
        es.removeEventListener(`step.${name}`, onMessage);
      }
      es.close();
      sourceRef.current = null;
    };
  }, [jobId]);

  return { events, error };
}

// helper: collapse the event stream into the latest event per step name,
// preserving the order each step first appeared. that's what
// ReasoningPath renders against.
export function latestPerStep(events: StepEvent[]): StepEvent[] {
  const order: string[] = [];
  const latest = new Map<string, StepEvent>();
  for (const e of events) {
    if (!latest.has(e.step)) order.push(e.step);
    latest.set(e.step, e);
  }
  return order.map((s) => latest.get(s)!);
}
