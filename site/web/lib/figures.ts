// Figures in a docs page's Markdown: an HTML comment `<!-- figure: replay -->` on a line of its own
// becomes the figure, when the docs layout renders the page ({{{ $utils.figures($page.content) }}}).
// Markdown passes comments through untouched, and tools/site/llms.ts drops them from the page's
// Markdown copy. A name with no figure fails the build.
import { anatomy, anatomyFull } from "./anatomy";
import { gate, kinds, ledger, names, replay, rungs, stateField } from "./claims";

const FIGURES: Record<string, () => string> = { anatomy, anatomyFull, replay, stateField, gate, names, ledger, kinds, rungs };

export const figures = (html: string) =>
	html.replace(/<!-- figure: (\w+) -->/g, (_, name: string) => {
		const f = FIGURES[name];
		if (!f) throw new Error(`figures: no figure named ${name}`);
		return f();
	});
