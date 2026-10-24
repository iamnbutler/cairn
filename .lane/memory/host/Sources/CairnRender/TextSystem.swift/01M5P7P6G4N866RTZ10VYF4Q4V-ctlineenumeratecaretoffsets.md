---
id: 01M5P7P6G4N866RTZ10VYF4Q4V
anchor: '@file'
created: 2026-10-24T05:56:09Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 4b360b305794667d
raw_hash: 27cdcf8ae4af731c
lines: 1-185
supersedes: 01M5NECAZXM9XH1EJJ0QT4RB0J
---

CTLineEnumerateCaretOffsets's leading edge only on untracked lines with no RTL run; other untracked lines still ask CTLineGetOffsetForStringIndex, and tracked lines use the pen ends (no Core Text carets)
