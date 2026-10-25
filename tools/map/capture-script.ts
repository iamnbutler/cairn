// The capture script for `make capture` (docs/claim-pages.md): an app's claims export → the
// sequences Cairn<App> --map-capture screenshots: the initial state, each flow's witness, and
// each move no flow presses.
//
//   bun tools/map/capture-script.ts --claims claims.json > script.json
//
// Kept for a per-claim visual export on the claim pages (/packages/<name>/<version>/claims/<id>/),
// which doesn't exist yet. evidence.ts also decides the statuses `cairn doc` shows.
import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { captureScript, type Claim } from "./evidence";

const { values: opts } = parseArgs({ options: { claims: { type: "string" } } });
if (!opts.claims) {
	console.error("usage: capture-script.ts --claims <claims.json>");
	process.exit(1);
}
const { claims } = JSON.parse(readFileSync(opts.claims, "utf8")) as { claims: Claim[] };
console.log(JSON.stringify(captureScript(claims), null, 2));
