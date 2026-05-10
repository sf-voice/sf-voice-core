# EllieAi — agent rules

App-specific Phoenix/Elixir guidance for ellie_ai. Read after the root
`AGENTS.md`, which covers the framework-level rules that apply to every
app in this workspace.

## Design rules (enforced in code review)

Ellie runs on screens inside restaurants — bright sun, dim service
light, smudged glass. Design for legibility. The rules below are the
floor, not the target.

### Contrast

- Every text/background pair must clear **WCAG AAA**: contrast ratio
  **≥ 7:1** for body text, **≥ 4.5:1** for large text (18pt+ or 14pt+
  bold).
- No grey-on-grey, no muted timestamps, no low-contrast decorative
  borders. If a divider isn't visible against its background at arm's
  length under fluorescent light, it shouldn't be there.

### Typography

- Minimum font size **14px** for anything the user has to read to act.
- Minimum font weight **500** for body copy. No `font-thin`,
  `font-extralight`, or `font-light` classes anywhere.
- Placeholder text must meet the same contrast floor as body text. If
  it can't, drop the placeholder and use a persistent label instead.

### State and feedback

- Disabled, hover, focus, and active states must each independently
  meet the contrast floor. A disabled button that fades to invisible is
  a bug.
- Focus rings must be visible without squinting — solid, ≥ 2px, and
  high-contrast against both the element and its background.

When a design or component conflicts with these rules, fix the design.
Do not silently relax the rule.
