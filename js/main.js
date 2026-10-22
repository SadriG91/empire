'use strict';
// Bootstraps the menus and runs the fixed-timestep game loop.

const STEP = 1 / 30;
const ui = new UI();
let game = null, renderer = null, acc = 0, last = performance.now();
let difficulty = 'normal';

const params = new URLSearchParams(location.search);

function resize() {
  if (!renderer) return;
  const v = $('view');
  renderer.resize(v.clientWidth, v.clientHeight);
  renderer.clampCam();
}
window.addEventListener('resize', resize);

function startGame() {
  const raw = $('seed').value.trim();
  const seed = raw ? (/^\d+$/.test(raw) ? +raw : [...raw].reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7)) : undefined;
  game = new Game({ difficulty, seed, revealAll: params.has('reveal') });
  renderer = new Renderer($('game'), $('minimap'), game);
  renderer.cam.z = 1.15;
  ui.attach(game, renderer);
  resize();
  const tc = game.buildings.find(b => b.owner === 0 && b.type === 'town_center');
  renderer.centerOn(tc.x, tc.y + 60);
  ui.setSel(game.units.filter(u => u.owner === 0 && u.def.cls === 'citizen').map(u => u.id));
  game.msg(0, `Map seed ${game.seed}. Gather resources, grow your empire and defeat the Rival Empire!`, '#fde68a');
  $('overlay-start').classList.add('hidden');
  $('overlay-end').classList.add('hidden');
  window.__game = game; window.__ui = ui; window.__renderer = renderer;
}

function showEnd() {
  const won = game.winner === 0;
  $('end-title').textContent = won ? 'Victory!' : 'Defeat';
  $('end-title').style.color = won ? '#fcd34d' : '#f87171';
  $('end-sub').textContent = (won ? 'Your empire stands supreme' : 'Your empire has fallen') + ` — ${game.winHow.toLowerCase()} after ${fmtTime(game.time)}.`;
  const [a, b] = game.players;
  const row = (k, l) => `<tr><td>${l}</td><td style="color:${a.color}">${a.stats[k]}</td><td style="color:${b.color}">${b.stats[k]}</td></tr>`;
  $('end-stats').innerHTML = `<tr><th></th><th>You</th><th>Rival</th></tr>` +
    `<tr><td>Epoch</td><td style="color:${a.color}">${EPOCHS[a.epoch].name}</td><td style="color:${b.color}">${EPOCHS[b.epoch].name}</td></tr>` +
    row('gathered', 'Resources gathered') + row('trained', 'Units trained') + row('built', 'Buildings built') + row('killed', 'Kills') + row('lost', 'Losses');
  $('overlay-end').classList.remove('hidden');
}

function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (game) {
    if (!ui.paused && !game.over) {
      acc += dt * ui.speed;
      let n = 0;
      while (acc >= STEP && n < 8) { game.update(STEP); acc -= STEP; n++; }
      if (n === 8) acc = 0;
      if (game.over) showEnd();
    }
    ui.update(dt);
    renderer.draw(ui);
  }
  requestAnimationFrame(frame);
}

// menu wiring
document.querySelectorAll('#diff button').forEach(b => b.addEventListener('click', () => {
  document.querySelectorAll('#diff button').forEach(x => x.classList.remove('on'));
  b.classList.add('on'); difficulty = b.dataset.v;
}));
$('btn-start').addEventListener('click', startGame);
$('seed').addEventListener('keydown', e => { if (e.key === 'Enter') startGame(); });
$('btn-again').addEventListener('click', () => { $('overlay-end').classList.add('hidden'); $('overlay-start').classList.remove('hidden'); game = null; });
$('btn-help').addEventListener('click', () => $('overlay-help').classList.toggle('hidden'));
$('btn-help-close').addEventListener('click', () => $('overlay-help').classList.add('hidden'));
$('btn-pause').addEventListener('click', () => ui.togglePause());
$('btn-speed').addEventListener('click', () => {
  ui.speed = ui.speed === 1 ? 1.5 : ui.speed === 1.5 ? 2 : 1;
  $('btn-speed').textContent = ui.speed + 'x';
});
if (params.has('autostart')) {
  if (params.get('difficulty')) difficulty = params.get('difficulty');
  if (params.get('seed')) $('seed').value = params.get('seed');
  startGame();
}
requestAnimationFrame(frame);
