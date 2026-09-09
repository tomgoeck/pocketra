

extends VBoxContainer

const NetHub := preload("res://scripts/net/net_hub.gd")
const ChatPanel := preload("res://scripts/ui/chat_panel.gd")
const MapPreview := preload("res://scripts/ui/map_preview.gd")

signal leave_pressed()

const FACTIONS := ["allies", "soviet", "random"]

var maps: Array = []

var _hub: Node = null
var _rows: VBoxContainer
var _code_label: Label
var _hint: Label
var _preview: Control
var _visibility_btn: Button = null
var _visibility_lbl: Label = null
var _start_btn: Button
var _ready_btn: Button
var _chat = null
var _my_ready := false


func _ready() -> void:
	add_theme_constant_override("separation", int(Dp.px(6)))
	_hub = NetHub.hub()
	if _hub != null:
		if not _hub.lobby_changed.is_connected(_on_lobby):
			_hub.lobby_changed.connect(_on_lobby)
		if not _hub.state_changed.is_connected(_on_state):
			_hub.state_changed.connect(_on_state)
	_build()


func _card(head_text: String, parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(10.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(4)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	if head_text != "":
		var head := Label.new()
		head.text = head_text
		head.add_theme_font_size_override("font_size", int(Dp.px(13)))
		head.add_theme_color_override("font_color", HudTheme.GOLD)
		box.add_child(head)
	parent.add_child(panel)
	return box


func _build() -> void:
	MapPreview.close_overlay(self)
	_close_map_picker()
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var top := _card("", self)
	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", int(Dp.px(30)))
	_code_label.add_theme_color_override("font_color", HudTheme.GOLD)
	_code_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_code_label.add_theme_constant_override("outline_size", int(Dp.px(2)))
	top.add_child(_code_label)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_hint.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	top.add_child(_hint)


	_visibility_btn = null
	_visibility_lbl = null
	var vis_row := HBoxContainer.new()
	vis_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if _hub != null and _hub.host:
		_visibility_btn = _btn(tr("mp.visibility_private"), _toggle_visibility, 210, 36)
		vis_row.add_child(_visibility_btn)
	else:
		_visibility_lbl = Label.new()
		_visibility_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_visibility_lbl.add_theme_font_size_override("font_size", int(Dp.px(11)))
		_visibility_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		vis_row.add_child(_visibility_lbl)
	top.add_child(vis_row)
	var landscape := get_viewport().get_visible_rect().size.x >= get_viewport().get_visible_rect().size.y
	var split: BoxContainer = HBoxContainer.new() if landscape else VBoxContainer.new()
	split.add_theme_constant_override("separation", int(Dp.px(8)))
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", int(Dp.px(6)))

	var mapbox := _card(tr("mp.preview"), left)
	_preview = MapPreview.new()
	_preview.custom_minimum_size = Vector2(Dp.px(180), Dp.px(112))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.tapped.connect(_zoom_map)
	mapbox.add_child(_preview)

	mapbox.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	mapbox.get_parent().size_flags_stretch_ratio = 1.4
	var maprow := HBoxContainer.new()
	maprow.add_theme_constant_override("separation", int(Dp.px(6)))
	maprow.add_child(_btn(tr("mp.map_big"), _zoom_map, 150, 34))
	if _hub != null and _hub.host and not maps.is_empty():
		maprow.add_child(_btn(tr("mp.change_map"), _open_map_picker, 170, 34))
	mapbox.add_child(maprow)
	var seatbox := _card(tr("lobby.slots"), left)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", int(Dp.px(3)))
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := TouchList.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, Dp.px(120))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	seatbox.add_child(scroll)
	seatbox.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.45
	split.add_child(left)

	var chatbox := _card(tr("mp.chat_log"), split)
	_chat = ChatPanel.new()
	_chat.history_rows = 6
	_chat.draw_background = false
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat.custom_minimum_size = Vector2(Dp.px(200), Dp.px(140))
	chatbox.add_child(_chat)
	chatbox.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chatbox.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(Dp.px(8)))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_child(_btn(tr("mp.leave"), _do_leave, 158, 42))
	_ready_btn = _btn(tr("mp.ready"), _toggle_ready, 150, 42)
	actions.add_child(_ready_btn)
	_start_btn = _btn(tr("mp.start"), _start_game, 150, 42)
	actions.add_child(_start_btn)
	add_child(actions)
	refresh()


func _do_leave() -> void:
	if _hub != null:
		_hub.leave()
	leave_pressed.emit()


func _btn(text: String, cb: Callable, w: float, h: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(w), Dp.px(h))
	HudTheme.plate_button_style(b, 13.0, 10.0)
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


func _toggle_visibility() -> void:
	if _hub != null and _hub.client != null:
		_hub.client.set_visibility(not bool(_hub.room_public))


func _on_lobby(_d: Dictionary) -> void:
	refresh()


func _on_state(what: String) -> void:


	if what in ["closed", "error", "reconnecting", "resumed", "session"]:
		refresh()


func refresh() -> void:
	if _hub == null or _rows == null:
		return
	_code_label.text = _hub.code
	var vis_key := "mp.visibility_public" if bool(_hub.room_public) else "mp.visibility_private"
	if _visibility_btn != null:
		_visibility_btn.text = tr(vis_key)
	if _visibility_lbl != null:
		_visibility_lbl.text = tr(vis_key)
	var slug: String = str(_hub.map_slug)
	var seats: Array = NetHub.map_seats(slug)
	var total := int(seats[0])
	var usable := int(seats[1])
	var lines: Array = []
	lines.append(tr("mp.map") % _map_title(slug))
	if total > usable:
		lines.append(tr("mp.seats_info") % [total, usable])
	if bool(_hub.reconnecting):
		lines.append(tr("mp.reconnecting"))
	elif _hub.last_error != "":
		lines.append(tr("mp.error") % _error_text(_hub.last_error))
	_hint.text = "  ·  ".join(PackedStringArray(lines))
	var clients: Array = _hub.lobby.get("clients", [])
	if _preview != null:
		_preview.set_map(slug, _taken_spawns(), _my_spawn())
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var all_ready := clients.size() > 0
	for c in clients:
		_rows.add_child(_seat_row(c))
		if str(c.get("kind", "human")) == "human" and not bool(c.get("ready", false)):
			all_ready = false
	if _hub.host and clients.size() < usable:
		var level: String = str(_hub.settings.get("ai_level", "normal"))
		var add := _btn(tr("mp.add_bot"), func():
			_hub.client.add_bot(level, "random", 0), 160, 34)
		_rows.add_child(add)


	var me := _my_row()
	if not me.is_empty():
		_my_ready = bool(me.get("ready", false))
	_ready_btn.text = tr("mp.not_ready") if _my_ready else tr("mp.ready")
	_start_btn.visible = _hub.host
	_start_btn.disabled = not all_ready


func _error_text(code: String) -> String:
	if code.begins_with("spawnoccupied"):
		return tr("lobby.spawn_taken")
	return code


func _taken_spawns() -> Dictionary:
	var out := {}
	if _hub == null:
		return out
	for c in _hub.lobby.get("clients", []):
		var sp := int(c.get("spawn", -1))
		if sp >= 0 and int(c.get("seat", -1)) != int(_hub.my_seat):
			out[sp] = int(c.get("color", 0))
	return out


func _my_spawn() -> int:
	if _hub == null:
		return -1
	for c in _hub.lobby.get("clients", []):
		if int(c.get("seat", -1)) == int(_hub.my_seat):
			return int(c.get("spawn", -1))
	return -1


func _my_row() -> Dictionary:
	if _hub != null:
		for c in _hub.lobby.get("clients", []):
			if int(c.get("seat", -1)) == int(_hub.my_seat):
				return c
	return {}


func _map_title(slug: String) -> String:
	for m in MapData.list_maps():
		if str(m.get("slug", "")) == slug:
			return str(m.get("title", slug))
	return slug


func _zoom_map() -> void:
	if _hub == null:
		return
	var slug: String = str(_hub.map_slug)
	var seats: Array = NetHub.map_seats(slug)
	var head := "%s — %s" % [_map_title(slug), tr("mp.seats_plain") % int(seats[1])]
	var mine := _my_spawn()
	MapPreview.open_overlay(self, slug, head, tr("lobby.map_hint"), _taken_spawns(), mine,
			func(idx): _pick_spawn(-1 if idx == mine else idx))


func open_map_overlay() -> void:
	_zoom_map()


func open_map_picker() -> void:
	_open_map_picker()


func _pick_spawn(idx: int) -> void:
	var c := _my_row()
	if _hub == null or _hub.client == null or c.is_empty():
		return


	_hub.last_error = ""
	_hub.client.set_slot(str(c.get("faction", "random")), int(c.get("team", 0)),
			int(c.get("color", 0)), idx)


var _picker: Control = null


func _open_map_picker() -> void:
	if _hub == null or not _hub.host or maps.is_empty():
		return
	_close_map_picker()
	var safe := Dp.safe_rect()
	_picker = Control.new()
	_picker.name = "MapPicker"
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_close_map_picker())
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker.add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(12.0))
	panel.position = safe.position + Vector2(Dp.px(12), Dp.px(12))
	panel.size = safe.size - Vector2(Dp.px(24), Dp.px(24))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	panel.add_child(box)
	var head := Label.new()
	head.text = tr("mp.change_map")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", int(Dp.px(16)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Dp.px(3)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in maps:
		var slug := str(m.get("slug", ""))
		var msize: Array = m.get("size", [0, 0])
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, Dp.px(32))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s  ·  %d×%d  ·  %s" % [m.get("title", ""), int(msize[0]), int(msize[1]),
				tr("mp.seats_plain") % int(NetHub.map_seats(slug)[1])]
		HudTheme.style_tab(b, 12.0)
		b.toggle_mode = true
		b.button_pressed = slug == str(_hub.map_slug)
		b.pressed.connect(func():
			Sfx.click(self)
			_change_map(slug))
		list.add_child(b)
	var scroll := TouchList.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	box.add_child(scroll)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_btn(tr("ui.close"), _close_map_picker, 150, 42))
	box.add_child(row)
	_picker.add_child(panel)
	MapPreview.overlay_host(self).add_child(_picker)
	HudTheme.touch_scroll(scroll)


func _close_map_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null


func _change_map(slug: String) -> void:
	_close_map_picker()
	if _hub == null or _hub.client == null or slug == "":
		return
	_hub.map_slug = slug
	_hub.client.change_map(slug, NetHub.map_sha256(slug), int(NetHub.map_seats(slug)[1]), {},
			_map_title(slug))


func _seat_row(c: Dictionary) -> Control:
	var seat := int(c.get("seat", -1))
	var mine: bool = seat == int(_hub.my_seat)
	var is_bot: bool = str(c.get("kind", "human")) == "bot"


	var can_edit: bool = mine or (_hub.host and is_bot)
	var edit_seat: int = -1 if mine else seat
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(4)))
	var dot := ColorRect.new()
	dot.color = ChatPanel.player_color(int(c.get("color", 0)))
	dot.custom_minimum_size = Vector2(Dp.px(14), Dp.px(14))
	row.add_child(dot)


	var absent := bool(c.get("absent", false))
	var name_lbl := Label.new()
	name_lbl.text = str(c.get("name", "?"))
	if absent:
		name_lbl.text += " ⟳"
	if is_bot:
		name_lbl.text = "%s (%s)" % [tr("mp.bot"), tr("menu.skirmish.ai_" + str(c.get("level", "normal")))]
	if seat == int(_hub.host_seat):
		name_lbl.text += " ★"
	name_lbl.custom_minimum_size = Vector2(Dp.px(96), 0)
	name_lbl.add_theme_font_size_override("font_size", int(Dp.px(12)))
	name_lbl.add_theme_color_override("font_color",
			HudTheme.TEXT_DIM if absent else (HudTheme.GOLD if mine else HudTheme.TEXT))
	row.add_child(name_lbl)
	var team := int(c.get("team", 0))
	var spawn := int(c.get("spawn", -1))
	var faction_text := tr("faction." + str(c.get("faction", "random")))
	var team_text: String = tr("lobby.team") % (str(team) if team > 0 else tr("lobby.team_none"))
	var spawn_text: String = tr("lobby.spawn") % (str(spawn + 1) if spawn >= 0 else tr("lobby.spawn_random"))
	if can_edit:
		row.add_child(_cycle(faction_text, true, func():
			var f := str(c.get("faction", "random"))
			_hub.client.set_slot(FACTIONS[(FACTIONS.find(f) + 1) % FACTIONS.size()],
					int(c.get("team", 0)), int(c.get("color", 0)), int(c.get("spawn", -1)),
					edit_seat)))
		row.add_child(_cycle(team_text, true, func():
			_hub.client.set_slot(str(c.get("faction", "random")), (team + 1) % 5,
					int(c.get("color", 0)), int(c.get("spawn", -1)), edit_seat)))
	else:
		row.add_child(_value(faction_text, 92.0, HudTheme.TEXT))
		row.add_child(_value(team_text, 92.0, HudTheme.GOLD if team > 0 else HudTheme.TEXT_DIM))


	if mine:
		row.add_child(_cycle(spawn_text, true, _zoom_map, 116.0))
	else:
		row.add_child(_value(spawn_text, 116.0, HudTheme.TEXT if spawn >= 0 else HudTheme.TEXT_DIM))
	var ready_lbl := Label.new()
	ready_lbl.text = "✔" if bool(c.get("ready", false)) or is_bot else "…"
	ready_lbl.custom_minimum_size = Vector2(Dp.px(20), 0)
	ready_lbl.add_theme_font_size_override("font_size", int(Dp.px(13)))
	ready_lbl.add_theme_color_override("font_color", HudTheme.READY_GREEN if bool(c.get("ready", false)) else HudTheme.TEXT_DIM)
	row.add_child(ready_lbl)
	var ping_lbl := Label.new()
	var ping := int(c.get("ping", -1))
	ping_lbl.text = "" if str(c.get("kind", "human")) == "bot" else ("%d ms" % ping if ping >= 0 else "—")
	if absent:
		ping_lbl.text = tr("mp.absent")
	ping_lbl.custom_minimum_size = Vector2(Dp.px(48), 0)
	ping_lbl.add_theme_font_size_override("font_size", int(Dp.px(11)))
	ping_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	row.add_child(ping_lbl)
	if _hub.host and not mine:
		var kick := Button.new()
		kick.text = "✕"
		kick.custom_minimum_size = Vector2(Dp.px(34), Dp.px(30))
		HudTheme.plate_button_style(kick, 12.0, 6.0)
		kick.pressed.connect(func():
			Sfx.click(self)
			if str(c.get("kind", "human")) == "bot":
				_hub.client.remove_bot(seat)
			else:
				_hub.client.kick(seat))
		row.add_child(kick)
	return row


func _value(text: String, w: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(Dp.px(w), Dp.px(30))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(Dp.px(11)))
	l.add_theme_color_override("font_color", col)
	return l


func _cycle(text: String, enabled: bool, cb: Callable, w: float = 92.0) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(Dp.px(w), Dp.px(30))
	HudTheme.plate_button_style(b, 11.0, 6.0)
	if enabled:
		b.pressed.connect(func(): Sfx.click(self))
		b.pressed.connect(cb)
	return b


func _toggle_ready() -> void:
	_my_ready = not _my_ready
	if _hub != null and _hub.client != null:
		_hub.client.set_ready(_my_ready)


func _start_game() -> void:
	if _hub == null or not _hub.host:
		return
	var clients: Array = _hub.lobby.get("clients", [])
	var setup: Dictionary = _hub.build_setup(str(_hub.map_slug), clients, _hub.settings)
	_hub.client.start_game(setup)
