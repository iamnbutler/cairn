// The link preview card, as the HTML bongo's $assets.render hands satori (through
// site/web/partials/og/card.ts). A label (the gold line, '' for none), a title and an optional
// line below it, over assets/og/scene.png: the homepage's scene and shade with no text, drawn by
// `make og-scene` after a change to the scene.

export type Args = { label: string; title: string; line?: string };
type Style = Record<string, string | number>;
type El = { type: string; props: { style?: Style; children?: Child | Child[]; [attr: string]: unknown } };
type Child = El | string;

const el = (type: string, style: Style, children?: Child | Child[], attrs: Record<string, unknown> = {}): El => ({
	type,
	props: { ...attrs, style, ...(children === undefined ? {} : { children }) },
});

// The assets the card names, relative to site/web/assets.
const FONTS = [
	{ name: "Pixelify Sans", weight: 500, src: "fonts/pixelify-sans-latin-500-normal.woff" },
	{ name: "Pixelify Sans", weight: 600, src: "fonts/pixelify-sans-latin-600-normal.woff" },
] as const;
const SCENE = "og/scene.png";
const ICON = "og/icon.svg";

/** The card's tree, its images named by their paths under site/web/assets. */
function card({ label, title, line }: Args): El {
	const brand = title !== "Cairn";
	const n = title.length;
	const size = n <= 12 ? 112 : n <= 20 ? 96 : n <= 30 ? 80 : 68;
	const shadow = "3px 3px 0 #2b2d6a";
	const text: Child[] = [];
	if (brand)
		text.push(
			el("div", { display: "flex", alignItems: "center", fontWeight: 600, fontSize: "30px", letterSpacing: "1px", textShadow: shadow }, [
				el("img", { marginRight: "16px" }, undefined, { src: ICON, width: 48, height: 48 }),
				"Cairn",
			]),
		);
	if (label) text.push(el("div", { display: "flex", marginTop: "34px", fontWeight: 600, fontSize: "34px", color: "#f2c46a", textShadow: shadow }, label));
	text.push(
		el(
			"div",
			{ display: "flex", marginTop: `${label ? 14 : brand ? 34 : 0}px`, fontWeight: 600, fontSize: `${size}px`, lineHeight: 1.05, textShadow: "5px 5px 0 #2b2d6a" },
			title,
		),
	);
	if (line)
		text.push(
			el("div", { display: "flex", marginTop: "28px", maxWidth: "640px", fontWeight: 500, fontSize: "32px", lineHeight: 1.35, textShadow: shadow }, line),
		);
	return el("div", { display: "flex", position: "relative", width: "1200px", height: "630px", fontFamily: "Pixelify Sans", color: "#f3efff" }, [
		el("img", { position: "absolute", left: 0, top: 0 }, undefined, { src: SCENE, width: 1200, height: 630 }),
		el(
			"div",
			{ display: "flex", flexDirection: "column", justifyContent: "center", position: "absolute", left: "72px", top: 0, width: "680px", height: "630px" },
			text,
		),
	]);
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const css = (style: Style) =>
	Object.entries(style)
		.map(([k, v]) => `${k.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}: ${v}`)
		.join("; ");

function html(node: Child): string {
	if (typeof node === "string") return esc(node);
	const { style, children, ...attrs } = node.props;
	const open = [node.type, ...(style ? [`style="${esc(css(style))}"`] : []), ...Object.entries(attrs).map(([k, v]) => `${k}="${esc(String(v))}"`)].join(" ");
	if (children === undefined) return `<${open}/>`;
	return `<${open}>${(Array.isArray(children) ? children : [children]).map(html).join("")}</${node.type}>`;
}

/** The card as the HTML bongo's $assets.render reads: its fonts as @font-face, then the tree. */
export const cardHtml = (args: Args): string =>
	`<style>${FONTS.map((f) => `@font-face { font-family: ${f.name}; src: url(${f.src}) format('woff'); font-weight: ${f.weight} }`).join("\n")}</style>${html(card(args))}`;
