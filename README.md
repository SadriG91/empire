# Empire: Epochs

A 3D real-time strategy game inspired by *Empire Earth*, built with **Godot 4.5**.
Lead your civilisation from the **Stone Age to the Modern Age**: gather resources, build a city,
research technologies, raise armies, navies and air forces, and defeat up to three rival empires.

Everything is generated in code (models, terrain, icons and sound effects), so the project has
no binary assets.

## Running it

1. Install [Godot 4.5](https://godotengine.org/download) (the standard build; .NET is not needed).
2. Open Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **F5** (Run Project).

To ship a standalone build, use **Project → Export** in the editor (install the export templates
when Godot asks) and pick Windows, macOS, Linux or Web.

The project uses the Compatibility renderer, so it runs on older GPUs and integrated graphics.

## Features

**Skirmish setup**: 2–4 players, free-for-all or teams with allied AI, four map types (Lakes,
Inland Sea, Plains, Highlands), three map sizes, three difficulties, a starting epoch, starting
resources, a population cap, map seeds and a reveal-map option. The main menu runs a live
four-way AI battle in the background.

**Six epochs**: Stone, Bronze, Middle Ages, Gunpowder, Industrial, Modern. Advancing upgrades
every soldier in a line, unlocks buildings and units, speeds up gathering, and changes the look
of your whole city (thatch huts → timber → stone → brick → concrete).

**Economy**: citizens gather food (berries, farms), wood, stone and gold; fishing boats catch fish.
Houses raise the population limit. Storehouses and docks are drop-off points.

**Military**: 40 unit types across infantry, ranged, cavalry, siege, anti-air, priests, heroes,
ships and aircraft.

| Building | Line (Stone → Modern) |
| --- | --- |
| Barracks | Clubman → Spearman → Swordsman → Musketeer → Rifleman → Assault Infantry |
| Archery Range | Slinger → Archer → Crossbowman → Grenadier → Sharpshooter → Machine Gunner |
| Stable | Horseman → Knight → Cuirassier → Dragoon → Tank |
| Siege Workshop | Catapult → Cannon → Artillery → Rocket Launcher; Flak Gun → SAM Launcher |
| Town Center | Citizen; heroes: Warlord → Paladin → General → Field Marshal → Commander |
| Temple | Priest (heals, converts enemies) → Medic |
| Dock | Fishing Boat; Galley → Galleon → Frigate → Ironclad → Battleship |
| Airfield | Biplane → Jet Fighter; Zeppelin → Bomber |

**Combat depth**:
- **Counters.** Spears and guns beat cavalry; cavalry beats ranged and siege; ranged beats
  infantry; siege wrecks buildings and ships. Only anti-air units, fighters, battleships and
  Industrial-era towers can hit aircraft.
- **Terrain and experience.** Units fighting from high ground deal +25% damage, and veterans
  earn up to three ranks of bonus attack.
- **Heroes and stances.** Heroes inspire nearby troops (+20% attack, +1 armour, healing).
  Units take an aggressive, defensive or stand-ground stance.
- **Defences.** Walls are drawn by dragging. Towers and Town Centers shoot back. Damaged
  buildings burn and can be repaired.

**Research**: 30 technologies at the Academy, Storehouse/Town Center, Temple, Dock, Workshop and
Airfield (weapons, armour, range, siege, medicine, gathering, carry capacity, masonry, naval and
air upgrades).

**Interface**:
- **HUD.** Resource bar, live scoreboard, minimap with attack pings, and a command card with
  3D-rendered portraits, hotkeys and cost tooltips.
- **Orders.** Production queues, rally points, control groups and attack-move.
- **Reference.** Encyclopedia (F2), help (F1), and an end screen with stats and a score graph.

**Save and load** (F5 / F9), game speed up to 3x, pause, and synthesized sound effects.

**Victory**: destroy every rival Town Center and citizen, or finish a **Wonder** and defend it for
five minutes. If you are defeated, the map is revealed so you can watch the rest of the game.

## Controls

| Input | Action |
| --- | --- |
| Left-click / drag | Select / box-select (Shift adds) |
| Double-click | Select all units of that type on screen |
| Right-click | Move, attack, gather, build, repair, heal, convert, set rally point |
| `A`, `S`, `Del` | Attack-move, stop, delete |
| `Ctrl+1-9`, `1-9` | Create / recall a control group (tap twice to jump to it) |
| `.` / `,` | Next idle citizen / all soldiers |
| `H` / `Space` | Select / jump to your Town Center |
| Arrows, screen edges | Pan the camera |
| Mouse wheel | Zoom |
| Middle-drag, `PgUp`/`PgDn`, `Home` | Rotate and tilt / rotate / reset the camera |
| `P`, `F1`, `F2`, `F5`, `F9` | Pause, help, encyclopedia, save, load |

Build and train hotkeys are shown on each command button.

## Code layout

| Path | Purpose |
| --- | --- |
| `scripts/defs.gd` | All game data: epochs, units, buildings, technologies, AI tuning |
| `scripts/sim/` | Simulation with no rendering dependencies: map and pathfinding (`world_map.gd`), entities (`ent.gd`), rules (`sim.gd`), AI (`ai.gd`) |
| `scripts/view/` | 3D presentation: procedural models, terrain/water/fog shaders, effects, RTS camera |
| `scripts/ui/` | Input controller, HUD and main menu |
| `scripts/audio/sfx.gd` | Synthesized sound effects |
| `scripts/tests/` | Headless tests and a screenshot harness |
| `legacy-web/` | The original 2D browser prototype (ignored by Godot) |

The simulation runs at a fixed 30 ticks per second and is rendered with interpolation. It needs
no scene tree, so whole games can be simulated headlessly.

## Tests

```sh
tools/run_tests.sh /path/to/godot
```

This compiles every script, runs 20 mechanic scenarios (air combat, anti-air, bombing, naval
combat, fishing, conversion, healing, hero aura, research, walls, elevation) and plays a
20-minute computer-vs-computer game followed by a save/load round trip.
