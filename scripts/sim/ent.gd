class_name Ent
extends RefCounted
## A simulation entity: unit, building or resource. Positions are in tiles.

enum { UNIT, BUILDING, RES }

var id := 0
var kind := UNIT
var type := ""
var def: Dictionary = {}
var owner := -1
var pos := Vector2.ZERO
var prev := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var dead := false
var hit_t := 0.0

# --- units
var state := "idle"
var path := PackedVector2Array()
var pi := 0
var target_id := 0
var carry := 0
var carry_res := ""
var gather_id := 0
var gather_type := ""
var build_id := 0
var drop_id := 0
var cd := 0.0
var scan_t := 0.0
var repath_t := 0.0
var amove := false
var amove_to := Vector2.ZERO
var facing := 0.0
var swing := 0.0
var fail := 0
var gacc := 0.0
var working := false
var moving := false
var stance := "aggressive"
var guard := Vector2.ZERO
var has_guard := false
var ordered := false
var kills := 0
var buff_t := 0.0
var conv_t := 0.0
var last_hurt := -99.0
var path_target := Vector2.ZERO

# --- buildings
var tx := 0
var ty := 0
var size := 1
var built := true
var progress := 1.0
var queue: Array = []
var rally := Vector2.ZERO
var has_rally := false
var rally_id := 0
var gatherer_id := 0

# --- resources
var res := ""
var amount := 0.0
var max_amount := 0.0

func is_unit() -> bool:
	return kind == UNIT

func cls() -> String:
	return "building" if kind == BUILDING else def.get("cls", "")

func rank() -> int:
	if kills >= 12:
		return 3
	if kills >= 6:
		return 2
	if kills >= 2:
		return 1
	return 0

func center() -> Vector2:
	if kind == UNIT:
		return pos
	return Vector2(tx + size * 0.5, ty + size * 0.5)
