// shared inline-svg icons. matches the sentry-flavoured pattern already
// in Layout.tsx (viewBox 16x16, currentColor stroke 1.4, round caps).
// kept inline so we don't pull a 200kb icon lib for a handful of glyphs.

type IconProps = { className?: string };

export function IconCloud({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      className={className}
    >
      <path
        d="M5 12h6.5a2.5 2.5 0 0 0 .3-4.98 4 4 0 0 0-7.55-1A2.75 2.75 0 0 0 5 12z"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function IconCloudOff({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      className={className}
    >
      <path
        d="M5 12h6.5a2.5 2.5 0 0 0 .3-4.98 4 4 0 0 0-7.55-1A2.75 2.75 0 0 0 5 12z"
        strokeLinejoin="round"
      />
      <path d="M2 2l12 12" strokeLinecap="round" />
    </svg>
  );
}

export function IconCheck({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      className={className}
    >
      <path d="M3.5 8.5l3 3 6-7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function IconX({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      className={className}
    >
      <path d="M4 4l8 8M12 4l-8 8" strokeLinecap="round" />
    </svg>
  );
}

// hollow ring — pending/idle marker.
export function IconCircle({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.4"
      className={className}
    >
      <circle cx="8" cy="8" r="5" />
    </svg>
  );
}

// spinner — pair with `animate-spin` on the parent. dashed arc gives the
// motion read at any size without needing a nested moving element.
export function IconLoader({ className }: IconProps) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      className={className}
    >
      <circle cx="8" cy="8" r="5.5" strokeOpacity="0.25" />
      <path d="M13.5 8a5.5 5.5 0 0 0-5.5-5.5" strokeLinecap="round" />
    </svg>
  );
}
