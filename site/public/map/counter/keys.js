// Keyboard: j/k move through rows (index) or flows and steps (area pages), Enter opens,
// / filters, [ ] change area, u goes up to the index, digits then Enter jump to an id.
(() => {
	const filter = document.getElementById("filter");
	const isIndex = Boolean(filter);
	let ids;
	let typed = "";
	let current = -1;

	const items = () =>
		[...document.querySelectorAll(isIndex ? "a.row" : "section.flow, li.step")].filter((el) => el.offsetParent !== null);

	const select = (index) => {
		const list = items();
		if (!list.length) return;
		current = Math.max(0, Math.min(list.length - 1, index));
		document.querySelector(".sel")?.classList.remove("sel");
		list[current].classList.add("sel");
		list[current].scrollIntoView({ block: "nearest" });
		if (!isIndex) history.replaceState(null, "", `#${list[current].id}`);
	};

	const jump = async (id) => {
		ids ||= await fetch("ids.json").then((response) => response.json());
		const entry = ids[id];
		if (entry) location.href = `${entry.area}.html#${id}`;
	};

	if (!isIndex && location.hash) {
		const list = items();
		const index = list.findIndex((el) => el.id === location.hash.slice(1));
		if (index >= 0) {
			current = index;
			list[index].classList.add("sel");
		}
	}

	filter?.addEventListener("input", () => {
		const words = filter.value.toLowerCase().replace(/^\^/, "").split(/\s+/).filter(Boolean);
		for (const li of [...document.querySelectorAll(".index li")].reverse()) {
			const row = li.querySelector(":scope > a.row");
			const own = row.textContent.toLowerCase();
			const hit = words.every((word) => own.includes(word));
			const child = [...li.querySelectorAll(":scope > ul > li")].some((el) => !el.hidden);
			li.hidden = !(hit || child);
		}
		current = -1;
	});

	document.addEventListener("keydown", (event) => {
		if (event.metaKey || event.ctrlKey || event.altKey) return;
		if (event.target === filter) {
			if (event.key === "Escape") filter.blur();
			if (event.key === "ArrowDown" || event.key === "Enter") {
				filter.blur();
				select(0);
				if (event.key === "Enter") items()[0]?.click();
				event.preventDefault();
			}
			return;
		}
		if (event.target.closest?.("input, textarea, [contenteditable]")) return;
		if (/^\d$/.test(event.key)) return void (typed += event.key);
		const id = typed;
		typed = "";
		if (event.key === "Enter" && id) return void jump(id);
		const go = (rel) => document.querySelector(`a[rel="${rel}"]`)?.click();
		const keys = {
			j: () => select(current + 1),
			ArrowDown: () => select(current + 1),
			k: () => select(current - 1),
			ArrowUp: () => select(current - 1),
			Enter: () => isIndex && items()[current]?.click(),
			"/": () => (filter ? filter.focus() : (location.href = "index.html")),
			u: () => (location.href = "index.html"),
			"[": () => go("prev"),
			"]": () => (isIndex ? document.querySelector(".rail a:nth-child(2)")?.click() : go("next")),
		};
		if (!keys[event.key]) return;
		event.preventDefault();
		keys[event.key]();
	});
})();

// The gaps page's views follow the hash (#ranked); no element has that id, so switching doesn't scroll.
(() => {
	const main = document.querySelector("main");
	if (!document.querySelector(".views")) return;
	const show = () => (main.dataset.view = location.hash.slice(1) || "by-area");
	show();
	addEventListener("hashchange", show);
})();
