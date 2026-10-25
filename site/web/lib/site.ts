// The milestones' posts and the progress log, for the feed and the homepage.
//
// Nothing is written twice by hand. The posts are the `article.post`s in
// content/milestones/index.hbs, each an h2 with a permanent id and a <time datetime>; the
// progress log is site/public/media.json: videos, written by tools/media/put.sh, and notes, entries
// with a "text" (a list of plain-text paragraphs) and no video, written by hand for work that
// has nothing to show on screen. From them come
//
//   - feed(): /feed.xml, an RSS 2.0 item per milestone and per log entry, newest first, with full
//     HTML and every URL absolute;
//   - latest(): the homepage's "latest milestone" panel;
//   - movedIds(): the ids that moved from the homepage to /milestones/, so a link from before the
//     move (/#second-milestone-yap-on-cairn) still lands on its section.
//
// Output depends only on those files, never on the clock or git. A problem throws, which fails
// the build and names the file.
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "../../..");
const ORIGIN = "https://cairn.iamnbutler.workers.dev";
const MILESTONES = "site/web/content/milestones/index.hbs";
const MEDIA = "site/public/media.json";

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const text = (html: string) =>
	html
		.replace(/<[^>]*>/g, "")
		.replace(/&(amp|lt|gt|quot|#39|apos);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", apos: "'" })[e as string]!)
		.replace(/\s+/g, " ")
		.trim();
// media.js's videoId, and scene.js's slugOf on plain text.
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

// A log entry is a video or a note: a note has "text" (plain-text paragraphs) instead of a video.
type Video = { video: string; poster: string; title: string; caption: string; date: string; published?: string; commit: string; width: number; height: number; seconds: number; milestone?: string };
type Note = { text: string[]; title: string; date: string; published?: string; commit: string; milestone?: string };
type Entry = Video | Note;
const isNote = (e: Entry): e is Note => !("video" in e);
type Post = { id: string; title: string; html: string; first: string; date: Date; milestone?: string; ids: string[] };
type Item = { title: string; link: string; guid: string; permalink: boolean; date: Date; html: string };

function sources() {
	const errors: string[] = [];
	const fail = (where: string, message: string) => errors.push(`${where}: ${message}`);
	const milestonesHtml = readFileSync(join(ROOT, MILESTONES), "utf8");
	const videos: Entry[] = JSON.parse(readFileSync(join(ROOT, MEDIA), "utf8"));

	const posts: Post[] = [];
	for (const [, body] of milestonesHtml.matchAll(/<article class="post">([\s\S]*?)<\/article>/g)) {
		const h = body.match(/<h2 id="([^"]+)">([\s\S]*?)<\/h2>/);
		if (!h) { fail(MILESTONES, "an article.post has no <h2 id=...>"); continue; }
		const [, id, inner] = h;
		const title = text(inner.replace(/<span class="soon">[\s\S]*?<\/span>/, ""));
		const t = body.match(/<time[^>]*datetime="([^"]+)"/);
		const date = t ? new Date(t[1]) : new Date(NaN);
		if (!t || !/T\d\d:\d\d/.test(t[1]) || isNaN(+date)) { fail(MILESTONES, `#${id} needs a <time datetime="…"> with a date and time`); continue; }
		const milestone = body.match(/<ul id="log-([^"]+)"/)?.[1];
		// The post's body: everything after the heading and its date line.
		const html = body.slice(body.indexOf(h[0]) + h[0].length).replace(/\s*<p class="meta"><time[\s\S]*?<\/p>/, "").trim();
		const first = html.match(/<p>([\s\S]*?)<\/p>/)?.[1] ?? html.match(/<li>([\s\S]*?)<\/li>/)?.[1] ?? "";
		const ids = [id, ...[...body.matchAll(/<h[2-4] id="([^"]+)"/g)].map((m) => m[1]).filter((x) => x !== id)];
		posts.push({ id, title, html, first, date, milestone, ids });
	}
	if (!posts.length) fail(MILESTONES, "has no article.post");

	const PAGE = "/milestones/";
	const permalink = (id: string) => `${ORIGIN}${PAGE}#${id}`;

	const items: Item[] = [];
	for (const v of videos) {
		const where = `${MEDIA} (${v.title})`;
		const date = new Date(v.published ?? NaN);
		if (!v.published || isNaN(+date)) { fail(where, `needs "published", the time it went up (tools/media/put.sh writes it)`); continue; }
		const post = posts.find((p) => p.milestone === (v.milestone || "m1"));
		const inLog = post ? ` in the progress log of <a href="${PAGE}#${post.id}">${esc(post.title)}</a>` : "";
		if (isNote(v)) {
			if (!Array.isArray(v.text) || !v.text.length || v.text.some((t) => typeof t !== "string" || !t.trim())) {
				fail(where, `a note needs "text", a list of paragraphs`);
				continue;
			}
			const html = v.text.map((t) => `<p>${esc(t)}</p>`).join("") + `<p>As of commit ${esc(v.commit)}${post ? "," : ""}${inLog}.</p>`;
			items.push({ title: v.title, link: permalink(slug(v.title)), guid: permalink(slug(v.title)), permalink: true, date, html: absolute(html, PAGE) });
			continue;
		}
		const html =
			`<figure><a href="${esc(v.video)}"><img src="${esc(v.poster)}" width="${v.width}" height="${v.height}" alt="${esc(v.title)}"></a>` +
			`<figcaption>${esc(v.caption)}</figcaption></figure>` +
			`<p><a href="${esc(v.video)}">Watch the video</a> (${v.seconds} s), recorded at commit ${esc(v.commit)}` +
			(post ? `,${inLog}.` : ".") + "</p>";
		// The guid is the video's content-hashed key, which never changes; the link is its heading.
		items.push({ title: v.title, link: permalink(slug(v.title)), guid: `${ORIGIN}${v.video}`, permalink: false, date, html: absolute(html, PAGE) });
	}
	for (const p of posts) {
		// The progress log is filled in by the page's script; in the feed it lists the videos and
		// notes, which are items of their own.
		const log = videos.filter((v) => (v.milestone || "m1") === p.milestone);
		const html = p.html.replace(/<ul id="log-[^"]+"[^>]*>[\s\S]*?<\/ul>/, () =>
			log.length
				? `<p>Progress so far:</p><ul>${log.map((v) => `<li><a href="${PAGE}#${slug(v.title)}">${esc(v.title)}</a> (${v.date})</li>`).join("")}</ul>`
				: "",
		);
		items.push({ title: p.title, link: permalink(p.id), guid: permalink(p.id), permalink: true, date: p.date, html: absolute(html, PAGE) });
	}
	items.sort((a, b) => +b.date - +a.date);

	if (errors.length) throw new Error(errors.join("\n"));
	return { posts, videos, items };
}

// --- The feed -----------------------------------------------------------------------------------

const DESCRIPTION = "Research into user interfaces where every action a person can take is a claim with a durable id and machine-checked evidence. Milestones and progress videos.";

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

// --- The homepage -------------------------------------------------------------------------------

export function latest(): string {
	const latest = [...sources().posts].sort((a, b) => +b.date - +a.date)[0];
	return `<aside class="note latest"><div class="card px">
    <p class="label"><img src="/icon.svg" alt=""><a href="/milestones/">Latest milestone</a></p>
    <h3 id="latest-milestone"><a href="/milestones/#${latest.id}">${esc(latest.title)}</a></h3>
    <p>${latest.first.trim()}</p>
    <p class="more"><a href="/milestones/#${latest.id}">Read on</a><a href="/milestones/">Every milestone</a><a class="feed" href="/feed.xml">RSS feed</a></p>
  </div></aside>`;
}

// Every id that lives on /milestones/: the posts' headings and the log entries' (media.js's
// videoId). `home` is the homepage's HTML: an id in both would be hidden by the redirect.
export function movedIds(home: string): string[] {
	const { posts, videos } = sources();
	const moved = [...posts.flatMap((p) => p.ids), ...videos.map((v) => slug(v.title))];
	const both = moved.filter((id) => home.includes(`id="${id}"`));
	if (both.length) throw new Error(`content/index.hbs: ${both.map((id) => `#${id}`).join(", ")} also on /milestones/; the redirect would hide it`);
	return moved;
}
