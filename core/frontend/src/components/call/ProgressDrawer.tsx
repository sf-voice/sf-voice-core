// slide-up drawer pinned to the bottom of the call page. when open,
// hosts the prompt flow.

import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type Props = {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  title?: string;
};

export function ProgressDrawer({ open, onClose, children, title }: Props) {
  return (
    <div
      className={cn(
        "fixed inset-x-0 bottom-0 z-30 transition-transform duration-200",
        open ? "translate-y-0" : "translate-y-full",
      )}
      aria-hidden={!open}
    >
      <div className="mx-auto max-w-3xl bg-neutral-950 border-t border-x border-neutral-800 rounded-t-xl shadow-2xl">
        <div className="flex items-center justify-between px-5 py-3 border-b border-neutral-900">
          <h2 className="text-sm font-semibold text-neutral-100">
            {title ?? "prompt"}
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-neutral-500 hover:text-neutral-100 text-sm"
            aria-label="close"
          >
            ×
          </button>
        </div>
        <div className="px-5 py-4 max-h-[60vh] overflow-y-auto">{children}</div>
      </div>
    </div>
  );
}
