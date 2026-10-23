// The header scene: a pixel landscape at night with a cairn on the meadow. It's drawn at a few CSS pixels per pixel into four layers: the sky,
// cloud sprites that drift, the land (which dissolves into the page colour as mist), and
// motes that rise and twinkle. Positions are measured from the centre, so a resize
// reveals more land instead of reshuffling it.

const LIGHT = { x: 0.62, y: -0.62, z: 0.48 }; // from the upper right, where the moon is

const THEMES = {
  night: {
    sky: ["#0b0e2a", "#0f1334", "#13183e", "#181d48", "#1e2353", "#25295d", "#2d2f67", "#363470", "#403878", "#4a3d7e"],
    glow: ["#5a3f80", "#764c8a"],
    wisp: ["#4a3f82", "#33347a"],
    cloud: ["#aaa6e0", "#8180c4", "#6462a6", "#58508f", "#5a4482", "#45346f"],
    ridges: [
      ["#4b4f92", "#30336f", "#262a5e"], ["#3e4386", "#282c63", "#1f2355"], ["#33397a", "#22275a", "#1a1e4c"],
    ],
    hills: [["#24366a", "#1b2a58"], ["#1f4258", "#17334a"]],
    meadow: ["#2a5452", "#1f4544", "#183838", "#122c2e"],
    pines: ["#163238", "#10262d", "#0b1c22"],
    flowers: [["#7d6cc0", "#5b4d98"], ["#d9b064", "#a88545"], ["#7d9bd0", "#5a74a6"], ["#c47aa8", "#94588a"], ["#b9bce6", "#8b8fc0"]],
    stones: [
      ["#1c1e45", "#2c2f62", "#424784", "#5e64a6", "#8a90cc"],
      ["#221b45", "#352b62", "#4e4384", "#6c60a6", "#978cce"],
      ["#122c34", "#1e434c", "#2f5f66", "#477f83", "#6fa8a6"],
      ["#2a1f3c", "#3f2f56", "#5a4774", "#786595", "#a08fbc"],
    ],
    rim: "#d9dcff",
    moon: { at: [0.36, 0.07], r: 6, tones: ["#fff7de", "#efe2bd", "#d9c99c"], halo: ["#262c66", "#20265c"] },
    sun: { at: [-0.18, 0.5] }, // the last of the sunset, low behind the ranges
    stars: 1,
    motes: { count: 34, core: "#ffe9a3", halo: "rgba(242, 196, 106, 0.42)", dim: "rgba(242, 196, 106, 0.3)" },
    sparkle: "#f2c46a",
  },
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
// Most of a band stays clean; only its seam breaks up.
const seam = (t, w = 0.3) => clamp((t - 0.5) / w + 0.5);

// Streak dithering: transitions break into short horizontal runs, the way painted pixel
// skies and water do, instead of a checkerboard.
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
  }
  set(x, y, c, a = 255) {
    x |= 0; y |= 0;
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const [r, g, b] = typeof c === "string" ? rgb(c) : c, i = (y * this.w + x) * 4;
    this.d[i] = r; this.d[i + 1] = g; this.d[i + 2] = b; this.d[i + 3] = a;
  }
  alpha(x, y) { return x < 0 || y < 0 || x >= this.w || y >= this.h ? 0 : this.d[(y * this.w + x) * 4 + 3]; }
  clear(x, y) { if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.d[(y * this.w + x) * 4 + 3] = 0; }
  done() { this.ctx.putImageData(this.img, 0, 0); return this; }
}

function drawSky(L, T, horizon, cx) {
  const n = T.sky.length;
  const sun = T.sun && [cx + Math.round(L.w * T.sun.at[0]), Math.round(L.h * T.sun.at[1])];
  for (let y = 0; y < L.h; y++) {
    const f = clamp(y / horizon) * (n - 1), i = Math.min(Math.floor(f), n - 2), t = f - i;
    for (let x = 0; x < L.w; x++) {
      let c = streak(x, y, seam(t, 0.35), 4, 10) ? T.sky[i + 1] : T.sky[i];
      if (sun) {
        // The sun has set behind the ridge; its glow warms the sky above it.
        const d = Math.hypot((x - sun[0]) / 2.4, y - sun[1]) / (L.h * 0.3);
        if (d < 1) c = streak(x, y, seam(1 - d, 0.5), 4, 10) ? (streak(x + 5, y, seam(1 - d / 0.5, 0.5), 4, 10) ? T.glow[1] : T.glow[0]) : c;
      }
      L.set(x, y, c);
    }
  }
  // Long thin wisps near the horizon.
  for (let k = 0; k < 9; k++) {
    const y = Math.round(horizon * (0.5 + hash(k * 3 + 1) * 0.45));
    const x0 = cx + Math.round((hash(k * 5 + 2) - 0.5) * L.w * 1.2), len = 30 + Math.round(hash(k * 7 + 3) * 70);
    for (let x = x0; x < x0 + len; x++) {
      const t = Math.sin(Math.PI * (x - x0) / len);
      if (streak(x, y, t * 0.9)) L.set(x, y, T.wisp[k % 2]);
      if (t > 0.6 && streak(x, y + 1, (t - 0.6) * 1.5)) L.set(x, y + 1, T.wisp[(k + 1) % 2]);
    }
  }
  if (T.stars) {
    for (let y = 0; y < horizon; y++) for (let x = 0; x < L.w; x++) {
      const h = h2(x - cx + 4096, y);
      if (h > 0.9955 - (1 - y / horizon) * 0.002) L.set(x, y, h > 0.9991 ? "#fff6dc" : h > 0.998 ? "#c9cff5" : "#7d84c6");
    }
  }
  // The moon, with a dithered halo at night.
  const [mx, my] = [cx + Math.round(Math.min(L.w * T.moon.at[0], 230)), Math.round(L.h * T.moon.at[1])];
  const r = T.moon.r;
  if (T.moon.halo) {
    for (let y = -r * 4; y <= r * 4; y++) for (let x = -r * 4; x <= r * 4; x++) {
      const d = Math.hypot(x, y) / r;
      if (d > 1 && d < 4 && streak(mx + x, my + y, (4 - d) / 3 * 0.8)) L.set(mx + x, my + y, d < 2.2 ? T.moon.halo[0] : T.moon.halo[1]);
    }
  }
  for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) {
    const d = x * x + y * y;
    if (d > r * r + r * 0.6) continue;
    const lit = (x * LIGHT.x + y * LIGHT.y) / r;
    const crater = r > 4 && ((x + 2) ** 2 + (y - 1) ** 2 < 2 || (x - 2) ** 2 + (y + 2) ** 2 < 1.5);
    L.set(mx + x, my + y, crater ? T.moon.tones[1] : lit > 0.25 || d < (r - 1.5) ** 2 ? T.moon.tones[0] : lit > -0.4 ? T.moon.tones[1] : T.moon.tones[2]);
  }
  return [mx, my];
}

// A cumulus sprite: lobes of a mound, each lit as its own sphere, with the base fading into
// the sky in streaks.
function makeCloud(T, w, seed) {
  const hgt = Math.round(w * 0.75), L = new Layer(Math.round(w * 1.5), hgt + 6);
  const base = hgt + 1, mid = L.w / 2, puffs = [];
  const r = k => hash(seed * 131 + k);
  const count = 7 + Math.floor(w / 9);
  for (let k = 0; k < count; k++) {
    const u = (r(k) * 2 - 1) * 0.9, mound = Math.cos(u * Math.PI / 2);
    const rad = w * (0.09 + 0.17 * mound) * (0.75 + r(k + 50) * 0.5);
    puffs.push([mid + u * w * 0.42, base - rad * 0.55 - mound * hgt * 0.42 * r(k + 90), rad]);
  }
  puffs.sort((a, b) => a[1] - b[1]); // lower lobes sit in front
  for (let y = 0; y < L.h; y++) for (let x = 0; x < L.w; x++) {
    let p = null;
    for (const q of puffs) if ((x - q[0]) ** 2 + (y - q[1]) ** 2 <= q[2] * q[2]) p = q;
    if (!p || y > base) continue;
    const nx = (x - p[0]) / p[2], ny = (y - p[1]) / p[2], nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny));
    const lobe = nx * LIGHT.x + ny * LIGHT.y + nz * LIGHT.z;
    const lum = 0.6 * (1 - y / base) * 1.6 + 0.4 * lobe - 0.1;
    const f = clamp(lum) * (T.cloud.length - 2);
    let i = T.cloud.length - 2 - Math.floor(f);
    if (i > 0 && streak(x, y, seam(f - Math.floor(f)), 2, 4)) i--;
    const under = (base - y) / 6;
    if (under < 1) { i = Math.max(i, T.cloud.length - 2); if (!streak(x, y, under + 0.15)) continue; }
    L.set(x, y, T.cloud[Math.min(i, T.cloud.length - 1)]);
  }
  return L.done();
}

// A ridge line made of peaks, so far ranges read as mountains, not noise.
function peaks(x, seed, amp, spacing) {
  let h = 0;
  for (let k = Math.floor(x / spacing) - 2; k <= Math.floor(x / spacing) + 2; k++) {
    const px = (k + 0.2 + hash(k * 92821 + seed) * 0.6) * spacing, ph = (0.4 + hash(k * 7919 + seed) * 0.6) * amp;
    h = Math.max(h, ph - Math.abs(x - px) * (0.42 + hash(k * 31 + seed) * 0.3));
  }
  return h + (fbm(x / 6, seed) - 0.5) * amp * 0.08;
}

function drawLand(L, T, horizon, cx, bg) {
  const W = L.w, H = L.h;
  // Far ranges: a few broad peaks, lit on the faces turned to the sunset, with snow-light
  // along the ridges and a softer middle tone where a face turns away.
  T.ridges.forEach((pal, k) => {
    const base = horizon + 4 + k * 6, amp = H * (0.24 - k * 0.055), spacing = 110 - k * 22, seed = 11 + k * 17;
    const hAt = x => base - peaks(x - cx + 2000, seed, amp, spacing);
    for (let x = 0; x < W; x++) {
      const h = Math.round(hAt(x)), slope = hAt(x + 2) - hAt(x - 2);
      for (let y = h; y < H; y++) {
        const depth = y - h;
        // A spur: the face's lighting wanders a little with depth, so faces aren't flat wedges.
        const wander = (fbm((x - cx) / 7 + depth / 9, seed + 3) - 0.5) * 1.6;
        const s2 = slope + wander;
        let c = s2 > 0.5 ? pal[0] : s2 < -0.4 ? pal[2] : pal[1];
        if (depth < 2) c = slope > -0.4 ? pal[0] : pal[1];
        if (c === pal[0] && depth > 10 && streak(x, y, seam((depth - 10) / 16), 3, 6)) c = pal[1];
        L.set(x, y, c);
      }
    }
  });
  // Haze between the ranges and the hills.
  for (let y = horizon - 2; y < horizon + 14; y++) for (let x = 0; x < W; x++) {
    const t = 1 - Math.abs(y - horizon - 6) / 8;
    if (t > 0 && streak(x, y, t * 0.55)) L.set(x, y, T.wisp[1]);
  }
  // Rolling hills.
  const hill = (pal, base, amp, scale, seed) => {
    const hAt = x => base - fbm((x - cx) / scale + 50, seed) * amp;
    for (let x = 0; x < W; x++) {
      const h = Math.round(hAt(x)), lit = hAt(x + 2) - hAt(x - 2) > -0.2;
      for (let y = h; y < H; y++) {
        const d = y - h;
        L.set(x, y, d < 2 || (lit && streak(x, y, 1 - d / 10)) ? pal[0] : pal[1]);
      }
    }
    return hAt;
  };
  // Pines in a few clusters, lit on their right. Each hill's pines are drawn before the
  // next hill, so the nearer hill hides their feet.
  const pine = (x0, ground, ht) => {
    for (let y = 0; y < ht; y++) {
      const t = y / ht, tier = (y % 4) / 4, half = Math.max(0, Math.round((t * 0.42 + tier * 0.12) * ht * 0.45));
      for (let x = -half; x <= half; x++) L.set(x0 + x, ground - ht + y, x > half * 0.3 ? T.pines[0] : x < -half * 0.4 ? T.pines[2] : T.pines[1]);
    }
    L.set(x0, ground - ht - 1, T.pines[1]);
    L.set(x0, ground, T.pines[2]); L.set(x0, ground + 1, T.pines[2]);
  };
  const pines = (hAt, onFar) => {
    for (let k = 0; k < 14; k++) {
      if ((hash(k * 43) > 0.5) !== onFar) continue;
      const x = cx + Math.round((hash(k * 41 + 5) - 0.5) * Math.min(W, 520));
      if (Math.abs(x - (cx + Math.min(W * 0.22, 120))) < 30) continue; // keep the cairn's skyline clear
      const n = 1 + Math.floor(hash(k * 47) * 4);
      for (let j = 0; j < n; j++) {
        const px = x + j * 3 + Math.round(hash(k * 53 + j) * 2);
        pine(px, Math.round(hAt(px)) + 3, Math.round((onFar ? 7 : 10) + hash(k * 59 + j) * (onFar ? 5 : 8)));
      }
    }
  };
  pines(hill(T.hills[0], horizon + 12, H * 0.1, 40, 21), true);
  pines(hill(T.hills[1], horizon + 22, H * 0.09, 30, 29), false);
  // The meadow, with grass strokes and flowers that grow larger toward the viewer.
  const meadowAt = x => horizon + 32 + (fbm((x - cx) / 34 + 9, 41) - 0.5) * H * 0.08;
  for (let x = 0; x < W; x++) {
    const h = Math.round(meadowAt(x));
    for (let y = h; y < H; y++) {
      const d = y - h;
      let i = d < 2 ? 0 : d < 10 ? (streak(x, y, (d - 2) / 8) ? 2 : 1) : 2;
      if (h2(x * 3, y) < 0.07) i = Math.max(0, i - 1);
      L.set(x, y, T.meadow[i]);
    }
  }
  for (let k = 0; k < W * 0.9; k++) {
    const x = Math.floor(h2(k, 1) * W), h = Math.round(meadowAt(x)), y = h + 3 + Math.floor(h2(k, 2) ** 0.7 * (H - h));
    const near = (y - h) / (H - h), pal = T.flowers[Math.floor(h2(k, 3) * T.flowers.length)];
    if (pal === T.flowers[0] && near > 0.35) { // lupine spikes in front
      const len = 3 + Math.round(near * 4);
      for (let j = 0; j < len; j++) L.set(x, y - j, j % 2 ? pal[1] : pal[0]);
      L.set(x, y + 1, T.meadow[3]);
    } else {
      L.set(x, y, pal[0]);
      if (near > 0.45) { L.set(x + 1, y, pal[1]); L.set(x, y + 1, pal[1]); }
    }
  }
  drawCairn(L, T, cx + Math.round(Math.min(W * 0.22, 120)), meadowAt);

  // Mist: the meadow fades into the page colour in long streaks, so the scene flows into
  // the page. A veil tone (half meadow, half page) comes first.
  const mistTop = horizon + 58, mistEnd = H - 34;
  for (let y = mistTop; y < H; y++) {
    const t = (y - mistTop) / (mistEnd - mistTop);
    for (let x = 0; x < W; x++) {
      if (t >= 1 || streak(x, y, t ** 1.2, 6, 18)) L.set(x, y, bg);
      else if (streak(x + 31, y, clamp(t * 2.2), 6, 18)) {
        const i = (y * W + x) * 4, a = 0.5;
        L.set(x, y, [L.d[i] * (1 - a) + bg[0] * a, L.d[i + 1] * (1 - a) + bg[1] * a, L.d[i + 2] * (1 - a) + bg[2] * a]);
      }
    }
  }
}

// The cairn: flat stones with uneven outlines, lit from the sunset side, selectively outlined
// (dark only away from the light), with contact shadows where stones rest on each other.
function drawCairn(L, T, kx, groundAt) {
  const ground = Math.round(groundAt(kx)) + 4;
  const specs = [[46, 14, 0, 0.04], [37, 12, 2, -0.05], [30, 11, -1, 0.06], [23, 10, 1, -0.04], [16, 8, 0, 0.05], [10, 6, 1, 0]];
  const pal = [0, 3, 2, 1, 3, 0];
  // Cast shadow on the grass, away from the light.
  for (let y = -2; y <= 2; y++) for (let x = -38; x <= 20; x++) {
    if ((x + 9) ** 2 / 29 ** 2 + y * y / 5 <= 1 && streak(kx + x, ground + y, 0.85)) L.set(kx + x, ground + y, T.meadow[3]);
  }
  let bottom = ground, prev = null;
  const placed = [];
  specs.forEach(([w, h, off, tilt], k) => {
    const ramp = T.stones[pal[k]], a = w / 2, b = h / 2, sx = kx + off, sy = bottom - b;
    const inside = (x, y) => {
      const dx = x + 0.5 - sx, dy = y + 0.5 - sy - dx * tilt;
      const ang = Math.atan2(dy / b, dx / a), wob = 1 + (noise(ang * 2.2 + 3, k * 13 + 1) - 0.5) * 0.16;
      return Math.abs(dx / (a * wob)) ** 2.6 + Math.abs(dy / (b * wob)) ** 2 <= 1;
    };
    placed.push({ sx, sy, a, b, inside });
    for (let y = Math.floor(sy - b) - 2; y <= sy + b + 2; y++) for (let x = Math.floor(sx - a) - 2; x <= sx + a + 2; x++) {
      if (!inside(x, y)) continue;
      const nx = clamp((x + 0.5 - sx) / a, -1, 1), ny = clamp((y + 0.5 - sy - (x - sx) * tilt) / b, -1, 1);
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx * 0.8 - ny * ny * 0.8));
      const lum = nx * LIGHT.x + ny * LIGHT.y * 1.25 + nz * LIGHT.z;
      let i = Math.round(clamp((lum + 0.15) / 1.2) * 3) + 1;
      if (h2(x * 5 + k, y * 3) < 0.08) i -= 1;            // pits and grain
      else if (h2(x * 7 + k, y * 11) < 0.04) i += 1;
      const edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
      if (edge) i = lum > 0.35 ? Math.min(i, 3) : 0;      // sel-out: no dark line on the lit rim
      // Contact shadow: the stone above sits in a dip of this one.
      if (prev && y < sy && y >= prev.sy + prev.b - 2 && Math.abs(x + 0.5 - prev.sx) < prev.a * 0.95) i = Math.min(i, 1);
      L.set(x, y, ramp[clamp(i, 0, 4)]);
      if (T.rim && edge && nx > 0.45 && ny < 0.3) L.set(x, y, T.rim);
    }
    prev = placed[placed.length - 1];
    bottom = Math.round(sy - b + 2);
  });
  // Grass and pebbles at the foot, in front of the base stone.
  for (let x = kx - 26; x <= kx + 27; x++) {
    if (h2(x, 77) < 0.5) continue;
    const len = 1 + Math.floor(h2(x, 78) * 3);
    for (let j = 0; j < len; j++) L.set(x, ground + 1 - j, j === len - 1 ? T.meadow[1] : T.meadow[2]);
  }
  for (const [dx, w] of [[-31, 3], [-25, 2], [29, 2]]) {
    L.set(kx + dx, ground, T.stones[0][2]); if (w > 2) L.set(kx + dx + 1, ground, T.stones[0][3]);
    if (w > 1) L.set(kx + dx + (w > 2 ? 2 : 1), ground, T.stones[0][1]);
  }
}

export function mountScene(canvas) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  let state = null, raf = 0, visible = true;

  function build() {
    const T = THEMES.night;
    const s = innerWidth < 600 ? 2 : 3;
    const W = Math.ceil(canvas.clientWidth / s), H = Math.ceil(canvas.clientHeight / s);
    canvas.width = W; canvas.height = H;
    const bg = getComputedStyle(document.body).backgroundColor.match(/\d+/g).slice(0, 3).map(Number);
    const cx = W >> 1, horizon = Math.round(H * 0.42);
    const sky = new Layer(W, H);
    const moon = drawSky(sky, T, horizon, cx);
    sky.done();
    const land = new Layer(W, H);
    drawLand(land, T, horizon, cx, bg);
    land.done();
    const clouds = [[-0.42, 0.1, 74], [-0.08, 0.2, 96], [0.24, 0.06, 56], [0.45, 0.22, 82], [-0.7, 0.24, 64], [0.75, 0.12, 70]]
      .map(([fx, fy, w], k) => {
        const sprite = makeCloud(T, Math.round(w * (W < 260 ? 0.7 : 1)), k + 1);
        return { sprite, x: cx + fx * Math.max(W, 420) - sprite.w / 2, y: Math.round(H * fy), speed: 0.6 + (1 - fy * 3) * 0.5 };
      });
    const sparkles = [[-0.3, 0.06], [-0.14, 0.2], [0.06, 0.05], [0.17, 0.24], [-0.44, 0.27], [0.4, 0.31], [-0.6, 0.12], [0.58, 0.2]]
      .map(([fx, fy], k) => ({ x: cx + Math.round(fx * Math.min(W, 640)), y: Math.round(H * fy), phase: k * 1.7 }));
    const motes = Array.from({ length: Math.round(T.motes.count * Math.min(1, W / 420)) }, (_, k) => spawn(k, W, H, horizon, true));
    // Past the width cap, the scene's sides dissolve into the page the same way its foot does.
    let edges = null;
    if (canvas.clientWidth < document.documentElement.clientWidth - 4) {
      edges = new Layer(W, H);
      const span = Math.min(48, W * 0.1);
      const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const t = 1 - Math.min(x, W - 1 - x) / span;
        if (t > 0 && Math.floor(t * 5) / 5 * 16 > bayer[(y & 3) * 4 + (x & 3)]) edges.set(x, y, bg);
      }
      edges.done();
    }
    state = { T, W, H, horizon, sky, land, clouds, sparkles, motes, moon, edges, t0: performance.now() };
    frame(performance.now());
  }

  function spawn(k, W, H, horizon, anywhere) {
    const r = Math.random;
    return {
      x: r() * W, y: anywhere ? horizon + 10 + r() * (H - horizon - 20) : H * (0.7 + r() * 0.2),
      vy: 1.2 + r() * 2.2, sway: 0.6 + r() * 1.2, phase: r() * 6.28, life: 0, max: 7 + r() * 9, tw: 1.5 + r() * 2,
    };
  }

  let last = 0;
  function frame(now) {
    if (!state) return;
    const { T, W, H, horizon, sky, land, clouds, sparkles, motes } = state;
    const dt = Math.min(0.1, last ? (now - last) / 1000 : 0);
    last = now;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, W, H);
    ctx.drawImage(sky.canvas, 0, 0);
    const t = (now - state.t0) / 1000;
    for (const c of clouds) {
      c.x += c.speed * dt;
      if (c.x > W + 10) c.x = -c.sprite.w - 10;
      ctx.drawImage(c.sprite.canvas, Math.round(c.x), c.y);
    }
    ctx.drawImage(land.canvas, 0, 0);
    // Sparkles in the sky: four-point stars that breathe.
    for (const s of sparkles) {
      const p = (Math.sin(t * 1.3 + s.phase) + 1) / 2, arm = p > 0.66 ? 2 : p > 0.2 ? 1 : 0;
      ctx.fillStyle = "#fffaf0"; ctx.fillRect(s.x, s.y, 1, 1);
      ctx.fillStyle = T.sparkle;
      for (let d = 1; d <= arm; d++) { ctx.fillRect(s.x + d, s.y, 1, 1); ctx.fillRect(s.x - d, s.y, 1, 1); ctx.fillRect(s.x, s.y + d, 1, 1); ctx.fillRect(s.x, s.y - d, 1, 1); }
    }
    // Fireflies rise slowly and twinkle.
    for (let k = 0; k < motes.length; k++) {
      const m = motes[k];
      m.life += dt; m.y -= m.vy * dt; m.x += Math.sin(t * 0.7 + m.phase) * m.sway * dt;
      if (m.life > m.max || m.y < horizon - 30) { motes[k] = spawn(k, W, H, horizon, false); continue; }
      const fade = Math.min(1, m.life / 1.5, (m.max - m.life) / 1.5);
      const tw = (Math.sin(t * m.tw + m.phase) + 1) / 2 * fade;
      const x = Math.round(m.x), y = Math.round(m.y);
      if (tw > 0.55) {
        ctx.fillStyle = T.motes.halo;
        ctx.fillRect(x - 1, y, 1, 1); ctx.fillRect(x + 1, y, 1, 1); ctx.fillRect(x, y - 1, 1, 1); ctx.fillRect(x, y + 1, 1, 1);
        ctx.fillStyle = T.motes.core;
      } else ctx.fillStyle = tw > 0.15 ? T.motes.dim : "rgba(0,0,0,0)";
      ctx.fillRect(x, y, 1, 1);
    }
    if (state.edges) ctx.drawImage(state.edges.canvas, 0, 0);
    if (!reduce.matches && visible && !document.hidden) raf = requestAnimationFrame(frame);
  }

  function restart() { cancelAnimationFrame(raf); last = 0; if (state) raf = requestAnimationFrame(frame); }
  let resizeTimer = 0;
  addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { cancelAnimationFrame(raf); build(); }, 120); });
  reduce.addEventListener("change", restart);
  document.addEventListener("visibilitychange", restart);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; restart(); }).observe(canvas);
  build();
}
