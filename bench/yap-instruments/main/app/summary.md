# app

- 2026-10-24T04:46:41Z Mac16,6 Apple M4 Max 64 GB
- macOS 27.0.1 (26A434); xctrace version 27.1 (27A9275)
- commit 622a8ea; APPS=cairn ref RUNS=5 SECS=20 SCREEN=0 BUFFER_MS=20
- display 0 60 Studio Display
- display 1 120 Built-in Retina Display
- 2026-10-24T05:14:45Z Mac16,6 Apple M4 Max 64 GB
- commit 622a8ea; APPS=cairn ref RUNS=3 SECS=20 SCREEN=0 BUFFER_MS=20
- 2026-10-24T05:33:43Z Mac16,6 Apple M4 Max 64 GB

Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:
median (min–max) over runs. runs.csv has every run, one row each.

## latency

| | cairn | ref |
|---|---|---|
| runs | 5 | 5 |
| key_up_to_typed_ms | 6.284 / 10.966 / 13.198 / 13.198 (n=100) | 4.617 / 19.798 / 22.671 / 22.671 (n=83) |
| run_medians_ms | 8.361 (2.029–8.87) | 7.46 (3.975–16.822) |

## idle

| | cairn | ref |
|---|---|---|
| runs | 3 | 3 |
| window_s | 99.9 (99.7–100.3) | 99.7 (99.7–99.7) |
| cpu_percent | 0.205 (0.187–0.229) | 0.012 (0.009–0.013) |
| wakeups_per_s | 6.53 (6.52–6.54) | 0.48 (0.48–0.48) |
| footprint_mb_end | 16.3 (16.11–16.3) | 17.61 (17.59–17.7) |
| footprint_mb_max | 16.3 (16.11–16.3) | 17.61 (17.59–17.7) |
| threads_end | 8 (8–8) | 4 (4–5) |

## menu

| | cairn | ref |
|---|---|---|
| runs | 3 | 3 |
| window_s | 51.3 (51.2–51.7) | 23.9 (23.8–24.1) |
| cpu_percent | 0.04 (0.037–0.047) | 0.002 (0.002–0.003) |
| wakeups_per_s | 4.39 (4.31–4.54) | 0.17 (0.17–0.17) |
| footprint_mb_end | 21.31 (21.08–21.49) | 22.53 (22.49–22.84) |
| footprint_mb_max | 21.55 (21.3–21.7) | 22.63 (22.55–22.88) |
| threads_end | 8 (8–8) | 3 (3–3) |

## launch

| | cairn | ref |
|---|---|---|
| runs | 5 | 5 |
| start_to_did_finish_launching_ms | 47.6 (46.5–54.0) | 70.5 (66.1–82.5) |
| start_to_ready_ms | 61.0 (58.9–74.0) | 91.6 (84.8–111.8) |
