

class_name RadialMenu
extends Control

signal chosen(action: String)


const UNIT_ITEMS := ["attack", "force_fire", "guard", "scatter", "stop", "harvest"]
const BUILDING_ITEMS := ["repair", "primary", "sell"]
const DEPLOY_ITEMS := ["deploy", "scatter", "stop"]

var ITEMS: Array = UNIT_ITEMS

var _press := Vector2.ZERO
var _center := Vector2.ZERO
var _highlight := -1
var _outer := 64.0
var _inner := 22.0
var _dead := 20.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func open(press_pos: Vector2, items: Array = UNIT_ITEMS) -> void:
	ITEMS = items


	var extra := maxi(0, items.size() - 5) * 14.0
	_outer = Dp.px(78 + extra)
	_inner = Dp.px(30 + extra * 0.5)
	_dead = Dp.px(20)
	_press = press_pos
	var vs := get_viewport().get_visible_rect().size
	size = vs

	_center = press_pos + Vector2(0, -Dp.px(100))
	_center.x = clampf(_center.x, _outer + 4, vs.x - _outer - 4)
	_center.y = clampf(_center.y, _outer + 4, vs.y - _outer - 4)
	_highlight = -1
	show()
	queue_redraw()


func update(pos: Vector2) -> void:
	var v := pos - _press
	if v.length() < _dead:
		_highlight = -1
	else:
		var seg := TAU / ITEMS.size()
		_highlight = int(floor(fposmod(v.angle() + PI / 2.0 + seg / 2.0, TAU) / seg))
	queue_redraw()


func close(pos: Vector2) -> void:
	update(pos)
	hide()
	chosen.emit(ITEMS[_highlight] if _highlight >= 0 else "")


func cancel() -> void:
	hide()


func _draw() -> void:
	var n := ITEMS.size()
	var seg := TAU / n
	var font := ThemeDB.fallback_font
	var fs := int(Dp.px(11))
	for i in n:
		var a0 := -PI / 2.0 + i * seg - seg / 2.0 + 0.03
		var a1 := a0 + seg - 0.06
		var pts := PackedVector2Array()
		for k in 13:
			pts.append(_center + Vector2.from_angle(lerpf(a0, a1, k / 12.0)) * _outer)
		for k in 13:
			pts.append(_center + Vector2.from_angle(lerpf(a1, a0, k / 12.0)) * _inner)
		var col := Color(0.95, 0.85, 0.3, 0.92) if i == _highlight else Color(0.08, 0.10, 0.08, 0.82)
		draw_colored_polygon(pts, col)
		var mid := _center + Vector2.from_angle(-PI / 2.0 + i * seg) * ((_outer + _inner) / 2.0)
		var text: String = tr("radial.action.%s" % ITEMS[i])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var tc := Color.BLACK if i == _highlight else Color.WHITE
		var ty := fs / 2.5


		if ITEMS[i] == "c4":
			ty += fs * 0.6
			_draw_c4_badge(mid + Vector2(0, -fs * 0.55), fs * 0.42, tc)
		draw_string(font, mid + Vector2(-tw / 2.0, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)

	draw_circle(_press, _dead, Color(1, 1, 1, 0.15))
	draw_arc(_press, _dead, 0, TAU, 32, Color(1, 1, 1, 0.6), 1.5)


func _draw_c4_badge(center: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.0, r * 0.22)
	draw_arc(center, r, 0.0, TAU, 20, col, w, true)
	draw_line(center + Vector2(r * 0.45, -r * 0.8), center + Vector2(r * 0.75, -r * 1.4), col, w)
	draw_circle(center + Vector2(r * 0.75, -r * 1.4), maxf(1.0, r * 0.28),
			Color(1.0, 0.45, 0.15) if col == Color.BLACK else col)
	draw_line(center, center + Vector2(0, -r * 0.6), col, w)
	draw_line(center, center + Vector2(r * 0.5, r * 0.2), col, w)
