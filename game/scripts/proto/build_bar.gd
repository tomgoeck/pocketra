

class_name BuildBar
extends Control


const NetOrders := preload("res://scripts/net/net_orders.gd")


const Desktop := preload("res://scripts/desktop.gd")

signal build_requested(type_id: int)
signal cancel_requested(kind: int, type_id: int)
signal place_requested(type_id: int)
signal blocked(text: String)
signal height_changed()


signal ready_changed(any_ready: bool)

const KIND_KEYS := ["buildbar.buildings", "buildbar.defense", "buildbar.infantry", "buildbar.vehicles",
	"buildbar.aircraft", "buildbar.ships"]
const KIND_QUEUES := [0, 3, 1, 2, 4, 5]


const TAB_ICON_PATHS := ["res://icons/ui/btn_tab_gebaeude_2.png", "res://icons/ui/btn_tab_abwehr_1.png",
	"res://icons/ui/btn_tab_infanterie_2.png", "res://icons/ui/btn_tab_fahrzeuge_1.png",
	"res://icons/ui/btn_tab_flugzeuge_2.png", "res://icons/ui/btn_tab_schiffe_1.png"]

const TAB_HELP_KEYS := ["help.btn.tab_building", "help.btn.tab_defense", "help.btn.tab_infantry",
	"help.btn.tab_vehicle", "help.btn.tab_aircraft", "help.btn.tab_ship"]


const MAX_COLUMNS := 4
const MIN_COLUMNS := 2
const ROWS := 3
const MAX_SHORT_SIDE := 0.30


const LONG_PRESS_MS := 600
const MARGIN_DP := 6.0
const TAB_H_DP := 52.0
const TAB_W_DP := 60.0
const SLOT_W_DP := 64.0
const SLOT_H_DP := 48.0


const HIDDEN_TYPES: Array[String] = []


const ARMOR_TR_KEYS := ["armor.none", "armor.wood", "armor.light", "armor.heavy", "armor.concrete", "armor.tree"]
const INFO_WIDTH_DP := 260.0

var world: ProtoWorld
var kind := 0
var columns := MAX_COLUMNS
var _tabs: Array[Button] = []
var _tab_glow: Array = []
var _any_ready := false
var _slots: Array = []
var _icons := {}
var _refresh := 0.0
var _slot_size := Vector2(64, 48)
var _area: Control
var _scroll := 0.0
var _content_h := 0.0
var _lists := {}
var _shown := {}
var _cancel_popup: PanelContainer
var _popup_backdrop: ColorRect = null


static func rows_for(short_px: float) -> int:
	var h3 := Dp.px(TAB_H_DP + 2 * MARGIN_DP + 3 * (SLOT_H_DP + MARGIN_DP))
	return 3 if (short_px <= 0.0 or h3 <= short_px * MAX_SHORT_SIDE) else 2


static func preferred_size(short_px: float = 0.0, cols: int = MAX_COLUMNS) -> Vector2:
	return Vector2(Dp.px(cols * SLOT_W_DP + (cols + 1) * MARGIN_DP),
			Dp.px(TAB_H_DP + 2 * MARGIN_DP + rows_for(short_px) * (SLOT_H_DP + MARGIN_DP)))


func wanted_size(short_px: float = 0.0) -> Vector2:
	var out := preferred_size(short_px, columns)
	var n: int = int(_shown.get(kind, _lists.get(kind, []).size()))
	if n > 0:
		var rows := clampi(int(ceil(n / float(columns))), 1, rows_for(short_px))
		out.y = Dp.px(TAB_H_DP + 2 * MARGIN_DP + rows * (SLOT_H_DP + MARGIN_DP))
	return out


func set_columns(n: int) -> void:
	n = clampi(n, MIN_COLUMNS, MAX_COLUMNS)
	if n == columns:
		return
	columns = n
	if world != null and world.sim != null:
		_rebuild()


func rescale() -> void:
	_slot_size = Vector2(Dp.px(SLOT_W_DP), Dp.px(SLOT_H_DP))
	if world != null and world.sim != null:
		_rebuild()
	queue_redraw()


class BuildSlot extends Control:
	var type_id := -1
	var icon: ImageTexture
	var progress := 0.0
	var count := 0
	var done := false
	var affordable := true
	var available := true
	var limited := false
	var paused := false
	var cost := 0
	var seconds := 0
	var name_text := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		HudTheme.draw_panel(self, r, HudTheme.PANEL_BG_SOLID, HudTheme.GOLD if done else HudTheme.BORDER_DIM, 5.0)
		if icon != null:
			draw_texture_rect(icon, r.grow(-Dp.px(4)), false, Color.WHITE if available else Color(0.72, 0.72, 0.72))
		if not available:


			draw_rect(r.grow(-Dp.px(3)), Color(0, 0, 0, 0.34), true)

		if count > 0 and not done:
			var covered := r.size.y * (1.0 - progress)
			draw_rect(Rect2(r.position, Vector2(r.size.x, covered)), Color(0, 0, 0, 0.6), true)
		var font := ThemeDB.fallback_font
		var fs := int(Dp.px(10))
		if done:
			draw_rect(r, Color(0.2, 0.9, 0.3, 0.25), true)
			_text(font, Vector2(Dp.px(4), fs + 2), tr("buildbar.ready"), fs, Color.WHITE)
		elif paused:
			_strip(font, r, tr("buildbar.hold_count") % count, fs, HudTheme.GOLD)
		elif count > 0:
			_text(font, Vector2(Dp.px(4), fs + 2), "×%d" % count, fs, Color.WHITE)

			if seconds > 0:
				_strip(font, r, "%d:%02d" % [seconds / 60, seconds % 60], fs, Color.WHITE)
		elif not available:


			_lock(r, fs, Color(0.92, 0.88, 0.76, 0.85))

		var cost_text := "$%d" % cost
		var cfs := int(Dp.px(11))
		var tw := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var at := Vector2(r.size.x - tw - Dp.px(6), Dp.px(4) + cfs)
		draw_rect(Rect2(at - Vector2(Dp.px(3), cfs), Vector2(tw + Dp.px(6), cfs + Dp.px(3))), Color(0, 0, 0, 0.6), true)
		draw_string(font, at + Vector2(1, 1), cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color.BLACK)
		var cost_col := HudTheme.GOLD if affordable else Color(1, 0.4, 0.4)
		draw_string(font, at, cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs,
			cost_col if available else cost_col.darkened(0.4))

	func _text(font: Font, at: Vector2, s: String, fs: int, col: Color) -> void:
		draw_string(font, at + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
		draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


	func _strip(font: Font, r: Rect2, s: String, fs: int, col: Color) -> void:
		var h := fs + Dp.px(5)
		var bar := Rect2(r.position.x + Dp.px(3), r.end.y - h - Dp.px(3), r.size.x - Dp.px(6), h)
		draw_rect(bar, Color(0, 0, 0, 0.92), true)
		draw_string(font, Vector2(bar.position.x + Dp.px(4), bar.get_center().y + fs * 0.38), s,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


	func _lock(r: Rect2, fs: int, col: Color) -> void:
		var c := Vector2(r.position.x + Dp.px(9), r.position.y + Dp.px(9))
		var w := maxf(1.0, Dp.px(1.2))
		draw_arc(c + Vector2(0, -fs * 0.20), fs * 0.24, PI, TAU, 10, col, w)
		draw_rect(Rect2(c + Vector2(-fs * 0.32, -fs * 0.10), Vector2(fs * 0.64, fs * 0.48)), col, true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


	visibility_changed.connect(func(): if is_visible_in_tree(): _auto_ready = -1)
	_slot_size = Vector2(Dp.px(SLOT_W_DP), Dp.px(SLOT_H_DP))
	for k in KIND_KEYS.size():
		var b := Button.new()


		b.text = ""
		b.tooltip_text = tr(KIND_KEYS[k])
		b.toggle_mode = true
		b.icon = load(TAB_ICON_PATHS[k])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		HudTheme.style_icon_button(b)
		HudTheme.wire_help(b, TAB_HELP_KEYS[k], self, func(): _select_kind(k))
		add_child(b)
		_tabs.append(b)
		_tab_glow.append(HudTheme.attach_ready_glow(b))
	_area = Control.new()
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_area)
	_select_kind(0)


func _select_kind(k: int) -> void:
	kind = KIND_QUEUES[k]
	_auto_ready = -1
	for i in _tabs.size():
		_tabs[i].button_pressed = i == k
	_scroll = 0.0
	_close_popup()
	_refresh = 1.0


func _update_tabs() -> void:
	var avail: Array[int] = world.available_queues()
	var fallback := -1
	for i in _tabs.size():
		var ok: bool = avail.has(KIND_QUEUES[i])
		_tabs[i].visible = ok
		if ok and fallback < 0:
			fallback = i
	if not avail.has(kind) and fallback >= 0:
		_select_kind(fallback)


func select_queue(q: int) -> void:
	var k := KIND_QUEUES.find(q)
	if k >= 0:
		_select_kind(k)


func select_tab(i: int) -> bool:
	if i < 0 or i >= _tabs.size() or not _tabs[i].visible:
		return false
	_select_kind(i)
	return true


func slot_rect_for(type_name: String) -> Rect2:
	if not visible or not world.type_ids.has(type_name):
		return Rect2()
	var tid: int = world.type_ids[type_name]
	for s in _slots:
		var slot: BuildSlot = s
		if slot.type_id == tid and slot.visible:
			return slot.get_global_rect()
	return Rect2()


func _draw() -> void:
	HudTheme.draw_panel(self, Rect2(Vector2.ZERO, size), HudTheme.PANEL_BG, HudTheme.BORDER_DIM, 8.0)

	if _area == null or _content_h <= _area.size.y + 1.0:
		return
	var track := Rect2(size.x - Dp.px(5), _area.position.y, Dp.px(3), _area.size.y)
	draw_rect(track, Color(0, 0, 0, 0.5), true)
	var frac := _area.size.y / _content_h
	var h := maxf(track.size.y * frac, Dp.px(16))
	var y := track.position.y + (track.size.y - h) * (_scroll / maxf(_content_h - _area.size.y, 1.0))
	draw_rect(Rect2(Vector2(track.position.x, y), Vector2(track.size.x, h)), HudTheme.BORDER, true)


var _press_slot := -1
var _press_pos := Vector2.ZERO
var _press_time := 0
var _moved := false
var _scroll_start := 0.0


func _slot_index_at(p: Vector2) -> int:
	if _area == null or not Rect2(_area.position, _area.size).has_point(p):
		return -1
	var local := p - _area.position
	for i in _slots.size():
		var s: BuildSlot = _slots[i]
		if s.visible and Rect2(s.position, s.size).has_point(local):
			return i
	return -1


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
	elif e is InputEventPanGesture:


		_set_scroll(_scroll + e.delta.y * Desktop.Scroller.PAN_SPEED)
		accept_event()
		return
	elif e is InputEventMouseButton:


		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:


			var step := Dp.px(SLOT_H_DP + MARGIN_DP)
			_set_scroll(_scroll + (step if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -step))
			accept_event()
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			accept_event()
			var idx := _slot_index_at(e.position)
			if idx >= 0 and idx < _slots.size():
				_on_right_click(_slots[idx])
		return
	else:
		return
	accept_event()
	if pressed:
		_press_slot = _slot_index_at(pos)
		_press_pos = pos
		_press_time = Time.get_ticks_msec()
		_moved = false
		_scroll_start = _scroll
		_close_popup()
	elif drag and _press_time != 0:
		if absf(pos.y - _press_pos.y) > Dp.px(8):
			_moved = true
		if _moved:
			_set_scroll(_scroll_start - (pos.y - _press_pos.y))
	elif released and _press_time != 0:
		var slot := _press_slot
		var held := Time.get_ticks_msec() - _press_time >= LONG_PRESS_MS
		_press_time = 0
		_press_slot = -1
		if _moved or slot < 0 or slot >= _slots.size():
			return
		var s: BuildSlot = _slots[slot]
		if held:
			_on_hold(s)
		else:
			_on_tap(s)


func scroll_value() -> float:
	return _scroll


func scroll_room() -> float:
	return maxf(_content_h - (_area.size.y if _area != null else 0.0), 0.0)


func slot_count(type_name: String) -> int:
	if not world.type_ids.has(type_name):
		return 0
	var tid: int = world.type_ids[type_name]
	for s in _slots:
		var slot: BuildSlot = s
		if slot.type_id == tid and slot.visible:
			return slot.count
	return 0


func slot_paused(type_name: String) -> bool:
	if not world.type_ids.has(type_name):
		return false
	var tid: int = world.type_ids[type_name]
	for s in _slots:
		var slot: BuildSlot = s
		if slot.type_id == tid and slot.visible:
			return slot.paused
	return false


func _set_scroll(v: float) -> void:
	_scroll = clampf(v, 0.0, maxf(_content_h - _area.size.y, 0.0))
	_refresh = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh < 0.15 or world == null or world.sim == null:
		return
	_refresh = 0.0
	_rebuild()


func _all_types(k: int) -> Array:
	if _lists.has(k):
		return _lists[k]
	var out: Array = []
	for name in world.types:
		var t: Dictionary = world.types[name]
		if int(t.get("queue", -1)) != k or not world.type_ids.has(name):
			continue
		if HIDDEN_TYPES.has(name):
			continue
		var ok := true
		for p in t.get("prerequisites", []):
			if not _token_possible(str(p)):
				ok = false
		if not ok:
			continue
		out.append([int(t.get("palette_order", 0)), world.type_ids[name], name])
	out.sort_custom(func(a, b): return a[0] < b[0])
	var ids: Array = []
	for e in out:
		ids.append(e[1])
	_lists[k] = ids
	return ids


func _token_possible(token: String) -> bool:
	if token == "" or token.begins_with("techlevel."):
		return true
	if token.begins_with("!"):
		return false
	for name in world.types:
		if (world.types[name].get("provides", []) as Array).has(token):
			return true
	return false


func _token_own_faction(token: String, faction: String) -> bool:
	if token == "" or token.begins_with("techlevel."):
		return true
	if token.begins_with("!"):
		return false
	for name in world.types:
		var t: Dictionary = world.types[name]
		var provides: Array = t.get("provides", [])
		var factions: Array = t.get("provides_factions", [])
		for i in provides.size():
			if provides[i] != token:
				continue
			var f: String = str(factions[i]) if i < factions.size() else ""
			if f == "" or ("," + f + ",").contains("," + faction + ","):
				return true
	return false


func _no_landing_pad(type_id: int) -> bool:
	if not world.sim.has_method("free_landing_pads"):
		return false
	var name: String = world.type_names[type_id]
	if not world.types[name].get("aircraft", false):
		return false
	return int(world.sim.free_landing_pads(world.local_player, type_id)) <= 0


func _missing_text(type_id: int) -> String:
	var name: String = world.type_names[type_id]
	var t: Dictionary = world.types[name]
	var faction := world.player_faction()
	for p in t.get("prerequisites", []):
		var token := str(p)
		if token.begins_with("techlevel.") or token == "":
			continue
		if world.sim.has_prerequisite(world.local_player, token):
			continue
		return _provider_name(token, faction)
	return ""


func _provider_name(token: String, faction: String) -> String:
	var fallback := ""
	for name in world.types:
		var t: Dictionary = world.types[name]
		var provides: Array = t.get("provides", [])
		var factions: Array = t.get("provides_factions", [])
		for i in provides.size():
			if provides[i] != token:
				continue
			var f: String = str(factions[i]) if i < factions.size() else ""
			if f != "" and not ("," + f + ",").contains("," + faction + ","):
				continue

			var own := true
			for p2 in t.get("prerequisites", []):
				if not _token_own_faction(str(p2), faction):
					own = false
			if own:
				return Names.of(t)
			if fallback == "":
				fallback = Names.of(t)
	return fallback if fallback != "" else token


func _producer_label() -> String:
	var faction := world.player_faction()
	var fallback := tr("buildbar.production_building")
	for name in world.types:
		var t: Dictionary = world.types[name]
		if not t.get("produces", []).has(kind):
			continue
		var own := true
		for p in t.get("prerequisites", []):
			if not _token_own_faction(str(p), faction):
				own = false
		if own:
			return Names.of(t)
		if fallback == tr("buildbar.production_building"):
			fallback = Names.of(t)
	return fallback


func _rebuild() -> void:
	var sim = world.sim
	_update_tabs()
	var list: Array = _all_types(kind)


	if sim.has_method("hidden_items"):
		var hidden := {}
		for t in sim.hidden_items(world.local_player, kind):
			hidden[t] = true
		if not hidden.is_empty():
			var shown: Array = []
			for t in list:
				if not hidden.has(t):
					shown.append(t)
			list = shown
	_shown[kind] = list.size()
	var ready := {}
	for t in sim.buildable(world.local_player, kind):
		ready[t] = true
	var queue: PackedInt32Array = sim.queue_state(world.local_player, kind)
	var counts := {}
	var progress := {}
	var done := {}
	var seconds := {}
	var tps: int = sim.ticks_per_second()


	for i in queue.size() / 7:
		var t := queue[i * 7]
		counts[t] = counts.get(t, 0) + 1
		if i == 0:
			progress[t] = queue[i * 7 + 1] / 1000.0
			done[t] = queue[i * 7 + 2] == 1


			seconds[t] = int(ceil(queue[i * 7 + 6] / maxf(tps, 1)))
	_paused = queue.size() >= 7 and queue[4] == 1


	var ready_type := -1
	if queue.size() >= 7 and queue[2] == 1 and (kind == 0 or kind == 3):
		ready_type = queue[0]


	var declined: int = _declined.get(kind, -1)
	if declined >= 0 and declined != ready_type:
		_declined.erase(kind)
		declined = -1
	if ready_type != _auto_ready:
		_auto_ready = ready_type
		if ready_type >= 0 and is_visible_in_tree() and world.placing_type < 0 and ready_type != declined:
			place_requested.emit(ready_type)
	_first_index = list.find(queue[0]) if queue.size() >= 7 else -1

	while _slots.size() < list.size():
		var s := BuildSlot.new()
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_area.add_child(s)
		_slots.append(s)
	var margin := Dp.px(MARGIN_DP)
	var tab_h := Dp.px(TAB_H_DP)
	var visible_tabs: Array[int] = []
	for i in _tabs.size():
		if _tabs[i].visible:
			visible_tabs.append(i)


	var natural_tab_w := (size.x - margin * (visible_tabs.size() + 1)) / maxf(visible_tabs.size(), 1)
	var tab_w := minf(Dp.px(TAB_W_DP), natural_tab_w)
	for vi in visible_tabs.size():
		var i: int = visible_tabs[vi]


		HudTheme.place_touch(_tabs[i], Vector2(margin + vi * (tab_w + margin), margin),
			Vector2(tab_w, tab_h), Vector2(margin / 2.0, margin * 0.75))
	_area.position = Vector2(0, tab_h + margin * 2)
	_area.size = Vector2(size.x, size.y - _area.position.y - margin / 2.0)
	var rows := int(ceil(list.size() / float(columns)))
	_content_h = rows * (_slot_size.y + margin)
	_scroll = clampf(_scroll, 0.0, maxf(_content_h - _area.size.y, 0.0))
	var credits: int = sim.credits(world.local_player)
	var producer_missing := ready.is_empty()
	for i in _slots.size():
		var s: BuildSlot = _slots[i]
		if i >= list.size():
			s.visible = false
			continue
		var t: int = list[i]
		s.visible = true
		s.type_id = t
		s.cost = sim.type_cost(t)
		s.count = counts.get(t, 0)
		s.progress = progress.get(t, 0.0)
		s.done = done.get(t, false)
		s.seconds = seconds.get(t, 0)
		s.affordable = credits >= s.cost
		s.available = ready.has(t)
		s.limited = sim.has_method("build_limit_reached") and sim.build_limit_reached(world.local_player, t)
		s.paused = _paused and i == _first_index
		if not _icons.has(t):
			var name: String = world.type_names[t]
			var icon_name: String = world.types[name].get("icon", name + "icon")
			_icons[t] = world.atlas().make_rgba_texture(icon_name, 0) if world.atlas().sprite_frame_count.has(icon_name) else null
		s.icon = _icons[t]
		s.size = _slot_size
		s.position = Vector2(margin + (i % columns) * (_slot_size.x + margin),
				(i / columns) * (_slot_size.y + margin) - _scroll)
		s.queue_redraw()
	_producer_missing = producer_missing
	_update_ready_glow(sim)

	var want := wanted_size(minf(get_viewport_rect().size.x, get_viewport_rect().size.y))
	if absf(want.y - size.y) > 1.0:
		height_changed.emit()
	queue_redraw()


func _update_ready_glow(sim) -> void:
	var any := false
	for i in _tabs.size():
		var q: PackedInt32Array = sim.queue_state(world.local_player, KIND_QUEUES[i])
		var rdy: bool = q.size() >= 7 and q[2] == 1 and q[0] != world.placing_type
		if i < _tab_glow.size():
			_tab_glow[i].on = rdy
		any = any or rdy
	if any != _any_ready:
		_any_ready = any
		ready_changed.emit(any)


func any_ready() -> bool:
	return _any_ready


func ready_building() -> int:
	if world == null or world.sim == null:
		return -1
	for k in [kind, 0, 3]:
		if k != 0 and k != 3:
			continue
		var q: PackedInt32Array = world.sim.queue_state(world.local_player, k)
		if q.size() >= 7 and q[2] == 1:
			return q[0]
	return -1


var _producer_missing := false
var _paused := false
var _first_index := -1
var _auto_ready := -1
var _declined: Dictionary = {}


func decline_ready(type_id: int) -> void:
	if type_id < 0 or world == null or world.sim == null:
		return
	for k in [0, 3]:
		var q: PackedInt32Array = world.sim.queue_state(world.local_player, k)
		if q.size() >= 7 and q[0] == type_id and q[2] == 1:
			_declined[k] = type_id


func mark_ready_offered() -> void:
	_auto_ready = -1
	if world == null or world.sim == null or not (kind == 0 or kind == 3):
		return
	var q: PackedInt32Array = world.sim.queue_state(world.local_player, kind)
	if q.size() >= 7 and q[2] == 1:
		_auto_ready = q[0]


func _on_tap(s: BuildSlot) -> void:
	if s.type_id < 0:
		return


	if s.paused:
		world.sfx.play_ui("ramenu1")
		world.issue(NetOrders.make(NetOrders.OP_PAUSE_BUILD, kind, 0))
		_refresh = 1.0
		return
	if not s.available:

		var missing := _missing_text(s.type_id)
		var label: String = Names.of(world.types[world.type_names[s.type_id]])
		if s.limited:
			var lim: int = world.sim.build_limit(s.type_id) if world.sim.has_method("build_limit") else 0
			blocked.emit(tr("buildbar.limit_reached") % [label, (" (%d)" % lim) if lim > 0 else ""])
		elif _no_landing_pad(s.type_id):


			blocked.emit(tr("buildbar.no_landing_pad") % label)
		elif missing != "":
			blocked.emit(tr("buildbar.requires") % [label, missing])
		elif _producer_missing:
			blocked.emit(tr("buildbar.missing_producer") % [label, _producer_label()])
		else:
			blocked.emit(tr("buildbar.not_buildable_now") % label)
		return
	var sim = world.sim
	world.sfx.play_ui("ramenu1")
	var queue: PackedInt32Array = sim.queue_state(world.local_player, kind)
	if (kind == 0 or kind == 3) and queue.size() >= 7 and queue[0] == s.type_id and queue[2] == 1:
		_declined.erase(kind)
		place_requested.emit(s.type_id)
	else:
		build_requested.emit(s.type_id)
	_refresh = 1.0


func _on_right_click(s: BuildSlot) -> void:
	if s.type_id < 0 or world == null or world.sim == null or s.count <= 0:
		return
	world.sfx.play_ui("ramenu1")
	var started: bool = s.progress > 0.0 and not s.done
	if started and not s.paused and world.sim.has_method("pause_build"):
		world.issue(NetOrders.make(NetOrders.OP_PAUSE_BUILD, kind, 1))

		world.eva("onhold1")
	else:
		cancel_requested.emit(kind, s.type_id)
	_close_popup()
	_refresh = 1.0


func _on_hold(s: BuildSlot) -> void:
	if s.type_id < 0:
		return
	_close_popup()
	move_to_front()
	var type_id := s.type_id
	var count := s.count
	var type_name: String = world.type_names[type_id]
	var t: Dictionary = world.types[type_name]


	_popup_backdrop = HudTheme.dim_backdrop(get_parent())
	_popup_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and e.pressed:
			if _popup_backdrop != null:
				_popup_backdrop.accept_event()
			_close_popup())
	_cancel_popup = PanelContainer.new()
	_cancel_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_cancel_popup.add_theme_stylebox_override("panel", HudTheme.panel(HudTheme.PANEL_BG_SOLID, HudTheme.BORDER, 6.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(4)))
	box.custom_minimum_size = Vector2(Dp.px(INFO_WIDTH_DP), 0)
	var title := Label.new()
	title.text = "%s ×%d" % [Names.of(t), count] if count > 0 else Names.of(t)
	HudTheme.log_overlay("BAULEISTEN-MENÜ", title.text)
	title.custom_minimum_size = Vector2(Dp.px(INFO_WIDTH_DP), 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", int(Dp.px(13)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	var desc := ActorInfo.description(type_name)
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.custom_minimum_size = Vector2(Dp.px(INFO_WIDTH_DP), 0)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_font_size_override("font_size", int(Dp.px(11)))
		dl.add_theme_color_override("font_color", HudTheme.TEXT)
		box.add_child(dl)
	_add_info_lines(box, type_id, t)
	_add_stat_lines(box, t)


	var qs: PackedInt32Array = world.sim.queue_state(world.local_player, kind)
	if (kind == 0 or kind == 3) and qs.size() >= 7 and qs[0] == type_id and qs[2] == 1:
		_info_line(box, tr("buildbar.ready_hint"), HudTheme.GOLD)
	if count <= 0:
		if s.available:
			blocked.emit(tr("buildbar.queue_empty"))
		_finish_hold_popup(box)
		return


	if world.sim.has_method("pause_build"):
		var hold := Button.new()
		hold.text = tr("buildbar.resume") if _paused else tr("buildbar.hold")
		hold.custom_minimum_size = Vector2(Dp.px(150), Dp.px(38))
		HudTheme.style_button(hold, 13.0)
		hold.pressed.connect(func():
			world.issue(NetOrders.make(NetOrders.OP_PAUSE_BUILD, kind, 1 if not _paused else 0))


			world.eva("onhold1")
			_close_popup()
			_refresh = 1.0)
		box.add_child(hold)
	for entry in [[tr("buildbar.cancel_one"), 1], [tr("buildbar.cancel_all"), count]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(Dp.px(150), Dp.px(38))
		HudTheme.style_button(b, 13.0)
		var n: int = entry[1]
		b.pressed.connect(func():
			for _i in n:
				cancel_requested.emit(kind, type_id)
			_close_popup()
			_refresh = 1.0)
		box.add_child(b)
	_finish_hold_popup(box)


func _add_info_lines(box: VBoxContainer, type_id: int, t: Dictionary) -> void:
	var sim = world.sim
	var tps: int = maxi(1, sim.ticks_per_second())
	var time_ticks: int = 0
	var queue: PackedInt32Array = sim.queue_state(world.local_player, kind)
	if queue.size() >= 7 and queue[0] == type_id:
		time_ticks = queue[5]
	elif sim.has_method("build_time"):
		time_ticks = sim.build_time(type_id)
	var secs := int(ceil(time_ticks / float(tps)))
	_info_line(box, tr("buildbar.info.price") % sim.type_cost(type_id), HudTheme.TEXT)
	_info_line(box, tr("buildbar.info.time") % [secs / 60, secs % 60], HudTheme.TEXT)
	var power := int(t.get("power", 0))
	if power > 0:
		_info_line(box, tr("buildbar.info.power_gen") % power, Color(0.3, 0.9, 0.3))
	elif power < 0:
		_info_line(box, tr("buildbar.info.power_use") % -power, Color(0.95, 0.25, 0.2))


func _info_line(box: VBoxContainer, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(Dp.px(INFO_WIDTH_DP), 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(Dp.px(11)))
	l.add_theme_color_override("font_color", col)
	box.add_child(l)


func _add_stat_lines(box: VBoxContainer, t: Dictionary) -> void:
	var armor_idx := int(t.get("armor", 0))
	if armor_idx >= 0 and armor_idx < ARMOR_TR_KEYS.size():
		_info_line(box, tr("info.armor") % tr(ARMOR_TR_KEYS[armor_idx]), HudTheme.TEXT)
	var speed := int(t.get("speed", 0))
	if speed > 0:
		var tps: int = maxi(1, world.sim.ticks_per_second())
		_info_line(box, tr("info.speed") % ("%.1f" % (speed / 1024.0 * tps)), HudTheme.TEXT)
	var wname: String = str(t.get("weapon", ""))
	if wname != "" and world.rules.weapons.has(wname):
		var w: Dictionary = world.rules.weapons[wname]
		var rng := float(w.get("range", 0)) / 1024.0
		_info_line(box, tr("info.weapon_range") % [Names.of_key(wname, wname), "%.1f" % rng], HudTheme.TEXT)
	elif wname == "" and not t.get("building", false):
		_info_line(box, tr("info.unarmed"), HudTheme.TEXT_DIM)
	var prereq_names: Array = []
	var hidden_prereqs: Array = t.get("prerequisites_hidden", [])
	for p in t.get("prerequisites", []):
		var pn := str(p)


		if pn.begins_with("~") or pn == "" or hidden_prereqs.has(pn):
			continue
		prereq_names.append(Names.of_key(pn, pn))
	if not prereq_names.is_empty():
		_info_line(box, tr("info.prereq") % ", ".join(prereq_names), HudTheme.TEXT)


func _finish_hold_popup(box: VBoxContainer) -> void:
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(150), Dp.px(34))
	HudTheme.style_button(close, 13.0)
	close.pressed.connect(_close_popup)
	box.add_child(close)
	var safe := Dp.safe_rect()

	var max_h := maxf(Dp.px(160), global_position.y - safe.position.y - Dp.px(8))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(Dp.px(INFO_WIDTH_DP), 0)
	scroll.add_child(box)
	_cancel_popup.add_child(scroll)
	get_parent().add_child(_cancel_popup)


	var content_h: float = box.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(content_h, max_h)
	_cancel_popup.reset_size()
	var pos := global_position + Vector2(size.x - _cancel_popup.size.x - Dp.px(MARGIN_DP), -_cancel_popup.size.y - Dp.px(4))
	pos.x = clampf(pos.x, safe.position.x, safe.position.x + safe.size.x - _cancel_popup.size.x)
	pos.y = clampf(pos.y, safe.position.y, safe.position.y + safe.size.y - _cancel_popup.size.y)
	_cancel_popup.global_position = pos


func _close_popup() -> void:
	if _cancel_popup != null:
		_cancel_popup.queue_free()
		_cancel_popup = null
	if _popup_backdrop != null:
		_popup_backdrop.queue_free()
		_popup_backdrop = null
