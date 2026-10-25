---
title: "Rust's website and docs: rust-lang.org, doc.rust-lang.org, docs.rs, crates.io, the Playground"
urls:
  - https://www.rust-lang.org/
  - https://www.rust-lang.org/learn
  - https://www.rust-lang.org/tools/install
  - https://doc.rust-lang.org/book/
  - https://doc.rust-lang.org/rust-by-example/
  - https://doc.rust-lang.org/error-index.html
  - https://doc.rust-lang.org/std/vec/struct.Vec.html
  - https://doc.rust-lang.org/edition-guide/editions/index.html
  - https://doc.rust-lang.org/rustdoc/write-documentation/documentation-tests.html
  - https://docs.rs/
  - https://docs.rs/about/builds
  - https://crates.io/api/v1/crates/serde
  - https://play.rust-lang.org/
  - https://github.com/rust-lang/rust-playground
  - https://blog.rust-lang.org/
date: 2026-10-25
relevance: 4
---

# Rust's site and docs

Rust's web presence is five separate properties with one job each: a marketing and routing site
(rust-lang.org), a shelf of books (doc.rust-lang.org), the registry (crates.io), docs for every
published version of every crate (docs.rs), and a sandbox (play.rust-lang.org). The
marketing site is the least important of them. The other four are where people spend their time,
and they link to each other on every page.

## 1. What the site and docs contain

**rust-lang.org** (fetched 2026-10-24).

- Top nav: Install, Learn, Playground, Tools, Governance, Funding, Community, Blog; a 10-language
  selector.
- Hero: "Rust", the tagline "A language empowering everyone to build reliable and efficient
  software.", a **Get Started** button (`/learn/get-started`) and a version badge ("Version
  1.99.1") linking to the latest release post.
- "Why Rust?": three cards, Performance, Reliability ("rich type system and ownership model
  guarantee memory-safety and thread-safety"), Productivity ("great documentation, a friendly
  compiler with useful error messages, and top-notch tooling").
- "Build it in Rust": four domain cards (CLI, WebAssembly, Networking, Embedded), each a
  `/what/<domain>` page.
- "Rust in production", "Get involved" (Read, Watch, Contribute), Thanks, Get help, policy footer.

**/learn** is the real index. In order: *Get started* (the Book, Rust by Example, Rustlings);
*Read the core documentation* (std, Edition Guide, Cargo Book, rustdoc Book, rustc Book,
**Compiler Error Index**); domain books (CLI, Embedded); *Master Rust* (Reference, Rustonomicon,
Unstable Book). One line each, saying who it is for.

**/tools/install**: one command, `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`,
then `rustup update` and `rustup self uninstall`. Next steps point at the Playground "for trying
code without installing anything".

**doc.rust-lang.org.** Every book is an mdBook: sidebar of chapters, `S` or `/` to search, `←`/`→`
between chapters, print view, "suggest an edit", themes. The Book's front page says: "Want a
more interactive learning experience? Try out a different version of the Rust Book, featuring:
quizzes, highlighting, visualizations, and more: https://rust-book.cs.brown.edu". Rust by Example
is "runnable examples" with minimal prose, organised by language feature.

**The Error Index** (https://doc.rust-lang.org/error_codes/E0382.html): one mdBook page per code.
E0382 has a one-line summary ("A variable was used after its contents have been moved
elsewhere"), an erroneous example, then four fixes (borrow, clone, `Copy`, `Rc<RefCell<…>>`) as
prose plus code, and a link to the Book's ownership chapter. The compiler prints the code and
`rustc --explain E0382` prints the same page in the terminal.

**std / rustdoc output** (https://doc.rust-lang.org/std/vec/struct.Vec.html): version and build
hash in the header; every item shows the version it stabilised in and a `Source` link with line
anchors (`1.57.0 · Source`); unstable items carry a banner naming the feature gate and its
tracking issue; every example has a "Run" link that opens the Playground prefilled with
`edition=2024`; examples that panic are marked as such. Trait impls, blanket impls and
`Deref` methods are listed per type.

**docs.rs**: search with "I'm Feeling Lucky", a live feed of recent releases with an Atom feed,
and docs at `/{crate}/{version}/{crate_name}/`. From https://docs.rs/about/builds: "Docs.rs
automatically builds documentation for crates released on crates.io", in a sandbox with no
network, 6.4 GB RAM, a 15-minute rustdoc limit, up to 10 targets. Authors don't upload docs.

**crates.io**: the site is a JS app (a plain fetch returns only the title), but its API shows
what each version records: `num`, `rust_version` (MSRV), `edition`, `license`, `features`,
`crate_size`, `published_by`, an audit log of publish actions, `yanked`, plus crate-level
`documentation` (pointing at docs.rs), `repository` and download counts. serde has 316 versions
and 1.58 billion downloads.

**play.rust-lang.org**: from its README, compile in debug or release on stable, beta or
nightly; "the top 100 popular crates" are available; share via Gist; run rustfmt and Clippy; see
LLVM IR, assembly or MIR. No network inside the sandbox.

**blog.rust-lang.org**: a stable release every six weeks ("Announcing Rust 1.99.0", Oct 1;
1.99.1 Oct 15), plus security notices, survey results and policy changes. The version badge on
the homepage links to the latest of these.

## 2. High-ROI pieces

1. **One install line, then the Playground.** The install page is a single command and a pointer
   to the Playground for people not ready to install. The Playground removes the install as a
   condition of trying the language at all, and every doc example links into it, so reading and
   trying are one click apart.
2. **The Book plus Rust by Example**, two shapes of the same material: narrative chapters for
   people who read, a feature-by-feature list of runnable snippets for people who skim. /learn
   says which is which in one line each.
3. **docs.rs: docs for every version of every package, built by the registry, not the author.**
   Nobody has to remember to publish docs, every version's docs exist forever at a stable URL,
   and the build is sandboxed so the docs are what the source says. crates.io's `documentation`
   field defaults to it.
4. **Doc examples are tests.** "rustdoc supports executing your documentation examples as tests.
   This makes sure that examples within your documentation are up to date and working."
   (rustdoc Book). Combined with the Run link, every example on docs.rs both compiles in CI and
   runs in the browser.
5. **Stable error codes with a page each.** The compiler message names a code; the code has a
   page with a failing example and fixes; `rustc --explain` prints it offline. The Productivity
   card calls it out ("a friendly compiler with useful error messages") as one of three reasons
   to use Rust.
6. **"Since" versions and source links on every item.** You can tell what you can rely on
   (stable since 1.0.0), what can still change (unstable, with the tracking issue), and read the
   code in one click.
7. **Predictable releases.** Every six weeks, one post, linked from the homepage badge. The badge
   doubles as a "this is alive" signal.
8. **Editions.** "Crates in one edition must seamlessly interoperate with those compiled with
   other editions." Breaking changes are opt-in per crate, and `cargo fix` migrates code. This
   is the promise that lets the ecosystem trust upgrades.

## 3. Low-value or missing

- **The `/what/*` domain pages** are thin and dated: /what/cli cites 2017 talks and a structopt
  sample that no longer matches clap. Nobody adopts Rust from them; they are routing to external
  books.
- **"Rust in production"** is a one-line claim ("hundreds of companies") with no evidence on the
  page.
- **Governance, Funding, Thanks** matter to the project but not to someone deciding whether to
  try it; they live in the top nav anyway.
- **Many books, no single path.** /learn lists 14 resources; the Reference "is not a formal
  spec", and the line between Book, Reference and Rust by Example is left to the reader.
- **crates.io and the Playground render nothing without JavaScript**, so they're invisible to
  plain fetchers and agents. docs.rs and doc.rust-lang.org are plain HTML and work fine.

## 4. For Cairn: cut / keep / add

Cairn's site today (fetched 2026-10-24): a homepage with the night scene, the latest milestone,
"The idea", "What a claim is" and the evidence levels; /milestones/; /docs/ (Guides, Examples,
Reference, Internals, Evidence); /docs/api/ with claims.html; /docs/evidence/ and /map/<app>/;
/packages/; /feed.xml.

**Cut or shrink**

- **/docs/reference/errors/ as it stands.** It is a 14-line "to do" page (rendered as
  "Errorsto do") that says errors have no codes yet and points at issue #99. Rust shows that an
  error index is high value, but an empty one in the sidebar costs more than it gives. Remove it
  from the sidebar until #99 ships codes, then bring it back as a real index (see Add).
- **The stale "isn't public yet" line in /docs/guide/first-app/.** The repository is public; this
  line tells the reader to stop. Rust's install page never makes you doubt you can get it.
- **The unlabeled counts on /packages/** ("108 active, 3 retired, 44 moved"). crates.io shows
  numbers people already understand (downloads, versions). Either label them ("claims: 108
  active") or drop them from the list view and keep them on the versions page.

**Keep**

- **/packages/ with per-version claim ledgers.** This is Cairn's crates.io plus something
  crates.io doesn't have: the registry refuses a version that drops or renumbers a claim
  (docs/cli.md, `cairn publish`). That is Cairn's equivalent of Rust's stability promise and
  should stay prominent.
- **/docs/api/ generated by `make doc`**, with claims.html. This is Cairn's rustdoc; Rust shows
  it's worth a lot more once it's per version and linked from the registry.
- **/feed.xml and milestone posts.** Rust's blog-as-heartbeat works because it's regular and
  linked from the homepage; Cairn's milestone panel does the same.

**Add (in order of ROI)**

1. **Docs per published version, built by the registry** (docs.rs). /packages/ already links
   "Docs (version 0.2.0)"; make that `/packages/<owner>/<name>/<version>/docs/` built from the
   published source (issue #94 in docs/cli.md: "It takes no docs from a publisher; they will be
   built from the source"). Old versions' API and claim pages should never disappear.
2. **One install line on the homepage and /docs/.** Today neither has install instructions; the
   closest is first-app's prerequisites list (macOS 27, Xcode, elan, bun) plus `make build`.
   Even before a release binary exists, a copy-paste block (`cairn new hello --bin && cairn
   build && …`) tells people the shape of the loop. docs/cli.md lists installing `cairn` as
   not done; it is the single biggest gap Rust's site highlights.
3. **Source links and "since" versions on every API item and claim.** Each claim row on
   claims.html should say which version introduced it (the ledger knows) and link to the line
   that declares it. That is exactly rustdoc's `1.57.0 · Source`, and for a claim the "since"
   is part of its contract.
4. **A "Run" or "See it" link from examples.** Cairn can't run Lean apps in a browser cheaply,
   but every code sample on /docs/guide/ and /docs/examples/ could link to the claim on its map
   (screenshot, evidence) the way rustdoc examples link to the Playground. The map is Cairn's
   playground; examples should open into it.
5. **A short /docs/ landing in /learn's style**: three lines, three audiences ("try it", "build
   an app", "understand the evidence"), each pointing at one page.

## 5. Ideas for the language and tooling

- **Error codes with `--explain`** (docs/cli.md, /docs/reference/errors/, issue #99). Give
  every claims-DSL and ledger error a stable code (`C0001` "claim id declared twice", "retired id
  reused", "flow witness not live"), print it in the message, and serve the same page from
  `cairn explain C0001` and the site. Write each with a failing snippet and the fix, checked by
  `make doctest` like rustdoc's `compile_fail`.
- **`compile_fail` doc tests for claims.** Rustdoc's `compile_fail` attribute is a natural fit
  for "this claim must be rejected" examples: an id reused, a move whose `post` isn't proved.
  Belongs in docs/doc.md next to the existing doc tests.
- **Editions for the claims DSL** (docs/roadmap.md, docs/package.md). Cairn's ledger already
  promises ids keep their meaning. An edition field in `cairn.toml` would let the DSL's syntax
  and defaults change per package without breaking the ledger, with a `cairn fix` that migrates
  source. Worth deciding before more packages exist.
- **Per-version metadata like crates.io's**: the minimum Lean toolchain (Rust's `rust_version`),
  the macOS version a host needs, and the claim counts by kind, recorded at publish and shown on
  the versions page (docs/package.md).
- **Yank, not delete.** crates.io keeps yanked versions resolvable for existing lockfiles. The
  Cairn registry should say what happens to a bad release and its claims (docs/package.md).
- **Six-week cadence as a habit, not a rule.** Rust's badge links to the newest release post.
  Cairn's equivalent is the latest milestone panel; adding the latest package version
  (`cairn 0.2.0`) next to it would make the homepage say both "what we learned" and "what you can
  depend on".
- **`cairn doctor`** is listed as planned in cairn-tool.md; rustup's job (one tool that installs
  and checks the right toolchains) is what Cairn's four-toolchain prerequisite list (Xcode,
  Metal toolchain, elan, bun) most needs.
