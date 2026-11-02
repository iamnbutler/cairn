// Links on the headings, in a module of their own so the docs load them without the scenes
// (scene.js re-exports mountAnchors for the pages that load both).

// Every heading gets an id, and a "#" to its left on hover that copies a link to it. A heading
// keeps the id it has; a claim's heading links to its section's id (^N, so page.html#N stays the
// citation, and the "#" goes left of the claim's row, not between ^N and the title); any other
// heading takes its text as a slug. Headings added later (the video log)
// get theirs as they arrive.
const slugOf = h => {
  const c = h.cloneNode(true);
  c.querySelectorAll(".n, .soon, .anchor, canvas").forEach(e => e.remove());
  return c.textContent.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section";
};

export function mountAnchors(root) {
  if (!document.getElementById("anchor-style")) {
    const style = document.createElement("style");
    style.id = "anchor-style";
    style.textContent = `
:is(h1, h2, h3, h4, .head):has(> a.anchor) { position: relative; scroll-margin-top: 24px; }
a.anchor { position: absolute; right: 100%; padding-right: 0.3em; top: 0; color: inherit; opacity: 0; text-decoration: none; font-weight: 400; }
:is(h1, h2, h3, h4, .head):hover > a.anchor, a.anchor:focus-visible { opacity: 0.45; }
a.anchor:hover { opacity: 0.9; }
a.anchor.copied { opacity: 0.9; }
a.anchor.copied::after { content: "copied"; position: absolute; left: 100%; top: -1.4em; font-size: 12px; white-space: nowrap; }`;
    document.head.append(style);
  }
  const mount = h => {
    const host = h.parentElement.classList.contains("head") ? h.parentElement : h;
    if (host.querySelector(":scope > a.anchor")) return;
    const section = h.closest("section[id]");
    let id = h.id || (section && section.querySelector("h1, h2, h3, h4") === h ? section.id : "");
    if (!id) {
      const base = slugOf(h);
      id = base;
      for (let k = 2; document.getElementById(id); k++) id = `${base}-${k}`;
      h.id = id;
    }
    const a = document.createElement("a");
    a.className = "anchor";
    a.href = `#${id}`;
    a.textContent = "#";
    a.setAttribute("aria-label", "Copy a link to this section");
    a.addEventListener("click", e => {
      e.preventDefault();
      const url = `${location.origin}${location.pathname}#${id}`;
      history.replaceState(null, "", `#${id}`);
      navigator.clipboard?.writeText(url).then(() => {
        a.classList.add("copied");
        setTimeout(() => a.classList.remove("copied"), 1200);
      }).catch(() => {});
    });
    host.prepend(a);
  };
  const all = () => root.querySelectorAll("h1, h2, h3, h4").forEach(mount);
  all();
  new MutationObserver(all).observe(root, { childList: true, subtree: true });
  // An id given here didn't exist when the page loaded, so the browser couldn't scroll to it.
  const target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  if (target) target.scrollIntoView();
}
