

class_name SupportPowersPanel
extends Control

signal activate(kind: int, ready: bool, paused: bool)

signal relayout()


const KINDS := 4


const ICONS := ["ironicon", "pdoxicon", "atomicon", "gpssicon"]
const LABELS := ["sp.ironcurtain", "sp.chronoshift", "sp.nuke", "sp.gps"]
const HELP_KEYS := ["help.btn.sp_iron", "help.btn.sp_chrono", "help.btn.sp_nuke", "help.btn.sp_gps"]

const KIND_GPS := 3

const CAMEO_RATIO := 64.0 / 48.0
const READY_BLINK_HZ := 1.2


const MAX_TILES := 2


const LEAD_MARGIN_TICKS := 50

var world: ProtoWorld

var help_host: Node = null

var _state := PackedInt32Array()
var _buttons: Array[Button] = []
var _overlays: Array = []
var _icons: Array = [null, null, null, null]
var _refresh := 0.0

var _col := {}

var _lead := -1

var _expanded := false
var _more: Button = null
var _more_badge = null
var _more_count := 0

var _charge_ticks := PackedInt32Array()


class ChargeOverlay extends Control:
	var charged := false
	var permille := 0
	var paused := false
	var tex: Texture2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()


	func _face() -> Rect2:
		var pad: Vector2 = get_parent().get_meta("hit_pad", Vector2.ZERO) if get_parent() != null else Vector2.ZERO
		return Rect2(pad, size - pad * 2.0)


	func cameo_rect() -> Rect2:
		var r := _face()
		var tsize := tex.get_size() if tex != null else Vector2.ZERO
		if tsize.x <= 0.0 or tsize.y <= 0.0:
			tsize = Vector2(CAMEO_RATIO, 1.0)
		var s := minf(r.size.x / tsize.x, r.size.y / tsize.y)
		var draw_size := tsize * s
		return Rect2(r.position + (r.size - draw_size) / 2.0, draw_size)

	func _draw() -> void:
		var cameo := cameo_rect()


		draw_rect(cameo, HudTheme.BORDER_DIM, false, maxf(1.0, Dp.px(1.2)))
		if charged:

			var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * READY_BLINK_HZ)
			var gold := HudTheme.GOLD
			draw_rect(cameo.grow(Dp.px(1)), Color(gold.r, gold.g, gold.b, lerpf(0.45, 1.0, blink)), false, Dp.px(2.5))
		else:

			var covered := cameo.size.y * (1.0 - permille / 1000.0)
			draw_rect(Rect2(cameo.position, Vector2(cameo.size.x, covered)), Color(0, 0, 0, 0.6), true)
			if paused:
				draw_rect(cameo.grow(-Dp.px(2)), Color(0.8, 0.1, 0.1, 0.25), true)


		var font := ThemeDB.fallback_font
		var fs := int(Dp.px(10))
		var strip_h := fs + Dp.px(4)
		var strip := Rect2(cameo.position.x + Dp.px(2), cameo.end.y - strip_h - Dp.px(2),
			cameo.size.x - Dp.px(4), strip_h)
		draw_rect(strip, Color(0, 0, 0, 0.92), true)
		var txt := tr("ui.ready") if charged else "%d%%" % (permille / 10)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(strip.get_center().x - tw / 2.0, strip.get_center().y + fs * 0.38)
		draw_string(font, at + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.GOLD if charged else HudTheme.TEXT)


class MoreBadge extends Control:
	var count := 0
	var open := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)


	func _face() -> Rect2:
		var pad: Vector2 = get_parent().get_meta("hit_pad", Vector2.ZERO) if get_parent() != null else Vector2.ZERO
		return Rect2(pad, size - pad * 2.0)

	func _draw() -> void:
		var r := _face()
		HudTheme.draw_panel(self, r, HudTheme.PANEL_BG_SOLID, HudTheme.BORDER, 6.0)
		var font := ThemeDB.fallback_font
		var fs := int(maxf(Dp.px(20), 10.0))
		var txt := "+%d" % count
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(r.get_center().x - tw / 2.0, r.get_center().y + fs * 0.30)
		draw_string(font, at + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.GOLD)

		var c := Vector2(r.get_center().x, r.end.y - Dp.px(9))
		var w := Dp.px(5)
		var pts := PackedVector2Array()
		if open:
			pts = PackedVector2Array([c + Vector2(-w, w * 0.6), c + Vector2(w, w * 0.6), c + Vector2(0, -w * 0.6)])
		else:
			pts = PackedVector2Array([c + Vector2(w * 0.6, -w), c + Vector2(w * 0.6, w), c + Vector2(-w * 0.6, 0)])
		draw_colored_polygon(pts, HudTheme.BORDER)


func _ready() -> void:

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in KINDS:
		var b := Button.new()
		b.name = "SupportPower%d" % k
		b.visible = false
		b.text = ""
		b.tooltip_text = tr(LABELS[k])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		HudTheme.style_icon_button(b)
		HudTheme.wire_help(b, HELP_KEYS[k], help_host if help_host != null else self, _fire.bind(k))
		add_child(b)

		b.add_to_group("layout_hud")
		_buttons.append(b)
		var ov := ChargeOverlay.new()
		b.add_child(ov)
		_overlays.append(ov)


	_more = Button.new()
	_more.name = "SupportPowerMore"
	_more.visible = false
	_more.text = ""
	_more.tooltip_text = tr("sp.more")
	HudTheme.style_icon_button(_more)
	HudTheme.wire_help(_more, "help.btn.sp_more", help_host if help_host != null else self, _toggle_expand)
	add_child(_more)
	_more.add_to_group("layout_hud")
	_more_badge = MoreBadge.new()
	_more.add_child(_more_badge)
	_read_charge_intervals()


func _read_charge_intervals() -> void:
	_charge_ticks.resize(KINDS)
	for k in KINDS:
		_charge_ticks[k] = 3000
	var actors: Dictionary = RulesDb.data().get("actors", {})
	for t in actors:
		var sp = (actors[t] as Dictionary).get("support_power", null)
		if sp is Dictionary:
			var k: int = RulesDb.SP_KINDS.find(str((sp as Dictionary).get("kind", "")))
			if k >= 0 and k < KINDS:
				_charge_ticks[k] = maxi(int((sp as Dictionary).get("charge_interval", 3000)), 1)


func _fire(k: int) -> void:
	if not _available(k):
		return
	_set_expanded(false)
	activate.emit(k, _state[k * 4 + 1] == 1, _state[k * 4 + 3] == 1)


func _toggle_expand() -> void:
	_set_expanded(not _expanded)


func _set_expanded(on: bool) -> void:
	if _expanded == on:
		return
	_expanded = on
	if _more_badge != null:
		_more_badge.open = on
		_more_badge.queue_redraw()
	if on:
		move_to_front()


	_refresh_display()
	relayout.emit()


func expanded() -> bool:
	return _expanded


func set_expanded(on: bool) -> void:
	_set_expanded(on)


func lead_kind() -> int:
	return _lead


func remaining_ticks(k: int) -> int:
	if not _available(k):
		return 1 << 30
	if _state[k * 4 + 1] == 1:
		return 0
	var per := clampi(_state[k * 4 + 2], 0, 1000)
	var full: int = _charge_ticks[k] if k < _charge_ticks.size() else 3000
	return full * (1000 - per) / 1000


func _pick_lead(kinds: Array[int]) -> int:
	if kinds.is_empty():
		return -1
	var best: int = kinds[0]
	var best_rem := remaining_ticks(best)
	for k in kinds:
		var rem := remaining_ticks(k)
		if rem < best_rem or (rem == best_rem and k < best):
			best = k
			best_rem = rem
	if kinds.has(_lead) and remaining_ticks(_lead) <= best_rem + LEAD_MARGIN_TICKS:
		return _lead
	return best


func _process(delta: float) -> void:
	if world == null or world.sim == null:
		return
	_refresh += delta
	if _refresh < 0.2:
		return
	_refresh = 0.0
	_poll()


func refresh_now() -> void:
	if world != null and world.sim != null:
		_poll()


func _poll() -> void:
	_state = world.support_powers()
	for k in KINDS:
		if not _available(k):
			continue
		if _icons[k] == null and world.atlas() != null and world.atlas().sprite_frame_count.has(ICONS[k]):
			_icons[k] = world.atlas().make_rgba_texture(ICONS[k], 0)
			_buttons[k].icon = _icons[k]
			_overlays[k].tex = _icons[k]
		var ov: ChargeOverlay = _overlays[k]
		ov.charged = _state[k * 4 + 1] == 1
		ov.permille = _state[k * 4 + 2]
		ov.paused = _state[k * 4 + 3] == 1
	if _refresh_display():
		relayout.emit()


func _refresh_display() -> bool:
	var kinds := visible_kinds()
	var lead := _lead
	var more := 0
	if kinds.size() > MAX_TILES:
		lead = _pick_lead(kinds)
		more = kinds.size() - 1
	else:
		lead = -1
	var changed := lead != _lead or more != _more_count
	_lead = lead
	_more_count = more
	if _expanded and more == 0:
		_set_expanded(false)
	for k in KINDS:
		var vis := _available(k) and (more == 0 or k == _lead or _expanded)
		if _buttons[k].visible != vis:
			_buttons[k].visible = vis
			changed = true
	if _more != null and _more.visible != (more > 0):
		_more.visible = more > 0
		changed = true
	if _more_badge != null and _more_badge.count != more:
		_more_badge.count = more
		_more_badge.queue_redraw()
	return changed


func _available(k: int) -> bool:
	return _state.size() >= (k + 1) * 4 and _state[k * 4] == 1


func visible_kinds() -> Array[int]:
	var out: Array[int] = []
	for k in KINDS:
		if _available(k):
			out.append(k)
	return out


func button_of(k: int) -> Button:
	return _buttons[k] if k >= 0 and k < _buttons.size() else null


func layout_stack(right_x: float, build_top_y: float, side: float, gap: float,
		fan_left: float, top_y: float) -> void:
	var kinds := visible_kinds()


	var step := maxf(gap, HudTheme.min_touch_px() - side)
	var pad := Vector2(step, step) / 2.0

	var bottom_y := build_top_y - step
	var x := right_x - side
	_col = {"tiles": 0, "more": _more_count, "expanded": _expanded, "lead": _lead,
		"fan_rows": 0, "fan_per_row": 0, "side": side, "step": step}
	if kinds.is_empty():
		return
	if _more_count == 0:


		for i in kinds.size():
			var from_bottom := kinds.size() - 1 - i
			HudTheme.place_touch(_buttons[kinds[i]],
				Vector2(x, bottom_y - side - from_bottom * (side + step)), Vector2(side, side), pad)
		_col["tiles"] = kinds.size()
		return

	HudTheme.place_touch(_buttons[_lead], Vector2(x, bottom_y - side), Vector2(side, side), pad)
	var badge_y := bottom_y - 2.0 * side - step
	HudTheme.place_touch(_more, Vector2(x, badge_y), Vector2(side, side), pad)
	_col["tiles"] = 1
	if not _expanded:
		return


	var fan: Array[int] = []
	for k in kinds:
		if k != _lead:
			fan.append(k)
	var right_edge := x - step
	var room := maxf(right_edge - fan_left, side)
	var per_row := maxi(int(floor((room + step) / (side + step))), 1)

	var rows_up := maxi(int(floor((badge_y - top_y) / (side + step))) + 1, 1)
	per_row = maxi(per_row, int(ceil(fan.size() / float(rows_up))))
	per_row = mini(per_row, fan.size())
	var rows := int(ceil(fan.size() / float(per_row)))
	for j in fan.size():
		var row := j / per_row
		var col := j % per_row
		var in_row := mini(fan.size() - row * per_row, per_row)
		var row_left := right_edge - (in_row * side + (in_row - 1) * step)
		HudTheme.place_touch(_buttons[fan[j]],
			Vector2(row_left + col * (side + step), badge_y - row * (side + step)),
			Vector2(side, side), pad)
	_col["fan_rows"] = rows
	_col["fan_per_row"] = per_row


func more_button() -> Button:
	return _more


func column_info() -> Dictionary:
	return _col.duplicate()
