---
title: Widget identity in immediate-mode UIs — Dear ImGui's ID stack and egui's Id (with React keys for contrast)
url: https://github.com/ocornut/imgui/blob/master/docs/FAQ.md#q-about-the-id-stack-system
author: Omar Cornut et al. (Dear ImGui); Emil Ernerfeldt et al. (egui); React docs
date: Dear ImGui master 09fe7b1 (1.93.1 WIP); egui 0.37.0; react.dev fetched 2026-10-23
relevance: 4
---

# How immediate-mode UIs name widgets, and how that fails

## What it is

Immediate-mode UIs rebuild the widget tree every frame, so they need an identity that survives
from one frame to the next, to know that the slider being dragged now is the one pressed last
frame, and to key per-widget state (open/closed, scroll, text cursor). Both Dear ImGui and egui
*derive* identity by hashing a path. That is the background for Cairn's opposite choice:
identity is a declared claim id plus an app-chosen key (`ControlRef`, `^5#12`).

Sources: Dear ImGui `docs/FAQ.md` "About the ID Stack system", `imgui.h`, `imgui.cpp` at
09fe7b1; egui `crates/egui/src/id.rs`, `ui.rs`, `context.rs`, `memory/mod.rs` at tag 0.37.0;
react.dev "Rendering Lists". All MIT/Apache or docs; quoted, not archived.

## Key findings (quoted)

### Dear ImGui

- Identity is a hash of a path: "Unique identifiers are hashes of the label + of the parent scope
  (e.g. parent window or parent tree node labels)" (FAQ, TL;DR). The type is 32 bits:
  `typedef unsigned int ImGuiID; // A unique ID used by widgets (typically the result of hashing
  a stack of string)` (imgui.h L172), computed with CRC32 (`ImHashStr`, imgui.cpp L2570).
- Label and identity are entangled, and the FAQ leads with the failure: "**USING THE SAME
  LABEL+ID IS THE MOST COMMON USER MISTAKE!** … **USING AN EMPTY LABEL IS THE SAME AS USING THE
  SAME LABEL AS YOUR PARENT WIDGET!**".
- What a collision does: `Button("OK"); Button("OK"); // ERROR: ID collision with the first
  button! Interacting with either button will trigger the first one.` and `Button(""); //
  ERROR: ID collision with Begin("MyWindow")!` (FAQ, "General description").
- Workarounds are string conventions: `"##suffix"` adds to the id invisibly, `"###id"` makes the
  id ignore the visible label so a label can change ("Hello###ID" and "World###ID" are the same
  widget), and `PushID(int | ptr | string)` scopes loops (FAQ).
- Loops: the choice of what to push decides what "same widget" means across edits. "when
  displaying a list of objects, using indices or pointers as ID will preserve the node
  open/closed state differently" (FAQ). Pushing an index means state follows the *position*
  after an insert or delete, not the object.
- Changing the hash function changes every id: "1.91.6 – changed CRC32 table from CRC32-adler to
  CRC32c … As a result, old .ini data may be partially lost" (imgui.cpp L666–668, changelog).
- Detection is dynamic, partial and debug-only: `io.ConfigDebugHighlightIdConflicts` ("Highlight
  and show an error message popup when multiple items have conflicting identifiers", imgui.h
  L2549), implemented on hover only: "this is specifically done here by comparing on hover
  because it allows us a detection of duplicates that is algorithmically extra cheap, 1 u32
  compare per item" (imgui.cpp L5120). A collision between two widgets the user never hovers
  is never reported. `ImGuiItemFlags_AllowDuplicateId` opts out.

### egui

- `pub struct Id(NonZeroU64)` "A (hopefully) unique identity within this application … egui
  tracks widgets frame-to-frame using [`Id`]s … This implies that the [`Id`]s must be "globally"
  unique" (id.rs). Made by hashing: `Id::unique(source)` uses `ahash` with fixed seeds; children
  by `parent.with(salt)`. A zero hash is silently mapped to `NonZeroU64::MIN` ("very bad luck").
- Two kinds, stable and unstable. `scope_id` is the stable one; `unique_id`: "This is NOT
  _stable_: it is based on where in the widget hierarchy this `Ui` is, so it changes if widgets
  are added or removed before it. It should therefore only be used for transient interactions
  (clicks etc), never for storing state over time" (ui.rs L374–383). Widgets without an explicit
  id get `next_auto_id`, "based on the [`Self::unique_id`] of this `Ui` and the number of
  widgets added so far. It is therefore NOT stable" (ui.rs L918–925). The file opens with
  `// TODO(emilk): have separate types PositionId and UniqueId. ?` (id.rs L1).
- The accessibility tree is keyed by these ids: `register_accesskit_parent(ui.unique_id, …)` and
  `accesskit_node_builder(ui.unique_id, …)` (ui.rs L159–191). So an assistive-technology node's
  identity can change when an unrelated widget is inserted above it.
- Clash detection is per frame, rect-based, on by default only in debug builds
  (`warn_on_id_clash: cfg!(debug_assertions)`, memory/mod.rs L347): a second use of an id is
  ignored if one rect contains the other ("It is ok to reuse the same ID for e.g. a frame around
  a widget"), otherwise it paints "Double use of {what} ID" with the hint "ID clashes happens
  when things like Windows or CollapsingHeaders share names, or when things like Plot and
  Grid:s aren't given unique id_salt:s. Sometimes the solution is to use ui.push_id"
  (context.rs L1432–1497).

### React keys (retained mode, same problem)

"Keys tell React which array item each component corresponds to … You might be tempted to use
an item's index in the array as its key. In fact, that's what React will use if you don't
specify a `key` at all … Index as a key often leads to subtle and confusing bugs … do not
generate keys on the fly … Instead, use a stable ID based on the data." (react.dev, Rendering
Lists)

## Failure modes, summarised

1. **Collision by equal path** (same label in same scope; empty label = parent): two controls,
   one identity; the second is unreachable. Detected late or never (hover-only, debug-only).
2. **Positional identity drift** (index push, auto ids, React index keys): insert/delete
   reattaches state, focus or an in-progress drag to a different object.
3. **Hash collisions** (32-bit CRC in ImGui, 64-bit in egui): rare, silent, not prevented.
4. **Identity tied to presentation** (label text): changing copy changes identity unless the
   `###` escape is used.
5. **Identity tied to the hash function or salting scheme**: changing either renumbers
   everything persisted (ImGui 1.91.6).

## For Cairn

- **Adopt (A):** the claim id is declared, not derived; never a hash, never a position, never a
  label. That removes failure modes 1, 3, 4 and 5 by construction. The ledger (`claims.lock`)
  already makes reuse a build error; add a theorem or `#guard` per app that `view` never emits two
  controls with the same `ControlRef` in one frame. That is the static version of ImGui's
  hover-only check and egui's debug-only check.
- **Adopt (A, I):** `ControlRef.key` must come from data identity, never list position (failure
  mode 2, React's "use a stable ID based on the data"). For TodoMVC, key = todo id (T24 in
  [../todomvc/README.md](../todomvc/README.md)), so `^toggle#7` is the same todo after a delete
  above it and under every filter. Prove it: after any move, a surviving todo's controls keep
  their `ControlRef`s.
- **Watch (A):** `ControlRef.key = 0` means "only one" (lean/Cairn/Claim.lean). If todo ids
  start at 0, the first todo's controls are indistinguishable from a singleton control. Start
  ids at 1 or make the key an `Option`.
- **Adopt (G):** accessibility identifiers are `^N#k`, stable across frames and edits, unlike
  egui's AccessKit node ids built from `unique_id`. Conformance (J) should assert identifier
  stability across an insert above, not just presence.
- **Study (A, D):** where Cairn needs per-control *runtime* state (a text field's caret,
  a pressed button, hover), key it by `ControlRef`, not by node path. When a todo is deleted
  while its row is hovered or its edit field is focused, the runtime state must be dropped,
  not inherited by the todo that slides into its place.
- **Study (A):** `###` shows a real need: the label changes, the identity doesn't. Cairn has
  that by default (title/does/sees text is metadata on a fixed id). The converse, a meaning
  change with the same label, needs a *new* id (AGENTS.md, "Changing what a claim means needs a
  new id").
