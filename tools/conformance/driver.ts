#!/usr/bin/env bun
// The conformance driver (docs/conformance.md).
//
//   bun tools/conformance/driver.ts --app Basics --bin <host app> --gen <generator> \
//       --claims <lake exe claims JSON> [--n 1000] [--length 12] [--seed 1] [--out build/conformance]
//
// Launches the app with its debug socket on, asks the generator (the Lean model, walking the
// app's own `step` and `frame`) for sequences, and replays each one on the running app as real
// input through the socket: clicks at each control's centre, keys and text-input calls for the
// field. After every step it compares what the app shows with what the model says it must show:
//
//   frame    the decoded frame the app applied, value for value (draws, AX nodes, text input, cursor)
//   ax       the accessibility tree as NSAccessibility answers it, against the model's AX nodes
//            through the host's role and value table (docs/host.md)
//   effects  the effects the host ran (clipboard writes, beeps)
//   shadow   no text-input shadow divergences (docs/host.md)
//   pixels   a sample inside each control's box, read from the presented drawable, has the
//            colour the model's draws paint there
//   model    the generator's own findings (presence, and a press delivering exactly that press)
//
// Then it replays every flow's witness from `lake exe claims` the same way. It writes
// build/conformance/<App>.json in the map's shape (docs/map.md) and <App>/report.md, with a
// shrunk, re-verified repro for each distinct failure.
//
// Privacy: input goes only into the app's own view through its socket (no CGEvent, no window
// server); the app is never activated; only the pid this script started is ever signalled.

import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createConnection, type Socket } from "node:net";
import { createInterface } from "node:readline";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

// MARK: Options

function parseArgs(argv: string[]) {
	const o: Record<string, string> = {};
	for (let i = 0; i < argv.length; i++) {
		if (argv[i].startsWith("--")) o[argv[i].slice(2)] = argv[i + 1]?.startsWith("--") || argv[i + 1] === undefined ? "1" : argv[++i];
	}
	return o;
}
const args = parseArgs(process.argv.slice(2));
const APP = args.app ?? "Basics";
const BIN = args.bin;
const GEN = args.gen;
const N = Number(args.n ?? 1000);
const LENGTH = Number(args.length ?? 12);
const SEED = Number(args.seed ?? 1);
const OUT = resolve(args.out ?? "build/conformance");
const TOLERANCE = Number(args.tolerance ?? 3);
const SHRINK_MAX = Number(args.shrink ?? 6); // distinct failures to shrink
if (!BIN || !GEN) {
	console.error("usage: driver.ts --app A --bin APP_BINARY --gen GENERATOR [--claims FILE] [--n N] [--length L] [--seed S]");
	process.exit(2);
}

// MARK: Types (the generator's JSON; see tools/conformance/lean/Conformance/Gen.lean)

type Rect = [number, number, number, number];
type Color = [number, number, number, number];
type AxNode = {
	role: string; control: string | null; parent: number | null; rect: Rect; label: string; value: string;
	focused: boolean; selected: boolean; checked: boolean | null;
};
type TextInput = { control: string; rect: Rect; caret: Rect; text: string; selection: [number, number]; marked: [number, number] | null; origin: [number, number] };
type Frame = { size: [number, number]; draws: unknown[]; ax: AxNode[]; textInput: TextInput | null; cursor: string };
type Probe = { ref: string; at: [number, number]; expect: Color; own: boolean };
type Gesture = { g: string; at?: [number, number]; clicks?: number; key?: string; mods?: string[]; char?: string; text?: string; sel?: [number, number]; name?: string };
type Step = {
	label: string; move: { ref: string; claim: number; key: number; trigger: string } | null; gestures: Gesture[];
	events: string[]; actions: { action: string; claim: number; ref: string; accepted: boolean }[];
	effects: Record<string, unknown>[]; clipboard: string; frame: Frame; probes: Probe[]; findings: string[];
};
type Sequence = { name: string; witness?: boolean; init: Frame; initProbes: Probe[]; stopped?: string | null; steps: Step[] };

type Problem = { kind: string; detail: string };
type StepResult = { problems: Problem[]; ms: number };

// MARK: The app and its socket

class Client {
	private buf = "";
	private waiting: ((line: string) => void)[] = [];
	private lines: string[] = [];
	constructor(private sock: Socket) {
		sock.setEncoding("utf8");
		sock.on("data", (d: string) => {
			this.buf += d;
			let i: number;
			while ((i = this.buf.indexOf("\n")) >= 0) {
				const line = this.buf.slice(0, i);
				this.buf = this.buf.slice(i + 1);
				const w = this.waiting.shift();
				if (w) w(line);
				else this.lines.push(line);
			}
		});
	}
	static async connect(path: string, timeoutMs = 20000): Promise<Client> {
		const until = Date.now() + timeoutMs;
		for (;;) {
			try {
				const s = await new Promise<Socket>((ok, err) => {
					const c = createConnection(path);
					c.once("connect", () => ok(c));
					c.once("error", err);
				});
				return new Client(s);
			} catch (e) {
				if (Date.now() > until) throw e;
				await Bun.sleep(100);
			}
		}
	}
	async req(cmd: Record<string, unknown>): Promise<any> {
		this.sock.write(JSON.stringify(cmd) + "\n");
		const line = this.lines.shift() ?? (await new Promise<string>((ok) => this.waiting.push(ok)));
		const r = JSON.parse(line);
		if (!r.ok) throw new Error(`${cmd.cmd}: ${r.error}`);
		return r;
	}
	close() { this.sock.destroy(); }
}

let app: ChildProcess | null = null;
const sockPath = join(tmpdir(), `cairn-conf-${process.pid}.sock`);

async function launch(): Promise<Client> {
	rmSync(sockPath, { force: true });
	mkdirSync(join(OUT, APP), { recursive: true });
	const log = Bun.file(join(OUT, APP, "app.log")).writer();
	app = spawn(BIN, [], { env: { ...process.env, CAIRN_DEBUG_SOCKET: sockPath }, stdio: ["ignore", "pipe", "pipe"] });
	app.stdout!.on("data", (d) => log.write(d));
	app.stderr!.on("data", (d) => log.write(d));
	app.on("exit", (code, sig) => { if (!quitting) console.error(`app exited (${code ?? sig})`); });
	return Client.connect(sockPath);
}

let quitting = false;
function stopApp() {
	quitting = true;
	// Only the process this script started, by its pid.
	if (app?.pid && app.exitCode === null) {
		try { process.kill(app.pid, "SIGTERM"); } catch {}
	}
	rmSync(sockPath, { force: true });
}
process.on("exit", stopApp);
process.on("SIGINT", () => { stopApp(); process.exit(130); });

// MARK: Performing gestures

async function perform(c: Client, g: Gesture): Promise<number> {
	switch (g.g) {
		case "move": case "down": case "up": case "exit":
			return (await c.req({ cmd: "pointer", type: g.g, at: g.at ?? [0, 0], clicks: g.clicks ?? 1 })).seq;
		case "key":
			return (await c.req({ cmd: "key", key: g.key, mods: g.mods ?? [], char: g.char })).seq;
		case "text":
			return (await c.req({ cmd: "text", op: "insert", text: g.text })).seq;
		case "marked":
			return (await c.req({ cmd: "text", op: "marked", text: g.text, sel: g.sel })).seq;
		case "unmark":
			return (await c.req({ cmd: "text", op: "unmark" })).seq;
		case "menu":
			return (await c.req({ cmd: "menu", name: g.name })).seq;
	}
	throw new Error(`unknown gesture ${g.g}`);
}

/** The gesture in the generator's `--gestures` line format. */
function gestureLine(g: Gesture): string {
	switch (g.g) {
		case "move": case "up": return `${g.g} ${g.at![0]} ${g.at![1]}`;
		case "down": return `down ${g.at![0]} ${g.at![1]} ${g.clicks ?? 1}`;
		case "key": return `key ${g.key} ${g.mods?.length ? g.mods.join(",") : "-"}${g.char !== undefined ? " " + g.char : ""}`;
		case "text": return `text ${g.text}`;
		case "marked": return `marked ${g.sel![0]} ${g.sel![1]} ${g.text}`;
		case "menu": return `menu ${g.name}`;
		default: return g.g;
	}
}

// MARK: Comparing

/** The first path at which two JSON values differ, with both sides. */
function diff(a: unknown, b: unknown, path = ""): string | null {
	if (a === b) return null;
	if (Array.isArray(a) && Array.isArray(b)) {
		for (let i = 0; i < Math.max(a.length, b.length); i++) {
			if (i >= a.length || i >= b.length) return `${path}: length ${a.length} (model) vs ${b.length} (app)`;
			const d = diff(a[i], b[i], `${path}[${i}]`);
			if (d) return d;
		}
		return null;
	}
	if (a && b && typeof a === "object" && typeof b === "object") {
		const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
		for (const k of keys) {
			const d = diff((a as any)[k], (b as any)[k], `${path}.${k}`);
			if (d) return d;
		}
		return null;
	}
	return `${path || "value"}: model ${JSON.stringify(a)}, app ${JSON.stringify(b)}`;
}

const utf16 = (s: string, scalars: number) => Array.from(s).slice(0, scalars).join("").length;

/** What the AX mirror must answer for the model's nodes (docs/host.md, "Accessibility"). */
function expectedAx(f: Frame): Record<string, unknown>[] {
	const role: Record<string, string> = {
		group: "AXGroup", listItem: "AXGroup", button: "AXButton", checkbox: "AXCheckBox", text: "AXStaticText",
		textField: "AXTextField", link: "AXLink", list: "AXList", heading: "AXHeading", tab: "AXRadioButton",
	};
	return f.ax.map((n) => {
		const field = f.textInput && f.textInput.control === n.control ? f.textInput : null;
		let value: unknown;
		switch (n.role) {
			case "checkbox": case "tab": value = (n.checked ?? n.selected) ? 1 : 0; break;
			case "textField": value = field ? field.text : n.value; break;
			case "text": value = n.value === "" ? n.label : n.value; break;
			default: value = n.value === "" ? null : n.value;
		}
		const e: Record<string, unknown> = {
			id: n.control ?? "", role: role[n.role], subrole: n.role === "tab" ? "AXTabButton" : null,
			label: n.label === "" ? null : n.label, title: n.role === "button" || n.role === "heading" ? n.label : null,
			value, focused: n.focused, selected: n.selected, enabled: true, frame: n.rect, parent: n.parent,
		};
		if (n.role === "listItem") e.roleDescription = "list item";
		if (n.role === "heading") e.roleDescription = "heading";
		if (n.role === "textField") {
			const text = field ? field.text : n.value;
			const len = text.length;
			if (field) {
				const a = utf16(text, field.selection[0]), b = utf16(text, field.selection[1]);
				e.selection = [a, b - a];
			} else e.selection = [len, 0];
			e.characters = len;
		}
		return e;
	});
}

function compareAx(model: Frame, actual: Record<string, unknown>[]): string | null {
	const want = expectedAx(model);
	// Compare only the keys the model determines (roleDescription only where the host sets it).
	const got = actual.map((a, i) => {
		const w = want[i] ?? {};
		const out: Record<string, unknown> = {};
		for (const k of Object.keys(w)) out[k] = a[k];
		return out;
	});
	if (want.length !== actual.length) return `ax: ${want.length} nodes (model) vs ${actual.length} (app)`;
	const d = diff(want, got, "ax");
	return d;
}

const near = (a: Color, b: Color) => a.every((v, i) => Math.abs(v - b[i]) <= TOLERANCE);

async function checkFrame(c: Client, f: Frame, probes: Probe[], clear: Color, problems: Problem[], stats: Stats) {
	const fr = await c.req({ cmd: "frame" });
	const d = diff(f, fr.frame, "frame");
	if (d) problems.push({ kind: "frame", detail: d });
	const ax = await c.req({ cmd: "ax" });
	const a = compareAx(f, ax.nodes);
	if (a) problems.push({ kind: "ax", detail: a });
	if (probes.length) {
		const px = await c.req({ cmd: "pixels", points: probes.map((p) => p.at) });
		stats.pixelSource[px.source] = (stats.pixelSource[px.source] ?? 0) + 1;
		probes.forEach((p, i) => {
			const got: Color = px.colors[i];
			stats.probes++;
			const ok = near(p.expect, got);
			if (!ok) problems.push({ kind: "pixels", detail: `${p.ref} at ${p.at}: model ${JSON.stringify(p.expect)}, app ${JSON.stringify(got)} (${px.source})` });
		});
	}
}

// MARK: Running sequences

type Stats = { steps: number; probes: number; pixelSource: Record<string, number>; stepMs: number[] };

async function runSequence(c: Client, seq: Sequence, clear: Color, stats: Stats, stopAtFirst = true):
	Promise<{ failedAt: number | null; problems: Problem[]; results: StepResult[] }> {
	const r = await c.req({ cmd: "restart" });
	const w = await c.req({ cmd: "wait", seq: r.seq });
	const init: Problem[] = [];
	if (w.divergences.length) init.push({ kind: "shadow", detail: w.divergences.join("; ") });
	await checkFrame(c, seq.init, seq.initProbes, clear, init, stats);
	if (init.length) return { failedAt: -1, problems: init, results: [] };
	const results: StepResult[] = [];
	for (let i = 0; i < seq.steps.length; i++) {
		const st = seq.steps[i];
		const t0 = performance.now();
		const problems: Problem[] = [];
		for (const f of st.findings) problems.push({ kind: "model", detail: f });
		let last = 0;
		for (const g of st.gestures) last = await perform(c, g);
		const wt = await c.req({ cmd: "wait", seq: last });
		const effects = diff(st.effects, wt.effects, "effects");
		if (effects) problems.push({ kind: "effects", detail: effects });
		if (wt.divergences.length) problems.push({ kind: "shadow", detail: wt.divergences.join("; ") });
		await checkFrame(c, st.frame, st.probes, clear, problems, stats);
		const ms = performance.now() - t0;
		stats.steps++;
		stats.stepMs.push(ms);
		results.push({ problems, ms });
		if (problems.length && stopAtFirst) return { failedAt: i, problems, results };
	}
	if (seq.stopped) return { failedAt: seq.steps.length, problems: [{ kind: "witness", detail: seq.stopped }], results };
	return { failedAt: null, problems: [], results };
}

/** Runs the generator and yields its sequences. */
async function* generate(extra: string[], hello: any): AsyncGenerator<Sequence> {
	const p = spawn(GEN!, ["--size", String(hello.size[0]), String(hello.size[1]), "--scale", String(hello.scale),
		"--clear", hello.clear.join(","), ...extra], { stdio: ["ignore", "pipe", "inherit"] });
	const rl = createInterface({ input: p.stdout! });
	for await (const line of rl) if (line.trim()) yield JSON.parse(line);
	await new Promise((ok) => (p.exitCode !== null ? ok(null) : p.once("exit", ok)));
	if (p.exitCode !== 0) throw new Error(`generator exited ${p.exitCode}`);
}

async function genOne(extra: string[], hello: any): Promise<Sequence[]> {
	const out: Sequence[] = [];
	for await (const s of generate(extra, hello)) out.push(s);
	return out;
}

/** Shrinks a failing sequence: the shortest failing prefix, then drops steps one at a time while
 * the replay (re-modelled from the gestures alone) still fails. Returns the gesture lines. */
async function shrink(c: Client, seq: Sequence, failedAt: number, hello: any, clear: Color, stats: Stats) {
	let steps = seq.steps.slice(0, failedAt + 1).map((s) => s.gestures.map(gestureLine).join("\x1f"));
	const file = join(OUT, APP, "shrink.txt");
	const tryLine = async (cand: string[]) => {
		writeFileSync(file, cand.join("\t") + "\n");
		const [s] = await genOne(["--gestures", file], hello);
		if (s.stopped) return null;
		const r = await runSequence(c, s, clear, stats);
		return r.failedAt === null ? null : { s, r };
	};
	let best = await tryLine(steps);
	if (!best) return { steps, verified: false, seq: null as Sequence | null, result: null as any };
	steps = steps.slice(0, best.r.failedAt + 1);
	for (let i = steps.length - 2; i >= 0; i--) {
		const cand = steps.filter((_, j) => j !== i);
		const t = await tryLine(cand);
		if (t) {
			best = t;
			steps = cand.slice(0, Math.max(t.r.failedAt, 0) + 1);
			i = Math.min(i, steps.length - 1);
		}
	}
	return { steps, verified: true, seq: best.s, result: best.r };
}

// MARK: Main

type ClaimTally = { runs: number; fails: number; notes: string[] };

async function main() {
	const t0 = performance.now();
	const c = await launch();
	const hello = await c.req({ cmd: "hello" });
	const clear: Color = hello.clear;
	console.log(`conformance: ${APP} pid ${hello.pid}, ${hello.size.join("x")} @${hello.scale / 100}x, socket ${sockPath}`);

	const stats: Stats = { steps: 0, probes: 0, pixelSource: {}, stepMs: [] };
	const tally = new Map<string, ClaimTally>();
	const bump = (ref: string, fail: string | null) => {
		const t = tally.get(ref) ?? { runs: 0, fails: 0, notes: [] };
		t.runs++;
		if (fail) { t.fails++; if (t.notes.length < 3) t.notes.push(fail); }
		tally.set(ref, t);
	};
	type Failure = { seq: Sequence; at: number; problems: Problem[]; signature: string };
	const failures: Failure[] = [];
	let sequences = 0, passed = 0, actions = 0;
	const triggers = new Map<string, number>();

	const record = (seq: Sequence, res: Awaited<ReturnType<typeof runSequence>>) => {
		sequences++;
		const upto = res.failedAt === null ? seq.steps.length : Math.min(res.failedAt + 1, seq.steps.length);
		for (let i = 0; i < upto; i++) {
			const st = seq.steps[i];
			const failed = res.failedAt === i;
			const note = failed ? `${seq.name} step ${i} (${st.label}): ${res.problems[0].kind}: ${res.problems[0].detail}` : null;
			actions += st.actions.length;
			if (st.move) {
				bump(`^${st.move.claim}`, note);
				const k = `^${st.move.claim} ${st.move.trigger}`;
				triggers.set(k, (triggers.get(k) ?? 0) + 1);
			} else bump("(plain UI)", note);
		}
		if (res.failedAt === null) passed++;
		else {
			const st = seq.steps[res.failedAt];
			const signature = `${res.problems.map((p) => p.kind).join("+")} ${st?.move ? `^${st.move.claim} ${st.move.trigger}` : st?.label ?? "init"}`;
			failures.push({ seq, at: res.failedAt, problems: res.problems, signature });
		}
	};

	// Random walks.
	let lastReport = performance.now();
	for await (const seq of generate(["--seed", String(SEED), "--count", String(N), "--length", String(LENGTH)], hello)) {
		const res = await runSequence(c, seq, clear, stats);
		record(seq, res);
		if (performance.now() - lastReport > 5000) {
			lastReport = performance.now();
			console.log(`  ${sequences}/${N} sequences, ${stats.steps} steps, ${failures.length} failing`);
		}
	}
	const walkMs = performance.now() - t0;

	// Flow witnesses.
	const flows: { ref: string; pass: boolean; note?: string; steps: number }[] = [];
	const claimsJson = args.claims ? JSON.parse(await Bun.file(args.claims).text()) : { claims: [] };
	const witnessed = claimsJson.claims.filter((c: any) => c.kind === "flow" && c.witness && !c.retired);
	if (witnessed.length) {
		const lines = witnessed.map((f: any) => [f.ref, ...f.witness.map((s: any) =>
			[s.trigger, s.claim, s.key, ...(s.op ? [s.op.kind, s.op.text ?? ""] : [])].join(" "))].join("\t"));
		const file = join(OUT, APP, "witnesses.txt");
		writeFileSync(file, lines.join("\n") + "\n");
		for await (const seq of generate(["--witness", file], hello)) {
			const res = await runSequence(c, seq, clear, stats);
			const ok = res.failedAt === null;
			const note = ok ? undefined : `step ${res.failedAt}: ${res.problems[0].kind}: ${res.problems[0].detail}`;
			flows.push({ ref: seq.name, pass: ok, note, steps: seq.steps.length });
			tally.set(seq.name, { runs: 1, fails: ok ? 0 : 1, notes: note ? [note] : [] });
			if (!ok) failures.push({ seq, at: res.failedAt!, problems: res.problems, signature: `flow ${seq.name}` });
		}
	}

	// Invariants: every state the app reached was the model's, where the invariant is proved.
	const allPass = failures.length === 0;
	for (const inv of claimsJson.claims.filter((c: any) => c.kind === "invariant" && !c.retired)) {
		tally.set(inv.ref, { runs: stats.steps, fails: allPass ? 0 : 1, notes: allPass ? [] : ["a reached state differed from the model; see report.md"] });
	}

	// Shrink the first failure of each kind.
	const repros: { signature: string; original: Failure; steps: string[]; verified: boolean; problems: Problem[]; labels: string[] }[] = [];
	const seen = new Set<string>();
	for (const f of failures) {
		if (seen.has(f.signature) || repros.length >= SHRINK_MAX) continue;
		seen.add(f.signature);
		if (f.at < 0) { repros.push({ signature: f.signature, original: f, steps: [], verified: true, problems: f.problems, labels: [] }); continue; }
		const s = await shrink(c, f.seq, Math.min(f.at, f.seq.steps.length - 1), hello, clear, stats);
		repros.push({ signature: f.signature, original: f, steps: s.steps, verified: s.verified,
			problems: s.result?.problems ?? f.problems, labels: s.steps.map((x) => x.split("\x1f").join(", ")) });
	}
	const totalMs = performance.now() - t0;
	await c.req({ cmd: "quit" }).catch(() => {});
	c.close();
	stopApp();

	// build/conformance/<App>.json, in the map's shape (docs/map.md).
	const commit = spawnSync("git", ["rev-parse", "--short", "HEAD"]).stdout.toString().trim();
	const claims: Record<string, { pass: boolean; runs: number; note?: string }> = {};
	for (const [ref, t] of [...tally].sort()) {
		if (!ref.startsWith("^")) continue;
		claims[ref] = { pass: t.fails === 0, runs: t.runs, ...(t.notes.length ? { note: t.notes[0] } : {}) };
	}
	const ms = stats.stepMs.sort((a, b) => a - b);
	const pct = (p: number) => Math.round(ms[Math.min(ms.length - 1, Math.floor(ms.length * p))] * 10) / 10;
	const summary = {
		runs: N, commit, claims,
		app: APP, seed: SEED, length: LENGTH,
		sequences: { walks: sequences, passed, failed: sequences - passed, flows: flows.length, flowsPassed: flows.filter((f) => f.pass).length },
		steps: stats.steps, actions, probes: stats.probes, pixelSource: stats.pixelSource,
		plainUi: tally.get("(plain UI)") ?? { runs: 0, fails: 0 },
		triggers: Object.fromEntries([...triggers].sort()),
		timing: { totalSeconds: Math.round(totalMs / 100) / 10, walkSeconds: Math.round(walkMs / 100) / 10, stepMs: { p50: pct(0.5), p90: pct(0.9), p99: pct(0.99), max: pct(1) } },
	};
	mkdirSync(OUT, { recursive: true });
	writeFileSync(join(OUT, `${APP}.json`), JSON.stringify(summary, null, 2) + "\n");

	// report.md
	const md: string[] = [`# Conformance: ${APP}`, "",
		`Commit ${commit}, seed ${SEED}, ${N} walks of ${LENGTH} steps, ${flows.length} flow witnesses.`, "",
		`- Walks: ${passed}/${sequences} passed; ${stats.steps} steps, ${actions} actions, ${stats.probes} pixel probes (${Object.entries(stats.pixelSource).map(([k, v]) => `${k} ${v}`).join(", ")}).`,
		`- Flows: ${flows.map((f) => `${f.ref} ${f.pass ? "pass" : "FAIL"}`).join(", ") || "none"}.`,
		`- Time: ${summary.timing.totalSeconds} s in all; per step p50 ${pct(0.5)} ms, p90 ${pct(0.9)} ms, max ${pct(1)} ms.`, "",
		"| Claim | Result | Runs | Note |", "|---|---|---|---|",
		...Object.entries(claims).map(([r, v]) => `| ${r} | ${v.pass ? "pass" : "**fail**"} | ${v.runs} | ${(v.note ?? "").replace(/\|/g, "\\|").slice(0, 300)} |`), ""];
	if (!failures.length) md.push("No failures.");
	else {
		md.push(`## Failures`, "", `${failures.length} failing sequences; distinct kinds:`, "");
		const kinds = new Map<string, number>();
		for (const f of failures) kinds.set(f.signature, (kinds.get(f.signature) ?? 0) + 1);
		for (const [k, n] of kinds) md.push(`- ${k}: ${n}`);
		for (const r of repros) {
			md.push("", `### ${r.signature}`, "", `First seen in ${r.original.seq.name} at step ${r.original.at}` +
				(r.original.at >= 0 ? ` (${r.original.seq.steps[r.original.at]?.label})` : " (initial frame)") + ".", "");
			md.push(r.verified ? `Minimal repro (${r.steps.length} steps, re-verified on the app; one step per line, gestures in the generator's \`--gestures\` format):` : "Could not re-verify by replaying gestures; the original sequence:", "", "```");
			const lines = r.verified ? r.labels : r.original.seq.steps.slice(0, r.original.at + 1).map((s) => `${s.label}: ${s.gestures.map(gestureLine).join(", ")}`);
			md.push(...lines, "```", "", "Problems:", "");
			for (const p of r.problems) md.push(`- ${p.kind}: ${p.detail.slice(0, 2000)}`);
		}
	}
	writeFileSync(join(OUT, APP, "report.md"), md.join("\n") + "\n");
	writeFileSync(join(OUT, APP, "failures.jsonl"), failures.map((f) => JSON.stringify({ name: f.seq.name, at: f.at, signature: f.signature, problems: f.problems, labels: f.seq.steps.slice(0, f.at + 1).map((s) => s.label) })).join("\n") + (failures.length ? "\n" : ""));

	console.log(`conformance: ${APP}: walks ${passed}/${sequences} passed, flows ${flows.filter((f) => f.pass).length}/${flows.length}, ${stats.steps} steps, ${stats.probes} probes, ${summary.timing.totalSeconds} s`);
	console.log(`  wrote ${join(OUT, `${APP}.json`)} and ${join(OUT, APP, "report.md")}`);
	process.exit(failures.length ? 1 : 0);
}

main().catch((e) => { console.error(e); stopApp(); process.exit(2); });
