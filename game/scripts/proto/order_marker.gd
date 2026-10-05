

class_name OrderMarker
extends Node2D

enum { ENTER, UNLOAD }


const FRAME_SEC := 0.08
const ENTER_FRAMES := 3
const DEPLOY_FRAMES := 9


const ENTER_SECONDS := FRAME_SEC * ENTER_FRAMES * 4
const UNLOAD_SECONDS := FRAME_SEC * DEPLOY_FRAMES * 2

const FADE_SECONDS := FRAME_SEC * 2.0


const CURSOR_PX_DP := 2.0


const MIN_WORLD_PER_PX := 0.6
const MAX_WORLD_PER_PX := 2.0
const MAX_MARKS := 16


const LIT := Color(0.0, 252.0 / 255.0, 0.0)
const LIT_EDGE := Color(0.0, 196.0 / 255.0, 0.0)
const MID := Color(0.0, 140.0 / 255.0, 0.0)
const DARK := Color(0.0, 88.0 / 255.0, 0.0)
const DIM := Color(88.0 / 255.0, 116.0 / 255.0, 76.0 / 255.0)
const DIM_EDGE := Color(76.0 / 255.0, 100.0 / 255.0, 60.0 / 255.0)

const SHADOW := Color(0.0, 0.0, 0.0, 0.35)

var world: ProtoWorld
var _marks: Array = []
var drawn := 0


var _hover_unit = null
var _hover_kind := -1
var _hover_age := 0.0


func flash(unit, kind: int) -> void:
	if unit == null or not unit.alive:
		return
	for m in _marks:
		if m["unit"] == unit and m["kind"] == kind:
			m["age"] = 0.0
			queue_redraw()
			return
	_marks.append({"unit": unit, "kind": kind, "age": 0.0})
	while _marks.size() > MAX_MARKS:
		_marks.pop_front()
	queue_redraw()


func set_hover(unit, kind: int) -> void:
	if unit == null or kind < 0 or not unit.alive:
		clear_hover()
		return
	if unit == _hover_unit and kind == _hover_kind:
		return
	_hover_unit = unit
	_hover_kind = kind
	_hover_age = 0.0
	queue_redraw()


func clear_hover() -> void:
	if _hover_unit == null:
		return
	_hover_unit = null
	_hover_kind = -1
	queue_redraw()


func hover_kind(unit = null) -> int:
	if _hover_unit == null or (unit != null and unit != _hover_unit):
		return -1
	return _hover_kind


func hover_unit():
	return _hover_unit


func count(kind: int = -1, unit = null) -> int:
	var n := 0
	for m in _marks:
		if (kind < 0 or m["kind"] == kind) and (unit == null or m["unit"] == unit):
			n += 1
	return n


func frame_of(unit, kind: int) -> int:
	for m in _marks:
		if m["unit"] == unit and m["kind"] == kind:
			return _frame(m)
	return -1


func age_of(unit, kind: int) -> float:
	for m in _marks:
		if m["unit"] == unit and m["kind"] == kind:
			return m["age"]
	return -1.0


static func duration(kind: int) -> float:
	return ENTER_SECONDS if kind == ENTER else UNLOAD_SECONDS


func _frame(m: Dictionary) -> int:
	var n := ENTER_FRAMES if m["kind"] == ENTER else DEPLOY_FRAMES
	return int(floor(m["age"] / FRAME_SEC)) % n


func step(dt: float) -> void:
	if _hover_unit != null:
		if _hover_unit.alive:
			_hover_age += dt
			queue_redraw()
		else:
			clear_hover()
	if _marks.is_empty():
		return
	for i in range(_marks.size() - 1, -1, -1):
		var m: Dictionary = _marks[i]
		m["age"] += dt
		if m["age"] >= duration(m["kind"]) or m["unit"] == null or not m["unit"].alive:
			_marks.remove_at(i)
	queue_redraw()


func _process(delta: float) -> void:
	step(delta)


func _scale() -> float:
	var z: float = world.zoom if world != null else 3.0
	return clampf(Dp.px(CURSOR_PX_DP) / maxf(z, 0.01), MIN_WORLD_PER_PX, MAX_WORLD_PER_PX)


func _draw() -> void:
	if (_marks.is_empty() and _hover_unit == null) or world == null:
		return
	var k := _scale()


	if _hover_unit != null and _hover_unit.alive and world.actor_shown(_hover_unit) \
			and count(_hover_kind, _hover_unit) == 0:
		var hc: Vector2 = world.unit_rect(_hover_unit).get_center()
		if _hover_kind == ENTER:
			_draw_enter(hc, k, int(floor(_hover_age / FRAME_SEC)) % ENTER_FRAMES, 1.0)
		else:
			_draw_unload(hc, k, int(floor(_hover_age / FRAME_SEC)) % DEPLOY_FRAMES, 1.0)
		drawn += 1
	for m in _marks:
		var u = m["unit"]
		if u == null or not u.alive or not world.actor_shown(u):
			continue
		var center: Vector2 = world.unit_rect(u).get_center()
		var left: float = duration(m["kind"]) - m["age"]
		var alpha := clampf(left / FADE_SECONDS, 0.0, 1.0)
		if m["kind"] == ENTER:
			_draw_enter(center, k, _frame(m), alpha)
		else:
			_draw_unload(center, k, _frame(m), alpha)
		drawn += 1


func _draw_enter(center: Vector2, k: float, frame: int, alpha: float) -> void:
	for j in 3:
		var top := (-19.0 + 7.0 * j) * k
		var tip := (-14.0 + 7.0 * j) * k
		var tri := PackedVector2Array([
				center + Vector2(-5.5 * k, top), center + Vector2(5.5 * k, top), center + Vector2(0.0, tip)])
		var lit := j == frame
		_poly(tri, LIT if lit else DIM, LIT_EDGE if lit else DIM_EDGE, k, alpha)


func _draw_unload(center: Vector2, k: float, frame: int, alpha: float) -> void:

	_rect(center, Rect2(-2.5, -2.5, 5.0, 5.0), LIT_EDGE, k, alpha, true)
	_rect(center, Rect2(1.5, -2.5, 1.0, 5.0), MID, k, alpha, false)
	_rect(center, Rect2(-2.5, 1.5, 5.0, 1.0), MID, k, alpha, false)
	_rect(center, Rect2(1.5, 1.5, 1.0, 1.0), DARK, k, alpha, false)
	_rect(center, Rect2(-1.5, -1.5, 1.0, 1.0), LIT, k, alpha, false)
	var base: float
	var tip: float
	var wide: float
	var narrow: float
	var fill := LIT
	var edge := LIT_EDGE
	if frame <= 6:
		base = 2.5 + frame
		tip = 5.5 + frame
		wide = 3.5
		narrow = 2.5
	elif frame == 7:
		base = 10.5
		tip = 12.5
		wide = 2.5
		narrow = 1.5
		fill = LIT_EDGE
		edge = DIM
	else:
		base = 11.5
		tip = 12.5
		wide = 1.5
		narrow = 1.5
		fill = DIM
		edge = DIM_EDGE
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var half: float = wide if dir.x == 0.0 else narrow
		var side := Vector2(-dir.y, dir.x) * half * k
		var b: Vector2 = center + dir * base * k
		var tri := PackedVector2Array([b + side, b - side, center + dir * tip * k])
		_poly(tri, fill, edge, k, alpha)


func _poly(tri: PackedVector2Array, fill: Color, edge: Color, k: float, alpha: float) -> void:
	var off := Vector2(0.75, 0.75) * k
	var sh := PackedVector2Array([tri[0] + off, tri[1] + off, tri[2] + off])
	var s := SHADOW
	s.a *= alpha
	draw_colored_polygon(sh, s)
	var f := fill
	f.a *= alpha
	draw_colored_polygon(tri, f)
	var e := edge
	e.a *= alpha
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), e, maxf(0.6 * k, 0.5), true)


func _rect(center: Vector2, r: Rect2, col: Color, k: float, alpha: float, shadow: bool) -> void:
	var rr := Rect2(center + r.position * k, r.size * k)
	if shadow:
		var s := SHADOW
		s.a *= alpha
		draw_rect(Rect2(rr.position + Vector2(0.75, 0.75) * k, rr.size), s, true)
	var c := col
	c.a *= alpha
	draw_rect(rr, c, true)
