

extends Control

const NetHub := preload("res://scripts/net/net_hub.gd")
const ChatPanel := preload("res://scripts/ui/chat_panel.gd")


signal tapped()

var slug := ""
var _tex: Texture2D = null
var _bounds := Rect2(0, 0, 64, 64)
var _spawns: Array = []
var _taken := {}
var _mine := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	resized.connect(queue_redraw)
	gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			tapped.emit())


func set_map(map_slug: String, taken: Dictionary = {}, mine: int = -1) -> void:
	slug = map_slug
	_tex = texture_for(map_slug)
	_bounds = bounds_of(map_slug)
	_spawns = spawns_of(map_slug)
	_taken = taken
	_mine = mine
	queue_redraw()


func spawn_count() -> int:
	return _spawns.size()


static func texture_for(map_slug: String) -> Texture2D:
	var path := "res://assets/maps/%s.png" % map_slug
	return load(path) if ResourceLoader.exists(path) else null


static func spawns_of(map_slug: String) -> Array:
	return NetHub.map_json(map_slug).get("spawns", [])


static func bounds_of(map_slug: String) -> Rect2:
	var d: Dictionary = NetHub.map_json(map_slug)
	var b: Array = d.get("bounds", [0, 0, int(d.get("width", 64)), int(d.get("height", 64))])
	if b.size() < 4:
		b = [0, 0, 64, 64]
	return Rect2(float(b[0]), float(b[1]), maxf(float(b[2]), 1.0), maxf(float(b[3]), 1.0))


static func fit(tex: Texture2D, area: Rect2) -> Rect2:
	var ar := 1.0
	if tex != null and tex.get_height() > 0:
		ar = float(tex.get_width()) / float(tex.get_height())
	var d := Vector2(area.size.y * ar, area.size.y)
	if d.x > area.size.x:
		d = Vector2(area.size.x, area.size.x / ar)
	return Rect2(area.position + (area.size - d) / 2.0, d)


static func spawn_point(sp: Array, bounds: Rect2, pic: Rect2) -> Vector2:
	var rel := Vector2((float(sp[0]) - bounds.position.x) / bounds.size.x,
			(float(sp[1]) - bounds.position.y) / bounds.size.y)
	return pic.position + rel * pic.size


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if _tex != null:
		area = fit(_tex, area)
		draw_texture_rect(_tex, area, false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.07, 0.9))
	HudTheme.draw_panel(self, Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), HudTheme.BORDER_DIM, 4.0)
	var font := ThemeDB.fallback_font
	var r := Dp.px(8)
	for i in _spawns.size():
		var p := spawn_point(_spawns[i], _bounds, area)
		var col: Color = ChatPanel.player_color(int(_taken[i])) if _taken.has(i) \
				else Color(0.62, 0.60, 0.55, 0.85)
		draw_circle(p, r + Dp.px(2), Color(0, 0, 0, 0.65))
		draw_circle(p, r, col)
		if i == _mine:
			draw_arc(p, r + Dp.px(3), 0.0, TAU, 24, HudTheme.GOLD, Dp.px(2), true)
		var num := str(i + 1)
		var fs := int(Dp.px(11))
		var w := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, p + Vector2(-w / 2.0, fs * 0.36), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.05, 0.05, 0.04))


static func open_overlay(host: Node, map_slug: String, head_text: String, hint_text: String,
		taken: Dictionary = {}, mine: int = -1, on_pick: Callable = Callable()) -> Control:
	var layer := overlay_host(host)
	var safe := Dp.safe_rect()
	var overlay := Control.new()
	overlay.name = "MapOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			close_overlay(host))
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)
	var head := Label.new()
	head.text = head_text
	head.add_theme_font_size_override("font_size", int(Dp.px(16)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	head.position = safe.position + Vector2(Dp.px(16), Dp.px(8))
	head.size = Vector2(safe.size.x - Dp.px(32), Dp.px(24))
	overlay.add_child(head)
	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_font_size_override("font_size", int(Dp.px(12)))
	hint.add_theme_color_override("font_color", HudTheme.TEXT)
	hint.position = safe.position + Vector2(Dp.px(16), Dp.px(32))
	hint.size = Vector2(safe.size.x - Dp.px(32), Dp.px(20))
	overlay.add_child(hint)
	var tex := texture_for(map_slug)
	var area := Rect2(safe.position + Vector2(Dp.px(16), Dp.px(58)),
			safe.size - Vector2(Dp.px(32), Dp.px(58 + 60)))
	var pic_rect := fit(tex, area)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = pic_rect.position
	pic.size = pic_rect.size
	overlay.add_child(pic)
	var bounds := bounds_of(map_slug)
	var spawns := spawns_of(map_slug)
	for i in spawns.size():
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(Dp.px(46), Dp.px(46))
		b.size = b.custom_minimum_size
		HudTheme.plate_button_style(b, 15.0, 4.0)
		var free: bool = not taken.has(i) or i == mine
		if taken.has(i):

			b.add_theme_color_override("font_color", ChatPanel.player_color(int(taken[i])))
			b.add_theme_color_override("font_disabled_color", ChatPanel.player_color(int(taken[i])))
		if i == mine:
			b.add_theme_color_override("font_color", HudTheme.GOLD)
		b.disabled = not on_pick.is_valid() or not free
		var p := spawn_point(spawns[i], bounds, pic_rect) - b.size / 2.0

		b.position = Vector2(clampf(p.x, safe.position.x, safe.end.x - b.size.x),
				clampf(p.y, safe.position.y, safe.end.y - b.size.y))
		var idx := i
		if not b.disabled:
			b.pressed.connect(func():
				Sfx.click(host)
				close_overlay(host)
				on_pick.call(idx))
		overlay.add_child(b)
	var close := Button.new()
	close.text = TranslationServer.translate("ui.close")
	close.custom_minimum_size = Vector2(Dp.px(150), Dp.px(44))
	close.size = close.custom_minimum_size
	HudTheme.plate_button_style(close, 15.0)
	close.position = Vector2(safe.position.x + (safe.size.x - Dp.px(150)) / 2.0,
			safe.end.y - Dp.px(52))
	close.pressed.connect(func():
		Sfx.click(host)
		close_overlay(host))
	overlay.add_child(close)
	close_overlay(host)
	layer.add_child(overlay)
	return overlay


static func overlay_host(host: Node) -> Node:
	var n: Node = host
	while n != null:
		if n is Control and not (n is Container):
			return n
		n = n.get_parent()
	return host


static func close_overlay(host: Node) -> void:
	var o: Node = overlay_host(host).get_node_or_null("MapOverlay")
	if o != null:
		o.name = "MapOverlayGone"
		o.queue_free()
