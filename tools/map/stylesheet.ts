// The style.css the maps and the API reference ship: the site's palette and corners
// (site/public/tokens.css), then the pages' own rules (style.css next to this file). One file, so
// a map or a package's docs stand alone off the site.
import { readFileSync } from "node:fs";
import { join } from "node:path";

export const stylesheet = (): string =>
	[join(import.meta.dir, "../../site/public/tokens.css"), join(import.meta.dir, "style.css")].map((f) => readFileSync(f, "utf8")).join("\n");
