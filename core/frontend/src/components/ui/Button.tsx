// shared button primitive. four variants, three sizes. centralises every
// `rounded-md bg-* px-* py-* hover:*` recipe so future visual tweaks are
// a one-file change. existing inline buttons can be migrated lazily — the
// styles are identical to what was in the wild, just deduplicated.

import { forwardRef, type ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export type ButtonVariant = "primary" | "secondary" | "ghost" | "destructive";
export type ButtonSize = "sm" | "md" | "lg";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
};

const base =
  "inline-flex items-center justify-center gap-1.5 rounded-md font-medium " +
  "transition-colors disabled:opacity-50 disabled:cursor-not-allowed " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring " +
  "focus-visible:ring-offset-2 focus-visible:ring-offset-background";

const variants: Record<ButtonVariant, string> = {
  primary:
    "bg-primary text-primary-foreground hover:opacity-90",
  secondary:
    "border border-border bg-surface text-foreground hover:bg-muted/60",
  ghost:
    "text-muted-foreground hover:text-foreground hover:bg-muted/50",
  destructive:
    "bg-destructive text-destructive-foreground hover:opacity-90",
};

const sizes: Record<ButtonSize, string> = {
  sm: "h-7 px-2.5 text-xs",
  md: "h-8 px-3 text-sm",
  lg: "h-10 px-4 text-sm",
};

export const Button = forwardRef<HTMLButtonElement, Props>(function Button(
  { variant = "secondary", size = "md", className, type = "button", ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      className={cn(base, variants[variant], sizes[size], className)}
      {...rest}
    />
  );
});
