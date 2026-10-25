---
title: "Elm's website, guide, package site and Ellie, read for Cairn's site"
urls:
  - https://elm-lang.org/
  - https://elm-lang.org/examples
  - https://elm-lang.org/docs
  - https://guide.elm-lang.org/
  - https://guide.elm-lang.org/architecture/
  - https://package.elm-lang.org/
  - https://package.elm-lang.org/help/documentation-format
  - https://package.elm-lang.org/help/design-guidelines
  - https://elm-lang.org/news/compiler-errors-for-humans
  - https://elm-lang.org/news/compilers-as-assistants
  - https://elm-lang.org/news/the-syntax-cliff
  - https://ellie-app.com/
  - https://github.com/elm/elm-lang.org (site source, read for exact copy)
date: 2026-10-25
relevance: 5
---

# Elm: the site, the guide, the packages

elm-lang.org and package.elm-lang.org are Elm apps that render client-side, so a plain fetch
returns an empty shell. The copy below was read from the site's source
([elm/elm-lang.org](https://github.com/elm/elm-lang.org), `pages/*.elm`) and
[elm/package.elm-lang.org](https://github.com/elm/package.elm-lang.org) (`assets/help/*.md`), and
the guide was fetched directly. Elm matters most of the three subjects: Cairn's app model *is* the
Elm Architecture (see [../../mvu-semantics/README.md](../../mvu-semantics/README.md)).

## 1. What the site and docs contain

**Top nav** (`pages/home.elm`, `toplevel`): Examples, Docs, Community, News. Footer columns:
Quick Links (Install, Packages, Guide, News), Beginners (Guide, Examples, Try online, Syntax,
From JavaScript?, FAQ, Advanced Topics), Community (News, Slack, Discourse, Twitter, Meetup, Code
of Conduct, Sharing code), Contributing (Design Guidelines, Style Guide, Writing Documentation),
and "We make everything by hand. Compiler, website, docs, blog, and everything in between."

**Homepage**, in order:

1. Hero: an interactive tangram logo, "A delightful language for reliable web applications.",
   two buttons, **Playground** (`/try`) and **Guide**, and "or download the installer."
2. A one-line summary used as the meta description: "A delightful language with friendly error
   messages, great performance, small assets, and no runtime exceptions."
3. Feature rows, each with a *concrete artifact* beside the prose:
   - **No Runtime Exceptions**: a real compiler error ("The 1st argument to `drop` is not what I
     expect … Hint: Use Maybe.withDefault"), and the NoRedInk claim: "300k+ lines later, they
     still have not had to scramble to fix a confusing runtime exception in production."
   - **Fearless refactoring**, with a quote: "you just follow the compiler errors and come out
     the other end with a working app."
   - **Understand anyone's code**: "Including your own, six months later. All Elm programs are
     written in the same pattern", next to the four signatures `init`, `update`,
     `subscriptions`, `view`.
   - **Fast and friendly feedback**: "Enjoy Elm's famously helpful error messages."
   - **Great Performance**: benchmark charts ("Benchmark Times on Chrome 52").
   - **Enforced Semantic Versioning**: "Elm detects all API changes automatically thanks to its
     type system. We use that information to guarantee that every single Elm package follows
     semantic versioning precisely. No surprises in PATCH releases." Beside it, real `elm diff`
     output showing a MAJOR change with the changed signatures.
   - **Small Assets** (`--optimize`), **JavaScript Interop** ("Try it for something small. See if
     you like it.").
4. A carousel of a dozen short user quotes with names and employers.

**/examples** (`pages/examples.elm`): about 30 programs grouped HTML, User Input, Random, HTTP,
Time, Files, WebGL, Playground. Every one opens in the online editor (`/examples/<name>`), code
left, running result right, compiled in the browser session; the page ends "Read through The
Official Guide to learn the basics of Elm."

**/docs** is a short page: "The best place to start is the official guide … the next place to
look for documentation is on the packages you are using", two big buttons (Official Guide,
Package Docs), then a list: Install, FAQ (community-hosted), Syntax, Syntax vs JS, Style Guide,
Package Design, Writing Documentation, Advanced Topics.

**The guide** (guide.elm-lang.org, a GitBook): Introduction → Core Language → **The Elm
Architecture** (Buttons, Text Fields, Forms) → Types → Error Handling → Commands and
Subscriptions (HTTP, JSON, Random, Time) → Installation → JavaScript Interop → Web Apps →
Optimization → Next Steps → Appendix. Installation comes *seventh*: you are expected to learn in
the online editor first. The architecture chapter is three sentences of theory ("Model — the
state of your application; View — a way to turn your state into HTML; Update — a way to update
your state based on messages") and then runnable examples, with "This editor shows hints in the
top left corner … Be sure to try out the hints."

**package.elm-lang.org**: search over all packages; each package page has README, module list,
per-module docs with every exposed value's type and doc comment, and a version list. Two help
pages carry the ecosystem's norms: *Documentation Format* ("Modules that are missing
documentation cannot be uploaded to the catalog"; "For publicly exposed functions, type
annotations and comments are required, and examples are best practice") and *Design Guidelines*
("Design for a concrete use case", "Abstraction is a tool, not a design goal", "Keep tags and
record constructors secret").

**/news**: long-form release posts by Evan Czaplicki, several of which are essays about tooling
UX: "Compiler Errors for Humans" (0.15.1, 2015), "Compilers as Assistants" (0.16), "The Syntax
Cliff" (0.19.1, 2019), and in 2026 "The Road to Elm 1.0" (0.19.2, 2026-07-06) and "Another step
towards Elm 1.0" (0.19.3, 2026-10-05).

**Ellie** ([ellie-app.com](https://ellie-app.com)), linked from Community → "Sharing code":
a third-party live editor with packages, compile errors, an HTML pane and short share links
(`ellie-app.com/<id>`). It is how Elm people ask questions: paste a link, not a snippet. Its
author argued against multi-file support to keep shares minimal
([dev.to post](https://dev.to/lukewestby/why-ellie-will-not-support-multiple-files-39i)).

## 2. High-ROI pieces

- **The online editor as the first step.** The hero's primary button is Playground, the guide
  defers installation to chapter 7, and every example is runnable. Time from landing to "I
  changed something and saw it" is seconds. This is the single largest adoption lever on the
  site.
- **Error messages as a marketed feature, shown not described.** The homepage displays an actual
  error; the news posts treat error UX as design work: "The error shows the code exactly as you
  wrote it", "Every message has a useful hint", "color is a huge usability improvement", and
  "Compilers should be assistants, not adversaries." The Syntax Cliff asks "how many people do
  not make it past these syntax errors?" Elm's reputation ("famously helpful", linked to a John
  Carmack tweet) comes from this.
- **One architecture, shown as four type signatures.** "Understand anyone's code" sells
  uniformity with `init/update/subscriptions/view` on screen. Readers grasp the whole app model
  from one box.
- **Enforced semver, with the tool output on the homepage.** `elm diff` turns a promise into a
  checkable artifact. It also makes the package site trustworthy without curation.
- **Docs required to publish, plus a short design guide.** Uniform package docs follow from a
  hard rule at upload time, not from exhortation.
- **Examples grouped by capability** (HTTP, Time, Files…) rather than by size, so a reader
  looking for "how do I do X" finds it.

## 3. Low-value or missing

- **Stale performance claims.** "Benchmark Times on Chrome 52" is years old; it reads as neglect
  more than evidence.
- **News as the only changelog.** Release notes are essays; there is no compact "what changed in
  0.19.x" list on the site, and between 2019 and 2026 the page did not move, which outsiders read
  as "Elm is dead". A dated, terse release list would have carried more signal.
- **FAQ is off-site and community-maintained** (faq.elm-community.org), so design questions ("why
  no typeclasses?") are answered by others, inconsistently.
- **No guidance on testing or tooling** beyond the compiler: elm-test, elm-format, elm-review are
  community tools the site barely mentions.
- **Client-rendered docs**: the package site and help pages are invisible to non-JS fetchers and
  tools; agents and search see an empty shell.
- The Community page's Slack/Twitter/Meetup links are low-value for a reader deciding whether to
  try the language.

## 4. For Cairn: cut / keep / add

Cairn's site today: homepage (animated pixel-art night scene, "Latest milestone" panel, "The
idea", the frame diagram, "Not a layer on top", "What a claim is" with the Reset move annotated,
"Ids are the contract", "Six kinds", "How sure we are"); top nav Milestones, Docs, Packages,
Maps, GitHub; `/docs/` with Guides, Example apps, Reference, Internals, Evidence; `/docs/api/`;
`/map/<app>/`; `/packages/`; `/feed.xml`.

**Keep**

- "What a claim is" with the annotated `move ^2 reset` is Cairn's equivalent of Elm's four
  signatures: the whole model in one box. It is the strongest thing on the homepage. Move it up,
  directly under the one-line pitch.
- The frame diagram (Swift → Lean → Metal, "trusted / proved / trusted") does what Elm's
  "Understand anyone's code" row does. Keep.
- `/milestones/` as the long-form log is Elm's /news done better (dated, with video). Keep, but
  it should not be the homepage's main panel (below).

**Cut or demote**

- **The "Latest milestone" panel as the homepage's second thing.** Elm's homepage never leads with
  news; it leads with a primary action. Cairn's leads with a progress report. Move it below the
  claim example, as one line.
- **"Errors (to do)" in the Reference sidebar.** A placeholder in a nav is a broken promise; Elm
  shows its errors on the homepage. Hide it until #99 lands.
- **Stale facts.** `/docs/guide/first-app/` still says "The Cairn repository. It isn't public
  yet." It is public. This is the Chrome-52-benchmark problem in miniature.
- **"Packages" in the top nav** while the registry has 2 libraries and 0 apps. Elm's package site
  earns top billing from thousands of packages with enforced semver. Link it from Docs →
  Reference until there is something to browse (see the Roc and Dafny notes for the same call).
- **"Internals → Profiling against a reference"** belongs in the repo's `docs/`, not the user
  docs' sidebar.

**Add**

- **A primary action in the hero.** Elm's is "Playground". Cairn cannot run in a browser (macOS
  host, Metal), so the zero-install artifact Cairn *does* have is the map. Make the hero button
  "See every claim TodoMVC makes" → `/map/todo/`, and the second button "Build your first app" →
  `/docs/guide/first-app/`. Secondary: a downloadable signed Counter/TodoMVC `.app` for people
  with a Mac.
- **Show an error on the homepage.** One real failure, verbatim: delete a move's proof, or retire
  an id and bring it back, and show what `make check`/`cairn build` prints. That demonstrates "the
  app doesn't compile without the proof" far better than the sentence saying so.
- **A Cairn diff, shown like `elm diff`.** The claim ledger already knows when a claim is added,
  retired or changes meaning (docs/claims.md "Retiring needs a major version"). Put a real
  `claims.lock` diff between `cairn` v0.1.3 and v0.2.0 on `/packages/cairn/` and on the homepage.
- **An examples page grouped by capability**, not by app: "a button", "a text field", "a keyed
  list", "a timer", "a request", "an image", each a small runnable example with its map. Today
  Example apps lists Counter, Basics, TodoMVC, Yap, which are sized for milestones, not lookup.
- **A one-page "Design guidelines for claims"** like Elm's package design guide: write `does`
  and `sees` in the person's words, one move per control, frame conditions first, keep ids
  stable. Today this lives scattered through `docs/claims.md`.

## 5. Ideas for the language and tooling

- **Enforced semver from the claim ledger** (docs/package.md, docs/cli.md). Elm computes the
  version bump from API types. Cairn can compute it from two things: the Lean API (as Elm does)
  and the claim ledger (a retired claim or a changed statement is a MAJOR change for the people
  who rely on it). `cairn publish` refusing a version that under-bumps is the Elm move. This is
  the parked "registry-assigned semver" idea; Elm is the existence proof that users love it.
  A `cairn diff <pkg> <v1> <v2>` command is the first step.
- **Docs required to publish** (docs/cli.md "Publishing", docs/doc.md). Refuse `cairn publish`
  when a public declaration or a claim lacks a doc string (`does`/`sees` already exist for
  claims; extend to public Lean API). Elm shows this keeps a whole ecosystem's docs uniform.
- **Error messages as product** (docs/claims.md "What the build checks", issue #99). Adopt Elm's
  rules: show the user's code as written with the line, name the claim by id and title, give one
  concrete hint, link to a stable error page. Claim-command errors are the first thing a new
  Cairn author hits; they are Cairn's syntax cliff.
- **Subscriptions as data** (docs/effects.md): Elm's `subscriptions : Model -> Sub Msg` is what
  M2's subscriptions copy. Elm's guide teaches it with HTTP, JSON, Random and Time in one chapter;
  Cairn's guide "Effects and the host" could follow the same four-example shape.
- **A shareable minimal reproduction**, Ellie's role. Cairn can't run in a browser, but a
  `cairn new --repro` that makes a one-file app, plus maps that render without the host
  (Lean-only claims, no screenshots), would let people share a link to a failing claim. Park in
  docs/roadmap.md "alongside" work.
