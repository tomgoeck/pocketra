

class_name HudTheme
extends RefCounted

const PANEL_BG := Color(0.07, 0.07, 0.06, 0.86)
const PANEL_BG_SOLID := Color(0.10, 0.10, 0.09, 0.96)
const BORDER := Color(0.82, 0.66, 0.30)
const BORDER_DIM := Color(0.55, 0.46, 0.25)
const GOLD := Color(1.0, 0.82, 0.25)
const TEXT := Color(0.92, 0.90, 0.84)
const TEXT_DIM := Color(0.62, 0.60, 0.55)
const OLIVE := Color(0.55, 0.53, 0.28)
const OLIVE_DARK := Color(0.36, 0.35, 0.17)
const OLIVE_LIGHT := Color(0.70, 0.68, 0.38)


static func panel(bg: Color = PANEL_BG, border: Color = BORDER, radius_dp: float = 6.0, border_dp: float = 1.5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(maxf(1.0, Dp.px(border_dp))))
	sb.set_corner_radius_all(int(Dp.px(radius_dp)))
	sb.anti_aliasing = true
	return sb


static func draw_panel(ci: CanvasItem, rect: Rect2, bg: Color = PANEL_BG, border: Color = BORDER, radius_dp: float = 6.0) -> void:
	panel(bg, border, radius_dp).draw(ci.get_canvas_item(), rect)


static func style_button(b: Button, font_dp: float = 16.0) -> void:
	b.add_theme_stylebox_override("normal", panel(PANEL_BG, BORDER_DIM))
	b.add_theme_stylebox_override("hover", panel(Color(0.14, 0.13, 0.10, 0.92), BORDER))
	b.add_theme_stylebox_override("pressed", panel(Color(0.30, 0.25, 0.10, 0.95), GOLD))
	b.add_theme_stylebox_override("focus", panel(PANEL_BG, BORDER_DIM))


	b.add_theme_stylebox_override("disabled", panel(Color(0.05, 0.05, 0.04, 0.80), Color(0.34, 0.29, 0.17)))
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_font_size_override("font_size", int(Dp.px(font_dp)))


static var _grabber: ImageTexture


static func slider_grabber() -> ImageTexture:
	if _grabber != null:
		return _grabber
	var d := int(maxf(18.0, Dp.px(18)))
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (d - 1) / 2.0
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			if r <= c - 1.0:
				img.set_pixel(x, y, GOLD)
			elif r <= c:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.05))
	_grabber = ImageTexture.create_from_image(img)
	return _grabber


static func style_slider(s: Range) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.04, 0.04, 0.03, 0.95)
	track.border_color = BORDER_DIM
	track.set_border_width_all(1)
	track.set_corner_radius_all(int(Dp.px(3)))
	track.content_margin_top = Dp.px(3)
	track.content_margin_bottom = Dp.px(3)
	s.add_theme_stylebox_override("slider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.72, 0.58, 0.22)
	filled.set_corner_radius_all(int(Dp.px(3)))
	s.add_theme_stylebox_override("grabber_area", filled)
	var hi := filled.duplicate()
	hi.bg_color = GOLD
	s.add_theme_stylebox_override("grabber_area_highlight", hi)
	s.add_theme_icon_override("grabber", slider_grabber())
	s.add_theme_icon_override("grabber_highlight", slider_grabber())


static func volume_row(key: String, label: String, host: Node = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(6)))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	name.text = label
	name.custom_minimum_size = Vector2(Dp.px(74), 0)
	name.add_theme_font_size_override("font_size", int(Dp.px(13)))
	name.add_theme_color_override("font_color", TEXT)
	var value := Label.new()
	value.custom_minimum_size = Vector2(Dp.px(46), 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", int(Dp.px(13)))
	value.add_theme_color_override("font_color", GOLD)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.volume(key)
	slider.custom_minimum_size = Vector2(Dp.px(150), Dp.px(40))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_slider(slider)
	value.text = "%d %%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(func(v):
		var idx := AudioServer.get_bus_index(Sfx.BUSES.get(key, ""))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		value.text = "%d %%" % int(round(v * 100.0)))
	slider.drag_ended.connect(func(_changed): Sfx.set_volume(key, slider.value))
	row.add_child(name)
	row.add_child(_step_button("−", func():
		slider.value = maxf(0.0, slider.value - 0.05)
		Sfx.set_volume(key, slider.value)
		if host != null:
			Sfx.click(host)))
	row.add_child(slider)
	row.add_child(_step_button("+", func():
		slider.value = minf(1.0, slider.value + 0.05)
		Sfx.set_volume(key, slider.value)
		if host != null:
			Sfx.click(host)))
	row.add_child(value)
	return row


static func choice_row(label: String, names: Array, current: int, on_change: Callable, host: Node = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(6)))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(Dp.px(74), 0)
	name_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	name_label.add_theme_color_override("font_color", TEXT)
	var value := Label.new()
	value.custom_minimum_size = Vector2(Dp.px(150), 0)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", int(Dp.px(13)))
	value.add_theme_color_override("font_color", GOLD)
	var state := [clampi(current, 0, maxi(names.size() - 1, 0))]
	value.text = str(names[state[0]]) if not names.is_empty() else ""
	var step := func(dir: int) -> void:
		if names.is_empty():
			return
		state[0] = clampi(state[0] + dir, 0, names.size() - 1)
		value.text = str(names[state[0]])
		if on_change.is_valid():
			on_change.call(state[0])
		if host != null:
			Sfx.click(host)
	row.add_child(name_label)
	row.add_child(_step_button("−", func(): step.call(-1)))
	row.add_child(value)
	row.add_child(_step_button("+", func(): step.call(1)))

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(Dp.px(46), 0)
	row.add_child(pad)
	return row


static func _step_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(44), Dp.px(40))
	style_button(b, 14.0)
	b.pressed.connect(cb)
	return b


static var _tap_icon: ImageTexture


static func tap_icon() -> ImageTexture:
	if _tap_icon != null:
		return _tap_icon
	var d := 96
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(d * 0.5, d * 0.62)
	var gold := Color(0.98, 0.97, 0.92)
	for y in d:
		for x in d:
			var p := Vector2(x, y)
			var r := p.distance_to(c)

			if r <= d * 0.16:
				img.set_pixel(x, y, gold)
				continue

			if p.y < c.y - d * 0.02:
				for band in [0.26, 0.38]:
					if absf(r - d * band) <= d * 0.035:
						img.set_pixel(x, y, gold)
						break
	_tap_icon = ImageTexture.create_from_image(img)
	return _tap_icon


static func style_tab(b: Button, font_dp: float = 13.0) -> void:
	style_button(b, font_dp)
	b.add_theme_stylebox_override("pressed", panel(Color(0.22, 0.20, 0.12, 0.95), BORDER))
	b.add_theme_color_override("font_pressed_color", GOLD)


const ICON_BUTTON_ALPHA := 0.92


const ICON_BTN_W_DP := 62.0
const ICON_BTN_H_DP := 52.0


const GROUP_BTN_W_DP := 46.0
const GROUP_BTN_H_DP := 38.0
const GROUP_GAP_DP := 3.0


const HELP_PRESS_MS := 400


static func style_icon_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(1, 1, 1, 0)
	ring.border_color = GOLD
	ring.set_border_width_all(int(maxf(1.0, Dp.px(2.0))))
	ring.set_corner_radius_all(int(Dp.px(8.0)))
	ring.anti_aliasing = true
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("focus", empty)
	b.add_theme_stylebox_override("disabled", empty)
	b.add_theme_stylebox_override("pressed", ring)
	b.add_theme_stylebox_override("hover_pressed", ring)
	b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("icon_hover_color", Color(1.08, 1.08, 1.0, 1))
	b.add_theme_color_override("icon_pressed_color", Color(0.72, 0.72, 0.7, 1))
	b.add_theme_color_override("icon_focus_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("icon_disabled_color", Color(0.6, 0.6, 0.6, 0.5))
	b.modulate = Color(1, 1, 1, ICON_BUTTON_ALPHA)


static func wire_help(b: Button, help_key: String, host: Node, cb: Callable) -> void:
	var t0 := {"v": 0}
	var was := {"v": b.button_pressed}
	var suppress := {"v": false}
	b.button_down.connect(func():
		t0.v = Time.get_ticks_msec()
		was.v = b.button_pressed
		suppress.v = false)
	b.pressed.connect(func():
		if Time.get_ticks_msec() - t0.v >= HELP_PRESS_MS:
			suppress.v = true
			if b.toggle_mode:
				b.set_pressed_no_signal(was.v)
			show_help_popup(host, help_key, b.get_global_rect())
		else:
			cb.call())
	if b.toggle_mode:
		b.toggled.connect(func(_on):
			if suppress.v:
				suppress.v = false
				b.set_pressed_no_signal(was.v))


static func show_help_popup(host: Node, help_key: String, anchor: Rect2 = Rect2()) -> void:
	if host is CanvasItem:
		host.move_to_front()
	var overlay := Control.new()
	overlay.name = "HelpPopupOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_to_group("modal")
	var vp_size: Vector2 = host.get_viewport().get_visible_rect().size
	overlay.size = vp_size
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_theme_stylebox_override("panel", panel_style(10.0))
	var label := Label.new()


	label.text = TranslationServer.translate(help_key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	label.custom_minimum_size = Vector2(minf(Dp.px(260), vp_size.x - Dp.px(32)), 0)
	box.add_child(label)
	overlay.add_child(box)
	box.reset_size()
	var safe := Dp.safe_rect()
	var pos: Vector2
	if anchor.size != Vector2.ZERO:
		pos = Vector2(anchor.get_center().x - box.size.x / 2.0, anchor.position.y - box.size.y - Dp.px(8))
		if pos.y < safe.position.y:
			pos.y = anchor.end.y + Dp.px(8)
	else:
		pos = safe.position + (safe.size - box.size) / 2.0
	pos.x = clampf(pos.x, safe.position.x, safe.position.x + safe.size.x - box.size.x)
	pos.y = clampf(pos.y, safe.position.y, safe.position.y + safe.size.y - box.size.y)
	box.position = pos
	var close := func(): overlay.queue_free()
	var maybe_close := func(e: InputEvent):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			close.call()
	overlay.gui_input.connect(maybe_close)
	box.gui_input.connect(maybe_close)
	host.add_child(overlay)


static func draw_atom(ci: CanvasItem, center: Vector2, radius: float, color: Color, width: float = 1.5) -> void:
	ci.draw_circle(center, radius * 0.16, color)
	for i in 3:
		var ang := i * PI / 3.0
		var pts := PackedVector2Array()
		for s in 25:
			var t := s / 24.0 * TAU
			var ex := cos(t) * radius
			var ey := sin(t) * radius * 0.42
			pts.append(center + Vector2(ex * cos(ang) - ey * sin(ang), ex * sin(ang) + ey * cos(ang)))
		ci.draw_polyline(pts, color, width, true)


static func style_menu_button(b: Button, font_dp: float = 24.0) -> void:
	var plate: Texture2D = load("res://assets/ui/button_plate.png")
	var normal := StyleBoxTexture.new()
	normal.texture = plate
	var m := 12.0
	normal.texture_margin_left = m
	normal.texture_margin_right = m
	normal.texture_margin_top = m
	normal.texture_margin_bottom = m
	normal.content_margin_left = Dp.px(16)
	normal.content_margin_right = Dp.px(16)
	normal.content_margin_top = Dp.px(4)
	normal.content_margin_bottom = Dp.px(4)
	normal.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	normal.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var hover := normal.duplicate()
	hover.modulate_color = Color(1.15, 1.15, 1.1)
	var pressed := normal.duplicate()
	pressed.modulate_color = Color(0.75, 0.75, 0.7)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", Color(0.98, 0.97, 0.92))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.9, 0.88, 0.8))
	b.add_theme_color_override("font_outline_color", Color(0.15, 0.14, 0.05))
	b.add_theme_constant_override("outline_size", int(Dp.px(2)))
	b.add_theme_font_size_override("font_size", int(Dp.px(font_dp)))


const PANEL_TEXTURE_MARGIN := 35.0
const PLATE_TEXTURE_MARGIN := 26.0

static var _panel_tex: Texture2D
static var _plate_tex: Texture2D


static func _panel_texture() -> Texture2D:
	if _panel_tex == null:
		_panel_tex = load("res://icons/ui/panel_frame.png")
	return _panel_tex


static func _plate_texture() -> Texture2D:
	if _plate_tex == null:
		_plate_tex = load("res://icons/ui/plate_empty.png")
	return _plate_tex


static func panel_style(content_dp: float = 18.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _panel_texture()
	sb.texture_margin_left = PANEL_TEXTURE_MARGIN
	sb.texture_margin_right = PANEL_TEXTURE_MARGIN
	sb.texture_margin_top = PANEL_TEXTURE_MARGIN
	sb.texture_margin_bottom = PANEL_TEXTURE_MARGIN
	sb.content_margin_left = Dp.px(content_dp)
	sb.content_margin_right = Dp.px(content_dp)
	sb.content_margin_top = Dp.px(content_dp)
	sb.content_margin_bottom = Dp.px(content_dp)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


static func plate_button_style(b: Button, font_dp: float = 15.0, content_dp: float = 12.0) -> void:
	var normal := StyleBoxTexture.new()
	normal.texture = _plate_texture()
	normal.texture_margin_left = PLATE_TEXTURE_MARGIN
	normal.texture_margin_right = PLATE_TEXTURE_MARGIN
	normal.texture_margin_top = PLATE_TEXTURE_MARGIN
	normal.texture_margin_bottom = PLATE_TEXTURE_MARGIN
	normal.content_margin_left = Dp.px(content_dp)
	normal.content_margin_right = Dp.px(content_dp)
	normal.content_margin_top = Dp.px(6)
	normal.content_margin_bottom = Dp.px(6)
	normal.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	normal.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	var hover := normal.duplicate()
	hover.modulate_color = Color(1.15, 1.15, 1.1)
	var pressed := normal.duplicate()
	pressed.modulate_color = Color(0.7, 0.7, 0.65)
	var disabled := normal.duplicate()
	disabled.modulate_color = Color(0.55, 0.55, 0.52, 0.7)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.7, 0.35))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.53, 0.45))
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.09, 0.03))
	b.add_theme_constant_override("outline_size", int(Dp.px(2)))
	b.add_theme_font_size_override("font_size", int(Dp.px(font_dp)))


static func draw_plate(ci: CanvasItem, rect: Rect2, tint: Color = Color(1, 1, 1, 1)) -> void:
	var sb := StyleBoxTexture.new()
	sb.texture = _plate_texture()
	sb.texture_margin_left = PLATE_TEXTURE_MARGIN
	sb.texture_margin_right = PLATE_TEXTURE_MARGIN
	sb.texture_margin_top = PLATE_TEXTURE_MARGIN
	sb.texture_margin_bottom = PLATE_TEXTURE_MARGIN
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = tint
	sb.draw(ci.get_canvas_item(), rect)


static func dim_backdrop(host: Node) -> ColorRect:
	var r := ColorRect.new()
	r.name = "ModalBackdrop"
	r.color = Color(0, 0, 0, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(r)


	if host is Node and (host as Node).get_viewport() != null:
		r.size = (host as Node).get_viewport().get_visible_rect().size
	return r


const READY_GREEN := Color(0.32, 1.0, 0.45)


const READY_PULSE_HZ := 1.0


class ReadyGlow extends Control:
	const RINGS := 3

	var on := false:
		set(v):
			if v == on:
				return
			on = v
			visible = v
			queue_redraw()

	var _rings: Array[StyleBoxFlat] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = on

	func _process(_delta: float) -> void:
		if on:
			queue_redraw()

	func _draw() -> void:
		if not on:
			return
		if _rings.is_empty():

			for i in RINGS:
				var sb := StyleBoxFlat.new()
				sb.draw_center = false
				sb.border_color = HudTheme.READY_GREEN
				sb.set_border_width_all(int(maxf(1.0, Dp.px(1.8 - i * 0.2))))
				sb.set_corner_radius_all(int(Dp.px(9.0 + i * 2.2)))


				sb.set_expand_margin_all(Dp.px(1.6 + i * 2.2))
				sb.anti_aliasing = true
				_rings.append(sb)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * HudTheme.READY_PULSE_HZ)
		var r := Rect2(Vector2.ZERO, size)
		for i in _rings.size():
			var sb: StyleBoxFlat = _rings[i]
			var c := HudTheme.READY_GREEN

			sb.border_color = Color(c.r, c.g, c.b, lerpf(0.30, 0.95, pulse) / (1.0 + i * 1.5))
			draw_style_box(sb, r)


static func attach_ready_glow(host: Control) -> ReadyGlow:
	var g := ReadyGlow.new()
	g.name = "ReadyGlow"
	host.add_child(g)
	return g
