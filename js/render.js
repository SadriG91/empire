'use strict';
// Canvas renderer: terrain, entities, effects, fog of war and minimap.

class Renderer {
  constructor(canvas, minimap, game) {
    this.c = canvas; this.ctx = canvas.getContext('2d');
    this.mm = minimap; this.mctx = minimap.getContext('2d');
    this.g = game;
    this.cam = { x: 0, y: 0, z: 1 };
    this.buildTerrain();
    this.fog = document.createElement('canvas'); this.fog.width = MAP_W; this.fog.height = MAP_H;
    this.fctx = this.fog.getContext('2d');
    this.fogImg = this.fctx.createImageData(MAP_W, MAP_H);
    this.fogVersion = -1;
    this.mmImg = this.mctx.createImageData(MAP_W, MAP_H);
    this.mmCanvas = document.createElement('canvas'); this.mmCanvas.width = MAP_W; this.mmCanvas.height = MAP_H;
    this.mmT = 0;
  }

  terrainColor(x, y) {
    const m = this.g.map, i = y * MAP_W + x, t = m.terrain[i];
    const v = this.g.noiseVar ? this.g.noiseVar(x, y) : 0.5, h = hash2(x, y);
    if (t === TER_WATER) {
      let land = 0;
      for (const [dx, dy] of DIRS) if (m.inb(x + dx, y + dy) && m.terrain[(y + dy) * MAP_W + x + dx] !== TER_WATER) land++;
      return land ? [58, 120, 170] : [38 + h * 6, 92 + h * 8, 145 + h * 8];
    }
    if (t === TER_SAND) return [214 + h * 10, 196 + h * 10, 140 + h * 8];
    if (t === TER_DIRT) return [128 + h * 12, 112 + h * 10, 72 + h * 8];
    return [78 + v * 30 + h * 10, 122 + v * 30 + h * 12, 52 + v * 14 + h * 6];
  }
  buildTerrain() {
    const off = document.createElement('canvas');
    off.width = MAP_W * T; off.height = MAP_H * T;
    const c = off.getContext('2d');
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
      const [r, g, b] = this.terrainColor(x, y);
      c.fillStyle = `rgb(${r | 0},${g | 0},${b | 0})`;
      c.fillRect(x * T, y * T, T, T);
    }
    // soft blend: draw tufts / speckles / waves
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
      const t = this.g.map.terrain[y * MAP_W + x];
      for (let k = 0; k < 5; k++) {
        const h1 = hash2(x * 7 + k, y * 13 + k * 3), h2 = hash2(x * 11 + k * 5, y * 3 + k);
        const px = x * T + h1 * T, py = y * T + h2 * T;
        if (t === TER_GRASS) { c.fillStyle = h1 > 0.5 ? 'rgba(40,80,20,0.35)' : 'rgba(170,200,90,0.25)'; c.fillRect(px, py, 2, 3); }
        else if (t === TER_WATER) { if (k < 2) { c.strokeStyle = 'rgba(200,230,255,0.18)'; c.beginPath(); c.moveTo(px - 4, py); c.quadraticCurveTo(px, py - 2, px + 4, py); c.stroke(); } }
        else { c.fillStyle = 'rgba(90,70,40,0.25)'; c.fillRect(px, py, 2, 2); }
      }
    }
    // shoreline foam
    c.fillStyle = 'rgba(235,245,255,0.35)';
    const m = this.g.map;
    for (let y = 0; y < MAP_H; y++) for (let x = 0; x < MAP_W; x++) {
      if (m.terrain[y * MAP_W + x] !== TER_WATER) continue;
      for (const [dx, dy] of DIRS.slice(0, 4)) {
        if (!m.inb(x + dx, y + dy) || m.terrain[(y + dy) * MAP_W + x + dx] === TER_WATER) continue;
        if (dx === 1) c.fillRect(x * T + T - 3, y * T, 3, T);
        if (dx === -1) c.fillRect(x * T, y * T, 3, T);
        if (dy === 1) c.fillRect(x * T, y * T + T - 3, T, 3);
        if (dy === -1) c.fillRect(x * T, y * T, T, 3);
      }
    }
    this.terrain = off;
  }

  resize(w, h) { this.c.width = w; this.c.height = h; }
  viewW() { return this.c.width / this.cam.z; }
  viewH() { return this.c.height / this.cam.z; }
  clampCam() {
    const cam = this.cam;
    cam.x = clamp(cam.x, -64, MAP_W * T - this.viewW() + 64);
    cam.y = clamp(cam.y, -64, MAP_H * T - this.viewH() + 64);
  }
  centerOn(x, y) { this.cam.x = x - this.viewW() / 2; this.cam.y = y - this.viewH() / 2; this.clampCam(); }
  toWorld(mx, my) { return { x: this.cam.x + mx / this.cam.z, y: this.cam.y + my / this.cam.z }; }

  // ------------------------------------------------------------------ frame
  draw(ui) {
    const ctx = this.ctx, cam = this.cam, g = this.g;
    const W = this.c.width, H = this.c.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#0b0f14'; ctx.fillRect(0, 0, W, H);
    ctx.setTransform(cam.z, 0, 0, cam.z, -cam.x * cam.z, -cam.y * cam.z);
    const vx0 = cam.x, vy0 = cam.y, vx1 = cam.x + W / cam.z, vy1 = cam.y + H / cam.z;
    const sx0 = clamp(vx0, 0, MAP_W * T), sy0 = clamp(vy0, 0, MAP_H * T), sx1 = clamp(vx1, 0, MAP_W * T), sy1 = clamp(vy1, 0, MAP_H * T);
    if (sx1 > sx0 && sy1 > sy0) ctx.drawImage(this.terrain, sx0, sy0, sx1 - sx0, sy1 - sy0, sx0, sy0, sx1 - sx0, sy1 - sy0);
    const inView = (x, y, m = 64) => x > vx0 - m && x < vx1 + m && y > vy0 - m && y < vy1 + m;
    const sel = ui.selSet;

    // decals
    for (const ef of g.effects) {
      if (!inView(ef.x, ef.y)) continue;
      if (ef.type === 'rubble') this.drawRubble(ctx, ef);
      else if (ef.type === 'corpse' && g.vis[Math.floor(ef.y / T) * MAP_W + Math.floor(ef.x / T)]) this.drawCorpse(ctx, ef);
    }
    // farms (ground level)
    for (const b of g.buildings) if (b.def.farm && inView(b.x, b.y) && (b.owner === 0 || g.isExplored(b))) this.drawFarm(ctx, b, sel.has(b.id));

    // depth-sorted objects
    const objs = [];
    for (const r of g.resources) if (inView(r.x, r.y) && g.explored[r.ty * MAP_W + r.tx]) objs.push(r);
    for (const b of g.buildings) if (!b.def.farm && inView(b.x, b.y, 128) && (b.owner === 0 || g.isExplored(b))) objs.push(b);
    for (const u of g.units) if (inView(u.x, u.y) && (u.owner === 0 || g.isVisible(u))) objs.push(u);
    objs.sort((a, b) => (a.kind === 'unit' ? a.y : (a.ty + a.size) * T - 2) - (b.kind === 'unit' ? b.y : (b.ty + b.size) * T - 2));
    // selection rings under everything
    for (const o of objs) if (sel.has(o.id)) this.drawSelRing(ctx, o);
    for (const o of objs) {
      if (o.kind === 'res') this.drawResource(ctx, o);
      else if (o.kind === 'building') this.drawBuilding(ctx, o);
      else this.drawUnit(ctx, o);
    }
    // projectiles & explosions
    for (const p of g.projectiles) if (inView(p.x, p.y)) this.drawProjectile(ctx, p);
    for (const ef of g.effects) if (ef.type === 'boom' && inView(ef.x, ef.y)) this.drawBoom(ctx, ef);

    // health bars
    for (const o of objs) {
      if (o.kind === 'res') { if (sel.has(o.id)) this.drawBar(ctx, o, o.amount / o.max, '#fbbf24'); continue; }
      if (sel.has(o.id) || o.hp < o.maxHp || (o.kind === 'building' && !o.built)) this.drawHp(ctx, o);
    }

    this.drawFog(ctx);

    // rally point of selected building
    if (ui.sel.length === 1) {
      const b = g.get(ui.sel[0]);
      if (b && b.kind === 'building' && b.owner === 0 && b.rally) {
        ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.setLineDash([6, 6]); ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(b.x, b.y); ctx.lineTo(b.rally.x, b.rally.y); ctx.stroke(); ctx.setLineDash([]);
        this.drawFlag(ctx, b.rally.x, b.rally.y, g.players[0].color);
      }
    }
    // move markers
    for (const mk of ui.markers) {
      const k = (performance.now() - mk.t) / 600;
      if (k > 1) continue;
      ctx.strokeStyle = mk.color; ctx.globalAlpha = 1 - k; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.ellipse(mk.x, mk.y, 12 * (1 - k * 0.6), 7 * (1 - k * 0.6), 0, 0, Math.PI * 2); ctx.stroke();
      ctx.globalAlpha = 1;
    }
    // building ghost
    if (ui.placing && ui.mouseWorld) {
      const def = BUILDINGS[ui.placing], s = def.size;
      const tx = Math.floor(ui.mouseWorld.x / T - s / 2 + 0.5), ty = Math.floor(ui.mouseWorld.y / T - s / 2 + 0.5);
      const ok = g.canPlace(ui.placing, tx, ty, 0);
      ctx.globalAlpha = 0.55;
      this.drawBuilding(ctx, { type: ui.placing, def, owner: 0, tx, ty, size: s, x: (tx + s / 2) * T, y: (ty + s / 2) * T, built: true, progress: 1, hp: 1, maxHp: 1, queue: [] });
      ctx.globalAlpha = 1;
      ctx.fillStyle = ok ? 'rgba(74,222,128,0.25)' : 'rgba(248,113,113,0.35)';
      ctx.fillRect(tx * T, ty * T, s * T, s * T);
      ctx.strokeStyle = ok ? '#4ade80' : '#f87171'; ctx.lineWidth = 2; ctx.strokeRect(tx * T, ty * T, s * T, s * T);
      if (def.range) { ctx.strokeStyle = 'rgba(255,255,255,0.25)'; ctx.beginPath(); ctx.arc((tx + s / 2) * T, (ty + s / 2) * T, def.range * T + s * T / 2, 0, Math.PI * 2); ctx.stroke(); }
    }
    // screen space: selection box
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    if (ui.drag && ui.drag.active) {
      const d = ui.drag;
      ctx.strokeStyle = '#a7f3d0'; ctx.lineWidth = 1; ctx.fillStyle = 'rgba(167,243,208,0.08)';
      const x = Math.min(d.sx, d.mx), y = Math.min(d.sy, d.my), w = Math.abs(d.mx - d.sx), h = Math.abs(d.my - d.sy);
      ctx.fillRect(x, y, w, h); ctx.strokeRect(x + 0.5, y + 0.5, w, h);
    }
    this.drawMinimap(ui);
  }

  drawFog(ctx) {
    const g = this.g;
    if (g.revealAll) return;
    if (this.fogVersion !== g.visVersion) {
      this.fogVersion = g.visVersion;
      const d = this.fogImg.data;
      for (let i = 0; i < MAP_W * MAP_H; i++) {
        d[i * 4] = 8; d[i * 4 + 1] = 10; d[i * 4 + 2] = 14;
        d[i * 4 + 3] = g.vis[i] ? 0 : g.explored[i] ? 130 : 255;
      }
      this.fctx.putImageData(this.fogImg, 0, 0);
    }
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.fog, 0, 0, MAP_W * T, MAP_H * T);
  }

  // ------------------------------------------------------------------ pieces
  drawSelRing(ctx, o) {
    const g = this.g;
    const col = o.kind === 'res' ? '#fbbf24' : o.owner === 0 ? '#4ade80' : '#f87171';
    ctx.strokeStyle = col; ctx.lineWidth = 2;
    if (o.kind === 'unit') { ctx.beginPath(); ctx.ellipse(o.x, o.y + o.def.r * 0.5, o.def.r + 4, (o.def.r + 4) * 0.55, 0, 0, Math.PI * 2); ctx.stroke(); }
    else { ctx.strokeRect(o.tx * T + 1, o.ty * T + 1, o.size * T - 2, o.size * T - 2); }
    void g;
  }
  drawBar(ctx, o, f, col) {
    const w = o.kind === 'unit' ? 22 : Math.min(o.size * T - 8, 70);
    const x = o.x - w / 2, y = o.kind === 'unit' ? o.y - o.def.r - 12 : o.ty * T - 8;
    ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(x - 1, y - 1, w + 2, 5);
    ctx.fillStyle = col; ctx.fillRect(x, y, w * clamp(f, 0, 1), 3);
  }
  drawHp(ctx, o) {
    const f = o.hp / o.maxHp;
    const col = o.owner === 0 ? (f > 0.5 ? '#4ade80' : f > 0.25 ? '#facc15' : '#f87171') : '#ef4444';
    this.drawBar(ctx, o, f, col);
    if (o.kind === 'building' && !o.built) {
      const w = Math.min(o.size * T - 8, 70), x = o.x - w / 2, y = o.ty * T - 3;
      ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(x - 1, y - 1, w + 2, 4);
      ctx.fillStyle = '#60a5fa'; ctx.fillRect(x, y, w * o.progress, 2);
    }
  }
  drawFlag(ctx, x, y, col) {
    ctx.strokeStyle = '#2b2b2b'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y - 22); ctx.stroke();
    ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(x, y - 22); ctx.lineTo(x + 12, y - 18); ctx.lineTo(x, y - 14); ctx.fill();
  }

  drawResource(ctx, r) {
    const h = hash2(r.tx, r.ty), h2 = hash2(r.ty + 5, r.tx + 9);
    const x = r.x + (h - 0.5) * 8, y = r.y + (h2 - 0.5) * 8;
    if (r.type === 'tree') {
      ctx.fillStyle = 'rgba(0,0,0,0.22)'; ctx.beginPath(); ctx.ellipse(x + 3, y + 10, 11, 5, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#5b3a1e'; ctx.fillRect(x - 2, y, 4, 11);
      if (h > 0.55) { // pine
        const g1 = `hsl(${130 + h2 * 20},40%,${22 + h * 8}%)`;
        ctx.fillStyle = g1;
        for (let k = 0; k < 3; k++) { const w = 13 - k * 3.5, yy = y + 4 - k * 7; ctx.beginPath(); ctx.moveTo(x - w, yy); ctx.lineTo(x + w, yy); ctx.lineTo(x, yy - 12); ctx.fill(); }
      } else {
        ctx.fillStyle = `hsl(${95 + h2 * 25},45%,${24 + h * 6}%)`;
        ctx.beginPath(); ctx.arc(x - 5, y - 4, 8, 0, 7); ctx.arc(x + 5, y - 5, 8, 0, 7); ctx.arc(x, y - 11, 8, 0, 7); ctx.fill();
        ctx.fillStyle = `hsla(${90 + h2 * 25},50%,45%,0.5)`;
        ctx.beginPath(); ctx.arc(x - 2, y - 12, 4, 0, 7); ctx.fill();
      }
    } else if (r.type === 'berries') {
      ctx.fillStyle = 'rgba(0,0,0,0.2)'; ctx.beginPath(); ctx.ellipse(x + 2, y + 6, 11, 5, 0, 0, 7); ctx.fill();
      ctx.fillStyle = '#2f6b2a'; ctx.beginPath(); ctx.arc(x - 4, y, 7, 0, 7); ctx.arc(x + 4, y - 1, 7, 0, 7); ctx.arc(x, y - 5, 7, 0, 7); ctx.fill();
      const n = Math.ceil(6 * r.amount / r.max);
      ctx.fillStyle = '#d63a4a';
      for (let k = 0; k < n; k++) { const a = k * 1.9 + h * 6; ctx.beginPath(); ctx.arc(x + Math.cos(a) * 6, y - 2 + Math.sin(a) * 5, 2, 0, 7); ctx.fill(); }
    } else {
      const gold = r.type === 'gold';
      const s = 0.6 + 0.4 * r.amount / r.max;
      ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.beginPath(); ctx.ellipse(x + 2, y + 7, 13 * s, 5 * s, 0, 0, 7); ctx.fill();
      const rocks = [[-5, 2, 8], [5, 3, 7], [0, -4, 8]];
      for (const [ox, oy, rr] of rocks) {
        ctx.fillStyle = gold ? '#8a7a55' : '#7d7d7d';
        ctx.beginPath(); ctx.moveTo(x + ox - rr * s, y + oy + 4); ctx.lineTo(x + ox - rr * 0.6 * s, y + oy - rr * s); ctx.lineTo(x + ox + rr * 0.7 * s, y + oy - rr * 0.8 * s); ctx.lineTo(x + ox + rr * s, y + oy + 4); ctx.closePath(); ctx.fill();
        ctx.fillStyle = gold ? '#f5cf3a' : '#c4c4c4';
        ctx.beginPath(); ctx.moveTo(x + ox - rr * 0.6 * s, y + oy - rr * s); ctx.lineTo(x + ox + rr * 0.7 * s, y + oy - rr * 0.8 * s); ctx.lineTo(x + ox + 1, y + oy - 1); ctx.closePath(); ctx.fill();
      }
      if (gold) { ctx.fillStyle = '#fff6b0'; ctx.fillRect(x - 3, y - 6, 2, 2); ctx.fillRect(x + 4, y, 2, 2); }
    }
  }

  drawFarm(ctx, b, selected) {
    const x = b.tx * T, y = b.ty * T, s = b.size * T;
    ctx.globalAlpha = b.built ? 1 : 0.6;
    ctx.fillStyle = '#7a5a32'; ctx.fillRect(x + 2, y + 2, s - 4, s - 4);
    const ripe = b.built;
    for (let k = 0; k < 6; k++) {
      ctx.fillStyle = k % 2 ? '#6a4d2a' : '#87643a';
      ctx.fillRect(x + 4, y + 5 + k * 9.5, s - 8, 4);
      if (ripe) { ctx.fillStyle = k % 2 ? '#c9b24a' : '#9bbf4a'; for (let j = 0; j < 7; j++) ctx.fillRect(x + 6 + j * 8, y + 4 + k * 9.5, 3, 4); }
    }
    ctx.strokeStyle = '#4a3519'; ctx.lineWidth = 2; ctx.strokeRect(x + 2, y + 2, s - 4, s - 4);
    ctx.fillStyle = this.g.players[b.owner].color; ctx.fillRect(x + 2, y + 2, 6, 6);
    ctx.globalAlpha = 1;
    if (selected) { ctx.strokeStyle = b.owner === 0 ? '#4ade80' : '#f87171'; ctx.strokeRect(x + 1, y + 1, s - 2, s - 2); }
  }

  // Pseudo-3D hall: roof on top, front wall below.
  hall(ctx, x, y, w, h, st, roofCol) {
    const wallTop = y + h * 0.45;
    ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(x + 4, y + 6, w, h);
    ctx.fillStyle = st.wall; ctx.fillRect(x, wallTop, w, h - h * 0.45);
    ctx.fillStyle = 'rgba(0,0,0,0.15)'; ctx.fillRect(x, y + h - 4, w, 4);
    ctx.fillStyle = roofCol || st.roof;
    ctx.beginPath(); ctx.moveTo(x - 3, wallTop + 4); ctx.lineTo(x + w * 0.15, y); ctx.lineTo(x + w * 0.85, y); ctx.lineTo(x + w + 3, wallTop + 4); ctx.closePath(); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.beginPath(); ctx.moveTo(x + w * 0.15, y); ctx.lineTo(x + w * 0.85, y); ctx.lineTo(x + w * 0.8, y + 5); ctx.lineTo(x + w * 0.2, y + 5); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = st.trim; ctx.lineWidth = 1.5;
    ctx.strokeRect(x, wallTop, w, h - h * 0.45);
    return wallTop;
  }
  door(ctx, cx, bottom, w, h, col = '#3a2614') { ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(cx - w / 2, bottom); ctx.lineTo(cx - w / 2, bottom - h + w / 2); ctx.arc(cx, bottom - h + w / 2, w / 2, Math.PI, 0); ctx.lineTo(cx + w / 2, bottom); ctx.fill(); }
  windows(ctx, x, y, w, n, col = '#2d3748') { ctx.fillStyle = col; for (let i = 0; i < n; i++) ctx.fillRect(x + (i + 0.5) * w / n - 3, y, 6, 6); }

  drawBuilding(ctx, b) {
    const g = this.g, p = g.players[b.owner], st = EPOCH_STYLE[p.epoch], col = p.color;
    if (b.def.farm) return this.drawFarm(ctx, b, false);
    const s = b.size * T, x0 = b.tx * T, y0 = b.ty * T;
    const x = x0 + 3, y = y0 + 2, w = s - 6, h = s - 6;
    const prevAlpha = ctx.globalAlpha;
    if (!b.built) ctx.globalAlpha = prevAlpha * (0.45 + 0.4 * b.progress);
    switch (b.type) {
      case 'town_center': {
        const wt = this.hall(ctx, x, y + 10, w, h - 10, st);
        this.door(ctx, b.x, y + h, 12, 16);
        this.windows(ctx, x + 4, wt + 6, w * 0.35, 2); this.windows(ctx, x + w * 0.65 - 4, wt + 6, w * 0.35, 2);
        // central keep
        ctx.fillStyle = st.wall; ctx.fillRect(b.x - 11, y - 2, 22, 30);
        ctx.fillStyle = st.trim; for (let i = 0; i < 4; i++) ctx.fillRect(b.x - 11 + i * 6, y - 6, 4, 5);
        ctx.fillStyle = st.roof; ctx.fillRect(b.x - 11, y - 2, 22, 5);
        this.drawFlag(ctx, b.x + 6, y - 4, col);
        break;
      }
      case 'house': {
        const wt = this.hall(ctx, x + 4, y + 8, w - 8, h - 8, st);
        this.door(ctx, b.x, y + h, 8, 12);
        this.windows(ctx, x + 8, wt + 5, w - 16, 2);
        ctx.fillStyle = col; ctx.fillRect(b.x - 6, y + 9, 12, 3);
        break;
      }
      case 'storehouse': {
        this.hall(ctx, x + 2, y + 6, w - 4, h - 8, st);
        this.door(ctx, b.x, y + h - 2, 14, 14, '#4a3520');
        ctx.fillStyle = '#a9773f'; ctx.fillRect(x + 1, y + h - 12, 10, 10); ctx.fillRect(x + w - 11, y + h - 12, 10, 10);
        ctx.strokeStyle = '#5a3b1a'; ctx.strokeRect(x + 1, y + h - 12, 10, 10); ctx.strokeRect(x + w - 11, y + h - 12, 10, 10);
        ctx.fillStyle = col; ctx.fillRect(b.x - 8, y + 7, 16, 3);
        break;
      }
      case 'barracks': case 'archery_range': case 'stable': case 'workshop': {
        const wt = this.hall(ctx, x, y + 8, w, h - 22, st);
        this.door(ctx, b.x, y + h - 14, 14, 18);
        this.windows(ctx, x + 6, wt + 6, w * 0.3, 2); this.windows(ctx, x + w * 0.7 - 6, wt + 6, w * 0.3, 2);
        // yard
        ctx.fillStyle = 'rgba(120,95,60,0.6)'; ctx.fillRect(x, y + h - 14, w, 14);
        ctx.strokeStyle = st.trim; ctx.lineWidth = 1; ctx.strokeRect(x, y + h - 14, w, 14);
        const cx = b.x, cy = y + 18;
        ctx.lineWidth = 2.5;
        if (b.type === 'barracks') {
          ctx.strokeStyle = '#e5e7eb';
          ctx.beginPath(); ctx.moveTo(cx - 8, cy - 6); ctx.lineTo(cx + 8, cy + 6); ctx.moveTo(cx + 8, cy - 6); ctx.lineTo(cx - 8, cy + 6); ctx.stroke();
          ctx.fillStyle = '#8b5a2b'; for (let i = 0; i < 4; i++) { ctx.fillRect(x + 6 + i * 20, y + h - 12, 2, 10); ctx.beginPath(); ctx.arc(x + 7 + i * 20, y + h - 13, 3, 0, 7); ctx.fill(); }
        } else if (b.type === 'archery_range') {
          for (const [r, c2] of [[8, '#f8fafc'], [5.5, '#dc2626'], [3, '#f8fafc'], [1.3, '#dc2626']]) { ctx.fillStyle = c2; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.fill(); }
          for (const ox of [x + 12, x + w - 12]) { ctx.fillStyle = '#d6c08a'; ctx.beginPath(); ctx.arc(ox, y + h - 7, 5, 0, 7); ctx.fill(); ctx.fillStyle = '#dc2626'; ctx.beginPath(); ctx.arc(ox, y + h - 7, 2, 0, 7); ctx.fill(); }
        } else if (b.type === 'stable') {
          ctx.strokeStyle = '#d1d5db'; ctx.beginPath(); ctx.arc(cx, cy + 2, 7, Math.PI * 0.15, Math.PI * 0.85, true); ctx.stroke();
          ctx.fillStyle = '#d4b45a'; ctx.fillRect(x + 4, y + h - 12, 14, 9); ctx.fillRect(x + w - 18, y + h - 12, 14, 9);
        } else {
          ctx.fillStyle = '#d1d5db'; ctx.beginPath();
          for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; ctx.rect(cx + Math.cos(a) * 7 - 2, cy + Math.sin(a) * 7 - 2, 4, 4); }
          ctx.fill(); ctx.beginPath(); ctx.arc(cx, cy, 6, 0, 7); ctx.fill(); ctx.fillStyle = st.roof; ctx.beginPath(); ctx.arc(cx, cy, 2.5, 0, 7); ctx.fill();
          ctx.fillStyle = '#555'; ctx.fillRect(x + w - 14, y - 2, 7, 16);
        }
        ctx.fillStyle = col; ctx.fillRect(x + 4, y + 10, 8, 5); ctx.fillRect(x + w - 12, y + 10, 8, 5);
        break;
      }
      case 'tower': {
        ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(x + 10, y + 8, w - 12, h);
        ctx.fillStyle = st.wall; ctx.fillRect(x + 8, y + 2, w - 16, h - 2);
        ctx.fillStyle = 'rgba(0,0,0,0.15)'; ctx.fillRect(x + w / 2, y + 2, w / 2 - 8, h - 2);
        ctx.fillStyle = st.trim; ctx.fillRect(x + 4, y - 2, w - 8, 10);
        ctx.fillStyle = st.wall; for (let i = 0; i < 4; i++) ctx.fillRect(x + 4 + i * (w - 12) / 3, y - 8, 6, 7);
        ctx.fillStyle = '#1f2937'; ctx.fillRect(b.x - 2, y + 16, 4, 9); ctx.fillRect(b.x - 2, y + 32, 4, 9);
        this.drawFlag(ctx, b.x, y - 6, col);
        break;
      }
      case 'wonder': {
        const lv = 4;
        for (let i = 0; i < lv; i++) {
          const inset = i * 12, yy = y + h - (i + 1) * (h - 16) / lv;
          ctx.fillStyle = i % 2 ? st.wall : st.trim;
          ctx.fillRect(x + inset, yy, w - inset * 2, (h - 16) / lv + 2);
          ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.fillRect(x + inset, yy, w - inset * 2, 3);
        }
        ctx.fillStyle = '#f5cf3a'; ctx.beginPath(); ctx.moveTo(b.x - 10, y + 18); ctx.lineTo(b.x, y - 4); ctx.lineTo(b.x + 10, y + 18); ctx.fill();
        ctx.fillStyle = col; ctx.fillRect(x + 2, y + h - 30, 6, 24); ctx.fillRect(x + w - 8, y + h - 30, 6, 24);
        this.door(ctx, b.x, y + h, 12, 18, '#1f1a12');
        break;
      }
    }
    if (!b.built) {
      ctx.globalAlpha = prevAlpha;
      ctx.strokeStyle = '#8b6b3e'; ctx.lineWidth = 2;
      for (let k = 0; k <= b.size; k++) { ctx.beginPath(); ctx.moveTo(x0 + k * T * 0.95 + 2, y0 + 2); ctx.lineTo(x0 + k * T * 0.95 + 2, y0 + s - 2); ctx.stroke(); }
      ctx.beginPath(); ctx.moveTo(x0 + 2, y0 + s * 0.35); ctx.lineTo(x0 + s - 2, y0 + s * 0.35); ctx.moveTo(x0 + 2, y0 + s * 0.75); ctx.lineTo(x0 + s - 2, y0 + s * 0.75); ctx.stroke();
    }
    if (b.hitT > 0) { ctx.fillStyle = 'rgba(255,80,60,0.25)'; ctx.fillRect(x0, y0, s, s); }
    // smoke from damaged buildings
    if (b.built && b.hp < b.maxHp * 0.5) {
      const t = performance.now() / 1000;
      for (let k = 0; k < 3; k++) {
        const ph = (t * 0.6 + k / 3 + b.id * 0.13) % 1;
        ctx.fillStyle = `rgba(60,60,60,${0.45 * (1 - ph)})`;
        ctx.beginPath(); ctx.arc(b.x - 6 + k * 6 + ph * 8, y0 + s * 0.4 - ph * 30, 4 + ph * 8, 0, 7); ctx.fill();
      }
      if (b.hp < b.maxHp * 0.25) { ctx.fillStyle = `rgba(255,${120 + Math.random() * 80 | 0},40,0.8)`; ctx.beginPath(); ctx.arc(b.x + 5, y0 + s * 0.45, 4 + Math.random() * 3, 0, 7); ctx.fill(); }
    }
    ctx.globalAlpha = prevAlpha;
  }

  drawUnit(ctx, u) {
    const p = this.g.players[u.owner], col = p.color, def = u.def;
    const bob = u.moving ? Math.sin(performance.now() / 90 + u.id) * 1.2 : 0;
    const lunge = u.swing > 0 && def.range < 1.5 ? Math.sin((u.swing / 0.25) * Math.PI) * 4 : 0;
    const fx = Math.cos(u.facing), fy = Math.sin(u.facing);
    const x = u.x + fx * lunge, y = u.y + fy * lunge + bob;
    ctx.fillStyle = 'rgba(0,0,0,0.28)';
    ctx.beginPath(); ctx.ellipse(u.x, u.y + def.r * 0.6, def.r * 0.95, def.r * 0.45, 0, 0, 7); ctx.fill();
    if (def.shape === 'tank') this.drawTank(ctx, u, x, y, col);
    else if (def.cls === 'siege') this.drawSiege(ctx, u, x, y, col);
    else if (def.cls === 'cavalry') this.drawRider(ctx, u, x, y, col);
    else this.drawPerson(ctx, u, x, y, col);
    if (u.hitT > 0) { ctx.fillStyle = 'rgba(255,60,60,0.45)'; ctx.beginPath(); ctx.arc(u.x, u.y - 2, def.r, 0, 7); ctx.fill(); }
  }
  weapon(ctx, u, x, y, fx, fy) {
    const wpn = u.def.weapon;
    ctx.lineCap = 'round';
    const ang = u.swing > 0 && u.def.range < 1.5 ? (u.swing / 0.25 - 0.5) * 1.4 : 0;
    const c = Math.cos(u.facing + ang), s = Math.sin(u.facing + ang);
    const hx = x + fy * -4 * 0 + fx * 3, hy = y + fx * 0 + fy * 3;
    switch (wpn) {
      case 'club': ctx.strokeStyle = '#6b4423'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(hx + c * 10, hy + s * 10); ctx.stroke(); break;
      case 'spear': ctx.strokeStyle = '#8b6b3e'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(hx - c * 6, hy - s * 6); ctx.lineTo(hx + c * 14, hy + s * 14); ctx.stroke();
        ctx.fillStyle = '#cbd5e1'; ctx.beginPath(); ctx.arc(hx + c * 14, hy + s * 14, 2, 0, 7); ctx.fill(); break;
      case 'sword': ctx.strokeStyle = '#e5e7eb'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(hx + c * 12, hy + s * 12); ctx.stroke(); break;
      case 'gun': case 'mg': ctx.strokeStyle = '#1f2937'; ctx.lineWidth = wpn === 'mg' ? 3.5 : 2.2; ctx.beginPath(); ctx.moveTo(hx - c * 3, hy - s * 3); ctx.lineTo(hx + c * 12, hy + s * 12); ctx.stroke();
        if (u.swing > 0.15) { ctx.fillStyle = '#fde68a'; ctx.beginPath(); ctx.arc(hx + c * 14, hy + s * 14, 2.5, 0, 7); ctx.fill(); } break;
      case 'bow': ctx.strokeStyle = '#7c4a1e'; ctx.lineWidth = 1.8; ctx.beginPath(); ctx.arc(hx + c * 4, hy + s * 4, 7, u.facing - 1.2, u.facing + 1.2); ctx.stroke(); break;
      case 'sling': ctx.strokeStyle = '#a16207'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(hx + c * 8, hy + s * 8 - 3); ctx.stroke(); ctx.fillStyle = '#777'; ctx.beginPath(); ctx.arc(hx + c * 8, hy + s * 8 - 3, 1.8, 0, 7); ctx.fill(); break;
      case 'grenade': ctx.fillStyle = '#365314'; ctx.beginPath(); ctx.arc(hx + c * 7, hy + s * 7, 2.5, 0, 7); ctx.fill(); break;
      case 'tool': {
        const work = u.working ? Math.sin(performance.now() / 120 + u.id) * 0.8 : 0;
        const c2 = Math.cos(u.facing + work), s2 = Math.sin(u.facing + work);
        ctx.strokeStyle = '#6b4423'; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.moveTo(hx, hy); ctx.lineTo(hx + c2 * 9, hy + s2 * 9); ctx.stroke();
        ctx.strokeStyle = '#9ca3af'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(hx + c2 * 9 - s2 * 3, hy + s2 * 9 + c2 * 3); ctx.lineTo(hx + c2 * 9 + s2 * 3, hy + s2 * 9 - c2 * 3); ctx.stroke();
        break;
      }
    }
  }
  drawPerson(ctx, u, x, y, col) {
    const r = u.def.r, fx = Math.cos(u.facing), fy = Math.sin(u.facing);
    const ep = this.g.players[u.owner].epoch;
    // body
    ctx.fillStyle = col;
    ctx.beginPath(); ctx.ellipse(x, y, r * 0.75, r * 0.9, 0, 0, 7); ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.5)'; ctx.lineWidth = 1; ctx.stroke();
    // belt/accent
    ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.fillRect(x - r * 0.7, y + 1, r * 1.4, 2);
    // head
    ctx.fillStyle = '#e0b48a'; ctx.beginPath(); ctx.arc(x, y - r * 0.85, r * 0.5, 0, 7); ctx.fill();
    // headgear by epoch for soldiers
    if (u.def.cls !== 'citizen') {
      ctx.fillStyle = ep >= 4 ? '#4b5563' : ep >= 2 ? '#9ca3af' : ep >= 1 ? '#b08d57' : '#7c5a3a';
      ctx.beginPath(); ctx.arc(x, y - r * 0.95, r * 0.52, Math.PI, 0); ctx.fill();
    } else {
      ctx.fillStyle = '#c2a36b'; ctx.beginPath(); ctx.ellipse(x, y - r * 1.05, r * 0.7, r * 0.25, 0, 0, 7); ctx.fill();
    }
    this.weapon(ctx, u, x, y - 2, fx, fy);
    if (u.carry > 0) { ctx.fillStyle = RES_COLOR[u.carryRes]; ctx.fillRect(x - fx * 6 - 3, y - fy * 6 - 3, 6, 6); ctx.strokeStyle = '#000'; ctx.lineWidth = 0.5; ctx.strokeRect(x - fx * 6 - 3, y - fy * 6 - 3, 6, 6); }
  }
  drawRider(ctx, u, x, y, col) {
    const fx = Math.cos(u.facing), fy = Math.sin(u.facing);
    const side = fx >= 0 ? 1 : -1;
    // horse body (side-ish view, mirrored by direction)
    const gait = u.moving ? Math.sin(performance.now() / 70 + u.id) * 2 : 0;
    ctx.fillStyle = '#6b4226';
    ctx.strokeStyle = '#3d2614'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(x - 7, y + 3); ctx.lineTo(x - 8 - gait, y + 10); ctx.moveTo(x - 3, y + 3); ctx.lineTo(x - 3 + gait, y + 10);
    ctx.moveTo(x + 4, y + 3); ctx.lineTo(x + 4 - gait, y + 10); ctx.moveTo(x + 8, y + 3); ctx.lineTo(x + 8 + gait, y + 10); ctx.stroke();
    ctx.beginPath(); ctx.ellipse(x, y + 1, 11, 6, 0, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.ellipse(x + side * 11, y - 5, 4, 6, side * 0.6, 0, 7); ctx.fill();
    ctx.fillStyle = '#2b1a0e'; ctx.fillRect(x - side * 12 - 1, y - 1, 3, 7);
    // rider
    ctx.fillStyle = col; ctx.beginPath(); ctx.ellipse(x - side, y - 6, 5, 6, 0, 0, 7); ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.5)'; ctx.lineWidth = 1; ctx.stroke();
    ctx.fillStyle = '#e0b48a'; ctx.beginPath(); ctx.arc(x - side, y - 13, 3.5, 0, 7); ctx.fill();
    ctx.fillStyle = '#9ca3af'; ctx.beginPath(); ctx.arc(x - side, y - 14, 3.7, Math.PI, 0); ctx.fill();
    this.weapon(ctx, u, x - side, y - 7, fx, fy);
  }
  drawSiege(ctx, u, x, y, col) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(u.facing);
    const type = u.type;
    ctx.fillStyle = '#1f2937';
    for (const [wx, wy] of [[-7, -8], [7, -8], [-7, 8], [7, 8]]) { ctx.beginPath(); ctx.arc(wx, wy, 3.5, 0, 7); ctx.fill(); }
    if (type === 'catapult') {
      ctx.fillStyle = '#8b5a2b'; ctx.fillRect(-11, -7, 22, 14);
      const arm = u.swing > 0 ? 1 - u.swing / 0.25 : 0;
      ctx.strokeStyle = '#5c3a1a'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(-6, 0); ctx.lineTo(-6 + Math.cos(Math.PI - arm * 2.5) * -14, Math.sin(Math.PI - arm * 2.5) * -4); ctx.stroke();
      ctx.fillStyle = '#777'; ctx.beginPath(); ctx.arc(6, 0, 3, 0, 7); ctx.fill();
    } else if (type === 'rocket_launcher') {
      ctx.fillStyle = '#4b5320'; ctx.fillRect(-13, -8, 26, 16);
      ctx.fillStyle = '#374151'; ctx.fillRect(-6, -6, 16, 12);
      ctx.fillStyle = '#9ca3af'; for (let i = 0; i < 3; i++) ctx.fillRect(-4, -5 + i * 4, 16, 2.5);
    } else {
      ctx.fillStyle = type === 'cannon' ? '#6b4423' : '#4b5320'; ctx.fillRect(-10, -7, 16, 14);
      ctx.fillStyle = type === 'cannon' ? '#2d2d2d' : '#3f4a1f';
      ctx.fillRect(-2, -3, type === 'artillery' ? 22 : 17, 6);
      if (u.swing > 0.12) { ctx.fillStyle = '#fde68a'; ctx.beginPath(); ctx.arc(type === 'artillery' ? 22 : 17, 0, 4, 0, 7); ctx.fill(); }
    }
    ctx.fillStyle = col; ctx.fillRect(-12, -2, 4, 4);
    ctx.restore();
  }
  drawTank(ctx, u, x, y, col) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(u.facing);
    ctx.fillStyle = '#1f2937'; ctx.fillRect(-14, -11, 28, 5); ctx.fillRect(-14, 6, 28, 5);
    ctx.fillStyle = '#4b5320'; ctx.fillRect(-12, -8, 24, 16);
    ctx.fillStyle = col; ctx.fillRect(-12, -8, 5, 16);
    ctx.fillStyle = '#3f4a1f'; ctx.beginPath(); ctx.arc(0, 0, 6.5, 0, 7); ctx.fill();
    ctx.fillRect(2, -2, 16, 4);
    if (u.swing > 0.12) { ctx.fillStyle = '#fde68a'; ctx.beginPath(); ctx.arc(19, 0, 4.5, 0, 7); ctx.fill(); }
    ctx.restore();
  }
  drawProjectile(ctx, p) {
    const ang = Math.atan2(p.ty - p.sy, p.tx - p.sx);
    const k = Math.min(1, p.t / p.dur);
    const arc = (p.kind === 'arrow' || p.kind === 'boulder' || p.kind === 'grenade' || p.kind === 'stone') ? Math.sin(k * Math.PI) * Math.min(40, Math.hypot(p.tx - p.sx, p.ty - p.sy) * 0.2) : 0;
    const x = p.x, y = p.y - arc;
    switch (p.kind) {
      case 'arrow':
        ctx.strokeStyle = '#3b2a1a'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x - Math.cos(ang) * 7, y - Math.sin(ang) * 7); ctx.lineTo(x, y); ctx.stroke(); break;
      case 'bullet':
        ctx.strokeStyle = 'rgba(255,240,180,0.9)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x - Math.cos(ang) * 8, y - Math.sin(ang) * 8); ctx.lineTo(x, y); ctx.stroke(); break;
      case 'rocket':
        ctx.fillStyle = 'rgba(200,200,200,0.4)'; ctx.beginPath(); ctx.arc(x - Math.cos(ang) * 8, y - Math.sin(ang) * 8, 4, 0, 7); ctx.fill();
        ctx.fillStyle = '#f97316'; ctx.beginPath(); ctx.arc(x, y, 3, 0, 7); ctx.fill(); break;
      default:
        ctx.fillStyle = p.kind === 'grenade' ? '#365314' : p.kind === 'stone' ? '#888' : '#333';
        ctx.beginPath(); ctx.arc(x, y, p.kind === 'boulder' ? 5 : p.kind === 'stone' ? 2 : 3.5, 0, 7); ctx.fill();
    }
  }
  drawBoom(ctx, ef) {
    const k = ef.t / ef.dur;
    ctx.fillStyle = `rgba(255,${180 - k * 120 | 0},60,${0.8 * (1 - k)})`;
    ctx.beginPath(); ctx.arc(ef.x, ef.y, ef.r * (0.4 + k * 0.8), 0, 7); ctx.fill();
    ctx.fillStyle = `rgba(80,80,80,${0.5 * (1 - k)})`;
    ctx.beginPath(); ctx.arc(ef.x + 4, ef.y - 6 - k * 10, ef.r * 0.5 * (0.5 + k), 0, 7); ctx.fill();
  }
  drawCorpse(ctx, ef) {
    const a = 1 - ef.t / ef.dur;
    ctx.globalAlpha = a * 0.7;
    ctx.fillStyle = '#5b1d1d'; ctx.beginPath(); ctx.ellipse(ef.x, ef.y + 3, ef.r, ef.r * 0.5, 0, 0, 7); ctx.fill();
    ctx.fillStyle = ef.color; ctx.beginPath(); ctx.ellipse(ef.x - 1, ef.y + 1, ef.r * 0.6, ef.r * 0.35, 0.4, 0, 7); ctx.fill();
    ctx.globalAlpha = 1;
  }
  drawRubble(ctx, ef) {
    const a = Math.min(1, (ef.dur - ef.t) / 4);
    ctx.globalAlpha = a * 0.8;
    const s = ef.size * T;
    ctx.fillStyle = '#4a4036'; ctx.fillRect(ef.x - s / 2 + 4, ef.y - s / 2 + 4, s - 8, s - 8);
    ctx.fillStyle = '#6b5f52';
    for (let k = 0; k < ef.size * 5; k++) { const h1 = hash2(ef.x + k, ef.y), h2 = hash2(ef.y + k, ef.x); ctx.fillRect(ef.x - s / 2 + 4 + h1 * (s - 14), ef.y - s / 2 + 4 + h2 * (s - 14), 6, 4); }
    ctx.globalAlpha = 1;
  }

  // ------------------------------------------------------------------ minimap
  drawMinimap(ui) {
    const g = this.g, now = performance.now();
    if (now - this.mmT > 250) {
      this.mmT = now;
      const d = this.mmImg.data, m = g.map;
      for (let i = 0; i < MAP_W * MAP_H; i++) {
        let r, gg, b;
        if (!g.explored[i] && !g.revealAll) { r = gg = b = 12; }
        else {
          const t = m.terrain[i];
          if (m.block[i] === B_RES) { r = 36; gg = 80; b = 30; }
          else if (t === TER_WATER) { r = 40; gg = 95; b = 150; }
          else if (t === TER_SAND) { r = 200; gg = 185; b = 130; }
          else { r = 80; gg = 130; b = 60; }
          if (!g.vis[i]) { r *= 0.6; gg *= 0.6; b *= 0.6; }
        }
        d[i * 4] = r; d[i * 4 + 1] = gg; d[i * 4 + 2] = b; d[i * 4 + 3] = 255;
      }
      const put = (tx, ty, c) => { if (tx < 0 || ty < 0 || tx >= MAP_W || ty >= MAP_H) return; const i = (ty * MAP_W + tx) * 4; d[i] = c[0]; d[i + 1] = c[1]; d[i + 2] = c[2]; };
      for (const r of g.resources) {
        if (r.type === 'tree' || (!g.explored[r.ty * MAP_W + r.tx] && !g.revealAll)) continue;
        put(r.tx, r.ty, r.type === 'gold' ? [242, 194, 48] : r.type === 'stone' ? [170, 170, 170] : [214, 58, 74]);
      }
      const pc = g.players.map(p => [parseInt(p.color.slice(1, 3), 16), parseInt(p.color.slice(3, 5), 16), parseInt(p.color.slice(5, 7), 16)]);
      for (const b of g.buildings) {
        if (b.owner !== 0 && !g.isExplored(b)) continue;
        for (let y = b.ty; y < b.ty + b.size; y++) for (let x = b.tx; x < b.tx + b.size; x++) put(x, y, pc[b.owner]);
      }
      for (const u of g.units) {
        if (u.owner !== 0 && !g.isVisible(u)) continue;
        const tx = Math.floor(u.x / T), ty = Math.floor(u.y / T);
        put(tx, ty, pc[u.owner]); put(tx + 1, ty, pc[u.owner]);
      }
      this.mmCanvas.getContext('2d').putImageData(this.mmImg, 0, 0);
    }
    const mc = this.mctx, W = this.mm.width, H = this.mm.height;
    mc.imageSmoothingEnabled = false;
    mc.drawImage(this.mmCanvas, 0, 0, W, H);
    const sx = W / (MAP_W * T), sy = H / (MAP_H * T);
    mc.strokeStyle = '#fff'; mc.lineWidth = 1;
    mc.strokeRect(this.cam.x * sx + 0.5, this.cam.y * sy + 0.5, this.viewW() * sx, this.viewH() * sy);
    for (const p of g.pings) {
      const k = (g.time - p.t) / 4;
      if (k > 1) continue;
      mc.strokeStyle = `rgba(255,60,60,${1 - k})`; mc.lineWidth = 2;
      mc.beginPath(); mc.arc(p.x * sx, p.y * sy, 4 + (k * 30) % 10, 0, 7); mc.stroke();
    }
    void ui;
  }
}
