extends Node
## Screenshot harness (used for testing): plays a game with AI on both sides and saves PNGs.
## godot -- --shots [--menu] [--t=SECONDS] [--players=N] [--map=TYPE] [--epoch=N] [--out=DIR]

var game

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.split("=")[1]
	return def

func _ready() -> void:
	var out = _arg("out", "user://shots")
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--menu"):
		game.menu = Menu.new()
		game.menu.game = game
		game.add_child(game.menu)
		game.start_demo()
		await _frames(30)
		_shot(out + "/menu.png")
		get_tree().quit()
		return
	var n = int(_arg("players", "2"))
	var pl = []
	for i in n:
		pl.append({"team": i, "ai": true, "personality": Defs.PERSONALITIES.keys()[i % 4]})
	var settings = {"players": pl, "map_type": _arg("map", "lakes"), "map_size": "medium" if n <= 2 else "large", "difficulty": "normal",
		"start_epoch": int(_arg("epoch", "0")), "resources": _arg("res", "standard"), "seed": int(_arg("seed", "3")), "reveal": OS.get_cmdline_user_args().has("--reveal")}
	if OS.get_cmdline_user_args().has("--input"):
		settings.players[0].ai = false
	game.start_game(settings)
	var s: Sim = game.sim
	await _frames(10)
	_shot(out + "/start.png")
	if OS.get_cmdline_user_args().has("--input"):
		await run_input_test(out)
		get_tree().quit()
		return
	# let the computer play for us and fast-forward
	var t = float(_arg("t", "600"))
	while s.time < t and not s.over:
		for i in 300:
			s.update(1.0 / 30.0)
		s.fx.clear()
	# 1: our base, citizens selected
	var tc: Ent = null
	for b in s.buildings:
		if b.owner == 0 and b.type == "town_center":
			tc = b
	if tc:
		game.cam.center_on(WorldView.to3(tc.pos + Vector2(1, 3), 0))
		game.ctrl.set_sel([tc.id])
	await _frames(20)
	_shot(out + "/base.png")
	# 2: a battle (densest cluster of mixed owners), with soldiers selected
	var best = Vector2.ZERO
	var bs = -1
	for u in s.units:
		if u.def.cls == "citizen":
			continue
		var owners = {}
		var cnt = 0
		for v in s.units_near(u.pos, 6.0):
			if v.pos.distance_to(u.pos) < 6.0:
				owners[v.owner] = true
				cnt += 1
		var sc = cnt * (3 if owners.size() > 1 else 1)
		if sc > bs:
			bs = sc
			best = u.pos
	game.cam.dist = 26.0
	game.cam.center_on(WorldView.to3(best, 0))
	game.ctrl.set_sel(s.units.filter(func(u): return u.owner == 0 and u.def.cls != "citizen" and u.pos.distance_to(best) < 10).map(func(u): return u.id))
	await _frames(20)
	_shot(out + "/battle.png")
	# 3: zoomed out overview, rotated
	game.cam.dist = 70.0
	game.cam.rotate_by(0.6, -0.2)
	if tc:
		game.cam.center_on(WorldView.to3(tc.pos, 0))
	game.ctrl.set_sel([])
	await _frames(20)
	_shot(out + "/overview.png")
	if OS.get_cmdline_user_args().has("--ui"):
		game.hud.toggle_help()
		await _frames(5)
		_shot(out + "/help.png")
		game.hud.toggle_help()
		game.hud.toggle_tree()
		await _frames(5)
		_shot(out + "/tree.png")
		game.hud.toggle_tree()
		# a dogfight over our base
		var mid: Vector2 = tc.pos if tc else Vector2(s.map.w, s.map.h) * 0.5
		for i in 4:
			s.add_unit("jet_fighter", 0, mid + Vector2(-6 + i, 2))
			s.add_unit("bomber", 1, mid + Vector2(6, -2 + i))
		var ships = []
		for i in 30:
			s.update(1.0 / 30.0)
		game.cam.dist = 34.0
		game.cam.center_on(WorldView.to3(mid, 0))
		await _frames(10)
		_shot(out + "/air.png")
		s._end_game(s.players[0].team, "Conquest")
		game.hud.show_end()
		await _frames(10)
		_shot(out + "/end.png")
	# timing: simulation tick and view sync cost
	var t_sim = 0
	var t_view = 0
	for i in 60:
		var a = Time.get_ticks_usec()
		s.update(1.0 / 30.0)
		s.fx.clear()
		var b = Time.get_ticks_usec()
		game.view.sync(1.0 / 60.0, 1.0, game.ctrl.sel_set)
		game.hud.update(1.0 / 60.0)
		var c = Time.get_ticks_usec()
		t_sim += b - a
		t_view += c - b
		await get_tree().process_frame
	print("PERF units=%d buildings=%d sim_tick=%.2fms view+hud=%.2fms" % [s.units.size(), s.buildings.size(), t_sim / 60000.0, t_view / 60000.0])
	print("SHOTS time=%d epochs=%s units=%d" % [s.time, str(s.players.map(func(p): return p.epoch)), s.units.size()])
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(path: String) -> void:
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)

# ---------------------------------------------------------------- input test
func _ev_button(pos: Vector2, button: int, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	Input.parse_input_event(e)

func _ev_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	Input.warp_mouse(pos)

func _ev_key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

func _scr(p: Vector2) -> Vector2:
	return game.cam.cam.unproject_position(Vector3(p.x * 2.0, game.sim.map.height_at(p), p.y * 2.0))

func run_input_test(out: String) -> void:
	var s: Sim = game.sim
	var c: Controller = game.ctrl
	c.set_sel([])
	await _frames(5)
	var cits := s.units.filter(func(u): return u.owner == 0 and u.def.cls == "citizen")
	var a := _scr(cits[0].pos)
	var b := a
	for u in cits:
		var p := _scr(u.pos)
		a = Vector2(minf(a.x, p.x), minf(a.y, p.y))
		b = Vector2(maxf(b.x, p.x), maxf(b.y, p.y))
	a -= Vector2(30, 40)
	b += Vector2(30, 30)
	_ev_move(a)
	_ev_button(a, MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_ev_move(b)
	await _frames(2)
	_ev_button(b, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	print("TEST box-select citizens: selected=%d of %d" % [c.sel_units().size(), cits.size()])
	var tc: Ent = s.buildings.filter(func(x): return x.owner == 0)[0]
	var berries: Array = s.resources.filter(func(r): return r.type == "berries")
	berries.sort_custom(func(x, y): return x.pos.distance_to(tc.pos) < y.pos.distance_to(tc.pos))
	var bp := _scr(berries[0].pos) + Vector2(0, -6)
	_ev_move(bp)
	_ev_button(bp, MOUSE_BUTTON_RIGHT, true)
	_ev_button(bp, MOUSE_BUTTON_RIGHT, false)
	await _frames(3)
	print("TEST right-click berries: states=%s" % str(c.sel_units().map(func(u): return u.state + ":" + u.gather_type)))
	# place a house with the hotkey
	_ev_key(KEY_E)
	await _frames(2)
	print("TEST hotkey E: placing=%s" % c.placing)
	var spot := Vector2i(-1, -1)
	for r in range(4, 9):
		for dx in range(-r, r + 1):
			if spot.x < 0 and s.can_place("house", tc.tx + dx, tc.ty + r, 0, 1):
				spot = Vector2i(tc.tx + dx, tc.ty + r)
	var hp := _scr(Vector2(spot) + Vector2(1, 1))
	_ev_move(hp)
	await _frames(3)
	_shot(out + "/placing.png")
	_ev_button(hp, MOUSE_BUTTON_LEFT, true)
	_ev_button(hp, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	print("TEST place house: buildings=%s placing=%s" % [str(s.buildings.filter(func(x): return x.owner == 0).map(func(x): return x.type + ("" if x.built else "*"))), c.placing])
	# select the town center and queue citizens with Q
	var tp := _scr(tc.pos)
	_ev_move(tp)
	_ev_button(tp, MOUSE_BUTTON_LEFT, true)
	_ev_button(tp, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	_ev_key(KEY_Q)
	_ev_key(KEY_Q)
	await _frames(3)
	print("TEST select TC + Q x2: selected=%s queue=%d" % [str(c.sel_ents().map(func(e): return e.type)), tc.queue.size()])
	# set a rally point
	var rp := _scr(tc.pos + Vector2(6, 2))
	_ev_button(rp, MOUSE_BUTTON_RIGHT, true)
	_ev_button(rp, MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	print("TEST rally: has_rally=%s" % tc.has_rally)
	# let it run and check the citizens worked
	for i in 900:
		s.update(1.0 / 30.0)
	print("TEST after 30s: food=%d house_built=%s pop=%d" % [s.players[0].res.food, str(s.buildings.filter(func(x): return x.owner == 0 and x.type == "house").map(func(x): return x.built)), s.players[0].pop])
	await _frames(10)
	_shot(out + "/after_input.png")
