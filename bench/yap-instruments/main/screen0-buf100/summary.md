# screen0-buf100

- 2026-10-24T04:30:23Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 622a8ea; APPS=cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=100
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 5 | 5 |
| display_hz | 60 | 60 |
| presented_per_s | 59.26 (59.16–59.31) | 59.89 (59.76–59.94) |
| frame_interval_ms | 16.666 / 16.719 / 16.871 / 83.362 (n=5361) | 16.666 / 16.717 / 16.844 / 33.492 (n=5417) |
| share_intervals_over_1.5x_median | 0.0063 | 0.0024 |
| cadence_changes_share | 0.0127 | 0.0048 |
| level_to_present_call_ms | 7.694 / 14.753 / 16.438 / 29.752 (n=900) | 7.249 / 14.883 / 16.58 / 22.63 (n=900) |
| level_to_presented_ms | 22.886 / 30.875 / 40.159 / 80.893 (n=900) | 23.372 / 30.427 / 32.758 / 38.814 (n=900) |
| cpu_ms_per_s_total | 60.76 (54.69–132.54) | 56.91 (26.56–62.26) |
| cpu_ms_per_s_by_quarter_median | 90.5 → 48.6 → 47.5 → 80.2 | 43.0 → 47.0 → 50.3 → 45.5 |
| fp.time_on_glass_avg_ms | 16.71 (16.697–16.73) | 16.714 (16.682–16.73) |
| fp.time_on_glass_stddev_ms | 0.345 (0.237–0.479) | 0.372 (0.122–0.496) |
| fp.time_on_glass_max_ms | 33.333 (33.333–33.333) | 33.333 (33.333–33.333) |
| fp.total_end_to_end_avg_ms | 47.847 (47.704–56.954) | 48.475 (48.337–53.46) |
| fp.cpu_end_to_end_avg_ms | 0.273 (0.23–0.452) | 0.24 (0.192–0.323) |
| fp.gpu_end_to_end_avg_ms | 0.107 (0.107–0.111) | 0.065 (0.064–0.067) |
| fp.gpu_done_to_completed_avg_ms | 46.924 (46.748–56.186) | 47.718 (47.642–52.794) |
| fp.next_drawable_wait_avg_ms | 5.754 (1.228–10.299) | 11.841 (6.509–11.988) |
| fp.next_drawable_wait_max_ms | 33.133 (17.209–33.245) | 33.023 (11.843–33.111) |
| fp.late_on_glass_frames | 951 (658–956) | 1017 (1016–1028) |
| fp.skipped_frames | 10 (9–13) | 0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 31.96, CairnYap 24.61, cairn.render 10.65, cairn.lean 3.98, com.apple.NSEventThread 0.06, com.apple.CFNetwork.CustomProtocols 0 | |
| CPU ms/s by thread, ref | Main Thread 32.01, YapRef 22.41, CVDisplayLink 0.33, com.apple.NSEventThread 0, com.apple.CFNetwork.CustomProtocols 0 | |
