

extends RefCounted


static func is_desktop() -> bool:
	return OS.get_name() not in ["Android", "iOS", "Web"]


static func has_keyboard() -> bool:
	return OS.get_name() not in ["Android", "iOS"]


static func fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


static func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen())


static func set_fullscreen_now(on: bool) -> void:
	if not is_desktop():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


static func set_fullscreen(on: bool) -> void:
	if not is_desktop():
		return
	set_fullscreen_now(on)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("display", "fullscreen", on)
	cfg.save("user://settings.cfg")


static func apply_saved_fullscreen() -> void:
	if not is_desktop():
		return
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if bool(cfg.get_value("display", "fullscreen", true)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func fullscreen_text() -> String:
	return TranslationServer.translate("menu.options.fullscreen_on" if fullscreen() else "menu.options.fullscreen_off")


static func want_test_window() -> bool:
	return is_desktop() and (OS.get_cmdline_user_args().has("--fullscreen") or test_resize_size().x > 0)


static func test_resize_size() -> Vector2i:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--resize")
	if k < 0 or k + 1 >= args.size():
		return Vector2i.ZERO
	var p: PackedStringArray = args[k + 1].split("x")
	return Vector2i(int(p[0]), int(p[1])) if p.size() == 2 else Vector2i.ZERO


static func apply_test_window() -> void:
	if not is_desktop():
		return
	var s := test_resize_size()
	if s.x > 0 and s.y > 0:
		DisplayServer.window_set_size(s)
	if OS.get_cmdline_user_args().has("--fullscreen"):
		set_fullscreen_now(true)


class Resizer extends Node:
	const DELAY := 0.15

	var on_change := Callable()
	var paused := false


	var ratio := 1.0
	var _left := 0.0
	var _last := Vector2i.ZERO

	func _ready() -> void:
		_last = DisplayServer.window_get_size()
		set_process(false)
		get_window().size_changed.connect(_on_size_changed)

	func _on_size_changed() -> void:
		if paused:
			return
		_left = DELAY
		set_process(true)

	func _process(delta: float) -> void:
		_left -= delta
		if _left > 0.0:
			return
		set_process(false)
		var now := DisplayServer.window_get_size()
		if paused or now == _last or now.x <= 0 or now.y <= 0:
			return
		_last = now
		var before := Dp.px_per_dp()
		Dp.window_changed()
		ratio = Dp.px_per_dp() / maxf(before, 0.001)
		if on_change.is_valid():
			on_change.call()


static func watch_resize(host: Node, on_change: Callable) -> Resizer:
	var r := Resizer.new()
	r.name = "Resizer"
	r.on_change = on_change
	host.add_child(r)
	return r


class Scroller extends Node:


	const EDGE_DP := 12.0


	const EDGE_SECONDS := 1.5
	const KEY_SECONDS := 1.2


	const WHEEL_DP := 90.0


	const PAN_SPEED := 2.5

	const ZOOM_STEP := 1.1


	const HARD_EDGE_DP := 2.0


	var pan := Callable()

	var zoom := Callable()

	var blocked := Callable()


	var edge_blocked := Callable()


	var probe := Vector2(-1.0, -1.0)
	var probe_on := false


	const KEYS_LEFT := [KEY_LEFT]
	const KEYS_RIGHT := [KEY_RIGHT]
	const KEYS_UP := [KEY_UP]
	const KEYS_DOWN := [KEY_DOWN]


	static func _desktop() -> bool:
		return OS.get_name() not in ["Android", "iOS"]

	func _ready() -> void:
		set_process(_desktop())
		set_process_unhandled_input(_desktop())

	func _off() -> bool:
		return blocked.is_valid() and bool(blocked.call())

	func _edge_off() -> bool:
		return _off() or (edge_blocked.is_valid() and bool(edge_blocked.call()))

	func _pan(d: Vector2) -> void:
		if d != Vector2.ZERO and pan.is_valid():
			pan.call(d)

	func _zoom(factor: float, at: Vector2) -> void:
		if factor > 0.0 and not is_equal_approx(factor, 1.0) and zoom.is_valid():
			zoom.call(factor, at)

	func _unhandled_input(e: InputEvent) -> void:
		if not _desktop() or _off():
			return
		if e is InputEventPanGesture:
			var pg: InputEventPanGesture = e
			_pan(-pg.delta * PAN_SPEED)
			get_viewport().set_input_as_handled()
		elif e is InputEventMagnifyGesture:
			var mg: InputEventMagnifyGesture = e
			_zoom(mg.factor, mg.position)
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed:
			var mb: InputEventMouseButton = e


			var f: float = mb.factor if mb.factor > 0.0 else 1.0
			var step := Dp.px(WHEEL_DP) * f
			var zoom_mod: bool = mb.ctrl_pressed or mb.meta_pressed
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if zoom_mod:
						_zoom(pow(ZOOM_STEP, f), mb.position)
					else:
						_pan(Vector2(0.0, step))
				MOUSE_BUTTON_WHEEL_DOWN:
					if zoom_mod:
						_zoom(pow(ZOOM_STEP, -f), mb.position)
					else:
						_pan(Vector2(0.0, -step))
				MOUSE_BUTTON_WHEEL_LEFT:
					_pan(Vector2(step, 0.0))
				MOUSE_BUTTON_WHEEL_RIGHT:
					_pan(Vector2(-step, 0.0))
				_:
					return
			get_viewport().set_input_as_handled()


	func key_direction() -> Vector2:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return Vector2.ZERO
		var d := Vector2.ZERO
		for k in KEYS_LEFT:
			if Input.is_physical_key_pressed(k):
				d.x -= 1.0
				break
		for k in KEYS_RIGHT:
			if Input.is_physical_key_pressed(k):
				d.x += 1.0
				break
		for k in KEYS_UP:
			if Input.is_physical_key_pressed(k):
				d.y -= 1.0
				break
		for k in KEYS_DOWN:
			if Input.is_physical_key_pressed(k):
				d.y += 1.0
				break
		return d.normalized()


	func edge_direction() -> Vector2:
		var vp := get_viewport()
		var vs := vp.get_visible_rect().size
		var m := probe if probe_on else vp.get_mouse_position()
		if not probe_on:
			if not DisplayServer.window_is_focused():
				return Vector2.ZERO
			if m.x < 0.0 or m.y < 0.0 or m.x > vs.x or m.y > vs.y:
				return Vector2.ZERO
		var edge := Dp.px(EDGE_DP)
		var d := Vector2.ZERO
		if m.x < edge:
			d.x = -1.0
		elif m.x >= vs.x - edge:
			d.x = 1.0
		if m.y < edge:
			d.y = -1.0
		elif m.y >= vs.y - edge:
			d.y = 1.0
		if d == Vector2.ZERO:
			return d


		var hard := Dp.px(HARD_EDGE_DP)
		var at_hard: bool = m.x < hard or m.y < hard or m.x >= vs.x - hard or m.y >= vs.y - hard
		if not at_hard and vp.gui_get_hovered_control() != null:
			return Vector2.ZERO
		return d.normalized()

	func _process(delta: float) -> void:
		if not _desktop() or _edge_off():
			return
		var d := key_direction()
		var secs := KEY_SECONDS
		if d == Vector2.ZERO:
			d = edge_direction()
			secs = EDGE_SECONDS
		if d == Vector2.ZERO:
			return
		var width := get_viewport().get_visible_rect().size.x

		_pan(-d * (width / secs) * delta)


static func watch_scroll(host: Node, pan: Callable, zoom: Callable) -> Scroller:
	var s := Scroller.new()
	s.name = "Scroller"
	s.pan = pan
	s.zoom = zoom
	host.add_child(s)
	return s


static func handle_fullscreen_key(e: InputEvent) -> bool:
	if not is_desktop() or not (e is InputEventKey) or not e.pressed or e.echo:
		return false
	var k: InputEventKey = e
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		toggle_fullscreen()
		return true
	return false


const KEYS := [

	{"id": "attack_move", "keys": [KEY_A], "show": "A", "label": "keys.attack_move"},
	{"id": "guard", "keys": [KEY_D], "show": "D", "label": "keys.guard"},
	{"id": "stop", "keys": [KEY_E], "show": "E", "label": "keys.stop"},
	{"id": "deploy", "keys": [KEY_F], "show": "F", "label": "keys.deploy"},
	{"id": "scatter", "keys": [KEY_X], "show": "X", "label": "keys.scatter"},

	{"id": "repair", "keys": [KEY_R], "show": "R", "label": "keys.repair"},
	{"id": "sell", "keys": [KEY_S], "show": "S", "label": "keys.sell"},

	{"id": "all_units", "keys": [KEY_Q], "show": "Q", "label": "keys.all_units"},
	{"id": "base", "keys": [KEY_H], "show": "H", "label": "keys.base"},
	{"id": "last_event", "keys": [KEY_SPACE], "show": "Space", "label": "keys.last_event"},
	{"id": "to_selection", "keys": [KEY_HOME], "show": "Home", "label": "keys.to_selection"},
	{"id": "", "keys": [], "show": "1 – 5", "label": "keys.groups"},
	{"id": "", "keys": [], "show": "Esc", "label": "keys.escape"},

	{"id": "", "keys": [], "show": "← ↑ → ↓", "label": "keys.scroll"},
	{"id": "zoom_in", "keys": [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_BRACKETRIGHT], "show": "+", "label": "keys.zoom_in"},
	{"id": "zoom_out", "keys": [KEY_MINUS, KEY_KP_SUBTRACT, KEY_BRACKETLEFT], "show": "−", "label": "keys.zoom_out"},
	{"id": "zoom_reset", "keys": [KEY_PERIOD], "show": ".", "label": "keys.zoom_reset"},
	{"id": "", "keys": [], "show": "F11", "label": "keys.fullscreen"},

	{"id": "build_bar", "keys": [KEY_B], "show": "B", "label": "keys.build_bar"},
	{"id": "tabs", "keys": [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6], "show": "F1 – F6", "label": "keys.tabs"},
	{"id": "pause", "keys": [KEY_P, KEY_PAUSE], "show": "P", "label": "keys.pause"},
	{"id": "music", "keys": [KEY_M], "show": "M", "label": "keys.music"},

	{"id": "", "keys": [], "show": "keys.rmb", "label": "keys.right_click"},
	{"id": "", "keys": [], "show": "keys.rmb", "label": "keys.right_click_build"},
]


static func key_action(e: InputEvent) -> Dictionary:
	if not has_keyboard() or not (e is InputEventKey) or not e.pressed or e.echo:
		return {"id": "", "index": 0}
	var k: InputEventKey = e
	if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
		return {"id": "", "index": 0}
	for row in KEYS:
		var i: int = row["keys"].find(k.keycode)
		if i >= 0:
			return {"id": row["id"], "index": i}
	return {"id": "", "index": 0}


static func key_rows() -> Array:
	var out: Array = []
	for row in KEYS:
		var show: String = row["show"]
		if show.begins_with("keys."):
			show = TranslationServer.translate(show)
		out.append([show, TranslationServer.translate(row["label"])])
	return out
