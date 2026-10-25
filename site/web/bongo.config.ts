import { markdown } from "@bongo/markdown";
import type { Config, Loader } from "bongo";

const md = markdown({ headingIds: true });
const mdLoader = md.$loaders!.md as Loader;

import { codeBlock, esc, include } from "./lib/source";
import { checkLinks, inline, pager, sidebar } from "./lib/docs";
import { feed, latest, movedIds, version } from "./lib/site";
import { ogCards } from "./lib/og";
import { bar, head, titleNav } from "../chrome.js";
import { architecture } from "./lib/architecture";

export default {
	$site: {
		lang: "en",
		title: "Cairn",
		url: "https://cairn.iamnbutler.workers.dev/",
		description: "Research into user interfaces where every action a person can take is a claim with a durable id and machine-checked evidence.",
	},
	$utils: { inline, checkLinks, sidebar, pager, feed, latest, movedIds, version, ogCards, bar, head, titleNav, architecture },
	$partials: {
		// <bongo:include src="lean/Examples/Counter.lean#counter-reset" />
		include(args: { src: string }) {
			const [path] = args.src.split("#");
			const r = include(args.src, "include");
			if (!path.endsWith(".md")) return codeBlock(path, r);
			// Internal notes: their links point into the private repository, so keep only the text. A
			// fenced block in the region becomes a code figure like any other include, captioned with
			// its own lines in the note.
			const lines = r.text.split("\n");
			let out = "";
			let prose: string[] = [];
			const flush = () => {
				if (prose.length) out += inline(prose.join("\n").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"), true);
				prose = [];
			};
			for (let k = 0; k < lines.length; k++) {
				const open = lines[k].match(/^\s*```\s*(\w*)/);
				if (!open) {
					prose.push(lines[k]);
					continue;
				}
				const end = lines.findIndex((l, j) => j > k && /^\s*```\s*$/.test(l));
				if (end < 0) throw new Error(`${args.src} has a fenced block that never closes`);
				flush();
				const lang = open[1] === "lean" || open[1] === "swift" ? open[1] : "make";
				out += codeBlock(path, { text: lines.slice(k + 1, end).join("\n"), first: r.first + k + 1, last: r.first + end - 1 }, lang);
				k = end;
			}
			flush();
			return out;
		},
		// <bongo:note label="Today">Markdown</bongo:note>: a note card. bongo passes a slot of one
		// paragraph without its <p>, so it goes back on.
		note(args: { label: string; $slot?: string }) {
			const slot = (args.$slot ?? "").trim();
			const body = /^<(p|ul|ol|div|figure|table|h[1-6]|pre|blockquote)\b/.test(slot) ? slot : `<p>${slot}</p>`;
			return `<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">${esc(args.label)}</p>${body}</div></aside>`;
		},
	},
	$hooks: {
		transform(text, ctx) {
			// A docs table scrolls on its own on a narrow screen.
			if (ctx.kind !== "page" || !ctx.path.startsWith("/docs/")) return text;
			return text.replace(/<table>/g, '<div class="wrap"><table>').replace(/<\/table>/g, "</table></div>");
		},
	},
	plugins: [
		{
			...md,
			$loaders: {
				async md(filename, content, utils) {
					// A page never holds a code sample: it includes one from a source file.
					const fence = utils.decode(content).split("\n").findIndex((l) => /^\s*(```|~~~)/.test(l));
					if (fence >= 0) throw new Error(`${filename}:${fence + 1}: a fenced code block: include the code from a source file instead`);
					return mdLoader(filename, content, utils);
				},
			},
		},
	],
} satisfies Config;

