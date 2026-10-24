#!/usr/bin/env python3
"""Aggregates a yap-instruments.sh output directory into summary.md, runs.csv and summary.json.

    report.py OUT/TAG

summary.md and runs.csv are what bench/yap-instruments/ keeps: the tables, and one row per run
(warm-ups and excluded runs included, with their status) holding every per-run number the
tables summarise. The per-run JSON (with the per-frame samples) stays in bench/out/.

Run 0 of every app is the warm-up and is left out. Per-frame and per-trial samples are pooled
across runs (median, p90, p99, max); per-run numbers (frames per second, CPU, memory) are given
as the median across runs with the range.
"""
import csv
import glob
import json
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(__file__))
from analyze import dist  # noqa: E402


EXCLUDED = []


def load(out, suite):
    by = {}
    for f in sorted(glob.glob(f"{out}/{suite}/*.json")):
        app, n = os.path.basename(f)[:-5].rsplit("-", 1)
        if int(n) == 0:
            continue
        r = json.load(open(f))["result"]
        if "error" in r:
            print(f"skipping {f}: {r['error']}", file=sys.stderr)
            EXCLUDED.append(f"{suite}/{os.path.basename(f)}: {r['error']}")
            continue
        if suite in ("overlay", "hitches") and r.get("per_frame", {}).get("presented_per_s", 99) < 5:
            # The panel was not on glass for this run (Core Animation saw almost no presents),
            # so there is nothing to compare; it is counted in summary.json's "excluded".
            print(f"skipping {f}: {r['per_frame']['presented']} presents", file=sys.stderr)
            EXCLUDED.append(f"{suite}/{os.path.basename(f)}: {r['per_frame']['presented']} presents in the window")
            continue
        by.setdefault(app, []).append(r)
    return by


def spread(xs, nd=2):
    xs = [x for x in xs if x is not None]
    if not xs:
        return None
    return {"median": round(statistics.median(xs), nd), "min": round(min(xs), nd), "max": round(max(xs), nd), "runs": len(xs)}


def get(d, path):
    for k in path.split("."):
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def overlay(rs, out):
    def pooled(k):
        return [x for r in rs for x in r["samples"][k]]
    iv = pooled("interval_ms")
    try:
        hz = int(open(f"{out}/refresh-hz").read().split()[0])
    except (OSError, ValueError, IndexError):
        hz = round(1000 / statistics.median([r["per_frame"]["refresh_ms"] for r in rs if r["per_frame"].get("refresh_ms")]))
    refresh = 1000 / hz
    own = statistics.median(pooled("interval_ms")) if iv else refresh
    s = {
        "runs": len(rs),
        "display_hz": hz,
        "presented_per_s": spread([r["per_frame"]["presented_per_s"] for r in rs]),
        "frame_interval_ms": dist(iv),
        # Frames held more than half again the app's own usual frame time (its median interval).
        "share_intervals_over_1.5x_median": round(sum(1 for x in iv if x > 1.5 * own) / len(iv), 4) if iv else None,
        # How often the time between frames changes from one frame to the next by more than
        # half a refresh: uneven motion even when no frame is "late".
        "cadence_changes_share": round(sum(sum(1 for a, b in zip(r["samples"]["interval_ms"], r["samples"]["interval_ms"][1:])
                                               if abs(b - a) > refresh / 2) for r in rs)
                                       / max(1, sum(len(r["samples"]["interval_ms"]) - 1 for r in rs)), 4),
        "level_to_present_call_ms": dist(pooled("level_to_present_call_ms")),
        "level_to_presented_ms": dist(pooled("level_to_presented_ms")),
        "cpu_ms_per_s_total": spread([r["cpu_ms_per_s_total"] for r in rs]),
    }
    qs = [r["cpu_ms_per_s_by_quarter"] for r in rs if "cpu_ms_per_s_by_quarter" in r]
    if qs:
        s["cpu_ms_per_s_by_quarter_median"] = " → ".join(str(round(statistics.median(q[i] for q in qs), 1)) for i in range(4))
    for k in ["time_on_glass_avg_ms", "time_on_glass_stddev_ms", "time_on_glass_max_ms", "total_end_to_end_avg_ms",
              "cpu_end_to_end_avg_ms", "gpu_end_to_end_avg_ms", "gpu_done_to_completed_avg_ms",
              "next_drawable_wait_avg_ms", "next_drawable_wait_max_ms", "late_on_glass_frames", "skipped_frames"]:
        s["fp." + k] = spread([get(r, "framepacing." + k) for r in rs], 3)
    threads = {}
    for r in rs:
        for k, v in r["cpu_ms_per_s_by_thread"].items():
            threads.setdefault(k, []).append(v)
    s["cpu_ms_per_s_by_thread"] = {k: spread(v + [0] * (len(rs) - len(v))) for k, v in threads.items()}
    return s


def hitches(rs):
    return {"runs": len(rs), "hitches": spread([r["hitches"] for r in rs]),
            "hitch_time_ratio_ms_per_s": spread([r["hitch_time_ratio_ms_per_s"] for r in rs], 3)}


def latency(rs):
    return {"runs": len(rs), "key_up_to_typed_ms": dist([x for r in rs for x in r["samples_ms"]]),
            "run_medians_ms": spread([r["key_up_to_typed_ms"].get("median") for r in rs], 3)}


def idle(rs):
    return {"runs": len(rs), "window_s": spread([r["window_s"] for r in rs], 1),
            "cpu_percent": spread([r["cpu_percent"] for r in rs], 3),
            "wakeups_per_s": spread([r["wakeups_per_s"] for r in rs]),
            "footprint_mb_end": spread([r["footprint_mb"]["end"] for r in rs]),
            "footprint_mb_max": spread([r["footprint_mb"]["max"] for r in rs]),
            "threads_end": spread([r["threads_end"] for r in rs], 0)}


def launch(rs):
    return {"runs": len(rs), "start_to_did_finish_launching_ms": spread([r["start_to_did_finish_launching_ms"] for r in rs], 1),
            "start_to_ready_ms": spread([r["start_to_ready_ms"] for r in rs], 1)}


def profile(rs):
    s = {"runs": len(rs), "cpu_ms_per_s_total": spread([r["cpu_ms_per_s_total"] for r in rs])}
    for k in rs[0].get("named_inclusive_ms_per_s", {}):
        s[k + " ms/s"] = spread([r["named_inclusive_ms_per_s"][k] for r in rs])
    threads = {}
    for r in rs:
        for k, v in r["cpu_ms_per_s_by_thread"].items():
            threads.setdefault(k, []).append(v)
    s["cpu_ms_per_s_by_thread"] = {k: spread(v + [0] * (len(rs) - len(v))) for k, v in threads.items()}
    return s


def thread_cols(r, key="cpu_ms_per_s_by_thread"):
    th = r.get(key, {})
    named = {"Main Thread": "cpu_main", "cairn.render": "cpu_render", "cairn.lean": "cpu_lean"}
    row = {c: th.get(t, 0) for t, c in named.items()}
    row["cpu_other_threads"] = round(sum(v for t, v in th.items() if t not in named), 2)
    return row


def per_run(suite, r, hz):
    """The per-run numbers of one result, flat, for runs.csv."""
    if "error" in r:
        return {}
    if suite == "overlay":
        iv = r["samples"]["interval_ms"]
        own = statistics.median(iv) if iv else None
        row = {"frames_per_s": r["per_frame"]["presented_per_s"]}
        for name, d in (("interval", r["per_frame"]["interval_ms"]), ("level_to_call", r["level_to_present_call_ms"]),
                        ("level_to_glass", r["level_to_presented_ms"])):
            for q in ("median", "p90", "p99", "max"):
                row[f"{name}_{q}_ms"] = d.get(q)
        row["held_long_share"] = round(sum(1 for x in iv if x > 1.5 * own) / len(iv), 4) if iv else None
        row["cadence_changes_share"] = (round(sum(1 for a, b in zip(iv, iv[1:]) if abs(b - a) > 500 / hz) / (len(iv) - 1), 4)
                                        if hz and len(iv) > 1 else None)
        row["cpu_ms_per_s"] = r["cpu_ms_per_s_total"]
        row.update(thread_cols(r))
        fp = r.get("framepacing", {})
        for k in ["time_on_glass_avg_ms", "time_on_glass_stddev_ms", "time_on_glass_max_ms", "total_end_to_end_avg_ms",
                  "gpu_done_to_completed_avg_ms", "next_drawable_wait_avg_ms", "next_drawable_wait_max_ms",
                  "late_on_glass_frames", "skipped_frames"]:
            row["fp_" + k] = fp.get(k)
        return row
    if suite == "hitches":
        return {"hitches": r["hitches"], "hitch_ms_per_s": r["hitch_time_ratio_ms_per_s"]}
    if suite == "latency":
        d = r["key_up_to_typed_ms"]
        return {"trials": r["trials"], **{f"typed_{q}_ms": d.get(q) for q in ("median", "p90", "p99", "max")}}
    if suite in ("idle", "menu"):
        return {"window_s": r["window_s"], "cpu_percent": r["cpu_percent"], "wakeups_per_s": r["wakeups_per_s"],
                "footprint_mb_end": r["footprint_mb"]["end"], "footprint_mb_max": r["footprint_mb"]["max"],
                "threads": r["threads_end"]}
    if suite == "launch":
        return {"did_finish_launching_ms": r["start_to_did_finish_launching_ms"], "ready_ms": r["start_to_ready_ms"]}
    if suite == "profile":
        row = {"cpu_ms_per_s": r["cpu_ms_per_s_total"], **thread_cols(r)}
        row.update({k.replace(" ", "_").replace(".", "_") + "_ms_per_s": v
                    for k, v in r.get("named_inclusive_ms_per_s", {}).items()})
        return row
    return {}


def write_csv(out):
    """runs.csv: one row per run of every suite, in run order, with the load when it started."""
    load = {}
    try:
        for line in open(f"{out}/runs.tsv"):
            f = line.rstrip("\n").split("\t")
            if len(f) == 5 and f[4].startswith("load"):
                load[(f[1], f[2], f[3])] = f[4].split()[2]
    except OSError:
        pass
    try:
        hz = int(open(f"{out}/refresh-hz").read().split()[0])
    except (OSError, ValueError, IndexError):
        hz = None
    rows = []
    for suite in SUITES:
        for f in sorted(glob.glob(f"{out}/{suite}/*.json"), key=lambda f: int(f[:-5].rsplit("-", 1)[1])):
            app, n = os.path.basename(f)[:-5].rsplit("-", 1)
            r = json.load(open(f))["result"]
            name = f"{suite}/{os.path.basename(f)}"
            status = "warm-up" if int(n) == 0 else next(("excluded: " + e.split(": ", 1)[1] for e in EXCLUDED
                                                          if e.startswith(name + ":")), "included")
            rows.append({"suite": suite, "app": app, "run": int(n), "status": status,
                         "load1": load.get((suite, app, n)), **per_run(suite, r, hz)})
    seen = {(r["suite"], r["app"], str(r["run"])) for r in rows}
    for (suite, app, n), l1 in load.items():
        if (suite, app, n) not in seen:
            # analyze.py exits non-zero only when the trace has no levels signposts: Instruments
            # started recording after the bench began, so there is no window to measure.
            rows.append({"suite": suite, "app": app, "run": int(n), "load1": l1,
                         "status": "excluded: no levels signposts (recording started late) so no result"})
    order = {k: i for i, k in enumerate(load)}
    rows.sort(key=lambda r: order.get((r["suite"], r["app"], str(r["run"])), len(order)))
    cols = []
    for r in rows:
        cols += [k for k in r if k not in cols]
    with open(f"{out}/runs.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


SUITES = {"overlay": overlay, "hitches": hitches, "latency": latency, "idle": idle, "menu": idle, "launch": launch,
          "profile": profile}


def fmt(v):
    if isinstance(v, dict):
        if "median" in v and "p90" in v:
            return f"{v['median']} / {v['p90']} / {v['p99']} / {v['max']} (n={v['n']})"
        if "median" in v:
            return f"{v['median']} ({v['min']}–{v['max']})"
        if v.get("n") == 0:
            return "–"
    return str(v)


def main():
    out = sys.argv[1]
    summary = {}
    for suite, fn in SUITES.items():
        by = load(out, suite)
        if by:
            summary[suite] = {app: (fn(rs, out) if suite == "overlay" else fn(rs)) for app, rs in sorted(by.items())}
    summary["excluded"] = EXCLUDED
    json.dump(summary, open(f"{out}/summary.json", "w"), indent=1)
    del summary["excluded"]
    try:
        header = [l.rstrip("\n").lstrip("# ") for l in open(f"{out}/runs.tsv") if l.startswith(("#", "display"))]
    except OSError:
        header = []
    lines = [f"# {os.path.basename(os.path.normpath(out))}", ""] + [f"- {h}" for h in dict.fromkeys(header)] + ["",
             "Distributions: median / p90 / p99 / max (n), pooled over the included runs. Per-run values:",
             "median (min–max) over runs. runs.csv has every run, one row each.", ""]
    for suite, apps in summary.items():
        names = list(apps)
        lines += [f"## {suite}", "", "| | " + " | ".join(names) + " |", "|---" * (len(names) + 1) + "|"]
        keys = [k for k in apps[names[0]] if k != "cpu_ms_per_s_by_thread"]
        for k in keys:
            lines.append(f"| {k} | " + " | ".join(fmt(apps[a].get(k)) for a in names) + " |")
        if "cpu_ms_per_s_by_thread" in apps[names[0]]:
            for a in names:
                th = ", ".join(f"{k} {v['median']}" for k, v in apps[a]["cpu_ms_per_s_by_thread"].items())
                lines.append(f"| CPU ms/s by thread, {a} | {th} |" + " |" * (len(names) - 1))
        lines.append("")
    if EXCLUDED:
        lines += ["Excluded runs: " + "; ".join(EXCLUDED), ""]
    open(f"{out}/summary.md", "w").write("\n".join(lines))
    write_csv(out)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
