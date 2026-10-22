extends Node
## Entry point: owns the simulation, 3D view, camera, input controller, HUD, menu and audio.

const SAVE_PATH := "user://savegame.json"
const STEP := 1.0 / 30.0

var sim: Sim
var view: WorldView
var cam: RTSCamera
var ctrl: Controller
var hud: Hud
var sfx: Sfx
var menu: Menu
var world_root: Node3D
var menu_open := true
var demo := false
var paused := false
var speed := 1.0
var _acc := 0.0
var _ended := false

func _ready() -> void:
	sfx = Sfx.new()
	add_child(sfx)
	ctrl = Controller.new()
	ctrl.game = self
	add_child(ctrl)
	var args = OS.get_cmdline_user_args()
	if args.has("--shots"):
		var shots: Node = load("res://scripts/tests/shots.gd").new()
		shots.game = self
		add_child(shots)
		return
	menu = Menu.new()
	menu.game = self
	add_child(menu)
	start_demo()

func _teardown() -> void:
	if world_root:
		world_root.queue_free()
		world_root = null
	if hud:
		hud.queue_free()
		hud = null
	sim = null
	view = null
	cam = null
	ctrl.sel.clear()
	ctrl.sel_set.clear()
	ctrl.placing = ""
	ctrl.mode = ""
	paused = false
	_ended = false

func _build_world(s: Sim) -> void:
	_teardown()
	sim = s
	world_root = Node3D.new()
	add_child(world_root)
	view = WorldView.new()
	world_root.add_child(view)
	view.setup(sim)
	cam = RTSCamera.new()
	cam.bounds = Rect2(0, 0, sim.map.w * WorldView.TILE, sim.map.h * WorldView.TILE)
	cam.height_fn = func(p: Vector3) -> float: return sim.map.height_at(Vector2(p.x / WorldView.TILE, p.z / WorldView.TILE))
	world_root.add_child(cam)

func start_demo() -> void:
	var pl = []
	for i in 4:
		pl.append({"team": i, "ai": true, "personality": Defs.PERSONALITIES.keys()[i]})
	var s = Sim.new({"players": pl, "map_type": "lakes", "map_size": "medium", "difficulty": "hard", "start_epoch": 2, "resources": "high", "seed": randi(), "reveal": true})
	s.new_game()
	for i in 1800:
		s.update(STEP)
	s.fx.clear()
	s.messages.clear()
	_build_world(s)
	demo = true
	menu_open = true
	cam.dist = 46.0
	cam.pitch = deg_to_rad(38.0)
	var c = Vector2(s.map.w, s.map.h) * 0.5
	var tgt: Vector2 = s.starts[0].lerp(c, 0.4)
	cam.center_on(WorldView.to3(tgt, 0))
	menu.visible = true
	menu.refresh()

func start_game(settings: Dictionary) -> void:
	var s = Sim.new(settings)
	s.new_game()
	_enter_game(s)
	var tc: Ent = null
	for b in s.buildings:
		if b.owner == 0:
			tc = b
	cam.center_on(WorldView.to3(tc.pos + Vector2(0, 2), 0))
	ctrl.set_sel(s.units.filter(func(u): return u.owner == 0 and u.def.cls == "citizen").map(func(u): return u.id))
	s.msg(0, "Map seed %d. Grow your empire and defeat your rivals!" % s.seed_value, Color("#fde68a"))

func _enter_game(s: Sim) -> void:
	_build_world(s)
	demo = false
	menu_open = false
	if menu:
		menu.visible = false
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	speed = 1.0

func to_menu() -> void:
	if menu == null:
		get_tree().quit()
		return
	start_demo()

func toggle_pause() -> void:
	if sim == null or demo or sim.over:
		return
	paused = not paused
	hud.set_paused(paused)

func cycle_speed() -> void:
	speed = {1.0: 1.5, 1.5: 2.0, 2.0: 3.0, 3.0: 1.0}[speed]
	hud.set_speed(speed)

func save_game() -> void:
	if sim == null or demo:
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(sim.to_dict()))
	f.close()
	hud.flash("Game saved.", Color("#86efac"))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		if hud:
			hud.flash("No saved game.")
		return
	var txt = FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if d == null:
		if hud:
			hud.flash("Save file is damaged.")
		return
	var s = Sim.from_dict(d)
	_enter_game(s)
	for b in s.buildings:
		if b.owner == 0 and b.type == "town_center":
			cam.center_on(WorldView.to3(b.pos, 0))
	hud.flash("Game loaded.", Color("#86efac"))

func _physics_process(_delta: float) -> void:
	if sim == null or paused or sim.over:
		return
	_acc += speed
	while _acc >= 1.0:
		_acc -= 1.0
		sim.update(STEP)
		var fx = sim.fx
		sim.fx = []
		view.handle_fx(fx)
		if not demo:
			sfx.handle_fx(fx, cam.focus)
	if sim.over and not _ended and not demo:
		_ended = true
		hud.show_end()
		sfx.play("victory" if sim.winner_team == sim.players[0].team else "defeat", 1.0)
	if demo and sim.over:
		start_demo()

func _process(delta: float) -> void:
	if sim == null:
		return
	var alpha = Engine.get_physics_interpolation_fraction() if not paused else 1.0
	if sim.over:
		alpha = 1.0
	view.sync(delta, alpha, ctrl.sel_set)
	if demo:
		cam.rotate_by(delta * 0.04, 0.0)
	else:
		cam.apply()
	if hud:
		hud.update(delta)
