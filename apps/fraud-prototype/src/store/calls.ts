type CallRole = "scammer" | "alert";

type CallState = {
   role: CallRole;
   script?: string;
};

const calls = new Map<string, CallState>();

export function markScammerLeg(ccid: string, script: string): void {
   calls.set(ccid, { role: "scammer", script });
}

export function markAlertLeg(ccid: string): void {
   calls.set(ccid, { role: "alert" });
}

export function isScammerLeg(ccid: string): boolean {
   return calls.get(ccid)?.role === "scammer";
}

export function isAlertLeg(ccid: string): boolean {
   return calls.get(ccid)?.role === "alert";
}

export function getScript(ccid: string): string | undefined {
   return calls.get(ccid)?.script;
}

export function drop(ccid: string): void {
   calls.delete(ccid);
}
