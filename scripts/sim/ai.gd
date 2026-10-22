class_name AIPlayer
extends RefCounted
## Computer opponent: runs an economy, researches, advances epochs, defends and attacks in waves.

const RATIOS := [
	{"food": 0.45, "wood": 0.4, "gold": 0.05, "stone": 0.1},
	{"food": 0.4, "wood": 0.3, "gold": 0.2, "stone": 0.1},
	{"food": 0.36, "wood": 0.24, "gold": 0.3, "stone": 0.1},
]
const MILITARY := ["barracks", "archery_range", "stable", "workshop"]

var s: Sim
var pid := 0
var p: Sim.Player
var d: Dictionary
var pers: Dictionary
var next_think := 1.0
var wave := 7
var attack_t := 420.0
var attacking := {}
var saving := false
var home := Vector2.ZERO
var home_t := Vector2i.ZERO
var has_home := false

func _init(sim: Sim, player_id: int) -> void:
	s = sim
	pid = player_id
	p = sim.players[pid]
	d = Defs.DIFFICULTY[sim.diff]
	pers = Defs.PERSONALITIES.get(p.personality, Defs.PERSONALITIES.balanced)
	wave = d.wave
	attack_t = d.first_attack * pers.attack

func to_dict() -> Dictionary:
	return {"pid": pid, "wave": wave, "attack_t": attack_t, "attacking": attacking.keys(), "next": next_think}

func from_dict(dd: Dictionary) -> void:
	wave = int(dd.wave)
	attack_t = dd.attack_t
	next_think = dd.next
	for id in dd.attacking:
		attacking[int(id)] = true

func update(_dt: float) -> void:
	if s.time < next_think:
		return
	next_think = s.time + d.think
	think()

func think() -> void:
	var cits = []
	var army = []
	var boats = []
	var warships = []
	for u in s.units:
		if u.dead or u.owner != pid:
			continue
		if u.def.cls == "citizen":
			cits.append(u)
		elif u.type == "fishing_boat":
			boats.append(u)
		elif u.def.get("naval", false):
			warships.append(u)
		else:
			army.append(u)
	var blds = []
	var count = {}
	var pending = 0
	var tc: Ent = null
	for b in s.buildings:
		if b.dead or b.owner != pid:
			continue
		blds.append(b)
		count[b.type] = count.get(b.type, 0) + 1
		if not b.built:
			pending += 1
		if b.type == "town_center" and (tc == null or (b.built and not tc.built)):
			tc = b
	if tc:
		home = tc.pos
		home_t = Vector2i(tc.pos)
		has_home = true
	if not has_home:
		return

	if count.get("town_center", 0) == 0 and cits.size():
		build("town_center", cits, 3, 2, 14)

	var cit_target = roundi(minf(20 + p.epoch * 8, 60) * (0.8 if d.gather < 1.0 else 1.0))
	if tc and tc.built and cits.size() < cit_target and tc.queue.is_empty():
		s.train(tc, "citizen")

	var housing = false
	for b in blds:
		if b.type == "house" and not b.built:
			housing = true
	if not housing and p.pop_cap < s.max_pop and p.pop_cap - p.pop <= 4 + p.epoch * 2:
		build("house", cits, 1)

	var mil = 0
	for t in MILITARY:
		mil += count.get(t, 0)
	if pending < 2:
		if cits.size() >= 7 and count.get("barracks", 0) == 0:
			build("barracks", cits, 2)
		elif cits.size() >= 11 and count.get("archery_range", 0) == 0:
			build("archery_range", cits, 2)
		elif cits.size() >= 12 and count.get("storehouse", 0) == 0:
			build_near_res("storehouse", "wood", cits)
		elif cits.size() >= 13 and count.get("dock", 0) == 0 and _fish_near():
			build("dock", cits, 1, 2, 18)
		elif p.epoch >= 1 and count.get("stable", 0) == 0:
			build("stable", cits, 2)
		elif p.epoch >= 1 and count.get("academy", 0) == 0:
			build("academy", cits, 1)
		elif p.epoch >= 1 and count.get("temple", 0) == 0 and p.res.stone > 200:
			build("temple", cits, 1)
		elif p.epoch >= 2 and count.get("workshop", 0) == 0:
			build("workshop", cits, 2)
		elif p.epoch >= 4 and count.get("airfield", 0) == 0:
			build("airfield", cits, 2)
		elif p.epoch >= 1 and d.towers and count.get("tower", 0) < mini(p.epoch, 2) + int(pers.towers) and p.res.stone > 250:
			build("tower", cits, 1, 5, 9)
		elif p.epoch >= 3 and count.get("storehouse", 0) < 2:
			build_near_res("storehouse", "gold", cits)
		elif p.res.wood > 450 and mil < 3 + p.epoch:
			var opts = MILITARY.filter(func(t): return Defs.BUILDINGS[t].epoch <= p.epoch)
			build(opts[s.rng.randi() % opts.size()], cits, 2)

	assign_idle(cits)

	var nxt = Defs.EPOCHS[p.epoch + 1] if p.epoch + 1 < Defs.EPOCHS.size() else null
	saving = nxt != null and not p.advancing and cits.size() >= 10 + p.epoch * 4 and s.time >= d.epoch_delay[p.epoch + 1] * pers.epoch
	if saving and tc and tc.built and tc.queue.is_empty() and Defs.can_afford(p.res, nxt.cost):
		s.advance(tc)
		saving = false

	research(blds)
	train_army(blds, army, boats, warships)
	military(army, warships)

func _fish_near() -> bool:
	for r in s.resources:
		if not r.dead and r.type == "fish" and r.pos.distance_to(home) < 22.0:
			return true
	return false

func weights() -> Dictionary:
	var w: Dictionary = RATIOS[mini(p.epoch, RATIOS.size() - 1)].duplicate()
	if saving:
		var cost: Dictionary = Defs.EPOCHS[p.epoch + 1].cost
		for k in cost:
			if p.res[k] < cost[k]:
				w[k] += 0.25
	if p.res.wood < 100:
		w.wood += 0.1
	for k in w:
		if p.res[k] > 1200:
			w[k] *= 0.3
	return w

func assign_idle(cits: Array) -> void:
	var counts = {"food": 0, "wood": 0, "stone": 0, "gold": 0}
	var use = {}
	for c in cits:
		if (c.state == "gather" or c.state == "return") and c.gather_type != "":
			counts[c.gather_type] += 1
			use[c.gather_id] = use.get(c.gather_id, 0) + 1
	# Rebalance: move one worker from the most over-staffed resource to the most needed one.
	var w0 = weights()
	var n0 = cits.size()
	var need = ""
	var over = ""
	var bn = 1.0
	var bo = 1.5
	for k in Defs.RES:
		var dlt = w0[k] * n0 - counts[k]
		if dlt > bn:
			bn = dlt
			need = k
		if -dlt > bo:
			bo = -dlt
			over = k
	if need != "" and over != "":
		for c in cits:
			if c.gather_type == over and c.state == "gather" and c.carry == 0:
				var tgt = gather_target(need, use)
				if tgt:
					s.cmd_gather([c], tgt)
				elif need == "food" and build("farm", [c], 1, 2, 9) == null:
					break
				counts[over] -= 1
				counts[need] += 1
				break
	for c in cits:
		if c.state != "idle":
			continue
		var w = weights()
		var n = cits.size()
		var order: Array = Defs.RES.duplicate()
		order.sort_custom(func(a, b): return (w[a] * n - counts[a]) > (w[b] * n - counts[b]))
		for res in order:
			var tgt = gather_target(res, use)
			if tgt:
				s.cmd_gather([c], tgt)
				counts[res] += 1
				use[tgt.id] = use.get(tgt.id, 0) + 1
				break
			if res == "food" and build("farm", [c], 1, 2, 9):
				counts.food += 1
				break

func gather_target(res: String, use: Dictionary) -> Ent:
	if res == "food":
		var farm = s.find_resource_near(pid, "food", home, 14.0, 0, false, true)
		if farm:
			return farm
	var best: Ent = null
	var bd = 16.0 if res == "food" else 60.0
	var cap = 2 if res == "wood" else 3
	for r in s.resources:
		if r.dead or r.res != res or r.type == "fish" or use.get(r.id, 0) >= cap:
			continue
		var dd = r.pos.distance_to(home)
		if dd < bd and s.accessible(r):
			bd = dd
			best = r
	return best

func build(type: String, cits: Array, n := 1, min_r := -1, max_r := -1, near := Vector2i(-1, -1)) -> Ent:
	var def: Dictionary = Defs.BUILDINGS[type]
	if def.epoch > p.epoch or not Defs.can_afford(p.res, def.cost) or cits.is_empty():
		return null
	var c = near if near.x >= 0 else home_t
	var spot = find_spot(type, c, min_r if min_r >= 0 else def.size + 2, max_r if max_r >= 0 else 16)
	if spot.x < 0:
		return null
	var sp = Vector2(spot)
	var builders = cits.filter(func(u): return u.state != "build")
	builders.sort_custom(func(a, b): return a.pos.distance_squared_to(sp) < b.pos.distance_squared_to(sp))
	builders = builders.slice(0, n)
	if builders.is_empty():
		return null
	var b = s.place_building(pid, type, spot.x, spot.y, builders)
	return b if b is Ent else null

func build_near_res(type: String, res: String, cits: Array) -> Ent:
	var best: Ent = null
	var bd = 1e9
	for r in s.resources:
		if r.dead or r.res != res or r.type == "fish":
			continue
		var dd = r.pos.distance_to(home)
		if dd > 6.0 and dd < bd:
			bd = dd
			best = r
	if best == null:
		return build(type, cits, 1)
	return build(type, cits, 1, 1, 6, Vector2i(best.tx, best.ty))

func find_spot(type: String, c: Vector2i, min_r: int, max_r: int) -> Vector2i:
	var sz: int = Defs.BUILDINGS[type].size
	var margin = 0 if type == "farm" or type == "dock" else 1
	for r in range(min_r, max_r + 1):
		var cand = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var tx = c.x + dx - sz / 2
				var ty = c.y + dy - sz / 2
				if s.can_place(type, tx, ty, pid, margin):
					cand.append(Vector2i(tx, ty))
		if cand.size():
			return cand[s.rng.randi() % cand.size()]
	return Vector2i(-1, -1)

func research(blds: Array) -> void:
	if saving and p.epoch < 3:
		return
	for b in blds:
		if not b.built or not b.queue.is_empty():
			continue
		if not (b.type in ["academy", "storehouse", "temple", "dock", "workshop", "airfield"]):
			continue
		for k in s.techs_for(b):
			var t: Dictionary = Defs.TECHS[k]
			if s.tech_available(b, k) and Defs.can_afford(p.res, t.cost):
				# keep a reserve so the economy keeps flowing
				var ok = true
				for r in t.cost:
					if p.res[r] - t.cost[r] < 150:
						ok = false
				if ok:
					s.research(b, k)
					break

func _enemy_air() -> bool:
	for u in s.units:
		if not u.dead and s.is_enemy(pid, u.owner) and u.def.get("air", false):
			return true
	return false

func train_army(blds: Array, army: Array, boats: Array, warships: Array) -> void:
	var cap = int((15 + p.epoch * 12) * d.army_cap * pers.army)
	var enemy_air = _enemy_air()
	for b in blds:
		if not b.built or not b.queue.is_empty():
			continue
		if b.type == "town_center":
			if p.epoch >= 1 and not s.has_hero(pid) and p.res.food > 450 and p.res.gold > 400:
				var hero = Defs.line_unit("town_center", 1, p.epoch)
				if hero:
					s.train(b, hero)
			continue
		if b.type == "dock":
			var opts = s.trainable(b)
			var fish_n = 0
			for r in s.resources:
				if not r.dead and r.type == "fish" and r.pos.distance_to(b.pos) < 20.0:
					fish_n += 1
			if boats.size() < mini(2 + p.epoch, fish_n) and opts.has("fishing_boat"):
				_try_train(b, "fishing_boat")
			elif opts.size() > 1 and warships.size() < 2 + p.epoch and army.size() >= 6:
				_try_train(b, opts[1])
			continue
		if not Defs.PRODUCTION.has(b.type) or army.size() >= cap:
			continue
		var opts = s.trainable(b)
		if opts.is_empty():
			continue
		var type: String = opts[s.rng.randi() % opts.size()]
		if Defs.UNITS[type].get("air_only", false) and not enemy_air:
			type = opts[0]
			if Defs.UNITS[type].get("air_only", false):
				continue
		if b.type == "temple":
			var priests = army.filter(func(u): return u.def.cls == "priest").size()
			if priests >= 2 + p.epoch / 2:
				continue
		_try_train(b, type)

func _try_train(b: Ent, type: String) -> void:
	var cost: Dictionary = Defs.UNITS[type].cost
	if saving:
		var need: Dictionary = Defs.EPOCHS[p.epoch + 1].cost
		for k in cost:
			if need.has(k) and p.res[k] - cost[k] < need[k]:
				return
	if p.res.wood < 80 and cost.has("wood"):
		return
	s.train(b, type)

func military(army: Array, warships: Array) -> void:
	for id in attacking.keys():
		if s.get_ent(id) == null:
			attacking.erase(id)
	var probe = Ent.new()
	probe.owner = pid
	probe.pos = home
	probe.def = {"atk": 1, "aa": true, "range": 10.0, "cls": "infantry"}
	var threat = s.find_target(probe, 15.0, true)
	if threat:
		for u in army:
			if not attacking.has(u.id) and u.state != "attack" and u.def.cls != "priest" and s.can_target(u, threat):
				s.cmd_attack([u], threat)
		for u in warships:
			if u.state == "idle" and s.can_target(u, threat):
				s.cmd_attack([u], threat)
	var at_home = army.filter(func(u): return not attacking.has(u.id))
	if threat == null and s.time >= attack_t and at_home.size() >= wave:
		var tgt = pick_target(home)
		if tgt:
			for u in at_home:
				attacking[u.id] = true
			s.cmd_move(at_home, tgt.pos, true)
			for u in warships:
				if u.state == "idle":
					s.cmd_move([u], tgt.pos, true)
			wave = mini(wave + int(d.wave_grow), 40)
			attack_t = s.time + 45.0
	for u in army:
		if attacking.has(u.id) and u.state == "idle":
			var tgt = pick_target(u.pos)
			if tgt:
				s.cmd_move([u], tgt.pos, true)
	if threat == null:
		var center = Vector2(s.map.w, s.map.h) * 0.5
		var rally = home + (center - home) * 0.12
		var loiter = at_home.filter(func(u): return u.state == "idle" and u.pos.distance_to(rally) > 5.0)
		if loiter.size():
			s.cmd_move(loiter, rally)

func pick_target(from: Vector2) -> Ent:
	var best: Ent = null
	var bd = 1e9
	for b in s.buildings:
		if b.dead or not s.is_enemy(pid, b.owner) or b.def.get("wall", false):
			continue
		var dd = b.pos.distance_to(from) - (8.0 if b.type == "town_center" or b.type == "wonder" else 0.0)
		if b.type == "wonder" and b.built:
			dd -= 30.0
		if dd < bd:
			bd = dd
			best = b
	if best:
		return best
	for u in s.units:
		if u.dead or not s.is_enemy(pid, u.owner):
			continue
		var dd = u.pos.distance_to(from)
		if dd < bd:
			bd = dd
			best = u
	return best
