---
title: "Svelte: svelte.dev, the interactive tutorial, the playground, the docs and docs for LLMs"
urls:
  - https://svelte.dev/
  - https://svelte.dev/tutorial/svelte/welcome-to-svelte
  - https://svelte.dev/playground
  - https://svelte.dev/docs/svelte/overview
  - https://svelte.dev/docs/svelte/getting-started
  - https://svelte.dev/docs/svelte/compiler-warnings
  - https://svelte.dev/docs/cli/overview
  - https://svelte.dev/docs/llms
  - https://svelte.dev/llms.txt
  - https://svelte.dev/docs/ai/overview
  - https://svelte.dev/docs/ai/tools
  - https://svelte.dev/packages
date: 2026-10-25
relevance: 4
---

# Svelte

Svelte is a compiler-first UI framework: components are compiled ahead of time into code that
updates the DOM directly. One site, svelte.dev, holds everything: Svelte, SvelteKit, the CLI,
the AI tooling, a tutorial, a playground, curated packages and the blog. It is the smallest and
most coherent of the three sites in this set, and the one that has gone furthest on docs for
LLMs. Pages fetched 2026-10-24.

## 1. What the site and docs contain

### Top nav and homepage

- **Nav:** Docs (Svelte, SvelteKit, CLI, AI), **Playground** (Create new app, Your saved apps),
  **Tutorial**, Packages, Blog; icons for Discord (/chat), Bluesky, GitHub.
- **Homepage, in order:** "Svelte" / "web development for the rest of us" with one CTA, "get
  started" → /docs; a compiler illustration; a pronunciation joke ("attractively thin, graceful
  and stylish"); one paragraph ("a UI framework that uses a compiler to let you write
  breathtakingly concise components … It's a love letter to web development"); survey badges
  (Stack Overflow 2024, State of JS 2025); "used by companies you've heard of" logos; the "Svelte
  Origins" documentary; community (Svelte Society, Discord); "backed by" Vercel and donors, "Svelte
  is here to stay", contributor avatars and sponsors. **There is no code on the homepage.**

### Tutorial (svelte.dev/tutorial)

- Prose on one side, an editor with a file tree (`src/App.svelte`) and a live preview on the
  other; toggles for text/editor and Vim mode.
- Four parts: **Basic Svelte** (Introduction, Reactivity, Props, Logic, Events, Bindings, Classes
  and styles, Attachments, Transitions), **Advanced Svelte** (advanced reactivity, snippets,
  motion, context, special elements, `<script module>`), **Basic SvelteKit** (routing, loading,
  forms, API routes, errors), **Advanced SvelteKit** (hooks, page options, advanced routing).
- "Each section will present an exercise designed to illustrate a feature." "If you get stuck,
  you can click the `solve` button in the top right of the screen", with the advice not to lean on
  it because typing the code yourself teaches faster.

### Playground

- Editor, live result, and **JS output, CSS output and AST output** tabs showing what the compiler
  produced (compile options affect only the output tabs, per a maintainer in
  sveltejs/svelte.dev#738). Save and share with a GitHub login; "Your saved apps".
- Sidebar examples in 22 groups: Introduction, Reactivity, Props, Logic, Events, Bindings,
  Lifecycle, Stores, Motion, Transitions, Animations, Easing, SVG, Actions, Classes, Component
  composition, Context API, Special elements, Module context, Debugging, **7GUIs**, Miscellaneous.

### Docs

- A switcher for four doc sets (Svelte, SvelteKit, CLI, AI). The Svelte set: Introduction
  (Overview, Getting started, file types) → Runes ($state, $derived, $effect, $props, …) →
  Template syntax (one page per block: {#if}, {#each}, {#await}, bind:, transition:, …) →
  Styling → Special elements → Runtime → Misc (best practices, testing, TypeScript, **Svelte 4
  and 5 migration guides**, FAQ) → Reference (one page per module, then **Compiler errors,
  Compiler warnings, Runtime errors, Runtime warnings**) → Legacy APIs, kept but fenced off.
- Opening line: "Svelte is a framework for building user interfaces on the web."
- **Getting started** is four commands: `npx sv create myapp`, `cd myapp`, `npm install`,
  `npm run dev`; then editor tooling and `npx sv check`.
- **Compiler warnings page:** ~80 warnings, each under its own anchor (`#a11y_autofocus`), with
  the message template ("Avoid using autofocus"), why it matters, a snippet that triggers it, and
  sometimes the fix. Suppression is a `svelte-ignore` comment above the line, because "Some
  warnings may be incorrect in your concrete use case."
- **CLI (`sv`):** create, add, check, migrate; add-ons (eslint, playwright, vitest, tailwindcss,
  storybook, drizzle, mdsvex, **ai-tools**, …) and community add-ons.

### Docs for LLMs and the AI docs

- svelte.dev/llms.txt points to three generated sizes: **llms-full.txt** (1.26 MB, "complete
  documentation … including all examples"), **llms-medium.txt** (870 KB, "examples and
  non-essential content removed") and **llms-small.txt** (53 KB, "many examples and non-essential
  content removed"), plus per-package files (/docs/svelte/llms.txt, /docs/kit/llms.txt, …). "The
  content is automatically generated from the same source as the official documentation."
- /docs/ai: Instructions (an AGENTS.md), an **MCP server**, Skills, Subagents, and plugins for
  Claude Code, OpenCode, Cursor, Copilot CLI and Codex CLI. The MCP tools: `list-sections`,
  `get-documentation`, **`svelte-autofixer`** ("static analysis on LLM-generated code"; "the model
  can call it repeatedly until no issues remain") and **`playground-link`** ("Generates an
  ephemeral playground link with the generated code").

### Packages

- "We've collected a few of our favourite packages that work well with Svelte and SvelteKit
  apps": ~20 categories, cards with version, last update and two unlabeled numbers. No search, no
  compatibility information.

## 2. High-ROI pieces

1. **The tutorial: edit, see, solve.** Every lesson is a runnable exercise with a preview and a
   `solve` button. It removes install from learning entirely and teaches by small edits, which is
   how people actually learn a component model. This is widely cited as the reason Svelte feels
   easy.
2. **JS output in the playground.** Showing exactly what the compiler produced is Svelte's
   argument made concrete: "look how little it does". It turns a design philosophy into something
   a reader can inspect.
3. **Docs for LLMs, generated from the same source.** Three sizes for three context windows,
   per-package files, and no drift because they are built from the docs. Plus an MCP tool that
   checks generated code and one that turns it into a shareable runnable link.
4. **Errors and warnings as reference pages with anchors.** Each diagnostic has a stable URL, an
   example and a reason. Diagnostics link to docs; search lands on them.
5. **7GUIs in the examples.** A standard benchmark of GUI tasks (counter, temperature converter,
   flight booker, timer, CRUD, circle drawer, cells), solved in the framework, so readers can
   compare frameworks task by task.
6. **One site, one IA.** Svelte, Kit, CLI and AI share a nav and a switcher; nothing is on
   another domain.
7. **Migration guides and fenced legacy APIs.** Svelte 5's runes changed everything; the docs keep
   old APIs reachable under "Legacy APIs" instead of deleting them, so old code still has docs.

## 3. Low-value or missing

- **The homepage shows no code and no running component.** For a framework whose pitch is
  concision, it relies on survey badges, logos, a documentary and a pronunciation joke. Someone
  who doesn't already know Svelte learns almost nothing from it; the tutorial carries the load.
- **Packages page:** hand-curated favourites with unlabeled numbers, no search, no compatibility.
  It neither helps choose nor signals quality; npm does the real work.
- **Sustainability section** ("Svelte is here to stay", sponsors) answers a worry most first-time
  visitors don't have yet.
- **No showcase of real apps** beyond the logo strip.

## 4. For Cairn: cut / keep / add

**Keep**

- **The homepage's annotated `move ^2 reset` sample.** It already does what Svelte's homepage
  doesn't: show the idea in code. It should be the first thing, not below the milestone panel.
- **The "every sample is included from a file `make check` compiles" rule** (/docs/). It is the
  same guarantee Svelte gets by generating llms.txt from the docs source; extend it to every
  generated surface.
- **/docs/reference/errors/** (today "Errors to do" in the sidebar). Svelte shows this is worth
  finishing: one anchored entry per diagnostic, with an example and the fix.

**Cut or demote**

- **The pixel-art night scene** as the main homepage content. Svelte's
  decoration (pronunciation, documentary) is its weakest part too. Keep a small band, not the
  page.
- **"Latest milestone" as the homepage's main panel** and **/milestones/ in the top nav at the
  same level as Docs.** Svelte keeps Blog in the nav but the homepage CTA is "get started". Make
  milestones the blog; move the panel down.
- **/packages/ in its current form** if it stays at two libraries and zero apps. Svelte's curated
  list shows a registry front end with no quality signal is low value; Cairn's has one (claims
  per version), so either put that signal in front (see the Flutter note's score block) or drop
  /packages/ from the top nav until there are more than a handful of packages.
- **The "Maps" top-nav item.** Readers don't know what a map is before they know what a claim is.
  Svelte's nav is Docs / Playground / Tutorial; Cairn's should be Docs / Tutorial-or-Examples /
  Packages / Milestones, with maps reached from examples.

**Add**

- **llms.txt and llms-full.txt**, generated by the docs build from the same Markdown (site/web/
  content/docs) and the API reference. /llms.txt 404s on Cairn today. Cairn is built largely by
  agents and its users will write Lean with agents; a small llms-small.txt (guide + claims
  reference + the claim command syntax) would pay for itself immediately. Also serve each docs
  page as `.md`.
- **7GUIs as Cairn examples with maps.** Cairn has Counter (7GUIs task 1) already. The other six
  (temperature converter, flight booker, timer, CRUD, circle drawer, cells) are each a small set
  of moves with real invariants ("return date is never before departure", "the timer never
  exceeds its duration"). A /docs/examples/7guis/ page with seven maps would be a direct,
  comparable showcase against every framework that has done 7GUIs, and cheaper than another
  milestone app.
- **A "what the proof checked" view, like JS output.** Svelte shows the compiled JS; Cairn's
  equivalent is showing, for a move, the theorem Lean checked and its axioms, beside the source.
  The API page has the counts ("684 theorems, every one on the standard axioms"); per-move
  "show the statement" toggles on the guide's samples would make the claim tangible.
- **A one-line getting started at the top of /docs/**: `cairn new hello --bin`, `cd hello`, `cairn build`, then run
  the host (docs/cli.md lists `cairn run` as not yet built), the way Svelte's is four commands. Today /docs/guide/first-app/ opens with prerequisites
  and says the repository "isn't public yet", which is out of date.

## 5. Ideas for the framework itself

- **Compiler-first, diagnostics as product.** Svelte's warnings (a11y ones especially) are part
  of the framework's value. Cairn's claim commands run at compile time (docs/claims.md); they can
  warn too: a control with no move, a move with no `sees`, a place with no reachable moves, a
  flow whose witness is longer than N. Each with a stable code and a docs anchor. Touches
  docs/claims.md and docs/doc.md (generating the reference page from the warning list).
- **An autofixer for agents.** `svelte-autofixer` runs static analysis on generated code and the
  model iterates "until no issues remain". Cairn's equivalent is a `cairn check --json` that an
  agent can loop on: build errors, missing proofs, ids missing from claims.lock, axioms used,
  with the claim id for each. Touches docs/cli.md.
- **Playground links.** `playground-link` turns generated code into a runnable URL. A browser
  Cairn isn't realistic soon (the host is AppKit and Metal), but a "frame link" is: run `view` on
  a state in Lean, render with the headless capture, and share the image plus the claims it
  shows. Touches docs/cli.md and docs/map.md.
- **`sv add` add-ons.** One command adds testing, lint or AI tooling to a project. `cairn add`
  already adds a package dependency (docs/cli.md); add-ons would extend it to evidence tooling
  (`cairn add fuzz`, `cairn add map`, `cairn add agents` writing an AGENTS.md for Cairn apps), so
  an app outside the Cairn repo gets maps and fuzzing in one line. Touches docs/cli.md and
  docs/package.md.
- **`sv migrate`.** Svelte ships a codemod for each breaking release. Cairn's id contract means
  claims never change meaning silently; API changes should come with the same kind of migration
  note (and eventually a Lean-level rewrite) per release. Touches docs/roadmap.md and
  /docs/reference/releases/.
- **Legacy APIs kept, fenced.** Cairn already retires claims rather than deleting them; do the
  same for docs pages of retired APIs, so a link to an old page still says what replaced it.
  Touches docs/doc.md.
