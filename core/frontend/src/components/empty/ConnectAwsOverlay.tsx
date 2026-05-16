// glass-morphic CTA card that reveals when the user clicks the empty
// dashboard. light-toned even on the dark product theme — meant to feel
// like the marketing brand poking through.

import { Link } from "@tanstack/react-router";
import { Watercolor } from "../brand/Watercolor";

type Props = {
   visible: boolean;
   onDismiss: () => void;
};

export function ConnectAwsOverlay({ visible, onDismiss }: Props) {
   return (
      <div
         role="dialog"
         aria-modal="true"
         aria-hidden={!visible}
         onClick={(e) => {
            // click outside the card body dismisses
            if (e.target === e.currentTarget) onDismiss();
         }}
         className={`absolute inset-0 z-50 flex items-center justify-center transition-opacity duration-300 ${
            visible
               ? "opacity-100 pointer-events-auto"
               : "opacity-0 pointer-events-none"
         }`}
         style={{ backdropFilter: "blur(8px)" }}
      >
         {/* dim wash over the timeline */}
         <div className="absolute inset-0 bg-background/80" aria-hidden />

         <div
            className="relative max-w-md w-full mx-6 rounded-2xl border border-border bg-background p-8 shadow-2xl overflow-hidden grain"
            style={{
               transform: visible ? "translateY(0)" : "translateY(8px)",
               transition: "transform 300ms ease-out",
            }}
         >
            <Watercolor
               hue="cyan"
               size={260}
               opacity={0.6}
               className="-top-20 -right-16"
            />
            <Watercolor
               hue="peach"
               size={220}
               opacity={0.45}
               className="-bottom-16 -left-12"
            />

            <div className="relative">
               <p className="text-sm uppercase tracking-[0.18em] text-muted-foreground font-medium">
                  You're touching the demo
               </p>
               <h2 className="mt-2 font-display text-3xl tracking-tight text-foreground leading-tight">
                  Connect AWS to <em className="italic">hear</em> your own
                  calls.
               </h2>
               <p className="mt-3 text-sm text-muted-foreground leading-relaxed">
                  Point us at the your bucket where your recordings land.
                  Ingest, transcribe, and surface what your voice agent actually
                  said — in about two minutes.
               </p>

               <div className="mt-6 space-y-2">
                  <Link
                     to="/settings/buckets"
                     className="block w-full rounded-md bg-primary text-primary-foreground text-sm font-medium py-2.5 text-center hover:opacity-90 transition-opacity"
                  >
                     Set up via AWS IAM role
                     <span aria-hidden className="ml-1">
                        →
                     </span>
                  </Link>
                  <Link
                     to="/settings/buckets"
                     search={{ method: "keys" } as never}
                     className="block w-full text-center text-sm text-muted-foreground hover:text-foreground transition-colors py-1.5"
                  >
                     Paste access keys instead
                  </Link>
               </div>

               <p className="mt-6 text-sm text-muted-foreground leading-relaxed">
                  We never store long-lived secrets for IAM-role setups.
                  Customer buckets stay in your AWS account; we assume a role
                  with read-only permissions on the prefix you pick.
               </p>
            </div>

            <button
               type="button"
               onClick={onDismiss}
               aria-label="Dismiss"
               className="absolute top-4 right-4 w-7 h-7 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/40 flex items-center justify-center text-lg leading-none"
            >
               ×
            </button>
         </div>
      </div>
   );
}
