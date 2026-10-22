'use strict';
// Tile grid, A* pathfinding and world generation.

const B_FREE = 0, B_WATER = 1, B_RES = 2, B_BLD = 3, B_FARM = 4;
const TER_GRASS = 0, TER_WATER = 1, TER_SAND = 2, TER_DIRT = 3;
const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
const LOS_OFFS = [[0, 0], [-6, -6], [6, -6], [-6, 6], [6, 6]];

class GameMap {
  constructor(w, h) {
    this.w = w; this.h = h;
    const n = w * h;
    this.terrain = new Uint8Array(n);
    this.block = new Uint8Array(n);
    this.g = new Float32Array(n);
    this.came = new Int32Array(n);
    this.seen = new Uint32Array(n);
    this.closed = new Uint32Array(n);
    this.gen = 0;
    this.lastReached = true;
  }
  inb(x, y) { return x >= 0 && y >= 0 && x < this.w && y < this.h; }
  walkable(x, y) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return false;
    const b = this.block[y * this.w + x];
    return b === B_FREE || b === B_FARM;
  }
  walkablePx(px, py) { return this.walkable(Math.floor(px / T), Math.floor(py / T)); }

  // A* over 8-connected grid. isGoal(tx,ty) decides arrival; (hx,hy) steers the heuristic.
  // If the goal is unreachable, returns a path to the closest explored tile.
  findPath(sx, sy, isGoal, hx, hy, maxIter = 5000) {
    const W = this.w;
    this.lastReached = true;
    if (isGoal(sx, sy)) return [];
    const gen = ++this.gen;
    const G = this.g, came = this.came, seen = this.seen, closed = this.closed;
    const heur = (x, y) => { const dx = Math.abs(x - hx), dy = Math.abs(y - hy); return Math.max(dx, dy) + 0.414 * Math.min(dx, dy); };
    const heap = new MinHeap();
    const s = sy * W + sx;
    G[s] = 0; seen[s] = gen; came[s] = -1;
    heap.push(s, heur(sx, sy));
    let best = s, bestH = heur(sx, sy), iter = 0;
    while (heap.size && iter++ < maxIter) {
      const cur = heap.pop();
      if (closed[cur] === gen) continue;
      closed[cur] = gen;
      const cx = cur % W, cy = (cur / W) | 0;
      if (isGoal(cx, cy)) return this.reconstruct(cur);
      const ch = heur(cx, cy);
      if (ch < bestH) { bestH = ch; best = cur; }
      for (let d = 0; d < 8; d++) {
        const dx = DIRS[d][0], dy = DIRS[d][1];
        const nx = cx + dx, ny = cy + dy;
        if (!this.walkable(nx, ny)) continue;
        const diag = d >= 4;
        if (diag && (!this.walkable(cx + dx, cy) || !this.walkable(cx, cy + dy))) continue;
        const n = ny * W + nx;
        if (closed[n] === gen) continue;
        const ng = G[cur] + (diag ? 1.414 : 1);
        if (seen[n] !== gen || ng < G[n]) {
          seen[n] = gen; G[n] = ng; came[n] = cur;
          heap.push(n, ng + heur(nx, ny));
        }
      }
    }
    this.lastReached = false;
    return this.reconstruct(best);
  }
  reconstruct(i) {
    const out = [];
    while (i !== -1 && this.came[i] !== -1) { out.push(i); i = this.came[i]; }
    out.reverse();
    return out.map(k => ({ x: (k % this.w) * T + T / 2, y: Math.floor(k / this.w) * T + T / 2 }));
  }
  lineClear(x0, y0, x1, y1) {
    const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0) / 6);
    for (let k = 1; k <= n; k++) {
      const t = k / n, x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
      for (const o of LOS_OFFS) if (!this.walkablePx(x + o[0], y + o[1])) return false;
    }
    return true;
  }
  // String-pulling: skip waypoints that are in direct line of sight.
  smooth(x0, y0, pts) {
    if (pts.length < 2) return pts;
    const out = [];
    let ax = x0, ay = y0, i = 0;
    while (i < pts.length) {
      let j = Math.min(pts.length - 1, i + 12);
      while (j > i && !this.lineClear(ax, ay, pts[j].x, pts[j].y)) j--;
      out.push(pts[j]);
      ax = pts[j].x; ay = pts[j].y; i = j + 1;
    }
    return out;
  }
  // Nearest walkable tile to (tx,ty), spiralling outwards.
  nearestWalkable(tx, ty, maxR = 12) {
    if (this.walkable(tx, ty)) return { x: tx, y: ty };
    for (let r = 1; r <= maxR; r++) {
      let best = null, bd = 1e9;
      for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (this.walkable(tx + dx, ty + dy)) { const d = dx * dx + dy * dy; if (d < bd) { bd = d; best = { x: tx + dx, y: ty + dy }; } }
      }
      if (best) return best;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// World generation
// ---------------------------------------------------------------------------
function generateWorld(game, rng) {
  const m = game.map, W = m.w, H = m.h;
  const starts = game.starts;
  const nWater = fbm(rng, W, H), nForest = fbm(rng, W, H), nVar = fbm(rng, W, H);
  const nearStart = (x, y, r) => starts.some(s => Math.hypot(x - s.x, y - s.y) < r);
  const a = starts[0], b = starts[1];
  const corridor = (x, y) => {
    const dx = b.x - a.x, dy = b.y - a.y;
    const t = clamp(((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy), 0, 1);
    return Math.hypot(x - (a.x + dx * t), y - (a.y + dy * t));
  };
  game.noiseVar = nVar;

  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x;
    const w = nWater(x, y);
    if (w < 0.3 && !nearStart(x, y, 14) && corridor(x, y) > 3) { m.terrain[i] = TER_WATER; m.block[i] = B_WATER; }
    else if (w < 0.345) m.terrain[i] = TER_SAND;
    else if (nVar(x, y) > 0.64) m.terrain[i] = TER_DIRT;
  }
  // Forests
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x;
    if (m.block[i] !== B_FREE || m.terrain[i] === TER_SAND) continue;
    if (nForest(x, y) > 0.6 && !nearStart(x, y, 9) && corridor(x, y) > 2.5 && rng() < 0.85) game.addResource('tree', x, y);
  }
  // Starting resources near each base, placed at spread-out angles.
  for (const s of starts) {
    const a0 = rng() * Math.PI * 2;
    const spots = [['berries', 6, 7, 0], ['gold', 5, 8, 1.55], ['stone', 5, 8, 3.1], ['tree', 22, 10, 4.65], ['berries', 5, 11, 2.3]];
    for (const [type, count, dist, off] of spots) {
      const ang = a0 + off;
      placeCluster(game, rng, type, Math.round(s.x + Math.cos(ang) * dist), Math.round(s.y + Math.sin(ang) * dist), count);
    }
  }
  // Scattered resources around the map
  const scatter = (type, clusters, size) => {
    for (let k = 0; k < clusters; k++) {
      for (let tries = 0; tries < 30; tries++) {
        const x = 3 + Math.floor(rng() * (W - 6)), y = 3 + Math.floor(rng() * (H - 6));
        if (nearStart(x, y, 16) || m.block[y * W + x] !== B_FREE) continue;
        placeCluster(game, rng, type, x, y, size);
        break;
      }
    }
  };
  scatter('gold', 10, 6); scatter('stone', 8, 5); scatter('berries', 8, 6); scatter('tree', 12, 14);
}

function placeCluster(game, rng, type, cx, cy, count) {
  const m = game.map;
  const open = [[cx, cy]];
  let placed = 0, guard = 0;
  while (open.length && placed < count && guard++ < 400) {
    const idx = Math.floor(rng() * open.length);
    const [x, y] = open.splice(idx, 1)[0];
    if (!m.inb(x, y) || m.block[y * m.w + x] !== B_FREE || m.terrain[y * m.w + x] === TER_WATER) continue;
    // keep space around starting town centers
    if (game.starts.some(s => Math.abs(x - s.x) <= 3 && Math.abs(y - s.y) <= 3)) continue;
    game.addResource(type, x, y);
    placed++;
    for (const [dx, dy] of DIRS.slice(0, 4)) open.push([x + dx, y + dy]);
  }
}
