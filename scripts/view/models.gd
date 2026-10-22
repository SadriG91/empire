class_name Models
extends RefCounted
## Procedural low-poly models. Every model is merged into one vertex-coloured ArrayMesh
## (one draw call) and cached per (key, colour, epoch). Units face +X; origin at the feet.

const SKIN := Color("#e0b48a")
const WOOD := Color("#7a5230")
const DARKWOOD := Color("#4e3420")
const METAL := Color("#b8bec6")
const DARK := Color("#2b2f36")
const OLIVE := Color("#5a6532")
const GOLD := Color("#f2c230")
const WHITE := Color("#eceae4")
const CLOTH := Color("#3d3a35")

static var _cache := {}
static var _prims := {}
static var _mat: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.85
	return _mat

static func _prim(key: String) -> Array:
	if _prims.has(key):
		return _prims[key]
	var m: PrimitiveMesh
	match key:
		"box":
			m = BoxMesh.new()
		"sphere":
			var s = SphereMesh.new()
			s.radius = 0.5; s.height = 1.0; s.radial_segments = 10; s.rings = 6
			m = s
		"prism":
			m = PrismMesh.new()
		"cyl":
			var c = CylinderMesh.new()
			c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 8; c.rings = 1
			m = c
		"cone":
			var c = CylinderMesh.new()
			c.top_radius = 0.0; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 8; c.rings = 1
			m = c
		"cyl16":
			var c = CylinderMesh.new()
			c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 16; c.rings = 1
			m = c
		"frustum":
			var c = CylinderMesh.new()
			c.top_radius = 0.3; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 8; c.rings = 1
			m = c
	var arr = m.get_mesh_arrays()
	_prims[key] = arr
	return arr

## Mesh builder.
class B:
	var st = SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func add(key: String, at: Vector3, scale: Vector3, col: Color, rot_deg := Vector3.ZERO) -> void:
		var arr: Array = Models._prim(key)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var basis = Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scale)
		var xf = Transform3D(basis, at)
		var nb = basis.inverse().transposed()
		var lin := col.srgb_to_linear()
		for i in idx:
			st.set_color(lin)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])

	func box(size: Vector3, at: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		add("box", at, size, col, rot)

	func cyl(r: float, h: float, at: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		add("cyl", at, Vector3(r * 2, h, r * 2), col, rot)

	func cone(r: float, h: float, at: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		add("cone", at, Vector3(r * 2, h, r * 2), col, rot)

	func ball(r: float, at: Vector3, col: Color, sc := Vector3.ONE) -> void:
		add("sphere", at, Vector3(r * 2, r * 2, r * 2) * sc, col)

	func prism(size: Vector3, at: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		add("prism", at, size, col, rot)

	func mesh() -> ArrayMesh:
		var m = st.commit()
		m.surface_set_material(0, Models.material())
		return m

static func _shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, 1.0)

# ============================================================================ units
static func unit_mesh(type: String, color: Color, epoch: int) -> ArrayMesh:
	var key = "u:%s:%s:%d" % [type, color.to_html(), epoch]
	if _cache.has(key):
		return _cache[key]
	var def: Dictionary = Defs.UNITS[type]
	var b = B.new()
	var model: String = def.get("model", "club")
	match model:
		"horse", "horse_gun":
			_horse(b, Vector3.ZERO)
			_human(b, Vector3(-0.08, 0.72, 0), color, epoch, "gun" if model == "horse_gun" else ("spear" if type == "horseman" else "sword"), 0.85, true)
		"tank": _tank(b, color)
		"catapult": _catapult(b, color)
		"cannon": _cannon(b, color, false)
		"artillery": _cannon(b, color, true)
		"rocket": _rocket_truck(b, color, false)
		"sam": _rocket_truck(b, color, true)
		"flak": _flak(b, color)
		"priest": _priest(b, color)
		"medic": _human(b, Vector3.ZERO, color, epoch, "medic", 1.0, false)
		"hero": _human(b, Vector3.ZERO, color, epoch, "hero_gun" if def.get("proj", "") != "" else "hero", 1.3, false)
		"fishing_boat", "galley", "galleon", "frigate", "ironclad", "battleship": _ship(b, model, color)
		"biplane", "jet", "zeppelin", "bomber": _aircraft(b, model, color)
		_:
			_human(b, Vector3.ZERO, color, epoch, model, 1.0, false)
	var m = b.mesh()
	_cache[key] = m
	return m

static func _human(b: B, o: Vector3, c: Color, epoch: int, weapon: String, s: float, mounted: bool) -> void:
	var torso = c
	var pants = Color("#4a4036") if epoch < 3 else Color("#3a3f47")
	if weapon == "medic":
		torso = WHITE
	if not mounted:
		b.box(Vector3(0.12, 0.45, 0.12) * s, o + Vector3(0, 0.225, 0.09) * s, pants)
		b.box(Vector3(0.12, 0.45, 0.12) * s, o + Vector3(0, 0.225, -0.09) * s, pants)
	else:
		b.box(Vector3(0.3, 0.12, 0.12) * s, o + Vector3(0.05, 0.42, 0.2) * s, pants)
		b.box(Vector3(0.3, 0.12, 0.12) * s, o + Vector3(0.05, 0.42, -0.2) * s, pants)
	b.box(Vector3(0.22, 0.42, 0.34) * s, o + Vector3(0, 0.66, 0) * s, torso)
	b.box(Vector3(0.23, 0.05, 0.35) * s, o + Vector3(0, 0.5, 0) * s, DARKWOOD)
	b.box(Vector3(0.1, 0.36, 0.1) * s, o + Vector3(0.04, 0.66, 0.22) * s, _shade(torso, 0.85))
	b.box(Vector3(0.1, 0.36, 0.1) * s, o + Vector3(0.04, 0.66, -0.22) * s, _shade(torso, 0.85))
	b.ball(0.13 * s, o + Vector3(0, 1.0, 0) * s, SKIN)
	var hand = o + Vector3(0.14, 0.55, 0.22) * s
	var helmet: Color
	match weapon:
		"tool":
			b.cyl(0.24 * s, 0.06 * s, o + Vector3(0, 1.1, 0) * s, Color("#d6b56a"))
			b.cone(0.13 * s, 0.1 * s, o + Vector3(0, 1.16, 0) * s, Color("#d6b56a"))
		"medic":
			b.box(Vector3(0.23, 0.08, 0.08) * s, o + Vector3(0.0, 0.7, 0) * s + Vector3(0.11, 0, 0) * s, Color("#d22"))
			b.box(Vector3(0.23, 0.2, 0.03) * s, o + Vector3(0.0, 0.7, 0) * s + Vector3(0.11, 0, 0) * s, Color("#d22"))
			helmet = WHITE
		"hero", "hero_gun":
			helmet = GOLD
			b.box(Vector3(0.04, 0.75, 0.42) * s, o + Vector3(-0.15, 0.62, 0) * s, _shade(c, 0.7), Vector3(0, 0, -6))
			b.cyl(0.15 * s, 0.07 * s, o + Vector3(0, 1.14, 0) * s, GOLD)
			for k in 5:
				var a = k * TAU / 5.0
				b.cone(0.03 * s, 0.1 * s, o + Vector3(cos(a) * 0.12, 1.21, sin(a) * 0.12) * s, GOLD)
		_:
			helmet = [Color("#7c5a3a"), Color("#b08d57"), Color("#a8adb4"), Color("#3a3a3a"), Color("#5b6148"), Color("#4b5320")][epoch]
	if helmet != Color(0, 0, 0, 0) and weapon != "tool" and weapon != "hero" and weapon != "hero_gun":
		b.ball(0.145 * s, o + Vector3(0, 1.05, 0) * s, helmet, Vector3(1, 0.6, 1))
	match weapon:
		"tool":
			b.cyl(0.02 * s, 0.7 * s, hand + Vector3(0.12, 0.12, 0) * s, WOOD, Vector3(0, 0, -55))
			b.box(Vector3(0.05, 0.25, 0.05) * s, hand + Vector3(0.38, 0.3, 0) * s, METAL, Vector3(0, 0, 30))
		"club":
			b.cyl(0.05 * s, 0.6 * s, hand + Vector3(0.18, 0.15, 0) * s, WOOD, Vector3(0, 0, -50))
		"spear":
			b.cyl(0.02 * s, 1.7 * s, hand + Vector3(0.3, 0.3, 0) * s, WOOD, Vector3(0, 0, -70))
			b.cone(0.04 * s, 0.18 * s, hand + Vector3(1.1, 0.6, 0) * s, METAL, Vector3(0, 0, -70))
			b.cyl(0.18 * s, 0.04 * s, o + Vector3(0.12, 0.68, -0.3) * s, c, Vector3(90, 0, 0))
		"sword", "hero":
			b.box(Vector3(0.6, 0.06, 0.02) * s, hand + Vector3(0.3, 0.05, 0) * s, METAL, Vector3(0, 0, 20))
			b.box(Vector3(0.05, 0.4, 0.3) * s, o + Vector3(0.12, 0.66, -0.29) * s, c if weapon == "sword" else GOLD)
		"gun", "hero_gun":
			b.box(Vector3(0.8, 0.06, 0.06) * s, o + Vector3(0.3, 0.78, 0.12) * s, DARK)
			b.box(Vector3(0.25, 0.08, 0.07) * s, o + Vector3(0.0, 0.76, 0.12) * s, WOOD)
		"mg":
			b.box(Vector3(0.8, 0.11, 0.11) * s, o + Vector3(0.32, 0.72, 0.1) * s, DARK)
			b.box(Vector3(0.12, 0.2, 0.06) * s, o + Vector3(0.25, 0.6, 0.1) * s, DARK)
		"bow":
			b.box(Vector3(0.03, 0.5, 0.03) * s, o + Vector3(0.3, 0.88, -0.2) * s, WOOD, Vector3(0, 0, 18))
			b.box(Vector3(0.03, 0.5, 0.03) * s, o + Vector3(0.3, 0.45, -0.2) * s, WOOD, Vector3(0, 0, -18))
			b.box(Vector3(0.12, 0.45, 0.12) * s, o + Vector3(-0.15, 0.75, 0.0) * s, Color("#8b5a2b"), Vector3(0, 0, 15))
		"sling":
			b.cyl(0.01 * s, 0.4 * s, hand + Vector3(0.05, 0.2, 0) * s, Color("#a16207"), Vector3(0, 0, -30))
			b.ball(0.05 * s, hand + Vector3(0.15, 0.38, 0) * s, Color("#777"))
		"grenade":
			b.ball(0.07 * s, hand + Vector3(0.05, 0.25, 0) * s, Color("#365314"))
			b.box(Vector3(0.1, 0.12, 0.36) * s, o + Vector3(0.12, 0.5, 0) * s, Color("#4d5b2a"))

static func _priest(b: B, c: Color) -> void:
	b.add("frustum", Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6), WHITE)
	b.box(Vector3(0.05, 0.75, 0.12), Vector3(0.14, 0.5, 0), c)
	b.ball(0.13, Vector3(0, 1.0, 0), SKIN)
	b.ball(0.16, Vector3(-0.02, 1.04, 0), WHITE, Vector3(1, 0.8, 1))
	b.cyl(0.025, 1.4, Vector3(0.18, 0.7, 0.25), WOOD)
	b.ball(0.08, Vector3(0.18, 1.45, 0.25), GOLD)

static func _horse(b: B, o: Vector3) -> void:
	var hc = Color("#6b4226")
	b.box(Vector3(1.0, 0.42, 0.36), o + Vector3(0, 0.9, 0), hc)
	for lx in [-0.38, 0.38]:
		for lz in [-0.12, 0.12]:
			b.box(Vector3(0.09, 0.72, 0.09), o + Vector3(lx, 0.36, lz), _shade(hc, 0.8))
	b.box(Vector3(0.18, 0.5, 0.2), o + Vector3(0.5, 1.15, 0), hc, Vector3(0, 0, -35))
	b.box(Vector3(0.38, 0.17, 0.16), o + Vector3(0.7, 1.33, 0), hc, Vector3(0, 0, -20))
	b.box(Vector3(0.06, 0.4, 0.06), o + Vector3(-0.55, 0.85, 0), Color("#2b1a0e"), Vector3(0, 0, 25))
	b.box(Vector3(0.4, 0.04, 0.4), o + Vector3(-0.05, 1.12, 0), Color("#8b1a1a"))

static func _wheels(b: B, xs: Array, r: float, half_w: float) -> void:
	for x in xs:
		for z in [-half_w, half_w]:
			b.cyl(r, 0.08, Vector3(x, r, z), DARKWOOD, Vector3(90, 0, 0))

static func _catapult(b: B, c: Color) -> void:
	_wheels(b, [-0.45, 0.45], 0.22, 0.42)
	b.box(Vector3(1.3, 0.12, 0.7), Vector3(0, 0.32, 0), WOOD)
	b.box(Vector3(0.12, 0.7, 0.12), Vector3(-0.1, 0.7, 0.25), WOOD)
	b.box(Vector3(0.12, 0.7, 0.12), Vector3(-0.1, 0.7, -0.25), WOOD)
	b.box(Vector3(1.3, 0.08, 0.08), Vector3(-0.2, 0.85, 0), DARKWOOD, Vector3(0, 0, 35))
	b.ball(0.13, Vector3(-0.72, 1.25, 0), Color("#777"))
	b.box(Vector3(0.1, 0.25, 0.3), Vector3(-0.6, 0.5, 0), c)

static func _cannon(b: B, c: Color, modern: bool) -> void:
	var body = OLIVE if modern else WOOD
	_wheels(b, [-0.1], 0.32, 0.38)
	b.box(Vector3(1.0, 0.18, 0.3), Vector3(-0.35, 0.35, 0), body, Vector3(0, 0, 12))
	var l = 1.6 if modern else 1.1
	b.cyl(0.09 if modern else 0.12, l, Vector3(l * 0.35, 0.62, 0), DARK if not modern else Color("#3f4a1f"), Vector3(0, 0, -78))
	if modern:
		b.box(Vector3(0.05, 0.5, 0.7), Vector3(0.05, 0.62, 0), Color("#3f4a1f"))
	b.box(Vector3(0.12, 0.12, 0.12), Vector3(-0.8, 0.25, 0), c)

static func _rocket_truck(b: B, c: Color, sam: bool) -> void:
	_wheels(b, [-0.55, 0.0, 0.55], 0.22, 0.42)
	b.box(Vector3(1.7, 0.35, 0.8), Vector3(0, 0.45, 0), OLIVE)
	b.box(Vector3(0.45, 0.4, 0.75), Vector3(0.62, 0.8, 0), _shade(OLIVE, 0.85))
	b.box(Vector3(0.4, 0.15, 0.76), Vector3(0.62, 0.95, 0), Color("#9fc3d8"))
	if sam:
		for z in [-0.18, 0.18]:
			b.cyl(0.08, 1.1, Vector3(-0.25, 1.05, z), WHITE, Vector3(0, 0, -60))
			b.cone(0.08, 0.2, Vector3(0.25, 1.33, z), Color("#c33"), Vector3(0, 0, -60))
	else:
		b.box(Vector3(1.0, 0.35, 0.7), Vector3(-0.3, 0.95, 0), Color("#3f4a1f"), Vector3(0, 0, 20))
		for k in 4:
			b.cyl(0.05, 0.05, Vector3(0.18, 1.12, -0.25 + k * 0.17), Color("#c33"), Vector3(0, 0, -70))
	b.box(Vector3(0.3, 0.06, 0.82), Vector3(-0.6, 0.65, 0), c)

static func _flak(b: B, c: Color) -> void:
	b.cyl(0.5, 0.25, Vector3(0, 0.12, 0), OLIVE)
	b.box(Vector3(0.5, 0.35, 0.5), Vector3(0, 0.42, 0), _shade(OLIVE, 0.9))
	for z in [-0.12, 0.12]:
		b.cyl(0.05, 1.1, Vector3(0.3, 0.9, z), DARK, Vector3(0, 0, -50))
	b.box(Vector3(0.52, 0.06, 0.52), Vector3(0, 0.62, 0), c)

static func _tank(b: B, c: Color) -> void:
	b.box(Vector3(1.6, 0.32, 0.25), Vector3(0, 0.2, 0.42), DARK)
	b.box(Vector3(1.6, 0.32, 0.25), Vector3(0, 0.2, -0.42), DARK)
	b.box(Vector3(1.5, 0.32, 0.7), Vector3(0, 0.42, 0), OLIVE)
	b.box(Vector3(0.3, 0.33, 0.72), Vector3(-0.55, 0.42, 0), c)
	b.cyl(0.32, 0.25, Vector3(-0.05, 0.7, 0), _shade(OLIVE, 0.85))
	b.cyl(0.06, 1.1, Vector3(0.6, 0.72, 0), _shade(OLIVE, 0.75), Vector3(0, 0, -90))

static func _ship(b: B, model: String, c: Color) -> void:
	var L = {"fishing_boat": 1.8, "galley": 2.8, "galleon": 3.2, "frigate": 3.5, "ironclad": 3.3, "battleship": 4.2}[model]
	var steel = model == "ironclad" or model == "battleship"
	var hull = Color("#6b6f75") if steel else Color("#6e4a2a")
	var W = L * 0.32
	b.box(Vector3(L * 0.8, 0.45, W), Vector3(-L * 0.05, 0.1, 0), hull)
	b.prism(Vector3(W, L * 0.25, 0.45), Vector3(L * 0.45, 0.1, 0), hull, Vector3(90, 0, -90))
	b.box(Vector3(L * 0.82, 0.06, W * 0.9), Vector3(-L * 0.05, 0.35, 0), Color("#a07a4a") if not steel else Color("#8a8f96"))
	b.box(Vector3(L * 0.8, 0.08, W * 1.02), Vector3(-L * 0.05, 0.3, 0), c)
	match model:
		"fishing_boat":
			b.cyl(0.03, 1.0, Vector3(0, 0.85, 0), WOOD)
			b.box(Vector3(0.04, 0.6, 0.5), Vector3(0.05, 0.95, 0), WHITE)
			b.box(Vector3(0.5, 0.05, 0.4), Vector3(-0.5, 0.42, 0), Color("#c8b88a"))
		"galley":
			b.cyl(0.04, 1.8, Vector3(0, 1.25, 0), WOOD)
			b.box(Vector3(0.05, 1.0, 1.1), Vector3(0.05, 1.4, 0), c)
			for k in 5:
				b.box(Vector3(0.05, 0.05, W * 1.8), Vector3(-0.9 + k * 0.4, 0.2, 0), WOOD, Vector3(0, 0, 15))
		"galleon", "frigate":
			var masts = [-0.8, 0.2, 1.0] if model == "frigate" else [-0.6, 0.5]
			for mx in masts:
				b.cyl(0.05, 2.4, Vector3(mx, 1.5, 0), WOOD)
				b.box(Vector3(0.05, 0.75, 1.2), Vector3(mx + 0.05, 1.35, 0), WHITE)
				b.box(Vector3(0.05, 0.55, 0.95), Vector3(mx + 0.05, 2.15, 0), WHITE)
				b.box(Vector3(0.06, 0.18, 0.3), Vector3(mx, 2.75, 0), c)
			b.box(Vector3(0.7, 0.45, W * 0.9), Vector3(-L * 0.38, 0.6, 0), Color("#8a5a32"))
		"ironclad":
			b.box(Vector3(1.0, 0.35, W * 0.7), Vector3(0.0, 0.55, 0), Color("#4b4f55"))
			b.cyl(0.14, 0.9, Vector3(-0.4, 0.95, 0), DARK)
			b.cyl(0.05, 0.9, Vector3(0.8, 0.6, 0), DARK, Vector3(0, 0, -90))
		"battleship":
			b.box(Vector3(0.9, 0.6, W * 0.6), Vector3(-0.3, 0.7, 0), Color("#7b8087"))
			b.box(Vector3(0.3, 0.5, 0.3), Vector3(-0.3, 1.25, 0), Color("#7b8087"))
			b.cyl(0.15, 0.8, Vector3(-0.8, 0.9, 0), DARK)
			for tx in [1.1, 0.55, -1.4]:
				b.cyl(0.28, 0.22, Vector3(tx, 0.5, 0), Color("#5d6268"))
				for z in [-0.08, 0.08]:
					b.cyl(0.04, 0.8, Vector3(tx + (0.45 if tx > 0 else -0.45), 0.55, z), DARK, Vector3(0, 0, 90))

static func _aircraft(b: B, model: String, c: Color) -> void:
	match model:
		"biplane":
			b.box(Vector3(1.4, 0.22, 0.22), Vector3(0, 0, 0), c)
			b.box(Vector3(0.35, 0.04, 2.2), Vector3(0.15, 0.2, 0), Color("#d8c9a3"))
			b.box(Vector3(0.35, 0.04, 2.2), Vector3(0.15, -0.12, 0), Color("#d8c9a3"))
			b.box(Vector3(0.25, 0.04, 0.7), Vector3(-0.62, 0.05, 0), Color("#d8c9a3"))
			b.box(Vector3(0.25, 0.3, 0.04), Vector3(-0.62, 0.18, 0), c)
			b.box(Vector3(0.04, 0.6, 0.08), Vector3(0.72, 0, 0), DARK)
		"jet":
			b.box(Vector3(1.8, 0.22, 0.24), Vector3(0, 0, 0), Color("#8a949e"))
			b.cone(0.12, 0.4, Vector3(1.1, 0, 0), Color("#6b747d"), Vector3(0, 0, -90))
			b.prism(Vector3(1.6, 0.9, 0.04), Vector3(-0.15, 0, 0), Color("#7b858f"), Vector3(90, 0, 90))
			b.box(Vector3(0.35, 0.45, 0.04), Vector3(-0.75, 0.25, 0), c)
			b.box(Vector3(0.3, 0.1, 0.18), Vector3(0.45, 0.14, 0), Color("#9fc3d8"))
		"zeppelin":
			b.ball(0.5, Vector3(0, 0.3, 0), Color("#b9b4a6"), Vector3(4.6, 1.3, 1.3))
			b.box(Vector3(0.8, 0.22, 0.25), Vector3(0.1, -0.45, 0), DARK)
			b.box(Vector3(0.4, 0.5, 0.04), Vector3(-1.9, 0.5, 0), c)
			b.box(Vector3(0.4, 0.04, 0.9), Vector3(-1.9, 0.3, 0), c)
			b.box(Vector3(2.5, 0.06, 1.33), Vector3(0, 0.3, 0), c)
		"bomber":
			b.box(Vector3(2.2, 0.32, 0.32), Vector3(0, 0, 0), Color("#7e8a6a"))
			b.box(Vector3(0.6, 0.06, 3.4), Vector3(0.1, 0.0, 0), Color("#6f7a5c"))
			for z in [-1.1, -0.5, 0.5, 1.1]:
				b.cyl(0.09, 0.4, Vector3(0.35, 0, z), DARK, Vector3(0, 0, -90))
			b.box(Vector3(0.35, 0.05, 1.1), Vector3(-1.0, 0.1, 0), Color("#6f7a5c"))
			b.box(Vector3(0.35, 0.5, 0.05), Vector3(-1.0, 0.32, 0), c)

# ============================================================================ buildings
static func building_mesh(type: String, color: Color, epoch: int) -> ArrayMesh:
	var key = "b:%s:%s:%d" % [type, color.to_html(), epoch]
	if _cache.has(key):
		return _cache[key]
	var def: Dictionary = Defs.BUILDINGS[type]
	var S: float = def.size * 2.0
	var st: Array = Defs.EPOCH_STYLE[epoch]
	var wall: Color = st[0]
	var roof: Color = st[1]
	var trim: Color = st[2]
	var b = B.new()
	var h = S * 0.5
	match type:
		"town_center":
			_hall(b, Vector3(0, 0, 0), Vector3(S * 0.85, 1.9, S * 0.7), wall, roof, trim, epoch)
			b.box(Vector3(1.6, 4.2, 1.6), Vector3(0, 2.1, 0), wall)
			_roof(b, Vector3(0, 4.2, 0), Vector3(1.9, 1.2, 1.9), roof, epoch, true)
			_flag(b, Vector3(0.6, 5.0, 0.6), color, 1.6)
			_door(b, Vector3(S * 0.43, 0, 0), 1.0, 1.3)
		"house":
			if epoch == 0:
				b.cyl(1.2, 1.3, Vector3(0, 0.65, 0), wall)
				b.cone(1.5, 1.4, Vector3(0, 2.0, 0), roof)
			else:
				_hall(b, Vector3.ZERO, Vector3(S * 0.75, 1.5, S * 0.6), wall, roof, trim, epoch)
			b.box(Vector3(0.1, 0.25, 0.8), Vector3(S * 0.38, 1.25, 0), color)
			_door(b, Vector3(S * 0.38 if epoch > 0 else 1.2, 0, 0), 0.6, 0.9)
		"farm":
			b.box(Vector3(S * 0.95, 0.08, S * 0.95), Vector3(0, 0.04, 0), Color("#6a4d2a"))
			for k in 6:
				var z = -S * 0.4 + k * S * 0.16
				b.box(Vector3(S * 0.85, 0.12, 0.22), Vector3(0, 0.1, z), Color("#5f7f2e") if k % 2 else Color("#b9a443"))
			for k in 4:
				var a = k * PI * 0.5
				b.box(Vector3(S * 0.98, 0.25, 0.05), Vector3(cos(a) * S * 0.48, 0.15, sin(a) * S * 0.48), WOOD, Vector3(0, rad_to_deg(a) + 90, 0))
			b.box(Vector3(0.2, 0.6, 0.2), Vector3(S * 0.45, 0.3, S * 0.45), color)
		"storehouse":
			_hall(b, Vector3.ZERO, Vector3(S * 0.7, 1.6, S * 0.7), wall, roof, trim, epoch)
			for k in 3:
				b.box(Vector3(0.5, 0.5, 0.5), Vector3(S * 0.42, 0.25, -0.8 + k * 0.6), Color("#a9773f"))
			b.box(Vector3(0.1, 0.3, 1.0), Vector3(S * 0.36, 1.4, 0), color)
		"dock":
			b.box(Vector3(S, 0.2, S), Vector3(0, 0.45, 0), Color("#8a6a42"))
			for x in [-1, 1]:
				for z in [-1, 1]:
					b.cyl(0.12, 1.4, Vector3(x * S * 0.42, 0.0, z * S * 0.42), DARKWOOD)
			b.box(Vector3(1.2, 1.2, 1.4), Vector3(-0.8, 1.15, -0.5), wall)
			_roof(b, Vector3(-0.8, 1.75, -0.5), Vector3(1.4, 0.6, 1.6), roof, epoch, false)
			b.cyl(0.08, 2.4, Vector3(1.2, 1.7, 1.2), WOOD)
			b.box(Vector3(1.2, 0.08, 0.08), Vector3(0.7, 2.8, 1.2), WOOD)
			_flag(b, Vector3(1.2, 2.9, 1.2), color, 0.8)
		"barracks", "archery_range", "stable", "academy", "temple", "workshop":
			_special(b, type, S, wall, roof, trim, epoch, color)
		"tower":
			var r = S * 0.32
			if epoch >= 4:
				b.box(Vector3(r * 1.6, 5.0, r * 1.6), Vector3(0, 2.5, 0), Color("#8a8f94"))
				b.box(Vector3(r * 2.2, 0.8, r * 2.2), Vector3(0, 5.2, 0), Color("#5d6268"))
				b.cyl(0.08, 1.2, Vector3(0.5, 5.8, 0), DARK, Vector3(0, 0, -60))
			else:
				b.cyl(r, 5.0, Vector3(0, 2.5, 0), wall)
				b.cyl(r * 1.25, 0.5, Vector3(0, 5.2, 0), trim)
				for k in 6:
					var a = k * TAU / 6.0
					b.box(Vector3(0.3, 0.4, 0.3), Vector3(cos(a) * r * 1.1, 5.6, sin(a) * r * 1.1), wall)
			_flag(b, Vector3(0, 5.6, 0), color, 1.2)
		"wall":
			var wc = Color("#8f8a80") if epoch < 4 else Color("#a2a6a8")
			b.box(Vector3(2.0, 1.8, 1.2), Vector3(0, 0.9, 0), wc)
			b.box(Vector3(2.02, 0.12, 1.25), Vector3(0, 1.85, 0), _shade(wc, 0.8))
			for k in 3:
				b.box(Vector3(0.35, 0.35, 1.2), Vector3(-0.65 + k * 0.65, 2.05, 0), wc)
			b.box(Vector3(2.04, 0.1, 0.05), Vector3(0, 1.5, 0.62), color)
		"airfield":
			b.box(Vector3(S * 0.95, 0.06, S * 0.4), Vector3(0, 0.03, S * 0.2), Color("#3d4044"))
			for k in 6:
				b.box(Vector3(0.6, 0.07, 0.12), Vector3(-S * 0.38 + k * S * 0.15, 0.04, S * 0.2), WHITE)
			b.box(Vector3(S * 0.5, 2.4, S * 0.4), Vector3(-S * 0.18, 1.2, -S * 0.22), Color("#8a8f94"))
			b.cyl(S * 0.2, S * 0.5, Vector3(-S * 0.18, 2.4, -S * 0.22), Color("#9aa0a6"), Vector3(0, 90, 90))
			b.box(Vector3(0.9, 3.6, 0.9), Vector3(S * 0.35, 1.8, -S * 0.3), Color("#b5babd"))
			b.box(Vector3(1.3, 0.7, 1.3), Vector3(S * 0.35, 3.9, -S * 0.3), Color("#9fc3d8"))
			_flag(b, Vector3(S * 0.35, 4.3, -S * 0.3), color, 1.0)
		"wonder":
			for i in 4:
				var inset = i * 0.85
				var col = wall if i % 2 == 0 else trim
				b.box(Vector3(S - inset * 2, 1.4, S - inset * 2), Vector3(0, 0.7 + i * 1.4, 0), col)
			b.add("cone", Vector3(0, 6.6, 0), Vector3(1.6, 1.8, 1.6), GOLD)
			for x in [-1, 1]:
				for z in [-1, 1]:
					b.box(Vector3(0.25, 2.8, 0.25), Vector3(x * S * 0.47, 1.4, z * S * 0.47), color)
			_door(b, Vector3(S * 0.5, 0, 0), 1.0, 1.6)
	var m = b.mesh()
	_cache[key] = m
	return m

static func _roof(b: B, at: Vector3, size: Vector3, roof: Color, epoch: int, square: bool) -> void:
	if epoch == 0:
		b.add("cone", at + Vector3(0, size.y * 0.5, 0), Vector3(maxf(size.x, size.z) * 1.15, size.y, maxf(size.x, size.z) * 1.15), roof)
	elif epoch >= 4:
		b.box(Vector3(size.x * 1.02, 0.18, size.z * 1.02), at + Vector3(0, 0.09, 0), roof)
	elif square:
		b.add("cone", at + Vector3(0, size.y * 0.5, 0), Vector3(size.x * 1.4, size.y, size.z * 1.4), roof)
	else:
		b.prism(Vector3(size.x * 1.08, size.y, size.z * 1.08), at + Vector3(0, size.y * 0.5, 0), roof, Vector3(0, 90, 0))

static func _hall(b: B, at: Vector3, size: Vector3, wall: Color, roof: Color, trim: Color, epoch: int) -> void:
	b.box(Vector3(size.x + 0.2, 0.18, size.z + 0.2), at + Vector3(0, 0.09, 0), trim)
	b.box(size, at + Vector3(0, size.y * 0.5 + 0.1, 0), wall)
	_roof(b, at + Vector3(0, size.y + 0.1, 0), Vector3(size.x, size.y * 0.7, size.z), roof, epoch, false)
	var wy = at.y + size.y * 0.6
	var wcol = Color("#2d3748") if epoch < 4 else Color("#9fc3d8")
	for k in 3:
		b.box(Vector3(0.05, 0.35, 0.3), Vector3(at.x + size.x * 0.5 + 0.02, wy, at.z - size.z * 0.3 + k * size.z * 0.3), wcol)

static func _door(b: B, at: Vector3, w: float, h: float) -> void:
	b.box(Vector3(0.08, h, w), at + Vector3(0.02, h * 0.5 + 0.1, 0), Color("#3a2614"))

static func _flag(b: B, at: Vector3, col: Color, pole: float) -> void:
	b.cyl(0.04, pole, at + Vector3(0, pole * 0.5, 0), DARK)
	b.box(Vector3(0.7, 0.42, 0.04), at + Vector3(0.35, pole - 0.22, 0), col)

static func _special(b: B, type: String, S: float, wall: Color, roof: Color, trim: Color, epoch: int, color: Color) -> void:
	match type:
		"temple":
			b.box(Vector3(S * 0.9, 0.4, S * 0.9), Vector3(0, 0.2, 0), trim)
			b.box(Vector3(S * 0.7, 0.4, S * 0.7), Vector3(0, 0.6, 0), wall)
			b.box(Vector3(S * 0.5, 2.4, S * 0.5), Vector3(0, 2.0, 0), WHITE)
			for x in [-1, 1]:
				for z in [-1, 1]:
					b.cyl(0.18, 2.4, Vector3(x * S * 0.3, 2.0, z * S * 0.3), Color("#e9e4d8"))
			b.add("cone", Vector3(0, 4.3, 0), Vector3(S * 0.55, 1.6, S * 0.55), GOLD if epoch >= 2 else roof)
			b.box(Vector3(0.12, 0.6, 0.12), Vector3(0, 5.4, 0), GOLD)
			b.box(Vector3(0.12, 0.12, 0.45), Vector3(0, 5.5, 0), GOLD)
			b.box(Vector3(0.1, 0.4, 1.2), Vector3(S * 0.45, 0.7, 0), color)
			return
		"academy":
			b.box(Vector3(S * 0.85, 0.3, S * 0.75), Vector3(0, 0.15, 0), trim)
			b.box(Vector3(S * 0.6, 2.2, S * 0.6), Vector3(-0.3, 1.4, 0), wall)
			for k in 4:
				b.cyl(0.16, 2.2, Vector3(S * 0.32, 1.4, -S * 0.27 + k * S * 0.18), WHITE)
			b.prism(Vector3(S * 0.75, 0.8, 0.4), Vector3(S * 0.32, 2.9, 0), roof, Vector3(0, 90, 0))
			b.box(Vector3(S * 0.75, 0.25, S * 0.7), Vector3(-0.05, 2.6, 0), trim)
			b.add("sphere", Vector3(-0.3, 2.9, 0), Vector3(2.2, 1.6, 2.2), Color("#6aa0b4") if epoch >= 2 else roof)
			b.box(Vector3(0.1, 0.35, 1.2), Vector3(S * 0.43, 2.25, 0), color)
			return
	_hall(b, Vector3(-S * 0.1, 0, 0), Vector3(S * 0.7, 2.0, S * 0.8), wall, roof, trim, epoch)
	_door(b, Vector3(S * 0.25, 0, 0), 1.0, 1.4)
	b.box(Vector3(0.1, 0.4, 1.6), Vector3(S * 0.25 + 0.05, 1.8, 0), color)
	var yard = Vector3(S * 0.38, 0, 0)
	match type:
		"barracks":
			for k in 4:
				b.cyl(0.05, 1.2, yard + Vector3(0, 0.6, -S * 0.35 + k * S * 0.23), WOOD)
				b.ball(0.15, yard + Vector3(0, 1.25, -S * 0.35 + k * S * 0.23), Color("#c8a46a"))
		"archery_range":
			for z in [-S * 0.3, S * 0.3]:
				b.cyl(0.4, 0.1, yard + Vector3(0, 0.7, z), WHITE, Vector3(0, 0, 90))
				b.cyl(0.25, 0.12, yard + Vector3(0.01, 0.7, z), Color("#d22"), Vector3(0, 0, 90))
				b.cyl(0.08, 0.14, yard + Vector3(0.02, 0.7, z), WHITE, Vector3(0, 0, 90))
		"stable":
			for z in [-S * 0.4, S * 0.4]:
				b.box(Vector3(S * 0.25, 0.6, 0.06), yard + Vector3(0, 0.35, z), WOOD)
			b.box(Vector3(0.6, 0.5, 0.8), yard + Vector3(0.05, 0.25, 0), Color("#d4b45a"))
		"workshop":
			b.cyl(0.25, 2.2, Vector3(-S * 0.3, 3.0, -S * 0.25), DARK)
			b.cyl(0.6, 0.15, yard + Vector3(0, 0.7, 0), Color("#8f959b"), Vector3(90, 0, 0))
			b.box(Vector3(0.8, 0.4, 0.5), yard + Vector3(-0.1, 0.2, S * 0.28), WOOD)

# ============================================================================ resources
static func resource_mesh(type: String, variant: int) -> ArrayMesh:
	var key = "r:%s:%d" % [type, variant]
	if _cache.has(key):
		return _cache[key]
	var b = B.new()
	match type:
		"pine":
			b.cyl(0.15, 1.0, Vector3(0, 0.5, 0), Color("#5b3a1e"))
			var g = Color("#2d5a2a").lerp(Color("#3d6e33"), variant * 0.3)
			for k in 3:
				b.cone(1.1 - k * 0.28, 1.4, Vector3(0, 1.3 + k * 0.8, 0), _shade(g, 1.0 + k * 0.08))
		"oak":
			b.cyl(0.18, 1.4, Vector3(0, 0.7, 0), Color("#5b3a1e"))
			var g = Color("#3f7a2c").lerp(Color("#5a8a32"), variant * 0.3)
			b.ball(0.95, Vector3(0, 2.1, 0), g)
			b.ball(0.7, Vector3(0.5, 1.8, 0.3), _shade(g, 1.08))
			b.ball(0.7, Vector3(-0.45, 1.85, -0.3), _shade(g, 0.92))
		"berries":
			b.ball(0.6, Vector3(0, 0.45, 0), Color("#2f6b2a"), Vector3(1.2, 0.8, 1.2))
			for k in 8:
				var a = k * 2.4
				b.ball(0.09, Vector3(cos(a) * 0.55, 0.5 + sin(k) * 0.15, sin(a) * 0.55), Color("#d63a4a"))
		"gold", "stone":
			var base = Color("#8a7a55") if type == "gold" else Color("#7d7d7d")
			var hi = GOLD if type == "gold" else Color("#c4c4c4")
			b.add("sphere", Vector3(0, 0.3, 0), Vector3(1.6, 0.9, 1.4), base)
			b.add("sphere", Vector3(0.5, 0.25, 0.4), Vector3(0.9, 0.7, 0.9), _shade(base, 1.1))
			for k in 5:
				var a = k * 1.3
				b.box(Vector3(0.28, 0.22, 0.2), Vector3(cos(a) * 0.5, 0.55 + (k % 2) * 0.15, sin(a) * 0.45), hi, Vector3(k * 20, k * 35, 15))
		"fish":
			for k in 3:
				var a = k * TAU / 3.0
				var p = Vector3(cos(a) * 0.5, -0.05, sin(a) * 0.5)
				b.ball(0.18, p, Color("#9ec8e0"), Vector3(1.8, 0.6, 0.8))
				b.prism(Vector3(0.2, 0.2, 0.05), p + Vector3(-0.32, 0, 0), Color("#7fb0cc"), Vector3(0, 0, 90))
	var m = b.mesh()
	_cache[key] = m
	return m

static func projectile_mesh(kind: String) -> ArrayMesh:
	var key = "p:" + kind
	if _cache.has(key):
		return _cache[key]
	var b = B.new()
	match kind:
		"arrow":
			b.box(Vector3(0.7, 0.03, 0.03), Vector3.ZERO, Color("#3b2a1a"))
		"bullet", "flak":
			b.box(Vector3(0.5, 0.05, 0.05), Vector3.ZERO, Color("#ffe9a8"))
		"rocket":
			b.box(Vector3(0.6, 0.12, 0.12), Vector3.ZERO, Color("#ddd"))
			b.ball(0.1, Vector3(-0.35, 0, 0), Color("#ff8c1a"))
		"bomb":
			b.ball(0.18, Vector3.ZERO, DARK, Vector3(1.6, 1, 1))
		_:
			b.ball(0.16 if kind != "boulder" else 0.28, Vector3.ZERO, Color("#555") if kind != "grenade" else Color("#365314"))
	var m = b.mesh()
	_cache[key] = m
	return m
