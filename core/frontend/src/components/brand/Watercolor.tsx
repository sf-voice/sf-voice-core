// soft radial blob in one of the brand's watercolor hues. used to add
// warmth to hero + empty-state surfaces. always pointer-events-none,
// always aria-hidden, always absolutely positioned.

import { cn } from "@/lib/utils";

export type WatercolorHue =
  | "cyan"
  | "sage"
  | "lavender"
  | "peach"
  | "sand";

const HEX: Record<WatercolorHue, string> = {
  cyan: "#CFE7E6",
  sage: "#C7D8C1",
  lavender: "#D8C7E6",
  peach: "#F6D6C7",
  sand: "#E7D7BE",
};

type Props = {
  hue: WatercolorHue;
  /** diameter in px. defaults to a generous 480 — big and soft. */
  size?: number;
  /** 0..1, defaults to 0.45. keep below 0.6; this is wash, not paint. */
  opacity?: number;
  /** placement classes (top-, left-, etc.). */
  className?: string;
};

export function Watercolor({
  hue,
  size = 480,
  opacity = 0.45,
  className,
}: Props) {
  return (
    <div
      aria-hidden
      className={cn(
        "pointer-events-none absolute rounded-full blur-3xl",
        className,
      )}
      style={{
        width: size,
        height: size,
        opacity,
        background: `radial-gradient(circle, ${HEX[hue]} 0%, transparent 70%)`,
      }}
    />
  );
}
