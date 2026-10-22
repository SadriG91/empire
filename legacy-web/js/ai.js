'use strict';
// Computer opponent: runs an economy, expands, advances epochs and attacks in waves.

const AI_RATIOS = [
  { food: 0.45, wood: 0.4, gold: 0.05, stone: 0.1 },
  { food: 0.4, wood: 0.3, gold: 0.2, stone: 0.1 },
  { food: 0.36, wood: 0.24, gold: 0.3, stone: 0.1 },
];

class AI {
  constructor(game, pid, diff) {
    this.g = game; this.pid = pid; this.p = game.players[pid]; this.d = DIFFICULTY[diff];
    this.next = 1; this.wave = this.d.wave; this.attackT = this.d.firstAttack;
    this.attacking = new Set(); this.saving = false; this.home = null;
  }
  update() {
    if (this.g.time < this.next) return;
    this.next = this.g.time + this.d.think;
    this.think();
  }
  think() {
    const g = this.g, p = this.p, pid = this.pid;
    const units = g.units.filter(u => !u.dead && u.owner === pid);
    const cits = units.filter(u => u.def.cls === 'citizen');
    const army = units.filter(u => u.def.cls !== 'citizen');
    const blds = g.buildings.filter(b => !b.dead && b.owner === pid);
    const tcs = blds.filter(b => b.type === 'town_center');
    const tc = tcs.find(b => b.built) || tcs[0];
    if (tc) this.home = { x: tc.x, y: tc.y, tx: tc.tx + 1, ty: tc.ty + 1 };
    if (!this.home) return;
    const count = t => blds.filter(b => b.type === t).length;
    const pending = blds.filter(b => !b.built).length;

    // Rebuild a lost Town Center
    if (!tcs.length && cits.length) this.build('town_center', cits, 3, 2, 14);

    // Citizens
    const citTarget = Math.round(Math.min(18 + p.epoch * 6, 50) * (this.d.gather < 1 ? 0.8 : 1));
    if (tc && tc.built && cits.length < citTarget && tc.queue.length === 0) g.train(tc, 'citizen');

    // Housing
    const housing = blds.some(b => b.type === 'house' && !b.built);
    if (!housing && p.popCap < MAX_POP && p.popCap - p.pop <= 4 + p.epoch * 2) this.build('house', cits, 1);

    // Infrastructure, one project at a time
    if (pending < 2) {
      if (cits.length >= 7 && count('barracks') === 0) this.build('barracks', cits, 2);
      else if (cits.length >= 11 && count('archery_range') === 0) this.build('archery_range', cits, 2);
      else if (cits.length >= 12 && count('storehouse') === 0) this.buildNearRes('storehouse', 'wood', cits);
      else if (p.epoch >= 1 && count('stable') === 0) this.build('stable', cits, 2);
      else if (p.epoch >= 2 && count('workshop') === 0) this.build('workshop', cits, 2);
      else if (p.epoch >= 1 && this.d.towers && count('tower') < Math.min(p.epoch, 3) && p.res.stone > 250) this.build('tower', cits, 1, 5, 9);
      else if (p.epoch >= 3 && count('barracks') < 2) this.build('barracks', cits, 2);
      else if (p.epoch >= 3 && count('storehouse') < 2) this.buildNearRes('storehouse', 'gold', cits);
      else if (p.res.wood > 450 && ['barracks', 'archery_range', 'stable', 'workshop'].reduce((a, t) => a + count(t), 0) < 3 + p.epoch) {
        const opts = ['barracks', 'archery_range', 'stable', 'workshop'].filter(t => BUILDINGS[t].epoch <= p.epoch);
        this.build(opts[Math.floor(g.rng() * opts.length)], cits, 2);
      }
    }

    this.assignIdle(cits);

    // Epoch advancement
    const nextE = EPOCHS[p.epoch + 1];
    this.saving = !!nextE && !p.advancing && cits.length >= 10 + p.epoch * 4 && g.time >= this.d.epochDelay[p.epoch + 1];
    if (this.saving && tc && tc.built && tc.queue.length === 0 && canAfford(p.res, nextE.cost)) { g.advance(tc); this.saving = false; }

    this.trainArmy(blds, army);
    this.military(army);
  }

  weights() {
    const p = this.p;
    const w = Object.assign({}, AI_RATIOS[Math.min(p.epoch, AI_RATIOS.length - 1)]);
    if (this.saving) {
      const cost = EPOCHS[p.epoch + 1].cost;
      for (const k in cost) if (p.res[k] < cost[k]) w[k] += 0.25;
    }
    if (p.res.wood < 100) w.wood += 0.1;
    return w;
  }

  assignIdle(cits) {
    const g = this.g;
    const counts = { food: 0, wood: 0, stone: 0, gold: 0 };
    const use = new Map();
    for (const c of cits) {
      if ((c.state === 'gather' || c.state === 'return') && c.gatherType) {
        counts[c.gatherType]++;
        use.set(c.gatherId, (use.get(c.gatherId) || 0) + 1);
      }
    }
    const idle = cits.filter(c => c.state === 'idle');
    for (const c of idle) {
      const w = this.weights();
      const order = RES.slice().sort((a, b) => (w[b] * cits.length - counts[b]) - (w[a] * cits.length - counts[a]));
      for (const res of order) {
        const tgt = this.gatherTarget(res, use);
        if (tgt) {
          g.cmdGather([c], tgt);
          counts[res]++; use.set(tgt.id, (use.get(tgt.id) || 0) + 1);
          break;
        }
        if (res === 'food' && this.build('farm', [c], 1, 2, 9)) { counts.food++; break; }
      }
    }
  }

  gatherTarget(res, use) {
    const g = this.g, h = this.home;
    if (res === 'food') {
      const farm = g.findResourceNear(this.pid, 'food', h.x, h.y, 14, 0, true);
      if (farm) return farm;
    }
    let best = null, bd = (res === 'food' ? 16 : 60) * T;
    for (const r of g.resources) {
      if (r.dead || r.res !== res || (use.get(r.id) || 0) >= (res === 'wood' ? 2 : 3)) continue;
      const d = Math.hypot(r.x - h.x, r.y - h.y);
      if (d < bd && g.accessible(r)) { bd = d; best = r; }
    }
    return best;
  }

  build(type, cits, n = 1, minR, maxR, near) {
    const g = this.g, p = this.p, def = BUILDINGS[type];
    if (def.epoch > p.epoch || !canAfford(p.res, def.cost) || !cits.length) return null;
    const c = near || this.home;
    const spot = this.findSpot(type, c.tx, c.ty, minR != null ? minR : def.size + 2, maxR != null ? maxR : 16);
    if (!spot) return null;
    const sx = spot.x * T, sy = spot.y * T;
    const builders = cits.filter(u => u.state !== 'build')
      .sort((a, b) => Math.hypot(a.x - sx, a.y - sy) - Math.hypot(b.x - sx, b.y - sy)).slice(0, n);
    if (!builders.length) return null;
    const b = g.placeBuilding(this.pid, type, spot.x, spot.y, builders);
    return typeof b === 'string' ? null : b;
  }
  buildNearRes(type, res, cits) {
    const g = this.g, h = this.home;
    let best = null, bd = 1e9;
    for (const r of g.resources) {
      if (r.dead || r.res !== res) continue;
      const d = Math.hypot(r.x - h.x, r.y - h.y);
      if (d > 6 * T && d < bd) { bd = d; best = r; }
    }
    if (!best) return this.build(type, cits, 1);
    return this.build(type, cits, 1, 1, 6, { tx: best.tx, ty: best.ty });
  }
  findSpot(type, cx, cy, minR, maxR) {
    const s = BUILDINGS[type].size;
    const margin = type === 'farm' ? 0 : 1;
    for (let r = minR; r <= maxR; r++) {
      const cand = [];
      for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const tx = cx + dx - Math.floor(s / 2), ty = cy + dy - Math.floor(s / 2);
        if (this.g.canPlace(type, tx, ty, this.pid, margin)) cand.push({ x: tx, y: ty });
      }
      if (cand.length) return cand[Math.floor(this.g.rng() * cand.length)];
    }
    return null;
  }

  trainArmy(blds, army) {
    const g = this.g, p = this.p;
    const cap = Math.floor((15 + p.epoch * 12) * this.d.armyCap);
    if (army.length >= cap) return;
    const prod = blds.filter(b => b.built && b.type !== 'town_center' && PRODUCTION[b.type] && b.queue.length === 0);
    for (const b of prod) {
      const type = g.trainable(b)[0];
      if (!type) continue;
      const cost = UNITS[type].cost;
      if (this.saving) {
        const need = EPOCHS[p.epoch + 1].cost;
        if (Object.keys(cost).some(k => need[k] && p.res[k] - cost[k] < need[k])) continue;
      }
      if (p.res.wood < 80 && cost.wood) continue; // keep wood for houses
      g.train(b, type);
    }
  }

  military(army) {
    const g = this.g, h = this.home;
    for (const id of this.attacking) if (!g.get(id)) this.attacking.delete(id);

    // Defend home
    const threat = g.findTarget(this.pid, h.x, h.y, 15 * T, true);
    if (threat) {
      for (const u of army) if (!this.attacking.has(u.id) && u.state !== 'attack') g.cmdAttack([u], threat);
    }

    // Launch attack waves
    const home = army.filter(u => !this.attacking.has(u.id));
    if (!threat && g.time >= this.attackT && home.length >= this.wave) {
      const tgt = this.pickTarget(h.x, h.y);
      if (tgt) {
        for (const u of home) this.attacking.add(u.id);
        g.cmdMove(home, tgt.x, tgt.y, true);
        this.wave = Math.min(this.wave + this.d.waveGrow, 40);
        this.attackT = g.time + 45;
      }
    }
    // Keep attackers pushing
    for (const u of army) {
      if (this.attacking.has(u.id) && u.state === 'idle') {
        const tgt = this.pickTarget(u.x, u.y);
        if (tgt) g.cmdMove([u], tgt.x, tgt.y, true);
      }
    }
    // Idle defenders gather in front of base
    if (!threat) {
      const rx = h.x + (MAP_W * T / 2 - h.x) * 0.12, ry = h.y + (MAP_H * T / 2 - h.y) * 0.12;
      const loiter = home.filter(u => u.state === 'idle' && Math.hypot(u.x - rx, u.y - ry) > 5 * T);
      if (loiter.length) g.cmdMove(loiter, rx, ry);
    }
  }
  pickTarget(x, y) {
    let best = null, bd = 1e9;
    for (const b of this.g.buildings) {
      if (b.dead || b.owner === this.pid) continue;
      const d = Math.hypot(b.x - x, b.y - y) - (b.type === 'town_center' || b.type === 'wonder' ? 8 * T : 0);
      if (d < bd) { bd = d; best = b; }
    }
    if (best) return best;
    for (const u of this.g.units) {
      if (u.dead || u.owner === this.pid) continue;
      const d = Math.hypot(u.x - x, u.y - y);
      if (d < bd) { bd = d; best = u; }
    }
    return best;
  }
}
