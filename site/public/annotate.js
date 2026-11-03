// The anatomy of a claim on the homepage: on a wide window its notes stand in the margins either
// side of the code (site.css places them), and this draws a dotted leader from each note to what
// it names, a bracketed span or a half's gutter bar. Pointing at a note lights its leader and what
// it names. Narrower, the notes are a numbered list and need none.
export function mountLeaders(fig) {
  const wide = matchMedia("(min-width: 1100px)");
  const pre = fig.querySelector("pre");
  const notes = [...fig.querySelectorAll(".callouts li")];
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.classList.add("leaders");
  svg.setAttribute("aria-hidden", "true");
  fig.append(svg);

  // Leaders on one side each run out of a note's heading to a lane of their own beside the code,
  // along it, and in to the target. They never cross if a leader whose lane passes another's
  // heading takes the lane nearer the code (the other's run out stops short of it), and one whose
  // lane passes another's target takes the lane further out (the other's run in starts inside it).
  function lanes(legs) {
    const spans = legs.map(l => [Math.min(l.sy, l.ty), Math.max(l.sy, l.ty)]);
    const inside = (k, y) => y > spans[k][0] && y < spans[k][1];
    const before = legs.map(() => new Set()); // before[b] holds a: a takes a lane nearer the code than b
    legs.forEach((_, a) => legs.forEach((b, j) => {
      if (a === j) return;
      if (inside(a, b.sy)) before[j].add(a);
      if (inside(a, b.ty)) before[a].add(j);
    }));
    const rank = [], left = new Set(legs.keys());
    while (left.size) {
      // Nearest first: a leader nothing still unplaced must sit inside of. A cycle (none on this
      // figure) falls back to the order of the notes.
      const next = [...left].find(k => [...before[k]].every(a => !left.has(a))) ?? Math.min(...left);
      rank[next] = legs.length - left.size;
      left.delete(next);
    }
    return rank;
  }

  function draw() {
    if (!wide.matches) { svg.innerHTML = ""; return; }
    const f = fig.getBoundingClientRect(), p = pre.getBoundingClientRect();
    const rel = (x, y) => [Math.round(x - f.left), Math.round(y - f.top)];
    const parts = [];
    for (const k of ["l", "r"]) {
      const left = k === "l";
      const legs = notes.filter(li => li.classList.contains(k)).map(li => {
        const t = document.getElementById(li.dataset.for);
        if (!t) return null;
        const n = li.querySelector("b").getBoundingClientRect(), r = t.getBoundingClientRect();
        const [sx, sy] = rel(left ? n.right + 10 : n.left - 10, n.top + n.height / 2);
        if (t.classList.contains("ln")) {
          // A half: the middle of its gutter bar.
          const lines = [...pre.querySelectorAll(`.ln.${t.classList.contains("people") ? "people" : "checker"}`)];
          const top = lines[0].getBoundingClientRect().top, bottom = lines.at(-1).getBoundingClientRect().bottom;
          const [tx, ty] = rel(p.left, (top + bottom) / 2);
          return { li, sx, sy, tx, ty, end: [tx, ty], up: 0 };
        }
        // A span: under its bracket, in the gap between lines, then up into it.
        const [tx, ty] = rel(r.left + r.width / 2, r.bottom + 5);
        return { li, sx, sy, tx, ty, end: [tx, ty - 4], up: 4 };
      }).filter(Boolean);
      const rank = lanes(legs);
      legs.forEach((l, i) => {
        const [lx] = rel(left ? p.left - 12 - rank[i] * 6 : p.right + 12 + rank[i] * 6, 0);
        const path = `M${l.sx} ${l.sy}H${lx}V${l.ty}H${l.tx}${l.up ? `V${l.ty - l.up}` : ""}`;
        const dot = ([x, y]) => `<rect x="${x - 2}" y="${y - 2}" width="4" height="4"/>`;
        parts.push(`<g data-for="${l.li.dataset.for}"><path d="${path}"/>${dot(l.end)}${dot([l.sx, l.sy])}</g>`);
      });
    }
    svg.innerHTML = parts.join("");
    svg.classList.add("on");
  }

  // Pointing at a note lights its leader and its bracket.
  for (const li of notes) {
    const light = on => {
      if (!wide.matches) return;
      svg.querySelector(`g[data-for="${li.dataset.for}"]`)?.classList.toggle("hot", on);
      document.getElementById(li.dataset.for)?.classList.toggle("hot", on);
      li.classList.toggle("hot", on);
      fig.classList.toggle("pointing", on);
    };
    li.addEventListener("pointerenter", () => light(true));
    li.addEventListener("pointerleave", () => light(false));
  }

  wide.addEventListener("change", draw);
  new ResizeObserver(draw).observe(fig);
  document.fonts?.ready.then(draw);
}
