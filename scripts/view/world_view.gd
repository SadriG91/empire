class_name WorldView
extends Node3D
## Renders the simulation: terrain, water, fog of war, trees, entities, projectiles and effects.

const TILE := 2.0
const UNIT_SCALE := 1.5
const AIR_ALT := 7.0
const WATER_Y := -0.35

const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2D fog_tex : filter_linear;
uniform vec2 map_size;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	vec2 cell = floor(wpos.xz * 1.5);
	float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	c *= 0.93 + 0.1 * n;
	float f = texture(fog_tex, wpos.xz / map_size).r;
	ALBEDO = c * f;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1 * f;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D fog_tex : filter_linear;
uniform vec2 map_size;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.6 + TIME * 1.3) * 0.05 + cos(wpos.z * 0.5 + TIME) * 0.05;
}
void fragment() {
	float f = texture(fog_tex, wpos.xz / map_size).r;
	float w = sin(wpos.x * 1.7 + TIME * 2.0) * sin(wpos.z * 1.3 - TIME * 1.6);
	vec3 deep = vec3(0.012, 0.06, 0.16);
	vec3 shallow = vec3(0.03, 0.15, 0.28);
	vec3 c = mix(deep, shallow, 0.5 + 0.25 * w);
	ALBEDO = c * f;
	ROUGHNESS = mix(1.0, 0.15, f);
	METALLIC = 0.1 * f;
	SPECULAR = 0.6 * f;
	ALPHA = mix(1.0, 0.88, f);
}
"""

var sim: Sim
var fog_img: Image
var fog_tex: ImageTexture
var _fog_version := -1
var _fog_bytes := PackedByteArray()
var nodes := {}            # id -> Node3D
var _mesh_key := {}        # id -> String
var _kinds := {}           # id -> Ent kind
var _trees := {}           # id -> [multimesh, index, revealed]
var _tree_mm: Array = []
var _tree_check := 0.0
var _proj_pool: Array = []
var _effects: Array = []   # {node, t, dur, kind, ...}
var _ring_mesh: TorusMesh
var _ring_mats := {}
var _ghosts: Array = []
var _ghost_mats := {}
var _rally: MeshInstance3D
var _plinths := {}
var _scaffold := {}
var _smoke_mat: StandardMaterial3D
var light: DirectionalLight3D

func setup(s: Sim) -> void:
	sim = s
	_build_environment()
	_build_terrain()
	_build_water()
	_build_trees()
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.86
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	for k in {"own": Color("#4ade80"), "enemy": Color("#f87171"), "ally": Color("#60a5fa"), "res": Color("#fbbf24")}.keys():
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"own": Color("#4ade80"), "enemy": Color("#f87171"), "ally": Color("#60a5fa"), "res": Color("#fbbf24")}[k]
		_ring_mats[k] = m
	for k in ["ok", "bad"]:
		var m = StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 1.0, 0.45, 0.45) if k == "ok" else Color(1.0, 0.3, 0.3, 0.5)
		_ghost_mats[k] = m
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_rally = MeshInstance3D.new()
	var fb = Models.B.new()
	fb.cyl(0.05, 2.0, Vector3(0, 1.0, 0), Models.DARK)
	fb.box(Vector3(0.9, 0.5, 0.05), Vector3(0.45, 1.75, 0), Color.WHITE)
	_rally.mesh = fb.mesh()
	_rally.visible = false
	add_child(_rally)
	update_fog(true)

static func to3(p: Vector2, h: float) -> Vector3:
	return Vector3(p.x * TILE, h, p.y * TILE)

func ground(p: Vector2) -> Vector3:
	return Vector3(p.x * TILE, sim.map.height_at(p), p.y * TILE)

# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var env = WorldEnvironment.new()
	var e = Environment.new()
	var sky = Sky.new()
	var sm = ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#5d8fc9")
	sm.sky_horizon_color = Color("#c9d9e6")
	sm.ground_bottom_color = Color("#1a1d22")
	sm.ground_horizon_color = Color("#6a7480")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.fog_enabled = false
	e.fog_light_color = Color("#b9c8d6")
	e.fog_density = 0.0025
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -38, 0)
	light.light_energy = 1.0
	light.light_color = Color("#fff4e0")
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 110.0
	add_child(light)

func _tile_color(i: int) -> Color:
	var m = sim.map
	var t = m.tint[i]
	match m.terrain[i]:
		WorldMap.SEA: return Color("#5d5a42")
		WorldMap.SAND: return Color("#d8c48a").lerp(Color("#cdb579"), t)
		WorldMap.DIRT: return Color("#8a7448").lerp(Color("#7a6a46"), t)
		WorldMap.ROCK: return Color("#8a877d").lerp(Color("#77746b"), t)
	return Color("#6a8a45").lerp(Color("#8a9c55"), t)

func _build_terrain() -> void:
	var m = sim.map
	var W = m.w
	var H = m.h
	var verts = PackedVector3Array()
	var cols = PackedColorArray()
	var norms = PackedVector3Array()
	var idx = PackedInt32Array()
	var s = W + 1
	verts.resize(s * (H + 1))
	cols.resize(s * (H + 1))
	norms.resize(s * (H + 1))
	for cy in H + 1:
		for cx in W + 1:
			var i = cy * s + cx
			verts[i] = Vector3(cx * TILE, m.heights[i], cy * TILE)
			var c = Color(0, 0, 0)
			var n = 0
			for oy in [-1, 0]:
				for ox in [-1, 0]:
					var tx: int = cx + ox
					var ty: int = cy + oy
					if m.inb(tx, ty):
						c += _tile_color(ty * W + tx)
						n += 1
			cols[i] = c / float(n)
	for cy in H + 1:
		for cx in W + 1:
			var hl = m.heights[cy * s + maxi(cx - 1, 0)]
			var hr = m.heights[cy * s + mini(cx + 1, W)]
			var hd = m.heights[maxi(cy - 1, 0) * s + cx]
			var hu = m.heights[mini(cy + 1, H) * s + cx]
			norms[cy * s + cx] = Vector3(hl - hr, 2.0 * TILE, hd - hu).normalized()
	for cy in H:
		for cx in W:
			var a = cy * s + cx
			idx.append_array([a, a + 1, a + s, a + 1, a + s + 1, a + s])
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	fog_img = Image.create(W, H, false, Image.FORMAT_L8)
	fog_tex = ImageTexture.create_from_image(fog_img)
	_fog_bytes.resize(W * H)
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = TERRAIN_SHADER
	mat.shader = sh
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", Vector2(W * TILE, H * TILE))
	mesh.surface_set_material(0, mat)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	# dark skirt around the map edge
	var skirt = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(W * TILE * 3, H * TILE * 3)
	skirt.mesh = pm
	var sm = StandardMaterial3D.new()
	sm.albedo_color = Color("#0d1014")
	skirt.material_override = sm
	skirt.position = Vector3(W * TILE * 0.5, -1.5, H * TILE * 0.5)
	add_child(skirt)

func _build_water() -> void:
	var W = sim.map.w
	var H = sim.map.h
	var pm = PlaneMesh.new()
	pm.size = Vector2(W * TILE, H * TILE)
	pm.subdivide_width = W / 2
	pm.subdivide_depth = H / 2
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = WATER_SHADER
	mat.shader = sh
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", Vector2(W * TILE, H * TILE))
	pm.material = mat
	var mi = MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(W * TILE * 0.5, WATER_Y, H * TILE * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_trees() -> void:
	var groups = [[], [], [], []]
	for r in sim.resources:
		if r.type != "tree":
			continue
		var h = hash(r.tx * 7919 + r.ty * 104729)
		groups[(h % 2) * 2 + (h >> 4) % 2].append(r)
	for gi in 4:
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.resource_mesh("pine" if gi < 2 else "oak", gi % 2)
		mm.instance_count = groups[gi].size()
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		_tree_mm.append(mm)
		for i in groups[gi].size():
			var r: Ent = groups[gi][i]
			_trees[r.id] = [mm, i, false, r]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

func _tree_xf(r: Ent) -> Transform3D:
	var h = hash(r.tx * 31 + r.ty * 977)
	var sc = 0.85 + (h % 100) / 250.0
	var off = Vector2(((h >> 3) % 100) / 400.0 - 0.12, ((h >> 7) % 100) / 400.0 - 0.12)
	var p = r.pos + off
	return Transform3D(Basis(Vector3.UP, (h % 628) / 100.0).scaled(Vector3(sc, sc, sc)), ground(p))

func _update_trees() -> void:
	for id in _trees.keys():
		var t: Array = _trees[id]
		var r: Ent = t[3]
		if r.dead:
			t[0].set_instance_transform(t[1], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			_trees.erase(id)
		elif not t[2] and sim.explored[r.ty * sim.map.w + r.tx]:
			t[2] = true
			t[0].set_instance_transform(t[1], _tree_xf(r))

func update_fog(force := false) -> void:
	if not force and sim.vis_version == _fog_version:
		return
	_fog_version = sim.vis_version
	var n = sim.vis.size()
	var vis = sim.vis
	var ex = sim.explored
	for i in n:
		_fog_bytes[i] = 255 if vis[i] else (105 if ex[i] else 0)
	fog_img.set_data(sim.map.w, sim.map.h, false, Image.FORMAT_L8, _fog_bytes)
	fog_tex.update(fog_img)
	_update_trees()

# ------------------------------------------------------------------ per frame
func sync(delta: float, alpha: float, selected: Dictionary) -> void:
	update_fog()
	_tree_check -= delta
	if _tree_check <= 0.0:
		_tree_check = 0.3
		_update_trees()
	var seen = {}
	var t = Time.get_ticks_msec() / 1000.0
	for u in sim.units:
		if u.dead:
			continue
		seen[u.id] = true
		var n: Node3D = nodes.get(u.id)
		var show: bool = sim.is_ally(0, u.owner) or sim.visible(u)
		if n == null:
			if not show:
				continue
			n = _make_node(u)
		n.visible = show
		if not show:
			continue
		_sync_unit(u, n, alpha, t, delta)
		_set_ring(n, u, selected.has(u.id))
	for b in sim.buildings:
		if b.dead:
			continue
		seen[b.id] = true
		var n: Node3D = nodes.get(b.id)
		var show: bool = sim.is_ally(0, b.owner) or sim.is_explored(b)
		if n == null:
			if not show:
				continue
			n = _make_node(b)
		n.visible = show
		if show:
			_sync_building(b, n)
			_set_ring(n, b, selected.has(b.id))
	for r in sim.resources:
		if r.dead or r.type == "tree":
			if r.type == "tree" and selected.has(r.id):
				seen[r.id] = true
			continue
		seen[r.id] = true
		var n: Node3D = nodes.get(r.id)
		var show = sim.explored[r.ty * sim.map.w + r.tx] == 1
		if n == null:
			if not show:
				continue
			n = _make_node(r)
		n.visible = show
		if r.type != "fish":
			var k = 0.55 + 0.45 * r.amount / r.max_amount
			n.scale = Vector3(k, k, k)
		else:
			n.position.y = WATER_Y + sin(t * 2.0 + r.id) * 0.05
			n.rotation.y = t * 0.4 + r.id
		_set_ring(n, r, selected.has(r.id))
	for id in nodes.keys():
		if seen.has(id):
			continue
		var n: Node3D = nodes[id]
		var kind: int = _kinds.get(id, Ent.RES)
		nodes.erase(id)
		_mesh_key.erase(id)
		_kinds.erase(id)
		if kind == Ent.RES or not n.visible:
			n.queue_free()
		else:
			n.get_node("R").visible = false
			_effects.append({"node": n, "t": 0.0, "dur": 2.5, "kind": "sink", "y0": n.position.y, "bld": kind == Ent.BUILDING})
	_sync_projectiles()
	_update_effects(delta)

func _make_node(e: Ent) -> Node3D:
	var n = Node3D.new()
	var mi = MeshInstance3D.new()
	mi.name = "M"
	n.add_child(mi)
	var ring = MeshInstance3D.new()
	ring.name = "R"
	ring.mesh = _ring_mesh
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	if e.kind == Ent.RES:
		mi.mesh = Models.resource_mesh(e.type, e.id % 2)
		var y = WATER_Y if e.type == "fish" else sim.map.height_at(e.pos)
		n.position = Vector3(e.pos.x * TILE, y, e.pos.y * TILE)
		n.rotation.y = (e.id * 1.7)
		ring.scale = Vector3(1.2, 1, 1.2)
	elif e.kind == Ent.BUILDING:
		var S = e.size * TILE
		var p = e.pos
		var base_h = _building_base(e)
		n.position = Vector3(p.x * TILE, base_h, p.y * TILE)
		ring.scale = Vector3(S * 0.62, 1, S * 0.62)
		ring.position.y = 0.15
		if not e.def.get("farm", false) and not e.def.get("naval", false):
			var pl = MeshInstance3D.new()
			pl.mesh = _plinth(e.size)
			n.add_child(pl)
	else:
		ring.scale = Vector3.ONE * (e.def.r * TILE * 1.25)
		ring.position.y = 0.06
		mi.scale = Vector3.ONE * UNIT_SCALE
	add_child(n)
	nodes[e.id] = n
	_kinds[e.id] = e.kind
	return n

func _building_base(b: Ent) -> float:
	if b.def.get("naval", false):
		return WATER_Y
	var hmax = -99.0
	var hsum = 0.0
	var s = sim.map.w + 1
	for y in range(b.ty, b.ty + b.size + 1):
		for x in range(b.tx, b.tx + b.size + 1):
			var hv = sim.map.heights[y * s + x]
			hmax = maxf(hmax, hv)
			hsum += hv
	if b.def.get("farm", false):
		return hsum / float((b.size + 1) * (b.size + 1)) + 0.02
	return hmax

func _plinth(size: int) -> ArrayMesh:
	if _plinths.has(size):
		return _plinths[size]
	var b = Models.B.new()
	var S = size * TILE
	b.box(Vector3(S * 0.94, 1.6, S * 0.94), Vector3(0, -0.78, 0), Color("#5a5044"))
	_plinths[size] = b.mesh()
	return _plinths[size]

func _scaffold_mesh(size: int) -> ArrayMesh:
	if _scaffold.has(size):
		return _scaffold[size]
	var b = Models.B.new()
	var S = size * TILE * 0.95
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			b.box(Vector3(0.12, 3.2, 0.12), Vector3(x * S, 1.6, z * S), Models.WOOD)
	for y in [1.0, 2.2]:
		for k in 4:
			var a = k * PI * 0.5
			b.box(Vector3(S, 0.08, 0.08), Vector3(cos(a) * S * 0.5, y, sin(a) * S * 0.5), Models.WOOD, Vector3(0, rad_to_deg(a) + 90, 0))
	_scaffold[size] = b.mesh()
	return _scaffold[size]

func _set_ring(n: Node3D, e: Ent, on: bool) -> void:
	var ring: MeshInstance3D = n.get_node("R")
	ring.visible = on
	if on:
		var k = "res" if e.kind == Ent.RES else ("own" if e.owner == 0 else ("ally" if sim.is_ally(0, e.owner) else "enemy"))
		ring.material_override = _ring_mats[k]

func _sync_unit(u: Ent, n: Node3D, alpha: float, t: float, delta: float) -> void:
	var mi: MeshInstance3D = n.get_node("M")
	var ep: int = sim.players[u.owner].epoch
	var key = "%s:%d:%d" % [u.type, u.owner, ep]
	if _mesh_key.get(u.id, "") != key:
		_mesh_key[u.id] = key
		mi.mesh = Models.unit_mesh(u.type, sim.players[u.owner].color, ep)
	var p: Vector2 = u.prev.lerp(u.pos, alpha)
	var y: float
	var air: bool = u.def.get("air", false)
	var naval: bool = u.def.get("naval", false)
	if air:
		y = maxf(sim.map.height_at(p), 0.0) + AIR_ALT + sin(t * 1.5 + u.id) * 0.3
	elif naval:
		y = WATER_Y - 0.05 + sin(t * 1.8 + u.id) * 0.06
	else:
		y = sim.map.height_at(p)
		if u.moving:
			y += absf(sin(t * 11.0 + u.id)) * 0.08
	var fwd = Vector3(cos(u.facing), 0, sin(u.facing))
	var off = Vector3.ZERO
	if u.swing > 0.0 and u.def.range < 1.5:
		off = fwd * sin(u.swing / 0.3 * PI) * 0.25
	n.position = Vector3(p.x * TILE, y, p.y * TILE) + off
	n.rotation.y = lerp_angle(n.rotation.y, -u.facing, minf(1.0, delta * 12.0))
	if air:
		mi.rotation.z = 0.0
		mi.rotation.x = sin(t + u.id) * 0.12
	elif naval:
		mi.rotation.x = sin(t * 1.3 + u.id) * 0.04
	elif u.working:
		mi.rotation.z = sin(t * 9.0 + u.id) * 0.12
	else:
		mi.rotation.z = 0.0
	if u.hit_t > 0.0:
		mi.position.y = 0.04
	else:
		mi.position.y = 0.0

func _sync_building(b: Ent, n: Node3D) -> void:
	var mi: MeshInstance3D = n.get_node("M")
	var ep: int = sim.players[b.owner].epoch
	var key = "%s:%d:%d" % [b.type, b.owner, ep]
	if _mesh_key.get(b.id, "") != key:
		_mesh_key[b.id] = key
		mi.mesh = Models.building_mesh(b.type, sim.players[b.owner].color, ep)
	var sc: Node3D = n.get_node_or_null("S")
	if not b.built:
		mi.scale = Vector3(1, maxf(0.12, b.progress), 1)
		if sc == null and not b.def.get("farm", false) and not b.def.get("wall", false):
			sc = MeshInstance3D.new()
			sc.name = "S"
			sc.mesh = _scaffold_mesh(b.size)
			n.add_child(sc)
	else:
		mi.scale = Vector3.ONE
		if sc:
			sc.queue_free()
	var smoke: CPUParticles3D = n.get_node_or_null("Smoke")
	var burning = b.built and b.hp < b.max_hp * 0.5
	if burning and smoke == null:
		smoke = _make_smoke(b.size)
		n.add_child(smoke)
	if smoke:
		smoke.emitting = burning

func _make_smoke(size: int) -> CPUParticles3D:
	var p = CPUParticles3D.new()
	p.name = "Smoke"
	var qm = QuadMesh.new()
	qm.size = Vector2(1.2, 1.2)
	qm.material = _smoke_mat
	p.mesh = qm
	p.amount = 14
	p.lifetime = 2.5
	p.position = Vector3(0, 2.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(size * 0.6, 0.5, size * 0.6)
	p.direction = Vector3(0.2, 1, 0)
	p.spread = 15.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.2
	var g = Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.15, 0.9))
	g.add_point(0.25, Color(0.25, 0.25, 0.25, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = g
	return p

# ------------------------------------------------------------------ projectiles & effects
func _sync_projectiles() -> void:
	var prs = sim.projectiles
	while _proj_pool.size() < prs.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_proj_pool.append(mi)
	for i in _proj_pool.size():
		var mi: MeshInstance3D = _proj_pool[i]
		if i >= prs.size():
			mi.visible = false
			continue
		var pr: Dictionary = prs[i]
		mi.visible = true
		mi.mesh = Models.projectile_mesh(pr.kind)
		var k: float = minf(1.0, pr.t / pr.dur)
		var to_h = sim.map.height_at(pr.to) + 0.6
		var tgt = sim.get_ent(pr.target)
		if tgt and tgt.kind == Ent.UNIT and tgt.def.get("air", false):
			to_h = maxf(sim.map.height_at(pr.to), 0.0) + AIR_ALT
		elif tgt and tgt.kind == Ent.UNIT and tgt.def.get("naval", false):
			to_h = WATER_Y + 0.5
		var dist: float = pr.from.distance_to(pr.to) * TILE
		var arc = 0.0
		if pr.kind in ["arrow", "stone", "boulder", "grenade", "ball", "shell"]:
			arc = minf(6.0, dist * 0.18)
		var p2: Vector2 = pr.pos
		var h: float = lerpf(pr.h0, to_h, k) + arc * sin(k * PI)
		mi.position = Vector3(p2.x * TILE, h, p2.y * TILE)
		var dir = Vector3((pr.to.x - pr.from.x) * TILE, (to_h - pr.h0) + arc * PI * cos(k * PI), (pr.to.y - pr.from.y) * TILE)
		if dir.length_squared() > 0.001:
			mi.basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT).rotated(Vector3.UP, PI * 0.5)

func handle_fx(events: Array) -> void:
	for f in events:
		match f.k:
			"boom":
				_explosion(ground(f.p) + Vector3(0, 0.3, 0), 0.8 + f.r * 1.2)
			"collapse":
				_dust(ground(f.p), f.size)
			"convert":
				_sparkle(ground(f.p) + Vector3(0, 1.0, 0), Color("#c4b5fd"))
			"heal":
				var b = sim.get_ent(f.b)
				if b:
					_sparkle(ground(b.pos) + Vector3(0, 1.2, 0), Color("#86efac"), 4)
			"convert_beam":
				var b = sim.get_ent(f.b)
				if b:
					_sparkle(ground(b.pos) + Vector3(0, 1.4, 0), Color("#c4b5fd"), 5)

func _explosion(at: Vector3, r: float) -> void:
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 12; sm.rings = 6
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.65, 0.2, 0.9)
	sm.material = mat
	mi.mesh = sm
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_effects.append({"node": mi, "t": 0.0, "dur": 0.45, "kind": "boom", "r": r, "mat": mat})
	_dust(at, 0.6, Color(0.35, 0.33, 0.3, 0.8))

func _dust(at: Vector3, size: float, col := Color(0.6, 0.55, 0.45, 0.8)) -> void:
	var p = CPUParticles3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	qm.material = _smoke_mat
	p.mesh = qm
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = int(10 + size * 8)
	p.lifetime = 1.6
	p.position = at + Vector3(0, 0.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.8
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -0.5, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5 + size * 0.4
	var g = Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.emitting = true
	add_child(p)
	_effects.append({"node": p, "t": 0.0, "dur": 2.0, "kind": "particles"})

func _sparkle(at: Vector3, col: Color, n := 14) -> void:
	var p = CPUParticles3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(0.25, 0.25)
	qm.material = _smoke_mat
	p.mesh = qm
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = n
	p.lifetime = 0.9
	p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	var g = Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	p.emitting = true
	add_child(p)
	_effects.append({"node": p, "t": 0.0, "dur": 1.2, "kind": "particles"})

func _update_effects(delta: float) -> void:
	var keep = []
	for ef in _effects:
		ef.t += delta
		var k: float = ef.t / ef.dur
		var n: Node3D = ef.node
		if k >= 1.0:
			n.queue_free()
			continue
		match ef.kind:
			"boom":
				n.scale = Vector3.ONE * ef.r * (0.5 + k)
				ef.mat.albedo_color.a = 0.9 * (1.0 - k)
			"marker":
				n.scale = Vector3.ONE * (1.2 - k * 0.8)
				ef.mat.albedo_color.a = 1.0 - k
			"sink":
				var mi: Node3D = n.get_node("M")
				if ef.bld:
					n.position.y = ef.y0 - k * k * 6.0
				else:
					if k < 0.25:
						mi.rotation.z = lerpf(0.0, PI * 0.45, k / 0.25)
					n.position.y = ef.y0 - maxf(0.0, k - 0.4) * 1.5
		keep.append(ef)
	_effects = keep

# ------------------------------------------------------------------ placement ghosts & rally
func set_ghosts(type: String, tiles: Array, oks: Array) -> void:
	while _ghosts.size() < tiles.size():
		var mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_ghosts.append(mi)
	for i in _ghosts.size():
		var g: MeshInstance3D = _ghosts[i]
		if i >= tiles.size():
			g.visible = false
			continue
		var def: Dictionary = Defs.BUILDINGS[type]
		var t: Vector2i = tiles[i]
		g.visible = true
		g.mesh = Models.building_mesh(type, sim.players[0].color, sim.players[0].epoch)
		g.material_override = _ghost_mats["ok" if oks[i] else "bad"]
		var p = Vector2(t.x + def.size * 0.5, t.y + def.size * 0.5)
		var y = WATER_Y if def.get("naval", false) else sim.map.height_at(p)
		g.position = Vector3(p.x * TILE, y, p.y * TILE)

## Brief shrinking ring that confirms an order on the ground.
func marker(p: Vector2, col: Color) -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = _ring_mesh
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y = maxf(sim.map.height_at(p), WATER_Y) + 0.1
	mi.position = Vector3(p.x * TILE, y, p.y * TILE)
	add_child(mi)
	_effects.append({"node": mi, "t": 0.0, "dur": 0.6, "kind": "marker", "mat": m})

func show_rally(b: Ent) -> void:
	if b and b.has_rally:
		_rally.visible = true
		_rally.position = ground(b.rally)
	else:
		_rally.visible = false
