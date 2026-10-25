---
title: "Elixir and Phoenix: elixir-lang.org, HexDocs/ExDoc, hex.pm, Livebook, phoenixframework.org, LiveView"
urls:
  - https://elixir-lang.org/
  - https://elixir-lang.org/docs/
  - https://elixir-lang.org/learning/
  - https://elixir-lang.org/blog/
  - https://elixir.hexdocs.pm/introduction.html
  - https://elixir.hexdocs.pm/docs-tests-and-with.html
  - https://ex-doc.hexdocs.pm/readme.html
  - https://hex.pm/packages/phoenix_live_view
  - https://livebook.dev/
  - https://livebook.dev/badge/
  - https://www.phoenixframework.org/
  - https://phoenix-live-view.hexdocs.pm/welcome.html
date: 2026-10-25
relevance: 5
---

# Elixir and Phoenix

The most relevant of the three for Cairn. Elixir's ecosystem made one decision that everything
else follows from: **documentation is part of the language** (`@doc`, doctests, ExDoc), and
every package on hex.pm gets the same docs site on HexDocs. LiveView is also the closest
production analogue to Cairn's architecture: state and rendering live in one place, and a thin
client paints diffs.

## 1. What the site and docs contain

**elixir-lang.org top nav** (fetched 2026-10-24): Home, Install (`/install/`), Learning
(`/learning/`), Docs (`/docs/`), Case studies (`/cases/`), Blog (`/blog/`), and a **Get
started** button straight to the guide on HexDocs. A banner links the v1.20 release post.

**Homepage**, in order: hero "Simple from zero to scale" (four bullets), Install now / Get
started; a code sample (a pipeline counting words with `Enum.frequencies()`, output shown);
"Why Elixir?" (Maintenance, Scalability, Loved by developers, Productivity: "built-in package
manager, formatter, and documentation, plus IEx and Livebook"); Elixir in production (logos);
**Use Elixir for**, tabs (Web development, Embedded, Machine Learning, Data and media, IoT &
Distributed), each with a code sample and the libraries to use (Phoenix, LiveView, Nerves, Nx,
Livebook, Broadway…); "What will you build?" → hex.pm; Shaped by many (team, EEF); Open Source
Stewards (companies funding full-time work).

**Docs** (`/docs/`): "The Elixir programming language is broken into 6 applications" (Elixir,
EEx, ExUnit, IEx, Logger, Mix). Per version (v1.20.4 back to v1.15, plus main): supported
Erlang/OTP versions, a Docs.zip, and links to each app's HexDocs.

**Learning** (`/learning/`): official resources (Getting Started guide, Mix and OTP, API docs),
then books, courses, screencasts, Exercism, Elixir School, Koans.

**Blog** (`/blog/`): four categories, Releases, Announcements, Elixir in Production,
Internals. Release posts double as feature explainers ("Elixir v1.20 released: now a gradually
typed language"). Internals posts go deep on the type system ("Lazy BDDs with eager literal
intersections").

**HexDocs / ExDoc** (e.g. `elixir.hexdocs.pm/introduction.html`; HexDocs now serves each
package on its own subdomain): sidebar with guides and modules, search box "Search
documentation of Elixir" with scope "Elixir + libraries" or "Search only this project"; version
shown (v1.20.4) with a version dropdown; each page has **"Copy Markdown"** and **"View
Source"**; footer "Go to package docs · View llms.txt · Download ePub version · Built using
ExDoc (v0.40.3)". ExDoc's feature list: "Automatically generates offline-accessible HTML,
Markdown (including `llms.txt`), and EPUB documents", "Full-text search", "Quick-search with
autocompletion support", "Version dropdown and 'Go to latest' notifications, automatically
configured when hosted on HexDocs". Autolinking: "ExDoc … will automatically generate links
across modules and functions if you enclose them in backticks." Extra pages: "Cheatsheets
(`.cheatmd`) - useful for discovery and quick reference" and "Livebooks (`.livemd`) - useful
for tutorials, interactive examples, and deep dives".

**Doctests** (Getting Started, "Documentation, doctests and with"): "Doctests are specified by
an indentation of four spaces followed by the `iex>` prompt in a documentation string"; "Elixir
makes documentation a first-class citizen in the language"; "doctest is documentation first and
a test later. Their goal is not to replace tests but to provide up-to-date documentation."

**hex.pm package page** (`/packages/phoenix_live_view`): name, version strip, description;
tabs Readme / Changelog / License; Dependency Config for mix.exs, rebar.config, Gleam,
erlang.mk; links HexDocs, Changelog, GitHub; license; downloads chart; "194 Versions";
"9 Dependencies", "756 Dependants"; "2 Advisories"; publisher and owners; checksum; Last
Updated; Build Tools; Files; Activity (audit log).

**Livebook** (livebook.dev): "Automate code & data workflows with interactive notebooks."
Desktop app for Mac/Windows/Linux; Smart cells; integrations; welcome notebooks. "Notebooks are
stored as .livemd files, a subset of Markdown that meshes together prose, code, and diagrams",
so they diff and version normally. The **Run in Livebook** badge (livebook.dev/badge) links to
`livebook.dev/run?url=…`, which opens any public notebook in your own Livebook.

**phoenixframework.org**: nav Docs (HexDocs), Community, Source, Blog. Hero "Peace of mind from
prototype to production"; a `TimelineLive` code sample; LiveView pitch and the three-command
install (`mix archive.install hex phx_new`); "Everything you need to ship it" (Real-time,
`mix phx.gen.auth`, APIs, Docker, Metrics with a live dashboard, Presence, Ecto); HEEx
(components, compiler checks, formatting); company logos. The docs are just HexDocs.

**LiveView docs** (`phoenix-live-view.hexdocs.pm/welcome.html`): "LiveViews are processes that
receive events, update their state, and render updates to a page as diffs"; "Every LiveView is
first rendered statically as part of a regular HTTP request"; then "A persistent connection is
then established"; `mount`, `render/1`, `handle_*`; "LiveView then computes diffs and sends
them to the client"; "The LiveView programming model is declarative… events in LiveView are
regular messages which may cause changes to the state."

## 2. High-ROI pieces

- **ExDoc's uniform docs for every package.** Every library on hex.pm, from Elixir itself to a
  weekend package, gets the same layout, search, version dropdown, autolinks, and source links.
  A reader learns HexDocs once. Cross-package search ("Elixir + libraries") makes the ecosystem
  feel like one manual.
- **Doctests.** The examples in docs are run by `mix test`. Cheap to write, and they make docs
  trustworthy without a separate examples pipeline.
- **Guides live in HexDocs, beside the API.** The Getting Started guide is ExDoc extras in the
  Elixir repo, versioned with the code, with the same search. The language site's "Get started"
  button just goes there. One docs system, not two.
- **Livebook.** A runnable, diffable notebook format (`.livemd`) plus a one-click "Run in
  Livebook" badge. It is how ML libraries (Nx, Bumblebee) teach, and it doubles as the
  tutorial format for ExDoc. It is the Elixir answer to Go's playground, but local and richer.
- **LLM/agent-ready output by default.** Every ExDoc site has "Copy Markdown" per page, an
  `llms.txt`, Markdown output, and EPUB. Zero work for package authors.
- **Release blog posts as explainers.** Each release post explains the main feature with code;
  the "Internals" category explains the type system as it is built. That is research progress
  told well.
- **Phoenix's three-command install and generators** (`mix phx.new`, `mix phx.gen.auth`). The
  shortest path from nothing to a running app is on the homepage.

## 3. Low-value or missing

- **Logo strips, "most loved" badges, Stewards, Use-Elixir-for tabs** on both homepages:
  adoption marketing; much of the Elixir homepage is about other projects.
- **The learning page is a list of paid books and courses**; little curation beyond order.
- **hex.pm's package page is thin** compared to HexDocs: Readme often "Loading", download
  charts, owners. The interesting parts (advisories, audit "Activity") are one-line links.
- **Phoenix's homepage feature grid** ("Docker Ready", "GraphQL") lists checkboxes.
- **No in-browser runner.** Livebook needs a local install or a server; there is no zero-install
  try-it on elixir-lang.org.
- **Docs for a version** are split: elixir-lang.org/docs lists versions, HexDocs has its own
  version dropdown. Two version switchers.

## 4. For Cairn: cut / keep / add

**Keep**

- **`cairn doc` and `/docs/api/`.** Cairn already made Elixir's choice: docs generated from code
  (docs/doc.md: "Cairn's rustdoc: a package's docs generated from its code, never written by
  hand"), with doc tests, a claims page and a summary line. Keep, and make it ExDoc-uniform
  (below).
- **`/packages/` with per-version claim ledgers.** hex.pm has nothing like "What changed in
  0.2.0: cairn^213 retired, cairn^225 new". Keep; it is Cairn's differentiator.
- **`/milestones/` as the release-post channel.** Matches Elixir's Releases posts. Keep.

**Cut or merge**

- **Two docs systems.** Cairn has hand-written `/docs/` (bongo, `site/web/content/docs/`) and
  generated `/docs/api/` with different chrome (the API page has its own header "Cairn / Cairn
  docs Claims", the guides a "Contents" sidebar). Elixir's guides *are* ExDoc extras. Merge:
  have `cairn doc` render the guide chapters (`docs/guide/*.md`) as extras so guides and API
  share one sidebar, one search and one version. Then `/docs/` stops being a separate site
  section to maintain.
- **"Maps" in the top nav** pointing at `/docs/evidence/`. Fold maps into each package's docs
  (ExDoc-style: a "Map" tab next to "Modules" and "Claims") and drop the nav entry.
- **`/docs/examples/*` prose pages** (counter, basics, todo, yap) that walk through source. With
  guides as doc extras, examples become packages with their own generated docs and maps; the
  hand-written walkthroughs duplicate both.
- **The animated scene** on the homepage. Elixir and Phoenix both lead with a code sample and
  its output in the first screen. Cairn's `^2` Reset walkthrough should be the hero.

**Add**

- **Uniform docs for every registry package, hosted by the registry.** Today `/packages/cairn/`
  links "Docs for 0.2.0", but `cairn_json` has a docs link that depends on what was built.
  HexDocs's lesson: the registry runs the doc generator for every version, every package gets
  the same layout, and search spans "Cairn + packages". docs/cli.md already says "Docs aren't
  uploaded"; the consequence is that the registry must build them, uniformly.
- **Copy Markdown, `llms.txt` and a Markdown twin of every page.** `/llms.txt` 404s today. Cairn
  is built largely by agents; claims with ids are exactly the kind of text an agent should
  read. Emit `llms.txt` listing claims by id, and a `.md` for each docs and map page.
- **A claim cheatsheet** (ExDoc's `.cheatmd`): one dense page with every claim kind, the fields
  of `move`, the evidence levels and the `cairn` commands. Cheaper than the single-page
  reference and immediately useful.
- **Autolinked ids everywhere.** ExDoc links anything in backticks to its definition. Cairn
  should do the same for `^N` / `pkg^N` in every doc, milestone post, release note and GitHub
  issue rendering: `cairn^213` should always be a link to its claim, its map row and its ledger
  history. That turns durable ids into the site's navigation.
- **A notebook / "Run in" story.** A `.livemd`-like format for Cairn would be a Markdown file
  that interleaves prose with moves by id and frames: "press ^1 three times; the frame is …;
  ^4 holds". Run locally by `cairn` against the real host, rendered statically on the site with
  the captured frames. That is both a tutorial format and a reproducible bug report.

## 5. Ideas for the language and tooling

- **Doctests over moves.** Elixir's `iex>` doctest runs an expression and compares the printed
  result. Cairn's doc tests (docs/doc.md, "Doc tests") could take a move sequence and assert the
  claims and a frame snapshot, rendered in the docs as a little filmstrip. docs/doc.md.
- **LiveView's model is Cairn's model, over a network.** State in a process, events as
  messages, `render` from assigns, diffs to a thin client that only paints. Cairn: state in
  Lean, events as bytes, `view`/`layout` to a frame, Swift/Metal only paints. LiveView proves
  the thin-client split scales to production and to many surfaces; its "first rendered
  statically as part of a regular HTTP request" is the same as Cairn's headless capture for
  maps. Worth a sentence in docs/architecture.md citing it, and a design note for M7 ("live
  updates over a websocket", docs/roadmap.md): the host could be remote.
- **LiveView diffs.** LiveView sends only changed dynamic parts of a template. Cairn encodes a
  whole frame each step (docs/frame.md). If frames get large (Bluesky timelines, M4), a
  static/dynamic split of the view with diffed frames is the proven path. docs/frame.md,
  docs/runtime.md.
- **Generators** (`mix phx.new`, `mix phx.gen.auth`): Cairn has `cairn new pairs --bin`.
  Generators that emit *claims with ids already allocated* (e.g. `cairn gen list` producing a
  keyed list with add/remove/reorder moves, their proofs and a flow) would make claims the
  default, not the extra. docs/cli.md.
- **One formatter, built in.** Elixir ships `mix format`; HEEx has "Built-in Formatting". Same
  recommendation as Go: a canonical formatter for claim blocks. docs/cli.md.
- **hex.pm's Activity log and Advisories.** A package's audit log (who published, retired,
  transferred) and advisories against versions. For Cairn: an append-only ledger per package on
  the registry, and an advisory kind that marks a claim as known-false in a version range.
  docs/package.md.
- **Gradual typing announced with a 15-month plan** ("Type inference of all constructs and the
  next 15 months"). Elixir publishes a long research arc as a dated plan and then posts
  Internals as it lands. docs/roadmap.md already has M1–M7; publishing it on the site as a page
  (not only in the repo) with status per milestone would do the same job.
