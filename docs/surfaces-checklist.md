# Surfaces: manual checklist

What the window server does with a status item and an overlay panel can't be asserted from
inside the app (docs/surfaces.md decision 9, docs/trusted.md ^942, ^943). Run this by hand with
Tray before a release, or after changing `host/Sources/CairnHost/Surfaces.swift`:

```sh
make bundle APP=Tray && open build/apps/Tray.app
```

Record the macOS version and the result of each line.

## Status item and menu

- [ ] A tray icon appears in the menu bar. There is no Dock icon and Tray is not in ⌘Tab.
- [ ] Clicking it opens the menu: "0 recent, menu opened 1 times", Show Overlay (⌘O), Keep
      Recent Items (checked), Add Item, Recent Items ▸, Quit Tray (⌘Q).
- [ ] With the menu open, ⌘O shows the overlay and ⌘Q quits.
- [ ] Arrow keys and Return choose items; VoiceOver reads each item's title, checked state and
      enabled state.
- [ ] Add Item twice: the icon becomes `tray.full`, Recent Items lists Item 2, Item 1.
- [ ] Keep Recent Items off: Add Item is greyed out and can't be chosen; the recent items are gone.
- [ ] The status line updates while the menu is open (leave it open across an overlay tick with
      the overlay shown: the menu stays responsive).

## Overlay panel

- [ ] Show Overlay: a dark panel with moving bars appears at the bottom centre of the screen the
      pointer is on, 56 pt above the bottom of its visible frame (above the Dock).
- [ ] It never takes focus: typing in the frontmost app keeps working, and that app's window
      stays key.
- [ ] Clicks pass through it to the window underneath.
- [ ] It stays put when switching Spaces (shown on every Space) and shows over a full-screen app.
- [ ] Moving the pointer to another display while shown doesn't move it; hide and show again on
      the other display and it appears there.
- [ ] It doesn't hide when another app is activated.
- [ ] The caption keeps its last two lines as it grows, ending in "tick N".
- [ ] Hide Overlay: it fades out over about a fifth of a second.
- [ ] Stage Manager on: it stays visible and doesn't join a stage.
