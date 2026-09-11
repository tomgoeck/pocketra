

extends Control

signal chosen(action: String)


signal dismissed(pos: Vector2)


const BTN_W_DP := 100.0
const BTN_H_DP := 50.0
const GAP_DP := 8.0

const MAX_COLS := 4


var ITEMS: Array = []

var _panel: PanelContainer
var _head: Label
var _flow: HFlowContainer
var _buttons := {}
var _ring := Vector2.ZERO
var _ring_r := 0.0


func _ready() -> void:


	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", HudTheme.panel(HudTheme.PANEL_BG_SOLID, HudTheme.BORDER, 8.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(4)))
	_head = Label.new()
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_head.add_theme_color_override("font_color", HudTheme.GOLD)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_head)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", int(Dp.px(GAP_DP)))
	_flow.add_theme_constant_override("v_separation", int(Dp.px(GAP_DP)))
	box.add_child(_flow)
	_panel.add_child(box)
	add_child(_panel)
	hide()


func open(items: Array, anchor: Vector2, title: String, ring: Vector2 = Vector2.ZERO,
		ring_r: float = 0.0, min_y: float = 0.0) -> void:
	ITEMS = items.duplicate()
	_ring = ring
	_ring_r = ring_r
	_head.text = title
	for c in _flow.get_children():
		c.queue_free()
	_buttons.clear()
	var vs := get_viewport().get_visible_rect().size
	size = vs
	var safe := Dp.safe_rect()


	if safe.size.x <= 1.0 or safe.size.y <= 1.0:
		safe = Rect2(Vector2.ZERO, vs)
	var bw := Dp.px(BTN_W_DP)
	var gap := Dp.px(GAP_DP)
	var room := maxf(safe.size.x - Dp.px(24), bw)
	var fit := maxi(1, int((room + gap) / (bw + gap)))
	var cols: int = clampi(ITEMS.size(), 1, mini(MAX_COLS, fit))
	_flow.custom_minimum_size = Vector2(cols * bw + (cols - 1) * gap, 0)
	for id in ITEMS:
		var b := Button.new()
		b.text = tr("radial.action.%s" % id)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(bw, Dp.px(BTN_H_DP))
		HudTheme.plate_button_style(b, 12.0, 6.0)
		var key := str(id)
		b.pressed.connect(func(): _pick(key))
		_flow.add_child(b)
		_buttons[key] = b
	show()
	_panel.reset_size()
	_place(anchor, safe, min_y)


	await get_tree().process_frame
	if visible:
		_panel.reset_size()
		_place(anchor, safe, min_y)
	queue_redraw()


func _place(anchor: Vector2, safe: Rect2, min_y: float) -> void:
	var sz: Vector2 = _panel.size.min(safe.size)
	_panel.size = sz
	var avail := safe.size - sz
	var pos := Vector2(anchor.x - sz.x / 2.0, anchor.y - Dp.px(70) - sz.y)
	pos.y = maxf(pos.y, min_y)
	pos.x = clampf(pos.x, safe.position.x, safe.position.x + maxf(avail.x, 0.0))
	pos.y = clampf(pos.y, safe.position.y, safe.position.y + maxf(avail.y, 0.0))
	_panel.position = pos


func button_for(action: String) -> Button:
	return _buttons.get(action, null)


func _pick(action: String) -> void:
	hide()
	ITEMS = []
	chosen.emit(action)


func _gui_input(e: InputEvent) -> void:
	var hit := (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed) \
			or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed)
	if hit:
		accept_event()
		var pos: Vector2 = (e as InputEventScreenTouch).position if e is InputEventScreenTouch \
				else (e as InputEventMouseButton).position
		ITEMS = []
		hide()
		dismissed.emit(pos)


func cancel() -> void:
	ITEMS = []
	hide()


func _draw() -> void:


	if not visible or _ring_r <= 0.0:
		return
	draw_arc(_ring, _ring_r, 0.0, TAU, 32, HudTheme.GOLD, maxf(1.5, Dp.px(2.0)), true)
	draw_arc(_ring, _ring_r * 0.62, 0.0, TAU, 24, Color(HudTheme.GOLD, 0.45), maxf(1.0, Dp.px(1.0)), true)
