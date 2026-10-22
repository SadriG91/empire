class_name Hud
extends CanvasLayer
## In-game interface built in code: resource bar, scoreboard, messages, minimap,
## selection info, command card, tooltips, health bars and overlays.

const GOLD := Color("#fcd34d")
const PANEL_BG := Color(0.09, 0.07, 0.045, 0.94)
const BORDER := Color("#8a6d40")
const CMD_COLS := 6
const TECH_COLORS := {"academy": Color("#7f1d1d"), "storehouse": Color("#14532d"), "town_center": Color("#14532d"), "temple": Color("#4c1d95"), "dock": Color("#1e3a8a"), "workshop": Color("#57534e"), "airfield": Color("#334155")}

var game
var root: Control
var theme_: Theme
var icons := {}
var lbl_res := {}
var lbl_pop: Label
var lbl_epoch: Label
var lbl_clock: Label
var lbl_wonder: Label
var btn_idle: Button
var btn_speed: Button
var btn_pause: Button
var btn_sound: Button
var msg_box: VBoxContainer
var score_box: VBoxContainer
var minimap: TextureRect
var mm_overlay: Control
var mm_img: Image
var mm_tex: ImageTexture
var mm_t := 0.0
var info_title: RichTextLabel
var info_body: RichTextLabel
var info_bar: ProgressBar
var info_bar2: ProgressBar
var queue_box: HBoxContainer
var multi_box: GridContainer
var cmd_grid: GridContainer
var cmds: Array = []
var cmd_sig := ""
var info_sig := ""
var queue_sig := ""
var multi_sig := ""
var msg_sig := ""
var tooltip: PanelContainer
var tip_label: RichTextLabel
var overlay: Control
var help_panel: Control
var tree_panel: Control
var end_panel: Control
var pause_label: Label
var _score_t := 0.0
var _tip_cmd = null
var _tip_btn: Control = null

func _ready() -> void:
	theme_ = _make_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_
	add_child(root)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	root.add_child(overlay)
	_build_top()
	_build_bottom()
	_build_side()
	_build_tooltip()
	_build_overlays()
	_make_icons()

# ====================================================================== theme
func _sb(bg: Color, border := BORDER, bw := 1, radius := 4) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 6; s.content_margin_right = 6
	s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

func _make_theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 15
	t.set_stylebox("panel", "PanelContainer", _sb(PANEL_BG, BORDER, 2, 6))
	t.set_stylebox("panel", "Panel", _sb(PANEL_BG, BORDER, 2, 6))
	t.set_stylebox("normal", "Button", _sb(Color("#3a2d1d"), BORDER))
	t.set_stylebox("hover", "Button", _sb(Color("#55422a"), GOLD))
	t.set_stylebox("pressed", "Button", _sb(Color("#2a2015"), GOLD))
	t.set_stylebox("disabled", "Button", _sb(Color("#241c12"), Color("#4a3a24")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color("#efe6d2"))
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_color", "Label", Color("#efe6d2"))
	t.set_color("default_color", "RichTextLabel", Color("#efe6d2"))
	t.set_stylebox("background", "ProgressBar", _sb(Color("#111"), Color("#000"), 1, 3))
	t.set_stylebox("fill", "ProgressBar", _sb(Color("#4ade80"), Color("#4ade80"), 0, 3))
	t.set_stylebox("normal", "LineEdit", _sb(Color("#0b0f14"), BORDER))
	t.set_stylebox("normal", "OptionButton", _sb(Color("#3a2d1d"), BORDER))
	t.set_stylebox("hover", "OptionButton", _sb(Color("#55422a"), GOLD))
	t.set_stylebox("panel", "PopupMenu", _sb(Color("#1f180f"), BORDER))
	return t

func _label(text: String, size := 15, color := Color("#efe6d2")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, cb: Callable, tip := "") -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b

func _dot(c: Color) -> Panel:
	var p = Panel.new()
	p.custom_minimum_size = Vector2(14, 14)
	p.add_theme_stylebox_override("panel", _sb(c, c.darkened(0.4), 1, 7))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

# ====================================================================== layout
func _build_top() -> void:
	var bar = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 40
	bar.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.075, 0.045, 0.96), BORDER, 0, 0))
	root.add_child(bar)
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)
	for k in Defs.RES:
		var box = HBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		box.add_child(_dot(Defs.RES_COLOR[k]))
		var l = _label("0", 16)
		l.custom_minimum_size.x = 58
		l.tooltip_text = k.capitalize()
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(l)
		lbl_res[k] = l
		h.add_child(box)
	var pb = HBoxContainer.new()
	pb.add_child(_label("Pop", 13, Color("#c9b896")))
	lbl_pop = _label("0/0", 16)
	pb.add_child(lbl_pop)
	h.add_child(pb)
	lbl_epoch = _label("Stone Age", 16, GOLD)
	h.add_child(lbl_epoch)
	btn_idle = _button("Idle 0", func(): game.ctrl.select_idle(), "Select next idle citizen ( . )")
	h.add_child(btn_idle)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	lbl_wonder = _label("", 15, Color("#fde68a"))
	h.add_child(lbl_wonder)
	lbl_clock = _label("0:00", 16, Color("#d6c7a6"))
	h.add_child(lbl_clock)
	btn_speed = _button("1x", func(): game.cycle_speed(), "Game speed")
	h.add_child(btn_speed)
	btn_pause = _button("Pause", func(): game.toggle_pause(), "Pause (P)")
	h.add_child(btn_pause)
	h.add_child(_button("Save", func(): game.save_game(), "Quick save (F5)"))
	h.add_child(_button("Load", func(): game.load_game(), "Quick load (F9)"))
	h.add_child(_button("Units", func(): toggle_tree(), "Encyclopedia and tech tree (F2)"))
	h.add_child(_button("Help", func(): toggle_help(), "Controls (F1)"))
	btn_sound = _button("Sound On", func(): _toggle_sound(), "Toggle sound")
	h.add_child(btn_sound)
	h.add_child(_button("Menu", func(): game.to_menu(), "Quit to main menu"))

func _build_side() -> void:
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(14, 50)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_box)
	var sb = PanelContainer.new()
	sb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sb.offset_left = -270
	sb.offset_top = 48
	sb.offset_right = -10
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 6))
	root.add_child(sb)
	score_box = VBoxContainer.new()
	sb.add_child(score_box)
	pause_label = _label("PAUSED", 56, Color("#fde68a"))
	pause_label.set_anchors_preset(Control.PRESET_CENTER)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_label.visible = false
	root.add_child(pause_label)

func _build_bottom() -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -214
	panel.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.075, 0.045, 0.97), BORDER, 2, 0))
	root.add_child(panel)
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	# minimap
	var mmf = PanelContainer.new()
	mmf.add_theme_stylebox_override("panel", _sb(Color("#05070a"), BORDER, 2, 3))
	h.add_child(mmf)
	minimap = TextureRect.new()
	minimap.custom_minimum_size = Vector2(196, 196)
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.stretch_mode = TextureRect.STRETCH_SCALE
	minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap.gui_input.connect(_minimap_input)
	mmf.add_child(minimap)
	mm_overlay = Control.new()
	mm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	mm_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm_overlay.draw.connect(_draw_minimap_overlay)
	minimap.add_child(mm_overlay)
	# info
	var info = PanelContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.3), Color("#4a3a24"), 1, 6))
	h.add_child(info)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	info.add_child(v)
	info_title = RichTextLabel.new()
	info_title.bbcode_enabled = true
	info_title.fit_content = true
	info_title.scroll_active = false
	info_title.add_theme_font_size_override("normal_font_size", 18)
	info_title.add_theme_font_size_override("bold_font_size", 18)
	v.add_child(info_title)
	info_bar = ProgressBar.new()
	info_bar.custom_minimum_size = Vector2(320, 10)
	info_bar.show_percentage = false
	info_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(info_bar)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	v.add_child(info_body)
	info_bar2 = ProgressBar.new()
	info_bar2.custom_minimum_size = Vector2(320, 10)
	info_bar2.show_percentage = false
	info_bar2.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_bar2.add_theme_stylebox_override("fill", _sb(Color("#a78bfa"), Color("#a78bfa"), 0, 3))
	v.add_child(info_bar2)
	queue_box = HBoxContainer.new()
	v.add_child(queue_box)
	multi_box = GridContainer.new()
	multi_box.columns = 16
	v.add_child(multi_box)
	# command card
	cmd_grid = GridContainer.new()
	cmd_grid.columns = CMD_COLS
	cmd_grid.add_theme_constant_override("h_separation", 5)
	cmd_grid.add_theme_constant_override("v_separation", 5)
	cmd_grid.custom_minimum_size = Vector2(CMD_COLS * 61, 0)
	h.add_child(cmd_grid)

func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.z_index = 10
	root.add_child(tooltip)
	tip_label = RichTextLabel.new()
	tip_label.bbcode_enabled = true
	tip_label.fit_content = true
	tip_label.custom_minimum_size = Vector2(300, 0)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tip_label)

func _overlay_panel(title: String) -> Array:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	root.add_child(bg)
	var p = PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(p)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t = _label(title, 30, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return [bg, v]

func _build_overlays() -> void:
	var hp = _overlay_panel("Controls")
	help_panel = hp[0]
	var ht = RichTextLabel.new()
	ht.bbcode_enabled = true
	ht.fit_content = true
	ht.custom_minimum_size = Vector2(820, 0)
	ht.text = """[table=2]
[cell][b]Left-click[/b] select · [b]drag[/b] box-select · [b]Shift[/b] add[/cell][cell][b]Right-click[/b] move · attack · gather · build · repair · heal · convert · rally[/cell]
[cell][b]Double-click[/b] all of that type on screen[/cell][cell][b]A[/b] attack-move · [b]S[/b] stop · [b]Del[/b] delete[/cell]
[cell][b]Ctrl+1-9[/b] make group · [b]1-9[/b] recall (twice to jump)[/cell][cell][b].[/b] idle citizen · [b],[/b] all soldiers · [b]H[/b] / [b]Space[/b] home[/cell]
[cell][b]Arrows[/b] / screen edges pan · [b]Wheel[/b] zoom[/cell][cell][b]Middle-drag[/b] rotate and tilt · [b]PgUp/PgDn[/b] rotate · [b]Home[/b] reset[/cell]
[cell][b]P[/b] pause · [b]F2[/b] encyclopedia · [b]F5/F9[/b] save/load[/cell][cell]Walls: choose Wall, then [b]drag[/b] a line. [b]Shift[/b] keeps placing.[/cell]
[/table]

[color=#fcd34d]Economy.[/color] Citizens gather food (berries, farms), wood, stone and gold; fishing boats catch fish. Houses raise the population limit. The Storehouse and Town Center research economy upgrades.
[color=#fcd34d]Epochs.[/color] Advance at the Town Center. Each epoch unlocks buildings, upgrades every soldier and improves gathering.
[color=#fcd34d]Combat.[/color] Spears and guns beat cavalry; cavalry beats ranged and siege; ranged beats infantry; siege wrecks buildings and ships. Only anti-air units, fighters and late towers hit aircraft. Units fighting from higher ground deal +25% damage, and veterans gain ranks.
[color=#fcd34d]Heroes[/color] (Town Center, Bronze Age+) inspire nearby troops. [color=#fcd34d]Priests[/color] heal and convert enemies.
[color=#fcd34d]Victory.[/color] Destroy every enemy Town Center and citizen, or finish a Wonder and defend it for 5 minutes."""
	hp[1].add_child(ht)
	hp[1].add_child(_button("Back to game", func(): help_panel.visible = false))
	var tp = _overlay_panel("Encyclopedia")
	tree_panel = tp[0]
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1180, 620)
	tp[1].add_child(sc)
	var tt = RichTextLabel.new()
	tt.bbcode_enabled = true
	tt.fit_content = true
	tt.custom_minimum_size = Vector2(1160, 0)
	tt.text = _tree_text()
	sc.add_child(tt)
	tp[1].add_child(_button("Back to game", func(): tree_panel.visible = false))
	var ep = _overlay_panel("Victory")
	end_panel = ep[0]

func _tree_text() -> String:
	var t = "[table=7][cell][b]Line[/b][/cell]"
	for e in Defs.EPOCHS:
		t += "[cell][b][color=#fcd34d]%s[/color][/b][/cell]" % e.name
	for bld in Defs.PRODUCTION:
		var rows: Array = Defs.PRODUCTION[bld]
		for r in rows.size():
			t += "[cell]%s[/cell]" % Defs.BUILDINGS[bld].name
			for ep in 6:
				var u = Defs.line_unit(bld, r, ep)
				t += "[cell]%s[/cell]" % (Defs.UNITS[u].name if u != null else "[color=#555]-[/color]")
	t += "[/table]\n\n[b][color=#fcd34d]Buildings[/color][/b]\n"
	for k in Defs.BUILD_MENU:
		var b: Dictionary = Defs.BUILDINGS[k]
		t += "[b]%s[/b] (%s) — %s  [color=#c9b896]%s[/color]\n" % [b.name, Defs.EPOCHS[b.epoch].name, b.desc, Defs.cost_text(b.cost)]
	t += "\n[b][color=#fcd34d]Technologies[/color][/b]\n[table=4]"
	for k in Defs.TECHS:
		var tech: Dictionary = Defs.TECHS[k]
		var at: Array = tech.at.map(func(x): return Defs.BUILDINGS[x].name)
		t += "[cell][b]%s[/b][/cell][cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % [tech.name, Defs.EPOCHS[tech.epoch].name, ", ".join(at), tech.desc]
	t += "[/table]"
	return t

# ====================================================================== icons
func _make_icons() -> void:
	var jobs = []
	for k in Defs.UNITS:
		jobs.append(["u:" + k, Models.unit_mesh(k, Defs.PLAYER_COLORS[0], 2)])
	for k in Defs.BUILDINGS:
		jobs.append(["b:" + k, Models.building_mesh(k, Defs.PLAYER_COLORS[0], 1)])
	var vps = []
	for j in jobs:
		var vp = SubViewport.new()
		vp.size = Vector2i(72, 72)
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var mi = MeshInstance3D.new()
		mi.mesh = j[1]
		vp.add_child(mi)
		var aabb: AABB = j[1].get_aabb()
		var c = aabb.get_center()
		var r = aabb.size.length() * 0.62
		var cam = Camera3D.new()
		cam.fov = 40
		vp.add_child(cam)
		cam.position = c + Vector3(0.8, 0.55, 1.0).normalized() * r / tan(deg_to_rad(20.0))
		var l = DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-45, 30, 0)
		vp.add_child(l)
		var we = WorldEnvironment.new()
		var env = Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.75, 0.8)
		env.background_mode = Environment.BG_CLEAR_COLOR
		we.environment = env
		vp.add_child(we)
		add_child(vp)
		cam.look_at(c, Vector3.UP)
		vps.append([j[0], vp])
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for pair in vps:
		var img: Image = pair[1].get_texture().get_image()
		icons[pair[0]] = ImageTexture.create_from_image(img)
		pair[1].queue_free()
	cmd_sig = ""
	multi_sig = ""
	queue_sig = ""

func icon_for(key: String) -> Texture2D:
	return icons.get(key)

# ====================================================================== commands
func _cmd(label: String, key: String, act: Callable, opts := {}) -> Dictionary:
	var d = {"label": label, "key": key, "act": act}
	d.merge(opts)
	return d

func command_list() -> Array:
	var s: Sim = game.sim
	var c: Controller = game.ctrl
	var p: Sim.Player = s.players[0]
	var list = []
	var units: Array = c.sel_units()
	var b: Ent = c.sel_building()
	if units.size():
		if units.any(func(u): return u.def.cls == "citizen"):
			for t in Defs.BUILD_MENU:
				var def: Dictionary = Defs.BUILDINGS[t]
				list.append(_cmd(def.name, def.key, func(_sh): c.start_placing(t), {"icon": "b:" + t, "cost": def.cost, "desc": def.desc,
					"locked": ("Requires the " + Defs.EPOCHS[def.epoch].name) if def.epoch > p.epoch else ""}))
		var fighters = units.filter(func(u): return u.def.cls != "citizen" and u.type != "fishing_boat")
		if fighters.size():
			list.append(_cmd("Attack-Move", "A", _amove, {"text": "ATK", "desc": "Move and engage any enemies on the way. Click a target point."}))
			for st in [["aggressive", "AGR", "Aggressive: chase any enemy in sight."], ["defensive", "DEF", "Defensive: engage nearby enemies, return to post."], ["hold", "HLD", "Stand ground: only attack what is in range."]]:
				var cur = fighters.all(func(u): return u.stance == st[0])
				list.append(_cmd(st[0].capitalize(), "", func(_sh): s.cmd_stance(c.sel_units(), st[0]), {"text": st[1], "desc": st[2], "active": cur}))
		list.append(_cmd("Stop", "S", func(_sh): s.cmd_stop(c.sel_units()), {"text": "STOP", "desc": "Stop current action."}))
		list.append(_cmd("Delete", "DEL", _delete_units, {"text": "DEL", "desc": "Kill the selected units."}))
	elif b and b.built:
		var keys = ["Q", "W", "E", "R"]
		var tr = s.trainable(b)
		for i in tr.size():
			var t: String = tr[i]
			var def: Dictionary = Defs.UNITS[t]
			var stats = "[color=#93c5fd]HP %d · ATK %d · ARM %d · RNG %s · SPD %.1f[/color]" % [def.hp, def.atk, def.armor, "melee" if def.range < 1.5 else str(def.range), def.speed]
			list.append(_cmd(def.name, keys[i], func(sh): _train(b, t, 5 if sh else 1), {"icon": "u:" + t, "cost": def.cost, "desc": def.desc + "\n" + stats + "\n[i]Shift-click: queue 5[/i]"}))
		for row in Defs.PRODUCTION.get(b.type, []):
			if row[mini(p.epoch, row.size() - 1)] != null:
				continue
			var ne = -1
			for i in row.size():
				if row[i] != null:
					ne = i
					break
			if ne >= 0:
				var def: Dictionary = Defs.UNITS[row[ne]]
				list.append(_cmd(def.name, "", Callable(), {"icon": "u:" + row[ne], "cost": def.cost, "desc": def.desc, "locked": "Requires the " + Defs.EPOCHS[ne].name}))
		for k in s.techs_for(b):
			var tech: Dictionary = Defs.TECHS[k]
			var words: PackedStringArray = tech.name.split(" ")
			var abbr = ""
			for w in words:
				abbr += w.substr(0, 1 if words.size() > 1 else 3)
			list.append(_cmd(tech.name, "", func(_sh): _research(b, k), {"text": abbr.to_upper(), "tech": true, "bg": TECH_COLORS.get(b.type, Color("#333")), "cost": tech.cost,
				"desc": tech.desc + "\n[color=#c9b896]Research time %ds[/color]" % tech.time, "locked": ("Requires the " + Defs.EPOCHS[tech.epoch].name) if tech.epoch > p.epoch else ""}))
		if b.type == "town_center" and p.epoch + 1 < Defs.EPOCHS.size():
			var ne: Dictionary = Defs.EPOCHS[p.epoch + 1]
			list.append(_cmd("Advance to the " + ne.name, "U", func(_sh): _advance(b), {"text": "UP", "bg": Color("#4338ca"), "cost": ne.cost,
				"desc": "Upgrades every soldier, unlocks new units and buildings and improves gathering. Takes %ds." % ne.time, "locked": "Already advancing" if p.advancing else ""}))
		if Defs.PRODUCTION.has(b.type):
			list.append(_cmd("Set Rally Point", "", func(_sh): flash("Right-click the map to set where new units gather.", Color("#93c5fd")), {"text": "FLAG", "desc": "Right-click the map, a resource or a target."}))
		list.append(_cmd("Delete", "DEL", _delete_building.bind(b), {"text": "DEL", "desc": "Demolish this building."}))
	elif b and not b.built:
		list.append(_cmd("Cancel construction", "DEL", func(_sh): _cancel_construction(b), {"text": "X", "desc": "Refunds 50% of the cost."}))
	return list

func _amove(_sh: bool) -> void:
	game.ctrl.mode = "amove"
	game.ctrl.placing = ""

func _delete_units(_sh: bool) -> void:
	for u in game.ctrl.sel_units():
		game.sim.kill(u)

func _delete_building(_sh: bool, b: Ent) -> void:
	game.sim.kill(b)
	game.ctrl.set_sel([])

func _on_cmd_input(ev: InputEvent, cmd: Dictionary, btn: Button) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if cmd.get("locked", "") == "" and cmd.act.is_valid():
			cmd.act.call(ev.shift_pressed)
			game.sfx.play("click", 0.4)
		btn.accept_event()

func _on_cmd_hover(cmd: Dictionary, btn: Button) -> void:
	_tip_cmd = cmd
	_tip_btn = btn
	_show_tip(btn, cmd)

func _cancel_q(b: Ent, idx: int) -> void:
	game.sim.cancel_queue(b, idx)
	queue_sig = ""

func _on_multi_input(ev: InputEvent, id: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.shift_pressed:
			game.ctrl.set_sel(game.ctrl.sel.filter(func(x): return x != id))
		else:
			game.ctrl.set_sel([id])

func _train(b: Ent, t: String, n: int) -> void:
	for i in n:
		var r = game.sim.train(b, t)
		if r is String:
			flash(r)
			break
	game.sfx.play("click", 0.5)

func _research(b: Ent, k: String) -> void:
	var r = game.sim.research(b, k)
	if r is String:
		flash(r)
	game.sfx.play("click", 0.5)

func _advance(b: Ent) -> void:
	var r = game.sim.advance(b)
	if r is String:
		flash(r)

func _cancel_construction(b: Ent) -> void:
	var p: Sim.Player = game.sim.players[0]
	for k in b.def.cost:
		p.res[k] += floorf(b.def.cost[k] * 0.5)
	game.sim.kill(b)
	p.stats.lost -= 1
	game.ctrl.set_sel([])

func hotkey(key: String, shift: bool) -> void:
	_render_commands()
	for c in cmds:
		if c.key == key and c.get("locked", "") == "" and c.act.is_valid():
			c.act.call(shift)
			return

func selection_changed() -> void:
	cmd_sig = ""
	info_sig = ""

func _render_commands() -> void:
	var s: Sim = game.sim
	var c: Controller = game.ctrl
	var p: Sim.Player = s.players[0]
	var b: Ent = c.sel_building()
	var stances = ""
	for u in c.sel_units():
		stances += u.stance.substr(0, 1)
	var sig = "%s|%d|%s|%s|%s|%d|%s|%d" % [str(c.sel), p.epoch, p.advancing, b.built if b else "", ",".join(c.sel_units().map(func(u): return u.type)), p.techs.size() + p.researching.size(), stances, icons.size()]
	if sig != cmd_sig:
		cmd_sig = sig
		cmds = command_list()
		for ch in cmd_grid.get_children():
			ch.queue_free()
		for cmd in cmds:
			cmd_grid.add_child(_make_cmd_button(cmd))
		hide_tip()
	for cmd in cmds:
		var btn: Button = cmd.btn
		var locked: bool = cmd.get("locked", "") != ""
		var poor: bool = not locked and cmd.has("cost") and not Defs.can_afford(p.res, cmd.cost)
		btn.modulate = Color(0.45, 0.45, 0.45) if locked else (Color(1.0, 0.55, 0.55) if poor else Color.WHITE)
	if _tip_cmd != null and _tip_btn and is_instance_valid(_tip_btn):
		_show_tip(_tip_btn, _tip_cmd)

func _make_cmd_button(cmd: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(56, 52)
	btn.focus_mode = Control.FOCUS_NONE
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cmd.has("icon") and icons.has(cmd.icon):
		btn.icon = icons[cmd.icon]
	else:
		btn.text = cmd.get("text", cmd.label.substr(0, 3))
		btn.add_theme_font_size_override("font_size", 13)
	if cmd.has("bg"):
		btn.add_theme_stylebox_override("normal", _sb(cmd.bg, BORDER))
		btn.add_theme_stylebox_override("hover", _sb(cmd.bg.lightened(0.15), GOLD))
	if cmd.get("active", false):
		btn.add_theme_stylebox_override("normal", _sb(Color("#3a5a2a"), GOLD))
	if cmd.key != "":
		var hk = _label(cmd.key.substr(0, 3), 11, GOLD)
		hk.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		hk.offset_left = -26; hk.offset_top = -16; hk.offset_right = -3
		hk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		btn.add_child(hk)
	btn.gui_input.connect(_on_cmd_input.bind(cmd, btn))
	btn.mouse_entered.connect(_on_cmd_hover.bind(cmd, btn))
	btn.mouse_exited.connect(hide_tip)
	cmd.btn = btn
	return btn

func _show_tip(btn: Control, cmd: Dictionary) -> void:
	var p: Sim.Player = game.sim.players[0]
	var t = "[b]%s[/b]" % cmd.label
	if cmd.key != "":
		t += "  [color=#fcd34d][%s][/color]" % cmd.key
	if cmd.has("cost"):
		var parts = []
		for k in cmd.cost:
			var ok: bool = p.res[k] >= cmd.cost[k]
			parts.append("[color=%s]%s %d[/color]" % ["#fde68a" if ok else "#f87171", k.capitalize(), cmd.cost[k]])
		t += "\n" + "  ".join(parts)
	if cmd.get("locked", "") != "":
		t += "\n[color=#f87171]%s[/color]" % cmd.locked
	if cmd.has("desc"):
		t += "\n" + cmd.desc
	if tip_label.text != t:
		tip_label.text = t
	tooltip.visible = true
	tooltip.reset_size()
	var r = btn.get_global_rect()
	var vs = root.get_viewport_rect().size
	tooltip.position = Vector2(clampf(r.position.x - 120, 8, vs.x - tooltip.size.x - 8), r.position.y - tooltip.size.y - 8)

func hide_tip() -> void:
	tooltip.visible = false
	_tip_cmd = null
	_tip_btn = null

# ====================================================================== info panel
func _render_info() -> void:
	var s: Sim = game.sim
	var ents: Array = game.ctrl.sel_ents()
	var title = ""
	var body = ""
	var bar = -1.0
	var bar_col = Color("#4ade80")
	var bar2 = -1.0
	if ents.is_empty():
		var p: Sim.Player = s.players[0]
		title = "[color=#fcd34d]%s[/color]" % Defs.EPOCHS[p.epoch].name
		body = "Select units or buildings. Right-click to give orders.\nTrained [b]%d[/b]   Gathered [b]%d[/b]   Kills [b]%d[/b]   Losses [b]%d[/b]   Technologies [b]%d[/b]" % [p.stats.trained, p.stats.gathered, p.stats.killed, p.stats.lost, p.techs.size()]
	elif ents.size() == 1:
		var e: Ent = ents[0]
		if e.kind == Ent.RES:
			title = {"tree": "Tree", "berries": "Berry Bush", "stone": "Stone Quarry", "gold": "Gold Mine", "fish": "Fish"}[e.type]
			body = "%d / %d %s" % [ceili(e.amount), e.max_amount, e.res]
			bar = e.amount / e.max_amount
			bar_col = Color("#fbbf24")
		else:
			var pl: Sim.Player = s.players[e.owner]
			title = "[color=#%s]%s[/color]" % [pl.color.to_html(false), e.def.name]
			if e.owner != 0:
				title += "  [color=#9ca3af][font_size=14](%s%s)[/font_size][/color]" % [pl.name, ", ally" if s.is_ally(0, e.owner) else ""]
			bar = e.hp / e.max_hp
			body = "HP %d / %d" % [ceili(e.hp), e.max_hp]
			if e.kind == Ent.UNIT:
				var d = e.def
				body += "    Attack %d   Armour %d   Range %s   Speed %.1f" % [roundi(s.u_atk(e)), roundi(s.armor_of(e)), "melee" if d.range < 1.5 else "%.1f" % s.u_range(e), s.u_speed(e)]
				if e.rank() > 0:
					body += "\n[color=#fde68a]Veteran rank %d[/color] (%d kills)" % [e.rank(), e.kills]
				if e.buff_t > s.time:
					body += "\n[color=#86efac]Inspired by a hero[/color]"
				if e.owner == 0:
					body += "\n" + _state_text(e) + ("    Stance: %s" % e.stance if e.def.cls != "citizen" else "")
				if e.carry > 0:
					body += "\nCarrying %d %s" % [e.carry, e.carry_res]
				if d.has("bonus"):
					body += "\n[color=#9ca3af]Strong against: %s[/color]" % ", ".join(d.bonus.keys())
				if d.get("aa", false):
					body += "\n[color=#9ca3af]Can attack aircraft[/color]"
			else:
				if not e.built:
					body += "\nUnder construction %d%%" % roundi(e.progress * 100)
					bar2 = e.progress
				elif e.def.get("farm", false):
					body += "\n" + ("Being farmed" if s.farm_taken(e, null) else "Idle: assign a citizen")
				if e.def.has("atk"):
					body += "\nAttack %d   Range %d" % [e.def.atk, e.def.range]
				if e.owner == 0 and e.queue.size():
					var q: Dictionary = e.queue[0]
					var what: String = "Advancing epoch" if q.type == "@epoch" else (("Researching " + Defs.TECHS[q.type.substr(1)].name) if q.type.begins_with("#") else ("Training " + Defs.UNITS[q.type].name))
					body += "\n%s%s %d%%" % ["[color=#fbbf24]Population limit![/color] " if q.get("blocked", false) else "", what, roundi(q.t / q.time * 100)]
					bar2 = q.t / q.time
				if e.type == "wonder" and e.built and pl.wonder_t >= 0.0:
					body += "\n[color=#fde68a]Victory in %s[/color]" % Defs.fmt_time(Defs.WONDER_TIME - pl.wonder_t)
	else:
		title = "%d selected" % ents.size()
	var sig = title + body
	if sig != info_sig:
		info_sig = sig
		info_title.text = title
		info_body.text = body
	info_bar.visible = bar >= 0.0
	if bar >= 0.0:
		info_bar.value = bar * 100.0
		var col = bar_col if bar_col != Color("#4ade80") else (Color("#4ade80") if bar > 0.5 else (Color("#facc15") if bar > 0.25 else Color("#f87171")))
		(info_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col
	info_bar2.visible = bar2 >= 0.0
	if bar2 >= 0.0:
		info_bar2.value = bar2 * 100.0
	# queue
	var b: Ent = game.ctrl.sel_building()
	var qs = ""
	if b:
		qs = str(b.id) + ":" + ",".join(b.queue.map(func(q): return q.type))
	if qs != queue_sig:
		queue_sig = qs
		for ch in queue_box.get_children():
			ch.queue_free()
		if b:
			for i in b.queue.size():
				var q: Dictionary = b.queue[i]
				var qb = Button.new()
				qb.custom_minimum_size = Vector2(38, 38)
				qb.focus_mode = Control.FOCUS_NONE
				qb.expand_icon = true
				var t: String = q.type
				if Defs.UNITS.has(t) and icons.has("u:" + t):
					qb.icon = icons["u:" + t]
				else:
					qb.text = "UP" if t == "@epoch" else t.substr(1, 3).to_upper()
				qb.tooltip_text = "Click to cancel"
				var idx = i
				qb.pressed.connect(_cancel_q.bind(b, idx))
				queue_box.add_child(qb)
	# multi-selection
	var ms = ""
	if ents.size() > 1:
		ms = ",".join(ents.map(func(e): return str(e.id) + e.type))
	if ms != multi_sig:
		multi_sig = ms
		for ch in multi_box.get_children():
			ch.queue_free()
		if ents.size() > 1:
			for e in ents.slice(0, 48):
				var mb = Button.new()
				mb.custom_minimum_size = Vector2(34, 34)
				mb.focus_mode = Control.FOCUS_NONE
				mb.expand_icon = true
				var key = ("u:" if e.kind == Ent.UNIT else "b:") + e.type
				if icons.has(key):
					mb.icon = icons[key]
				else:
					mb.text = e.def.name.substr(0, 2)
				mb.tooltip_text = e.def.name
				var id: int = e.id
				mb.gui_input.connect(_on_multi_input.bind(id))
				multi_box.add_child(mb)
	for i in multi_box.get_child_count():
		if i < ents.size():
			var e: Ent = ents[i]
			var f = e.hp / e.max_hp
			multi_box.get_child(i).modulate = Color.WHITE if f > 0.5 else (Color(1, 0.9, 0.5) if f > 0.25 else Color(1, 0.55, 0.55))

func _state_text(u: Ent) -> String:
	var s: Sim = game.sim
	match u.state:
		"idle": return "Idle"
		"move": return "Attack-moving" if u.amove else "Moving"
		"attack":
			var t = s.get_ent(u.target_id)
			return "Attacking " + (t.def.name if t else "")
		"gather": return "Gathering " + u.gather_type
		"return": return "Returning " + u.carry_res
		"build":
			var t = s.get_ent(u.build_id)
			return ("Repairing " if t and t.built else "Building ") + (t.def.name if t else "")
		"heal": return "Healing"
		"convert": return "Converting"
	return ""

# ====================================================================== per frame
func update(delta: float) -> void:
	var s: Sim = game.sim
	if s == null:
		return
	var p: Sim.Player = s.players[0]
	for k in Defs.RES:
		_set_text(lbl_res[k], str(int(p.res[k])))
	_set_text(lbl_pop, "%d/%d" % [p.pop, mini(p.pop_cap, s.max_pop)])
	lbl_pop.add_theme_color_override("font_color", Color("#f87171") if p.pop >= p.pop_cap else Color("#efe6d2"))
	_set_text(lbl_epoch, Defs.EPOCHS[p.epoch].name + ("  (advancing)" if p.advancing else ""))
	_set_text(lbl_clock, Defs.fmt_time(s.time))
	var idle = 0
	for u in s.units:
		if u.owner == 0 and u.def.cls == "citizen" and u.state == "idle":
			idle += 1
	_set_text(btn_idle, "Idle %d" % idle)
	var wt = ""
	for q in s.players:
		if q.wonder_t >= 0.0:
			wt += "%s Wonder %s  " % ["Your" if q.id == 0 else q.name + "'s", Defs.fmt_time(Defs.WONDER_TIME - q.wonder_t)]
	_set_text(lbl_wonder, wt)
	# messages
	var msgs = s.messages.filter(func(m): return s.time - m.t < 7.0)
	var ms = ",".join(msgs.map(func(m): return m.text + str(m.t)))
	if ms != msg_sig:
		msg_sig = ms
		for ch in msg_box.get_children():
			ch.queue_free()
		for m in msgs:
			var l = _label(m.text, 16, m.color)
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 5)
			msg_box.add_child(l)
	_score_t -= delta
	if _score_t <= 0.0:
		_score_t = 1.0
		_render_scores()
	_render_commands()
	_render_info()
	mm_t -= delta
	if mm_t <= 0.0:
		mm_t = 0.3
		_render_minimap()
	mm_overlay.queue_redraw()
	overlay.queue_redraw()

func _set_text(c: Control, t: String) -> void:
	if c.text != t:
		c.text = t

func _render_scores() -> void:
	var s: Sim = game.sim
	for ch in score_box.get_children():
		ch.queue_free()
	var head = _label("Score", 13, Color("#c9b896"))
	score_box.add_child(head)
	for p in s.players:
		var h = HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_dot(p.color))
		var rel = "" if p.id == 0 else (" (ally)" if s.is_ally(0, p.id) else "")
		var l = _label("%s%s  %d  %s" % [p.name, rel, s.score(p), Defs.EPOCHS[p.epoch].name.split(" ")[0]], 14, Color("#6b7280") if p.defeated else Color("#efe6d2"))
		h.add_child(l)
		score_box.add_child(h)

# ====================================================================== minimap
func _render_minimap() -> void:
	var s: Sim = game.sim
	var W = s.map.w
	var H = s.map.h
	if mm_img == null or mm_img.get_width() != W:
		mm_img = Image.create(W, H, false, Image.FORMAT_RGB8)
		mm_tex = ImageTexture.create_from_image(mm_img)
		minimap.texture = mm_tex
	var data = PackedByteArray()
	data.resize(W * H * 3)
	var m = s.map
	for i in W * H:
		var c: Color
		if s.explored[i] == 0:
			c = Color(0.05, 0.05, 0.06)
		else:
			match m.terrain[i]:
				WorldMap.SEA: c = Color(0.16, 0.37, 0.58)
				WorldMap.SAND: c = Color(0.78, 0.72, 0.5)
				WorldMap.ROCK: c = Color(0.5, 0.48, 0.44)
				_: c = Color(0.32, 0.5, 0.24)
			if m.block[i] == WorldMap.RES:
				var r: Ent = s.res_at.get(i)
				if r:
					c = {"tree": Color(0.14, 0.32, 0.12), "gold": Color(0.95, 0.76, 0.19), "stone": Color(0.66, 0.66, 0.66), "berries": Color(0.84, 0.23, 0.29), "fish": Color(0.6, 0.8, 0.95)}[r.type]
			if s.vis[i] == 0:
				c = c.darkened(0.4)
		data[i * 3] = int(c.r * 255); data[i * 3 + 1] = int(c.g * 255); data[i * 3 + 2] = int(c.b * 255)
	var put = func(x: int, y: int, c: Color):
		if x >= 0 and y >= 0 and x < W and y < H:
			var j = (y * W + x) * 3
			data[j] = int(c.r * 255); data[j + 1] = int(c.g * 255); data[j + 2] = int(c.b * 255)
	for b in s.buildings:
		if b.dead or not (s.is_ally(0, b.owner) or s.is_explored(b)):
			continue
		for y in range(b.ty, b.ty + b.size):
			for x in range(b.tx, b.tx + b.size):
				put.call(x, y, s.players[b.owner].color)
	for u in s.units:
		if u.dead or not (s.is_ally(0, u.owner) or s.visible(u)):
			continue
		var c: Color = s.players[u.owner].color.lightened(0.25)
		put.call(int(u.pos.x), int(u.pos.y), c)
		put.call(int(u.pos.x) + 1, int(u.pos.y), c)
	mm_img.set_data(W, H, false, Image.FORMAT_RGB8, data)
	mm_tex.update(mm_img)

func _draw_minimap_overlay() -> void:
	var s: Sim = game.sim
	if s == null:
		return
	var sz = minimap.size
	var k = Vector2(sz.x / (s.map.w * WorldView.TILE), sz.y / (s.map.h * WorldView.TILE))
	var vs = root.get_viewport_rect().size
	var corners = [Vector2(0, 40), Vector2(vs.x, 40), Vector2(vs.x, vs.y - 214), Vector2(0, vs.y - 214)]
	var pts = PackedVector2Array()
	for c in corners:
		var g: Vector3 = game.cam.ground_at(c)
		pts.append(Vector2(clampf(g.x * k.x, 0, sz.x), clampf(g.z * k.y, 0, sz.y)))
	pts.append(pts[0])
	mm_overlay.draw_polyline(pts, Color.WHITE, 1.5)
	for pg in s.pings:
		var a = s.time - pg.t
		if a < 4.0:
			mm_overlay.draw_arc(Vector2(pg.p.x / s.map.w * sz.x, pg.p.y / s.map.h * sz.y), 4.0 + fmod(a * 12.0, 10.0), 0, TAU, 16, Color(1, 0.25, 0.25, 1.0 - a / 4.0), 2.0)

func _minimap_input(ev: InputEvent) -> void:
	var s: Sim = game.sim
	if s == null:
		return
	var pos = Vector2.ZERO
	var go = false
	var cmd = false
	if ev is InputEventMouseButton and ev.pressed:
		pos = ev.position
		go = ev.button_index == MOUSE_BUTTON_LEFT
		cmd = ev.button_index == MOUSE_BUTTON_RIGHT
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		pos = ev.position
		go = true
	if not go and not cmd:
		return
	var t = Vector2(pos.x / minimap.size.x * s.map.w, pos.y / minimap.size.y * s.map.h)
	if go:
		game.cam.center_on(WorldView.to3(t, 0))
	elif cmd:
		var u: Array = game.ctrl.sel_units()
		if u.size():
			s.cmd_move(u, t)
			game.view.marker(t, Color("#4ade80"))

# ====================================================================== overlay drawing
func _draw_overlay() -> void:
	var s: Sim = game.sim
	if s == null:
		return
	var c: Controller = game.ctrl
	var cam: Camera3D = game.cam.cam
	var vs = root.get_viewport_rect().size
	for e in s.units:
		if e.dead:
			continue
		var selected: bool = c.sel_set.has(e.id)
		var r = e.rank()
		if not selected and e.hp >= e.max_hp and r == 0 and not e.def.get("hero", false):
			continue
		if not (s.is_ally(0, e.owner) or s.visible(e)):
			continue
		var p3: Vector3 = c._unit_world(e) + Vector3(0, 1.3 if not e.def.get("naval", false) else 2.2, 0)
		if cam.is_position_behind(p3):
			continue
		var sp = cam.unproject_position(p3)
		if sp.x < -20 or sp.y < 30 or sp.x > vs.x + 20 or sp.y > vs.y - 200:
			continue
		if selected or e.hp < e.max_hp:
			_bar(sp, 30.0, e.hp / e.max_hp, e.owner)
		if r > 0:
			for i in r:
				var y = sp.y - 9 - i * 4
				overlay.draw_polyline(PackedVector2Array([Vector2(sp.x - 5, y), Vector2(sp.x, y - 3), Vector2(sp.x + 5, y)]), GOLD, 2.0)
		if e.def.get("hero", false):
			overlay.draw_circle(sp + Vector2(0, -12 - r * 4), 4.0, GOLD)
	for b in s.buildings:
		if b.dead:
			continue
		var selected: bool = c.sel_set.has(b.id)
		if not selected and b.hp >= b.max_hp and b.built:
			continue
		if not (s.is_ally(0, b.owner) or s.is_explored(b)):
			continue
		var p3 = Vector3(b.pos.x * 2.0, s.map.height_at(b.pos) + 2.5 + b.size, b.pos.y * 2.0)
		if cam.is_position_behind(p3):
			continue
		var sp = cam.unproject_position(p3)
		_bar(sp, 56.0, b.hp / b.max_hp, b.owner)
		if not b.built:
			overlay.draw_rect(Rect2(sp + Vector2(-28, 6), Vector2(56, 3)), Color(0, 0, 0, 0.7))
			overlay.draw_rect(Rect2(sp + Vector2(-28, 6), Vector2(56 * b.progress, 3)), Color("#60a5fa"))
	if c.drag_active:
		var r = Rect2(c.drag_start, c.drag_cur - c.drag_start).abs()
		overlay.draw_rect(r, Color(0.65, 0.95, 0.8, 0.1))
		overlay.draw_rect(r, Color("#a7f3d0"), false, 1.0)
	if c.mode == "amove":
		var mp = root.get_viewport().get_mouse_position()
		overlay.draw_arc(mp, 10, 0, TAU, 20, Color("#f87171"), 2.0)
		overlay.draw_line(mp - Vector2(14, 0), mp + Vector2(14, 0), Color("#f87171"), 1.5)
		overlay.draw_line(mp - Vector2(0, 14), mp + Vector2(0, 14), Color("#f87171"), 1.5)

func _bar(sp: Vector2, w: float, f: float, owner: int) -> void:
	var col = Color("#4ade80") if f > 0.5 else (Color("#facc15") if f > 0.25 else Color("#f87171"))
	if owner != 0:
		col = Color("#60a5fa") if game.sim.is_ally(0, owner) else Color("#ef4444")
	overlay.draw_rect(Rect2(sp + Vector2(-w * 0.5 - 1, -1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.75))
	overlay.draw_rect(Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w * clampf(f, 0, 1), 4)), col)

# ====================================================================== misc
func flash(text: String, color := Color("#fca5a5")) -> void:
	var s: Sim = game.sim
	s.messages.append({"text": text, "color": color, "t": s.time})
	if s.messages.size() > 6:
		s.messages.pop_front()

func _toggle_sound() -> void:
	game.sfx.muted = not game.sfx.muted
	btn_sound.text = "Sound Off" if game.sfx.muted else "Sound On"

func set_paused(p: bool) -> void:
	pause_label.visible = p
	btn_pause.text = "Resume" if p else "Pause"

func set_speed(v: float) -> void:
	btn_speed.text = ("%sx" % v).replace(".0x", "x")

func toggle_help() -> void:
	help_panel.visible = not help_panel.visible

func toggle_tree() -> void:
	tree_panel.visible = not tree_panel.visible

func close_overlays() -> bool:
	if help_panel.visible or tree_panel.visible:
		help_panel.visible = false
		tree_panel.visible = false
		return true
	return false

func show_end() -> void:
	var s: Sim = game.sim
	var won: bool = s.winner_team == s.players[0].team
	var v: VBoxContainer = end_panel.get_child(0).get_child(0)
	for ch in v.get_children():
		ch.queue_free()
	var t = _label("Victory!" if won else "Defeat", 44, GOLD if won else Color("#f87171"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub = _label(("Your empire stands supreme" if won else "Your empire has fallen") + " — %s after %s." % [s.win_how.to_lower(), Defs.fmt_time(s.time)], 17, Color("#c9b896"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var g = GridContainer.new()
	g.columns = s.players.size() + 1
	g.add_theme_constant_override("h_separation", 26)
	v.add_child(g)
	g.add_child(_label(""))
	for p in s.players:
		g.add_child(_label(p.name, 15, p.color))
	var rows = [["Score", func(p): return str(s.score(p))], ["Epoch", func(p): return Defs.EPOCHS[p.epoch].name], ["Resources gathered", func(p): return str(int(p.stats.gathered))],
		["Units trained", func(p): return str(int(p.stats.trained))], ["Buildings built", func(p): return str(int(p.stats.built))], ["Technologies", func(p): return str(p.techs.size())],
		["Kills", func(p): return str(int(p.stats.killed))], ["Losses", func(p): return str(int(p.stats.lost))]]
	for row in rows:
		g.add_child(_label(row[0], 15, Color("#c9b896")))
		for p in s.players:
			g.add_child(_label(row[1].call(p), 15))
	var graph = Control.new()
	graph.custom_minimum_size = Vector2(640, 200)
	graph.draw.connect(func(): _draw_graph(graph))
	v.add_child(_label("Score over time", 14, Color("#c9b896")))
	v.add_child(graph)
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(_button("Main Menu", func(): game.to_menu()))
	v.add_child(hb)
	end_panel.visible = true

func _draw_graph(c: Control) -> void:
	var s: Sim = game.sim
	var sz = c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.35))
	var mx = 1.0
	var n = 1
	for p in s.players:
		for v in p.score_hist:
			mx = maxf(mx, v)
		n = maxi(n, p.score_hist.size())
	for i in 5:
		var y = sz.y - sz.y * i / 4.0
		c.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.08))
	for p in s.players:
		var pts = PackedVector2Array()
		for i in p.score_hist.size():
			pts.append(Vector2(sz.x * i / maxf(n - 1, 1), sz.y - sz.y * p.score_hist[i] / mx * 0.95))
		if pts.size() >= 2:
			c.draw_polyline(pts, p.color, 2.5, true)
