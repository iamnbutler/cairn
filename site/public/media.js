// The progress log under a post is in the page's HTML (site/web/lib/site.ts's progressLog, from
// media.json). Its videos fetch nothing until they're played (preload "none"); this gives each
// its poster, the frame most readers see, when it comes within a screen or so of the window.
export function posters(root) {
  const near = new IntersectionObserver(es => {
    for (const e of es) if (e.isIntersecting) { e.target.poster = e.target.dataset.poster; near.unobserve(e.target); }
  }, { rootMargin: "100% 0px" });
  root.querySelectorAll("video[data-poster]").forEach(v => near.observe(v));
}
