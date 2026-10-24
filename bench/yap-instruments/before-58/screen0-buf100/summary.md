# screen0-buf100

- 2026-10-24T03:35:00Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit fdafb99; APPS=cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=100

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | ref |
|---|---|---|
| runs | 5 | 5 |
| display_hz | 60 | 60 |
| presented_per_s | 12.53 (12.42–13.41) | 59.86 (59.75–59.97) |
| frame_interval_ms | 99.801 / 100.097 / 116.701 / 149.978 (n=1151) | 16.666 / 16.712 / 16.82 / 33.51 (n=5414) |
| share_intervals_over_1.5x_median | 0.0009 | 0.0026 |
| cadence_changes_share | 0.6239 | 0.0052 |
| level_to_present_call_ms | 9.634 / 15.393 / 17.055 / 17.959 (n=900) | 7.731 / 14.317 / 17.458 / 32.73 (n=900) |
| level_to_presented_ms | 42.25 / 48.777 / 55.878 / 81.465 (n=900) | 20.019 / 30.178 / 32.614 / 48.977 (n=900) |
| cpu_ms_per_s_total | 43.66 (30.48–72.71) | 55.11 (29.83–58.59) |
| fp.time_on_glass_avg_ms | 79.775 (74.304–80.473) | 16.718 (16.684–16.734) |
| fp.time_on_glass_stddev_ms | 25.991 (25.827–30.984) | 0.384 (0.125–0.508) |
| fp.time_on_glass_max_ms | 116.666 (116.666–116.666) | 33.333 (33.333–33.333) |
| fp.total_end_to_end_avg_ms | 33.28 (33.141–33.465) | 43.824 (30.087–48.833) |
| fp.cpu_end_to_end_avg_ms | 0.251 (0.244–0.477) | 0.226 (0.188–0.313) |
| fp.gpu_end_to_end_avg_ms | 0.066 (0.066–0.068) | 0.064 (0.064–0.065) |
| fp.gpu_done_to_completed_avg_ms | 32.436 (32.294–32.717) | 43.188 (29.368–48.073) |
| fp.next_drawable_wait_avg_ms | 0.021 (0.019–0.054) | 6.983 (0.007–11.863) |
| fp.next_drawable_wait_max_ms | 0.37 (0.312–1.545) | 24.169 (0.641–32.588) |
| fp.late_on_glass_frames | 2 (0–3) | 1014 (440–1021) |
| fp.skipped_frames | 1 (1–2) | 0 (0–0) |
| CPU ms/s by thread, cairn | Main Thread 25.5, CairnYap 6.79, cairn.lean 3.64, cairn.render 6.29, com.apple.CFNetwork.CustomProtocols 0.06, com.apple.NSEventThread 0.06 | |
| CPU ms/s by thread, ref | Main Thread 28.16, YapRef 24.96, CVDisplayLink 0.22, com.apple.NSEventThread 0.06, com.apple.CFNetwork.CustomProtocols 0 | |
