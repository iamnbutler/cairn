# fix-status-screen0

- 2026-10-24T06:08:51Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 622a8ea; APPS=cairnbase cairn RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=20
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | cairnbase |
|---|---|---|
| runs | 5 | 4 |
| display_hz | 60 | 60 |
| presented_per_s | 59.28 (59.25–59.36) | 59.28 (59.27–59.32) |
| frame_interval_ms | 16.667 / 16.744 / 16.879 / 66.696 (n=5364) | 16.666 / 16.733 / 16.888 / 83.377 (n=4292) |
| share_intervals_over_1.5x_median | 0.0073 | 0.007 |
| cadence_changes_share | 0.0146 | 0.014 |
| level_to_present_call_ms | 8.293 / 15.126 / 16.542 / 32.114 (n=4500) | 8.47 / 14.945 / 16.575 / 27.649 (n=3600) |
| level_to_presented_ms | 24.282 / 31.359 / 40.421 / 81.99 (n=4500) | 23.562 / 31.026 / 39.488 / 84.594 (n=3600) |
| cpu_ms_per_s_total | 97.94 (55.55–105.92) | 196.53 (116.6–256.88) |
| cpu_ms_per_s_by_quarter_median | 122.4 → 93.7 → 85.9 → 89.0 | 229.6 → 190.1 → 179.4 → 180.9 |
| fp.time_on_glass_avg_ms | 16.733 (16.7–16.751) | 16.73 (16.698–16.73) |
| fp.time_on_glass_stddev_ms | 0.506 (0.254–0.562) | 0.48 (0.238–0.481) |
| fp.time_on_glass_max_ms | 33.333 (33.333–33.333) | 33.333 (33.333–33.333) |
| fp.total_end_to_end_avg_ms | 48.485 (47.632–49.441) | 48.373 (47.734–50.452) |
| fp.cpu_end_to_end_avg_ms | 0.493 (0.233–0.535) | 0.38 (0.249–0.499) |
| fp.gpu_end_to_end_avg_ms | 0.107 (0.095–0.107) | 0.107 (0.107–0.108) |
| fp.gpu_done_to_completed_avg_ms | 47.381 (46.566–48.757) | 47.501 (46.766–49.444) |
| fp.next_drawable_wait_avg_ms | 10.023 (9.927–14.646) | 10.338 (0.372–14.735) |
| fp.next_drawable_wait_max_ms | 33.225 (33.083–33.299) | 33.156 (3.486–33.24) |
| fp.late_on_glass_frames | 945 (895–1008) | 958.0 (663–1067) |
| fp.skipped_frames | 9 (8–10) | 9.0 (9–11) |
| CPU ms/s by thread, cairn | CairnYap 42.78, cairn.render 20.81, cairn.lean 23.24, Main Thread 11.65, com.apple.CFNetwork.CustomProtocols 0.06, com.apple.NSEventThread 0.06 | |
| CPU ms/s by thread, cairnbase | Main Thread 127.55, CairnYap 36.25, cairn.lean 15.7, cairn.render 17.39, com.apple.CFNetwork.CustomProtocols 0.0 | |
