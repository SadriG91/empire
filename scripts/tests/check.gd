extends SceneTree
## Loads every script to surface parse errors (used for testing).
func _initialize() -> void:
	var bad := 0
	for p in ["res://scripts/defs.gd", "res://scripts/sim/ent.gd", "res://scripts/sim/world_map.gd", "res://scripts/sim/sim.gd", "res://scripts/sim/ai.gd",
			"res://scripts/view/models.gd", "res://scripts/view/world_view.gd", "res://scripts/view/rts_camera.gd", "res://scripts/audio/sfx.gd",
			"res://scripts/ui/controller.gd", "res://scripts/ui/hud.gd", "res://scripts/ui/menu.gd", "res://scripts/main.gd", "res://scripts/tests/shots.gd"]:
		var s: GDScript = load(p)
		if s == null or not s.can_instantiate():
			print("FAILED ", p)
			bad += 1
	print("checked, failures=", bad)
	quit()
