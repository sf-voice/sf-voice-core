// the full-bleed mock audio-mixing surface a new user sees before any
// real calls land. five stacked tracks, auto-scrolling playhead, a thin
// time ruler. NO CTA on first paint — touching anything reveals the
// connect-aws overlay (ConnectAwsOverlay).

import { useEffect, useRef, useState } from "react";
import { MockTrack } from "./MockTrack";
import { ConnectAwsOverlay } from "./ConnectAwsOverlay";
import { Watercolor } from "../brand/Watercolor";
import { IconCloud, IconCloudOff } from "../ui/icons";
import { useBucket } from "@/lib/queries";

const TRACKS: Array<{
   label: string;
   kind: "wave" | "vad" | "dots" | "bars";
   color: string;
   intensity?: number;
   seed: number;
}> = [
   {
      label: "Caller",
      kind: "wave",
      color: "var(--color-cyan-deep)",
      seed: 1,
      intensity: 0.9,
   },
   {
      label: "AI",
      kind: "wave",
      color: "var(--color-sage-deep)",
      seed: 7,
      intensity: 0.75,
   },
   {
      label: "VAD",
      kind: "vad",
      color: "var(--color-lavender-deep)",
      seed: 13,
      intensity: 1,
   },
   {
      label: "LLM",
      kind: "dots",
      color: "var(--color-lavender-deep)",
      seed: 19,
      intensity: 1,
   },
   {
      label: "Tools",
      kind: "bars",
      color: "var(--color-sand-deep)",
      seed: 23,
      intensity: 1,
   },
];

export function EmptyDashboard() {
   const [overlayOpen, setOverlayOpen] = useState(false);
   const [playhead, setPlayhead] = useState(0); // 0..1 across the canvas
   const playing = !overlayOpen;
   const { data: bucket } = useBucket();
   const connected = Boolean(bucket?.method);
   const rafRef = useRef<number | null>(null);
   const lastRef = useRef<number>(0);

   // auto-scrolling playhead loop. paused while the overlay is open so
   // motion doesn't fight the user reading the cta.
   useEffect(() => {
      if (!playing) return;
      const tick = (t: number) => {
         const dt = lastRef.current === 0 ? 16 : t - lastRef.current;
         lastRef.current = t;
         // 28s sweep across the canvas. matches "feel" of a real ~30s call.
         setPlayhead((p) => (p + dt / 28000) % 1);
         rafRef.current = requestAnimationFrame(tick);
      };
      rafRef.current = requestAnimationFrame(tick);
      return () => {
         if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
         lastRef.current = 0;
      };
   }, [playing]);

   return (
      <div
         className="relative h-full min-h-[calc(100vh-0px)] overflow-hidden"
         onClick={() => {
            if (!overlayOpen) setOverlayOpen(true);
         }}
      >
         {/* watercolor warmth in two corners — the dark theme inherits the
          same hex values, so they bloom softly against the deep navy bg. */}
         <Watercolor
            hue="lavender"
            size={520}
            opacity={0.18}
            className="-top-32 -left-32"
         />
         <Watercolor
            hue="cyan"
            size={460}
            opacity={0.15}
            className="bottom-1/4 -right-32"
         />

         {/* header strip */}
         <header className="relative z-10 px-10 pt-10 pb-6">
            <p className="text-sm uppercase tracking-[0.18em] text-muted-foreground font-medium">
               Your calls
            </p>
            <h1 className="mt-2 font-display text-4xl tracking-tight text-foreground">
               Nothing yet.
            </h1>
            <p className="mt-2 text-sm text-muted-foreground max-w-md leading-relaxed">
               The surface below is a sample call. Yours will live here once you
               connect a bucket.
            </p>
         </header>

         {/* timeline ruler */}
         <div className="relative z-10 px-10 mt-4">
            <Ruler />
         </div>

         {/* tracks */}
         <div className="relative z-10 px-10 mt-6 space-y-8">
            {TRACKS.map((t) => (
               <div key={t.label} className="h-16">
                  <MockTrack
                     label={t.label}
                     kind={t.kind}
                     color={t.color}
                     intensity={t.intensity}
                     seed={t.seed}
                  />
               </div>
            ))}
         </div>

         {/* playhead — vertical amber line riding from left to right */}
         <div
            className="absolute top-0 bottom-0 w-px bg-foreground/40 pointer-events-none"
            style={{
               left: `calc(80px + ${playhead * 100}% * (1 - 80px / 100vw))`,
               transform: "translateX(0)",
            }}
            aria-hidden
         >
            <div className="absolute -top-1.5 -translate-x-1/2 w-2.5 h-2.5 rotate-45 bg-foreground/60 rounded-[2px]" />
         </div>

         {/* hint strip pinned bottom */}
         <footer className="absolute bottom-0 left-0 right-0 z-10 px-10 py-4 flex items-center justify-between border-t border-border bg-background">
            <span className="text-sm font-mono text-foreground inline-flex items-center gap-2">
               {connected ? (
                  <IconCloud className="w-4 h-4 text-success" />
               ) : (
                  <IconCloudOff className="w-4 h-4 text-warning" />
               )}
               {connected ? "Connected to storage" : "Not connected to storage"}
            </span>
         </footer>

         <ConnectAwsOverlay
            visible={overlayOpen}
            onDismiss={() => setOverlayOpen(false)}
         />
      </div>
   );
}

function Ruler() {
   // 12 ticks across, labeled at every 5s up to ~48s.
   const ticks = Array.from({ length: 13 });
   return (
      <div className="relative h-6 ml-20 border-b border-border/40">
         {ticks.map((_, i) => {
            const pct = (i / (ticks.length - 1)) * 100;
            const sec = i * 4;
            return (
               <div
                  key={i}
                  className="absolute top-0 text-[10px] font-mono text-muted-foreground"
                  style={{ left: `${pct}%`, transform: "translateX(-50%)" }}
               >
                  <div className="h-2 w-px bg-border mx-auto" />
                  <div className="mt-0.5">
                     0:{sec.toString().padStart(2, "0")}
                  </div>
               </div>
            );
         })}
      </div>
   );
}
