// What every page of the site shares: the links in its head, and its nav.

/** The icons, the font and the palette, then the page's own stylesheet. */
export const head = (stylesheet) =>
  [
    `<link rel="icon" href="/favicon.ico" sizes="32x32">`,
    `<link rel="icon" href="/icon.svg" type="image/svg+xml">`,
    `<link rel="apple-touch-icon" href="/apple-touch-icon.png">`,
    FONT_LINKS,
    `<link rel="stylesheet" href="/tokens.css">`,
    `<link rel="stylesheet" href="${stylesheet}">`,
  ].join("\n");

/** The self-hosted Pixelify Sans (fonts.css), its most used weight preloaded. */
export const FONT_LINKS = `<link rel="preload" href="/fonts/pixelify-sans-latin-600-normal.woff2" as="font" type="font/woff2" crossorigin>\n<link rel="stylesheet" href="/fonts.css">`;

// The site's own links, in the order every page shows them: the homepage's and /milestones/'s
// title nav (site/web), the docs' bar (site/web/layouts/docs/html.hbs) and the package pages'
// (site/registry.js, in the Worker). `current` is the page or section the reader is in; it gets
// aria-current, which the stylesheets mark.
// Packages and GitHub sit apart at the right end ("end" pushes them there).
const LINKS = [
  ["home", "/", "Home"],
  ["docs", "/docs/", "Docs"],
  ["claims", "/docs/evidence/", "Claims"],
  ["milestones", "/milestones/", "Milestones"],
  ["packages", "/packages/", "Packages", "end"],
];
const GITHUB = `<a class="gh" href="https://github.com/iamnbutler/cairn" aria-label="GitHub" title="Cairn on GitHub"><img src="/github.svg" alt=""></a>`;

const link = ([key, href, label, cls], current) =>
  `<a href="${href}"${cls ? ` class="${cls}"` : ""}${key === current ? ' aria-current="page"' : ""}>${label}</a>`;

/** The title nav over the homepage's scene and /milestones/'s. */
export const titleNav = (current) =>
  `<nav class="links" aria-label="Site">${LINKS.map((l) => link(l, current)).join("")}${GITHUB}</nav>`;

/** The bar along the top of the docs and the package pages, led by the cairn as Home. */
export const bar = (current) => {
  const items = [`<a class="home" href="/"><img src="/icon.svg" alt="">Cairn</a>`, ...LINKS.slice(1).map((l) => link(l, current)), GITHUB];
  return `<header class="bar">\n${items.map((a) => `  ${a}\n`).join("")}</header>`;
};
