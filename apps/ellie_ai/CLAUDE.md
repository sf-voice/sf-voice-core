# EllieAi

App-specific instructions for Claude. Read after the root `CLAUDE.md`.

## Audience and environment

Ellie runs on screens inside restaurants. The lighting is unpredictable:
direct afternoon sun on a host stand, dim service light during dinner,
back-of-house fluorescents, smudged or greasy screens. Staff using it are
often mid-task, not focused, and not "computer people."

## Design requirement: high contrast

Every UI surface in this app must be designed for legibility first.
Maximize contrast between text and background on every screen, in every
state. Default to the most contrast that still looks intentional, not the
least.

Concrete floors (do not go below):

- Every text/background pair must clear **WCAG AAA**: 7:1 for body text,
  4.5:1 for large text (18pt+ or 14pt+ bold).
- Minimum font size **14px** for any text a user has to read to act.
- Minimum font weight **500** for body text. No thin or extra-light
  weights anywhere.
- No grey-on-grey, no muted placeholder text the user has to lean in to
  read, no decorative low-contrast borders or dividers.

If a design choice trades contrast for prettiness, contrast wins. Flag
the tradeoff before making it — never silently soften something to look
nicer.
