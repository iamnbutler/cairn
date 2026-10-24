// The registry fixture: what the Cairn site's /packages pages render when no package registry
// is configured (site/registry.js). It has the shape of the nextpm `cairn` kind's API (nextpm
// docs/adr/0005-cairn-kind.md).
//
// Cairn's versions are its real releases, the tags in RELEASES. Each one is read from git at its
// tag: the revision and commit date, cairn.toml, lean/lean-toolchain and the claims.lock ledger.
// Yap's entry is a sample: yap-cairn has no tags yet. Its claims are the ids Cairn's claims.lock
// marks `moved:yap`, shown as active, and its revision is yap-cairn's main when this was written.
// Cairn is a library (kind = "lib") and Yap an app (kind = "bin"). `swift` is whether a version
// has a SwiftPM package, as `cairn publish` reports it: Cairn has its root Package.swift at each
// tag, and Yap's app is a Swift host.
//
//   bun tools/registry/fixture.ts           write site/registry/fixture.json
//   bun tools/registry/fixture.ts --check   fail if the committed fixture differs
//
// It needs the tags: a clone without them (a shallow CI checkout) fails with a hint to run
// `git fetch --tags`. A new release is a new line at the top of RELEASES, after it is tagged.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

// Cairn's final releases, newest first.
const RELEASES = ["0.1.2", "0.1.1", "0.1.0"];

const ROOT = resolve(import.meta.dir, "../..");
const OUT = join(ROOT, "site/registry/fixture.json");

const git = (...args: string[]) => execFileSync("git", args, { cwd: ROOT, encoding: "utf8" });

type Claim = { id: number; kind: string; status: string; statement: string; title: string };

const parseClaims = (text: string): Claim[] =>
	text
		.split("\n")
		.filter((line) => line.trim() && !line.startsWith("#"))
		.map((line) => {
			const [id, kind, status, statement, ...title] = line.split("\t");
			return { id: Number(id), kind, status, statement, title: title.join("\t") };
		});

// `moved:yap` (or any other `moved:<pkg>`) counts as moved.
const summary = (list: Claim[]) => ({
	active: list.filter((c) => c.status === "active").length,
	retired: list.filter((c) => c.status === "retired").length,
	moved: list.filter((c) => c.status !== "active" && c.status !== "retired").length,
});

/** A `key = "value"` line from cairn.toml's [package] table. */
const field = (toml: string, key: string) => toml.match(new RegExp(`^${key}\\s*=\\s*"([^"]*)"`, "m"))?.[1];
const list = (toml: string, key: string) =>
	[...(toml.match(new RegExp(`^${key}\\s*=\\s*\\[([^\\]]*)\\]`, "m"))?.[1] ?? "").matchAll(/"([^"]*)"/g)].map((m) => m[1]);

type Version = {
	version: string;
	kind: "lib" | "bin";
	swift: boolean;
	revision: string;
	date: string;
	toolchain: string;
	description: string;
	license: string;
	dependencies: Record<string, string>;
	libs: string[];
	claims: Claim[];
};

const entry = (v: Version) => ({
	version: v.version,
	kind: v.kind,
	swift: v.swift,
	revision: v.revision,
	tag: `v${v.version}`,
	date: v.date,
	toolchain: v.toolchain,
	yanked: false,
	publisher: "iamnbutler",
	description: v.description,
	license: v.license,
	dependencies: v.dependencies,
	libs: v.libs,
	claims: summary(v.claims),
});

function release(version: string): Version {
	const tag = `v${version}`;
	try {
		git("rev-parse", "--quiet", "--verify", `refs/tags/${tag}`);
	} catch {
		console.error(`tools/registry/fixture.ts: tag ${tag} is missing here: run \`git fetch --tags\``);
		process.exit(1);
	}
	const at = (path: string) => git("show", `${tag}:${path}`);
	const has = (path: string) => {
		try {
			git("cat-file", "-e", `${tag}:${path}`);
			return true;
		} catch {
			return false;
		}
	};
	const toml = at("cairn.toml");
	const swift = field(toml, "swift") ?? ".";
	if (field(toml, "version") !== version) throw new Error(`${tag}: cairn.toml says version ${field(toml, "version")}`);
	return {
		version,
		kind: field(toml, "kind") === "bin" ? "bin" : "lib",
		swift: has(swift === "." ? "Package.swift" : `${swift}/Package.swift`),
		revision: git("rev-list", "-n1", tag).trim(),
		date: new Date(Number(git("log", "-1", "--format=%ct", tag).trim()) * 1000).toISOString(),
		toolchain: at("lean/lean-toolchain").trim(),
		description: field(toml, "description") ?? "",
		license: field(toml, "license") ?? "",
		dependencies: {},
		libs: list(toml, "libs"),
		claims: parseClaims(at("claims.lock")),
	};
}

const cairn = RELEASES.map(release);
const latest = cairn[0];

// The sample: yap-cairn's manifest (version 0.1.0, depending on cairn ^0.1.1) at its main,
// 97ac1a0, and the ids Cairn's latest ledger marks moved to Yap.
const yap: Version = {
	version: "0.1.0",
	kind: "bin",
	swift: true,
	revision: "97ac1a07937344a39d0c60d1b5853f7351e0dc3f",
	date: "2026-10-24T20:44:00.000Z",
	toolchain: latest.toolchain,
	description: "Hold-to-talk dictation overlay, ported one-to-one from Yap onto Cairn.",
	license: "MIT",
	dependencies: { cairn: "^0.1.1" },
	libs: ["Yap"],
	claims: latest.claims.filter((c) => c.status === "moved:yap").map((c) => ({ ...c, status: "active" })),
};

const fixture = {
	note: "Generated by tools/registry/fixture.ts. Cairn's versions are its real releases; Yap's entry is a sample. Nothing is published to a registry yet.",
	owner: "iamnbutler",
	registry: "cairn.fixture",
	packages: [
		{
			name: "cairn",
			readme: null,
			versions: cairn.map(entry),
			claims: Object.fromEntries(cairn.map((v) => [v.version, v.claims])),
		},
		{
			name: "yap",
			readme: null,
			versions: [entry(yap)],
			claims: { [yap.version]: yap.claims },
		},
	],
};

const text = `${JSON.stringify(fixture, null, "\t")}\n`;
if (process.argv.includes("--check")) {
	let committed = "";
	try {
		committed = readFileSync(OUT, "utf8");
	} catch {}
	if (committed !== text) {
		console.error("site/registry/fixture.json is stale: run `bun tools/registry/fixture.ts`");
		process.exit(1);
	}
} else {
	writeFileSync(OUT, text);
}
