class_name WorldMap
extends RefCounted
## Tile grid, heights, A* pathfinding (land and water) and world generation.

enum { FREE, WATER, RES, BLD, FARM }
enum { GRASS, SEA, SAND, DIRT, ROCK }

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var w: int
var h: int
var terrain := PackedByteArray()
var block := PackedByteArray()
var heights := PackedFloat32Array()   # (w+1)*(h+1) corner heights in metres
var tint := PackedFloat32Array()      # per-tile colour variation 0..1
var land := AStarGrid2D.new()
var sea := AStarGrid2D.new()

func _init(width: int, height: int) -> void:
	w = width
	h = height
	terrain.resize(w * h)
	block.resize(w * h)
	tint.resize(w * h)
	heights.resize((w + 1) * (h + 1))
	for g in [land, sea]:
		g.region = Rect2i(0, 0, w, h)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()

func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

func idx(x: int, y: int) -> int:
	return y * w + x

func walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var b = block[y * w + x]
	return b == FREE or b == FARM

func swimmable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return block[y * w + x] == WATER

func passable(x: int, y: int, naval: bool) -> bool:
	return swimmable(x, y) if naval else walkable(x, y)

func passable_at(p: Vector2, naval: bool) -> bool:
	return passable(floori(p.x), floori(p.y), naval)

func set_block(x: int, y: int, code: int) -> void:
	block[y * w + x] = code
	var c = Vector2i(x, y)
	land.set_point_solid(c, not (code == FREE or code == FARM))
	sea.set_point_solid(c, code != WATER)

func sync_grids() -> void:
	for y in h:
		for x in w:
			set_block(x, y, block[y * w + x])

## Height in metres at a position measured in tiles (bilinear over corners).
func height_at(p: Vector2) -> float:
	var fx = clampf(p.x, 0.0, w - 0.001)
	var fy = clampf(p.y, 0.0, h - 0.001)
	var ix = int(fx)
	var iy = int(fy)
	var tx = fx - ix
	var ty = fy - iy
	var s = w + 1
	var a = heights[iy * s + ix]
	var b = heights[iy * s + ix + 1]
	var c = heights[(iy + 1) * s + ix]
	var d = heights[(iy + 1) * s + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

# ------------------------------------------------------------------ paths
func nearest_passable(t: Vector2i, naval: bool, max_r := 12) -> Vector2i:
	if passable(t.x, t.y, naval):
		return t
	for r in range(1, max_r + 1):
		var best = Vector2i(-1, -1)
		var bd = 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if passable(t.x + dx, t.y + dy, naval):
					var d = float(dx * dx + dy * dy)
					if d < bd:
						bd = d
						best = Vector2i(t.x + dx, t.y + dy)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

## Returns waypoints (tile centres) from `from` toward `to`, ending as close as possible.
func find_path(from: Vector2i, to: Vector2i, naval: bool) -> PackedVector2Array:
	var g: AStarGrid2D = sea if naval else land
	var out = PackedVector2Array()
	if not passable(from.x, from.y, naval):
		from = nearest_passable(from, naval, 3)
		if from.x < 0:
			return out
		out.append(Vector2(from) + Vector2(0.5, 0.5))
	if not inb(to.x, to.y):
		to = Vector2i(clampi(to.x, 0, w - 1), clampi(to.y, 0, h - 1))
	var ids: Array[Vector2i] = g.get_id_path(from, to, true)
	for i in range(1, ids.size()):
		out.append(Vector2(ids[i]) + Vector2(0.5, 0.5))
	return out

func line_clear(a: Vector2, b: Vector2, naval: bool) -> bool:
	var n = int(ceil(a.distance_to(b) / 0.2))
	for k in range(1, n + 1):
		var p = a.lerp(b, float(k) / n)
		for o in [Vector2.ZERO, Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
			if not passable_at(p + o, naval):
				return false
	return true

## String-pulling: drop waypoints that are in direct line of sight.
func smooth(start: Vector2, pts: PackedVector2Array, naval: bool) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out = PackedVector2Array()
	var a = start
	var i = 0
	while i < pts.size():
		var j = mini(pts.size() - 1, i + 12)
		while j > i and not line_clear(a, pts[j], naval):
			j -= 1
		out.append(pts[j])
		a = pts[j]
		i = j + 1
	return out

func connected(a: Vector2i, b: Vector2i, naval := false) -> bool:
	var p = find_path(a, b, naval)
	if a == b:
		return true
	return p.size() > 0 and Vector2i(p[p.size() - 1]) == b

# ------------------------------------------------------------------ generation
func generate(sim, rng: RandomNumberGenerator, map_type: String, starts: Array) -> void:
	var nw = FastNoiseLite.new()
	nw.seed = rng.randi(); nw.frequency = 0.045; nw.fractal_octaves = 3
	var nf = FastNoiseLite.new()
	nf.seed = rng.randi(); nf.frequency = 0.06; nf.fractal_octaves = 3
	var nh = FastNoiseLite.new()
	nh.seed = rng.randi(); nh.frequency = 0.03; nh.fractal_octaves = 4
	var nv = FastNoiseLite.new()
	nv.seed = rng.randi(); nv.frequency = 0.08
	var amp = 2.6 if map_type == "highlands" else 1.2
	var center = Vector2(w, h) / 2.0
	var tile_h = PackedFloat32Array()
	tile_h.resize(w * h)

	for y in h:
		for x in w:
			var i = idx(x, y)
			var p = Vector2(x + 0.5, y + 0.5)
			var near_start = _near(starts, p, 13.0)
			var water = false
			var n = (nw.get_noise_2d(x, y) + 1.0) * 0.5
			match map_type:
				"lakes": water = n < 0.33
				"plains": water = n < 0.24
				"highlands": water = n < 0.28
				"inland_sea":
					var r = w * 0.2 * (0.8 + 0.5 * (nw.get_noise_2d(x * 0.5, y * 0.5) + 1.0) * 0.5)
					water = p.distance_to(center) < r or n < 0.25
			if near_start:
				water = false
			var hh = 0.4 + amp * (nh.get_noise_2d(x, y) + 1.0) * 0.5
			for s in starts:
				var d: float = p.distance_to(s)
				if d < 16.0:
					hh = lerpf(0.7, hh, smoothstep(9.0, 16.0, d))
			tint[i] = (nv.get_noise_2d(x, y) + 1.0) * 0.5
			if water:
				terrain[i] = SEA
				block[i] = WATER
				tile_h[i] = -1.2
			else:
				terrain[i] = GRASS
				block[i] = FREE
				tile_h[i] = hh
				if map_type == "highlands" and hh > 2.4:
					terrain[i] = ROCK
				elif tint[i] > 0.66:
					terrain[i] = DIRT
	# Guarantee land routes between all bases.
	for k in range(1, starts.size()):
		var a = Vector2i(starts[0])
		var b = Vector2i(starts[k])
		if not _land_connected(a, b):
			_carve(a, b, tile_h)
	# Shores
	for y in h:
		for x in w:
			var i = idx(x, y)
			if terrain[i] == SEA:
				continue
			for d in DIRS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if inb(nx, ny) and terrain[idx(nx, ny)] == SEA:
					terrain[i] = SAND
					tile_h[i] = minf(tile_h[i], 0.25)
					break
	# Corner heights = average of touching tiles.
	var s = w + 1
	for cy in h + 1:
		for cx in w + 1:
			var sum = 0.0
			var cnt = 0
			var water_n = 0
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var tx: int = cx + ox
					var ty: int = cy + oy
					if inb(tx, ty):
						sum += tile_h[idx(tx, ty)]
						cnt += 1
						if terrain[idx(tx, ty)] == SEA:
							water_n += 1
			var v = sum / maxi(cnt, 1)
			if water_n > 0 and water_n < cnt:
				v = minf(v, -0.15)
			heights[cy * s + cx] = v
	sync_grids()

	# Forests
	var forest_thr = 0.36 if map_type == "plains" else 0.3
	for y in h:
		for x in w:
			var i = idx(x, y)
			if block[i] != FREE or terrain[i] == SAND:
				continue
			var p = Vector2(x + 0.5, y + 0.5)
			if _near(starts, p, 9.5):
				continue
			if nf.get_noise_2d(x, y) > forest_thr and rng.randf() < 0.85:
				sim.add_resource("tree", x, y)
	# Base resources at spread-out angles around each start.
	for st in starts:
		var a0 = rng.randf() * TAU
		var spots = [["berries", 6, 7.0, 0.0], ["gold", 5, 8.0, 1.55], ["stone", 5, 8.0, 3.1], ["tree", 22, 10.5, 4.65], ["berries", 5, 11.0, 2.3], ["gold", 4, 13.0, 5.4]]
		for sp in spots:
			var ang: float = a0 + sp[3]
			var c = Vector2i(roundi(st.x + cos(ang) * sp[2]), roundi(st.y + sin(ang) * sp[2]))
			_cluster(sim, rng, sp[0], c, sp[1], starts)
	# Scattered resources
	var area_k = float(w * h) / (96.0 * 96.0)
	var scatter = [["gold", 10, 6], ["stone", 8, 5], ["berries", 8, 6], ["tree", 12, 14]]
	for sc in scatter:
		for k in int(sc[1] * area_k):
			for tries in 30:
				var x = 3 + rng.randi() % (w - 6)
				var y = 3 + rng.randi() % (h - 6)
				if _near(starts, Vector2(x, y), 16.0) or block[idx(x, y)] != FREE:
					continue
				_cluster(sim, rng, sc[0], Vector2i(x, y), sc[2], starts)
				break
	# Fish in open water
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if block[idx(x, y)] != WATER:
				continue
			var open = true
			for d in DIRS:
				if terrain[idx(x + d.x, y + d.y)] != SEA:
					open = false
					break
			if open and rng.randf() < 0.035:
				sim.add_resource("fish", x, y)
	# Forests must not wall bases off from each other.
	for k in range(1, starts.size()):
		var a = Vector2i(starts[0])
		var b = Vector2i(starts[k])
		if not connected(a, b):
			_clear_line(sim, a, b)

func _near(starts: Array, p: Vector2, r: float) -> bool:
	for s in starts:
		if p.distance_to(s) < r:
			return true
	return false

func _land_connected(a: Vector2i, b: Vector2i) -> bool:
	var seen = {}
	var q = [a]
	seen[a] = true
	while q.size():
		var c: Vector2i = q.pop_back()
		if c == b:
			return true
		for d in DIRS.slice(0, 4):
			var n: Vector2i = c + d
			if inb(n.x, n.y) and not seen.has(n) and terrain[idx(n.x, n.y)] != SEA:
				seen[n] = true
				q.append(n)
	return false

func _carve(a: Vector2i, b: Vector2i, tile_h: PackedFloat32Array) -> void:
	var n = int(Vector2(a).distance_to(Vector2(b)))
	for k in n + 1:
		var p = Vector2(a).lerp(Vector2(b), float(k) / maxf(n, 1))
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				var x = int(p.x) + ox
				var y = int(p.y) + oy
				if inb(x, y) and terrain[idx(x, y)] == SEA:
					terrain[idx(x, y)] = GRASS
					block[idx(x, y)] = FREE
					tile_h[idx(x, y)] = 0.3

func _clear_line(sim, a: Vector2i, b: Vector2i) -> void:
	var n = int(Vector2(a).distance_to(Vector2(b)))
	for k in n + 1:
		var p = Vector2(a).lerp(Vector2(b), float(k) / maxf(n, 1))
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var x = int(p.x) + ox
				var y = int(p.y) + oy
				if inb(x, y) and block[idx(x, y)] == RES:
					sim.remove_resource_at(x, y)

func _cluster(sim, rng: RandomNumberGenerator, type: String, c: Vector2i, count: int, starts: Array) -> void:
	var open = [c]
	var placed = 0
	var guard = 0
	while open.size() and placed < count and guard < 400:
		guard += 1
		var cur: Vector2i = open.pop_at(rng.randi() % open.size())
		if not inb(cur.x, cur.y) or block[idx(cur.x, cur.y)] != FREE:
			continue
		var too_close = false
		for s in starts:
			if absf(cur.x + 0.5 - s.x) <= 3.5 and absf(cur.y + 0.5 - s.y) <= 3.5:
				too_close = true
		if too_close:
			continue
		sim.add_resource(type, cur.x, cur.y)
		placed += 1
		for d in DIRS.slice(0, 4):
			open.append(cur + d)
