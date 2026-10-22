class_name Defs
extends RefCounted
## Static game data: epochs, units, buildings, technologies and AI tuning.
## Distances and speeds are in tiles; times are in seconds.

const RES := ["food", "wood", "stone", "gold"]
const RES_COLOR := {"food": Color("#e5533d"), "wood": Color("#a0703f"), "stone": Color("#b4b4b4"), "gold": Color("#f2c230")}
const WONDER_TIME := 300.0

const PLAYER_COLORS := [Color("#2f7cf6"), Color("#e23b3b"), Color("#22b357"), Color("#e6b60d")]
const PLAYER_NAMES := ["You", "Crimson Dominion", "Jade Khanate", "Golden Republic"]

const EPOCHS := [
	{"name": "Stone Age", "cost": {}, "time": 0.0},
	{"name": "Bronze Age", "cost": {"food": 500, "wood": 300}, "time": 30.0},
	{"name": "Middle Ages", "cost": {"food": 900, "gold": 400}, "time": 40.0},
	{"name": "Gunpowder Age", "cost": {"food": 1300, "gold": 700, "stone": 300}, "time": 50.0},
	{"name": "Industrial Age", "cost": {"food": 1800, "gold": 1100, "wood": 800}, "time": 60.0},
	{"name": "Modern Age", "cost": {"food": 2400, "gold": 1600, "stone": 600}, "time": 70.0},
]

# Building colours per epoch: wall, roof, trim.
const EPOCH_STYLE := [
	[Color("#9a7347"), Color("#d1ae62"), Color("#6b4a2b")],
	[Color("#c39a6b"), Color("#9a5b3a"), Color("#6e4128")],
	[Color("#a3a198"), Color("#6e3d2b"), Color("#5c5a54")],
	[Color("#c9bb9a"), Color("#47597d"), Color("#6f6650")],
	[Color("#9b4d3b"), Color("#4a4a4a"), Color("#5a2e24")],
	[Color("#b5babd"), Color("#566470"), Color("#7b8288")],
]

# cls: citizen infantry ranged cavalry siege priest ship air
const UNITS := {
	"citizen": {"name": "Citizen", "cls": "citizen", "hp": 50, "atk": 3, "range": 0.6, "cd": 1.2, "speed": 2.1, "los": 5, "armor": 0, "r": 0.22, "cost": {"food": 50}, "time": 10, "model": "citizen", "gather": true,
		"desc": "Gathers resources, builds and repairs."},

	"clubman": {"name": "Clubman", "cls": "infantry", "hp": 70, "atk": 6, "range": 0.6, "cd": 1.1, "speed": 2.2, "los": 5, "armor": 1, "r": 0.25, "cost": {"food": 40, "wood": 20}, "time": 12, "model": "club",
		"desc": "Cheap melee infantry."},
	"spearman": {"name": "Spearman", "cls": "infantry", "hp": 90, "atk": 8, "range": 0.7, "cd": 1.1, "speed": 2.2, "los": 5, "armor": 2, "r": 0.25, "cost": {"food": 45, "wood": 25}, "time": 13, "model": "spear", "bonus": {"cavalry": 2.5},
		"desc": "Melee infantry. Strong against cavalry."},
	"swordsman": {"name": "Swordsman", "cls": "infantry", "hp": 125, "atk": 12, "range": 0.6, "cd": 1.1, "speed": 2.2, "los": 5, "armor": 3, "r": 0.25, "cost": {"food": 55, "gold": 25}, "time": 14, "model": "sword", "bonus": {"cavalry": 1.6},
		"desc": "Armoured melee infantry. Good against cavalry."},
	"musketeer": {"name": "Musketeer", "cls": "infantry", "hp": 110, "atk": 15, "range": 5.0, "cd": 1.8, "speed": 2.1, "los": 7, "armor": 2, "r": 0.25, "cost": {"food": 55, "gold": 35}, "time": 15, "model": "gun", "proj": "bullet", "bonus": {"cavalry": 1.4},
		"desc": "Gunpowder infantry. Good against cavalry."},
	"rifleman": {"name": "Rifleman", "cls": "infantry", "hp": 130, "atk": 20, "range": 6.0, "cd": 1.6, "speed": 2.2, "los": 8, "armor": 3, "r": 0.25, "cost": {"food": 60, "gold": 45}, "time": 15, "model": "gun", "proj": "bullet", "aa": true, "bonus": {"cavalry": 1.4},
		"desc": "Long range infantry. Can fire at aircraft."},
	"assault_infantry": {"name": "Assault Infantry", "cls": "infantry", "hp": 160, "atk": 26, "range": 6.0, "cd": 1.3, "speed": 2.3, "los": 8, "armor": 4, "r": 0.25, "cost": {"food": 70, "gold": 55}, "time": 16, "model": "gun", "proj": "bullet", "aa": true, "bonus": {"cavalry": 1.4},
		"desc": "Modern all-round infantry. Can fire at aircraft."},

	"slinger": {"name": "Slinger", "cls": "ranged", "hp": 40, "atk": 5, "range": 4.5, "cd": 1.5, "speed": 2.2, "los": 6, "armor": 0, "r": 0.22, "cost": {"food": 30, "wood": 30}, "time": 12, "model": "sling", "proj": "stone", "bonus": {"infantry": 1.3},
		"desc": "Ranged. Strong against infantry, weak to cavalry."},
	"archer": {"name": "Archer", "cls": "ranged", "hp": 50, "atk": 7, "range": 5.5, "cd": 1.5, "speed": 2.2, "los": 7, "armor": 0, "r": 0.22, "cost": {"food": 35, "wood": 40}, "time": 13, "model": "bow", "proj": "arrow", "bonus": {"infantry": 1.3},
		"desc": "Ranged. Strong against infantry, weak to cavalry."},
	"crossbowman": {"name": "Crossbowman", "cls": "ranged", "hp": 65, "atk": 10, "range": 6.0, "cd": 1.8, "speed": 2.2, "los": 7, "armor": 1, "r": 0.22, "cost": {"food": 40, "wood": 35, "gold": 20}, "time": 14, "model": "bow", "proj": "arrow", "bonus": {"infantry": 1.3},
		"desc": "Ranged. Strong against infantry, weak to cavalry."},
	"grenadier": {"name": "Grenadier", "cls": "ranged", "hp": 80, "atk": 16, "range": 5.0, "cd": 2.2, "speed": 2.2, "los": 7, "armor": 1, "r": 0.25, "cost": {"food": 50, "gold": 45}, "time": 15, "model": "grenade", "proj": "grenade", "splash": 1.0, "bonus": {"infantry": 1.3},
		"desc": "Throws grenades that damage groups."},
	"sharpshooter": {"name": "Sharpshooter", "cls": "ranged", "hp": 90, "atk": 24, "range": 8.0, "cd": 2.0, "speed": 2.2, "los": 10, "armor": 1, "r": 0.25, "cost": {"food": 55, "gold": 55}, "time": 15, "model": "gun", "proj": "bullet", "aa": true, "bonus": {"infantry": 1.3},
		"desc": "Very long range marksman."},
	"machine_gunner": {"name": "Machine Gunner", "cls": "ranged", "hp": 120, "atk": 8, "range": 6.0, "cd": 0.35, "speed": 2.0, "los": 8, "armor": 2, "r": 0.25, "cost": {"food": 65, "gold": 65}, "time": 16, "model": "mg", "proj": "bullet", "aa": true, "bonus": {"infantry": 1.3},
		"desc": "Rapid fire. Shreds infantry and aircraft."},

	"horseman": {"name": "Horseman", "cls": "cavalry", "hp": 130, "atk": 9, "range": 0.7, "cd": 1.2, "speed": 3.6, "los": 6, "armor": 2, "r": 0.35, "cost": {"food": 60, "gold": 40}, "time": 16, "model": "horse", "bonus": {"ranged": 1.8, "siege": 2.0},
		"desc": "Fast cavalry. Strong against ranged and siege."},
	"knight": {"name": "Knight", "cls": "cavalry", "hp": 190, "atk": 14, "range": 0.7, "cd": 1.2, "speed": 3.4, "los": 6, "armor": 4, "r": 0.35, "cost": {"food": 80, "gold": 70}, "time": 18, "model": "horse", "bonus": {"ranged": 1.8, "siege": 2.0},
		"desc": "Heavy cavalry. Strong against ranged and siege."},
	"cuirassier": {"name": "Cuirassier", "cls": "cavalry", "hp": 220, "atk": 18, "range": 0.7, "cd": 1.2, "speed": 3.6, "los": 6, "armor": 4, "r": 0.35, "cost": {"food": 90, "gold": 80}, "time": 18, "model": "horse", "bonus": {"ranged": 1.8, "siege": 2.0},
		"desc": "Armoured cavalry. Strong against ranged and siege."},
	"dragoon": {"name": "Dragoon", "cls": "cavalry", "hp": 200, "atk": 19, "range": 5.0, "cd": 1.6, "speed": 3.6, "los": 7, "armor": 3, "r": 0.35, "cost": {"food": 90, "gold": 90}, "time": 18, "model": "horse_gun", "proj": "bullet", "bonus": {"ranged": 1.5, "siege": 2.0},
		"desc": "Mounted gunner. Strong against ranged and siege."},
	"tank": {"name": "Tank", "cls": "cavalry", "hp": 520, "atk": 42, "range": 6.0, "cd": 2.4, "speed": 3.0, "los": 8, "armor": 8, "r": 0.42, "cost": {"wood": 100, "gold": 200}, "time": 25, "model": "tank", "proj": "shell", "splash": 0.8, "bonus": {"building": 1.2, "infantry": 1.2},
		"desc": "Armoured vehicle. Devastating all-rounder."},

	"catapult": {"name": "Catapult", "cls": "siege", "hp": 120, "atk": 40, "range": 8.0, "cd": 4.0, "speed": 1.4, "los": 9, "armor": 2, "r": 0.38, "cost": {"wood": 150, "gold": 100}, "time": 25, "model": "catapult", "proj": "boulder", "splash": 1.0, "bonus": {"building": 3.0, "ship": 1.5},
		"desc": "Siege. Destroys buildings and ships from afar."},
	"cannon": {"name": "Cannon", "cls": "siege", "hp": 160, "atk": 55, "range": 9.0, "cd": 4.0, "speed": 1.5, "los": 9, "armor": 2, "r": 0.38, "cost": {"wood": 150, "gold": 150}, "time": 25, "model": "cannon", "proj": "ball", "splash": 0.8, "bonus": {"building": 3.0, "ship": 1.5},
		"desc": "Siege. Destroys buildings and ships from afar."},
	"artillery": {"name": "Artillery", "cls": "siege", "hp": 180, "atk": 75, "range": 11.0, "cd": 4.5, "speed": 1.5, "los": 12, "armor": 3, "r": 0.38, "cost": {"wood": 175, "gold": 200}, "time": 28, "model": "artillery", "proj": "shell", "splash": 1.2, "bonus": {"building": 3.0, "ship": 1.5},
		"desc": "Long range siege gun."},
	"rocket_launcher": {"name": "Rocket Launcher", "cls": "siege", "hp": 220, "atk": 95, "range": 12.0, "cd": 5.0, "speed": 2.2, "los": 12, "armor": 4, "r": 0.4, "cost": {"wood": 200, "gold": 250}, "time": 30, "model": "rocket", "proj": "rocket", "splash": 1.5, "bonus": {"building": 3.0, "ship": 1.5},
		"desc": "Mobile rocket artillery."},
	"flak_gun": {"name": "Flak Gun", "cls": "siege", "hp": 200, "atk": 30, "range": 8.0, "cd": 1.2, "speed": 1.6, "los": 10, "armor": 3, "r": 0.38, "cost": {"wood": 120, "gold": 120}, "time": 20, "model": "flak", "proj": "flak", "aa": true, "air_only": true,
		"desc": "Anti-aircraft gun. Only attacks aircraft."},
	"sam_launcher": {"name": "SAM Launcher", "cls": "siege", "hp": 250, "atk": 70, "range": 11.0, "cd": 2.0, "speed": 2.2, "los": 12, "armor": 4, "r": 0.4, "cost": {"wood": 150, "gold": 175}, "time": 22, "model": "sam", "proj": "rocket", "aa": true, "air_only": true,
		"desc": "Surface-to-air missiles. Only attacks aircraft."},

	"priest": {"name": "Priest", "cls": "priest", "hp": 55, "atk": 0, "range": 5.0, "cd": 1.0, "speed": 1.9, "los": 7, "armor": 0, "r": 0.22, "cost": {"gold": 100}, "time": 20, "model": "priest", "heal": 4.0, "convert": true,
		"desc": "Heals allies and converts enemy units to your side."},
	"medic": {"name": "Medic", "cls": "priest", "hp": 90, "atk": 0, "range": 4.0, "cd": 1.0, "speed": 2.5, "los": 7, "armor": 1, "r": 0.22, "cost": {"food": 60, "gold": 40}, "time": 15, "model": "medic", "heal": 9.0,
		"desc": "Quickly heals nearby allied units."},

	"warlord": {"name": "Warlord", "cls": "infantry", "hp": 650, "atk": 22, "range": 0.7, "cd": 1.0, "speed": 2.6, "los": 8, "armor": 5, "r": 0.3, "cost": {"food": 200, "gold": 200}, "time": 40, "model": "hero", "hero": true,
		"desc": "Hero. Inspires nearby troops: +20% attack, +1 armour, healing."},
	"paladin": {"name": "Paladin", "cls": "infantry", "hp": 850, "atk": 30, "range": 0.7, "cd": 1.0, "speed": 2.6, "los": 8, "armor": 6, "r": 0.3, "cost": {"food": 250, "gold": 250}, "time": 40, "model": "hero", "hero": true,
		"desc": "Hero. Inspires nearby troops: +20% attack, +1 armour, healing."},
	"general": {"name": "General", "cls": "infantry", "hp": 950, "atk": 34, "range": 5.0, "cd": 1.2, "speed": 2.6, "los": 9, "armor": 6, "r": 0.3, "cost": {"food": 300, "gold": 300}, "time": 40, "model": "hero", "hero": true, "proj": "bullet",
		"desc": "Hero. Inspires nearby troops: +20% attack, +1 armour, healing."},
	"field_marshal": {"name": "Field Marshal", "cls": "infantry", "hp": 1100, "atk": 40, "range": 6.0, "cd": 1.2, "speed": 2.7, "los": 9, "armor": 7, "r": 0.3, "cost": {"food": 350, "gold": 350}, "time": 40, "model": "hero", "hero": true, "proj": "bullet", "aa": true,
		"desc": "Hero. Inspires nearby troops: +20% attack, +1 armour, healing."},
	"commander": {"name": "Commander", "cls": "infantry", "hp": 1300, "atk": 48, "range": 6.0, "cd": 1.0, "speed": 2.8, "los": 10, "armor": 8, "r": 0.3, "cost": {"food": 400, "gold": 400}, "time": 40, "model": "hero", "hero": true, "proj": "bullet", "aa": true,
		"desc": "Hero. Inspires nearby troops: +20% attack, +1 armour, healing."},

	"fishing_boat": {"name": "Fishing Boat", "cls": "ship", "hp": 90, "atk": 0, "range": 0.8, "cd": 1.0, "speed": 2.6, "los": 6, "armor": 1, "r": 0.4, "cost": {"wood": 60}, "time": 15, "model": "fishing_boat", "naval": true, "gather": true,
		"desc": "Catches fish and brings it to a Dock."},
	"galley": {"name": "Galley", "cls": "ship", "hp": 260, "atk": 10, "range": 5.0, "cd": 1.8, "speed": 2.8, "los": 7, "armor": 2, "r": 0.5, "cost": {"wood": 120, "gold": 40}, "time": 25, "model": "galley", "naval": true, "proj": "arrow", "bonus": {"building": 1.2},
		"desc": "Warship. Attacks ships and the coast."},
	"galleon": {"name": "Galleon", "cls": "ship", "hp": 400, "atk": 16, "range": 6.0, "cd": 1.8, "speed": 2.8, "los": 8, "armor": 3, "r": 0.55, "cost": {"wood": 150, "gold": 60}, "time": 25, "model": "galleon", "naval": true, "proj": "ball", "bonus": {"building": 1.5},
		"desc": "Warship. Attacks ships and the coast."},
	"frigate": {"name": "Frigate", "cls": "ship", "hp": 520, "atk": 24, "range": 7.0, "cd": 1.8, "speed": 3.0, "los": 8, "armor": 4, "r": 0.55, "cost": {"wood": 170, "gold": 90}, "time": 25, "model": "frigate", "naval": true, "proj": "ball", "bonus": {"building": 1.5},
		"desc": "Warship. Attacks ships and the coast."},
	"ironclad": {"name": "Ironclad", "cls": "ship", "hp": 720, "atk": 34, "range": 8.0, "cd": 2.0, "speed": 3.0, "los": 9, "armor": 6, "r": 0.55, "cost": {"wood": 150, "gold": 150}, "time": 28, "model": "ironclad", "naval": true, "proj": "shell", "bonus": {"building": 1.5},
		"desc": "Steam warship with heavy guns."},
	"battleship": {"name": "Battleship", "cls": "ship", "hp": 1100, "atk": 50, "range": 10.0, "cd": 2.2, "speed": 3.0, "los": 10, "armor": 8, "r": 0.6, "cost": {"wood": 200, "gold": 250}, "time": 32, "model": "battleship", "naval": true, "proj": "shell", "splash": 1.0, "aa": true, "bonus": {"building": 1.5},
		"desc": "Dominates the seas. Can fire at aircraft."},

	"biplane": {"name": "Biplane", "cls": "air", "hp": 160, "atk": 12, "range": 4.0, "cd": 0.8, "speed": 6.0, "los": 9, "armor": 1, "r": 0.4, "cost": {"wood": 150, "gold": 150}, "time": 25, "model": "biplane", "air": true, "aa": true, "proj": "bullet", "bonus": {"air": 2.0, "building": 0.3},
		"desc": "Fighter. Hunts aircraft and harasses troops."},
	"jet_fighter": {"name": "Jet Fighter", "cls": "air", "hp": 280, "atk": 20, "range": 5.0, "cd": 0.8, "speed": 8.0, "los": 10, "armor": 2, "r": 0.45, "cost": {"wood": 150, "gold": 220}, "time": 28, "model": "jet", "air": true, "aa": true, "proj": "rocket", "bonus": {"air": 2.5, "building": 0.3},
		"desc": "Fighter. Hunts aircraft and harasses troops."},
	"zeppelin": {"name": "Zeppelin", "cls": "air", "hp": 600, "atk": 60, "range": 0.8, "cd": 4.0, "speed": 2.0, "los": 9, "armor": 2, "r": 0.6, "cost": {"wood": 200, "gold": 250}, "time": 30, "model": "zeppelin", "air": true, "bomber": true, "proj": "bomb", "splash": 1.5, "bonus": {"building": 2.5},
		"desc": "Bomber airship. Drops bombs on buildings and troops."},
	"bomber": {"name": "Bomber", "cls": "air", "hp": 420, "atk": 90, "range": 0.8, "cd": 4.0, "speed": 6.5, "los": 10, "armor": 3, "r": 0.5, "cost": {"wood": 220, "gold": 300}, "time": 32, "model": "bomber", "air": true, "bomber": true, "proj": "bomb", "splash": 1.5, "bonus": {"building": 2.5},
		"desc": "Heavy bomber. Flattens buildings."},
}

# Production lines: index = epoch. Units of a line upgrade automatically on epoch advance.
const PRODUCTION := {
	"town_center": [["citizen"], [null, "warlord", "paladin", "general", "field_marshal", "commander"]],
	"barracks": [["clubman", "spearman", "swordsman", "musketeer", "rifleman", "assault_infantry"]],
	"archery_range": [["slinger", "archer", "crossbowman", "grenadier", "sharpshooter", "machine_gunner"]],
	"stable": [[null, "horseman", "knight", "cuirassier", "dragoon", "tank"]],
	"workshop": [[null, null, "catapult", "cannon", "artillery", "rocket_launcher"], [null, null, null, null, "flak_gun", "sam_launcher"]],
	"temple": [[null, "priest", "priest", "priest", "medic", "medic"]],
	"dock": [["fishing_boat"], [null, "galley", "galleon", "frigate", "ironclad", "battleship"]],
	"airfield": [[null, null, null, null, "biplane", "jet_fighter"], [null, null, null, null, "zeppelin", "bomber"]],
}

const BUILDINGS := {
	"town_center": {"name": "Town Center", "size": 3, "hp": 2400, "armor": 2, "cost": {"wood": 300, "stone": 200}, "time": 80, "epoch": 0, "pop": 10, "dropoff": true, "atk": 6, "range": 6.0, "cd": 1.5, "los": 8, "key": "C",
		"desc": "Trains citizens and heroes, stores resources, advances epochs. Shoots arrows."},
	"house": {"name": "House", "size": 2, "hp": 500, "armor": 1, "cost": {"wood": 50}, "time": 18, "epoch": 0, "pop": 5, "los": 3, "key": "E",
		"desc": "+5 population."},
	"farm": {"name": "Farm", "size": 2, "hp": 250, "armor": 0, "cost": {"wood": 60}, "time": 12, "epoch": 0, "farm": true, "walkable": true, "los": 2, "key": "F",
		"desc": "Endless food source for one citizen."},
	"storehouse": {"name": "Storehouse", "size": 2, "hp": 600, "armor": 1, "cost": {"wood": 100}, "time": 22, "epoch": 0, "dropoff": true, "los": 4, "key": "R",
		"desc": "Resource drop-off. Researches economy upgrades."},
	"dock": {"name": "Dock", "size": 2, "hp": 1000, "armor": 2, "cost": {"wood": 120}, "time": 30, "epoch": 0, "naval": true, "dropoff": true, "los": 6, "key": "D",
		"desc": "Built on the shoreline. Trains fishing boats and warships."},
	"barracks": {"name": "Barracks", "size": 3, "hp": 1100, "armor": 2, "cost": {"wood": 150}, "time": 35, "epoch": 0, "los": 5, "key": "B",
		"desc": "Trains infantry."},
	"archery_range": {"name": "Archery Range", "size": 3, "hp": 1000, "armor": 2, "cost": {"wood": 150}, "time": 35, "epoch": 0, "los": 5, "key": "V",
		"desc": "Trains ranged units."},
	"stable": {"name": "Stable", "size": 3, "hp": 1100, "armor": 2, "cost": {"wood": 175, "gold": 50}, "time": 40, "epoch": 1, "los": 5, "key": "T",
		"desc": "Trains cavalry and, later, tanks."},
	"academy": {"name": "Academy", "size": 3, "hp": 1000, "armor": 2, "cost": {"wood": 175, "gold": 75}, "time": 40, "epoch": 1, "los": 5, "key": "N",
		"desc": "Researches military technologies."},
	"temple": {"name": "Temple", "size": 3, "hp": 1000, "armor": 2, "cost": {"wood": 100, "stone": 150}, "time": 45, "epoch": 1, "los": 6, "key": "Y",
		"desc": "Trains priests (later medics)."},
	"tower": {"name": "Tower", "size": 2, "hp": 1100, "armor": 3, "cost": {"wood": 50, "stone": 150}, "time": 40, "epoch": 1, "atk": 9, "range": 7.0, "cd": 1.3, "los": 9, "key": "O",
		"desc": "Defensive tower. Shoots at enemies (and aircraft from the Industrial Age)."},
	"wall": {"name": "Wall", "size": 1, "hp": 900, "armor": 6, "cost": {"stone": 6}, "time": 5, "epoch": 1, "los": 2, "key": "L", "wall": true,
		"desc": "Click and drag to build a line of wall. Blocks movement."},
	"workshop": {"name": "Siege Workshop", "size": 3, "hp": 1100, "armor": 2, "cost": {"wood": 200, "gold": 100}, "time": 45, "epoch": 2, "los": 5, "key": "K",
		"desc": "Trains siege weapons and anti-aircraft guns."},
	"airfield": {"name": "Airfield", "size": 4, "hp": 1600, "armor": 3, "cost": {"wood": 300, "gold": 200}, "time": 60, "epoch": 4, "los": 7, "key": "I",
		"desc": "Trains fighters and bombers."},
	"wonder": {"name": "Wonder", "size": 4, "hp": 6000, "armor": 3, "cost": {"food": 1000, "wood": 1000, "stone": 1000, "gold": 1000}, "time": 200, "epoch": 3, "los": 6, "key": "W",
		"desc": "Defend a completed Wonder for 5 minutes to win."},
}
const BUILD_MENU := ["house", "farm", "storehouse", "dock", "barracks", "archery_range", "stable", "academy", "temple", "tower", "wall", "workshop", "airfield", "town_center", "wonder"]

# eff keys: atk{cls:+mult} armor{cls:+n} range{cls:+n} speed{cls:+mult} gather{res:+mult} carry(+n) bld_hp(+mult) bld_armor(+n) heal(+mult) regen(hp/s)
const ECON := ["storehouse", "town_center"]
const TECHS := {
	"axes": {"name": "Bronze Axes", "at": ECON, "epoch": 0, "cost": {"food": 100, "wood": 50}, "time": 25, "eff": {"gather": {"wood": 0.15}}, "desc": "+15% wood gathering."},
	"saws": {"name": "Steel Saws", "at": ECON, "epoch": 2, "req": "axes", "cost": {"food": 200, "wood": 150}, "time": 35, "eff": {"gather": {"wood": 0.15}}, "desc": "+15% wood gathering."},
	"chainsaws": {"name": "Chainsaws", "at": ECON, "epoch": 4, "req": "saws", "cost": {"food": 300, "gold": 200}, "time": 45, "eff": {"gather": {"wood": 0.2}}, "desc": "+20% wood gathering."},
	"picks": {"name": "Pickaxes", "at": ECON, "epoch": 0, "cost": {"food": 100, "wood": 75}, "time": 25, "eff": {"gather": {"stone": 0.15, "gold": 0.15}}, "desc": "+15% stone and gold mining."},
	"shafts": {"name": "Shaft Mining", "at": ECON, "epoch": 2, "req": "picks", "cost": {"food": 200, "wood": 200}, "time": 35, "eff": {"gather": {"stone": 0.15, "gold": 0.15}}, "desc": "+15% stone and gold mining."},
	"dynamite": {"name": "Dynamite", "at": ECON, "epoch": 4, "req": "shafts", "cost": {"food": 300, "gold": 250}, "time": 45, "eff": {"gather": {"stone": 0.2, "gold": 0.2}}, "desc": "+20% stone and gold mining."},
	"irrigation": {"name": "Irrigation", "at": ECON, "epoch": 0, "cost": {"food": 75, "wood": 100}, "time": 25, "eff": {"gather": {"food": 0.15}}, "desc": "+15% food gathering."},
	"rotation": {"name": "Crop Rotation", "at": ECON, "epoch": 2, "req": "irrigation", "cost": {"food": 200, "wood": 200}, "time": 35, "eff": {"gather": {"food": 0.15}}, "desc": "+15% food gathering."},
	"tractors": {"name": "Tractors", "at": ECON, "epoch": 4, "req": "rotation", "cost": {"food": 300, "gold": 250}, "time": 45, "eff": {"gather": {"food": 0.2}}, "desc": "+20% food gathering."},
	"wheelbarrow": {"name": "Wheelbarrow", "at": ECON, "epoch": 1, "cost": {"food": 150, "wood": 100}, "time": 30, "eff": {"carry": 5}, "desc": "Citizens carry 5 more resources."},
	"masonry": {"name": "Masonry", "at": ECON, "epoch": 1, "cost": {"wood": 100, "stone": 150}, "time": 30, "eff": {"bld_hp": 0.25}, "desc": "+25% building hit points."},
	"concrete": {"name": "Reinforced Concrete", "at": ECON, "epoch": 4, "req": "masonry", "cost": {"stone": 300, "gold": 200}, "time": 45, "eff": {"bld_hp": 0.25, "bld_armor": 2}, "desc": "+25% building hit points, +2 building armour."},

	"weapons1": {"name": "Bronze Weapons", "at": ["academy"], "epoch": 1, "cost": {"food": 150, "gold": 100}, "time": 30, "eff": {"atk": {"infantry": 0.15, "cavalry": 0.15}}, "desc": "+15% attack for infantry and cavalry."},
	"weapons2": {"name": "Steel Weapons", "at": ["academy"], "epoch": 3, "req": "weapons1", "cost": {"food": 300, "gold": 250}, "time": 45, "eff": {"atk": {"infantry": 0.15, "cavalry": 0.15}}, "desc": "+15% attack for infantry and cavalry."},
	"weapons3": {"name": "Advanced Munitions", "at": ["academy"], "epoch": 5, "req": "weapons2", "cost": {"food": 500, "gold": 450}, "time": 60, "eff": {"atk": {"infantry": 0.15, "cavalry": 0.15}}, "desc": "+15% attack for infantry and cavalry."},
	"armor1": {"name": "Scale Armour", "at": ["academy"], "epoch": 1, "cost": {"food": 150, "gold": 100}, "time": 30, "eff": {"armor": {"infantry": 1, "cavalry": 1, "citizen": 1}}, "desc": "+1 armour for infantry, cavalry and citizens."},
	"armor2": {"name": "Plate Armour", "at": ["academy"], "epoch": 3, "req": "armor1", "cost": {"food": 300, "gold": 250}, "time": 45, "eff": {"armor": {"infantry": 2, "cavalry": 2}}, "desc": "+2 armour for infantry and cavalry."},
	"armor3": {"name": "Composite Armour", "at": ["academy"], "epoch": 5, "req": "armor2", "cost": {"food": 500, "gold": 450}, "time": 60, "eff": {"armor": {"infantry": 2, "cavalry": 3}}, "desc": "+2 infantry and +3 cavalry armour."},
	"fletching": {"name": "Fletching", "at": ["academy"], "epoch": 1, "cost": {"food": 150, "wood": 100}, "time": 30, "eff": {"atk": {"ranged": 0.15}, "range": {"ranged": 0.5}}, "desc": "+15% attack and +0.5 range for ranged units."},
	"rifling": {"name": "Rifling", "at": ["academy"], "epoch": 3, "req": "fletching", "cost": {"food": 300, "gold": 250}, "time": 45, "eff": {"atk": {"ranged": 0.15}, "range": {"ranged": 0.5}}, "desc": "+15% attack and +0.5 range for ranged units."},
	"optics": {"name": "Optics", "at": ["academy"], "epoch": 5, "req": "rifling", "cost": {"food": 500, "gold": 450}, "time": 60, "eff": {"atk": {"ranged": 0.15}, "range": {"ranged": 1.0}}, "desc": "+15% attack and +1 range for ranged units."},
	"engineering": {"name": "Engineering", "at": ["academy", "workshop"], "epoch": 2, "cost": {"wood": 250, "gold": 150}, "time": 40, "eff": {"atk": {"siege": 0.2}, "range": {"siege": 1.0}}, "desc": "+20% attack and +1 range for siege."},
	"ballistics": {"name": "Ballistics", "at": ["academy", "workshop"], "epoch": 4, "req": "engineering", "cost": {"wood": 400, "gold": 300}, "time": 50, "eff": {"atk": {"siege": 0.2}, "range": {"siege": 1.0}}, "desc": "+20% attack and +1 range for siege."},
	"medicine": {"name": "Medicine", "at": ["academy", "temple"], "epoch": 2, "cost": {"food": 200, "gold": 200}, "time": 40, "eff": {"heal": 0.5, "regen": 0.5}, "desc": "+50% healing. All units slowly regenerate."},
	"logistics": {"name": "Logistics", "at": ["academy"], "epoch": 3, "cost": {"food": 300, "gold": 200}, "time": 40, "eff": {"speed": {"infantry": 0.1, "ranged": 0.1, "siege": 0.15}}, "desc": "Infantry and ranged +10% speed, siege +15%."},
	"zeal": {"name": "Zeal", "at": ["temple"], "epoch": 1, "cost": {"food": 150, "gold": 150}, "time": 30, "eff": {"convert": 0.4}, "desc": "Priests convert 40% faster."},
	"shipbuilding": {"name": "Shipbuilding", "at": ["dock"], "epoch": 2, "cost": {"wood": 250, "gold": 150}, "time": 40, "eff": {"atk": {"ship": 0.15}, "armor": {"ship": 1}}, "desc": "+15% ship attack, +1 ship armour."},
	"steam": {"name": "Steam Power", "at": ["dock"], "epoch": 4, "req": "shipbuilding", "cost": {"wood": 300, "gold": 300}, "time": 50, "eff": {"atk": {"ship": 0.15}, "armor": {"ship": 2}, "speed": {"ship": 0.2}}, "desc": "+15% ship attack, +2 armour, +20% speed."},
	"aerodynamics": {"name": "Aerodynamics", "at": ["airfield"], "epoch": 5, "cost": {"wood": 300, "gold": 400}, "time": 50, "eff": {"atk": {"air": 0.2}, "speed": {"air": 0.2}}, "desc": "+20% aircraft attack and speed."},
}

const DIFFICULTY := {
	"easy": {"gather": 0.75, "first_attack": 600.0, "wave": 5, "wave_grow": 2, "think": 1.5, "army_cap": 0.6, "towers": false, "bonus": 0, "epoch_delay": [0, 480, 960, 1440, 1920, 2400]},
	"normal": {"gather": 1.0, "first_attack": 420.0, "wave": 7, "wave_grow": 3, "think": 1.0, "army_cap": 0.85, "towers": true, "bonus": 0, "epoch_delay": [0, 300, 600, 900, 1200, 1500]},
	"hard": {"gather": 1.3, "first_attack": 270.0, "wave": 9, "wave_grow": 4, "think": 0.7, "army_cap": 1.0, "towers": true, "bonus": 200, "epoch_delay": [0, 220, 520, 820, 1120, 1420]},
}

const PERSONALITIES := {
	"balanced": {"name": "Balanced", "attack": 1.0, "epoch": 1.0, "towers": 0, "army": 1.0},
	"conqueror": {"name": "Conqueror", "attack": 0.7, "epoch": 1.2, "towers": 0, "army": 1.15},
	"builder": {"name": "Builder", "attack": 1.3, "epoch": 0.8, "towers": 1, "army": 0.9},
	"defender": {"name": "Defender", "attack": 1.4, "epoch": 1.0, "towers": 3, "army": 1.0},
}

const MAP_SIZES := {"small": 72, "medium": 96, "large": 128}
const MAP_TYPES := {"lakes": "Lakes", "inland_sea": "Inland Sea", "plains": "Plains", "highlands": "Highlands"}

static var unit_line := {}

static func _static_init() -> void:
	for bld in PRODUCTION:
		var rows: Array = PRODUCTION[bld]
		for ri in rows.size():
			for t in rows[ri]:
				if t != null and not unit_line.has(t):
					unit_line[t] = {"bld": bld, "row": ri}

static func line_unit(bld: String, row: int, epoch: int):
	var r: Array = PRODUCTION[bld][row]
	return r[mini(epoch, r.size() - 1)]

static func can_afford(res: Dictionary, cost: Dictionary) -> bool:
	for k in cost:
		if res.get(k, 0.0) < cost[k]:
			return false
	return true

static func missing(res: Dictionary, cost: Dictionary) -> String:
	for k in cost:
		if res.get(k, 0.0) < cost[k]:
			return k
	return ""

static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%s %d" % [k.capitalize(), cost[k]])
	return "  ".join(parts)

static func fmt_time(s: float) -> String:
	var t := int(s)
	return "%d:%02d" % [t / 60, t % 60]
