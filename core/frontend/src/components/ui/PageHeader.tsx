// shared page-header pattern. settings + admin pages all open with a
// title + optional description; pulling it into one component keeps
// spacing, font sizes, and the top divider consistent.

import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type Props = {
  title: string;
  description?: ReactNode;
  // right-aligned slot for action buttons / status pills next to the title
  actions?: ReactNode;
  className?: string;
};

export function PageHeader({ title, description, actions, className }: Props) {
  return (
    <header
      className={cn(
        "flex items-start justify-between gap-4 pb-5 mb-6 border-b border-border",
        className,
      )}
    >
      <div className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight font-sans">
          {title}
        </h1>
        {description && (
          <p className="mt-1 text-sm text-muted-foreground max-w-2xl">
            {description}
          </p>
        )}
      </div>
      {actions && <div className="shrink-0 flex items-center gap-2">{actions}</div>}
    </header>
  );
}
