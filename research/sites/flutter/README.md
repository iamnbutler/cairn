---
title: "Flutter: flutter.dev, docs.flutter.dev, pub.dev scores, DartPad, the widget catalog, showcase"
urls:
  - https://flutter.dev/
  - https://flutter.dev/showcase
  - https://docs.flutter.dev/
  - https://docs.flutter.dev/llms.txt
  - https://docs.flutter.dev/ui/widgets
  - https://docs.flutter.dev/learn/pathway
  - https://docs.flutter.dev/tools/hot-reload
  - https://docs.flutter.dev/tools/widget-previewer
  - https://docs.flutter.dev/tools/devtools/inspector
  - https://docs.flutter.dev/ai/get-started
  - https://docs.flutter.dev/packages-and-plugins/favorites
  - https://api.flutter.dev/flutter/widgets/Row-class.html
  - https://pub.dev/help/scoring
  - https://pub.dev/packages/provider/score
  - https://dart.dev/tools/dartpad
date: 2026-10-25
relevance: 5
---

# Flutter

Flutter is the UI framework whose model is closest to Cairn's: it paints every pixel itself
rather than wrapping platform widgets, owns layout (one-pass constraints, see
research/constraint-layout/), and mirrors its own tree to accessibility. Its web presence is
large and Google-run: a marketing site (flutter.dev), a docs site (docs.flutter.dev), API docs
(api.flutter.dev), a package registry with automated scoring (pub.dev), and an in-browser editor
(DartPad). Pages fetched 2026-10-24; the docs report Flutter 3.47.

## 1. What the site and docs contain

### flutter.dev

- **Top nav:** Development (Mobile, iOS, Web, Desktop, Embedded, AI, Google integrations, Games,
  Monetization), Ecosystem (Community, Culture, Packages → pub.dev, Events, Consultants), Why
  Flutter, **Showcase**, Blog, Docs (Overview, What's new, Editor support, **Hot reload**,
  Profiling, Install, App architecture, Learning, DevTools), search, **Get started**.
- **Homepage, in order:** "Build for any screen." / "Flutter transforms the development process."
  → Fast / Productive / Flexible cards, **each with "Try it in DartPad"** ("Productive: Hot
  Reload, with state preserved") → reach every screen → workflow and tooling → "Trusted by many" →
  Google services → a Google Pay case study → a 19-company logo wall → community → "Flutter is
  powered by Dart" → news carousel → newsletter → Install / Read the docs.
- **/showcase:** Flutter at Google (NotebookLM, Google Pay, Earth, Ads, Classroom), a filterable
  grid of case studies each framed by one number (Whirlpool "50% reduction in development costs",
  KQED "55% increase in feature cadence"), developer stories, runnable demo apps (Wonderous,
  Flokk, Folio), logo wall, one quoted testimonial (Alibaba: feature time "from 1 month down to 2
  weeks").

### docs.flutter.dev

- **Tabs above the sidebar:** Guides, Learn (/learn/pathway), AI, Reference (api.flutter.dev).
- **Homepage cards:** Install Flutter, **Widget catalog**, API docs, Learning resources, Videos,
  Develop with AI. Then "New to Flutter?" with "Understanding constraints" and the **"Flutter for
  …" guides** (Android, SwiftUI, UIKit, React Native, Xamarin.Forms developers).
- **Sidebar IA:** Get started (Quick start, Custom setup, Learn Flutter) → User interface (widget
  catalog, layout, adaptive design, theming, interactivity, assets, navigation, animation,
  accessibility, i18n) → Beyond UI (data and backend, app architecture with a case study,
  platform integration, packages and plugins, testing and debugging, performance, deployment, add
  to an existing app) → AI → Resources (tools and editors incl. DevTools, **Widget Previewer**,
  Property Editor; Flutter concepts: architectural overview, "Inside Flutter", constraints, build
  modes, hot reload; "Flutter for" guides; release notes, **breaking changes, compatibility
  policy**; install management; glossary). Cookbook recipes are embedded by topic, not a section.
- **Learning pathway:** install → Dart tutorial (skippable) → the Flutter Getting Started
  tutorial, where you "build three small Flutter apps" across Introduction to Flutter UI, State in
  Flutter apps, Flutter UI 102 → a video series on how Flutter works.
- **Widget catalog:** "Create beautiful apps faster with Flutter's collection of visual,
  structural, platform, and interactive widgets." Design systems (Cupertino, Material, plus
  community `fluent_ui`, `macos_ui`, `yaru`) then 12 base categories (Accessibility, Animation,
  Assets, Async, Basics, Input, Interaction, Layout, Painting, Scrolling, Styling, Text), an A–Z
  widget index, and "100+ short, 1-minute explainer videos" (Widget of the Week).
- **API pages** (Row): summary, diagrams of layouts *and of the error state*, a "Troubleshooting"
  section ("The row reports this by drawing a yellow and black striped warning box on the edge
  that is overflowing"), a numbered six-step **layout algorithm**, See also, inheritance.
- **llms.txt** (docs.flutter.dev/llms.txt, 17.5 KB): a curated, sectioned link list "to help
  Large Language Models understand the Flutter framework", stating the core principle "everything
  is a widget". flutter.dev/llms.txt 404s.
- **AI page:** an agent plugin with the Dart and Flutter MCP server (`dart mcp-server`: "real-time
  access to analyzer diagnostics, symbol resolution, test runners, and runtime inspection"),
  skills installed with `npx skills add flutter/agent-plugins`, rules ("proactively triggering
  stateful hot reload when editing Flutter widgets"), an a11y agent, and **package skills** that
  pub.dev packages ship themselves.

### pub.dev and DartPad

- **Score page** (provider): 11k likes, **150/160 pub points**, 1.16M downloads. Points in five
  categories with each check and its points: file conventions 30/30 (pubspec, README, CHANGELOG,
  OSI licence), documentation 20/20 ("326 of 351 API elements (92.9%)" documented; has an
  example), platform support 20/20 (6 of 6, WASM-ready), static analysis 40/50 (4 issues, listed
  with file and line), up-to-date dependencies 40/40 (incl. "Compatible with dependency constraint
  lower bounds", checked by `pub downgrade`). Footer: "Analyzed with Pana 0.23.19, Flutter 3.47.7,
  Dart 3.13.5". Tabs: Readme, Changelog, Example, Installing, Versions, Scores.
- pub.dev/help/scoring is candid about downloads: "not a direct measure of how many users a
  package has … should only be regarded as an indicator of popularity." Authors can run `pana`
  locally to preview their score.
- **Flutter Favorite:** a committee-picked badge for packages "you should first consider", with
  criteria (score, licence, tag matches version, verified publisher, usability, runtime
  behaviour, dependencies) and an explicit "This is not a guarantee of quality".
- **DartPad:** in-browser Dart and Flutter (`package:flutter`, `dart:ui`, a fixed list of pub
  packages), samples menu, formatter, autocomplete; "can embed DartPad inside of web pages", which
  dart.dev does for tutorials with exercises.

## 2. High-ROI pieces

1. **"Try it in DartPad" from the homepage.** A runnable Flutter app one click from the marketing
   copy, no install. The single strongest adoption lever on the site.
2. **The widget catalog.** A visual, categorised answer to "what can I build with?" plus 1-minute
   videos per widget. Every UI framework reader asks this before reading a guide.
3. **pub.dev's score page.** Quality is computed, broken into named checks with their points and
   the exact toolchain versions used, and reproducible locally with pana. Authors chase points, so
   the score shapes the ecosystem (docs, examples, lower-bound testing) without any policing.
4. **"Flutter for SwiftUI/UIKit/React Native developers".** Meets readers where they are, mapping
   concepts they know to Flutter's.
5. **API pages that explain failure.** Row's page draws the overflow error and walks through the
   fix. Diagnostics docs are what people land on from search.
6. **Hot reload as a headline feature**, with a precise page on its limits (enum↔class,
   `initState`, static initialisers).
7. **Showcase with numbers.** Each case study leads with one outcome. Persuasive to the
   decision-maker, not the developer.
8. **AI tooling that touches the running app.** The MCP server exposes analyzer diagnostics and
   runtime inspection, and packages ship their own skills.

## 3. Low-value or missing

- **The marketing homepage is long and generic.** "Build for any screen", Google services,
  newsletter, news carousel: a lot of scroll before anything concrete; the page "contains no
  statistics or metrics" despite the showcase having them.
- **Logo walls appear on three pages** (home, showcase, ecosystem). Repetition with no content.
- **Download counts** are admitted by pub.dev itself to be a weak signal; likes are a vanity
  metric.
- **The docs IA is enormous** (11 top sidebar groups, platform-specific sections for six
  platforms). Finding "how layout works" needs the separate "Understanding constraints" link.
- **API page samples are static** for Row even though DartPad can embed; the interactive version
  lives elsewhere.
- **Flutter Favorite** depends on a seven-person committee and an email address; hard to scale,
  and it duplicates what the score already says.

## 4. For Cairn: cut / keep / add

**Keep**

- **/packages/ with per-version claim ledgers.** It is already a stronger evidence story than
  pub.dev's (pub points check hygiene; Cairn's ledger checks behaviour). Keep it, but present it
  the way pub.dev presents its score (below).
- **/map/<app>/'s evidence summary** ("proved 21/21 … seen 19/20", then "Gaps 3, failures
  first"). This is exactly pub.dev's score layout: totals, then each failing check with a reason.
  It is the most Flutter-like and most valuable generated page Cairn has.
- **/docs/reference/errors/.** Flutter's Row troubleshooting shows that error pages are worth it;
  fill it from real `cairn` and Lean error output with the failing state drawn.

**Cut or demote**

- **The animated night scene** as the homepage's first screen. Flutter, the most visual
  framework there is, leads with "Try it in DartPad", not decoration. Cairn's scene is charming but
  says nothing about claims; shrink it to a header band or the 404 page and lead with the
  annotated `move` sample and a captured frame of a real app.
- **"Maps" as a top-nav item.** Flutter has no top-level "evidence" area; evidence lives on the
  package page. Fold maps into each example (/docs/examples/todo/ embeds or links /map/todo/) and
  each package version.
- **Milestone posts as the main "what's new" surface in the docs.** Flutter separates "What's
  new" and "breaking changes" from blog posts. Cairn's /docs/reference/releases/ should be the
  canonical place; /milestones/ stays as the narrative log, not the changelog.

**Add**

- **A claim/control catalog.** Cairn's equivalent of the widget catalog: every view node and
  control in `Cairn` (box, text, field, button, image, menu item, panel) with a captured frame of
  it, the moves it can carry, and the claims Cairn proves about it (presence, pressability). The
  API reference has "43 claims (43 assumed)" but no visual catalog. Put it at /docs/reference/
  catalog/, generated like the maps.
- **A pub.dev-style score block on each package version page:** named checks with pass/fail
  ("every move has a proof", "standard axioms only", "claims.lock has no missing ids", "fuzzed
  N sequences", "conformance N walks", "every public declaration documented", "has an example
  app"), plus "Checked with Lean 4.x, cairn 0.2.0" and a command to reproduce locally. Today
  /packages/ shows "108 active 3 retired 44 moved", which counts claims but doesn't judge them.
- **"Cairn for SwiftUI developers" and "Cairn for Elm developers".** Two concept maps (View →
  `view`, `@State` → `State`, `Button(action:)` → a control ref to a `move`; Elm's `update` →
  `update` with effects as data). Most of Cairn's likely readers come from one of those.
- **llms.txt** with a curated link list the way Flutter does it, stating the core principle in
  one line ("every action is a move with an id and a proof").
- **Videos per concept, short.** /milestones/ already has videos; a 30-second "what a claim is"
  clip on the homepage would do more than the scene.

## 5. Ideas for the framework itself

- **Hot reload with state preserved.** Flutter reloads code and keeps state, and documents
  exactly when that's unsound. Cairn's state is plain data and the host is separate from Lean, so
  reloading the Lean library and re-running `view` on the old `State` is plausible whenever
  `State`'s type is unchanged (the analogue of Flutter's enum↔class limit). A `cairn run --watch`
  would touch docs/cli.md and docs/host.md ("Running", "ABI").
- **Widget Previewer → claim previews.** `@Preview(name:, group:, brightness:)` on a function
  returning a widget, rendered in the IDE or `flutter widget-preview start` in a browser, with
  search by name and group. For Cairn: preview a `place` at named states, and preview a *flow*
  (the frames along its witness path). The map's capture already does this; expose it while
  editing. Touches docs/cli.md and docs/doc.md.
- **Inspector's "Select Widget Mode".** Click the running app and the tree scrolls to that node.
  Cairn's version: click a control and get its claim id, the move's `does`/`sees`, and its
  evidence, via the debug socket. That would make "every action has an id" tangible in the first
  minute. Touches docs/host.md (debug socket) and the map's claim pages.
- **Debug paint toggles** (guidelines, baselines, highlight repaints). Layout is in Lean with
  integer boxes; drawing the `Laid` boxes and hit regions over the frame is cheap and doubles as
  a visual check of `hitTest`. Touches docs/host.md and docs/layout.md.
- **pana and lower-bound testing.** pub.dev awards 20 points for "Compatible with dependency
  constraint lower bounds" via `pub downgrade`. Cairn packages depend on tagged Cairn versions
  (docs/package.md); the registry should build each version against the lowest Cairn it claims
  to support, and run a local `cairn score`. Touches docs/package.md and docs/cli.md.
- **Package skills.** pub.dev packages ship their own agent skills. Cairn packages could ship
  a short agent note (how to use the package's moves and what it proves), served by the registry
  next to the ledger. Touches docs/package.md.
- **An MCP server with runtime inspection.** Flutter's exposes diagnostics and the live app.
  Cairn's debug socket plus the claim ledger would let an agent ask "which claims does this
  frame show" and "is ^219 seen". Touches docs/cli.md and docs/host.md.
- **A compatibility policy and breaking-changes page.** Flutter has both. Cairn's id contract
  (never renumber, retire instead) is already a compatibility policy for claims; write the
  matching one for the API and ABI. Touches docs/roadmap.md and docs/package.md.
