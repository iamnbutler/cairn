# cairn doc

Issue #74. Cairn's rustdoc: a package's docs generated from its code, never written by hand. It
works for an app and for Cairn itself, and Cairn's output is the API reference of the developer
docs (#73), at [/docs/api/](../site/public/docs/api/).

```sh
make doc APP=Todo           # Examples.Todo and its submodules → build/doc/Todo/dist/
make doc PKG=Cairn          # the framework → build/doc/Cairn/dist/
make doc APP=Todo OPEN=1    # …and open it; PRIVATE=1 shows private declarations
make site-api               # Cairn's docs → site/public/docs/api/ (committed)
make doctest                # the doc tests alone (in make check)
```

On a built tree `make doc` takes about 8 s, nearly all of it Lake checking the build and two
environment imports; rendering takes under a second.

## The decision: our own export, rendered beside the map

Two ways to get the rustdoc half (modules, types, functions and theorems, with doc comments,
signatures, positions, search and cross-links):

**(a) doc-gen4**, Lean's generator, with the claims and evidence added on top. It has a tag for
our toolchain (`v4.35.0`), so it would work today. Measured in a scratch package (Examples.Todo,
which imports `Lean` through the claim commands):

| | doc-gen4 v4.35.0 |
|---|---|
| Dependencies | 6 packages (doc-gen4, Cli, UnicodeBasic, BibtexQuery, MD4Lean, leansqlite, two in C) |
| Building the generator | 66 s |
| Documenting Examples.Todo | 185 s |
| Disk, `.lake` | 836 MB |
| Output | 227 MB, 2,538 pages (Init 71 MB, Std 90 MB, Lean 44 MB; Cairn and Examples 2.3 MB) |

It documents the whole import closure, so every app pulls in `Lean`'s docs. It knows nothing of
claims: `^202` appears as eleven unrelated declarations (`newTodo`, `newTodo.edit.post`,
`newTodo.submit.sound`, `newTodo.info`, `Cairn.Claims.Issued.«^202»`, …) in its own look. Adding
the claims means either forking its HTML or post-processing 2,500 pages, and keeping either in
step with doc-gen4's releases. AGENTS.md also keeps Lean dependencies to core and Std.

**(b) Our own export** walks the Lean environment, as `lake exe claims` already does, and
`tools/doc` renders it with the map's code and style. `lake exe doc` (lean/Cairn/Doc/Export.lean,
about 250 lines) takes each declaration's doc comment (`findDocString?`), its signature
(`ppSignature`, with the constants in it tagged so pages can link them, the way doc-gen4 does
it), its position (`findDeclarationRanges?`), and a theorem's axioms (`collectAxioms`, as the
audit). No dependencies, a few seconds, and output only for the package asked for.

**Chosen: (b).** It fits the map: claims come from the same export and their evidence from the
same `tools/map/evidence.ts`, so a claim reads the same on both. We control the pages, so they
look like the site and a claim is one entry, not eleven. It costs nothing to build. What we give
up is doc-gen4's breadth (Verso docstrings, `simp` attribute listings, `Init`/`Std` pages,
equation lemmas, a declaration-data API for the editor); none of it is needed yet, and links to
Lean's own declarations stay plain text (with the full name on hover).

## Pages

`build/doc/<name>/dist/` is static, flat and relative, so it works from disk and from any path
on the site:

| Page | Shows |
|---|---|
| `index.html` | the root module's doc comment (for an app), counts (modules, declarations, theorems and whether every one is on the standard axioms, claims by how they read, doc tests, hidden private declarations), then every module, nested by name, with its declaration and claim counts and the first sentence of its doc comment |
| `<Module.Name>.html` | the module's doc comment and imports; then its claims, then its declarations grouped by kind (structures, inductive types, classes, definitions, theorems, instances, axioms), with a sidebar of them all. A toggle shows them in source order instead, with the module's section comments (`/-! ## … -/`) between them |
| `claims.html` | every claim by id, with how it reads and each kind of evidence, linking to its entry: the address book for `^N` |
| `search-index.js`, `search.js` | client-side search over names, doc comments and claims |

**A declaration** shows its kind, its full name, its source as text (`lean/Cairn/Layout/Core.lean:329`;
the repository is private, so there is no link), its signature with every constant in the package
linked, and its doc comment as Markdown. A structure lists its fields with their types and
docs, an inductive type its constructors, and a type the instances for it (`Repr`, `BEq`, …). A
theorem carries a chip: `proved` when it depends only on `propext`, `Classical.choice` and
`Quot.sound`, red with the axioms otherwise. Left out: recursors, `noConfusion`, matchers,
equation lemmas, structure projections (they are the fields) and the methods of instances.

**A claim** is the map's card, on the page of the module that declares it: its id, title, kind
and how it reads; `does` and `sees`; the place it is in; its **formal statement**, each
statement declaration as written (`edit.post s op s' := s'.newField = …`); the evidence ladder
with what each kind rests on; its proofs, linked to their declarations; a flow's witness; for a
move, the before and after screenshots when `make map` captured them; its source and ledger
state; and, folded, the declarations the claim command generated (`newTodo.edit.sound`,
`newTodo.info`, …), which therefore aren't listed again as loose definitions.

**Anchors never change while the name does not.** A declaration's anchor is its full name
(`Cairn.Layout.Core.html#Cairn.Layout.layout`), a field's `Type.field`, a claim's its number
(`Examples.Todo.html#202`, the map's convention). A claim keeps its id for ever, so `#202` is
permanent; a declaration's anchor is as stable as its name.

**Links.** `^N` anywhere (doc comments, `does`/`sees`, witnesses, evidence details) links to the
claim's entry. In doc comments, a name in backticks links when it resolves from the documented
declaration's namespace the way Lean would (`layout` from `Cairn.Layout`) or is a module name.
Signatures link every constant in the package. Constants from another package link when it was
given with `--link`: an app's docs link `Cairn.*` to `../../Cairn/dist/` (`make doc` does this),
so `build/doc/Todo/dist/` links into `build/doc/Cairn/dist/`.

**Search** is a static index (names, kinds, the first 280 characters of each doc comment, and
`^N` with each claim's title and prose), loaded as a script so it works from `file://`. Names
rank above doc text; `^212` or `212` finds the claim. `/` focuses it, arrows and Enter pick.

**Private declarations** (`private`, or not `public` in a `module` file) are left out by
default and counted on the index; `PRIVATE=1` (`--private`) shows them, marked.

**Look.** The map's `style.css` plus `tools/doc/doc.css`: the night palette, Pixelify Sans for
headings and labels, a serif for prose, a monospace for code, the evidence chips. Pages load
`/scene.js` and call `mountSprigs(main)` and `mountAnchors(main)`, as map pages do, so on the site
headings get sprigs and copyable `#` links; from disk the import fails quietly.

## Doc tests

Lean code blocks in doc comments are checked, like rustdoc's doc tests. `lake exe doc --check`
elaborates each ` ```lean ` block, in an environment with the documented modules imported,
inside the namespace of the declaration (or module) it documents, with `autoImplicit` off. Any
error is reported with the block's file and line, and the exit code is 1, so `make doc` stops.
`make doctest` runs them for Cairn and every example, and is part of `make check`.

A block fenced ` ```lean ignore ` is shown and not checked: for sketches that name things that
don't exist (`MyApp.State` in `Cairn.Runtime.Abi`). Today there is one doc test,
`Cairn.ControlRef.label`'s, and two ignored sketches.

## How it is built

| Step | Command (inside `make doc`) | Output in `build/doc/<name>/` |
|---|---|---|
| Declarations | `lake exe doc --check <modules>` | `doc.json`: modules (doc comments, imports), declarations (kind, signature, doc, line, private, fields, constructors, instance, axioms), each claim's statement declarations as binders and body, the doc test count |
| Claims | `lake exe claims <modules>` | `claims.json`, as for the map |
| Pages | `bun tools/doc/cairn-doc.ts` | `dist/` |

For `APP=Todo` the modules are `Examples.Todo` and every file under `lean/Examples/Todo/`; for
`PKG=Cairn`, `DOC_CAIRN` in the Makefile (`Cairn`, `Cairn.Claims`, `Cairn.Fuzz` and the trusted
base's modules; the tool executables `Cairn.Claims.Export`, `Ledger`, `Tool`, `Tests` and
`Cairn.Doc.Export` are left out). Evidence is whatever `build/` already has, as on the map:
`build/fuzz/<App>.json`, `build/fuzz/trusted.json`, `build/conformance/<App>.json`, and the map's
capture in `build/map/<App>/capture/` for screenshots. Proved comes from the export's own axiom
check, so `make doc` doesn't need the whole-package audit (60 s).

Sizes on this build: Cairn 59 modules with pages, 2,124 declarations (1,924 listed: the public
ones not generated by a claim command), 665 theorems, 40 claims, 2.2 MB in 66 files; Todo 6 modules, 388 declarations, 24 claims, 0.9 MB with its screenshots.

## Not yet

- **More doc tests.** Only one block is checked today. Blocks could also run (`#guard`) and
  show their output, as rustdoc's do.
- **Cross-package links on the site.** Apps' docs link Cairn by its build directory
  (`../../Cairn/dist/`); on the site Cairn is at `/docs/api/` and apps' docs aren't published, so the
  link scheme needs a decision once they are. Links into Lean's own declarations are plain text.
- **Hosting per version.** `site/public/docs/api/` is main's. Versioned paths
  (`/docs/api/<tag>/`) wait for releases.
- **The map and the docs are still two outputs.** They share the claim export, the evidence
  model and the style; a claim's map page and its doc entry could become one page.
- **Signatures** are pretty-printed at 92 columns, with no per-binder layout or implicit-argument
  folding as doc-gen4 has.
