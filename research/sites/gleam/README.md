---
title: "Gleam's website and docs: gleam.run, the language tour, the playground, packages.gleam.run, HexDocs"
urls:
  - https://gleam.run/
  - https://gleam.run/documentation/
  - https://gleam.run/install/
  - https://gleam.run/install/macos/gleam/homebrew
  - https://gleam.run/writing-gleam/
  - https://gleam.run/documentation/command-line-reference/
  - https://gleam.run/news/
  - https://gleam.run/news/gleam-doesnt-compile-to-erlang-source-anymore/
  - https://gleam.run/roadmap/
  - https://gleam.run/case-studies/
  - https://tour.gleam.run/
  - https://playground.gleam.run/
  - https://packages.gleam.run/
  - https://gleam-stdlib.hexdocs.pm/gleam/list.html
date: 2026-10-25
relevance: 4
---

# Gleam's site and docs

Gleam is a small language run by a small team, which makes it the closest in scale to Cairn of
the three. Its site does a few things very well: one homepage that reads top to bottom and ends
in the tour, a tour that runs entirely in the browser, one binary that is the compiler, build
tool, formatter, language server and package manager, and release posts that are the changelog.
It leans on Hex (Erlang's registry) rather than running its own.

## 1. What the site and docs contain

**gleam.run** (fetched 2026-10-24).

- Top nav: News, Community, Sponsor, Packages (packages.gleam.run), Docs, Install. Lucy the star
  mascot by the wordmark.
- Hero: "Gleam is a friendly language for building type-safe systems that scale!", a **Try
  Gleam** button (the tour) and a five-line `hello, friend!` sample.
- Then one section per reason, each with a short sample:
  - "Reliable and scalable": the BEAM, with a process sending "Hello, Joe!".
  - "Ready when you are": "Gleam comes with compiler, build tool, formatter, editor
    integrations, and package manager all built in", shown as `gleam add gleam_json` then
    `gleam test` passing.
  - "Here to help": "No null values, no exceptions, clear error messages, and a practical type
    system", shown as a real compiler error:
    ```
    error: Unknown record field
      ┌─ ./src/app.gleam:8:16
      │
    8 │ user.alias
      │     ^^^^^^ Did you mean `name`?
    The value being accessed has this type:
        User
    It has these fields:
        .name
    ```
  - "Multilingual": Erlang/Elixir interop, JavaScript output, generated TypeScript definitions.
  - "Friendly 💜": community values and code of conduct.
  - "Lovely people": sponsor avatars.
  - "You're still here?": "Let's go!" to the tour. Then a newsletter signup.

**/documentation/**: Learning (tour, Writing Gleam, Installing), unofficial courses (Exercism,
CodeCrafters), references (language overview = the tour on one page, command line, language
server, `gleam.toml`, compatibility, package index, stdlib on HexDocs, Awesome Gleam), guides
(conventions and anti-patterns, externals), security (source bill of materials), six
cheatsheets ("Gleam for Elixir / Elm / Erlang / PHP / Python / Rust users"), deployment (Linux,
Fly.io), FAQ, branding.

**/install/**: pick an OS, then a method. macOS offers Homebrew, asdf, MacPorts, Nix, a
precompiled binary from GitHub, or source. The Homebrew page is one line, `brew install gleam`,
then "Continue to install editor support".

**tour.gleam.run**: editor above, output below; "To evaluate Gleam code the tour compiles Gleam
to JavaScript and runs it, all entirely within your browser window", recompiling as you type.
Back/Next, a contents page, and the whole tour on one page (`/everything/`, which the docs
index reuses as the language reference).

**playground.gleam.run**: editor plus tabs **Output**, **Compiled Erlang**, **Compiled
JavaScript**, and **Share code**.

**/writing-gleam/**: one walk-through (`gleam new vars`, `gleam add envoy argv`, `gleam run`,
`gleam test`, `gleam export escript`). "Gleam's build tool is built into the `gleam` program you
installed earlier."

**Command line reference**: `new`, `add`, `build`, `check`, `run`, `test`, `format`, `fix`,
`lsp`, `deps list|download|outdated|update|tree`, `docs build|publish|remove`,
`export escript|erlang-shipment|hex-tarball|package-interface|…`, `publish` (`--replace` within an
hour), `hex retire|unretire|revert|owner|authenticate`.

**packages.gleam.run**: "1716 packages are available!" Each row: `name@version`, a one-line
description, "Updated X ago", and buttons to Docs (HexDocs), Repo and Hex. It is an index over
Hex, not a registry.

**HexDocs output** (gleam_stdlib v1.0.5, `gleam/list`): sidebar with README, links (Website,
Sponsor, Repository, Hex), modules, and every type and value; each function has its signature,
prose, an Examples section written as `assert` lines, and a "View Source" link to the tagged
line on GitHub.

**/news/**: one post per minor release, titled by the headline change with the version as the
subtitle: "Gleam doesn't compile to Erlang source anymore" (v1.19.0, 5 Oct 2026), "A field day
for Gleam's language server" (v1.18.0), "Single file Gleam BEAM programs with escript"
(v1.17.0), "JavaScript source maps" (v1.16.0). Each post is long, first-person, with
before/after snippets, contributors credited inline, and a sponsor ask at the end.

**/roadmap/**: In progress (dependency conflict hints, **semantic versioning checks for package
releases**, Windows production support, warnings for vulnerable Hex packages), planned and
research items, and a version history from v1.1.

**/case-studies/**: two (Strand, Uncover), each a long write-up.

## 2. High-ROI pieces

1. **The tour, in the browser, no install.** The homepage's two main buttons go there. It
   compiles to JS client-side, so it costs nothing to host and works offline once loaded. It is
   also the reference (`/everything/`).
2. **One binary.** "compiler, build tool, formatter, editor integrations, and package manager
   all built in." The install is `brew install gleam`; every workflow on /writing-gleam/ is a
   `gleam` subcommand. Nothing to choose, nothing to configure.
3. **Errors as a selling point, shown, not described.** The homepage puts a real error (file,
   line, caret, "Did you mean `name`?", the type and its fields) where other sites put a feature
   list. It turns "friendly" from an adjective into evidence.
4. **The playground shows the compiled output.** "Compiled Erlang" and "Compiled JavaScript"
   tabs let people see what their code becomes. For a language that compiles to other
   languages, this answers "what does it actually do?" directly.
5. **Release posts as the changelog.** One per minor version, titled by what changed, with
   examples. They are the most-read pages after the tour and keep the project visibly alive.
6. **Cheatsheets by origin language.** "Gleam for Elm users", "for Rust users": a newcomer finds
   the one page that maps their existing knowledge.
7. **Doc examples written as `assert`s** on HexDocs: each example is also a statement of what
   the function returns.
8. **A readable homepage that ends in a call to action** ("You're still here?" → "Let's go!").
   Every section is one reason plus one small sample.

## 3. Low-value or missing

- **packages.gleam.run is a long flat list** (510k characters of HTML), newest first, with no
  visible search in the static page. Its value is the Docs/Repo/Hex links; Hex does the rest.
- **No per-version docs selector** on HexDocs pages; the version is a label.
- **Install is a two-level picker** (OS, then six methods) where one line would do for most
  people; the macOS page lists Homebrew first but makes you click to see the command.
- **Case studies**: two in total, linked from the footer. Credibility, not adoption.
- **Sponsorship and merch** take a large share of the homepage and footer; necessary for a
  sponsor-funded project, not useful to a learner.
- **`gleam fix` "currently does nothing"** but is in the reference anyway.

## 4. For Cairn: cut / keep / add

**Cut or shrink**

- **The homepage night scene's share of the page.** Gleam has Lucy, but the mascot is a small
  logo, and the first screen is the tagline, a button and code. Cairn's first screen is the
  animated scene and the latest milestone; the code arrives in "What a claim is", several
  sections down. Keep the scene as a band, but put a claim and its evidence (the Reset button
  sample and its `cairn^N`) on the first screen.
- **/milestones/ as one long page.** It holds three long posts with videos that load late
  ("Loading…" placeholders in a plain fetch). Gleam gives each release its own URL titled by
  what changed. Give each milestone its own page (`/milestones/m2-yap/`), titled by the
  question it answered, and let the index be a list.
- **Docs pages for things that don't exist yet.** /docs/reference/errors/ (a to-do) and the
  "planned commands" table in /docs/reference/cairn-tool/. Gleam lists `gleam fix` as doing
  nothing and it reads as noise. Keep planned work in docs/roadmap.md, not the reference.

**Keep**

- **/packages/ with versions and claim ledgers.** Gleam leans on Hex; Cairn has its own
  registry because the ledger check needs one. That's a real reason, unlike most custom
  registries.
- **The feed.** Gleam's news is its heartbeat; Cairn's milestones and /feed.xml are the same.
- **The `cairn` command as the single tool** (docs/cli.md: `new`, `add`, `build`, `doc`,
  `publish`, `login`). This is already Gleam's shape; finish it.

**Add**

1. **A "Try it" path without a Mac build.** Gleam's tour is the highest-value thing on its site
   and Cairn has nothing equivalent; first-app needs macOS 27, Xcode, elan, bun and a long first
   build. The cheapest Cairn version is not a compiler in the browser but **an interactive
   map**: a recorded app (Counter, TodoMVC) rendered from its real frames, where clicking a
   control shows the move's `cairn^N`, its `enabled`/`post`, and its evidence. The frame format
   (docs/frame.md) already carries draw commands and accessibility nodes, so a JS renderer of
   recorded frames is a bounded job.
2. **A real claims error on the homepage.** Gleam shows its compiler error. Cairn's most
   distinctive output is the claims checker refusing something: a move whose `post` isn't proved,
   or `cairn publish` refusing a version that renumbers a claim. Show that message, verbatim, in
   a "Here to help"-style section.
3. **"Cairn for Elm / SwiftUI / React users" cheatsheets.** Cairn is the Elm Architecture in
   Lean with a native host. A page mapping `Model/Msg/update/view` to Cairn's
   `State/Msg/update/view` and to claims would land faster than /docs/guide/ for the people most
   likely to try it.
4. **A one-line install, once a binary exists** (`brew install cairn` or a release download),
   shown on the homepage and /docs/.
5. **A "compiled output" view on maps.** Gleam's playground shows the Erlang and JS it emits.
   Cairn's analogue is the frame: for a step on a map, show the encoded frame's draw list and
   accessibility nodes beside the screenshot. That's what "Lean owns meaning" looks like.

## 5. Ideas for the language and tooling

- **Semantic versioning checks at publish** (Gleam roadmap: "semantic versioning checks for
  package releases"). Cairn's registry already refuses a version that drops or renumbers a
  claim; the parked auto-versioning idea (registry-assigned semver from the ledger diff) is the
  same feature from the claims side. Gleam computes API diffs from `gleam export
  package-interface`; Cairn could combine both (API diff + claim ledger diff) in docs/package.md.
- **`gleam export package-interface` → `cairn export ledger`.** A JSON description of a
  package's code and claims, stable enough for other tools (the site, the registry, agents) to
  read. docs/doc.md's export is close; make it a documented command in docs/cli.md.
- **`hex retire` with a reason, `revert` within 24 h, `publish --replace` within an hour.**
  Cairn's registry needs a story for a bad release; Gleam's is small and concrete
  (docs/package.md).
- **`gleam docs publish` vs registry-built docs.** Gleam has authors publish docs; Rust's docs.rs
  builds them. Cairn's cli.md already chose the latter (#94). Gleam's per-function "View Source"
  pinned to the tag is worth copying either way.
- **Errors with "Did you mean" and the type shown** (issue #99, docs/claims.md). Claims errors
  should show the claim, its id, the nearest existing id or name, and, for an unproved move, the
  goal Lean couldn't close. Gleam's format (file:line, caret, suggestion, context) is the
  template.
- **Doc examples as asserts.** Cairn's doc tests (`make doctest`) can follow HexDocs' style:
  every example a `#guard` that states the result, so the example is its own claim.
- **One tool for everything, including `lsp` and `format`.** Gleam's reference lists `lsp` as a
  subcommand. Cairn leans on Lean's language server, which is right, but `cairn doctor` and
  `cairn run`/`check`/`map` (planned in cairn-tool.md) should land before more reference pages
  do; they are what /writing-gleam/ shows a newcomer in one sitting.
