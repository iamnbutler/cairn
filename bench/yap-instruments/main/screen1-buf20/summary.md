# screen1-buf20

- 2026-10-24T04:14:17Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 622a8ea; APPS=cairn ref RUNS=5 SECS=20 SCREEN=1 BUFFER_MS=20
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 4 | 5 |
| display_hz | 120 | 120 |
| presented_per_s | 117.84 (105.65–118.9) | 60.02 (59.96–60.05) |
| frame_interval_ms | 8.335 / 8.412 / 16.68 / 41.716 (n=8332) | 16.666 / 16.72 / 24.984 / 41.809 (n=5429) |
| share_intervals_over_1.5x_median | 0.0364 | 0.0094 |
| cadence_changes_share | 0.0664 | 0.0428 |
| level_to_present_call_ms | 4.492 / 9.395 / 14.756 / 29.67 (n=3600) | 8.418 / 14.919 / 16.902 / 18.36 (n=4500) |
| level_to_presented_ms | 11.203 / 15.456 / 28.745 / 47.592 (n=3600) | 12.266 / 19.055 / 24.512 / 43.81 (n=4500) |
| cpu_ms_per_s_total | 224.61 (118.34–270.13) | 71.51 (33.14–77.41) |
| cpu_ms_per_s_by_quarter_median | 257.4 → 234.9 → 199.8 → 192.0 | 65.4 → 67.4 → 61.8 → 78.0 |
| fp.time_on_glass_avg_ms | 8.439 (8.357–9.421) | 16.667 (16.663–16.672) |
| fp.time_on_glass_stddev_ms | 0.823 (0.254–2.957) | 0.527 (0.129–1.926) |
| fp.time_on_glass_max_ms | 25.0 (16.666–41.666) | 33.333 (25.0–37.5) |
| fp.total_end_to_end_avg_ms | 32.039 (31.758–32.343) | 20.276 (19.609–22.581) |
| fp.cpu_end_to_end_avg_ms | 0.312 (0.181–0.377) | 0.354 (0.171–0.37) |
| fp.gpu_end_to_end_avg_ms | 0.124 (0.11–0.131) | 0.066 (0.064–0.068) |
| fp.gpu_done_to_completed_avg_ms | 31.295 (31.048–31.49) | 19.628 (18.995–21.745) |
| fp.next_drawable_wait_avg_ms | 6.069 (3.691–7.648) | 0.009 (0.004–0.009) |
| fp.next_drawable_wait_max_ms | 29.443 (21.909–35.615) | 0.123 (0.01–0.328) |
| fp.late_on_glass_frames | 2080.0 (1900–2125) | 935 (926–964) |
| fp.skipped_frames | 13.0 (13–14) | 0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 126.03, CairnYap 55.04, cairn.render 23.74, cairn.lean 15.84, com.apple.NSEventThread 0.0, com.apple.CFNetwork.CustomProtocols 0.0 | |
| CPU ms/s by thread, ref | Main Thread 44.56, YapRef 26.28, CVDisplayLink 0.55, com.apple.CFNetwork.CustomProtocols 0, com.apple.NSEventThread 0 | |
