# screen1-buf20

- 2026-10-24T03:19:55Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit fdafb99; APPS=cairn ref RUNS=5 SECS=20 SCREEN=1 BUFFER_MS=20

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 5 | 4 |
| display_hz | 120 | 120 |
| presented_per_s | 52.06 (51.79–52.43) | 59.97 (59.96–60.01) |
| frame_interval_ms | 16.7 / 25.081 / 33.409 / 58.286 (n=4712) | 16.666 / 16.703 / 16.76 / 38.412 (n=4341) |
| share_intervals_over_1.5x_median | 0.1426 | 0.0012 |
| cadence_changes_share | 0.7383 | 0.0081 |
| level_to_present_call_ms | 4.732 / 8.137 / 9.011 / 10.168 (n=4500) | 7.997 / 14.745 / 16.639 / 18.257 (n=3600) |
| level_to_presented_ms | 12.98 / 31.713 / 33.784 / 57.943 (n=4500) | 11.753 / 18.667 / 20.771 / 35.614 (n=3600) |
| cpu_ms_per_s_total | 161.4 (94.43–183.68) | 37.27 (33.19–43.79) |
| fp.time_on_glass_avg_ms | 19.045 (18.922–19.143) | 16.666 (16.666–16.666) |
| fp.time_on_glass_stddev_ms | 6.608 (6.116–6.923) | 0.278 (0.0–0.485) |
| fp.time_on_glass_max_ms | 41.666 (41.666–41.666) | 29.166 (16.667–41.666) |
| fp.total_end_to_end_avg_ms | 24.351 (23.955–24.653) | 20.437 (19.654–21.149) |
| fp.cpu_end_to_end_avg_ms | 0.282 (0.179–0.323) | 0.169 (0.161–0.187) |
| fp.gpu_end_to_end_avg_ms | 0.071 (0.069–0.073) | 0.064 (0.063–0.064) |
| fp.gpu_done_to_completed_avg_ms | 23.598 (23.352–23.91) | 19.824 (19.167–20.549) |
| fp.next_drawable_wait_avg_ms | 0.012 (0.007–0.014) | 0.004 (0.003–0.005) |
| fp.next_drawable_wait_max_ms | 0.74 (0.352–1.496) | 0.171 (0.013–0.342) |
| fp.late_on_glass_frames | 753 (692–794) | 933.0 (929–980) |
| fp.skipped_frames | 5 (4–6) | 0.0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 105.83, CairnYap 23.25, cairn.render 5.96, cairn.lean 15.69, com.apple.NSEventThread 0, com.apple.CFNetwork.CustomProtocols 0.06 | |
| CPU ms/s by thread, ref | Main Thread 25.38, YapRef 13.22, CVDisplayLink 0.64, com.apple.NSEventThread 0.0 | |
