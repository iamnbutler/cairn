# Claim pages

Every package on the registry gets claim pages: every claim a version makes, grouped by the
place (window) it belongs to, and a page for each claim under its id. The site's Worker renders
them from JSON the registry serves (`site/claims.js`, `site/registry.js`). Nothing on them is
written by hand or by an agent: titles and prose come from the claims, and every status from
the claims export.

They replace the maps, which an agent built per app with screenshots and committed to
`site/public/map/`. The old `/map/<app>/` URLs redirect to the matching place page
(`site/public/_redirects`); a fragment such as `#202` still lands on that claim's row.

## URLs

| URL | Shows |
|---|---|
| `/packages/<name>/claims/` | the latest version's overview |
| `/packages/<name>/<version>/claims/` | a version's overview |
| `/packages/<name>/<version>/claims/<id>/` | one claim; the versionless form also works |

**Overview.** A tally of how the claims read, then one section per place (`#place-<id>`) with
its moves, flows and anything else that names it; claims in no place; invariants; assumptions,
grouped by module (for Cairn, its trusted base, ^9xx and ^10xx); and ids moved to other
packages, linked to their new home. Every row has its claim's id as its anchor, so
`…/claims/#202` and `…/claims/201/#202` both find ^202.

**A claim's page.** Its kind, how it reads, its place and version; what you do (or what it is,
or says) and what you see; a flow's steps, each linking to the move it presses; a place's claims;
its evidence theorems with any axioms beyond the standard three, and the evidence it could have
that isn't shown yet; where it's defined (declaration, module, file and line at the version's
tag, machine, the declarations its statement hash covers); and its ledger row.

## Where the data comes from

Two answers of the registry, both JSON:

- `GET /api/v1/packages/<owner>/<name>/versions/<v>/claims`: the version's `claims.lock` as rows
  (id, kind, status, statement hash, title). Every published version has it.
- `GET …/versions/<v>/claims/export`: the version's claims export (docs/claims.md, "The claims
  export"), exactly the package's own claims (`lake exe claims --scope <name>`).

`cairn publish` sends the export as the publish body's sixth section (docs/cli.md) when the
registry's `/config.json` lists `claims.json` in `publish.sections`. The registry parses it,
keeps only the known fields, checks it against `claims.lock` (same scope, every id in the lock
with the same kind, no moved id, the lock's statement hash for every live claim), and stores the
re-encoded JSON beside the pack. A version's metadata says `export: true` when it has one, so
the site doesn't ask for one it knows is missing.

The registry stores and serves JSON only. It never accepts or serves HTML from a publisher: the
site renders every page and escapes every field.

**Why publish it, rather than commit `claims.json` for the registry to read.** A committed
export changes on every edit that moves a line, so it would be stale or churn; checking it would
need a Lean build in CI anyway; and the Worker would have to read a file out of a git pack. The
CLI already builds the package to publish it, and the registry already checks `claims.lock` at
publish, so the export is checked in the same place against the same lock.

**Before a version has an export** (anything published before this, or to a registry that
doesn't take one), its pages come from the ledger alone: each id with its kind, status and
title, and a note that the rest is in the export. Places can't be grouped without it.

**A package outside this repository** gets claim pages by publishing with a `cairn` CLI that
sends the export: nothing else to set up. Its scope is its name, and `cairn claims --ledger`
shows what will be sent.

## Evidence

The ladder (proved, fuzzed, tested, seen, assumed) is in
[the evidence reference](../site/web/content/docs/reference/evidence.md). The claim pages show
only what the export holds:

| Reads as | When |
|---|---|
| `retired` | the claim is retired; its reason shows |
| `moved` | the ledger says another package owns the id now |
| `assumed` | an `assume`: stated, never proved |
| `proved` | every evidence theorem depends on no axioms beyond `propext`, `Classical.choice` and `Quot.sound` |
| `not proved` | an evidence theorem uses another axiom |
| `no proof` | a live claim with no evidence theorem |
| `ledger only` | the version has no export |

A flow's witness (its steps) is shown as written; it is what its liveness proof follows.
Fuzzing, conformance and screenshots need a build that runs the app. Each claim lists the ones
its kind can have as "not shown yet"; a CI step will publish them as JSON beside the export
(#95). `cairn doc` and `make doc` still show them locally, from `build/` (docs/doc.md).

## The capture, for a visual export later

A claim's page leaves room for a picture of it: its place with its control highlighted, as PNG
or SVG at `…/claims/<id>/<file>`. That isn't built. The pieces it can reuse are kept:

```sh
make capture APP=Counter     # headless screenshots → build/capture/Counter/shots/
```

`tools/map/capture-script.ts` turns an app's export into a script: the initial state, each
flow's witness, and each move no flow presses. `host/Sources/CairnCapture` (`MapCapture`) runs
it inside the app's own executable (`Cairn<App> --map-capture <script.json> <dir>`) on a Lean
thread with no window: for each step it finds the control with that ref in the frame's
accessibility nodes, sends pointer events at its centre (or, for text steps, focuses the field
and sends the text or key), takes the next frame, and renders it offscreen with CairnRender's
`Renderer.image(frame, scale:)`. A step that leaves the frame unchanged is recorded as `inert`.
Pins come from each node's visible rect, labelled `^N` or `^N#k`: dashed orange for a control,
solid blue for the one the next step acts on. Each app executable opts in with one line:

```swift
if let code = MapCapture.main(args, size: Size(w: 480, h: 320), core: { LeanCore(counter) }) { exit(code) }
```

`tools/map/evidence.ts` decides the evidence statuses `cairn doc` shows, from the audit, fuzz,
conformance and the capture; a CI step for #95 can reuse it.
