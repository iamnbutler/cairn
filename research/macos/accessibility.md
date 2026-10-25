---
title: Accessibility for custom-drawn UIs on macOS
date: 2026-10-23
relevance: 5
urls:
  - https://github.com/AccessKit/accesskit/tree/a39329d281a9/adapters/macos/src
  - https://github.com/zed-industries/zed/tree/604a0ff023ec/crates/gpui/src/window/a11y.rs
  - https://github.com/zed-industries/zed/blob/604a0ff023ec/crates/gpui_macos/src/window.rs
  - https://github.com/chromium/chromium/tree/eb4f56eefdfeed72228d1436906df55c90374838/ui/accessibility/platform
  - https://github.com/flutter/flutter/tree/7b0a985e549de7c9401db8def8b77e1d1e618617/engine/src/flutter/shell/platform/darwin/macos/framework/Source
  - https://developer.apple.com/documentation/appkit/nsaccessibilityelement-swift.class
  - https://developer.apple.com/documentation/appkit/nsaccessibilityelement-swift.class/accessibilityframeinparentspace
  - https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/layoutchanged
---

# Accessibility for custom-drawn UIs on macOS

Question: how do apps that paint their own pixels (AccessKit, GPUI, Chromium, Flutter) expose an
accessibility tree to VoiceOver, and what breaks? Cairn's host (workstream G) mirrors each
frame's `AxNode`s as `NSAccessibilityElement`s with identifier `^N`; the conformance driver
(J) reads that tree back. The spike (`host/Sources/CairnSpike/HostView.swift`, `mirror()`)
allocates a fresh `NodeElement` for every node on every frame and posts `layoutChanged` on the
view. Everything below is about why that has to change and what to copy instead.

Commits: AccessKit `a39329d281a9`, Zed `604a0ff023ec`, Chromium `eb4f56eefdfe`,
Flutter `7b0a985e549d`.

## 1. Identity: one native object per logical node, for the node's lifetime

**AccessKit** keeps a map from node id to its `NSAccessibilityElement` subclass and hands out
the same object every time; the object holds only a weak context and the id, and resolves all
attributes against the *current* tree on each call.

> `platform_nodes: RefCell<HashMap<FullNodeId, Id<PlatformNode>>>,`
> `pub(crate) fn get_or_create_platform_node(self: &Rc<Self>, id: FullNodeId) -> Id<PlatformNode> { … if let Some(result) = platform_nodes.get(&id) { return result.clone(); }`
> — `adapters/macos/src/context.rs:38,70-79`

> `type Super = NSAccessibilityElement;` … `struct PlatformNodeIvars { context: Weak<Context>, node_id: FullNodeId }`
> `fn resolve_with_context … let node = state.node_by_id(self.ivars().node_id)?;`
> — `adapters/macos/src/node.rs:391-404,1340-1350`

So an element whose node vanished answers `nil`/zero for everything instead of dangling, and it is
only removed from the map when the diff says the node was removed, at which point
`UIElementDestroyed` is posted on it (`event.rs:55-63`, `event.rs:328-334`).
`accessibilityNotifiesWhenDestroyed` returns `true` (`node.rs:750-753`).

**GPUI** (Zed now uses AccessKit through `accesskit_macos::SubclassingAdapter`) states the rule
outright:

> "Each node has an ID, and this ID *should* be stable across frames. If a node's ID changes,
> then, from AccessKit's point of view, it is a different node. We derive the node ID from the
> [`GlobalElementId`] … Nodes without [`GlobalElementId`]s cannot produce an AccessKit
> [`NodeId`], and so are not included in the accessibility tree."
> — `crates/gpui/src/window/a11y.rs:51-58`

Duplicate ids are a silent drop in release:

> `"Duplicate a11y node id: {id:?}. In a release build, this node would be silently discarded from the a11y tree."`
> — `crates/gpui/src/window/a11y.rs:414-419`

and GPUI "repairs" every update because "Accesskit panics on invalid [`TreeUpdate`]s" (focus not
in tree, children referencing missing ids) — `a11y.rs:589-633`.

**Chromium** shows how much VoiceOver keys on object identity: to make VoiceOver re-announce a
focused element whose selection changed, it deliberately *swaps* the native object, because
"VoiceOver ignores focus events to an already focused object":

> "Replace a native object and refocus if it had focus. This will force VoiceOver to re-announce
> it, and refresh Braille output." … "Detach the old native wrapper to avoid UAF, but suppress
> the notification so it won't interfere the VO changing focus to the new native object." …
> "The worst case scenario if this gets destroyed too early is that VoiceOver announces the wrong
> thing once."
> — `ui/accessibility/platform/browser_accessibility_mac.mm:104-164`;
> `browser_accessibility_manager_mac.mm:323-341`

The corollary for Cairn: recreating every element every frame is the same trick applied to the
whole tree on every keystroke. VoiceOver's cursor sits on an object; when that object is
replaced, VO loses its place or re-announces. Chromium also guards against stale objects with
`instanceActive` checks on nearly every method (`ax_platform_node_cocoa.mm:558-560`, and
`detachAndNotifyDestroyed:` at `:1061-1069`).

## 2. Coordinates

Apple: `accessibilityFrame` "Returns the accessibility element's frame in screen coordinates";
for `NSAccessibilityElement`, `setAccessibilityFrameInParentSpace` "ensures that the
accessibility client receives the correct frame (in screen coordinates) as the element's parent
moves" (docs, URLs above).

**AccessKit** does not use parent space. It overrides `accessibilityFrame` and converts itself:
physical px → logical, flip if the view is *not* flipped, view → window → screen.

> `y: if view.isFlipped() { rect.y0 / factor } else { let view_bounds = view.bounds(); view_bounds.size.height - rect.y1 / factor },`
> `let rect = view.convertRect_toView(rect, None); … window.convertRectToScreen(rect)`
> — `adapters/macos/src/util.rs:57-81` (changelog: "Handle views with flipped coordinates
> (#174)", "Correctly apply the DPI scale factor to coordinates (#185)")

Hit testing goes the other way from a *screen* point (`util.rs:38-55`, `adapter.rs:275-294`).

**Flutter** flips with the *primary* screen, not the main screen:

> "The VoiceOver seems to only accept bounds that are relative to primary screen. Thus, this
> method uses [[NSScreen screens] firstObject] instead of [NSScreen mainScreen]."
> — `FlutterPlatformNodeDelegateMac.mm:141-150`; the y flip from top-left to bottom-left is at
> `:120-139`.

**Chromium** computes `accessibilityFrame` as clipped screen DIPs
(`ax_platform_node_cocoa.mm:1071-1077, 2840-2841`).

**Cairn spike** found empirically that parent space is y-up even when the parent view is
flipped (`docs/spike-boundary.md`; `HostView.swift` converts with `bounds.height - y - h`). That
matches AccessKit's need to special-case flipped views. Parent space does not track the view
scrolling or the window being on a second display with a different height unless AppKit
re-queries; computing `accessibilityFrame` on demand from the last frame avoids both.

## 3. Notifications: what to post, on which object, in what order

AccessKit's event generator (`adapters/macos/src/event.rs`) is the smallest complete reference:

| Change | Notification | Target | Source |
|---|---|---|---|
| node removed (or filtered out) | `UIElementDestroyed` | the removed element | `event.rs:55-63,250-258,328-334` |
| focus moved | `FocusedUIElementChanged` | new focus | `event.rs:133-138,319-326` |
| title changed | `TitleChanged` | node | `event.rs:264-269` |
| value changed | `ValueChanged` | node | `event.rs:270-290` |
| text changed in a text node | `ValueChanged`, inserted *first* | text node | `event.rs:182-191` |
| text selection changed | `SelectedTextChanged` | text node | `event.rs:291-299` |
| selection in list changed | `SelectedRowsChanged` | container | `event.rs:204-214` |
| live region | `AnnouncementRequested` with `userInfo` | the **window** | `event.rs:65-103` |

Ordering rules recorded in the code:

> "Text change events must come before selection change events."  — `event.rs:182-184`
> "Bool value changed event for the focused node must come last in order for VoiceOver to
> announce it. Otherwise, if we raise bool value changed events for other nodes after this one,
> VoiceOver will announce them instead." — `event.rs:272-283`

AccessKit posts **no** `LayoutChanged` and no `Created`. Flutter, by contrast:

> "NSAccessibilityCreatedNotification seems to be the only way to let Voiceover pick up layout
> changes." (posted on the window for CHILDREN_CHANGED) — `AccessibilityBridgeMac.mm:263-271`

Apple says `LayoutChanged` "should be accompanied by a `userInfo` dictionary with the key
`uiElements` and an array containing the UI elements that have been added or changed" — the
spike posts it with no userInfo every frame.

Chromium quirks worth knowing:

- Posting on an element with no `AXWindow`: "AppKit will hang trying to reach the root,
  resulting in a bug where VoiceOver keeps repeating '[appname] is not responding'."
  — `ax_platform_node_mac.mm:37-44`
- "Voiceover seems to drop live region changed notifications if they come too soon after a live
  region created notification" — delayed 20 ms, `browser_accessibility_manager_mac.mm:37,236-282`.
- `SelectedTextChanged` / `ValueChanged` carry a `userInfo` with
  `AXTextStateChangeType` (`Edit` vs `SelectionMove`); "This key prevents a bug where VoiceOver
  repeats placeholder information in text inputs while the user is typing." —
  `browser_accessibility_manager_mac.mm:640-660, 700-724`.

AccessKit's `QueuedEvents::raise` must run with no locks held: "It is unknown whether
accessibility methods on the view may be called while events are being raised" —
`event.rs:120-130`. Posting a notification can re-enter your `accessibilityChildren` etc.
synchronously.

## 4. Text fields

AccessKit implements the modern `NSAccessibility` text methods and expresses every range in
**UTF-16**:

> `node.text_position_from_global_utf16_index(ns_range.location)` … `range.start().to_global_utf16_index()`
> — `adapters/macos/src/util.rs:13-28`
> `accessibilityNumberOfCharacters` → `document_range().end().to_global_utf16_index()` —
> `node.rs:755-765`

The full set it answers (gated per node in `isAccessibilitySelectorAllowed:`,
`node.rs:1235-1263`): `accessibilityNumberOfCharacters`, `SelectedText`,
`SelectedTextRange`, `InsertionPointLineNumber`, `RangeForLine:`, `RangeForPosition:`,
`StringForRange:`, `AttributedStringForRange:`, `FrameForRange:` (union of glyph boxes →
screen, `node.rs:960-983`), `LineForIndex:`, `RangeForIndex:`, `StyleRangeForIndex:`, and
`setAccessibilitySelectedTextRange:` (routed as an action, `node.rs:1031-1046`).
`setAccessibilityValue:` is allowed only for editable text or nodes supporting `SetValue`
(`node.rs:1258-1260`).

Flutter takes a different route: an editable text field is backed by a real, invisible
`NSTextField` whose field editor is Flutter's `NSTextView`-based input plugin, so AppKit's own
text accessibility does the work. Getting it attached is fiddly:

> "Selecting text seems to be the only way to make the field editor current editor." —
> `FlutterTextInputSemanticsObject.mm:121-131`

and read-only text fields are re-roled to static text (`FlutterPlatformNodeDelegateMac.mm:53-61`).

## 5. Actions

AccessKit routes every AX action as a semantic request to the app, never a synthesized click,
and returns whether it was supported:

> `accessibilityPerformPress` → `ActionRequest { action: Action::Click, … }`; returns `clickable`
> — `node.rs:693-710`; likewise Increment/Decrement (`:712-748`), `setAccessibilityFocused:`
> (`:663-691`, unfocus focuses the root), `setAccessibilityValue:` (`:580-606`),
> `setAccessibilitySelected:` / `accessibilityPerformPick` → Click (`node.rs:1067-1088,1140-1158`).


The action handler "will always be called on the main thread" (`adapter.rs:81-86`) and
"may queue the request and handle it asynchronously. This behavior is preferred over blocking"
(`accesskit/src/lib.rs:3362-3374`).

Mixed protocols: "when mixing the newer NSAccessibility protocols with the older informal
protocol, the platform uses both protocols to discover which actions are available" — so
`accessibilityActionNames`/`accessibilityPerformAction:` only add `AXScrollToVisible`
(`node.rs:1200-1232`). Chromium likewise: these deprecated methods "are a) still called by
AppKit internally and b) not implemented by NSAccessibilityElement" —
`ax_platform_node_cocoa.mm:1471-1473`.

Chromium's press is `kDoDefault` on the node (`ax_platform_node_cocoa.mm:1548-1553`), not a
pointer event.

## 6. Hit testing, focus, children, laziness

- **Hit test.** Chromium walks children in reverse z-order against their screen frames and falls
  back to `NSAccessibilityUnignoredAncestor(self)` (`ax_platform_node_cocoa.mm:1448-1462`).
  AccessKit converts the screen point and asks the tree (`adapter.rs:275-294`). Both answer
  from data, never from the renderer.
- **Focus.** The view's `accessibilityFocusedUIElement` returns the element for the tree's
  focus (`adapter.rs:248-262`). If the host puts first responder on the window rather than the
  content view, AccessKit has to patch `NSWindow` to forward the query
  (`patch.rs:25-48`; changelog #266). AccessKit also decouples in-tree focus from window focus:
  `update_view_focus_state` is called on key-window changes (`adapter.rs:147-172`; GPUI calls it
  from its activation callback, `gpui_macos/src/window.rs:3181-3189`).
- **Navigation order.** `accessibilityChildrenInNavigationOrder` is implemented (as children
  order) — changelog: "Make VoiceOver move through nodes in logical order (#176)";
  `node.rs:454-458`.
- **Parent chain.** The root node's `accessibilityParent` is the view's parent, and
  `accessibilityWindow`/`TopLevelUIElement` come from the view (`node.rs:412-447`).
- **Laziness.** AccessKit builds nothing until an assistive client first asks for children,
  focus or hit test (`adapter.rs:174-221`); `request_initial_tree` "must always generate a
  [`TreeUpdate`] with a full tree" (`accesskit/src/lib.rs:3340-3358`). Until then
  `update_if_active` is a no-op (`adapter.rs:114-145`).
- **Lifetime.** Zed found a retain cycle: "`MacWindowState -> adapter -> content view ->
  GPUIView -> MacWindowState`, a cycle the delegate/`frame_source` teardown below cannot break"
  — `gpui_macos/src/window.rs:1355-1367`.

## Pitfalls

1. **Recreating elements per frame breaks VoiceOver.** Identity is the object pointer, not
   `accessibilityIdentifier`. Chromium replaces an object *on purpose* to force a re-announce
   (`browser_accessibility_mac.mm:104-164`); doing it every frame means VO loses its cursor and
   re-reads. Keep a `[ControlRef or node key → element]` map; mutate in place.
2. **Every range on the AX text API is UTF-16.** AccessKit converts at the boundary
   (`util.rs:13-28`); Cairn's `TextInput.selection` and Lean `Field` are Unicode-scalar indices
   (`lean/Cairn/Font.lean:7`). Emoji and astral characters make them diverge.
3. **Flipped view, y-up parent space, primary screen.** Parent space is y-up even under a flipped
   parent (spike); screen flips use `NSScreen.screens[0]`, not `mainScreen` (Flutter
   `FlutterPlatformNodeDelegateMac.mm:141-150`); backing vs logical px (AccessKit #185).
4. **Notification order matters.** Text-change before selection-change; focused-node bool value
   change last (`event.rs:182-191,272-283`). VoiceOver ignores a focus notification for the
   already-focused object (Chromium `browser_accessibility_manager_mac.mm:335-340`).
5. **Never post on an element that isn't attached to a window** — AppKit hangs and VO says the
   app is not responding (`ax_platform_node_mac.mm:37-44`). After a node goes away, post
   `UIElementDestroyed` on it once and make the stale object answer empty.
6. **Re-entrancy.** Posting a notification may synchronously call back into your AX methods;
   don't hold the frame lock while posting (`event.rs:120-130`).
7. **Legacy action API still matters.** `NSAccessibilityElement` doesn't implement
   `accessibilityActionNames`; AppKit queries both protocols (`node.rs:1200-1205`,
   `ax_platform_node_cocoa.mm:1471-1473`). Gate selectors with `isAccessibilitySelectorAllowed:`
   so a non-text node doesn't advertise text attributes (`node.rs:1235-1330`).
8. **Duplicate or dangling ids** are silently dropped (GPUI) or panic (AccessKit) —
   `a11y.rs:411-423,589-633`. For Cairn, `^5#12` keys must be unique per frame; worth a theorem.
9. **`LayoutChanged` without `uiElements` userInfo, every frame**, is noise; nobody surveyed
   posts it per frame. AccessKit doesn't post it at all; Flutter uses `Created` on the window.
10. **First responder on the window, not the view**, hides the focused element from VO unless
    the window forwards `accessibilityFocusedUIElement` (`patch.rs:25-48`).

## Counter-evidence

- AccessKit and Chromium do not rely on `accessibilityFrameInParentSpace` at all; they compute
  `accessibilityFrame` in screen space on demand. Apple's docs recommend parent space for
  `NSAccessibilityElement`. Either works; on-demand screen frames are simpler to make correct with
  a flipped Metal view, and avoid the y-up surprise the spike hit.
- AccessKit posts no `LayoutChanged` or `Created`, yet Flutter says `Created` "seems to be the
  only way" to get VO to notice layout changes. These disagree; AccessKit relies on
  `UIElementDestroyed` plus VO re-querying `accessibilityChildren`. Test with VoiceOver on
  Cairn's add/delete todo flows before choosing.
- Flutter gets text-field accessibility (and IME) by hosting a real `NSTextField` + `NSTextView`
  field editor, not by implementing the text attributes itself. That is less code but puts
  AppKit's own text state next to Lean's, which Cairn's "Lean owns meaning" rule rejects; it is
  evidence the hand-rolled route (AccessKit's) has more edges.
- Synthesizing a click at the node centre for `accessibilityPerformPress` (the spike's approach)
  is unusual: every surveyed implementation sends a semantic action. The click route is what
  makes Cairn's pressable theorem cover AX presses, so it is defensible, but it fails for nodes
  that are scrolled off or occluded, which VoiceOver can still reach.

## For Cairn

**G (host):**

- Replace per-frame `NodeElement` allocation with a map keyed by the stable node key
  (`ControlRef` where present, else a key Lean derives from the tree path). On each frame:
  update existing elements' properties in place, create new ones, post `UIElementDestroyed` on
  removed ones and mark them dead (every getter returns empty). Return the same objects from
  `accessibilityChildren`.
- Override `accessibilityFrame` (screen coords, computed from the last frame's rect via
  `convert(_:to: nil)` then `window.convertToScreen`) instead of setting parent space, and
  implement the view's `accessibilityHitTest(_:)` from the frame's rects (front-most first),
  and `accessibilityFocusedUIElement` from the frame's focused node.
- Diff consecutive frames' `ax` arrays and post, in AccessKit's order: `ValueChanged` for text
  edits first, then `SelectedTextChanged`, `TitleChanged`/`ValueChanged`, `FocusedUIElementChanged`
  last for the focused node. Drop the unconditional per-frame `layoutChanged`. Post after
  releasing the frame lock; skip when the view has no window.
- Text field element: implement `accessibilityNumberOfCharacters`, `SelectedTextRange`,
  `SelectedText`, `StringForRange:`, `FrameForRange:`, `RangeForPosition:`, `LineForIndex:`,
  `setAccessibilitySelectedTextRange:`, all in **UTF-16**, converting from Lean's scalar indices
  with one shared helper (the same one `NSTextInputClient` needs). `FrameForRange:` needs per
  scalar caret offsets — the `TextMetrics.offsets` Lean already has; carry them in `TextInput`
  or the AX node.
- Route `setAccessibilityFocused:`, `setAccessibilityValue:` and
  `setAccessibilitySelectedTextRange:` as events to Lean (new `Event` cases, workstream E), never
  by mutating host state. Keep press as a centre click if the pressable theorem needs it, and
  record in `docs/trusted.md` that AX press assumes the control is on screen.
- Implement `isAccessibilitySelectorAllowed(_:)` per role, and `accessibilityActionNames` for
  anything not covered by the modern protocol.
- Make `HostView` (not the window) first responder, or forward `accessibilityFocusedUIElement`
  from the window.
- Conformance (J) can rely on `accessibilityIdentifier == "^N"` only if identifiers are unique
  per frame; ask E/C for a theorem that `ControlRef`s in a frame are distinct.

**F (renderer/text):** expose per-character rects (or per-scalar caret offsets plus line box)
from the Core Text path so `accessibilityFrameForRange:` and `firstRectForCharacterRange:`
(IME) share one implementation.
