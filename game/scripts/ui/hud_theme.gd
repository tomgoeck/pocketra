

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


const MODE_BORDER_DP := 3.0
const MODE_SELL := Color(0.95, 0.30, 0.25)
const MODE_REPAIR := Color(0.30, 0.85, 0.40)
const MODE_ADD := Color(1.00, 0.85, 0.15)


const VOICE_OFF := Color(0.74, 0.72, 0.66)
const VOICE_TEAM := Color(0.30, 0.88, 0.45)
const VOICE_ALL := Color(1.00, 0.45, 0.10)
const VOICE_BLOCKED := Color(0.90, 0.25, 0.22)


static var log_overlays := false

static var log_tick := Callable()

static var log_counts := {}
static var log_total := 0


static func log_overlay(kind: String, text: String, secs: float = 0.0) -> void:
	if not log_overlays:
		return
	var t := -1
	if log_tick.is_valid():
		t = int(log_tick.call())
	log_total += 1
	log_counts[text] = int(log_counts.get(text, 0)) + 1
	print("T: ÜBERLAGERUNG t=%d %s %s „%s\"" % [t, kind, ("%.1fs" % secs) if secs > 0.0 else "dauerhaft", text])


static func log_summary() -> void:
	if not log_overlays:
		return
	var items: Array = []
	for k in log_counts:
		items.append([int(log_counts[k]), k])
	items.sort_custom(func(a, b): return a[0] > b[0])
	print("T: ÜBERLAGERUNGEN gesamt %d, verschiedene %d" % [log_total, items.size()])
	for it in items:
		print("T:   %4d × „%s\"" % [it[0], it[1]])


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


	slider.scrollable = false
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


		var idx := AudioServer.get_bus_index(AudioMix.BUSES.get(key, ""))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) + AudioMix.duck_db(key))
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


const MIC_SCALE := 0.08


static func mic_probe_row(voice: Node, host: Node) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(4)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(Dp.px(6)))
	var name := Label.new()
	name.text = TranslationServer.translate("menu.options.mic_probe")
	name.custom_minimum_size = Vector2(Dp.px(120), 0)
	name.add_theme_font_size_override("font_size", int(Dp.px(13)))
	name.add_theme_color_override("font_color", TEXT)
	head.add_child(name)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(Dp.px(110), Dp.px(38))
	style_button(btn, 12.0)
	head.add_child(btn)
	box.add_child(head)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(Dp.px(240), Dp.px(18))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(Dp.px(240), 0)
	info.add_theme_font_size_override("font_size", int(Dp.px(11)))
	info.add_theme_color_override("font_color", TEXT_DIM)
	box.add_child(info)


	var diag := Label.new()
	diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diag.custom_minimum_size = Vector2(Dp.px(240), 0)
	diag.add_theme_font_size_override("font_size", int(Dp.px(10)))
	diag.add_theme_color_override("font_color", TEXT_DIM)
	box.add_child(diag)
	var setze_knopf := func():
		btn.text = TranslationServer.translate(
				"menu.options.mic_stop" if voice.probe else "menu.options.mic_start")
	setze_knopf.call()
	btn.pressed.connect(func():
		if voice.probe:
			voice.stop_probe()
		else:


			voice.ensure_permission()
			voice.start_probe()
		setze_knopf.call())
	bar.draw.connect(func():
		var r := Rect2(Vector2.ZERO, bar.size)
		bar.draw_rect(r, Color(0.04, 0.04, 0.03, 0.95))
		bar.draw_rect(r, BORDER_DIM, false, maxf(1.0, Dp.px(1.0)))
		if not voice.probe:
			info.text = TranslationServer.translate("menu.options.mic_hint")
			info.add_theme_color_override("font_color", TEXT_DIM)
			diag.text = ""
			return
		diag.text = str(voice.diagnose())
		var pegel: float = clampf(float(voice.rms()) / MIC_SCALE, 0.0, 1.0)
		var schwelle: float = clampf(float(voice.open_threshold()) / MIC_SCALE, 0.0, 1.0)
		var offen: bool = voice.gate_open()
		bar.draw_rect(Rect2(Vector2(1, 1), Vector2(maxf(r.size.x - 2.0, 0.0) * pegel, r.size.y - 2.0)),
				VOICE_TEAM if offen else Color(0.55, 0.53, 0.45))
		var mx: float = 1.0 + (r.size.x - 2.0) * schwelle
		bar.draw_rect(Rect2(Vector2(mx - maxf(1.0, Dp.px(1.0)), 0.0),
				Vector2(maxf(2.0, Dp.px(2.0)), r.size.y)), GOLD)

		var text := ""
		var farbe := TEXT_DIM
		if int(voice.stat_frames) == 0:
			text = TranslationServer.translate("mp.mic_no_input")
			farbe = MODE_SELL
		elif int(voice.stat_nonzero) == 0:

			text = TranslationServer.translate(voice.trouble_text_key(
					voice.trouble_reason(int(voice.stat_frames), 0, voice.has_permission())))
			farbe = MODE_SELL
		else:
			text = "%s  ·  %s %.4f  ·  %s %.4f" % [
					TranslationServer.translate("mp.mic_opens" if offen else "mp.mic_silent"),
					TranslationServer.translate("mp.mic_level"), float(voice.rms()),
					TranslationServer.translate("mp.mic_threshold"), float(voice.open_threshold())]
			farbe = VOICE_TEAM if offen else TEXT_DIM
		info.text = text
		info.add_theme_color_override("font_color", farbe))
	var tree := host.get_tree()
	if tree != null:
		tree.process_frame.connect(Callable(bar, "queue_redraw"))

	box.tree_exiting.connect(func(): voice.stop_probe())
	return box


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


static var _chat_icon: ImageTexture


static func chat_icon() -> ImageTexture:
	if _chat_icon != null:
		return _chat_icon
	var d := 96
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gold := Color(0.98, 0.97, 0.92)

	var body := Rect2(d * 0.12, d * 0.16, d * 0.76, d * 0.52)
	var rad := d * 0.16
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := p.clamp(body.position + Vector2(rad, rad), body.end - Vector2(rad, rad))
			var dist := p.distance_to(q) - rad
			if dist <= 0.0 and dist >= -d * 0.055:
				img.set_pixel(x, y, gold)

	for y in range(int(d * 0.62), int(d * 0.86)):
		var t := (y - d * 0.62) / (d * 0.24)
		var x0 := int(d * 0.26)
		var x1 := int(d * 0.44 - (d * 0.18) * t)
		for x in range(x0, maxi(x1, x0 + 1)):
			if absf(float(x) - float(x1)) <= d * 0.055 or y >= d * 0.62 and y <= d * 0.68:
				img.set_pixel(x, y, gold)
	for i in 3:
		var cx := int(d * (0.30 + 0.10 * i))
		for yy in range(int(d * 0.38), int(d * 0.46)):
			for xx in range(cx, cx + int(d * 0.06)):
				img.set_pixel(xx, yy, gold)
	_chat_icon = ImageTexture.create_from_image(img)
	return _chat_icon


static var _mic_icon: ImageTexture


static func mic_icon() -> ImageTexture:
	if _mic_icon != null:
		return _mic_icon
	var d := 96
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1, 1)
	var cx := d * 0.5

	var a := Vector2(cx, d * 0.28)
	var b := Vector2(cx, d * 0.44)
	var r := d * 0.145

	var bc := Vector2(cx, d * 0.44)
	var br := d * 0.30
	for y in d:
		for x in d:
			var p := Vector2(x + 0.5, y + 0.5)
			var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			if p.distance_to(a.lerp(b, t)) <= r:
				img.set_pixel(x, y, white)
				continue
			if p.y >= bc.y and absf(p.distance_to(bc) - br) <= d * 0.05:
				img.set_pixel(x, y, white)
				continue

			if p.y >= d * 0.72 and p.y <= d * 0.86 and absf(p.x - cx) <= d * 0.035:
				img.set_pixel(x, y, white)
			elif p.y > d * 0.86 and p.y <= d * 0.92 and absf(p.x - cx) <= d * 0.20:
				img.set_pixel(x, y, white)
	_mic_icon = ImageTexture.create_from_image(img)
	return _mic_icon


static func wire_tap_hold(b: Button, on_tap: Callable, on_hold: Callable) -> void:
	var t0 := {"v": 0}
	var down := {"v": false}
	b.button_down.connect(func():
		t0.v = Time.get_ticks_msec()
		down.v = true)
	b.pressed.connect(func():
		var held: bool = down.v and Time.get_ticks_msec() - t0.v >= HELP_PRESS_MS
		down.v = false
		if held:
			on_hold.call()
		else:
			on_tap.call())


static func style_tab(b: Button, font_dp: float = 13.0) -> void:
	style_button(b, font_dp)
	b.add_theme_stylebox_override("pressed", panel(Color(0.22, 0.20, 0.12, 0.95), BORDER))
	b.add_theme_color_override("font_pressed_color", GOLD)


const ICON_BUTTON_ALPHA := 0.92


const ICON_BTN_W_DP := 62.0
const ICON_BTN_H_DP := 52.0


const ICON_GAP_DP := 10.0


const GROUP_BTN_W_DP := 46.0
const GROUP_BTN_H_DP := 38.0
const GROUP_GAP_DP := ICON_GAP_DP


const HELP_PRESS_MS := 600


static func rescale_tree(root: Node, ratio: float) -> void:
	if not is_finite(ratio) or ratio <= 0.0 or absf(ratio - 1.0) < 0.002:
		return
	_rescale_node(root, ratio, {})


static func _rescale_node(n: Node, r: float, seen: Dictionary) -> void:
	if n is Control:
		var c: Control = n
		for p in c.get_property_list():
			var pname: String = p["name"]
			if pname.begins_with("theme_override_font_sizes/") or pname.begins_with("theme_override_constants/"):
				var v = c.get(pname)
				if typeof(v) == TYPE_INT and v > 0:
					c.set(pname, maxi(1, int(round(v * r))))
			elif pname.begins_with("theme_override_styles/"):
				var sb = c.get(pname)

				if sb is StyleBoxFlat and not seen.has(sb.get_instance_id()):
					seen[sb.get_instance_id()] = true
					_rescale_stylebox(sb, r)
		if c.custom_minimum_size != Vector2.ZERO:
			c.custom_minimum_size = c.custom_minimum_size * r
		c.queue_redraw()
	for child in n.get_children():
		_rescale_node(child, r, seen)


static func _rescale_stylebox(sb: StyleBoxFlat, r: float) -> void:
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_border_width(side, maxi(1, int(round(sb.get_border_width(side) * r))) if sb.get_border_width(side) > 0 else 0)
		if sb.get_content_margin(side) >= 0.0:
			sb.set_content_margin(side, sb.get_content_margin(side) * r)
		sb.set_expand_margin(side, sb.get_expand_margin(side) * r)
	for corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
		sb.set_corner_radius(corner, int(round(sb.get_corner_radius(corner) * r)))
	sb.shadow_size = int(round(sb.shadow_size * r))
	sb.shadow_offset = sb.shadow_offset * r


const MIN_TOUCH_DP := 48.0


static func min_touch_px() -> float:
	return Dp.device_px(MIN_TOUCH_DP)


static func place_touch(c: Control, pos: Vector2, visible_size: Vector2,
		max_pad: Vector2 = Vector2(1e9, 1e9)) -> void:
	var need := min_touch_px()
	var pad := Vector2(
		clampf((need - visible_size.x) / 2.0, 0.0, maxf(max_pad.x, 0.0)),
		clampf((need - visible_size.y) / 2.0, 0.0, maxf(max_pad.y, 0.0)))
	c.set_meta("hit_pad", pad)
	c.position = pos - pad
	c.size = visible_size + pad * 2.0
	if c is Button:
		_pad_styleboxes(c, pad)


static func visible_rect(c: Control) -> Rect2:
	var pad: Vector2 = c.get_meta("hit_pad", Vector2.ZERO)
	return c.get_global_rect().grow_individual(-pad.x, -pad.y, -pad.x, -pad.y)


const _STYLEBOX_STATES := ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]


static func _pad_styleboxes(b: Button, pad: Vector2) -> void:
	var seen := {}
	for state in _STYLEBOX_STATES:
		if not b.has_theme_stylebox_override(state):
			continue
		var sb: StyleBox = b.get_theme_stylebox(state)
		if sb == null or seen.has(sb.get_instance_id()):
			continue
		seen[sb.get_instance_id()] = true


		if not sb.has_meta("base_content"):
			sb.set_meta("base_content", Vector4(sb.content_margin_left, sb.content_margin_top,
				sb.content_margin_right, sb.content_margin_bottom))
		var base: Vector4 = sb.get_meta("base_content")
		sb.content_margin_left = maxf(base.x, 0.0) + pad.x
		sb.content_margin_top = maxf(base.y, 0.0) + pad.y
		sb.content_margin_right = maxf(base.z, 0.0) + pad.x
		sb.content_margin_bottom = maxf(base.w, 0.0) + pad.y


		if sb is StyleBoxFlat:
			var f: StyleBoxFlat = sb
			f.expand_margin_left = -pad.x
			f.expand_margin_right = -pad.x
			f.expand_margin_top = -pad.y
			f.expand_margin_bottom = -pad.y
		elif sb is StyleBoxTexture:
			var t: StyleBoxTexture = sb
			t.expand_margin_left = -pad.x
			t.expand_margin_right = -pad.x
			t.expand_margin_top = -pad.y
			t.expand_margin_bottom = -pad.y


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


	var down := {"v": false}
	var was := {"v": b.button_pressed}
	var suppress := {"v": false}
	b.button_down.connect(func():
		t0.v = Time.get_ticks_msec()
		down.v = true
		was.v = b.button_pressed
		suppress.v = false)
	b.pressed.connect(func():
		var held: bool = down.v and Time.get_ticks_msec() - t0.v >= HELP_PRESS_MS
		down.v = false
		if held:
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


static func show_help_popup(host: Node, help_key: String, anchor: Rect2 = Rect2(),
		bbcode: String = "") -> void:
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
	var breite := minf(Dp.px(300) if bbcode != "" else Dp.px(260), vp_size.x - Dp.px(32))
	if bbcode != "":
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.text = bbcode
		rt.add_theme_color_override("default_color", TEXT)
		rt.add_theme_font_size_override("normal_font_size", int(Dp.px(13)))
		rt.add_theme_font_size_override("bold_font_size", int(Dp.px(13)))
		rt.custom_minimum_size = Vector2(breite, 0)
		log_overlay("HILFE-POPUP", rt.get_parsed_text().replace("\n", " | "))
		box.add_child(rt)
	else:
		var label := Label.new()


		label.text = TranslationServer.translate(help_key)
		log_overlay("HILFE-POPUP", label.text)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_font_size_override("font_size", int(Dp.px(13)))
		label.custom_minimum_size = Vector2(breite, 0)
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

	var plate: Texture2D = load("res://icons/ui/button_plate.png")
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


	var inset := maxf(Dp.px(content_dp), PANEL_TEXTURE_MARGIN + 6.0)
	sb.content_margin_left = inset
	sb.content_margin_right = inset
	sb.content_margin_top = inset
	sb.content_margin_bottom = inset
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


const DIM_GROUP := "modal_backdrop"


static func dim_backdrop(host: Node) -> ColorRect:
	var r := ColorRect.new()
	r.name = "ModalBackdrop"
	r.color = Color(0, 0, 0, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.add_to_group(DIM_GROUP)
	host.add_child(r)


	if host is Node and (host as Node).get_viewport() != null:
		r.size = (host as Node).get_viewport().get_visible_rect().size
	return r


static func refit_dim_backdrops(tree: SceneTree) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(DIM_GROUP):
		if n is Control and (n as Control).get_viewport() != null:
			(n as Control).size = (n as Control).get_viewport().get_visible_rect().size


static func touch_scroll(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	_touch_scroll_apply(scroll)


	if not scroll.has_meta("touch_scroll"):
		scroll.set_meta("touch_scroll", true)
		scroll.sort_children.connect(_touch_scroll_apply.bind(scroll))


static func _touch_scroll_apply(root: Node) -> void:
	for child in root.get_children():
		if child is Control:
			var c: Control = child

			if c is ScrollBar:
				continue
			if c is Range or c is LineEdit or c is TextEdit or c is ScrollContainer:
				continue
			if c.has_meta("kein_rollen"):
				continue
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
		_touch_scroll_apply(child)


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


		var pad: Vector2 = get_parent().get_meta("hit_pad", Vector2.ZERO) if get_parent() != null else Vector2.ZERO
		var r := Rect2(pad, size - pad * 2.0)
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
