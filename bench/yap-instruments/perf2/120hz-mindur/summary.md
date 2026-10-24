# perf2-120hz-mindur

- 2026-10-24T12:56:52Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 6160ed3; APPS=cairnbase cairn ref RUNS=3 SECS=20 SCREEN=0 BUFFER_MS=20
- display 0 120 Built-in Retina Display

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## overlay

| | cairn | cairnbase | ref |
|---|---|---|---|
| runs | 3 | 3 | 3 |
| display_hz | 120 | 120 | 120 |
| presented_per_s | 59.45 (59.31–59.52) | 59.76 (59.75–59.77) | 59.98 (59.96–60.03) |
| frame_interval_ms | 16.665 / 16.719 / 16.811 / 66.704 (n=3226) | 16.666 / 16.73 / 25.046 / 41.618 (n=3243) | 16.666 / 16.705 / 16.783 / 33.354 (n=3256) |
| share_intervals_over_1.5x_median | 0.0037 | 0.0126 | 0.0018 |
| cadence_changes_share | 0.0093 | 0.0491 | 0.0126 |
| level_to_present_call_ms | 8.232 / 14.899 / 16.586 / 18.375 (n=2700) | 8.169 / 14.798 / 16.388 / 17.108 (n=2700) | 8.118 / 14.459 / 16.692 / 18.138 (n=2700) |
| level_to_presented_ms | 20.208 / 29.428 / 33.246 / 73.823 (n=2700) | 16.483 / 23.219 / 24.993 / 41.406 (n=2700) | 11.044 / 17.424 / 19.604 / 24.826 (n=2700) |
| cpu_ms_per_s_total | 58.62 (44.73–65.43) | 52.46 (50.2–74.02) | 49.91 (47.44–51.25) |
| cpu_ms_per_s_by_quarter_median | 68.0 → 40.0 → 66.0 → 50.1 | 84.4 → 60.3 → 53.2 → 43.3 | 46.4 → 58.3 → 39.1 → 59.0 |
| fp.time_on_glass_avg_ms | 16.675 (16.674–16.675) | 16.666 (16.658–16.666) | 16.666 (16.666–16.67) |
| fp.time_on_glass_stddev_ms | 0.063 (0.06–0.064) | 0.831 (0.797–1.342) | 0.423 (0.187–0.574) |
| fp.time_on_glass_max_ms | 25.0 (25.0–25.0) | 25.0 (25.0–25.0) | 33.333 (29.166–33.333) |
| fp.total_end_to_end_avg_ms | 43.883 (37.728–48.842) | 24.871 (24.827–24.909) | 19.479 (19.466–19.542) |
| fp.cpu_end_to_end_avg_ms | 0.295 (0.272–0.334) | 0.301 (0.266–0.376) | 0.176 (0.174–0.196) |
| fp.gpu_end_to_end_avg_ms | 0.107 (0.104–0.109) | 0.105 (0.105–0.108) | 0.064 (0.064–0.065) |
| fp.gpu_done_to_completed_avg_ms | 43.061 (36.88–48.052) | 24.015 (23.956–24.112) | 18.867 (18.864–18.896) |
| fp.next_drawable_wait_avg_ms | 0.255 (0.011–0.75) | 0.011 (0.009–0.013) | 0.004 (0.003–0.004) |
| fp.next_drawable_wait_max_ms | 2.863 (1.303–6.434) | 1.682 (0.509–1.836) | 0.318 (0.315–0.329) |
| fp.late_on_glass_frames | 5 (5–5) | 977 (974–987) | 903 (893–953) |
| fp.skipped_frames | 9 (8–12) | 4 (4–4) | 0 (0–0) |
| CPU ms/s by thread, cairn | CairnYap 26.66, cairn.render 12.81, cairn.lean 11.92, Main Thread 6.9, com.apple.NSEventThread 0.06, com.apple.CFNetwork.CustomProtocols 0.06 | | |
| CPU ms/s by thread, cairnbase | CairnYap 24.36, cairn.lean 11.54, cairn.render 11.82, Main Thread 6.13, com.apple.CFNetwork.CustomProtocols 0.06 | | |
| CPU ms/s by thread, ref | Main Thread 31.09, YapRef 16.12, CVDisplayLink 0.61, com.apple.NSEventThread 0 | | |
