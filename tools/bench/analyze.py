#!/usr/bin/env python3
"""Summarises one Instruments trace of the Yap bench (bench/yap-instruments.md) as JSON.

    analyze.py SUITE TRACE [--warm SECONDS]

Every number here is read from tables Instruments wrote: the timestamps of the bench's
os_signposts (subsystem dev.yap.bench), Core Animation's and FramePacing's own signposts for
the app's CAMetalLayer, the presented-drawable events, the time profiler's samples, the
activity monitor's process samples and the launch lifecycle. Nothing comes from the apps' own
timers.

Suites (and the template the trace was recorded with):
  overlay   Metal System Trace + os_signpost   frame pacing, level -> present, CPU by thread
  hitches   Animation Hitches + os_signpost    hitches and the hitch time ratio
  latency   Logging                            key-up -> typed (stubbed) per trial
  idle      Activity Monitor                   CPU, wakeups, memory
  launch    App Launch + os_signpost           process start -> didFinishLaunching -> ready
"""
import json
import re
import statistics
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
import xctable  # noqa: E402

NS = 1e9


def pct(xs, p):
    """Nearest-rank percentile (p in 0..100) of a non-empty list."""
    s = sorted(xs)
    if not s:
        return None
    k = max(0, min(len(s) - 1, int(round(p / 100 * len(s) + 0.5)) - 1))
    return s[k]


def dist(xs, scale=1.0, nd=3):
    if not xs:
        return {"n": 0}
    v = [x * scale for x in xs]
    return {"n": len(v), "median": round(statistics.median(v), nd), "p90": round(pct(v, 90), nd),
            "p99": round(pct(v, 99), nd), "max": round(max(v), nd), "mean": round(statistics.fmean(v), nd)}


def pid_of(cell):
    if cell is None:
        return None
    p = cell.find("pid")
    return int(p.raw) if p is not None and p.raw else None


def thread_name(cell):
    if cell is None or not cell.fmt:
        return "?"
    name = cell.fmt.split(" (0x")[0]
    return name


class Trace:
    def __init__(self, path):
        self.path = path
        self.info = xctable.toc_info(path)
        self.pid = int(self.info["process"].get("pid", 0))
        self._sp = None

    def rows(self, schema, pred=""):
        return xctable.rows(self.path, schema, pred=pred)

    def signposts(self):
        """The general os-signpost table, our process only: (time ns, subsystem, name, type, id, message)."""
        if self._sp is None:
            out = []
            for r in self.rows("os-signpost", 'not(@subsystem) and not(@category)'):
                if pid_of(r.get("process")) != self.pid:
                    continue
                out.append((r["time"].num(), r["subsystem"].raw if r.get("subsystem") else None,
                            r["name"].raw if r.get("name") else None,
                            r["event-type"].raw if r.get("event-type") else None,
                            r["identifier"].raw if r.get("identifier") else None,
                            r["message"].fmt if r.get("message") is not None else ""))
            self._sp = out
        return self._sp

    def bench(self, name, kind=None):
        return [s for s in self.signposts() if s[1] == "dev.yap.bench" and s[2] == name and (kind is None or s[3] == kind)]


def framepacing(msg):
    """The numbers in a FramePacing stats message, by label."""
    out = {}
    # "Frames (count, frames) =45", "Frames_CPUEndToEndWalltime (CPUEndToEndWalltime average, ms) =0.2274"
    for m in re.finditer(r"(\w+) \((\w+)(?: (average|min|max|stddev))?, [^)]*\) =(-?[0-9.,]+)", msg):
        key = m.group(2) + "." + m.group(3) if m.group(3) else m.group(1)
        out[key] = float(m.group(4).replace(",", ""))
    return out


def window(t, warm):
    b = t.bench("levels", "Begin")
    e = t.bench("levels", "End")
    if not b or not e:
        raise SystemExit(f"{t.path}: no levels interval signposts")
    return b[0][0] + warm * NS, e[0][0]


def overlay(t, warm):
    lo, hi = window(t, warm)
    secs = (hi - lo) / NS
    sp = t.signposts()
    # FramePacing's per-second stats for the app's CAMetalLayer(s). Each window is one
    # signpost interval whose Begin and End carry the same message; read the End.
    def fpstats(name):
        return [framepacing(s[5]) for s in sp if s[1] == "com.apple.FramePacing" and s[2] == name
                and s[3] == "End" and lo + NS <= s[0] <= hi]
    stats = [s for s in fpstats("PresentedFrameStats") if s.get("Frames", 0) > 0]
    late, skipped = fpstats("LateOnGlassPresentStats"), fpstats("SkippedFrameStats")

    def avg(k):
        return round(statistics.fmean(s.get(k, 0) for s in stats), 4)
    fp = {}
    if stats:
        fp = {
            "windows": len(stats),
            "frames_per_window": dist([s["Frames"] for s in stats], nd=1),
            "time_on_glass_avg_ms": avg("TimeOnGlass.average"),
            "time_on_glass_min_ms": round(min(s["TimeOnGlass.min"] for s in stats), 3),
            "time_on_glass_max_ms": round(max(s["TimeOnGlass.max"] for s in stats), 3),
            "time_on_glass_stddev_ms": avg("TimeOnGlass.stddev"),
            "total_end_to_end_avg_ms": avg("TotalEndToEndWalltime.average"),
            "cpu_end_to_end_avg_ms": avg("CPUEndToEndWalltime.average"),
            "gpu_end_to_end_avg_ms": avg("GPUEndToEndWalltime.average"),
            "gpu_done_to_completed_avg_ms": avg("GPUDoneToCompletedWalltime.average"),
            "next_drawable_wait_avg_ms": avg("NextDrawableWaitWaltime.average"),
            "next_drawable_wait_max_ms": round(max(s["NextDrawableWaitWaltime.max"] for s in stats), 4),
            "late_on_glass_frames": int(sum(s.get("LateOnGlassPresents", 0) for s in late)),
            "skipped_frames": int(sum(s.get("Frames", 0) for s in skipped)),
        }
    # Every presented drawable of the process (Core Animation's presented events).
    presented = sorted(r["timestamp"].num() for r in t.rows("ca-client-presented-handler")
                       if pid_of(r.get("process")) == t.pid)
    shown = [x for x in presented if lo <= x <= hi]
    iv = [(b - a) / 1e6 for a, b in zip(shown, shown[1:])]
    small = sorted(iv)[: max(1, len(iv) // 10)]
    refresh = statistics.median(small) if small else None
    per_frame = {"presented": len(shown), "presented_per_s": round(len(shown) / secs, 2) if secs else None,
                 "interval_ms": dist(iv), "refresh_ms": round(refresh, 3) if refresh else None}
    if refresh:
        per_frame["intervals_over_1.5_refresh"] = sum(1 for x in iv if x > 1.5 * refresh)
        per_frame["share_over_1.5_refresh"] = round(per_frame["intervals_over_1.5_refresh"] / len(iv), 4) if iv else None
    # Level -> the app's next present call -> the next presented drawable.
    calls = sorted(s[0] for s in sp if s[1] == "com.apple.coreanimation" and s[2] == "ClientDrawable" and s[3] == "End")
    levels = [s[0] for s in t.bench("level") if lo <= s[0] <= hi]
    to_call, to_glass = [], []
    import bisect
    for x in levels:
        i = bisect.bisect_left(calls, x)
        if i == len(calls):
            continue
        to_call.append((calls[i] - x) / 1e6)
        j = bisect.bisect_left(presented, calls[i])
        if j < len(presented):
            to_glass.append((presented[j] - x) / 1e6)
    # CPU by thread: the time profiler's 1 ms samples of running threads.
    cpu, quarters = {}, [0, 0, 0, 0]
    for r in t.rows("time-sample"):
        th = r.get("thread")
        if pid_of(th) != t.pid or r["thread-state"].raw != "Running":
            continue
        tm = r["time"].num()
        if lo <= tm <= hi:
            name = thread_name(th)
            cpu[name] = cpu.get(name, 0) + 1
            quarters[min(3, int((tm - lo) / (hi - lo) * 4))] += 1
    cpu_ms_per_s = {k: round(v / secs, 2) for k, v in sorted(cpu.items(), key=lambda kv: -kv[1])}
    return {"window_s": round(secs, 3), "levels": len(levels), "framepacing": fp, "per_frame": per_frame,
            "level_to_present_call_ms": dist(to_call), "level_to_presented_ms": dist(to_glass),
            "samples": {"interval_ms": [round(x, 3) for x in iv], "level_to_presented_ms": [round(x, 3) for x in to_glass],
                        "level_to_present_call_ms": [round(x, 3) for x in to_call]},
            "cpu_ms_per_s_by_thread": cpu_ms_per_s, "cpu_ms_per_s_total": round(sum(cpu.values()) / secs, 2),
            # CPU in each quarter of the window: whether the cost grows as the recording does.
            "cpu_ms_per_s_by_quarter": [round(q / (secs / 4), 2) for q in quarters]}


def hitches(t, warm):
    lo, hi = window(t, warm)
    secs = (hi - lo) / NS
    hs = []
    for r in t.rows("hitches"):
        if pid_of(r.get("process")) != t.pid:
            continue
        s = r["start"].num()
        if lo <= s <= hi:
            hs.append(r["duration"].num() / 1e6)
    # CPU time per thread from the scheduler's thread states: time in "Running" (exact, not sampled).
    cpu = {}
    for r in t.rows("thread-state"):
        th = r.get("thread")
        if pid_of(th) != t.pid or r["state"].raw != "Running":
            continue
        s = r["start"].num()
        d = r["duration"].num() or 0
        if s + d < lo or s > hi:
            continue
        name = thread_name(th)
        cpu[name] = cpu.get(name, 0) + (min(hi, s + d) - max(lo, s)) / 1e6
    return {"window_s": round(secs, 3), "hitches": len(hs), "hitch_ms_total": round(sum(hs), 3),
            "hitch_time_ratio_ms_per_s": round(sum(hs) / secs, 3), "hitch_ms": dist(hs),
            "thread_cpu_ms_per_s": {k: round(v / secs, 2) for k, v in sorted(cpu.items(), key=lambda kv: -kv[1])}}


def profile(t, warm, top=25):
    """Time Profiler: CPU by thread, and the functions the samples fall in (self: the leaf
    frame; inclusive: anywhere on the stack), for the main thread and the whole process."""
    lo, hi = window(t, warm)
    secs = (hi - lo) / NS
    threads, self_main, incl_main, self_all, incl_all = {}, {}, {}, {}, {}
    for r in t.rows("time-profile"):
        th = r.get("thread")
        if pid_of(th) != t.pid or not lo <= r["time"].num() <= hi:
            continue
        w = (r["weight"].num() or 0) / 1e6
        name = thread_name(th)
        threads[name] = threads.get(name, 0) + w
        bt = r.get("stack")
        frames = [f.fmt or "?" for f in (bt.kids if bt is not None else []) if f is not None and f.tag == "frame"]
        if not frames:
            continue
        main = name == "Main Thread"
        for d, fn in ((self_all, frames[0]),) + (((self_main, frames[0]),) if main else ()):
            d[fn] = d.get(fn, 0) + w
        for fn in set(frames):
            incl_all[fn] = incl_all.get(fn, 0) + w
            if main:
                incl_main[fn] = incl_main.get(fn, 0) + w

    # Functions the report names (bench/yap-instruments.md, "Where the time goes"), inclusive.
    named = {"status item replicants": "-[NSStatusItem _updateReplicants]",
             "HostView.applyLatestFrame": "HostView.applyLatestFrame()",
             "StatusHost.update": "StatusHost.update(_:)",
             "CA transaction commit": "CA::Transaction::commit()",
             "RenderLoop.tick": "RenderLoop.tick(_:)",
             "LeanCore.step": "LeanCore.step(_:)",
             "ShapeCache.paintShadow": "specialized static ShapeCache.paintShadow(into:tw:th:g:shape:color:)",
             "vImage blur": "vImageSepConvolve_PlanarF"}

    def head(d):
        return {k: round(v / secs, 2) for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:top]}
    return {"window_s": round(secs, 3), "cpu_ms_per_s_total": round(sum(threads.values()) / secs, 2),
            "cpu_ms_per_s_by_thread": head(threads),
            "named_inclusive_ms_per_s": {k: round(incl_all.get(f, 0) / secs, 2) for k, f in named.items()},
            "main_self_ms_per_s": head(self_main), "main_inclusive_ms_per_s": head(incl_main),
            "process_self_ms_per_s": head(self_all), "process_inclusive_ms_per_s": head(incl_all)}


def latency(t, warm_trials):
    begins = {s[4]: s[0] for s in t.bench("keyUpToTyped", "Begin")}
    ends = {s[4]: s[0] for s in t.bench("keyUpToTyped", "End")}
    ids = sorted((i for i in begins if i in ends), key=lambda i: begins[i])
    ms = [(ends[i] - begins[i]) / 1e6 for i in ids]
    kept = ms[warm_trials:]
    return {"trials": len(ms), "discarded_warmup": min(warm_trials, len(ms)), "key_up_to_typed_ms": dist(kept),
            "samples_ms": [round(x, 3) for x in kept]}


def idle(t, warm):
    rows = [r for r in t.rows("sysmon-process") if pid_of(r.get("process")) == t.pid]
    rows = [r for r in rows if r["time"].num() >= warm * NS]
    if len(rows) < 2:
        return {"error": "too few samples"}

    def v(r, k):
        c = r.get(k)
        return c.num() if c is not None and c.num() is not None else 0

    a, b = rows[0], rows[-1]
    secs = (b["time"].num() - a["time"].num()) / NS
    cpu_ns = (v(b, "cpu-total-user") + v(b, "cpu-total-system")) - (v(a, "cpu-total-user") + v(a, "cpu-total-system"))
    fp = [v(r, "memory-physical-footprint") for r in rows]
    menu = t.bench("menuOpen")
    return {"window_s": round(secs, 2), "cpu_percent": round(cpu_ns / NS / secs * 100, 3),
            "cpu_ms_per_s": round(cpu_ns / 1e6 / secs, 3),
            "wakeups_per_s": round((v(b, "interrupt-wakeups") - v(a, "interrupt-wakeups")) / secs, 2),
            "context_switches_per_s": round((v(b, "context-switch") - v(a, "context-switch")) / secs, 2),
            "footprint_mb": {"end": round(fp[-1] / 2**20, 2), "max": round(max(fp) / 2**20, 2)},
            "resident_mb_end": round(v(b, "memory-resident-size") / 2**20, 2),
            "threads_end": v(b, "thread-count"), "menu_opened": bool(menu)}


def launch(t, _warm):
    periods = [r for r in t.rows("life-cycle-period") if pid_of(r.get("process")) == t.pid]
    starts = {r["period"].raw: r["start"].num() for r in periods if r.get("period")}
    if not periods:
        return {"error": "no lifecycle"}
    t0 = min(r["start"].num() for r in periods)
    dfl = next((v for k, v in starts.items() if "applicationDidFinishLaunching" in (k or "")), None)
    ready = t.bench("ready")
    return {"start_to_did_finish_launching_ms": round((dfl - t0) / 1e6, 3) if dfl else None,
            "start_to_ready_ms": round((ready[0][0] - t0) / 1e6, 3) if ready else None,
            "periods": {k: round((v - t0) / 1e6, 3) for k, v in starts.items()}}


def main():
    suite, path = sys.argv[1], sys.argv[2]
    warm = float(sys.argv[sys.argv.index("--warm") + 1]) if "--warm" in sys.argv else None
    t = Trace(path)
    fn = {"overlay": overlay, "hitches": hitches, "latency": latency, "idle": idle, "menu": idle,
          "launch": launch, "profile": profile}[suite]
    default_warm = {"overlay": 2.0, "hitches": 2.0, "latency": 1, "idle": 20.0, "menu": 8.0, "launch": 0, "profile": 2.0}[suite]
    w = default_warm if warm is None else warm
    out = {"suite": suite, "trace": path.split("/")[-1], "template": t.info["template"],
           "process": t.info["process"].get("name"), "pid": t.pid,
           "exit": t.info["process"].get("termination-reason"),
           "os": t.info["device"].get("os-version"), "model": t.info["device"].get("model"),
           "result": fn(t, int(w) if suite == "latency" else w)}
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
