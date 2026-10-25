// The progress log: media.json, newest first. Videos and stills (an "image" instead of a video,
// for a screenshot) are written by tools/media/put.sh; a note is an entry with "text"
// (plain-text paragraphs) and neither, for work with nothing to show on screen. The homepage shows the featured video; /milestones/ puts each entry in its milestone's
// progress log. site/web/lib/site.ts reads the same list for the feed, and links each entry to the
// id that videoId gives it here.

export const list = () => fetch("/media.json").then(r => r.json());

// A video's heading id: its title as a slug, as scene.js's mountAnchors would make it.
export const videoId = m => m.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "video";

export function figure(m, autoplay) {
  const f = document.createElement("figure");
  f.className = "frame";
  const box = document.createElement("div");
  box.className = "box px";
  let v;
  if (m.image) {
    v = document.createElement("img");
    Object.assign(v, { src: m.image, alt: m.title, loading: "lazy" });
  } else {
    v = document.createElement("video");
    Object.assign(v, { src: m.video, poster: m.poster, controls: true, muted: true, loop: true, playsInline: true, preload: "metadata" });
    v.autoplay = autoplay;
  }
  v.width = m.width; v.height = m.height;
  f.style.setProperty("--ar", m.width / m.height);
  box.append(v);
  const c = document.createElement("figcaption");
  c.textContent = m.caption;
  const meta = document.createElement("div");
  meta.className = "meta";
  for (const [cls, text] of [["date", m.date], ["", m.commit], ...(m.image ? [] : [["", `${m.seconds}s`]])]) {
    const s = document.createElement("span");
    if (cls) s.className = cls;
    s.textContent = text;
    meta.append(s);
  }
  f.append(box, c, meta);
  return f;
}

// A note: its paragraphs, and the date and commit under them, as a video's are.
export function note(m) {
  const d = document.createElement("div");
  d.className = "text";
  for (const t of m.text) {
    const p = document.createElement("p");
    p.textContent = t;
    d.append(p);
  }
  const meta = document.createElement("div");
  meta.className = "meta";
  for (const [cls, text] of [["date", m.date], ["", m.commit]]) {
    const s = document.createElement("span");
    if (cls) s.className = cls;
    s.textContent = text;
    meta.append(s);
  }
  d.append(meta);
  return d;
}

// Fill each `ul[id^=log-]` in root with its milestone's videos and notes (`log-m2` takes milestone "m2";
// an entry without one goes to m1, the first log).
export function fillLogs(root, list) {
  const logs = [...root.querySelectorAll("[id^=log-]")];
  for (const log of logs) log.textContent = "";
  for (const m of list) {
    const log = root.querySelector(`#log-${m.milestone || "m1"}`) || logs[0];
    if (!log) continue;
    const li = document.createElement("li");
    const h = document.createElement("h3");
    h.id = videoId(m);
    h.textContent = m.title;
    li.append(h, m.video || m.image ? figure(m, false) : note(m));
    log.append(li);
  }
  for (const log of logs) if (!log.children.length) log.innerHTML = '<li class="meta">Nothing yet.</li>';
}
