

extends VBoxContainer

const NetHub := preload("res://scripts/net/net_hub.gd")

signal sent(text: String, scope: String)

signal input_focus(on: bool)


const QUICK := ["#attack", "#help", "#yes", "#no", "#wait", "#gg"]

var scope := "all"
var show_quick := true


var show_log := true

var draw_background := false
var history_rows := 8

var _log: RichTextLabel
var _edit: LineEdit
var _scope_btn: Button
var _hub: Node = null


func _draw() -> void:
	if draw_background:
		HudTheme.draw_panel(self, Rect2(Vector2.ZERO, size), HudTheme.PANEL_BG_SOLID, HudTheme.BORDER, 6.0)


func _ready() -> void:
	add_theme_constant_override("separation", int(Dp.px(4)))
	resized.connect(queue_redraw)
	_hub = NetHub.hub()
	if show_log:
		_log = RichTextLabel.new()
		_log.bbcode_enabled = true
		_log.scroll_following = true
		_log.fit_content = false
		_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_log.custom_minimum_size = Vector2(0, Dp.px(16) * history_rows)
		_log.add_theme_font_size_override("normal_font_size", int(Dp.px(12)))
		_log.add_theme_color_override("default_color", HudTheme.TEXT)
		_log.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_log)
	if show_quick:
		var quick := HBoxContainer.new()
		quick.add_theme_constant_override("separation", int(Dp.px(4)))
		for key in QUICK:
			var b := Button.new()
			b.text = tr("chat.quick." + key.substr(1))
			b.custom_minimum_size = Vector2(0, Dp.px(34))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudTheme.style_button(b, 11.0)
			var k: String = str(key)
			b.pressed.connect(func():
				Sfx.click(self)
				_send(k))
			quick.add_child(b)
		add_child(quick)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(4)))
	_scope_btn = Button.new()
	_scope_btn.custom_minimum_size = Vector2(Dp.px(78), Dp.px(38))
	HudTheme.style_button(_scope_btn, 12.0)
	_scope_btn.pressed.connect(func():
		scope = "team" if scope == "all" else "all"
		_update_scope())
	row.add_child(_scope_btn)
	_edit = LineEdit.new()
	_edit.placeholder_text = tr("chat.placeholder")
	_edit.max_length = 200
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, Dp.px(38))
	_edit.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_edit.text_submitted.connect(func(t): _send(t); _edit.text = "")
	_edit.focus_entered.connect(func(): input_focus.emit(true))
	_edit.focus_exited.connect(func(): input_focus.emit(false))
	row.add_child(_edit)
	var send_btn := Button.new()
	send_btn.text = tr("chat.send")
	send_btn.custom_minimum_size = Vector2(Dp.px(74), Dp.px(38))
	HudTheme.style_button(send_btn, 12.0)
	send_btn.pressed.connect(func():
		_send(_edit.text)
		_edit.text = "")
	row.add_child(send_btn)
	add_child(row)
	_update_scope()
	if _hub != null:
		_hub.chat_added.connect(_on_line)
		refresh()


func _update_scope() -> void:
	_scope_btn.text = tr("chat.scope_all") if scope == "all" else tr("chat.scope_team")


func focus_input() -> void:
	if _edit != null:
		_edit.grab_focus()


func has_input_focus() -> bool:
	return _edit != null and _edit.has_focus()


func release_input() -> void:
	if _edit != null and _edit.has_focus():
		_edit.release_focus()


func _send(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	if _hub != null:
		_hub.send_chat(t, scope)
	sent.emit(t, scope)


func _on_line(_line: Dictionary) -> void:
	refresh()


func refresh() -> void:
	if _log == null or _hub == null:
		return
	_log.clear()
	for line in _hub.chat:
		_log.append_text(format_line(line) + "\n")


static func format_line(line: Dictionary) -> String:
	var col: Color = player_color(int(line.get("color", 0)))
	return "[color=#%s]%s:[/color] %s" % [col.to_html(false), str(line.get("name", "?")),
			NetHub.display_text(line).replace("[", "[lb]")]


static func player_color(idx: int) -> Color:
	var seats: Array = NetHub.SIM_SEATS
	var cols: Array = ProtoWorld.PLAYER_COLORS
	return cols[int(seats[clampi(idx, 0, seats.size() - 1)])]
