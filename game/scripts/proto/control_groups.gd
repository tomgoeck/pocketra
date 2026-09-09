

class_name ControlGroups
extends Control

signal group_selected(index: int, count: int)
signal group_focused(index: int)
signal group_assigned(index: int, count: int)

const SLOTS := 5
const LONG_PRESS := 0.35
const DOUBLE_TAP := 0.3

var world: ProtoWorld
var groups: Array = []
var slot_h := 44.0
var _press_slot := -1
var _press_time := 0.0
var _press_pos := Vector2.ZERO
var _assigned := false
var _last_tap_slot := -1
var _last_tap_time := -10.0
var _icons := {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for _i in SLOTS:
		groups.append([])


	slot_h = Dp.px(HudTheme.GROUP_BTN_H_DP)
	size = Vector2(Dp.px(HudTheme.GROUP_BTN_W_DP),
			slot_h * SLOTS + Dp.px(HudTheme.GROUP_GAP_DP) * (SLOTS - 1))


func _slot_at(p: Vector2) -> int:
	var step := slot_h + Dp.px(HudTheme.GROUP_GAP_DP)
	var i := int(p.y / step)
	if i < 0 or i >= SLOTS or p.y - i * step > slot_h or p.x < 0 or p.x > size.x:
		return -1
	return i


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_press_slot = _slot_at(e.position)
			_press_time = Time.get_ticks_msec() / 1000.0
			_press_pos = e.position
			_assigned = false
			if _press_slot >= 0:
				accept_event()
		else:
			var slot := _press_slot
			_press_slot = -1
			if slot < 0 or _assigned:
				return
			var now := Time.get_ticks_msec() / 1000.0
			if slot == _last_tap_slot and now - _last_tap_time < DOUBLE_TAP:
				_last_tap_slot = -1
				if not groups[slot].is_empty():
					world.select_units(groups[slot])
					group_focused.emit(slot)
			else:
				_last_tap_slot = slot
				_last_tap_time = now
				group_selected.emit(slot, world.select_units(groups[slot]))
			accept_event()
	elif e is InputEventScreenDrag and _press_slot >= 0:
		if e.position.distance_to(_press_pos) > Dp.px(12):
			_press_slot = -1


func _process(_delta: float) -> void:
	if _press_slot >= 0 and not _assigned and Time.get_ticks_msec() / 1000.0 - _press_time >= LONG_PRESS:
		_assigned = true

		var list: Array = groups[_press_slot].duplicate() if world.additive_select else []
		for u in world.selection:
			if u.alive and not world.types[u.type].get("building", false) and not list.has(u):
				list.append(u)
		groups[_press_slot] = list
		group_assigned.emit(_press_slot, list.size())

	for g in groups:
		for i in range(g.size() - 1, -1, -1):
			if not g[i].alive:
				g.remove_at(i)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	var fs := int(Dp.px(12))
	var step := slot_h + Dp.px(HudTheme.GROUP_GAP_DP)
	for i in SLOTS:
		var r := Rect2(0, i * step, size.x, slot_h)
		var n: int = groups[i].size()
		var pressed := i == _press_slot
		var occupied := n > 0


		var tint := Color(1.0, 1.0, 1.0, 1.0)
		if pressed:
			tint = Color(1.2, 1.12, 0.85, 1.0)
		elif not occupied:
			tint = Color(0.55, 0.55, 0.52, 0.85)
		HudTheme.draw_plate(self, r, tint)
		if occupied or pressed:
			draw_rect(r.grow(-1.0), HudTheme.GOLD, false, maxf(1.0, Dp.px(2.0)))

		var tc := HudTheme.GOLD if (pressed or occupied) else HudTheme.BORDER_DIM
		var label := str(i + 1)
		if n > 0:

			var icon := _icon_for(groups[i][0].type)
			if icon != null:
				var ir := Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4))
				draw_texture_rect(icon, ir, false, Color(0.6, 0.75, 1.0) if not pressed else Color(1, 1, 0.8))
			var small := int(Dp.px(9))
			var cnt := "%d ×%d" % [i + 1, n]
			var cw := font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_CENTER, -1, small).x
			var at := Vector2(r.position.x + (r.size.x - cw) / 2.0, r.end.y - Dp.px(3))
			draw_string(font, at + Vector2(1, 1), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.BLACK)
			draw_string(font, at, cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.WHITE if not pressed else Color.BLACK)
		else:
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(font, Vector2(r.position.x + (r.size.x - tw) / 2.0, r.position.y + r.size.y / 2.0 + fs / 2.5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)


func group_of(u) -> int:
	for i in SLOTS:
		if groups[i].has(u):
			return i
	return -1


func _icon_for(type: String) -> ImageTexture:
	if _icons.has(type):
		return _icons[type]
	var atlas := world.atlas()
	var tex: ImageTexture = null
	if atlas != null and atlas.sprite_frame_count.has(type + "icon"):
		tex = atlas.make_rgba_texture(type + "icon", 0, 0)
	_icons[type] = tex
	return tex
