---
id: 01M5RDTQ7PCXTXJYKA1JVXZJAG
anchor: func conformance
created: 2026-10-25T02:21:57Z
norm: '1'
---

SwiftPM builds no static lib for a dependency's product (CairnMetrics), so the generator links the app build's CairnRender.o and CairnFrame.o; their strong cairn_text_metrics beats text_host.c's weak one
