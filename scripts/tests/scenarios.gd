extends SceneTree
## Scenario tests for individual mechanics. Prints PASS/FAIL per scenario.
## godot --headless --script res://scripts/tests/scenarios.gd

var fails := 0

func _sim(epoch := 5) -> Sim:
	var s := Sim.new({"seed": 99, "players": [{"team": 0, "ai": false}, {"team": 1, "ai": false}], "map_type": "plains", "map_size": "small", "start_epoch": epoch, "resources": "high", "reveal": true})
	s.new_game()
	return s

func _run(s: Sim, sec: float) -> void:
	for i in int(sec * 30):
		s.update(1.0 / 30.0)

func _check(name: String, ok: bool, info := "") -> void:
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1

func _open_spot(s: Sim, near: Vector2) -> Vector2:
	var t: Vector2i = s.map.nearest_passable(Vector2i(near), false, 20)
	return Vector2(t) + Vector2(0.5, 0.5)

func _initialize() -> void:
	# --- aircraft: fighters beat bombers, melee cannot touch aircraft, AA can
	var s := _sim()
	var mid := Vector2(s.map.w * 0.5, s.map.h * 0.5)
	var f := s.add_unit("jet_fighter", 0, mid)
	var bmb := s.add_unit("bomber", 1, mid + Vector2(4, 0))
	var club := s.add_unit("assault_infantry", 1, _open_spot(s, mid + Vector2(-3, 0)))
	_check("melee/ground non-AA cannot target aircraft", not s.can_target(s.add_unit("knight", 1, _open_spot(s, mid + Vector2(0, 3))), f))
	_check("assault infantry can target aircraft", s.can_target(club, f))
	s.cmd_attack([f], bmb)
	_run(s, 20)
	_check("jet fighter shoots down bomber", bmb.dead, "bomber hp=%d" % bmb.hp)

	# --- flak only shoots aircraft
	s = _sim()
	mid = Vector2(s.map.w * 0.5, s.map.h * 0.5)
	var flak := s.add_unit("flak_gun", 0, _open_spot(s, mid))
	var inf := s.add_unit("rifleman", 1, _open_spot(s, mid + Vector2(3, 0)))
	_check("flak cannot target infantry", not s.can_target(flak, inf))
	var plane := s.add_unit("biplane", 1, mid + Vector2(2, 2))
	plane.state = "move"
	plane.path = PackedVector2Array([mid + Vector2(2, 2)])
	_run(s, 15)
	_check("flak gun engages aircraft", plane.dead or plane.hp < plane.max_hp, "plane hp=%d" % plane.hp)

	# --- bombers flatten buildings
	s = _sim()
	var tgt: Ent = s.buildings.filter(func(b): return b.owner == 1)[0]
	var bm := s.add_unit("bomber", 0, tgt.pos + Vector2(-12, 0))
	for u in s.units.filter(func(u): return u.owner == 1):
		s.kill(u)
	s.cmd_attack([bm], tgt)
	var hp0 := tgt.hp
	_run(s, 20)
	_check("bomber damages town center", tgt.hp < hp0 - 300, "tc hp %d -> %d" % [hp0, tgt.hp])

	# --- ships fight on water
	s = Sim.new({"seed": 5, "players": [{"team": 0, "ai": false}, {"team": 1, "ai": false}], "map_type": "inland_sea", "map_size": "medium", "start_epoch": 3, "resources": "high", "reveal": true})
	s.new_game()
	var c := Vector2i(s.map.w / 2, s.map.h / 2)
	var w1 := s.map.nearest_passable(c, true, 30)
	var w2 := s.map.nearest_passable(c + Vector2i(5, 0), true, 30)
	var sh1 := s.add_unit("frigate", 0, Vector2(w1) + Vector2(0.5, 0.5))
	var sh2 := s.add_unit("galley", 1, Vector2(w2) + Vector2(0.5, 0.5))
	s.cmd_attack([sh1], sh2)
	_run(s, 40)
	_check("frigate sinks galley", sh2.dead, "galley hp=%d" % sh2.hp)
	_check("ships stay on water", s.map.swimmable(int(sh1.pos.x), int(sh1.pos.y)))

	# --- fishing boat gathers fish and returns to a dock
	var fish: Ent = null
	for r in s.resources:
		if r.type == "fish":
			fish = r
			break
	var dock_spot := Vector2i(-1, -1)
	for y in s.map.h:
		for x in s.map.w:
			if dock_spot.x < 0 and s.can_place("dock", x, y, 0) and Vector2(x, y).distance_to(fish.pos) < 25:
				dock_spot = Vector2i(x, y)
	_check("found a dock site", dock_spot.x >= 0)
	if dock_spot.x >= 0:
		var dock := s.add_building("dock", 0, dock_spot.x, dock_spot.y, true)
		var boat := s._spawn_from(dock, "fishing_boat")
		s.cmd_gather([boat], fish)
		var food0: float = s.players[0].res.food
		_run(s, 90)
		_check("fishing boat delivers fish", s.players[0].res.food > food0, "food %d -> %d" % [food0, s.players[0].res.food])

	# --- priest converts an enemy soldier
	s = _sim(2)
	mid = _open_spot(s, Vector2(s.map.w * 0.5, s.map.h * 0.5))
	var pr := s.add_unit("priest", 0, mid)
	var victim := s.add_unit("swordsman", 1, _open_spot(s, mid + Vector2(3, 0)))
	victim.stance = "hold"
	s.cmd_convert([pr], victim)
	_run(s, 20)
	_check("priest converts swordsman", victim.owner == 0, "owner=%d" % victim.owner)

	# --- priest heals
	var hurt := s.add_unit("swordsman", 0, _open_spot(s, mid + Vector2(-2, 0)))
	hurt.hp = 30
	pr.state = "idle"
	_run(s, 12)
	_check("priest heals wounded ally", hurt.hp > 60, "hp=%d" % hurt.hp)

	# --- hero aura boosts allies
	s = _sim(2)
	mid = _open_spot(s, Vector2(s.map.w * 0.5, s.map.h * 0.5))
	var hero := s.add_unit("paladin", 0, mid)
	var sw := s.add_unit("swordsman", 0, _open_spot(s, mid + Vector2(1.5, 0)))
	var base_atk := s.u_atk(sw)
	_run(s, 1)
	_check("hero aura raises attack", s.u_atk(sw) > base_atk, "%.1f -> %.1f" % [base_atk, s.u_atk(sw)])
	_check("only one hero at a time", s.train(s.buildings.filter(func(b): return b.owner == 0)[0], "paladin") is String)

	# --- research applies modifiers
	s = _sim(1)
	var tc: Ent = s.buildings.filter(func(b): return b.owner == 0)[0]
	var cit: Ent = s.units.filter(func(u): return u.owner == 0 and u.def.cls == "citizen")[0]
	var ac := s.add_building("academy", 0, tc.tx + 6, tc.ty, true)
	var sp := s.add_unit("spearman", 0, _open_spot(s, tc.pos + Vector2(0, 5)))
	var a0 := s.u_atk(sp)
	_check("research starts", s.research(ac, "weapons1") == true)
	_run(s, 35)
	_check("Bronze Weapons raises attack 15%", absf(s.u_atk(sp) - a0 * 1.15) < 0.01, "%.2f -> %.2f" % [a0, s.u_atk(sp)])
	_check("Wheelbarrow requires its epoch and building", s.research(ac, "wheelbarrow") is String)

	# --- walls block movement
	s = _sim(1)
	tc = s.buildings.filter(func(b): return b.owner == 0)[0]
	cit = s.units.filter(func(u): return u.owner == 0 and u.def.cls == "citizen")[0]
	var a := Vector2i(tc.tx - 4, tc.ty + 6)
	var b := Vector2i(tc.tx + 7, tc.ty + 6)
	var r = s.place_wall(0, a, b, [cit])
	_check("wall line placed", r is int and r >= 8, str(r))
	for w in s.buildings.filter(func(x): return x.type == "wall"):
		w.built = true
		w.progress = 1.0
	_check("walls are solid", not s.map.walkable(tc.tx, tc.ty + 6))

	# --- elevation bonus
	s = _sim(1)
	var e1 := s.add_unit("archer", 0, Vector2(10.5, 10.5))
	var e2 := s.add_unit("clubman", 1, Vector2(12.5, 10.5))
	var hp_before := e2.hp
	s.damage(e1.id, 0, e1.def, e2, 10.0, s.height_of(e2) + 2.0)
	var high_dmg := hp_before - e2.hp
	hp_before = e2.hp
	s.damage(e1.id, 0, e1.def, e2, 10.0, s.height_of(e2))
	var flat_dmg := hp_before - e2.hp
	_check("high ground deals more damage", high_dmg > flat_dmg, "%.1f vs %.1f" % [high_dmg, flat_dmg])

	print("SCENARIOS DONE, failures=%d" % fails)
	quit()
