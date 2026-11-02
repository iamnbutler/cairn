// The blog's posts and the progress log, for the feed, the blog's index and the homepage.
//
// Nothing is written twice by hand. The posts are content/blog/<slug>.md, Markdown with a title,
// a date and time, a summary and, for a milestone's post, its milestone ("m5"); the progress log
// is site/public/media.json: videos and stills, written by tools/media/put.sh, and notes,
// entries with a "text" (a list of plain-text paragraphs) and neither, written by hand for work
// that has nothing to show on screen. Each entry belongs to a milestone, and its post's page
// shows it. From them come
//
//   - feed(): /feed.xml, an RSS 2.0 item per post and per log entry, newest first, with full HTML
//     and every URL absolute;
//   - postList(), postPager(): the blog's index and the newer and older links under a post;
//   - progressLog(): a post's progress log, its milestone's entries, newest first;
//   - latest(): the homepage's "latest post" panel;
//   - oldLinks(): where each section of the old /milestones/ page went (a post's `was` id, and
//     every log entry's), so a link from before the blog still lands on it.
//
// Output depends only on those files, never on the clock or git. A problem throws, which fails
// the build and names the file.
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "../../..");
const ORIGIN = "https://cairn.iamnbutler.workers.dev";
const BLOG = "site/web/content/blog";
const MEDIA = "site/public/media.json";
// The page the milestones and their logs were on before the blog. Its ids are links people have,
// and the feed's guids for posts and notes from then are built on it, so they never change.
const OLD = "/milestones/";
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const text = (html: string) =>
	html
		.replace(/<[^>]*>/g, "")
		.replace(/&(amp|lt|gt|quot|#39|apos);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", apos: "'" })[e as string]!)
		.replace(/\s+/g, " ")
		.trim();
// A log entry's heading id (progressLog), and anchors.js's slugOf on plain text.
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "video";
// RFC 822 dates, as RSS 2.0 requires: "Sat, 24 Oct 2026 07:16:39 GMT".
const rfc822 = (d: Date) => d.toUTCString();
// Every URL in feed content absolute: readers resolve relative ones inconsistently, or not at all.
// The site's classes mean nothing in a reader, so they go too.
function absolute(html: string, page: string): string {
	return html.replace(/ class="[^"]*"/g, "").replace(/\b(href|src|poster)="([^"]*)"/g, (_, attr, url) => {
		if (url.startsWith("#")) url = page + url;
		else if (url.startsWith("/")) url = ORIGIN + url;
		else if (!/^(https?:|mailto:)/.test(url)) url = new URL(url, ORIGIN + page).href;
		return `${attr}="${url}"`;
	});
}

// --- Sources ------------------------------------------------------------------------------------

// A log entry is a video, a still (a screenshot: "image" instead of a video) or a note: a note has
// "text" (plain-text paragraphs) instead of either.
type Video = { video: string; poster: string; title: string; caption: string; date: string; published?: string; commit: string; width: number; height: number; seconds: number; milestone?: string };
type Note = { text: string[]; title: string; date: string; published?: string; commit: string; milestone?: string };
type Still = { image: string; webp?: string; title: string; caption: string; date: string; published?: string; commit: string; width: number; height: number; milestone?: string };
type Entry = Video | Still | Note;
const isNote = (e: Entry): e is Note => !("video" in e) && !("image" in e);
const isStill = (e: Entry): e is Still => "image" in e;
type Post = { slug: string; url: string; title: string; html: string; summary: string; date: Date; day: string; milestone?: string; number?: number; status?: string; was?: string };
type Item = { title: string; link: string; guid: string; permalink: boolean; date: Date; html: string };

function sources() {
	const errors: string[] = [];
	const fail = (where: string, message: string) => errors.push(`${where}: ${message}`);
	const videos: Entry[] = JSON.parse(readFileSync(join(ROOT, MEDIA), "utf8"));

	const posts: Post[] = [];
	for (const file of readdirSync(join(ROOT, BLOG)).filter((f) => f.endsWith(".md")).sort()) {
		const where = `${BLOG}/${file}`;
		const src = readFileSync(join(ROOT, BLOG, file), "utf8");
		const m = src.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
		if (!m) { fail(where, "needs front matter between --- lines"); continue; }
		const fm = Bun.YAML.parse(m[1]) as Record<string, unknown>;
		const raw = fm.date instanceof Date ? fm.date.toISOString() : String(fm.date ?? "");
		const date = new Date(raw);
		if (!/T\d\d:\d\d/.test(raw) || isNaN(+date)) { fail(where, `needs a date with a time ("2026-10-26T04:18:05-04:00")`); continue; }
		for (const k of ["title", "summary"]) if (typeof fm[k] !== "string" || !(fm[k] as string).trim()) fail(where, `needs a ${k}`);
		const slug = file.replace(/\.md$/, "");
		posts.push({
			slug, url: `/blog/${slug}/`, title: String(fm.title), summary: String(fm.summary ?? ""), date, day: raw.slice(0, 10),
			html: (Bun.markdown.html(m[2], {}) as string).trim(),
			milestone: fm.milestone ? String(fm.milestone) : undefined, number: typeof fm.number === "number" ? fm.number : undefined,
			status: fm.status ? String(fm.status) : undefined, was: fm.was ? String(fm.was) : undefined,
		});
	}
	if (!posts.length) fail(BLOG, "has no posts");
	posts.sort((a, b) => +b.date - +a.date);
	const postOf = (v: Entry) => posts.find((p) => p.milestone === (v.milestone || "m1"));
	// Where a log entry is shown: under its post, at its heading (progressLog).
	const entryUrl = (v: Entry) => { const p = postOf(v); return `${p ? p.url : "/blog/"}#${slug(v.title)}`; };

	const items: Item[] = [];
	for (const v of videos) {
		const where = `${MEDIA} (${v.title})`;
		const date = new Date(v.published ?? NaN);
		if (!v.published || isNaN(+date)) { fail(where, `needs "published", the time it went up (tools/media/put.sh writes it)`); continue; }
		const post = postOf(v);
		const page = post?.url ?? "/blog/";
		const link = ORIGIN + entryUrl(v);
		const inLog = post ? ` in the progress log of <a href="${post.url}">${esc(post.title)}</a>` : "";
		if (isNote(v)) {
			if (!Array.isArray(v.text) || !v.text.length || v.text.some((t) => typeof t !== "string" || !t.trim())) {
				fail(where, `a note needs "text", a list of paragraphs`);
				continue;
			}
			const html = v.text.map((t) => `<p>${esc(t)}</p>`).join("") + `<p>As of commit ${esc(v.commit)}${post ? "," : ""}${inLog}.</p>`;
			items.push({ title: v.title, link, guid: `${ORIGIN}${OLD}#${slug(v.title)}`, permalink: false, date, html: absolute(html, page) });
			continue;
		}
		if (isStill(v)) {
			const html =
				`<figure><img src="${esc(v.image)}" width="${v.width}" height="${v.height}" alt="${esc(v.title)}">` +
				`<figcaption>${esc(v.caption)}</figcaption></figure>` +
				`<p>A screenshot at commit ${esc(v.commit)}` + (post ? `,${inLog}.` : ".") + "</p>";
			// The guid is the image's content-hashed key, which never changes.
			items.push({ title: v.title, link, guid: `${ORIGIN}${v.image}`, permalink: false, date, html: absolute(html, page) });
			continue;
		}
		const html =
			`<figure><a href="${esc(v.video)}"><img src="${esc(v.poster)}" width="${v.width}" height="${v.height}" alt="${esc(v.title)}"></a>` +
			`<figcaption>${esc(v.caption)}</figcaption></figure>` +
			`<p><a href="${esc(v.video)}">Watch the video</a> (${v.seconds} s), recorded at commit ${esc(v.commit)}` +
			(post ? `,${inLog}.` : ".") + "</p>";
		// The guid is the video's content-hashed key, which never changes; the link is its heading.
		items.push({ title: v.title, link, guid: `${ORIGIN}${v.video}`, permalink: false, date, html: absolute(html, page) });
	}
	for (const p of posts) {
		// In the feed a post's progress log lists the videos and notes, which are items of their own.
		const log = videos.filter((v) => p.milestone && (v.milestone || "m1") === p.milestone);
		const html = p.html + (log.length ? `<p>Progress so far:</p><ul>${log.map((v) => `<li><a href="${entryUrl(v)}">${esc(v.title)}</a> (${v.date})</li>`).join("")}</ul>` : "");
		// A post from before the blog keeps the guid it had then, so readers don't show it again.
		const guid = p.was ? `${ORIGIN}${OLD}#${p.was}` : ORIGIN + p.url;
		items.push({ title: p.title, link: ORIGIN + p.url, guid, permalink: !p.was, date: p.date, html: absolute(html, p.url) });
	}
	items.sort((a, b) => +b.date - +a.date);

	if (errors.length) throw new Error(errors.join("\n"));
	return { posts, videos, items, entryUrl };
}

// --- The feed -----------------------------------------------------------------------------------

const DESCRIPTION = "Research into user interfaces where every action a person can take is a claim with a durable id and machine-checked evidence. The blog and progress videos.";

export function feed(): string {
	const { items } = sources();
	return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>Cairn</title>
<link>${ORIGIN}/</link>
<description>${esc(DESCRIPTION)}</description>
<language>en</language>
<atom:link href="${ORIGIN}/feed.xml" rel="self" type="application/rss+xml"/>
<image><url>${ORIGIN}/apple-touch-icon.png</url><title>Cairn</title><link>${ORIGIN}/</link></image>
${items.length ? `<lastBuildDate>${rfc822(items[0].date)}</lastBuildDate>\n` : ""}${items
	.map(
		(i) => `<item>
<title>${esc(i.title)}</title>
<link>${esc(i.link)}</link>
<guid isPermaLink="${i.permalink}">${esc(i.guid)}</guid>
<pubDate>${rfc822(i.date)}</pubDate>
<description>${esc(i.html)}</description>
</item>
`,
	)
	.join("")}</channel>
</rss>
`;
}

// --- The blog -----------------------------------------------------------------------------------

// A post's line of metadata: its date, and its milestone and how far along it is.
export function postMeta(path: string): string {
	const p = sources().posts.find((x) => x.url === path);
	if (!p) throw new Error(`${path}: not a post in ${BLOG}`);
	const parts = [`<time class="date" datetime="${p.date.toISOString()}">${p.day}</time>`];
	if (p.number) parts.push(`<span>Milestone ${p.number}${p.status ? `, ${esc(p.status)}` : ""}</span>`);
	return parts.join("");
}

// The blog's index: every post, newest first, as a dated title and its summary.
export function postList(): string {
	return `<ol class="posts">${sources()
		.posts.map(
			(p) => `
  <li><p class="meta"><time class="date" datetime="${p.date.toISOString()}">${p.day}</time>${p.number ? `<span>Milestone ${p.number}${p.status ? `, ${esc(p.status)}` : ""}</span>` : ""}</p>
    <h2 id="${p.slug}"><a href="${p.url}">${esc(p.title)}</a></h2>
    <p>${esc(p.summary)}</p></li>`,
		)
		.join("")}
</ol>`;
}

// Under a post: the newer and the older one.
export function postPager(path: string): string {
	const { posts } = sources();
	const k = posts.findIndex((p) => p.url === path);
	const newer = posts[k - 1], older = posts[k + 1];
	const a = (p: Post | undefined, label: string, cls: string) => (p ? `<a class="${cls}" href="${p.url}"><span>${label}</span>${esc(p.title)}</a>` : "");
	return `<nav class="pager" aria-label="Posts">${a(older, "Older", "older")}${a(newer, "Newer", "newer")}</nav>`;
}

// A post's progress log: its milestone's videos, stills and notes, newest first, each under a
// heading with its id. A video fetches nothing until it's played (preload none), and media.js
// gives it its poster when it comes near the window; a still shows its WebP when it has one.
export function progressLog(milestone: string): string {
	const log = sources().videos.filter((v) => (v.milestone || "m1") === milestone);
	if (!log.length) return `<li class="meta">Nothing yet.</li>`;
	const meta = (parts: [string, string][]) =>
		`<div class="meta">${parts.map(([cls, t]) => `<span${cls ? ` class="${cls}"` : ""}>${esc(t)}</span>`).join("")}</div>`;
	return log
		.map((v) => {
			const h = `<h3 id="${slug(v.title)}">${esc(v.title)}</h3>`;
			if (isNote(v)) return `<li>${h}<div class="text">${v.text.map((t) => `<p>${esc(t)}</p>`).join("")}${meta([["date", v.date], ["commit", v.commit]])}</div></li>`;
			const size = `width="${v.width}" height="${v.height}"`;
			const media = isStill(v)
				? `<img src="${esc(v.webp ?? v.image)}" alt="${esc(v.title)}" loading="lazy" ${size}>`
				: `<video src="${esc(v.video)}" data-poster="${esc(v.poster)}" controls muted loop playsinline preload="none" ${size}></video>`;
			const parts: [string, string][] = [["date", v.date], ["commit", v.commit]];
			if (!isStill(v)) parts.push(["", `${v.seconds}s`]);
			return `<li>${h}<figure class="frame" style="--ar: ${v.width / v.height}"><div class="box px">${media}</div><figcaption>${esc(v.caption)}</figcaption>${meta(parts)}</figure></li>`;
		})
		.join("\n");
}

// --- The homepage -------------------------------------------------------------------------------

export function latest(): string {
	const p = sources().posts[0];
	return `<aside class="note latest"><div class="card px">
    <p class="label"><img src="/icon.svg" alt=""><a href="/blog/">Latest post</a></p>
    <h3 id="latest-post"><a href="${p.url}">${esc(p.title)}</a></h3>
    <p>${esc(p.summary)}</p>
    <p class="more"><a href="${p.url}">Read on</a><a href="/blog/">Every post</a><a class="feed" href="/feed.xml">RSS feed</a></p>
  </div></aside>`;
}

// Where every section of the old /milestones/ page went, by its id: a post's heading (its `was`)
// and each log entry's. The milestones lived on the homepage before that, so the homepage sends
// these ids on too; `home` is its HTML, and an id it has itself would be hidden.
export function oldLinks(home = ""): Record<string, string> {
	const { posts, videos, entryUrl } = sources();
	const map: Record<string, string> = {};
	for (const p of posts) if (p.was) map[p.was] = p.url;
	for (const v of videos) map[slug(v.title)] ??= entryUrl(v);
	const both = Object.keys(map).filter((id) => home.includes(`id="${id}"`));
	if (both.length) throw new Error(`content/index.hbs: ${both.map((id) => `#${id}`).join(", ")} also an old /milestones/ id; the redirect would hide it`);
	return map;
}

// Cairn's version, for the homepage's Get started: cairn.toml's, so it changes with the release
// that bumps it.
export function version(): string {
	const m = /^version\s*=\s*"([^"]+)"/m.exec(readFileSync(join(ROOT, "cairn.toml"), "utf8"));
	if (!m) throw new Error("cairn.toml: no version");
	return m[1];
}
