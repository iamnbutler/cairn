// The header scene: a pixel landscape at night with a cairn on the meadow. It runs the full
// width of the window, the featured video sits on its meadow, and behind the video's lower part
// it fades into the page as mist. Everything is drawn once at a few CSS pixels per pixel; only
// the sparkles and fireflies move. Positions are measured from the centre, so a resize reveals
// more land instead of reshuffling it.

const LIGHT = { x: 0.62, y: -0.62, z: 0.48 }; // from the upper right, where the moon is

const T = {
  sky: ["#0a0d28", "#0d1130", "#111638", "#151b42", "#1a1f4c", "#202456", "#272a60", "#2f2f69", "#383471", "#433878", "#4f3c7d", "#5c3f80"],
  skyStreaks: ["#2d3070", "#3a3a7a", "#4a3f80", "#5a4486", "#6a4a8a", "#7a5290"],
  glow: ["#6a4a8a", "#7d5592", "#93619a"],
  cloud: ["#ddd6f6", "#c6bdec", "#ada3de", "#968bcf", "#a585c4", "#8676bc", "#7465ac", "#61559c", "#52488e", "#443d80", "#383472"],
  cloudPink: ["#e3c6e6", "#c9a2d2", "#b088c2", "#9673b0"],
  ranges: [
    { peak: "#a7a2df", lit: ["#8f8acd", "#7e79c0"], shade: ["#5f5ba6", "#514e96"] },
    { peak: "#8a85c8", lit: ["#736fb6", "#6561a8"], shade: ["#4b4890", "#3f3d80"] },
    { peak: "#6f6bb2", lit: ["#5b58a0", "#4f4c92"], shade: ["#3a3878", "#30306a"] },
  ],
  haze: ["#5d4c8e", "#53488a", "#674f90", "#47437f"],
  hills: [["#34507e", "#2b4570", "#243b63"], ["#2b5c6a", "#244f5e", "#1e4352"]],
  lake: ["#20245e", "#272b68", "#2f3172", "#38377a", "#443d80", "#524386", "#5f4a8a"],
  glint: ["#9c97d8", "#d9d3f6", "#fff4d6"],
  meadow: ["#4a8a72", "#3f7a68", "#356c60", "#2c5f58", "#25534f", "#1f4746", "#193b3d", "#143034"],
  tips: ["#6aa688", "#82b896"],
  pines: ["#1f4a52", "#163a44", "#0f2c36"],
  flowers: [["#e29bc8", "#b06e9e"], ["#a892ec", "#7462c0"], ["#f4c870", "#c99645"], ["#9cbcf0", "#6c88c6"], ["#eceafd", "#bdbbe0"]],
  foliage: ["#173842", "#1f4a4c", "#2a5c58", "#3f7a68", "#5a9a80"],
  stones: [
    ["#1c1e45", "#2c2f62", "#424784", "#5e64a6", "#8a90cc"],
    ["#221b45", "#352b62", "#4e4384", "#6c60a6", "#978cce"],
    ["#122c34", "#1e434c", "#2f5f66", "#477f83", "#6fa8a6"],
    ["#2c1d3e", "#45305a", "#634a7c", "#85699e", "#b08fc2"],
  ],
  rim: "#dcdcff",
  moon: ["#fff7de", "#efe2bd", "#d9c99c"],
  halo: ["#2b3070", "#252a64", "#20255a"],
  sparkle: "#f2c46a",
  fly: { core: "#ffe9a3", halo: "rgba(242, 196, 106, 0.42)", dim: "rgba(242, 196, 106, 0.3)" },
};

// Deterministic noise, so the scene is the same on every visit.
function hash(n) {
  n = (n ^ 61) ^ (n >>> 16); n = Math.imul(n, 9); n ^= n >>> 4;
  n = Math.imul(n, 0x27d4eb2d); n ^= n >>> 15; return (n >>> 0) / 4294967296;
}
const h2 = (x, y) => hash(Math.imul(x | 0, 73856093) ^ Math.imul(y | 0, 19349663));
function noise(x, seed) {
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return hash(i * 374761 + seed) * (1 - u) + hash((i + 1) * 374761 + seed) * u;
}
const fbm = (x, seed) => noise(x, seed) * 0.62 + noise(x * 2.03, seed + 7) * 0.26 + noise(x * 4.1, seed + 13) * 0.12;
const rgb = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
const seam = (t, w = 0.3) => clamp((t - 0.5) / w + 0.5);
const pick = (arr, i) => arr[clamp(Math.round(i), 0, arr.length - 1)];

// Streak dithering: transitions break into short horizontal runs, the way painted pixel skies
// and water do, instead of a checkerboard.
function streak(x, y, t, min = 3, spread = 7) {
  const len = min + Math.floor(h2(y, 911) * spread);
  return h2(Math.floor((x + h2(y, 17) * 64) / len), y * 7 + 3) < t;
}

class Layer {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.canvas = document.createElement("canvas");
    this.canvas.width = w; this.canvas.height = h;
    this.ctx = this.canvas.getContext("2d");
    this.img = this.ctx.createImageData(w, h);
    this.d = this.img.data;
    this.cache = new Map();
  }
  set(x, y, c) {
    x |= 0; y |= 0;
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    let v = typeof c === "string" ? this.cache.get(c) : c;
    if (!v) { v = rgb(c); this.cache.set(c, v); }
    const i = (y * this.w + x) * 4;
    this.d[i] = v[0]; this.d[i + 1] = v[1]; this.d[i + 2] = v[2]; this.d[i + 3] = 255;
  }
  get(x, y) { const i = (y * this.w + x) * 4; return [this.d[i], this.d[i + 1], this.d[i + 2]]; }
  done() { this.ctx.putImageData(this.img, 0, 0); return this; }
}

// --- Sky -------------------------------------------------------------------------------------

function drawSky(L, g) {
  const { cx, horizon } = g, n = T.sky.length;
  for (let y = 0; y < Math.min(L.h, g.lakeTop + 2); y++) {
    const f = clamp(y / horizon) * (n - 1), i = Math.min(Math.floor(f), n - 2), t = f - i;
    for (let x = 0; x < L.w; x++) {
      let c = streak(x, y, seam(t, 0.4), 4, 10) ? T.sky[i + 1] : T.sky[i];
      // The last of the sunset, low behind the ranges on the left.
      const d = Math.hypot((x - g.glowX) / 2.6, y - horizon) / (horizon * 0.62);
      if (d < 1) {
        const k = Math.floor((1 - d) * 3.2);
        if (k > 0 && streak(x, y, seam((1 - d) * 3.2 - k + 0.5, 0.5), 4, 12)) c = T.glow[Math.min(k, 3) - 1];
      }
      L.set(x, y, c);
    }
  }
  // Stratus streaks: thin runs of a neighbouring hue, thicker and warmer near the horizon.
  for (let k = 0; k < 70; k++) {
    const v = hash(k * 3 + 1) ** 0.6, y = Math.round(horizon * (0.16 + v * 0.8));
    const x0 = cx + Math.round((hash(k * 5 + 2) - 0.5) * L.w * 1.2), len = 14 + Math.round(hash(k * 7 + 3) * 60);
    const c = pick(T.skyStreaks, v * (T.skyStreaks.length - 1) + (hash(k * 11) - 0.5) * 1.5);
    const rows = v > 0.7 ? 2 : 1;
    for (let r = 0; r < rows; r++) for (let x = x0 + r * 3; x < x0 + len - r * 4; x++) {
      const t = Math.sin(Math.PI * (x - x0) / len);
      if (streak(x, y + r, t * 1.2, 4, 9)) L.set(x, y + r, c);
    }
  }
  // Stars, denser toward the top.
  for (let y = 0; y < horizon; y++) for (let x = 0; x < L.w; x++) {
    const h = h2(x - cx + 4096, y);
    if (h > 0.9955 - (1 - y / horizon) * 0.002) L.set(x, y, h > 0.9991 ? "#fff6dc" : h > 0.998 ? "#c9cff5" : "#7d84c6");
  }
  // The moon, with a stepped halo.
  const [mx, my, r] = [g.moonX, g.moonY, 6];
  for (let y = -r * 5; y <= r * 5; y++) for (let x = -r * 5; x <= r * 5; x++) {
    const d = Math.hypot(x, y) / r;
    if (d > 1.1 && d < 5) {
      const k = d < 2 ? 0 : d < 3.2 ? 1 : 2;
      if (streak(mx + x, my + y, seam((5 - d) / 4 + 0.15, 0.5), 3, 6)) L.set(mx + x, my + y, T.halo[k]);
    }
  }
  for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) {
    const d = x * x + y * y;
    if (d > r * r + r * 0.6) continue;
    const lit = (x * LIGHT.x + y * LIGHT.y) / r;
    const crater = (x + 2) ** 2 + (y - 1) ** 2 < 2 || (x - 2) ** 2 + (y + 2) ** 2 < 1.5 || (x + 1) ** 2 + (y + 3) ** 2 < 1;
    L.set(mx + x, my + y, crater ? T.moon[1] : lit > -0.35 || d < (r - 1.5) ** 2 ? T.moon[0] : T.moon[2]);
  }
}

// Cumulus, built the way the references build them: dozens of small round heads, each a step
// lighter on the moon side and a step darker on its lower rim, their base tone set by height
// with a little jitter, so the cloud reads as a mosaic of lit and shadowed lumps. A streaky
// flat base runs out past the heads on both sides. `warm` tints the side away from the moon
// with the sunset's pinks.
function drawCloud(L, x0, base, w, hgt, seed, warm = 0) {
  const r = k => hash(seed * 7919 + k * 31);
  const skew = (r(0) - 0.5) * 0.5;
  const profile = u => {
    // A dome with big billows on top: rounded, never a peak.
    const a = Math.abs(u - skew * 0.4);
    return hgt * Math.sqrt(Math.max(0, 1 - a ** 2.4)) * (0.6 + 0.4 * noise(u * 4.5 + 5, seed));
  };
  const heads = [];
  const count = Math.round(w * hgt / 22);
  for (let k = 0; k < count; k++) {
    const u = r(k) * 2 - 1, top = profile(u);
    if (top < 3) continue;
    const v = r(k + 4000) ** 0.8, rad = 4 + r(k + 8000) * 4 + (1 - v) * 3;
    heads.push({ x: x0 + u * w / 2, y: base - v * (top - rad * 0.5), r: rad });
  }
  // Heads along the outline make the silhouette bumpy.
  const rim = Math.round(w / 2.2);
  for (let k = 0; k < rim; k++) {
    const u = (k / rim) * 2 - 1 + (r(k + 9000) - 0.5) * 0.05, top = profile(u);
    if (top < 2) continue;
    const rad = 3.5 + r(k + 9500) * 4.5;
    heads.push({ x: x0 + u * w / 2, y: base - top + rad * 0.85, r: rad });
  }
  heads.sort((a, b) => a.y - b.y); // lower heads sit in front
  const tones = T.cloud.length;
  for (const h of heads) {
    const t = 1 - (h.y - (base - hgt)) / hgt; // 1 at the top
    const tone = (1 - clamp(t)) * (tones - 4) + (r(Math.round(h.x * 13 + h.y)) - 0.5) * 1.6;
    const warmSide = warm && h.x < x0 + skew * w * 0.2 && r(Math.round(h.x * 7 + h.y * 3)) < 0.8;
    for (let y = Math.floor(h.y - h.r); y <= h.y + h.r; y++) for (let x = Math.floor(h.x - h.r); x <= h.x + h.r; x++) {
      const nx = (x + 0.5 - h.x) / h.r, ny = (y + 0.5 - h.y) / h.r, d = nx * nx + ny * ny;
      if (d > 1 || y > base) continue;
      const lit = nx * LIGHT.x + ny * LIGHT.y;
      const i = tone + (lit > 0.3 ? -1.4 : lit < -0.35 ? 1.2 : 0) + (d > 0.7 && ny > 0.1 ? 1 : 0);
      let c = pick(T.cloud, i);
      if (warmSide && i > 2.5 && i < 8) c = pick(T.cloudPink, (i - 3) * 0.75);
      L.set(x, y, c);
    }
  }
  // The flat base: streaks in the darker tones, running wide.
  for (let y = base - 3; y <= base + 2; y++) {
    const spread = w * (0.62 + (y - base + 3) * 0.06);
    for (let x = Math.floor(x0 - spread); x <= x0 + spread; x++) {
      const t = 1 - Math.abs(x - x0) / spread;
      if (streak(x, y, seam(t * 1.6, 0.6), 5, 14)) L.set(x, y, pick(T.cloud, tones - 4 + (y - base + 3) * 0.6));
    }
  }
}

// --- Land ------------------------------------------------------------------------------------

function peaks(x, seed, amp, spacing) {
  let best = { h: 0, px: x, top: 0 };
  for (let k = Math.floor(x / spacing) - 2; k <= Math.floor(x / spacing) + 2; k++) {
    const px = (k + 0.2 + hash(k * 92821 + seed) * 0.6) * spacing, ph = (0.4 + hash(k * 7919 + seed) * 0.6) * amp;
    const h = ph - Math.abs(x - px) * (0.42 + hash(k * 31 + seed) * 0.3);
    if (h > best.h) best = { h, px, top: ph };
  }
  best.h += (fbm(x / 6, seed) - 0.5) * amp * 0.08;
  return best;
}

function drawRanges(L, g) {
  const { cx, horizon, W } = g;
  T.ranges.forEach((pal, k) => {
    const base = horizon + 4 + k * 6, amp = g.unit * (0.17 - k * 0.04), spacing = 110 - k * 22, seed = 11 + k * 17;
    for (let x = 0; x < W; x++) {
      const p = peaks(x - cx + 2000, seed, amp, spacing), h = Math.round(base - p.h);
      const side = (x - cx + 2000) - p.px; // > 0 on the moon side
      for (let y = h; y < g.lakeTop; y++) {
        const dy = y - (base - p.top), depth = y - h;
        // Rock facets: noise stretched along each face's slope, so the planes run diagonally.
        const f = noise((side * 0.9 + dy * (side > 0 ? -0.55 : 0.55)) / 6 + k * 40, seed + 5);
        let c;
        if (side > 0) c = depth < 2 || (dy < 10 && f > 0.55) ? pal.peak : f > 0.42 ? pal.lit[0] : pal.lit[1];
        else c = depth < 1 ? pal.lit[1] : f > 0.5 ? pal.shade[0] : pal.shade[1];
        L.set(x, y, c);
      }
    }
    // Haze along the foot of each range.
    for (let y = base - 8; y < base + 6; y++) for (let x = 0; x < W; x++) {
      const t = 1 - Math.abs(y - base + 1) / 7;
      if (t > 0 && streak(x, y, t * 0.6, 5, 14)) L.set(x, y, T.haze[(k + (y & 1)) % T.haze.length]);
    }
  });
}

function drawHills(L, g) {
  const { cx, horizon, W } = g;
  const hill = (pal, base, amp, scale, seed) => {
    const hAt = x => base - fbm((x - cx) / scale + 50, seed) * amp;
    for (let x = 0; x < W; x++) {
      const h = Math.round(hAt(x)), lit = hAt(x + 2) - hAt(x - 2) > -0.2;
      for (let y = h; y < g.lakeTop + 1; y++) {
        const d = y - h;
        L.set(x, y, d < 2 || (lit && streak(x, y, 1 - d / 8, 3, 6)) ? pal[0] : d > 6 && streak(x, y, 0.5, 4, 8) ? pal[2] : pal[1]);
      }
    }
    return hAt;
  };
  const pine = (x0, ground, ht) => {
    for (let y = 0; y < ht; y++) {
      const t = y / ht, tier = (y % 4) / 4, half = Math.max(0, Math.round((t * 0.42 + tier * 0.12) * ht * 0.45));
      for (let x = -half; x <= half; x++) L.set(x0 + x, ground - ht + y, x > half * 0.3 ? T.pines[0] : x < -half * 0.4 ? T.pines[2] : T.pines[1]);
    }
    L.set(x0, ground - ht - 1, T.pines[1]);
    L.set(x0, ground, T.pines[2]);
  };
  const pines = (hAt, onFar) => {
    for (let k = 0; k < 30; k++) {
      if ((hash(k * 43) > 0.5) !== onFar) continue;
      const x = cx + Math.round((hash(k * 41 + 5) - 0.5) * Math.min(W, 900));
      if (Math.abs(x - g.cairnX) < 32) continue; // keep the cairn's skyline clear
      const n = 1 + Math.floor(hash(k * 47) * 4);
      for (let j = 0; j < n; j++) {
        const px = x + j * 3 + Math.round(hash(k * 53 + j) * 2);
        pine(px, Math.min(g.lakeTop - 1, Math.round(hAt(px)) + 3), Math.round((onFar ? 7 : 10) + hash(k * 59 + j) * (onFar ? 5 : 8)));
      }
    }
  };
  pines(hill(T.hills[0], horizon + 12, g.unit * 0.1, 40, 21), true);
  pines(hill(T.hills[1], horizon + 19, g.unit * 0.07, 30, 29), false);
}

// A still lake between the hills and the meadow, holding the sky's colours in streaks and the
// moon's path as broken glints.
function drawLake(L, g) {
  const { W, lakeTop } = g, depth = 26;
  for (let y = lakeTop; y < lakeTop + depth; y++) {
    const t = (y - lakeTop) / depth;
    for (let x = 0; x < W; x++) {
      let c = pick(T.lake, (1 - t) * 2.5 + h2(Math.floor((x + h2(y, 3) * 40) / (6 + h2(y, 5) * 14)), y) * 3.2);
      const dm = Math.abs(x - g.moonX);
      if (dm < 4 + t * 16 && streak(x, y, 0.55 - dm / (10 + t * 30), 2, 5)) c = T.glint[dm < 3 ? (y % 3 ? 1 : 2) : 0];
      const dg = Math.abs(x - g.glowX) / 2.4;
      if (dg < 30 && t < 0.5 && streak(x + 7, y, (1 - dg / 30) * 0.6, 4, 10)) c = T.glow[h2(x >> 3, y) < 0.5 ? 0 : 1];
      L.set(x, y, c);
    }
  }
  // The far shore: a dark line where the hills meet the water.
  for (let x = 0; x < W; x++) if (h2(x, 1) < 0.85) L.set(x, lakeTop, T.hills[1][2]);
}

function drawMeadow(L, g) {
  const { W, H } = g;
  for (let x = 0; x < W; x++) {
    const h = Math.round(g.meadowAt(x));
    for (let y = h; y < H; y++) {
      const d = y - h;
      // Bands of green that darken toward the viewer, broken into streaks, with moonlit tips.
      // Further down, slow swells of light and shade keep the meadow from going flat.
      const swell = d > 30 ? (fbm(x / 23 + y / 41, 83) - 0.5) * 4 : 0;
      let i = d < 2 ? 0 : 1 + Math.min(d / 9, 4.5) + swell;
      i += (h2(Math.floor((x + h2(y, 9) * 30) / (3 + h2(y, 4) * 6)), y) - 0.5) * 1.6;
      let c = pick(T.meadow, i);
      if (d > 1 && h2(x * 3, y) < 0.015) c = T.tips[h2(x, y * 5) < 0.5 ? 0 : 1];
      L.set(x, y, c);
    }
  }
  // Grass blades: short vertical strokes, longer toward the viewer.
  for (let k = 0; k < W * H * 0.03; k++) {
    const x = Math.floor(h2(k, 21) * W), top = g.meadowAt(x), y = Math.floor(top + 3 + h2(k, 22) * (H - top));
    const near = clamp((y - top) / 120), len = 1 + Math.floor(near * 5 * h2(k, 23));
    const c = h2(k, 24) < 0.5 ? T.meadow[Math.min(7, 3 + Math.floor(near * 4))] : T.tips[0];
    for (let j = 0; j < len; j++) L.set(x, y - j, c);
  }
  // Flowers in drifts: clusters of one colour, bigger toward the viewer.
  for (let k = 0; k < W * 1.2 + H * 1.4; k++) {
    const x = Math.floor(h2(k, 1) * W), top = g.meadowAt(x), y = Math.floor(top + 4 + h2(k, 2) ** 0.8 * (H - top - 4));
    if (fbm(x / 26 + 3, 91) + fbm(y / 19 + 5, 93) < 1.05) continue; // drifts, with bare grass between
    const near = clamp((y - top) / 140), pal = T.flowers[Math.floor(fbm(x / 40 + y / 60, 97) * T.flowers.length * 1.6) % T.flowers.length];
    const n = 2 + Math.floor(h2(k, 4) * 5);
    for (let j = 0; j < n; j++) {
      const fx = x + Math.round((h2(k, 10 + j) - 0.5) * (6 + near * 16)), fy = y + Math.round((h2(k, 20 + j) - 0.5) * (3 + near * 6));
      if (pal === T.flowers[1] && near > 0.3) { // lupine spikes
        const len = 3 + Math.round(near * 6);
        for (let s = 0; s < len; s++) L.set(fx, fy - s, s % 2 ? pal[1] : pal[0]);
        L.set(fx, fy + 1, T.meadow[6]);
      } else {
        L.set(fx, fy, pal[0]);
        if (near > 0.35) { L.set(fx + 1, fy, pal[1]); L.set(fx, fy + 1, pal[1]); }
        if (near > 0.7) { L.set(fx - 1, fy, pal[0]); L.set(fx, fy - 1, pal[0]); L.set(fx + 1, fy + 1, T.meadow[7]); }
      }
    }
  }
}

// A few lone stones resting in the meadow out beside the video, echoing the cairn.
function drawBoulders(L, g) {
  for (let k = 0; k < 10; k++) {
    const side = k % 2 ? 1 : -1, d = g.plateHalf + 16 + hash(k * 70 + 3) * (g.cx - g.plateHalf - 24);
    if (d > g.cx - 10) continue;
    const x = g.cx + side * Math.round(d), y = Math.round(g.lakeTop + 40 + hash(k * 80 + 3) * (g.fadeY - g.lakeTop - 50));
    const a = 3 + hash(k * 90 + 3) * 5, b = a * 0.6, ramp = T.stones[k % T.stones.length];
    for (let yy = -b - 1; yy <= b + 1; yy++) for (let xx = -a - 1; xx <= a + 1; xx++) {
      const dd = (xx / a) ** 2 + (yy / b) ** 2;
      if (dd > 1) {
        if (yy > 0 && yy < b + 2 && Math.abs(xx) < a * 1.1 && streak(x + xx, y + yy, 0.6)) L.set(x + xx, y + yy, T.meadow[7]);
        continue;
      }
      const lum = (xx / a) * LIGHT.x + (yy / b) * LIGHT.y + Math.sqrt(1 - dd) * LIGHT.z;
      L.set(x + xx, y + yy, ramp[clamp(Math.round((lum + 0.2) * 3), 0, 4)]);
    }
  }
}

// --- Stones ---------------------------------------------------------------------------------

// Six-step ramps: outline, dark, mid, light, top face, highlight.
const RAMPS = {
  slate: ["#151838", "#262a58", "#3b4079", "#575e9c", "#8088c4", "#b4b9e8"],
  violet: ["#1d1736", "#30264f", "#4a3b74", "#665596", "#8c7cbd", "#bfb2e6"],
  teal: ["#0f2430", "#1a3a46", "#2a5660", "#3f7a7c", "#64a39e", "#9fd2c4"],
  rose: ["#2a1832", "#432a4c", "#634069", "#87598a", "#b07fae", "#dcb2d4"],
};
const MOSS = ["#2c5f58", "#3f7a68", "#5a9a80", "#82b896"];

function blend(L, x, y, c, a) {
  if (x < 0 || y < 0 || x >= L.w || y >= L.h) return;
  const o = L.get(x, y), v = typeof c === "string" ? rgb(c) : c;
  L.set(x, y, [o[0] + (v[0] - o[0]) * a, o[1] + (v[1] - o[1]) * a, o[2] + (v[2] - o[2]) * a]);
}

// One stone. Shading is in flat planes rather than a smooth gradient: a lit top face, a front in
// two or three tones split by which way it faces, a dark underside and a selective outline.
function stone(L, own, ramps, o) {
  const { x: x0, by, w, h, tilt = 0, ramp, shape = "slab", seed = 1, speck = 0.04, moss = 0, rim = 1, p = 2.6 } = o;
  const id = ramps.push(ramp) - 1;
  const a = w / 2, b = h / 2, sy = by - b;
  const inside = (x, y) => {
    const dx = x + 0.5 - x0, dy = y + 0.5 - sy - dx * tilt;
    const ang = Math.atan2(dy / b, dx / a), wob = 1 + (noise(ang * 2.2 + 3, seed) - 0.5) * 0.14;
    return Math.abs(dx / (a * wob)) ** p + Math.abs(dy / (b * wob)) ** 2 <= 1;
  };
  const px = [];
  for (let y = Math.floor(sy - b) - 2; y <= sy + b + 2; y++) for (let x = Math.floor(x0 - a) - 2; x <= x0 + a + 2; x++) {
    if (!inside(x, y)) continue;
    const nx = clamp((x + 0.5 - x0) / a, -1, 1), ny = clamp((y + 0.5 - sy - (x - x0) * tilt) / b, -1, 1);
    const edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
    let i, top = false;
    if (shape === "slab") {
      top = ny < -0.3 + 0.1 * Math.sin(nx * 3 + seed);
      i = top ? (nx > -0.35 ? 4 : 3) : nx > 0.35 ? 3 : nx > -0.45 ? 2 : 1;
      if (!top && ny > 0.55) i = Math.max(1, i - 1);
    } else if (shape === "round") {
      const lum = nx * 0.55 - ny * 0.7 + 0.2 + (h2(x, y * 3) - 0.5) * 0.12;
      i = lum > 0.75 ? 4 : lum > 0.3 ? 3 : lum > -0.2 ? 2 : 1;
      top = ny < -0.4;
    } else { // facets: the outline split into wedges, each lit by which way it faces
      const n = 7, ang = Math.atan2(ny, nx * 0.85) + Math.PI + (seed % 7) * 0.3;
      const fc = (Math.floor(ang / (2 * Math.PI / n)) + 0.5) * (2 * Math.PI / n) - Math.PI - (seed % 7) * 0.3;
      const d = Math.cos(fc) * 0.62 - Math.sin(fc) * 0.78;
      i = nx * nx + ny * ny < 0.22 ? 3 : d > 0.5 ? 4 : d > 0.05 ? 3 : d > -0.45 ? 2 : 1;
      top = ny < -0.35;
    }
    if (!edge && speck) {
      if (h2(x * 5 + seed, y * 3) < speck) i = Math.max(1, i - 1);
      else if (h2(x * 7 + seed, y * 11) < speck * 0.4) i = Math.min(5, i + 1);
    }
    let c = ramp[i];
    if (moss && top && noise(x / 2.5, seed * 3 + y) + h2(x, y) * 0.35 > 0.62) c = MOSS[clamp(Math.round(1 + nx * 1.5 + (ny < -0.6 ? 1 : 0)), 0, 3)];
    if (edge) c = nx > 0.15 && ny < 0.2 && rim ? (rim > 1 || i >= 3 ? ramp[5] : ramp[3]) : ramp[0];
    L.set(x, y, c);
    px.push(x, y);
  }
  // Contact shadow: where this stone rests on one below, darken the lower stone's top under it.
  for (let k = 0; k < px.length; k += 2) {
    const x = px[k], y = px[k + 1];
    if (inside(x, y + 1)) continue;
    for (let d = 1; d <= 2; d++) {
      const j = (y + d) * L.w + x, other = own[j];
      if (other >= 0 && other !== id) L.set(x, y + d, ramps[other][d === 1 ? 0 : 1]);
    }
  }
  for (let k = 0; k < px.length; k += 2) own[px[k + 1] * L.w + px[k]] = id;
  return Math.round(sy - b);
}

function stack(L, own, ramps, x, ground, specs, opt = {}) {
  let bottom = ground, top = ground;
  specs.forEach(([w, h, off, tilt, ramp, shape], k) => {
    top = stone(L, own, ramps, { ...opt, x: x + off, by: bottom, w, h, tilt, ramp: RAMPS[ramp] || ramp, shape: shape || opt.shape, seed: k * 13 + (opt.seed || 1) });
    bottom = top + 2;
  });
  return top;
}

function groundShadow(L, x, y, w, len = 0) {
  for (let dy = -2; dy <= 3; dy++) for (let dx = -w * 0.7 - len; dx <= w * 0.5; dx++) {
    const t = ((dx + len * 0.5 + w * 0.1) / (w * 0.6 + len * 0.5)) ** 2 + (dy / 3) ** 2;
    if (t <= 1 && streak(x + dx, y + dy, 0.9 - t * 0.4)) blend(L, Math.round(x + dx), y + dy, "#0b1a26", 0.55);
  }
}

function tufts(L, x, y, w, seed) {
  for (let k = 0; k < w; k++) {
    if (h2(k, seed) < 0.45) continue;
    const len = 1 + Math.floor(h2(k, seed + 1) * 4);
    for (let j = 0; j < len; j++) L.set(x - (w >> 1) + k, y + 1 - j, j === len - 1 ? T.tips[h2(k, seed + 2) < 0.5 ? 0 : 1] : T.meadow[3]);
  }
}

// The cairn: slabs in the slate ramps with moss on their tops, ferns and flowers at its foot,
// lit from the moon like everything else, with its shadow falling to the left.
function drawCairn(L, g) {
  const own = new Int16Array(L.w * L.h).fill(-1), ramps = [];
  const kx = g.cairnX, ground = Math.round(g.meadowAt(kx)) + 6;
  groundShadow(L, kx - 6, ground, 48);
  stack(L, own, ramps, kx, ground, [[46, 12, 0, 0.03, "slate"], [38, 11, 2, -0.04, "teal"], [31, 10, -2, 0.05, "slate"], [24, 9, 1, -0.03, "violet"], [17, 7, 0, 0.04, "slate"], [11, 6, 1, 0, "teal"]], { shape: "slab", moss: 1 });
  for (const [fx, dir, len] of [[-24, -1, 9], [-19, -1, 7], [22, 1, 8], [26, 1, 6], [-27, 1, 5]]) {
    for (let s = 0; s < len; s++) {
      const x = kx + fx + dir * Math.round(s * 0.6), y = ground - s;
      L.set(x, y, MOSS[s < 2 ? 0 : 1]);
      if (s > 1 && s % 2 === 0) { L.set(x + 1, y, MOSS[2]); L.set(x - 1, y + 1, MOSS[1]); } // lit from the right, like everything
    }
  }
  for (const [fx, fy, c] of [[-30, 1, 0], [-21, 2, 4], [18, 1, 0], [29, 2, 4], [-12, 3, 1]]) {
    const pal = T.flowers[c];
    L.set(kx + fx, ground + fy, pal[0]); L.set(kx + fx + 1, ground + fy, pal[1]); L.set(kx + fx, ground + fy - 1, pal[0]);
  }
  tufts(L, kx, ground, 54, 9);
}

// --- Where the scene gives way to the page ---------------------------------------------------

// The scene runs the full width of the window and ends behind the lower part of the featured
// video in a long, slow mist: a gently arched line, a little lower on the left, with the land
// thinning into the page colour over a tall band and pale streaks of mist drifting through it.
const smoothT = t => t * t * (3 - 2 * t);

function dissolve(L, g, bg) {
  const { cx, W, H } = g, band = g.fadeBand;
  const mist = [[0x2a, 0x2e, 0x62], [0x33, 0x37, 0x6e], [0x3c, 0x3e, 0x78]];
  for (let x = 0; x < W; x++) {
    const mid = g.fadeY + (fbm(x / 60, 79) - 0.5) * 14 + ((cx - x) / W) * 18 - Math.cos((x - cx) / W * Math.PI) * 6;
    for (let y = Math.max(0, Math.floor(mid - band)); y < H; y++) {
      const t = (y - (mid - band)) / (band * 2);
      if (t >= 1) { L.set(x, y, bg); continue; }
      if (streak(x, y, smoothT(t), 5, 16)) { L.set(x, y, bg); continue; }
      if (streak(x + 57, y, Math.sin(Math.PI * t) * 0.22, 6, 20)) {
        const c = L.get(x, y), m = mist[Math.min(2, Math.floor(h2(x >> 4, y) * 3))];
        L.set(x, y, [(c[0] + m[0] * 2) / 3, (c[1] + m[1] * 2) / 3, (c[2] + m[2] * 2) / 3]);
        continue;
      }
      if (streak(x + 31, y, clamp(t * 1.6), 4, 12)) {
        const c = L.get(x, y);
        L.set(x, y, [(c[0] + bg[0]) >> 1, (c[1] + bg[1]) >> 1, (c[2] + bg[2]) >> 1]);
      }
    }
  }
  // Past the width cap, the canvas's own edges dissolve too.
  if (!g.capped) return;
  for (let y = 0; y < H; y++) for (let x = 0; x < 24; x++) {
    const t = 1 - x / 24;
    for (const xx of [x, W - 1 - x]) if (streak(xx, y * 3 + 1, t, 3, 5)) L.set(xx, y, bg);
  }
}

// --- Assembly --------------------------------------------------------------------------------

export function mountScene(canvas, layout = {}) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const header = canvas.parentElement;
  let state = null, raf = 0, visible = true, lastKey = "";

  // Where the featured video sits, in canvas pixels from the canvas's top.
  function measure(s) {
    const top = canvas.getBoundingClientRect().top;
    const box = layout.feature?.querySelector(".box")?.getBoundingClientRect();
    return box
      ? { top: Math.round((box.top - top) / s), height: Math.round(box.height / s), half: Math.round(box.width / 2 / s) }
      : { top: Math.round(header.clientHeight / s), height: 0, half: 0 };
  }

  function build(force) {
    const s = innerWidth < 600 ? 2 : 3;
    const k = measure(s);
    const key = JSON.stringify([innerWidth, k]);
    if (!force && key === lastKey) return;
    lastKey = key;
    // The mist is centred about two thirds of the way down the video (or a little below the
    // header before it loads), and never so low that the scene runs on for a whole screen.
    const fadeBand = 48;
    const fadeY = k.top + Math.min(Math.round(k.height * 0.62), Math.round(420 / s)) + (k.height ? 0 : 30);
    const W = Math.ceil(canvas.clientWidth / s), cx = W >> 1, H = fadeY + fadeBand + 24;
    canvas.style.height = `${H * s}px`;
    canvas.width = W; canvas.height = H;
    const bg = getComputedStyle(document.body).backgroundColor.match(/\d+/g).slice(0, 3).map(Number);
    const unit = 200, horizon = 84;
    const g = {
      W, H, cx, unit, horizon, fadeY, fadeBand, plateHalf: k.half,
      lakeTop: horizon + 24,
      moonX: cx + Math.round(Math.min(W * 0.32, 200)), moonY: Math.round(horizon * 0.22),
      glowX: cx - Math.round(Math.min(W * 0.2, 110)),
      cairnX: cx + Math.round(Math.min(W * 0.22, 120)),
      capped: canvas.clientWidth < innerWidth - 2,
    };
    g.meadowAt = x => g.lakeTop + 24 + (fbm((x - cx) / 34 + 9, 41) - 0.5) * 8;

    const L = new Layer(W, H);
    const off = f => Math.round(Math.min(W * f, 1600 / s * f));
    drawSky(L, g);
    drawCloud(L, cx - off(0.27), horizon - 18, 104, 46, 3, 1);
    drawCloud(L, cx + off(0.08), horizon - 34, 54, 22, 7, 1);
    drawCloud(L, cx + off(0.33), horizon - 14, 90, 40, 11, 0);
    drawCloud(L, cx - off(0.48), horizon - 34, 60, 24, 17, 1);
    drawCloud(L, cx + off(0.5), horizon - 40, 48, 18, 19, 0);
    drawRanges(L, g);
    drawHills(L, g);
    drawLake(L, g);
    drawMeadow(L, g);
    drawCairn(L, g);
    drawBoulders(L, g);
    dissolve(L, g, bg);
    L.done();

    // Fireflies start on kept meadow pixels, so they never rise out of the mist.
    const spots = [];
    for (let k = 0; spots.length < 800 && k < 30000; k++) {
      const x = Math.floor(Math.random() * W), y = Math.floor(g.lakeTop + 20 + Math.random() * (H - g.lakeTop - 20));
      const c = L.get(x, y);
      if (Math.abs(c[0] - bg[0]) + Math.abs(c[1] - bg[1]) + Math.abs(c[2] - bg[2]) > 6) spots.push([x, y]);
    }
    const sparkles = [[-0.3, 0.06], [-0.14, 0.2], [0.06, 0.05], [0.17, 0.24], [-0.44, 0.27], [0.4, 0.31], [-0.6, 0.12], [0.58, 0.2], [-0.8, 0.18], [0.82, 0.08]]
      .map(([fx, fy], k) => ({ x: cx + Math.round(fx * Math.min(W, 760)), y: Math.round(horizon * 2 * fy), phase: k * 1.7 }));
    const count = Math.round(Math.min(70, spots.length / 8));
    state = { W, H, L, spots, sparkles, motes: [], t0: performance.now() };
    for (let k = 0; k < count; k++) state.motes.push(spawn(true));
    last = 0;
    frame(performance.now());
  }

  function spawn(fresh) {
    const [x, y] = state.spots[Math.floor(Math.random() * state.spots.length)] || [0, 0];
    return { x, y, vy: 0.8 + Math.random() * 1.8, sway: 0.6 + Math.random() * 1.2, phase: Math.random() * 6.28,
      life: fresh ? Math.random() * 6 : 0, max: 7 + Math.random() * 9, tw: 1.2 + Math.random() * 2 };
  }

  let last = 0;
  function frame(now) {
    if (!state) return;
    const { W, H, L, sparkles, motes } = state;
    const dt = Math.min(0.1, last ? (now - last) / 1000 : 0);
    last = now;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, W, H);
    ctx.drawImage(L.canvas, 0, 0);
    const t = (now - state.t0) / 1000;
    for (const s of sparkles) {
      const p = (Math.sin(t * 1.1 + s.phase) + 1) / 2, arm = p > 0.66 ? 2 : p > 0.2 ? 1 : 0;
      ctx.fillStyle = "#fffaf0"; ctx.fillRect(s.x, s.y, 1, 1);
      ctx.fillStyle = T.sparkle;
      for (let d = 1; d <= arm; d++) { ctx.fillRect(s.x + d, s.y, 1, 1); ctx.fillRect(s.x - d, s.y, 1, 1); ctx.fillRect(s.x, s.y + d, 1, 1); ctx.fillRect(s.x, s.y - d, 1, 1); }
    }
    // Fireflies rise slowly and twinkle.
    for (let k = 0; k < motes.length; k++) {
      const m = motes[k];
      m.life += dt; m.y -= m.vy * dt; m.x += Math.sin(t * 0.7 + m.phase) * m.sway * dt;
      if (m.life > m.max) { motes[k] = spawn(false); continue; }
      const fade = Math.min(1, m.life / 1.5, (m.max - m.life) / 1.5);
      const tw = (Math.sin(t * m.tw + m.phase) + 1) / 2 * fade;
      const x = Math.round(m.x), y = Math.round(m.y);
      if (tw > 0.55) {
        ctx.fillStyle = T.fly.halo;
        ctx.fillRect(x - 1, y, 1, 1); ctx.fillRect(x + 1, y, 1, 1); ctx.fillRect(x, y - 1, 1, 1); ctx.fillRect(x, y + 1, 1, 1);
        ctx.fillStyle = T.fly.core;
      } else if (tw > 0.15) ctx.fillStyle = T.fly.dim;
      else continue;
      ctx.fillRect(x, y, 1, 1);
    }
    if (!reduce.matches && visible && !document.hidden) raf = requestAnimationFrame(frame);
  }

  function restart() { cancelAnimationFrame(raf); last = 0; if (state) raf = requestAnimationFrame(frame); }
  let resizeTimer = 0, lastW = innerWidth;
  addEventListener("resize", () => {
    if (innerWidth === lastW) return; // phones fire resize on scroll as the toolbar moves
    lastW = innerWidth;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { cancelAnimationFrame(raf); build(true); }, 120);
  });
  // The video arriving, or fonts loading, moves the text; redraw when the layout really changes.
  let layoutTimer = 0;
  if (layout.feature) new ResizeObserver(() => {
    clearTimeout(layoutTimer);
    layoutTimer = setTimeout(() => { cancelAnimationFrame(raf); build(false); }, 80);
  }).observe(layout.feature);
  reduce.addEventListener("change", restart);
  document.addEventListener("visibilitychange", restart);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; restart(); }).observe(canvas);
  build(true);
}

// --- Frames for the videos -------------------------------------------------------------------

// Each video sits in a thin wooden frame with moss along the top, tufts of grass at the foot and
// two fireflies, with an empty margin between it and the picture. The frame lives inside a
// margin the box reserves, so it never covers the text around it. Lit from the upper right like
// the scene: edges facing up or right catch the moon, the others fall into shade.
const WOOD = { line: "#1d1a36", dark: "#352a4a", mid: "#4a3956", grain: "#40324f", light: "#66506a", lit: "#8a6f84" };
const LEAF = { dark: "#3f7a68", mid: "#5a9a80", lit: "#82b896", tip: "#a8d8b0" };
const FRAME = { gap: 4, wood: 3, m: 10 };

// Where a canvas pixel sits relative to the box: its distance out (1 = touching) and the side.
function rim(x, y, W, H, m) {
  const dl = m - x, dr = x - (W - m - 1), dt = m - y, db = y - (H - m - 1);
  const dx = Math.max(dl, dr, 0), dy = Math.max(dt, db, 0), d = Math.max(dx, dy);
  const side = dy > dx || (dy === dx && dy > 0 && dt > 0) ? (dt > 0 ? "t" : "b") : dl > 0 ? "l" : "r";
  return { d, side, corner: dx === dy && d > 0 };
}

// A mitred frame of four planks. Each plank has its own tone by which way it faces the moon,
// so the joins read; a dark seam runs down each diagonal. Rows go outer edge, face, inner lip.
const PLANK = {
  t: [WOOD.lit, WOOD.light, WOOD.dark],
  r: [WOOD.lit, WOOD.mid, WOOD.dark],
  b: [WOOD.line, WOOD.grain, WOOD.light],
  l: [WOOD.line, WOOD.mid, WOOD.light],
};
function drawWood(L, m, seed) {
  const { w: W, h: H } = L, g = FRAME.gap, n = FRAME.wood;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const { d, side, corner } = rim(x, y, W, H, m), r = d - g - 1;
    if (r < 0 || r >= n) continue;
    if (corner) { L.set(x, y, r === n - 1 && (side === "t" || side === "r") && x > W / 2 && y < H / 2 ? WOOD.light : WOOD.line); continue; }
    const row = n - 1 - r, along = side === "t" || side === "b" ? x : y;
    let c = PLANK[side][row];
    // Grain: short darker runs along the face.
    if (row === 1 && h2(Math.floor(along / (3 + h2(r, seed) * 4)), seed + side.charCodeAt(0)) < 0.3) c = side === "t" ? WOOD.mid : WOOD.grain === c ? WOOD.dark : WOOD.grain;
    L.set(x, y, c);
  }
}

// The perimeter at distance d, clockwise from the top left, with each point's outward normal.
function around(W, H, m, d) {
  const pts = [], x0 = m - d, y0 = m - d, x1 = W - m - 1 + d, y1 = H - m - 1 + d;
  for (let x = x0; x < x1; x++) pts.push([x, y0, 0, -1]);
  for (let y = y0; y < y1; y++) pts.push([x1, y, 1, 0]);
  for (let x = x1; x > x0; x--) pts.push([x, y1, 0, 1]);
  for (let y = y1; y > y0; y--) pts.push([x0, y, -1, 0]);
  return pts;
}

// Moss along the top edge and a tuft or two of grass on the bottom one.
function drawMoss(L, m, seed) {
  const { w: W, h: H } = L, top = m - FRAME.gap - FRAME.wood - 1, foot = H - m + FRAME.gap + FRAME.wood;
  for (let x = m - 6; x < W - m + 6; x++) {
    const v = fbm(x / 14, seed), h = Math.floor((v - 0.5) * 10 + h2(x, seed) * 1.5);
    for (let j = 0; j < h; j++) L.set(x, top + 1 - j, j === h - 1 ? (h2(x, seed + 1) < 0.5 ? LEAF.tip : LEAF.lit) : j ? LEAF.mid : LEAF.dark);
  }
  for (const f of [0.18, 0.74]) {
    const cx = Math.round(m + (W - 2 * m) * f);
    for (const [dx, len] of [[-2, 2], [-1, 3], [0, 2], [1, 4], [2, 2]])
      for (let j = 0; j < len; j++) L.set(cx + dx, foot - j, j === len - 1 ? LEAF.tip : LEAF.mid);
  }
  const pal = T.flowers[0], fx = Math.round(m + (W - 2 * m) * 0.74) + 1;
  L.set(fx, foot - 5, pal[0]); L.set(fx, foot - 4, pal[1]);
}

// The empty margin: page background between the picture and the frame, so the meadow behind a
// featured video stops at the frame instead of running up to the picture.
function drawMat(L, m, upto) {
  const { w: W, h: H } = L;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const { d } = rim(x, y, W, H, m);
    if (d >= 1 && d <= upto) L.set(x, y, "#161937");
  }
}

function drawFrame(L, m, seed) {
  drawMat(L, m, FRAME.gap);
  drawWood(L, m, seed);
  drawMoss(L, m, seed);
}

export function mountFrames(root) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const live = new Set();
  let raf = 0;

  function mount(fig) {
    const box = fig.querySelector(".box");
    if (!box || fig.querySelector("canvas.stones")) return;
    const canvas = document.createElement("canvas");
    canvas.className = "stones";
    canvas.setAttribute("aria-hidden", "true");
    fig.append(canvas);
    const f = { fig, box, canvas, key: "", visible: false, flies: [] };
    new ResizeObserver(() => build(f)).observe(box);
    new IntersectionObserver(([e]) => { f.visible = e.isIntersecting; tick(); }).observe(canvas);
    live.add(f);
    build(f);
  }

  function build(f) {
    const s = innerWidth < 600 ? 2 : 3, m = FRAME.m;
    f.box.style.margin = `${m * s}px`;
    const bw = Math.round(f.box.offsetWidth / s), bh = Math.round(f.box.offsetHeight / s);
    const key = `${s}:${bw}x${bh}`;
    if (!bw || !bh || key === f.key) return;
    f.key = key;
    const W = bw + 2 * m, H = bh + 2 * m;
    Object.assign(f.canvas.style, { left: `${f.box.offsetLeft - m * s}px`, top: `${f.box.offsetTop - m * s}px`, width: `${W * s}px`, height: `${H * s}px` });
    f.canvas.width = W; f.canvas.height = H;
    f.L = new Layer(W, H);
    drawFrame(f.L, m, (bw * 7 + bh) % 97 + 1);
    f.L.done();
    f.ring = around(W, H, m, m - 2);
    f.flies = Array.from({ length: 2 }, (_, k) => ({ u: Math.random(), v: 0.6 + Math.random() * 0.8, off: 3 + Math.random() * 6, ph: Math.random() * 6.28, tw: 1 + Math.random() * 2 }));
    f.m = m;
    draw(f, performance.now());
  }

  // A firefly's place: a slow walk round the frame, just outside the wood.
  function at(f, fl, t) {
    const P = f.ring.length, [x, y, nx, ny] = f.ring[Math.floor(((fl.u + t * fl.v * 0.004) % 1) * P)];
    const o = Math.round(Math.sin(t * 0.8 + fl.ph));
    return [x - nx * o, y - ny * o];
  }

  function draw(f, now) {
    if (!f.L) return;
    const ctx = f.canvas.getContext("2d"), t = now / 1000;
    ctx.clearRect(0, 0, f.canvas.width, f.canvas.height);
    ctx.drawImage(f.L.canvas, 0, 0);
    for (const fl of f.flies) {
      const [x, y] = at(f, fl, t).map(Math.round), tw = (Math.sin(t * fl.tw + fl.ph) + 1) / 2;
      if (tw < 0.15) continue;
      if (tw > 0.55) {
        ctx.fillStyle = T.fly.halo;
        ctx.fillRect(x - 1, y, 1, 1); ctx.fillRect(x + 1, y, 1, 1); ctx.fillRect(x, y - 1, 1, 1); ctx.fillRect(x, y + 1, 1, 1);
        ctx.fillStyle = T.fly.core;
      } else ctx.fillStyle = T.fly.dim;
      ctx.fillRect(x, y, 1, 1);
    }
  }

  function tick() {
    cancelAnimationFrame(raf);
    const loop = now => {
      let any = false;
      for (const f of live) if (f.visible) { draw(f, now); any = true; }
      if (any && !reduce.matches && !document.hidden) raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
  }

  root.querySelectorAll(".frame").forEach(mount);
  new MutationObserver(() => root.querySelectorAll(".frame").forEach(mount)).observe(root, { childList: true, subtree: true });
  document.addEventListener("visibilitychange", tick);
  addEventListener("resize", () => { for (const f of live) build(f); });
}

// --- Sprigs beside the headings ----------------------------------------------------------------

// A strip of ground at the far right of each section heading: a thin line of turf that thins out
// to the left, a few tufts of grass and a flower or two. Drawn once; hidden when the heading's
// text would reach it.
function drawSprig(L, seed) {
  const { w: W, h: H } = L, base = H - 2;
  for (let x = 0; x < W; x++) {
    const fade = x / W;
    if (h2(x, seed) > fade * 1.6) continue;
    L.set(x, base, h2(x, seed + 1) < 0.5 ? T.meadow[2] : T.meadow[3]);
    if (fade > 0.45 && h2(x, seed + 2) < fade - 0.2) L.set(x, base + 1, T.meadow[5]);
  }
  const tuft = (cx, tall) => {
    for (let dx = -2; dx <= 2; dx++) {
      if (h2(cx + dx, seed + 3) < 0.3) continue;
      const len = Math.max(1, Math.round(tall - Math.abs(dx) * 1.2 + (h2(cx + dx, seed + 4) - 0.5) * 2));
      const lean = dx > 0 ? 1 : 0;
      for (let j = 1; j <= len; j++) {
        const x = cx + dx + (j > len - 1 && len > 2 ? lean : 0);
        L.set(x, base - j, j === len ? T.tips[dx >= 0 ? 1 : 0] : j > len / 2 ? T.meadow[1] : T.meadow[3]);
      }
    }
  };
  const spots = [0.5, 0.66, 0.8, 0.93].filter((_, k) => h2(k, seed + 5) < 0.85);
  spots.forEach((f, k) => tuft(Math.round(W * f), 3 + Math.floor(h2(k, seed + 6) * 4)));
  const pal = T.flowers[seed % T.flowers.length];
  for (const [f, tall] of [[0.73, 7], [0.88, 5]].slice(0, 1 + (seed % 2))) {
    const x = Math.round(W * f) + (seed % 3) - 1;
    for (let j = 1; j < tall; j++) L.set(x, base - j, T.meadow[2]);
    L.set(x, base - tall, pal[0]); L.set(x + 1, base - tall, pal[0]); L.set(x, base - tall - 1, pal[0]);
    L.set(x + 1, base - tall + 1, pal[1]); L.set(x - 1, base - tall, pal[1]);
    L.set(x + 1, base - 3, T.meadow[1]);
  }
}

export function mountSprigs(root) {
  const heads = [...root.querySelectorAll("h2")];
  heads.forEach((h, k) => {
    const W = 46, H = 14;
    const canvas = document.createElement("canvas");
    canvas.className = "sprig";
    canvas.setAttribute("aria-hidden", "true");
    canvas.width = W; canvas.height = H;
    const L = new Layer(W, H);
    drawSprig(L, k * 7 + 3);
    L.done();
    canvas.getContext("2d").drawImage(L.canvas, 0, 0);
    h.append(canvas);
    // Hide the sprig rather than let it crowd a long heading on a narrow screen.
    const range = document.createRange();
    range.selectNodeContents(h);
    range.setEndBefore(canvas);
    const fit = () => { canvas.hidden = false; canvas.hidden = range.getBoundingClientRect().right + 24 > canvas.getBoundingClientRect().left; };
    new ResizeObserver(fit).observe(h);
  });
}
