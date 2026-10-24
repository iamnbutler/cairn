# profile

- 2026-10-24T06:47:27Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 4c6e265; APPS=cairnbase cairn ref RUNS=3 SECS=10 SCREEN=0 BUFFER_MS=20
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## profile

| | cairn | cairnbase | ref |
|---|---|---|---|
| runs | 3 | 3 | 3 |
| cpu_ms_per_s_total | 114.52 (114.0–117.48) | 341.89 (341.19–380.26) | 102.03 (68.3–116.81) |
| status item replicants ms/s | 0.0 (0.0–0.0) | 75.46 (75.31–79.13) | 0.0 (0.0–0.0) |
| HostView.applyLatestFrame ms/s | 10.11 (8.87–12.34) | 31.31 (28.48–31.43) | 0.0 (0.0–0.0) |
| StatusHost.update ms/s | 8.75 (7.76–10.98) | 28.23 (26.38–30.08) | 0.0 (0.0–0.0) |
| CA transaction commit ms/s | 0.12 (0.0–0.25) | 92.69 (92.47–93.31) | 33.31 (25.03–33.51) |
| RenderLoop.tick ms/s | 22.92 (19.62–22.93) | 26.62 (18.62–38.21) | 0.0 (0.0–0.0) |
| LeanCore.step ms/s | 14.56 (13.68–17.87) | 19.48 (18.12–20.71) | 0.0 (0.0–0.0) |
| ShapeCache.paintShadow ms/s | 5.55 (3.21–5.67) | 4.07 (3.7–6.04) | 0.0 (0.0–0.0) |
| vImage blur ms/s | 2.34 (1.6–3.2) | 1.73 (1.36–2.59) | 0.0 (0.0–0.0) |
| CPU ms/s by thread, cairn | CairnYap 55.35, cairn.lean 23.2, cairn.render 23.42, Main Thread 12.94, com.apple.CFNetwork.CustomProtocols 0.12, com.apple.NSEventThread 0.12 | | |
| CPU ms/s by thread, cairnbase | Main Thread 229.64, CairnYap 66.33, cairn.render 28.35, cairn.lean 26.26, com.apple.CFNetwork.CustomProtocols 0 | | |
| CPU ms/s by thread, ref | Main Thread 55.4, YapRef 43.43, CVDisplayLink 3.08, com.apple.NSEventThread 0, com.apple.CFNetwork.CustomProtocols 0 | | |
