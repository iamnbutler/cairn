# perf2-120hz-buf20

- 2026-10-24T12:31:20Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit e413f87; APPS=cairnbase cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=20
- display 0 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | cairnbase | ref |
|---|---|---|---|
| runs | 5 | 4 | 5 |
| display_hz | 120 | 120 | 120 |
| presented_per_s | 59.75 (59.71–59.82) | 118.34 (117.43–118.95) | 59.97 (59.94–60.04) |
| frame_interval_ms | 16.666 / 16.74 / 25.096 / 41.701 (n=5406) | 8.333 / 8.379 / 12.526 / 41.675 (n=8562) | 16.666 / 16.72 / 16.816 / 33.337 (n=5424) |
| share_intervals_over_1.5x_median | 0.0374 | 0.01 | 0.0024 |
| cadence_changes_share | 0.1602 | 0.0201 | 0.0166 |
| level_to_present_call_ms | 8.605 / 15.45 / 16.56 / 25.996 (n=4500) | 4.207 / 7.553 / 8.629 / 31.636 (n=3600) | 7.931 / 14.363 / 16.66 / 20.075 (n=4500) |
| level_to_presented_ms | 16.906 / 24.091 / 37.698 / 50.558 (n=4500) | 11.767 / 15.181 / 26.774 / 39.322 (n=3600) | 11.309 / 17.732 / 20.177 / 43.812 (n=4500) |
| cpu_ms_per_s_total | 50.04 (40.32–60.98) | 70.02 (60.36–78.88) | 64.84 (61.32–70.93) |
| cpu_ms_per_s_by_quarter_median | 68.3 → 36.9 → 38.9 → 48.8 | 74.5 → 60.0 → 65.3 → 71.1 | 47.5 → 71.3 → 76.7 → 77.3 |
| fp.time_on_glass_avg_ms | 16.666 (16.658–16.667) | 8.401 (8.354–8.472) | 16.67 (16.666–16.687) |
| fp.time_on_glass_stddev_ms | 1.358 (0.718–3.592) | 0.551 (0.224–1.039) | 0.467 (0.215–0.793) |
| fp.time_on_glass_max_ms | 25.0 (25.0–33.333) | 27.083 (16.666–29.166) | 29.166 (25.0–33.333) |
| fp.total_end_to_end_avg_ms | 24.766 (23.43–24.892) | 32.667 (32.589–32.723) | 20.047 (20.001–20.132) |
| fp.cpu_end_to_end_avg_ms | 0.272 (0.222–0.314) | 0.218 (0.192–0.257) | 0.213 (0.185–0.276) |
| fp.gpu_end_to_end_avg_ms | 0.106 (0.104–0.111) | 0.107 (0.104–0.108) | 0.074 (0.068–0.082) |
| fp.gpu_done_to_completed_avg_ms | 23.944 (22.73–24.162) | 31.947 (31.903–31.953) | 19.39 (19.361–19.54) |
| fp.next_drawable_wait_avg_ms | 0.01 (0.007–0.013) | 7.521 (5.623–8.269) | 0.005 (0.004–0.007) |
| fp.next_drawable_wait_max_ms | 0.944 (0.377–2.132) | 27.937 (24.861–33.136) | 0.023 (0.015–0.305) |
| fp.late_on_glass_frames | 859 (589–969) | 2011.0 (1995–2021) | 688 (552–849) |
| fp.skipped_frames | 4 (4–4) | 12.5 (12–14) | 0 (0–0) |
| CPU ms/s by thread, cairn | CairnYap 25.46, cairn.render 14.91, cairn.lean 10.66, Main Thread 4.53, com.apple.CFNetwork.CustomProtocols 0 | | |
| CPU ms/s by thread, cairnbase | cairn.render 16.48, CairnYap 33.52, cairn.lean 12.79, Main Thread 6.07, com.apple.NSEventThread 0.06 | | |
| CPU ms/s by thread, ref | Main Thread 43.24, YapRef 19.72, CVDisplayLink 0.99, com.apple.CFNetwork.CustomProtocols 0.06, com.apple.NSEventThread 0 | | |
