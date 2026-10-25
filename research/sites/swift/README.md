---
title: "Swift and SwiftUI: swift.org, Swift Package Index, Apple's SwiftUI tutorials"
urls:
  - https://www.swift.org/
  - https://www.swift.org/getting-started/swiftui/
  - https://www.swift.org/packages/
  - https://www.swift.org/swift-evolution/
  - https://swiftpackageindex.com/
  - https://swiftpackageindex.com/apple/swift-argument-parser
  - https://developer.apple.com/tutorials/swiftui
  - https://developer.apple.com/tutorials/develop-in-swift/
date: 2026-10-25
relevance: 4
---

# Swift and SwiftUI

Swift is the closest neighbour Cairn has: Cairn's host is Swift/AppKit, its apps are Mac apps, and
SwiftUI is the declarative UI framework a Cairn user would otherwise reach for. The Swift web
presence is split three ways: the language site (swift.org, run by the open-source project), the
package index (swiftpackageindex.com, community-run, now part of Apple), and the framework
tutorials (developer.apple.com, Apple's DocC-rendered content). Pages fetched 2026-10-24.

## 1. What the site and docs contain

### swift.org

- **Top nav:** Docs (docs.swift.org/latest/documentation/), Community, Packages, Blog,
  **Install (6.4.1)**. The version number is in the nav button itself.
- **Homepage, in order:** hero "Swift is the powerful, flexible, multiplatform programming
  language." / "Fast. Expressive. Safe." with one CTA, Install ("Tools for Linux, macOS, and
  Windows"); a **"Create using Swift" grid** of seven use cases (Cloud services, Command line,
  Embedded, iOS apps, Windows apps, ML & AI, Packages), each linking to a getting-started page;
  then five feature bands (Fast, Expressive, Safe, Interoperable, Adaptable), **each with a real
  code sample** (a vectorised ASCII check, a whole ArgumentParser tool, calling C, using
  `std::string` from C++, Swift MMIO on a microcontroller); then Open Source (GitHub, forums).
- **Footer:** editor setup (Xcode, VS Code, Emacs, Neovim, Cursor, "Other editors" via
  sourcekit-lsp), Swift Evolution, governance, an Atom feed, light/dark/auto toggle.
- **Getting started per use case.** /getting-started/swiftui/ "Build an iOS app with SwiftUI"
  builds one small app (WhyNotTry, a random activity in a coloured circle with a "Try again"
  button) in four sections: "Building a static UI", "Bringing it to life", "Adding some polish",
  "Where now?". About 16 screenshots (including the compiler errors you will hit with optionals and
  `@State`) and ~20 snippets that accumulate into the final file; code is on GitHub.
- **/packages/:** curated category cards (Community Showcase, macros, server, networking, testing,
  logging, databases), "nominated by community members like you" and refreshed monthly, then
  hands off to the Swift Package Index: "There are thousands more packages to browse".
- **/swift-evolution/:** a dashboard of proposals with filters. "Anyone with a good idea can help
  shape the future features and direction of the language." Proposals have durable ids
  (SE-NNNN) and statuses, and every release's notes cite them.

### Swift Package Index

- Homepage: "The place to find Swift packages", "Indexing 12,376 packages", recent additions and
  recent releases with relative timestamps.
- **A package page** (apple/swift-argument-parser): a **compatibility matrix built from real
  builds**: Swift 6.4/6.3/6.2/6.1 × iOS, macOS, visionOS, watchOS, tvOS, Linux, Wasm, Android, with
  "Full Build Results" behind it; "**Zero data race safety errors**" (also from a build); hosted
  DocC documentation per version; README and Release Notes tabs; "Use this Package" snippets for an
  Xcode project and for a manifest, with a version picker; plain-language activity ("In
  development for 6 years, with 543 commits and 46 releases", "last issue closed 10 hours ago");
  dependency count ("No package dependencies"); products (1 library, 2 plugins, no macros); a
  score (145); licence; keywords; a "Do you maintain this package?" box offering shields.io
  compatibility badges.

### developer.apple.com/tutorials/swiftui

Read from the DocC JSON behind the page (tutorials/data/tutorials/swiftui.json):

- Four chapters, 10 tutorials, each with a time estimate: SwiftUI essentials (Creating and
  combining views 40 min, Building lists and navigation 35, Handling user input 20), Drawing and
  animation, App design and layout, Framework integration (UIKit, watchOS, **Creating a macOS
  app** 30).
- One continuous app, *Landmarks*, "an app for discovering and sharing the places you love".
- A tutorial is tasks → steps. "Creating and combining views" has 6 tasks and **44 steps; 28 carry
  a code file and 40 carry a screenshot or live preview**. The page shows prose on the left and the
  code (with the change from the previous step highlighted) or the preview on the right, pinned as
  you scroll. Each tutorial ends with **"Check Your Understanding"**: 4 multiple-choice questions
  with a justification for every answer, then a "next tutorial" call to action. Project files are
  downloadable.
- It now opens with an aside: "This tutorial no longer demonstrates current SwiftUI or Xcode
  practices", pointing to **Develop in Swift**, a larger course in eight volumes (Welcome,
  Discovery and prototyping, Explore Xcode/Views/Layout/State/Lists, models and persistence,
  views and data storage, ML and Foundation Models, visionOS, distribution to the App Store).

## 2. High-ROI pieces

1. **The step-by-step tutorial with a screenshot per step.** The SwiftUI tutorial is the thing
   people cite when they say they learned SwiftUI. Why it works: one app built across ten
   tutorials, each step small and paired with what you should now see, a time estimate up front,
   and a short quiz to check the idea stuck. Diffs between steps mean the reader never wonders
   what changed. It is authored in DocC (`@Tutorial`, `@Steps`, `@Code`) so the format is a
   tool, not a one-off.
2. **Previews in the loop.** The tutorial's chapter blurb promises you'll build "while watching it
   unfold in Xcode's preview". The thing being taught is visible at every step; that's what makes
   step 3 of 44 bearable.
3. **Code on the homepage.** Each swift.org feature claim ("Safe", "Interoperable") is backed by a
   short real program rather than an adjective. A sceptic can judge the language in thirty
   seconds.
4. **Install with the version in the nav.** "Install (6.4.1)" answers "is this alive, and what do
   I get" before any click.
5. **Use-case router.** "Create using Swift" sends each kind of reader to a getting-started page
   for their kind of project instead of one generic quick start.
6. **Package pages with evidence from builds.** SPI's compatibility grid and data-race line are
   not author-declared metadata; they come from SPI building the package across toolchains and
   platforms. That is the most trusted part of the page.
7. **Durable ids for language changes.** SE-NNNN ids appear everywhere (release notes, forums,
   compiler diagnostics), so a design decision has one citable home.

## 3. Low-value or missing

- **Split brand.** Language, packages and the UI framework live on three domains with three
  designs; swift.org's "iOS apps" card leads to a swift.org page, which ends by sending you to
  Apple. There is no one place that says "here is how you build a UI in Swift".
- **The best tutorial is marked stale.** The Landmarks tutorial carries a "no longer demonstrates
  current practices" banner. Tutorials rot when they aren't built from source that CI compiles.
- **No LLM docs.** swift.org/llms.txt, docs.swift.org/llms.txt and swiftpackageindex.com/llms.txt
  all 404. Apple's tutorials are rendered by JavaScript from JSON, so a plain fetch gets only the
  page title (our fetch of developer.apple.com/tutorials/swiftui returned only "Introducing
  SwiftUI"); the JSON is reachable but undiscoverable.
- **The docs hub is a redirect stub** (swift.org/documentation/ → docs.swift.org, which renders
  client-side).
- **SPI's "score" (145) is unexplained** on the page; the compatibility grid is what carries
  trust, the number doesn't.
- Homepage feature bands are aimed at language buyers (C++ interop, MMIO). Fine for Swift; a UI
  framework needs a picture of a UI instead.

## 4. For Cairn: cut / keep / add

What Cairn has: a homepage with a pixel-art night scene and a "latest milestone" panel plus an
annotated `move ^2 reset` sample; /milestones/; /docs/ (guide in six chapters, examples,
reference, internals, evidence); /docs/api/; /docs/evidence/ and /map/<app>/; /packages/;
/feed.xml.

**Keep**

- The annotated `move` sample on the homepage. It is Cairn's equivalent of swift.org's code
  bands and is the single best thing on the page; make sure it stays above the scene.
- /map/<app>/ pages. They are Cairn's SPI compatibility grid: evidence produced by the build, not
  written by an author (the Todo map's "proved 21/21, fuzzed 11/13, tested 21/21, seen 19/20" is
  exactly that). Nothing in the Swift world has this for UI behaviour.
- The guide's chapter structure ("Building an app · Chapter 1") and the rule that every sample is
  included from a file `make check` compiles. That is the fix for Apple's stale-tutorial banner.

**Cut or demote**

- **The milestone panel as the homepage's main content.** swift.org leads with what the thing is
  and how to install it; the latest milestone is blog material. Move it below the sample, or to a
  one-line "Latest: Third milestone: Pairs →".
- **"Maps" in the top nav as a separate destination** next to Docs. The maps are evidence for the
  docs' examples; SPI puts its build grid on the package page, not in its own nav item. Link each
  map from its example page (/docs/examples/todo/ → /map/todo/) and from its package version.
- **/map/trusted/ in the docs sidebar** ("The trusted base's map"). It is internals; it belongs
  under /docs/internals/trusted-base/, not next to the example apps' maps.
- **Stale text in the guide.** /docs/guide/first-app/ still says "The Cairn repository. It isn't
  public yet" and /docs/internals/contributing/ says the same, though github.com/iamnbutler/cairn
  is public. A reader who hits that stops.

**Add**

- **A screenshot (or frame capture) per guide step.** None of the six guide chapters has an
  image (grep of site/web/content/docs finds none outside the evidence pages). Cairn can do what
  Apple does by hand automatically: the map's headless capture already renders the app's own
  frames for each flow step, so a guide step can include the frame after the move it describes.
  Counter → Basics → TodoMVC as one continuous app across chapters, Landmarks-style.
- **Time estimates and a "what you'll build" image on each guide chapter**, and a two-question
  check at the end of "Proving a claim" (the concept most likely not to land).
- **Install, with the version, in the nav.** /packages/ shows cairn 0.2.0; the homepage doesn't.
  A "Get started (0.2.0)" button that goes to `cairn new hello` would answer the first question.
- **Per-version evidence on /packages/** in SPI's style: for each version, "builds on Lean
  4.x / macOS 27 ✓", "684 theorems, standard axioms only", "claims: 108 active, 3 retired". The
  ledger is there; put a one-line verdict at the top like SPI's "Zero data race safety errors".
- **A README badge** endpoint like SPI's ("proved 21/21") from the map data, for packages to show
  on GitHub.
- **Fetchable docs.** Serve the guide and reference as plain Markdown (or an llms.txt) since
  Swift's own client-rendered docs are hard for agents; Cairn's static site is already halfway
  there.

## 5. Ideas for the framework itself

- **Previews (`#Preview`).** SwiftUI's canvas renders a view from sample state next to the code;
  multiple `#Preview` blocks show variants. Cairn's view is a pure function of `State`, so a
  preview is just `view s` for a named `s`, painted headlessly by the same capture the map uses.
  A `preview` command in Lean (named states, rendered to PNG by `cairn preview` or shown in the
  infoview via ProofWidgets, research/lean/07-proofwidgets.md) would give previews for free and
  double as doc images. Touches docs/cli.md (a `cairn preview` command) and docs/doc.md (preview
  images in pages).
- **DocC's tutorial format as a model for `cairn doc`.** Steps with a code file each and an
  automatic diff against the previous step; a `@Code` that points at a file is the same discipline
  as bongo includes. A guide step could name a file *and a flow step* so the image is generated.
  Touches docs/doc.md.
- **SPI-style build matrix in the registry.** The registry builds each version anyway (docs/cli.md
  "Publishing", docs/package.md "What a version is"). Record which Lean toolchains and macOS
  versions it built on, and show it on the version page. Touches docs/package.md and
  site/registry.js.
- **Swift Evolution's ids.** Cairn already has durable claim ids; design decisions don't. An
  "evolution" log of decisions with ids (or reuse GitHub issue numbers consistently) would let
  docs cite why a thing is the way it is. Touches docs/roadmap.md.
- **Use-case routing.** swift.org's "Create using Swift" grid maps to Cairn's examples: "a window
  app" (TodoMVC), "a menu bar app" (Yap), "an app from packages" (Pairs). Touches the homepage and
  docs/roadmap.md's milestone list.
- **Interop as a feature.** SwiftUI's "Interfacing with UIKit" tutorial is an admission that
  people adopt incrementally. Cairn's host effects (docs/host.md, /docs/internals/host-effects/)
  are the escape hatch to AppKit; a guide chapter "Calling AppKit from a Cairn app" would answer
  the first objection a Swift developer has.
