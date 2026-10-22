class_name Controller
extends Node
## Player input: selection, orders, building placement, control groups and camera control.

var game  # Main node (sim, view, cam, hud, sfx)
var sel: Array = []
var sel_set := {}
var placing := ""
var wall_start := Vector2i(-1, -1)
var mode := ""
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var dragging := false
var drag_active := false
var rotating := false
var groups := {}
var _last_click_t := 0
var _last_click_id := 0
var _last_group := ""
var _last_group_t := 0
var _idle_i := 0
var mouse_ground := Vector2.ZERO

func sim() -> Sim:
	return game.sim

# ------------------------------------------------------------------ selection
func set_sel(ids: Array) -> void:
	sel = ids.slice(0, 80)
	sel_set.clear()
	for id in sel:
		sel_set[id] = true
	if game.hud:
		game.hud.selection_changed()

func sel_ents() -> Array:
	var out = []
	for id in sel:
		var e = sim().get_ent(id)
		if e:
			out.append(e)
	return out

func sel_units() -> Array:
	return sel_ents().filter(func(e): return e.kind == Ent.UNIT and e.owner == 0)

func sel_building() -> Ent:
	var es = sel_ents()
	if es.size() == 1 and es[0].kind == Ent.BUILDING and es[0].owner == 0:
		return es[0]
	return null

func prune() -> void:
	var alive = sel.filter(func(id): return sim().get_ent(id) != null and sim().get_ent(id).owner == sim().get_ent(id).owner)
	if alive.size() != sel.size():
		set_sel(alive)
	# converted units leave the selection
	var own = sel_ents()
	if own.size() > 1 and own.any(func(e): return e.owner != 0):
		set_sel(own.filter(func(e): return e.owner == 0).map(func(e): return e.id))

func _screen_of(p3: Vector3) -> Vector2:
	return game.cam.cam.unproject_position(p3)

func _unit_world(u: Ent) -> Vector3:
	var y = sim().map.height_at(u.pos) + 0.7
	if u.def.get("air", false):
		y = maxf(sim().map.height_at(u.pos), 0.0) + WorldView.AIR_ALT
	elif u.def.get("naval", false):
		y = WorldView.WATER_Y + 0.6
	return Vector3(u.pos.x * WorldView.TILE, y, u.pos.y * WorldView.TILE)

func _px_radius(world_r: float, p3: Vector3) -> float:
	var c: Camera3D = game.cam.cam
	var d = c.global_position.distance_to(p3)
	var vh = get_viewport().get_visible_rect().size.y
	return world_r / maxf(d, 0.1) * vh / (2.0 * tan(deg_to_rad(c.fov) * 0.5))

func pick_at(screen: Vector2) -> Ent:
	var s = sim()
	var c: Camera3D = game.cam.cam
	var best: Ent = null
	var bd = 1e9
	for u in s.units:
		if u.dead or not (s.is_ally(0, u.owner) or s.visible(u)):
			continue
		var p3 = _unit_world(u)
		if c.is_position_behind(p3):
			continue
		var sp = _screen_of(p3)
		var r = maxf(12.0, _px_radius(u.def.r * WorldView.TILE * 1.8, p3))
		var d = sp.distance_to(screen)
		if d < r and d < bd:
			bd = d
			best = u
	if best:
		return best
	var g = mouse_tile(screen)
	var gt = Vector2i(g)
	for b in s.buildings:
		if b.dead or not (s.is_ally(0, b.owner) or s.is_explored(b)):
			continue
		if gt.x >= b.tx and gt.y >= b.ty and gt.x < b.tx + b.size and gt.y < b.ty + b.size:
			return b
	# tall buildings: test their projected centre
	for b in s.buildings:
		if b.dead or not (s.is_ally(0, b.owner) or s.is_explored(b)):
			continue
		var p3 = Vector3(b.pos.x * 2.0, s.map.height_at(b.pos) + 1.5, b.pos.y * 2.0)
		if c.is_position_behind(p3):
			continue
		var d = _screen_of(p3).distance_to(screen)
		var r = _px_radius(b.size * 0.8, p3)
		if d < r and d < bd:
			bd = d
			best = b
	if best:
		return best
	if not s.map.inb(gt.x, gt.y) or (s.explored[gt.y * s.map.w + gt.x] == 0 and not s.reveal):
		return null
	var r: Ent = s.res_at.get(s.map.idx(gt.x, gt.y))
	if r:
		return r
	# trees are tall; also check the tile in front
	for dy in [0, 1]:
		for dx in [-1, 0, 1]:
			var rr: Ent = s.res_at.get(s.map.idx(clampi(gt.x + dx, 0, s.map.w - 1), clampi(gt.y + dy, 0, s.map.h - 1)))
			if rr and rr.type == "tree":
				var p3 = Vector3(rr.pos.x * 2.0, s.map.height_at(rr.pos) + 2.0, rr.pos.y * 2.0)
				if _screen_of(p3).distance_to(screen) < _px_radius(1.4, p3):
					return rr
	return null

func mouse_tile(screen: Vector2) -> Vector2:
	var p: Vector3 = game.cam.ground_at(screen)
	return Vector2(p.x / WorldView.TILE, p.z / WorldView.TILE)

func click_select(screen: Vector2, shift: bool) -> void:
	var t = pick_at(screen)
	var now = Time.get_ticks_msec()
	if t == null:
		if not shift:
			set_sel([])
		return
	if t.kind == Ent.UNIT and t.owner == 0 and now - _last_click_t < 350 and _last_click_id == t.id:
		var vr = get_viewport().get_visible_rect()
		var ids = []
		for u in sim().units:
			if u.owner == 0 and u.type == t.type and vr.has_point(_screen_of(_unit_world(u))):
				ids.append(u.id)
		set_sel(ids)
	elif shift and t.kind == Ent.UNIT and t.owner == 0 and sel_units().size():
		if sel_set.has(t.id):
			set_sel(sel.filter(func(id): return id != t.id))
		else:
			set_sel(sel + [t.id])
	else:
		set_sel([t.id])
	game.sfx.play("click", 0.5)
	_last_click_t = now
	_last_click_id = t.id

func box_select(a: Vector2, b: Vector2, shift: bool) -> void:
	var r = Rect2(a, b - a).abs().grow(4)
	var ids = []
	var c: Camera3D = game.cam.cam
	for u in sim().units:
		if u.owner != 0 or u.dead:
			continue
		var p3 = _unit_world(u)
		if not c.is_position_behind(p3) and r.has_point(_screen_of(p3)):
			ids.append(u.id)
	if ids.is_empty():
		return
	if shift:
		for id in sel:
			if not ids.has(id):
				ids.append(id)
	set_sel(ids)
	game.sfx.play("click", 0.5)

# ------------------------------------------------------------------ orders
func right_click(screen: Vector2) -> void:
	var s = sim()
	if placing != "" or mode != "":
		placing = ""
		mode = ""
		wall_start = Vector2i(-1, -1)
		return
	var g = mouse_tile(screen)
	var own = sel_units()
	var t = pick_at(screen)
	if own.is_empty():
		var b = sel_building()
		if b and b.built and Defs.PRODUCTION.has(b.type):
			s.set_rally(b, g, t)
			game.view.marker(g, Color("#93c5fd"))
		return
	if t and t.kind != Ent.RES and s.is_enemy(0, t.owner):
		s.cmd_attack(own, t)
		var rest = own.filter(func(u): return u.state != "attack" and u.state != "convert")
		if rest.size():
			s.cmd_move(rest, t.pos)
		game.view.marker(t.pos, Color("#f87171"))
		return
	if t and t.kind == Ent.RES:
		s.cmd_gather(own, t)
		game.view.marker(t.pos, Color("#fbbf24"))
		return
	if t and t.kind == Ent.BUILDING and s.is_ally(0, t.owner):
		var cits = own.filter(func(u): return u.def.cls == "citizen")
		var rest = own.filter(func(u): return u.def.cls != "citizen")
		if cits.size() and t.owner == 0:
			if not t.built or (t.hp < t.max_hp and not t.def.get("farm", false)):
				s.cmd_build(cits, t)
			elif t.def.get("farm", false):
				s.cmd_gather(cits, t)
			elif t.def.get("dropoff", false) and cits.any(func(c): return c.carry > 0):
				s.cmd_return(cits.filter(func(c): return c.carry > 0), t)
				var o = cits.filter(func(c): return c.carry <= 0)
				if o.size():
					s.cmd_move(o, g)
			else:
				s.cmd_move(cits, g)
		elif cits.size():
			s.cmd_move(cits, g)
		var boats = rest.filter(func(u): return u.type == "fishing_boat" and u.carry > 0 and t.def.get("naval", false))
		if boats.size():
			s.cmd_return(boats, t)
			rest = rest.filter(func(u): return not boats.has(u))
		if rest.size():
			s.cmd_move(rest, g)
		game.view.marker(t.pos, Color("#4ade80"))
		return
	if t and t.kind == Ent.UNIT and s.is_ally(0, t.owner) and t.hp < t.max_hp:
		var healers = own.filter(func(u): return u.def.get("heal", 0.0) > 0.0 and u != t)
		if healers.size():
			s.cmd_heal(healers, t)
			var rest = own.filter(func(u): return not healers.has(u))
			if rest.size():
				s.cmd_move(rest, g)
			game.view.marker(t.pos, Color("#86efac"))
			return
	s.cmd_move(own, g)
	game.view.marker(g, Color("#4ade80"))

func attack_move_at(screen: Vector2) -> void:
	var s = sim()
	var t = pick_at(screen)
	var own = sel_units()
	if t and t.kind != Ent.RES and s.is_enemy(0, t.owner):
		s.cmd_attack(own, t)
	else:
		s.cmd_move(own, mouse_tile(screen), true)
	game.view.marker(mouse_tile(screen), Color("#f87171"))

func start_placing(type: String) -> void:
	var p: Sim.Player = sim().players[0]
	var def: Dictionary = Defs.BUILDINGS[type]
	if def.epoch > p.epoch:
		game.hud.flash("Requires the " + Defs.EPOCHS[def.epoch].name)
		return
	if not Defs.can_afford(p.res, def.cost):
		game.hud.flash("Not enough " + Defs.missing(p.res, def.cost))
		return
	placing = type
	mode = ""
	wall_start = Vector2i(-1, -1)

func _place_tile(type: String, g: Vector2) -> Vector2i:
	var size: int = Defs.BUILDINGS[type].size
	return Vector2i(floori(g.x - size * 0.5 + 0.5), floori(g.y - size * 0.5 + 0.5))

func try_place(screen: Vector2, shift: bool) -> void:
	var t = _place_tile(placing, mouse_tile(screen))
	var builders = sel_units().filter(func(u): return u.def.cls == "citizen")
	var r = sim().place_building(0, placing, t.x, t.y, builders)
	if r is String:
		game.hud.flash(r)
		return
	game.sfx.play("hammer", 0.6)
	if not shift or not Defs.can_afford(sim().players[0].res, Defs.BUILDINGS[placing].cost):
		placing = ""

func finish_wall(screen: Vector2) -> void:
	var end = Vector2i(mouse_tile(screen))
	var builders = sel_units().filter(func(u): return u.def.cls == "citizen")
	var r = sim().place_wall(0, wall_start, end, builders)
	wall_start = Vector2i(-1, -1)
	if r is String:
		game.hud.flash(r)
		return
	game.sfx.play("hammer", 0.6)
	if not Input.is_key_pressed(KEY_SHIFT):
		placing = ""

func wall_tiles(a: Vector2i, b: Vector2i) -> Array:
	var n = maxi(absi(b.x - a.x), absi(b.y - a.y))
	var out = []
	for k in n + 1:
		var t = Vector2i(Vector2(a).lerp(Vector2(b), float(k) / maxf(n, 1)).round())
		if not out.has(t):
			out.append(t)
	return out

func select_idle() -> void:
	var idle = sim().units.filter(func(u): return u.owner == 0 and u.def.cls == "citizen" and u.state == "idle")
	if idle.is_empty():
		return
	var u: Ent = idle[_idle_i % idle.size()]
	_idle_i += 1
	set_sel([u.id])
	game.cam.center_on(WorldView.to3(u.pos, 0))

func select_military() -> void:
	var ids = sim().units.filter(func(u): return u.owner == 0 and u.def.cls != "citizen" and u.type != "fishing_boat").map(func(u): return u.id)
	set_sel(ids)

func go_home(select: bool) -> void:
	for b in sim().buildings:
		if b.owner == 0 and b.type == "town_center":
			if select:
				set_sel([b.id])
			game.cam.center_on(WorldView.to3(b.pos, 0))
			return

# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if game.sim == null or game.menu_open:
		return
	var s = sim()
	if ev is InputEventMouseButton:
		var mb = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			game.cam.zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			game.cam.zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = mb.pressed
		if s.over:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if placing == "wall":
					wall_start = Vector2i(mouse_tile(mb.position))
				elif placing != "":
					try_place(mb.position, mb.shift_pressed)
				elif mode == "amove":
					attack_move_at(mb.position)
					if not mb.shift_pressed:
						mode = ""
				else:
					dragging = true
					drag_active = false
					drag_start = mb.position
					drag_cur = mb.position
			else:
				if placing == "wall" and wall_start.x >= 0:
					finish_wall(mb.position)
				elif dragging:
					if drag_active:
						box_select(drag_start, mb.position, mb.shift_pressed)
					else:
						click_select(mb.position, mb.shift_pressed)
				dragging = false
				drag_active = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			right_click(mb.position)
	elif ev is InputEventMouseMotion:
		var mm = ev as InputEventMouseMotion
		if rotating:
			game.cam.rotate_by(-mm.relative.x * 0.006, mm.relative.y * 0.004)
		if dragging:
			drag_cur = mm.position
			if drag_cur.distance_to(drag_start) > 6.0:
				drag_active = true
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_on_key(ev as InputEventKey)

func _on_key(k: InputEventKey) -> void:
	var s = sim()
	match k.keycode:
		KEY_ESCAPE:
			if placing != "" or mode != "":
				placing = ""; mode = ""; wall_start = Vector2i(-1, -1)
			elif game.hud.close_overlays():
				pass
			else:
				set_sel([])
			return
		KEY_F1:
			game.hud.toggle_help(); return
		KEY_F2:
			game.hud.toggle_tree(); return
		KEY_F5:
			game.save_game(); return
		KEY_F9:
			game.load_game(); return
		KEY_P, KEY_PAUSE:
			game.toggle_pause(); return
		KEY_HOME:
			game.cam.yaw = 0.0; game.cam.pitch = deg_to_rad(52.0); game.cam.apply(); return
		KEY_PAGEUP:
			game.cam.rotate_by(0.3, 0.0); return
		KEY_PAGEDOWN:
			game.cam.rotate_by(-0.3, 0.0); return
	if s.over:
		return
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		var n = str(k.keycode - KEY_0)
		if k.ctrl_pressed or k.meta_pressed:
			groups[n] = sel.duplicate()
			game.hud.flash("Group %s set." % n, Color("#93c5fd"))
		elif groups.has(n):
			var ids: Array = groups[n].filter(func(id): return s.get_ent(id) != null and s.get_ent(id).owner == 0)
			var now = Time.get_ticks_msec()
			if _last_group == n and now - _last_group_t < 400 and ids.size():
				game.cam.center_on(WorldView.to3(s.get_ent(ids[0]).pos, 0))
			_last_group = n
			_last_group_t = now
			set_sel(ids)
		return
	match k.keycode:
		KEY_PERIOD:
			select_idle(); return
		KEY_COMMA:
			select_military(); return
		KEY_H:
			go_home(true); return
		KEY_SPACE:
			go_home(false); return
	var key = OS.get_keycode_string(k.keycode).to_upper()
	if k.keycode == KEY_DELETE:
		key = "DEL"
	game.hud.hotkey(key, k.shift_pressed)

func _process(delta: float) -> void:
	if game.sim == null or game.menu_open:
		return
	var vp = get_viewport()
	var mp = vp.get_mouse_position()
	var size = vp.get_visible_rect().size
	var dx = 0.0
	var dz = 0.0
	if Input.is_key_pressed(KEY_LEFT): dx -= 1
	if Input.is_key_pressed(KEY_RIGHT): dx += 1
	if Input.is_key_pressed(KEY_UP): dz += 1
	if Input.is_key_pressed(KEY_DOWN): dz -= 1
	if DisplayServer.window_is_focused() and not dragging and Rect2(Vector2.ZERO, size).has_point(mp):
		var m = 6.0
		if mp.x < m: dx -= 1
		if mp.x > size.x - m: dx += 1
		if mp.y < m: dz += 1
		if mp.y > size.y - m: dz -= 1
	if dx != 0.0 or dz != 0.0:
		game.cam.pan(dx * 40.0 * delta, dz * 40.0 * delta)
	mouse_ground = mouse_tile(mp)
	# placement ghosts
	if placing != "":
		if placing == "wall" and wall_start.x >= 0:
			var tiles = wall_tiles(wall_start, Vector2i(mouse_ground))
			var oks = tiles.map(func(t): return sim().can_place("wall", t.x, t.y, 0))
			game.view.set_ghosts("wall", tiles, oks)
		else:
			var t = _place_tile(placing, mouse_ground)
			game.view.set_ghosts(placing, [t], [sim().can_place(placing, t.x, t.y, 0)])
	else:
		game.view.set_ghosts("house", [], [])
	game.view.show_rally(sel_building())
	prune()
