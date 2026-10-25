// The "Try it" pages (/try/, /try/<app>/; docs/try.md). Each app's graph.json holds the states
// `make site-try` found by running the app's real Lean step and frame headless: one image per
// state, each control's rect and claim, and for each action on each control the state it led to.
// This file only follows those recorded edges. It decides nothing about what an action does.

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
/** Prose from the claims: escaped, with `code` spans. */
const md = (s) => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>");

/** A reading's words, as the claim pages print them (site/claims.js). */
const LABEL = { retired: "retired", moved: "moved", assumed: "assumed", proved: "proved", unproved: "not proved", open: "no proof", ledger: "ledger only" };
const chip = (r) => `<span class="chip ev ${esc(r)}">${esc(LABEL[r] ?? r)}</span>`;
const claimPage = (id) => `/packages/cairn/claims/${id}/`;

const load = async (app) => {
	const res = await fetch(`/try/${app}/graph.json`);
	if (!res.ok) throw new Error(`graph.json: ${res.status}`);
	return res.json();
};

/** /try/: each app's first frame and how much was explored. */
export async function pick(list) {
	for (const shot of list.querySelectorAll(".shot[data-app]")) {
		const app = shot.dataset.app;
		const count = list.querySelector(`[data-count="${app}"]`);
		try {
			const g = await load(app);
			const edges = g.states.reduce((n, s) => n + s.edges.length, 0);
			shot.innerHTML = `<img src="/try/${app}/img/${esc(g.states[0].image)}" alt="${esc(g.app)}'s first frame" width="${g.width}" height="${g.height}">`;
			if (count) count.textContent = `${g.states.length} states, ${edges} steps explored`;
		} catch {
			if (count) count.textContent = "Not built here: make site-try";
		}
	}
}

/** /try/<app>/: the app. */
export async function mount(root, app) {
	let g;
	try {
		g = await load(app);
	} catch {
		root.innerHTML = `<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">Not here yet</p><p>This app's explored states aren't on this server. They are written when the site is built (<code>make site-try</code>, run by <code>make site-dist</code>).</p></div></aside>`;
		return;
	}
	const states = g.states;
	const edgeCount = states.reduce((n, s) => n + s.edges.length, 0);
	const W = g.width, H = g.height;
	const pct = (v, of) => `${(100 * v) / of}%`;
	const place = Object.values(g.claims).find((c) => c.kind === "place");
	const placeId = Object.keys(g.claims).find((id) => g.claims[id].kind === "place");

	root.innerHTML = `
<div class="try-grid">
  <section class="try-stage" aria-label="${esc(g.app)}">
    <div class="try-tools">
      <button type="button" class="b back">Back</button>
      <button type="button" class="b reset">Start over</button>
      <label class="pins"><input type="checkbox" checked> Show every control</label>
      <span class="where" aria-live="polite"></span>
    </div>
    <div class="try-shadow" style="max-width:${W + 20}px"><div class="try-window px"><div class="try-frame pinned" style="aspect-ratio:${W}/${H}">
      <img alt="" width="${W}" height="${H}">
      <div class="spots" role="group" aria-label="Controls in this frame"></div>
    </div></div><div class="menu px" role="menu" hidden></div></div>
    <p class="msg" role="status" aria-live="polite"></p>
  </section>
  <aside class="try-panel">
    <div class="card px info" aria-live="polite"></div>
    <div class="card px trail"><p class="label">Your steps</p><ol class="steps"></ol></div>
  </aside>
</div>
<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">What this is</p>
<p>These are frames the ${esc(g.app)} app's real Lean code produced, explored ahead of time: from the first frame, every control was acted on and every new frame kept, ${states.length} states and ${edgeCount} steps in all, within ${g.maxDepth} steps of the start${g.maxStates <= states.length ? `, capped at ${g.maxStates} states` : ""}. A click here follows a step the app took then; nothing runs in your browser but this page. A step that would leave the explored states says so instead of guessing.</p>
<p>Text fields take the texts the app's own flows type, rather than free typing: those are the inputs the capture tried. Evidence is what the claims export holds, as on <a href="${claimPage(placeId)}">the claim pages</a>.</p>
</div></aside>`;

	const $ = (s) => root.querySelector(s);
	const img = $(".try-frame img"), spots = $(".spots"), menu = $(".menu"), info = $(".info"), steps = $(".steps"), msg = $(".msg"), where = $(".where");
	const back = $(".back"), reset = $(".reset"), pins = $(".pins input"), frame = $(".try-frame");

	// The path from the start to the current state: [{state, via: {ref, action, label}}].
	let path = [{ state: 0, via: null }];
	let hovered = null; // a control of the current state, by ref
	let focused = null;

	const cur = () => states[path[path.length - 1].state];
	const control = (ref) => cur().controls.find((c) => c.ref === ref);
	const actionsOf = (c) => g.actions[String(c.claim)] ?? [];
	const edgeOf = (s, ref, a) => s.edges.find((e) => e[0] === ref && e[1] === a);
	const quote = (s) => `“${s}”`;
	const stepLabel = (c, a) => {
		const act = actionsOf(c)[a];
		const name = c.label && !/^Type|^Clear|Enter|Escape/.test(act.label) ? ` ${quote(c.label)}` : c.label ? ` in ${quote(c.label)}` : "";
		return `${act.label}${name}`;
	};
	const outcome = (e) =>
		e == null ? "not recorded" : typeof e[2] === "number" ? (e[2] === path[path.length - 1].state ? "no change" : "a new frame") : e[2] === "inert" ? "no change" : e[2] === "beyond" ? "past the explored states" : "not supported by the capture";

	// ---- The frame and its controls ------------------------------------------------------------
	function draw(focusRef) {
		const s = cur();
		img.src = `/try/${app}/img/${s.image}`;
		img.alt = `${g.app}, state ${path[path.length - 1].state}: ${s.controls.map((c) => c.label).filter(Boolean).join(", ")}`;
		spots.innerHTML = s.controls
			.map((c, i) => {
				const info = g.claims[c.claim];
				const [x, y, w, h] = c.rect;
				const label = `${info ? `cairn^${c.claim}${c.ref.includes("#") ? c.ref.slice(c.ref.indexOf("#")) : ""} ${info.title}` : c.ref}${c.label ? `: ${c.label}` : ""}`;
				return `<button type="button" class="spot ${esc(info?.reading ?? "")}${c.focused ? " focus" : ""}" data-ref="${esc(c.ref)}" style="left:${pct(x, W)};top:${pct(y, H)};width:${pct(w, W)};height:${pct(h, H)}" aria-label="${esc(label)}"${actionsOf(c).length > 1 ? ' aria-haspopup="menu"' : ""}><span class="badge">${esc(c.ref)}</span></button>`;
			})
			.join("");
		back.disabled = path.length === 1;
		reset.disabled = path.length === 1;
		const k = path[path.length - 1].state;
		where.textContent = `State ${k + 1} of ${states.length} · ${s.depth} step${s.depth === 1 ? "" : "s"} from the start`;
		hovered = null;
		if (focusRef) {
			const again = spots.querySelector(`[data-ref="${CSS.escape(focusRef)}"]`) ?? spots.querySelector(".spot");
			again?.focus({ preventScroll: true });
		}
		show();
		trail();
		// The next frames, so a click shows its frame at once.
		for (const e of s.edges) if (typeof e[2] === "number") new Image().src = `/try/${app}/img/${states[e[2]].image}`;
		try { history.replaceState(null, "", k ? `#s${k}` : location.pathname); } catch {}
	}

	// ---- The side panel ------------------------------------------------------------------------
	function show() {
		const ref = hovered ?? focused;
		const c = ref && control(ref);
		if (!c) {
			info.innerHTML = place
				? `<p class="label">The window</p><p class="ref"><a href="${claimPage(placeId)}"><code>cairn^${esc(placeId)}</code></a> ${chip(place.reading)}</p><p class="title">${esc(place.title)}</p><p>${md(place.does)}</p><p class="hint">Point at a control, or Tab to one, to see its claim. Click it, or press Enter or Space, to take the step.</p>`
				: `<p class="hint">Point at a control, or Tab to one, to see its claim.</p>`;
			return;
		}
		const cl = g.claims[c.claim] ?? { title: c.ref, reading: "ledger", does: "", sees: "", theorems: [], kind: "move" };
		const key = c.ref.includes("#") ? `<span class="key" title="One instance of a repeated control: key ${esc(c.ref.split("#")[1])}">#${esc(c.ref.split("#")[1])}</span>` : "";
		const role = [c.role, c.label && quote(c.label), c.checked === true ? "checked" : c.checked === false ? "unchecked" : "", c.focused ? "has focus" : ""].filter(Boolean).join(" · ");
		const s = cur();
		const acts = actionsOf(c)
			.map((a, k) => {
				const e = edgeOf(s, c.ref, k);
				const o = outcome(e);
				return `<li><button type="button" class="b act" data-ref="${esc(c.ref)}" data-a="${k}"${e && e[2] === "beyond" ? ' aria-describedby="beyond-note"' : ""}>${esc(a.label)}</button> <span class="out ${o === "a new frame" ? "ok" : o === "no change" ? "inert" : "far"}">${esc(o)}</span></li>`;
			})
			.join("");
		const thms = cl.theorems?.length
			? `<details><summary>${cl.theorems.length} theorem${cl.theorems.length === 1 ? "" : "s"}</summary><ul class="thms">${cl.theorems.map((t) => `<li><span class="${t.proved ? "ok" : "bad"}">${t.proved ? "✓" : "✗"}</span> <code>${esc(t.theorem)}</code></li>`).join("")}</ul></details>`
			: "";
		info.innerHTML = `<p class="label">${hovered ? "Under the pointer" : "Focused"}</p>
<p class="ref"><a href="${claimPage(c.claim)}"><code>cairn^${esc(c.claim)}</code></a>${key} ${chip(cl.reading)}</p>
<p class="title">${esc(cl.title)}</p>
<p class="role">${esc(cl.kind)} · ${esc(role)}</p>
${cl.does ? `<p class="said"><b>Does</b>${md(cl.does)}</p>` : ""}${cl.sees ? `<p class="said"><b>Sees</b>${md(cl.sees)}</p>` : ""}
${thms}
${acts ? `<p class="label">From this frame</p><ul class="acts">${acts}</ul>` : `<p class="hint">The capture has no action for this control.</p>`}
<p class="go"><a href="${claimPage(c.claim)}">Claim page for cairn^${esc(c.claim)} →</a></p>`;
	}

	function trail() {
		steps.innerHTML = path
			.map((p, k) => {
				const label = p.via ? esc(p.via.label) : "Start";
				const ref = p.via ? ` <code>${esc(p.via.ref)}</code>` : "";
				return k === path.length - 1
					? `<li aria-current="step">${label}${ref}</li>`
					: `<li><a href="#${p.state ? `s${p.state}` : "start"}" data-k="${k}">${label}</a>${ref}</li>`;
			})
			.join("");
		steps.scrollTop = steps.scrollHeight;
	}

	// ---- Acting --------------------------------------------------------------------------------
	function take(ref, a) {
		closeMenu();
		const s = cur(), c = control(ref);
		if (!c) return;
		const e = edgeOf(s, ref, a);
		const label = stepLabel(c, a);
		if (!e) return say(`${label}: the capture recorded nothing for this.`);
		if (e[2] === "inert") return say(`${label}: nothing changed. The app drew the same frame, so this step leaves the window as it was.`);
		if (e[2] === "beyond")
			return say(`${label} leads past what was explored ahead of time (${g.maxDepth} steps from the start, at most ${g.maxStates} states). The real app would go on; this page shows only frames the capture kept. Go back, or start over.`, true);
		if (e[2] === "unsupported") return say(`${label}: the capture can't send this step yet.`);
		if (e[2] === path[path.length - 1].state) return say(`${label}: nothing changed.`);
		path.push({ state: e[2], via: { ref, action: a, label } });
		say("");
		draw(ref);
	}
	function say(text, far = false) {
		msg.textContent = text;
		msg.classList.toggle("far", far);
	}
	function goTo(k) {
		path = path.slice(0, k + 1);
		say("");
		draw(document.activeElement?.closest?.(".try-stage") ? focused : null);
	}

	function openMenu(spot, c) {
		const s = cur();
		menu.innerHTML = actionsOf(c)
			.map((a, k) => {
				const o = outcome(edgeOf(s, c.ref, k));
				return `<button type="button" role="menuitem" data-a="${k}">${esc(a.label)}<span class="out">${esc(o)}</span></button>`;
			})
			.join("");
		menu.dataset.ref = c.ref;
		// Under the control, outside the window's clipped corners, kept inside the stage.
		const box = menu.parentElement.getBoundingClientRect(), r = spot.getBoundingClientRect();
		menu.hidden = false;
		menu.style.left = `${Math.max(0, Math.min(r.left - box.left, box.width - menu.offsetWidth))}px`;
		menu.style.top = `${r.bottom - box.top + 6}px`;
		menu.querySelector("button")?.focus();
	}
	function closeMenu(refocus = false) {
		if (menu.hidden) return;
		menu.hidden = true;
		if (refocus) spots.querySelector(`[data-ref="${CSS.escape(menu.dataset.ref)}"]`)?.focus();
	}

	spots.addEventListener("click", (ev) => {
		const spot = ev.target.closest(".spot");
		if (!spot) return;
		const c = control(spot.dataset.ref);
		const acts = actionsOf(c);
		focused = c.ref;
		if (acts.length === 1) take(c.ref, 0);
		else if (acts.length > 1) openMenu(spot, c);
		else say(`${c.ref}: the capture has no action for this control.`);
	});
	spots.addEventListener("pointerover", (ev) => {
		const spot = ev.target.closest(".spot");
		if (spot && ev.pointerType !== "touch") { hovered = spot.dataset.ref; show(); }
	});
	frame.addEventListener("pointerleave", () => { if (hovered) { hovered = null; show(); } });
	spots.addEventListener("focusin", (ev) => {
		const spot = ev.target.closest(".spot");
		if (spot) { focused = spot.dataset.ref; if (!hovered) show(); }
	});
	menu.addEventListener("click", (ev) => {
		const b = ev.target.closest("button[data-a]");
		if (b) take(menu.dataset.ref, Number(b.dataset.a));
	});
	menu.addEventListener("keydown", (ev) => {
		const items = [...menu.querySelectorAll("button")];
		const i = items.indexOf(document.activeElement);
		if (ev.key === "Escape") { ev.preventDefault(); closeMenu(true); }
		else if (ev.key === "ArrowDown") { ev.preventDefault(); items[(i + 1) % items.length]?.focus(); }
		else if (ev.key === "ArrowUp") { ev.preventDefault(); items[(i - 1 + items.length) % items.length]?.focus(); }
		else if (ev.key === "Tab") closeMenu();
	});
	document.addEventListener("pointerdown", (ev) => { if (!menu.hidden && !menu.contains(ev.target) && !ev.target.closest?.(".spot")) closeMenu(); });
	info.addEventListener("click", (ev) => {
		const b = ev.target.closest("button.act");
		if (b) take(b.dataset.ref, Number(b.dataset.a));
	});
	steps.addEventListener("click", (ev) => {
		const b = ev.target.closest("a[data-k]");
		if (b) { ev.preventDefault(); goTo(Number(b.dataset.k)); }
	});
	back.addEventListener("click", () => goTo(path.length - 2));
	reset.addEventListener("click", () => goTo(0));
	pins.addEventListener("change", () => frame.classList.toggle("pinned", pins.checked));

	// A link to a state (#s12) rebuilds the path that first reached it.
	const want = /^#s(\d+)$/.exec(location.hash)?.[1];
	if (want && states[Number(want)]) {
		const chain = [];
		for (let k = Number(want); k && states[k].from; k = states[k].from[0]) {
			const [p, e] = states[k].from;
			const [ref, a] = states[p].edges[e];
			const c = states[p].controls.find((x) => x.ref === ref);
			chain.unshift({ state: k, via: { ref, action: a, label: c ? stepLabel(c, a) : ref } });
		}
		path = [{ state: 0, via: null }, ...chain];
	}
	draw(null);
}
