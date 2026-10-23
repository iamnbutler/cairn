# Research

Sourced notes on prior art. One folder per source or topic. Each note has frontmatter (title,
urls, date, relevance 1–5), quoted findings with locations, pitfalls, counter-evidence and a
"For Cairn" section naming the workstream it serves (see `docs/plan.md`). Archived originals and
probe scripts go in a `raw/` folder next to the notes.

## macOS host and renderer (`macos/`)

How custom-rendered macOS apps do text, input methods, accessibility and GPU drawing, and where
they break. For workstreams F (renderer/text) and G (host).

| Note | For | Relevance |
|---|---|---|
| [macos/text-rendering.md](macos/text-rendering.md): Core Text shaping, glyph atlases, grayscale AA, font smoothing, gamma, measured caret offsets | F | 5 |
| [macos/text-input-ime.md](macos/text-input-ime.md): NSTextInputClient in GPUI, winit, Chromium, Firefox, Ghostty, kitty; IME, dead keys, press-and-hold, dictation | G, D, E | 5 |
| [macos/accessibility.md](macos/accessibility.md): NSAccessibilityElement trees, AccessKit, GPUI, Chromium, Flutter; identity, coordinates, notifications | G | 5 |
| [macos/metal-ui-rendering.md](macos/metal-ui-rendering.md): SDF rects, clipping, batching, frame pacing, colour space, latency | F | 5 |
| [macos/appkit-events.md](macos/appkit-events.md): tracking areas, cursors, scroll phases, key equivalents, Edit-menu routing | G | 5 |
