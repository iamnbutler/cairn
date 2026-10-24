# screen0-buf20

- 2026-10-24T03:03:49Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit fdafb99; APPS=cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=20
- 2026-10-24T03:51:24Z Mac16,6 Apple M4 Max 64 GB
- commit fdafb99; APPS=cairn ref RUNS=3 SECS=20 SCREEN=0 BUFFER_MS=20

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 5 | 5 |
| display_hz | 60 | 60 |
| presented_per_s | 48.68 (48.57–49.39) | 59.88 (59.77–59.9) |
| frame_interval_ms | 16.676 / 33.334 / 33.421 / 83.346 (n=4418) | 16.666 / 16.708 / 16.786 / 33.462 (n=5414) |
| share_intervals_over_1.5x_median | 0.2189 | 0.0026 |
| cadence_changes_share | 0.3886 | 0.0052 |
| level_to_present_call_ms | 8.84 / 15.858 / 16.993 / 18.465 (n=4500) | 7.865 / 14.908 / 16.611 / 31.195 (n=4500) |
| level_to_presented_ms | 11.693 / 30.242 / 48.71 / 76.899 (n=4500) | 20.116 / 29.741 / 32.759 / 47.444 (n=4500) |
| cpu_ms_per_s_total | 109.56 (84.48–172.39) | 40.07 (35.63–47.36) |
| fp.time_on_glass_avg_ms | 20.331 (20.021–20.401) | 16.7 (16.696–16.731) |
| fp.time_on_glass_stddev_ms | 6.907 (6.651–6.925) | 0.252 (0.234–0.5) |
| fp.time_on_glass_max_ms | 33.333 (33.333–50.0) | 33.333 (33.333–33.333) |
| fp.total_end_to_end_avg_ms | 34.365 (33.362–38.1) | 48.401 (28.578–52.638) |
| fp.cpu_end_to_end_avg_ms | 0.208 (0.194–0.344) | 0.192 (0.184–0.291) |
| fp.gpu_end_to_end_avg_ms | 0.066 (0.066–0.07) | 0.065 (0.064–0.065) |
| fp.gpu_done_to_completed_avg_ms | 33.541 (32.578–37.404) | 47.739 (27.916–51.978) |
| fp.next_drawable_wait_avg_ms | 0.013 (0.008–0.015) | 7.109 (0.006–11.89) |
| fp.next_drawable_wait_max_ms | 0.665 (0.328–1.211) | 23.639 (0.344–33.186) |
| fp.late_on_glass_frames | 8 (5–17) | 1017 (311–1075) |
| fp.skipped_frames | 7 (6–8) | 0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 70.48, cairn.render 5.41, CairnYap 12.64, cairn.lean 10.22, com.apple.CFNetwork.CustomProtocols 0, com.apple.NSEventThread 0 | |
| CPU ms/s by thread, ref | Main Thread 26.67, YapRef 16.29, CVDisplayLink 0.72, com.apple.CFNetwork.CustomProtocols 0 | |
