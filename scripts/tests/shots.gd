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
		"start_epoch": int(_arg("epoch", "0")), "resources": _arg("res", "standard"), "seed": int(_arg("seed", "3")), "reveal": false}
	game.start_game(settings)
	var s: Sim = game.sim
	await _frames(10)
	_shot(out + "/start.png")
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
	print("SHOTS time=%d epochs=%s units=%d" % [s.time, str(s.players.map(func(p): return p.epoch)), s.units.size()])
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(path: String) -> void:
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
