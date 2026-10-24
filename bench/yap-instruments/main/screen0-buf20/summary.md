# screen0-buf20

- 2026-10-24T03:57:55Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 622a8ea; APPS=cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=20
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display
- 2026-10-24T05:44:16Z Mac16,6 Apple M4 Max 64 GB
- commit 622a8ea; APPS=cairn ref RUNS=3 SECS=20 SCREEN=0 BUFFER_MS=20

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 5 | 4 |
| display_hz | 60 | 60 |
| presented_per_s | 59.34 (59.28–59.35) | 59.91 (59.74–59.97) |
| frame_interval_ms | 16.667 / 16.734 / 16.874 / 66.903 (n=5368) | 16.666 / 16.749 / 16.851 / 33.484 (n=4334) |
| share_intervals_over_1.5x_median | 0.0058 | 0.0021 |
| cadence_changes_share | 0.0119 | 0.0042 |
| level_to_present_call_ms | 8.314 / 14.971 / 16.592 / 30.017 (n=4500) | 8.155 / 14.957 / 16.803 / 27.903 (n=3600) |
| level_to_presented_ms | 18.689 / 30.344 / 33.343 / 79.31 (n=4500) | 19.178 / 29.559 / 32.706 / 43.941 (n=3600) |
| cpu_ms_per_s_total | 205.12 (165.38–267.02) | 81.63 (74.94–89.82) |
| cpu_ms_per_s_by_quarter_median | 249.7 → 127.4 → 262.6 → 228.2 | 85.0 → 80.7 → 79.5 → 84.7 |
| fp.time_on_glass_avg_ms | 16.714 (16.682–16.714) | 16.7 (16.683–16.726) |
| fp.time_on_glass_stddev_ms | 0.359 (0.119–0.361) | 0.251 (0.126–0.467) |
| fp.time_on_glass_max_ms | 33.333 (33.333–33.333) | 33.333 (33.333–33.333) |
| fp.total_end_to_end_avg_ms | 47.901 (43.24–48.15) | 48.637 (29.21–50.283) |
| fp.cpu_end_to_end_avg_ms | 0.413 (0.343–0.533) | 0.401 (0.335–0.449) |
| fp.gpu_end_to_end_avg_ms | 0.107 (0.106–0.108) | 0.066 (0.064–0.068) |
| fp.gpu_done_to_completed_avg_ms | 46.807 (42.318–47.291) | 47.824 (28.293–49.394) |
| fp.next_drawable_wait_avg_ms | 5.7 (0.012–10.173) | 3.777 (0.011–8.965) |
| fp.next_drawable_wait_max_ms | 32.907 (1.134–33.108) | 16.209 (0.049–24.943) |
| fp.late_on_glass_frames | 660 (3–953) | 1018.0 (2–1075) |
| fp.skipped_frames | 10 (9–11) | 0.0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 131.56, CairnYap 38.47, cairn.lean 17.55, cairn.render 23.96, com.apple.CFNetwork.CustomProtocols 0.06, com.apple.NSEventThread 0 | |
| CPU ms/s by thread, ref | Main Thread 48.17, YapRef 31.66, CVDisplayLink 0.77, com.apple.NSEventThread 0.08, com.apple.CFNetwork.CustomProtocols 0.0 | |

## hitches

| | cairn | ref |
|---|---|---|
| runs | 3 | 3 |
| hitches | 0 (0–0) | 0 (0–0) |
| hitch_time_ratio_ms_per_s | 0.0 (0.0–0.0) | 0.0 (0.0–0.0) |

Excluded runs: overlay/ref-3.json: 6 presents in the window
