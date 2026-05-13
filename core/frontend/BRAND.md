# sf-voice / debugger — brand reference

Sub-brand of sf-voice. Source of truth for design tokens, typography, voice, and component patterns across the debugger app. Read once, refer back, don't drift.

The brand is anchored to the live marketing site at https://sf-voice.sh — tokens below were extracted from its production CSS bundle so the debugger reads as the same product.

---

## Identity

> meaning lives beneath the surface of speech.
> — sf-voice

The debugger is the audio engineer's workstation for voice AI. It should feel **precise, calm, and dignified** — like a high-end DAW, not a developer dashboard. Engineers come here to do forensic work; the surface should respect that and stay out of the way.

What we are NOT: playful, loud, gradient-heavy, AI-emoji-stickered, "purple-gradient SaaS."

## Voice and tone

- **Lowercase by default** in UI copy, comments, and labels. Caps reserved for proper nouns and acronyms.
- **Direct and technical**. "no calls yet" beats "you don't have any calls yet, but don't worry!"
- **Occasional poetic flourish** on hero / empty-state copy — sparingly, matching the parent brand. Examples that fit:
  - "meaning lives beneath the surface of speech."
  - "what others hear · what we hear"
  - "you're touching the demo."
- **No filler words** (just, simply, easily). **No emojis.** **No em dashes in user-facing copy** (we keep them in source comments).

## Color tokens

Pulled directly from the production sf-voice.sh CSS bundle. Names match the parent's `--name` custom properties so the debugger inherits identically.

### Core (semantic)

| Token | Value (HSL) | Hex approx | Use |
|---|---|---|---|
| `--background` | `220 20% 97%` | `#F4F5F7` | page background, warm cream |
| `--foreground` | `210 60% 11%` | `#0B1D2D` | primary text, deep navy |
| `--muted` | `210 18% 72%` | `#B0B7BF` | disabled surfaces |
| `--muted-foreground` | `211 35% 31%` | `#33455A` | secondary text |
| `--border` | `210 30% 88%` | `#D6DDE3` | 1px hairlines |
| `--input` | `210 30% 88%` | `#D6DDE3` | form field borders |
| `--ring` | `211 35% 31%` | `#33455A` | focus ring |
| `--primary` | `210 60% 11%` | `#0B1D2D` | filled buttons, default cta |
| `--primary-foreground` | `220 20% 97%` | `#F4F5F7` | text on primary |
| `--destructive` | `12 65% 55%` | `#D26643` | errors, interrupts, alerts |
| `--accent` | `36 47% 82%` | `#E5D2B0` | warm sand highlight |
| `--radius` | `0.375rem` | 6px | corner radius |

### Watercolor accent set

Five named hues, each with a base + deep variant. Use the **base** for fills and decorative blobs at 20–60% opacity; use **deep** for borders, foregrounds on washes, and track waveforms. These hues are the soul of the brand — every track in the timeline gets one.

| Hue | Base | Deep | Assigned to |
|---|---|---|---|
| Cyan | `#CFE7E6` | `#B6D5D4` | **caller** voice waveform |
| Sage | `#C7D8C1` | `#B5CBAE` | **AI** voice waveform |
| Lavender | `#D8C7E6` | `#C7B3DA` | LLM event dots, model thinking |
| Peach | `#F6D6C7` | `#EBC1AD` | **interrupts**, alerts (calm coral) |
| Sand | `#E7D7BE` | `#DBC8A8` | tool calls, neutral metadata |

The destructive coral `#D26643` is reserved for *errors*. Interrupts use peach — they are diagnostic, not catastrophic.

## Typography

| Role | Font | Weight | Tracking |
|---|---|---|---|
| Display / hero / empty-state headlines | **Playfair Display** | 400, 600 | tight (-0.01em) |
| Body, ui labels, buttons | **Inter** | 400, 500, 600 | normal |
| Code, identifiers, timecodes, ms values | `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace` | 400, 500 | normal |

Font scale (use these, don't invent new sizes):

| Size | px | Use |
|---|---|---|
| `text-xs` | 12 | dense labels, hints |
| `text-sm` | 14 | body, buttons, table rows |
| `text-base` | 16 | body emphasis |
| `text-lg` | 18 | section labels |
| `text-2xl` | 24 | page titles |
| `text-4xl` | 36 | empty-state hero |
| `text-6xl` | 60 | landing-only headlines |

Mix Playfair + Inter the way the marketing site does: Playfair for the *promise* (hero, empty-state hook, section eyebrows), Inter for the *work* (data, buttons, controls).

## Density and spacing

**Airy.** Generous whitespace beats dense packing. Tailwind scale (4px base):

- Section gutter: `px-8 py-6` minimum on top-level routes
- Card inner padding: `p-5` (20px) or `p-6` (24px)
- Stack gap between sections: `gap-6` to `gap-8`
- Inline gap inside rows: `gap-3` (12px)

1px borders only. Soft 6px corners (`rounded-md` per `--radius`).

## Signature visual elements

- **Subtle SVG grain overlay** behind hero / empty-state sections. Source is the parent's `--grain` token — a `fractalNoise` filter at low opacity giving paper texture. Apply via a `::before` pseudo-element at ~6% opacity.
- **Watercolor blobs**: radial gradients in lavender, peach, cyan, sage at 5–10% opacity, positioned softly in corners of large surfaces. Never centered, never opaque. Adds the "watercolor wash" sf-voice.sh feel without being decorative noise.
- **Backdrop-blur** on overlays: `backdrop-blur-md` (12px) for full overlays, `backdrop-blur-sm` (2px) for subtle hover states.
- **Mono + sans pairing**: identifiers, IDs, ms values, file paths in mono. Prose, labels, and titles in Inter. Headlines and quotes in Playfair.
- **Comparison columns** ("what others hear / what we hear") — the parent's signature pattern, available to us for empty states, marketing pages, docs.

## Component patterns

### Buttons
- Primary: `bg-foreground text-background rounded-md px-4 py-2 text-sm font-medium hover:opacity-90`
- Secondary: `bg-transparent text-foreground border border-border rounded-md px-4 py-2 text-sm hover:bg-muted/40`
- Tertiary / link: underline on hover, no fill

### Cards
- `bg-background border border-border rounded-md`
- Optional grain overlay via `::before`
- Watercolor blob in a corner if it's a hero card

### Tables (call list)
- `border border-border rounded-md overflow-hidden`
- Header row: `bg-muted/30 text-muted-foreground text-xs uppercase tracking-wider`
- Body rows: `border-t border-border hover:bg-muted/20`

### Overlays (modals, CTA cards)
- Fixed position, centered
- `bg-background/80 backdrop-blur-md border border-border rounded-lg shadow-2xl`
- Watercolor blob inside the card for warmth

## Where each theme applies

Two surfaces. Different jobs, same brand:

| Surface | Theme | Rationale |
|---|---|---|
| **Marketing / auth** (`/signup`, `/login`, public marketing) | **Light** (cream background, navy text, watercolor accents) | Welcoming, brand-consistent with sf-voice.sh, first impression |
| **Product** (after login: timeline, call list, settings, prompt flow) | **TBD — see open decision below** | Tools are often dark for long sessions; brand is light. Tension to resolve. |

Whichever theme applies, the **tokens stay semantic** (`bg-background`, `text-foreground`, etc.). Switching a surface from light to dark only requires re-pointing the CSS variables, not editing components.

### Open decision (block before coding)

Three coherent ways to apply the brand to the product surfaces:

- **A. Light everywhere.** Mirror sf-voice.sh exactly. Cream background, navy text, watercolor accents, in product too. Unified feel, novel for a debugger.
- **B. Hybrid (Vercel-style).** Marketing + auth light; in-product dark (token set inverted). Long debugging sessions stay easy on the eyes; brand still threaded through via the watercolor accents on charts/waveforms.
- **C. Dark everywhere, light accents only.** The current debugger dark theme stays, but every waveform / pill / overlay re-tinted using the watercolor palette so the product reads as sf-voice even at night.

Recommendation: **B**. Marketing/auth pages should feel like sf-voice.sh; the timeline view is where engineers spend hours and dark mode is dramatically easier on the eyes there. The watercolor accents bridge both surfaces visually.

---

## Implementation notes

- Tokens live in `src/index.css` as CSS custom properties on `:root` (and `.dark` for the inverted set). Tailwind 4's `@theme` block aliases them so `bg-background`, `text-foreground`, etc. work everywhere.
- Fonts: load **Inter** and **Playfair Display** from Google Fonts via `<link>` in `index.html`. Add `font-display: swap` to avoid FOIT.
- Grain texture: inline SVG data URI as a CSS background-image, applied via utility class `.grain` or pseudo-elements.
- Watercolor blobs: shipped as a reusable `<Watercolor>` React component (positioned absolutely, configurable hue + opacity).

This file is the spec. Implementation should reference it, not redefine it.
