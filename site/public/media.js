// The videos: media.json, newest first, written by tools/media/put.sh. The homepage shows the
// featured one; /milestones/ puts each in its milestone's progress log. tools/site/build.ts reads
// the same list for the feed, and links each video to the id that videoId gives it here.

export const list = () => fetch("/media.json").then(r => r.json());

// A video's heading id: its title as a slug, as scene.js's mountAnchors would make it.
export const videoId = m => m.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "video";

export function figure(m, autoplay) {
  const f = document.createElement("figure");
  f.className = "frame";
  const box = document.createElement("div");
  box.className = "box px";
  const v = document.createElement("video");
  Object.assign(v, { src: m.video, poster: m.poster, controls: true, muted: true, loop: true, playsInline: true, preload: "metadata" });
  v.width = m.width; v.height = m.height;
  f.style.setProperty("--ar", m.width / m.height);
  v.autoplay = autoplay;
  box.append(v);
  const c = document.createElement("figcaption");
  c.textContent = m.caption;
  const meta = document.createElement("div");
  meta.className = "meta";
  for (const [cls, text] of [["date", m.date], ["", m.commit], ["", `${m.seconds}s`]]) {
    const s = document.createElement("span");
    if (cls) s.className = cls;
    s.textContent = text;
    meta.append(s);
  }
  f.append(box, c, meta);
  return f;
}

// Fill each `ul[id^=log-]` in root with its milestone's videos (`log-m2` takes milestone "m2";
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
    li.append(h, figure(m, false));
    log.append(li);
  }
  for (const log of logs) if (!log.children.length) log.innerHTML = '<li class="meta">No videos yet.</li>';
}
