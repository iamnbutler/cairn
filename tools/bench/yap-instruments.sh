#!/bin/bash
# Records the Yap bench with Apple's Instruments and summarises each trace (bench/yap-instruments.md).
#
#   tools/bench/yap-instruments.sh [SUITE...]      default: overlay latency idle launch
#
# Suites and templates (xcrun xctrace record ... --launch, so Instruments starts the app and
# records only that process):
#   overlay   Metal System Trace + os_signpost   --bench-overlay, SECS of voice, hands free
#   hitches   Animation Hitches + os_signpost    --bench-overlay, HITCH_SECS of voice
#   latency   Logging                            --bench-latency, TRIALS key-up -> typed
#   idle      Activity Monitor                   --bench-idle for IDLE_SECS in the menu bar
#   menu      Activity Monitor + os_signpost     --bench-menu: its own status menu open
#   launch    App Launch + os_signpost           --bench-idle, launch to "ready"
#   profile   Time Profiler + os_signpost        --bench-overlay, CPU by thread and function
#
# Environment: APPS ("cairn ref"; also "refdebug", and "cairnbase" for a CairnYap build copied to
# build/bench/YapCairn-base.app to compare a change against), RUNS (5, plus one discarded warm-up per
# app), SECS (20), HITCH_SECS (8), TRIALS (21), IDLE_SECS (180), SCREEN (0: NSScreen index the
# overlay shows on), BUFFER_MS (20: the fake microphone's buffer), TAG (a name for this
# configuration), KEEP=1 to keep traces, OUT (bench/out/yap-instruments).
#
# Runs alternate app order (ABBA). Each run writes OUT/TAG/SUITE/APP-N.json (N=0 is the
# warm-up) and a line in OUT/TAG/runs.tsv with the load average. Only the bench apps from
# build/bench are started, and only those are stopped, by pid.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APPS=${APPS:-cairn ref}
RUNS=${RUNS:-5}
SECS=${SECS:-20}
HITCH_SECS=${HITCH_SECS:-8}
TRIALS=${TRIALS:-21}
IDLE_SECS=${IDLE_SECS:-180}
SCREEN=${SCREEN:-0}
BUFFER_MS=${BUFFER_MS:-20}
TAG=${TAG:-screen$SCREEN-buf$BUFFER_MS}
KEEP=${KEEP:-0}
OUT=${OUT:-$ROOT/bench/out/yap-instruments}/$TAG
TRACES=${TRACES:-/tmp/yap-instruments}
SUITES=${*:-overlay latency idle launch}
mkdir -p "$OUT" "$TRACES"

bin() {
	case $1 in
	cairn) echo "$ROOT/build/bench/YapCairn.app/Contents/MacOS/CairnYap" ;;
	ref) echo "$ROOT/build/bench/YapRef.app/Contents/MacOS/YapRef" ;;
	refdebug) echo "$ROOT/build/bench/YapRef-Debug.app/Contents/MacOS/YapRef" ;;
	cairnbase) echo "$ROOT/build/bench/YapCairn-base.app/Contents/MacOS/CairnYap" ;;  # an earlier build kept for A/B
	esac
}

# Stops bench processes still alive from this script's records (xctrace --launch can leave a
# stopped copy behind). Matches only the bench binaries under this tree's build/bench.
reap() {
	for p in $(pgrep -f "$ROOT/build/bench/"); do
		kill -9 "$p" 2>/dev/null && echo "  stopped stray bench process $p"
	done
}

{
	echo "# $(date -u +%FT%TZ) $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string) $(($(sysctl -n hw.memsize) / 1073741824)) GB"
	echo "# macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcrun xctrace version)"
	echo "# commit $(git -C "$ROOT" rev-parse --short HEAD); APPS=$APPS RUNS=$RUNS SECS=$SECS SCREEN=$SCREEN BUFFER_MS=$BUFFER_MS"
} >>"$OUT/runs.tsv"
# The displays' refresh rates as AppKit reports them (NSScreen.maximumFramesPerSecond).
swift -e 'import AppKit; for (i, s) in NSScreen.screens.enumerated() { print("display", i, s.maximumFramesPerSecond, s.localizedName) }' \
	2>/dev/null | tee -a "$OUT/runs.tsv" | awk -v s="$SCREEN" '$2 == s { print $3 }' >"$OUT/refresh-hz"

record() { # suite app n
	local suite=$1 app=$2 n=$3 b trace args tmpl limit
	b=$(bin "$app")
	trace="$TRACES/$TAG-$suite-$app-$n.trace"
	rm -rf "$trace"
	args=() tmpl=() limit=60
	case $suite in
	overlay) tmpl=(--template "Metal System Trace" --instrument os_signpost)
		args=(--bench-overlay --seconds "$SECS" --buffer-ms "$BUFFER_MS" --screen "$SCREEN") limit=$((SECS + 20)) ;;
	hitches) tmpl=(--template "Animation Hitches" --instrument os_signpost)
		args=(--bench-overlay --seconds "$HITCH_SECS" --buffer-ms "$BUFFER_MS" --screen "$SCREEN") limit=$((HITCH_SECS + 20)) ;;
	profile) tmpl=(--template "Time Profiler" --instrument os_signpost)
		args=(--bench-overlay --seconds "$SECS" --buffer-ms "$BUFFER_MS" --screen "$SCREEN") limit=$((SECS + 20)) ;;
	latency) tmpl=(--template "Logging")
		args=(--bench-latency --trials "$TRIALS") limit=$((TRIALS * 8 + 30)) ;;
	idle) tmpl=(--template "Activity Monitor")
		args=(--bench-idle) limit=$IDLE_SECS ;;
	menu) tmpl=(--template "Activity Monitor" --instrument os_signpost)
		args=(--bench-menu) limit=$IDLE_SECS ;;
	launch) tmpl=(--template "App Launch" --instrument os_signpost)
		args=(--bench-idle) limit=10 ;;
	esac
	local home
	home=$(mktemp -d /tmp/yap-bench-home.XXXXXX)
	printf '%s\t%s\t%s\t%s\tload %s\n' "$(date +%T)" "$suite" "$app" "$n" "$(sysctl -n vm.loadavg)" >>"$OUT/runs.tsv"
	echo "== $suite $app run $n"
	xcrun xctrace record "${tmpl[@]}" --output "$trace" --time-limit "${limit}s" --no-prompt \
		--target-stdout - --env YAP_BENCH_HOME="$home" --launch -- "$b" "${args[@]}" 2>&1 | grep -E "^bench:|^Error|failed|Output file" | tail -3
	reap
	rm -rf "$home"
	if python3 -I "$ROOT/tools/bench/analyze.py" "$suite" "$trace" >"$OUT/$suite/$app-$n.json.tmp"; then
		mv "$OUT/$suite/$app-$n.json.tmp" "$OUT/$suite/$app-$n.json"
	else
		echo "  analysis failed, trace kept: $trace"
		rm -f "$OUT/$suite/$app-$n.json.tmp"
		return
	fi
	[ "$KEEP" = 1 ] || rm -rf "$trace"
}

for suite in $SUITES; do
	mkdir -p "$OUT/$suite"
	runs=$RUNS
	for n in $(seq 0 "$runs"); do
		order=$APPS
		[ $((n % 2)) = 1 ] && order=$(echo "$APPS" | awk '{for (i = NF; i > 0; i--) printf "%s ", $i}')
		for app in $order; do
			record "$suite" "$app" "$n"
		done
	done
done
python3 -I "$ROOT/tools/bench/report.py" "$OUT"
