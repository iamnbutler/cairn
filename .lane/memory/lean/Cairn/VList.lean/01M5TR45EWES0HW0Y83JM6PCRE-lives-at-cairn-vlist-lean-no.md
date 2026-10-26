---
id: 01M5TR45EWES0HW0Y83JM6PCRE
anchor: '@file'
created: 2026-10-26T00:00:21Z
norm: '1'
---

Lives at Cairn/VList.lean, not Cairn/UI/: it imports Cairn.App (for UI), and Cairn.App imports Cairn.UI.Node, so filing it under UI/ is a directory-level cycle that make lint rejects.
