'use strict';
// Core simulation: entities, orders, combat, economy, epochs, victory.

const GATHER_RATE = { food: 0.6, wood: 0.5, stone: 0.42, gold: 0.42 };
const FARM_RATE = 0.45;
const RES_AMOUNT = { tree: 100, berries: 150, stone: 250, gold: 300 };
const RES_KIND = { tree: 'wood', berries: 'food', stone: 'stone', gold: 'gold' };
const PROJ_SPEED = { arrow: 420, stone: 330, bullet: 900, grenade: 300, boulder: 260, ball: 420, shell: 450, rocket: 380 };

class Game {
  constructor(opts = {}) {
    this.seed = opts.seed != null ? opts.seed : (Math.random() * 1e9) | 0;
    this.diff = opts.difficulty || 'normal';
    this.rng = mulberry32(this.seed);
    this.map = new GameMap(MAP_W, MAP_H);
    this.ents = new Map();
    this.units = []; this.buildings = []; this.resources = [];
    this.projectiles = []; this.effects = []; this.pings = [];
    this.time = 0; this.nextId = 1; this.messages = []; this.winner = null; this.over = false;
    this.vis = new Uint8Array(MAP_W * MAP_H); this.explored = new Uint8Array(MAP_W * MAP_H);
    this.visT = 0; this.checkT = 0; this.dirty = false; this.visVersion = 0;
    this.lastAlert = [-99, -99];
    this.revealAll = !!opts.revealAll;

    // Randomly pick which diagonal corners the empires start in.
    const flip = this.rng() < 0.5;
    const c0 = { x: 14, y: MAP_H - 15 }, c1 = { x: MAP_W - 15, y: 14 };
    this.starts = flip ? [c0, c1] : [{ x: 14, y: 14 }, { x: MAP_W - 15, y: MAP_H - 15 }];

    const d = DIFFICULTY[this.diff];
    this.players = [0, 1].map(i => ({
      id: i, name: i === 0 ? 'You' : 'Rival Empire', color: PLAYER_COLORS[i],
      res: { food: 200, wood: 250, stone: 150, gold: 100 }, epoch: 0, advancing: false,
      pop: 0, popCap: 0, isAI: i !== 0, gatherMult: i === 0 ? 1 : d.gather,
      stats: { trained: 0, lost: 0, killed: 0, gathered: 0, built: 0 }, wonderT: null,
    }));
    for (const k of RES) this.players[1].res[k] += d.bonus;

    generateWorld(this, this.rng);
    this.starts.forEach((s, i) => {
      this.addBuilding('town_center', i, s.x - 1, s.y - 1, true);
      const offs = [[-2, 2], [0, 2], [2, 2], [2, 0], [-2, 0]];
      for (const [dx, dy] of offs) this.addUnit('citizen', i, (s.x + dx) * T + T / 2, (s.y + dy) * T + T / 2);
      this.addUnit('clubman', i, (s.x + 2) * T + T / 2, (s.y - 2) * T + T / 2);
    });
    this.ais = opts.noAI ? [] : [new AI(this, 1, this.diff)];
    if (opts.aiForPlayer0) this.ais.push(new AI(this, 0, this.diff));
    this.updatePopCaps();
    this.updateVis();
  }

  // ---------------------------------------------------------------- entities
  addUnit(type, owner, x, y) {
    const def = UNITS[type];
    const u = {
      id: this.nextId++, kind: 'unit', type, def, owner, x, y, hp: def.hp, maxHp: def.hp,
      state: 'idle', path: null, pi: 0, targetId: 0, carry: 0, carryRes: null, gatherId: 0, gatherType: null,
      buildId: 0, dropId: 0, cd: 0, scanT: Math.random() * 0.5, repathT: 0, amove: null, facing: Math.PI / 2,
      swing: 0, failCount: 0, gacc: 0, hitT: 0, working: false, moving: false, born: this.time,
    };
    this.units.push(u); this.ents.set(u.id, u);
    this.players[owner].pop++;
    return u;
  }
  addBuilding(type, owner, tx, ty, built) {
    const def = BUILDINGS[type];
    const b = {
      id: this.nextId++, kind: 'building', type, def, owner, tx, ty, size: def.size,
      x: (tx + def.size / 2) * T, y: (ty + def.size / 2) * T,
      hp: built ? def.hp : Math.max(1, def.hp * 0.05), maxHp: def.hp, built, progress: built ? 1 : 0,
      queue: [], rally: null, cd: 0, gathererId: 0, hitT: 0,
    };
    const code = def.walkable ? B_FARM : B_BLD;
    for (let y = ty; y < ty + def.size; y++) for (let x = tx; x < tx + def.size; x++) this.map.block[y * MAP_W + x] = code;
    this.buildings.push(b); this.ents.set(b.id, b);
    if (!def.walkable) this.evictUnits(b);
    return b;
  }
  addResource(type, tx, ty) {
    const i = ty * MAP_W + tx;
    if (this.map.block[i] !== B_FREE) return null;
    const r = { id: this.nextId++, kind: 'res', type, res: RES_KIND[type], amount: RES_AMOUNT[type], max: RES_AMOUNT[type], tx, ty, size: 1, x: tx * T + T / 2, y: ty * T + T / 2 };
    this.map.block[i] = B_RES;
    this.resources.push(r); this.ents.set(r.id, r);
    return r;
  }
  evictUnits(b) {
    for (const u of this.units) {
      const tx = Math.floor(u.x / T), ty = Math.floor(u.y / T);
      if (tx >= b.tx && ty >= b.ty && tx < b.tx + b.size && ty < b.ty + b.size) {
        const s = this.map.nearestWalkable(tx, ty);
        if (s) { u.x = s.x * T + T / 2; u.y = s.y * T + T / 2; u.path = null; }
      }
    }
  }
  get(id) { const e = this.ents.get(id); return e && !e.dead ? e : null; }

  distToEnt(px, py, e) {
    if (e.kind === 'unit') return Math.max(0, Math.hypot(px - e.x, py - e.y) - e.def.r);
    const x0 = e.tx * T, y0 = e.ty * T, s = e.size * T;
    const dx = Math.max(x0 - px, 0, px - (x0 + s)), dy = Math.max(y0 - py, 0, py - (y0 + s));
    return Math.hypot(dx, dy);
  }
  nearestPoint(e, px, py) {
    if (e.kind === 'unit') return [e.x, e.y];
    const x0 = e.tx * T, y0 = e.ty * T, s = e.size * T;
    return [clamp(px, x0, x0 + s), clamp(py, y0, y0 + s)];
  }
  accessible(e) {
    for (let y = e.ty - 1; y <= e.ty + e.size; y++) for (let x = e.tx - 1; x <= e.tx + e.size; x++) {
      if ((x < e.tx || y < e.ty || x >= e.tx + e.size || y >= e.ty + e.size) && this.map.walkable(x, y)) return true;
    }
    return false;
  }

  msg(owner, text, color = '#e5e7eb') {
    if (owner !== 0) return;
    this.messages.push({ text, color, t: this.time });
    if (this.messages.length > 6) this.messages.shift();
  }

  // ---------------------------------------------------------------- movement
  pathTo(u, px, py) {
    const m = this.map;
    const sx = Math.floor(u.x / T), sy = Math.floor(u.y / T);
    let tx = Math.floor(px / T), ty = Math.floor(py / T);
    let pts = m.findPath(sx, sy, (x, y) => x === tx && y === ty, tx, ty);
    if (m.walkablePx(px, py) && (m.lastReached || (sx === tx && sy === ty))) {
      if (pts.length) pts[pts.length - 1] = { x: px, y: py }; else pts = [{ x: px, y: py }];
    }
    u.path = m.smooth(u.x, u.y, pts); u.pi = 0;
  }
  pathToEnt(u, e, reach) {
    const m = this.map;
    const sx = Math.floor(u.x / T), sy = Math.floor(u.y / T);
    const hx = Math.floor(e.x / T), hy = Math.floor(e.y / T);
    const r = Math.max(reach, T * 0.75);
    const pts = m.findPath(sx, sy, (x, y) => this.distToEnt(x * T + T / 2, y * T + T / 2, e) <= r, hx, hy);
    if (!m.lastReached) u.failCount++;
    u.path = m.smooth(u.x, u.y, pts); u.pi = 0;
    u.pathEntPos = { x: e.x, y: e.y };
  }
  stepPath(u, dt) {
    if (!u.path || u.pi >= u.path.length) return true;
    const p = u.path[u.pi];
    const dx = p.x - u.x, dy = p.y - u.y, d = Math.hypot(dx, dy);
    const sp = u.def.speed * T * dt;
    u.moving = true;
    if (d > 0.01) u.facing = Math.atan2(dy, dx);
    if (d <= sp) { u.x = p.x; u.y = p.y; u.pi++; return u.pi >= u.path.length; }
    u.x += dx / d * sp; u.y += dy / d * sp;
    return false;
  }
  // Move toward an entity until within reach. Returns true when in range.
  approach(u, e, reach, dt) {
    if (this.distToEnt(u.x, u.y, e) <= reach) { u.path = null; u.failCount = 0; return true; }
    u.repathT -= dt;
    const moved = u.pathEntPos && Math.hypot(e.x - u.pathEntPos.x, e.y - u.pathEntPos.y) > T * 1.5;
    const done = !u.path || u.pi >= u.path.length;
    if (!u.path || (u.repathT <= 0 && (moved || done))) {
      this.pathToEnt(u, e, reach);
      u.repathT = 0.7 + Math.random() * 0.5;
    }
    if (u.path && u.pi < u.path.length) this.stepPath(u, dt);
    else {
      const [nx, ny] = this.nearestPoint(e, u.x, u.y);
      const dx = nx - u.x, dy = ny - u.y, d = Math.hypot(dx, dy) || 1;
      const sp = u.def.speed * T * dt;
      const x2 = u.x + dx / d * sp, y2 = u.y + dy / d * sp;
      if (this.map.walkablePx(x2, y2)) { u.x = x2; u.y = y2; u.facing = Math.atan2(dy, dx); u.moving = true; }
    }
    return this.distToEnt(u.x, u.y, e) <= reach;
  }

  // ---------------------------------------------------------------- orders
  formationSpots(tx, ty, n) {
    const spots = [];
    for (let r = 0; r < 12 && spots.length < n; r++) {
      for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (this.map.walkable(tx + dx, ty + dy)) spots.push({ x: tx + dx, y: ty + dy, d: dx * dx + dy * dy });
      }
    }
    spots.sort((a, b) => a.d - b.d);
    return spots;
  }
  cmdMove(units, x, y, amove = false) {
    units = units.filter(u => u.kind === 'unit' && !u.dead);
    if (!units.length) return;
    x = clamp(x, 1, MAP_W * T - 1); y = clamp(y, 1, MAP_H * T - 1);
    const tx = Math.floor(x / T), ty = Math.floor(y / T);
    const spots = this.formationSpots(tx, ty, units.length);
    // nearest units take the central spots
    units.sort((a, b) => Math.hypot(a.x - x, a.y - y) - Math.hypot(b.x - x, b.y - y));
    units.forEach((u, i) => {
      let px = x, py = y;
      if (units.length > 1 || !this.map.walkablePx(x, y)) {
        const s = spots[i % Math.max(1, spots.length)];
        if (s) { px = s.x * T + T / 2 + (Math.random() - 0.5) * 6; py = s.y * T + T / 2 + (Math.random() - 0.5) * 6; }
      }
      u.state = 'move'; u.targetId = 0; u.buildId = 0; u.failCount = 0;
      u.amove = amove ? { x: px, y: py } : null;
      if (!amove && u.def.cls === 'citizen') { u.gatherType = null; u.gatherId = 0; }
      this.pathTo(u, px, py);
    });
  }
  cmdAttack(units, e) {
    for (const u of units) {
      if (u.kind !== 'unit' || u.dead || e.owner === u.owner) continue;
      u.state = 'attack'; u.targetId = e.id; u.path = null; u.amove = null; u.failCount = 0; u.repathT = 0;
    }
  }
  cmdStop(units) {
    for (const u of units) { if (u.kind !== 'unit') continue; u.state = 'idle'; u.path = null; u.amove = null; u.targetId = 0; }
  }
  cmdGather(units, e) {
    const cits = units.filter(u => u.kind === 'unit' && u.def.cls === 'citizen');
    const others = units.filter(u => !cits.includes(u));
    if (others.length) this.cmdMove(others, e.x, e.y);
    if (e.kind === 'building' && !e.built) return this.cmdBuild(cits, e);
    for (const u of cits) {
      let tgt = e;
      if (e.kind === 'building' && e.def.farm) {
        if (this.farmTaken(e, u)) {
          const alt = this.findResourceNear(u.owner, 'food', e.x, e.y, 8, 0, true);
          if (alt) tgt = alt;
        }
        if (tgt.kind === 'building') tgt.gathererId = u.id;
      }
      u.state = 'gather'; u.gatherId = tgt.id; u.gatherType = tgt.kind === 'res' ? tgt.res : 'food';
      u.path = null; u.amove = null; u.targetId = 0; u.failCount = 0; u.repathT = 0;
    }
  }
  farmTaken(f, u) {
    const g = this.get(f.gathererId);
    return g && g !== u && g.state !== 'idle' && g.gatherId === f.id;
  }
  cmdBuild(units, b) {
    for (const u of units) {
      if (u.kind !== 'unit' || u.def.cls !== 'citizen') continue;
      u.state = 'build'; u.buildId = b.id; u.path = null; u.amove = null; u.targetId = 0; u.failCount = 0; u.repathT = 0;
    }
  }
  cmdReturn(units, drop) {
    for (const u of units) {
      if (u.def.cls !== 'citizen' || u.carry <= 0) continue;
      u.state = 'return'; u.dropId = drop.id; u.path = null;
    }
  }

  canPlace(type, tx, ty, owner, margin = 0) {
    const s = BUILDINGS[type].size, m = this.map;
    for (let y = ty - margin; y < ty + s + margin; y++) for (let x = tx - margin; x < tx + s + margin; x++) {
      if (!m.inb(x, y)) return false;
      const inner = x >= tx && y >= ty && x < tx + s && y < ty + s;
      const bl = m.block[y * MAP_W + x];
      if (inner) {
        if (bl !== B_FREE) return false;
        if (owner === 0 && !this.explored[y * MAP_W + x] && !this.revealAll) return false;
      } else if (bl !== B_FREE && bl !== B_FARM) return false;
    }
    // can't build right on top of enemy units
    for (const u of this.units) {
      if (u.owner === owner || u.dead) continue;
      const ux = Math.floor(u.x / T), uy = Math.floor(u.y / T);
      if (ux >= tx && uy >= ty && ux < tx + s && uy < ty + s) return false;
    }
    return true;
  }
  placeBuilding(owner, type, tx, ty, builders) {
    const p = this.players[owner], def = BUILDINGS[type];
    if (def.epoch > p.epoch) return `Requires ${EPOCHS[def.epoch].name}`;
    if (!this.canPlace(type, tx, ty, owner)) return 'Cannot build there';
    if (type === 'wonder' && this.buildings.some(b => b.owner === owner && b.type === 'wonder')) return 'Only one Wonder allowed';
    if (!canAfford(p.res, def.cost)) return `Not enough ${missingRes(p.res, def.cost)}`;
    pay(p.res, def.cost);
    const b = this.addBuilding(type, owner, tx, ty, false);
    this.cmdBuild(builders, b);
    return b;
  }
  trainable(b) {
    const lines = PRODUCTION[b.type];
    if (!lines || !b.built) return [];
    const ep = this.players[b.owner].epoch;
    return lines.map(row => row[Math.min(ep, row.length - 1)]).filter(Boolean);
  }
  train(b, type) {
    const p = this.players[b.owner], def = UNITS[type];
    if (!this.trainable(b).includes(type)) return 'Not available';
    if (b.queue.length >= 8) return 'Queue is full';
    if (!canAfford(p.res, def.cost)) return `Not enough ${missingRes(p.res, def.cost)}`;
    pay(p.res, def.cost);
    b.queue.push({ type, t: 0, time: def.time });
    return true;
  }
  advance(b) {
    const p = this.players[b.owner];
    const next = EPOCHS[p.epoch + 1];
    if (!next) return 'Final epoch reached';
    if (b.type !== 'town_center' || !b.built) return 'Need a Town Center';
    if (p.advancing) return 'Already advancing';
    if (!canAfford(p.res, next.cost)) return `Not enough ${missingRes(p.res, next.cost)}`;
    pay(p.res, next.cost);
    p.advancing = true;
    b.queue.push({ type: '@epoch', t: 0, time: next.time });
    this.msg(b.owner, `Advancing to the ${next.name}...`, '#a5b4fc');
    return true;
  }
  cancelQueue(b, i) {
    const q = b.queue[i];
    if (!q) return;
    const p = this.players[b.owner];
    if (q.type === '@epoch') { refund(p.res, EPOCHS[p.epoch + 1].cost); p.advancing = false; }
    else refund(p.res, UNITS[q.type].cost);
    b.queue.splice(i, 1);
  }
  setRally(b, x, y, target) { b.rally = { x, y, id: target ? target.id : 0 }; }

  // ---------------------------------------------------------------- queries
  findTarget(owner, x, y, rad, unitsOnly = false) {
    let best = null, bs = 1e9;
    for (const u of this.units) {
      if (u.dead || u.owner === owner) continue;
      const d = Math.hypot(u.x - x, u.y - y) - u.def.r;
      if (d > rad) continue;
      const s = d + (u.def.cls === 'citizen' ? T : 0);
      if (s < bs) { bs = s; best = u; }
    }
    if (unitsOnly || best) return best;
    for (const b of this.buildings) {
      if (b.dead || b.owner === owner) continue;
      const d = this.distToEnt(x, y, b);
      if (d > rad) continue;
      const s = d + (b.def.farm ? T * 4 : 0);
      if (s < bs) { bs = s; best = b; }
    }
    return best;
  }
  findResourceNear(owner, res, x, y, radTiles, excludeId = 0, farmsOnly = false) {
    let best = null, bd = radTiles * T;
    if (res === 'food') {
      for (const b of this.buildings) {
        if (b.dead || b.owner !== owner || !b.def.farm || !b.built || b.id === excludeId || this.farmTaken(b, null)) continue;
        const d = Math.hypot(b.x - x, b.y - y);
        if (d < bd) { bd = d; best = b; }
      }
      if (farmsOnly || best) return best;
    }
    for (const r of this.resources) {
      if (r.dead || r.res !== res || r.id === excludeId) continue;
      const d = Math.hypot(r.x - x, r.y - y);
      if (d < bd && this.accessible(r)) { bd = d; best = r; }
    }
    return best;
  }
  nearestDropoff(owner, x, y) {
    let best = null, bd = 1e9;
    for (const b of this.buildings) {
      if (b.dead || b.owner !== owner || !b.built || !b.def.dropoff) continue;
      const d = this.distToEnt(x, y, b);
      if (d < bd) { bd = d; best = b; }
    }
    return best;
  }
  carryCap(owner) { return 10 + this.players[owner].epoch * 2; }

  // ---------------------------------------------------------------- unit AI
  updateUnit(u, dt) {
    u.cd -= dt; if (u.swing > 0) u.swing -= dt; if (u.hitT > 0) u.hitT -= dt;
    u.moving = false; u.working = false;
    switch (u.state) {
      case 'idle': if (u.def.cls !== 'citizen') this.scan(u, dt); break;
      case 'move':
        if (u.amove) this.scan(u, dt);
        if (u.state === 'move' && this.stepPath(u, dt)) { u.path = null; u.state = 'idle'; u.amove = null; }
        break;
      case 'attack': this.uAttack(u, dt); break;
      case 'gather': this.uGather(u, dt); break;
      case 'return': this.uReturn(u, dt); break;
      case 'build': this.uBuild(u, dt); break;
    }
  }
  scan(u, dt) {
    u.scanT -= dt;
    if (u.scanT > 0) return;
    u.scanT = 0.5;
    const e = this.findTarget(u.owner, u.x, u.y, u.def.los * T);
    if (e) { u.targetId = e.id; u.state = 'attack'; u.path = null; u.failCount = 0; u.repathT = 0; }
  }
  uAttack(u, dt) {
    const e = this.get(u.targetId);
    if (!e || e.owner === u.owner) return this.endAttack(u);
    const reach = u.def.range * T;
    if (this.approach(u, e, reach, dt)) {
      u.facing = Math.atan2(e.y - u.y, e.x - u.x);
      if (u.cd <= 0) { u.cd = u.def.cd; this.strike(u, e); }
    } else if (u.failCount > 4) this.endAttack(u);
    // ranged units on attack-move switch to closer threats
    if (u.amove && u.def.range > 1.5 && e.kind === 'building') { u.scanT -= dt; if (u.scanT <= 0) { u.scanT = 1; const t = this.findTarget(u.owner, u.x, u.y, reach, true); if (t) u.targetId = t.id; } }
  }
  endAttack(u) {
    u.targetId = 0; u.path = null;
    if (u.amove) { u.state = 'move'; this.pathTo(u, u.amove.x, u.amove.y); }
    else { u.state = 'idle'; u.scanT = 0; }
  }
  uGather(u, dt) {
    let e = this.get(u.gatherId);
    if (!e) {
      e = this.findResourceNear(u.owner, u.gatherType, u.x, u.y, 10);
      if (!e) { if (u.carry > 0) { u.state = 'return'; u.path = null; } else u.state = 'idle'; return; }
      u.gatherId = e.id; u.failCount = 0; u.path = null;
      if (e.kind === 'building') e.gathererId = u.id;
    }
    const isFarm = e.kind === 'building';
    if (isFarm && !e.built) { u.buildId = e.id; u.state = 'build'; return; }
    if (u.carry > 0 && u.carryRes !== u.gatherType) { u.carry = 0; }
    const cap = this.carryCap(u.owner);
    if (u.carry >= cap) { u.state = 'return'; u.path = null; return; }
    if (this.approach(u, e, isFarm ? 2 : 0.8 * T, dt)) {
      u.working = true;
      u.facing = Math.atan2(e.y - u.y, e.x - u.x);
      const p = this.players[u.owner];
      const rate = (isFarm ? FARM_RATE : GATHER_RATE[u.gatherType]) * (1 + 0.1 * p.epoch) * p.gatherMult;
      u.gacc += rate * dt;
      while (u.gacc >= 1 && u.carry < cap) {
        if (!isFarm) { if (e.amount <= 0) break; e.amount--; }
        u.carry++; u.gacc--;
      }
      u.carryRes = u.gatherType;
      if (!isFarm && e.amount <= 0) this.depleteResource(e);
      if (u.carry >= cap) { u.state = 'return'; u.path = null; }
    } else if (u.failCount > 3) {
      u.failCount = 0;
      const alt = this.findResourceNear(u.owner, u.gatherType, u.x, u.y, 12, e.id);
      if (alt) { u.gatherId = alt.id; u.path = null; } else u.state = 'idle';
    }
  }
  depleteResource(r) {
    r.dead = true; this.dirty = true;
    this.map.block[r.ty * MAP_W + r.tx] = B_FREE;
    this.ents.delete(r.id);
  }
  uReturn(u, dt) {
    if (u.carry <= 0) return this.resumeGather(u);
    let d = this.get(u.dropId);
    if (!d || d.owner !== u.owner || !d.built) {
      d = this.nearestDropoff(u.owner, u.x, u.y);
      if (!d) { u.state = 'idle'; return; }
      u.dropId = d.id; u.path = null;
    }
    if (this.approach(u, d, 0.8 * T, dt)) {
      const p = this.players[u.owner];
      p.res[u.carryRes] += u.carry; p.stats.gathered += u.carry;
      u.carry = 0; u.dropId = 0;
      this.resumeGather(u);
    } else if (u.failCount > 4) { u.state = 'idle'; u.failCount = 0; }
  }
  resumeGather(u) {
    u.path = null; u.failCount = 0;
    u.state = u.gatherType ? 'gather' : 'idle';
  }
  uBuild(u, dt) {
    const b = this.get(u.buildId);
    if (!b || b.owner !== u.owner || (b.built && b.hp >= b.maxHp)) {
      if (b && b.def.farm && b.owner === u.owner && !this.farmTaken(b, u)) {
        b.gathererId = u.id; u.gatherType = 'food'; u.gatherId = b.id; u.state = 'gather'; return;
      }
      const nb = this.buildings.find(x => !x.dead && !x.built && x.owner === u.owner && Math.hypot(x.x - u.x, x.y - u.y) < T * 10);
      if (nb) { u.buildId = nb.id; u.path = null; return; }
      u.buildId = 0;
      if (u.gatherType && this.get(u.gatherId)) this.resumeGather(u); else { u.state = 'idle'; u.gatherType = null; }
      return;
    }
    if (this.approach(u, b, 0.8 * T, dt)) {
      u.working = true;
      u.facing = Math.atan2(b.y - u.y, b.x - u.x);
      if (b.built) { b.hp = Math.min(b.maxHp, b.hp + b.maxHp * dt / (b.def.time * 1.5)); return; } // repair
      const inc = dt / b.def.time;
      b.progress = Math.min(1, b.progress + inc);
      b.hp = Math.min(b.maxHp, b.hp + b.maxHp * inc);
      if (b.progress >= 1) this.completeBuilding(b);
    } else if (u.failCount > 4) { u.state = 'idle'; u.failCount = 0; }
  }
  completeBuilding(b) {
    b.built = true; b.progress = 1;
    const p = this.players[b.owner];
    p.stats.built++;
    this.msg(b.owner, `${b.def.name} completed.`, '#86efac');
    if (b.type === 'wonder') {
      p.wonderT = 0;
      const other = this.players[1 - b.owner];
      if (b.owner === 0) this.msg(0, `Wonder complete! Defend it for ${WONDER_TIME / 60} minutes to win.`, '#fde68a');
      else this.msg(0, `The enemy built a Wonder! Destroy it within ${WONDER_TIME / 60} minutes!`, '#fca5a5');
      void other;
    }
  }

  // ---------------------------------------------------------------- combat
  strike(u, e) {
    u.swing = 0.25;
    if (u.def.proj) this.fire(u, e, u.def.atk, u.def.proj, u.def.splash || 0);
    else this.damage(u, e, u.def.atk);
  }
  fire(src, e, atk, kind, splash = 0) {
    const sx = src.x, sy = src.kind === 'building' ? src.y - src.size * T * 0.3 : src.y;
    const dist = Math.hypot(e.x - sx, e.y - sy);
    this.projectiles.push({
      x: sx, y: sy, sx, sy, tx: e.x, ty: e.y, targetId: e.id, t: 0, dur: Math.max(0.05, dist / (PROJ_SPEED[kind] || 400)),
      atk, kind, splash, src: { id: src.id, owner: src.owner, kind: src.kind, def: src.def },
    });
  }
  updateProjectiles(dt) {
    for (const pr of this.projectiles) {
      pr.t += dt;
      const e = this.get(pr.targetId);
      if (e) { pr.tx = e.x; pr.ty = e.y; }
      const k = Math.min(1, pr.t / pr.dur);
      pr.x = pr.sx + (pr.tx - pr.sx) * k; pr.y = pr.sy + (pr.ty - pr.sy) * k;
      if (k >= 1) {
        pr.done = true;
        if (e) this.damage(pr.src, e, pr.atk);
        if (pr.splash) {
          const r = pr.splash * T;
          for (const u of this.units) {
            if (u.dead || u === e || u.owner === pr.src.owner) continue;
            if (Math.hypot(u.x - pr.tx, u.y - pr.ty) <= r + u.def.r) this.damage(pr.src, u, pr.atk * 0.5);
          }
          this.effects.push({ type: 'boom', x: pr.tx, y: pr.ty, t: 0, dur: 0.45, r });
        }
      }
    }
    this.projectiles = this.projectiles.filter(p => !p.done);
  }
  damage(src, e, atk) {
    if (e.dead) return;
    const tcls = e.kind === 'building' ? 'building' : e.def.cls;
    let m = 1;
    const bonus = src.def.bonus;
    if (bonus && bonus[tcls] != null) m = bonus[tcls];
    else if (tcls === 'building') m = src.kind === 'building' ? 0.5 : (src.def.range > 1.5 ? 0.25 : 0.5);
    if (src.kind === 'building') m *= 1 + 0.15 * this.players[src.owner].epoch;
    const dmg = Math.max(1, atk * m - (e.def.armor || 0));
    e.hp -= dmg; e.hitT = 0.15;
    if (e.kind === 'unit' && e.def.cls !== 'citizen' && this.get(src.id)) {
      if (e.state === 'idle' || (e.state === 'move' && e.amove)) { e.targetId = src.id; e.state = 'attack'; e.path = null; e.failCount = 0; }
    }
    this.alert(e.owner, e);
    if (e.hp <= 0) this.kill(e, src);
  }
  alert(owner, e) {
    if (this.time - this.lastAlert[owner] < 20) return;
    this.lastAlert[owner] = this.time;
    if (owner === 0) {
      this.msg(0, e.kind === 'building' ? `Your ${e.def.name} is under attack!` : 'Your units are under attack!', '#fca5a5');
      this.pings.push({ x: e.x, y: e.y, t: this.time });
    }
  }
  kill(e, src) {
    if (e.dead) return;
    e.dead = true; this.dirty = true;
    this.ents.delete(e.id);
    const owner = this.players[e.owner];
    owner.stats.lost++;
    if (src && src.owner != null && src.owner !== e.owner) this.players[src.owner].stats.killed++;
    if (e.kind === 'unit') {
      owner.pop--;
      this.effects.push({ type: 'corpse', x: e.x, y: e.y, t: 0, dur: 8, color: owner.color, r: e.def.r });
    } else {
      for (let y = e.ty; y < e.ty + e.size; y++) for (let x = e.tx; x < e.tx + e.size; x++) this.map.block[y * MAP_W + x] = B_FREE;
      this.effects.push({ type: 'rubble', x: e.x, y: e.y, t: 0, dur: 20, size: e.size });
      this.effects.push({ type: 'boom', x: e.x, y: e.y, t: 0, dur: 0.7, r: e.size * T * 0.6 });
      if (e.queue.some(q => q.type === '@epoch')) owner.advancing = false;
      if (e.type === 'wonder') owner.wonderT = null;
      this.msg(e.owner, `Your ${e.def.name} was destroyed!`, '#fca5a5');
      if (e.owner === 1) this.msg(0, `Enemy ${e.def.name} destroyed.`, '#86efac');
    }
  }

  // ---------------------------------------------------------------- buildings
  updateBuilding(b, dt) {
    if (b.hitT > 0) b.hitT -= dt;
    if (!b.built) return;
    const p = this.players[b.owner];
    if (b.queue.length) {
      const q = b.queue[0];
      if (q.type === '@epoch') {
        q.t += dt;
        if (q.t >= q.time) { b.queue.shift(); this.advanceEpoch(p); }
      } else if (p.pop >= p.popCap) {
        if (!q.blocked && b.owner === 0) this.msg(0, p.popCap >= MAX_POP ? 'Population limit reached.' : 'Need more houses! Population limit reached.', '#fbbf24');
        q.blocked = true;
      } else {
        q.blocked = false;
        q.t += dt;
        if (q.t >= q.time) { b.queue.shift(); this.spawnFrom(b, q.type); }
      }
    }
    if (b.def.atk) {
      b.cd -= dt;
      if (b.cd <= 0) {
        const e = this.findTarget(b.owner, b.x, b.y, b.def.range * T + b.size * T / 2, true);
        if (e) { b.cd = b.def.cd; this.fire(b, e, b.def.atk, 'arrow'); } else b.cd = 0.4;
      }
    }
    if (b.type === 'wonder' && p.wonderT != null) {
      p.wonderT += dt;
      if (p.wonderT >= WONDER_TIME) this.endGame(b.owner, 'Wonder victory');
    }
  }
  spawnFrom(b, type) {
    const p = this.players[b.owner];
    const want = b.rally || { x: b.x, y: b.y + b.size * T };
    let best = null, bd = 1e9;
    for (let r = 1; r <= 3 && !best; r++) {
      for (let y = b.ty - r; y < b.ty + b.size + r; y++) for (let x = b.tx - r; x < b.tx + b.size + r; x++) {
        if (x > b.tx - r && x < b.tx + b.size + r - 1 && y > b.ty - r && y < b.ty + b.size + r - 1) continue;
        if (!this.map.walkable(x, y)) continue;
        const d = Math.hypot(x * T + T / 2 - want.x, y * T + T / 2 - want.y);
        if (d < bd) { bd = d; best = { x, y }; }
      }
    }
    if (!best) best = this.map.nearestWalkable(b.tx, b.ty, 10) || { x: b.tx, y: b.ty };
    const u = this.addUnit(type, b.owner, best.x * T + T / 2 + (Math.random() - 0.5) * 8, best.y * T + T / 2 + (Math.random() - 0.5) * 8);
    p.stats.trained++;
    if (b.rally) {
      const t = this.get(b.rally.id);
      if (t && u.def.cls === 'citizen' && (t.kind === 'res' || (t.kind === 'building' && t.owner === u.owner && (t.def.farm || !t.built)))) this.cmdGather([u], t);
      else if (t && t.owner !== u.owner && t.kind !== 'res') this.cmdAttack([u], t);
      else this.cmdMove([u], b.rally.x, b.rally.y);
    }
    return u;
  }
  advanceEpoch(p) {
    p.epoch++; p.advancing = false;
    this.msg(p.id, `You have entered the ${EPOCHS[p.epoch].name}!`, '#a5b4fc');
    if (p.id === 1) this.msg(0, `The Rival Empire has entered the ${EPOCHS[p.epoch].name}.`, '#fcd34d');
    for (const u of this.units) {
      if (u.dead || u.owner !== p.id) continue;
      const line = UNIT_LINE[u.type];
      if (!line) continue;
      const row = PRODUCTION[line.bld][line.row];
      const nt = row[Math.min(p.epoch, row.length - 1)];
      if (nt && nt !== u.type) {
        const ratio = u.hp / u.maxHp;
        u.type = nt; u.def = UNITS[nt]; u.maxHp = u.def.hp; u.hp = Math.max(1, ratio * u.maxHp);
      }
    }
  }
  updatePopCaps() {
    for (const p of this.players) p.popCap = 0;
    for (const b of this.buildings) if (!b.dead && b.built && b.def.pop) this.players[b.owner].popCap += b.def.pop;
    for (const p of this.players) p.popCap = Math.min(MAX_POP, p.popCap);
  }

  // ---------------------------------------------------------------- world
  separate(dt) {
    const buckets = new Map();
    for (const u of this.units) {
      if (u.dead) continue;
      const k = Math.floor(u.y / T) * MAP_W + Math.floor(u.x / T);
      let a = buckets.get(k);
      if (!a) buckets.set(k, a = []);
      a.push(u);
    }
    const f = Math.min(1, dt * 10);
    for (const u of this.units) {
      if (u.dead) continue;
      const tx = Math.floor(u.x / T), ty = Math.floor(u.y / T);
      for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
        const a = buckets.get((ty + oy) * MAP_W + tx + ox);
        if (!a) continue;
        for (const v of a) {
          if (v.id <= u.id) continue;
          let dx = v.x - u.x, dy = v.y - u.y;
          const rr = (u.def.r + v.def.r) * 0.85;
          const d2 = dx * dx + dy * dy;
          if (d2 >= rr * rr) continue;
          let d = Math.sqrt(d2);
          if (d < 0.01) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; d = Math.hypot(dx, dy); }
          const push = (rr - d) * 0.5 * f;
          const nx = dx / d * push, ny = dy / d * push;
          // units standing still yield to moving ones
          const wu = u.moving && !v.moving ? 0.3 : 1, wv = v.moving && !u.moving ? 0.3 : 1;
          this.shift(u, -nx * wu, -ny * wu); this.shift(v, nx * wv, ny * wv);
        }
      }
    }
  }
  shift(u, dx, dy) { const x = u.x + dx, y = u.y + dy; if (this.map.walkablePx(x, y)) { u.x = x; u.y = y; } }

  updateVis() {
    const vis = this.vis, ex = this.explored;
    vis.fill(0);
    const mark = (cx, cy, r) => {
      const tx = Math.floor(cx / T), ty = Math.floor(cy / T), r2 = r * r;
      for (let y = Math.max(0, ty - r); y <= Math.min(MAP_H - 1, ty + r); y++) {
        for (let x = Math.max(0, tx - r); x <= Math.min(MAP_W - 1, tx + r); x++) {
          const dx = x - tx, dy = y - ty;
          if (dx * dx + dy * dy <= r2) { const i = y * MAP_W + x; vis[i] = 1; ex[i] = 1; }
        }
      }
    };
    for (const u of this.units) if (!u.dead && u.owner === 0) mark(u.x, u.y, u.def.los);
    for (const b of this.buildings) if (!b.dead && b.owner === 0) mark(b.x, b.y, b.def.los + Math.floor(b.size / 2));
    if (this.revealAll) { vis.fill(1); ex.fill(1); }
    this.visVersion++;
  }
  isVisible(e) {
    if (e.kind === 'unit') return this.vis[Math.floor(e.y / T) * MAP_W + Math.floor(e.x / T)] === 1;
    for (let y = e.ty; y < e.ty + e.size; y++) for (let x = e.tx; x < e.tx + e.size; x++) if (this.vis[y * MAP_W + x]) return true;
    return false;
  }
  isExplored(e) {
    for (let y = e.ty; y < e.ty + e.size; y++) for (let x = e.tx; x < e.tx + e.size; x++) if (this.explored[y * MAP_W + x]) return true;
    return false;
  }

  checkVictory() {
    for (const p of this.players) {
      const hasTC = this.buildings.some(b => !b.dead && b.owner === p.id && b.type === 'town_center');
      const hasCit = this.units.some(u => !u.dead && u.owner === p.id && u.def.cls === 'citizen');
      if (!hasTC && !hasCit) { this.endGame(1 - p.id, 'Conquest'); return; }
    }
  }
  endGame(winner, how) {
    if (this.over) return;
    this.over = true; this.winner = winner; this.winHow = how;
  }

  update(dt) {
    if (this.over) return;
    this.time += dt;
    this.updatePopCaps();
    for (const u of this.units) if (!u.dead) this.updateUnit(u, dt);
    for (const b of this.buildings) if (!b.dead) this.updateBuilding(b, dt);
    this.updateProjectiles(dt);
    this.separate(dt);
    for (const ef of this.effects) ef.t += dt;
    this.effects = this.effects.filter(e => e.t < e.dur);
    for (const ai of this.ais) ai.update(dt);
    if (this.dirty) {
      this.units = this.units.filter(e => !e.dead);
      this.buildings = this.buildings.filter(e => !e.dead);
      this.resources = this.resources.filter(e => !e.dead);
      this.dirty = false;
    }
    this.visT -= dt;
    if (this.visT <= 0) { this.visT = 0.2; this.updateVis(); }
    this.checkT -= dt;
    if (this.checkT <= 0) { this.checkT = 1; this.checkVictory(); }
  }
}
