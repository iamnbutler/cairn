---
title: Menu bar menus as data, and non-activating overlay panels, on macOS
urls:
  - https://developer.apple.com/tutorials/data/documentation/appkit/nsmenudelegate/menuneedsupdate(_:).json
  - https://developer.apple.com/tutorials/data/documentation/appkit/nspanel/becomeskeyonlyifneeded.json
  - https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/sharingtype-swift.enum/none.json
  - https://developer.apple.com/tutorials/data/documentation/appkit/nsstatusbar.json
  - https://developer.apple.com/tutorials/data/documentation/swiftui/menubarextra.json
  - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html
  - https://raw.githubusercontent.com/swiftlang/swift-corelibs-foundation/main/Sources/CoreFoundation/CFRunLoop.c
  - https://github.com/zed-industries/zed/blob/main/crates/gpui/src/platform/app_menu.rs
  - https://v2.tauri.app/learn/window-menu/
  - https://v2.tauri.app/learn/system-tray/
  - https://docs.rs/muda
  - https://www.electronjs.org/docs/latest/api/menu-item
  - https://api.flutter.dev/flutter/widgets/PlatformMenuBar-class.html
  - https://github.com/iced-rs/iced/pull/2931
  - https://code.visualstudio.com/docs/configure/custom-layout
date: 2026-10-23
relevance: 5
---

# Surfaces: status menus and overlay panels

Sources for [docs/surfaces.md](../../docs/surfaces.md) (M2, docs/goals/m2.md "Done means" item 3). Most
AppKit facts are quoted from the **macOS 27.0 SDK headers** (`xcrun --show-sdk-path`, then
`System/Library/Frameworks/AppKit.framework/Headers/`), cited as "SDK 27.0 X.h". Apple's doc
pages don't render to text; their JSON form (`developer.apple.com/tutorials/data/documentation/<path>.json`)
does. Items marked **measured** come from a throwaway Swift script run on macOS 27.0.1 (not kept).

## Findings that contradict common assumptions

1. **`NSMenuItem.identifier` is not its accessibility identifier.** Measured: setting
   `identifier` left `accessibilityIdentifier()` empty; `setAccessibilityIdentifier(_:)` works.
   `NSMenuItem` adopts the protocols (SDK 27.0 NSMenuItem.h: `@interface NSMenuItem : NSObject
   <NSCopying, NSCoding, NSValidatedUserInterfaceItem, NSUserInterfaceItemIdentification,
   NSAccessibilityElement, NSAccessibility>`).
2. **`sharingType = .none` no longer hides a window from capture.** Apple: "A legacy constant
   that macOS no longer uses… Don't use this value to hide or omit content from being captured."
   (sharingtype none.json)
3. **`hidesOnDeactivate` defaults differ from the docs.** The docs say the default for NSPanel is
   true; measured, a borderless or `.nonactivatingPanel` panel had `hidesOnDeactivate == false`
   and `canBecomeKey == false`, a `.titled` panel `true`. Set both explicitly.
4. **macOS 27 adds an official popover hook for status items.** SDK 27.0 NSStatusItem.h,
   `expandedInterfaceDelegate`: "This method should be used instead of manually toggling your
   interface by target/action handling on the button… This allows the status item to participate
   in keyboard navigation and menu tracking behaviors."
5. **macOS 27 hides menu item images by default.** SDK 27.0 NSMenuItem.h: "in macOS 27 and later,
   AppKit determines the visibility of menu item images, and will typically hide images. Use the
   `preferredImageVisibility` property with the `.visible` constant…" (Yap's menu has none.)
6. **Announcement key name.** The header comment says `NSAccessibilityAnnouncementPriorityKey`;
   the exported symbol is `NSAccessibilityPriorityKey`.

## AppKit

**Status items** (SDK 27.0 NSStatusBar.h, NSStatusItem.h)
- `- (NSStatusItem *)statusItemWithLength:(CGFloat)length;`
- `menu`: "The drop down menu that is displayed when the status item is pressed or clicked."
- `button`: "created automatically on the creation of the StatusItem."
- `visible`: "Defaults to YES. Persisted based on the -autosaveName. This is observable through
  KVO." `autosaveName`: "Apps with multiple status bar items should set an autosave after
  creation."
- `NSStatusItemBehaviorRemovalAllowed`: "By default, an item is not removable… Upon removal,
  -visible is set to NO." `TerminationOnRemoval`: "The application terminates when the user
  removes the item."
- NSStatusBar doc: "status items are not guaranteed to be available at all times."

**NSMenu** (SDK 27.0 NSMenu.h)
- `autoenablesItems`: "If a menu autoenables items, then calls to -[NSMenuItem setEnabled:] are
  ignored, and the enabled state is computed via the NSMenuValidation informal protocol…
  Autoenabling is on by default." → a data-driven host turns it off.
- Delegate: `menuNeedsUpdate:` or `numberOfItemsInMenu:` + `menu:updateItem:atIndex:shouldCancel:`
  ("implement either the first one or the next two"). Doc JSON: "Invoked when a menu is about to
  be displayed at the start of a tracking session… Menu item validation occurs after this method
  is called."
- `menuWillOpen:`/`menuDidClose:`: "Do not modify the structure of the menu or the menu items from
  within these callbacks."
- **Not confirmed:** whether title/state/structure changes while a menu is displayed show live.
  The header promises it only for item views ("Changes to the view's frame during tracking are
  reflected immediately in the menu"); an old mailing-list thread
  (https://macosx-dev.omnigroup.narkive.com/LZQpV24a/) says item text can't be changed while
  displayed. The surfaces spike must measure it.

**NSMenuItem** (SDK 27.0 NSMenuItem.h): `state` (on/off/mixed), `enabled`, `alternate`, `tag`,
`representedObject`, `keyEquivalent`, `keyEquivalentModifierMask`, `toolTip`, `submenu`; macOS 14
`badge` (`NSMenuItemBadge`) and `+sectionHeaderWithTitle:`; macOS 14.4 `subtitle`.

**Run-loop modes during tracking**
- NSMenuItem.h: "because menu tracking occurs in the NSEventTrackingRunLoopMode, you must add the
  timer to the run loop in that mode."
- `Timer.scheduledTimer(withTimeInterval:repeats:block:)` "schedules it on the current run loop in
  the default mode" (doc JSON), so it stalls while a menu is open.
- Common modes include "event tracking modes by default" (Threading Programming Guide, archived).
- CFRunLoop.c (L3069): `if (libdispatchQSafe && (CFRunLoopGetMain() == rl) &&
  CFSetContainsValue(rl->_commonModes, rlm->_name)) dispatchPort =
  _dispatch_get_main_queue_port_4CF();` → `DispatchQueue.main` is drained in every common mode,
  so Cairn's `MainHop` keeps applying frames while a menu is open.

**Panels and windows** (SDK 27.0 NSWindow.h, NSPanel.h, CGWindowLevel.h)
- `NSWindowStyleMaskNonactivatingPanel` (`1 << 7`): "does not activate the owning application.
  Only applicable for NSPanel."
- `becomesKeyOnlyIfNeeded`: "If the panel is a non-activating panel, then it becomes key only if
  the hit view returns true from needsPanelToBecomeKey." Default false.
- `ignoresMouseEvents`: "whether the window is transparent to mouse events."
- `orderFrontRegardless`: "Moves the window to the front of its level, even if its application
  isn't active, without changing either the key window or the main window."
- `isFloatingPanel` measured: raises the level from 0 to 3.
- Levels: normal 0, floating 3, main menu 24, status 25, pop-up menu 101, screen saver 1000
  (`.statusBar`, `.popUpMenu`, `.screenSaver` measured as 25, 101, 1000).
- Collection behaviour: Transient "Floats in spaces, hidden by exposé"; Stationary "Unaffected by
  exposé"; IgnoresCycle default when the level isn't normal; FullScreenAuxiliary "can be shown with
  the fullscreen window"; CanJoinAllApplications (macOS 13) "allowing it to join other apps' sets
  and full screen spaces… should commonly be used for floating windows and system overlays";
  Auxiliary (macOS 13) for About/Settings windows; at most one of Primary, Auxiliary,
  CanJoinAllApplications. CanJoinAllSpaces and MoveToActiveSpace have no header description.

**Activation policy** (SDK 27.0 NSRunningApplication.h): Accessory "does not appear in the Dock and
does not have a menu bar, but it may be activated programmatically or by clicking on one of its
windows. This corresponds to LSUIElement=1." Prohibited corresponds to LSBackgroundOnly and is "the
default for unbundled executables."

**Accessibility** (SDK 27.0 NSAccessibilityConstants.h)
- Announcements: post `NSAccessibilityAnnouncementRequestedNotification` "for the application
  element" with `NSAccessibilityAnnouncementKey`; `NSAccessibilityPriorityKey` "is required"
  (low 10, medium 50, high 90).
- Menu roles a custom menu would have to imitate: `NSAccessibilityMenuRole`,
  `NSAccessibilityMenuItemRole`, `NSAccessibilityMenuBarItemRole`.
- **Not confirmed:** whether `ignoresMouseEvents` affects VoiceOver. One report of a non-activating
  click-through overlay whose toasts were never announced: https://github.com/woosublee/quill/issues/391.

**Screens** (NSScreen.h, NSEvent.h, NSApplication.h): `screens` ("first one is 'zero' screen"),
`visibleFrame`, `NSEvent.mouseLocation` ("global mouse coordinates"),
`NSApplicationDidChangeScreenParametersNotification`. No API for "the screen under the pointer":
hit-test `mouseLocation` against each screen's frame (as Yap does).

**SwiftUI `MenuBarExtra`** (doc JSON): `.menu` "renders its contents as a menu that pulls down";
`.window` "renders its contents in a popover-like window". "An app that only shows in the menu bar
will be automatically terminated if the user removes the extra." Yap uses `.menu` because "only a
native menu has submenus" (`~/code/yap/App/YapApp.swift`).

## Menus as data in other toolkits

| Toolkit | Model | Rendering | Ids and events |
|---|---|---|---|
| GPUI (Zed), `app_menu.rs` | `enum MenuItem { Separator, Submenu(Menu), SystemMenu(OsMenu), Action { name, action: Box<dyn Action>, os_action: Option<OsAction>, checked: bool, disabled: bool } }`, `set_menus(Vec<Menu>, &Keymap)` | native NSMenu (`crates/gpui_macos/src/platform.rs`, `create_menu_item`: `item.setEnabled(!disabled); let tag = actions.len() as NSInteger; item.setTag(tag); actions.push(action.boxed_clone());`) | tag = index into an action table, looked up again in `validateMenuItem:`. No status items (no `NSStatusBar` in the repo) |
| Tauri v2 / muda | `MenuItem`, `CheckMenuItem`, `Submenu`, `PredefinedMenuItem`, built with ids: `CheckMenuItemBuilder::with_id("en", "EN")` | native; tray via `TrayIconBuilder::new().menu(&menu)` | string ids; `match event.id().0.as_str()`; muda delivers `MenuEvent` through `MenuEvent::receiver()`. To change text or check state "you can `set_menu` again" |
| Electron | `Menu.buildFromTemplate([{ id, type: 'checkbox', enabled, checked, submenu }])`, `Tray` | native | `id` "Unique within a single menu"; `enabled`, `checked`, `label`, `visible` "can be dynamically changed"; on Linux trays you must call `setContextMenu` again |
| Flutter | `PlatformMenuBar`, `PlatformMenuItem` | "uses the platform's native APIs to construct and render a menu… has no visual representation, and intercepts no events" (macOS only out of the box) | callbacks per item. The closest analogue to Cairn's design |
| SwiftUI | `MenuBarExtra` content as views | native in `.menu` style | closures |
| iced | none native; the muda integration PR (#2931) was closed unmerged; iced_aw's `menu` widget is custom-drawn | custom | messages |
| Elm | browser; no native menus (general knowledge, not sourced) | DOM | messages |
| VS Code | `window.menuStyle`: "native by the OS, custom, or inherited from the title bar style" | either | custom menus need their own roles and states ("Custom controls need to provide proper textual name, role, and state information", microsoft/vscode#227484) |

Pattern: every toolkit that keeps menus as data renders them natively and routes a stable id back
to the app; the ones that draw their own do it for cross-platform sameness, and inherit an
accessibility burden.

## Pitfalls

- Leaving `autoenablesItems` on silently overrides the app's enabled state.
- Rebuilding a menu wholesale while it is open loses the highlighted item; reconcile in place.
- Default-mode timers stop during menu tracking.
- Relying on documented panel defaults (`hidesOnDeactivate`), or on `sharingType` for privacy.
- `NSMenuItem.identifier` alone leaves VoiceOver and UI tests without the id.

## For Cairn

Workstream R (surfaces), and the host: [docs/surfaces.md](../../docs/surfaces.md) recommends a
native, reconciled NSMenu from a Lean menu description, ids via `representedObject` and
`setAccessibilityIdentifier`, `autoenablesItems = false`; and a borderless `.nonactivatingPanel`
with `canBecomeKey = false`, `ignoresMouseEvents`, explicit `hidesOnDeactivate = false`,
`.statusBar` level, all-Spaces and full-screen-auxiliary behaviour, shown with
`orderFrontRegardless`. The spike must confirm live menu updates while open and VoiceOver access to
a click-through panel.
