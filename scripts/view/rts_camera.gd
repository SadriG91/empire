class_name RTSCamera
extends Node3D
## Orbiting strategy camera: pan, rotate, tilt and zoom around a focus point on the ground.

var cam: Camera3D
var focus := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(52.0)
var dist := 34.0
var bounds := Rect2(0, 0, 200, 200)
var height_fn: Callable
var _h := 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.5
	cam.far = 700.0
	add_child(cam)
	cam.make_current()
	apply()

func apply() -> void:
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	if height_fn.is_valid():
		var target_h: float = maxf(height_fn.call(focus), -0.3)
		_h = lerpf(_h, target_h, 0.2)
	var off = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var f = Vector3(focus.x, _h, focus.z)
	cam.global_position = f + off
	cam.look_at(f, Vector3.UP)

func pan(dx: float, dz: float) -> void:
	var right = Vector3(cos(yaw), 0, -sin(yaw))
	var fwd = Vector3(-sin(yaw), 0, -cos(yaw))
	var k = dist / 34.0
	focus += (right * dx + fwd * dz) * k
	apply()

func rotate_by(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, deg_to_rad(25.0), deg_to_rad(80.0))
	apply()

func zoom(f: float) -> void:
	dist = clampf(dist * f, 12.0, 90.0)
	apply()

func center_on(p: Vector3) -> void:
	focus = Vector3(p.x, 0, p.z)
	apply()

## Ground point under a screen position (ray-marched against the height field).
func ground_at(screen: Vector2) -> Vector3:
	var o = cam.project_ray_origin(screen)
	var d = cam.project_ray_normal(screen)
	if absf(d.y) < 0.001:
		return Vector3(focus.x, 0, focus.z)
	var h = 0.0
	var p = o
	for i in 6:
		var t = (h - o.y) / d.y
		p = o + d * t
		if height_fn.is_valid():
			h = maxf(height_fn.call(p), -0.35)
	return p
