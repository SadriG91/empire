'use strict';
// ---------------------------------------------------------------------------
// Static game data: epochs, units, buildings, production lines.
// ---------------------------------------------------------------------------

const T = 32;              // tile size in pixels
const MAP_W = 96, MAP_H = 96;
const MAX_POP = 200;
const WONDER_TIME = 300;   // seconds a completed Wonder must survive to win
const RES = ['food', 'wood', 'stone', 'gold'];
const RES_ICON = { food: '🍖', wood: '🪵', stone: '🪨', gold: '🪙' };
const RES_COLOR = { food: '#e5533d', wood: '#a0703f', stone: '#b4b4b4', gold: '#f2c230' };
const PLAYER_COLORS = ['#3b82f6', '#ef4444', '#22c55e', '#eab308'];

const EPOCHS = [
  { name: 'Stone Age', cost: null, time: 0 },
  { name: 'Bronze Age', cost: { food: 500, wood: 300 }, time: 30 },
  { name: 'Middle Ages', cost: { food: 900, gold: 400 }, time: 40 },
  { name: 'Gunpowder Age', cost: { food: 1300, gold: 700, stone: 300 }, time: 50 },
  { name: 'Industrial Age', cost: { food: 1800, gold: 1100, wood: 800 }, time: 60 },
  { name: 'Modern Age', cost: { food: 2400, gold: 1600, stone: 600 }, time: 70 },
];

// Visual palette for buildings per epoch.
const EPOCH_STYLE = [
  { wall: '#9a7347', roof: '#d1ae62', trim: '#6b4a2b' },
  { wall: '#c39a6b', roof: '#9a5b3a', trim: '#6e4128' },
  { wall: '#9d9b92', roof: '#6e3d2b', trim: '#5c5a54' },
  { wall: '#c2b392', roof: '#47597d', trim: '#6f6650' },
  { wall: '#9b4d3b', roof: '#4a4a4a', trim: '#5a2e24' },
  { wall: '#b5babd', roof: '#566470', trim: '#7b8288' },
];

// cls: citizen | infantry | ranged | cavalry | siege
// range in tiles, speed in tiles/second, cd = seconds between attacks
const UNITS = {
  citizen: { name: 'Citizen', cls: 'citizen', hp: 50, atk: 3, range: 0.8, cd: 1.2, speed: 2.1, los: 5, armor: 0, r: 7, cost: { food: 50 }, time: 10, weapon: 'tool',
    desc: 'Gathers resources and constructs buildings.' },

  clubman: { name: 'Clubman', cls: 'infantry', hp: 70, atk: 6, range: 0.8, cd: 1.1, speed: 2.2, los: 5, armor: 1, r: 8, cost: { food: 40, wood: 20 }, time: 12, weapon: 'club',
    desc: 'Cheap melee infantry.' },
  spearman: { name: 'Spearman', cls: 'infantry', hp: 90, atk: 8, range: 0.9, cd: 1.1, speed: 2.2, los: 5, armor: 2, r: 8, cost: { food: 45, wood: 25 }, time: 13, weapon: 'spear', bonus: { cavalry: 2.5 },
    desc: 'Melee infantry. Strong against cavalry.' },
  swordsman: { name: 'Swordsman', cls: 'infantry', hp: 125, atk: 12, range: 0.8, cd: 1.1, speed: 2.2, los: 5, armor: 3, r: 8, cost: { food: 55, gold: 25 }, time: 14, weapon: 'sword', bonus: { cavalry: 1.6 },
    desc: 'Armoured melee infantry. Good against cavalry.' },
  musketeer: { name: 'Musketeer', cls: 'infantry', hp: 110, atk: 15, range: 5, cd: 1.8, speed: 2.1, los: 7, armor: 2, r: 8, cost: { food: 55, gold: 35 }, time: 15, weapon: 'gun', proj: 'bullet', bonus: { cavalry: 1.4 },
    desc: 'Gunpowder infantry. Good against cavalry.' },
  rifleman: { name: 'Rifleman', cls: 'infantry', hp: 130, atk: 20, range: 6, cd: 1.6, speed: 2.2, los: 8, armor: 3, r: 8, cost: { food: 60, gold: 45 }, time: 15, weapon: 'gun', proj: 'bullet', bonus: { cavalry: 1.4 },
    desc: 'Industrial infantry with long range.' },
  assault_infantry: { name: 'Assault Infantry', cls: 'infantry', hp: 160, atk: 26, range: 6, cd: 1.3, speed: 2.3, los: 8, armor: 4, r: 8, cost: { food: 70, gold: 55 }, time: 16, weapon: 'gun', proj: 'bullet', bonus: { cavalry: 1.4 },
    desc: 'Modern all-round infantry.' },

  slinger: { name: 'Slinger', cls: 'ranged', hp: 40, atk: 5, range: 4.5, cd: 1.5, speed: 2.2, los: 6, armor: 0, r: 7, cost: { food: 30, wood: 30 }, time: 12, weapon: 'sling', proj: 'stone', bonus: { infantry: 1.3 },
    desc: 'Ranged. Strong against infantry, weak to cavalry.' },
  archer: { name: 'Archer', cls: 'ranged', hp: 50, atk: 7, range: 5.5, cd: 1.5, speed: 2.2, los: 7, armor: 0, r: 7, cost: { food: 35, wood: 40 }, time: 13, weapon: 'bow', proj: 'arrow', bonus: { infantry: 1.3 },
    desc: 'Ranged. Strong against infantry, weak to cavalry.' },
  crossbowman: { name: 'Crossbowman', cls: 'ranged', hp: 65, atk: 10, range: 6, cd: 1.8, speed: 2.2, los: 7, armor: 1, r: 7, cost: { food: 40, wood: 35, gold: 20 }, time: 14, weapon: 'bow', proj: 'arrow', bonus: { infantry: 1.3 },
    desc: 'Ranged. Strong against infantry, weak to cavalry.' },
  grenadier: { name: 'Grenadier', cls: 'ranged', hp: 80, atk: 16, range: 5, cd: 2.2, speed: 2.2, los: 7, armor: 1, r: 8, cost: { food: 50, gold: 45 }, time: 15, weapon: 'grenade', proj: 'grenade', splash: 1, bonus: { infantry: 1.3 },
    desc: 'Throws grenades that damage groups.' },
  sharpshooter: { name: 'Sharpshooter', cls: 'ranged', hp: 90, atk: 24, range: 8, cd: 2.0, speed: 2.2, los: 10, armor: 1, r: 8, cost: { food: 55, gold: 55 }, time: 15, weapon: 'gun', proj: 'bullet', bonus: { infantry: 1.3 },
    desc: 'Very long range marksman.' },
  machine_gunner: { name: 'Machine Gunner', cls: 'ranged', hp: 120, atk: 8, range: 6, cd: 0.35, speed: 2.0, los: 8, armor: 2, r: 8, cost: { food: 65, gold: 65 }, time: 16, weapon: 'mg', proj: 'bullet', bonus: { infantry: 1.3 },
    desc: 'Rapid fire. Shreds infantry.' },

  horseman: { name: 'Horseman', cls: 'cavalry', hp: 130, atk: 9, range: 0.9, cd: 1.2, speed: 3.6, los: 6, armor: 2, r: 11, cost: { food: 60, gold: 40 }, time: 16, weapon: 'spear', bonus: { ranged: 1.8, siege: 2 },
    desc: 'Fast cavalry. Strong against ranged and siege.' },
  knight: { name: 'Knight', cls: 'cavalry', hp: 190, atk: 14, range: 0.9, cd: 1.2, speed: 3.4, los: 6, armor: 4, r: 11, cost: { food: 80, gold: 70 }, time: 18, weapon: 'sword', bonus: { ranged: 1.8, siege: 2 },
    desc: 'Heavy cavalry. Strong against ranged and siege.' },
  cuirassier: { name: 'Cuirassier', cls: 'cavalry', hp: 220, atk: 18, range: 0.9, cd: 1.2, speed: 3.6, los: 6, armor: 4, r: 11, cost: { food: 90, gold: 80 }, time: 18, weapon: 'sword', bonus: { ranged: 1.8, siege: 2 },
    desc: 'Armoured cavalry. Strong against ranged and siege.' },
  dragoon: { name: 'Dragoon', cls: 'cavalry', hp: 200, atk: 19, range: 5, cd: 1.6, speed: 3.6, los: 7, armor: 3, r: 11, cost: { food: 90, gold: 90 }, time: 18, weapon: 'gun', proj: 'bullet', bonus: { ranged: 1.5, siege: 2 },
    desc: 'Mounted gunner. Strong against ranged and siege.' },
  tank: { name: 'Tank', cls: 'cavalry', shape: 'tank', hp: 520, atk: 42, range: 6, cd: 2.4, speed: 3.0, los: 8, armor: 8, r: 13, cost: { wood: 100, gold: 200 }, time: 25, proj: 'shell', splash: 0.8, bonus: { building: 1.2, infantry: 1.2 },
    desc: 'Armoured vehicle. Devastating all-rounder.' },

  catapult: { name: 'Catapult', cls: 'siege', hp: 120, atk: 40, range: 8, cd: 4, speed: 1.4, los: 9, armor: 2, r: 12, cost: { wood: 150, gold: 100 }, time: 25, proj: 'boulder', splash: 1, bonus: { building: 3 },
    desc: 'Siege. Destroys buildings from afar.' },
  cannon: { name: 'Cannon', cls: 'siege', hp: 160, atk: 55, range: 9, cd: 4, speed: 1.5, los: 9, armor: 2, r: 12, cost: { wood: 150, gold: 150 }, time: 25, proj: 'ball', splash: 0.8, bonus: { building: 3 },
    desc: 'Siege. Destroys buildings from afar.' },
  artillery: { name: 'Artillery', cls: 'siege', hp: 180, atk: 75, range: 11, cd: 4.5, speed: 1.5, los: 12, armor: 3, r: 12, cost: { wood: 175, gold: 200 }, time: 28, proj: 'shell', splash: 1.2, bonus: { building: 3 },
    desc: 'Long range siege gun.' },
  rocket_launcher: { name: 'Rocket Launcher', cls: 'siege', hp: 220, atk: 95, range: 12, cd: 5, speed: 2.2, los: 12, armor: 4, r: 12, cost: { wood: 200, gold: 250 }, time: 30, proj: 'rocket', splash: 1.5, bonus: { building: 3 },
    desc: 'Mobile rocket artillery.' },
};

// Production lines: index = epoch. The newest available unit of each row is trainable,
// and existing units of a row upgrade automatically when the epoch advances.
const PRODUCTION = {
  town_center: [['citizen']],
  barracks: [['clubman', 'spearman', 'swordsman', 'musketeer', 'rifleman', 'assault_infantry']],
  archery_range: [['slinger', 'archer', 'crossbowman', 'grenadier', 'sharpshooter', 'machine_gunner']],
  stable: [[null, 'horseman', 'knight', 'cuirassier', 'dragoon', 'tank']],
  workshop: [[null, null, 'catapult', 'cannon', 'artillery', 'rocket_launcher']],
};
const UNIT_LINE = {};
for (const bld in PRODUCTION) {
  PRODUCTION[bld].forEach((row, ri) => row.forEach(t => { if (t && !UNIT_LINE[t]) UNIT_LINE[t] = { bld, row: ri }; }));
}

const BUILDINGS = {
  town_center: { name: 'Town Center', size: 3, hp: 2400, armor: 2, cost: { wood: 300, stone: 200 }, time: 80, epoch: 0, pop: 10, dropoff: true, atk: 6, range: 6, cd: 1.5, los: 8, key: 'C', icon: '🏛️',
    desc: 'Trains citizens, stores resources, advances epochs. Shoots arrows.' },
  house: { name: 'House', size: 2, hp: 500, armor: 1, cost: { wood: 50 }, time: 18, epoch: 0, pop: 5, los: 3, key: 'E', icon: '🏠',
    desc: '+5 population.' },
  farm: { name: 'Farm', size: 2, hp: 250, armor: 0, cost: { wood: 60 }, time: 12, epoch: 0, farm: true, walkable: true, los: 2, key: 'F', icon: '🌾',
    desc: 'Endless food source for one citizen.' },
  storehouse: { name: 'Storehouse', size: 2, hp: 600, armor: 1, cost: { wood: 100 }, time: 22, epoch: 0, dropoff: true, los: 4, key: 'R', icon: '📦',
    desc: 'Drop-off point for all resources.' },
  barracks: { name: 'Barracks', size: 3, hp: 1100, armor: 2, cost: { wood: 150 }, time: 35, epoch: 0, los: 5, key: 'B', icon: '⚔️',
    desc: 'Trains infantry.' },
  archery_range: { name: 'Archery Range', size: 3, hp: 1000, armor: 2, cost: { wood: 150 }, time: 35, epoch: 0, los: 5, key: 'V', icon: '🏹',
    desc: 'Trains ranged units.' },
  stable: { name: 'Stable', size: 3, hp: 1100, armor: 2, cost: { wood: 175, gold: 50 }, time: 40, epoch: 1, los: 5, key: 'T', icon: '🐎',
    desc: 'Trains cavalry (and later tanks).' },
  workshop: { name: 'Siege Workshop', size: 3, hp: 1100, armor: 2, cost: { wood: 200, gold: 100 }, time: 45, epoch: 2, los: 5, key: 'K', icon: '⚙️',
    desc: 'Trains siege weapons.' },
  tower: { name: 'Tower', size: 2, hp: 1100, armor: 3, cost: { wood: 50, stone: 150 }, time: 40, epoch: 1, atk: 9, range: 7, cd: 1.3, los: 9, key: 'O', icon: '🗼',
    desc: 'Defensive tower. Shoots at enemies.' },
  wonder: { name: 'Wonder', size: 4, hp: 6000, armor: 3, cost: { food: 1000, wood: 1000, stone: 1000, gold: 1000 }, time: 200, epoch: 3, los: 6, key: 'W', icon: '🗿',
    desc: `Defend a completed Wonder for ${WONDER_TIME / 60} minutes to win.` },
};
const BUILD_MENU = ['house', 'farm', 'storehouse', 'barracks', 'archery_range', 'stable', 'workshop', 'tower', 'town_center', 'wonder'];

const UNIT_ICON = { citizen: '👷', infantry: '🗡️', ranged: '🏹', cavalry: '🐎', siege: '💣' };
function unitIcon(def) { return def.shape === 'tank' ? '🛡️' : UNIT_ICON[def.cls]; }

// Per-difficulty AI tuning.
const DIFFICULTY = {
  easy:   { gather: 0.75, firstAttack: 600, wave: 5, waveGrow: 2, think: 1.5, armyCap: 0.6, towers: false, bonus: 0,   epochDelay: [0, 480, 960, 1440, 1920, 2400] },
  normal: { gather: 1.0,  firstAttack: 420, wave: 7, waveGrow: 3, think: 1.0, armyCap: 0.85, towers: true, bonus: 0,  epochDelay: [0, 330, 720, 1100, 1500, 1900] },
  hard:   { gather: 1.3,  firstAttack: 270, wave: 9, waveGrow: 4, think: 0.7, armyCap: 1.0, towers: true, bonus: 200, epochDelay: [0, 220, 520, 820, 1120, 1420] },
};

