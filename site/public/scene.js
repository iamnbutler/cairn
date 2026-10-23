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

// The cairn: flat stones with uneven outlines, lit from the moon side, selectively outlined
// (dark only away from the light), with contact shadows where stones rest on each other.
function drawCairn(L, g) {
  const kx = g.cairnX, ground = Math.round(g.meadowAt(kx)) + 6;
  const specs = [[46, 14, 0, 0.04], [37, 12, 2, -0.05], [30, 11, -1, 0.06], [23, 10, 1, -0.04], [16, 8, 0, 0.05], [10, 6, 1, 0]];
  const pal = [0, 3, 2, 1, 3, 0];
  for (let y = -2; y <= 2; y++) for (let x = -38; x <= 20; x++) {
    if ((x + 9) ** 2 / 29 ** 2 + y * y / 5 <= 1 && streak(kx + x, ground + y, 0.85)) L.set(kx + x, ground + y, T.meadow[7]);
  }
  let bottom = ground, prev = null;
  specs.forEach(([w, h, off, tilt], k) => {
    const ramp = T.stones[pal[k]], a = w / 2, b = h / 2, sx = kx + off, sy = bottom - b;
    const inside = (x, y) => {
      const dx = x + 0.5 - sx, dy = y + 0.5 - sy - dx * tilt;
      const ang = Math.atan2(dy / b, dx / a), wob = 1 + (noise(ang * 2.2 + 3, k * 13 + 1) - 0.5) * 0.16;
      return Math.abs(dx / (a * wob)) ** 2.6 + Math.abs(dy / (b * wob)) ** 2 <= 1;
    };
    for (let y = Math.floor(sy - b) - 2; y <= sy + b + 2; y++) for (let x = Math.floor(sx - a) - 2; x <= sx + a + 2; x++) {
      if (!inside(x, y)) continue;
      const nx = clamp((x + 0.5 - sx) / a, -1, 1), ny = clamp((y + 0.5 - sy - (x - sx) * tilt) / b, -1, 1);
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx * 0.8 - ny * ny * 0.8));
      const lum = nx * LIGHT.x + ny * LIGHT.y * 1.25 + nz * LIGHT.z;
      let i = Math.round(clamp((lum + 0.15) / 1.2) * 3) + 1;
      if (h2(x * 5 + k, y * 3) < 0.08) i -= 1;
      else if (h2(x * 7 + k, y * 11) < 0.04) i += 1;
      const edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
      if (edge) i = lum > 0.35 ? Math.min(i, 3) : 0;
      if (prev && y < sy && y >= prev.sy + prev.b - 2 && Math.abs(x + 0.5 - prev.sx) < prev.a * 0.95) i = Math.min(i, 1);
      L.set(x, y, ramp[clamp(i, 0, 4)]);
      if (edge && nx > 0.45 && ny < 0.3) L.set(x, y, T.rim);
    }
    prev = { sx, sy, a, b };
    bottom = Math.round(sy - b + 2);
  });
  for (let x = kx - 26; x <= kx + 27; x++) {
    if (h2(x, 77) < 0.5) continue;
    const len = 1 + Math.floor(h2(x, 78) * 3);
    for (let j = 0; j < len; j++) L.set(x, ground + 1 - j, j === len - 1 ? T.meadow[1] : T.meadow[4]);
  }
  for (const [dx, w] of [[-31, 3], [-25, 2], [29, 2]]) {
    L.set(kx + dx, ground, T.stones[0][2]); if (w > 2) L.set(kx + dx + 1, ground, T.stones[0][3]);
    if (w > 1) L.set(kx + dx + (w > 2 ? 2 : 1), ground, T.stones[0][1]);
  }
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
