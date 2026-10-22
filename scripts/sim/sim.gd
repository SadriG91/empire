class_name Sim
extends RefCounted
## Core simulation: players, entities, orders, economy, combat, epochs, research and victory.

const GATHER_RATE := {"food": 0.6, "wood": 0.5, "stone": 0.42, "gold": 0.42}
const FISH_RATE := 0.7
const FARM_RATE := 0.45
const RES_AMOUNT := {"tree": 100, "berries": 150, "stone": 250, "gold": 300, "fish": 250}
const RES_KIND := {"tree": "wood", "berries": "food", "stone": "stone", "gold": "gold", "fish": "food"}
const PROJ_SPEED := {"arrow": 13.0, "stone": 10.0, "bullet": 28.0, "grenade": 9.0, "boulder": 8.0, "ball": 13.0, "shell": 14.0, "rocket": 12.0, "flak": 20.0, "bomb": 6.0}
const START_RES := {"standard": {"food": 200, "wood": 250, "stone": 150, "gold": 100}, "high": {"food": 1000, "wood": 1000, "stone": 800, "gold": 800}}
const AURA_R := 6.0

class Player:
	var id = 0
	var name = ""
	var color = Color.WHITE
	var team = 0
	var is_ai = false
	var personality = "balanced"
	var res = {}
	var epoch = 0
	var advancing = false
	var pop = 0
	var pop_cap = 0
	var gather_mult = 1.0
	var stats = {"trained": 0, "lost": 0, "killed": 0, "gathered": 0, "built": 0, "techs": 0, "kill_value": 0}
	var techs = {}
	var researching = {}
	var mods = {"atk": {}, "armor": {}, "range": {}, "speed": {}, "gather": {}, "carry": 0, "bld_hp": 0.0, "bld_armor": 0, "heal": 0.0, "regen": 0.0, "convert": 0.0}
	var wonder_t = -1.0
	var defeated = false
	var score_hist: Array = []

var settings: Dictionary
var map: WorldMap
var rng := RandomNumberGenerator.new()
var seed_value := 0
var diff := "normal"
var players: Array = []
var ents := {}
var units: Array = []
var buildings: Array = []
var resources: Array = []
var res_at := {}            # tile index -> resource ent
var projectiles: Array = []
var fx: Array = []          # one-shot events for view/audio
var messages: Array = []
var pings: Array = []
var ais: Array = []
var time := 0.0
var next_id := 1
var over := false
var winner_team := -1
var win_how := ""
var vis := PackedByteArray()
var explored := PackedByteArray()
var vis_version := 0
var reveal := false
var max_pop := 200
var starts: Array = []
var _vis_t := 0.0
var _check_t := 0.0
var _aura_t := 0.0
var _score_t := 0.0
var _dirty := false
var _alert_t := {}
var _ub := {}               # unit buckets (8x8 tiles) for queries
var _sb := {}               # 1x1 buckets for separation

# ======================================================================== setup
func _init(s: Dictionary) -> void:
	settings = s
	seed_value = int(s.get("seed", randi()))
	rng.seed = seed_value
	diff = s.get("difficulty", "normal")
	reveal = s.get("reveal", false)
	max_pop = int(s.get("pop_cap", 200))
	var n: int = Defs.MAP_SIZES.get(s.get("map_size", "medium"), 96)
	map = WorldMap.new(n, n)
	vis.resize(n * n)
	explored.resize(n * n)

func new_game() -> void:
	var pl: Array = settings.get("players", [{"team": 0, "ai": false}, {"team": 1, "ai": true}])
	var n = map.w
	var corners = [Vector2(14.5, 14.5), Vector2(n - 14.5, n - 14.5), Vector2(n - 14.5, 14.5), Vector2(14.5, n - 14.5)]
	if rng.randf() < 0.5:
		corners = [corners[2], corners[3], corners[0], corners[1]]
	starts = corners.slice(0, pl.size())
	var start_epoch = int(settings.get("start_epoch", 0))
	var base: Dictionary = START_RES.get(settings.get("resources", "standard"), START_RES.standard)
	var d: Dictionary = Defs.DIFFICULTY[diff]
	for i in pl.size():
		var p = Player.new()
		p.id = i
		p.name = Defs.PLAYER_NAMES[i]
		p.color = Defs.PLAYER_COLORS[i]
		p.team = int(pl[i].get("team", i))
		p.is_ai = pl[i].get("ai", i != 0)
		p.personality = pl[i].get("personality", "balanced")
		p.epoch = start_epoch
		for k in Defs.RES:
			p.res[k] = float(base[k] + start_epoch * 400 + (d.bonus if p.is_ai else 0))
		p.gather_mult = d.gather if p.is_ai else 1.0
		players.append(p)
	map.generate(self, rng, settings.get("map_type", "lakes"), starts)
	for i in pl.size():
		var s: Vector2 = starts[i]
		add_building("town_center", i, int(s.x) - 1, int(s.y) - 1, true)
		for o in [Vector2(-2, 2), Vector2(0, 2.2), Vector2(2, 2), Vector2(2.2, 0), Vector2(-2.2, 0)]:
			add_unit("citizen", i, s + o)
		add_unit(Defs.line_unit("barracks", 0, start_epoch), i, s + Vector2(2, -2))
		if start_epoch >= 1:
			add_unit("citizen", i, s + Vector2(-2, -2))
			add_unit("citizen", i, s + Vector2(0, -2.2))
	for p in players:
		if p.is_ai:
			ais.append(AIPlayer.new(self, p.id))
	update_pop_caps()
	update_vis()

# ======================================================================== entities
func add_unit(type: String, owner: int, p: Vector2) -> Ent:
	var e = Ent.new()
	e.id = next_id; next_id += 1
	e.kind = Ent.UNIT
	e.type = type
	e.def = Defs.UNITS[type]
	e.owner = owner
	e.pos = p; e.prev = p
	e.hp = e.def.hp; e.max_hp = e.def.hp
	e.facing = PI * 0.5
	e.scan_t = rng.randf() * 0.5
	units.append(e)
	ents[e.id] = e
	players[owner].pop += 1
	return e

func bld_max_hp(owner: int, def: Dictionary) -> float:
	return def.hp * (1.0 + players[owner].mods.bld_hp)

func add_building(type: String, owner: int, tx: int, ty: int, built: bool) -> Ent:
	var def: Dictionary = Defs.BUILDINGS[type]
	var e = Ent.new()
	e.id = next_id; next_id += 1
	e.kind = Ent.BUILDING
	e.type = type; e.def = def; e.owner = owner
	e.tx = tx; e.ty = ty; e.size = def.size
	e.pos = Vector2(tx + def.size * 0.5, ty + def.size * 0.5); e.prev = e.pos
	e.max_hp = bld_max_hp(owner, def)
	e.hp = e.max_hp if built else maxf(1.0, e.max_hp * 0.05)
	e.built = built
	e.progress = 1.0 if built else 0.0
	var code = WorldMap.FARM if def.get("walkable", false) else WorldMap.BLD
	for y in range(ty, ty + e.size):
		for x in range(tx, tx + e.size):
			map.set_block(x, y, code)
	buildings.append(e)
	ents[e.id] = e
	if code == WorldMap.BLD:
		_evict(e)
	return e

func add_resource(type: String, tx: int, ty: int) -> Ent:
	var i = map.idx(tx, ty)
	var fish = type == "fish"
	if fish and map.block[i] != WorldMap.WATER:
		return null
	if not fish and map.block[i] != WorldMap.FREE:
		return null
	var e = Ent.new()
	e.id = next_id; next_id += 1
	e.kind = Ent.RES
	e.type = type; e.res = RES_KIND[type]
	e.amount = RES_AMOUNT[type]; e.max_amount = e.amount
	e.tx = tx; e.ty = ty; e.size = 1
	e.pos = Vector2(tx + 0.5, ty + 0.5); e.prev = e.pos
	map.set_block(tx, ty, WorldMap.RES)
	resources.append(e)
	ents[e.id] = e
	res_at[i] = e
	return e

func remove_resource_at(x: int, y: int) -> void:
	var e: Ent = res_at.get(map.idx(x, y))
	if e:
		_deplete(e)

func _evict(b: Ent) -> void:
	for u in units:
		var t = Vector2i(u.pos)
		if t.x >= b.tx and t.y >= b.ty and t.x < b.tx + b.size and t.y < b.ty + b.size and not u.def.get("air", false):
			var s = map.nearest_passable(t, u.def.get("naval", false))
			if s.x >= 0:
				u.pos = Vector2(s) + Vector2(0.5, 0.5); u.prev = u.pos
				u.path = PackedVector2Array()

func get_ent(id: int) -> Ent:
	var e: Ent = ents.get(id)
	return e if e and not e.dead else null

func is_enemy(a: int, b: int) -> bool:
	return a != b and a >= 0 and b >= 0 and players[a].team != players[b].team

func is_ally(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and players[a].team == players[b].team

func dist_to(p: Vector2, e: Ent) -> float:
	if e.kind == Ent.UNIT:
		return maxf(0.0, p.distance_to(e.pos) - e.def.r)
	var dx = maxf(maxf(e.tx - p.x, 0.0), p.x - (e.tx + e.size))
	var dy = maxf(maxf(e.ty - p.y, 0.0), p.y - (e.ty + e.size))
	return sqrt(dx * dx + dy * dy)

func nearest_point(e: Ent, p: Vector2) -> Vector2:
	if e.kind == Ent.UNIT:
		return e.pos
	return Vector2(clampf(p.x, e.tx, e.tx + e.size), clampf(p.y, e.ty, e.ty + e.size))

func accessible(e: Ent, naval := false) -> bool:
	for y in range(e.ty - 1, e.ty + e.size + 1):
		for x in range(e.tx - 1, e.tx + e.size + 1):
			var inner = x >= e.tx and y >= e.ty and x < e.tx + e.size and y < e.ty + e.size
			if not inner and map.passable(x, y, naval):
				return true
	return false

func msg(owner: int, text: String, color := Color("#e5e7eb")) -> void:
	if owner != 0:
		return
	messages.append({"text": text, "color": color, "t": time})
	if messages.size() > 6:
		messages.pop_front()

func sfx(sound: String, p: Vector2, global := false) -> void:
	fx.append({"k": "sfx", "s": sound, "p": p, "g": global})

func height_of(e: Ent) -> float:
	return map.height_at(e.pos)

# ======================================================================== stats with modifiers
func u_atk(u: Ent) -> float:
	var p: Player = players[u.owner]
	var a: float = u.def.atk * (1.0 + p.mods.atk.get(u.def.cls, 0.0)) * (1.0 + 0.1 * u.rank())
	if u.buff_t > time:
		a *= 1.2
	return a

func armor_of(e: Ent) -> float:
	var p: Player = players[e.owner] if e.owner >= 0 else null
	if e.kind == Ent.BUILDING:
		return e.def.armor + (p.mods.bld_armor if p else 0)
	var a: float = e.def.armor + (p.mods.armor.get(e.def.cls, 0) if p else 0)
	if e.buff_t > time:
		a += 1
	return a

func u_range(e: Ent) -> float:
	if e.kind == Ent.BUILDING:
		return e.def.get("range", 0.0)
	var r: float = e.def.range
	if r > 1.5:
		r += players[e.owner].mods.range.get(e.def.cls, 0.0)
	return r

func u_speed(u: Ent) -> float:
	return u.def.speed * (1.0 + players[u.owner].mods.speed.get(u.def.cls, 0.0))

func carry_cap(owner: int) -> int:
	return 10 + players[owner].epoch * 2 + int(players[owner].mods.carry)

func can_target(src: Ent, t: Ent) -> bool:
	if t.kind == Ent.RES or t.dead:
		return false
	var sd = src.def
	if t.kind == Ent.UNIT and t.def.get("air", false):
		if src.kind == Ent.BUILDING:
			return sd.has("atk") and players[src.owner].epoch >= 4
		return sd.get("aa", false)
	if sd.get("air_only", false) or sd.get("atk", 0) <= 0:
		return false
	if sd.get("bomber", false) and t.kind == Ent.UNIT and t.def.get("naval", false):
		return true
	if t.kind == Ent.UNIT and t.def.get("naval", false):
		return src.kind == Ent.BUILDING or u_range(src) > 1.5 or sd.get("naval", false)
	return true

# ======================================================================== movement
func _naval(u: Ent) -> bool:
	return u.def.get("naval", false)

func _air(u: Ent) -> bool:
	return u.def.get("air", false)

func path_to(u: Ent, p: Vector2) -> void:
	if _air(u):
		u.path = PackedVector2Array([p]); u.pi = 0
		return
	var nav = _naval(u)
	var from = Vector2i(u.pos)
	var to = Vector2i(p)
	var pts = map.find_path(from, to, nav)
	if map.passable_at(p, nav) and (pts.size() == 0 or Vector2i(pts[pts.size() - 1]) == to):
		if pts.size():
			pts[pts.size() - 1] = p
		else:
			pts.append(p)
	u.path = map.smooth(u.pos, pts, nav)
	u.pi = 0

func path_to_ent(u: Ent, e: Ent, reach: float) -> void:
	u.path_target = e.pos
	if _air(u):
		u.path = PackedVector2Array([nearest_point(e, u.pos)]); u.pi = 0
		return
	var nav = _naval(u)
	# Goal: the passable tile next to the target that is closest to us.
	var goal = Vector2i(-1, -1)
	var bd = 1e9
	var r = 1 if reach < 1.5 else 0
	if e.kind == Ent.UNIT:
		var t = Vector2i(e.pos)
		goal = map.nearest_passable(t, nav, 3) if reach >= 0.5 else t
	else:
		for y in range(e.ty - 1, e.ty + e.size + 1):
			for x in range(e.tx - 1, e.tx + e.size + 1):
				var inner = x >= e.tx and y >= e.ty and x < e.tx + e.size and y < e.ty + e.size
				if inner and not (e.def.get("walkable", false)):
					continue
				if not map.passable(x, y, nav):
					continue
				var d = u.pos.distance_squared_to(Vector2(x + 0.5, y + 0.5))
				if d < bd:
					bd = d
					goal = Vector2i(x, y)
	if r == 0 and e.kind != Ent.UNIT:
		# ranged: aim for a tile on the line between us and the target, inside range
		var c = nearest_point(e, u.pos)
		var dir = (u.pos - c).normalized()
		var cand = Vector2i(c + dir * maxf(reach * 0.7, 1.0))
		if map.passable(cand.x, cand.y, nav):
			goal = cand
	if goal.x < 0:
		goal = Vector2i(e.pos)
		u.fail += 1
	var pts = map.find_path(Vector2i(u.pos), goal, nav)
	if pts.size() == 0 and Vector2i(u.pos) != goal:
		u.fail += 1
	elif pts.size() and Vector2i(pts[pts.size() - 1]) != goal:
		u.fail += 1
	u.path = map.smooth(u.pos, pts, nav)
	u.pi = 0

func step_path(u: Ent, dt: float) -> bool:
	if u.pi >= u.path.size():
		return true
	var target = u.path[u.pi]
	var d = u.pos.distance_to(target)
	var sp = u_speed(u) * dt
	u.moving = true
	if d > 0.001:
		u.facing = atan2(target.y - u.pos.y, target.x - u.pos.x)
	if d <= sp:
		u.pos = target
		u.pi += 1
		return u.pi >= u.path.size()
	u.pos += (target - u.pos) / d * sp
	return false

## Move toward an entity until within reach. Returns true when in range.
func approach(u: Ent, e: Ent, reach: float, dt: float) -> bool:
	if dist_to(u.pos, e) <= reach:
		u.path = PackedVector2Array()
		u.fail = 0
		return true
	u.repath_t -= dt
	var moved = u.path_target.distance_to(e.pos) > 1.5
	var done = u.pi >= u.path.size()
	if (u.path.size() == 0 and moved) or (u.repath_t <= 0.0 and (moved or done)):
		path_to_ent(u, e, reach)
		u.repath_t = 0.7 + rng.randf() * 0.5
	if u.pi < u.path.size():
		step_path(u, dt)
	else:
		var np = nearest_point(e, u.pos)
		var dir = np - u.pos
		var l = dir.length()
		if l > 0.001:
			var p2 = u.pos + dir / l * u_speed(u) * dt
			if _air(u) or map.passable_at(p2, _naval(u)):
				u.pos = p2
				u.facing = atan2(dir.y, dir.x)
				u.moving = true
	return dist_to(u.pos, e) <= reach

# ======================================================================== orders
func formation_spots(t: Vector2i, n: int, naval: bool, air: bool) -> Array:
	var spots = []
	for r in 14:
		if spots.size() >= n:
			break
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x = t.x + dx
				var y = t.y + dy
				if (air and map.inb(x, y)) or map.passable(x, y, naval):
					spots.append(Vector2i(x, y))
	spots.sort_custom(func(a, b): return Vector2(a - t).length_squared() < Vector2(b - t).length_squared())
	return spots

func cmd_move(sel: Array, p: Vector2, amove := false) -> void:
	var us = sel.filter(func(u): return u.kind == Ent.UNIT and not u.dead)
	if us.is_empty():
		return
	p = Vector2(clampf(p.x, 0.5, map.w - 0.5), clampf(p.y, 0.5, map.h - 0.5))
	us.sort_custom(func(a, b): return a.pos.distance_squared_to(p) < b.pos.distance_squared_to(p))
	var groups = {"land": [], "sea": [], "air": []}
	for u in us:
		groups["air" if _air(u) else ("sea" if _naval(u) else "land")].append(u)
	for g in groups:
		var arr: Array = groups[g]
		if arr.is_empty():
			continue
		var spots = formation_spots(Vector2i(p), arr.size(), g == "sea", g == "air")
		for i in arr.size():
			var u: Ent = arr[i]
			var q = p
			if arr.size() > 1 or not (g == "air" or map.passable_at(p, g == "sea")):
				if spots.size():
					var s: Vector2i = spots[i % spots.size()]
					q = Vector2(s) + Vector2(0.5 + rng.randf_range(-0.1, 0.1), 0.5 + rng.randf_range(-0.1, 0.1))
			u.state = "move"; u.target_id = 0; u.build_id = 0; u.fail = 0; u.ordered = true
			u.amove = amove; u.amove_to = q
			u.has_guard = false
			if not amove and u.def.get("gather", false):
				u.gather_type = ""; u.gather_id = 0
			path_to(u, q)

func cmd_attack(sel: Array, e: Ent) -> void:
	for u in sel:
		if u.kind != Ent.UNIT or u.dead or not is_enemy(u.owner, e.owner):
			continue
		if u.def.cls == "priest":
			if u.def.get("convert", false):
				cmd_convert([u], e)
			continue
		if not can_target(u, e):
			continue
		u.state = "attack"; u.target_id = e.id; u.path = PackedVector2Array(); u.amove = false
		u.fail = 0; u.repath_t = 0.0; u.ordered = true; u.has_guard = false

func cmd_convert(sel: Array, e: Ent) -> void:
	if e.kind != Ent.UNIT or e.def.get("hero", false) or _air(e):
		return
	for u in sel:
		if u.def.get("convert", false):
			u.state = "convert"; u.target_id = e.id; u.conv_t = 0.0; u.path = PackedVector2Array(); u.ordered = true; u.fail = 0

func cmd_heal(sel: Array, e: Ent) -> void:
	for u in sel:
		if u.def.get("heal", 0.0) > 0.0 and u != e:
			u.state = "heal"; u.target_id = e.id; u.path = PackedVector2Array(); u.ordered = true; u.fail = 0

func cmd_stop(sel: Array) -> void:
	for u in sel:
		if u.kind == Ent.UNIT:
			u.state = "idle"; u.path = PackedVector2Array(); u.amove = false; u.target_id = 0; u.has_guard = false

func cmd_stance(sel: Array, s: String) -> void:
	for u in sel:
		if u.kind == Ent.UNIT:
			u.stance = s

func farm_taken(f: Ent, by: Ent) -> bool:
	var g = get_ent(f.gatherer_id)
	return g != null and g != by and g.state != "idle" and g.gather_id == f.id

func cmd_gather(sel: Array, e: Ent) -> void:
	var gatherers = []
	var others = []
	for u in sel:
		if u.kind != Ent.UNIT:
			continue
		var ok: bool = u.def.get("gather", false)
		if ok and e.kind == Ent.RES:
			ok = (e.type == "fish") == _naval(u)
		elif ok and e.kind == Ent.BUILDING:
			ok = not _naval(u)
		(gatherers if ok else others).append(u)
	if others.size():
		cmd_move(others, e.pos)
	if e.kind == Ent.BUILDING and not e.built:
		cmd_build(gatherers, e)
		return
	for u in gatherers:
		var tgt = e
		if e.kind == Ent.BUILDING and e.def.get("farm", false):
			if farm_taken(e, u):
				var alt = find_resource_near(u.owner, "food", e.pos, 8.0, 0, false, true)
				if alt:
					tgt = alt
			if tgt.kind == Ent.BUILDING:
				tgt.gatherer_id = u.id
		u.state = "gather"; u.gather_id = tgt.id
		u.gather_type = tgt.res if tgt.kind == Ent.RES else "food"
		u.path = PackedVector2Array(); u.amove = false; u.target_id = 0; u.fail = 0; u.repath_t = 0.0

func cmd_build(sel: Array, b: Ent) -> void:
	for u in sel:
		if u.kind != Ent.UNIT or u.def.cls != "citizen":
			continue
		u.state = "build"; u.build_id = b.id; u.path = PackedVector2Array(); u.amove = false
		u.target_id = 0; u.fail = 0; u.repath_t = 0.0

func cmd_return(sel: Array, drop: Ent) -> void:
	for u in sel:
		if u.def.get("gather", false) and u.carry > 0:
			u.state = "return"; u.drop_id = drop.id; u.path = PackedVector2Array()

func can_place(type: String, tx: int, ty: int, owner: int, margin := 0) -> bool:
	var def: Dictionary = Defs.BUILDINGS[type]
	var s: int = def.size
	if def.get("naval", false):
		var land_n = 0
		var water_n = 0
		for y in range(ty - 1, ty + s + 1):
			for x in range(tx - 1, tx + s + 1):
				if not map.inb(x, y):
					return false
				var inner = x >= tx and y >= ty and x < tx + s and y < ty + s
				if inner:
					if map.block[map.idx(x, y)] != WorldMap.WATER:
						return false
					if owner == 0 and not reveal and explored[map.idx(x, y)] == 0:
						return false
				elif map.walkable(x, y):
					land_n += 1
				elif map.swimmable(x, y):
					water_n += 1
		return land_n > 0 and water_n > 0
	for y in range(ty - margin, ty + s + margin):
		for x in range(tx - margin, tx + s + margin):
			if not map.inb(x, y):
				return false
			var inner = x >= tx and y >= ty and x < tx + s and y < ty + s
			var bl = map.block[map.idx(x, y)]
			if inner:
				if bl != WorldMap.FREE:
					return false
				if owner == 0 and not reveal and explored[map.idx(x, y)] == 0:
					return false
			elif bl != WorldMap.FREE and bl != WorldMap.FARM:
				return false
	for u in units:
		if u.dead or not is_enemy(owner, u.owner) or _air(u):
			continue
		var t = Vector2i(u.pos)
		if t.x >= tx and t.y >= ty and t.x < tx + s and t.y < ty + s:
			return false
	return true

## Returns the new building, or an error string.
func place_building(owner: int, type: String, tx: int, ty: int, builders: Array):
	var p: Player = players[owner]
	var def: Dictionary = Defs.BUILDINGS[type]
	if def.epoch > p.epoch:
		return "Requires the " + Defs.EPOCHS[def.epoch].name
	if not can_place(type, tx, ty, owner):
		return "Cannot build there"
	if type == "wonder":
		for b in buildings:
			if b.owner == owner and b.type == "wonder" and not b.dead:
				return "Only one Wonder allowed"
	if not Defs.can_afford(p.res, def.cost):
		return "Not enough " + Defs.missing(p.res, def.cost)
	_pay(p, def.cost)
	var b = add_building(type, owner, tx, ty, false)
	cmd_build(builders, b)
	return b

## Builds a line of wall segments from a to b. Returns number placed or an error string.
func place_wall(owner: int, a: Vector2i, b: Vector2i, builders: Array):
	var p: Player = players[owner]
	var def: Dictionary = Defs.BUILDINGS["wall"]
	if def.epoch > p.epoch:
		return "Requires the " + Defs.EPOCHS[def.epoch].name
	var n = maxi(absi(b.x - a.x), absi(b.y - a.y))
	var placed: Array = []
	var seen = {}
	for k in n + 1:
		var t = Vector2i(Vector2(a).lerp(Vector2(b), float(k) / maxf(n, 1)).round())
		if seen.has(t):
			continue
		seen[t] = true
		if not can_place("wall", t.x, t.y, owner) or not Defs.can_afford(p.res, def.cost):
			continue
		_pay(p, def.cost)
		placed.append(add_building("wall", owner, t.x, t.y, false))
	if placed.is_empty():
		return "Cannot build a wall there"
	cmd_build(builders, placed[0])
	return placed.size()

func trainable(b: Ent) -> Array:
	var out = []
	if not b.built or not Defs.PRODUCTION.has(b.type):
		return out
	var ep: int = players[b.owner].epoch
	for row in Defs.PRODUCTION[b.type]:
		var t = row[mini(ep, row.size() - 1)]
		if t != null:
			out.append(t)
	return out

func has_hero(owner: int) -> bool:
	for u in units:
		if not u.dead and u.owner == owner and u.def.get("hero", false):
			return true
	for b in buildings:
		if not b.dead and b.owner == owner:
			for q in b.queue:
				if Defs.UNITS.has(q.type) and Defs.UNITS[q.type].get("hero", false):
					return true
	return false

## Returns true or an error string.
func train(b: Ent, type: String):
	var p: Player = players[b.owner]
	var def: Dictionary = Defs.UNITS[type]
	if not trainable(b).has(type):
		return "Not available"
	if b.queue.size() >= 8:
		return "Queue is full"
	if def.get("hero", false) and has_hero(b.owner):
		return "Only one hero at a time"
	if not Defs.can_afford(p.res, def.cost):
		return "Not enough " + Defs.missing(p.res, def.cost)
	_pay(p, def.cost)
	b.queue.append({"type": type, "t": 0.0, "time": float(def.time)})
	return true

func tech_available(b: Ent, key: String) -> bool:
	var t: Dictionary = Defs.TECHS[key]
	var p: Player = players[b.owner]
	return b.built and t.at.has(b.type) and t.epoch <= p.epoch and not p.techs.has(key) and not p.researching.has(key) \
		and (not t.has("req") or p.techs.has(t.req))

func techs_for(b: Ent) -> Array:
	var out = []
	var p: Player = players[b.owner]
	for k in Defs.TECHS:
		var t: Dictionary = Defs.TECHS[k]
		if t.at.has(b.type) and not p.techs.has(k) and not p.researching.has(k) and (not t.has("req") or p.techs.has(t.req)):
			out.append(k)
	return out

func research(b: Ent, key: String):
	var p: Player = players[b.owner]
	var t: Dictionary = Defs.TECHS[key]
	if not tech_available(b, key):
		return "Requires the " + Defs.EPOCHS[t.epoch].name if t.epoch > p.epoch else "Not available"
	if b.queue.size() >= 8:
		return "Queue is full"
	if not Defs.can_afford(p.res, t.cost):
		return "Not enough " + Defs.missing(p.res, t.cost)
	_pay(p, t.cost)
	p.researching[key] = true
	b.queue.append({"type": "#" + key, "t": 0.0, "time": float(t.time)})
	return true

func advance(b: Ent):
	var p: Player = players[b.owner]
	if p.epoch + 1 >= Defs.EPOCHS.size():
		return "Final epoch reached"
	var nxt: Dictionary = Defs.EPOCHS[p.epoch + 1]
	if b.type != "town_center" or not b.built:
		return "Need a Town Center"
	if p.advancing:
		return "Already advancing"
	if not Defs.can_afford(p.res, nxt.cost):
		return "Not enough " + Defs.missing(p.res, nxt.cost)
	_pay(p, nxt.cost)
	p.advancing = true
	b.queue.append({"type": "@epoch", "t": 0.0, "time": nxt.time})
	msg(b.owner, "Advancing to the %s..." % nxt.name, Color("#a5b4fc"))
	return true

func cancel_queue(b: Ent, i: int) -> void:
	if i < 0 or i >= b.queue.size():
		return
	var q: Dictionary = b.queue[i]
	var p: Player = players[b.owner]
	if q.type == "@epoch":
		_refund(p, Defs.EPOCHS[p.epoch + 1].cost)
		p.advancing = false
	elif q.type.begins_with("#"):
		var k: String = q.type.substr(1)
		_refund(p, Defs.TECHS[k].cost)
		p.researching.erase(k)
	else:
		_refund(p, Defs.UNITS[q.type].cost)
	b.queue.remove_at(i)

func set_rally(b: Ent, p: Vector2, target: Ent) -> void:
	b.rally = p; b.has_rally = true
	b.rally_id = target.id if target else 0

func _pay(p: Player, cost: Dictionary) -> void:
	for k in cost:
		p.res[k] -= cost[k]

func _refund(p: Player, cost: Dictionary, f := 1.0) -> void:
	for k in cost:
		p.res[k] += floorf(cost[k] * f)

# ======================================================================== queries
func _bucket_key(x: int, y: int) -> int:
	return y * 4096 + x

func _rebuild_buckets() -> void:
	_ub.clear()
	for u in units:
		if u.dead:
			continue
		var k = _bucket_key(int(u.pos.x) >> 3, int(u.pos.y) >> 3)
		if _ub.has(k):
			_ub[k].append(u)
		else:
			_ub[k] = [u]

func units_near(p: Vector2, r: float) -> Array:
	var out = []
	var x0 = int(p.x - r) >> 3
	var x1 = int(p.x + r) >> 3
	var y0 = int(p.y - r) >> 3
	var y1 = int(p.y + r) >> 3
	for by in range(y0, y1 + 1):
		for bx in range(x0, x1 + 1):
			var a = _ub.get(_bucket_key(bx, by))
			if a:
				out.append_array(a)
	return out

func find_target(src: Ent, rad: float, units_only := false) -> Ent:
	var best: Ent = null
	var bs = 1e9
	var p = src.pos
	for u in units_near(p, rad + 1.0):
		if u.dead or not is_enemy(src.owner, u.owner) or not can_target(src, u):
			continue
		var d = p.distance_to(u.pos) - u.def.r
		if d > rad:
			continue
		var s = d + (1.0 if u.def.cls == "citizen" else 0.0)
		if s < bs:
			bs = s
			best = u
	if units_only or best:
		return best
	for b in buildings:
		if b.dead or not is_enemy(src.owner, b.owner) or not can_target(src, b):
			continue
		var d = dist_to(p, b)
		if d > rad:
			continue
		var s = d + (4.0 if b.def.get("farm", false) else 0.0) + (2.0 if b.def.get("wall", false) else 0.0)
		if s < bs:
			bs = s
			best = b
	return best

func find_resource_near(owner: int, res: String, p: Vector2, rad: float, exclude := 0, naval := false, farms_only := false) -> Ent:
	var best: Ent = null
	var bd = rad
	if res == "food" and not naval:
		for b in buildings:
			if b.dead or b.owner != owner or not b.def.get("farm", false) or not b.built or b.id == exclude or farm_taken(b, null):
				continue
			var d = p.distance_to(b.pos)
			if d < bd:
				bd = d
				best = b
		if farms_only or best:
			return best
	for r in resources:
		if r.dead or r.res != res or r.id == exclude or (r.type == "fish") != naval:
			continue
		var d = p.distance_to(r.pos)
		if d < bd and accessible(r, naval):
			bd = d
			best = r
	return best

func nearest_dropoff(owner: int, p: Vector2, naval := false) -> Ent:
	var best: Ent = null
	var bd = 1e9
	for b in buildings:
		if b.dead or b.owner != owner or not b.built or not b.def.get("dropoff", false):
			continue
		if naval and not b.def.get("naval", false):
			continue
		var d = dist_to(p, b)
		if d < bd:
			bd = d
			best = b
	return best

# ======================================================================== unit behaviour
func update_unit(u: Ent, dt: float) -> void:
	u.cd -= dt
	if u.swing > 0.0: u.swing -= dt
	if u.hit_t > 0.0: u.hit_t -= dt
	u.moving = false
	u.working = false
	# regeneration
	var p: Player = players[u.owner]
	if u.hp < u.max_hp:
		var regen: float = p.mods.regen if time - u.last_hurt > 6.0 else 0.0
		if u.def.get("hero", false):
			regen += 2.0
		elif u.buff_t > time and time - u.last_hurt > 3.0:
			regen += 0.5
		u.hp = minf(u.max_hp, u.hp + regen * dt)
	match u.state:
		"idle": _u_idle(u, dt)
		"move":
			if u.amove:
				_scan(u, dt)
			if u.state == "move" and step_path(u, dt):
				u.path = PackedVector2Array(); u.state = "idle"; u.amove = false
		"attack": _u_attack(u, dt)
		"gather": _u_gather(u, dt)
		"return": _u_return(u, dt)
		"build": _u_build(u, dt)
		"heal": _u_heal(u, dt)
		"convert": _u_convert(u, dt)

func _u_idle(u: Ent, dt: float) -> void:
	var c: String = u.def.cls
	if c == "priest":
		_priest_scan(u, dt)
	elif c != "citizen" and u.def.atk > 0 and not (c == "ship" and u.def.get("gather", false)):
		_scan(u, dt)

func _scan(u: Ent, dt: float) -> void:
	u.scan_t -= dt
	if u.scan_t > 0.0:
		return
	u.scan_t = 0.5
	var r: float = maxf(u.def.los, u_range(u)) if u.stance != "hold" else u_range(u) + u.def.r
	var e = find_target(u, r)
	if e:
		if not u.has_guard:
			u.guard = u.pos; u.has_guard = true
		u.target_id = e.id; u.state = "attack"; u.path = PackedVector2Array(); u.fail = 0; u.repath_t = 0.0; u.ordered = false

func _priest_scan(u: Ent, dt: float) -> void:
	u.scan_t -= dt
	if u.scan_t > 0.0:
		return
	u.scan_t = 0.6
	var best: Ent = null
	var bd = 1e9
	for v in units_near(u.pos, u.def.los + 1.0):
		if v.dead or v == u or not is_ally(u.owner, v.owner) or v.hp >= v.max_hp or _air(v):
			continue
		var d = u.pos.distance_to(v.pos)
		if d < u.def.los and d < bd:
			bd = d; best = v
	if best:
		u.state = "heal"; u.target_id = best.id; u.ordered = false
		return
	if u.def.get("convert", false) and u.stance != "hold":
		for v in units_near(u.pos, u.def.los):
			if v.dead or not is_enemy(u.owner, v.owner) or v.def.get("hero", false) or _air(v):
				continue
			if u.pos.distance_to(v.pos) < u.def.los:
				u.state = "convert"; u.target_id = v.id; u.conv_t = 0.0; u.ordered = false
				return

func _u_attack(u: Ent, dt: float) -> void:
	var e = get_ent(u.target_id)
	if e == null or not is_enemy(u.owner, e.owner) or not can_target(u, e):
		_end_attack(u)
		return
	var reach = u_range(u)
	if u.stance == "hold" and not u.ordered and dist_to(u.pos, e) > reach:
		_end_attack(u)
		return
	if u.stance == "defensive" and not u.ordered and u.has_guard and u.pos.distance_to(u.guard) > 7.0:
		u.target_id = 0; u.state = "move"; u.amove = false
		path_to(u, u.guard)
		return
	if approach(u, e, reach, dt):
		u.facing = atan2(e.pos.y - u.pos.y, e.pos.x - u.pos.x)
		if u.cd <= 0.0:
			u.cd = u.def.cd
			_strike(u, e)
	elif u.fail > 4:
		_end_attack(u)
	# ranged attack-movers switch from buildings to units that come into range
	if u.amove and reach > 1.5 and e.kind == Ent.BUILDING:
		u.scan_t -= dt
		if u.scan_t <= 0.0:
			u.scan_t = 1.0
			var t = find_target(u, reach, true)
			if t:
				u.target_id = t.id

func _end_attack(u: Ent) -> void:
	u.target_id = 0
	u.path = PackedVector2Array()
	if u.amove:
		u.state = "move"
		path_to(u, u.amove_to)
	else:
		u.state = "idle"
		u.scan_t = 0.0

func _u_heal(u: Ent, dt: float) -> void:
	var e = get_ent(u.target_id)
	if e == null or e.hp >= e.max_hp or not is_ally(u.owner, e.owner):
		u.state = "idle"; u.scan_t = 0.0
		return
	if approach(u, e, u_range(u), dt):
		u.working = true
		u.facing = atan2(e.pos.y - u.pos.y, e.pos.x - u.pos.x)
		var rate: float = u.def.heal * (1.0 + players[u.owner].mods.heal)
		e.hp = minf(e.max_hp, e.hp + rate * dt)
		u.cd -= 0.0
		if int(time * 2.0) != int((time - dt) * 2.0):
			fx.append({"k": "heal", "a": u.id, "b": e.id})
	elif u.fail > 4:
		u.state = "idle"

func _u_convert(u: Ent, dt: float) -> void:
	var e = get_ent(u.target_id)
	if e == null or not is_enemy(u.owner, e.owner):
		u.state = "idle"; u.scan_t = 0.0
		return
	if approach(u, e, u_range(u), dt):
		u.working = true
		u.facing = atan2(e.pos.y - u.pos.y, e.pos.x - u.pos.x)
		u.conv_t += dt * (1.0 + players[u.owner].mods.convert)
		if int(time * 2.0) != int((time - dt) * 2.0):
			fx.append({"k": "convert_beam", "a": u.id, "b": e.id})
		var need: float = 5.0 + e.max_hp / 60.0
		if u.conv_t >= need:
			convert_unit(e, u.owner)
			u.state = "idle"; u.conv_t = 0.0
	elif u.fail > 4:
		u.state = "idle"

func convert_unit(e: Ent, owner: int) -> void:
	var old: Player = players[e.owner]
	old.pop -= 1
	old.stats.lost += 1
	players[owner].pop += 1
	players[owner].stats.killed += 1
	msg(e.owner, "Your %s was converted!" % e.def.name, Color("#fca5a5"))
	msg(owner, "%s converted." % e.def.name, Color("#c4b5fd"))
	e.owner = owner
	e.state = "idle"; e.target_id = 0; e.amove = false; e.path = PackedVector2Array()
	e.gather_id = 0; e.gather_type = ""; e.carry = 0; e.has_guard = false
	_upgrade_to_epoch(e, players[owner].epoch)
	fx.append({"k": "convert", "p": e.pos})
	sfx("convert", e.pos)

func _u_gather(u: Ent, dt: float) -> void:
	var nav = _naval(u)
	var e = get_ent(u.gather_id)
	if e == null:
		e = find_resource_near(u.owner, u.gather_type, u.pos, 10.0, 0, nav)
		if e == null:
			if u.carry > 0:
				u.state = "return"; u.path = PackedVector2Array()
			else:
				u.state = "idle"
			return
		u.gather_id = e.id; u.fail = 0; u.path = PackedVector2Array()
		if e.kind == Ent.BUILDING:
			e.gatherer_id = u.id
	var is_farm = e.kind == Ent.BUILDING
	if is_farm and not e.built:
		u.build_id = e.id; u.state = "build"
		return
	if u.carry > 0 and u.carry_res != u.gather_type:
		u.carry = 0
	var cap = carry_cap(u.owner)
	if u.carry >= cap:
		u.state = "return"; u.path = PackedVector2Array()
		return
	if approach(u, e, 0.05 if is_farm else 0.6, dt):
		u.working = true
		u.facing = atan2(e.pos.y - u.pos.y, e.pos.x - u.pos.x)
		var p: Player = players[u.owner]
		var base: float = FARM_RATE if is_farm else (FISH_RATE if e.type == "fish" else GATHER_RATE[u.gather_type])
		var rate = base * (1.0 + 0.1 * p.epoch + p.mods.gather.get(u.gather_type, 0.0)) * p.gather_mult
		u.gacc += rate * dt
		while u.gacc >= 1.0 and u.carry < cap:
			if not is_farm:
				if e.amount <= 0:
					break
				e.amount -= 1
			u.carry += 1
			u.gacc -= 1.0
		u.carry_res = u.gather_type
		if not is_farm and e.amount <= 0:
			_deplete(e)
		if u.carry >= cap:
			u.state = "return"; u.path = PackedVector2Array()
	elif u.fail > 3:
		u.fail = 0
		var alt = find_resource_near(u.owner, u.gather_type, u.pos, 12.0, e.id, nav)
		if alt:
			u.gather_id = alt.id; u.path = PackedVector2Array()
		else:
			u.state = "idle"

func _deplete(r: Ent) -> void:
	r.dead = true
	_dirty = true
	map.set_block(r.tx, r.ty, WorldMap.WATER if r.type == "fish" else WorldMap.FREE)
	ents.erase(r.id)
	res_at.erase(map.idx(r.tx, r.ty))

func _u_return(u: Ent, dt: float) -> void:
	if u.carry <= 0:
		_resume_gather(u)
		return
	var d = get_ent(u.drop_id)
	if d == null or d.owner != u.owner or not d.built:
		d = nearest_dropoff(u.owner, u.pos, _naval(u))
		if d == null:
			u.state = "idle"
			return
		u.drop_id = d.id; u.path = PackedVector2Array()
	if approach(u, d, 0.6, dt):
		var p: Player = players[u.owner]
		p.res[u.carry_res] += u.carry
		p.stats.gathered += u.carry
		u.carry = 0; u.drop_id = 0
		_resume_gather(u)
	elif u.fail > 4:
		u.state = "idle"; u.fail = 0

func _resume_gather(u: Ent) -> void:
	u.path = PackedVector2Array(); u.fail = 0
	u.state = "gather" if u.gather_type != "" else "idle"

func _u_build(u: Ent, dt: float) -> void:
	var b = get_ent(u.build_id)
	if b == null or b.owner != u.owner or (b.built and b.hp >= b.max_hp):
		if b and b.def.get("farm", false) and b.owner == u.owner and not farm_taken(b, u):
			b.gatherer_id = u.id; u.gather_type = "food"; u.gather_id = b.id; u.state = "gather"
			return
		var nb: Ent = null
		var bd = 10.0
		for x in buildings:
			if not x.dead and not x.built and x.owner == u.owner:
				var d = x.pos.distance_to(u.pos)
				if d < bd:
					bd = d; nb = x
		if nb:
			u.build_id = nb.id; u.path = PackedVector2Array()
			return
		u.build_id = 0
		if u.gather_type != "" and get_ent(u.gather_id):
			_resume_gather(u)
		else:
			u.state = "idle"; u.gather_type = ""
		return
	if approach(u, b, 0.6, dt):
		u.working = true
		u.facing = atan2(b.pos.y - u.pos.y, b.pos.x - u.pos.x)
		if int(time * 1.6) != int((time - dt) * 1.6):
			sfx("hammer", u.pos)
		if b.built:
			b.hp = minf(b.max_hp, b.hp + b.max_hp * dt / (b.def.time * 1.5))
			return
		var inc: float = dt / b.def.time
		b.progress = minf(1.0, b.progress + inc)
		b.hp = minf(b.max_hp, b.hp + b.max_hp * inc)
		if b.progress >= 1.0:
			_complete_building(b)
	elif u.fail > 4:
		u.state = "idle"; u.fail = 0

func _complete_building(b: Ent) -> void:
	b.built = true
	b.progress = 1.0
	var p: Player = players[b.owner]
	p.stats.built += 1
	if not b.def.get("wall", false):
		msg(b.owner, "%s completed." % b.def.name, Color("#86efac"))
		if b.owner == 0:
			sfx("complete", b.pos, true)
	if b.type == "wonder":
		p.wonder_t = 0.0
		for q in players:
			if q.id == 0:
				if is_ally(0, b.owner):
					msg(0, "%s completed a Wonder! Defend it for 5 minutes to win." % ("You" if b.owner == 0 else p.name), Color("#fde68a"))
				else:
					msg(0, "%s built a Wonder! Destroy it within 5 minutes!" % p.name, Color("#fca5a5"))
		sfx("fanfare", b.pos, true)

# ======================================================================== combat
func _strike(u: Ent, e: Ent) -> void:
	u.swing = 0.3
	var atk = u_atk(u)
	if u.def.has("proj"):
		fire(u, e, atk, u.def.proj, u.def.get("splash", 0.0))
	else:
		damage(u.id, u.owner, u.def, e, atk, height_of(u))
		sfx("sword" if u.def.cls != "citizen" else "hit", u.pos)

func fire(src: Ent, e: Ent, atk: float, kind: String, splash := 0.0) -> void:
	var sp = src.pos
	var from_h = height_of(src) + (2.0 if src.kind == Ent.BUILDING else 0.6)
	if src.kind == Ent.UNIT and _air(src):
		from_h = height_of(src) + 5.0
	var d = sp.distance_to(e.pos)
	projectiles.append({
		"from": sp, "to": e.pos, "pos": sp, "h0": from_h, "t": 0.0, "dur": maxf(0.06, d / PROJ_SPEED.get(kind, 12.0)),
		"target": e.id, "atk": atk, "kind": kind, "splash": splash,
		"src_id": src.id, "src_owner": src.owner, "src_def": src.def, "src_h": height_of(src),
	})
	match kind:
		"bullet": sfx("gun", sp)
		"arrow", "stone": sfx("bow", sp)
		"shell", "ball", "flak": sfx("cannon", sp)
		"rocket": sfx("rocket", sp)
		"boulder", "grenade", "bomb": sfx("throw", sp)

func _update_projectiles(dt: float) -> void:
	var keep = []
	for pr in projectiles:
		pr.t += dt
		var e = get_ent(pr.target)
		if e:
			pr.to = e.pos
		var k = minf(1.0, pr.t / pr.dur)
		pr.pos = pr.from.lerp(pr.to, k)
		if k >= 1.0:
			if e:
				damage(pr.src_id, pr.src_owner, pr.src_def, e, pr.atk, pr.src_h)
			if pr.splash > 0.0:
				var r: float = pr.splash
				for u in units_near(pr.to, r + 1.0):
					if u.dead or u == e or not is_enemy(pr.src_owner, u.owner) or _air(u):
						continue
					if u.pos.distance_to(pr.to) <= r + u.def.r:
						damage(pr.src_id, pr.src_owner, pr.src_def, u, pr.atk * 0.5, pr.src_h)
				fx.append({"k": "boom", "p": pr.to, "r": r})
				sfx("boom", pr.to)
		else:
			keep.append(pr)
	projectiles = keep

func damage(src_id: int, src_owner: int, sdef: Dictionary, e: Ent, atk: float, src_h := 0.0) -> void:
	if e.dead:
		return
	var tcls = e.cls()
	var m = 1.0
	var bonus: Dictionary = sdef.get("bonus", {})
	if bonus.has(tcls):
		m = bonus[tcls]
	elif tcls == "building":
		var src_is_bld = sdef.has("size")
		m = 0.5 if src_is_bld else (0.25 if sdef.get("range", 0.0) > 1.5 else 0.5)
	if sdef.has("size"):
		m *= 1.0 + 0.15 * players[src_owner].epoch
	# elevation advantage
	if src_h - height_of(e) > 0.8:
		m *= 1.25
	var dmg = maxf(1.0, atk * m - armor_of(e))
	e.hp -= dmg
	e.hit_t = 0.15
	e.last_hurt = time
	var src = get_ent(src_id)
	if e.kind == Ent.UNIT and src and e.def.cls != "citizen" and e.def.cls != "priest" and can_target(e, src):
		if e.state == "idle" or (e.state == "move" and e.amove):
			if e.stance != "hold" or dist_to(e.pos, src) <= u_range(e):
				e.target_id = src.id; e.state = "attack"; e.path = PackedVector2Array(); e.fail = 0; e.ordered = false
				if not e.has_guard:
					e.guard = e.pos; e.has_guard = true
	_alert(e)
	if e.hp <= 0.0:
		kill(e, src_owner, src)

func _alert(e: Ent) -> void:
	if e.owner != 0:
		return
	if time - _alert_t.get(0, -99.0) < 20.0:
		return
	_alert_t[0] = time
	msg(0, ("Your %s is under attack!" % e.def.name) if e.kind == Ent.BUILDING else "Your units are under attack!", Color("#fca5a5"))
	pings.append({"p": e.pos, "t": time})
	sfx("alarm", e.pos, true)

func kill(e: Ent, by_owner := -1, by: Ent = null) -> void:
	if e.dead:
		return
	e.dead = true
	_dirty = true
	ents.erase(e.id)
	var owner: Player = players[e.owner]
	owner.stats.lost += 1
	if by_owner >= 0 and by_owner != e.owner:
		var kp: Player = players[by_owner]
		kp.stats.killed += 1
		var value = 0
		for k in e.def.cost:
			value += e.def.cost[k]
		kp.stats.kill_value += value
		if by and by.kind == Ent.UNIT and e.kind == Ent.UNIT:
			var r0 = by.rank()
			by.kills += 1
			if by.rank() > r0 and by.owner == 0:
				msg(0, "%s promoted to rank %d!" % [by.def.name, by.rank()], Color("#fde68a"))
	if e.kind == Ent.UNIT:
		owner.pop -= 1
		fx.append({"k": "death", "p": e.pos, "owner": e.owner, "type": e.type, "air": _air(e), "naval": _naval(e)})
		sfx("die" if not (_air(e) or _naval(e) or e.def.cls == "siege" or e.def.get("model", "") == "tank") else "boom", e.pos)
	else:
		var code = WorldMap.WATER if e.def.get("naval", false) else WorldMap.FREE
		for y in range(e.ty, e.ty + e.size):
			for x in range(e.tx, e.tx + e.size):
				map.set_block(x, y, code)
		fx.append({"k": "collapse", "p": e.pos, "size": e.size})
		sfx("collapse", e.pos)
		for q in e.queue:
			if q.type == "@epoch":
				owner.advancing = false
			elif q.type.begins_with("#"):
				owner.researching.erase(q.type.substr(1))
		if e.type == "wonder":
			owner.wonder_t = -1.0
		if not e.def.get("wall", false):
			msg(e.owner, "Your %s was destroyed!" % e.def.name, Color("#fca5a5"))
			if by_owner == 0:
				msg(0, "Enemy %s destroyed." % e.def.name, Color("#86efac"))

# ======================================================================== buildings
func update_building(b: Ent, dt: float) -> void:
	if b.hit_t > 0.0:
		b.hit_t -= dt
	if not b.built:
		return
	var p: Player = players[b.owner]
	if b.queue.size():
		var q: Dictionary = b.queue[0]
		var t: String = q.type
		if t == "@epoch" or t.begins_with("#"):
			q.t += dt
			if q.t >= q.time:
				b.queue.pop_front()
				if t == "@epoch":
					_advance_epoch(p)
				else:
					_complete_tech(p, t.substr(1))
		elif p.pop >= mini(p.pop_cap, max_pop):
			if not q.get("blocked", false) and b.owner == 0:
				msg(0, "Population limit reached." if p.pop_cap >= max_pop else "Need more houses! Population limit reached.", Color("#fbbf24"))
			q.blocked = true
		else:
			q.blocked = false
			q.t += dt
			if q.t >= q.time:
				b.queue.pop_front()
				_spawn_from(b, t)
	if b.def.has("atk"):
		b.cd -= dt
		if b.cd <= 0.0:
			var e = find_target(b, b.def.range + b.size * 0.5, true)
			if e:
				b.cd = b.def.cd
				fire(b, e, b.def.atk, "flak" if e.def.get("air", false) else "arrow")
			else:
				b.cd = 0.4
	if b.type == "wonder" and p.wonder_t >= 0.0:
		p.wonder_t += dt
		if p.wonder_t >= Defs.WONDER_TIME:
			_end_game(p.team, "Wonder victory")

func _spawn_from(b: Ent, type: String) -> Ent:
	var p: Player = players[b.owner]
	var def: Dictionary = Defs.UNITS[type]
	var nav: bool = def.get("naval", false)
	var air: bool = def.get("air", false)
	var want: Vector2 = b.rally if b.has_rally else b.pos + Vector2(0, b.size)
	var best = Vector2i(-1, -1)
	var bd = 1e9
	for r in range(1, 4):
		if best.x >= 0:
			break
		for y in range(b.ty - r, b.ty + b.size + r):
			for x in range(b.tx - r, b.tx + b.size + r):
				if x > b.tx - r and x < b.tx + b.size + r - 1 and y > b.ty - r and y < b.ty + b.size + r - 1:
					continue
				if not (air and map.inb(x, y)) and not map.passable(x, y, nav):
					continue
				var d = Vector2(x + 0.5, y + 0.5).distance_squared_to(want)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	if best.x < 0:
		best = map.nearest_passable(Vector2i(b.tx, b.ty), nav, 10)
		if best.x < 0:
			best = Vector2i(b.tx, b.ty)
	var u = add_unit(type, b.owner, Vector2(best) + Vector2(0.5 + rng.randf_range(-0.15, 0.15), 0.5 + rng.randf_range(-0.15, 0.15)))
	p.stats.trained += 1
	if b.owner == 0:
		sfx("ready", u.pos, true)
	if b.has_rally:
		var t = get_ent(b.rally_id)
		if t and def.get("gather", false) and (t.kind == Ent.RES or (t.kind == Ent.BUILDING and t.owner == u.owner and (t.def.get("farm", false) or not t.built))):
			cmd_gather([u], t)
		elif t and t.kind != Ent.RES and is_enemy(u.owner, t.owner):
			cmd_attack([u], t)
		else:
			cmd_move([u], b.rally)
	return u

func _upgrade_to_epoch(u: Ent, epoch: int) -> void:
	var line = Defs.unit_line.get(u.type)
	if line == null:
		return
	var nt = Defs.line_unit(line.bld, line.row, epoch)
	if nt != null and nt != u.type:
		var ratio = u.hp / u.max_hp
		u.type = nt
		u.def = Defs.UNITS[nt]
		u.max_hp = u.def.hp
		u.hp = maxf(1.0, ratio * u.max_hp)

func _advance_epoch(p: Player) -> void:
	p.epoch += 1
	p.advancing = false
	var name: String = Defs.EPOCHS[p.epoch].name
	msg(p.id, "You have entered the %s!" % name, Color("#a5b4fc"))
	if p.id != 0:
		msg(0, "%s has entered the %s." % [p.name, name], Color("#fcd34d"))
	if p.id == 0:
		sfx("fanfare", Vector2.ZERO, true)
	for u in units:
		if not u.dead and u.owner == p.id:
			_upgrade_to_epoch(u, p.epoch)

func _complete_tech(p: Player, key: String) -> void:
	p.researching.erase(key)
	p.techs[key] = true
	p.stats.techs += 1
	var eff: Dictionary = Defs.TECHS[key].eff
	for k in eff:
		var v = eff[k]
		if v is Dictionary:
			for c in v:
				p.mods[k][c] = p.mods[k].get(c, 0) + v[c]
		else:
			p.mods[k] += v
	if eff.has("bld_hp"):
		for b in buildings:
			if not b.dead and b.owner == p.id:
				var nm = bld_max_hp(p.id, b.def)
				b.hp *= nm / b.max_hp
				b.max_hp = nm
	msg(p.id, "Research complete: %s." % Defs.TECHS[key].name, Color("#93c5fd"))
	if p.id == 0:
		sfx("complete", Vector2.ZERO, true)

func update_pop_caps() -> void:
	for p in players:
		p.pop_cap = 0
	for b in buildings:
		if not b.dead and b.built and b.def.has("pop"):
			players[b.owner].pop_cap += b.def.pop
	for p in players:
		p.pop_cap = mini(max_pop, p.pop_cap)

# ======================================================================== world upkeep
func _separate(dt: float) -> void:
	_sb.clear()
	for u in units:
		if u.dead:
			continue
		var k = int(u.pos.y) * 4096 + int(u.pos.x)
		if _sb.has(k):
			_sb[k].append(u)
		else:
			_sb[k] = [u]
	var f = minf(1.0, dt * 10.0)
	for u in units:
		if u.dead:
			continue
		var tx = int(u.pos.x)
		var ty = int(u.pos.y)
		var ua = _air(u)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var a = _sb.get((ty + oy) * 4096 + tx + ox)
				if a == null:
					continue
				for v in a:
					if v.id <= u.id or _air(v) != ua:
						continue
					var d = v.pos - u.pos
					var rr: float = (u.def.r + v.def.r) * 0.85
					var d2 = d.length_squared()
					if d2 >= rr * rr:
						continue
					var dl = sqrt(d2)
					if dl < 0.001:
						d = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
						dl = d.length()
					var push = (rr - dl) * 0.5 * f
					var n = d / dl * push
					var wu = 0.3 if (u.moving and not v.moving) else 1.0
					var wv = 0.3 if (v.moving and not u.moving) else 1.0
					_shift(u, -n * wu)
					_shift(v, n * wv)

func _shift(u: Ent, d: Vector2) -> void:
	var p = u.pos + d
	if _air(u):
		u.pos = Vector2(clampf(p.x, 0.2, map.w - 0.2), clampf(p.y, 0.2, map.h - 0.2))
	elif map.passable_at(p, _naval(u)):
		u.pos = p

func _update_auras() -> void:
	for hero in units:
		if hero.dead or not hero.def.get("hero", false):
			continue
		for v in units_near(hero.pos, AURA_R):
			if not v.dead and is_ally(hero.owner, v.owner) and v.pos.distance_to(hero.pos) <= AURA_R:
				v.buff_t = time + 0.7

func update_vis() -> void:
	vis.fill(0)
	var W = map.w
	var H = map.h
	for e in units + buildings:
		if e.dead or e.owner < 0 or not is_ally(0, e.owner):
			continue
		var r: int = e.def.los + (e.size >> 1 if e.kind == Ent.BUILDING else 0)
		var cx = int(e.pos.x)
		var cy = int(e.pos.y)
		var r2 = r * r
		for y in range(maxi(0, cy - r), mini(H - 1, cy + r) + 1):
			var dy = y - cy
			for x in range(maxi(0, cx - r), mini(W - 1, cx + r) + 1):
				var dx = x - cx
				if dx * dx + dy * dy <= r2:
					var i = y * W + x
					vis[i] = 1
					explored[i] = 1
	if reveal:
		vis.fill(1)
		explored.fill(1)
	vis_version += 1

func visible(e: Ent) -> bool:
	if e.kind == Ent.UNIT:
		return vis[int(e.pos.y) * map.w + int(e.pos.x)] == 1
	for y in range(e.ty, e.ty + e.size):
		for x in range(e.tx, e.tx + e.size):
			if vis[y * map.w + x]:
				return true
	return false

func is_explored(e: Ent) -> bool:
	for y in range(e.ty, e.ty + e.size):
		for x in range(e.tx, e.tx + e.size):
			if explored[y * map.w + x]:
				return true
	return false

func score(p: Player) -> int:
	return int(p.stats.gathered / 10 + p.stats.kill_value / 5 + p.stats.built * 5 + p.stats.techs * 40 + p.epoch * 150)

func _check_victory() -> void:
	for p in players:
		if p.defeated:
			continue
		var has_tc = false
		var has_cit = false
		for b in buildings:
			if not b.dead and b.owner == p.id and b.type == "town_center":
				has_tc = true
				break
		if not has_tc:
			for u in units:
				if not u.dead and u.owner == p.id and u.def.cls == "citizen":
					has_cit = true
					break
		if not has_tc and not has_cit:
			p.defeated = true
			msg(0, "%s has been defeated!" % ("You have" if p.id == 0 else p.name), Color("#fde68a"))
			if p.id != 0:
				sfx("fanfare", Vector2.ZERO, true)
	if players[0].defeated:
		var alive_team = -1
		for p in players:
			if not p.defeated:
				alive_team = p.team
		_end_game(alive_team, "Conquest")
		return
	var teams = {}
	for p in players:
		if not p.defeated:
			teams[p.team] = true
	if teams.size() <= 1:
		_end_game(teams.keys()[0], "Conquest")

func _end_game(team: int, how: String) -> void:
	if over:
		return
	over = true
	winner_team = team
	win_how = how
	_record_scores()

func _record_scores() -> void:
	var row = []
	for p in players:
		row.append(score(p))
	for i in players.size():
		players[i].score_hist.append(row[i])

func update(dt: float) -> void:
	if over:
		return
	time += dt
	update_pop_caps()
	_rebuild_buckets()
	for u in units:
		u.prev = u.pos
	for u in units:
		if not u.dead:
			update_unit(u, dt)
	for b in buildings:
		if not b.dead:
			update_building(b, dt)
	_update_projectiles(dt)
	_separate(dt)
	_aura_t -= dt
	if _aura_t <= 0.0:
		_aura_t = 0.5
		_update_auras()
	for ai in ais:
		if not players[ai.pid].defeated:
			ai.update(dt)
	if _dirty:
		units = units.filter(func(e): return not e.dead)
		buildings = buildings.filter(func(e): return not e.dead)
		resources = resources.filter(func(e): return not e.dead)
		_dirty = false
	_vis_t -= dt
	if _vis_t <= 0.0:
		_vis_t = 0.2
		update_vis()
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 1.0
		_check_victory()
	_score_t -= dt
	if _score_t <= 0.0:
		_score_t = 30.0
		_record_scores()

# ======================================================================== save / load
func to_dict() -> Dictionary:
	var d = {"v": 1, "settings": settings, "seed": seed_value, "time": time, "next_id": next_id,
		"terrain": Marshalls.raw_to_base64(map.terrain), "block": Marshalls.raw_to_base64(map.block),
		"heights": Marshalls.raw_to_base64(map.heights.to_byte_array()), "tint": Marshalls.raw_to_base64(map.tint.to_byte_array()),
		"explored": Marshalls.raw_to_base64(explored), "starts": starts.map(func(s): return [s.x, s.y]),
		"players": [], "units": [], "buildings": [], "resources": [], "ais": []}
	for p in players:
		d.players.append({"name": p.name, "color": p.color.to_html(), "team": p.team, "is_ai": p.is_ai, "personality": p.personality,
			"res": p.res, "epoch": p.epoch, "advancing": p.advancing, "gather_mult": p.gather_mult, "stats": p.stats,
			"techs": p.techs.keys(), "researching": p.researching.keys(), "mods": p.mods, "wonder_t": p.wonder_t,
			"defeated": p.defeated, "score_hist": p.score_hist})
	for u in units:
		d.units.append({"id": u.id, "type": u.type, "owner": u.owner, "x": u.pos.x, "y": u.pos.y, "hp": u.hp, "max_hp": u.max_hp,
			"carry": u.carry, "carry_res": u.carry_res, "gather_id": u.gather_id, "gather_type": u.gather_type, "kills": u.kills,
			"stance": u.stance, "facing": u.facing, "state": u.state if u.state in ["gather", "return", "idle"] else "idle"})
	for b in buildings:
		d.buildings.append({"id": b.id, "type": b.type, "owner": b.owner, "tx": b.tx, "ty": b.ty, "hp": b.hp, "max_hp": b.max_hp,
			"built": b.built, "progress": b.progress, "queue": b.queue, "rally": [b.rally.x, b.rally.y] if b.has_rally else null, "rally_id": b.rally_id})
	for r in resources:
		d.resources.append([r.id, r.type, r.tx, r.ty, r.amount])
	for ai in ais:
		d.ais.append(ai.to_dict())
	return d

static func from_dict(d: Dictionary) -> Sim:
	var s = Sim.new(d.settings)
	s.seed_value = int(d.seed)
	s.time = d.time
	s.next_id = int(d.next_id)
	s.map.terrain = Marshalls.base64_to_raw(d.terrain)
	s.map.block = Marshalls.base64_to_raw(d.block)
	s.map.heights = Marshalls.base64_to_raw(d.heights).to_float32_array()
	s.map.tint = Marshalls.base64_to_raw(d.tint).to_float32_array()
	s.explored = Marshalls.base64_to_raw(d.explored)
	s.starts = d.starts.map(func(a): return Vector2(a[0], a[1]))
	for pd in d.players:
		var p = Player.new()
		p.id = s.players.size()
		p.name = pd.name; p.color = Color(pd.color); p.team = int(pd.team); p.is_ai = pd.is_ai; p.personality = pd.personality
		p.res = pd.res; p.epoch = int(pd.epoch); p.advancing = pd.advancing; p.gather_mult = pd.gather_mult
		p.stats = pd.stats; p.mods = pd.mods; p.wonder_t = pd.wonder_t; p.defeated = pd.defeated; p.score_hist = pd.score_hist
		for k in pd.techs: p.techs[k] = true
		for k in pd.researching: p.researching[k] = true
		s.players.append(p)
	s.map.sync_grids()
	for r in d.resources:
		var e = Ent.new()
		e.id = int(r[0]); e.kind = Ent.RES; e.type = r[1]; e.res = RES_KIND[e.type]
		e.tx = int(r[2]); e.ty = int(r[3]); e.size = 1; e.amount = r[4]; e.max_amount = RES_AMOUNT[e.type]
		e.pos = Vector2(e.tx + 0.5, e.ty + 0.5); e.prev = e.pos
		s.resources.append(e); s.ents[e.id] = e; s.res_at[s.map.idx(e.tx, e.ty)] = e
	for bd in d.buildings:
		var e = Ent.new()
		e.id = int(bd.id); e.kind = Ent.BUILDING; e.type = bd.type; e.def = Defs.BUILDINGS[e.type]; e.owner = int(bd.owner)
		e.tx = int(bd.tx); e.ty = int(bd.ty); e.size = e.def.size; e.hp = bd.hp; e.max_hp = bd.max_hp
		e.built = bd.built; e.progress = bd.progress; e.queue = bd.queue
		e.pos = Vector2(e.tx + e.size * 0.5, e.ty + e.size * 0.5); e.prev = e.pos
		if bd.rally != null:
			e.rally = Vector2(bd.rally[0], bd.rally[1]); e.has_rally = true; e.rally_id = int(bd.rally_id)
		s.buildings.append(e); s.ents[e.id] = e
	for ud in d.units:
		var e = Ent.new()
		e.id = int(ud.id); e.kind = Ent.UNIT; e.type = ud.type; e.def = Defs.UNITS[e.type]; e.owner = int(ud.owner)
		e.pos = Vector2(ud.x, ud.y); e.prev = e.pos; e.hp = ud.hp; e.max_hp = ud.max_hp
		e.carry = int(ud.carry); e.carry_res = ud.carry_res; e.gather_id = int(ud.gather_id); e.gather_type = ud.gather_type
		e.kills = int(ud.kills); e.stance = ud.stance; e.facing = ud.facing; e.state = ud.state
		s.units.append(e); s.ents[e.id] = e
		s.players[e.owner].pop += 1
	for i in d.ais.size():
		var ai = AIPlayer.new(s, int(d.ais[i].pid))
		ai.from_dict(d.ais[i])
		s.ais.append(ai)
	s.update_pop_caps()
	s.update_vis()
	return s
