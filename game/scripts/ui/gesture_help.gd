

class_name GestureHelp
extends RefCounted


const Desktop := preload("res://scripts/desktop.gd")

const SETTINGS := "user://settings.cfg"


const LINE_KEYS := [
	["gesture.one_finger.label", "gesture.one_finger.desc"],
	["gesture.tap_own.label", "gesture.tap_own.desc"],
	["gesture.tap_friendly.label", "gesture.tap_friendly.desc"],
	["gesture.tap_own_building.label", "gesture.tap_own_building.desc"],
	["gesture.double_tap.label", "gesture.double_tap.desc"],
	["gesture.drag_empty.label", "gesture.drag_empty.desc"],
	["gesture.tap_ground.label", "gesture.tap_ground.desc"],
	["gesture.tap_enemy.label", "gesture.tap_enemy.desc"],
	["gesture.tap_ore.label", "gesture.tap_ore.desc"],
	["gesture.long_press_selection.label", "gesture.long_press_selection.desc"],
	["gesture.long_press_own.label", "gesture.long_press_own.desc"],
	["gesture.long_press_empty.label", "gesture.long_press_empty.desc"],
	["gesture.two_finger_drag.label", "gesture.two_finger_drag.desc"],
	["gesture.three_finger_spread.label", "gesture.three_finger_spread.desc"],
	["gesture.minimap.label", "gesture.minimap.desc"],
	["gesture.build_bar.label", "gesture.build_bar.desc"],
	["gesture.place_building.label", "gesture.place_building.desc"],
	["gesture.group_column.label", "gesture.group_column.desc"],
	["gesture.button_over_enemy.label", "gesture.button_over_enemy.desc"],
	["gesture.bottom_buttons.label", "gesture.bottom_buttons.desc"],
]


static func panel(title: String = "", close_text: String = "", on_close: Callable = Callable(),
		max_height: float = 0.0, max_width: float = 0.0) -> PanelContainer:
	if title == "":
		title = TranslationServer.translate("menu.controls")
	if close_text == "":
		close_text = TranslationServer.translate("ui.understood")
	HudTheme.log_overlay("GESTENHILFE", title)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudTheme.panel(HudTheme.PANEL_BG_SOLID, HudTheme.BORDER, 8.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	var head := Label.new()
	head.text = title
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", int(Dp.px(20)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)

	var touch_rows: Array = []
	for e in LINE_KEYS:
		touch_rows.append([TranslationServer.translate(e[0]), TranslationServer.translate(e[1])])
	var key_rows: Array = []
	if Desktop.has_keyboard():
		key_rows.append([TranslationServer.translate("keys.title"), ""])
		key_rows.append_array(Desktop.key_rows())


	const TOUCH_W := Vector2(160, 250)


	const PC_TOUCH_W := Vector2(140, 230)
	const KEY_W := Vector2(80, 190)


	var need: float = PC_TOUCH_W.x + PC_TOUCH_W.y + KEY_W.x + KEY_W.y + 92.0 if not key_rows.is_empty() else 940.0
	var cols := 2 if max_width >= Dp.px(need) else 1


	var groups: Array = []
	if cols == 2 and not key_rows.is_empty():
		groups = [[touch_rows, PC_TOUCH_W, true], [key_rows, KEY_W, false]]
	else:
		var all_rows: Array = touch_rows + key_rows
		var per0 := int(ceil(all_rows.size() / float(cols)))
		for c in cols:
			groups.append([all_rows.slice(c * per0, mini((c + 1) * per0, all_rows.size())), TOUCH_W, false])
	var per := 0
	for g in groups:
		per = maxi(per, g[0].size())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", int(Dp.px(16)))
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for g2 in groups:
		var widths: Vector2 = g2[1]
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(Dp.px(2)))
		for e in g2[0]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", int(Dp.px(8)))
			var a := Label.new()
			a.text = e[0]
			a.custom_minimum_size = Vector2(Dp.px(widths.x), 0)
			if g2[2]:
				a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			a.add_theme_font_size_override("font_size", int(Dp.px(12)))
			a.add_theme_color_override("font_color", HudTheme.GOLD)
			var b := Label.new()
			b.text = e[1]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(Dp.px(widths.y), 0)
			b.add_theme_font_size_override("font_size", int(Dp.px(12)))
			b.add_theme_color_override("font_color", HudTheme.TEXT)
			row.add_child(a)
			row.add_child(b)
			col.add_child(row)
		columns.add_child(col)


	var row_h := Dp.px(17)

	var wanted := (per + (12 if cols == 1 else 7)) * row_h + Dp.px(20)
	var room := wanted
	if max_height > 0.0:
		room = clampf(max_height - Dp.px(120), Dp.px(140), wanted)


	var total_w := 16.0 * (groups.size() - 1)
	for g3 in groups:
		total_w += g3[1].x + g3[1].y + 8.0
	var list := TouchList.new()
	list.custom_minimum_size = Vector2(Dp.px(total_w), room)
	list.add_child(columns)
	box.add_child(list)
	var close := Button.new()
	close.text = close_text
	close.custom_minimum_size = Vector2(Dp.px(200), Dp.px(46))
	HudTheme.style_button(close, 16.0)
	close.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
		p.queue_free())
	var center := CenterContainer.new()
	center.add_child(close)
	box.add_child(center)
	p.add_child(box)
	return p


static func seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		return false
	return bool(cfg.get_value("ui", "gestures_seen", false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "gestures_seen", true)
	cfg.save(SETTINGS)
