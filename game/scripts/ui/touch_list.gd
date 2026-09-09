

class_name TouchList
extends ScrollContainer

const DEADZONE_DP := 8.0

var _press_pos := Vector2.ZERO
var _pressing := false
var _moved := false
var _start_scroll := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child_entered_tree.connect(func(_n): call_deferred("_neutralize"))
	_neutralize()


func _neutralize() -> void:
	for b in find_children("*", "Button", true, false):
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_NONE


func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var drag := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenDrag:
		pos = e.position
		drag = true
	elif e is InputEventMouseButton or e is InputEventMouseMotion:


		return
	else:
		return
	accept_event()
	if pressed:
		_pressing = true
		_moved = false
		_press_pos = pos
		_start_scroll = scroll_vertical
	elif drag and _pressing:
		var dy := pos.y - _press_pos.y
		if absf(dy) > Dp.px(DEADZONE_DP):
			_moved = true
		if _moved:
			scroll_vertical = _start_scroll - int(dy)
	elif released and _pressing:
		_pressing = false
		if not _moved:
			_tap(pos)


func _tap(local: Vector2) -> void:
	var gp := get_global_position() + local
	for b in find_children("*", "Button", true, false):
		if not b.visible or b.disabled:
			continue
		if b.get_global_rect().has_point(gp):
			if b.toggle_mode:
				b.button_pressed = true
			b.pressed.emit()
			return
