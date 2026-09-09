

extends Node

@onready var world: ProtoWorld = $World
@onready var gestures: GestureRecognizer = $Gestures
@onready var radial: RadialMenu = $UI/RadialMenu
@onready var minimap: Minimap = $UI/Minimap
@onready var debug_label: Label = $UI/Debug
@onready var build_bar: BuildBar = $UI/BuildBar
@onready var build_toggle: Button = $UI/BuildToggle
@onready var music_toggle: Button = $UI/MusicToggle
@onready var place_confirm: Button = $UI/PlaceConfirm
@onready var place_cancel: Button = $UI/PlaceCancel
@onready var status_bar: StatusBar = $UI/Status
@onready var groups: ControlGroups = $UI/Groups

const PLACE_OFFSET_CELLS := 0.0

const HIT_RADIUS_DP := 32.0


const MUSIC_ICON := "res://icons/ui/btn_musik_1.png"
const MENU_ICON := "res://icons/ui/btn_menu_2.png"
const BUILD_TOGGLE_ICON := "res://icons/ui/btn_bauen_3.png"


const TOP_ICON_BTN_DP := 56.0


const HUD_LEFT_DP := 132.0
const HUD_TOP_DP := 70.0


var _map_rect := Rect2()


const NOTIFY_KEYS := ["notify.building", "notify.building_in_progress", "notify.construction_complete",
	"notify.unit_ready", "notify.insufficient_funds", "notify.no_build", "notify.cancelled",
	"notify.new_options", "notify.low_power", "notify.structure_sold", "notify.repairing",
	"notify.primary_selected", "notify.unit_repaired", "notify.win", "notify.lose",
	"notify.silos_needed", "notify.cannot_place"]

var _last_gesture := "—"
var _screenshot_path := ""
var _test_sell := false
var _test_ai := false
var _test_buildings := false
var _test_tesla := false
var _test_nuke := false
var _test_nuke_target := Vector2i.ZERO
var _test_nuke_wait_until := 0
var _test_spy := false
var _test_ui := false
var _test_mission := false
var _test_force := false
var _test_step := 0
var _diag := false
var _test_placement := false
var _demo_battle := false
var _demo_shots := 0
var _demo_next_tick := 0

var _test_ready := ""
var _test_lobby_tap := false
var _placement_shots: Dictionary = {}
var _confirm_mode := ""


var _order_mode := ""
var _sp_panel: SupportPowersPanel
var _sp_source := Vector2.ZERO

var _click_mode := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--screenshot")
	if k >= 0 and k + 1 < args.size():
		_screenshot_path = args[k + 1]
	_test_sell = args.has("--test-sell")
	_test_defense = args.has("--test-defense")
	_test_buildings = args.has("--test-buildings")
	_test_tesla = args.has("--test-tesla")
	_test_nuke = args.has("--test-nuke")
	_test_spy = args.has("--test-spy")
	_test_ai = args.has("--test-ai")
	_test_ui = args.has("--test-ui")
	_test_briefing = args.has("--test-briefing")
	_test_mission = args.has("--test-mission")
	_test_force = args.has("--test-force")
	_diag = args.has("--diag")
	_test_cycle = args.has("--test-cycle")
	if args.has("--test-layout"):
		call_deferred("_run_test_layout")
	_test_speed = args.has("--test-speed")
	var tsk := args.find("--test-speed-switch")
	if tsk >= 0 and tsk + 1 < args.size():
		_test_speed_switch = int(args[tsk + 1])
	_test_speed_ui = args.has("--test-speed-ui")
	if _test_speed_ui:
		call_deferred("_run_test_speed_ui")
	_test_defeat = args.has("--test-defeat")
	_test_victory = args.has("--test-victory")
	_test_motion = args.has("--test-motion")
	_test_projectile = args.has("--test-projectile")
	_test_barrels = args.has("--test-barrels")
	_test_air = args.has("--test-air")
	_test_air_player = args.has("--test-air-player")
	_test_cargo = args.has("--test-cargo")
	_test_naval = args.has("--test-naval")
	_test_lst = args.has("--test-lst")
	_test_save = args.has("--test-save")
	_test_armaments = args.has("--test-armaments")
	_test_dog = args.has("--test-dog")
	_test_placement = args.has("--test-placement")
	_demo_battle = args.has("--demo-battle")
	if _demo_battle:
		_any_test = true
		_screenshot_tick = 1 << 30

	var trk := args.find("--test-ready")
	if trk >= 0:
		_test_ready = args[trk + 1] if (trk + 1 < args.size() and not args[trk + 1].begins_with("--")) else "zu"
		_test_ui = true
	_test_lobby_tap = args.has("--test-lobby")
	for a in args:
		if a.begins_with("--test") or a == "--screenshot" or a == "--autostart":
			_any_test = true
	var auk := args.find("--test-ai-until")
	if auk >= 0 and auk + 1 < args.size():
		_test_ai_until = int(args[auk + 1])
	var ssk := args.find("--screenshot-series")
	if ssk >= 0 and ssk + 1 < args.size():
		_screenshot_series = int(args[ssk + 1])
	var stk := args.find("--screenshot-at")
	if stk >= 0 and stk + 1 < args.size():
		_screenshot_tick = int(args[stk + 1])
	if world.atlas() == null:

		push_error("Karte konnte nicht geladen werden — zurück ins Hauptmenü")
		call_deferred("_leave_battlefield")
		return
	minimap.world = world


	minimap.add_to_group("layout_hud")
	build_bar.add_to_group("layout_hud")


	groups.add_to_group("layout_hud")
	status_bar.add_to_group("layout_hud")
	music_toggle.add_to_group("layout_hud")
	build_toggle.add_to_group("layout_hud")
	minimap.navigate.connect(world.center_on)
	minimap.focus_base.connect(_jump_to_base)

	gestures.tap.connect(_on_tap)
	gestures.double_tap.connect(_on_double_tap)
	gestures.drag_started.connect(_on_drag_started)
	gestures.drag_updated.connect(_on_drag_updated)
	gestures.drag_ended.connect(_on_drag_ended)
	gestures.drag_cancelled.connect(func(): world.cancel_box(); _boxing = false; _log("Rahmen abgebrochen (2. Finger)"))
	gestures.long_press.connect(_on_long_press)
	gestures.long_press_moved.connect(func(p): if radial.visible: radial.update(p))
	gestures.long_press_ended.connect(func(p): if radial.visible: radial.close(p))
	gestures.long_press_cancelled.connect(radial.cancel)
	gestures.pan.connect(func(d): world.pan_screen(d); _last_gesture = "Schwenken")
	gestures.pinch.connect(func(f, c): world.zoom_at(f, c); _last_gesture = "Zoom %.2f" % world.zoom)
	gestures.two_finger_ended.connect(world.end_camera_gesture)
	radial.chosen.connect(_on_radial)


	build_toggle.toggle_mode = true
	build_toggle.text = ""
	build_toggle.icon = load(BUILD_TOGGLE_ICON)
	build_toggle.expand_icon = true
	build_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_toggle.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	build_toggle.tooltip_text = tr("ui.build_toggle_tip")
	HudTheme.style_icon_button(build_toggle)
	HudTheme.wire_help(build_toggle, "help.btn.build_toggle", $UI, func(): build_bar.visible = not build_bar.visible)
	build_bar.visibility_changed.connect(func(): build_toggle.set_pressed_no_signal(build_bar.visible))
	build_toggle.set_pressed_no_signal(build_bar.visible)


	_build_ready_glow = HudTheme.attach_ready_glow(build_toggle)
	build_bar.ready_changed.connect(func(on: bool): _build_ready_glow.on = on)
	music_toggle.text = ""
	music_toggle.icon = load(MUSIC_ICON)
	music_toggle.expand_icon = true
	music_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_toggle.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	HudTheme.style_icon_button(music_toggle)
	_music_off_mark = _MuteStrike.new()
	_music_off_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music_off_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	music_toggle.add_child(_music_off_mark)
	HudTheme.plate_button_style(place_confirm)
	HudTheme.plate_button_style(place_cancel)
	build_bar.world = world
	build_bar.build_requested.connect(world.queue_build)
	build_bar.cancel_requested.connect(world.cancel_build)
	build_bar.place_requested.connect(_begin_placement)
	build_bar.blocked.connect(_toast)
	build_bar.height_changed.connect(_layout_ui)
	place_confirm.pressed.connect(_confirm_placement)
	place_cancel.pressed.connect(_cancel_placement)
	HudTheme.wire_help(music_toggle, "help.btn.music", $UI, _toggle_music)
	_update_music_icon()
	status_bar.world = world
	_sp_panel = SupportPowersPanel.new()
	_sp_panel.world = world
	_sp_panel.activate.connect(_on_support_power)
	$UI.add_child(_sp_panel)
	groups.world = world
	groups.group_selected.connect(func(i, n): _toast(tr("toast.group_selected") % [i + 1, n]))
	groups.group_assigned.connect(func(i, n): _toast(tr("toast.group_assigned") % [i + 1, n]))
	groups.group_focused.connect(func(i): world.center_on(world.selection_center()); _log("Kamera zu Gruppe %d" % (i + 1)))
	world.notify_event.connect(_on_notify)
	world.under_attack.connect(_on_under_attack)
	_restore_groups(world.loaded_view_state())
	_build_command_bar()
	_build_game_menu()
	_build_mission_ui()
	_layout_ui()
	get_viewport().size_changed.connect(func(): Dp.invalidate(); _layout_ui())
	debug_label.visible = _diag


	if ProtoWorld.next_mission == "":
		_toast(tr("toast.you_play") % tr("faction.soviet" if world.player_faction() == "soviet" else "faction.allies"))
	if not GestureHelp.seen() and _screenshot_path == "" and not _any_test:
		call_deferred("_show_gesture_help", true)


func _layout_ui() -> void:


	var safe := Dp.safe_rect()
	var off := safe.position
	var vs := safe.position + safe.size
	var m := Dp.px(12)
	minimap.position = Vector2(off.x + m, vs.y - minimap.size.y - m)


	var fit := _fit_bottom_bars(safe, m)
	build_bar.set_columns(fit["build_cols"])
	build_bar.size = build_bar.wanted_size(minf(safe.size.x, safe.size.y))
	build_bar.position = vs - build_bar.size - Vector2(m, m)
	place_confirm.size = Vector2(Dp.px(110), Dp.px(48))
	place_cancel.size = Vector2(Dp.px(110), Dp.px(48))
	place_confirm.position = Vector2(vs.x - place_confirm.size.x - m, vs.y - place_confirm.size.y - m)
	place_cancel.position = place_confirm.position - Vector2(place_cancel.size.x + m, 0)


	build_toggle.size = Vector2(Dp.px(TOP_ICON_BTN_DP), Dp.px(TOP_ICON_BTN_DP))
	build_toggle.position = Vector2(vs.x - build_toggle.size.x - m, build_bar.position.y - build_toggle.size.y - m / 2)
	music_toggle.size = Vector2(Dp.px(TOP_ICON_BTN_DP), Dp.px(TOP_ICON_BTN_DP))
	music_toggle.position = Vector2(vs.x - music_toggle.size.x - m, off.y + m)
	if _music_off_mark != null:
		_music_off_mark.queue_redraw()
	if _sp_panel != null:
		_sp_panel.size = Vector2(Dp.px(60), Dp.px(3 * 64))
		_sp_panel.position = Vector2(vs.x - _sp_panel.size.x - m, music_toggle.position.y + music_toggle.size.y + m)


	status_bar.size = Vector2(Dp.px(220), Dp.px(42))
	status_bar.position = Vector2(off.x + (safe.size.x - status_bar.size.x) / 2.0, off.y + m / 4)


	groups.position = Vector2(off.x + m, off.y + (safe.size.y - groups.size.y) / 2.0)
	_menu_button.size = Vector2(Dp.px(TOP_ICON_BTN_DP), Dp.px(TOP_ICON_BTN_DP))
	_menu_button.position = off + Vector2(m, m)
	_mission_label.position = Vector2(off.x + m + _menu_button.size.x + m, off.y + m)

	_mission_label.size = Vector2(maxf(Dp.px(160), status_bar.position.x - _mission_label.position.x - m), Dp.px(90))
	_message_label.size = Vector2(Dp.px(420), Dp.px(44))
	_message_label.position = Vector2(off.x + (safe.size.x - _message_label.size.x) / 2.0, vs.y - build_bar.size.y - Dp.px(58))
	_toast_label.size = Vector2(Dp.px(460), Dp.px(56))
	_toast_bottom = _message_label.position.y - Dp.px(4)
	_toast_label.position = Vector2(off.x + (safe.size.x - _toast_label.size.x) / 2.0, _toast_bottom - _toast_label.size.y)
	_info_label.size = Vector2(Dp.px(360), Dp.px(22))

	_info_label.position = Vector2(off.x + (safe.size.x - _info_label.size.x) / 2.0, vs.y - Dp.px(96) - _info_label.size.y)
	_layout_command_bar(vs, m, off, fit["cmd_cols"])
	_map_rect = hud_map_rect(safe, fit)
	_mode_frame.position = off
	_mode_frame.size = safe.size
	debug_label.position = Vector2(off.x + m, status_bar.position.y + status_bar.size.y + m)
	debug_label.modulate = Color(1, 1, 1, 0.75)
	debug_label.add_theme_font_size_override("font_size", int(Dp.px(12)))


func _log(s: String) -> void:
	_last_gesture = s
	print(s)


var _toast_label: Label
var _toasts: Array = []
var _toast_bottom := 0.0
var _last_event_pos := Vector2.ZERO
var _has_event := false


func _toast(text: String) -> void:
	_log(text)
	var now := Time.get_ticks_msec() / 1000.0
	_toasts.append([text, now + 3.0])
	while _toasts.size() > 3:
		_toasts.pop_front()
	_update_toasts()


func _update_toasts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _toasts.is_empty() and _toasts[0][1] < now:
		_toasts.pop_front()
	var lines: Array = []
	for t in _toasts:
		lines.append(t[0])
	var ttext := "\n".join(lines)
	if _toast_label.text != ttext:
		_toast_label.text = ttext


	var h := maxf(lines.size(), 1) * Dp.px(17)
	_toast_label.size.y = h
	_toast_label.position.y = _toast_bottom - h


	var clickable := _has_event and not lines.is_empty() and now - _event_time < 20.0
	_toast_label.mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	if clickable:

		var fw := 0.0
		for l in lines:
			fw = maxf(fw, ThemeDB.fallback_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, int(Dp.px(13)))).x)
		var vs := get_viewport().get_visible_rect().size
		_toast_label.size.x = minf(fw + Dp.px(20), Dp.px(460))
		_toast_label.position.x = (vs.x - _toast_label.size.x) / 2.0


func _on_notify(kind: int) -> void:
	if kind >= 0 and kind < NOTIFY_KEYS.size():
		_toast(tr(NOTIFY_KEYS[kind]))


var _event_time := -100.0


func _on_under_attack(pos: Vector2) -> void:
	_event_time = Time.get_ticks_msec() / 1000.0
	if _test_ai and not _ai_attacked:
		_ai_attacked = true
		print("T%d Angriff: Basis unter Beschuss" % world.sim.tick())
	_last_event_pos = pos
	_has_event = true
	minimap.add_ping(pos)


func _begin_placement(type_id: int) -> void:


	_order_mode = ""
	_end_click_mode()
	world.begin_placement(type_id)
	build_bar.visible = false
	_show_confirm("place", tr("ui.build_confirm"))
	_toast(tr("toast.placing") % _type_label(world.type_names[type_id]))


func _show_confirm(mode: String, label: String) -> void:
	_confirm_mode = mode
	place_confirm.text = label
	place_confirm.visible = mode != "order"
	place_cancel.visible = true


func _confirm_placement() -> void:
	if _confirm_mode == "sell":

		_end_placement(tr("toast.sold") if world.sell_selected() else tr("toast.sell_impossible"))
		return
	if world.confirm_placement():
		_end_placement(tr("toast.built"))
	else:
		_toast(tr("toast.cannot_build_here"))


func _cancel_placement() -> void:
	if _confirm_mode == "place":
		world.cancel_placement()
	if _confirm_mode == "order":
		_order_mode = ""
		_end_placement(tr("toast.order_cancelled"))
		return
	_end_placement(tr("toast.cancelled"))


func _end_placement(msg: String) -> void:
	_confirm_mode = ""
	_order_mode = ""
	place_confirm.visible = false
	place_cancel.visible = false
	build_bar.visible = true
	_toast(msg)


func _begin_order(mode: String, label: String) -> void:
	_order_mode = mode
	_show_confirm("order", "")
	place_cancel.text = tr("ui.cancel")
	_toast(tr("toast.select_target") % label)


func _finish_order(wp: Vector2) -> void:
	var mode := _order_mode
	_order_mode = ""
	place_cancel.visible = false
	place_confirm.visible = false
	place_cancel.text = tr("ui.cancel")
	_confirm_mode = ""
	match mode:
		"move":
			world.order_move(wp)
			_toast(tr("toast.move_count") % world.selection.size())
		"attack_move":
			world.order_attack_move(wp)
			_toast(tr("toast.attack_move_count") % world.selection.size())
		"harvest":
			if world.order_harvest(wp):
				_toast(tr("radial.action.harvest"))
			else:
				_toast(tr("toast.no_harvester"))
		"force_fire":

			_toast(tr("radial.action.force_fire") if world.order_attack_cell(wp) else tr("toast.force_fire_impossible"))
		"sp0", "sp2":
			var kind := 0 if mode == "sp0" else 2
			_toast(tr("toast.sp_fired") % tr(SupportPowersPanel.LABELS[kind]) if world.activate_support_power(kind, wp) else tr("toast.sp_failed"))
		"sp1a":
			_sp_source = wp
			_begin_order("sp1b", tr("sp.chronoshift"))
			_toast(tr("toast.sp_chrono_dest"))
		"sp1b":
			_toast(tr("toast.sp_fired") % tr("sp.chronoshift") if world.activate_support_power(1, _sp_source, wp) else tr("toast.sp_failed"))
		"guard":
			var target := world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
			if target != null and world.order_guard(target):
				_toast(tr("toast.guarding") % _type_label(target.type))
			else:
				_toast(tr("toast.no_guard_target"))


func _on_support_power(kind: int, ready: bool, paused: bool) -> void:
	var label := tr(SupportPowersPanel.LABELS[kind])


	if kind == SupportPowersPanel.KIND_GPS:
		_toast(tr("toast.sp_gps_auto") % label)
		return
	if not ready:
		if paused:
			world.eva("nopowr1")
			_toast(tr("toast.sp_no_power") % label)
		else:
			_toast(tr("toast.sp_not_ready") % label)
		return
	world.eva("slcttgt1")
	_begin_order("sp1a" if kind == 1 else "sp%d" % kind, label)


func _type_label(type_name: String) -> String:
	var t: Dictionary = world.types.get(type_name, {})
	return Names.of(t)


func _on_tap(p: Vector2) -> void:
	var wp := world.screen_to_world(p)
	if world.placing_type >= 0:

		if world.tap_placement(wp):
			_end_placement(tr("toast.built"))
		else:
			_toast(tr("toast.tap_again_to_build") if world.placement_ok() else tr("toast.cannot_build_here"))
		return
	if _confirm_mode == "sell":
		_end_placement(tr("toast.sale_cancelled"))
	var hit := world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
	if _order_mode != "":
		_finish_order(wp)
		return
	if _click_mode != "":
		if _apply_click_mode(hit):
			return


		_end_click_mode()


	if hit != null and hit.player == 0 and not world.selection.is_empty() and world.selected_building() == null \
			and world.order_land_at(hit):
		_toast(tr("toast.landing") % _type_label(hit.type))
		return
	if hit != null and hit.player == 0 and not world.selection.is_empty() and world.selected_building() == null \
			and world.types[hit.type].get("repairs_units", false) and world.order_repair(hit):
		_toast(tr("toast.repair_at_depot"))
		return

	if hit != null and hit.player == 0 and not world.selection.is_empty() and world.selected_building() == null \
			and world.order_deliver(hit):
		_toast(tr("toast.deliver_ore") % _type_label(hit.type))
		return


	if hit != null and not world.selection.is_empty() and world.selected_building() == null:
		var ek := world.enter_kind(hit)
		if ek != 0:
			var what := world.order_enter(hit)
			if what != "":
				_toast(tr(what) % _type_label(hit.type))
				return

	if hit != null and hit.player != 0 and not world.selection.is_empty() and world.has_disguiser() \
			and not world.types[hit.type].get("building", false) and world.order_disguise(hit):
		_toast(tr("toast.disguised_as") % _type_label(hit.type))
		return

	if hit != null and hit.player == 0 and not hit.selected and not world.selection.is_empty() \
			and world.order_enter_transport(hit):
		_toast(tr("toast.boarding") % _type_label(hit.type))
		return
	if hit != null and hit.player == 0 and hit.selected and world.selection.size() == 1 and world.types[hit.type].has("transforms"):

		_toast(tr("toast.deployed") if world.deploy_selected() else tr("toast.deploy_impossible"))
		return
	if hit != null and hit.player == 0:
		world.select_only(hit)
		_show_selection_info()

		var kind := world.producer_kind(hit)
		if kind >= 0:
			build_bar.select_queue(kind)
			build_bar.visible = true
	elif world.selected_building() != null:

		if hit == null and world.set_rally(wp):
			_toast(tr("toast.rally_set"))
		elif hit == null:
			_toast(tr("toast.no_rally_point"))
		else:
			_toast(tr("toast.rally_ground_only"))
	elif hit != null:
		if not world.selection.is_empty():


			if world.hostile(0, hit.player):
				world.order_attack(hit)
				_last_gesture = "Angriff (%d)" % world.selection.size()
				_toast(tr("toast.attacking") % [_type_label(hit.type), world.selection.size()])
			else:
				world.order_move(hit.pos)
				_last_gesture = "Bewegen (%d)" % world.selection.size()
		else:
			_inspect(hit)
	elif not world.selection.is_empty():

		if world.has_ore(wp) and world.order_harvest(wp):
			_toast(tr("radial.action.harvest"))
		else:
			world.order_move(wp)
			_last_gesture = "Bewegen (%d)" % world.selection.size()
	else:
		_last_gesture = "Tippen ins Leere"


func _apply_click_mode(hit: ProtoWorld.Unit) -> bool:
	if hit == null or hit.player != 0 or not world.types[hit.type].get("building", false):
		return false
	if _click_mode == "sell":
		_toast(tr("toast.sold_unit") % _type_label(hit.type) if world.sell_unit(hit) else tr("toast.sell_impossible"))
	else:
		_toast("%s: %s" % [_type_label(hit.type), tr("toast.repair_toggled") if world.toggle_repair_unit(hit) else tr("toast.repair_not_needed")])
	return true


func _place_pos(p: Vector2) -> Vector2:
	return world.screen_to_world(p) - Vector2(0, PLACE_OFFSET_CELLS * ProtoWorld.CELL)


var _boxing := false
var _drag_pos := Vector2.ZERO


func _on_drag_started(p: Vector2) -> void:
	if world.placing_type >= 0:
		world.move_placement(_place_pos(p))
		world.place_armed = true
		return


	_end_click_mode()
	if _order_mode != "":
		_order_mode = ""
		_end_placement(tr("toast.order_cancelled"))
	world.begin_box(p)
	_boxing = true
	_drag_pos = p
	_last_gesture = "Rahmen …"


func _on_drag_updated(p: Vector2) -> void:
	if world.placing_type >= 0:
		world.move_placement(_place_pos(p))
		return
	_drag_pos = p
	world.update_box(p)


func _on_drag_ended(_p: Vector2) -> void:
	_boxing = false
	if world.placing_type >= 0:
		return
	var n := world.end_box()
	_show_selection_info()
	_last_gesture = "Rahmenauswahl: %d Einheiten" % n


func _edge_scroll(delta: float) -> void:
	if not _boxing:
		return
	var vs := get_viewport().get_visible_rect().size
	var edge := Dp.px(48)
	var speed := Dp.px(600) * delta
	var d := Vector2.ZERO
	if _drag_pos.x < edge:
		d.x = speed
	elif _drag_pos.x > vs.x - edge:
		d.x = -speed
	if _drag_pos.y < edge:
		d.y = speed
	elif _drag_pos.y > vs.y - edge:
		d.y = -speed
	if d != Vector2.ZERO:
		world.pan_screen(d)
		world.update_box(_drag_pos)


func _on_double_tap(p: Vector2) -> void:
	var wp := world.screen_to_world(p)
	var hit := world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit != null and hit.player == 0:
		world.select_same_type_visible(hit)
		_show_selection_info()
		_last_gesture = "Alle sichtbaren %s: %d" % [hit.type, world.selection.size()]


func _on_long_press(p: Vector2) -> void:
	if world.placing_type >= 0:
		return
	var hit := world.pick_unit(world.screen_to_world(p), Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit != null:
		_inspect(hit)
		if hit.player != 0:
			_show_info_card(hit, p)
			_last_gesture = "Infokarte"
			return
		if world.selection.is_empty():
			world.select_only(hit)
		if not world.selected_buildings().is_empty():
			radial.open(p, RadialMenu.BUILDING_ITEMS)
		else:
			radial.open(p, _unit_items())
		_last_gesture = "Radialmenü"
		return
	if world.selection.is_empty():
		_toast(tr("toast.ground"))
		return
	if not world.selected_buildings().is_empty():
		radial.open(p, RadialMenu.BUILDING_ITEMS)
	else:
		radial.open(p, _unit_items())
	_last_gesture = "Radialmenü"


func _unit_items() -> Array:


	var items: Array = ["attack_move", "move"]
	if world.sim != null and world.sim.has_method("order_attack_cell"):
		items.append("force_fire")
	items.append("stop")
	if world.sim != null and world.sim.has_method("order_guard"):
		items.append("guard")
	items.append("scatter")
	var has_harvester := false
	for u in world.selection:
		if world.types[u.type].get("harvester", false):
			has_harvester = true
	if has_harvester:
		items.append("harvest")
	if world.selection_can_deploy():
		items.append("deploy")
	if world.selection_can_lay_mine():
		items.append("mine")
	if world.selection_can_unload():
		items.append("unload")
	items.append("clear")
	return items


func _on_radial(action: String) -> void:
	if action != "":
		world.sfx.play_ui("ramenu1")
	match action:
		"stop":
			world.order_stop()
			_toast(tr("radial.action.stop"))
		"scatter":
			world.order_scatter()
			_toast(tr("radial.action.scatter"))
		"attack_move":
			_begin_order("attack_move", tr("radial.action.attack_move"))
		"move":
			_begin_order("move", tr("radial.action.move"))
		"harvest":
			_begin_order("harvest", tr("radial.action.harvest"))
		"force_fire":
			_begin_order("force_fire", tr("radial.target.force_fire"))
		"guard":
			_begin_order("guard", tr("radial.target.guard"))
		"clear":
			world.clear_selection()
			_toast(tr("toast.selection_cleared"))
		"sell":

			var refund := world.sell_refund()
			_toast(tr("toast.sold_for") % refund if world.sell_selected() else tr("toast.sell_impossible"))
		"repair":
			_toast(tr("toast.repair_toggled") if world.toggle_repair_selected() else tr("toast.repair_not_needed"))
		"primary":
			_toast(tr("toast.primary_set") if world.set_primary_selected() else tr("toast.produces_nothing"))
		"deploy":
			_toast(tr("toast.deployed") if world.deploy_selected() else tr("toast.deploy_impossible"))
		"mine":
			_toast(tr("toast.mine_laid") if world.lay_mine_selected() else tr("toast.mine_impossible"))
		"unload":
			_toast(tr("toast.unloading") if world.unload_selected() else tr("toast.nobody_aboard"))
		"":
			_last_gesture = "Radial abgebrochen"


var _info_label: Label
var _inspect_unit: ProtoWorld.Unit = null
var _inspect_until := 0.0


func _inspect(u: ProtoWorld.Unit) -> void:
	_inspect_unit = u
	_inspect_until = Time.get_ticks_msec() / 1000.0 + 6.0
	_update_info()


func _show_selection_info() -> void:
	_inspect_unit = null
	_update_info()


func _unit_text(u: ProtoWorld.Unit, owner_hint: bool) -> String:
	var s := _type_label(u.type)
	if owner_hint:
		s += " (%s)" % (tr("label.owner_own") if u.player == 0 else (tr("label.owner_neutral") if not world.hostile(0, u.player) else tr("label.owner_hostile")))
	s += "   %d %%" % int(round(u.hp * 100.0))
	if world.types[u.type].get("harvester", false):
		s += "   " + tr("label.ore_pct") % int(round(u.cargo * 100.0))
	return s


func _set_info(text: String) -> void:
	if _info_label.text != text:
		_info_label.text = text


func _update_info() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not world.selection.is_empty():
		var lead: ProtoWorld.Unit = world.selection[0]
		var text := _unit_text(lead, false)
		if world.selection.size() > 1:
			text = "%s ×%d" % [_type_label(lead.type), world.selection.size()]
			var hp := 0.0
			for u in world.selection:
				hp += u.hp
			text += "   %d %%" % int(round(hp / world.selection.size() * 100.0))
		var g := groups.group_of(lead)
		if g >= 0:
			text = "[%d] %s" % [g + 1, text]
		_set_info(text)
		return


	if _inspect_unit != null and now < _inspect_until and world.actor_shown(_inspect_unit):
		_set_info(_unit_text(_inspect_unit, true))
		return
	_inspect_unit = null
	_set_info("")


var _info_card: PanelContainer = null
var _info_card_backdrop: ColorRect = null


const ARMOR_TR_KEYS := ["armor.none", "armor.wood", "armor.light", "armor.heavy", "armor.concrete", "armor.tree"]

const INFO_CARD_WIDTH_DP := 260.0


func _show_info_card(u: ProtoWorld.Unit, press_pos: Vector2) -> void:
	_close_info_card()
	var t: Dictionary = world.types[u.type]


	_info_card_backdrop = HudTheme.dim_backdrop($UI)
	_info_card_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and e.pressed:
			if _info_card_backdrop != null:
				_info_card_backdrop.accept_event()
			_close_info_card())
	_info_card = PanelContainer.new()
	_info_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_card.add_theme_stylebox_override("panel", HudTheme.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(3)))
	box.custom_minimum_size = Vector2(Dp.px(INFO_CARD_WIDTH_DP), 0)
	var title := Label.new()
	title.text = Names.of(t)
	title.custom_minimum_size = Vector2(Dp.px(INFO_CARD_WIDTH_DP), 0)
	title.add_theme_font_size_override("font_size", int(Dp.px(16)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var desc := ActorInfo.description(u.type)
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.custom_minimum_size = Vector2(Dp.px(INFO_CARD_WIDTH_DP), 0)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_font_size_override("font_size", int(Dp.px(12)))
		dl.add_theme_color_override("font_color", HudTheme.TEXT)
		box.add_child(dl)
	if t.has("cost"):
		_info_card_line(box, tr("buildbar.info.price") % int(t["cost"]))
	var armor_idx := int(t.get("armor", 0))
	if armor_idx >= 0 and armor_idx < ARMOR_TR_KEYS.size():
		_info_card_line(box, tr("info.armor") % tr(ARMOR_TR_KEYS[armor_idx]))
	var speed := int(t.get("speed", 0))
	if speed > 0:
		var tps: int = maxi(1, world.sim.ticks_per_second())
		_info_card_line(box, tr("info.speed") % ("%.1f" % (speed / 1024.0 * tps)))
	var wname: String = str(t.get("weapon", ""))
	if wname != "" and world.rules.weapons.has(wname):
		var w: Dictionary = world.rules.weapons[wname]
		var rng := float(w.get("range", 0)) / 1024.0
		_info_card_line(box, tr("info.weapon_range") % [Names.of_key(wname, wname), "%.1f" % rng])
	elif wname == "" and not t.get("building", false):
		_info_card_line(box, tr("info.unarmed"), HudTheme.TEXT_DIM)
	var power := int(t.get("power", 0))
	if power > 0:
		_info_card_line(box, tr("buildbar.info.power_gen") % power, Color(0.3, 0.9, 0.3))
	elif power < 0:
		_info_card_line(box, tr("buildbar.info.power_use") % -power, Color(0.95, 0.25, 0.2))
	var prereq_names: Array = []
	var hidden_prereqs: Array = t.get("prerequisites_hidden", [])
	for p in t.get("prerequisites", []):
		var pn := str(p)


		if pn.begins_with("~") or pn == "" or hidden_prereqs.has(pn):
			continue
		prereq_names.append(Names.of_key(pn, pn))
	if not prereq_names.is_empty():
		_info_card_line(box, tr("info.prereq") % ", ".join(prereq_names))
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(120), Dp.px(34))
	HudTheme.plate_button_style(close, 12.0, 10.0)
	close.pressed.connect(_close_info_card)
	box.add_child(close)
	_info_card.add_child(box)
	$UI.add_child(_info_card)
	_info_card.reset_size()
	_position_info_card(press_pos)


func _info_card_line(box: VBoxContainer, text: String, col: Color = HudTheme.TEXT) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(Dp.px(INFO_CARD_WIDTH_DP), 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(Dp.px(12)))
	l.add_theme_color_override("font_color", col)
	box.add_child(l)


func _position_info_card(press_pos: Vector2) -> void:
	var safe := Dp.safe_rect()
	var size: Vector2 = _info_card.size.min(safe.size)
	_info_card.size = size
	var avail := safe.size - size
	var min_y := status_bar.position.y + status_bar.size.y + Dp.px(8)
	var pos := Vector2(press_pos.x - size.x / 2.0, maxf(press_pos.y - Dp.px(140) - size.y, min_y))
	pos.x = clampf(pos.x, safe.position.x, safe.position.x + avail.x)
	pos.y = clampf(pos.y, safe.position.y, safe.position.y + avail.y)
	_info_card.position = pos


func _close_info_card() -> void:
	if _info_card != null:
		_info_card.queue_free()
		_info_card = null
	if _info_card_backdrop != null:
		_info_card_backdrop.queue_free()
		_info_card_backdrop = null


const CMD_BTN_W_DP := HudTheme.ICON_BTN_W_DP
const CMD_BTN_H_DP := HudTheme.ICON_BTN_H_DP


const CMD_ICONS := {
	"sell": "res://icons/ui/btn_verkauf_2.png", "repair": "res://icons/ui/btn_reparatur_1.png",
	"add": "res://icons/ui/btn_mehr_2.png", "all": "res://icons/ui/btn_alle_1.png",
	"clear": "res://icons/ui/btn_leer_1.png", "base": "res://icons/ui/btn_basis_1.png",
	"event": "res://icons/ui/btn_alarm_1.png", "sel": "res://icons/ui/btn_ausw_2.png",
	"zoom_in": "res://icons/ui/btn_zoomplus_1.png", "zoom_out": "res://icons/ui/btn_zoomminus_1.png",
}

var _cmd_buttons := {}
var _mode_frame: Panel


const CMD_ORDER := ["sell", "repair", "add", "all", "clear", "base", "event", "sel", "zoom_in", "zoom_out"]


func _cmd_button(id: String, text: String, tip: String, toggle: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.tooltip_text = "%s — %s" % [text, tip]
	b.toggle_mode = toggle
	b.icon = load(CMD_ICONS[id])
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	HudTheme.style_icon_button(b)
	HudTheme.wire_help(b, "help.btn.%s" % id, $UI, cb)
	$UI.add_child(b)
	b.add_to_group("layout_hud")
	_cmd_buttons[id] = b
	return b


func _build_command_bar() -> void:
	_cmd_button("sell", tr("cmd.sell.label"), tr("cmd.sell.tip"), true, func(): _set_click_mode("sell"))
	_cmd_button("repair", tr("cmd.repair.label"), tr("cmd.repair.tip"), true, func(): _set_click_mode("repair"))
	_cmd_button("add", tr("cmd.add.label"), tr("cmd.add.tip"), true, func():
		world.additive_select = _cmd_buttons["add"].button_pressed
		_toast(tr("toast.add_select") % (tr("word.on") if world.additive_select else tr("word.off"))))
	_cmd_button("all", tr("cmd.all.label"), tr("cmd.all.tip"), false, func():
		_end_click_mode()
		_toast(tr("toast.all_units_count") % world.select_all_units())
		_show_selection_info())
	_cmd_button("clear", tr("cmd.clear.label"), tr("cmd.clear.tip"), false, func():
		_end_click_mode()
		world.clear_selection()
		_show_selection_info()
		_toast(tr("toast.selection_cleared")))
	_cmd_button("base", tr("cmd.base.label"), tr("cmd.base.tip"), false, _jump_to_base)
	_cmd_button("event", tr("cmd.event.label"), tr("cmd.event.tip"), false, func():
		if _has_event:
			world.center_on(_last_event_pos)
		else:
			_toast(tr("toast.no_event")))
	_cmd_button("sel", tr("cmd.sel.label"), tr("cmd.sel.tip"), false, func():
		if world.selection.is_empty():
			_toast(tr("toast.nothing_selected"))
		else:
			world.center_on(world.selection_center()))
	_cmd_button("zoom_in", tr("cmd.zoom_in.label"), tr("cmd.zoom_in.tip"), false, func(): _zoom_step(1.25))
	_cmd_button("zoom_out", tr("cmd.zoom_out.label"), tr("cmd.zoom_out.tip"), false, func(): _zoom_step(0.8))

	_mode_frame = Panel.new()
	_mode_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_frame.visible = false
	$UI.add_child(_mode_frame)


func _layout_command_bar(vs: Vector2, m: float, off: Vector2, cols: int) -> void:
	var bw := Dp.px(CMD_BTN_W_DP)
	var bh := Dp.px(CMD_BTN_H_DP)
	var gap := Dp.px(4)
	var x0 := off.x + m + minimap.size.x + m
	var y_bottom := vs.y - m - bh
	var rows := int(ceil(CMD_ORDER.size() / float(cols)))
	for i in CMD_ORDER.size():
		var b: Button = _cmd_buttons[CMD_ORDER[i]]
		var col := i % cols
		var row_from_bottom := rows - 1 - i / cols
		b.size = Vector2(bw, bh)
		b.position = Vector2(x0 + col * (bw + gap), y_bottom - row_from_bottom * (bh + gap))


func _fit_bottom_bars(safe: Rect2, m: float) -> Dictionary:
	var bw := Dp.px(CMD_BTN_W_DP)
	var gap := Dp.px(4)
	var bmargin := Dp.px(BuildBar.MARGIN_DP)
	var slot_w := Dp.px(BuildBar.SLOT_W_DP)
	var avail := safe.size.x - minimap.size.x - 3.0 * m
	for cmd_cols in [5, 2]:
		var cmd_w: float = cmd_cols * bw + (cmd_cols - 1) * gap
		for build_cols in [BuildBar.MAX_COLUMNS, 3, BuildBar.MIN_COLUMNS]:
			var build_w: float = build_cols * slot_w + (build_cols + 1) * bmargin
			if cmd_w + m + build_w <= avail:
				return {"cmd_cols": cmd_cols, "build_cols": build_cols}
	return {"cmd_cols": 2, "build_cols": BuildBar.MIN_COLUMNS}


func hud_map_rect(safe: Rect2, fit: Dictionary) -> Rect2:
	var m := Dp.px(12)
	var bb := BuildBar.preferred_size(minf(safe.size.x, safe.size.y), fit["build_cols"])
	var cmd_rows := int(ceil(CMD_ORDER.size() / float(fit["cmd_cols"])))
	var cmd_h := cmd_rows * Dp.px(CMD_BTN_H_DP) + maxi(cmd_rows - 1, 0) * Dp.px(4)
	var left := Dp.px(HUD_LEFT_DP)
	var top := Dp.px(HUD_TOP_DP)
	var right := m + bb.x
	var bottom := m + maxf(maxf(minimap.size.y, bb.y), cmd_h)


	var w := safe.size.x - left - right
	var h := safe.size.y - top - bottom
	if w <= 0.0 or h <= 0.0:
		return Rect2()
	return Rect2(safe.position + Vector2(left, top), Vector2(w, h))


func _set_click_mode(mode: String) -> void:
	if _click_mode == mode:
		_end_click_mode()
		return
	_click_mode = mode
	for id in ["sell", "repair"]:
		_cmd_buttons[id].button_pressed = _click_mode == id
	_mode_frame.visible = true
	var col := Color(0.95, 0.3, 0.25) if _click_mode == "sell" else Color(0.3, 0.85, 0.4)
	_mode_frame.add_theme_stylebox_override("panel", HudTheme.panel(Color(0, 0, 0, 0), col, 0.0, 3.0))
	_toast(tr("toast.mode_tap_building") % (tr("word.sell_verb") if _click_mode == "sell" else tr("word.repair_verb")))


func _end_click_mode() -> void:
	if _click_mode == "":
		return
	_click_mode = ""
	for id in ["sell", "repair"]:
		_cmd_buttons[id].button_pressed = false
	_mode_frame.visible = false
	_toast(tr("toast.mode_off"))


func _zoom_step(factor: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	world.zoom_at(factor, vs / 2.0)


var _base_index := 0


func _jump_to_base() -> void:
	var list := world.base_buildings()
	if list.is_empty():
		_toast(tr("toast.no_base"))
		return
	_base_index = (_base_index + 1) % list.size()
	world.center_on(list[_base_index].pos)


func _run_test_sell() -> void:
	var sim = world.sim
	var powr: int = world.type_ids["powr"]
	var tick: int = sim.tick()
	match _test_step:
		0:
			if tick >= 10:


				_test_origin = _place_test_fact()
				print("T: queue powr → ", sim.queue_build(0, powr))
				_test_step = 1
		1:
			var q: PackedInt32Array = sim.queue_state(0, 0)
			if q.size() >= 4 and q[2] == 1:
				_begin_placement(powr)


				var found := false
				for dy in range(-5, 10):
					for dx in range(-7, 8):
						var c: Vector2 = Vector2(_test_origin) + Vector2(dx, dy)
						world.move_placement(c * ProtoWorld.CELL)
						if world.placement_ok():
							print("T: try ", c, " origin=", world.place_origin, " cells=", world.sim.can_place(0, powr, world.place_origin.x, world.place_origin.y))
							found = true
							break
					if found:
						break
				print("T: place → ", world.confirm_placement(), " ok=", world.placement_ok())
				_end_placement("T platziert")
				_test_step = 2
				_test_tick = tick
		2:
			if tick >= _test_tick + 80:
				for u in world.units:
					if u.alive and u.player == 0 and u.type == "powr":
						world.select_only(u)
				print("T: sell → ", world.sell_selected(), " refund=", world.sell_refund())
				_test_step = 3
				_test_tick = tick
		3:
			if tick >= _test_tick + 80:
				print("T: queue powr again → ", sim.queue_build(0, powr), " queue=", sim.queue_state(0, 0),
					" buildable=", sim.buildable(0, 0), " credits=", sim.credits(0))
				_test_step = 4
				_test_tick = tick
		4:
			if tick >= _test_tick + 30:
				print("T: queue=", sim.queue_state(0, 0))
				get_tree().quit()


var _test_tick := 0
var _screenshot_tick := 600
var _screenshot_series := 1
var _test_frame_extra := 0
var _shot_running := false
var _test_origin := Vector2i.ZERO
var _test_ai_until := 6000
var _test_cycle := false
var _test_speed := false
var _speed_t0 := -1.0
var _speed_tick0 := 0


var _test_speed_switch := -1
var _speed_switched := false


var _test_speed_ui := false
var _test_defeat := false
var _test_victory := false
var _defeat_step := 0
var _defeat_tick := 0
var _any_test := false
var _ai_attacked := false
var _ai_alive := -1
var _ai_shot := false


func _place_test_fact() -> Vector2i:
	var origin := Vector2i(10, 10)
	for u in world.units:
		if u.alive and u.player == 0:
			origin = Vector2i(u.pos / ProtoWorld.CELL)
			break
	for u in world.units:
		if u.alive and u.player == 0 and u.type == "fact":
			return origin

	if world.type_ids.has("fact"):
		world.call("_add_building", "fact", 0, origin + Vector2i(2, 0))
	return origin


var _test_frame := 0
var _test_defense := false
var _test_briefing := false


func _run_test_buildings() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		var i := 0
		var focus := origin
		for t in ["powr", "powr", "weap", "proc", "fix", "dome"]:
			if world.type_ids.has(t):
				var cell := origin + Vector2i(-4 + i * 5, 4)
				world.call("_add_building", t, 0, cell)
				if t == "weap":
					focus = cell
				i += 1
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(focus) + Vector2(3.0, 3.0)) * ProtoWorld.CELL)
		sim.give_credits(0, 20000)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 120:

		if world.type_ids.has("1tnk"):
			sim.queue_build(0, world.type_ids["1tnk"])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 460:
		_test_step = 3

		for t in ["weap", "proc"]:
			var d: Dictionary = world.types.get(t, {})
			print("T: ", t, " overlay=", d.get("overlay_sprite", "-"), " start=", d.get("overlay_start", -1),
				" len=", d.get("overlay_len", 0), " door=", d.get("door_len", 0))
		if _screenshot_path != "":
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _run_demo_battle() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 50000)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		for k in 3:
			world.call("_add_building", "powr", 0, origin + Vector2i(7, -4 + 3 * k))
		world.call("_add_building", "tsla", 0, origin + Vector2i(-2, -4))
		world.call("_add_building", "tsla", 0, origin + Vector2i(-2, 4))
		var own := PackedInt32Array()
		var tanya = null
		var lineup := [["4tnk", 3, -3], ["4tnk", 3, -1], ["4tnk", 3, 1], ["4tnk", 3, 3],
			["ttnk", 1, -2], ["ttnk", 1, 0], ["ttnk", 1, 2], ["4tnk", -1, -3], ["4tnk", -1, 3],
			["e7", -1, 0], ["e1", -1, -1], ["e1", -1, 1], ["e3", 0, -1], ["e3", 0, 1]]
		for row in lineup:
			var u = world.spawn_unit(row[0], 0, origin + Vector2i(row[1], row[2]))
			if u != null:
				own.append(u.id)
				if row[0] == "e7":
					tanya = u
		var foe := PackedInt32Array()
		var wave := [["2tnk", -11, -3], ["2tnk", -11, -1], ["2tnk", -11, 1], ["2tnk", -11, 3],
			["2tnk", -13, -2], ["2tnk", -13, 0], ["2tnk", -13, 2], ["1tnk", -14, -3], ["1tnk", -14, 3],
			["arty", -16, -1], ["arty", -16, 1], ["jeep", -12, -4], ["jeep", -12, 4],
			["e1", -10, -2], ["e1", -10, 0], ["e1", -10, 2], ["e3", -9, -1], ["e3", -9, 1], ["e2", -9, -3], ["e2", -9, 3]]
		for row in wave:
			var u = world.spawn_unit(row[0], 1, origin + Vector2i(row[1], row[2]), 96)
			if u != null:
				foe.append(u.id)
		sim.order_attack_move(foe, origin.x + 2, origin.y)
		sim.order_attack_move(own, origin.x - 8, origin.y)
		if tanya != null:
			world.select_only(tanya)
		world.zoom_at(2.8 / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(-6.5, -0.5)) * ProtoWorld.CELL)
		_test_step = 1
		_demo_next_tick = tick + 20
	elif _test_step == 1 and tick >= _demo_next_tick:
		_demo_next_tick = tick + 15
		if _screenshot_path != "":
			var path := "%s-%02d.png" % [_screenshot_path.get_basename(), _demo_shots]
			get_viewport().get_texture().get_image().save_png(path)
			print("T%d --demo-battle: Bild %s" % [tick, path])
		_demo_shots += 1
		if _demo_shots >= 40:
			get_tree().quit()


func _run_test_tesla() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 20000)
		for t in ["powr", "powr"]:
			world.call("_add_building", t, 0, origin + Vector2i(-6, 4))
		world.call("_add_building", "powr", 0, origin + Vector2i(-6, 8))
		world.call("_add_building", "tsla", 0, origin)

		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		for k in 4:
			world.spawn_unit("e1", 1, origin + Vector2i(4, -2 + k))
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(2.0, 0.5)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 14:

		if _screenshot_path != "":
			var charge_path: String = _screenshot_path.get_basename() + "_laden.png"
			get_viewport().get_texture().get_image().save_png(charge_path)
			print("T%d --test-tesla: Ladeanimation, Screenshot %s" % [tick, charge_path])
		print("T%d --test-tesla: Ziele %d" % [tick, sim.alive_count(1)])
		_test_step = 2
	elif _test_step == 2:

		if sim.alive_count(1) == 0:
			print("T%d --test-tesla: alle Ziele zerstört, kein Blitz mehr" % tick)
			get_tree().quit()
			return
		if _tesla_shot_frames < 0 and _tesla_zap_now():
			_tesla_shot_frames = Engine.get_process_frames()
		if _tesla_shot_frames >= 0 and _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("T%d --test-tesla: Blitz sichtbar, Screenshot %s" % [tick, _screenshot_path])
			get_tree().quit()


func _run_test_nuke() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 20000)
		for i in 4:
			world.call("_add_building", "powr", 0, origin + Vector2i(-6, i * 3))
		world.call("_add_building", "mslo", 0, origin + Vector2i(6, 0))
		world.call("_add_building", "dome", 0, origin + Vector2i(-6, 12))
		_test_nuke_target = origin + Vector2i(14, 4)


		var b: Rect2i = world.bounds
		_test_nuke_target.x = clampi(_test_nuke_target.x, b.position.x + 2, b.end.x - 3)
		_test_nuke_target.y = clampi(_test_nuke_target.y, b.position.y + 2, b.end.y - 3)
		world.center_on((Vector2(_test_nuke_target) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_nuke_wait_until = Time.get_ticks_msec() + 900
		_test_step = 1
	elif _test_step == 1:


		if Time.get_ticks_msec() < _test_nuke_wait_until:
			return
		_test_step = 2
	elif _test_step == 2:
		var ready := false
		for _i in 14000:
			sim.step()
			var st: PackedInt32Array = sim.support_powers(0)
			if st.size() >= 12 and st[9] == 1:
				ready = true
				break
		if not ready:
			print("T --test-nuke: Silo nicht rechtzeitig geladen")
			get_tree().quit()
			return
		if not world.activate_support_power(2, (Vector2(_test_nuke_target) + Vector2(0.5, 0.5)) * ProtoWorld.CELL):
			print("T --test-nuke: Abfeuern fehlgeschlagen")
			get_tree().quit()
			return
		print("T%d --test-nuke: Rakete gestartet, Ziel %s" % [sim.tick(), _test_nuke_target])
		_test_step = 3
	elif _test_step == 3:
		var nukes: PackedInt32Array = sim.pending_nukes()
		if nukes.size() < 4:
			print("T%d --test-nuke: kein pending_nukes()-Eintrag während des Flugs" % tick)
			get_tree().quit()
			return
		if _screenshot_path != "":
			var flight_path: String = _screenshot_path.get_basename() + "_flug.png"
			get_viewport().get_texture().get_image().save_png(flight_path)
			print("T%d --test-nuke: im Flug (Restticks %d), Screenshot %s" % [tick, nukes[3], flight_path])
		_test_step = 4
	elif _test_step == 4:
		var nukes: PackedInt32Array = sim.pending_nukes()
		if nukes.is_empty():
			if _screenshot_path != "":
				var impact_path: String = _screenshot_path.get_basename() + "_einschlag.png"
				get_viewport().get_texture().get_image().save_png(impact_path)
				print("T%d --test-nuke: Einschlag, Screenshot %s" % [tick, impact_path])
			else:
				print("T%d --test-nuke: Einschlag" % tick)
			get_tree().quit()


const PLACEMENT_TEST_TYPES := ["tsla", "gap", "apwr", "powr", "dome", "atek", "stek", "mslo", "iron",
	"pdox", "sam", "agun", "ftur", "silo", "fix", "weap", "proc", "fact", "hpad", "afld", "kenn", "barr", "tent"]


func _run_test_placement() -> void:
	if _test_step != 0 or world.sim.tick() < 10:
		return
	_test_step = 1
	const COLS := 6
	const STEP := 6


	var base := Vector2i(40, 35)
	var fail := 0
	var checked := 0
	var i := 0
	for t in PLACEMENT_TEST_TYPES:
		if not world.type_ids.has(t):
			print("T --test-placement: %-5s fehlt in rules.json — übersprungen" % t)
			continue
		var cell := base + Vector2i((i % COLS) * STEP, (i / COLS) * STEP)
		i += 1
		var u: ProtoWorld.Unit = world.call("_add_building", t, 0, cell)
		if u == null or u.id < 0:
			print("T --test-placement: %-5s konnte nicht gebaut werden" % t)
			fail += 1
			continue
		checked += 1
		var td: Dictionary = world.types[t]
		var texture_size := Vector2(world.atlas().sprite_frame_size[td["body"]])
		var ghost_pos: Vector2 = world.ghost_draw_pos(t, cell, texture_size)
		var off := Vector2(td.get("offset_x", 0), td.get("offset_y", 0))
		var real_pos: Vector2 = u.pos - texture_size / 2.0 + off
		var diff: float = ghost_pos.distance_to(real_pos)
		var ok := diff < 0.01
		if not ok:
			fail += 1
		print("T --test-placement: %-5s Geist=%s Gebaut=%s Diff=%.3fpx %s" % [
			t, ghost_pos, real_pos, diff, "OK" if ok else "FEHLER"])
		_placement_shots[t] = {"origin": cell}
	print("T --test-placement: %d/%d Gebäude geprüft, %d Abweichungen" % [checked, PLACEMENT_TEST_TYPES.size(), fail])
	call_deferred("_run_test_placement_tap")


func _run_test_ready() -> void:
	var sim = world.sim
	var pid: int = world.type_ids.get("powr", -1)
	if pid < 0:
		print("T --test-ready: Typ 'powr' fehlt")
		return
	sim.give_credits(0, 20000)
	world.queue_build(pid)
	var ready := false
	for _i in 20000:
		sim.step()
		var q: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
		if q.size() >= 3 and q[0] == pid and q[2] == 1:
			ready = true
			break
	if not ready:
		print("T --test-ready: Kraftwerk nicht rechtzeitig fertig")
		return
	build_bar.visible = _test_ready != "zu"
	build_bar.select_queue(ProtoWorld.Queue.DEFENSE if _test_ready != "zu" else ProtoWorld.Queue.BUILDING)
	build_bar.call("_rebuild")
	if _test_ready == "platziert":
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "fact":
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		var placed := false
		for dy in range(-4, 12):
			for dx in range(-8, 12):
				var cand := origin + Vector2i(dx, dy)
				var res: PackedByteArray = sim.can_place(0, pid, cand.x, cand.y)
				if res.size() > 0 and res[0] == 1:
					placed = sim.place_building(0, pid, cand.x, cand.y)
					break
			if placed:
				break
		build_bar.call("_rebuild")
		print("T --test-ready: platziert=%s" % placed)
	print("T --test-ready %s: Warteschlange=%s Leiste offen=%s Reiter=%d Leuchten gesamt=%s" % [
		_test_ready, sim.queue_state(0, ProtoWorld.Queue.BUILDING).slice(0, 3), build_bar.visible,
		build_bar.kind, build_bar.call("any_ready")])
	_test_frame_extra = 30


func _run_test_placement_tap() -> void:
	if not world.type_ids.has("weap") or not _placement_shots.has("weap"):
		print("T --test-placement: weap fehlt — Tipp-Test übersprungen")
		call_deferred("_run_test_placement_shots")
		return
	var sim = world.sim
	var type_id: int = world.type_ids["weap"]


	sim.give_credits(0, 20000)
	print("T --test-placement Tipp: queue weap → ", sim.queue_build(0, type_id))
	var ready := false
	for _i in 20000:
		sim.step()
		var q: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
		if q.size() >= 3 and q[0] == type_id and q[2] == 1:
			ready = true
			break
	if not ready:
		print("T --test-placement Tipp: weap nicht rechtzeitig fertig — Tipp-Test übersprungen")
		call_deferred("_run_test_placement_shots")
		return


	var free_cell := Vector2i(-1, -1)
	var probe: Vector2i = Vector2i(_placement_shots["weap"]["origin"])
	for dy in range(-2, 24):
		for dx in range(-2, 24):
			var cand := probe + Vector2i(dx, dy)
			var res: PackedByteArray = sim.can_place(0, type_id, cand.x, cand.y)
			if res.size() > 0 and res[0] == 1:
				free_cell = cand
				break
		if free_cell.x >= 0:
			break
	if free_cell.x < 0:
		print("T --test-placement Tipp: keine freie Zelle für weap gefunden — Tipp-Test übersprungen")
		call_deferred("_run_test_placement_shots")
		return
	var td: Dictionary = world.types["weap"]
	var rows0: PackedStringArray = td["footprint"].split(" ")


	var free_pos := (Vector2(free_cell) + Vector2(rows0[0].length(), rows0.size()) / 2.0) * ProtoWorld.CELL


	world.begin_placement(type_id)
	world.tap_placement(free_pos)
	var before_origin := world.place_origin
	var outside := free_pos + Vector2(15 * ProtoWorld.CELL, 0)
	var built := world.tap_placement(outside)
	var moved := world.place_origin != before_origin
	print("T --test-placement Tipp: 1. Tipp außerhalb built=%s verschoben=%s %s" % [
		built, moved, "OK" if (not built and moved) else "FEHLER"])


	world.begin_placement(type_id)
	built = world.tap_placement(free_pos)
	print("T --test-placement Tipp: 2. Tipp setzt Position built=%s armed=%s origin=%s (erwartet %s)" % [
		built, world.place_armed, world.place_origin, free_cell])
	var bounds_v: Vector2 = td.get("bounds", Vector2(ProtoWorld.CELL, ProtoWorld.CELL))
	var center := Vector2(world.place_origin) * ProtoWorld.CELL + bounds_v / 2.0
	built = world.tap_placement(center)
	print("T --test-placement Tipp: 3. Tipp Mitte built=%s %s" % [built, "OK" if built else "FEHLER"])
	world.cancel_placement()
	call_deferred("_run_test_placement_shots")


func _run_test_placement_shots() -> void:
	for t in ["tsla", "apwr", "weap"]:
		if not _placement_shots.has(t) or not world.type_ids.has(t):
			continue
		var info: Dictionary = _placement_shots[t]
		var origin: Vector2i = info["origin"]
		var type_id: int = world.type_ids[t]
		var td: Dictionary = world.types[t]
		var rows: PackedStringArray = td["footprint"].split(" ")
		var w := rows[0].length()


		world.begin_placement(type_id)
		world.move_placement((Vector2(origin) + Vector2(w + 2, 0.5)) * ProtoWorld.CELL)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(w + 1.0, 1.0)) * ProtoWorld.CELL)
		await get_tree().process_frame
		await get_tree().process_frame
		if _screenshot_path != "":
			var path: String = _screenshot_path.get_basename() + "_" + t + ".png"
			get_viewport().get_texture().get_image().save_png(path)
			print("T --test-placement: Screenshot %s" % path)
		world.cancel_placement()
	get_tree().quit()


func _run_test_lobby_tap() -> void:
	if _test_step != 0 or world.sim.tick() < 60:
		return
	_test_step = 1
	var own: ProtoWorld.Unit = null
	var ally: ProtoWorld.Unit = null
	for u in world.units:
		if not u.alive or u.type == "":
			continue

		if u.player == 0 and own == null and not world.types[u.type].get("building", false):
			own = u


		elif u.player != 0 and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS \
				and not world.hostile(0, u.player) and ally == null:
			ally = u
		if own != null and ally != null:
			break
	if own == null or ally == null:
		var by_player := {}
		for u in world.units:
			if u.alive:
				var key := "%d/%s/bld=%s/hostile0=%s" % [u.player, u.type, world.types[u.type].get("building", false), world.hostile(0, u.player)]
				by_player[key] = by_player.get(key, 0) + 1
		print("T --test-lobby: eigene Einheit oder Verbündeter nicht gefunden (own=%s ally=%s), Einheiten=%s — Team-Aufteilung prüfen" % [
			own != null, ally != null, by_player])
		get_tree().quit()
		return
	world.select_only(own)
	world.center_on(ally.pos)
	_on_tap(world.world_to_screen(ally.pos))
	var attacked: bool = _last_gesture.begins_with("Angriff")
	print("T --test-lobby: eigene=%s Verbündeter=%s (Spieler %d) → %s (%s)" % [
		own.type, ally.type, ally.player, _last_gesture, "FEHLER: Angriff auf Verbündeten" if attacked else "OK"])


	var foe: ProtoWorld.Unit = null
	for u in world.units:
		if u.alive and u.type != "" and u.player != 0 and world.hostile(0, u.player):
			foe = u
			break
	if foe != null:
		world.select_only(own)
		world.center_on(foe.pos)
		_on_tap(world.world_to_screen(foe.pos))
		var foe_attacked: bool = _last_gesture.begins_with("Angriff")
		print("T --test-lobby: eigene=%s Feind=%s (Spieler %d) → %s (%s)" % [
			own.type, foe.type, foe.player, _last_gesture, "OK" if foe_attacked else "FEHLER: kein Angriff auf Feind"])
	get_tree().quit()


var _tesla_shot_frames := -1


func _tesla_zap_now() -> bool:
	for u in world.units:
		if u.alive and u.type == "tsla" and u.firing:
			return true
	return false


func _run_test_spy() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		var i := 0
		for t in ["proc", "powr", "dome", "barr"]:
			if world.type_ids.has(t):
				world.call("_add_building", t, 1, origin + Vector2i(-6 + i * 6, -10))
				i += 1

		if world.type_ids.has("powr"):
			var own: ProtoWorld.Unit = world.call("_add_building", "powr", 0, origin + Vector2i(6, 4))
			if own != null:
				sim.set_health(own.id, int(world.types["powr"].get("hp", 1)) / 3)
		for t in ["e6", "e7", "spy", "thf", "e1"]:
			if world.type_ids.has(t):
				world.spawn_unit(t, 0, origin + Vector2i(i, 2))
				i += 1
		world.spawn_unit("e1", 1, origin + Vector2i(0, -4))
		sim.give_credits(1, 4000)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 25:
		print("T: Strom Gegner=%d Credits Gegner=%d Credits Spieler=%d" % [sim.power_provided(1), sim.credits(1), sim.credits(0)])
		_order("spy", "dome", "Spion → Radarkuppel")
		_order("thf", "proc", "Dieb → Raffinerie")
		_order("e6", "powr", "Pionier → eigenes Kraftwerk", 0)

		var tanya: ProtoWorld.Unit = _find_own("e7")
		if tanya != null:
			sim.set_stance(tanya.id, 0)
		_order("e7", "barr", "Tanya → Kaserne")

		var spy: ProtoWorld.Unit = _find_own("spy")
		var foe: ProtoWorld.Unit = _find_foe("e1")
		if spy != null and foe != null:
			world.select_only(spy)
			print("T: Verkleidung ", "ok" if world.order_disguise(foe) else "fehlgeschlagen")
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 1500:
		print("T: Credits Spieler=%d Gegner=%d (Dieb: 50 %% aus der Raffinerie)" % [sim.credits(0), sim.credits(1)])
		var own_powr: ProtoWorld.Unit = _find_own("powr")
		print("T: eigenes Kraftwerk HP=%.2f (Pionier repariert voll)" % (own_powr.hp if own_powr != null else -1.0))
		print("T: Kaserne des Gegners lebt=%s (Tanya sprengt), Tanya lebt=%s" % [
			_find_foe("barr") != null, _find_own("e7") != null])
		var unexplored := 0
		var vis: PackedByteArray = sim.visibility_map(0)
		for v in vis:
			if v == 0:
				unexplored += 1
		print("T: unerkundete Zellen=%d (Spion in der Radarkuppel deckt die Karte auf)" % unexplored)
		_test_step = 3
		get_tree().quit()


func _find_decoration() -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and world.types[u.type].get("decoration", false) and not world.types[u.type].get("capturable", false) \
				and int(world.types[u.type].get("target_types", 0)) & ProtoWorld.TARGET_BARREL == 0:
			return u
	return null


func _find_own(type: String) -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and u.player == 0 and u.type == type:
			return u
	return null


func _find_foe(type: String) -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and u.player == 1 and u.type == type:
			return u
	return null


func _order(unit_type: String, target_type: String, label: String, target_player: int = 1) -> void:
	var u: ProtoWorld.Unit = _find_own(unit_type)
	var t: ProtoWorld.Unit = null
	for o in world.units:
		if o.alive and o.player == target_player and o.type == target_type and o != u:
			t = o
			break
	if u == null or t == null:
		print("T: %s — Einheit oder Ziel fehlt" % label)
		return
	world.select_only(u)
	var kind := world.enter_kind(t)
	print("T: %s → Wirkung %d „%s\"" % [label, kind, tr(world.order_enter(t)) % target_type])


var _test_armaments := false
var _arm_hp := {}
var _test_projectile := false
var _proj_shots := 0
var _proj_ticks := 0
var _proj_frames := PackedInt32Array()
var _v2_blocks := {}


func _run_test_projectile() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		var dirs := [Vector2i(0, -7), Vector2i(7, 0), Vector2i(0, 7), Vector2i(-7, 0)]
		var i := 0
		for d in dirs:
			var shooter: String = "v2rl" if i % 2 == 0 else "e3"
			if world.type_ids.has(shooter):
				world.spawn_unit(shooter, 0, origin + d)
			if world.type_ids.has("e1"):
				world.spawn_unit("e1", 1, origin - d)
			i += 1
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on(Vector2(origin) * ProtoWorld.CELL)
		for n in ["dragon", "scud"]:
			var wd: Dictionary = world.rules.weapons.get(n, {})
			print("T: Waffe %s Sprite=%s Facings=%d Start=%d" % [n, wd.get("sprite", "-"),
				int(wd.get("sprite_facings", 1)), int(wd.get("sprite_start", 0))])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 20:
		_test_step = 2
	elif _test_step == 2:


		if sim.projectile_count() > 0:


			var atlas0 = world.atlas()
			var b: PackedFloat32Array = sim.render_buffer(1.0)
			for j in b.size() / 12:
				var f: int = int(b[j * 12 + 8])
				for n2 in ["dragon", "v2"]:
					if not atlas0.sprite_frame_count.has(n2):
						continue
					var base: int = atlas0.frame_index(n2, 0)
					if f >= base and f < base + 32 and not _proj_frames.has(f):
						_proj_frames.append(f)


				if atlas0.sprite_frame_count.has("v2rl"):
					var vbase: int = atlas0.frame_index("v2rl", 0)
					if f >= vbase and f < vbase + 64:
						_v2_blocks[(f - vbase) / 32] = true
			_proj_shots += 1

			if _proj_shots == 6 and _screenshot_path != "":
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("Screenshot: ", _screenshot_path)
		_proj_ticks += 1
		if _proj_ticks >= 900:
			_test_step = 3
			var atlas = world.atlas()
			for n2 in ["dragon", "v2"]:
				print("T: Atlas %s erster Frame=%d Frames=%d" % [n2,
					atlas.frame_index(n2, 0) if atlas.sprite_frame_count.has(n2) else -1,
					atlas.sprite_frame_count.get(n2, 0)])
			_proj_frames.sort()
			var facings := PackedInt32Array()
			for f in _proj_frames:
				for n2 in ["dragon", "v2"]:
					if not atlas.sprite_frame_count.has(n2):
						continue
					var base: int = atlas.frame_index(n2, 0)
					if f >= base and f < base + 32:
						facings.append(f - base)
			print("T: --test-projectile: %d verschiedene Flugrichtungen (Facing-Frames) %s" % [
				facings.size(), str(facings)])
			print("T: v2rl Rumpfblöcke gesehen: %s (0 = geladen, 1 = leere Rampe)" % [_v2_blocks.keys()])
			get_tree().quit()


var _test_barrels := false


func _run_test_barrels() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		for d in [Vector2i(0, -6), Vector2i(1, -6)]:
			if world.type_ids.has("barl"):
				world.call("_add_building", "barl", ProtoWorld.PLAYER_NEUTRAL, origin + d)
		if world.type_ids.has("e1"):
			world.spawn_unit("e1", 0, origin + Vector2i(0, -5))
			world.spawn_unit("e1", 0, origin + Vector2i(0, 0))
		world.center_on((Vector2(origin) + Vector2(0, -3)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 25:
		var barrel: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.type == "barl":
				barrel = u
				break
		var shooter: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "e1":
				shooter = u
		print("T: Fässer=%d Schütze=%s Ziel=%s" % [
			_count_type("barl"), shooter != null, barrel != null])
		if shooter != null and barrel != null:
			world.select_only(shooter)
			world.order_attack(barrel)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 600:
		var infantry := 0
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "e1":
				infantry += 1
		print("T: --test-barrels: Fässer übrig=%d, eigene Infanterie übrig=%d (erwartet 0 / 1)" % [
			_count_type("barl"), infantry])
		_test_step = 3
		get_tree().quit()


func _count_type(type: String) -> int:
	var n := 0
	for u in world.units:
		if u.alive and u.type == type:
			n += 1
	return n


var _test_dog := false


func _run_test_dog() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		var dog: ProtoWorld.Unit = null
		if world.type_ids.has("dog"):
			dog = world.spawn_unit("dog", 0, origin)
		if world.type_ids.has("e1"):
			world.spawn_unit("e1", 1, origin + Vector2i(2, 0))
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(1, 0)) * ProtoWorld.CELL)
		var man: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.player == 1 and u.type == "e1":
				man = u
		if dog != null and man != null:
			world.select_only(dog)
			world.order_attack(man)
		print("T: --test-dog: Hund=%s Schütze=%s" % [dog != null, man != null])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 1:
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_1.png")
		_test_step = 2
	elif _test_step == 2 and tick >= _test_tick + 2:
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_2.png")
		_test_step = 3
	elif _test_step == 3 and tick >= _test_tick + 3:
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_3.png")
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 40:
		var man_alive := false
		for u in world.units:
			if u.player == 1 and u.type == "e1":
				man_alive = u.alive
		print("T%d --test-dog: Sprung beobachtet, Ziel tot: %s" % [tick, not man_alive])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_air := false
var _air_ids: Array = []
var _air_target := 0

var _test_air_player := false
var _ap_step := 0
var _ap_tick := 0
var _ap_heli = null
var _ap_pad = null
var _ap_foe = null
var _ap_shots := 0
var _ap_ammo0 := -1
var _ap_landed_again := false


func _ap_tap_unit(u) -> void:
	world.center_on(u.pos)
	_on_tap(world.world_to_screen(u.pos - Vector2(0.0, u.altitude)))


func _ap_state(u) -> String:
	return "%s Höhe=%.1f Munition=%d/%d gewählt=%s" % [u.type, u.altitude, u.ammo, u.ammo_max, u.selected]


func _run_test_air_player() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	var soviet := world.player_faction() == "soviet"
	var pad_type := "afld" if soviet else "hpad"
	var air_type := "yak" if soviet else "heli"
	if _ap_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 30000)
		var chain: Array = ["powr", "powr", "powr", "dome", "afld"] if soviet \
				else ["powr", "powr", "powr", "dome", "atek", "hpad"]
		var i := 0
		for t in chain:
			if world.type_ids.has(t):
				var b = world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
				if t == pad_type:
					_ap_pad = b
				i += 1

		if world.type_ids.has("powr"):
			_ap_foe = world.call("_add_building", "powr", 1, origin + Vector2i(10, 12))
			world.call("_add_building", "powr", 1, origin + Vector2i(28, 28))
		world.center_on((Vector2(origin) + Vector2(0, 6)) * ProtoWorld.CELL)
		print("T: Platz ", pad_type, " Flieger ", air_type)
		_ap_step = 1
		_ap_tick = tick
	elif _ap_step == 1 and tick >= _ap_tick + 60:

		if world.type_ids.has(air_type):
			world.queue_build(world.type_ids[air_type])
		_ap_step = 2
		_ap_tick = tick
	elif _ap_step == 2:
		for u in world.units:
			if u.alive and u.player == 0 and u.type == air_type:
				_ap_heli = u
				break
		if _ap_heli == null:
			if tick > _ap_tick + 6000:
				print("T: FEHLER kein Flieger gebaut")
				get_tree().quit()
			return
		print("T: aus der Produktion bei Tick ", tick, ": ", _ap_state(_ap_heli))
		_ap_step = 3
		_ap_tick = tick
	elif _ap_step == 3 and tick >= _ap_tick + 60:

		print("T: 60 Ticks später: ", _ap_state(_ap_heli), " (erwartet Höhe 0, volle Munition)")

		_ap_tap_unit(_ap_heli)
		var sel: Array = []
		for u in world.selection:
			sel.append(u.type)
		print("T: Tipp auf den Flieger → Auswahl ", sel)
		_ap_step = 4
		_ap_tick = tick
	elif _ap_step == 4:
		if not _ap_heli.selected:
			print("T: FEHLER Flieger nicht anwählbar — Auswahl ", world.selection.size())
			get_tree().quit()
			return

		_ap_ammo0 = _ap_heli.ammo
		_ap_tap_unit(_ap_foe)
		print("T: Tipp auf ", _ap_foe.type, " → Ziel-HP %.2f, Munition %d" % [_ap_foe.hp, _ap_heli.ammo])
		_ap_step = 5
		_ap_tick = tick
	elif _ap_step == 5:
		world.center_on(_ap_heli.pos)
		if _ap_heli.ammo < _ap_ammo0:
			_ap_shots = _ap_ammo0 - _ap_heli.ammo
		if tick == _ap_tick + 300 or tick == _ap_tick + 900:
			print("T: bei +%d: %s Ziel-HP %.2f" % [tick - _ap_tick, _ap_state(_ap_heli), _ap_foe.hp])

		if (_ap_heli.ammo_max > 0 and _ap_heli.ammo <= 0) or tick >= _ap_tick + 3000:
			print("T: Angriff: %d Schuss, Ziel-HP %.2f, %s" % [_ap_shots, _ap_foe.hp, _ap_state(_ap_heli)])
			if _ap_shots == 0:
				print("T: FEHLER kein Schuss abgegeben")
			_ap_step = 6
			_ap_tick = tick
	elif _ap_step == 6:

		world.center_on(_ap_heli.pos)
		if _ap_heli.altitude <= 0.01 and _ap_heli.ammo >= _ap_heli.ammo_max:
			print("T: nachgeladen bei +%d: %s" % [tick - _ap_tick, _ap_state(_ap_heli)])
			_ap_step = 7
			_ap_tick = tick
		elif tick >= _ap_tick + 3000:
			print("T: FEHLER kein Nachladen: ", _ap_state(_ap_heli))
			_ap_step = 7
			_ap_tick = tick
	elif _ap_step == 7:

		if not _ap_heli.selected:
			world.select_units([_ap_heli])
		world.order_move((Vector2(_test_origin) + Vector2(3, 14)) * ProtoWorld.CELL)
		_ap_step = 8
		_ap_tick = tick
	elif _ap_step == 8 and tick >= _ap_tick + 400:
		print("T: nach dem Bewegen: ", _ap_state(_ap_heli))
		if _ap_pad != null:
			_ap_tap_unit(_ap_heli)
			_ap_tap_unit(_ap_pad)
			var sel2: Array = []
			for u in world.selection:
				sel2.append(u.type)
			print("T: Tipp auf ", _ap_pad.type, " → Auswahl ", sel2)
		_ap_step = 9
		_ap_tick = tick
	elif _ap_step == 9 and tick >= _ap_tick + 600:
		print("T: nach dem Landebefehl: ", _ap_state(_ap_heli))
		print("T: air-player fertig")
		get_tree().quit()


func _run_test_air() -> void:
	var sim = world.sim
	var tick: int = sim.tick()


	var soviet := world.player_faction() == "soviet"
	var heli_type := "yak" if soviet else "heli"
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 30000)

		var chain: Array = ["powr", "powr", "powr", "dome", "afld"] if soviet \
				else ["powr", "powr", "powr", "dome", "atek", "hpad"]
		var i := 0
		for t in chain:
			if world.type_ids.has(t):
				world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
				i += 1
		world.center_on((Vector2(origin) + Vector2(0, 5)) * ProtoWorld.CELL)
		print("T: Flugfeld ", chain[-1], ", Flugzeug ", heli_type)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 200:

		if world.type_ids.has(heli_type):
			sim.queue_build(0, world.type_ids[heli_type])
			sim.queue_build(0, world.type_ids[heli_type])
		else:
			print("T: kein Flugzeugtyp verfügbar")
		var names: Array = []
		for b in sim.buildable(0, 4):
			names.append(world.type_names[b])
		print("T: baubar in der Flugzeug-Queue: ", names)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:

		_air_ids.clear()
		for u in world.units:
			if u.alive and u.player == 0 and u.type == heli_type:
				_air_ids.append(u)
		if _air_ids.size() < 2 and tick < _test_tick + 4000:
			return
		print("T: Flugzeuge gebaut: ", _air_ids.size(), " bei Tick ", tick)

		var target = null
		for u in world.units:
			if u.alive and world.hostile(0, u.player) and world.types[u.type].get("building", false):
				target = u
				break
		if target == null and world.type_ids.has("powr"):
			var o := Vector2i(world.units[0].pos / ProtoWorld.CELL) + Vector2i(8, 8)
			target = world.call("_add_building", "powr", 1, o)


			world.call("_add_building", "powr", 1, o + Vector2i(20, 20))
		if target != null and not _air_ids.is_empty():
			world.select_units(_air_ids)
			world.order_attack(target)
			_air_target = target.id
			print("T: Angriff auf ", target.type, " id=", target.id)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:

		for u in _air_ids:
			if u.alive:
				if world.zoom < ProtoWorld.MAX_ZOOM:
					world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
				world.center_on(u.pos)
				break
		if tick == _test_tick + 200 or tick == _test_tick + 600:
			for u in _air_ids:
				if u.alive:
					print("T: %s Höhe=%.1f Munition=%d/%d" % [u.type, u.altitude, u.ammo, u.ammo_max])

		if _screenshot_path != "" and (tick == _test_tick + 300 or tick == _test_tick + 306):
			var b: PackedFloat32Array = sim.render_buffer(1.0)
			var atlas = world.atlas()
			var frames: Array = []
			for rt in world.types[heli_type].get("rotors", []):
				var lo: int = atlas.frame_index(rt["sprite"], 0)
				var hi: int = lo + int(atlas.sprite_frame_count[rt["sprite"]])
				for i in b.size() / 12:
					var f := int(b[i * 12 + 8])
					if f >= lo and f < hi:
						frames.append(f - lo)
			var shadows := 0
			for i in b.size() / 12:
				if b[i * 12 + 9] < -0.5:
					shadows += 1
			print("T: Rotorframes bei Tick ", tick, ": ", frames, " Schatteninstanzen: ", shadows)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(
				_screenshot_path.get_basename() + ("_a.png" if tick == _test_tick + 300 else "_b.png"))
		if tick >= _test_tick + 700:
			var hp := 1.0
			for u in world.units:
				if u.id == _air_target:
					hp = u.hp
			print("T: Ziel-HP %.2f" % hp)
			_test_step = 4
			_test_tick = tick
			_start_paradrop()
	elif _test_step == 4:

		if _para_plane != null and not _para_plane.alive:
			_para_plane = null
		if _para_plane != null:
			world.center_on(_para_plane.pos)

		if _screenshot_path != "" and tick == _test_tick + 150:
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_para.png")
		if tick < _test_tick + 400:
			return
		var landed := 0
		var floating := 0
		for u in _para_troop:
			if not u.alive:
				continue
			if u.altitude > 0.0:
				floating += 1
			elif world.sim.transport_of(u.id) < 0:
				landed += 1
		print("T: Fallschirme: %d gelandet, %d am Schirm, an Bord %d" % [landed, floating,
			world.sim.cargo_weight(_para_plane.id) if _para_plane != null else 0])
		_test_step = 5
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_naval := false
var _naval_yard = null
var _naval_ships: Array = []
var _naval_sub = null
var _naval_seen := false
var _test_lst := false
var _lst_yard = null
var _lst_boat = null
var _lst_troop: Array = []


func _find_water_site(type: String, from: Vector2i, max_r: int = 60) -> Vector2i:
	if not world.type_ids.has(type):
		return Vector2i(-1, -1)
	var t: Dictionary = world.types[type]
	var rows: PackedStringArray = String(t.get("footprint", "x")).split(" ")
	var fw: int = rows[0].length()
	var fh: int = rows.size()
	for r in range(1, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := from + Vector2i(dx, dy)
				var ok := true
				for y in fh:
					for x in fw:
						if world.terrain_type(c + Vector2i(x, y)) != ProtoWorld.TER_WATER:
							ok = false
				if ok:
					return c
	return Vector2i(-1, -1)


func _find_land_site(type: String, from: Vector2i, max_r: int = 20) -> Vector2i:
	if not world.type_ids.has(type):
		return Vector2i(-1, -1)
	var rows: PackedStringArray = String(world.types[type].get("footprint", "x")).split(" ")
	var fw: int = rows[0].length()
	var fh: int = rows.size()
	for r in range(1, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := from + Vector2i(dx, dy)
				var ok := true
				for y in fh:
					for x in fw:
						var terr: int = world.terrain_type(c + Vector2i(x, y))
						if terr != ProtoWorld.TER_CLEAR and terr != ProtoWorld.TER_ROAD:
							ok = false
				if ok:
					return c
	return Vector2i(-1, -1)


func _base_at_water(site: Vector2i) -> void:
	var shore := _find_land_site("fact", site, 12)
	if shore.x >= 0:
		world.call("_add_building", "fact", 0, shore)
		var powr := _find_land_site("powr", shore, 8)
		if powr.x >= 0:
			world.call("_add_building", "powr", 0, powr)
		print("T: Ufer-Basis: fact ", shore, ", powr ", powr)


func _run_test_naval() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	var soviet := world.player_faction() == "soviet"
	var yard_type := "spen" if soviet else "syrd"
	var boat_type := "ss" if soviet else "pt"
	var hunter_type := "ss" if soviet else "dd"
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 40000)

		var i := 0

		for t in ["powr", "powr", "powr", "dome"]:
			world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
			i += 1
		var site := _find_water_site(yard_type, origin)
		if site.x >= 0:
			_base_at_water(site)
		if _diag:
			var water := _find_water_cell(origin, 1, 60)
			print("T: nächste Wasserzelle ", water, " Abstand ", (water - origin).length() if water.x >= 0 else -1)
			if water.x >= 0 and world.type_ids.has(yard_type):
				for d: Vector2i in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-2, 0)]:
					var c: Vector2i = water + d
					print("T: can_place ", c, " → ", world.sim.can_place(0, world.type_ids[yard_type], c.x, c.y),
						" Terrain ", world.terrain_type(c))

		var res: PackedByteArray = world.sim.can_place(0, world.type_ids[yard_type], site.x, site.y) \
				if world.type_ids.has(yard_type) else PackedByteArray()
		var land := _find_land_site(yard_type, origin, 12)
		var land_res: PackedByteArray = world.sim.can_place(0, world.type_ids[yard_type], land.x, land.y) \
				if land.x >= 0 and world.type_ids.has(yard_type) else PackedByteArray()
		print("T: Werft %s auf Wasser %s → %s, auf Land %s → %s" % [yard_type, site,
			"ja" if res.size() > 0 and res[0] == 1 else "nein", land,
			"ja" if land_res.size() > 0 and land_res[0] == 1 else "nein"])
		if site.x >= 0:
			_naval_yard = world.call("_add_building", yard_type, 0, site)
			world.center_on((Vector2(site) + Vector2(2, 4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 60:
		var names: Array = []
		for b in sim.buildable(0, 5):
			names.append(world.type_names[b])
		print("T: baubar in der Schiffs-Queue: ", names)
		if world.type_ids.has(boat_type):
			sim.queue_build(0, world.type_ids[boat_type])
		if world.type_ids.has(hunter_type):
			sim.queue_build(0, world.type_ids[hunter_type])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:
		_naval_ships.clear()
		for u in world.units:
			if u.alive and u.player == 0 and (u.type == boat_type or u.type == hunter_type):
				_naval_ships.append(u)
		if _naval_ships.size() < 2 and tick < _test_tick + 4000:
			return
		var cells: Array = []
		for u in _naval_ships:
			cells.append(Vector2i(u.pos / ProtoWorld.CELL))
		print("T: Schiffe gebaut: ", _naval_ships.size(), " bei Tick ", tick, " Zellen ", cells)

		var lz := Vector2i(_naval_yard.pos / ProtoWorld.CELL) if _naval_yard != null else _test_origin
		var spot := _find_water_cell(lz, 12)
		if spot.x >= 0 and world.type_ids.has("ss"):
			_naval_sub = world.spawn_unit("ss", 1, spot)
			print("T: gegnerisches U-Boot bei ", spot)
		if _naval_sub != null and not _naval_ships.is_empty():
			world.select_units(_naval_ships)
			world.order_attack(_naval_sub)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:

		for u in _naval_ships:
			if u.alive:
				world.center_on(u.pos)
				break


		if tick == _test_tick + 100 and _naval_sub != null:
			print("T: U-Boot getaucht — sichtbar=%s HP=%.2f" % [str(_naval_sub.visible), _naval_sub.hp])
		if _naval_sub != null and _naval_sub.visible and not _naval_seen:
			_naval_seen = true
			print("T: U-Boot aufgedeckt bei Tick ", tick, " HP %.2f" % _naval_sub.hp)
		if tick < _test_tick + 900:
			return
		var alive := 0
		for u in _naval_ships:
			if u.alive:
				alive += 1
		print("T: Marine fertig — Schiffe am Leben %d, U-Boot HP %.2f (lebt: %s)" % [
			alive, _naval_sub.hp if _naval_sub != null else -1.0,
			str(_naval_sub != null and _naval_sub.alive)])
		_test_step = 4
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _run_test_lst() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	var soviet := world.player_faction() == "soviet"
	var yard_type := "spen" if soviet else "syrd"
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 20000)
		var i := 0
		for t in ["powr", "powr", "powr"]:
			world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
			i += 1
		var site := _find_water_site(yard_type, origin)
		if site.x >= 0:
			_base_at_water(site)
			_lst_yard = world.call("_add_building", yard_type, 0, site)
			world.center_on((Vector2(site) + Vector2(2, 4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 60:
		if world.type_ids.has("lst"):
			sim.queue_build(0, world.type_ids["lst"])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:
		if _lst_boat == null:
			for u in world.units:
				if u.alive and u.player == 0 and u.type == "lst":
					_lst_boat = u
					break
		if _lst_boat == null and tick < _test_tick + 2000:
			return
		if _lst_boat == null:
			print("T: Landungsboot nicht gebaut — Abbruch")
			_test_step = 6
			_test_tick = tick
			return
		print("T: Landungsboot gebaut bei Tick ", tick, " Zelle ", Vector2i(_lst_boat.pos / ProtoWorld.CELL))
		world.center_on(_lst_boat.pos)


		var shore := Vector2i(_lst_boat.pos / ProtoWorld.CELL)
		for dx in range(3):
			var e = world.spawn_unit("e1", 0, shore + Vector2i(-4 - dx, -2))
			if e != null:
				_lst_troop.append(e)
		if world.type_ids.has("2tnk"):
			var tnk = world.spawn_unit("2tnk", 0, shore + Vector2i(-4, 2))
			if tnk != null:
				_lst_troop.append(tnk)
		print("T: ", _lst_troop.size(), " Passagiere an Land gesetzt")
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 20:

		world.select_units(_lst_troop)
		print("T: Einsteigen befohlen: ", world.order_enter_transport(_lst_boat))
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4:
		var weight: int = sim.cargo_weight(_lst_boat.id)
		if weight < _lst_troop.size() and tick < _test_tick + 1500:
			return
		print("T: an Bord ", weight, "/", _lst_troop.size(), " bei Tick ", tick,
			" (Boot bei ", Vector2i(_lst_boat.pos / ProtoWorld.CELL), ")")

		world.select_only(_lst_boat)
		var far := _find_water_cell(Vector2i(_lst_boat.pos / ProtoWorld.CELL), 10, 30)
		if far.x >= 0:
			world.order_move((Vector2(far) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5 and tick >= _test_tick + 300:

		var shore := _find_land_neighbor(Vector2i(_lst_boat.pos / ProtoWorld.CELL))
		if shore.x >= 0:
			world.order_move((Vector2(shore) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 55
		_test_tick = tick
	elif _test_step == 55 and tick >= _test_tick + 400:
		world.select_only(_lst_boat)
		print("T: Entladen befohlen: ", world.unload_selected())
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 250:
		var out := 0
		for u in _lst_troop:
			if u.alive and sim.transport_of(u.id) < 0:
				out += 1
		print("T: ausgestiegen ", out, " von ", _lst_troop.size(), ", an Bord ", sim.cargo_weight(_lst_boat.id))

		var reboarded := PackedInt32Array()
		for u in _lst_troop:
			if u.alive and sim.transport_of(u.id) < 0:
				reboarded.append(u.id)
		if reboarded.size() > 0 and sim.has_method("order_enter_transport"):
			sim.order_enter_transport(reboarded, _lst_boat.id)
		_test_step = 7
		_test_tick = tick
	elif _test_step == 7 and tick >= _test_tick + 400:
		var loaded_again: int = sim.cargo_weight(_lst_boat.id)
		sim.destroy(_lst_boat.id)
		_test_step = 8
		_test_tick = tick
		_test_origin.x = loaded_again
	elif _test_step == 8 and tick >= _test_tick + 20:
		var dead := 0
		for u in _lst_troop:
			if not u.alive:
				dead += 1
		print("T: Boot mit ", _test_origin.x, " Passagieren zerstört — ", dead, " von ", _lst_troop.size(), " tot")
		print("T: LST fertig")
		_test_step = 9
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _find_land_neighbor(from: Vector2i) -> Vector2i:
	for r in range(1, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := from + Vector2i(dx, dy)
				var t := world.terrain_type(c)
				if t != ProtoWorld.TER_WATER and t != ProtoWorld.TER_ROCK:
					return c
	return Vector2i(-1, -1)


func _find_water_cell(from: Vector2i, min_r: int = 1, max_r: int = 40) -> Vector2i:
	for r in range(min_r, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := from + Vector2i(dx, dy)
				if world.terrain_type(c) == ProtoWorld.TER_WATER:
					return c
	return Vector2i(-1, -1)


var _para_plane = null
var _para_troop: Array = []


func _start_paradrop() -> void:


	var lz := _test_origin + Vector2i(0, 10)
	lz.x = clampi(lz.x, 22, world.map_w - 23)
	lz.y = clampi(lz.y, 2, world.map_h - 3)
	var entry := Vector2i(lz.x - 20, lz.y)
	_para_plane = world.spawn_unit("badr", 0, entry, 768, 100, true)
	if _para_plane == null:
		print("T: kein Badger verfügbar")
		return
	for i in 5:
		var e = world.spawn_unit("e1", 0, entry)
		if e != null and world.sim.load_passenger(_para_plane.id, e.id):
			_para_troop.append(e)
	world.sim.order_paradrop(_para_plane.id, lz.x, lz.y)
	world.order_move_ids(PackedInt32Array([_para_plane.id]), Vector2i(lz.x + 20, lz.y))
	print("T: Badger mit ", _para_troop.size(), " Mann, Landezone ", lz, " Start ", entry,
		" Höhe ", world.sim.air_altitude(_para_plane.id))


var _test_cargo := false
var _cargo_apc = null
var _cargo_troop: Array = []


func _run_test_cargo() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		_cargo_apc = world.spawn_unit("apc", 0, origin + Vector2i(2, 2))
		for i in 5:
			var e = world.spawn_unit("e1", 0, origin + Vector2i(5 + i, 5))
			if e != null:
				_cargo_troop.append(e)
		world.center_on((Vector2(origin) + Vector2(3, 3)) * ProtoWorld.CELL)
		print("T: Transporter ", "da" if _cargo_apc != null else "fehlt", ", Infanterie ", _cargo_troop.size())
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 20:
		world.select_units(_cargo_troop)
		print("T: Einsteigen befohlen: ", world.order_enter_transport(_cargo_apc))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 400:
		print("T: an Bord ", sim.cargo_weight(_cargo_apc.id), " Pips ", _cargo_apc.passengers, "/", _cargo_apc.cargo_max)
		world.select_only(_cargo_apc)
		world.order_move((Vector2(_test_origin) + Vector2(12, 12)) * ProtoWorld.CELL)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 400:
		print("T: Entladen befohlen: ", world.unload_selected())
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 200:
		var out := 0
		for e in _cargo_troop:
			if e.alive and sim.transport_of(e.id) < 0:
				out += 1
		print("T: ausgestiegen ", out, " von ", _cargo_troop.size(), ", an Bord ", sim.cargo_weight(_cargo_apc.id))
		_test_step = 5
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _run_test_defense() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		var i := 0
		for t in ["gun", "pbox", "hbox", "tsla", "ftur", "agun", "powr"]:
			if world.type_ids.has(t):
				var u = world.call("_add_building", t, 0, origin + Vector2i(-3 + i * 2, 4))
				print("T: ", t, " id=", u.id)
				i += 1
		world.center_on((Vector2(origin) + Vector2(2, 4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 120:
		_test_step = 2
		var atlas = world.atlas()
		for t in ["gun", "gunmake", "agun", "agunmake", "powr", "powrmake", "pbox", "tsla"]:
			print("T: atlas ", t, " first=", atlas.frame_index(t, 0) if atlas.sprite_frame_count.has(t) else -1, " n=", atlas.sprite_frame_count.get(t, 0))
		for t in ["gun", "agun", "powr", "pbox"]:
			if not world.types.has(t):
				continue
			var d: Dictionary = world.types[t]
			print("T: type ", t, " turret_start=", d.get("turret_start"), " make=", d.get("make"), " damaged=", d.get("damaged_frame"), " idle_len=", d.get("idle_len"))
		var b: PackedFloat32Array = sim.render_buffer(1.0)
		for i in b.size() / 12:
			var k := i * 12
			print("T: inst ", i, " frame=", b[k + 8], " pal=", b[k + 9], " at=", Vector2(b[k + 3], b[k + 7]))
		var st: PackedFloat32Array = sim.render_state(1.0)
		for i in st.size() / ProtoWorld.RENDER_STRIDE:
			var k := i * ProtoWorld.RENDER_STRIDE
			if st[k] >= 129:
				print("T: actor id=", st[k], " type=", world.type_names[int(st[k + 1])], " alive=", st[k + 7], " flags=", st[k + 11], " at=", Vector2(st[k + 3], st[k + 4]))
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _run_test_ui() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		var i := 0
		for t in ["fact", "powr", "proc"]:
			if world.type_ids.has(t):
				world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
				i += 1
		world.center_on((Vector2(origin) + Vector2(0, 4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 140:
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "fact":
				world.select_only(u)
		_show_selection_info()
		var args := OS.get_cmdline_user_args()
		var tk := args.find("--test-tab")
		var tab := clampi(int(args[tk + 1]), 0, BuildBar.KIND_QUEUES.size() - 1) if tk >= 0 and tk + 1 < args.size() else 0
		build_bar.select_queue(BuildBar.KIND_QUEUES[tab])
		_toast(tr("test.build_bar_run"))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 20:
		var args2 := OS.get_cmdline_user_args()
		var mk := args2.find("--test-menu")
		if mk >= 0 and mk + 1 < args2.size():
			match args2[mk + 1]:
				"pause": _toggle_menu(true)
				"save": _toggle_menu(true); _show_slots(true)
				"load": _toggle_menu(true); _show_slots(false)
				"deliver":

					var harv: ProtoWorld.Unit = null
					var proc: ProtoWorld.Unit = null


					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].get("refinery", false):
							world.spawn_unit("harv", 0, Vector2i(u.pos / ProtoWorld.CELL) + Vector2i(4, 3))
							break
					for u in world.units:
						if not u.alive or u.player != 0:
							continue
						if harv == null and world.types[u.type].get("harvester", false):
							harv = u
						if proc == null and world.types[u.type].get("refinery", false):
							proc = u
					if harv != null and proc != null:
						world.select_only(harv)
						world.center_on(proc.pos)
						print("T: Harvester Ladung %.2f → Raffinerie: %s (order_deliver in der Brücke: %s)" % [
							harv.cargo, world.order_deliver(proc), world.sim.has_method("order_deliver")])
					else:
						var own: Array = []
						for u in world.units:
							if u.alive and u.player == 0:
								own.append(u.type)
						print("T: kein Harvester/keine Raffinerie — eigene Actors: %s" % [own])
				"c4":


					var o := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							o = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var b1 = world.call("_add_building", "barr", 1, o + Vector2i(-6, -4))
					var b2 = world.call("_add_building", "barr", 1, o + Vector2i(2, -4))
					var tanya = world.spawn_unit("e7", 0, o + Vector2i(-2, 0))

					var barrel = world.call("_add_building", "barl", ProtoWorld.PLAYER_NEUTRAL, o + Vector2i(-2, -3))
					if barrel != null:
						print("T: Fass anvisierbar=%s (Baum anvisierbar=%s)" % [world.pickable(barrel),
							world.pickable(_find_decoration())])
					if tanya != null:
						world.select_only(tanya)
						world.center_on(tanya.pos)
						if b2 != null:
							print("T: C4 auf %s → „%s\"" % [b2.type, tr(world.order_enter(b2))])


						_test_frame_extra = 260
				"platzieren-ready":

					var pid: int = world.type_ids.get("powr", -1)
					if pid >= 0:
						world.queue_build(pid)
						for _t in 400:
							world.sim.step()
						build_bar.visible = false
						build_bar.call("_rebuild")
						build_bar.visible = true
						build_bar.select_queue(0)
						build_bar.call("_rebuild")
						print("T: Warteschlange=%s → Platzierungsmodus=%s" % [
							world.sim.queue_state(0, 0).slice(0, 3), world.placing_type >= 0])
				"platzieren-abbruch": _test_place_cancel()
				"oel":

					var o2 := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							o2 = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var oil = world.call("_add_building", "oilb", 0, o2 + Vector2i(3, 3))
					if oil != null:
						world.center_on(oil.pos)
						var iv: int = int(world.types["oilb"].get("cash_interval", 375))
						print("T: Ölturm gesetzt, Intervall %d Ticks, Betrag %d" % [
							iv, int(world.types["oilb"].get("cash_amount", 0))])


						for _t in iv:
							world.sim.step()
						_test_frame_extra = 30
				"silo", "silo-voll":


					var so3 := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							so3 = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var silo = world.call("_add_building", "silo", 0, so3 + Vector2i(5, 3))
					if silo != null:
						world.center_on(silo.pos)
						world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
						var cap: int = world.sim.storage_capacity(0)
						var target: int = 0 if args2[mk + 1] == "silo" else int(cap * 0.9)
						world.sim.set_resources(0, target)
						world.select_only(silo)
						print("T: %s: Konto %d/%d (Kapazität mit vorhandener Raffinerie)" % [
							args2[mk + 1], world.sim.resources_stored(0), cap])
					else:
						print("T: Silo nicht gefunden (type_ids fehlt 'silo'?)")
				"deploy":

					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].has("transforms") \
								and not world.types[u.type].get("building", false):
							world.select_only(u)
							world.center_on(u.pos)
							_show_selection_info()
							print("T: MCV gewählt: %s, ausklappbar hier: %s" % [
								u.type, world.sim.can_deploy(u.id)])
							break
					_test_frame_extra = 30
				"deploy-blockiert":

					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].has("transforms") \
								and not world.types[u.type].get("building", false):
							var mc2 := Vector2i(u.pos / ProtoWorld.CELL)
							world.call("_add_building", "powr", 0, mc2 + Vector2i(1, 0))
							world.select_only(u)
							world.center_on(u.pos)
							print("T: MCV blockiert, ausklappbar hier: %s" % world.sim.can_deploy(u.id))
							break
					_test_frame_extra = 30
				"deploy-gemischt":

					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].has("transforms") \
								and not world.types[u.type].get("building", false):
							var mc3 := Vector2i(u.pos / ProtoWorld.CELL)
							var tank := world.spawn_unit("2tnk", 0, mc3 + Vector2i(2, 0))
							world.select_only(u)
							if tank != null:
								world.additive_select = true
								world.select_only(tank)
								world.additive_select = false
							world.center_on(u.pos)
							print("T: Auswahl: %d Einheiten (gemischt)" % world.selection.size())
							break
					_test_frame_extra = 30
				"kiste":


					var mob: ProtoWorld.Unit = null
					for u in world.units:
						if u.alive and u.player == 0 and not world.types[u.type].get("building", false):
							mob = u
							break
					if mob != null:
						var mc := Vector2i(mob.pos / ProtoWorld.CELL)
						var neutral: int = int(world.player_map.get("Neutral", 1))
						var crate_units: Array[ProtoWorld.Unit] = []
						for i in 5:
							var c := world.spawn_unit("crate", neutral, mc + Vector2i(2 + i, 0))
							if c != null:
								crate_units.append(c)
						world.select_only(mob)
						world.center_on(mob.pos)
						var before: int = world.sim.credits(0)
						if not crate_units.is_empty():
							var target_crate := crate_units[0]
							print("T: Kiste antippbar=%s (muss false sein)" % world.pickable(target_crate))
							_on_tap(world.world_to_screen(target_crate.pos))
							print("T: nach Kiste-Tipp: %s, Ziel=%s" % [_last_gesture, mob.goal / ProtoWorld.CELL])
						print("T: Kisten gelegt: %d, Konto vorher %d" % [world.sim.crate_count(), before])
						_test_frame_extra = 700
				"alle-kampf":


					var oa := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							oa = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var e1u := world.spawn_unit("e1", 0, oa + Vector2i(1, 0))
					var harvu := world.spawn_unit("harv", 0, oa + Vector2i(2, 0))
					var e6u := world.spawn_unit("e6", 0, oa + Vector2i(3, 0)) if world.type_ids.has("e6") else null
					var n_all := world.select_all_units()
					var types_selected: Array[String] = []
					for u in world.selection:
						types_selected.append(u.type)
					print("T: alle-kampf: %d gewählt, Typen=%s (harv/e6 dürfen nicht dabei sein)" % [n_all, types_selected])
					print("T: select_priority e1=%d harv=%d e6=%s" % [
						world.types["e1"].get("select_priority", 10), world.types["harv"].get("select_priority", 10),
						str(world.types["e6"].get("select_priority", 10)) if e6u != null else "n/a"])
					world.center_on((Vector2(oa) + Vector2(1.5, 0.5)) * ProtoWorld.CELL)
				"reiter":


					build_bar.visible = true
					build_bar.call("_rebuild")
					print("T: Reiter (nur Bauhof): %s, aktiv=%d" % [_visible_tab_kinds(), build_bar.kind])
					var barr_type := "barr" if world.type_ids.has("barr") else "tent"
					var ro := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0 and u.type == "fact":
							ro = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var barr = world.call("_add_building", barr_type, 0, ro + Vector2i(0, 6))
					build_bar.call("_rebuild")
					print("T: Reiter (+Kaserne): %s" % [_visible_tab_kinds()])
					build_bar.select_queue(1)
					build_bar.call("_rebuild")
					if barr != null:
						world.sim.destroy(barr.id)
						world.call("_refresh_units_fast")
					build_bar.call("_rebuild")
					print("T: Reiter (Kaserne verloren): %s, aktiv=%d (darf nicht mehr 1 sein)" % [
						_visible_tab_kinds(), build_bar.kind])
				"reiter-voll":


					var rv := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0 and u.type == "fact":
							rv = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var rv_types := ["tent" if world.type_ids.has("tent") else "barr", "weap", "hpad", "syrd"]
					var rv_i := 0
					for t in rv_types:
						if world.type_ids.has(t):
							world.call("_add_building", t, 0, rv + Vector2i(-6 + rv_i * 4, -6))
							rv_i += 1
					build_bar.visible = true
					build_bar.call("_rebuild")
					build_bar.select_queue(0)
					build_bar.call("_rebuild")
					print("T: Reiter (alle Gebäude): %s" % [_visible_tab_kinds()])
					world.center_on(Vector2(rv) * ProtoWorld.CELL)
				"shroud":


					var vis := world.vis_map()
					var c0 := 0
					var c1 := 0
					var c2 := 0
					for b in vis:
						if b == 0: c0 += 1
						elif b == 1: c1 += 1
						else: c2 += 1
					print("T: Shroud unerkundet=%d erkundet=%d sichtbar=%d (explored_map=%s fog=%s)" % [
						c0, c1, c2, ProtoWorld.next_explored_map, ProtoWorld.next_fog])
				"strom", "strom-an":


					var so := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							so = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var k := 0
					for t in ["dome", "tsla"]:
						if world.type_ids.has(t):
							world.call("_add_building", t, 0, so + Vector2i(5 + k * 4, 1))
							k += 1
					world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
					world.center_on((Vector2(so) + Vector2(7.0, 2.5)) * ProtoWorld.CELL)
					_test_frame_extra = 200
					if args2[mk + 1] == "strom":

						for u in world.units:
							if u.alive and u.player == 0 and int(world.types[u.type].get("power", 0)) > 0:
								world.sim.destroy(u.id)
					else:

						for n in 2:
							world.call("_add_building", "apwr", 0, so + Vector2i(-4 + n * 3, 7))
					print("T: Strom %d/%d" % [world.sim.power_provided(0), world.sim.power_drained(0)])
				"reparatur":

					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].get("building", false):
							if world.sim.has_method("set_health"):
								world.sim.set_health(u.id, int(world.types[u.type]["hp"] * 0.5))
							print("T: Reparatur %s → %s" % [u.type, world.toggle_repair_unit(u)])
							break
				"reparieren-abbruch":


					var own_building: ProtoWorld.Unit = null
					var own_unit: ProtoWorld.Unit = null
					for u in world.units:
						if not u.alive or u.player != 0:
							continue
						if own_building == null and world.types[u.type].get("building", false):
							own_building = u
						elif own_unit == null and not world.types[u.type].get("building", false):
							own_unit = u
					var ra_origin := Vector2i((own_building.pos if own_building != null else Vector2.ZERO) / ProtoWorld.CELL)
					if own_unit == null:
						own_unit = world.spawn_unit("e1", 0, ra_origin + Vector2i(6, 0))


					world.sim.set_enemy(0, 1, true)
					world.sim.set_enemy(1, 0, true)
					var enemy := world.spawn_unit("e1", 1, ra_origin + Vector2i(9, 0))
					if own_building != null and own_unit != null:
						if world.sim.has_method("set_health"):
							world.sim.set_health(own_building.id, int(world.types[own_building.type]["hp"] * 0.5))
						world.center_on(own_building.pos)
						_set_click_mode("repair")
						_on_tap(world.world_to_screen(own_building.pos))
						print("T: nach Gebäude-Tipp: Modus=%s (muss 'repair' bleiben)" % _click_mode)
						_on_tap(world.world_to_screen(own_unit.pos))
						print("T: nach Einheit-Tipp: Modus=%s (muss leer sein), Einheit gewählt=%s" % [
							_click_mode, own_unit.selected])
						if enemy != null:


							world.sim.reveal(0, ra_origin.x + 9, ra_origin.y, 3)
							_on_tap(world.world_to_screen(enemy.pos))
							print("T: nach Gegner-Tipp: %s" % _last_gesture)
					else:
						print("T: reparieren-abbruch — eigenes Gebäude oder Einheit fehlt")
				"platzieren":

					if world.type_ids.has("gun"):
						_begin_placement(world.type_ids["gun"])
						world.move_placement(world.visible_world_rect().get_center())
						print("T: Reichweite gun=%.0f px, Bauradius fact=%.0f px" % [
							world.weapon_range_px("gun"), world.base_range_px("fact")])
				"superwaffen":


					var swo := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							swo = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var swi := 0
					for t in ["iron", "pdox", "mslo", "atek"]:
						if world.type_ids.has(t):
							world.call("_add_building", t, 0, swo + Vector2i(-8 + swi * 6, 6))
							swi += 1
					print("T: Superwaffen gebaut: %d" % swi)
				"superwaffe1":


					var so1 := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							so1 = Vector2i(u.pos / ProtoWorld.CELL)
							break
					if world.type_ids.has("iron"):
						world.call("_add_building", "iron", 0, so1 + Vector2i(-5, 6))
						print("T: Superwaffe (nur Eiserner Vorhang) gebaut")
				"optionen":
					_toggle_menu(true)
					_show_options()
				"help": _show_gesture_help(false)
				"hilfe":


					build_bar.visible = true
					build_bar.call("_rebuild")
					HudTheme.show_help_popup($UI, "help.btn.sell", _cmd_buttons["sell"].get_global_rect())
					print("T: Hilfe-Popup Verkauf offen=%s" % $UI.has_node("HelpPopupOverlay"))
				"ziele": _show_objectives()
				"radial": radial.open(get_viewport().get_visible_rect().size / 2.0, _unit_items())
				"win": world.sim.set_win_state(0, 1)
				"lose":

					for u in world.units:
						if u.alive and u.player == 0:
							world.sim.destroy(u.id)
				"input": _test_input_double()
				"halt":
					world.queue_build(world.type_ids["powr"])
					world.sim.pause_build(0, 0, true)
					build_bar.call("_rebuild")
				"hold":

					world.queue_build(world.type_ids["powr"])
					build_bar.call("_rebuild")
					for s2 in build_bar._slots:
						if s2.visible and s2.count > 0:
							build_bar.call("_on_hold", s2)
							break
				"bauinfo":


					build_bar.visible = true
					build_bar.call("_rebuild")
					for s3 in build_bar._slots:
						if s3.visible and s3.type_id == world.type_ids.get("apwr", -1):
							build_bar.call("_on_hold", s3)
							print("T: bauinfo apwr: Preis=%d Strom=%d (muss > 0 sein)" % [
								world.sim.type_cost(s3.type_id), world.types["apwr"].get("power", 0)])
							break
				"info", "info-gebaeude", "info-gegner":


					var io := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							io = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var target: ProtoWorld.Unit = null
					match args2[mk + 1]:
						"info": target = world.spawn_unit("1tnk", 0, io + Vector2i(3, 3))
						"info-gebaeude": target = world.call("_add_building", "agun", 0, io + Vector2i(6, 3))
						"info-gegner": target = world.spawn_unit("3tnk", 1, io + Vector2i(-3, 3))
					if target != null:
						world.center_on(target.pos)
						_on_long_press(world.world_to_screen(target.pos))
						print("T: %s: Karte offen=%s Radial offen=%s Text=%s" % [args2[mk + 1],
							_info_card != null, radial.visible, ActorInfo.description(target.type)])
					else:
						print("T: %s: Actor nicht gespawnt (type_ids fehlt?)" % args2[mk + 1])
		if _test_ready != "":
			_run_test_ready()
		if args2.has("--test-orders"):

			world.select_all_units()
			var p := get_viewport().get_visible_rect().size / 2.0
			_on_tap(p)
			_on_radial("Angriffszug")
			_on_tap(p + Vector2(40, 40))
			_on_radial("Bewegen")
			_on_tap(p + Vector2(-40, 40))
			_on_radial("Ernten")
			_on_tap(p)
			_on_radial("Zwangsfeuer")
			_on_tap(p + Vector2(60, 0))
			_on_radial("Bewachen")
			_on_tap(p)
			_on_radial("Stopp")
			_on_radial("Leeren")
			_set_click_mode("repair")
			_on_tap(p)
			_set_click_mode("repair")
			_cmd_buttons["add"].button_pressed = true
			world.additive_select = true
			_on_tap(p)
			world.additive_select = false
			_jump_to_base()
			_zoom_step(1.25)
			_on_under_attack(world.selection_center())
			print("T: Befehlswege ok")
		if args2.has("--test-scroll"):
			build_bar.call("_set_scroll", 9999.0)
		if args2.has("--test-locked"):
			for s in build_bar._slots:
				if s.visible and not s.available:
					build_bar.call("_on_tap", s)
					break
		_test_step = 3
		_test_frame = Engine.get_process_frames()
	elif _test_step == 3 and Engine.get_process_frames() >= _test_frame + 20 + _test_frame_extra:
		var marked := 0
		var barr_alive := 0
		var dark: Array = []
		for u in world.units:
			if u.alive and u.demolishing:
				marked += 1
			if u.alive and u.type == "barr":
				barr_alive += 1
			if u.alive and u.unpowered:
				dark.append(u.type)
		print("T: gelegte Ladungen: %d (Kasernen am Leben: %d), ohne Strom: %s" % [marked, barr_alive, dark])
		if OS.get_cmdline_user_args().has("kiste"):
			var kn := 0
			for u in world.units:
				if u.type == "crate" and u.alive:
					kn += 1
			print("T: Kisten übrig %d (units: %d), Konto %d, aufgestiegene Zahlen %d" % [
				world.sim.crate_count(), kn, world.sim.credits(0), world.floats_shown])


		var shown: Array = []
		for s3 in build_bar._slots:
			if s3.visible and s3.type_id >= 0:
				shown.append(world.type_names[s3.type_id])
		print("T: Bauleiste (%s, Reiter %d): %s" % [world.player_faction(), build_bar.kind, shown])
		if _screenshot_path != "":
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		if OS.get_cmdline_user_args().has("deploy") and not world.selection.is_empty():

			var mcv: ProtoWorld.Unit = world.selection[0]
			var facts0 := 0
			for u in world.units:
				if u.alive and u.player == 0 and u.type == "fact":
					facts0 += 1
			_on_tap(world.world_to_screen(mcv.pos))
			for _t in 120:
				world.sim.step()
			var snap2: PackedFloat32Array = world.sim.render_state(1.0)
			world.call("_sync_new_actors", snap2)
			world.call("_refresh_units_fast", snap2)
			var facts := 0
			for u in world.units:
				if u.alive and u.player == 0 and u.type == "fact":
					facts += 1
			print("T: nach dem zweiten Tippen — Bauhöfe %d → %d, MCV am Leben: %s" % [
				facts0, facts, mcv.alive])
		get_tree().quit()


func _run_test_armaments() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		for pair in [["4tnk", 0, Vector2i(0, 0)], ["e1", 1, Vector2i(4, 0)],
					["4tnk", 0, Vector2i(0, 8)], ["2tnk", 1, Vector2i(4, 8)]]:
			if world.type_ids.has(pair[0]):
				world.spawn_unit(pair[0], pair[1], origin + pair[2])
		world.center_on((Vector2(origin) + Vector2(2, 4)) * ProtoWorld.CELL)
		for n in ["4tnk", "e3", "ftrk"]:
			var t: Dictionary = world.types.get(n, {})
			print("T: %s Waffen: %s / %s" % [n, t.get("weapon", "-"), t.get("weapon_secondary", "-")])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 5:
		for u in world.units:
			if u.alive and u.player == 1:
				_arm_hp[u.id] = u.hp
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 250:
		for u in world.units:
			if u.player != 1 or not _arm_hp.has(u.id):
				continue
			var now: float = u.hp if u.alive else 0.0
			print("T: %s Schaden %.0f %% der Trefferpunkte" % [u.type, (float(_arm_hp[u.id]) - now) * 100.0])
		_test_step = 3
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _visible_tab_kinds() -> Array[int]:
	var out: Array[int] = []
	for i in BuildBar.KIND_QUEUES.size():
		if build_bar._tabs[i].visible:
			out.append(BuildBar.KIND_QUEUES[i])
	return out


func _test_input_double() -> void:

	if world.type_ids.has("dome"):
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		world.call("_add_building", "dome", 0, origin + Vector2i(4, 4))
		minimap.call("_process", 0.0)
	var n := [0, 0]
	minimap.navigate.connect(func(_p): n[0] += 1)
	minimap.focus_base.connect(func(): n[1] += 1)
	var pos := minimap.global_position + minimap.size / 2.0
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
	print("T: Minimap-Tipp → navigate=%d focus_base=%d (erwartet 1 / 0)" % [n[0], n[1]])


func _test_place_cancel() -> void:
	var pid: int = world.type_ids.get("powr", -1)
	if pid < 0:
		print("T: --test-menu platzieren-abbruch: Typ 'powr' fehlt")
		get_tree().quit()
		return
	world.queue_build(pid)
	for _t in 400:
		world.sim.step()

	_begin_placement(pid)
	await get_tree().process_frame
	await get_tree().process_frame
	var was_placing: bool = world.placing_type >= 0
	var before: PackedInt32Array = world.sim.queue_state(0, 0)
	var pos := place_cancel.global_position + place_cancel.size / 2.0
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
	var still_placing: bool = world.placing_type >= 0
	var after: PackedInt32Array = world.sim.queue_state(0, 0)
	var ok := was_placing and not still_placing and after.size() >= 3
	print("T: --test-menu platzieren-abbruch: vor Tipp Platzierung=%s Queue=%s, nach \"Abbrechen\" Platzierung=%s Queue=%s — %s" % [
		was_placing, before.slice(0, 3), still_placing, after.slice(0, 3), "OK" if ok else "FEHLER"])
	get_tree().quit()


func _find_button_by_text(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and c.text == text:
			return c
		var found := _find_button_by_text(c, text)
		if found != null:
			return found
	return null


func _run_test_speed_ui() -> void:
	while world.sim == null:
		await get_tree().process_frame
	GameSpeed.set_index(GameSpeed.DEFAULT_INDEX)
	var window := 5.0
	var t0 := Time.get_ticks_msec() / 1000.0
	var tick0 := int(world.sim.tick())
	while Time.get_ticks_msec() / 1000.0 - t0 < window:
		await get_tree().process_frame
	var dt0 := Time.get_ticks_msec() / 1000.0 - t0
	var dticks0: int = int(world.sim.tick()) - tick0
	print("T: --test-speed-ui vorher Index=%d (%d ms) -> %.1f Ticks/s (%.2fs, %d Ticks)" % [
		GameSpeed.index(), GameSpeed.TIMESTEPS[GameSpeed.index()], dticks0 / dt0, dt0, dticks0])


	_toggle_menu(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var plus := _find_button_by_text(_menu_panel, "+")
	if plus == null:
		print("T: --test-speed-ui: Plus-Knopf im Pausenmenü nicht gefunden")
		get_tree().quit()
		return
	for _n in 2:
		var pos := plus.global_position + plus.size / 2.0
		for pressed in [true, false]:
			var ev := InputEventScreenTouch.new()
			ev.index = 0
			ev.position = pos
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await get_tree().process_frame
			await get_tree().process_frame
	var index_after_taps := GameSpeed.index()
	_toggle_menu(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var t1 := Time.get_ticks_msec() / 1000.0
	var tick1 := int(world.sim.tick())
	while Time.get_ticks_msec() / 1000.0 - t1 < window:
		await get_tree().process_frame
	var dt1 := Time.get_ticks_msec() / 1000.0 - t1
	var dticks1: int = int(world.sim.tick()) - tick1
	var rate1 := dticks1 / dt1
	print("T: --test-speed-ui nach 2x Tipp auf Plus Index=%d (Knopf setzte %d) (%d ms) -> %.1f Ticks/s (%.2fs, %d Ticks) - erwartet >= 45 - %s" % [
		GameSpeed.index(), index_after_taps, GameSpeed.TIMESTEPS[GameSpeed.index()], rate1, dt1, dticks1,
		"OK" if rate1 >= 45.0 else "FEHLER"])
	get_tree().quit()


const LAYOUT_MATRIX := [
	[1096, 2560, 420], [2560, 1096, 420],
	[1080, 2400, 440], [1080, 1920, 420], [720, 1600, 320],
	[1600, 2560, 320], [2560, 1600, 320],
]


func _test_layout_info_unit() -> ProtoWorld.Unit:
	if world.type_ids.has("agun"):
		return world.call("_add_building", "agun", 0, Vector2i(10, 10))
	for u in world.units:
		if u.alive:
			return u
	return null


func _run_test_layout() -> void:
	var total := 0
	var info_unit := _test_layout_info_unit()
	for e in LAYOUT_MATRIX:
		DisplayServer.window_set_size(Vector2i(e[0], e[1]))
		Dp.set_forced_dpi(float(e[2]))
		Dp.set_ui_scale(1.0)
		await get_tree().process_frame
		_layout_ui()
		for what in ["hud", "pause", "optionen", "ziele", "help", "info"]:
			match what:
				"pause": _toggle_menu(true)
				"optionen": _show_options()
				"ziele": _show_objectives()
				"help": _show_gesture_help(false)
				"info":
					if info_unit != null:
						world.center_on(info_unit.pos)
						_show_info_card(info_unit, get_viewport().get_visible_rect().size / 2.0)
			for _i in 4:
				await get_tree().process_frame
			var real := DisplayServer.window_get_size()
			var tag := "%s %dx%d@%d" % [what, real.x, real.y, e[2]]
			var v := LayoutCheck.violations($UI, Dp.safe_rect(), tag)
			for line in v:
				print(line)
			total += v.size()


			var ov := LayoutCheck.overlap_violations($UI, tag)
			for line in ov:
				print(line)
			total += ov.size()


			if what == "hud" and _map_rect.size.x > 0.0:
				var mv := LayoutCheck.map_violations($UI, _map_rect, tag)
				for line in mv:
					print(line)
				total += mv.size()
			for n in get_tree().get_nodes_in_group("modal"):
				n.queue_free()
			_toggle_menu(false)
			_close_info_card()
			await get_tree().process_frame
	print("T: Layout-Prüfung (Spiel) fertig — %d Verstöße" % total)
	get_tree().quit()


func _run_test_ai() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	var alive: int = sim.alive_count(0)
	if _ai_alive < 0:
		_ai_alive = alive
	if not _ai_attacked and alive < _ai_alive:
		_ai_attacked = true
		print("T%d Angriff: eigene Einheiten %d → %d" % [tick, _ai_alive, alive])
	_ai_alive = mini(_ai_alive, alive) if _ai_attacked else alive
	if tick >= _test_tick + 1000:
		_test_tick = tick

		var per := {}
		for u in world.units:
			if u.alive and u.player != 0 and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS:
				if not per.has(u.player):
					per[u.player] = {}
				per[u.player][u.type] = per[u.player].get(u.type, 0) + 1
		for pl in per:
			print("T%d KI%d: %s credits=%d ertrag=%d squads=%d" % [tick, pl, per[pl], sim.credits(pl), sim.earned(pl), sim.bot_squad_count(pl)])
		print("T%d Spieler: %d | %d µs/Tick, %d Actors" % [tick, sim.alive_count(0), sim.last_step_usec(), sim.actor_count()])


		for pl in per:
			for u in world.units:
				if u.alive and u.player == pl and u.type == "harv":
					var best := -1.0
					for r in world.units:
						if r.alive and r.player == pl and r.type == "proc":
							var d := u.pos.distance_to(r.pos) / ProtoWorld.CELL
							best = d if best < 0.0 else minf(best, d)
					print("   KI%d Harvester %d bei %s, %s Zellen zur Raffinerie" % [pl, u.id,
						Vector2i(u.pos / ProtoWorld.CELL), "-" if best < 0.0 else "%.1f" % best])
		if world.mission_api != null:
			print("   Mission: Ziele ", world.mission_api.objectives.get(0, []), " Zeit ", world.mission_api.time_left, " Sieg ", world.win_state())
		if tick >= mini(3000, _test_ai_until) and _screenshot_path != "" and not _ai_shot:
			_ai_shot = true
			for u in world.units:
				if u.alive and u.player == 1 and u.type == "fact":
					world.center_on(u.pos)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		if tick >= _test_ai_until:
			var ws := world.win_state()
			print("T%d Ende: %s | Angriff erlebt: %s | eigene %d, Gegner %d" % [tick,
				["offen", "Sieg", "Niederlage"][clampi(ws, 0, 2)], "ja" if _ai_attacked else "nein",
				sim.alive_count(0), sim.alive_count(1)])
			get_tree().quit()


var _game_over_shown := false
var _movie: Movie = null


func _leave_battlefield() -> void:
	_autosave("leave")
	var path := "res://assets/sfx/bct1.wav"
	if ResourceLoader.exists(path):
		var p := AudioStreamPlayer.new()
		p.stream = load(path)
		p.finished.connect(p.queue_free)
		get_tree().root.add_child(p)
		p.play()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


var _menu_button: Button
var _menu_panel: PanelContainer
var _menu_backdrop: ColorRect


const PAUSE_GRID := [
	["pause.objectives", "_show_objectives"], ["pause.save", "_show_slots_save"],
	["pause.load", "_show_slots_load"], ["menu.main.options", "_show_options"],
	["pause.restart", "_restart_battle"], ["pause.give_up", "_leave_battlefield"],
	["pause.quit_game", "_quit_game"],
]


func _restart_battle() -> void:
	get_tree().reload_current_scene()


func _quit_game() -> void:
	_autosave("quit")
	get_tree().quit()


func _show_slots_save() -> void:
	_show_slots(true)


func _show_slots_load() -> void:
	_show_slots(false)


func _build_game_menu() -> void:
	_menu_button = Button.new()
	_menu_button.text = ""
	_menu_button.icon = load(MENU_ICON)
	_menu_button.expand_icon = true
	_menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_menu_button.tooltip_text = tr("pause.title")
	HudTheme.style_icon_button(_menu_button)
	HudTheme.wire_help(_menu_button, "help.btn.menu", $UI, func(): _toggle_menu(not _menu_panel.visible))
	$UI.add_child(_menu_button)
	_menu_button.add_to_group("layout_hud")


	_menu_backdrop = HudTheme.dim_backdrop($UI)
	_menu_backdrop.visible = false
	_menu_panel = PanelContainer.new()
	_menu_panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	_menu_panel.visible = false
	$UI.add_child(_menu_panel)


func _rebuild_pause_menu() -> void:
	for c in _menu_panel.get_children():
		_menu_panel.remove_child(c)
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(10)))
	var title := Label.new()
	title.text = tr("pause.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(Dp.px(22)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	box.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
			func(i): GameSpeed.set_index(i), self))
	var landscape: bool = Dp.safe_rect().size.x >= Dp.safe_rect().size.y
	var cell_w := Dp.px(200.0 if landscape else 260.0)
	var grid := GridContainer.new()
	grid.columns = 2 if landscape else 1
	grid.add_theme_constant_override("h_separation", int(Dp.px(8)))
	grid.add_theme_constant_override("v_separation", int(Dp.px(8)))
	for entry in PAUSE_GRID:
		var b := Button.new()
		b.text = tr(entry[0])
		b.custom_minimum_size = Vector2(cell_w, Dp.px(42))
		HudTheme.plate_button_style(b, 14.0)
		b.pressed.connect(Callable(self, entry[1]))
		grid.add_child(b)
	var scroll := TouchList.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(grid)


	var rows := int(ceil(PAUSE_GRID.size() / float(grid.columns)))
	var row_h := Dp.px(42.0)
	var v_sep := Dp.px(8.0)
	var grid_h := rows * row_h + maxi(rows - 1, 0) * v_sep
	var reserved := Dp.px(230.0)
	scroll.custom_minimum_size = Vector2(grid.columns * cell_w + maxi(grid.columns - 1, 0) * Dp.px(8.0),
			minf(grid_h, get_viewport().get_visible_rect().size.y - reserved))
	box.add_child(scroll)
	var resume := Button.new()
	resume.text = tr("pause.resume")
	resume.custom_minimum_size = Vector2(cell_w, Dp.px(48))
	HudTheme.plate_button_style(resume, 16.0)
	resume.pressed.connect(func(): _toggle_menu(false))
	var center := CenterContainer.new()
	center.add_child(resume)
	box.add_child(center)
	_menu_panel.add_child(box)


var _music_button: Button


func _play_movie(name: String) -> Movie:
	_movie = Movie.play(self, name)
	return _movie


func _toggle_music() -> void:
	world.music.toggle()
	_update_music_icon()
	if _music_button != null:
		_music_button.text = _music_text()


func _music_text() -> String:
	return tr("options.music_on") if (world.music != null and world.music.enabled) else tr("options.music_off")


class _MuteStrike extends Control:
	func _draw() -> void:
		var pad := minf(size.x, size.y) * 0.22
		var w := maxf(2.0, minf(size.x, size.y) * 0.06)
		draw_line(Vector2(pad, size.y - pad), Vector2(size.x - pad, pad), Color(0.95, 0.25, 0.2, 0.9), w, true)


var _music_off_mark: Control
var _build_ready_glow: Control


func _update_music_icon() -> void:
	var on: bool = world.music != null and world.music.enabled
	music_toggle.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 1) if on else Color(0.5, 0.5, 0.5, 1))
	music_toggle.add_theme_color_override("icon_hover_color", Color(1.08, 1.08, 1.0, 1) if on else Color(0.6, 0.6, 0.6, 1))
	if _music_off_mark != null:
		_music_off_mark.visible = not on


var _mission_label: Label
var _message_label: Label
var _message_until := 0.0
var _mission_highlight: Control
var _mission_highlight_id := ""
var _mission_ack_btn: Button
var _mission_color := Color(0, 0, 0, 0)


func _build_mission_ui() -> void:
	_mission_label = Label.new()
	_mission_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_mission_label.add_theme_color_override("font_color", HudTheme.GOLD)
	_mission_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_mission_label.add_theme_constant_override("outline_size", int(Dp.px(2)))
	_mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$UI.add_child(_mission_label)
	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", int(Dp.px(14)))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$UI.add_child(_message_label)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast_label.add_theme_color_override("font_color", HudTheme.TEXT)
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast_label.add_theme_constant_override("outline_size", int(Dp.px(3)))
	_toast_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast_label.gui_input.connect(func(e):


		var down: bool = e is InputEventScreenTouch and e.pressed
		if down and _has_event:
			world.center_on(_last_event_pos)
			_toast_label.accept_event())
	$UI.add_child(_toast_label)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_color_override("font_color", HudTheme.GOLD)
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_info_label.add_theme_constant_override("outline_size", int(Dp.px(3)))
	$UI.add_child(_info_label)


	_mission_highlight = Control.new()
	_mission_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mission_highlight.draw.connect(_draw_mission_highlight)
	$UI.add_child(_mission_highlight)


	_mission_ack_btn = Button.new()
	_mission_ack_btn.text = tr("ui.understood")
	_mission_ack_btn.visible = false


	_mission_ack_btn.custom_minimum_size = Vector2(Dp.px(170), Dp.px(52))
	HudTheme.plate_button_style(_mission_ack_btn, 16.0)
	_mission_ack_btn.pressed.connect(func():
		if world.mission_api != null:
			world.mission_api.confirm_ack())
	$UI.add_child(_mission_ack_btn)
	world.mission_message.connect(_on_mission_message)
	if ProtoWorld.next_mission != "":
		var text := Missions.briefing(ProtoWorld.next_mission)
		if text != "":
			_show_briefing(text)
		elif Missions.video(ProtoWorld.next_mission, "start") != "":
			_play_start_video()


func _play_start_video() -> void:
	var name := "" if _skip_videos() else Missions.video(ProtoWorld.next_mission, "start")
	if name == "":
		world.paused = false
		return
	world.paused = true
	var m := _play_movie(name)
	if m == null:
		world.paused = false
		return
	m.finished.connect(func(): world.paused = false)


func _show_briefing(text: String) -> void:
	world.paused = true
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.add_to_group("modal")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(10)))
	var title := Label.new()
	title.text = world.map_data.title
	title.add_theme_font_size_override("font_size", int(Dp.px(20)))
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))


	var scroll := TouchList.new()
	scroll.custom_minimum_size = Vector2(Dp.px(430), _text_rows_height(14.0, Dp.px(200), 4, 16))
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(Dp.px(420), 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", int(Dp.px(14)))
	scroll.add_child(body)
	var start := Button.new()
	start.text = tr("menu.missions.start")
	start.custom_minimum_size = Vector2(Dp.px(200), Dp.px(48))
	HudTheme.plate_button_style(start, 16.0)
	start.pressed.connect(func():
		panel.queue_free()
		backdrop.queue_free()
		_play_start_video())
	box.add_child(title)
	box.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(10)))


	var brief_video := Missions.video(ProtoWorld.next_mission, "briefing")
	if brief_video == "":
		brief_video = Missions.video(ProtoWorld.next_mission, "background")
	if brief_video != "":
		var film := Button.new()
		film.text = tr("briefing.video")
		film.custom_minimum_size = Vector2(Dp.px(170), Dp.px(48))
		HudTheme.plate_button_style(film, 15.0)
		film.pressed.connect(func(): _play_movie(brief_video))
		row.add_child(film)
	row.add_child(start)
	var center := CenterContainer.new()
	center.add_child(row)
	box.add_child(center)
	panel.add_child(box)
	$UI.add_child(panel)
	panel.reset_size()
	_center_panel(panel)

	if (_any_test or _screenshot_path != "") and not _test_briefing:
		start.pressed.emit()


func _text_rows_height(font_dp: float, reserved: float, min_rows: int, max_rows: int) -> float:
	var fs := maxi(1, int(Dp.px(font_dp)))
	var line := ThemeDB.fallback_font.get_height(fs)
	var avail := get_viewport().get_visible_rect().size.y - reserved
	var rows := clampi(int(avail / maxf(line, 1.0)), min_rows, max_rows)
	return rows * line


func _center_panel(panel: Control) -> void:
	var safe := Dp.safe_rect()
	panel.size = panel.get_combined_minimum_size().min(safe.size)
	panel.position = (safe.position + (safe.size - panel.size) / 2.0).max(safe.position)
	panel.move_to_front()


func _show_objectives() -> void:
	var lines: Array = []
	if world.mission_api != null:
		for o in world.mission_api.objectives.get(0, []):
			if o["text"] == "":
				continue
			var mark := "✔" if o["state"] == "done" else ("✘" if o["state"] == "failed" else "•")
			lines.append("%s %s" % [mark, o["text"]])
		if world.mission_api.time_limit > 0:
			lines.append(tr("objectives.time") % world.mission_api.format_time(world.mission_api.time_left))
	if lines.is_empty() and world.mission_api != null:
		lines.append(tr("objectives.none_yet"))
		if world.mission_api.mission_text != "":
			lines.append(world.mission_api.mission_text)
	if lines.is_empty():

		lines.append(tr("objectives.skirmish_destroy"))
		lines.append(tr("objectives.skirmish_survive"))
	if ProtoWorld.next_mission != "":
		var brief := Missions.briefing(ProtoWorld.next_mission)
		if brief != "":
			lines.append("")
			lines.append(brief)
	lines.append("")
	lines.append(tr("gameover.stats") % [world.sim.alive_count(0), world.sim.alive_count(1)])
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.add_to_group("modal")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var title := Label.new()
	title.text = tr("objectives.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(Dp.px(20)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	var scroll := TouchList.new()
	scroll.custom_minimum_size = Vector2(Dp.px(430), _text_rows_height(13.0, Dp.px(190), 4, 16))
	var body := Label.new()
	body.text = "\n".join(lines)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(Dp.px(420), 0)
	body.add_theme_font_size_override("font_size", int(Dp.px(13)))
	scroll.add_child(body)
	box.add_child(scroll)
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(200), Dp.px(44))
	HudTheme.plate_button_style(close, 15.0)
	close.pressed.connect(func(): panel.queue_free(); backdrop.queue_free())
	var center := CenterContainer.new()
	center.add_child(close)
	box.add_child(center)
	panel.add_child(box)
	$UI.add_child(panel)
	_center_panel(panel)


const AUTOSAVE_TICKS := 4500
var _test_save := false
var _last_autosave_tick := -1


func _show_slots(save_mode: bool) -> void:
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.add_to_group("modal")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var title := Label.new()
	title.text = tr("pause.save") if save_mode else tr("pause.load")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(Dp.px(20)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)

	if save_mode and ProtoWorld.next_mission != "":
		var hint := Label.new()
		hint.text = tr("save.mission_restart_only")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(Dp.px(420), 0)
		hint.add_theme_font_size_override("font_size", int(Dp.px(12)))
		box.add_child(hint)
	var scroll := TouchList.new()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Dp.px(6)))
	var rows: Array = []
	if save_mode:
		for slot in SaveGame.SLOTS:
			rows.append([slot, SaveGame.read(slot, false)])
	else:
		for e in SaveGame.list_all():
			rows.append([str(e["slot"]), e])
	if rows.is_empty():
		var none := Label.new()
		none.text = tr("save.none")
		none.add_theme_font_size_override("font_size", int(Dp.px(13)))
		list.add_child(none)
	for row in rows:
		var slot: String = row[0]
		var entry: Dictionary = row[1]
		var b := Button.new()
		var name := tr("save.slot_auto") if SaveGame.is_auto(slot) else tr("save.slot") % slot
		b.text = "%s\n%s" % [name, SaveGame.label(entry)]
		b.custom_minimum_size = Vector2(Dp.px(420), Dp.px(54))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudTheme.plate_button_style(b, 13.0)
		if save_mode:
			b.pressed.connect(func():
				var ok: bool = world.save_to_slot(slot, groups.groups)
				panel.queue_free()
				backdrop.queue_free()
				_toggle_menu(false)
				_toast(tr("save.saved") % slot if ok else tr("save.failed")))
		else:
			b.pressed.connect(func():
				panel.queue_free()
				backdrop.queue_free()
				_load_slot(slot))
		list.add_child(b)
	scroll.add_child(list)

	var wanted := Dp.px(58) * maxi(rows.size(), 1) + Dp.px(12)
	scroll.custom_minimum_size = Vector2(Dp.px(440),
			minf(wanted, get_viewport().get_visible_rect().size.y * 0.5))
	box.add_child(scroll)
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(200), Dp.px(44))
	HudTheme.plate_button_style(close, 15.0)
	close.pressed.connect(func(): panel.queue_free(); backdrop.queue_free())
	var center := CenterContainer.new()
	center.add_child(close)
	box.add_child(center)
	panel.add_child(box)
	$UI.add_child(panel)
	_center_panel(panel)


func _load_slot(slot: String) -> void:
	ProtoWorld.next_savegame = slot
	get_tree().reload_current_scene()


func _autosave_tick() -> void:
	if world == null or world.sim == null or world.paused or _any_test:
		return


	if ProtoWorld.next_mission != "":
		return
	var t: int = world.sim.tick()
	if _last_autosave_tick < 0:
		_last_autosave_tick = t
		return
	if t - _last_autosave_tick >= AUTOSAVE_TICKS:
		_autosave("timer")


func _autosave(reason: String) -> void:
	if world == null or world.sim == null or _any_test or _game_over_shown:
		return
	var slot := SaveGame.next_auto_slot()
	if not world.save_to_slot(slot, groups.groups):
		return
	_last_autosave_tick = world.sim.tick()
	if reason == "timer":
		_toast(tr("save.autosaved"))


func _run_test_save() -> void:
	var sim = world.sim
	if sim.tick() < 1500 or _test_step != 0:
		return
	_test_step = 1
	world.paused = true
	var bytes: PackedByteArray = sim.save_state()
	var ok_file: bool = world.save_to_slot("5", groups.groups)
	var size_file := 0
	if FileAccess.file_exists(SaveGame.path_for("5")):
		size_file = FileAccess.open(SaveGame.path_for("5"), FileAccess.READ).get_length()
	print("T: --test-save: Sim-Zustand %d Bytes bei Tick %d, %d Actors; Datei %d Bytes (%s)" % [
			bytes.size(), sim.tick(), sim.actor_count(), size_file, "ok" if ok_file else "FEHLER"])
	for _i in 500:
		sim.step()
	var ha := _sim_state_hash()
	if not world.load_state_bytes(bytes):
		print("T: --test-save: load_state FEHLGESCHLAGEN")
		get_tree().quit()
		return
	for _i in 500:
		sim.step()
	var hb := _sim_state_hash()
	print("T: --test-save: Hash nach 500 Ticks A=%d B=%d — %s" % [ha, hb, "gleich" if ha == hb else "ABWEICHUNG"])

	get_tree().quit()


func _sim_state_hash() -> int:
	var sim = world.sim
	var st: PackedFloat32Array = sim.render_state(1.0)
	return hash([st.to_byte_array(), sim.tick(), sim.credits(0), sim.credits(1),
			sim.alive_count(0), sim.alive_count(1)])


func _restore_groups(gd: Dictionary) -> void:
	var saved: Array = gd.get("groups", [])
	for i in mini(saved.size(), groups.groups.size()):
		var g: Array = []
		for id in saved[i]:
			var u := world.unit_by_id(int(id))
			if u != null and u.alive:
				g.append(u)
		groups.groups[i] = g
	if not saved.is_empty():
		groups.queue_redraw()


func _show_options() -> void:
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.add_to_group("modal")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var title := Label.new()
	title.text = tr("menu.main.options")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(Dp.px(20)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	var music_btn := Button.new()
	music_btn.text = _music_text()
	music_btn.custom_minimum_size = Vector2(Dp.px(300), Dp.px(44))
	HudTheme.plate_button_style(music_btn, 15.0)
	music_btn.pressed.connect(func():
		_toggle_music()
		music_btn.text = _music_text())
	box.add_child(music_btn)


	box.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
			func(i): GameSpeed.set_index(i), self))
	for entry in [["master", "menu.options.master"], ["music", "menu.options.music"],
			["sfx", "menu.options.sfx"], ["voice", "menu.options.voice"]]:
		box.add_child(HudTheme.volume_row(entry[0], tr(entry[1]), self))


	var controls_btn := Button.new()
	controls_btn.text = tr("menu.controls")
	controls_btn.custom_minimum_size = Vector2(Dp.px(300), Dp.px(44))
	HudTheme.plate_button_style(controls_btn, 15.0)
	controls_btn.pressed.connect(func(): _show_gesture_help(false))
	box.add_child(controls_btn)


	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(box.get_combined_minimum_size().y, Dp.safe_rect().size.y - Dp.px(110)))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(Dp.px(8)))
	scroll.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	panel.add_child(outer)
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(200), Dp.px(44))
	HudTheme.plate_button_style(close, 15.0)
	close.pressed.connect(func(): panel.queue_free(); backdrop.queue_free())
	var center := CenterContainer.new()
	center.add_child(close)
	outer.add_child(center)
	$UI.add_child(panel)
	_center_panel(panel)


func _show_gesture_help(first_time: bool) -> void:
	var was_paused := world.paused
	world.paused = true
	var panel := GestureHelp.panel(tr("menu.controls"), tr("ui.understood"), func():
		world.paused = was_paused
		if first_time:
			GestureHelp.mark_seen(), get_viewport().get_visible_rect().size.y,
			get_viewport().get_visible_rect().size.x)
	panel.add_to_group("modal")
	$UI.add_child(panel)
	_center_panel(panel)


func _on_mission_message(text: String, prefix: String) -> void:
	_message_label.text = ("%s: %s" % [prefix, text]) if prefix != "" else text
	_message_until = Time.get_ticks_msec() / 1000.0 + 8.0


func _skip_videos() -> bool:

	return _any_test or _screenshot_path != "" or DisplayServer.get_name() == "headless"


func _game_over_reason(ws: int) -> String:
	if world.mission_api != null:
		var wanted := "done" if ws == 1 else "failed"
		for o in world.mission_api.objectives.get(0, []):
			if o["primary"] and o["state"] == wanted and o["text"] != "":
				return o["text"]
		return tr("gameover.mission_done") if ws == 1 else tr("gameover.mission_failed")
	return tr("gameover.all_enemies_destroyed") if ws == 1 else tr("gameover.base_fallen")


func _update_mission_ui() -> void:
	if Time.get_ticks_msec() / 1000.0 > _message_until:
		_message_label.text = ""
	if world.mission_api == null:
		_mission_label.text = ""
		return
	var api := world.mission_api
	var lines: Array = []
	for o in api.objectives.get(0, []):
		if o["text"] == "":
			continue
		var mark := "✔" if o["state"] == "done" else ("✘" if o["state"] == "failed" else "•")
		lines.append("%s %s" % [mark, o["text"]])

	var mission_text: String = api.mission_text
	if api.time_limit > 0:
		var t := api.format_time(api.time_left)
		var ctext: String = api.countdown_text.replace("{0}", t) if api.countdown_text != "" else tr("objectives.time") % t

		if mission_text.find(t) >= 0:
			ctext = ""
		if ctext != "":
			lines.append(ctext)
	if mission_text != "":
		lines.append(mission_text)
	var mtext := "\n".join(lines)
	if _mission_label.text != mtext:
		_mission_label.text = mtext

	var mcol: Color = api.mission_color if api.mission_text != "" else HudTheme.GOLD
	if _mission_color != mcol:
		_mission_color = mcol
		_mission_label.add_theme_color_override("font_color", mcol)
	_mission_highlight_id = api.hud_highlight


	api.build_bar_open = build_bar.visible
	api.build_bar_kind = build_bar.kind
	api.control_groups = groups.groups
	if _mission_highlight != null:
		_mission_highlight.queue_redraw()
	if _mission_ack_btn != null:
		_mission_ack_btn.visible = api.awaiting_ack
		if api.awaiting_ack:


			_mission_ack_btn.position = Vector2(_mission_label.position.x,
					_mission_label.position.y + _mission_label.size.y + Dp.px(4))


var _hud_highlight_targets := {}


func _hud_highlight_target() -> Control:
	if _hud_highlight_targets.is_empty():
		_hud_highlight_targets = {
			"build_toggle": build_toggle, "build_bar": build_bar, "status_bar": status_bar,
			"minimap": minimap, "groups": groups, "menu_button": _menu_button, "music_toggle": music_toggle,
			"tab_building": build_bar._tabs[0] if build_bar._tabs.size() > 0 else null,
			"tab_defense": build_bar._tabs[1] if build_bar._tabs.size() > 1 else null,
			"tab_infantry": build_bar._tabs[2] if build_bar._tabs.size() > 2 else null,
			"tab_vehicle": build_bar._tabs[3] if build_bar._tabs.size() > 3 else null,
			"btn_all": _cmd_buttons.get("all"), "cmd_sell": _cmd_buttons.get("sell"),
			"cmd_repair": _cmd_buttons.get("repair"), "cmd_add": _cmd_buttons.get("add"),
			"cmd_clear": _cmd_buttons.get("clear"), "cmd_base": _cmd_buttons.get("base"),
			"cmd_event": _cmd_buttons.get("event"), "cmd_sel": _cmd_buttons.get("sel"),
			"cmd_zoom_in": _cmd_buttons.get("zoom_in"), "cmd_zoom_out": _cmd_buttons.get("zoom_out"),
		}
	return _hud_highlight_targets.get(_mission_highlight_id, null)


const _HUD_HIGHLIGHT_MAP_IDS := {"deploy_mcv": "PlayerMCV", "radial_attack": "EnemyYard"}


func _draw_mission_highlight() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)


	if _mission_ack_btn != null and _mission_ack_btn.visible:
		var br := Rect2(_mission_highlight.get_global_transform().affine_inverse() * _mission_ack_btn.get_global_rect().position,
				_mission_ack_btn.get_global_rect().size).grow(Dp.px(3))
		_mission_highlight.draw_rect(br, Color(1.0, 0.85, 0.2, 0.7 + 0.3 * pulse), false, Dp.px(4))
	if _mission_highlight_id == "cameo":


		var ct: String = world.mission_api.highlight_cameo_type if world.mission_api != null else ""
		var cr := build_bar.slot_rect_for(ct) if ct != "" else Rect2()
		if cr.size != Vector2.ZERO:
			var lr := Rect2(_mission_highlight.get_global_transform().affine_inverse() * cr.position, cr.size).grow(Dp.px(4))
			_mission_highlight.draw_rect(lr, Color(1.0, 0.82, 0.15, pulse), false, Dp.px(3))
		return
	if _mission_highlight_id == "unit":
		var hu = world.mission_api.highlight_unit if world.mission_api != null else null
		if hu != null and hu.alive:
			var p: Vector2 = _mission_highlight.get_global_transform().affine_inverse() * world.world_to_screen(hu.pos)
			_mission_highlight.draw_arc(p, Dp.px(28), 0, TAU, 32, Color(1.0, 0.82, 0.15, pulse), Dp.px(3))
		return
	var map_id: String = _HUD_HIGHLIGHT_MAP_IDS.get(_mission_highlight_id, "")
	if map_id != "":
		var u = world.mission_api.actor(map_id) if world.mission_api != null else null
		if u != null and u.alive:
			var p: Vector2 = _mission_highlight.get_global_transform().affine_inverse() * world.world_to_screen(u.pos)
			_mission_highlight.draw_arc(p, Dp.px(28), 0, TAU, 32, Color(1.0, 0.82, 0.15, pulse), Dp.px(3))
		return
	var target := _hud_highlight_target()
	if target == null or not target.is_visible_in_tree():
		return
	var r := Rect2(_mission_highlight.get_global_transform().affine_inverse() * target.get_global_rect().position,
			target.get_global_rect().size)
	r = r.grow(Dp.px(4))
	_mission_highlight.draw_rect(r, Color(1.0, 0.82, 0.15, pulse), false, Dp.px(3))


func _modal_open() -> bool:
	return get_tree().get_node_count_in_group("modal") > 0


func _toggle_menu(open: bool) -> void:
	_close_info_card()
	if open:
		_menu_backdrop.size = get_viewport().get_visible_rect().size
		_rebuild_pause_menu()
	_menu_panel.visible = open
	_menu_backdrop.visible = open
	world.paused = open or _modal_open()
	if open:
		_center_panel(_menu_panel)


func _notification(what: int) -> void:


	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave("pause")
		return
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if is_instance_valid(_movie) and _movie.is_inside_tree():
		return
	if _info_card != null:
		_close_info_card()
	elif radial.visible:
		radial.cancel()
	elif world.placing_type >= 0 or _confirm_mode != "" or _order_mode != "":
		_cancel_placement()
	elif _click_mode != "":
		_set_click_mode(_click_mode)
	elif _menu_panel.visible:
		_toggle_menu(false)
	else:
		_toggle_menu(true)


func _check_game_over() -> void:
	if _game_over_shown or world.sim == null:
		return
	var ws := world.win_state()
	if ws == 0:
		return
	_game_over_shown = true


	if ProtoWorld.next_mission != "" and not _skip_videos():
		_play_movie(Missions.video(ProtoWorld.next_mission, "win" if ws == 1 else "loss"))
	var mp := get_node_or_null("/root/MusicPlayer")
	if mp != null:
		mp.play_track(mp.victory_track() if ws == 1 else mp.defeat_track())
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.name = "GameOver"
	panel.add_to_group("modal")
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var label := Label.new()
	label.text = tr("gameover.won") if ws == 1 else tr("gameover.lost")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(Dp.px(32)))
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if ws == 1 else Color(0.95, 0.3, 0.25))
	var sub := Label.new()
	sub.text = _game_over_reason(ws)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", int(Dp.px(14)))

	box.add_child(label)
	box.add_child(sub)
	var stats := Label.new()
	stats.text = tr("gameover.stats") % [world.sim.alive_count(0), world.sim.alive_count(1)]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", int(Dp.px(12)))
	stats.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(stats)
	if ProtoWorld.next_mission != "" and ws == 1:
		Missions.mark_completed(ProtoWorld.next_mission)
		var next_slug := Missions.next_after(ProtoWorld.next_mission)
		if next_slug != "":
			var next_btn := Button.new()
			next_btn.text = tr("gameover.next_mission")
			next_btn.custom_minimum_size = Vector2(Dp.px(180), Dp.px(46))
			HudTheme.plate_button_style(next_btn, 15.0)
			next_btn.pressed.connect(func():
				ProtoWorld.next_map = next_slug
				ProtoWorld.next_mission = next_slug
				get_tree().reload_current_scene())
			box.add_child(next_btn)
	var again := Button.new()
	again.text = tr("gameover.new_game") if ProtoWorld.next_mission == "" else tr("gameover.retry_mission")
	again.custom_minimum_size = Vector2(Dp.px(180), Dp.px(46))
	HudTheme.plate_button_style(again, 15.0)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)
	var watch := Button.new()
	watch.text = tr("gameover.keep_watching")
	watch.custom_minimum_size = Vector2(Dp.px(180), Dp.px(46))
	HudTheme.plate_button_style(watch, 15.0)
	watch.pressed.connect(func(): panel.queue_free(); backdrop.queue_free())
	box.add_child(watch)
	var menu_btn := Button.new()
	menu_btn.text = tr("gameover.main_menu")
	menu_btn.custom_minimum_size = Vector2(Dp.px(180), Dp.px(46))
	HudTheme.plate_button_style(menu_btn, 15.0)
	menu_btn.pressed.connect(_leave_battlefield)
	box.add_child(menu_btn)
	panel.add_child(box)
	$UI.add_child(panel)
	_center_panel(panel)


func _process(delta: float) -> void:

	if _cmd_buttons.has("add"):
		_cmd_buttons["add"].button_pressed = world.additive_select
	_check_game_over()
	_update_mission_ui()
	_update_toasts()
	_update_info()
	_edge_scroll(delta)
	if _test_sell and world.sim != null:
		_run_test_sell()
	if _test_defense and world.sim != null:
		_run_test_defense()
	if _test_buildings and world.sim != null:
		_run_test_buildings()
	if _test_tesla and world.sim != null:
		_run_test_tesla()
	if _demo_battle and world.sim != null:
		_run_demo_battle()
	if _test_nuke and world.sim != null:
		_run_test_nuke()
	if _test_spy and world.sim != null:
		_run_test_spy()
	if _test_ui and world.sim != null:
		_run_test_ui()
	if _test_ai and world.sim != null:
		_run_test_ai()
	if _test_motion and world.sim != null:
		_run_test_motion()
	if _test_projectile and world.sim != null:
		_run_test_projectile()
	if _test_barrels and world.sim != null:
		_run_test_barrels()
	if _test_air and world.sim != null:
		_run_test_air()
	if _test_air_player and world.sim != null:
		_run_test_air_player()
	if _test_cargo and world.sim != null:
		_run_test_cargo()
	if _test_naval and world.sim != null:
		_run_test_naval()
	if _test_lst and world.sim != null:
		_run_test_lst()
	if _test_save and world.sim != null:
		_run_test_save()
	if _test_armaments and world.sim != null:
		_run_test_armaments()
	if _test_dog and world.sim != null:
		_run_test_dog()
	if _test_placement and world.sim != null:
		_run_test_placement()
	if _test_lobby_tap and world.sim != null:
		_run_test_lobby_tap()
	_autosave_tick()
	if (_test_defeat or _test_victory) and world.sim != null:
		var dt: int = world.sim.tick()
		if _defeat_step == 0 and dt >= 150:
			_defeat_step = 1
			for u in world.units:
				if not u.alive:
					continue
				var own := u.player == 0
				var foe := u.player != 0 and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS
				if (own and _test_defeat) or (foe and _test_victory):
					world.sim.destroy(u.id)
			print("T: %s Actors entfernt bei Tick %d" % ["eigene" if _test_defeat else "gegnerische", dt])
		elif _defeat_step == 1 and world.win_state() != 0:
			_defeat_step = 2
			_defeat_tick = dt
			print("T: Spielende erkannt bei Tick %d (Zustand %d)" % [dt, world.win_state()])
		elif _defeat_step == 2 and dt >= _defeat_tick + 120:
			print("T: Spielende-Probe fertig")
			get_tree().quit()
	if _test_speed and world.sim != null and not world.paused:
		var now := Time.get_ticks_msec() / 1000.0
		var window := 5.0 if _test_speed_switch >= 0 else 10.0
		if _speed_t0 < 0.0:
			_speed_t0 = now
			_speed_tick0 = int(world.sim.tick())
		elif _test_speed_switch >= 0 and not _speed_switched and now - _speed_t0 >= window:
			var dt0 := now - _speed_t0
			var dticks0: int = int(world.sim.tick()) - _speed_tick0
			print("T: Stufe %d (%d ms) → %.1f Ticks/s in %.1f s (%d Ticks) [vor Wechsel]" % [
				GameSpeed.index(), GameSpeed.TIMESTEPS[GameSpeed.index()], dticks0 / dt0, dt0, dticks0])


			GameSpeed.set_index(_test_speed_switch)
			_speed_switched = true
			_speed_t0 = now
			_speed_tick0 = int(world.sim.tick())
		elif _speed_switched and now - _speed_t0 >= window:
			var dt1 := now - _speed_t0
			var dticks1: int = int(world.sim.tick()) - _speed_tick0
			print("T: Stufe %d (%d ms) → %.1f Ticks/s in %.1f s (%d Ticks) [nach Wechsel]" % [
				GameSpeed.index(), GameSpeed.TIMESTEPS[GameSpeed.index()], dticks1 / dt1, dt1, dticks1])
			get_tree().quit()
		elif _test_speed_switch < 0 and now - _speed_t0 >= window:
			var dt := now - _speed_t0
			var dticks: int = int(world.sim.tick()) - _speed_tick0
			print("T: Stufe %d (%d ms) → %.1f Ticks/s in %.1f s (%d Ticks)" % [
				GameSpeed.index(), GameSpeed.TIMESTEPS[GameSpeed.index()], dticks / dt, dt, dticks])
			get_tree().quit()
	if _test_cycle and world.sim != null and world.sim.tick() >= 120:
		print("T: Zyklus %d — Karte %s, Mission '%s', Einheiten %d" % [ProtoWorld.test_cycle_step,
			world.map_data.slug, ProtoWorld.next_mission, world.sim.alive_count(0)])
		ProtoWorld.test_cycle_step += 1
		_test_cycle = false
		_leave_battlefield()
		return
	if _test_mission and world.sim != null:
		_run_test_mission()
	if _diag:
		debug_label.text = "Geste: %s\nAuswahl: %d   Zoom: %.1f   FPS: %d\n%s" % [
			_last_gesture, world.selection.size(), world.zoom, Engine.get_frames_per_second(), world.sim_text]

	if _screenshot_path == "" or _test_ai or _test_ui or _test_defense or _test_buildings or _test_tesla or _test_nuke \
			or _test_projectile or _test_barrels or _test_air or _test_air_player or _test_cargo or _test_placement or _test_naval or _test_lst:
		return
	var f := Engine.get_process_frames()
	if _test_briefing:
		if f == 40:
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
			get_tree().quit()
		return
	if f == 5:


		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for u in world.units:
			if u.alive and u.player == 0:
				lo = lo.min(u.pos)
				hi = hi.max(u.pos)
		if lo.x <= hi.x:
			world.center_on((lo + hi) / 2.0)
			world.begin_box(world.world_to_screen(lo - Vector2.ONE * ProtoWorld.CELL))
			world.update_box(world.world_to_screen(hi + Vector2.ONE * ProtoWorld.CELL))
			_log("Rahmenauswahl: %d Einheiten" % world.end_box())
	elif f > 5 and world.sim != null and world.sim.tick() >= _screenshot_tick - 40 and world.sim.tick() < _screenshot_tick:
		if not world.selection.is_empty():
			world.center_on(world.selection_center())
	elif f > 5 and world.sim != null and world.sim.tick() >= _screenshot_tick and not _shot_running:
		_shot_running = true

		for i in maxi(1, _screenshot_series):
			if i > 0:
				await get_tree().create_timer(0.1).timeout
			var img := get_viewport().get_texture().get_image()
			var path := _screenshot_path if _screenshot_series <= 1 else \
					"%s-%d.%s" % [_screenshot_path.get_basename(), i + 1, _screenshot_path.get_extension()]
			img.save_png(path)
			print("Screenshot: ", path)
		get_tree().quit()


var _test_motion := false
var _mo_state := 0
var _mo_last := {}
var _mo_dir := {}
var _mo_back := 0
var _mo_worst := 0.0
var _mo_frames := 0
var _mo_until := 0
var _mo_goal := Vector2.ZERO
var _mo_next_order := 0


func _run_test_motion() -> void:
	var sim = world.sim
	if _mo_state == 0:
		if sim.tick() < 25:
			return
		var n := world.select_all_units()
		if n == 0:
			print("T: --test-motion: keine eigenen Einheiten")
			get_tree().quit()
			return
		_mo_goal = world.selection_center() + Vector2(30.0 * ProtoWorld.CELL, 0.0)
		world.order_move(_mo_goal)
		_mo_until = sim.tick() + 900
		_mo_state = 1
		print("T: --test-motion: %d Einheiten fahren 30 Zellen" % n)
		return


	if sim.tick() >= _mo_next_order:
		_mo_next_order = sim.tick() + 20
		world.order_move(_mo_goal)
	_mo_frames += 1
	for u in world.units:
		if not u.alive or u.player != 0:
			continue
		var p: Vector2 = u.pos
		var d: Vector2 = p - _mo_last.get(u.id, p)
		_mo_last[u.id] = p
		var step := d.length()
		if step < 0.01:
			continue
		var dir: Vector2 = _mo_dir.get(u.id, Vector2.ZERO)


		if dir != Vector2.ZERO and d.dot(dir) < 0.0 and step > 0.5:
			_mo_back += 1
			_mo_worst = maxf(_mo_worst, step)
			if _mo_back <= 10:
				print("T%d Rückwärts: %s um %.1f px (Richtung %.2f/%.2f, Versatz %.2f/%.2f)"
					% [sim.tick(), u.type, step, dir.x, dir.y, d.x, d.y])
		_mo_dir[u.id] = d.normalized() if dir == Vector2.ZERO else (dir + d.normalized()).normalized()
	if sim.tick() >= _mo_until:
		print("T%d --test-motion: %d Rückwärtssprünge in %d Frames (größter %.1f px)"
			% [sim.tick(), _mo_back, _mo_frames, _mo_worst])
		get_tree().quit()


var _tm_seen := {}
var _tm_text := ""
var _tm_over := false
var _tm_forced := false


func _run_test_mission() -> void:
	var api := world.mission_api
	if api == null:
		return
	var t := int(world.sim.tick())
	if _test_force and not _tm_forced and t >= 250 and world.mission != null:
		_tm_forced = true
		print("MISSION t=%d ERZWINGE Siegkette" % t)
		world.mission.test_force()
	for owner in api.objectives:
		for o in api.objectives[owner]:
			var key := "%d/%d" % [owner, o["id"]]
			var val := "%s|%s" % [o["state"], o["text"]]
			if _tm_seen.get(key, "") != val:
				_tm_seen[key] = val
				print("MISSION t=%d spieler=%d ziel=%d %s %s \"%s\"" % [
					t, owner, o["id"], "haupt" if o["primary"] else "neben", o["state"], o["text"]])
	var line := api.mission_text
	if api.time_limit > 0:
		line += " [%s]" % api.format_time(api.time_left)
	if line != _tm_text:
		_tm_text = line
		if line.strip_edges() != "":
			print("MISSION t=%d text \"%s\"" % [t, line])
	var ws := world.win_state()
	if ws != 0 and not _tm_over:
		_tm_over = true
		print("MISSION t=%d ENDE %s" % [t, "SIEG" if ws == 1 else "NIEDERLAGE"])
