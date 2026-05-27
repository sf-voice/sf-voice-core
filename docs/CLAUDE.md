# docs/ — sf-voice documentation

Mintlify documentation for San Francisco Voice Company. Read this before touching any file in this folder.

## Run locally

```sh
mise run docs:dev        # starts at http://localhost:3001
mintlify dev             # same thing, from inside docs/
```

Requires `mintlify` CLI: `npm i -g mintlify`. Node 19+.

---

## File map

| File | What it does |
|---|---|
| `docs.json` | Everything: colors, fonts, nav structure, navbar, footer. The only config file. |
| `custom.css` | CSS overrides loaded automatically by Mintlify. Only add rules here that `docs.json` can't handle. |
| `introduction.mdx` | Company intro — mission, first product, GDPR, SDK grid, quickstart CTA. |
| `quickstart.mdx` | Five-minute path from API key to first search result (TypeScript only). |
| `how-it-works.mdx` | The ingest → index → search lifecycle. |
| `data-privacy.mdx` | What we store, regional processing, GDPR, deletion. |
| `sdks/overview.mdx` | All 8 SDKs at a glance + shared error code table. |
| `sdks/*.mdx` | One page per language. Each has install, client, ingest, poll, search, assets, errors. |
| `logos/` | Light and dark logo files. Referenced in `docs.json` as `/logos/light-logo.png` etc. |

---

## Design principles

These come from studying Vercel and Next.js docs. Apply them to every page and every CSS change.

### Sidebar

- **No icons on conceptual pages.** Introduction, Quickstart, How it works, Data Privacy, SDK Overview, Elixir, Kotlin, C++, Go — all have no `icon:` in frontmatter. Vercel's sidebar has no icons. Ours should only use icons where they add meaning.
- **No icons on any SDK pages.** All SDK sidebar items are text-only. Consistency matters more than individual icon value — four branded icons next to five plain items looks broken, not helpful.
- **Section dividers between groups.** `custom.css` adds a thin border-top to every `.sidebar-group + .sidebar-group`. Keep this — it matches the Next.js docs visual structure exactly.
- **Subtle active state.** The active page gets a light tinted background at ~10–15% opacity. Not a heavy filled box. The brand color shows in the text, not a banner.

### Content

- **One reading column, ~620px wide.** `custom.css` constrains `.mdx-content` to `max-width: 620px`. Don't widen it. This is the Next.js / Stripe content width.
- **No feature cards on SDK pages.** The three-card intro blocks (Ingest / Keep your IDs / Scope search) were removed from the TypeScript page. Don't add them back. They fill space without adding information.
- **Code before prose when showing output.** Show what a function returns before explaining the fields.
- **No redundant Notes and Warnings.** Every `<Note>` and `<Warning>` should say something the surrounding text doesn't. Don't use them for decoration.

### Navbar

- **GitHub is the only navbar primary action.** When there's a real dashboard/signup URL, swap it for a `type: "button"` CTA. Until then, GitHub stays.
- **No community links in the navbar.** Discord and Slack live in the footer (`footer.socials`) only. The navbar is for navigation and one conversion action — nothing else.
- **Search bar is always expanded.** `custom.css` overrides Mintlify's collapse-to-icon behaviour and keeps the search bar at 240px wide at all times.

---

## Writing rules

Follow these. They match the voice of Vercel and Next.js docs — direct, technical, no filler.

### Voice

- Second person: "you", "your". Not "the developer" or "the user".
- Active voice. "Send a URL" not "A URL can be sent".
- Sentence case for all headings. "How it works" not "How It Works".
- Lead with what something is before how to use it.

### What never to write

- "powerful", "seamless", "robust", "cutting-edge", "intuitive"
- "it's important to note that", "in order to", "please note"
- "simply", "just", "easily", "obviously"
- Closing summaries that restate what you just said
- Generic opening sentences that describe what the page is about ("This page explains how to ingest media")

### Code blocks

- Always include a language tag: ` ```ts `, ` ```sh `, ` ```json `
- Use realistic values — `call_001`, `customer_acme`, `+14155550199`. Not `foo`, `bar`, `example`.
- One clear example is better than three variations showing the same thing.

### Tables

- Use for reference data: field names, types, defaults, accepted values.
- Don't use tables for prose that reads fine as sentences.
- Keep descriptions short — one clause, not a full sentence with a subject.

---

## docs.json rules

- **Never create `mint.json`** — it's deprecated. `docs.json` only.
- **Add every new page to `navigation.groups`** or it won't appear in the sidebar.
- **No icons in navigation groups.** The SDKs group does not have an `"icon"` field. Consistent with the no-icon sidebar rule.
- **Colors** — primary is `#5E6AD2` (Linear indigo). Don't change to cyan — that's LiveKit territory.
- **Background decoration** is `"grid"` — the subtle grid texture. Don't remove it.
- **Fonts** are Geist (Vercel's font, loaded from Google Fonts by Mintlify).

### Navigation structure

Groups only — no tabs. Tabs are for multi-audience docs (guides vs API reference at different reading levels). We have one audience: engineers.

```
Get Started   → introduction, quickstart, how-it-works
Platform      → data-privacy
SDKs          → overview + one page per language
```

When we add an API reference later (OpenAPI spec), add a second tab at that point. Until then, keep it flat.

---

## SDK pages — standard structure

Every SDK page follows this order exactly:

1. One-line description (what the package is called, where it runs)
2. Install
3. Create a client
4. Ingest (URL, S3, and file examples in a CodeGroup)
5. Poll until ready
6. Search (by asset_class, by asset_ids, global)
7. Assets (list, get, delete)
8. Errors

Don't add marketing sentences between sections. Don't add a "Next steps" block at the end unless there's a genuine next step that isn't obvious from the navigation.

---

## What to learn from Vercel / Next.js docs

These are the reference points. When unsure about a layout or copy decision, compare against these.

| What they do | Why it works |
|---|---|
| No sidebar icons on most pages | Removes visual noise. Text alone is scannable. |
| Muted gray text for non-active items | Creates clear hierarchy. Active page stands out without needing a heavy box. |
| Thin divider lines between nav sections | Separates concerns without vertical whitespace waste. |
| "Last updated" timestamp on pages | Signals freshness. Builds trust. |
| Right TOC with active-section highlight | Orients the reader without requiring scrollback. Mintlify renders this automatically. |
| Collapsed sidebar sections with chevron | Reduces sidebar length without hiding content. Use `expanded: false` on the SDKs group once it's long enough to warrant it. |
| Ghost "Feedback" button + filled CTA in nav | Two distinct actions, clear visual priority. We'll add this once we have a signup URL. |
| Horizontal rules (`---`) between major content sections | Gives the reader a visual breath between conceptual shifts. Use sparingly — not on every page. |
| No feature card grids on reference pages | Cards are for landing pages. Reference pages use prose + code. |
