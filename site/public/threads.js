// The architecture figure on the homepage (web/lib/architecture.ts lays it out, site.css places
// it). This draws its connectors in an overlay and runs a playhead along the time axis: across the
// lanes on a wide window, down them on a narrow one. The CSS places every step, so nothing here
// moves the page; the overlay fades in once it's drawn.
//
// As the playhead passes a step it lights; the frame it publishes gets the next number, and every
// display refresh after that paints it, while the refreshes before kept painting the old one.
// Following animation/loops.md in the prompt library, each frame is a function of the time since
// mount alone: the playhead's place is the phase of an 8s loop, the frame number counts loops, so
// nothing is carried between frames and the loop never jumps. It pauses off screen and in a
// hidden tab, and with reduced motion the figure stays a still: the moment after frame 42 lands.

const D = 8000; // one key press, ms
const SWEEP = [0.06, 0.86]; // the part of the loop the playhead moves in
const FADE = 0.05; // its fade in before and out after, as a part of the loop
const TRAIL = 96; // px of wire lit behind the playhead
const FIRST = 42; // the frame the still shows

const NS = "http://www.w3.org/2000/svg";

export function mountThreads(fig) {
  const lanes = fig.querySelector(".lanes");
  const $ = id => fig.querySelector(`#th-${id}`);
  const strip = $("ticks");
  const ticks = [...strip.querySelectorAll(".tk")];
  const nums = { frame: $("frame").querySelector(".n"), ask: $("ask").querySelector(".n") };
  const lights = [$("key"), $("queue"), ...fig.querySelectorAll(".chip"), $("frame"), $("ask")];
  const wires = [["key", "queue"], ["queue", "work"], ["work", "frame"], ["frame", "ticks"], ["frame", "ask", "dash"]];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");

  const svg = document.createElementNS(NS, "svg");
  svg.classList.add("wires");
  svg.setAttribute("aria-hidden", "true");
  lanes.append(svg);

  let g = null; // geometry, from measure()
  let raf = 0, visible = false, t0 = performance.now();
  const shown = new Map(); // what each number and light currently shows, to touch the DOM only on change

  function box(el, L) {
    const r = el.getBoundingClientRect();
    return { l: r.left - L.left, t: r.top - L.top, r: r.right - L.left, b: r.bottom - L.top };
  }

  // A wire from a to b: straight when they share a row or a column, else an elbow that leaves a
  // toward b's lane and turns along the time axis into b's leading edge. 4px clear of both ends.
  function route(a, b, x) {
    const [A0, A1, C0, C1] = x ? ["l", "r", "t", "b"] : ["t", "b", "l", "r"];
    const P = (along, cross) => (x ? [along, cross] : [cross, along]);
    const overlap = (p, q, lo, hi) => [Math.max(p[lo], q[lo]), Math.min(p[hi], q[hi])];
    const gap = 4;
    let [lo, hi] = overlap(a, b, C0, C1);
    if (hi - lo > 8) {
      const c = Math.round((lo + hi) / 2), fwd = b[A0] >= a[A1];
      return [P(fwd ? a[A1] + gap : a[A0] - gap, c), P(fwd ? b[A0] - gap : b[A1] + gap, c)];
    }
    [lo, hi] = overlap(a, b, A0, A1);
    if (hi - lo > 8) {
      const c = Math.round((lo + hi) / 2), fwd = b[C0] >= a[C1];
      return [P(c, fwd ? a[C1] + gap : a[C0] - gap), P(c, fwd ? b[C0] - gap : b[C1] + gap)];
    }
    const ac = Math.round((a[A0] + a[A1]) / 2), bc = Math.round((b[C0] + b[C1]) / 2), down = b[C0] >= a[C1];
    // Rows of lanes carry their names above the steps, so there the wire runs on out of a, drops
    // in the gap before b and turns into it, clear of the text. Columns turn once.
    if (x) {
      const ar = Math.round((a[C0] + a[C1]) / 2), mid = Math.round((a[A1] + b[A0]) / 2);
      return [P(a[A1] + gap, ar), P(mid, ar), P(mid, bc), P(b[A0] - gap, bc)];
    }
    return [P(ac, down ? a[C1] + gap : a[C0] - gap), P(ac, bc), P(b[A0] - gap, bc)];
  }

  // An open chevron at the end of a wire, pointing the way its last leg runs.
  function head(pts) {
    const [[x0, y0], [x1, y1]] = pts.slice(-2), k = 6;
    const dx = Math.sign(x1 - x0), dy = Math.sign(y1 - y0);
    return `${x1 - dx * k - dy * k},${y1 - dy * k - dx * k} ${x1},${y1} ${x1 - dx * k + dy * k},${y1 - dy * k + dx * k}`;
  }

  function measure() {
    const L = lanes.getBoundingClientRect();
    if (!L.width) return;
    const x = getComputedStyle(strip).flexDirection === "row";
    const at = el => box(el, L);
    const along = r => (x ? [r.l, r.r] : [r.t, r.b]);
    const marks = ticks.map(tk => {
      const r = at(tk);
      return x ? (r.l + r.r) / 2 : (r.t + r.b) / 2;
    });
    const paths = wires.map(([a, b, cls]) => {
      const pts = route(at($(a)), at($(b)), x);
      return { d: `M${pts.map(p => p.join(" ")).join("L")}`, head: head(pts), cls: cls ?? "" };
    });
    // The playhead runs over the moments only, from just before the first refresh to the end.
    const [s0, s1] = along(at(strip));
    const span = [Math.max(0, s0 - 12), x ? L.width : L.height];
    g = { x, W: L.width, H: L.height, span, marks, publish: along(at($("frame")))[0],
      lit: lights.map(el => [el, ...along(at(el))]) };
    const wire = cls => paths.map(p => `<path class="${cls} ${p.cls}" d="${p.d}"/><polyline class="${cls}" points="${p.head}"/>`).join("");
    svg.innerHTML = `<defs><clipPath id="th-trail"><rect/></clipPath></defs>${wire("w")}<g clip-path="url(#th-trail)">${wire("hot")}</g><line class="ph"/>`;
    g.rect = svg.querySelector("rect");
    g.line = svg.querySelector("line");
    g.trail = svg.querySelector("g");
    still();
    svg.classList.add("on");
    if (running()) frame(performance.now());
  }

  const flags = new Map();
  function setClass(el, cls, on) {
    const k = el, v = flags.get(k) ?? {};
    if (v[cls] === on) return;
    v[cls] = on;
    flags.set(k, v);
    el.classList.toggle(cls, on);
  }

  function set(el, key, value) {
    if (shown.get(el) === value) return;
    shown.set(el, value);
    if (key === "text") el.textContent = value;
    else el.classList.toggle("lit", value);
  }

  // The still: frame 42 just published, the refreshes before it painted 41.
  function still() {
    if (!g) return;
    g.marks.forEach((m, i) => {
      set(ticks[i].querySelector(".n"), "text", String(m < g.publish ? FIRST - 1 : FIRST));
      set(ticks[i], "lit", false);
      setClass(ticks[i], "ahead", false);
    });
    set(nums.frame, "text", String(FIRST));
    set(nums.ask, "text", String(FIRST));
    for (const [el] of g.lit) set(el, "lit", false);
    g.rect.setAttribute("width", 0);
    g.line.setAttribute("stroke-opacity", 0);
  }

  function frame(now) {
    if (!g) return;
    const t = now - t0, k = Math.floor(t / D), ph = (t % D) / D;
    const [s0, s1] = SWEEP, [a, b] = g.span;
    const p = a + (b - a) * Math.min(1, Math.max(0, (ph - s0) / (s1 - s0)));
    const alpha = Math.min(1, Math.max(0, Math.min((ph - (s0 - FADE)) / FADE, (s1 + FADE - ph) / FADE)));
    const before = FIRST + (k % 900), latest = p >= g.publish ? before + 1 : before;
    // A refresh the playhead has passed paints whatever was latest then; those ahead of it still
    // show what they painted last time round.
    g.marks.forEach((m, i) => {
      const passed = ph >= s0 && m <= p;
      if (passed) set(ticks[i].querySelector(".n"), "text", String(m < g.publish ? before : before + 1));
      set(ticks[i], "lit", alpha > 0 && Math.abs(m - p) < 8);
      setClass(ticks[i], "ahead", ph >= s0 - FADE && ph < s1 + FADE && m > p);
    });
    set(nums.frame, "text", String(latest));
    for (const [el, lo, hi] of g.lit) {
      const on = alpha > 0 && p >= lo - 2 && p <= hi + 2;
      set(el, "lit", on);
      if (on && el.id === "th-ask") set(nums.ask, "text", String(latest));
    }
    const [x0, w] = [p - TRAIL, TRAIL];
    if (g.x) { g.rect.setAttribute("x", x0); g.rect.setAttribute("y", -8); g.rect.setAttribute("width", w); g.rect.setAttribute("height", g.H + 16); }
    else { g.rect.setAttribute("y", x0); g.rect.setAttribute("x", -8); g.rect.setAttribute("height", w); g.rect.setAttribute("width", g.W + 16); }
    const q = Math.round(p) + 1;
    if (g.x) { g.line.setAttribute("x1", q); g.line.setAttribute("x2", q); g.line.setAttribute("y1", 0); g.line.setAttribute("y2", g.H); }
    else { g.line.setAttribute("y1", q); g.line.setAttribute("y2", q); g.line.setAttribute("x1", 0); g.line.setAttribute("x2", g.W); }
    g.line.setAttribute("stroke-opacity", (0.55 * alpha).toFixed(2));
    g.trail.setAttribute("opacity", alpha.toFixed(2));
  }

  const running = () => visible && !reduce.matches && !document.hidden;
  function tick() {
    cancelAnimationFrame(raf);
    if (!running()) { still(); return; }
    const loop = now => { frame(now); raf = requestAnimationFrame(loop); };
    raf = requestAnimationFrame(loop);
  }

  new ResizeObserver(measure).observe(lanes);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; tick(); }).observe(fig);
  reduce.addEventListener("change", tick);
  document.addEventListener("visibilitychange", tick);
  document.fonts?.ready.then(measure);
}
