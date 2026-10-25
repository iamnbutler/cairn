// The site's own links, in the order every page shows them: the homepage's and /milestones/'s
// title nav (site/web), the docs' bar (site/web/layouts/docs/html.hbs) and the package pages'
// (site/registry.js, in the Worker). `current` is the page or section the reader is in; it gets
// aria-current, which the stylesheets mark.
const LINKS = [
  ["home", "/", "Home"],
  ["milestones", "/milestones/", "Milestones"],
  ["docs", "/docs/", "Docs"],
  ["packages", "/packages/", "Packages"],
  ["maps", "/docs/evidence/", "Maps"],
];
const GITHUB = `<a class="gh" href="https://github.com/iamnbutler/cairn"><img src="/github.svg" alt="">GitHub</a>`;

const link = ([key, href, label], current) =>
  `<a href="${href}"${key === current ? ' aria-current="page"' : ""}>${label}</a>`;

/** The title nav over the homepage's scene and /milestones/'s. */
export const titleNav = (current) =>
  `<nav class="links" aria-label="Site">${LINKS.map((l) => link(l, current)).join("")}${GITHUB}</nav>`;

/** The bar along the top of the docs and the package pages, led by the cairn as Home. */
export const bar = (current) => {
  const items = [`<a class="home" href="/"><img src="/icon.svg" alt="">Cairn</a>`, ...LINKS.slice(1).map((l) => link(l, current)), GITHUB];
  return `<header class="bar">\n${items.map((a) => `  ${a}\n`).join("")}</header>`;
};
