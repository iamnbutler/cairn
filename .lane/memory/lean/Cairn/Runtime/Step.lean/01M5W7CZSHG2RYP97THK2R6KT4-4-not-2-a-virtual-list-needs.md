---
id: 01M5W7CZSHG2RYP97THK2R6KT4
anchor: def settleFuel
created: 2026-10-26T13:46:34Z
norm: '1'
supersedes: 01M5TR3AXE6XZ60BC6JH5F4VFE
---

4, not 2: a virtual list needs a layout at the estimate, one at the recorded heights, and one more for rows the corrected offset brings into the window; the fuzz 'vlist' check fails (unsettled rows) with 2. Lists that need more (many known rows changing at once, #276) get them from resettle, not from raising this.
