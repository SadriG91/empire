'use strict';
// Input handling and HTML interface (top bar, selection panel, command card, overlays).

const $ = id => document.getElementById(id);

class UI {
  constructor() {
    this.g = null; this.r = null;
    this.sel = []; this.selSet = new Set();
    this.placing = null; this.mode = null;
    this.drag = null; this.mouse = { x: 0, y: 0, in: false }; this.mouseWorld = null;
    this.keys = new Set(); this.groups = {};
    this.markers = []; this.paused = false; this.speed = 1;
    this.cmdSig = ''; this.cmds = []; this.infoSig = ''; this.msgSig = '';
    this.lastClick = { t: 0, id: 0 }; this.idleIdx = 0; this.mmDrag = false;
    this.canvas = $('game'); this.minimap = $('minimap');
    this.bind();
  }
  attach(game, renderer) {
    this.g = game; this.r = renderer;
    this.sel = []; this.selSet = new Set(); this.placing = null; this.mode = null; this.groups = {};
    this.cmdSig = ''; this.infoSig = ''; this.paused = false;
  }
  get active() { return this.g && !this.g.over; }

  // ---------------------------------------------------------------- selection
  setSel(ids) {
    this.sel = ids.slice(0, 60);
    this.selSet = new Set(this.sel);
  }
  selEnts() { return this.sel.map(id => this.g.get(id)).filter(Boolean); }
  selUnits() { return this.selEnts().filter(e => e.kind === 'unit' && e.owner === 0); }
  selBuilding() { const e = this.selEnts(); return e.length === 1 && e[0].kind === 'building' && e[0].owner === 0 ? e[0] : null; }

  pickAt(wx, wy) {
    const g = this.g;
    let best = null, bd = 1e9;
    for (const u of g.units) {
      if (u.owner !== 0 && !g.isVisible(u)) continue;
      const d = Math.hypot(u.x - wx, u.y - 3 - wy);
      if (d < u.def.r + 6 && d < bd) { bd = d; best = u; }
    }
    if (best) return best;
    for (const b of g.buildings) {
      if (b.owner !== 0 && !g.isExplored(b)) continue;
      if (wx >= b.tx * T && wx < (b.tx + b.size) * T && wy >= b.ty * T - 8 && wy < (b.ty + b.size) * T) return b;
    }
    const tx = Math.floor(wx / T), ty = Math.floor(wy / T);
    if (!g.explored[ty * MAP_W + tx] && !g.revealAll) return null;
    for (const r of g.resources) if (!r.dead && r.tx === tx && r.ty === ty) return r;
    return null;
  }
  clickSelect(mx, my, shift) {
    const w = this.r.toWorld(mx, my);
    const t = this.pickAt(w.x, w.y);
    const now = performance.now();
    if (!t) { if (!shift) this.setSel([]); return; }
    if (t.kind === 'unit' && t.owner === 0 && now - this.lastClick.t < 350 && this.lastClick.id === t.id) {
      // double click: all of this type on screen
      const vw = this.r.viewW(), vh = this.r.viewH(), c = this.r.cam;
      this.setSel(this.g.units.filter(u => u.owner === 0 && u.type === t.type && u.x > c.x && u.x < c.x + vw && u.y > c.y && u.y < c.y + vh).map(u => u.id));
    } else if (shift && t.kind === 'unit' && t.owner === 0 && this.selUnits().length) {
      if (this.selSet.has(t.id)) this.setSel(this.sel.filter(id => id !== t.id)); else this.setSel([...this.sel, t.id]);
    } else this.setSel([t.id]);
    this.lastClick = { t: now, id: t.id };
  }
  boxSelect(d, shift) {
    const a = this.r.toWorld(Math.min(d.sx, d.mx), Math.min(d.sy, d.my));
    const b = this.r.toWorld(Math.max(d.sx, d.mx), Math.max(d.sy, d.my));
    const ids = this.g.units.filter(u => u.owner === 0 && u.x >= a.x - 4 && u.x <= b.x + 4 && u.y >= a.y - 4 && u.y <= b.y + 4).map(u => u.id);
    if (!ids.length) return;
    // prefer soldiers when the box mixes soldiers and citizens? keep everything, like the classics.
    this.setSel(shift ? [...new Set([...this.sel, ...ids])] : ids);
  }

  // ---------------------------------------------------------------- commands
  marker(x, y, color) { this.markers.push({ x, y, color, t: performance.now() }); if (this.markers.length > 12) this.markers.shift(); }
  flash(text, color = '#fca5a5') { this.g.messages.push({ text, color, t: this.g.time }); if (this.g.messages.length > 6) this.g.messages.shift(); }

  rightClick(wx, wy) {
    const g = this.g;
    if (this.placing || this.mode) { this.placing = null; this.mode = null; return; }
    const own = this.selUnits();
    const t = this.pickAt(wx, wy);
    if (!own.length) {
      const b = this.selBuilding();
      if (b && b.built && PRODUCTION[b.type]) { g.setRally(b, wx, wy, t); this.marker(wx, wy, '#93c5fd'); }
      return;
    }
    if (t && t.kind !== 'res' && t.owner !== 0) { g.cmdAttack(own, t); this.marker(t.x, t.y, '#f87171'); return; }
    if (t && t.kind === 'res') { g.cmdGather(own, t); this.marker(t.x, t.y, '#fbbf24'); return; }
    if (t && t.kind === 'building' && t.owner === 0) {
      const cits = own.filter(u => u.def.cls === 'citizen'), rest = own.filter(u => u.def.cls !== 'citizen');
      if (cits.length) {
        if (!t.built || (t.hp < t.maxHp && !t.def.farm)) g.cmdBuild(cits, t);
        else if (t.def.farm) g.cmdGather(cits, t);
        else if (t.def.dropoff && cits.some(c => c.carry > 0)) { g.cmdReturn(cits.filter(c => c.carry > 0), t); const o = cits.filter(c => c.carry <= 0); if (o.length) g.cmdMove(o, wx, wy); }
        else g.cmdMove(cits, wx, wy);
      }
      if (rest.length) g.cmdMove(rest, wx, wy);
      this.marker(t.x, t.y, '#4ade80');
      return;
    }
    g.cmdMove(own, wx, wy);
    this.marker(wx, wy, '#4ade80');
  }
  startPlacing(type) {
    const p = this.g.players[0], def = BUILDINGS[type];
    if (def.epoch > p.epoch) return this.flash(`Requires ${EPOCHS[def.epoch].name}`);
    if (!canAfford(p.res, def.cost)) return this.flash(`Not enough ${missingRes(p.res, def.cost)}`);
    this.placing = type; this.mode = null;
  }
  tryPlace(shift) {
    const def = BUILDINGS[this.placing], s = def.size, w = this.mouseWorld;
    const tx = Math.floor(w.x / T - s / 2 + 0.5), ty = Math.floor(w.y / T - s / 2 + 0.5);
    const builders = this.selUnits().filter(u => u.def.cls === 'citizen');
    const res = this.g.placeBuilding(0, this.placing, tx, ty, builders);
    if (typeof res === 'string') { this.flash(res); return; }
    if (!shift || !canAfford(this.g.players[0].res, def.cost)) this.placing = null;
  }
  tryTrain(b, type, n = 1) {
    for (let i = 0; i < n; i++) { const r = this.g.train(b, type); if (r !== true) { this.flash(r); break; } }
  }

  commandList() {
    const g = this.g, p = g.players[0], list = [];
    const units = this.selUnits(), b = this.selBuilding();
    if (units.length) {
      if (units.some(u => u.def.cls === 'citizen')) {
        for (const t of BUILD_MENU) {
          const def = BUILDINGS[t];
          list.push({ icon: def.icon, label: def.name, key: def.key, cost: def.cost, desc: def.desc, locked: def.epoch > p.epoch ? `Requires ${EPOCHS[def.epoch].name}` : null, act: () => this.startPlacing(t) });
        }
      }
      if (units.some(u => u.def.cls !== 'citizen')) list.push({ icon: '🎯', label: 'Attack-Move', key: 'A', desc: 'Move and engage any enemies on the way.', act: () => { this.mode = 'amove'; this.placing = null; } });
      list.push({ icon: '✋', label: 'Stop', key: 'S', desc: 'Stop current action.', act: () => g.cmdStop(this.selUnits()) });
      list.push({ icon: '💀', label: 'Delete', key: 'DELETE', desc: 'Kill the selected units.', act: () => { for (const u of this.selUnits()) g.kill(u, null); } });
    } else if (b && b.built) {
      const keys = ['Q', 'W', 'E', 'R'];
      g.trainable(b).forEach((t, i) => {
        const def = UNITS[t];
        list.push({ icon: unitIcon(def), label: def.name, key: keys[i], cost: def.cost, desc: `${def.desc}<br><span class="stat">HP ${def.hp} · ATK ${def.atk} · ARM ${def.armor} · RNG ${def.range < 1.5 ? 'melee' : def.range}</span><br><i>Shift+click: queue 5</i>`, act: (e) => this.tryTrain(b, t, e && e.shiftKey ? 5 : 1) });
      });
      // show upcoming units of locked lines
      for (const row of PRODUCTION[b.type] || []) {
        if (row[Math.min(p.epoch, row.length - 1)]) continue;
        const ne = row.findIndex(Boolean), def = UNITS[row[ne]];
        list.push({ icon: unitIcon(def), label: def.name, cost: def.cost, desc: def.desc, locked: `Requires ${EPOCHS[ne].name}` });
      }
      if (b.type === 'town_center' && EPOCHS[p.epoch + 1]) {
        const ne = EPOCHS[p.epoch + 1];
        list.push({ icon: '⏫', label: `Advance to ${ne.name}`, key: 'U', cost: ne.cost, desc: `Upgrades all your soldiers and unlocks new units and buildings. Takes ${ne.time}s.`, locked: p.advancing ? 'Already advancing' : null,
          act: () => { const r = g.advance(b); if (r !== true) this.flash(r); } });
      }
      if (PRODUCTION[b.type]) list.push({ icon: '🚩', label: 'Set Rally Point', desc: 'Right-click the map to set where new units go.', act: () => this.flash('Right-click on the map to set the rally point.', '#93c5fd') });
      list.push({ icon: '💀', label: 'Delete', key: 'DELETE', desc: 'Demolish this building.', act: () => { g.kill(b, null); this.setSel([]); } });
    } else if (b && !b.built) {
      list.push({ icon: '❌', label: 'Cancel construction', key: 'DELETE', desc: 'Refunds 50% of the cost.', act: () => { refund(p.res, b.def.cost, 0.5); g.kill(b, null); p.stats.lost--; this.setSel([]); } });
    }
    return list;
  }
  renderCommands() {
    const g = this.g, p = g.players[0];
    const b = this.selBuilding();
    const sig = this.sel.join(',') + '|' + p.epoch + '|' + p.advancing + '|' + (b ? b.built : '') + '|' + this.selUnits().map(u => u.type).join();
    if (sig !== this.cmdSig) {
      this.cmdSig = sig;
      this.cmds = this.commandList();
      const el = $('commands');
      el.innerHTML = '';
      this.cmds.forEach((c, i) => {
        const btn = document.createElement('button');
        btn.className = 'cmd';
        btn.innerHTML = `<span class="ic">${c.icon}</span>${c.key ? `<span class="hk">${c.key === 'DELETE' ? 'Del' : c.key}</span>` : ''}`;
        btn.addEventListener('click', e => { if (!c.locked && c.act) c.act(e); });
        btn.addEventListener('mouseenter', () => this.showTip(btn, c));
        btn.addEventListener('mouseleave', () => this.hideTip());
        c.el = btn; btn.dataset.i = i;
        el.appendChild(btn);
      });
      this.hideTip();
    }
    for (const c of this.cmds) {
      c.el.classList.toggle('locked', !!c.locked);
      c.el.classList.toggle('poor', !c.locked && !!c.cost && !canAfford(p.res, c.cost));
    }
  }
  showTip(el, c) {
    const tip = $('tooltip');
    tip.innerHTML = `<b>${c.label}</b>${c.key ? ` <span class="hk2">[${c.key === 'DELETE' ? 'Del' : c.key}]</span>` : ''}${c.cost ? `<div class="cost">${costText(c.cost)}</div>` : ''}${c.locked ? `<div class="lock">${c.locked}</div>` : ''}${c.desc ? `<div>${c.desc}</div>` : ''}`;
    tip.style.display = 'block';
    const r = el.getBoundingClientRect();
    tip.style.left = Math.min(window.innerWidth - tip.offsetWidth - 8, r.left) + 'px';
    tip.style.top = (r.top - tip.offsetHeight - 8) + 'px';
  }
  hideTip() { $('tooltip').style.display = 'none'; }

  renderInfo() {
    const g = this.g, ents = this.selEnts(), el = $('info');
    let html = '';
    if (!ents.length) {
      const p = g.players[0];
      html = `<div class="title">${EPOCHS[p.epoch].name}</div><div class="sub">Select units or buildings. Right-click to command.</div>
        <div class="stats2"><div>Trained <b>${p.stats.trained}</b></div><div>Gathered <b>${p.stats.gathered}</b></div><div>Kills <b>${p.stats.killed}</b></div><div>Losses <b>${p.stats.lost}</b></div></div>`;
    } else if (ents.length === 1) {
      const e = ents[0];
      if (e.kind === 'res') {
        html = `<div class="title">${{ tree: 'Tree', berries: 'Berry Bush', stone: 'Stone Quarry', gold: 'Gold Mine' }[e.type]}</div>
          <div class="sub">${RES_ICON[e.res]} ${Math.ceil(e.amount)} / ${e.max} ${e.res}</div>${this.bar(e.amount / e.max, '#fbbf24')}`;
      } else {
        const own = e.owner === 0, pl = g.players[e.owner];
        const hpTxt = `${Math.ceil(e.hp)} / ${e.maxHp}`;
        html = `<div class="title" style="color:${pl.color}">${e.kind === 'unit' ? unitIcon(e.def) : e.def.icon} ${e.def.name}${own ? '' : ` <small>(${pl.name})</small>`}</div>
          <div class="sub">❤️ ${hpTxt}</div>${this.bar(e.hp / e.maxHp, '#4ade80')}`;
        if (e.kind === 'unit') {
          const d = e.def;
          html += `<div class="stats2"><div>⚔️ ${d.atk}</div><div>🛡️ ${d.armor}</div><div>🎯 ${d.range < 1.5 ? 'melee' : d.range}</div><div>👟 ${d.speed}</div></div>`;
          if (own) html += `<div class="sub">${this.stateText(e)}</div>`;
          if (e.carry > 0) html += `<div class="sub">Carrying ${RES_ICON[e.carryRes]} ${e.carry}</div>`;
          if (d.bonus) html += `<div class="sub dim">Bonus vs ${Object.keys(d.bonus).join(', ')}</div>`;
        } else {
          if (!e.built) html += `<div class="sub">Under construction: ${Math.floor(e.progress * 100)}%</div>${this.bar(e.progress, '#60a5fa')}`;
          else if (own && e.def.farm) html += `<div class="sub">${g.farmTaken(e, null) ? 'Being farmed' : 'Idle — assign a citizen'}</div>`;
          if (own && e.queue.length) {
            const q0 = e.queue[0];
            html += `<div class="sub">${q0.blocked ? '⚠️ Population limit' : q0.type === '@epoch' ? 'Advancing epoch' : 'Training ' + UNITS[q0.type].name} ${Math.floor(q0.t / q0.time * 100)}%</div>${this.bar(q0.t / q0.time, '#a78bfa')}`;
            html += `<div class="queue">${e.queue.map((q, i) => `<span class="qi" data-q="${i}" title="Click to cancel">${q.type === '@epoch' ? '⏫' : unitIcon(UNITS[q.type])}</span>`).join('')}</div>`;
          }
          if (e.def.atk) html += `<div class="stats2"><div>⚔️ ${e.def.atk}</div><div>🎯 ${e.def.range}</div></div>`;
          if (e.type === 'wonder' && e.built && pl.wonderT != null) html += `<div class="sub">Victory in ${fmtTime(WONDER_TIME - pl.wonderT)}</div>`;
        }
      }
    } else {
      html = `<div class="title">${ents.length} selected</div><div class="multi">` + ents.map(e => {
        const f = e.hp / e.maxHp;
        return `<span class="mu" data-id="${e.id}" title="${e.def.name}">${e.kind === 'unit' ? unitIcon(e.def) : e.def.icon}<i style="width:${Math.round(f * 100)}%;background:${f > 0.5 ? '#4ade80' : f > 0.25 ? '#facc15' : '#f87171'}"></i></span>`;
      }).join('') + '</div>';
    }
    if (html !== this.infoSig) { this.infoSig = html; el.innerHTML = html; }
  }
  bar(f, col) { return `<div class="bar"><i style="width:${Math.round(clamp(f, 0, 1) * 100)}%;background:${col}"></i></div>`; }
  stateText(u) {
    const g = this.g;
    switch (u.state) {
      case 'idle': return 'Idle';
      case 'move': return u.amove ? 'Attack-moving' : 'Moving';
      case 'attack': { const t = g.get(u.targetId); return t ? `Attacking ${t.def.name}` : 'Attacking'; }
      case 'gather': return `Gathering ${u.gatherType}`;
      case 'return': return `Returning ${u.carryRes}`;
      case 'build': { const t = g.get(u.buildId); return t ? `${t.built ? 'Repairing' : 'Building'} ${t.def.name}` : 'Building'; }
    }
    return '';
  }

  // ---------------------------------------------------------------- per-frame
  update(dt) {
    if (!this.g) return;
    const g = this.g, p = g.players[0], r = this.r;
    // scroll
    let sx = 0, sy = 0;
    if (this.keys.has('ArrowLeft')) sx--; if (this.keys.has('ArrowRight')) sx++;
    if (this.keys.has('ArrowUp')) sy--; if (this.keys.has('ArrowDown')) sy++;
    if (this.mouse.in && !this.drag && document.hasFocus()) {
      const m = 10;
      if (this.mouse.x < m) sx--; if (this.mouse.x > this.canvas.width - m) sx++;
      if (this.mouse.y < m) sy--; if (this.mouse.y > this.canvas.height - m) sy++;
    }
    if (sx || sy) { r.cam.x += sx * 900 * dt / r.cam.z; r.cam.y += sy * 900 * dt / r.cam.z; r.clampCam(); }
    this.mouseWorld = r.toWorld(this.mouse.x, this.mouse.y);
    // prune dead
    if (this.sel.some(id => !g.get(id))) this.setSel(this.sel.filter(id => g.get(id)));
    // top bar
    for (const k of RES) this.setText('r-' + k, Math.floor(p.res[k]));
    this.setText('r-pop', `${p.pop}/${p.popCap}`);
    $('r-pop').classList.toggle('warn', p.pop >= p.popCap);
    this.setText('epoch', EPOCHS[p.epoch].name + (p.advancing ? ' ⏫' : ''));
    this.setText('clock', fmtTime(g.time));
    this.setText('idle-n', g.units.filter(u => u.owner === 0 && u.def.cls === 'citizen' && u.state === 'idle').length);
    let wt = '';
    for (const pl of g.players) if (pl.wonderT != null) wt += `<span style="color:${pl.color}">🗿 ${pl.id === 0 ? 'Your' : 'Enemy'} Wonder: ${fmtTime(WONDER_TIME - pl.wonderT)}</span> `;
    if ($('wonder-timer').innerHTML !== wt) $('wonder-timer').innerHTML = wt;
    // messages
    const msgs = g.messages.filter(m => g.time - m.t < 7);
    const ms = msgs.map(m => m.text + m.t).join('|');
    if (ms !== this.msgSig) { this.msgSig = ms; $('messages').innerHTML = msgs.map(m => `<div style="color:${m.color}">${m.text}</div>`).join(''); }
    this.renderCommands();
    this.renderInfo();
    this.canvas.style.cursor = this.placing ? 'none' : this.mode === 'amove' ? 'crosshair' : this.hoverCursor();
  }
  hoverCursor() {
    if (!this.mouseWorld || !this.selUnits().length) return 'default';
    const t = this.pickAt(this.mouseWorld.x, this.mouseWorld.y);
    if (t && t.kind !== 'res' && t.owner !== 0) return 'crosshair';
    if (t && t.kind === 'res' && this.selUnits().some(u => u.def.cls === 'citizen')) return 'pointer';
    return 'default';
  }
  setText(id, v) { const el = $(id); const s = String(v); if (el.textContent !== s) el.textContent = s; }

  // ---------------------------------------------------------------- events
  bind() {
    const cv = this.canvas;
    cv.addEventListener('contextmenu', e => e.preventDefault());
    $('minimap').addEventListener('contextmenu', e => e.preventDefault());
    cv.addEventListener('mousedown', e => {
      if (!this.active) return;
      const mx = e.offsetX, my = e.offsetY, w = this.r.toWorld(mx, my);
      if (e.button === 0) {
        if (this.placing) return this.tryPlace(e.shiftKey);
        if (this.mode === 'amove') {
          const t = this.pickAt(w.x, w.y);
          if (t && t.kind !== 'res' && t.owner !== 0) this.g.cmdAttack(this.selUnits(), t);
          else this.g.cmdMove(this.selUnits(), w.x, w.y, true);
          this.marker(w.x, w.y, '#f87171');
          if (!e.shiftKey) this.mode = null;
          return;
        }
        this.drag = { sx: mx, sy: my, mx, my, active: false };
      } else if (e.button === 2) this.rightClick(w.x, w.y);
    });
    window.addEventListener('mousemove', e => {
      const rc = cv.getBoundingClientRect();
      this.mouse.x = e.clientX - rc.left; this.mouse.y = e.clientY - rc.top;
      this.mouse.in = this.mouse.x >= 0 && this.mouse.y >= 0 && this.mouse.x <= rc.width && this.mouse.y <= rc.height;
      if (this.drag) {
        this.drag.mx = clamp(this.mouse.x, 0, rc.width); this.drag.my = clamp(this.mouse.y, 0, rc.height);
        if (Math.hypot(this.drag.mx - this.drag.sx, this.drag.my - this.drag.sy) > 6) this.drag.active = true;
      }
      if (this.mmDrag) this.minimapAt(e, false);
    });
    document.addEventListener('mouseleave', () => { this.mouse.in = false; });
    window.addEventListener('mouseup', e => {
      if (e.button === 0) this.mmDrag = false;
      if (!this.drag || e.button !== 0) return;
      if (this.active) {
        if (this.drag.active) this.boxSelect(this.drag, e.shiftKey);
        else this.clickSelect(this.drag.sx, this.drag.sy, e.shiftKey);
      }
      this.drag = null;
    });
    cv.addEventListener('wheel', e => {
      if (!this.r) return;
      e.preventDefault();
      const cam = this.r.cam, before = this.r.toWorld(e.offsetX, e.offsetY);
      cam.z = clamp(cam.z * (e.deltaY < 0 ? 1.1 : 1 / 1.1), 0.5, 1.6);
      cam.x = before.x - e.offsetX / cam.z; cam.y = before.y - e.offsetY / cam.z;
      this.r.clampCam();
    }, { passive: false });
    this.minimap.addEventListener('mousedown', e => {
      if (!this.active) return;
      if (e.button === 0) { this.mmDrag = true; this.minimapAt(e, false); }
      else if (e.button === 2) this.minimapAt(e, true);
    });
    $('info').addEventListener('mousedown', e => {
      if (!this.active) return;
      const q = e.target.closest('[data-q]');
      if (q) { const b = this.selBuilding(); if (b) this.g.cancelQueue(b, +q.dataset.q); return; }
      const m = e.target.closest('[data-id]');
      if (m) { if (e.shiftKey) this.setSel(this.sel.filter(id => id !== +m.dataset.id)); else this.setSel([+m.dataset.id]); }
    });
    $('idle-btn').addEventListener('click', () => this.selectIdle());
    window.addEventListener('keydown', e => this.onKey(e));
    window.addEventListener('keyup', e => this.keys.delete(e.key));
    window.addEventListener('blur', () => this.keys.clear());
  }
  minimapAt(e, command) {
    const rc = this.minimap.getBoundingClientRect();
    const x = clamp((e.clientX - rc.left) / rc.width, 0, 1) * MAP_W * T, y = clamp((e.clientY - rc.top) / rc.height, 0, 1) * MAP_H * T;
    if (command) { const u = this.selUnits(); if (u.length) { this.g.cmdMove(u, x, y); this.marker(x, y, '#4ade80'); } }
    else this.r.centerOn(x, y);
  }
  selectIdle() {
    const idle = this.g.units.filter(u => u.owner === 0 && u.def.cls === 'citizen' && u.state === 'idle');
    if (!idle.length) return;
    const u = idle[this.idleIdx++ % idle.length];
    this.setSel([u.id]); this.r.centerOn(u.x, u.y);
  }
  onKey(e) {
    if (e.target && e.target.tagName === 'INPUT') return;
    if (e.key.startsWith('Arrow')) { this.keys.add(e.key); e.preventDefault(); return; }
    if (!this.g) return;
    if (e.key === 'Escape') {
      if (this.placing || this.mode) { this.placing = null; this.mode = null; }
      else if (!$('overlay-help').classList.contains('hidden')) $('overlay-help').classList.add('hidden');
      else this.setSel([]);
      return;
    }
    if (e.key === 'F1' || e.key === '?') { e.preventDefault(); $('overlay-help').classList.toggle('hidden'); return; }
    if (e.key === 'p' || e.key === 'P' || e.key === 'Pause') { this.togglePause(); return; }
    if (!this.active) return;
    if (/^[0-9]$/.test(e.key)) {
      if (e.ctrlKey || e.metaKey) { e.preventDefault(); this.groups[e.key] = this.sel.slice(); this.flash(`Group ${e.key} set.`, '#93c5fd'); }
      else if (this.groups[e.key]) {
        const ids = this.groups[e.key].filter(id => this.g.get(id));
        const now = performance.now();
        if (this.lastGroup === e.key && now - this.lastGroupT < 400 && ids.length) { const u = this.g.get(ids[0]); this.r.centerOn(u.x, u.y); }
        this.lastGroup = e.key; this.lastGroupT = now;
        this.setSel(ids);
      }
      return;
    }
    if (e.key === '.') { this.selectIdle(); return; }
    if (e.key === ' ' || e.key === 'h' || e.key === 'H') {
      e.preventDefault();
      const tc = this.g.buildings.find(b => b.owner === 0 && b.type === 'town_center');
      if (tc) { if (e.key !== ' ') this.setSel([tc.id]); this.r.centerOn(tc.x, tc.y); }
      return;
    }
    const k = e.key.toUpperCase();
    this.renderCommands();
    const c = this.cmds.find(c => c.key === k && !c.locked && c.act);
    if (c) { e.preventDefault(); c.act(e); }
  }
  togglePause() {
    if (!this.g || this.g.over) return;
    this.paused = !this.paused;
    $('paused').classList.toggle('hidden', !this.paused);
    $('btn-pause').textContent = this.paused ? '▶' : '⏸';
  }
}
