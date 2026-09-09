

class_name SupportPowersPanel
extends Control

signal activate(kind: int, ready: bool, paused: bool)

const KINDS := 4


const ICONS := ["ironicon", "pdoxicon", "atomicon", "gpssicon"]
const LABELS := ["sp.ironcurtain", "sp.chronoshift", "sp.nuke", "sp.gps"]

const KIND_GPS := 3

const CAMEO_RATIO := 64.0 / 48.0
const READY_BLINK_HZ := 1.2

var world: ProtoWorld
var _state := PackedInt32Array()
var _icons: Array = [null, null, null, null]
var _refresh := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	if world == null or world.sim == null:
		return
	_refresh += delta
	if _refresh >= 0.2:
		_refresh = 0.0
		_state = world.support_powers()
	queue_redraw()


func _visible_count() -> int:
	var n := 0
	for k in KINDS:
		if _available(k):
			n += 1
	return maxi(n, 1)


func _slot_index(k: int) -> int:
	var n := 0
	for i in k:
		if _available(i):
			n += 1
	return n


func _slot_rect(k: int) -> Rect2:
	var h := size.y / float(_visible_count())
	return Rect2(Vector2(0, _slot_index(k) * h), Vector2(size.x, h - Dp.px(4)))


func _available(k: int) -> bool:
	return _state.size() >= (k + 1) * 4 and _state[k * 4] == 1


func _draw() -> void:
	for k in KINDS:
		if not _available(k):
			continue
		var r := _slot_rect(k)
		var ready := _state[k * 4 + 1] == 1
		var permille := _state[k * 4 + 2]
		var paused := _state[k * 4 + 3] == 1


		HudTheme.draw_panel(self, r, HudTheme.PANEL_BG_SOLID, HudTheme.BORDER_DIM, 5.0)
		if _icons[k] == null and world.atlas().sprite_frame_count.has(ICONS[k]):
			_icons[k] = world.atlas().make_rgba_texture(ICONS[k], 0)


		var cameo := _cameo_rect(r.grow(-Dp.px(4)), _icons[k])
		if _icons[k] != null:
			draw_texture_rect(_icons[k], cameo, false)
		if ready:

			var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * READY_BLINK_HZ)
			var gold := HudTheme.GOLD
			draw_rect(cameo.grow(Dp.px(1)), Color(gold.r, gold.g, gold.b, lerpf(0.45, 1.0, blink)), false, Dp.px(2.5))
		else:


			var covered := cameo.size.y * (1.0 - permille / 1000.0)
			draw_rect(Rect2(cameo.position, Vector2(cameo.size.x, covered)), Color(0, 0, 0, 0.6), true)
			if paused:
				draw_rect(cameo.grow(-Dp.px(2)), Color(0.8, 0.1, 0.1, 0.25), true)
		var font := ThemeDB.fallback_font
		var fs := int(Dp.px(10))
		var txt := tr("ui.ready") if ready else "%d%%" % (permille / 10)
		draw_string(font, cameo.position + Vector2(Dp.px(3) + 1, cameo.size.y - Dp.px(3) + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
		draw_string(font, cameo.position + Vector2(Dp.px(3), cameo.size.y - Dp.px(3)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			HudTheme.GOLD if ready else HudTheme.TEXT)


func _cameo_rect(r: Rect2, tex: Texture2D) -> Rect2:
	var tsize := tex.get_size() if tex != null else Vector2.ZERO
	if tsize.x <= 0.0 or tsize.y <= 0.0:
		tsize = Vector2(CAMEO_RATIO, 1.0)
	var s := minf(r.size.x / tsize.x, r.size.y / tsize.y)
	var draw_size := tsize * s
	var pos := r.position + (r.size - draw_size) / 2.0
	return Rect2(pos, draw_size)


func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
	else:
		return
	accept_event()
	if not pressed:
		return
	for k in KINDS:
		if _available(k) and _slot_rect(k).has_point(pos):
			activate.emit(k, _state[k * 4 + 1] == 1, _state[k * 4 + 3] == 1)
			return
