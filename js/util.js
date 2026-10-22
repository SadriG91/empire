'use strict';

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// Binary min-heap keyed by number.
class MinHeap {
  constructor() { this.k = []; this.v = []; }
  get size() { return this.k.length; }
  push(v, key) {
    const K = this.k, V = this.v;
    let i = K.length; K.push(key); V.push(v);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (K[p] <= key) break;
      K[i] = K[p]; V[i] = V[p]; i = p;
    }
    K[i] = key; V[i] = v;
  }
  pop() {
    const K = this.k, V = this.v;
    const top = V[0];
    const lk = K.pop(), lv = V.pop();
    const n = K.length;
    if (n > 0) {
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        if (l >= n) break;
        const r = l + 1;
        const c = (r < n && K[r] < K[l]) ? r : l;
        if (K[c] >= lk) break;
        K[i] = K[c]; V[i] = V[c]; i = c;
      }
      K[i] = lk; V[i] = lv;
    }
    return top;
  }
}

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
function canAfford(res, cost) { for (const k in cost) if ((res[k] || 0) < cost[k]) return false; return true; }
function pay(res, cost) { for (const k in cost) res[k] -= cost[k]; }
function refund(res, cost, f = 1) { for (const k in cost) res[k] += Math.floor(cost[k] * f); }
function missingRes(res, cost) { for (const k in cost) if ((res[k] || 0) < cost[k]) return k; return null; }
function costText(cost) { return Object.keys(cost).map(k => `${RES_ICON[k]} ${cost[k]}`).join('  '); }

function valueNoise(rng, w, h, cell) {
  const gw = Math.ceil(w / cell) + 2, gh = Math.ceil(h / cell) + 2;
  const g = new Float32Array(gw * gh);
  for (let i = 0; i < g.length; i++) g[i] = rng();
  const sm = t => t * t * (3 - 2 * t);
  return (x, y) => {
    const fx = x / cell, fy = y / cell;
    const ix = Math.floor(fx), iy = Math.floor(fy);
    const tx = sm(fx - ix), ty = sm(fy - iy);
    const a = g[iy * gw + ix], b = g[iy * gw + ix + 1], c = g[(iy + 1) * gw + ix], d = g[(iy + 1) * gw + ix + 1];
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
  };
}
function fbm(rng, w, h) {
  const n1 = valueNoise(rng, w, h, 16), n2 = valueNoise(rng, w, h, 8), n3 = valueNoise(rng, w, h, 4);
  return (x, y) => n1(x, y) * 0.6 + n2(x, y) * 0.3 + n3(x, y) * 0.1;
}
function hash2(x, y) {
  let h = (x * 374761393 + y * 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function fmtTime(s) { s = Math.floor(s); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; }
