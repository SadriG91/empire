# Empire: Epochs

A browser real-time strategy game inspired by *Empire Earth*. Lead your people from the
**Stone Age to the Modern Age**, gather resources, build a city, raise an army and defeat
the Rival Empire.

It is plain HTML5 Canvas and JavaScript with no dependencies and no build step.

## Play

Open `index.html` in a browser, or serve the folder:

```sh
python3 -m http.server 8000   # then visit http://localhost:8000
```

URL options: `?autostart&difficulty=hard&seed=42` skips the menu; `?reveal` disables fog of war.

## Features

- **6 epochs**: Stone, Bronze, Middle Ages, Gunpowder, Industrial, Modern. Advancing upgrades
  every existing soldier, unlocks units and buildings, and changes how your buildings look.
- **Economy**: citizens gather food (berries, farms), wood, stone and gold; houses raise the
  population limit (max 200); storehouses are extra drop-off points.
- **24 unit types** in 4 production lines plus citizens:
  - Barracks: Clubman → Spearman → Swordsman → Musketeer → Rifleman → Assault Infantry
  - Archery Range: Slinger → Archer → Crossbowman → Grenadier → Sharpshooter → Machine Gunner
  - Stable: Horseman → Knight → Cuirassier → Dragoon → Tank
  - Siege Workshop: Catapult → Cannon → Artillery → Rocket Launcher
- **Counter system**: spears and guns beat cavalry, cavalry beats ranged and siege, ranged
  beats infantry, siege wrecks buildings. Splash damage for grenades, artillery and rockets.
- Towers and Town Centers shoot back. Citizens can repair damaged buildings.
- **AI opponent** (Easy / Normal / Hard) that builds an economy, advances epochs, builds
  defences and attacks in growing waves.
- Fog of war, minimap, control groups, attack-move, rally points, production queues.
- **Victory**: destroy all enemy Town Centers and citizens, or finish a **Wonder** and
  keep it standing for 5 minutes.

## Controls

| Input | Action |
| --- | --- |
| Left-click / drag | Select / box-select (Shift adds) |
| Double-click | Select all units of that type on screen |
| Right-click | Move, attack, gather, build, repair, set rally point |
| `A` / `S` / `Del` | Attack-move / stop / delete |
| `Ctrl+1-9`, `1-9` | Create / recall control group (tap twice to jump to it) |
| `.` | Next idle citizen |
| `H` / `Space` | Select / jump to the Town Center |
| Arrows, screen edge, wheel | Scroll and zoom |
| `P`, `F1` | Pause, help |

Each build and train button shows its hotkey.

## Code layout

| File | Purpose |
| --- | --- |
| `js/data.js` | Epochs, units, buildings, production lines, difficulty tuning |
| `js/util.js` | RNG, heap, noise and resource helpers |
| `js/map.js` | Tile grid, A* pathfinding, world generation |
| `js/game.js` | Simulation: orders, gathering, combat, epochs, victory |
| `js/ai.js` | Computer opponent |
| `js/render.js` | Canvas renderer, fog of war, minimap |
| `js/ui.js` | Input handling, HUD and command card |
| `js/main.js` | Menus and the fixed-timestep game loop |

The simulation (`data`, `util`, `map`, `game`, `ai`) has no DOM dependencies, so it can be run
headlessly in Node to simulate AI-vs-AI games.
