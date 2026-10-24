// cairn doc's search and the module page's order toggle (docs/doc.md). Plain script, no modules,
// so the pages work from disk too. The index is search-index.js: [name, kind, href, text], one
// row per module, declaration and claim.
(() => {
  const index = window.CAIRN_DOC_INDEX || [];
  const input = document.getElementById("search");
  const box = document.getElementById("results");
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const last = (n) => n.split(".").pop();

  // Names first (the last component exact, then a prefix of it, then anywhere in the name), then
  // doc text. `^12` finds claim 12.
  const search = (q) => {
    q = q.trim().toLowerCase();
    if (!q) return [];
    const id = /^\^?(\d+)$/.exec(q);
    const scored = [];
    for (const row of index) {
      const [name, , , text] = row;
      const n = name.toLowerCase();
      const l = last(n);
      let s = 0;
      if (id && n.startsWith(`^${id[1]} `)) s = 100;
      else if (id && n.startsWith(`^${id[1]}`)) s = 80;
      else if (l === q) s = 90;
      else if (l.startsWith(q)) s = 70;
      else if (n.includes(q)) s = 50;
      else if (q.length > 2 && text.toLowerCase().includes(q)) s = 10;
      if (s) scored.push([s - n.length / 1000, row]);
    }
    return scored.sort((a, b) => b[0] - a[0]).slice(0, 40).map((x) => x[1]);
  };
  let picked = 0;
  const show = () => {
    const hits = search(input.value);
    picked = Math.min(picked, Math.max(hits.length - 1, 0));
    box.hidden = !input.value.trim();
    box.innerHTML = hits.length
      ? hits.map(([name, kind, href, text], k) => `<a href="${esc(href)}"${k === picked ? ' class="on"' : ""}><span class="k">${esc(kind)}</span><span class="nm">${esc(name)}</span>${text ? `<span class="tx">${esc(text.slice(0, 140))}</span>` : ""}</a>`).join("")
      : `<p class="none">Nothing matches.</p>`;
  };
  if (input && box) {
    input.addEventListener("input", () => { picked = 0; show(); });
    input.addEventListener("keydown", (e) => {
      const links = box.querySelectorAll("a");
      if (e.key === "ArrowDown") { picked = Math.min(picked + 1, links.length - 1); show(); e.preventDefault(); }
      else if (e.key === "ArrowUp") { picked = Math.max(picked - 1, 0); show(); e.preventDefault(); }
      else if (e.key === "Enter" && links[picked]) location.href = links[picked].href;
      else if (e.key === "Escape") { input.value = ""; show(); input.blur(); }
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "/" && document.activeElement !== input) { e.preventDefault(); input.focus(); }
    });
    document.addEventListener("click", (e) => { if (!e.target.closest(".search")) box.hidden = true; });
    input.addEventListener("focus", () => { if (input.value.trim()) show(); });
  }

  // Module pages: declarations grouped by kind (the default), or as in the source, where the
  // module's section comments sit between them.
  const items = document.getElementById("items");
  const buttons = document.querySelectorAll(".order button");
  if (items && buttons.length) {
    const original = [...items.children];
    const setOrder = (order) => {
      buttons.forEach((b) => b.classList.toggle("on", b.dataset.order === order));
      if (order === "source") {
        const entries = original.filter((e) => e.dataset.line);
        entries.sort((a, b) => Number(a.dataset.line) - Number(b.dataset.line));
        original.forEach((e) => { if (!e.dataset.line) e.hidden = true; });
        items.querySelectorAll(".mdoc").forEach((e) => (e.hidden = false));
        entries.forEach((e) => items.append(e));
      } else {
        original.forEach((e) => { e.hidden = e.classList.contains("mdoc"); items.append(e); });
      }
      try { localStorage.setItem("cairn-doc-order", order); } catch {}
    };
    buttons.forEach((b) => b.addEventListener("click", () => setOrder(b.dataset.order)));
    let saved = "kind";
    try { saved = localStorage.getItem("cairn-doc-order") || "kind"; } catch {}
    if (saved !== "kind") setOrder(saved);
  }
})();
