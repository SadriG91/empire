class_name Menu
extends CanvasLayer
## Main menu and skirmish setup, drawn over a live AI-vs-AI battle.

const GOLD := Color("#fcd34d")

var game
var root: Control
var opts := {}
var seed_edit: LineEdit
var reveal_check: CheckBox
var btn_continue: Button

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.01, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var card = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.03, 0.9)
	sb.border_color = Color("#8a6d40")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 34; sb.content_margin_right = 34
	sb.content_margin_top = 26; sb.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.offset_left = 70
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(card)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	var title = Label.new()
	title.text = "EMPIRE: EPOCHS"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color("#3a2410"))
	title.add_theme_constant_override("outline_size", 8)
	v.add_child(title)
	var tag = Label.new()
	tag.text = "Lead your people from the Stone Age to the Modern Age."
	tag.add_theme_color_override("font_color", Color("#c9b896"))
	v.add_child(tag)
	v.add_child(HSeparator.new())

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	_opt(grid, "players", "Players", [["2 players", 2], ["3 players", 3], ["4 players", 4]], 0)
	_opt(grid, "mode", "Mode", [["Free for all", "ffa"], ["Teams (you + allies)", "teams"]], 0)
	_opt(grid, "map_type", "Map", [["Lakes", "lakes"], ["Inland Sea", "inland_sea"], ["Plains", "plains"], ["Highlands", "highlands"]], 0)
	_opt(grid, "map_size", "Map size", [["Small", "small"], ["Medium", "medium"], ["Large", "large"]], 1)
	_opt(grid, "difficulty", "Difficulty", [["Easy", "easy"], ["Normal", "normal"], ["Hard", "hard"]], 1)
	var eps = []
	for i in Defs.EPOCHS.size():
		eps.append([Defs.EPOCHS[i].name, i])
	_opt(grid, "start_epoch", "Starting epoch", eps, 0)
	_opt(grid, "resources", "Resources", [["Standard", "standard"], ["High", "high"]], 0)
	_opt(grid, "pop_cap", "Population cap", [["100", 100], ["200", 200], ["300", 300]], 1)
	grid.add_child(_lbl("Map seed"))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size.x = 220
	grid.add_child(seed_edit)
	grid.add_child(_lbl("Reveal map"))
	reveal_check = CheckBox.new()
	reveal_check.text = "Show the whole map"
	grid.add_child(reveal_check)

	v.add_child(HSeparator.new())
	var bb = HBoxContainer.new()
	bb.add_theme_constant_override("separation", 12)
	v.add_child(bb)
	var start = _big("Start Game", _on_start)
	bb.add_child(start)
	btn_continue = _big("Continue", func(): game.load_game())
	bb.add_child(btn_continue)
	bb.add_child(_big("Quit", func(): get_tree().quit()))
	var how = Label.new()
	how.text = "Win by destroying every rival Town Center and citizen,\nor by defending a completed Wonder for 5 minutes.\nPress F1 in game for controls, F2 for the encyclopedia."
	how.add_theme_color_override("font_color", Color("#a8987a"))
	how.add_theme_font_size_override("font_size", 13)
	v.add_child(how)
	refresh()

func refresh() -> void:
	btn_continue.visible = FileAccess.file_exists(game.SAVE_PATH)

func _lbl(t: String) -> Label:
	var l = Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color("#d6c7a6"))
	return l

func _big(t: String, cb: Callable) -> Button:
	var b = Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 18)
	var n = StyleBoxFlat.new()
	n.bg_color = Color("#b8892f")
	n.border_color = GOLD
	n.set_border_width_all(1)
	n.set_corner_radius_all(6)
	var h = n.duplicate()
	h.bg_color = Color("#d4a13d")
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_color_override("font_color", Color("#1a1208"))
	b.add_theme_color_override("font_hover_color", Color("#1a1208"))
	b.pressed.connect(cb)
	return b

func _opt(grid: GridContainer, key: String, label: String, items: Array, sel: int) -> void:
	grid.add_child(_lbl(label))
	var ob = OptionButton.new()
	ob.custom_minimum_size.x = 220
	for i in items.size():
		ob.add_item(items[i][0], i)
	ob.select(sel)
	grid.add_child(ob)
	opts[key] = [ob, items]

func _val(key: String):
	var o: Array = opts[key]
	return o[1][o[0].selected][1]

func settings() -> Dictionary:
	var n: int = _val("players")
	var teams: bool = _val("mode") == "teams"
	var pers: Array = Defs.PERSONALITIES.keys()
	pers.shuffle()
	var pl = []
	for i in n:
		pl.append({"team": (i % 2) if teams else i, "ai": i != 0, "personality": pers[i % pers.size()]})
	var size: String = _val("map_size")
	if n >= 3 and size == "small":
		size = "medium"
	var raw = seed_edit.text.strip_edges()
	var seed = randi()
	if raw != "":
		seed = int(raw) if raw.is_valid_int() else raw.hash()
	return {"players": pl, "map_type": _val("map_type"), "map_size": size, "difficulty": _val("difficulty"),
		"start_epoch": _val("start_epoch"), "resources": _val("resources"), "pop_cap": _val("pop_cap"), "seed": seed, "reveal": reveal_check.button_pressed}

func _on_start() -> void:
	game.start_game(settings())
