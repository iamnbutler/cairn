// The figures on /claims/ (site/web/lib/claims.ts draws them). Both are complete without this
// script: the replay shows Todo's last frame with every control's id, and the field shows the
// test's path over every state lit. This only animates them, by classes on what is already laid
// out, so nothing moves or resizes. Each loop is a function of the time (a phase), paused while
// the figure is off screen or the tab is hidden, and never started under prefers-reduced-motion.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");

/** Runs `frame(t)` with t in [0, 1) over a loop of `ms`, only while `el` is on screen. */
function loop(el, ms, frame, still) {
	let on = false, raf = 0, t0 = 0, held = 0, paused = false;
	const tick = (now) => {
		if (!t0) t0 = now - held;
		held = now - t0;
		frame((held % ms) / ms);
		raf = requestAnimationFrame(tick);
	};
	const run = () => {
		const go = on && !paused && !document.hidden && !reduced.matches;
		if (go && !raf) { t0 = 0; raf = requestAnimationFrame(tick); }
		if (!go && raf) { cancelAnimationFrame(raf); raf = 0; }
		if (reduced.matches) still();
	};
	new IntersectionObserver(([e]) => { on = e.isIntersecting; run(); }, { rootMargin: "80px" }).observe(el);
	document.addEventListener("visibilitychange", run);
	reduced.addEventListener?.("change", run);
	return { pause(p) { paused = p; run(); } };
}

// ---- The replay -------------------------------------------------------------------------------

const LEAD = 1100; // ms on the first frame before the first step
const STEP = 1800; // ms per step: its control lights, then the next frame shows
const SHOW = 0.55; // of a step, when the frame after it shows
const HOLD = 3600; // ms on the last frame, every id showing

export function mountReplay(fig) {
	if (!fig) return;
	const layers = [...fig.querySelectorAll(".layer")];
	const steps = [...fig.querySelectorAll(".steps li")];
	const goal = fig.querySelector(".goal");
	const cards = new Map([...fig.querySelectorAll(".card")].map((c) => [c.dataset.claim, c]));
	const D = LEAD + steps.length * STEP + HOLD;
	let shown = -1, card = "204", hover = null;
	fig.classList.add("live");

	const showCard = (k) => {
		if (k === card || !cards.has(k)) return;
		cards.get(card)?.setAttribute("hidden", "");
		cards.get(k).removeAttribute("hidden");
		card = k;
	};
	const set = (frame, step, done) => {
		if (frame !== shown) {
			layers.forEach((l, i) => l.classList.toggle("on", i === frame));
			shown = frame;
		}
		steps.forEach((li, i) => {
			li.classList.toggle("lit", i === step);
			li.classList.toggle("done", i < done);
		});
		goal.classList.toggle("lit", done === steps.length);
		fig.classList.toggle("all", done === steps.length);
		const ref = step >= 0 ? steps[step].dataset.ref : null;
		for (const s of layers[frame].querySelectorAll(".spot")) s.classList.toggle("hot", s.dataset.ref === ref);
		if (ref && !hover) showCard(ref.slice(1).split("#")[0]);
	};
	const still = () => set(layers.length - 1, -1, steps.length);

	const frame = (p) => {
		const t = p * D;
		if (t < LEAD) return set(0, -1, 0);
		const k = Math.floor((t - LEAD) / STEP);
		if (k >= steps.length) return set(layers.length - 1, -1, steps.length);
		const u = (t - LEAD - k * STEP) / STEP;
		set(u < SHOW ? k : k + 1, k, u < SHOW ? k : k + 1);
	};
	const l = loop(fig, D, frame, still);

	// Pointing at a control pauses the run and shows its claim.
	fig.querySelector(".frames").addEventListener("pointerover", (e) => {
		const s = e.target.closest(".spot");
		if (!s) return;
		hover?.classList.remove("point");
		hover = s;
		s.classList.add("point");
		showCard(s.dataset.claim);
		l.pause(true);
	});
	fig.querySelector(".frames").addEventListener("pointerleave", () => {
		hover?.classList.remove("point");
		hover = null;
		l.pause(false);
	});
}

// ---- The state field --------------------------------------------------------------------------

const FIELD = 11000;
const TEST = [0.06, 0.38]; // the test walks its six states
const PROOF = [0.46, 0.74]; // the proof covers ring after ring, then the unexplored ones
const FADE = 0.95;

export function mountField(fig) {
	if (!fig) return;
	const svg = fig.querySelector("svg");
	const ring = [];
	for (const el of svg.querySelectorAll("[data-d]")) (ring[+el.dataset.d] ??= []).push(el);
	const path = svg.querySelector(".tpath");
	const test = [...svg.querySelectorAll(".s.t")].sort((a, b) => a.dataset.d - b.dataset.d);
	const [lt, lp] = fig.querySelectorAll(".legend li");
	const len = path.getTotalLength();
	path.style.strokeDasharray = `${len} ${len}`;
	fig.classList.add("live");
	let lastT = -1, lastP = -1;

	const set = (tk, tu, pk) => {
		if (tk !== lastT) test.forEach((d, i) => d.classList.toggle("walk", i < tk));
		path.style.strokeDashoffset = `${len * (1 - tu)}`;
		if (pk !== lastP) ring.forEach((els, d) => els.forEach((el) => el.classList.toggle("lit", d < pk)));
		lastT = tk; lastP = pk;
		lt.classList.toggle("lit", tk > 0 && pk === 0);
		lp.classList.toggle("lit", pk > 0);
	};
	const still = () => { set(test.length, 1, ring.length); lt.classList.add("lit"); };
	const span = (p, [a, b]) => Math.min(1, Math.max(0, (p - a) / (b - a)));

	loop(fig, FIELD, (p) => {
		if (p >= FADE) return set(0, 0, 0);
		const u = span(p, TEST);
		const tk = p < TEST[0] ? 0 : Math.min(test.length, 1 + Math.floor(u * test.length));
		set(tk, u, Math.round(span(p, PROOF) * ring.length));
	}, still);
}
