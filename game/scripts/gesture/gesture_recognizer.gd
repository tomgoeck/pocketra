

class_name GestureRecognizer
extends Node

signal tap(pos: Vector2)
signal double_tap(pos: Vector2)
signal long_press(pos: Vector2)
signal long_press_moved(pos: Vector2)
signal long_press_ended(pos: Vector2)
signal long_press_cancelled()
signal drag_started(pos: Vector2)
signal drag_updated(pos: Vector2)
signal drag_ended(pos: Vector2)
signal drag_cancelled()
signal pan(delta: Vector2)
signal pinch(factor: float, center: Vector2)
signal two_finger_ended(velocity: Vector2)


@export var tap_slop_dp := 8.0
@export var double_tap_dp := 30.0
@export var double_tap_ms := 300
@export var long_press_ms := 300

enum S { IDLE, PRESS, ONE_DRAG, LONG, TWO, THREE, TAIL }

var state := S.IDLE


var input_blocked := false


var mouse_long_press := true
var _fingers := {}
var _press_emulated := false
var _press_pos := Vector2.ZERO
var _press_time := 0
var _last_tap_time := -100000
var _last_tap_pos := Vector2.ZERO
var _centroid := Vector2.ZERO
var _spread := 1.0
var _multi_time := 0
var _pan_velocity := Vector2.ZERO
var _pan_samples: Array = []


func _unhandled_input(e: InputEvent) -> void:
	if input_blocked:

		if not _fingers.is_empty():
			_fingers.clear()
			state = S.IDLE
			drag_cancelled.emit()
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_press_emulated = e.device == InputEvent.DEVICE_ID_EMULATION
			_down(e.index, e.position)
		else:
			_up(e.index, e.position)
	elif e is InputEventScreenDrag:
		_move(e.index, e.position)


func _process(_delta: float) -> void:
	if state == S.PRESS and (mouse_long_press or not _press_emulated) \
			and Time.get_ticks_msec() - _press_time >= long_press_ms:
		state = S.LONG
		long_press.emit(_press_pos)


func _down(idx: int, pos: Vector2) -> void:
	_fingers[idx] = pos
	match _fingers.size():
		1:
			state = S.PRESS
			_press_pos = pos
			_press_time = Time.get_ticks_msec()
		2:
			if state == S.ONE_DRAG:
				drag_cancelled.emit()
			elif state == S.LONG:
				long_press_cancelled.emit()
			state = S.TWO
			_multi_init()
		3:
			if state == S.TWO:
				two_finger_ended.emit(Vector2.ZERO)
			state = S.THREE
			_multi_init()


func _move(idx: int, pos: Vector2) -> void:
	if not _fingers.has(idx):
		return
	_fingers[idx] = pos
	match state:
		S.PRESS:
			if pos.distance_to(_press_pos) > Dp.px(tap_slop_dp):
				state = S.ONE_DRAG
				drag_started.emit(_press_pos)
				drag_updated.emit(pos)
		S.ONE_DRAG:
			drag_updated.emit(pos)
		S.LONG:
			long_press_moved.emit(pos)
		S.TWO:
			_two_update()
		S.THREE:
			_three_update()


func _up(idx: int, pos: Vector2) -> void:
	if not _fingers.has(idx):
		return
	_fingers.erase(idx)
	match state:
		S.PRESS:
			var now := Time.get_ticks_msec()
			if now - _last_tap_time < double_tap_ms and pos.distance_to(_last_tap_pos) < Dp.px(double_tap_dp):
				_last_tap_time = -100000
				double_tap.emit(pos)
			else:
				_last_tap_time = now
				_last_tap_pos = pos
				tap.emit(pos)
			state = S.IDLE
		S.ONE_DRAG:
			drag_ended.emit(pos)
			state = S.IDLE
		S.LONG:
			long_press_ended.emit(pos)
			state = S.IDLE
		S.TWO:
			two_finger_ended.emit(_pan_velocity)
			state = S.TAIL if not _fingers.is_empty() else S.IDLE
		S.THREE:
			state = S.TAIL if not _fingers.is_empty() else S.IDLE
		S.TAIL:
			pass
	if _fingers.is_empty():
		state = S.IDLE


func _centroid_and_spread() -> Array:
	var c := Vector2.ZERO
	for p in _fingers.values():
		c += p
	c /= _fingers.size()
	var s := 0.0
	for p in _fingers.values():
		s += c.distance_to(p)
	return [c, maxf(s / _fingers.size(), 1.0)]


func _multi_init() -> void:
	var cs := _centroid_and_spread()
	_centroid = cs[0]
	_spread = cs[1]
	_multi_time = Time.get_ticks_msec()
	_pan_velocity = Vector2.ZERO
	_pan_samples = [[_multi_time, _centroid]]


func _two_update() -> void:
	if _fingers.size() < 2:
		return
	var cs := _centroid_and_spread()
	var now := Time.get_ticks_msec()
	var delta: Vector2 = cs[0] - _centroid
	if delta != Vector2.ZERO:
		pan.emit(delta)
	_centroid = cs[0]
	_multi_time = now

	_pan_samples.append([now, cs[0]])
	while _pan_samples.size() > 1 and now - _pan_samples[0][0] > 120:
		_pan_samples.pop_front()
	var span := maxf((now - _pan_samples[0][0]) / 1000.0, 0.03)
	_pan_velocity = (cs[0] - _pan_samples[0][1]) / span


func _three_update() -> void:
	if _fingers.size() < 3:
		return
	var cs := _centroid_and_spread()
	var f: float = cs[1] / _spread
	if absf(f - 1.0) > 0.002:
		pinch.emit(f, cs[0])
	_centroid = cs[0]
	_spread = cs[1]
