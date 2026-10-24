---
id: 01M5PCKFV67N1R7BH3AW8F2BZH
anchor: YapMapCapture
created: 2026-10-24T07:22:03Z
norm: '1'
---

The map-capture flag must be handled in main.swift before Bench and CairnApp.main: CairnYap with an unknown argument launches the live app (real key, microphone, typing). The capture's world is fakeWorld's, and effectHook keeps every effect, so Copy never touches the real clipboard.
