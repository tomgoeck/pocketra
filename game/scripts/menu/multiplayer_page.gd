

extends VBoxContainer

const NetHub := preload("res://scripts/net/net_hub.gd")
const NetClient := preload("res://scripts/net/net_client.gd")
const MapPreview := preload("res://scripts/ui/map_preview.gd")

signal back_pressed()
signal lobby_entered()

const CODE_LEN := 6
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const AI_LEVELS := ["easy", "normal", "hard"]

const AI_STRATEGY_KEYS := {"normal": "menu.skirmish.strat_normal", "rush": "menu.skirmish.strat_rush",
		"turtle": "menu.skirmish.strat_turtle", "air": "menu.skirmish.strat_air",
		"naval": "menu.skirmish.strat_naval", "random": "menu.skirmish.strat_random"}
const AI_LEVEL_KEYS := {"easy": "menu.skirmish.ai_easy", "normal": "menu.skirmish.ai_normal",
		"hard": "menu.skirmish.ai_hard"}
const UNIT_KEYS := {"none": "menu.skirmish.units_none", "light": "menu.skirmish.units_light",
		"heavy": "menu.skirmish.units_heavy"}

var maps: Array = []
var mode := "start"

var _hub: Node = null
var _body: VBoxContainer
var _status: Label
var _selected := 0
var _credits := 5000
var _starting_units := "none"
var _crates := true
var _explored := false
var _fog := true
var _ai_level := "normal"
var _ai_strategy := "normal"
var _code_fields: Array = []
var _name_edit: LineEdit
var _preview: Control = null
var _wide := false
var _public := false
var _rooms: Array = []
var _rooms_box: VBoxContainer = null
var _poll: Timer = null
var _wait_return := "start"

var demo_rooms: Array = []

const POLL_SECONDS := 3.0


func _ready() -> void:
	add_theme_constant_override("separation", int(Dp.px(8)))
	_hub = NetHub.hub()
	if _hub != null:
		if not _hub.state_changed.is_connected(_on_state):
			_hub.state_changed.connect(_on_state)
		if not _hub.rooms_listed.is_connected(_on_rooms):
			_hub.rooms_listed.connect(_on_rooms)
	_poll = Timer.new()
	_poll.wait_time = POLL_SECONDS
	_poll.timeout.connect(_refresh_rooms)
	add_child(_poll)


	get_viewport().size_changed.connect(_on_viewport_resized)
	_build()


func _on_viewport_resized() -> void:
	if mode == "create" and _want_wide() != _wide:
		_build()


func _want_wide() -> bool:
	return get_viewport().get_visible_rect().size.x >= Dp.device_px(640)


func show_start() -> void:
	mode = "start"
	_build()


func show_mode(m: String) -> void:
	mode = m
	_build()


func _clear() -> void:
	MapPreview.close_overlay(self)
	for c in get_children():
		if c == _poll:
			continue
		remove_child(c)
		c.queue_free()


func _title(text: String, size_dp: float = 18.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(Dp.px(size_dp)))
	l.add_theme_color_override("font_color", HudTheme.GOLD)
	return l


func _card(head_text: String, parent: Node = null) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(10.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(5)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	if head_text != "":
		var head := Label.new()
		head.text = head_text
		head.add_theme_font_size_override("font_size", int(Dp.px(14)))
		head.add_theme_color_override("font_color", HudTheme.GOLD)
		box.add_child(head)
	(parent if parent != null else _body).add_child(panel)
	return box


func _label(text: String, size_dp: float = 12.0, dim: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(Dp.px(size_dp)))
	l.add_theme_color_override("font_color", HudTheme.TEXT_DIM if dim else HudTheme.TEXT)
	return l


func _button(text: String, cb: Callable, w: float = 200.0, h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(w), Dp.px(h))
	HudTheme.plate_button_style(b, 13.0, 10.0)
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


func _build() -> void:
	_clear()
	_preview = null
	add_child(_title(tr("menu.main.multiplayer")))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(Dp.px(6)))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL


	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL


	_wide = mode == "create" and _want_wide()
	var scroll: TouchList = null
	if _wide:
		add_child(_body)
	else:
		scroll = TouchList.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(_body)
		add_child(scroll)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_status.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_rooms_box = null
	match mode:
		"create": _build_create()
		"join": _build_join()
		"wait": _build_wait()
		_: _build_start()
	if scroll != null:
		HudTheme.touch_scroll(scroll)
	_update_poll()


func _update_poll() -> void:
	if _poll == null:
		return
	if mode == "join" and demo_rooms.is_empty() and _hub != null:
		if _poll.is_stopped():
			_poll.start()
		_refresh_rooms()
	else:
		_poll.stop()


func _refresh_rooms() -> void:
	if mode != "join" or _hub == null or not demo_rooms.is_empty():
		return
	_hub.browse_refresh()


func _on_rooms(rooms: Array) -> void:
	if not is_inside_tree() or mode != "join":
		return
	_rooms = rooms
	_fill_rooms()


func _build_start() -> void:
	var box := _card(tr("mp.your_name"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", int(Dp.px(6)))
	_name_edit = LineEdit.new()
	_name_edit.text = NetClient.configured_name()
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(Dp.px(180), Dp.px(38))
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_name_edit.text_changed.connect(func(t): NetClient.save_name(t))
	name_row.add_child(_name_edit)
	box.add_child(name_row)
	box.add_child(_label(tr("mp.intro")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button(tr("mp.create"), func(): mode = "create"; _build(), 170, 44))
	row.add_child(_button(tr("mp.join"), func(): mode = "join"; _build(), 170, 44))
	box.add_child(row)
	box.add_child(_label(tr("mp.server") % NetClient.configured_url(), 10.0, true))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_child(_button(tr("ui.back"), func(): back_pressed.emit(), 140, 40))
	_body.add_child(actions)


func _build_create() -> void:
	if maps.is_empty():
		_card("").add_child(_label(tr("menu.skirmish.empty")))
		var row0 := HBoxContainer.new()
		row0.alignment = BoxContainer.ALIGNMENT_CENTER
		row0.add_child(_button(tr("ui.back"), func(): mode = "start"; _build(), 140, 40))
		_body.add_child(row0)
		return
	_selected = clampi(_selected, 0, maps.size() - 1)

	var split: BoxContainer = null
	var right: VBoxContainer = null
	var right_body: VBoxContainer = null
	if _wide:
		split = HBoxContainer.new()
		split.add_theme_constant_override("separation", int(Dp.px(10)))
		split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body.add_child(split)
		right = VBoxContainer.new()
		right.add_theme_constant_override("separation", int(Dp.px(6)))
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_body = VBoxContainer.new()
		right_body.add_theme_constant_override("separation", int(Dp.px(6)))
		right_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rs := TouchList.new()
		rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rs.add_child(right_body)
		right.add_child(rs)
		HudTheme.touch_scroll(rs)

	var box := _card(tr("mp.pick_map"), split)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Dp.px(3)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in maps.size():
		var m: Dictionary = maps[i]
		var msize: Array = m.get("size", [0, 0])
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = i == _selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, Dp.px(32))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s  ·  %d×%d  ·  %s" % [m.get("title", ""), int(msize[0]), int(msize[1]),
				tr("mp.seats_plain") % int(NetHub.map_seats(str(m.get("slug", "")))[1])]
		HudTheme.style_tab(b, 12.0)
		var idx := i
		b.pressed.connect(func():
			Sfx.click(self)
			_selected = idx
			_build())
		list.add_child(b)
	var scroll := TouchList.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, Dp.px(132))
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)
	if _wide:
		box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
		HudTheme.touch_scroll(scroll)

	var pv := _card(tr("mp.preview"), right_body)
	_preview = MapPreview.new()
	_preview.custom_minimum_size = Vector2(Dp.px(180), Dp.px(112))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.set_map(_slug(), {}, -1)
	_preview.tapped.connect(_zoom_map)
	pv.add_child(_preview)
	var m2: Dictionary = maps[_selected]
	var msize2: Array = m2.get("size", [0, 0])
	pv.add_child(_label(tr("menu.skirmish.map_info") % [m2.get("title", ""), int(m2.get("players", 0)),
			_tileset_name(str(m2.get("tileset", ""))), int(msize2[0]), int(msize2[1])], 11.0))
	var seats: Array = NetHub.map_seats(_slug())
	pv.add_child(_label(tr("mp.seats_info") % [int(seats[0]), int(seats[1])] if int(seats[0]) > int(seats[1]) \
			else tr("mp.seats_room") % int(seats[1]), 11.0))
	pv.add_child(_label(tr("mp.map_zoom"), 10.0, true))

	var st := _card(tr("mp.settings"), right_body)
	st.add_child(_button(tr("menu.skirmish.credits") % _credits, func():
		_credits = 2500 if _credits >= 20000 else _credits + 2500
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.starting_units") % tr(UNIT_KEYS.get(_starting_units, "menu.skirmish.units_none")), func():
		var order := ["none", "light", "heavy"]
		_starting_units = order[(order.find(_starting_units) + 1) % order.size()]
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.crates") % tr("word.on" if _crates else "word.off"), func():
		_crates = not _crates
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.explored_map") % tr("word.on" if _explored else "word.off"), func():
		_explored = not _explored
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.fog") % tr("word.on" if _fog else "word.off"), func():
		_fog = not _fog
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.ai_difficulty") % tr(AI_LEVEL_KEYS.get(_ai_level, "menu.skirmish.ai_normal")), func():
		_ai_level = AI_LEVELS[(AI_LEVELS.find(_ai_level) + 1) % AI_LEVELS.size()]
		_build(), 260, 36))
	st.add_child(_button(tr("menu.skirmish.ai_strategy") % tr(AI_STRATEGY_KEYS.get(_ai_strategy, "menu.skirmish.strat_normal")), func():
		var lst: Array = ProtoWorld.AI_STRATEGIES
		_ai_strategy = str(lst[(lst.find(_ai_strategy) + 1) % lst.size()])
		_build(), 260, 36))


	st.add_child(_button(tr("mp.visibility") % tr("mp.public" if _public else "mp.private"), func():
		_public = not _public
		_build(), 260, 36))
	st.add_child(_label(tr("mp.public_hint" if _public else "mp.private_hint"), 10.0, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button(tr("ui.back"), func(): mode = "start"; _build(), 120, 42))
	row.add_child(_button(tr("mp.create_room"), _do_create, 190, 42))
	if _wide:
		right.add_child(row)
		split.add_child(right)
	else:
		_body.add_child(row)


func _slug() -> String:
	if _selected < 0 or _selected >= maps.size():
		return ""
	return str(maps[_selected].get("slug", ""))


const TILESET_KEYS := {"temperat": "tileset.temperat", "snow": "tileset.snow",
		"desert": "tileset.desert", "interior": "tileset.interior"}


static func _tileset_name(t: String) -> String:
	return TranslationServer.translate(TILESET_KEYS[t]) if TILESET_KEYS.has(t) else t


func _zoom_map() -> void:
	if _selected < 0 or _selected >= maps.size():
		return
	var m: Dictionary = maps[_selected]
	var msize: Array = m.get("size", [0, 0])
	MapPreview.open_overlay(self, _slug(), "%s — %d×%d — %s" % [m.get("title", ""),
			int(msize[0]), int(msize[1]), tr("mp.seats_plain") % int(NetHub.map_seats(_slug())[1])],
			tr("mp.map_hint_lobby"))


func main_units_key() -> String:
	return UNIT_KEYS.get(_starting_units, "menu.skirmish.units_none")


func _do_create() -> void:
	if _hub == null or maps.is_empty():
		return
	var slug := _slug()
	var seats: Array = NetHub.map_seats(slug)
	_hub.map_slug = slug
	_hub.settings = {"credits": _credits, "starting_units": _starting_units, "crates": _crates,
			"explored_map": _explored, "fog": _fog, "ai_level": _ai_level, "ai_strategy": _ai_strategy}
	_hub.connect_server("", NetClient.configured_name())
	var public := _public
	var map_name := _map_title(slug)
	_hub.client.opened.connect(func():
		_hub.client.create_room(slug, NetHub.map_sha256(slug), int(seats[1]), _hub.settings,
				public, map_name),
		CONNECT_ONE_SHOT)
	_wait_return = "create"
	mode = "wait"
	_build()


func _build_join() -> void:
	var box := _card(tr("mp.enter_code"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(Dp.px(4)))
	_code_fields = []
	for i in CODE_LEN:
		var e := LineEdit.new()
		e.max_length = 1
		e.alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.custom_minimum_size = Vector2(Dp.px(44), Dp.px(52))
		e.add_theme_font_size_override("font_size", int(Dp.px(22)))
		var idx := i
		e.text_changed.connect(func(t): _on_code_typed(idx, t))
		row.add_child(e)
		_code_fields.append(e)
	box.add_child(row)
	box.add_child(_label(tr("mp.code_hint"), 11.0, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(Dp.px(8)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_child(_button(tr("ui.back"), _leave_join, 120, 42))
	actions.add_child(_button(tr("mp.join_room"), _do_join, 190, 42))
	box.add_child(actions)


	var rooms_card := _card(tr("mp.public_rooms"))
	rooms_card.add_child(_label(tr("mp.public_rooms_hint"), 10.0, true))
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", int(Dp.px(4)))
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_card.add_child(_rooms_box)
	_fill_rooms()
	_code_fields[0].grab_focus.call_deferred()


func _leave_join() -> void:
	if _hub != null and _hub.code == "":
		_hub.leave()
	_rooms = []
	mode = "start"
	_build()


func _fill_rooms() -> void:
	if _rooms_box == null or not is_instance_valid(_rooms_box):
		return
	for c in _rooms_box.get_children():
		_rooms_box.remove_child(c)
		c.queue_free()
	var rooms: Array = demo_rooms if not demo_rooms.is_empty() else _rooms
	if rooms.is_empty():
		_rooms_box.add_child(_label(tr("mp.no_public_rooms"), 11.0, true))
		return
	for r in rooms:
		_rooms_box.add_child(_room_row(r))


func _room_row(r: Dictionary) -> Control:
	var code_text := str(r.get("code", ""))
	var started := bool(r.get("started", false))
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, Dp.px(52))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudTheme.plate_button_style(b, 12.0, 6.0)
	b.tooltip_text = code_text
	b.disabled = started
	if not started:
		b.pressed.connect(func(): Sfx.click(self))
		b.pressed.connect(func(): _join_code(code_text))
	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(Dp.px(7)))
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", int(Dp.px(7)))
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(Dp.px(52), Dp.px(34))
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.texture = MapPreview.texture_for(str(r.get("map", "")))
	content.add_child(thumb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := _label("%s  ·  %s" % [_room_map_name(r), str(r.get("host_name", ""))], 12.0)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.clip_text = true
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var info := _label("%s  ·  %s  ·  %s" % [
			tr("mp.room_seats") % [int(r.get("seats_used", 0)), int(r.get("seats_total", 0))],
			tr("mp.room_running" if started else "mp.room_lobby"), code_text], 10.0, true)
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.clip_text = true
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(info)
	content.add_child(col)
	b.add_child(content)
	return b


func _room_map_name(r: Dictionary) -> String:
	var n := str(r.get("map_name", ""))
	return n if n != "" else _map_title(str(r.get("map", "")))


func _map_title(slug: String) -> String:
	for m in maps:
		if str(m.get("slug", "")) == slug:
			return str(m.get("title", slug))
	return slug


func tap_first_room() -> String:
	if _rooms_box == null or not is_instance_valid(_rooms_box):
		return ""
	for c in _rooms_box.get_children():
		if c is Button and not (c as Button).disabled:
			var b := c as Button
			b.pressed.emit()
			return b.tooltip_text
	return ""


func _join_code(room_code: String) -> void:
	if room_code == "" or _hub == null:
		return
	_hub.when_open(func(): _hub.client.join_room(room_code))
	_wait_return = "join"
	mode = "wait"
	_build()


func _on_code_typed(i: int, t: String) -> void:
	var up := t.to_upper()
	if up != "" and not CODE_CHARS.contains(up):
		_code_fields[i].text = ""
		return
	_code_fields[i].text = up
	_code_fields[i].caret_column = up.length()
	if up != "" and i + 1 < _code_fields.size():
		_code_fields[i + 1].grab_focus()


func code() -> String:
	var out := ""
	for e in _code_fields:
		out += str(e.text)
	return out


func _do_join() -> void:
	var c := code()
	if c.length() < CODE_LEN or _hub == null:
		_status.text = tr("mp.code_incomplete")
		return
	_join_code(c)


func _build_wait() -> void:
	_card("").add_child(_title(tr("mp.connecting"), 16.0))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button(tr("ui.cancel"), func():
		if _hub != null:
			_hub.leave()
		_rooms = []
		mode = _wait_return
		_build(), 160, 42))
	_body.add_child(row)


func _on_state(what: String) -> void:
	if not is_inside_tree():
		return
	match what:
		"created", "joined":
			lobby_entered.emit()
		"error":
			_back_from_error(tr("mp.error") % _error_text(_hub.last_error))
		"closed":
			_back_from_error(tr("mp.disconnected"))


func _back_from_error(text: String) -> void:
	if mode == "join":
		_rooms = []
		_fill_rooms()
		_status.text = text
		return
	mode = _wait_return if mode == "wait" else "start"
	_wait_return = "start"
	_build()
	_status.text = text


static func _error_text(code_name: String) -> String:
	var key := "mp.err." + code_name.split(":")[0].strip_edges()
	var t := TranslationServer.translate(key)
	return code_name if t == key else t
