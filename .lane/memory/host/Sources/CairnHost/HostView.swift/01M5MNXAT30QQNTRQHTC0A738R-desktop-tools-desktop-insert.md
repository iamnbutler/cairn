---
id: 01M5MNXAT30QQNTRQHTC0A738R
anchor: keyDown
created: 2026-10-23T15:26:14Z
norm: '1'
---

Desktop Tools' desktop_insert route type sends one keyDown per character (keyCode 0, flags 0, ~5 ms apart); other tools may put a whole string in one event. Both paths must take every character: interpretKeyEvents does, the no-field path uses KeyMapping.keys.
