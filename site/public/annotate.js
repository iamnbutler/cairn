// The anatomy of a claim on the homepage: on a wide window its notes stand in the margins either
// side of the code (site.css), and this draws a dotted leader from each note to what it names, a
// bracketed span or a half's gutter bar. Narrower, the notes are a numbered list and need none.
export function mountLeaders(fig) {
  const wide = matchMedia("(min-width: 1100px)");
  const list = fig.querySelector(".callouts"), pre = fig.querySelector("pre");
  const notes = [...list.children];
  // The notes go in two columns; the list keeps their order for the narrow layout.
  const sides = { l: document.createElement("div"), r: document.createElement("div") };
  for (const k of ["l", "r"]) sides[k].className = `side ${k}`;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.classList.add("leaders");
  svg.setAttribute("aria-hidden", "true");

  function place() {
    if (wide.matches) {
      for (const li of notes) sides[li.classList.contains("l") ? "l" : "r"].append(li);
      if (!sides.l.isConnected) fig.append(sides.l, sides.r, svg);
    } else if (sides.l.isConnected) {
      for (const li of notes) list.append(li);
      sides.l.remove(); sides.r.remove(); svg.remove();
    }
    draw();
  }

  function draw() {
    if (!wide.matches) return;
    const f = fig.getBoundingClientRect(), p = pre.getBoundingClientRect();
    const rel = (x, y) => [Math.round(x - f.left), Math.round(y - f.top)];
    const parts = [];
    for (const k of ["l", "r"]) {
      const mine = notes.filter(li => li.classList.contains(k));
      mine.forEach((li, i) => {
        const t = document.getElementById(li.dataset.for);
        if (!t) return;
        const n = li.querySelector("b").getBoundingClientRect(), r = t.getBoundingClientRect();
        const left = k === "l";
        // Out of the note's heading, along to a lane beside the code, then to the target.
        const [sx, sy] = rel(left ? n.right + 10 : n.left - 10, n.top + n.height / 2);
        const lane = left ? p.left - 12 - i * 6 : p.right + 12 + i * 6;
        let path, end;
        if (t.classList.contains("ln")) {
          // A half: the middle of its gutter bar.
          const lines = [...pre.querySelectorAll(`.ln.${t.classList.contains("people") ? "people" : "checker"}`)];
          const top = lines[0].getBoundingClientRect().top, bottom = lines.at(-1).getBoundingClientRect().bottom;
          const [lx] = rel(lane, 0), [bx, by] = rel(p.left, (top + bottom) / 2);
          path = `M${sx} ${sy}H${lx}V${by}H${bx}`;
          end = [bx, by];
        } else {
          // A span: under its bracket, in the gap between lines, then up into it.
          const [lx] = rel(lane, 0), [tx, ty] = rel(r.left + r.width / 2, r.bottom + 5);
          path = `M${sx} ${sy}H${lx}V${ty}H${tx}V${ty - 4}`;
          end = [tx, ty - 4];
        }
        parts.push(`<path d="${path}"/><rect x="${end[0] - 2}" y="${end[1] - 2}" width="4" height="4"/>`, `<rect x="${sx - 2}" y="${sy - 2}" width="4" height="4"/>`);
      });
    }
    svg.innerHTML = parts.join("");
  }

  place();
  wide.addEventListener("change", place);
  new ResizeObserver(draw).observe(fig);
  document.fonts?.ready.then(draw);
}
