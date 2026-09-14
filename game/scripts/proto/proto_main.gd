

extends Node


const Desktop := preload("res://scripts/desktop.gd")


const ActionBar := preload("res://scripts/proto/action_bar.gd")

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


var _key_group_last := -1
var _key_group_time := -10.0

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
	"notify.silos_needed", "notify.cannot_place",


	"", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
	"toast.place_pending"]

var _last_gesture := "—"
var _screenshot_path := ""
var _test_sell := false
var _test_ai := false
var _test_buildings := false
var _test_tesla := false
var _test_ttnk := false
var _test_nuke := false
var _test_nuke_target := Vector2i.ZERO
var _test_nuke_wait_until := 0
var _test_spy := false


var _spy_nuke_last := -1
var _spy_nuke_drop := ""
var _test_bridge := false
var _test_bridges := false
var _test_capture := false
var _test_ui := false
var _test_mission := false
var _test_force := false
var _test_step := 0
var _diag := false
var _test_placement := false
var _test_heal := false
var _test_iron := false
var _test_water := false
var _test_voice := false
var _test_duck := false
var _test_players := false
var _test_mic := false
var _test_mic_secs := 8.0
var _test_placement_cancel := false
var _test_deploy := false
var _test_forcefire := false

var _test_ready := ""
var _test_lobby_tap := false


var _test_toasts := false
var _test_toasts_until := 6000


var _test_harvest := false
var _test_harvest_until := 6000
var _harv_ids: Array[int] = []
var _harv_last_cell := {}
var _harv_stall := {}
var _harv_worst := {}
var _harv_last_tick := -1
var _harv_parked := false
var _harv_resumed := false

var _test_eva := false
var _eva_step := 0
var _eva_tick := 0
var _eva_lines: Array = []
var _eva_marks: Array = []
var _eva_power_flip := -1
var _eva_origin := Vector2i.ZERO
var _eva_order_tick := -1
var _toast_frames := 0
var _toast_frames_busy := 0
var _toast_line_sum := 0
var _toast_lines_max := 0
var _placement_shots: Dictionary = {}
var _confirm_mode := ""


var _order_mode := ""
var _sp_panel: SupportPowersPanel
var _sp_source := Vector2.ZERO

var _click_mode := ""


var action_bar: Control = null

var _bar_target: ProtoWorld.Unit = null

var _bar_cell := Vector2.ZERO
var _bar_has_cell := false

var _bar_press := Vector2.ZERO


var _unload_ids := PackedInt32Array()
var _unload_cell := Vector2.ZERO
var _unload_deadline := -1


var _force_touch := false


func _touch_model() -> bool:
	return _force_touch or not Desktop.is_desktop()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--screenshot")
	if k >= 0 and k + 1 < args.size():
		_screenshot_path = args[k + 1]
	_test_sell = args.has("--test-sell")
	_test_defense = args.has("--test-defense")
	_test_defense_fire = args.has("--test-defense-fire")
	_test_buildings = args.has("--test-buildings")
	_test_tesla = args.has("--test-tesla")
	_test_ttnk = args.has("--test-ttnk")
	_test_nuke = args.has("--test-nuke")
	_test_spy = args.has("--test-spy")
	_test_bridge = args.has("--test-bridge")
	_test_bridges = args.has("--test-bridges")
	_test_capture = args.has("--test-capture")
	_test_ai = args.has("--test-ai")
	_test_ai_audit = args.has("--test-ai-audit")
	if _test_ai_audit:
		_test_ai = true
	_test_ui = args.has("--test-ui")
	_test_briefing = args.has("--test-briefing")
	_test_mission = args.has("--test-mission")
	_test_force = args.has("--test-force")
	_diag = args.has("--diag")
	_test_cycle = args.has("--test-cycle")
	if args.has("--test-layout"):
		call_deferred("_run_test_layout")
	_test_superwaffen = args.has("--test-superwaffen")
	if _test_superwaffen:
		call_deferred("_run_test_superwaffen")
	_test_hit = args.has("--test-hit")
	if _test_hit:
		call_deferred("_run_test_hit")
	_test_speed = args.has("--test-speed")
	var tsk := args.find("--test-speed-switch")
	if tsk >= 0 and tsk + 1 < args.size():
		_test_speed_switch = int(args[tsk + 1])
	_test_speed_ui = args.has("--test-speed-ui")
	if _test_speed_ui:
		call_deferred("_run_test_speed_ui")


	var aisk := args.find("--test-ai-start")
	if aisk >= 0:
		_test_ai_start = 3
		if aisk + 1 < args.size() and str(args[aisk + 1]).is_valid_int():
			_test_ai_start = maxi(int(args[aisk + 1]), 1)
		call_deferred("_run_test_ai_start")

	_test_ai_count = args.has("--test-ai-count")
	if _test_ai_count:
		call_deferred("_run_test_ai_count")
	if args.has("--test-keys"):
		call_deferred("_run_test_keys")
	if args.has("--test-desktop-scroll"):
		call_deferred("_run_test_desktop_scroll")
	if args.has("--test-desktop-input"):
		call_deferred("_run_test_desktop_input")
	_test_defeat = args.has("--test-defeat")
	_test_victory = args.has("--test-victory")
	_test_motion = args.has("--test-motion")
	_test_projectile = args.has("--test-projectile")
	_test_barrels = args.has("--test-barrels")
	_test_kaserne = args.has("--test-kaserne")
	_test_husk = args.has("--test-husk")
	_test_effects = args.has("--test-effects")
	_test_gap = args.has("--test-gap")
	_test_gps = args.has("--test-gps")
	_test_nebel = args.has("--test-nebel")
	_test_jammer = args.has("--test-jammer")
	_test_mech = args.has("--test-mech")
	_test_muzzle = args.has("--test-muzzle")
	_test_rotor = args.has("--test-rotor")
	_test_turret = args.has("--test-turret")
	_test_make = args.has("--test-make")
	_test_autotarget = args.has("--test-autotarget")
	_test_air = args.has("--test-air")
	_test_crash = args.has("--test-crash")
	_test_air_player = args.has("--test-air-player")
	_test_cargo = args.has("--test-cargo")
	_test_naval = args.has("--test-naval")
	_test_msub = args.has("--test-msub")
	_test_lst = args.has("--test-lst")
	_test_save = args.has("--test-save")
	_test_armaments = args.has("--test-armaments")
	_test_dog = args.has("--test-dog")
	_test_placement = args.has("--test-placement")

	var dbk := args.find("--demo-battle")
	if dbk >= 0:
		_demo_battle = 1
		if dbk + 1 < args.size() and not args[dbk + 1].begins_with("--"):
			_demo_battle = maxi(1, int(args[dbk + 1]))
		_any_test = true
		_screenshot_tick = 1 << 30
		var ddk := args.find("--demo-delay")
		if ddk >= 0 and ddk + 1 < args.size():
			_demo_delay = int(args[ddk + 1])
		var dek := args.find("--demo-every")
		if dek >= 0 and dek + 1 < args.size():
			_demo_every = maxi(1, int(args[dek + 1]))
		var dsk := args.find("--demo-shots")
		if dsk >= 0 and dsk + 1 < args.size():
			_demo_count = maxi(1, int(args[dsk + 1]))
		_demo_zap = args.has("--demo-zap")
		_demo_follow = args.has("--demo-follow")
	_test_heal = args.has("--test-heal")
	_test_iron = args.has("--test-iron")
	_test_water = args.has("--test-water")


	_test_voice = args.has("--test-sprechfunk")
	if _test_voice and not args.has("--test-mikrofon"):
		call_deferred("_run_test_sprechfunk")


	_test_duck = args.has("--test-voice-duck")
	if _test_duck:
		_test_voice = true
		call_deferred("_run_test_voice_duck")
	_test_players = args.has("--test-spielerliste")
	if _test_players:
		call_deferred("_run_test_spielerliste")


	var mk := args.find("--test-mikrofon")
	if mk >= 0:
		_test_mic = true
		_test_voice = true
		if mk + 1 < args.size() and not args[mk + 1].begins_with("--"):
			_test_mic_secs = maxf(float(args[mk + 1]), 1.0)
		call_deferred("_run_test_mikrofon")
	if _test_water:
		call_deferred("_run_test_water")


	_test_placement_cancel = args.has("--test-placement-cancel")
	_test_deploy = args.has("--test-deploy")
	_test_crate = args.has("--test-crate")
	_test_cratedrop = args.has("--test-cratedrop")
	_test_forcefire = args.has("--test-forcefire")
	_test_c4 = args.has("--test-c4")
	_test_wall = args.has("--test-wall")
	_test_build_area = args.has("--test-build-area")


	_auto_bar_enabled = true
	for a in args:
		if String(a).begins_with("--test-") and a != "--test-build-area":
			_auto_bar_enabled = false
	_test_retreat = args.has("--test-retreat")

	var trk := args.find("--test-ready")
	if trk >= 0:
		_test_ready = args[trk + 1] if (trk + 1 < args.size() and not args[trk + 1].begins_with("--")) else "zu"
		_test_ui = true
	_force_touch = args.has("--touch")
	_test_tap_orders = args.has("--test-tap-orders")
	if _test_tap_orders:
		_force_touch = true
	_test_lobby_tap = args.has("--test-lobby")
	_test_toasts = args.has("--test-toasts")
	_test_eva = args.has("--test-eva")
	_test_harvest = args.has("--test-harvest")
	var thu := args.find("--test-harvest-until")
	if thu >= 0 and thu + 1 < args.size():
		_test_harvest_until = int(args[thu + 1])
	var ttu := args.find("--test-toasts-until")
	if ttu >= 0 and ttu + 1 < args.size():
		_test_toasts_until = int(args[ttu + 1])
	if _test_toasts:
		HudTheme.log_overlays = true
		HudTheme.log_counts = {}
		HudTheme.log_total = 0
		HudTheme.log_tick = func(): return world.sim.tick() if world != null and world.sim != null else -1
	for a in args:
		if a.begins_with("--test") or a == "--screenshot" or a == "--autostart":
			_any_test = true


		if a == "--mp-autoplay" or a == "--mp-shot":
			_any_test = true
	var auk := args.find("--test-ai-until")
	if auk >= 0 and auk + 1 < args.size():
		_test_ai_until = int(args[auk + 1])
	var ssk := args.find("--screenshot-series")
	if ssk >= 0 and ssk + 1 < args.size():
		_screenshot_series = int(args[ssk + 1])
	var stk := args.find("--screenshot-at")
	if stk >= 0 and stk + 1 < args.size() and _demo_battle == 0:
		_screenshot_tick = int(args[stk + 1])
	elif _test_spy or _test_bridge or _test_bridges or _test_capture:


		_screenshot_tick = 1 << 30
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


	gestures.mouse_long_press = not Desktop.has_keyboard()
	radial.chosen.connect(_on_radial)


	action_bar = ActionBar.new()
	action_bar.name = "ActionBar"
	$UI.add_child(action_bar)
	action_bar.chosen.connect(_on_action_bar)
	action_bar.dismissed.connect(_on_action_bar_dismissed)


	build_toggle.toggle_mode = true
	build_toggle.text = ""
	build_toggle.icon = load(BUILD_TOGGLE_ICON)
	build_toggle.expand_icon = true
	build_toggle.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_toggle.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	build_toggle.tooltip_text = tr("ui.build_toggle_tip")
	HudTheme.style_icon_button(build_toggle)
	HudTheme.wire_help(build_toggle, "help.btn.build_toggle", $UI, _toggle_build_bar)
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


	HudTheme.wire_help(place_confirm, "help.placement", $UI, _confirm_placement)
	place_cancel.pressed.connect(_cancel_placement)
	HudTheme.wire_help(music_toggle, "help.btn.music", $UI, _toggle_music)
	_update_music_icon()
	status_bar.world = world
	_sp_panel = SupportPowersPanel.new()
	_sp_panel.world = world
	_sp_panel.help_host = $UI
	_sp_panel.activate.connect(_on_support_power)
	_sp_panel.relayout.connect(_layout_ui)
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
	_setup_multiplayer_hud()
	_layout_ui()
	_resizer = Desktop.watch_resize(self, _on_window_resized)


	_scroller = Desktop.watch_scroll(self, _scroll_pan, _scroll_zoom)
	_scroller.blocked = _scroll_blocked
	_scroller.edge_blocked = _edge_scroll_blocked
	if Desktop.want_test_window():
		_go_test_window.call_deferred()
	debug_label.visible = _diag


	if ProtoWorld.next_mission == "":
		_toast(tr("toast.you_play") % tr("faction.soviet" if world.player_faction() == "soviet" else "faction.allies"))
	if not GestureHelp.seen() and _screenshot_path == "" and not _any_test:
		call_deferred("_show_gesture_help", true)


var _resizer: Desktop.Resizer


var _scroller: Desktop.Scroller


func _scroll_pan(d: Vector2) -> void:
	world.pan_screen(d)
	_last_gesture = "Schwenken"


func _scroll_zoom(factor: float, at: Vector2) -> void:
	world.zoom_at(factor, at)
	_last_gesture = "Zoom %.2f" % world.zoom


func _scroll_blocked() -> bool:
	if world == null or world.sim == null:
		return true
	if is_instance_valid(_movie) and _movie.is_inside_tree():
		return true
	if _menu_panel != null and _menu_panel.visible:
		return true
	if _mp_chat_panel != null and _mp_chat_panel.visible:
		return true
	return gestures.input_blocked or _modal_open()


func _edge_scroll_blocked() -> bool:
	return _boxing or radial.visible or _info_card != null \
			or (action_bar != null and action_bar.visible)


func _on_window_resized() -> void:
	HudTheme.rescale_tree($UI, _resizer.ratio)
	HudTheme.refit_dim_backdrops(get_tree())
	build_bar.rescale()
	_layout_ui()


func _go_test_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Desktop.apply_test_window()


func _layout_ui() -> void:


	var safe := Dp.safe_rect()
	var off := safe.position
	var vs := safe.position + safe.size
	var m := Dp.px(12)


	var mini_side := Dp.px(Minimap.SIDE_DP)
	minimap.custom_minimum_size = Vector2(mini_side, mini_side)
	minimap.size = minimap.custom_minimum_size
	minimap.position = Vector2(off.x + m, vs.y - minimap.size.y - m)


	var fit := _fit_bottom_bars(safe, m)
	build_bar.set_columns(fit["build_cols"])
	build_bar.size = build_bar.wanted_size(minf(safe.size.x, safe.size.y))
	build_bar.position = vs - build_bar.size - Vector2(m, m)

	var confirm_box := Vector2(Dp.px(110), Dp.px(48))
	var confirm_pos := Vector2(vs.x - confirm_box.x - m, vs.y - confirm_box.y - m)
	HudTheme.place_touch(place_confirm, confirm_pos, confirm_box, Vector2(m / 2.0, m / 2.0))
	HudTheme.place_touch(place_cancel, confirm_pos - Vector2(confirm_box.x + m, 0), confirm_box,
		Vector2(m / 2.0, m / 2.0))


	var icon_side := Dp.px(TOP_ICON_BTN_DP)
	var icon_box := Vector2(icon_side, icon_side)
	var icon_pad := Vector2(m / 2.0, m / 2.0)


	var bb_pref := BuildBar.preferred_size(minf(safe.size.x, safe.size.y), fit["build_cols"])
	var bt_pos := Vector2(vs.x - icon_side - m, vs.y - m - bb_pref.y - icon_side - m / 2)
	HudTheme.place_touch(build_toggle, bt_pos, icon_box, icon_pad)
	var mt_pos := Vector2(vs.x - icon_side - m, off.y + m)
	HudTheme.place_touch(music_toggle, mt_pos, icon_box, icon_pad)
	if _music_off_mark != null:
		_music_off_mark.queue_redraw()
	if _sp_panel != null:


		_sp_panel.position = Vector2.ZERO
		_sp_panel.size = get_viewport().get_visible_rect().size
		var sp_gap := Dp.px(HudTheme.ICON_GAP_DP)
		var cmd_right: float = off.x + m + minimap.size.x + m \
			+ fit["cmd_cols"] * Dp.px(CMD_BTN_W_DP) + (fit["cmd_cols"] - 1) * sp_gap


		_sp_panel.layout_stack(vs.x - m, bt_pos.y, icon_side, sp_gap,
			maxf(maxf(off.x + m, cmd_right + m), vs.x - m - bb_pref.x), off.y + m)


	status_bar.size = Vector2(Dp.px(220), Dp.px(42))
	status_bar.position = Vector2(off.x + (safe.size.x - status_bar.size.x) / 2.0, off.y + m / 4)


	var top_comm := _layout_top_comm(off, m, icon_side, icon_box)
	var groups_top: float = float(top_comm["bottom"]) + m
	var groups_bottom := minimap.position.y - m
	groups.layout_slots(maxf(groups_bottom - groups_top, Dp.px(HudTheme.GROUP_BTN_H_DP) * ControlGroups.SLOTS))
	var groups_pad: Vector2 = groups.get_meta("hit_pad", Vector2.ZERO)
	groups.position = Vector2(off.x + m - groups_pad.x,
			groups_top + maxf(groups_bottom - groups_top - groups.size.y, 0.0) / 2.0)
	HudTheme.place_touch(_menu_button, off + Vector2(m, m), icon_box, icon_pad)
	_mission_label.position = Vector2(float(top_comm["right"]) + m, off.y + m)

	_mission_label.size = Vector2(maxf(Dp.px(160), status_bar.position.x - _mission_label.position.x - m), Dp.px(90))
	_message_label.size = Vector2(Dp.px(420), Dp.px(44))
	_message_label.position = Vector2(off.x + (safe.size.x - _message_label.size.x) / 2.0, vs.y - build_bar.size.y - Dp.px(58))
	_toast_label.size = Vector2(Dp.px(460), Dp.px(56))
	_toast_bottom = _message_label.position.y - Dp.px(4)
	_toast_label.position = Vector2(off.x + (safe.size.x - _toast_label.size.x) / 2.0, _toast_bottom - _toast_label.size.y)
	_info_label.size = Vector2(Dp.px(360), Dp.px(22))

	_info_label.position = Vector2(off.x + (safe.size.x - _info_label.size.x) / 2.0, vs.y - Dp.px(96) - _info_label.size.y)
	_layout_command_bar(vs, m, off, fit["cmd_cols"])
	_layout_mp(safe, m)
	_map_rect = hud_map_rect(safe, fit)
	_mode_frame.position = off
	_mode_frame.size = safe.size
	debug_label.position = Vector2(off.x + m, status_bar.position.y + status_bar.size.y + m)
	debug_label.modulate = Color(1, 1, 1, 0.75)
	debug_label.add_theme_font_size_override("font_size", int(Dp.px(12)))


func _log(s: String) -> void:
	_last_gesture = s


	if _diag or _any_test or OS.is_debug_build():
		print(s)


const TOAST_SECS := 2.0

const TOAST_LINES := 2

var _toast_label: Label
var _toasts: Array = []
var _toast_bottom := 0.0
var _last_event_pos := Vector2.ZERO
var _has_event := false


func _toast(text: String) -> void:
	_log(text)
	HudTheme.log_overlay("TOAST", text, TOAST_SECS)
	var now := Time.get_ticks_msec() / 1000.0
	for i in _toasts.size():
		if _toasts[i][0] == text:
			var again: Array = _toasts[i]
			again[1] = now + TOAST_SECS
			again[2] = int(again[2]) + 1
			_toasts.remove_at(i)
			_toasts.append(again)
			_update_toasts()
			return
	_toasts.append([text, now + TOAST_SECS, 1])
	while _toasts.size() > TOAST_LINES:
		_toasts.pop_front()
	_update_toasts()


func _update_toasts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not _toasts.is_empty() and _toasts[0][1] < now:
		_toasts.pop_front()
	var lines: Array = []
	for t in _toasts:
		lines.append(t[0] if int(t[2]) < 2 else "%s ×%d" % [t[0], int(t[2])])
	var ttext := "\n".join(lines)
	if _toast_label.text != ttext:
		_toast_label.text = ttext
	if _test_toasts:


		_toast_frames += 1
		if not lines.is_empty():
			_toast_frames_busy += 1
			_toast_line_sum += lines.size()
			_toast_lines_max = maxi(_toast_lines_max, lines.size())


	var h := maxf(lines.size(), 1) * Dp.px(17)
	_toast_label.size.y = h
	_toast_label.position.y = _toast_bottom - h


func _on_notify(kind: int) -> void:

	if kind >= 0 and kind < NOTIFY_KEYS.size() and NOTIFY_KEYS[kind] != "":
		_toast(tr(NOTIFY_KEYS[kind]))


func _on_under_attack(pos: Vector2) -> void:
	if _test_ai and not _ai_attacked:
		_ai_attacked = true
		print("T%d Angriff: Basis unter Beschuss" % world.sim.tick())
	_last_event_pos = pos
	_has_event = true
	minimap.add_ping(pos)


var _hover_ghost := false
var _hover_declined := -1


func _hover_ghost_possible() -> bool:


	if not _auto_bar_enabled or world == null or world.sim == null or not Desktop.has_keyboard():
		return false
	if not build_bar.visible or not build_bar.is_visible_in_tree():
		return false
	if _confirm_mode != "" or _order_mode != "" or _click_mode != "" or _boxing:
		return false
	if radial.visible or _info_card != null or (_menu_panel != null and _menu_panel.visible):
		return false
	if action_bar != null and action_bar.visible:
		return false
	return _hover_ghost or world.placing_type < 0


func _over_hud(p: Vector2) -> bool:
	if build_bar.visible and build_bar.get_global_rect().has_point(p):
		return true
	if _menu_panel != null and _menu_panel.visible and _menu_panel.get_global_rect().has_point(p):
		return true
	if _info_card != null and _info_card.get_global_rect().has_point(p):
		return true
	return _hud_button_at(p)


func _hover_ghost_motion(m: InputEventMouseMotion) -> void:
	if m.button_mask != 0 or world == null or world.sim == null or not Desktop.has_keyboard():
		return
	if _confirm_mode == "place" and world.placing_type >= 0:
		if _over_hud(m.position):
			return
		world.move_placement(world.screen_to_world(m.position))
		world.place_armed = true
		return
	if not _hover_ghost_possible() or _over_hud(m.position):
		_end_hover_ghost()
		return
	var ready: int = build_bar.ready_building()
	if ready < 0 or ready == _hover_declined:
		_end_hover_ghost()
		return
	if not _hover_ghost or world.placing_type != ready:
		_bar_open_before_placement = build_bar.visible
		world.begin_placement(ready)
		_hover_ghost = true

		build_bar.mark_ready_offered()


	world.move_placement(world.screen_to_world(m.position))
	world.place_armed = true


func _end_hover_ghost(declined: bool = false) -> void:
	if not _hover_ghost:
		return
	_hover_ghost = false
	if declined:
		_hover_declined = world.placing_type
	world.cancel_placement()


const AUTO_BAR_DELAY := 0.3

var _auto_bar_enabled := true
var _auto_bar_timer := 0.0
var _auto_bar_manual_closed := false
var _auto_bar_manual_open := false
var _auto_bar_open_at := Vector2.ZERO


func _toggle_build_bar() -> void:
	var open := not build_bar.visible
	build_bar.visible = open
	_auto_bar_manual_closed = not open
	_auto_bar_manual_open = open
	_hover_declined = -1
	_auto_bar_open_at = world.visible_world_rect().get_center() if world != null else Vector2.ZERO
	_auto_bar_timer = 0.0


func _tick_auto_build_bar(delta: float) -> void:
	if not _auto_bar_enabled or world == null or world.sim == null:
		return


	if world.placing_type >= 0 or _confirm_mode != "":
		_auto_bar_timer = 0.0
		return
	var yard := _conyard_in_view()
	var area: bool = world.build_area_in_view()


	var view := world.visible_world_rect()
	if not yard:
		_auto_bar_manual_closed = false
	if _auto_bar_manual_open and view.get_center().distance_to(_auto_bar_open_at) > minf(view.size.x, view.size.y) / 2.0:
		_auto_bar_manual_open = false
	var want := build_bar.visible
	if yard and not _auto_bar_manual_closed:
		want = true
	elif not area and not _auto_bar_manual_open:
		want = false
	if want == build_bar.visible:
		_auto_bar_timer = 0.0
		return
	_auto_bar_timer += delta
	if _auto_bar_timer < AUTO_BAR_DELAY:
		return
	_auto_bar_timer = 0.0
	build_bar.visible = want
	if want:


		build_bar.mark_ready_offered()


func _conyard_in_view() -> bool:
	var view := world.visible_world_rect()
	for u in world.units:
		if u.alive and u.player == world.local_player and world.types[u.type].get("base_provider", false) \
				and view.intersects(world.unit_rect(u)):
			return true
	return false


var _bar_open_before_placement := true


func _begin_placement(type_id: int) -> void:


	_order_mode = ""
	_end_click_mode()
	world.begin_placement(type_id)
	_hover_ghost = false
	_hover_declined = -1
	_bar_open_before_placement = build_bar.visible
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
		_hover_declined = -1
		_end_placement(tr("toast.built"))
	else:
		_toast(tr("toast.cannot_build_here"))


func _cancel_placement() -> void:


	if _hover_ghost and _confirm_mode == "":
		_end_hover_ghost(true)
		_toast(tr("toast.placement_cancelled"))
		return
	if _confirm_mode == "place":


		_hover_declined = world.placing_type


		build_bar.decline_ready(world.placing_type)
		world.cancel_placement()
		_end_placement(tr("toast.placement_cancelled"))
		return
	if _confirm_mode == "order":
		_order_mode = ""
		_end_placement(tr("toast.order_cancelled"))
		return
	_end_placement(tr("toast.cancelled"))


func _end_placement(msg: String) -> void:
	_confirm_mode = ""
	_order_mode = ""
	_hover_ghost = false
	place_confirm.visible = false
	place_cancel.visible = false


	build_bar.visible = _bar_open_before_placement


	build_bar.mark_ready_offered()
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
		"chrono":

			_toast(tr("toast.chrono_jumped") if world.chrono_selected(wp) else tr("toast.chrono_impossible"))


func _do_deploy_action(action: String) -> void:
	match action:
		"deploy":
			_toast(tr("toast.deployed") if world.deploy_selected() else tr("toast.deploy_impossible"))
		"mine":
			_toast(tr("toast.mine_laid") if world.lay_mine_selected() else tr("toast.mine_impossible"))
		"detonate":
			_toast(tr("toast.detonating") if world.detonate_selected() else tr("toast.detonate_impossible"))
		"demolish":
			_toast(tr("toast.demolished") if world.detonate_selected() else tr("toast.detonate_impossible"))
		"chrono":
			if world.selection_can_chrono():
				_begin_order("chrono", tr("radial.action.chrono"))
			else:
				_toast(tr("toast.chrono_charging"))


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


	if _sp_panel != null and _sp_panel.expanded():
		_sp_panel.set_expanded(false)
		return
	var wp := world.screen_to_world(p)
	if world.placing_type >= 0:


		if _hover_ghost and not world.placement_ok():
			_end_hover_ghost(true)
		else:

			if world.tap_placement(wp):
				_hover_declined = -1
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


	if _desktop_select_first():
		_desktop_left_click(p, hit)
		return


	if _touch_model() and _bar_candidate(hit):
		_open_target_bar(hit, p)
		return


	if hit != null and hit.player == world.local_player and not world.selection.is_empty() and world.selected_building() == null \
			and world.order_land_at(hit):
		_toast(tr("toast.landing") % _type_label(hit.type))
		return
	if hit != null and hit.player == world.local_player and not world.selection.is_empty() and world.selected_building() == null \
			and world.types[hit.type].get("repairs_units", false) and world.order_repair(hit):
		_toast(tr("toast.repair_at_depot"))
		return

	if hit != null and hit.player == world.local_player and not world.selection.is_empty() and world.selected_building() == null \
			and world.order_deliver(hit):
		_toast(tr("toast.deliver_ore") % _type_label(hit.type))
		return


	if not world.selection.is_empty() and world.selected_building() == null:
		var br: ProtoWorld.Unit = world.pick_bridge(wp)
		if br != null:
			var bwhat := world.order_enter(br)
			if bwhat != "":
				_toast(tr(bwhat) % _type_label(br.type))
				return


	if hit != null and not world.selection.is_empty() and world.selected_building() == null:
		var ek := world.enter_kind(hit)
		if ek != 0:
			var what := world.order_enter(hit)
			if what != "":
				_toast(tr(what) % _type_label(hit.type))
				return

	if hit != null and hit.player != world.local_player and not world.selection.is_empty() and world.has_disguiser() \
			and not world.types[hit.type].get("building", false) and world.order_disguise(hit):
		_toast(tr("toast.disguised_as") % _type_label(hit.type))
		return

	if hit != null and hit.player == world.local_player and not hit.selected and not world.selection.is_empty() \
			and world.order_enter_transport(hit):
		_toast(tr("toast.boarding") % _type_label(hit.type))
		return


	if hit != null and hit.player == world.local_player and hit.selected and world.selection.size() == 1 \
			and world.has_deploy_action(hit.type):
		_do_deploy_action(world.deploy_action(hit.type))
		return


	if _tap_order_on_friendly(hit):
		return


	if hit != null and hit.player == world.local_player and world.selectable(hit):
		_select_tapped(hit)
	elif world.selected_building() != null:


		if hit != null and world.hostile(world.local_player, hit.player) and world.selection_armed():
			world.order_attack(hit)
			_last_gesture = "Angriff (%d)" % world.selection.size()
			_toast(tr("toast.attacking") % [_type_label(hit.type), world.selection.size()])

		elif hit == null and world.set_rally(wp):
			_toast(tr("toast.rally_set"))
		elif hit == null:
			_toast(tr("toast.no_rally_point"))
		else:
			_toast(tr("toast.rally_ground_only"))
	elif hit != null:
		if not world.selection.is_empty():


			if world.hostile(world.local_player, hit.player):
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


func _select_tapped(hit: ProtoWorld.Unit, mode: String = "") -> void:
	if mode == "only":
		world.select_exclusive(hit)
	else:
		world.select_only(hit)
	_show_selection_info()
	var kind := world.producer_kind(hit)
	if kind >= 0:
		build_bar.select_queue(kind)
		build_bar.visible = true
		build_bar.mark_ready_offered()


func _tap_order_on_friendly(hit: ProtoWorld.Unit) -> bool:
	if hit == null or world.selection.is_empty() or world.selected_building() != null:
		return false


	if hit.player != world.local_player:
		if hit.player == ProtoWorld.PLAYER_NEUTRAL or hit.player == ProtoWorld.PLAYER_CREEPS \
				or world.hostile(world.local_player, hit.player):
			return false

	if not world.selectable(hit):
		return false


	if hit.selected and not _desktop_cmd:
		return false


	if world.types[hit.type].get("building", false):
		world.order_move(hit.pos)
		_toast(tr("toast.move_next_to") % _type_label(hit.type))
		_last_gesture = "Bewegen neben Gebäude (%d)" % world.selection.size()
		return true
	if world.order_guard(hit):
		_toast(tr("toast.guarding") % _type_label(hit.type))
		_last_gesture = "Bewachen (%d)" % world.selection.size()
		return true
	world.order_move(hit.pos)
	_last_gesture = "Bewegen (%d)" % world.selection.size()
	return true


const ENTER_ACTIONS := {1: "capture", 2: "fix", 3: "c4", 4: "infiltrate", 5: "bridge"}


func _bar_candidate(hit: ProtoWorld.Unit) -> bool:
	if hit == null or not hit.alive or world.selection.is_empty() or world.selected_building() != null:
		return false


	if hit.selected:
		return false


	if not world.selectable(hit):
		return false
	if hit.player != world.local_player:
		if hit.player == ProtoWorld.PLAYER_NEUTRAL or hit.player == ProtoWorld.PLAYER_CREEPS \
				or world.hostile(world.local_player, hit.player):
			return false
	return true


func _target_items(hit: ProtoWorld.Unit) -> Array:
	var items: Array = []
	if hit == null:
		return items
	var own: bool = hit.player == world.local_player
	var foe: bool = world.hostile(world.local_player, hit.player)


	var friendly: bool = own or (not foe and hit.player != ProtoWorld.PLAYER_NEUTRAL \
			and hit.player != ProtoWorld.PLAYER_CREEPS)
	var ek := world.enter_kind(hit)
	if ENTER_ACTIONS.has(ek):
		items.append(ENTER_ACTIONS[ek])
	if own:
		if world.can_land_at(hit):
			items.append("land")
		if world.can_board(hit):
			items.append("board")
		if world.can_deliver_to(hit):
			items.append("deliver")
		if world.can_repair_at(hit):
			items.append("repair_at")


	if friendly and not world.types[hit.type].get("building", false) and world.sim != null \
			and world.sim.has_method("order_guard"):
		items.append("guard")
	if foe and world.selection_armed():
		items.append("attack")
	elif world.selection_can_force_attack(hit):


		items.append("force_attack")
	if friendly:
		items.append("move")
	items.append("info")
	items.append("cancel")


	if own and world.selectable(hit):
		if not world.selection.is_empty():
			items.push_front("add")
		items.push_front("select")
	return items


func _cell_items() -> Array:


	if not world.selected_buildings().is_empty():
		var b: Array = _radial_items()
		b.append("cancel")
		return b
	var items: Array = ["move", "attack_move"]
	if world.sim != null and world.sim.has_method("order_attack_cell"):
		items.append("force_fire")

	if world.selection_can_unload():
		items.append("unload")
	var has_harvester := false
	for u in world.selection:
		if world.types[u.type].get("harvester", false):
			has_harvester = true
	if has_harvester:
		items.append("harvest")
	if world.selection_can_lay_mine():
		items.append("mine")
	if world.selection_can_chrono():
		items.append("chrono")
	if world.selection_can_deploy():
		items.append("deploy")
	if world.selection_can_detonate():
		items.append("detonate")
	items.append("stop")
	items.append("scatter")
	items.append("clear")
	items.append("cancel")
	return items


func _open_target_bar(hit: ProtoWorld.Unit, press: Vector2, extra: Array = []) -> void:
	_clear_pending_unload()
	var items: Array = extra.duplicate()
	for a in _target_items(hit):
		if not items.has(a):
			items.append(a)
	_bar_target = hit
	_bar_has_cell = false
	_bar_press = press
	_force_target = hit if world.selection_can_force_attack(hit) else null
	_c4_target = hit if world.enter_kind(hit) == ProtoWorld.ENTER_DEMOLISH else null


	var r := world.unit_rect(hit)
	var ring_r: float = maxf(Dp.px(16), maxf(r.size.x, r.size.y) * 0.75 * world.zoom)
	action_bar.open(items, press, tr("bar.target") % _type_label(hit.type),
			world.world_to_screen(r.get_center()), ring_r, _bar_min_y())
	_toast(tr("toast.target_picked") % _type_label(hit.type))
	_last_gesture = "Ziel: %s" % hit.type


func _open_cell_bar(wp: Vector2, press: Vector2) -> void:
	_clear_pending_unload()
	_bar_target = null
	_bar_cell = wp
	_bar_has_cell = true
	_bar_press = press
	_force_target = null
	_c4_target = null
	action_bar.open(_cell_items(), press, tr("bar.target_ground"),
			world.world_to_screen(wp), Dp.px(18), _bar_min_y())
	_last_gesture = "Ziel: Stelle"


func _bar_min_y() -> float:
	return status_bar.position.y + status_bar.size.y + Dp.px(8)


func _on_action_bar(action: String) -> void:
	var target := _bar_target
	var cell := _bar_cell
	var has_cell := _bar_has_cell
	var press := _bar_press
	_bar_target = null
	_bar_has_cell = false
	if action == "" or action == "cancel":
		_force_target = null
		_c4_target = null
		_last_gesture = "Zielwahl verworfen"
		_toast(tr("toast.target_dropped"))
		return


	if action in ["stop", "scatter", "clear", "deploy", "mine", "detonate", "sell", "repair",
			"primary", "force_attack", "c4"]:
		_on_radial(action)
		return
	_force_target = null
	_c4_target = null
	world.sfx.play_ui("ramenu1")
	match action:
		"move":
			if has_cell:
				world.order_move(cell)
			else:


				world.order_move(target.pos)
				_toast(tr("toast.move_next_to") % _type_label(target.type))
			_last_gesture = "Bewegen (%d)" % world.selection.size()
		"attack_move":
			world.order_attack_move(cell)
			_toast(tr("toast.attack_move_count") % world.selection.size())
			_last_gesture = "Angriffszug (%d)" % world.selection.size()
		"force_fire":
			_toast(tr("radial.action.force_fire") if world.order_attack_cell(cell) else tr("toast.force_fire_impossible"))
			_last_gesture = "Zwangsfeuer (%d)" % world.selection.size()
		"harvest":
			_toast(tr("radial.action.harvest") if world.order_harvest(cell) else tr("toast.no_harvester"))
		"chrono":
			_toast(tr("toast.chrono_jumped") if world.chrono_selected(cell) else tr("toast.chrono_impossible"))
		"unload":
			_begin_unload_at(cell)
		"guard":
			if world.order_guard(target):
				_toast(tr("toast.guarding") % _type_label(target.type))
				_last_gesture = "Bewachen (%d)" % world.selection.size()
			else:
				_toast(tr("toast.no_guard_target"))
		"attack":
			if world.order_attack(target):
				_toast(tr("toast.attacking") % [_type_label(target.type), world.selection.size()])
				_last_gesture = "Angriff (%d)" % world.selection.size()
		"land":
			_toast(tr("toast.landing") % _type_label(target.type) if world.order_land_at(target) else tr("toast.order_impossible"))
		"board":
			_toast(tr("toast.boarding") % _type_label(target.type) if world.order_enter_transport(target) else tr("toast.order_impossible"))
		"deliver":
			_toast(tr("toast.deliver_ore") % _type_label(target.type) if world.order_deliver(target) else tr("toast.order_impossible"))
		"repair_at":
			_toast(tr("toast.repair_at_depot") if world.order_repair(target) else tr("toast.order_impossible"))
		"capture", "fix", "infiltrate", "bridge":


			var what := world.order_enter(target)
			_toast(tr(what) % _type_label(target.type) if what != "" else tr("toast.order_impossible"))
			_last_gesture = "Enter (%s)" % action
		"select":
			if target != null:
				_select_tapped(target, "only")
				_toast(tr("toast.selected_target") % _type_label(target.type))
				_last_gesture = "Auswählen: %s" % target.type
		"add":
			if target != null and world.select_append(target):
				_show_selection_info()
				_toast(tr("toast.added_to_selection") % [_type_label(target.type), world.selection.size()])
				_last_gesture = "Hinzugefügt: %s (%d)" % [target.type, world.selection.size()]
			else:
				_toast(tr("toast.already_selected"))
		"info":
			if target != null:
				_show_info_card(target, press)


func _on_action_bar_dismissed(pos: Vector2) -> void:
	var hit := world.pick_unit(world.screen_to_world(pos), Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit != null and hit != _bar_target and _bar_candidate(hit):
		_open_target_bar(hit, pos)
		return
	_bar_target = null
	_bar_has_cell = false
	_force_target = null
	_c4_target = null
	_last_gesture = "Zielwahl verworfen"
	_toast(tr("toast.target_dropped"))


func _begin_unload_at(wp: Vector2) -> void:
	var ids := world.loaded_ids(false)
	if ids.is_empty():
		_toast(tr("toast.nobody_aboard"))
		return
	world.order_move_ids(ids, Vector2i(wp / ProtoWorld.CELL))
	_unload_ids = ids
	_unload_cell = wp


	_unload_deadline = world.sim.tick() + 2000 if world.sim != null else -1
	_toast(tr("toast.unload_ordered"))
	_last_gesture = "Entladen hier (%d)" % ids.size()


func _clear_pending_unload() -> void:
	_unload_ids = PackedInt32Array()
	_unload_deadline = -1


func _step_pending_unload() -> void:
	if _unload_ids.is_empty() or world == null or world.sim == null:
		return
	if _unload_deadline >= 0 and world.sim.tick() > _unload_deadline:
		_clear_pending_unload()
		return
	var ready := PackedInt32Array()
	var left := PackedInt32Array()
	for id in _unload_ids:
		var u := world.unit_by_id(id)
		if u == null or not u.alive:
			continue


		if not u.moving and u.pos.distance_to(_unload_cell) <= ProtoWorld.CELL * 1.9:
			ready.append(id)
		else:
			left.append(id)
	_unload_ids = left
	if not ready.is_empty():
		if world.unload_ids(ready):
			_toast(tr("toast.unloading"))
		else:
			_toast(tr("toast.unload_blocked"))
	if _unload_ids.is_empty():
		_unload_deadline = -1


var _hud_tap_from := Vector2.ZERO
var _hud_tap_live := false


func _input(e: InputEvent) -> void:


	if e is InputEventMouseMotion:
		var mm: InputEventMouseMotion = e
		if (_radial_mouse or _radial_sticky) and radial.visible:
			radial.update(mm.position)
			return
		_hover_ghost_motion(mm)
		return


	if e is InputEventMouseButton and Desktop.has_keyboard():
		var rb: InputEventMouseButton = e
		if rb.button_index == MOUSE_BUTTON_RIGHT and not rb.pressed and not _rmb_consumed:
			_attack_under_hud(rb.position)
		return
	if not (e is InputEventScreenTouch):
		return
	var t: InputEventScreenTouch = e
	if t.index != 0:
		return
	if t.pressed:


		_tap_from_mouse = t.device == InputEvent.DEVICE_ID_EMULATION
		_hud_tap_from = t.position
		_hud_tap_live = true
		return
	if not _hud_tap_live:
		return
	_hud_tap_live = false

	if t.position.distance_to(_hud_tap_from) > Dp.px(gestures.tap_slop_dp):
		return
	if _tap_from_mouse:
		return
	_attack_under_hud(t.position)


func _attack_under_hud(p: Vector2) -> bool:
	if world == null or world.sim == null or _scroll_blocked():
		return false


	if action_bar != null and action_bar.visible:
		return false


	if world.placing_type >= 0 or _order_mode != "" or _click_mode != "":
		return false


	if world.selection.is_empty() or not world.selection_armed():
		return false
	if not _hud_button_at(p):
		return false
	var wp := world.screen_to_world(p)
	var hit := world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit == null or not hit.alive or not world.hostile(world.local_player, hit.player):
		return false
	if not world.order_attack(hit):
		return false
	_toast(tr("toast.attacking") % [_type_label(hit.type), world.selection.size()])
	_last_gesture = "Angriff unter Knopf (%d)" % world.selection.size()
	return true


func _hud_button_at(p: Vector2) -> bool:
	if groups != null and groups.is_visible_in_tree() and groups.get_global_rect().has_point(p):
		return true
	return _hud_button_under($UI, p)


func _hud_button_under(n: Node, p: Vector2) -> bool:
	if n is Control and not (n as Control).is_visible_in_tree():
		return false
	if n == build_bar or (_menu_panel != null and n == _menu_panel) \
			or (_info_card != null and n == _info_card) or n == action_bar or n.is_in_group("modal"):
		return false
	if n is Button:
		var b: Button = n
		if b.mouse_filter != Control.MOUSE_FILTER_IGNORE and b.get_global_rect().has_point(p):
			return true
	for c in n.get_children():
		if _hud_button_under(c, p):
			return true
	return false


func _apply_click_mode(hit: ProtoWorld.Unit) -> bool:
	if hit == null or hit.player != world.local_player or not world.types[hit.type].get("building", false):
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


	if _hover_ghost:
		_end_hover_ghost(true)
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
	if hit != null and hit.player == world.local_player and world.selectable(hit):
		if world.types[hit.type].get("building", false):
			_select_tapped(hit)
			_last_gesture = "Gebäude gewählt: %s" % hit.type
		else:
			world.select_same_type_visible(hit)
			_show_selection_info()
			_last_gesture = "Alle sichtbaren %s: %d" % [hit.type, world.selection.size()]


func _on_long_press(p: Vector2) -> void:
	if world.placing_type >= 0:
		return
	_force_target = null
	_c4_target = null
	_force_press = p
	var wp := world.screen_to_world(p)


	var hit := world.pick_unit(wp, 0.0)
	if hit == null:
		hit = world.pick_bridge(wp, false)
	if hit == null:
		hit = world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit != null:
		_inspect(hit)


		if not world.hostile(world.local_player, hit.player) and world.selection_can_force_attack(hit):
			_force_target = hit


		if world.enter_kind(hit) == ProtoWorld.ENTER_DEMOLISH:
			_c4_target = hit


		if _touch_model():
			if world.selection.is_empty():
				_show_info_card(hit, p)
				_last_gesture = "Infokarte"
				return


			if hit.selected:
				_open_cell_bar(wp, p)
				return
			_open_target_bar(hit, p)
			return
		if hit.player != world.local_player or not world.selectable(hit):


			if _c4_target != null or _force_target != null:
				var foreign: Array = []
				if _c4_target != null:
					foreign.append("c4")
				if _force_target != null:
					foreign.append("force_attack")
				foreign.append("info")
				radial.open(p, foreign)
				_last_gesture = "Radialmenü (fremd)"
				return
			_show_info_card(hit, p)
			_last_gesture = "Infokarte"
			return
		if world.selection.is_empty():
			world.select_only(hit)
		radial.open(p, _radial_items())
		_last_gesture = "Radialmenü"
		return
	if world.selection.is_empty():
		_toast(tr("toast.ground"))
		return


	if _touch_model():
		_open_cell_bar(wp, p)
		return
	radial.open(p, _radial_items())
	_last_gesture = "Radialmenü"


func _radial_items() -> Array:
	var items: Array = RadialMenu.BUILDING_ITEMS.duplicate() if not world.selected_buildings().is_empty() \
			else _unit_items()


	if not world.selected_buildings().is_empty() and world.selection_armed():
		if world.sim != null and world.sim.has_method("order_attack_cell"):
			items.append("force_fire")
		items.append("stop")
	if _force_target != null and not items.has("force_attack"):
		items.insert(0, "force_attack")
	if _c4_target != null and not items.has("c4"):
		items.insert(0, "c4")
	return items


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


	if world.selection_can_detonate():
		items.append("detonate")
	if world.selection_can_chrono():
		items.append("chrono")
	if world.selection_can_unload():
		items.append("unload")
	items.append("clear")
	return items


func _on_radial(action: String) -> void:
	if action != "":
		world.sfx.play_ui("ramenu1")

	var force_target := _force_target
	var c4_target := _c4_target
	_force_target = null
	_c4_target = null
	match action:
		"c4":


			var c4what := "" if c4_target == null else world.order_enter(c4_target)
			if c4what != "":
				_last_gesture = "Sprengen (%d)" % world.selection.size()
				_toast(tr(c4what) % _type_label(c4_target.type))
			else:
				_toast(tr("toast.demolish_impossible"))
		"force_attack":


			if force_target != null and world.order_attack(force_target, true):
				_last_gesture = "Zwangsfeuer (%d)" % world.selection.size()
				_toast(tr("toast.force_attacking") % [_type_label(force_target.type), world.selection.size()])
			else:
				_toast(tr("toast.force_fire_impossible"))
		"info":
			if force_target != null:
				_show_info_card(force_target, _force_press)
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
		"detonate":
			_do_deploy_action("detonate")
		"chrono":
			_do_deploy_action("chrono")
		"unload":


			if world.unload_selected():
				_toast(tr("toast.unloading"))
			elif world.selection_can_unload():
				_toast(tr("toast.unload_blocked"))
			else:
				_toast(tr("toast.nobody_aboard"))
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
		s += " (%s)" % (tr("label.owner_own") if u.player == world.local_player else (tr("label.owner_neutral") if not world.hostile(world.local_player, u.player) else tr("label.owner_hostile")))
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


var _force_target: ProtoWorld.Unit = null
var _force_press := Vector2.ZERO


var _c4_target: ProtoWorld.Unit = null

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


	var deploy_act := world.deploy_action(u.type)
	if deploy_act != "":
		_info_card_line(box, tr("info.deploy.%s" % deploy_act), Color(0.3, 0.9, 0.4))
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


	"harv": "res://icons/ui/btn_erzsammler_1.png",
}

var _cmd_buttons := {}
var _mode_frame: Panel
var _mode_frame_col := Color(0, 0, 0, 0)


const CMD_ORDER := ["sell", "repair", "add", "all", "harv", "base", "event", "sel", "zoom_in", "zoom_out"]


const BOTTOM_ROW_VISIBLE := false


const CMD_BOTTOM_ROW := ["base", "event", "sel", "zoom_in", "zoom_out"]


const CMD_HIDDEN := ["clear"]


static func visible_cmd_order() -> Array:
	var out: Array = []
	for id in CMD_ORDER:
		if id in CMD_HIDDEN or (not BOTTOM_ROW_VISIBLE and id in CMD_BOTTOM_ROW):
			continue
		out.append(id)
	return out


var _cmd_order: Array = CMD_ORDER.duplicate()


func _cmd_button(id: String, text: String, tip: String, toggle: bool, cb: Callable,
		hold: Callable = Callable()) -> Button:
	var b := Button.new()
	b.tooltip_text = "%s — %s" % [text, tip]
	b.toggle_mode = toggle


	if id == "chat":
		b.icon = HudTheme.chat_icon()
	elif id == "mic":
		b.icon = HudTheme.mic_icon()
	else:
		b.icon = load(CMD_ICONS[id])
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	HudTheme.style_icon_button(b)
	if hold.is_valid():


		HudTheme.wire_tap_hold(b, cb, hold)
	else:
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
		if world.additive_select:
			_end_click_mode()
		_update_mode_frame()
		_toast(tr("toast.add_select") % (tr("word.on") if world.additive_select else tr("word.off"))))
	_cmd_button("all", tr("cmd.all.label"), tr("cmd.all.tip"), false, func():
		_end_click_mode()
		_toast(tr("toast.all_units_count") % world.select_all_units())
		_show_selection_info())


	_cmd_button("harv", tr("cmd.harv.label"), tr("cmd.harv.tip"), false, _on_harvester_button)
	_cmd_button("clear", tr("cmd.clear.label"), tr("cmd.clear.tip"), false, func():
		_end_click_mode()
		world.additive_select = false
		_cmd_buttons["add"].button_pressed = false
		_update_mode_frame()
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
	var hub := NetHub.hub()
	if hub != null and (hub.active() or _test_voice):


		_mp_chat_btn = _cmd_button("chat", tr("cmd.chat.label"), tr("cmd.chat.tip"), false, _toggle_chat_input)


		_mp_mic_btn = _cmd_button("mic", tr("cmd.mic.label"), tr("cmd.mic.tip"), false,
				func(): _toggle_mic(false), func(): _toggle_mic(true))


	for id in CMD_HIDDEN + ([] if BOTTOM_ROW_VISIBLE else CMD_BOTTOM_ROW):
		if _cmd_buttons.has(id):
			_cmd_buttons[id].visible = false
		_cmd_order.erase(id)

	_mode_frame = Panel.new()
	_mode_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_frame.visible = false
	$UI.add_child(_mode_frame)


func _layout_top_comm(off: Vector2, m: float, icon_side: float, icon_box: Vector2) -> Dictionary:
	var gap := Dp.px(HudTheme.ICON_GAP_DP)
	var out := {"right": off.x + m + icon_side, "bottom": off.y + m + icon_side}
	var ids: Array = []
	for id in ["chat", "mic"]:
		if _cmd_buttons.has(id):
			ids.append(id)
	if ids.is_empty():
		return out


	var x := off.x + m + icon_side
	if x + ids.size() * (gap + icon_side) <= status_bar.position.x - m:
		for id in ids:
			x += gap


			HudTheme.place_touch(_cmd_buttons[id], Vector2(x, off.y + m), icon_box,
					Vector2(gap / 2.0, m / 2.0))
			x += icon_side
		out["right"] = x
		return out
	var y := off.y + m + icon_side
	for id in ids:
		y += gap
		HudTheme.place_touch(_cmd_buttons[id], Vector2(off.x + m, y), icon_box,
				Vector2(m / 2.0, gap / 2.0))
		y += icon_side
	out["bottom"] = y
	return out


func _layout_command_bar(vs: Vector2, m: float, off: Vector2, cols: int) -> void:
	var bw := Dp.px(CMD_BTN_W_DP)
	var bh := Dp.px(CMD_BTN_H_DP)
	var gap := Dp.px(HudTheme.ICON_GAP_DP)
	var x0 := off.x + m + minimap.size.x + m
	var y_bottom := vs.y - m - bh
	var rows := int(ceil(_cmd_order.size() / float(cols)))
	for i in _cmd_order.size():
		var b: Button = _cmd_buttons[_cmd_order[i]]
		var col := i % cols
		var row_from_bottom := rows - 1 - i / cols


		HudTheme.place_touch(b, Vector2(x0 + col * (bw + gap), y_bottom - row_from_bottom * (bh + gap)),
			Vector2(bw, bh), Vector2(gap, gap) / 2.0)


func _fit_bottom_bars(safe: Rect2, m: float) -> Dictionary:
	var bw := Dp.px(CMD_BTN_W_DP)
	var gap := Dp.px(HudTheme.ICON_GAP_DP)
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
	var cmd_rows := int(ceil(_cmd_order.size() / float(fit["cmd_cols"])))
	var cmd_h := cmd_rows * Dp.px(CMD_BTN_H_DP) + maxi(cmd_rows - 1, 0) * Dp.px(HudTheme.ICON_GAP_DP)
	var left := Dp.px(HUD_LEFT_DP)
	var top := Dp.px(HUD_TOP_DP)
	var right := m + bb.x
	var bottom := m + maxf(maxf(minimap.size.y, bb.y), cmd_h)


	var w := safe.size.x - left - right
	var h := safe.size.y - top - bottom
	if w <= 0.0 or h <= 0.0:
		return Rect2()
	return Rect2(safe.position + Vector2(left, top), Vector2(w, h))


func _update_mode_frame() -> void:
	var col := HudTheme.MODE_SELL
	if _click_mode == "repair":
		col = HudTheme.MODE_REPAIR
	elif _click_mode == "" and world != null and world.additive_select:
		col = HudTheme.MODE_ADD
	elif _click_mode == "":
		_mode_frame.visible = false
		_mode_frame_col = Color(0, 0, 0, 0)
		return
	if _mode_frame_col != col:
		_mode_frame_col = col
		_mode_frame.add_theme_stylebox_override("panel",
			HudTheme.panel(Color(0, 0, 0, 0), col, 0.0, HudTheme.MODE_BORDER_DP))
	_mode_frame.visible = true


func _set_click_mode(mode: String) -> void:
	if _click_mode == mode:
		_end_click_mode()
		return
	_click_mode = mode
	for id in ["sell", "repair"]:
		_cmd_buttons[id].button_pressed = _click_mode == id


	world.additive_select = false
	_cmd_buttons["add"].button_pressed = false
	_update_mode_frame()
	_toast(tr("toast.mode_tap_building") % (tr("word.sell_verb") if _click_mode == "sell" else tr("word.repair_verb")))


func _end_click_mode() -> void:
	if _click_mode == "":
		return
	_click_mode = ""
	for id in ["sell", "repair"]:
		_cmd_buttons[id].button_pressed = false
	_update_mode_frame()
	_toast(tr("toast.mode_off"))


const HARVESTER_DOUBLE_MS := 400


const HARVESTER_NEVER := -1000000
var _harv_last_tap := HARVESTER_NEVER

var _last_harv_cmd := ""


func _on_harvester_button() -> void:
	var now := Time.get_ticks_msec()
	var double_tap := now - _harv_last_tap <= HARVESTER_DOUBLE_MS

	_harv_last_tap = HARVESTER_NEVER if double_tap else now
	var count := world.own_harvester_count()
	if count == 0:
		_toast(tr("toast.no_harvester_owned"))
		return
	if double_tap:
		world.order_harvesters_resume()
		_toast(tr("toast.harv_resume") % count)
		world.sfx.play_harvester_voice("harv_resume")
		_last_harv_cmd = "resume"
	else:
		world.order_harvesters_return()
		_toast(tr("toast.harv_return") % count)
		world.sfx.play_harvester_voice("harv_return")
		_last_harv_cmd = "return"


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
var _test_ai_audit := false
var _audit_seen := {}
var _audit_errors := 0
var _audit_tick := 0
var _audit_crate_tick := 0
var _audit_notes := 0
var _test_cycle := false
var _test_speed := false
var _speed_t0 := -1.0
var _speed_tick0 := 0


var _test_speed_switch := -1
var _speed_switched := false


var _test_speed_ui := false


var _test_ai_start := -1


var _test_ai_count := false
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


var _demo_battle := 0
var _demo_shots := 0
var _demo_next_tick := 0
var _demo_delay := 60
var _demo_every := 12
var _demo_count := 30
var _demo_attackers := PackedInt32Array()
var _demo_rally := Vector2i.ZERO
var _demo_select := ""
var _demo_zap := false
var _demo_follow := false
var _demo_center := Vector2.ZERO


func _demo_units(rows: Array, player: int, origin: Vector2i, facing: int = -1,
		airborne: bool = false) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for row in rows:
		var u = world.spawn_unit(String(row[0]), player, origin + Vector2i(int(row[1]), int(row[2])),
				facing, 100, airborne)
		if u != null and u.id >= 0:
			ids.append(u.id)
	return ids


const DEMO_GROUND := [0, 1, 2, 6]


func _demo_land_ok(type: String, cell: Vector2i) -> bool:
	if not world.type_ids.has(type):
		return false
	var rows: PackedStringArray = String(world.types[type].get("footprint", "x")).split(" ")
	for y in rows.size():
		for x in rows[0].length():
			if not DEMO_GROUND.has(world.terrain_type(cell + Vector2i(x, y))):
				return false
	return true


func _demo_site(type: String, from: Vector2i, max_r: int = 10) -> Vector2i:
	for r in range(0, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dy) != r:
					continue
				if _demo_land_ok(type, from + Vector2i(dx, dy)):
					return from + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _demo_base(rows: Array, player: int, origin: Vector2i) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for row in rows:
		var type := String(row[0])
		if not world.type_ids.has(type):
			continue
		var cell := origin + Vector2i(int(row[1]), int(row[2]))
		if not _demo_land_ok(type, cell):
			cell = _demo_site(type, cell, 5)
		if cell.x < 0:
			continue
		var u = world.call("_add_building", type, player, cell)
		if u != null and u.id >= 0:
			ids.append(u.id)
	return ids


func _demo_water_cells(center: Vector2i, want: int, radius: int = 20) -> Array:
	var out: Array = []
	for r in range(0, radius):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dy) != r:
					continue
				var c := center + Vector2i(dx, dy)
				if world.terrain_type(c) != ProtoWorld.TER_WATER:
					continue
				var free := true
				for p in out:
					if (Vector2i(p) - c).length_squared() < 6:
						free = false
				if free:
					out.append(c)
				if out.size() >= want:
					return out
	return out


func _demo_show_hud() -> void:


	_auto_bar_enabled = false
	if build_bar != null and build_toggle != null:
		build_bar.visible = true
		build_toggle.button_pressed = true
	if _demo_select == "":
		return
	var list: Array = []
	for u in world.units:
		if u.alive and u.player == 0 and u.type == _demo_select and list.size() < 6:
			list.append(u)
	if not list.is_empty():
		world.select_units(list)


func _demo_camera(center: Vector2, zoom: float) -> void:
	world.zoom_at(clampf(zoom, ProtoWorld.MIN_ZOOM, ProtoWorld.MAX_ZOOM) / world.zoom,
			world.get_viewport_rect().size / 2.0)
	world.center_on(center * ProtoWorld.CELL)
	_demo_center = center


func _demo_track() -> void:
	var sum := Vector2.ZERO
	var n := 0
	for u in world.units:
		if not u.alive or (u.player != 0 and u.player != 1):
			continue
		if bool(world.types.get(u.type, {}).get("building", false)):
			continue
		var cell := u.pos / ProtoWorld.CELL
		if cell.distance_to(_demo_center) > 30.0:
			continue
		sum += cell
		n += 1
	if n > 0:
		world.center_on(sum / float(n) * ProtoWorld.CELL)


func _run_demo_battle() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		origin.x = clampi(origin.x, 24, world.map_w - 25)
		origin.y = clampi(origin.y, 14, world.map_h - 15)
		_test_origin = origin
		sim.give_credits(0, 50000)
		sim.give_credits(1, 50000)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)


		for u in world.units:
			if u.alive and u.player == 0:
				sim.remove_actor(u.id)


		var away: int = 22 if origin.y + 34 < world.map_h else -22
		var home := _demo_site("fact", origin + Vector2i(0, away), 22)
		if home.x < 0:
			home = _demo_site("fact", origin + Vector2i(0, -away), 22)
		if home.x >= 0:
			_demo_base([["fact", 0, 0], ["powr", 4, 0], ["powr", 4, 3], ["apwr", -4, 0],
					["dome", 0, 4], ["weap", 4, 6], ["barr", -4, 4], ["proc", -4, 8]], 0, home)
		match _demo_battle:
			2: _demo_scene_mammut(origin)
			3: _demo_scene_marine(origin)
			4: _demo_scene_luft(origin)
			5: _demo_scene_feld(origin)
			_: _demo_scene_tesla(origin)
		_demo_show_hud()
		_test_step = 1
		_demo_next_tick = tick + _demo_delay
		print("T%d --demo-battle %d: Aufbau fertig, erstes Bild bei Tick %d"
				% [tick, _demo_battle, _demo_next_tick])
	elif _test_step == 1 and tick >= _demo_next_tick:


		if _demo_zap and not _tesla_zap_now() and tick < _demo_next_tick + 60:
			return
		_demo_next_tick = tick + _demo_every

		if _demo_attackers.size() > 0 and _demo_shots % 5 == 0:
			sim.order_attack_move(_demo_attackers, _demo_rally.x, _demo_rally.y)
		if _demo_follow:
			_demo_track()
		if _screenshot_path != "":
			var path := "%s-%02d.png" % [_screenshot_path.get_basename(), _demo_shots]
			get_viewport().get_texture().get_image().save_png(path)
			print("T%d --demo-battle: Bild %s" % [tick, path])
		_demo_shots += 1
		if _demo_shots >= _demo_count:
			get_tree().quit()


func _demo_scene_tesla(origin: Vector2i) -> void:
	_demo_base([["powr", 7, -5], ["powr", 7, -2], ["powr", 7, 1], ["powr", 7, 4],
			["tsla", -2, -5], ["tsla", -2, 0], ["tsla", -2, 5],
			["barr", 5, -8], ["proc", 5, 6]], 0, origin)
	var own := _demo_units([["4tnk", 3, -4], ["4tnk", 3, -2], ["4tnk", 3, 2], ["4tnk", 3, 4],
			["ttnk", 1, -3], ["ttnk", 1, -1], ["ttnk", 1, 1], ["ttnk", 1, 3],
			["e1", 0, -5], ["e1", 0, 5], ["e3", 0, -2], ["e3", 0, 2], ["e4", 0, 0]], 0, origin, 768)
	var foe := _demo_units([["2tnk", -11, -4], ["2tnk", -11, -2], ["2tnk", -11, 0], ["2tnk", -11, 2],
			["2tnk", -11, 4], ["2tnk", -13, -3], ["2tnk", -13, -1], ["2tnk", -13, 1], ["2tnk", -13, 3],
			["1tnk", -15, -4], ["1tnk", -15, 4], ["arty", -17, -1], ["arty", -17, 1],
			["jeep", -12, -6], ["jeep", -12, 6],
			["e1", -9, -3], ["e1", -9, 3], ["e3", -9, -1], ["e3", -9, 1], ["e2", -10, 0]], 1, origin, 256)
	world.sim.order_attack_move(foe, origin.x + 2, origin.y)
	world.sim.order_attack_move(own, origin.x - 7, origin.y)
	_demo_attackers = foe
	_demo_rally = origin + Vector2i(2, 0)
	_demo_select = "ttnk"
	_demo_camera(Vector2(origin) + Vector2(-5.5, -0.5), 2.9)


func _demo_scene_mammut(origin: Vector2i) -> void:
	var base := origin + Vector2i(-13, 0)
	var walls := _demo_base([["fact", 0, -2], ["powr", 4, -5], ["powr", 4, -2], ["apwr", 4, 1],
			["proc", -4, 3], ["weap", -4, -4], ["dome", 0, 3], ["fix", 0, 6],
			["gun", 7, -2], ["gun", 7, 1], ["pbox", 6, -4], ["pbox", 6, 4],
			["agun", 2, -6], ["ftur", 7, 4]], 1, base)
	_demo_units([["2tnk", 9, -2], ["2tnk", 9, 2], ["1tnk", 9, 0],
			["e1", 8, -3], ["e1", 8, 3], ["e3", 8, 0]], 1, base, 768)
	var column := _demo_units([["4tnk", 0, -4], ["4tnk", 0, -2], ["4tnk", 0, 0], ["4tnk", 0, 2],
			["4tnk", 0, 4], ["4tnk", 3, -3], ["4tnk", 3, -1], ["4tnk", 3, 1], ["4tnk", 3, 3],
			["ttnk", 5, -2], ["ttnk", 5, 2], ["3tnk", 5, 0],
			["e4", 2, -5], ["e4", 2, 5], ["e2", 4, 0]], 0, origin, 256)
	var v2 := _demo_units([["v2rl", 7, -4], ["v2rl", 7, -2], ["v2rl", 7, 2], ["v2rl", 7, 4],
			["v2rl", 9, -1], ["v2rl", 9, 1]], 0, origin, 256)
	world.sim.order_attack_move(column, base.x + 6, base.y)

	if walls.size() > 0:
		for i in v2.size():
			world.sim.order_attack(PackedInt32Array([v2[i]]), walls[i % walls.size()], false, true)
	_demo_attackers = column
	_demo_rally = base + Vector2i(6, 0)
	_demo_select = "4tnk"
	_demo_camera(Vector2(origin) + Vector2(-4.5, 0.0), 2.3)


func _demo_scene_marine(origin: Vector2i) -> void:
	var water := _find_water_cell(origin, 3, 60)
	if water.x < 0:
		print("--demo-battle 3: kein Wasser in der Nähe — Karte mit Küste wählen")
		_demo_scene_tesla(origin)
		return
	var shore := _demo_site("fact", water, 18)
	if shore.x < 0:
		shore = origin
	var base := _demo_base([["fact", 0, 0], ["powr", -4, -3], ["powr", -4, 0], ["proc", -4, 3],
			["dome", 0, 4], ["tent", -4, -6], ["gun", 3, -2], ["gun", 3, 2], ["pbox", 3, 0],
			["agun", 0, -4], ["silo", -1, 7], ["fix", 4, 5]], 1, shore)
	_demo_units([["2tnk", 1, -2], ["1tnk", 2, 3], ["e1", -1, 0], ["e3", -1, 2]], 1, shore, 256)
	var spots := _demo_water_cells(water, 16, 24)
	var fleet := PackedInt32Array()
	var guards := PackedInt32Array()
	for i in spots.size():
		var cell: Vector2i = spots[i]
		if i < 5:
			var m = world.spawn_unit("msub", 0, cell, 256)
			if m != null and m.id >= 0:
				fleet.append(m.id)
		elif i < 9:
			var s = world.spawn_unit("ss", 0, cell, 256)
			if s != null and s.id >= 0:
				fleet.append(s.id)
		elif i < 13:
			var d = world.spawn_unit("dd", 1, cell, 768)
			if d != null and d.id >= 0:
				guards.append(d.id)
		else:
			var p = world.spawn_unit("pt", 1, cell, 768)
			if p != null and p.id >= 0:
				guards.append(p.id)
	if base.size() > 0 and fleet.size() > 0:
		for i in fleet.size():
			world.sim.order_attack(PackedInt32Array([fleet[i]]), base[i % base.size()], false, true)
	if guards.size() > 0 and fleet.size() > 0:
		world.sim.order_attack(guards, fleet[0], false, true)
	_demo_attackers = PackedInt32Array()
	_demo_select = "msub"


	var mid := Vector2.ZERO
	for c in spots:
		mid += Vector2(c)
	if not spots.is_empty():
		mid /= float(spots.size())
	else:
		mid = Vector2(water)
	_demo_camera(mid.lerp(Vector2(shore), 0.25), 2.6)


func _demo_scene_luft(origin: Vector2i) -> void:
	var base := origin + Vector2i(-14, 0)
	var targets := _demo_base([["fact", 0, -2], ["powr", 4, -5], ["powr", 4, -2], ["apwr", 4, 2],
			["proc", -4, 3], ["weap", -5, -4], ["dome", 0, 4], ["atek", -5, 6], ["hpad", 2, 6],
			["agun", 3, -7], ["agun", 3, 5], ["agun", -3, -6], ["agun", -6, 0],
			["pbox", 6, -1], ["pbox", 6, 2]], 1, base)
	_demo_units([["e1", 2, -4], ["e1", 2, 4], ["e3", 1, 0], ["2tnk", 5, 0]], 1, base, 768)
	_demo_units([["heli", -2, -3], ["heli", -2, 3]], 1, base, 768, true)
	var wing := _demo_units([["mig", 9, -4], ["mig", 10, -2], ["mig", 10, 2], ["mig", 9, 4],
			["yak", 13, -3], ["yak", 13, 0], ["yak", 13, 3]], 0, origin, 256, true)
	if targets.size() > 0:
		for i in wing.size():
			world.sim.order_attack(PackedInt32Array([wing[i]]), targets[i % targets.size()], false, true)
	_demo_attackers = PackedInt32Array()
	_demo_select = "mig"
	_demo_camera(Vector2(base) + Vector2(1.0, 0.0), 2.7)


func _demo_scene_feld(origin: Vector2i) -> void:
	_demo_base([["powr", 12, -6], ["powr", 12, -3], ["powr", 12, 0], ["powr", 12, 3],
			["tsla", 6, -6], ["tsla", 6, 0], ["tsla", 6, 6], ["barr", 11, 6]], 0, origin)
	_demo_base([["gun", -20, -4], ["gun", -20, 4], ["pbox", -19, 0], ["powr", -24, -2],
			["powr", -24, 2], ["tent", -24, 6]], 1, origin)
	var red := _demo_units([
			["4tnk", 3, -7], ["4tnk", 3, -5], ["4tnk", 3, 5], ["4tnk", 3, 7],
			["3tnk", 1, -6], ["3tnk", 1, -4], ["3tnk", 1, -2], ["3tnk", 1, 2], ["3tnk", 1, 4], ["3tnk", 1, 6],
			["ttnk", 3, -1], ["ttnk", 3, 1], ["ttnk", 5, -3], ["ttnk", 5, 3],
			["v2rl", 7, -4], ["v2rl", 7, -2], ["v2rl", 7, 2], ["v2rl", 7, 4],
			["e1", -1, -7], ["e1", -1, -5], ["e1", -1, -3], ["e1", -1, 3], ["e1", -1, 5], ["e1", -1, 7],
			["e2", 0, -1], ["e2", 0, 1], ["e4", -1, -1], ["e4", -1, 1],
			["dog", 0, -4], ["dog", 0, 4], ["ftrk", 5, -6], ["ftrk", 5, 6]], 0, origin, 256)
	var blue := _demo_units([
			["2tnk", -10, -7], ["2tnk", -10, -5], ["2tnk", -10, -3], ["2tnk", -10, 3],
			["2tnk", -10, 5], ["2tnk", -10, 7], ["2tnk", -12, -6], ["2tnk", -12, 6],
			["1tnk", -12, -4], ["1tnk", -12, -2], ["1tnk", -12, 2], ["1tnk", -12, 4],
			["arty", -14, -5], ["arty", -14, -2], ["arty", -14, 2], ["arty", -14, 5],
			["jeep", -9, -8], ["jeep", -9, 8], ["mech", -13, 0], ["mech", -13, 3],
			["e1", -7, -6], ["e1", -7, -4], ["e1", -7, -2], ["e1", -7, 2], ["e1", -7, 4], ["e1", -7, 6],
			["e3", -8, -3], ["e3", -8, -1], ["e3", -8, 1], ["e3", -8, 3],
			["e3", -6, -5], ["e3", -6, 5], ["e2", -6, -2], ["e2", -6, 2], ["e7", -11, 0]], 1, origin, 768)
	world.sim.order_attack_move(red, origin.x - 9, origin.y)
	world.sim.order_attack_move(blue, origin.x + 2, origin.y)
	_demo_attackers = blue
	_demo_rally = origin + Vector2i(2, 0)
	_demo_select = "4tnk"
	_demo_camera(Vector2(origin) + Vector2(-6.0, 0.0), 2.45)


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


func _run_test_ttnk() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 30000)
		var i := 0


		for t in ["powr", "powr", "apwr", "proc", "barr", "weap", "stek", "tsla"]:
			if world.type_ids.has(t):
				world.call("_add_building", t, 0, origin + Vector2i(-10 + i * 3, 5))
				i += 1
		_ttnk_origin = origin
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 100:

		build_bar.select_queue(ProtoWorld.Queue.VEHICLE)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 10:


		_test_step = 3
		_test_tick = tick

		var shown: Array = []
		for s3 in build_bar._slots:
			if s3.visible and s3.type_id >= 0:
				shown.append(world.type_names[s3.type_id])
		var ready_ids: PackedInt32Array = sim.buildable(0, ProtoWorld.Queue.VEHICLE)
		var buildable: bool = world.type_ids.has("ttnk") and ready_ids.has(world.type_ids["ttnk"])
		print("T%d --test-ttnk: Fraktion %s, Reiter %d: %s" % [tick, world.player_faction(), build_bar.kind, shown])
		print("T%d --test-ttnk: ttnk in der Leiste: %s, baubar: %s" % [
			tick, "ja" if shown.has("ttnk") else "NEIN", "ja" if buildable else "NEIN"])
		if _screenshot_path != "":
			await get_tree().process_frame
			await get_tree().process_frame
			var bar_path: String = _screenshot_path.get_basename() + "_leiste.png"
			get_viewport().get_texture().get_image().save_png(bar_path)
			print("T --test-ttnk: Bauleiste, Screenshot %s" % bar_path)
	elif _test_step == 3 and tick >= _test_tick + 10:

		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		for k in 4:
			world.spawn_unit("e1", 1, _ttnk_origin + Vector2i(6, -3 + k))
		world.spawn_unit("3tnk", 1, _ttnk_origin + Vector2i(6, 2))
		var tank: ProtoWorld.Unit = world.spawn_unit("ttnk", 0, _ttnk_origin + Vector2i(1, 0))
		if tank != null:
			world.select_only(tank)
		build_bar.select_queue(ProtoWorld.Queue.BUILDING)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(_ttnk_origin) + Vector2(3.5, 0.0)) * ProtoWorld.CELL)
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4:
		if sim.alive_count(1) == 0:
			print("T%d --test-ttnk: alle Ziele zerstört" % tick)
			get_tree().quit()
			return
		if _tesla_shot_frames < 0 and _ttnk_zap_now():
			_tesla_shot_frames = Engine.get_process_frames()
		if _tesla_shot_frames >= 0 and _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("T%d --test-ttnk: Blitz sichtbar, Screenshot %s" % [tick, _screenshot_path])
			get_tree().quit()
		elif tick > _test_tick + 400:
			print("T%d --test-ttnk: kein Blitz gesehen (Ziele übrig: %d)" % [tick, sim.alive_count(1)])
			get_tree().quit()


var _ttnk_origin := Vector2i.ZERO


func _ttnk_zap_now() -> bool:
	for u in world.units:
		if u.alive and u.type == "ttnk" and u.firing:
			return true
	return false


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


		for i in 8:
			world.call("_add_building", "powr", 0, origin + Vector2i(-6 - (i / 4) * 3, (i % 4) * 3))
		world.call("_add_building", "mslo", 0, origin + Vector2i(6, 0))
		world.call("_add_building", "dome", 0, origin + Vector2i(-6, 12))


		for i in ["iron", "pdox", "atek"]:
			if world.type_ids.has(i):
				world.call("_add_building", i, 0, origin + Vector2i(6, 4 + ["iron", "pdox", "atek"].find(i) * 4))
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


		var silo0: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "mslo":
				silo0 = u
				break
		if silo0 != null:
			world.center_on(silo0.pos)
			build_bar.visible = false
			if _sp_panel != null:
				_sp_panel.visible = false
			_test_step = 25
			_cd_wait = 30
			return
	elif _test_step == 25:
		if _cd_wait > 0:
			_cd_wait -= 1
			return
		_shot("silo-vorher")
		if not world.activate_support_power(2, (Vector2(_test_nuke_target) + Vector2(0.5, 0.5)) * ProtoWorld.CELL):
			print("T --test-nuke: Abfeuern fehlgeschlagen")
			get_tree().quit()
			return
		print("T%d --test-nuke: Rakete gestartet, Ziel %s, sichtbare Superwaffen=%s" % [
			sim.tick(), _test_nuke_target, _sp_panel.visible_kinds() if _sp_panel != null else []])


		var silo: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "mslo":
				silo = u
				break
		if silo != null:
			world.center_on(silo.pos)


			build_bar.visible = false
			if _sp_panel != null:
				_sp_panel.visible = false
			print("T%d --test-nuke: Silo bei %s (Bildschirm %s), Kamera auf %s" % [
					sim.tick(), silo.pos / ProtoWorld.CELL, world.world_to_screen(silo.pos),
					world.visible_world_rect().get_center() / ProtoWorld.CELL])
		else:
			print("T --test-nuke: kein Silo gefunden (Kamera bleibt am Ziel)")

		_test_step = 3
		_cd_wait = 1
	elif _test_step == 3:
		if _cd_wait > 0:
			_cd_wait -= 1
			return
		if _screenshot_path != "":
			var start_path: String = _screenshot_path.get_basename() + "_start.png"
			get_viewport().get_texture().get_image().save_png(start_path)
			print("T%d --test-nuke: Start am Silo (Klappe + aufsteigende Rakete), Screenshot %s" % [
					sim.tick(), start_path])
		build_bar.visible = true
		if _sp_panel != null:
			_sp_panel.visible = true
		world.center_on((Vector2(_test_nuke_target) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 4
	elif _test_step == 4:
		var nukes: PackedInt32Array = sim.pending_nukes()
		if nukes.size() < 4:
			print("T%d --test-nuke: kein pending_nukes()-Eintrag während des Flugs" % tick)
			get_tree().quit()
			return
		if _screenshot_path != "":
			var flight_path: String = _screenshot_path.get_basename() + "_flug.png"
			get_viewport().get_texture().get_image().save_png(flight_path)
			print("T%d --test-nuke: im Flug (Restticks %d), Screenshot %s" % [tick, nukes[3], flight_path])
		_test_step = 5
	elif _test_step == 5:
		var nukes: PackedInt32Array = sim.pending_nukes()
		if nukes.is_empty():


			_test_step = 6
	elif _test_step == 6:
		var flash: float = world.nuke_flash()
		if _screenshot_path != "":
			var impact_path: String = _screenshot_path.get_basename() + "_einschlag.png"
			get_viewport().get_texture().get_image().save_png(impact_path)
			print("T%d --test-nuke: Einschlag, weißer Blitz=%.2f s (Sollwert > 0), Screenshot %s %s" % [
					tick, flash, impact_path, "OK" if flash > 0.0 else "FEHLER"])
		else:
			print("T%d --test-nuke: Einschlag, weißer Blitz=%.2f s (Sollwert > 0) %s" % [
					tick, flash, "OK" if flash > 0.0 else "FEHLER"])
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
	call_deferred("_run_test_placement_geometrie")


const PLACEMENT_GEOMETRY_TYPES := ["silo", "sam", "pdox", "afld", "fix", "powr", "fact"]


func _run_test_placement_geometrie() -> void:
	var sim = world.sim
	var fehler := 0
	var stellen := [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]
	for t in PLACEMENT_GEOMETRY_TYPES:
		if not world.type_ids.has(t):
			print("T --test-placement Geometrie: %-5s fehlt in rules.json — übersprungen" % t)
			continue
		var tid: int = world.type_ids[t]
		var td: Dictionary = world.types[t]
		var rows: PackedStringArray = String(td["footprint"]).split(" ")
		var fw := rows[0].length()
		var fh := rows.size()
		var b: Vector2 = td.get("bounds", Vector2(ProtoWorld.CELL, ProtoWorld.CELL))
		var bw := int(round(b.x / ProtoWorld.CELL))
		var bh := int(round(b.y / ProtoWorld.CELL))

		var zelle := Vector2i(40, 30)
		var mitte_soll := zelle - Vector2i(int(floor((bw - 1) / 2.0)), int(floor((bh - 1) / 2.0)))
		world.begin_placement(tid)
		var geo_ok := true
		var abw := PackedStringArray()
		for s in stellen:
			var wp: Vector2 = (Vector2(zelle) + s) * ProtoWorld.CELL
			world.move_placement(wp)
			var soll := Vector2i(floori(zelle.x + s.x - (bw - 1) / 2.0), floori(zelle.y + s.y - (bh - 1) / 2.0))
			var o: Vector2i = world.place_origin
			var drin: bool = o.x <= zelle.x and zelle.x < o.x + fw and o.y <= zelle.y and zelle.y < o.y + fh
			if o != soll or not drin:
				geo_ok = false
				abw.append("%s→%s(soll %s%s)" % [s, o, soll, "" if drin else ", Zeiger außerhalb"])
		if not geo_ok:
			fehler += 1
		print("T --test-placement Geometrie: %-5s %d×%d (Sprite %d×%d) Zeiger %s → Ursprung %s (Sollwert %s) %s%s" % [
			t, fw, fh, bw, bh, zelle, world.place_origin, mitte_soll,
			"OK" if geo_ok else "FEHLER", "" if geo_ok else " " + " ".join(abw)])
		world.cancel_placement()

		var frei := _placement_free_cell(tid, Vector2i(40, 35))
		if frei.x < 0:
			print("T --test-placement Geometrie: %-5s keine freie Zelle — Tipp-Probe übersprungen" % t)
			continue
		var zeiger := frei + Vector2i(int(floor((bw - 1) / 2.0)), int(floor((bh - 1) / 2.0)))
		var zp: Vector2 = (Vector2(zeiger) + Vector2(0.5, 0.5)) * ProtoWorld.CELL
		world.begin_placement(tid)
		world.place_armed = false
		var erster: bool = world.tap_placement(zp)
		var gesetzt: Vector2i = world.place_origin
		var zweiter: bool = world.tap_placement(zp)
		var tipp_ok: bool = not erster and gesetzt == frei and zweiter
		if not tipp_ok:
			fehler += 1
		print("T --test-placement Geometrie: %-5s Tipp auf %s → Ursprung %s (Sollwert %s), zweiter Tipp baut=%s %s" % [
			t, zeiger, gesetzt, frei, zweiter, "OK" if tipp_ok else "FEHLER"])
		world.cancel_placement()


	var sid: int = world.type_ids.get("silo", -1)
	if not Desktop.has_keyboard():
		print("T --test-placement Geometrie: kein Desktop — Hover-Probe übersprungen")
	elif sid < 0:
		print("T --test-placement Geometrie: silo fehlt — Hover-Probe übersprungen")
	else:
		sim.give_credits(0, 20000)
		var frei2 := _placement_free_cell(sid, Vector2i(40, 35))
		if build_bar.ready_building() != sid:
			world.queue_build(sid)
			for _t in 20000:
				sim.step()
				if build_bar.ready_building() == sid:
					break
		await get_tree().process_frame
		if frei2.x < 0 or build_bar.ready_building() != sid:
			print("T --test-placement Geometrie: Silo nicht fertig oder keine freie Zelle — Hover-Probe übersprungen")
		else:


			var fenster_vorher := get_window().size
			get_window().size = Vector2i(1280, 720)
			for _f in 3:
				await get_tree().process_frame
			_begin_placement(sid)
			world.center_on(world.placement_pos_for("silo", frei2))
			await get_tree().process_frame
			await get_tree().process_frame
			var sp := world.world_to_screen((Vector2(frei2) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
			var mm := InputEventMouseMotion.new()
			mm.position = sp
			mm.global_position = sp
			Input.parse_input_event(mm)
			await get_tree().process_frame
			var hover_ok: bool = world.placing_type == sid and world.place_origin == frei2 and world.place_armed
			if not hover_ok:
				fehler += 1
			print("T --test-placement Geometrie: Maus auf Zelle %s → Geist auf %s (Sollwert %s), bereit=%s %s" % [
				frei2, world.place_origin, frei2, world.place_armed, "OK" if hover_ok else "FEHLER"])
			for gedrueckt in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = gedrueckt
				mb.position = sp
				mb.global_position = sp
				Input.parse_input_event(mb)
				await get_tree().process_frame
				await get_tree().process_frame
			for _t in 5:
				sim.step()
			await get_tree().process_frame


			var steht := false
			for u in world.units:
				if u.alive and u.player == 0 and u.type == "silo" and world.placement_origin_of("silo", u.pos) == frei2:
					steht = true
					break
			var gebaut: bool = world.placing_type < 0 \
					and (steht or not sim.pending_place(0, ProtoWorld.Queue.BUILDING).is_empty())
			if not gebaut:
				fehler += 1
				world.cancel_placement()
				world.cancel_build(ProtoWorld.Queue.BUILDING, sid)
			print("T --test-placement Geometrie: Linksklick auf dieselbe Stelle → gebaut=%s, Platzierung beendet=%s %s" % [
				gebaut, world.placing_type < 0, "OK" if gebaut else "FEHLER"])
			_end_placement("T Geistbild-Geometrie geprüft")
			get_window().size = fenster_vorher
			await get_tree().process_frame
	print("T --test-placement Geometrie: %d Befund(e) (Sollwert 0)" % fehler)
	call_deferred("_run_test_placement_tap")


func _placement_free_cell(type_id: int, probe: Vector2i) -> Vector2i:
	for r in range(0, 26):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := probe + Vector2i(dx, dy)
				var res: PackedByteArray = world.sim.can_place(0, type_id, c.x, c.y)
				if res.size() > 0 and res[0] == 1:
					return c
	return Vector2i(-1, -1)


func _run_test_forcefire() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		var origin := Vector2i(30, 30)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		var shooter := _spawn_force_test("3tnk", 0, Vector2i(0, 0))
		if shooter == null:
			shooter = _spawn_force_test("1tnk", 0, Vector2i(0, 0))
		var victim := _spawn_force_test("3tnk", 0, Vector2i(3, 0))
		if victim == null:
			victim = _spawn_force_test("1tnk", 0, Vector2i(3, 0))
		if shooter == null or victim == null:
			print("T --test-forcefire: kein Panzer in rules.json — abgebrochen")
			get_tree().quit()
			return
		_force_shooter = shooter.id
		_force_victim = victim.id
		_force_hp0 = victim.hp
		world.select_only(shooter)
		world.center_on(shooter.pos)

		world.order_attack(victim)
		print("T --test-forcefire: ohne Zwangsfeuer force_attacking=%s (erwartet false)" % sim.force_attacking(shooter.id))
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 90:
		var victim := world.unit_by_id(_force_victim)
		var unhurt: bool = victim != null and victim.hp >= _force_hp0 - 0.001
		print("T --test-forcefire: ohne Zwangsfeuer Ziel bei %.0f %% (vorher %.0f %%) %s" % [
				(victim.hp if victim != null else 0.0) * 100.0, _force_hp0 * 100.0,
				"OK" if unhurt else "FEHLER"])

		var shooter := world.unit_by_id(_force_shooter)
		if shooter != null:
			world.select_only(shooter)
		_on_long_press(world.world_to_screen(victim.pos))
		var has_item: bool = radial.visible and radial.ITEMS.has("force_attack")
		print("T --test-forcefire: Radialmenü offen=%s, Eintrag Zwangsangriff=%s %s" % [
				radial.visible, has_item, "OK" if has_item else "FEHLER"])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 4:

		_shot("radial")
		_on_radial("force_attack")
		radial.cancel()
		var v0 := world.unit_by_id(_force_victim)
		if v0 != null:
			world.center_on(v0.pos)
		print("T --test-forcefire: mit Zwangsfeuer force_attacking=%s (erwartet true)" % world.sim.force_attacking(_force_shooter))
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 150:
		var victim2 := world.unit_by_id(_force_victim)
		var hp: float = victim2.hp if victim2 != null and victim2.alive else 0.0
		var hurt: bool = hp < _force_hp0 - 0.001
		print("T --test-forcefire: eigene Einheit %.0f %% → %.0f %% %s" % [
				_force_hp0 * 100.0, hp * 100.0, "OK" if hurt else "FEHLER"])
		_shot("treffer")

		var b: ProtoWorld.Unit = null
		if world.type_ids.has("powr"):
			b = world.call("_add_building", "powr", 0, _test_origin + Vector2i(0, 5))
		if b == null:
			print("T --test-forcefire: kein eigenes Gebäude setzbar — Gebäudeteil übersprungen")
			get_tree().quit()
			return
		_force_victim = b.id
		_force_hp0 = b.hp
		var shooter2 := world.unit_by_id(_force_shooter)
		if shooter2 != null:
			world.select_only(shooter2)
			world.center_on(shooter2.pos)
		_on_long_press(world.world_to_screen(b.pos))
		print("T --test-forcefire: Gebäude — Radialmenü offen=%s, Eintrag=%s" % [
				radial.visible, radial.visible and radial.ITEMS.has("force_attack")])
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 4:
		_shot("radial_gebaeude")
		_on_radial("force_attack")
		radial.cancel()
		var b0 := world.unit_by_id(_force_victim)
		if b0 != null:
			world.center_on(b0.pos)
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5 and tick >= _test_tick + 250:
		var b2 := world.unit_by_id(_force_victim)
		var bhp: float = b2.hp if b2 != null and b2.alive else 0.0
		var bhurt: bool = bhp < _force_hp0 - 0.001
		print("T --test-forcefire: eigenes Gebäude %.0f %% → %.0f %% %s" % [
				_force_hp0 * 100.0, bhp * 100.0, "OK" if bhurt else "FEHLER"])
		_shot("gebaeude")
		get_tree().quit()


const WALL_TYPES := ["sbag", "fenc", "brik", "cycl", "barb", "wood"]
var _test_wall := false
var _wall_tank = null
var _wall_cases: Array = []
var _wall_case := 0
var _wall_report: Array = []


func _wall_owner_of(name: String) -> int:
	match name:
		"eigen": return 0
		"verbündet": return 3
		"neutral": return ProtoWorld.PLAYER_NEUTRAL
		_: return 1


func _run_test_wall() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 20000)
		sim.set_alliance(0, 3, true)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)

		var owners := ["eigen", "verbündet", "neutral", "feindlich"]
		var row := 0
		for oname in owners:
			var col := 0
			for wt in WALL_TYPES:
				var cell: Vector2i = origin + Vector2i(-9 + col * 2, -8 + row * 2)
				var u = world.call("_add_building", wt, _wall_owner_of(oname), cell)
				if u != null:
					_wall_report.append({"type": wt, "owner": oname, "unit": u})
				col += 1
			row += 1
		_wall_tank = world.spawn_unit("2tnk", 0, origin + Vector2i(6, 0))
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 20:
		var bad := 0
		for e in _wall_report:
			var u = e["unit"]
			var pick: bool = world.pickable(u)
			var hit = world.pick_unit(world.unit_rect(u).get_center(), 0.0)
			var got: bool = hit != null and hit.id == u.id
			var foe: bool = world.hostile(world.local_player, u.player)
			e["pick"] = pick
			e["got"] = got
			if not pick or not got:
				bad += 1
			print("T --test-wall: %-4s %-10s pickable=%s Tipp trifft=%s feindlich=%s %s" % [
					e["type"], e["owner"], pick, got, foe, "OK" if pick and got else "FEHLER"])
		print("T --test-wall: %d von %d Kombinationen antippbar %s" % [
				_wall_report.size() - bad, _wall_report.size(), "OK" if bad == 0 else "FEHLER"])


		for oname in ["feindlich", "eigen", "verbündet", "neutral"]:
			for e in _wall_report:
				if e["type"] == "sbag" and e["owner"] == oname and e["unit"].alive:
					_wall_cases.append({"unit": e["unit"], "owner": oname})
					break
		print("T --test-wall: %d Angriffsfälle vorbereitet (erwartet 4) %s" % [
				_wall_cases.size(), "OK" if _wall_cases.size() == 4 else "FEHLER"])
		_wall_case = 0
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 10:
		if _wall_case >= _wall_cases.size():
			_test_step = 4
			_test_tick = tick
			return
		var c: Dictionary = _wall_cases[_wall_case]
		var target = c["unit"]
		c["hp0"] = target.hp
		world.select_only(_wall_tank)
		sim.teleport(_wall_tank.id, int(target.pos.x / ProtoWorld.CELL) - 3, int(target.pos.y / ProtoWorld.CELL))
		world.center_on(target.pos)
		if c["owner"] == "feindlich":

			_on_tap(world.world_to_screen(target.pos))
			c["weg"] = "Tipp"
		else:

			_on_long_press(world.world_to_screen(target.pos))
			c["radial"] = radial.visible and radial.ITEMS.has("force_attack")
			radial.cancel()
			_on_radial("force_attack")
			c["weg"] = "Langdruck → Zwangsfeuer"
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:
		var c: Dictionary = _wall_cases[_wall_case]
		var target = c["unit"]
		if target.alive and tick < _test_tick + 900:
			return
		var ok: bool = not target.alive
		print("T --test-wall: sbag %-10s über %-22s → zerstört=%s nach %d Ticks%s %s" % [
				c["owner"], c["weg"], not target.alive, tick - _test_tick,
				("" if not c.has("radial") else ", Ring bot Zwangsfeuer=%s" % c["radial"]),
				"OK" if ok else "FEHLER"])
		_wall_case += 1
		_test_step = 2
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 10:

		var tree = _find_decoration()
		if tree != null:
			print("T --test-wall: Baum/Feld %s pickable=%s (muss false sein) %s" % [
					tree.type, world.pickable(tree), "OK" if not world.pickable(tree) else "FEHLER"])
		else:
			print("T --test-wall: keine reine Dekoration auf der Karte — Gegenprobe übersprungen")

		var own_wall = null
		for e in _wall_report:
			if e["owner"] == "eigen" and e["unit"].alive:
				own_wall = e["unit"]
				break
		if own_wall != null and _wall_tank != null and _wall_tank.alive:
			world.select_only(_wall_tank)
			_on_tap(world.world_to_screen(own_wall.pos))
			var keeps: bool = world.selection.size() == 1 and world.selection[0].id == _wall_tank.id
			print("T --test-wall: Tipp auf die eigene Mauer lässt die Auswahl stehen=%s (^Wall ohne Selectable) %s" % [
					keeps, "OK" if keeps else "FEHLER"])
		print("T --test-wall: fertig")
		get_tree().quit()


var _test_build_area := false


func _bau_footprint_free(type: String, c: Vector2i) -> bool:
	var r: PackedByteArray = world.sim.can_place(0, world.type_ids[type], c.x, c.y)
	if r.size() < 2:
		return false
	for i in range(1, r.size()):
		if r[i] == 0:
			return false
	return true


func _bau_ok(type: String, c: Vector2i) -> bool:
	var r: PackedByteArray = world.sim.can_place(0, world.type_ids[type], c.x, c.y)
	return r.size() > 0 and r[0] == 1


func _bau_dist(c: Vector2i, org: Vector2i, w: int, h: int) -> int:
	var dx: int = maxi(maxi(org.x - c.x, c.x - (org.x + w - 1)), 0)
	var dy: int = maxi(maxi(org.y - c.y, c.y - (org.y + h - 1)), 0)
	return maxi(dx, dy)


func _bau_free_ring(type: String, org: Vector2i, w: int, h: int, r: int) -> Vector2i:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(org.x + dx, org.y + dy)
			if _bau_dist(c, org, w, h) == r and _bau_footprint_free(type, c):
				return c
	return Vector2i(-1, -1)


func _bau_look_at(c: Vector2i) -> void:
	world.center_on(Vector2(c) * ProtoWorld.CELL)
	await get_tree().create_timer(0.8).timeout


func _run_test_build_area() -> void:
	var sim = world.sim
	if _test_step != 0 or sim.tick() < 10:
		return
	_test_step = 1
	var fehler := 0
	_place_test_fact()
	sim.give_credits(0, 50000)
	var fact = null
	for u in world.units:
		if u.alive and u.player == 0 and u.type == "fact":
			fact = u
			break
	if fact == null:
		print("T --test-build-area: kein Bauhof auf der Karte — FEHLER")
		get_tree().quit()
		return
	var fo := Vector2i(world.unit_rect(fact).position / ProtoWorld.CELL)
	var ft: Dictionary = world.types["fact"]
	var fw: int = int(String(ft["footprint"]).split(" ")[0].length())
	var fh: int = int(ft["sprite_h"])
	print("T --test-build-area: Bauhof %s, Fußabdruck %d×%d" % [fo, fw, fh])


	var ohne: Array = []
	for n in world.types.keys():
		var t: Dictionary = world.types[n]
		if t.get("building", false) and not t.get("decoration", false) and not t.get("gives_buildable_area", false):
			ohne.append(n)
	ohne.sort()
	print("T --test-build-area: keine Baufläche (%d Typen): %s" % [ohne.size(), ", ".join(ohne)])
	for n in ohne:
		if not world.types[n].get("wall", false):
			print("T --test-build-area: %s gibt keine Baufläche, ist aber keine Mauer — FEHLER" % n)
			fehler += 1
	for n in ["fact", "powr", "proc", "silo", "tsla", "gun", "pbox", "kenn", "spen", "syrd"]:
		if world.types.has(n) and not world.types[n].get("gives_buildable_area", false):
			print("T --test-build-area: %s gibt keine Baufläche (Sollwert ja) — FEHLER" % n)
			fehler += 1
	for n in ["sbag", "fenc", "brik", "cycl", "barb", "wood"]:
		if world.types.has(n) and world.types[n].get("gives_buildable_area", false):
			print("T --test-build-area: %s ist eine Mauer und gibt trotzdem Baufläche — FEHLER" % n)
			fehler += 1


	const R := 20
	var karte: Array = []
	for probe in ["sbag", "silo"]:
		if not world.type_ids.has(probe):
			continue
		var frei := 0
		var ok := 0
		var maxd := 0
		var zeilen: Array = []
		for y in range(fo.y - R, fo.y + fh + R):
			var line := ""
			for x in range(fo.x - R, fo.x + fw + R):
				var c := Vector2i(x, y)
				var f: bool = _bau_footprint_free(probe, c)
				var o: bool = f and _bau_ok(probe, c)
				if f:
					frei += 1
				if o:
					ok += 1
					maxd = maxi(maxd, _bau_dist(c, fo, fw, fh))
				line += ("+" if o else ("." if f else "#"))
			zeilen.append(line)
		print("T --test-build-area: %-4s %d von %d freien Zellen erlaubt, größter Abstand zum Bauhof %d Zellen" % [
				probe, ok, frei, maxd])
		if probe == "silo":
			karte = zeilen
	if not karte.is_empty():
		print("T --test-build-area: Karte für silo (+ erlaubt, . frei aber außerhalb, # belegt/Terrain):")
		for line in karte:
			print("T   " + line)


	var tp := _bau_free_ring("tsla", fo, fw, fh, 2)
	if tp.x < 0 or not world.type_ids.has("tsla"):
		print("T --test-build-area: keine freie Stelle für die Teslaspule — Schritt 3 übersprungen")
	else:
		world.call("_add_building", "tsla", 0, tp)


		var weiter := Vector2i(-1, -1)
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var c: Vector2i = tp + d
			if _bau_footprint_free("tsla", c) and _bau_dist(c, fo, fw, fh) > 2:
				weiter = c
				break
		if weiter.x < 0:
			print("T --test-build-area: keine zweite Stelle hinter der Spule — übersprungen")
		else:
			var tok: bool = _bau_ok("tsla", weiter)
			print("T --test-build-area: Teslaspule auf %s als Anker → zweite Spule auf %s erlaubt=%s (Sollwert true) %s" % [
					tp, weiter, tok, "OK" if tok else "FEHLER"])
			if not tok:
				fehler += 1
	var mp := _bau_free_ring("sbag", fo, fw, fh, 7)
	if mp.x < 0 or not world.type_ids.has("sbag"):
		print("T --test-build-area: keine freie Stelle für die Mauer — Gegenprobe übersprungen")
	else:
		world.call("_add_building", "sbag", 0, mp)
		var hinter := Vector2i(-1, -1)
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var c2: Vector2i = mp + d
			if _bau_footprint_free("silo", c2) and _bau_dist(c2, fo, fw, fh) > 4:
				hinter = c2
				break
		if hinter.x >= 0:
			var sok: bool = _bau_ok("silo", hinter)
			print("T --test-build-area: Mauer auf %s als Anker → Silo auf %s erlaubt=%s (Sollwert false) %s" % [
					mp, hinter, sok, "OK" if not sok else "FEHLER"])
			if sok:
				fehler += 1


	var kette := 0
	var richtung := Vector2i.ZERO
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var frei2 := 0
		var probe: Vector2i = fo + d
		for i in 30:
			if not _bau_footprint_free("silo", probe):
				break
			frei2 += 1
			probe += d
		if frei2 > kette:
			kette = frei2
			richtung = d
	kette = 0
	if richtung == Vector2i.ZERO:
		print("T --test-build-area: keine freie Richtung für die Silo-Kette — Schritt 4 übersprungen")
	else:
		var c3: Vector2i = fo + richtung * 2
		for i in 30:
			if not _bau_footprint_free("silo", c3) or not _bau_ok("silo", c3):
				break
			world.call("_add_building", "silo", 0, c3)
			kette = _bau_dist(c3, fo, fw, fh)
			c3 += richtung
		print("T --test-build-area: Silo-Kette nach %s reicht %d Zellen vom Bauhof weg (früherer Bauhof-Kreis: 16) %s" % [
				richtung, kette, "OK" if kette > 16 else "FEHLER"])
		if kette <= 16:
			fehler += 1


	if not _auto_bar_enabled:
		print("T --test-build-area: Automatik ausgeschaltet — Schritt 5 übersprungen")
	else:
		var leer := Vector2i(world.bounds.position) + Vector2i(3, 3)
		if _bau_dist(leer, fo, fw, fh) < 30:
			leer = Vector2i(world.bounds.end) - Vector2i(3, 3)
		await _bau_look_at(fo)
		var auf1: bool = build_bar.visible
		print("T --test-build-area: Bauhof im Bild → Leiste offen=%s (Sollwert true) %s" % [
				auf1, "OK" if auf1 else "FEHLER"])
		if not auf1:
			fehler += 1
		await _bau_look_at(leer)
		var zu1: bool = not build_bar.visible
		print("T --test-build-area: Kamera in der Leere (%s), Baufläche im Bild=%s → Leiste zu=%s (Sollwert true) %s" % [
				leer, world.build_area_in_view(), zu1, "OK" if zu1 else "FEHLER"])
		if not zu1:
			fehler += 1


		_toggle_build_bar()
		var auf2: bool = build_bar.visible
		await get_tree().create_timer(0.8).timeout
		var bleibt: bool = build_bar.visible
		print("T --test-build-area: von Hand aufgeklappt=%s, bleibt ohne Kameraschwenk offen=%s (Sollwert true/true) %s" % [
				auf2, bleibt, "OK" if auf2 and bleibt else "FEHLER"])
		if not (auf2 and bleibt):
			fehler += 1
		await _bau_look_at(fo)

		_toggle_build_bar()
		await get_tree().create_timer(0.8).timeout
		var zu2: bool = not build_bar.visible
		print("T --test-build-area: von Hand zugeklappt bei sichtbarem Bauhof → bleibt zu=%s (Sollwert true) %s" % [
				zu2, "OK" if zu2 else "FEHLER"])
		if not zu2:
			fehler += 1

		await _bau_look_at(leer)
		await _bau_look_at(fo)
		var auf3: bool = build_bar.visible
		print("T --test-build-area: Bauhof nach dem Wegschwenken wieder im Bild → Leiste offen=%s (Sollwert true) %s" % [
				auf3, "OK" if auf3 else "FEHLER"])
		if not auf3:
			fehler += 1

		var pid: int = world.type_ids.get("powr", -1)
		if pid >= 0:
			world.queue_build(pid)
			build_bar.visible = false
			var q0: PackedInt32Array = sim.queue_state(0, 0)
			for _t in 120:
				sim.step()
			var q1: PackedInt32Array = sim.queue_state(0, 0)
			var laeuft: bool = q1.size() >= 7 and q0.size() >= 7 and (q1[1] > q0[1] or q1[2] == 1)
			print("T --test-build-area: Produktion bei zugeklappter Leiste läuft weiter=%s (Fortschritt %d → %d) %s" % [
					laeuft, q0[1] if q0.size() > 1 else -1, q1[1] if q1.size() > 1 else -1,
					"OK" if laeuft else "FEHLER"])
			if not laeuft:
				fehler += 1


	if not Desktop.has_keyboard():
		print("T --test-build-area: kein Desktop — Schritt 6 übersprungen")
	else:


		var fenster6 := get_window().size
		get_window().size = Vector2i(1280, 720)
		for _f in 3:
			await get_tree().process_frame
		var pid2: int = world.type_ids.get("powr", -1)
		build_bar.visible = true
		build_bar.select_queue(ProtoWorld.Queue.BUILDING)
		_hover_declined = -1
		await _bau_look_at(fo)
		if pid2 >= 0 and build_bar.ready_building() < 0:
			world.queue_build(pid2)
			for _t in 2000:
				sim.step()
				if build_bar.ready_building() >= 0:
					break
		await get_tree().process_frame
		var fertig: int = build_bar.ready_building()
		print("T --test-build-area: fertiges Gebäude in der Leiste: %s, Platzierung läuft=%s" % [
				world.type_names[fertig] if fertig >= 0 else "keins", _confirm_mode == "place"])
		var gut := _bau_free_ring("powr", fo, fw, fh, 2)
		var maus := func(p2: Vector2) -> void:
			var mm := InputEventMouseMotion.new()
			mm.position = p2
			mm.global_position = p2
			Input.parse_input_event(mm)
			await get_tree().process_frame


		var pname: String = world.type_names[fertig] if fertig >= 0 else "powr"
		var zelle := func(c: Vector2i) -> Vector2:
			return world.world_to_screen(world.placement_pos_for(pname, c))
		if fertig < 0 or gut.x < 0:
			print("T --test-build-area: nichts fertig oder keine freie Zelle — Schritt 6 übersprungen")
		else:

			await maus.call(zelle.call(gut))
			var h1: bool = world.placing_type == fertig and world.place_origin == gut and world.placement_ok()
			print("T --test-build-area: Maus über gültiger Zelle %s → Geist auf %s, baubar=%s (Sollwert %s/true) %s" % [
					gut, world.place_origin, world.placement_ok(), gut, "OK" if h1 else "FEHLER"])
			if not h1:
				fehler += 1

			var weit2 := Vector2i(world.bounds.position) + Vector2i(4, 4)
			await maus.call(zelle.call(weit2))
			var h2: bool = not world.placement_ok()
			print("T --test-build-area: Maus weit außerhalb %s → baubar=%s (Sollwert false) %s" % [
					weit2, world.placement_ok(), "OK" if h2 else "FEHLER"])
			if not h2:
				fehler += 1


			_on_right_click_map()
			await get_tree().process_frame
			await maus.call(zelle.call(gut))
			var h3: bool = world.placing_type < 0 and not _hover_ghost and build_bar.ready_building() == fertig
			print("T --test-build-area: Rechtsklick → Geist weg=%s, Gebäude weiter fertig=%s, bleibt weg=%s (Sollwert true/true/true) %s" % [
					world.placing_type < 0, build_bar.ready_building() == fertig, not _hover_ghost,
					"OK" if h3 else "FEHLER"])
			if not h3:
				fehler += 1

			_toggle_build_bar()
			_toggle_build_bar()
			await get_tree().process_frame
			await maus.call(zelle.call(gut))
			var h4: bool = _hover_ghost and world.placing_type == fertig and build_bar.visible
			print("T --test-build-area: nach dem Umschalten der Leiste → Schwebe-Geist=%s, Leiste offen=%s (Sollwert true/true) %s" % [
					_hover_ghost, build_bar.visible, "OK" if h4 else "FEHLER"])
			if not h4:
				fehler += 1

			await maus.call(build_toggle.get_global_rect().get_center())
			var h5: bool = not _hover_ghost and world.placing_type < 0
			print("T --test-build-area: Maus über dem Bauleisten-Knopf → Geist=%s (Sollwert false) %s" % [
					_hover_ghost, "OK" if h5 else "FEHLER"])
			if not h5:
				fehler += 1
		get_window().size = fenster6
		await get_tree().process_frame


	var pid3: int = world.type_ids.get("powr", -1)
	var stelle := _bau_free_ring("powr", fo, fw, fh, 2)
	if pid3 < 0 or stelle.x < 0:
		print("T --test-build-area: keine freie Stelle für die Einheitprobe — Schritt 7 übersprungen")
	else:
		var panzer: ProtoWorld.Unit = world.spawn_unit("2tnk", 0, stelle)
		var gegner: ProtoWorld.Unit = world.spawn_unit("2tnk", 1, stelle + Vector2i(0, 3))
		if panzer == null:
			print("T --test-build-area: kein Panzer setzbar — Schritt 7 übersprungen")
		else:
			for _t in 3:
				sim.step()
			var eigen_ok: bool = _bau_ok("powr", stelle)
			print("T --test-build-area: eigener Panzer auf %s → Platzierung erlaubt=%s (Sollwert true) %s" % [
					stelle, eigen_ok, "OK" if eigen_ok else "FEHLER"])
			if not eigen_ok:
				fehler += 1
			if gegner != null:
				var feind_ok: bool = _bau_ok("powr", stelle + Vector2i(0, 3))
				print("T --test-build-area: gegnerischer Panzer auf %s → Platzierung erlaubt=%s (Sollwert false) %s" % [
						stelle + Vector2i(0, 3), feind_ok, "OK" if not feind_ok else "FEHLER"])
				if feind_ok:
					fehler += 1

			if build_bar.ready_building() != pid3:
				world.queue_build(pid3)
				for _t in 3000:
					sim.step()
					if build_bar.ready_building() == pid3:
						break
			if build_bar.ready_building() != pid3:
				print("T --test-build-area: Kraftwerk wurde nicht fertig — Schritt 7 unvollständig")
			else:
				world.begin_placement(pid3)


				world.move_placement(world.placement_pos_for("powr", stelle))
				var gesetzt: bool = world.place_origin == stelle and world.confirm_placement()
				for _t in 3:
					sim.step()
				var vorgemerkt: PackedInt32Array = sim.pending_place(0, 0)
				print("T --test-build-area: Bestätigt=%s → vorgemerkt=%s" % [gesetzt, vorgemerkt])
				var ticks := -1
				for t in 400:
					sim.step()
					if sim.pending_place(0, 0).is_empty():
						ticks = t
						break

				await get_tree().process_frame
				await get_tree().process_frame
				var steht := false
				for u in world.units:
					if u.alive and u.player == 0 and u.type == "powr" and Vector2i(world.unit_rect(u).position / ProtoWorld.CELL) == stelle:
						steht = true
				print("T --test-build-area: Einheit ausgewichen → Kraftwerk nach %d Ticks auf %s gebaut=%s (Sollwert true) %s" % [
						ticks, stelle, steht, "OK" if steht else "FEHLER"])
				if not steht:
					fehler += 1
	print("T --test-build-area: fertig, %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


var _test_c4 := false
var _c4_tanya := -1
var _c4_tank := -1
var _c4_barr = null
var _c4_apc := -1
var _c4_shot_timer := false
var _c4_house = null
var _c4_pump = null
var _c4_bridge = null
var _c4_hidden := 0
var _c4_hidden_since := -1


func _run_test_c4() -> void:
	var sim = world.sim
	var tick: int = sim.tick()


	if _test_step >= 3 and _c4_tanya >= 0:
		var tw := world.unit_by_id(_c4_tanya)
		if tw != null and tw.alive and not tw.visible:
			if _c4_hidden_since < 0:
				_c4_hidden_since = tick
			_c4_hidden = maxi(_c4_hidden, tick - _c4_hidden_since + 1)
		else:
			_c4_hidden_since = -1
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		var origin := Vector2i(30, 30)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		var tanya := _spawn_force_test("e7", 0, Vector2i(0, 0))
		var tank := _spawn_force_test("3tnk", 1, Vector2i(4, 0))
		if tank == null:
			tank = _spawn_force_test("1tnk", 1, Vector2i(4, 0))
		var own := _spawn_force_test("2tnk", 0, Vector2i(0, 3))
		var apc := _spawn_force_test("apc", 0, Vector2i(-3, 0))
		_c4_barr = world.call("_add_building", "barr", 1, _test_origin + Vector2i(3, -5))
		if tanya == null or tank == null:
			print("T --test-c4: Tanya oder Panzer fehlt in rules.json — abgebrochen")
			get_tree().quit()
			return
		_c4_tanya = tanya.id
		_c4_tank = tank.id
		_c4_apc = -1 if apc == null else apc.id
		world.select_only(tanya)
		world.center_on((tanya.pos + tank.pos) / 2.0)

		var k_foe: int = world.enter_kind(tank)
		var k_own: int = 0 if own == null else world.enter_kind(own)
		var k_bld: int = 0 if _c4_barr == null else world.enter_kind(_c4_barr)
		print("T --test-c4: Gegnerpanzer enter_kind=%d (erwartet 3) %s" % [
				k_foe, "OK" if k_foe == ProtoWorld.ENTER_DEMOLISH else "FEHLER"])
		print("T --test-c4: eigener Panzer enter_kind=%d (erwartet 0 — nie einsteigen) %s" % [
				k_own, "OK" if k_own == ProtoWorld.ENTER_NONE else "FEHLER"])
		print("T --test-c4: Gegnergebäude enter_kind=%d (erwartet 3) %s" % [
				k_bld, "OK" if k_bld == ProtoWorld.ENTER_DEMOLISH else "FEHLER"])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 40:

		var marks: int = world.c4_marker_count()
		print("T --test-c4: Bombensymbole über Zielen=%d (erwartet 2: Panzer + Kaserne) %s"
				% [marks, "OK" if marks == 2 else "FEHLER"])
		_shot("ziele")
		var tank := world.unit_by_id(_c4_tank)
		_on_long_press(world.world_to_screen(tank.pos))
		var has_c4: bool = radial.visible and radial.ITEMS.has("c4")
		print("T --test-c4: Radialmenü offen=%s, Eintrag Sprengen(C4)=%s %s" % [
				radial.visible, has_c4, "OK" if has_c4 else "FEHLER"])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 4:
		_shot("radial")
		radial.cancel()
		_c4_target = null

		var tanya := world.unit_by_id(_c4_tanya)
		var tank := world.unit_by_id(_c4_tank)
		world.select_only(tanya)
		_on_tap(world.world_to_screen(tank.pos))
		print("T --test-c4: Tipp auf den Gegnerpanzer → Ziellinie goal_kind=%d (4 = Sprengen), Transporter=%d (erwartet -1)"
				% [tanya.goal_kind, sim.transport_of(tanya.id)])
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:
		var tank := world.unit_by_id(_c4_tank)
		if tank != null and tank.alive and tank.demolishing and not _c4_shot_timer:
			_c4_shot_timer = true
			world.center_on(tank.pos)
			print("T --test-c4: Ladung liegt (Tick %d), Zünder-Restzeit %d Ticks" % [tick, tank.demolish_left])
			_shot("timer")
		if tank == null or not tank.alive:
			print("T --test-c4: Gegnerpanzer gesprengt (Tick %d), Zünderbild gemacht=%s %s"
					% [tick, _c4_shot_timer, "OK" if _c4_shot_timer else "FEHLER"])
			_shot("explosion")
			_test_step = 4
			_test_tick = tick
		elif tick > _test_tick + 1200:
			print("T --test-c4: FEHLER — Panzer nach 1200 Ticks noch heil (hp %.0f %%), Ladung gelegt=%s"
					% [tank.hp * 100.0, _c4_shot_timer])
			_test_step = 4
			_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 20:
		var tanya := world.unit_by_id(_c4_tanya)
		var alive: bool = tanya != null and tanya.alive
		print("T --test-c4: Tanya überlebt=%s (EnterBehaviour Exit) %s" % [alive, "OK" if alive else "FEHLER"])

		if alive and _c4_barr != null and _c4_barr.alive:
			world.select_only(tanya)
			world.center_on(_c4_barr.pos)
			_on_long_press(world.world_to_screen(_c4_barr.pos))
			var has_c4b: bool = radial.visible and radial.ITEMS.has("c4")
			print("T --test-c4: Gebäude — Radialmenü offen=%s, Eintrag=%s %s"
					% [radial.visible, has_c4b, "OK" if has_c4b else "FEHLER"])
			radial.cancel()
			_on_radial("c4")
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5:
		var dead: bool = _c4_barr == null or not _c4_barr.alive
		if dead or tick > _test_tick + 1500:
			print("T --test-c4: Gebäude über das Radialmenü gesprengt=%s %s"
					% [dead, "OK" if dead else "FEHLER"])


			_c4_house = world.call("_add_building", "v01", ProtoWorld.PLAYER_NEUTRAL, _test_origin + Vector2i(-7, -5))
			_c4_pump = world.call("_add_building", "v19", ProtoWorld.PLAYER_NEUTRAL, _test_origin + Vector2i(-7, -1))
			_test_step = 50
			_test_tick = tick
	elif _test_step == 50 and tick >= _test_tick + 20:
		var tanya3 := world.unit_by_id(_c4_tanya)
		if _c4_house == null or _c4_pump == null or tanya3 == null or not tanya3.alive:
			print("T --test-c4: FEHLER — Zivilbauten oder Tanya fehlen, Zivilteil übersprungen")
			_test_step = 60
			_test_tick = tick
			return
		world.select_only(tanya3)
		world.center_on(_c4_house.pos)

		var pick_h: bool = world.pickable(_c4_house)
		var pick_p: bool = world.pickable(_c4_pump)
		var hit_h = world.pick_unit(world.unit_rect(_c4_house).get_center(), 0.0)
		var kind_h: int = world.enter_kind(_c4_house)
		print("T --test-c4: Zivilhaus V01 pickable=%s, Tipp trifft=%s, enter_kind=%d (erwartet 3) %s" % [
				pick_h, ("nichts" if hit_h == null else hit_h.type), kind_h,
				"OK" if pick_h and hit_h != null and hit_h.type == "v01" and kind_h == ProtoWorld.ENTER_DEMOLISH else "FEHLER"])
		print("T --test-c4: Ölpumpe V19 pickable=%s, enter_kind=%d (erwartet 3) %s" % [
				pick_p, world.enter_kind(_c4_pump),
				"OK" if pick_p and world.enter_kind(_c4_pump) == ProtoWorld.ENTER_DEMOLISH else "FEHLER"])
		_on_tap(world.world_to_screen(_c4_house.pos))
		_test_step = 51
		_test_tick = tick
	elif _test_step == 51:
		if _c4_house.alive and tick < _test_tick + 1500:
			return
		print("T --test-c4: Zivilhaus gesprengt=%s nach %d Ticks %s" % [
				not _c4_house.alive, tick - _test_tick, "OK" if not _c4_house.alive else "FEHLER"])
		var tanya4 := world.unit_by_id(_c4_tanya)
		if tanya4 != null and tanya4.alive:
			world.select_only(tanya4)
			world.center_on(_c4_pump.pos)
			_on_tap(world.world_to_screen(_c4_pump.pos))
		_test_step = 52
		_test_tick = tick
	elif _test_step == 52:
		if _c4_pump.alive and tick < _test_tick + 1500:
			return
		print("T --test-c4: Ölpumpe gesprengt=%s nach %d Ticks %s" % [
				not _c4_pump.alive, tick - _test_tick, "OK" if not _c4_pump.alive else "FEHLER"])
		_c4_bridge = _find_bridge()
		if _c4_bridge == null:
			print("T --test-c4: keine Brücke auf dieser Karte — Brückenteil übersprungen (--map a-path-beyond)")
			_test_step = 60
			_test_tick = tick
			return
		var bc: Vector2 = _c4_bridge.pos
		var tanya5 := world.unit_by_id(_c4_tanya)
		world.select_only(tanya5)
		world.center_on(bc)


		var tap_hit = world.pick_unit(bc, 0.0)
		var long_hit = world.pick_bridge(bc, false)
		print("T --test-c4: Brücke %s — Tipp trifft=%s (erwartet nichts), Langdruck trifft=%s, enter_kind=%d (erwartet 3) %s" % [
				_c4_bridge.type, ("nichts" if tap_hit == null else tap_hit.type),
				("nichts" if long_hit == null else long_hit.type), world.enter_kind(_c4_bridge),
				"OK" if tap_hit == null and long_hit == _c4_bridge and world.enter_kind(_c4_bridge) == ProtoWorld.ENTER_DEMOLISH else "FEHLER"])

		sim.teleport(tanya5.id, int(bc.x / ProtoWorld.CELL) - 3, int(bc.y / ProtoWorld.CELL))
		_test_step = 53
		_test_tick = tick
	elif _test_step == 53 and tick >= _test_tick + 20:
		var tanya6 := world.unit_by_id(_c4_tanya)
		world.select_only(tanya6)
		_on_long_press(world.world_to_screen(_c4_bridge.pos))
		var has_c4c: bool = radial.visible and radial.ITEMS.has("c4")
		print("T --test-c4: Brücke — Radialmenü offen=%s, Eintrag Sprengen(C4)=%s %s" % [
				radial.visible, has_c4c, "OK" if has_c4c else "FEHLER"])
		radial.cancel()
		_on_radial("c4")
		_test_step = 54
		_test_tick = tick
	elif _test_step == 54:
		if _c4_bridge.alive and tick < _test_tick + 2000:
			return
		var bcell := Vector2i(_c4_bridge.pos / ProtoWorld.CELL)
		var ter: int = sim.cell_terrain(bcell.x, bcell.y)

		var walkable: bool = ter != ProtoWorld.TER_WATER and ter != ProtoWorld.TER_ROCK
		print("T --test-c4: Brücke zerstört=%s nach %d Ticks; Fahrbahn (%d,%d) Terrain=%s begehbar=%s %s" % [
				not _c4_bridge.alive, tick - _test_tick, bcell.x, bcell.y,
				(ProtoWorld.TERRAIN_ORDER[ter] if ter >= 0 and ter < ProtoWorld.TERRAIN_ORDER.size() else str(ter)),
				walkable, "OK" if not _c4_bridge.alive and not walkable else "FEHLER"])
		_test_step = 60
		_test_tick = tick
	elif _test_step == 60 and tick >= _test_tick + 20:


		print("T --test-c4: Tanya am Stück unsichtbar höchstens %d Ticks (erwartet ≤ 12) %s" % [
				_c4_hidden, "OK" if _c4_hidden <= 12 else "FEHLER"])

		var tanya2 := world.unit_by_id(_c4_tanya)
		var apc := world.unit_by_id(_c4_apc)
		if tanya2 != null and tanya2.alive and apc != null and apc.alive:
			world.select_only(tanya2)
			sim.teleport(tanya2.id, int(apc.pos.x / ProtoWorld.CELL) + 2, int(apc.pos.y / ProtoWorld.CELL))
			_on_tap(world.world_to_screen(apc.pos))
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 600:
		var aboard: bool = _c4_apc >= 0 and sim.transport_of(_c4_tanya) == _c4_apc
		print("T --test-c4: Tipp auf das eigene MTW → eingestiegen=%s %s" % [
				aboard, "OK" if aboard else "FEHLER"])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _spawn_force_test(type_name: String, player: int, offset: Vector2i) -> ProtoWorld.Unit:
	if not world.type_ids.has(type_name):
		return null
	return world.spawn_unit(type_name, player, _test_origin + offset)


var _force_shooter := -1
var _force_victim := -1
var _force_hp0 := 1.0


var _test_crate := false
var _test_cratedrop := false


var _cd_wait := 0
var _crate_hp_before: Dictionary = {}
var _crate_names: Dictionary = {}
var _crate_collector: ProtoWorld.Unit = null


func _crate_note(u: ProtoWorld.Unit, role: String) -> void:
	if u == null:
		print("T --test-crate: %s konnte nicht gesetzt werden" % role)
		return
	_crate_hp_before[u.id] = u.hp
	_crate_names[u.id] = role


func _run_test_cratedrop() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		if not world.type_ids.has("crate") or not world.type_ids.has("badr"):
			print("T --test-cratedrop: crate/badr fehlt in rules.json — übersprungen")
			get_tree().quit()
			return

		var cs: Dictionary = RulesDb.data().get("world", {}).get("crate_spawner", {})
		var ground := 0
		for tn in cs.get("valid_ground", []):
			var ti: int = ProtoWorld.TERRAIN_ORDER.find(str(tn))
			if ti >= 0:
				ground |= 1 << ti
		sim.set_crate_spawner({
			"enabled": true, "crate_type": world.type_ids["crate"],
			"minimum": 1, "maximum": 1, "spawn_interval": 100000, "initial_delay": 1,
			"valid_ground": ground, "delivery_type": world.type_ids["badr"],
			"quantized_facings": int(cs.get("quantized_facings", 16)),
			"cordon": int(cs.get("cordon", 5120)),
		})
		print("T --test-cratedrop: Spawner scharf (Lieferflugzeug badr=%d)" % world.type_ids["badr"])
		_test_step = 1
	elif _test_step == 1:
		var plane := _cratedrop_plane()
		if plane == null:
			if tick > 400:
				var on_map0 := 0
				for u in world.units:
					if u.alive and u.type == "crate":
						on_map0 += 1
				print("T --test-cratedrop: kein Badger erschienen FEHLER (Kisten gesamt %d, davon auf der Karte %d, Actors %d)" % [
						sim.crate_count(), on_map0, world.units.size()])
				get_tree().quit()
			return


		var on_map := 0
		var aboard := 0
		for u in world.units:
			if u.alive and u.type == "crate":
				if u.visible:
					on_map += 1
				else:
					aboard += 1
		world.center_on(plane.pos)
		print("T%d --test-cratedrop: Badger bei %s, Kiste an Bord=%d (Sollwert 1), auf der Karte=%d %s" % [
				tick, plane.pos / ProtoWorld.CELL, aboard, on_map, "OK" if aboard == 1 else "FEHLER"])
		_test_step = 11
		_cd_wait = 3
	elif _test_step == 11:
		if _cd_wait > 0:
			_cd_wait -= 1
			var pl := _cratedrop_plane()
			if pl != null:
				world.center_on(pl.pos)
			return
		_shot("anflug")
		_test_step = 2
	elif _test_step == 2:


		for u in world.units:
			if u.alive and u.type == "crate" and u.altitude > 0.0:
				world.center_on(u.pos)
				print("T%d --test-cratedrop: Kiste abgeworfen bei %s, Höhe %d px (Fallschirm)" % [
						tick, u.pos / ProtoWorld.CELL, u.altitude])
				_test_step = 21
				_cd_wait = 3
				_test_tick = tick
				return
		if tick > 3000:
			print("T --test-cratedrop: kein Abwurf FEHLER")
			get_tree().quit()
	elif _test_step == 21:

		for u in world.units:
			if u.alive and u.type == "crate" and u.altitude > 0.0:
				world.center_on(u.pos)
		if _cd_wait > 0:
			_cd_wait -= 1
			return
		_shot("fallschirm")
		_test_step = 3
	elif _test_step == 3:
		for u in world.units:
			if u.alive and u.type == "crate" and u.visible and u.altitude <= 0.0:
				print("T%d --test-cratedrop: Kiste gelandet bei %s (Fallzeit %d Ticks) OK" % [
						tick, u.pos / ProtoWorld.CELL, tick - _test_tick])
				world.center_on(u.pos)
				_test_step = 31
				_cd_wait = 3
				_test_tick = tick
				return
		if tick > _test_tick + 600:
			print("T --test-cratedrop: Kiste kam nicht am Boden an FEHLER")
			get_tree().quit()
	elif _test_step == 31:
		if _cd_wait > 0:
			_cd_wait -= 1
			return
		_shot("gelandet")
		_test_step = 4
	elif _test_step == 4:

		if _cratedrop_plane() == null:
			print("T%d --test-cratedrop: Badger verschwunden, Kisten auf der Karte=%d — fertig" % [
					tick, sim.crate_count()])
			get_tree().quit()
		elif tick > _test_tick + 3000:
			print("T --test-cratedrop: Badger blieb auf der Karte FEHLER")
			get_tree().quit()


func _cratedrop_plane() -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and u.type == "badr":
			return u
	return null


func _run_test_crate() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		var origin := Vector2i(30, 30)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		if not world.type_ids.has("crate"):
			print("T --test-crate: Kistentyp fehlt in rules.json — übersprungen")
			get_tree().quit()
			return


		_crate_collector = _spawn_deploy_test("3tnk", 0, Vector2i(2, 0))
		var crate := world.spawn_unit("crate", ProtoWorld.PLAYER_NEUTRAL, _test_origin + Vector2i(6, 0))
		var mate := _spawn_deploy_test("3tnk", 0, Vector2i(6, 1))
		var mate2 := _spawn_deploy_test("3tnk", 0, Vector2i(6, 2))
		var away := _spawn_deploy_test("3tnk", 0, Vector2i(6, 6))
		_crate_note(_crate_collector, "Sammler")
		_crate_note(mate, "eigen, eine Zelle")
		_crate_note(mate2, "eigen, zwei Zellen")
		_crate_note(away, "eigen, sechs Zellen")
		print("T --test-crate: Kistenart=%s Kiste gesetzt=%s Kisten in der Welt=%d" % [
				_crate_type_label(), crate != null, sim.crate_count()])
		if _crate_collector != null:
			world.center_on(_crate_collector.pos)
			world.select_only(_crate_collector)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 8:
		_shot("kiste-vorher")
		if _crate_collector != null:
			world.order_move(_crate_collector.pos + Vector2(6 * ProtoWorld.CELL, 0))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 200:
		var hurt := 0
		for u in world.units:
			if not _crate_hp_before.has(u.id):
				continue
			var now: float = u.hp if u.alive else 0.0
			var before: float = float(_crate_hp_before[u.id])
			if now < before - 0.001:
				hurt += 1
			print("T --test-crate: %s (%s) %.1f %% → %.1f %%%s" % [
					_crate_names[u.id], u.type, before * 100.0, now * 100.0,
					"" if u.alive else " — zerstört"])
		var explode: bool = ProtoWorld.next_crate_action == 2
		var ok: bool = sim.crate_count() == 0 and (not explode or hurt >= 2)
		print("T --test-crate: Kisten übrig=%d, beschädigt=%d %s" % [
				sim.crate_count(), hurt, "OK" if ok else "FEHLER"])
		_shot("kiste-nachher")
		_test_step = 3
		get_tree().quit()


func _crate_type_label() -> String:
	for k in ProtoWorld.CRATE_ACTION_ALIASES:
		if int(ProtoWorld.CRATE_ACTION_ALIASES[k]) == ProtoWorld.next_crate_action:
			return String(k)
	return "alle"


func _run_test_deploy() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		var origin := Vector2i(30, 30)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		var ml := _spawn_deploy_test("mnly", 0, Vector2i(2, 0))
		if ml != null:
			world.select_only(ml)
			world.center_on(ml.pos)
			print("T --test-deploy: Minenleger Aktion=%s bereit=%s" % [
					world.deploy_action("mnly"), world.deploy_ready(ml, "mine")])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 6:
		_shot("zeichen")
		_deploy_mines_before = _count_type("minv")
		_do_deploy_action("mine")
		var ml2 := _find_own("mnly")
		if ml2 != null:
			world.order_move(ml2.pos + Vector2(4 * ProtoWorld.CELL, 0))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 90:
		var mines := _count_type("minv")
		print("T --test-deploy: Minen vorher %d, jetzt %d, Vorrat %d %s" % [
				_deploy_mines_before, mines, _find_own("mnly").ammo if _find_own("mnly") != null else -1,
				"OK" if mines > _deploy_mines_before else "FEHLER"])
		_shot("mine")

		var mad := _spawn_deploy_test("qtnk", 0, Vector2i(0, 8))
		_spawn_deploy_test("3tnk", 1, Vector2i(3, 8))
		if world.type_ids.has("powr"):
			world.call("_add_building", "powr", 1, _test_origin + Vector2i(-3, 8))
		if mad == null:
			print("T --test-deploy: qtnk fehlt — MAD-Teil übersprungen")
			_test_step = 5
			_test_tick = tick
			return
		world.select_only(mad)
		world.center_on(mad.pos)
		_deploy_mad_pos = mad.pos
		_deploy_hp_before = _foe_hp()
		_do_deploy_action("detonate")
		print("T --test-deploy: MAD entfaltet=%s" % sim.detonating(mad.id))
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 60:
		var mad2 := _find_own("qtnk")
		if mad2 != null:
			world.order_move(mad2.pos + Vector2(6 * ProtoWorld.CELL, 0))
			print("T --test-deploy: MAD steht still=%s (Bewegungsbefehl wirkungslos)" % (mad2.pos == _deploy_mad_pos))

		print("T --test-deploy: Fahrer ausgeworfen=%s (e1 auf der Karte: %d)" % [
				_count_type("e1") > 0, _count_type("e1")])
		_shot("laden")
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 120:
		var hurt := _report_damage("MAD")
		print("T --test-deploy: MAD zerstört=%s, beschädigte Gegner %d %s" % [
				_find_own("qtnk") == null, hurt, "OK" if _find_own("qtnk") == null and hurt >= 2 else "FEHLER"])
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5 and tick >= _test_tick + 10:

		var truck := _spawn_deploy_test("dtrk", 0, Vector2i(0, -8))
		_spawn_deploy_test("3tnk", 1, Vector2i(1, -8))
		if truck == null:
			print("T --test-deploy: dtrk fehlt — übersprungen")
			_test_step = 7
			_test_tick = tick
			return
		world.select_only(truck)
		world.center_on(truck.pos)
		_deploy_hp_before = _foe_hp()
		_do_deploy_action("demolish")
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 40:
		var hurt2 := _report_damage("LKW")
		print("T --test-deploy: LKW zerstört=%s, beschädigte Gegner %d %s" % [
				_find_own("dtrk") == null, hurt2, "OK" if _find_own("dtrk") == null and hurt2 >= 1 else "FEHLER"])
		_test_step = 7
		_test_tick = tick
	elif _test_step == 7 and tick >= _test_tick + 10:

		var ct := _spawn_deploy_test("ctnk", 0, Vector2i(6, 0))
		if ct == null:
			print("T --test-deploy: ctnk fehlt — übersprungen")
			get_tree().quit()
			return
		world.select_only(ct)
		world.center_on(ct.pos)
		_deploy_mad_pos = ct.pos
		_do_deploy_action("chrono")
		var reach: int = world.chrono_range_cells()
		print("T --test-deploy: Chrono Zielwahl aktiv=%s Reichweite=%s" % [
				_order_mode == "chrono", "unbegrenzt" if reach <= 0 else "%d Zellen" % reach])
		_on_tap(world.world_to_screen(ct.pos + Vector2(0, -6 * ProtoWorld.CELL)))
		_test_step = 8
		_test_tick = tick
	elif _test_step == 8 and tick >= _test_tick + 3:
		var ct2 := _find_own("ctnk")
		var jumped: bool = ct2 != null and ct2.pos.distance_to(_deploy_mad_pos) > ProtoWorld.CELL
		print("T --test-deploy: Chrono gesprungen=%s (%s → %s), Abklingzeit %d Ticks %s" % [
				jumped, _deploy_mad_pos, ct2.pos if ct2 != null else Vector2.ZERO,
				sim.chrono_charge_left(ct2.id) if ct2 != null else -1, "OK" if jumped else "FEHLER"])
		_deploy_mad_pos = ct2.pos if ct2 != null else Vector2.ZERO
		_do_deploy_action("chrono")
		if _order_mode == "chrono":
			_on_tap(world.world_to_screen(_deploy_mad_pos + Vector2(0, -4 * ProtoWorld.CELL)))
		_test_step = 9
		_test_tick = tick
	elif _test_step == 9 and tick >= _test_tick + 3:
		var ct3 := _find_own("ctnk")
		var stayed: bool = ct3 != null and ct3.pos.distance_to(_deploy_mad_pos) < ProtoWorld.CELL
		print("T --test-deploy: zweiter Sprung abgewiesen=%s %s" % [stayed, "OK" if stayed else "FEHLER"])
		_shot("chrono")
		_test_step = 10
		_test_tick = tick
	elif _test_step == 10 and tick >= _test_tick + 260:


		var ct4 := _find_own("ctnk")
		if ct4 == null:
			print("T --test-deploy: Chrono-Panzer verschwunden — Weitsprung übersprungen")
			get_tree().quit()
			return
		world.zoom_at(ProtoWorld.MIN_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.select_only(ct4)
		world.center_on(ct4.pos)
		_deploy_mad_pos = ct4.pos

		var b: Rect2i = world.bounds
		var here := Vector2i(ct4.pos / ProtoWorld.CELL)
		var far := Vector2i(
				(b.position.x + 3) if here.x > (b.position.x + b.size.x / 2) else (b.end.x - 4),
				(b.position.y + 3) if here.y > (b.position.y + b.size.y / 2) else (b.end.y - 4))
		_deploy_chrono_target = (Vector2(far) + Vector2(0.5, 0.5)) * ProtoWorld.CELL
		_deploy_chrono_from = Vector2i(here)
		_deploy_chrono_to = far
		_test_step = 11
		_test_tick = tick
	elif _test_step == 11 and tick >= _test_tick + 6:

		var ctj := _find_own("ctnk")
		_shot("chrono-fern-vorher")
		var jumped_far: bool = ctj != null and world.chrono_selected(_deploy_chrono_target)
		print("T --test-deploy: Weitsprung %s → %s (%.1f Zellen) angenommen=%s Ladung=%d" % [
				_deploy_chrono_from, _deploy_chrono_to,
				_deploy_mad_pos.distance_to(_deploy_chrono_target) / ProtoWorld.CELL, jumped_far,
				world.sim.chrono_charge_left(ctj.id) if ctj != null else -1])
		_test_step = 12
		_test_tick = tick
	elif _test_step == 12 and tick >= _test_tick + 20:
		var ct5 := _find_own("ctnk")
		var moved: float = (ct5.pos.distance_to(_deploy_mad_pos) / ProtoWorld.CELL) if ct5 != null else 0.0
		var near_goal: float = (ct5.pos.distance_to(_deploy_chrono_target) / ProtoWorld.CELL) if ct5 != null else 999.0

		var ok: bool = moved > 12.0 and near_goal < 4.0
		print("T --test-deploy: Weitsprung zurückgelegt=%.1f Zellen, Abstand zum Ziel=%.1f %s" % [
				moved, near_goal, "OK" if ok else "FEHLER"])
		if ct5 != null:
			world.center_on(ct5.pos)
		_test_step = 13
		_test_tick = tick
	elif _test_step == 13 and tick >= _test_tick + 4:
		_shot("chrono-fern-nachher")
		_test_step = 14
		get_tree().quit()


func _spawn_deploy_test(type_name: String, player: int, offset: Vector2i) -> ProtoWorld.Unit:
	if not world.type_ids.has(type_name):
		print("T --test-deploy: %s fehlt in rules.json" % type_name)
		return null
	var u: ProtoWorld.Unit = world.spawn_unit(type_name, player, _test_origin + offset)
	if u == null:
		print("T --test-deploy: %s konnte bei %s nicht gesetzt werden" % [type_name, _test_origin + offset])
	return u


func _foe_hp() -> Dictionary:
	var out := {}
	for u in world.units:
		if u.alive and u.player == 1:
			out[u.id] = u.hp
	return out


func _report_damage(label: String) -> int:
	var hurt := 0
	for u in world.units:
		if not _deploy_hp_before.has(u.id):
			continue
		var now: float = u.hp if u.alive else 0.0
		var before: float = float(_deploy_hp_before[u.id])
		if now < before - 0.001:
			hurt += 1
		print("T --test-deploy: %s → %s bei %.0f %% (vorher %.0f %%)%s" % [
				label, u.type, now * 100.0, before * 100.0, "" if u.alive else " — zerstört"])
	return hurt


func _shot(name: String) -> void:
	if _screenshot_path == "":
		return
	get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_" + name + ".png")
	print("T: Screenshot %s" % name)


var _deploy_mines_before := 0
var _deploy_moved := 0
var _deploy_mad_pos := Vector2.ZERO
var _deploy_chrono_target := Vector2.ZERO
var _deploy_chrono_from := Vector2i.ZERO
var _deploy_chrono_to := Vector2i.ZERO
var _deploy_hp_before: Dictionary = {}


func _run_test_placement_cancel() -> void:
	var sim = world.sim


	_screenshot_tick = 1 << 30
	sim.give_credits(0, 50000)

	var base := Vector2i(10, 10)
	for u in world.units:
		if u.alive and u.player == 0:
			base = Vector2i(u.pos / ProtoWorld.CELL)
			break
	var n := 0
	for t in ["fact", "powr"]:
		if world.type_ids.has(t):
			world.call("_add_building", t, 0, base + Vector2i(-6 + n * 4, 4))
			n += 1
	for _t in 30:
		sim.step()


	var bname := ""
	for cand in ["spen", "syrd", "powr"]:
		if world.type_ids.has(cand) and sim.queue_build(0, world.type_ids[cand]):
			bname = cand
			break
	if bname == "":
		print("T --test-placement-cancel: kein Gebäude baubar — Haken übersprungen")
		get_tree().quit()
		return
	var pid: int = world.type_ids[bname]

	var ready := false
	for _i in 20000:
		sim.step()
		var q: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
		if q.size() >= 3 and q[0] == pid and q[2] == 1:
			ready = true
			break
	if not ready:
		print("T --test-placement-cancel: %s nicht rechtzeitig fertig" % bname)
		get_tree().quit()
		return

	var origin := Vector2i(10, 10)
	for u in world.units:
		if u.alive and u.player == 0 and u.type == "fact":
			origin = Vector2i(u.pos / ProtoWorld.CELL)
			break
	var placeable := false
	for dy in range(-20, 21):
		for dx in range(-20, 21):
			var res: PackedByteArray = sim.can_place(0, pid, origin.x + dx, origin.y + dy)
			if res.size() > 0 and res[0] == 1:
				placeable = true
				break
		if placeable:
			break
	print("T --test-placement-cancel: %s fertig, platzierbar in Reichweite=%s" % [bname, placeable])


	build_bar.visible = true
	build_bar.select_queue(ProtoWorld.Queue.BUILDING)
	build_bar.call("_rebuild")
	for _f in 120:
		await get_tree().process_frame
		if world.placing_type >= 0:
			break
	var was_placing: bool = world.placing_type == pid
	world.center_on(Vector2(origin) * ProtoWorld.CELL)
	await get_tree().process_frame
	if _screenshot_path != "":
		get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_geistbild.png")


	var pos := place_cancel.global_position + place_cancel.size / 2.0
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame

	for _f in 70:
		await get_tree().process_frame
	var after_cancel: int = world.placing_type
	var queue_after: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
	var still_ready: bool = queue_after.size() >= 3 and queue_after[0] == pid and queue_after[2] == 1
	print("T --test-placement-cancel: nach Abbrechen placing_type=%d (erwartet -1), Warteschlange=%s fertig=%s %s" % [
		after_cancel, queue_after.slice(0, 3), still_ready,
		"OK" if (was_placing and after_cancel < 0 and still_ready) else "FEHLER"])
	if _screenshot_path != "":
		get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_abgebrochen.png")


	var powr_id: int = world.type_ids.get("powr", -1)
	if powr_id >= 0 and powr_id != pid:
		world.queue_build(powr_id)
	for _f in 90:
		await get_tree().process_frame
		build_bar.call("_rebuild")
	var after_build: int = world.placing_type
	print("T --test-placement-cancel: nach Kraftwerk-Auftrag placing_type=%d (erwartet -1) %s" % [
		after_build, "OK" if after_build < 0 else "FEHLER"])


	var picked := -1
	for slot in build_bar.get("_slots"):
		if slot.type_id == pid and slot.visible:
			build_bar.call("_on_tap", slot)
			break
	for _f in 20:
		await get_tree().process_frame
		if world.placing_type >= 0:
			break
	picked = world.placing_type
	print("T --test-placement-cancel: Tipp aufs Cameo placing_type=%d (erwartet %d) %s" % [
		picked, pid, "OK" if picked == pid else "FEHLER"])
	world.cancel_placement()
	get_tree().quit()


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
	var bar_open := _test_ready != "zu" and _test_ready != "kette"
	build_bar.visible = bar_open
	build_bar.select_queue(ProtoWorld.Queue.DEFENSE if bar_open else ProtoWorld.Queue.BUILDING)
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
	print("T --test-ready %s: Warteschlange=%s Leiste offen=%s Reiter=%d Leuchten gesamt=%s Platzierung=%d" % [
		_test_ready, sim.queue_state(0, ProtoWorld.Queue.BUILDING).slice(0, 3), build_bar.visible,
		build_bar.kind, build_bar.call("any_ready"), world.placing_type])
	if _test_ready == "kette":
		_run_ready_chain(pid)
		return
	_test_frame_extra = 30


func _run_ready_chain(pid: int) -> void:
	var ok := true
	build_bar.visible = false
	build_bar.select_queue(ProtoWorld.Queue.BUILDING)
	for _f in 90:
		await get_tree().process_frame
	var step1: bool = world.placing_type < 0 and bool(build_bar.call("any_ready"))
	ok = ok and step1
	print("T --test-ready kette 1: Leiste zu → Platzierung=%d Leuchten=%s %s" % [
		world.placing_type, build_bar.call("any_ready"), "OK" if step1 else "FEHLER"])
	await _tap_control(build_toggle)
	for _f in 90:
		await get_tree().process_frame
		if world.placing_type >= 0:
			break
	var step2 := world.placing_type == pid
	ok = ok and step2
	print("T --test-ready kette 2: Tipp auf den Bau-Knopf → Leiste offen=%s Platzierung=%d %s" % [
		build_bar.visible, world.placing_type, "OK" if step2 else "FEHLER"])
	await _tap_control(place_cancel)
	for _f in 90:
		await get_tree().process_frame
	var step3: bool = world.placing_type < 0 and bool(build_bar.call("any_ready"))
	ok = ok and step3
	print("T --test-ready kette 3: Abbrechen → Platzierung=%d Leuchten=%s %s" % [
		world.placing_type, build_bar.call("any_ready"), "OK" if step3 else "FEHLER"])
	await _tap_control(build_toggle)
	for _f in 90:
		await get_tree().process_frame
	var step4 := not build_bar.visible and world.placing_type < 0
	ok = ok and step4
	print("T --test-ready kette 4: Bau-Knopf erneut → Leiste offen=%s Platzierung=%d %s" % [
		build_bar.visible, world.placing_type, "OK" if step4 else "FEHLER"])


	var sim = world.sim
	sim.give_credits(0, 50000)


	var origin := Vector2i(10, 10)
	for u in world.units:
		if u.alive and u.player == 0 and u.type == "fact":
			origin = Vector2i(u.pos / ProtoWorld.CELL)
			break
	for dy in range(-6, 14):
		for dx in range(-10, 14):
			var cand := origin + Vector2i(dx, dy)
			var res: PackedByteArray = sim.can_place(0, pid, cand.x, cand.y)
			if res.size() > 0 and res[0] == 1 and sim.place_building(0, pid, cand.x, cand.y):
				dy = 99
				break
	for _t in 30:
		sim.step()
	var second := -1
	var powr_id: int = world.type_ids.get("powr", -1)
	for t in sim.buildable(0, ProtoWorld.Queue.BUILDING):
		if t != powr_id and sim.queue_build(0, t):
			second = t
			break
	if second < 0:
		print("T --test-ready kette: kein zweites Gebäude baubar — Schritte 5-7 übersprungen")
	if second >= 0:
		for _i in 20000:
			sim.step()
			var q: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
			if q.size() >= 3 and q[0] == second and q[2] == 1:
				break
		for _f in 60:
			await get_tree().process_frame
		var step5: bool = not build_bar.visible and world.placing_type < 0 and bool(build_bar.call("any_ready"))
		ok = ok and step5
		print("T --test-ready kette 5: zweites Gebäude fertig, Leiste zu → Platzierung=%d Leuchten=%s %s" % [
			world.placing_type, build_bar.call("any_ready"), "OK" if step5 else "FEHLER"])


		var producer: ProtoWorld.Unit = null
		for u in world.units:
			if u.alive and u.player == 0 and world.producer_kind(u) >= 0:
				producer = u
				break
		if producer != null:
			world.center_on(producer.pos)
			await get_tree().process_frame
			_on_tap(world.world_to_screen(producer.pos))
			for _f in 60:
				await get_tree().process_frame
			var step6 := build_bar.visible and world.placing_type < 0
			ok = ok and step6
			print("T --test-ready kette 6: Tipp auf %s → Leiste offen=%s Platzierung=%d %s" % [
				producer.type, build_bar.visible, world.placing_type, "OK" if step6 else "FEHLER"])

		await _tap_control(build_toggle)
		for _f in 30:
			await get_tree().process_frame
		await _tap_control(build_toggle)
		for _f in 90:
			await get_tree().process_frame
			if world.placing_type >= 0:
				break
		var step7 := world.placing_type == second
		ok = ok and step7
		print("T --test-ready kette 7: Leiste zu/auf über den Bau-Knopf → Platzierung=%d (erwartet %d) %s" % [
			world.placing_type, second, "OK" if step7 else "FEHLER"])
	print("T --test-ready kette: %s" % ("OK" if ok else "FEHLER"))
	get_tree().quit()


func _tap_control(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame


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


	var free_pos: Vector2 = world.placement_pos_for("weap", free_cell)


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
		world.move_placement(world.placement_pos_for(t, origin + Vector2i(w + 2, 0)))
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


		if u.player == world.local_player and not world.types[u.type].get("building", false) \
				and (own == null or (str(world.types[own.type].get("weapon", "")) == ""
					and str(world.types[u.type].get("weapon", "")) != "")):
			own = u


		elif u.player != world.local_player and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS \
				and not world.hostile(world.local_player, u.player) and ally == null:
			ally = u
		if own != null and ally != null and str(world.types[own.type].get("weapon", "")) != "":
			break
	if own == null or ally == null:
		var by_player := {}
		for u in world.units:
			if u.alive:
				var key := "%d/%s/bld=%s/hostile0=%s" % [u.player, u.type, world.types[u.type].get("building", false), world.hostile(world.local_player, u.player)]
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


var _test_tap_orders := false
var _tap_o := {}


func _tap_o_name(u) -> String:
	return "—" if u == null else str(u.type)


func _tap_o_map(p: Vector2) -> void:
	_on_tap(p)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap_o_bar(action: String) -> bool:
	var b: Button = action_bar.button_for(action)
	if b == null:
		return false
	b.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	return true


func _tap_o_beside(p: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = p
	ev.pressed = true
	action_bar._gui_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _tap_o_aim(wp: Vector2) -> Vector2:
	world.center_on(wp)
	await get_tree().process_frame
	await get_tree().process_frame
	return world.world_to_screen(wp)


func _tap_o_wait(cond: Callable, ticks: int) -> bool:
	var until: int = world.sim.tick() + ticks
	while world.sim.tick() < until:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _tap_o_free_spot(origin: Vector2i) -> Vector2:
	var offsets: Array[Vector2i] = [Vector2i(11, 9), Vector2i(12, 11), Vector2i(9, 12),
			Vector2i(13, 8), Vector2i(8, 13)]
	for d in offsets:
		var wp := (Vector2(origin + d) + Vector2(0.5, 0.5)) * ProtoWorld.CELL
		if world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom) == null:
			return wp
	return (Vector2(origin + Vector2i(11, 9)) + Vector2(0.5, 0.5)) * ProtoWorld.CELL


func _run_test_tap_orders() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 20000)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		_tap_o["cmd"] = world.spawn_unit("2tnk", 0, origin + Vector2i(6, 2))
		_tap_o["mate"] = world.spawn_unit("e1", 0, origin + Vector2i(9, 2))
		_tap_o["bld"] = world.call("_add_building", "powr", 0, origin + Vector2i(6, 6))

		_tap_o["apc"] = world.spawn_unit("apc", 0, origin + Vector2i(3, 1))
		_tap_o["pax"] = world.spawn_unit("e1", 0, origin + Vector2i(4, 1))

		var foe_cell := origin + Vector2i(0, -9)
		_tap_o["foe"] = world.call("_add_building", "barr", 1, foe_cell)
		if _tap_o["foe"] == null:
			_tap_o["foe"] = world.spawn_unit("e1", 1, foe_cell)
		sim.reveal(0, foe_cell.x, foe_cell.y, 8)
		_test_step = 1
		_test_tick = tick
		return
	if _test_step == 1 and tick >= _test_tick + 20:
		_test_step = 9
		_tap_orders_cases()


func _tap_orders_cases() -> void:
	var cmd = _tap_o.get("cmd")
	var mate = _tap_o.get("mate")
	var bld = _tap_o.get("bld")
	var foe = _tap_o.get("foe")
	var apc = _tap_o.get("apc")
	var pax = _tap_o.get("pax")
	if cmd == null or mate == null or bld == null or foe == null:
		print("T --test-tap-orders: Aufbau unvollständig (Panzer=%s Kamerad=%s Gebäude=%s Gegner=%s) FEHLER" % [
				_tap_o_name(cmd), _tap_o_name(mate), _tap_o_name(bld), _tap_o_name(foe)])
		get_tree().quit()
		return
	var fails := 0


	world.clear_selection()
	await _tap_o_map(await _tap_o_aim(cmd.pos))
	var ok1: bool = world.selection.size() == 1 and world.selection[0].id == cmd.id
	fails += 0 if ok1 else 1
	print("T --test-tap-orders: 1 Tipp ohne Auswahl auf %s → gewählt=%s (%s) %s" % [
			cmd.type, ok1, _last_gesture, "OK" if ok1 else "FEHLER: keine Auswahl"])


	world.select_only(cmd)
	cmd.goal_kind = -1
	await _tap_o_map(await _tap_o_aim(mate.pos))
	var open2: bool = action_bar.visible
	var miss2: Array = []
	for a in ["guard", "force_attack", "move", "info", "cancel"]:
		if not action_bar.ITEMS.has(a):
			miss2.append(a)
	var quiet2: bool = cmd.goal_kind == -1
	var keeps2: bool = world.selection.size() == 1 and world.selection[0].id == cmd.id
	var ok2: bool = open2 and miss2.is_empty() and quiet2 and keeps2
	fails += 0 if ok2 else 1
	print("T --test-tap-orders: 2 Tipp mit Auswahl auf eigene %s → Leiste=%s %s, fehlend %s, Sofortbefehl=%d (−1 = keiner), Auswahl bleibt=%s %s" % [
			mate.type, open2, str(action_bar.ITEMS), str(miss2), cmd.goal_kind, keeps2,
			"OK" if ok2 else "FEHLER"])


	var hit3: bool = await _tap_o_bar("guard")
	var ok3: bool = hit3 and cmd.goal_kind == 1 and not action_bar.visible
	fails += 0 if ok3 else 1
	print("T --test-tap-orders: 3 Eintrag „Bewachen\" → Befehlsart=%d (1=Bewachen), Leiste zu=%s, Meldung \"%s\" %s" % [
			cmd.goal_kind, not action_bar.visible, _last_gesture, "OK" if ok3 else "FEHLER"])


	world.select_only(cmd)
	cmd.goal_kind = -1
	await _tap_o_map(await _tap_o_aim(bld.pos))
	var items4: bool = action_bar.visible and action_bar.ITEMS.has("move") and not action_bar.ITEMS.has("guard")
	var list4 := str(action_bar.ITEMS)
	var hit4: bool = await _tap_o_bar("move")
	var near4: float = cmd.goal.distance_to(bld.pos) / ProtoWorld.CELL
	var ok4: bool = items4 and hit4 and cmd.goal_kind == 0 and near4 > 0.5
	fails += 0 if ok4 else 1
	print("T --test-tap-orders: 4 Ziel eigenes %s → Leiste %s, Eintrag „Bewegen\" → Befehlsart=%d (0=Bewegen), Ziel %.1f Zellen vom Gebäude %s" % [
			bld.type, list4, cmd.goal_kind, near4,
			"OK" if ok4 else "FEHLER"])


	world.select_only(cmd)
	cmd.goal_kind = -1
	await _tap_o_map(await _tap_o_aim(mate.pos))
	var was5: bool = action_bar.visible and action_bar.ITEMS.has("guard")
	await _tap_o_beside(world.world_to_screen(bld.pos))
	var now5: bool = action_bar.visible and not action_bar.ITEMS.has("guard") and action_bar.ITEMS.has("move")
	var ok5: bool = was5 and now5 and cmd.goal_kind == -1
	fails += 0 if ok5 else 1
	print("T --test-tap-orders: 5 Zielwechsel %s → %s: Leiste erst Einheit=%s, dann Gebäude=%s, Befehl dazwischen=%d (−1 = keiner) %s" % [
			mate.type, bld.type, was5, now5, cmd.goal_kind, "OK" if ok5 else "FEHLER"])


	var void6 := world.world_to_screen(_tap_o_free_spot(_test_origin))
	await _tap_o_beside(void6)
	var ok6: bool = not action_bar.visible and cmd.goal_kind == -1
	fails += 0 if ok6 else 1
	print("T --test-tap-orders: 6 Tipp ins Leere bei offener Leiste → Leiste zu=%s, Befehlsart=%d (−1 = kein Befehl) %s" % [
			not action_bar.visible, cmd.goal_kind, "OK" if ok6 else "FEHLER"])


	world.select_only(cmd)
	cmd.goal_kind = -1
	var spot := _tap_o_free_spot(_test_origin)
	var p7 := await _tap_o_aim(spot)
	_on_long_press(p7)
	await get_tree().process_frame
	await get_tree().process_frame
	var miss7: Array = []
	for a in ["move", "attack_move", "force_fire", "stop", "scatter", "clear", "cancel"]:
		if not action_bar.ITEMS.has(a):
			miss7.append(a)
	var items7 := str(action_bar.ITEMS)
	var hit7: bool = await _tap_o_bar("attack_move")
	var near7: float = cmd.goal.distance_to(world.screen_to_world(p7)) / ProtoWorld.CELL
	var ok7: bool = miss7.is_empty() and hit7 and cmd.goal_kind == 1 and near7 < 2.0
	fails += 0 if ok7 else 1
	print("T --test-tap-orders: 7 Langdruck auf Boden → Leiste %s, fehlend %s, Eintrag „Angriffszug\" → Befehlsart=%d (1), %.1f Zellen neben der Stelle %s" % [
			items7, str(miss7), cmd.goal_kind, near7, "OK" if ok7 else "FEHLER"])


	if apc != null and pax != null:
		world.select_only(pax)
		world.order_enter_transport(apc)
		var loaded: bool = await _tap_o_wait(func(): return apc.passengers > 0, 900)
		world.select_only(apc)
		var drop := (Vector2(_test_origin + Vector2i(9, 8)) + Vector2(0.5, 0.5)) * ProtoWorld.CELL
		var p8 := await _tap_o_aim(drop)
		_on_long_press(p8)
		await get_tree().process_frame
		await get_tree().process_frame
		var has8: bool = action_bar.ITEMS.has("unload")
		var hit8: bool = await _tap_o_bar("unload")
		var queued8: bool = not _unload_ids.is_empty()
		var done8: bool = await _tap_o_wait(func(): return apc.passengers == 0, 2000)
		var ok8: bool = loaded and has8 and hit8 and queued8 and done8
		fails += 0 if ok8 else 1
		print("T --test-tap-orders: 8 Entladen hier → beladen=%s, Eintrag „Entladen\"=%s, Fahrbefehl gemerkt=%s, ausgestiegen=%s (Rest an Bord %d) %s" % [
				loaded, has8, queued8, done8, apc.passengers, "OK" if ok8 else "FEHLER"])
	else:
		print("T --test-tap-orders: 8 Entladen hier — kein Transporter, übersprungen")


	world.select_only(cmd)
	_on_double_tap(await _tap_o_aim(mate.pos))
	await get_tree().process_frame
	var ok9: bool = world.selection.size() >= 1 and not world.selection.has(cmd) and world.selection[0].type == mate.type
	fails += 0 if ok9 else 1
	print("T --test-tap-orders: 9 Doppeltipp auf eigene %s → Auswahl=%d × %s %s" % [
			mate.type, world.selection.size(),
			"—" if world.selection.is_empty() else world.selection[0].type,
			"OK" if ok9 else "FEHLER: keine Neuauswahl"])


	world.select_only(cmd)
	cmd.goal_kind = -1
	await _tap_o_map(await _tap_o_aim(foe.pos))
	var ok10: bool = world.selection.size() == 1 and world.selection[0].id == cmd.id \
			and cmd.goal_kind == 2 and not action_bar.visible
	fails += 0 if ok10 else 1
	print("T --test-tap-orders: 10 Tipp auf gegnerisches %s → Befehlsart=%d (2=Angriff), Leiste zu=%s, Meldung \"%s\" %s" % [
			foe.type, cmd.goal_kind, not action_bar.visible, _last_gesture, "OK" if ok10 else "FEHLER"])


	for i in 3:
		var sp := _tap_slot_point()
		world.center_on(world.visible_world_rect().get_center() + (foe.pos - world.screen_to_world(sp)))
		await get_tree().process_frame
		await get_tree().process_frame
	var sp2 := _tap_slot_point()
	var under = world.pick_unit(world.screen_to_world(sp2), Dp.px(HIT_RADIUS_DP) / world.zoom)
	var aligned: bool = under != null and under.id == foe.id
	world.select_only(cmd)
	groups.assign(0)
	world.clear_selection()
	world.select_only(cmd)
	cmd.goal_kind = -1
	_last_gesture = ""
	var before_sel: int = world.selection.size()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = sp2
		ev.pressed = pressed
		get_viewport().push_input(ev)
	groups._press_slot = -1
	var attacked: bool = cmd.goal_kind == 2
	var grouped: bool = world.selection.size() == 1 and world.selection[0].id == cmd.id
	var ok11: bool = aligned and attacked and grouped
	fails += 0 if ok11 else 1
	print("T --test-tap-orders: 11 Tipp auf Gruppenknopf 1 über gegnerischem %s bei %s → darunter=%s, Befehlsart=%d (2=Angriff), Gruppe danach gewählt=%s (vorher %d) %s" % [
			foe.type, sp2, _tap_o_name(under), cmd.goal_kind, grouped, before_sel,
			"OK" if ok11 else "FEHLER"])


	world.select_only(cmd)
	world.additive_select = true
	await _tap_o_map(await _tap_o_aim(mate.pos))
	var first12: bool = action_bar.ITEMS.size() >= 2 and action_bar.ITEMS[0] == "select" \
			and action_bar.ITEMS[1] == "add"
	var list12 := str(action_bar.ITEMS)
	var hit12: bool = await _tap_o_bar("select")
	world.additive_select = false
	var ok12: bool = first12 and hit12 and world.selection.size() == 1 \
			and world.selection[0].id == mate.id
	fails += 0 if ok12 else 1
	print("T --test-tap-orders: 12 Ziel eigene %s → Leiste %s (》Auswählen《 zuerst, 》Hinzufügen《 danach=%s), nach 》Auswählen《 Auswahl=%d × %s %s" % [
			mate.type, list12, first12, world.selection.size(),
			"—" if world.selection.is_empty() else world.selection[0].type,
			"OK" if ok12 else "FEHLER"])


	world.select_exclusive(cmd)
	await _tap_o_map(await _tap_o_aim(mate.pos))
	var hit13: bool = await _tap_o_bar("add")
	var ok13: bool = hit13 and world.selection.size() == 2 and world.selection.has(cmd) \
			and world.selection.has(mate)
	fails += 0 if ok13 else 1
	print("T --test-tap-orders: 13 Eintrag „Hinzufügen\" → Auswahl=%d (%s + %s erwartet) %s" % [
			world.selection.size(), cmd.type, mate.type, "OK" if ok13 else "FEHLER"])

	print("T --test-tap-orders: fertig — %d Fehlschläge" % fails)
	get_tree().quit()


func _tap_slot_point() -> Vector2:
	return groups.global_position + Vector2(groups.size.x / 2.0, groups.step / 2.0)


var _tesla_shot_frames := -1


func _tesla_zap_now() -> bool:
	for u in world.units:
		if u.alive and u.type == "tsla" and u.firing:
			return true
	return false


func _run_test_voice_duck() -> void:
	while world.sim == null or world.sim.tick() < 60:
		await get_tree().process_frame
	var hub := NetHub.hub()
	var v = hub.ensure_voice()
	v.test_tone = true
	var fehler := 0
	print("T --test-voice-duck: Start — %s" % AudioMix.state_line())


	for fall in [{"headset": 0, "name": "ohne Headset", "soll": AudioMix.DUCK_SILENT_DB},
			{"headset": 1, "name": "mit Headset", "soll": AudioMix.DUCK_HEADSET_DB}]:
		AudioMix.set_test_headset(int(fall["headset"]))
		v.set_mode(VoiceChat.Mode.TEAM)
		AudioMix.settle()
		await get_tree().process_frame
		print("T --test-voice-duck: %s AN — %s" % [fall["name"], AudioMix.state_line()])
		fehler += _duck_check(str(fall["name"]), float(fall["soll"]))
		v.set_mode(VoiceChat.Mode.OFF)
		AudioMix.settle()
		await get_tree().process_frame
		print("T --test-voice-duck: %s AUS — %s" % [fall["name"], AudioMix.state_line()])
		fehler += _duck_check(str(fall["name"]) + " aus", 0.0)


	AudioMix.set_test_headset(1)
	var origin := Vector2i(20, 20)
	for u in world.units:
		if u.alive and u.player == 0:
			origin = Vector2i(u.pos / ProtoWorld.CELL)
			break

	v.set_mode(VoiceChat.Mode.TEAM)
	_update_voice_power()
	if int(v.mode) == int(VoiceChat.Mode.OFF):
		print("T --test-voice-duck: FEHLER — Sprechfunk ging vor dem Stromausfall gar nicht an")
		fehler += 1


	if world.type_ids.has("tsla"):
		world.call("_add_building", "tsla", 0, origin + Vector2i(-6, -6))
	for _i in 30:
		await get_tree().process_frame
	print("T --test-voice-duck: Strom %d/%d, low_power=%s" % [
			world.sim.power_provided(0), world.sim.power_drained(0), world.low_power()])
	if not world.low_power():
		print("T --test-voice-duck: FEHLER — Niedrigstrom ließ sich nicht herstellen (Rest des Strom-Blocks übersprungen)")
		fehler += 1
	else:
		if int(v.mode) != int(VoiceChat.Mode.OFF):
			print("T --test-voice-duck: FEHLER — Sprechfunk lief bei Niedrigstrom weiter (Modus %d)" % int(v.mode))
			fehler += 1
		if not bool(v.receive_muted):
			print("T --test-voice-duck: FEHLER — Empfang war bei Niedrigstrom nicht dicht")
			fehler += 1

		_toggle_mic(false)
		if int(v.mode) != int(VoiceChat.Mode.OFF):
			print("T --test-voice-duck: FEHLER — Einschalten trotz Niedrigstrom möglich")
			fehler += 1
		else:
			print("T --test-voice-duck: Einschalten bei Niedrigstrom abgelehnt — OK (Hinweis „%s\")"
					% tr("toast.voice_no_power"))

		for k in 3:
			if world.type_ids.has("powr"):
				world.call("_add_building", "powr", 0, origin + Vector2i(-10 + k * 3, -10))
		for _i in 30:
			await get_tree().process_frame
		print("T --test-voice-duck: Strom zurück %d/%d, low_power=%s, Modus %d" % [
				world.sim.power_provided(0), world.sim.power_drained(0), world.low_power(), int(v.mode)])
		if world.low_power():
			print("T --test-voice-duck: FEHLER — Strom kam nicht zurück")
			fehler += 1
		elif int(v.mode) != int(VoiceChat.Mode.TEAM):
			print("T --test-voice-duck: FEHLER — Sprechfunk kam nicht von selbst zurück (Modus %d)" % int(v.mode))
			fehler += 1
		if bool(v.receive_muted):
			print("T --test-voice-duck: FEHLER — Empfang blieb nach der Stromrückkehr dicht")
			fehler += 1


	var tesla_ids: Array = world.sfx.tesla_sounds.keys()
	print("T --test-voice-duck: Tesla-Sounds %s (erwartet 1 Kennung für tesla1)" % str(tesla_ids))
	if tesla_ids.is_empty():
		print("T --test-voice-duck: FEHLER — keine Tesla-Waffe erkannt (zap_duration/report_sound)")
		fehler += 1
	else:
		var tid := int(tesla_ids[0])
		var mitte: Vector2 = world.visible_world_rect().get_center()
		var weit: Vector2 = world.visible_world_rect().position - Vector2(4000, 4000)
		v.set_mode(VoiceChat.Mode.TEAM)
		AudioMix.settle()
		AudioMix.crackles_played = 0
		AudioMix._last_crackle = -1000.0
		world.sfx.play_events(PackedInt32Array([tid, int(mitte.x), int(mitte.y)]))
		var nach_erst := AudioMix.crackles_played
		world.sfx.play_events(PackedInt32Array([tid, int(mitte.x), int(mitte.y)]))
		var nach_zweit := AudioMix.crackles_played
		AudioMix._last_crackle = -1000.0
		world.sfx.play_events(PackedInt32Array([tid, int(weit.x), int(weit.y)]))
		var nach_weit := AudioMix.crackles_played
		v.set_mode(VoiceChat.Mode.OFF)
		AudioMix._last_crackle = -1000.0
		world.sfx.play_events(PackedInt32Array([tid, int(mitte.x), int(mitte.y)]))
		var nach_aus := AudioMix.crackles_played
		print("T --test-voice-duck: Knacken im Bild=%d, sofort nochmal=%d, ausserhalb=%d, Funk aus=%d"
				% [nach_erst, nach_zweit, nach_weit, nach_aus])
		if nach_erst != 1:
			print("T --test-voice-duck: FEHLER — Tesla im Bild gab kein Knacken")
			fehler += 1
		if nach_zweit != 1:
			print("T --test-voice-duck: FEHLER — zweites Knacken vor Ablauf der %.0f s" % AudioMix.CRACKLE_GAP)
			fehler += 1
		if nach_weit != 1:
			print("T --test-voice-duck: FEHLER — Tesla ausserhalb des Bildes gab ein Knacken")
			fehler += 1
		if nach_aus != 1:
			print("T --test-voice-duck: FEHLER — Knacken bei ausgeschaltetem Sprechfunk")
			fehler += 1

	AudioMix.set_test_headset(-1)
	AudioMix.settle()
	print("T --test-voice-duck: Ende — %s" % AudioMix.state_line())
	print("T --test-voice-duck: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


func _duck_check(fall: String, soll_offset: float) -> int:
	var fehler := 0
	for key in AudioMix.DUCK_KEYS:
		var idx := AudioServer.get_bus_index(AudioMix.BUSES[key])
		if idx < 0:
			continue
		var basis := linear_to_db(maxf(AudioMix.volume(key), 0.0001))
		var ist := AudioServer.get_bus_volume_db(idx)
		if absf(ist - (basis + soll_offset)) > 0.2:
			print("T --test-voice-duck: FEHLER (%s) %s = %+.1f dB, erwartet %+.1f dB" % [
					fall, AudioMix.BUSES[key], ist, basis + soll_offset])
			fehler += 1

	var ridx := AudioServer.get_bus_index(AudioMix.BUSES[AudioMix.RADIO_KEY])
	if ridx >= 0:
		var rbasis := linear_to_db(maxf(AudioMix.volume(AudioMix.RADIO_KEY), 0.0001))
		var rsoll: float = maxf(0.0, rbasis) if soll_offset < 0.0 else rbasis
		var rist := AudioServer.get_bus_volume_db(ridx)
		if absf(rist - rsoll) > 0.2:
			print("T --test-voice-duck: FEHLER (%s) Funk = %+.1f dB, erwartet %+.1f dB" % [fall, rist, rsoll])
			fehler += 1
	return fehler


func _run_test_spy() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step >= 1:
		var now := _sp_permille(1, 2)
		if _spy_nuke_last >= 0 and now < _spy_nuke_last and _spy_nuke_drop == "":
			_spy_nuke_drop = "Tick %d: %d‰ → %d‰" % [tick, _spy_nuke_last, now]
		_spy_nuke_last = now
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break


		var i := 0
		for t in ["proc", "powr", "dome", "barr", "mslo", "tsla"]:
			if world.type_ids.has(t):
				world.call("_add_building", t, 1, origin + Vector2i(-5 + (i % 3) * 5, -8 - (i / 3) * 4))
				i += 1

		for k in range(3):
			if world.type_ids.has("powr"):
				world.call("_add_building", "powr", 1, origin + Vector2i(-5 + k * 4, -16))

		if world.type_ids.has("powr"):
			var own: ProtoWorld.Unit = world.call("_add_building", "powr", 0, origin + Vector2i(6, 4))
			if own != null:
				sim.set_health(own.id, int(world.types["powr"].get("hp", 1)) / 3)

		for t in ["e6", "e6", "e7", "spy", "spy", "thf", "e1"]:
			if world.type_ids.has(t):
				world.spawn_unit(t, 0, origin + Vector2i(i, 2))
				i += 1
		world.spawn_unit("e1", 1, origin + Vector2i(0, -4))


		if world.type_ids.has("jeep"):
			world.spawn_unit("jeep", 1, origin + Vector2i(3, -4))


		for u in world.units:
			if u.alive and u.player == 1 and (u.type == "tsla" or u.type == "e1"):
				sim.set_stance(u.id, 0)
		sim.give_credits(1, 4000)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 25:
		print("T: Strom Gegner=%d Credits Gegner=%d Credits Spieler=%d" % [sim.power_provided(1), sim.credits(1), sim.credits(0)])
		_order("spy", "dome", "Spion → Radarkuppel")
		_order("spy", "mslo", "Spion → Raketensilo (Ladung zurücksetzen)", 1, 1)
		_order("thf", "proc", "Dieb → Raffinerie")
		_order("e6", "powr", "Pionier → eigenes Kraftwerk", 0)
		_order("e6", "tsla", "Pionier → Tesla-Spule erobern", 1, 1)

		var tanya: ProtoWorld.Unit = _find_own("e7")
		if tanya != null:
			sim.set_stance(tanya.id, 0)
		_order("e7", "barr", "Tanya → Kaserne")


		var spy: ProtoWorld.Unit = _find_own("spy")
		var foe: ProtoWorld.Unit = _find_foe("e1")
		var veh: ProtoWorld.Unit = _find_foe("jeep")
		if spy != null and veh != null:
			world.select_only(spy)
			print("T: Verkleidung als Fahrzeug ", "FEHLER (angenommen)" if world.order_disguise(veh) else "abgelehnt (richtig)")
		if spy != null and foe != null:
			world.select_only(spy)
			print("T: Verkleidung ", "ok" if world.order_disguise(foe) else "fehlgeschlagen")
			print("T: Spion sieht aus wie Typ %d (echt %d)" % [sim.disguise_type(spy.id), world.type_ids.get("spy", -1)])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 3000:
		_test_step = 3
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

		print("T: Atombomben-Ladung zurückgesetzt: %s (jetzt %d‰)"
				% [_spy_nuke_drop if _spy_nuke_drop != "" else "NEIN — kein Rückgang gesehen", _sp_permille(1, 2)])
		var silo: ProtoWorld.Unit = _find_foe("mslo")
		print("T: Raketensilo infiltriert=%d" % [sim.infiltrated_count(silo.id) if silo != null else -1])

		print("T: Tesla-Spule erobert=%s (Gegner hat noch %s)" % [_find_own("tsla") != null, _find_foe("tsla") != null])
		if _screenshot_path != "":
			var shot_at: ProtoWorld.Unit = _find_own("tsla")
			if shot_at == null:
				shot_at = _find_own("spy")
			if shot_at != null:
				world.center_on(shot_at.pos)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("T --test-spy: Screenshot %s" % _screenshot_path)
		get_tree().quit()


func _run_test_bridge() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var br: ProtoWorld.Unit = _find_bridge()
		if br == null:
			print("T --test-bridge: keine Brücke auf dieser Karte — mit --map a-path-beyond starten")
			get_tree().quit()
			return

		sim.set_health(br.id, int(world.types[br.type].get("hp", 1)) * 3 / 10)


		var cell := Vector2i(br.pos / ProtoWorld.CELL)
		var eng: ProtoWorld.Unit = world.spawn_unit("e6", 0, cell)
		if eng == null:
			print("T --test-bridge: kein Pionier (e6) in den Regeln")
			get_tree().quit()
			return
		world.select_only(eng)
		print("T: Brücke %s bei %s, Pionier repariert Brücken=%s, enter_kind=%d (5 = Brücke reparieren)" % [
				br.type, cell, world.types.get("e6", {}).get("repairs_bridges", "?"), world.enter_kind(br)])


		var tap: Vector2 = world.world_to_screen(br.pos)
		_on_tap(tap)
		print("T: Tipp auf die Brücke → Befehl „%s\"" % [world.order_enter(br)])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 900:
		_test_step = 2
		var br: ProtoWorld.Unit = _find_bridge()
		print("T: Brücke HP=%.2f (1.00 = repariert), Pionier verbraucht=%s" % [
				br.hp if br != null else -1.0, _find_own("e6") == null])
		if _screenshot_path != "":
			if br != null:
				world.center_on(br.pos)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("T --test-bridge: Screenshot %s" % _screenshot_path)
		get_tree().quit()


func _find_bridge() -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and not world.types[u.type].get("bridge", {}).is_empty():
			return u
	return null


var _brs: Array = []
var _br_i := -1
var _br_tanya := -1
var _br_fail := 0
var _br_done := 0


func _run_test_bridges() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_test_step = 1
		var spans: Array = world.bridge_spans()
		if spans.is_empty():
			print("T --test-bridges: keine Brücke auf dieser Karte — mit --map a-path-beyond/tandem/chernobyl starten")
			get_tree().quit()
			return
		var templates: Dictionary = world.atlas().meta.get("templates", {})
		var seen := {}
		print("T --test-bridges: %d Spannen auf „%s“" % [spans.size(), world.map_data.slug])
		for b: Dictionary in spans:
			var u: ProtoWorld.Unit = b["unit"]
			var t: Dictionary = world.types[u.type]
			var cells: Array = b["cells"]
			var meta: Dictionary = templates.get(str(int(b["bridge"].get("template", 0))), {})


			var rect: Rect2 = world.unit_rect(u)
			var inside := 0
			var in_rect := 0
			for c: Vector2i in cells:
				var wp := Vector2(c.x + 0.5, c.y + 0.5) * ProtoWorld.CELL
				if world.pick_bridge(wp, false) == u:
					inside += 1
				if rect.has_point(wp):
					in_rect += 1
			var bnds: Vector2 = t.get("bounds", Vector2.ZERO)
			var dims := Vector2i(bnds / ProtoWorld.CELL)
			var covered: bool = inside == cells.size()
			if not covered:
				_br_fail += 1
			print("T   %-9s Templ %3d %dx%d, Regel-Abdruck %dx%d, Kacheln %2d, Langdruck trifft auf %2d (Regel-Rechteck deckt %2d) %s | sprengbar=%s" % [
					u.type, int(b["bridge"].get("template", 0)), int(meta.get("w", 0)), int(meta.get("h", 0)),
					dims.x, dims.y, cells.size(), inside, in_rect,
					"OK" if covered else "FEHLER (Langdruck geht auf %d Kacheln ins Leere)" % [cells.size() - inside],
					t.get("demolishable", false)])
			if not seen.has(u.type):
				seen[u.type] = true
				_brs.append(b)
		print("T --test-bridges: %d Brückenart(en) werden gesprengt: %s" % [_brs.size(), seen.keys()])
		_br_i = -1
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 10:
		_br_i += 1
		if _br_i >= _brs.size():
			print("T --test-bridges: %d von %d Arten gesprengt, %d Fehler %s" % [
					_br_done, _brs.size(), _br_fail, "OK" if _br_fail == 0 and _br_done == _brs.size() else "FEHLER"])
			get_tree().quit()
			return
		var b: Dictionary = _brs[_br_i]
		var u: ProtoWorld.Unit = b["unit"]
		if u == null or not u.alive:
			print("T --test-bridges: %s schon zerstört — übersprungen" % [u.type if u != null else "?"])
			_test_tick = tick
			return


		var cells: Array = b["cells"]
		var deck: Vector2i = cells[cells.size() - 1]
		var tanya := world.spawn_unit("e7", 0, deck)
		if tanya == null:
			print("T --test-bridges: FEHLER — Tanya (e7) fehlt in den Regeln")
			get_tree().quit()
			return
		_br_tanya = tanya.id
		world.select_only(tanya)


		var c := Vector2(cells[0].x + 0.5, cells[0].y + 0.5) * ProtoWorld.CELL
		world.center_on(c)


		var tap_hit = world.pick_unit(c, 0.0)
		var long_hit = world.pick_bridge(c, false)
		var kind: int = world.enter_kind(u)
		var ok_pick: bool = tap_hit == null and long_hit == u and kind == ProtoWorld.ENTER_DEMOLISH
		if not ok_pick:
			_br_fail += 1
		print("T --test-bridges: %s — Tipp trifft=%s (erwartet nichts), Langdruck trifft=%s, enter_kind=%d (erwartet 3) %s" % [
				u.type, ("nichts" if tap_hit == null else tap_hit.type),
				("nichts" if long_hit == null else long_hit.type), kind, "OK" if ok_pick else "FEHLER"])
		_on_long_press(world.world_to_screen(c))
		var has_c4: bool = radial.visible and radial.ITEMS.has("c4")
		if not has_c4:
			_br_fail += 1
		print("T --test-bridges: %s — Radialmenü offen=%s, Eintrag Sprengen(C4)=%s %s" % [
				u.type, radial.visible, has_c4, "OK" if has_c4 else "FEHLER"])
		radial.cancel()
		if has_c4:
			_on_radial("c4")
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:
		var b: Dictionary = _brs[_br_i]
		var u: ProtoWorld.Unit = b["unit"]
		if u.alive and tick < _test_tick + 1200:
			return
		var deck: Vector2i = b["cells"][0]
		var ter: int = sim.cell_terrain(deck.x, deck.y)


		var walkable: bool = ter >= 0 and ter <= ProtoWorld.TER_BEACH
		var ok: bool = not u.alive and not walkable
		if ok:
			_br_done += 1
		else:
			_br_fail += 1
		print("T --test-bridges: %s zerstört=%s nach %d Ticks; Fahrbahn (%d,%d) Terrain=%s begehbar=%s %s" % [
				u.type, not u.alive, tick - _test_tick, deck.x, deck.y,
				(ProtoWorld.TERRAIN_ORDER[ter] if ter >= 0 and ter < ProtoWorld.TERRAIN_ORDER.size() else str(ter)),
				walkable, "OK" if ok else "FEHLER"])
		_test_step = 2
		_test_tick = tick


var _cap_targets: Array = []
var _cap_engineers: Array = []
var _cap_fail := 0
var _cap_before := {}


func _cap_visible(kind: int) -> Array:
	var hidden := {}
	for t in world.sim.hidden_items(0, kind):
		hidden[t] = true
	var out: Array = []
	for id in build_bar._all_types(kind):
		if not hidden.has(id):
			out.append(world.type_names[id])
	return out


func _cap_ready(kind: int) -> Array:
	var out: Array = []
	for id in world.sim.buildable(0, kind):
		out.append(world.type_names[id])
	return out


func _cap_report(titel: String) -> Dictionary:
	var namen := ["Gebäude", "Abwehr", "Infanterie", "Fahrzeuge", "Flugzeuge", "Schiffe"]
	var kinds := [0, 3, 1, 2, 4, 5]
	var snap := {}
	print("T --test-capture: %s" % titel)
	for i in kinds.size():
		var k: int = kinds[i]
		var vis: Array = _cap_visible(k)
		var rdy: Array = _cap_ready(k)
		snap[k] = vis
		var neu: Array = []
		if _cap_before.has(k):
			for n in vis:
				if not (_cap_before[k] as Array).has(n):
					neu.append(n)
		print("T   %-10s sichtbar %2d: %s" % [namen[i], vis.size(), ", ".join(PackedStringArray(vis))])
		print("T   %-10s baubar   %2d: %s%s" % ["", rdy.size(), ", ".join(PackedStringArray(rdy)),
				("   NEU: " + ", ".join(PackedStringArray(neu))) if not neu.is_empty() else ""])
	return snap


func _run_test_capture() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		var origin := Vector2i(30, 30)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		sim.set_faction(0, "soviet")
		sim.set_faction(1, "allies")
		world.player_factions[0] = "soviet"
		world.player_factions[1] = "allies"
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)

		for e in [["fact", Vector2i(0, 0)], ["powr", Vector2i(4, 0)], ["proc", Vector2i(4, 4)],
				["barr", Vector2i(0, 5)], ["weap", Vector2i(-4, 0)], ["dome", Vector2i(-4, 5)],
				["fix", Vector2i(-8, 0)]]:
			world.call("_add_building", e[0], 0, _test_origin + (e[1] as Vector2i))

		for e in [["tent", Vector2i(0, -8)], ["weap", Vector2i(-5, -8)], ["fact", Vector2i(5, -8)],
				["atek", Vector2i(10, -8)]]:
			var b = world.call("_add_building", e[0], 1, _test_origin + (e[1] as Vector2i))
			if b != null:
				_cap_targets.append(b)
		print("T --test-capture: Spieler 0 = %s, Spieler 1 = %s; Ziele: %s" % [
				sim.faction(0) if sim.has_method("faction") else "soviet", "allies",
				", ".join(PackedStringArray(_cap_targets.map(func(u): return u.type)))])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:
		_cap_before = _cap_report("VOR der Eroberung (Sowjet mit eigener Basis)")

		for t in _cap_targets:
			var cell := Vector2i(t.pos / ProtoWorld.CELL) + Vector2i(0, 3)
			var eng := world.spawn_unit("e6", 0, cell)
			if eng == null:
				print("T --test-capture: FEHLER — Pionier (e6) fehlt in den Regeln")
				get_tree().quit()
				return
			_cap_engineers.append(eng)
			world.select_only(eng)
			_on_tap(world.world_to_screen(t.pos))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:
		var offen := 0
		for t in _cap_targets:
			if t.alive and t.player != 0:
				offen += 1
		if offen > 0 and tick < _test_tick + 1500:
			return
		var uebernommen: Array = []
		for t in _cap_targets:
			if t.alive and t.player == 0:
				uebernommen.append(t.type)
		if uebernommen.size() != _cap_targets.size():
			_cap_fail += 1
		print("T --test-capture: erobert %d von %d (%s) %s" % [uebernommen.size(), _cap_targets.size(),
				", ".join(PackedStringArray(uebernommen)),
				"OK" if uebernommen.size() == _cap_targets.size() else "FEHLER"])
		_cap_report("NACH der Eroberung (alliierte Technik beim Sowjet)")

		var soll_geb := ["tent", "atek", "hpad", "syrd"]
		var soll_abw := ["pbox", "gun", "agun"]
		var soll_inf := ["medi", "mech"]
		var soll_fzg := ["1tnk", "jeep", "2tnk", "arty"]
		for paar in [[0, soll_geb], [3, soll_abw], [1, soll_inf], [2, soll_fzg]]:
			var vis: Array = _cap_visible(paar[0])
			var fehlt: Array = []
			for n in (paar[1] as Array):
				if not vis.has(n):
					fehlt.append(n)
			if not fehlt.is_empty():
				_cap_fail += 1
			print("T --test-capture: Reiter %d — erwartet %s, fehlt %s %s" % [paar[0],
					", ".join(PackedStringArray(paar[1] as Array)), ", ".join(PackedStringArray(fehlt)),
					"OK" if fehlt.is_empty() else "FEHLER"])

		for t in _cap_targets:
			if t.type == "fact":
				sim.destroy(t.id)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 30:
		var vis0: Array = _cap_visible(0)
		var vis3: Array = _cap_visible(3)
		var weg := not vis0.has("tent") and not vis0.has("atek") and not vis3.has("pbox")
		if not weg:
			_cap_fail += 1
		_cap_report("NACH dem Verlust des eroberten Bauhofs")
		print("T --test-capture: alliierte Gebäude/Abwehr wieder verschwunden=%s %s" % [
				weg, "OK" if weg else "FEHLER"])

		var inf: Array = _cap_visible(1)
		var fzg: Array = _cap_visible(2)
		var bleibt: bool = inf.has("medi") and fzg.has("1tnk")
		if not bleibt:
			_cap_fail += 1
		print("T --test-capture: Sanitäter/Alliiertenpanzer bleiben (Kaserne+Fabrik noch unser)=%s %s" % [
				bleibt, "OK" if bleibt else "FEHLER"])
		print("T --test-capture: %d Fehler %s" % [_cap_fail, "OK" if _cap_fail == 0 else "FEHLER"])
		get_tree().quit()


func _sp_permille(owner: int, kind: int) -> int:
	var st: PackedInt32Array = world.sim.support_powers(owner)
	return st[kind * 4 + 2] if st.size() > kind * 4 + 2 else -1


func _find_decoration() -> ProtoWorld.Unit:
	for u in world.units:
		var tt: int = int(world.types[u.type].get("target_types", 0))
		if u.alive and world.types[u.type].get("decoration", false) \
				and tt & ~(ProtoWorld.TARGET_TREES | ProtoWorld.TARGET_NO_AUTO) == 0:
			return u
	return null


func _find_own(type: String, nth: int = 0) -> ProtoWorld.Unit:
	var n := nth
	for u in world.units:
		if u.alive and u.player == 0 and u.type == type:
			if n <= 0:
				return u
			n -= 1
	return null


func _find_foe(type: String) -> ProtoWorld.Unit:
	for u in world.units:
		if u.alive and u.player == 1 and u.type == type:
			return u
	return null


func _order(unit_type: String, target_type: String, label: String, target_player: int = 1, nth: int = 0) -> void:
	var u: ProtoWorld.Unit = _find_own(unit_type, nth)
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
const ARM_GAP := 6
var _arm_origin := Vector2i(20, 20)
var _arm_case := 0
var _arm_ok := 0
var _arm_fail := 0
var _arm_shooter: ProtoWorld.Unit = null
var _arm_target: ProtoWorld.Unit = null
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


		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)

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
var _barrel_target: ProtoWorld.Unit = null
var _barrel_neighbours: Array = []
var _barrel_shooter: ProtoWorld.Unit = null
var _barrel_shot_at := -1
var _barrel_shot_done := false


func _run_test_barrels() -> void:
	if ProtoWorld.next_mission != "":
		_run_test_barrels_mission()
		return
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


var _test_kaserne := false
var _kaserne_id := -1
var _kaserne_type := ""
var _kaserne_cell := Vector2i.ZERO
var _kaserne_bad := 0


func _kaserne_report(label: String) -> void:
	var sim = world.sim
	var atlas := world.atlas()
	var first: int = int(atlas.sprite_first_frame.get(_kaserne_type, -1))
	var count: int = int(atlas.sprite_frame_count.get(_kaserne_type, 0))
	var mk: String = _kaserne_type + "make"
	var mk_first: int = int(atlas.sprite_first_frame.get(mk, -1))
	var mk_count: int = int(atlas.sprite_frame_count.get(mk, 0))

	var buf: PackedFloat32Array = sim.render_buffer(0.0)
	var frame := -1
	var row := -1.0
	for i in buf.size() / 12:
		var f := int(buf[i * 12 + 8])
		if (first >= 0 and f >= first and f < first + count) or (mk_first >= 0 and f >= mk_first and f < mk_first + mk_count):
			frame = f
			row = buf[i * 12 + 9]
			break
	var u: ProtoWorld.Unit = world.unit_by_id(_kaserne_id)
	var unpowered := u != null and u.unpowered


	var bad := 0
	if int(row) != 0:
		print("FEHLER: Palettenzeile %.1f statt 0 (helle Spielerzeile) bei %s" % [row, label])
		bad += 1
	if unpowered:
		print("FEHLER: Strom-Bit gesetzt bei %s — die Kaserne hat kein ^DisableOnLowPower" % label)
		bad += 1
	_kaserne_bad += bad
	print("T%d --test-kaserne %s: %s Frame=%d (idle %d..%d, make %d..%d) Palettenzeile=%.1f (hell=0, dim=%d, vorhang=%d, terrain=%d, husk=%d, getaucht=%d) Strom-Bit=%s Bilanz=%d/%d"
			% [sim.tick(), label, _kaserne_type, frame, first, first + count - 1, mk_first, mk_first + mk_count - 1,
			row, atlas.dim_offset, atlas.invuln_offset, atlas.terrain_row, atlas.husk_offset, atlas.submerged_row,
			str(unpowered), sim.power_provided(0), sim.power_drained(0)])
	if _screenshot_path != "":
		var path: String = _screenshot_path.get_basename() + "_" + label + ".png"
		get_viewport().get_texture().get_image().save_png(path)
		print("Screenshot: ", path)


const KASERNE_LOWPOWER := ["agun", "atef", "atek", "dome", "domf", "gap", "iron", "mslf", "mslo",
	"pdof", "pdox", "sam", "tsla"]


func _kaserne_lowpower_check() -> int:
	var have: Array = []
	for name in world.types:
		if world.types[name].get("needs_power", false):
			have.append(name)
	have.sort()
	var soll := KASERNE_LOWPOWER.duplicate()
	soll.sort()
	if have != soll:
		print("FEHLER: ^DisableOnLowPower-Liste weicht ab — ist %s, soll %s" % [have, soll])
		return 1
	print("--test-kaserne: ^DisableOnLowPower = %s (wie mods/ra), Kaserne nicht dabei" % [have])
	return 0


func _run_test_kaserne() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 20000)
		_kaserne_type = "barr" if ProtoWorld.next_faction in ["soviet", "russia", "ukraine"] else "tent"


		var k := 0
		for t in ["fact", "powr", "powr"]:
			world.call("_add_building", t, 0, origin + Vector2i(-11 + k * 4, 5))
			k += 1


		var bid: int = world.type_ids.get(_kaserne_type, -1)
		world.queue_build(bid)
		var ready := false
		for _i in 20000:
			sim.step()
			var q: PackedInt32Array = sim.queue_state(0, ProtoWorld.Queue.BUILDING)
			if q.size() >= 3 and q[0] == bid and q[2] == 1:
				ready = true
				break
		if not ready:
			print("T%d --test-kaserne: %s wird nicht fertig (Voraussetzungen?)" % [tick, _kaserne_type])
			get_tree().quit()
			return
		var placed := false
		var at := origin
		for dy in range(4, 12):
			for dx in range(0, 10):
				var cand := origin + Vector2i(dx, dy)
				var res: PackedByteArray = sim.can_place(0, bid, cand.x, cand.y)
				if res.size() > 0 and res[0] == 1:
					placed = sim.place_building(0, bid, cand.x, cand.y)
					at = cand
					break
			if placed:
				break
		if not placed:
			print("T%d --test-kaserne: keine freie Bauzelle" % tick)
			get_tree().quit()
			return
		_kaserne_cell = at
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(at) + Vector2(1.0, 1.5)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = sim.tick()
	elif _test_step == 1:
		for u in world.units:
			if u.alive and u.player == 0 and u.type == _kaserne_type:
				_kaserne_id = u.id
		if _kaserne_id < 0:
			return
		_test_step = 2
		_test_tick = sim.tick()
	elif _test_step == 2 and tick >= _test_tick + 10:
		_kaserne_report("bau")
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 90:
		_kaserne_report("hell")
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 5:
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "powr":
				sim.destroy(u.id)
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5 and tick >= _test_tick + 60:
		_kaserne_report("stromlos")
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 5:
		world.call("_add_building", "powr", 0, _kaserne_cell + Vector2i(-4, 0))
		_test_step = 7
		_test_tick = tick
	elif _test_step == 7 and tick >= _test_tick + 40:
		_kaserne_report("wieder")
		_kaserne_bad += _kaserne_lowpower_check()
		print("--test-kaserne: %d Befund(e) (Sollwert 0)" % _kaserne_bad)
		get_tree().quit()


var _test_husk := false
var _husk_facings := {}


func _run_test_husk() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		var facings := [0, 128, 384, 640]
		for i in 4:
			var tname := "2tnk" if i % 2 == 0 else "3tnk"
			if not world.type_ids.has(tname):
				continue
			var v: ProtoWorld.Unit = world.spawn_unit(tname, 0, origin + Vector2i(i * 2 - 3, -4), facings[i])
			if v != null:
				_husk_facings[v.id] = facings[i]
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(0, -4)) * ProtoWorld.CELL)
		print("T%d --test-husk: %d Fahrzeuge gesetzt" % [tick, _husk_facings.size()])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 25:
		for id in _husk_facings:
			sim.destroy(id)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 15:
		var husks := 0
		var facing_ok := 0
		for u in world.units:
			if not u.alive or not str(u.type).ends_with(".husk"):
				continue
			husks += 1

			for id in _husk_facings:
				var dead: ProtoWorld.Unit = world.unit_by_id(id)
				if dead != null and dead.pos.distance_to(u.pos) < ProtoWorld.CELL \
						and absi(int(u.facing) - int(_husk_facings[id])) <= 4:
					facing_ok += 1
					break


		var smudge_cells := {}
		var list: PackedInt32Array = sim.smudges()
		for si in list.size() / 5:
			smudge_cells[Vector2i(list[si * 5], list[si * 5 + 1])] = list[si * 5 + 2]
		var under := 0
		for u in world.units:
			if u.alive and str(u.type).ends_with(".husk") and smudge_cells.has(Vector2i(u.pos / ProtoWorld.CELL)):
				under += 1
		print("T%d --test-husk: Wracks=%d (Blickrichtung übernommen: %d), Krater/Brandflecken=%d, davon unter einem Wrack=%d"
				% [tick, husks, facing_ok, smudge_cells.size(), under])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_wrack.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_wrack.png")
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 1200:


		var husks := 0
		for u in world.units:
			if u.alive and str(u.type).ends_with(".husk"):
				husks += 1
		var smudges: int = sim.smudges().size() / 5 if sim.has_method("smudges") else -1
		print("T%d --test-husk: nach Zerfall Wracks=%d (erwartet 0), Krater/Brandflecken=%d"
				% [tick, husks, smudges])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_effects := false
var _fx_cases: Array = []
var _fx_index := 0
var _fx_origin := Vector2i.ZERO
var _fx_water := Vector2i(-1, -1)
var _fx_victim := 0
var _fx_cell := Vector2i.ZERO


func _fx_case(name: String, weapon: String, kill_type: String, damage_type: int, wait: int,
		alt: int = 0, water: bool = false) -> Dictionary:
	return {"name": name, "weapon": weapon, "kill": kill_type, "dtype": damage_type,
			"wait": wait, "alt": alt, "water": water}


func _run_test_effects() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		for u in world.units:
			if u.alive and u.player == 0:
				_fx_origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		var best := 9999
		for dy in range(-24, 25):
			for dx in range(-24, 25):
				var c := _fx_origin + Vector2i(dx, dy)
				if world.terrain_type(c) != ProtoWorld.TER_WATER:
					continue
				var d: int = absi(dx) + absi(dy)
				if d < best:
					best = d
					_fx_water = c

		_fx_cases = [
			_fx_case("kugel", "m1carbine", "", -1, 1),
			_fx_case("maschinenkanone", "vulcan", "", -1, 3),
			_fx_case("granate", "grenade", "", -1, 3),
			_fx_case("rakete", "dragon", "", -1, 3),
			_fx_case("napalm", "napalm", "", -1, 4),
			_fx_case("flak", "flak-23-aa", "", -1, 2, 512),
			_fx_case("wasser", "105mm", "", -1, 3, 0, true),
			_fx_case("wasser-gross", "8inch", "", -1, 4, 0, true),
			_fx_case("schiffstod", "unitexplodeship", "", -1, 4, 0, true),
			_fx_case("tod-normal", "", "e1", 0, 8),
			_fx_case("tod-kugel", "", "e1", 1, 8),
			_fx_case("tod-kleine-explosion", "", "e1", 2, 8),
			_fx_case("tod-explosion", "", "e1", 3, 10),
			_fx_case("tod-feuer", "", "e1", 4, 16),
			_fx_case("tod-strom", "", "e1", 5, 6),
			_fx_case("tod-zermatscht", "", "e1", 6, 40),
			_fx_case("tod-fahrzeug", "", "2tnk", 3, 3),
			_fx_case("tod-gebaeude", "buildingexplode", "", -1, 3),
		]
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		print("T%d --test-effects: %d Fälle, Ursprung %s, Wasser %s"
				% [tick, _fx_cases.size(), _fx_origin, _fx_water])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1:

		if _fx_index >= _fx_cases.size():
			print("T%d --test-effects: %d Fälle fotografiert" % [tick, _fx_index])
			get_tree().quit()
			return
		if _fx_victim != 0:
			sim.remove_actor(_fx_victim)
			_fx_victim = 0
		var c: Dictionary = _fx_cases[_fx_index]
		_fx_cell = _fx_origin + Vector2i(_fx_index % 4 * 4 - 6, -5 - int(_fx_index / 4) * 4)
		if bool(c["water"]):
			_fx_cell = _fx_water
		if bool(c["water"]) and _fx_water.x < 0:
			print("T%d --test-effects: %s übersprungen (keine Wasserzelle auf der Karte)" % [tick, c["name"]])
			_fx_index += 1
			return

		world.center_on((Vector2(_fx_cell) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 3:
		var c: Dictionary = _fx_cases[_fx_index]
		var ok := true
		if str(c["kill"]) != "":
			var v: ProtoWorld.Unit = world.spawn_unit(str(c["kill"]), 1, _fx_cell, 128)
			if v == null:
				ok = false
			else:
				_fx_victim = v.id
				sim.destroy(v.id, int(c["dtype"]))
		else:
			var wid: int = world.weapon_ids.get(str(c["weapon"]), -1)
			if wid < 0:
				ok = false
			else:
				sim.test_impact(wid, Vector2i(_fx_cell.x * 1024 + 512, _fx_cell.y * 1024 + 512), int(c["alt"]))
		if not ok:
			print("T%d --test-effects: %s übersprungen (Typ/Waffe fehlt)" % [tick, c["name"]])
			_fx_index += 1
			_test_step = 1
			return
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + int(_fx_cases[_fx_index]["wait"]):
		var c: Dictionary = _fx_cases[_fx_index]
		print("T%d --test-effects: %s (Foto %d Ticks nach dem Auslöser)" % [tick, c["name"], int(c["wait"])])
		if _screenshot_path != "":


			var img := get_viewport().get_texture().get_image()
			var side := 224
			var mid := Vector2i(img.get_width() / 2, img.get_height() / 2)
			var region := Rect2i(mid - Vector2i(side / 2, side / 2), Vector2i(side, side))
			var cut := img.get_region(region)
			cut.resize(side * 3, side * 3, Image.INTERPOLATE_NEAREST)
			var path: String = "%s_%s.png" % [_screenshot_path.get_basename(), c["name"]]
			cut.save_png(path)
			print("Screenshot: ", path)
		_fx_index += 1
		_test_step = 1
		_test_tick = tick


var _test_gap := false
var _gap_cell := Vector2i.ZERO


func _shroud_in_circle(center: Vector2i, cells: int) -> Array:

	var vis: PackedByteArray = world.vis_map()
	var out := [0, 0, 0]
	if vis.size() != world.map_w * world.map_h:
		return out
	for dy in range(-cells, cells + 1):
		for dx in range(-cells, cells + 1):
			if dx * dx + dy * dy > cells * cells:
				continue
			var c := center + Vector2i(dx, dy)
			if c.x < 0 or c.y < 0 or c.x >= world.map_w or c.y >= world.map_h:
				continue
			out[int(vis[c.y * world.map_w + c.x])] += 1
	return out


func _run_test_gap() -> void:
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
		_gap_cell = origin + Vector2i(0, -8)


		for i in 5:
			world.spawn_unit("2tnk", 0, _gap_cell + Vector2i(i * 3 - 6, 5), 0)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(_gap_cell) + Vector2(0.5, 2.5)) * ProtoWorld.CELL)
		print("T%d --test-gap: Beobachter steht, Tarngenerator kommt nach %s" % [tick, _gap_cell])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 40:
		var n := _shroud_in_circle(_gap_cell, 2)
		print("T%d --test-gap: ohne Generator schwarz=%d Nebel=%d sichtbar=%d" % [tick, n[0], n[1], n[2]])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_vorher.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_vorher.png")


		world.call("_add_building", "fact", 1, _gap_cell + Vector2i(14, 0))
		world.call("_add_building", "powr", 1, _gap_cell + Vector2i(-5, 0))
		world.call("_add_building", "gap", 1, _gap_cell)
		world.spawn_unit("e1", 1, _gap_cell + Vector2i(3, 0))
		world.spawn_unit("e1", 1, _gap_cell + Vector2i(-3, 0))
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 40:
		var n := _shroud_in_circle(_gap_cell, 2)
		var hidden := 0
		for u in world.units:
			if u.alive and u.player == 1 and not u.visible:
				hidden += 1
		print("T%d --test-gap: mit Generator schwarz=%d Nebel=%d sichtbar=%d, verborgene Gegner=%d"
				% [tick, n[0], n[1], n[2], hidden])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_gap.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_gap.png")

		for u in world.units:
			if u.alive and u.player == 1 and u.type == "powr":
				sim.destroy(u.id)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 40:
		var n := _shroud_in_circle(_gap_cell, 2)
		print("T%d --test-gap: ohne Strom schwarz=%d Nebel=%d sichtbar=%d" % [tick, n[0], n[1], n[2]])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_gps := false
var _gps_cell := Vector2i.ZERO
var _gps_scout_id := -1
var _gps_killed_id := -1


func _run_test_gps() -> void:
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
		sim.give_credits(0, 30000)


		for i in 4:
			world.call("_add_building", "powr", 0, origin + Vector2i(-7, i * 3))
		world.call("_add_building", "dome", 0, origin + Vector2i(-7, 12))
		world.call("_add_building", "atek", 0, origin + Vector2i(-3, 0))

		var b: Rect2i = world.bounds
		_gps_cell = origin + Vector2i(0, -16)
		_gps_cell.x = clampi(_gps_cell.x, b.position.x + 4, b.end.x - 10)
		_gps_cell.y = clampi(_gps_cell.y, b.position.y + 4, b.end.y - 10)
		world.call("_add_building", "fact", 1, _gps_cell)
		world.call("_add_building", "powr", 1, _gps_cell + Vector2i(5, 0))
		world.call("_add_building", "tent", 1, _gps_cell + Vector2i(0, 4))
		world.call("_add_building", "proc", 1, _gps_cell + Vector2i(5, 4))
		world.spawn_unit("e1", 1, _gps_cell + Vector2i(3, 7))
		world.spawn_unit("2tnk", 1, _gps_cell + Vector2i(8, 7))


		var scout: ProtoWorld.Unit = world.spawn_unit("2tnk", 0, _gps_cell + Vector2i(0, 7), 0)
		_gps_scout_id = scout.id if scout != null else -1
		world.center_on((Vector2(_gps_cell) + Vector2(2.5, 2.5)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 40:

		if _gps_scout_id >= 0:
			sim.destroy(_gps_scout_id)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 30:
		print("T%d --test-gps: vor dem Start eingefroren=%d Punkte=%d gps=%s" % [
			tick, sim.frozen_actors().size() / 6, sim.gps_dots().size() / 4, sim.gps_active()])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_vorher.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_vorher.png")


		var ok := false
		for _i in 14000:
			sim.step()
			if sim.gps_active():
				ok = true
				break
		if not ok:
			print("T --test-gps: Satellit nicht rechtzeitig oben")
			get_tree().quit()
			return
		_test_step = 3
		_test_tick = sim.tick()
	elif _test_step == 3 and tick >= _test_tick + 20:
		var frozen: PackedInt32Array = sim.frozen_actors()
		var dots: PackedInt32Array = sim.gps_dots()
		var buildings := 0
		var units := 0
		var i := 0
		while i + 3 < dots.size():
			if dots[i + 3] != 0: buildings += 1
			else: units += 1
			i += 4
		print("T%d --test-gps: nach dem Start eingefroren=%d Punkte=%d (Gebäude %d, Einheiten %d)" % [
			tick, frozen.size() / 6, dots.size() / 4, buildings, units])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_gps.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_gps.png")


		_gps_killed_id = frozen[0] if frozen.size() >= 6 else -1
		if _gps_killed_id >= 0:
			sim.destroy(_gps_killed_id)
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + 30:
		var frozen: PackedInt32Array = sim.frozen_actors()
		var still := false
		var alive := true
		var i := 0
		while i + 5 < frozen.size():
			if frozen[i] == _gps_killed_id and frozen[i + 5] >= 0:
				still = true
			i += 6
		for u in world.units:
			if u.id == _gps_killed_id:
				alive = u.alive
		print("T%d --test-gps: Gebäude %d zerstört (lebt=%s), Momentaufnahme steht weiter=%s (eingefroren=%d)" % [
			tick, _gps_killed_id, alive, still, frozen.size() / 6])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_nebel := false
var _nebel_scout: ProtoWorld.Unit = null
var _nebel_near: ProtoWorld.Unit = null
var _nebel_far: ProtoWorld.Unit = null
var _nebel_survey: Array = []
var _nebel_home := Vector2i.ZERO
var _nebel_out := Vector2i.ZERO
var _nebel_in := Vector2i.ZERO
var _nebel_fails := 0


func _nebel_level(u) -> int:
	return world.visibility_at(u.pos) if u != null else -1


func _nebel_report(tag: String, u, want_visible: bool) -> void:
	var tick: int = world.sim.tick()
	var cell := Vector2i(u.pos / ProtoWorld.CELL)
	var dist: float = (Vector2(cell) - Vector2(_nebel_home)).length()
	var ok: bool = bool(u.visible) == want_visible
	if not ok:
		_nebel_fails += 1
	print("T%d --test-nebel: %s — Gegner %s, Abstand %.1f Zellen, Sichtstufe %d, visible=%s, gezeichnet=%s (erwartet visible=%s) %s" % [
		tick, tag, cell, dist, _nebel_level(u), u.visible, world.actor_shown(u), want_visible,
		"OK" if ok else "FEHLER"])


func _run_test_nebel() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:


		var origin: Vector2i = world.bounds.get_center()
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		var b: Rect2i = world.bounds
		_nebel_home = origin + Vector2i(0, 10)
		_nebel_home.x = clampi(_nebel_home.x, b.position.x + 15, b.end.x - 16)
		_nebel_home.y = clampi(_nebel_home.y, b.position.y + 3, b.end.y - 4)
		_nebel_in = _nebel_home + Vector2i(2, 0)
		_nebel_out = _nebel_home + Vector2i(12, 0)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)


		_nebel_scout = world.spawn_unit("mcv", 0, _nebel_home, 0)
		_nebel_near = world.spawn_unit("mcv", 1, _nebel_out, 0)


		_nebel_far = world.spawn_unit("mcv", 1, _nebel_home - Vector2i(12, 0), 0)


		_nebel_survey.clear()
		for i in 3:
			var s: ProtoWorld.Unit = world.spawn_unit("mcv", 0, _nebel_home + Vector2i(4 + i * 4, 0), 0)
			if s != null:
				_nebel_survey.append(s)
		world.center_on((Vector2(_nebel_home) + Vector2(3.0, 0.5)) * ProtoWorld.CELL)
		print("T%d --test-nebel: Nebel=%s, Karte erkundet=%s, --reveal=%s, Betrachtermaske=%d, örtlicher Spieler=%d (Sim %d)" % [
			tick, ProtoWorld.next_fog, ProtoWorld.next_explored_map, world.get("_reveal_all"),
			sim.visibility_players(), world.local_player, sim.local_player()])
		print("T%d --test-nebel: Beobachter %s, Gegner startet %s, Ziel %s, %d Vermesser" % [
			tick, _nebel_home, _nebel_out, _nebel_in, _nebel_survey.size()])
		if _nebel_scout == null or _nebel_near == null or _nebel_far == null or _nebel_survey.size() < 3:
			print("T --test-nebel: Aufbau gescheitert (Zelle belegt?) — andere Karte oder anderen Seed nehmen")
			get_tree().quit()
			return
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:

		for s in _nebel_survey:
			sim.destroy(s.id)
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 30:

		_nebel_report("weit weg (erkundet)", _nebel_near, not ProtoWorld.next_fog)
		_nebel_report("Gegenprobe (nie erkundet)", _nebel_far, false)
		var ids := PackedInt32Array([_nebel_near.id])
		sim.order_move(ids, _nebel_in.x, _nebel_in.y)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:

		var near: float = (Vector2(Vector2i(_nebel_near.pos / ProtoWorld.CELL)) - Vector2(_nebel_home)).length()
		if near <= 3.0 or tick >= _test_tick + 400:
			_nebel_report("in Sichtweite gefahren", _nebel_near, true)
			if _screenshot_path != "":
				get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_sichtbar.png")
				print("Screenshot: ", _screenshot_path.get_basename() + "_sichtbar.png")
			var ids := PackedInt32Array([_nebel_near.id])
			sim.order_move(ids, _nebel_out.x, _nebel_out.y)
			_test_step = 4
			_test_tick = tick
	elif _test_step == 4:

		var away: float = (Vector2(Vector2i(_nebel_near.pos / ProtoWorld.CELL)) - Vector2(_nebel_home)).length()
		if away >= 8.0 or tick >= _test_tick + 400:
			_nebel_report("wieder herausgefahren", _nebel_near, not ProtoWorld.next_fog)
			_nebel_report("Gegenprobe (nie erkundet)", _nebel_far, false)
			var sichtbar := 0
			var verborgen := 0
			for u in world.units:
				if u.alive and u.player != world.local_player:
					if u.visible: sichtbar += 1
					else: verborgen += 1
			print("T%d --test-nebel: gegnerische Actors sichtbar=%d verborgen=%d" % [tick, sichtbar, verborgen])
			print("T --test-nebel Ende: %d Fehler (Sollwert 0)" % _nebel_fails)
			if _screenshot_path != "":
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("Screenshot: ", _screenshot_path)
			get_tree().quit()


var _test_jammer := false
var _jammer_wait := 0


func _run_test_jammer() -> void:
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
		sim.give_credits(0, 20000)
		world.call("_add_building", "powr", 0, origin + Vector2i(-6, 0))
		world.call("_add_building", "dome", 0, origin + Vector2i(-6, 4))
		_gap_cell = origin
		world.center_on((Vector2(origin) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_jammer_wait = Time.get_ticks_msec() + 1200
		_test_step = 1
	elif _test_step == 1 and Time.get_ticks_msec() >= _jammer_wait:
		print("T%d --test-jammer: Radar=%s gestört=%s" % [tick, world.has_radar(), world.radar_jammed()])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_radar.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_radar.png")


		world.spawn_unit("mrj", 1, _gap_cell + Vector2i(2, 3), 512)
		world.spawn_unit("mgg", 0, _gap_cell + Vector2i(-2, 3), 512)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(_gap_cell) + Vector2(0.5, 3.5)) * ProtoWorld.CELL)
		_jammer_wait = Time.get_ticks_msec() + 1200
		_test_step = 2
	elif _test_step == 2 and Time.get_ticks_msec() >= _jammer_wait:
		print("T%d --test-jammer: mit Störsender Radar=%s gestört=%s"
				% [tick, world.has_radar(), world.radar_jammed()])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_mech := false
var _mech_ids := []


func _run_test_mech() -> void:
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

		var mine: ProtoWorld.Unit = world.spawn_unit("2tnk", 0, origin + Vector2i(-3, -4), 256)
		var foe: ProtoWorld.Unit = world.spawn_unit("3tnk", 1, origin + Vector2i(3, -4), 768)
		if mine != null:
			_mech_ids.append(mine.id)
		if foe != null:
			_mech_ids.append(foe.id)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(0, -4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 25:
		for id in _mech_ids:
			sim.destroy(id)
		_mech_ids.clear()
	elif _test_step == 2 and tick >= _test_tick + 20:
		var husks := []
		for u in world.units:
			if u.alive and str(u.type).ends_with(".husk"):
				husks.append(u)
		print("T%d --test-mech: %d Wracks" % [tick, husks.size()])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_wrack.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_wrack.png")

		for h in husks:
			var cell := Vector2i(h.pos / ProtoWorld.CELL)
			var m: ProtoWorld.Unit = world.spawn_unit("mech", 0, cell + Vector2i(0, 3))
			if m == null:
				print("  Mechaniker konnte nicht gesetzt werden (Typ vorhanden: %s)" % world.type_ids.has("mech"))
				continue
			world.select_only(m)
			var kind: int = world.enter_kind(h)
			var label: String = world.order_enter(h)
			print("  Mechaniker %d → Wrack %s (Besitzer %d): enter_kind=%d, Befehl=%s"
					% [m.id, h.type, h.player, kind, label])
		world.clear_selection()
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 500:
		var tanks := 0
		var husks := 0
		var line := ""
		for u in world.units:
			if not u.alive:
				continue
			if str(u.type).ends_with(".husk"):
				husks += 1
			elif u.player == 0 and u.type in ["2tnk", "3tnk"]:
				tanks += 1
				line += " %s(%d %%)" % [u.type, int(round(100.0 * u.hp))]
		print("T%d --test-mech: Wracks=%d, eigene Panzer=%d:%s" % [tick, husks, tanks, line])
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_muzzle := false


func _run_test_muzzle() -> void:
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
		var tank: ProtoWorld.Unit = world.spawn_unit("2tnk", 0, origin + Vector2i(-2, -4), 768)
		var foe: ProtoWorld.Unit = world.spawn_unit("e1", 1, origin + Vector2i(2, -4))
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(0, -4)) * ProtoWorld.CELL)
		if tank != null and foe != null:
			world.select_only(tank)
			world.order_attack(foe)
		print("T%d --test-muzzle: Panzer=%s Ziel=%s" % [tick, tank != null, foe != null])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1:
		for u in world.units:
			if not (u.alive and u.type == "2tnk" and u.firing):
				continue
			print("T%d --test-muzzle: Schuss-Sequenz läuft, Mündungsfeuer gezeichnet" % tick)
			if _screenshot_path != "":
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("Screenshot: ", _screenshot_path)
			get_tree().quit()
			return
		if tick > _test_tick + 600:
			print("T%d --test-muzzle: kein Schuss beobachtet" % tick)
			get_tree().quit()


var _test_rotor := false
var _rotor_air: Array = []
var _rotor_pads: Array = []
var _rotor_origin := Vector2i.ZERO
var _rotor_done := false
var _rotor_faced := false

const ROTOR_FACINGS := [0, 256, 512, 768]
const ROTOR_KINDS := ["heli", "hind", "tran"]


func _rotor_report() -> void:
	var sim = world.sim
	var atlas = world.atlas()
	var b: PackedFloat32Array = sim.render_buffer(1.0)
	for kind in ROTOR_KINDS:
		if not world.types.has(kind):
			continue
		var t: Dictionary = world.types[kind]
		var bstem: String = t["body"]
		var blo: int = atlas.frame_index(bstem, 0)
		var bhi: int = blo + int(atlas.sprite_frame_count[bstem])
		var bsize: Vector2i = atlas.sprite_frame_size[bstem]
		var bodies: Array = []
		for i in b.size() / 12:
			var f := int(b[i * 12 + 8])
			if f >= blo and f < bhi and b[i * 12 + 9] >= -0.5:
				bodies.append(Vector2(b[i * 12 + 3] + bsize.x * 0.5, b[i * 12 + 7] + bsize.y * 0.5))
		for rt in t.get("rotors", []):
			var rstem: String = rt["sprite"]
			var rlo: int = atlas.frame_index(rstem, 0)
			var rhi: int = rlo + int(atlas.sprite_frame_count[rstem])
			var rsize: Vector2i = atlas.sprite_frame_size[rstem]
			var deltas: Array = []
			for i in b.size() / 12:
				var f := int(b[i * 12 + 8])
				if f < rlo or f >= rhi:
					continue
				var c := Vector2(b[i * 12 + 3] + rsize.x * 0.5, b[i * 12 + 7] + rsize.y * 0.5)
				var best := Vector2.ZERO
				var best_d := 1.0e9
				for bc in bodies:
					if bc.distance_to(c) < best_d:
						best_d = bc.distance_to(c)
						best = bc
				if best_d < 1.0e9:
					deltas.append("%.1f,%.1f" % [c.x - best.x, c.y - best.y])
			print("T --test-rotor: %s/%s Offset %d,%d,%d → Rotormitte gegen Rumpfmitte %s"
					% [kind, rstem, rt["ox"], rt["oy"], rt["oz"], ", ".join(deltas)])


func _rotor_air_screenshots() -> void:
	for r in ROTOR_KINDS.size():
		world.center_on((Vector2(_rotor_origin) + Vector2(0.5, -4.0 + r * 3.0)) * ProtoWorld.CELL)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
				_screenshot_path.get_basename() + "_luft_" + ROTOR_KINDS[r] + ".png")


func _run_test_rotor() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:


		var origin: Vector2i = world.bounds.position + world.bounds.size / 2 + Vector2i(0, -14)
		_rotor_origin = origin
		for r in ROTOR_KINDS.size():
			for c in ROTOR_FACINGS.size():
				var u: ProtoWorld.Unit = world.spawn_unit(ROTOR_KINDS[r], 0,
						origin + Vector2i(-6 + c * 4, -4 + r * 3), ROTOR_FACINGS[c], 100, true)
				if u != null:
					_rotor_air.append(u)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(0.5, -1.0)) * ProtoWorld.CELL)
		print("T%d --test-rotor: %d Maschinen in der Luft" % [tick, _rotor_air.size()])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:
		_test_step = 2
		_test_tick = tick
		_rotor_report()


		if _screenshot_path != "":
			call_deferred("_rotor_air_screenshots")

		for k in 3:
			_rotor_pads.append(world.call("_add_building", "hpad", 0, _rotor_origin + Vector2i(-6 + k * 4, 8)))
		for k in 2:
			_rotor_pads.append(world.call("_add_building", "afld", 0, _rotor_origin + Vector2i(7 + k * 5, 8)))
		for k in 2:
			var u: ProtoWorld.Unit = world.spawn_unit(["mig", "yak"][k], 0,
					_rotor_origin + Vector2i(8 + k * 5, 5), 512, 100, true)
			if u != null:
				_rotor_air.append(u)
	elif _test_step == 2 and tick >= _test_tick + 20:

		var pad_of := {"heli": 0, "hind": 1, "tran": 2, "mig": 3, "yak": 4}
		for u in _rotor_air:
			if not u.alive or not pad_of.has(u.type):
				continue
			var pad = _rotor_pads[pad_of[u.type]]
			world.select_only(u)
			if not world.order_land_at(pad):
				print("T%d --test-rotor: %s kann auf %s nicht landen" % [tick, u.type, pad.type])
			pad_of.erase(u.type)
		world.clear_selection()
		_test_step = 3
		_test_tick = tick
	elif _rotor_done and not _rotor_faced and tick >= _test_tick + 20:


		_rotor_faced = true
		var pad_for := {"heli": 0, "hind": 1, "tran": 2, "mig": 3, "yak": 4}
		var seen := {}
		for u in _rotor_air:
			if not u.alive or u.altitude > 0.0 or not pad_for.has(u.type) or seen.has(u.type):
				continue
			seen[u.type] = true
			var pad = _rotor_pads[pad_for[u.type]]
			var want: int = int(world.types.get(pad.type, {}).get("exit_facing", 0))
			print("T%d --test-rotor: %s auf %s Richtung %d (Sollwert %d)%s"
					% [tick, u.type, pad.type, u.facing, want,
					   "" if u.facing == want else "  FEHLER"])
		get_tree().quit()
	elif _test_step == 3 and not _rotor_done:
		var landed := 0
		for u in _rotor_air:
			if u.alive and u.altitude <= 0.0:
				landed += 1
		if landed < 5 and tick < _test_tick + 1200:
			return
		print("T%d --test-rotor: %d von 5 Maschinen aufgesetzt" % [tick, landed])
		_rotor_done = true
		_test_tick = tick
		if _screenshot_path != "":
			world.center_on((Vector2(_rotor_origin) + Vector2(-2.0, 9.5)) * ProtoWorld.CELL)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_pad.png")
			world.center_on((Vector2(_rotor_origin) + Vector2(11.0, 9.5)) * ProtoWorld.CELL)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_afld.png")
			print("Screenshot: ", _screenshot_path.get_basename() + "_luft_*/_pad/_afld.png")


var _test_turret := false
var _turret_origin := Vector2i.ZERO
var _turret_kinds: Array = []

const TURRET_FACINGS := [0, 256, 512, 768]
const TURRET_SHIPS := ["ca", "dd", "pt"]
const TURRET_LAND := ["1tnk", "2tnk", "jeep"]
const TURRET_TOLERANCE := 1.5


func _turret_expected_px(facing: int, ox: int, oy: int, oz: int) -> Vector2:
	var a: float = float(facing) / 1024.0 * TAU
	var fwd := Vector2(-sin(a), -cos(a))
	var right := Vector2(cos(a), -sin(a))
	var wx: float = fwd.x * float(ox) + right.x * float(oy)
	var wy: float = (fwd.y * float(ox) + right.y * float(oy)) * 654.0 / 1024.0
	return Vector2(wx, wy - float(oz)) * (float(ProtoWorld.CELL) / 1024.0)


func _turret_centers(buf: PackedFloat32Array, lo: int, hi: int, size: Vector2) -> Array:
	var out: Array = []
	for i in buf.size() / 12:
		var f := int(buf[i * 12 + 8])
		if f < lo or f >= hi or buf[i * 12 + 9] < -0.5:
			continue
		out.append(Vector2(buf[i * 12 + 3], buf[i * 12 + 7]) + size * 0.5)
	return out


func _turret_measure(kinds: Array) -> bool:
	var atlas = world.atlas()
	var buf: PackedFloat32Array = world.sim.render_buffer(1.0)
	var ok := true
	for kind in kinds:
		var t: Dictionary = world.types.get(kind, {})
		if t.is_empty() or int(t.get("turret_first", -1)) < 0:
			print("T --test-turret: %s hat keinen Turm" % kind)
			continue
		var body: String = str(t["body"])
		var bsize := Vector2(atlas.sprite_frame_size[body])
		var blo: int = atlas.frame_index(body, 0)
		var bodies := _turret_centers(buf, blo, blo + int(t.get("facings", 32)), bsize)
		var tsize := Vector2(float(t.get("turret_w", 24)), float(t.get("turret_h", 24)))
		var tlo: int = int(t["turret_first"])
		var turrets := _turret_centers(buf, tlo, tlo + int(t.get("turret_facings", 32)), tsize)

		var seq := Vector2(float(t.get("turret_off_x", 0)) - float(t.get("offset_x", 0)),
				float(t.get("turret_off_y", 0)) - float(t.get("offset_y", 0)))
		var offsets: Array = t.get("turret_offsets", [[0, 0, 0]])
		for u in world.units:
			if not u.alive or u.type != kind:
				continue
			var b := _turret_nearest(bodies, u.pos)
			if b.x > 1.0e8:
				continue


			for k in offsets.size():
				var o: Array = offsets[k]
				var want: Vector2 = _turret_expected_px(u.facing, int(o[0]), int(o[1]), int(o[2])) + seq
				var got := _turret_nearest(turrets, b + want)
				if got.x > 1.0e8:
					continue
				var d := got - b - want
				var pass_ := d.length() <= TURRET_TOLERANCE
				ok = ok and pass_
				print("T --test-turret: %-5s Facing %3d Turm %d Offset %5d,%4d,%4d → Soll %6.1f,%6.1f  Ist %6.1f,%6.1f  Abweichung %4.1f px %s" % [
						kind, u.facing, k, int(o[0]), int(o[1]), int(o[2]),
						want.x, want.y, got.x - b.x, got.y - b.y, d.length(),
						"OK" if pass_ else "FEHLER"])
	print("T --test-turret: %s" % ("alle Türme sitzen richtig" if ok else "FEHLER — Turmsitz weicht ab"))
	return ok


func _turret_nearest(points: Array, to: Vector2) -> Vector2:
	var best := Vector2(1.0e9, 1.0e9)
	var best_d := 1.0e18
	for c in points:
		var d: float = (c - to).length_squared()
		if d < best_d:
			best_d = d
			best = c
	return best


func _turret_open_water(rx: int, ry: int) -> Vector2i:
	var b := world.bounds
	var mid := Vector2(b.get_center())
	var best := Vector2i(-1, -1)
	var best_d := 1.0e18
	for y in range(b.position.y + ry + 1, b.end.y - ry - 1):
		for x in range(b.position.x + rx + 1, b.end.x - rx - 1):
			var c := Vector2i(x, y)
			var d: float = (Vector2(c) - mid).length_squared()
			if d >= best_d:
				continue
			var all_water := true
			for dy in range(-ry, ry + 1):
				for dx in range(-rx, rx + 1):
					if world.terrain_type(c + Vector2i(dx, dy)) != ProtoWorld.TER_WATER:
						all_water = false
						break
				if not all_water:
					break
			if all_water:
				best = c
				best_d = d
	return best


func _turret_screenshots() -> void:
	for r in _turret_kinds.size():
		world.center_on((Vector2(_turret_origin) + Vector2(0.5, -4.0 + r * 4.0)) * ProtoWorld.CELL)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
				_screenshot_path.get_basename() + "_" + str(_turret_kinds[r]) + ".png")
	print("Screenshot: ", _screenshot_path.get_basename() + "_<Bauart>.png")
	get_tree().quit()


func _run_test_turret() -> void:
	var tick: int = world.sim.tick()
	if _test_step == 0 and tick >= 10:
		var water := _turret_open_water(7, 6)
		_turret_kinds = TURRET_LAND.duplicate()
		_turret_origin = world.bounds.position + world.bounds.size / 2
		if water.x >= 0:
			_turret_kinds = TURRET_SHIPS.duplicate()
			_turret_origin = water
			print("T%d --test-turret: offenes Wasser bei %s" % [tick, water])
		else:
			print("T%d --test-turret: kein offenes Wasser — nur Landeinheiten (Karte mit See wählen)" % tick)
		for r in _turret_kinds.size():
			for c in TURRET_FACINGS.size():
				world.spawn_unit(str(_turret_kinds[r]), 0,
						_turret_origin + Vector2i(-6 + c * 4, -4 + r * 4), TURRET_FACINGS[c], 100, false)
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(_turret_origin) + Vector2(0.5, -1.0)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:
		_test_step = 2
		_turret_measure(_turret_kinds)
		if _screenshot_path != "":
			call_deferred("_turret_screenshots")
		else:
			get_tree().quit()


var _test_make := false
var _make_kinds: Array = []
var _make_units: Array = []
var _make_findings := 0

const MAKE_SPACING := 5
const MAKE_COLUMNS := 9


func _make_instances(buf: PackedFloat32Array, lo: int, hi: int, size: Vector2, near: Vector2,
		radius: float) -> Array:
	var out: Array = []
	for i in buf.size() / 12:
		var f := int(buf[i * 12 + 8])
		if f < lo or f >= hi or buf[i * 12 + 9] < -0.5:
			continue
		var tl := Vector2(buf[i * 12 + 3], buf[i * 12 + 7])
		if (tl + size * 0.5).distance_to(near) <= radius:
			out.append(tl)
	return out


func _make_measure(building: bool) -> void:
	var atlas = world.atlas()
	var buf: PackedFloat32Array = world.sim.render_buffer(1.0)
	var phase := "Bauphase " if building else "fertig   "
	for u in _make_units:
		if not u.alive:
			continue
		var t: Dictionary = world.types[u.type]
		var body: String = str(t["body"])
		var mk: String = str(t.get("make", ""))

		var stem: String = mk if building else body
		var size := Vector2(atlas.sprite_frame_size[stem])
		var off := Vector2(float(t.get("make_off_x", 0)), float(t.get("make_off_y", 0))) if building \
				else Vector2(float(t.get("offset_x", 0)), float(t.get("offset_y", 0)))
		var lo: int = atlas.frame_index(stem, 0)
		var hi: int = lo + int(atlas.sprite_frame_count[stem])
		var want: Vector2 = u.pos - size * 0.5 + off
		var found := _make_instances(buf, lo, hi, size, u.pos, 90.0)
		var line := "%s%-6s %-9s" % [phase, u.type, stem]
		if found.is_empty():
			print("T --test-make: %s KEIN Körpersprite gefunden (Soll %.1f,%.1f) FEHLER" % [line, want.x, want.y])
			_make_findings += 1
		else:
			var best: Vector2 = found[0]
			for c in found:
				if c.distance_to(want) < best.distance_to(want):
					best = c
			var d: Vector2 = best - want
			var ok := d.length() < 0.5
			if not ok:
				_make_findings += 1
			print("T --test-make: %s Soll %7.1f,%7.1f  Ist %7.1f,%7.1f  Abweichung %5.1f px %s" % [
					line, want.x, want.y, best.x, best.y, d.length(), "OK" if ok else "FEHLER"])

		if int(t.get("turret_first", -1)) >= 0:
			var tsize := Vector2(float(t.get("turret_w", 24)), float(t.get("turret_h", 24)))
			var tlo: int = int(t["turret_first"])
			var thi: int = tlo + int(t.get("turret_facings", 32))
			var turrets := _make_instances(buf, tlo, thi, tsize, u.pos, 90.0)
			var want_n := 0 if building else 1
			var ok2: bool = turrets.size() == want_n
			if not ok2:
				_make_findings += 1
			print("T --test-make: %s%-6s Turm: %d gezeichnet (Soll %d) %s" % [
					phase, u.type, turrets.size(), want_n, "OK" if ok2 else "FEHLER"])


func _run_test_make() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		sim.give_credits(0, 200000)
		_make_kinds = []
		for name in world.types:
			if world.types[name].has("make") and world.type_ids.has(name):
				_make_kinds.append(name)
		_make_kinds.sort()
		var origin: Vector2i = world.bounds.position + Vector2i(3, 3)
		var i := 0
		var missing: Array = []
		for name in _make_kinds:
			var cell: Vector2i = origin + Vector2i((i % MAKE_COLUMNS) * MAKE_SPACING,
					(i / MAKE_COLUMNS) * MAKE_SPACING)
			var u = world.call("_add_building", name, 0, cell)
			if u != null and u.id >= 0:
				_make_units.append(u)
			else:
				missing.append(name)
			i += 1
		print("T%d --test-make: %d von %d Gebäuden mit eigener make-Datei gesetzt%s" % [
				tick, _make_units.size(), _make_kinds.size(),
				("" if missing.is_empty() else " (kein Platz: " + ", ".join(missing) + ")")])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:

		_make_measure(false)
		var sold := 0
		for u in _make_units:
			if u.alive and sim.sell(u.id):
				sold += 1
		print("T%d --test-make: %d von %d Gebäuden in den Verkauf geschickt (Bauanimation rückwärts)"
				% [tick, sold, _make_units.size()])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 6:

		_make_measure(true)
		print("T --test-make: %d Befund(e) (Sollwert 0)" % _make_findings)
		get_tree().quit()


func _run_test_barrels_mission() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 60:
		var best: ProtoWorld.Unit = null
		var best_score := -1
		for u in world.units:
			if not u.alive or u.type not in ["barl", "brl3"]:
				continue
			var score := 0
			for v in world.units:
				if v == u or not v.alive:
					continue
				if (v.pos - u.pos).length() <= 2.5 * ProtoWorld.CELL:
					score += 1
			if score > best_score:
				best_score = score
				best = u
		if best == null:
			print("T: --test-barrels --mission %s: kein Fass auf der Karte" % ProtoWorld.next_mission)
			get_tree().quit()
			return
		_barrel_target = best
		_barrel_shooter = null
		_barrel_neighbours = []
		for v in world.units:
			if v == best or not v.alive:
				continue
			if (v.pos - best.pos).length() <= 2.5 * ProtoWorld.CELL:
				_barrel_neighbours.append({"unit": v, "hp": v.hp, "type": v.type, "player": v.player})


		var origin := Vector2i(best.pos / ProtoWorld.CELL)
		var shooter: ProtoWorld.Unit = null
		for d in [Vector2i(0, 5), Vector2i(0, -5), Vector2i(5, 0), Vector2i(-5, 0),
				Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4),
				Vector2i(0, 6), Vector2i(6, 0), Vector2i(0, -6), Vector2i(-6, 0)]:
			shooter = world.spawn_unit("e1", 0, origin + d)
			if shooter != null:
				break
		_barrel_shooter = shooter
		print("T: Fass %s (Besitzer %d) bei %s, Nachbarn %d, Schütze %s" % [
			best.type, best.player, str(origin), _barrel_neighbours.size(), shooter != null])
		world.center_on(best.pos)
		if shooter != null:
			world.select_only(shooter)
			world.order_attack(_barrel_target)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and _screenshot_path != "" and not _barrel_shot_done \
			and not _barrel_target.alive and _barrel_shot_at < 0:
		_barrel_shot_at = tick + 8
	elif _test_step == 1 and not _barrel_shot_done and _barrel_shot_at > 0 and tick >= _barrel_shot_at:
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("Screenshot: ", _screenshot_path)
		_barrel_shot_done = true
	elif _test_step == 1 and tick >= _test_tick + 900:
		var dead := 0
		var hurt := 0
		var lines: Array = []
		for e in _barrel_neighbours:
			var v: ProtoWorld.Unit = e["unit"]
			if not v.alive:
				dead += 1
				lines.append("%s(P%d) tot" % [e["type"], e["player"]])
			elif v.hp < float(e["hp"]) - 0.001:
				hurt += 1
				lines.append("%s(P%d) %.0f%%→%.0f%%" % [e["type"], e["player"],
					float(e["hp"]) * 100.0, v.hp * 100.0])
		print("T: --test-barrels --mission %s: Fass zerstört=%s (Schütze lebt=%s), Nachbarn tot=%d beschädigt=%d von %d [%s]" % [
			ProtoWorld.next_mission, str(not _barrel_target.alive),
			str(_barrel_shooter != null and _barrel_shooter.alive), dead, hurt,
			_barrel_neighbours.size(), ", ".join(PackedStringArray(lines))])
		_test_step = 2
		get_tree().quit()


var _test_autotarget := false
var _autotarget_hero: ProtoWorld.Unit = null
var _autotarget_foe: ProtoWorld.Unit = null


func _run_test_autotarget() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 25:
		for u in world.units:
			if u.alive and u.player == 0 and u.type.begins_with("e7"):
				_autotarget_hero = u
				break
		if _autotarget_hero == null and ProtoWorld.next_mission == "":
			var origin := Vector2i(20, 20)
			for u in world.units:
				if u.alive and u.player == 0:
					origin = Vector2i(u.pos / ProtoWorld.CELL)
					break
			_autotarget_hero = world.spawn_unit("e7", 0, origin + Vector2i(0, -3))
		if _autotarget_hero == null:
			if tick < 2000:
				return
			print("T: --test-autotarget: keine Tanya gefunden")
			get_tree().quit()
			return


		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		var cell := Vector2i(_autotarget_hero.pos / ProtoWorld.CELL)
		for d in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, 2)]:
			_autotarget_foe = world.spawn_unit("e1", 1, cell + d)
			if _autotarget_foe != null:
				break
		world.center_on(_autotarget_hero.pos)
		print("T: --test-autotarget: Held %s Stance %d, Gegner gesetzt %s" % [
			_autotarget_hero.type, sim.stance(_autotarget_hero.id), _autotarget_foe != null])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 120:


		var hurt := _autotarget_foe != null and (not _autotarget_foe.alive or _autotarget_foe.hp < 0.999)
		var by_hero: bool = hurt and world.sim.last_attacker(_autotarget_foe.id) == _autotarget_hero.id
		print("T: --test-autotarget: %s feuert von allein=%s (Gegner beschädigt=%s, Schütze-ID %d von %d)" % [
			_autotarget_hero.type, str(by_hero), str(hurt),
			world.sim.last_attacker(_autotarget_foe.id) if _autotarget_foe != null else -1,
			_autotarget_hero.id])
		_test_step = 2
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
var _air_bar_shot := false

var _test_air_player := false
var _ap_step := 0
var _ap_tick := 0
var _ap_heli = null
var _ap_pad = null
var _ap_foe = null
var _ap_shots := 0
var _ap_ammo0 := -1
var _ap_landed_again := false
var _ap_tank = null
var _ap_tank_hp := 1.0
var _ap_shot_taken := false
var _ap_shot_done := false
var _ap_extra = null
var _ap_extra_tank = null
var _ap_extra_hp := 1.0


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


		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)

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


		if not _ap_shot_taken or _ap_shot_done:
			world.center_on(_ap_heli.pos)
		if _ap_heli.ammo < _ap_ammo0:
			_ap_shots = _ap_ammo0 - _ap_heli.ammo

			if _screenshot_path != "" and not _ap_shot_taken and _ap_shots >= 2:
				_ap_shot_taken = true
				if world.zoom < ProtoWorld.MAX_ZOOM:
					world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
				world.center_on(_ap_foe.pos)
				call_deferred("_ap_attack_screenshot")
		if tick == _ap_tick + 300 or tick == _ap_tick + 900:
			print("T: bei +%d: %s Ziel-HP %.2f" % [tick - _ap_tick, _ap_state(_ap_heli), _ap_foe.hp])

		if (_ap_heli.ammo_max > 0 and _ap_heli.ammo <= 0) or tick >= _ap_tick + 3000:
			print("T: Angriff: %d Schuss, Ziel-HP %.2f, %s" % [_ap_shots, _ap_foe.hp, _ap_state(_ap_heli)])
			if _ap_shots == 0:
				print("T: FEHLER kein Schuss abgegeben")
			elif _ap_foe.hp >= 1.0:
				print("T: FEHLER Schüsse ohne Wirkung am Ziel")
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
	elif _ap_step == 7 and tick >= _ap_tick + 30:


		for d in [Vector2i(14, 10), Vector2i(12, 8), Vector2i(16, 12), Vector2i(10, 6)]:
			_ap_tank = world.spawn_unit("2tnk", 1, _test_origin + d)
			if _ap_tank != null:
				break
		if _ap_tank == null:
			print("T: FEHLER kein Panzer als Ziel gesetzt")
			_ap_step = 9
			_ap_tick = tick
			return
		_ap_tank_hp = _ap_tank.hp
		_ap_ammo0 = _ap_heli.ammo
		_ap_tap_unit(_ap_heli)
		_ap_tap_unit(_ap_tank)
		print("T: Tipp auf %s → %s" % [_ap_tank.type, _ap_state(_ap_heli)])
		_ap_step = 8
		_ap_tick = tick
	elif _ap_step == 8:
		world.center_on(_ap_heli.pos)
		if not _ap_tank.alive or _ap_tank.hp < _ap_tank_hp or tick >= _ap_tick + 1500:
			var shots2: int = _ap_ammo0 - _ap_heli.ammo
			print("T: Panzerangriff: %d Schuss, Ziel-HP %.2f (vorher %.2f), %s" % [
					shots2, 0.0 if not _ap_tank.alive else _ap_tank.hp, _ap_tank_hp, _ap_state(_ap_heli)])
			if shots2 == 0:
				print("T: FEHLER kein Schuss auf den Panzer")
			elif _ap_tank.alive and _ap_tank.hp >= _ap_tank_hp:
				print("T: FEHLER Panzer unbeschädigt")
			_ap_step = 9
			_ap_tick = tick
	elif _ap_step == 9:

		if not _ap_heli.selected:
			world.select_units([_ap_heli])
		world.order_move((Vector2(_test_origin) + Vector2(3, 14)) * ProtoWorld.CELL)
		_ap_step = 10
		_ap_tick = tick
	elif _ap_step == 10 and tick >= _ap_tick + 400:
		print("T: nach dem Bewegen: ", _ap_state(_ap_heli))
		if _ap_pad != null:
			_ap_tap_unit(_ap_heli)
			_ap_tap_unit(_ap_pad)
			var sel2: Array = []
			for u in world.selection:
				sel2.append(u.type)
			print("T: Tipp auf ", _ap_pad.type, " → Auswahl ", sel2)
		_ap_step = 11
		_ap_tick = tick
	elif _ap_step == 11 and tick >= _ap_tick + 600:
		print("T: nach dem Landebefehl: ", _ap_state(_ap_heli))


		var extra_type := "hind" if soviet else "mig"
		if world.type_ids.has(extra_type):
			_ap_extra = world.spawn_unit(extra_type, 0, _test_origin + Vector2i(0, -8), 0, 100, true)
		for d in [Vector2i(16, 14), Vector2i(18, 12), Vector2i(14, 16), Vector2i(12, 14)]:
			_ap_extra_tank = world.spawn_unit("2tnk", 1, _test_origin + d)
			if _ap_extra_tank != null:
				break
		if _ap_extra == null or _ap_extra_tank == null:
			print("T: kein zweiter Flieger (%s) oder kein Ziel — übersprungen" % extra_type)
			_ap_step = 14
			_ap_tick = tick
			return
		_ap_step = 12
		_ap_tick = tick
	elif _ap_step == 12 and tick >= _ap_tick + 30:


		_ap_extra_hp = _ap_extra_tank.hp
		_ap_ammo0 = _ap_extra.ammo
		_ap_tap_unit(_ap_extra)
		_ap_tap_unit(_ap_extra_tank)
		print("T: zweiter Flieger %s: Tipp auf %s → %s" % [
				_ap_extra.type, _ap_extra_tank.type, _ap_state(_ap_extra)])
		_ap_step = 13
		_ap_tick = tick
	elif _ap_step == 13:
		world.center_on(_ap_extra.pos)
		if not _ap_extra_tank.alive or _ap_extra_tank.hp < _ap_extra_hp or tick >= _ap_tick + 1500:
			var shots3: int = _ap_ammo0 - _ap_extra.ammo
			print("T: %s gegen Panzer: %d Schuss, Ziel-HP %.2f (vorher %.2f), %s" % [
					_ap_extra.type, shots3, 0.0 if not _ap_extra_tank.alive else _ap_extra_tank.hp,
					_ap_extra_hp, _ap_state(_ap_extra)])
			if shots3 <= 0:
				print("T: FEHLER %s hat nicht gefeuert" % _ap_extra.type)
			elif _ap_extra_tank.alive and _ap_extra_tank.hp >= _ap_extra_hp:
				print("T: FEHLER Panzer von %s unbeschädigt" % _ap_extra.type)
			_ap_step = 14
			_ap_tick = tick
	elif _ap_step == 14:
		print("T: air-player fertig")
		get_tree().quit()


func _ap_attack_screenshot() -> void:
	world.center_on(_ap_foe.pos)
	await get_tree().process_frame
	await get_tree().process_frame
	var path: String = _screenshot_path.get_basename() + "_angriff.png"
	get_viewport().get_texture().get_image().save_png(path)
	_ap_shot_done = true
	print("T: --test-air-player: Angriff, Screenshot %s" % path)


var _test_crash := false
var _crash_units: Array = []
var _crash_victim = null
var _crash_victim_hp := 1.0
var _crash_log: Array = []
var _crash_logged := -1
var _crash_shots := 0


func _run_test_crash() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	var soviet := world.player_faction() == "soviet"
	var plane := "mig" if soviet else "yak"
	var chopper := "hind" if soviet else "heli"
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		_crash_units.clear()
		for i in 2:
			var tn: String = plane if i == 0 else chopper
			if not world.type_ids.has(tn):
				print("T: kein Typ ", tn)
				continue
			var cell := origin + Vector2i(-4 if i == 0 else 4, -6)
			var u = world.spawn_unit(tn, 0, cell, 0, 100, true)
			if u != null:
				_crash_units.append(u)

		_crash_victim = world.spawn_unit("2tnk", 1, origin + Vector2i(4, -6))
		if _crash_victim != null:
			_crash_victim_hp = _crash_victim.hp
		if world.zoom < ProtoWorld.MAX_ZOOM:
			world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on((Vector2(origin) + Vector2(0, -6)) * ProtoWorld.CELL)
		print("T%d --test-crash: %d Maschinen in der Luft (%s, %s)" % [tick, _crash_units.size(), plane, chopper])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:
		for u in _crash_units:
			print("T: %s Höhe=%.0f vor dem Abschuss" % [u.type, u.altitude])
			sim.destroy(u.id)
		_crash_log.clear()
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:

		for u in _crash_units:
			if u.alive:
				world.center_on(u.pos)
				break
		var dt := tick - _test_tick
		if dt <= 40 and dt % 5 == 0 and dt != _crash_logged:
			_crash_logged = dt
			var line := []
			for u in _crash_units:
				line.append("%s alive=%s Höhe=%.0f Richtung=%d" % [u.type, u.alive, u.altitude, u.facing])
			_crash_log.append("T%d %s" % [tick, ", ".join(line)])


		var falling := 0
		for u in _crash_units:
			if u.alive:
				falling += 1
		var want := -1
		if _crash_shots == 0 and dt >= 2:
			want = 0
		elif _crash_shots == 1 and dt >= 12:
			want = 1
		elif _crash_shots == 2 and falling == 0:
			want = 2
		if _screenshot_path != "" and want >= 0:
			_crash_shots += 1
			await get_tree().process_frame
			var suffix: String = ["_trudeln.png", "_fallen.png", "_aufschlag.png"][want]
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + suffix)
		elif want >= 0:
			_crash_shots += 1
		if dt < 60:
			return
		for l in _crash_log:
			print("T: ", l)
		var husks := 0
		for u in _crash_units:
			if str(u.type).ends_with(".husk"):
				husks += 1
		var gone := 0
		for u in _crash_units:
			if not u.alive:
				gone += 1

		var smudges: int = sim.smudges().size() / 5 if sim.has_method("smudges") else -1
		var vhp: float = _crash_victim.hp if _crash_victim != null else 1.0
		print("T: Absturz — %d/%d wurden zum Luftwrack, %d/%d am Boden zerschellt, %d Flecken, Panzer %.2f → %.2f" %
			[husks, _crash_units.size(), gone, _crash_units.size(), smudges, _crash_victim_hp, vhp])
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + 30:
		if _screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


func _air_bar_screenshot(heli_type: String) -> void:
	build_bar.select_queue(4)
	build_bar.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	for s in build_bar._slots:
		if s.visible and s.type_id == world.type_ids.get(heli_type, -1):
			print("T: Cameo ", heli_type, " verfügbar=", s.available)
			build_bar._on_tap(s)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_leiste.png")


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


		var pad2 = world.call("_add_building", chain[-1], 0, origin + Vector2i(-6, 9))
		world.center_on((Vector2(origin) + Vector2(0, 5)) * ProtoWorld.CELL)
		print("T: Flugfeld ", chain[-1], " ×2 (zweites ", "ok" if pad2 != null and pad2.id >= 0 else "FEHLT",
				"), Flugzeug ", heli_type)
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

		var spots := []
		for u in _air_ids:
			spots.append(Vector2i(u.pos / ProtoWorld.CELL))
		var pads_ok: bool = spots.size() < 2 or spots[0] != spots[1]
		var third: bool = world.type_ids.has(heli_type) and \
				not Array(world.sim.buildable(0, 4)).has(world.type_ids[heli_type])
		print("T: Landeplätze ", spots, " getrennt=", pads_ok, ", dritter Flieger gesperrt=", third)


		if _screenshot_path != "" and not _air_bar_shot:
			_air_bar_shot = true
			call_deferred("_air_bar_screenshot", heli_type)

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


		var tran_base := _para_lz if _para_lz.x >= 0 else _test_origin
		_tran_heli = world.spawn_unit("tran", 0, tran_base + Vector2i(0, -6), 256, 100, true)
		if _tran_heli != null:
			for i in 3:
				var e = world.spawn_unit("e1", 0, tran_base + Vector2i(-2 + i, -4))
				if e != null:
					_tran_troop.append(e)
			world.center_on(_tran_heli.pos)
			world.select_units(_tran_troop)
			print("T: Chinook Höhe ", world.sim.air_altitude(_tran_heli.id),
				" — Einsteigen befohlen: ", world.order_enter_transport(_tran_heli))
		else:
			print("T: kein tran-Typ verfügbar — Transporthubschrauber übersprungen")
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5:
		if _tran_heli == null:
			_test_step = 8
			_test_tick = tick
			return
		world.center_on(_tran_heli.pos)
		if world.sim.cargo_weight(_tran_heli.id) < _tran_troop.size() and tick < _test_tick + 1200:
			return
		print("T: Chinook an Bord ", world.sim.cargo_weight(_tran_heli.id), "/", _tran_troop.size(),
			" Höhe ", world.sim.air_altitude(_tran_heli.id))
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_tran.png")
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 150:

		print("T: Chinook nach dem Beladen Höhe ", world.sim.air_altitude(_tran_heli.id), " (erwartet > 0)")
		world.select_only(_tran_heli)


		var base := _para_lz if _para_lz.x >= 0 else _test_origin
		var drop := base + _toward_map_center(base) * 4
		print("T: Chinook bei ", Vector2i(_tran_heli.pos / ProtoWorld.CELL), " → Absetzpunkt ", drop,
			" Terrain ", world.terrain_type(drop))
		world.order_move((Vector2(drop) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 7
		_test_tick = tick
	elif _test_step == 7 and tick >= _test_tick + 300:
		world.center_on(_tran_heli.pos)
		world.select_only(_tran_heli)


		if not world.sim.can_unload(_tran_heli.id) and _tran_tries < 6:
			_tran_tries += 1
			var here := Vector2i(_tran_heli.pos / ProtoWorld.CELL)
			var c := here + _toward_map_center(here) * 3
			print("T: Chinook kann hier nicht entladen (Versuch ", _tran_tries, ", Terrain ",
				world.terrain_type(here), ") — weiter nach ", c)
			world.order_move((Vector2(c) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
			_test_tick = tick - 150
			return
		print("T: Chinook Entladen befohlen: ", world.unload_selected(),
			" Höhe ", world.sim.air_altitude(_tran_heli.id), " nach ", _tran_tries, " Ausweichzügen")
		_test_step = 8
		_test_tick = tick
	elif _test_step == 8 and tick >= _test_tick + 500:
		var tran_out := 0
		for u in _tran_troop:
			if u.alive and world.sim.transport_of(u.id) < 0 and u.altitude <= 0.0:
				tran_out += 1
		print("T: Chinook abgesetzt ", tran_out, " von ", _tran_troop.size(),
			", an Bord ", (world.sim.cargo_weight(_tran_heli.id) if _tran_heli != null else 0),
			", Höhe nach dem Entladen ", (world.sim.air_altitude(_tran_heli.id) if _tran_heli != null else 0),
			" (erwartet > 0 — UnloadCargo.takeOffAfterUnload)")
		print("T: air fertig")
		_test_step = 9
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)
		get_tree().quit()


var _test_naval := false
var _naval_repair = null
var _naval_repair_hp := 1.0
var _naval_ca = null
var _naval_tank = null
var _naval_tank_hp := 1.0
var _naval_victim = null
var _test_msub := false
var _msub_yard = null
var _msub_boat = null
var _msub_victim = null
var _msub_victim_hp := 1.0
var _naval_yard = null
var _naval_ships: Array = []
var _naval_sub = null
var _naval_seen := false
var _test_lst := false
var _lst_yard = null
var _lst_boat = null
var _lst_troop: Array = []

var _lst_ramp_seq: Array = []


func _ramp_name(sim, id: int) -> String:
	if not sim.has_method("ramp_state"):
		return "unbekannt"
	return ["zu", "faehrt auf", "offen", "faehrt zu"][clampi(sim.ramp_state(id), 0, 3)]


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
		if _screenshot_path != "":
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path)
			print("Screenshot: ", _screenshot_path)


		_naval_repair = null
		for u in _naval_ships:
			if u.alive:
				_naval_repair = u
				break
		if _naval_repair != null and _naval_yard != null:
			sim.set_health(_naval_repair.id, int(world.types[_naval_repair.type]["hp"] * 0.3))
			_naval_repair_hp = _naval_repair.hp
			world.select_units([_naval_repair])
			var ok: bool = world.order_repair(_naval_yard)
			print("T: Reparaturbefehl an der Werft: ", ok, " HP vorher %.2f" % _naval_repair_hp)
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4:
		if tick < _test_tick + 1500 and _naval_repair != null and _naval_repair.alive \
				and _naval_repair.hp < 0.999:
			return
		if _naval_repair != null:
			print("T: Werft-Reparatur: HP %.2f → %.2f" % [_naval_repair_hp, _naval_repair.hp])

		var land := _find_land_site("2tnk", _test_origin, 12)
		if land.x >= 0 and world.type_ids.has("2tnk"):
			_naval_tank = world.spawn_unit("2tnk", 0, land)
			if _naval_tank != null and _naval_yard != null:
				sim.set_health(_naval_tank.id, int(world.types["2tnk"]["hp"] * 0.4))
				_naval_tank_hp = 0.4
				world.select_units([_naval_tank])
				world.order_repair(_naval_yard)
				print("T: Panzer (RepairActors: fix) an der Werft angemeldet, HP %.2f" % _naval_tank_hp)


		var victim := _find_land_site("silo", _test_origin, 14)
		if victim.x >= 0 and world.type_ids.has("ca"):
			_naval_victim = world.call("_add_building", "silo", 1, victim)
			var spot := _find_water_cell(victim, 5, 40)
			if spot.x >= 0 and _naval_victim != null:
				_naval_ca = world.spawn_unit("ca", 0, spot)
				if _naval_ca != null:
					world.select_units([_naval_ca])
					world.order_attack(_naval_victim)
					world.center_on(_naval_ca.pos)
					print("T: Kreuzer bei ", spot, " beschießt Silo bei ", victim,
						" Abstand %d Zellen" % (spot - victim).length())
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5:
		if tick < _test_tick + 1200:
			return
		if _naval_victim != null:
			print("T: Kreuzer-Beschuss: Silo HP %.2f (lebt: %s)" % [
				_naval_victim.hp, str(_naval_victim.alive)])
		if _naval_tank != null:
			print("T: Panzer an der Werft: HP %.2f → %.2f (%s)" % [_naval_tank_hp, _naval_tank.hp,
				"korrekt abgewiesen" if _naval_tank.hp < 0.999 else "FEHLER: wurde repariert"])
		_test_step = 6
		if _screenshot_path != "":
			await get_tree().process_frame
			var ca_path: String = _screenshot_path.get_basename() + "_kreuzer.png"
			get_viewport().get_texture().get_image().save_png(ca_path)
			print("Screenshot: ", ca_path)
		get_tree().quit()


func _run_test_msub() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 40000)
		var i := 0

		for t in ["powr", "powr", "powr", "stek"]:
			world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
			i += 1
		var site := _find_water_site("spen", origin)
		if site.x >= 0:
			_base_at_water(site)
			_msub_yard = world.call("_add_building", "spen", 0, site)
			world.center_on((Vector2(site) + Vector2(2, 4)) * ProtoWorld.CELL)
		print("T: U-Boot-Bunker spen bei ", site)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 60:
		var names: Array = []
		for b in sim.buildable(0, 5):
			names.append(world.type_names[b])
		print("T: baubar in der Schiffs-Queue: ", names, " (msub dabei: %s)" % str(names.has("msub")))
		if world.type_ids.has("msub"):
			sim.queue_build(0, world.type_ids["msub"])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:
		for u in world.units:
			if u.alive and u.player == 0 and u.type == "msub":
				_msub_boat = u
		if _msub_boat == null:
			if tick < _test_tick + 6000:
				return
			print("T: msub wurde nicht gebaut — Abbruch")
			get_tree().quit()
			return
		var boat_cell := Vector2i(_msub_boat.pos / ProtoWorld.CELL)
		print("T: msub gebaut bei Tick ", tick, " Zelle ", boat_cell)


		var victim := _find_land_site("silo", boat_cell, 20)
		if victim.x >= 0:
			_msub_victim = world.call("_add_building", "silo", 1, victim)
			_msub_victim_hp = _msub_victim.hp if _msub_victim != null else 1.0
			print("T: Ziel silo bei ", victim, " Abstand %d Zellen" % (victim - boat_cell).length())
		world.center_on(_msub_boat.pos)
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3:

		if tick < _test_tick + 400:
			return
		print("T: getaucht ohne Befehl — sichtbar=%s, Ziel unverändert=%s" % [
			str(_msub_boat.visible),
			str(_msub_victim == null or is_equal_approx(_msub_victim.hp, _msub_victim_hp))])
		if _screenshot_path != "":
			await get_tree().process_frame
			var dive_path: String = _screenshot_path.get_basename() + "_getaucht.png"
			get_viewport().get_texture().get_image().save_png(dive_path)
			print("Screenshot: ", dive_path)
		if _msub_victim != null:
			world.select_units([_msub_boat])
			world.order_attack(_msub_victim)
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4:
		if _msub_victim != null and _msub_victim.alive and _msub_victim.hp >= _msub_victim_hp \
				and tick < _test_tick + 3000:
			return
		print("T: SubMissile: Silo HP %.2f → %.2f (lebt: %s)" % [
			_msub_victim_hp, _msub_victim.hp if _msub_victim != null else -1.0,
			str(_msub_victim != null and _msub_victim.alive)])
		world.center_on(_msub_boat.pos)
		_test_step = 5
		_test_tick = tick
	elif _test_step == 5:
		if tick < _test_tick + 20:
			return
		print("T: nach dem Schuss aufgetaucht (Cloak.UncloakOn Attack)")
		if _screenshot_path != "":
			await get_tree().process_frame
			var up_path: String = _screenshot_path.get_basename() + "_aufgetaucht.png"
			get_viewport().get_texture().get_image().save_png(up_path)
			print("Screenshot: ", up_path)
		_test_step = 6
		get_tree().quit()


func _run_test_lst() -> void:
	var sim = world.sim
	var tick: int = sim.tick()


	if _lst_boat != null and _lst_boat.alive and sim.has_method("ramp_state"):
		var rs: int = sim.ramp_state(_lst_boat.id)
		if _lst_ramp_seq.is_empty() or int(_lst_ramp_seq[-1]) != rs:
			_lst_ramp_seq.append(rs)
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


		world.select_only(_lst_boat)


		print("T: draussen bei ", Vector2i(_lst_boat.pos / ProtoWorld.CELL),
			" — Rampe ", _ramp_name(sim, _lst_boat.id),
			" — Eintrag sichtbar: ", world.selection_can_unload(),
			" can_unload: ", (sim.can_unload(_lst_boat.id) if sim.has_method("can_unload") else true),
			" blockiert: ", world.selection_unload_blocked(),
			" Entladen befohlen: ", world.unload_selected(),
			" an Bord ", sim.cargo_weight(_lst_boat.id))
		if _screenshot_path != "":
			world.center_on(_lst_boat.pos)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_see.png")

		var shore := _find_land_neighbor(Vector2i(_lst_boat.pos / ProtoWorld.CELL))
		if shore.x >= 0:
			world.order_move((Vector2(shore) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 55
		_test_tick = tick
	elif _test_step == 55 and tick >= _test_tick + 400:
		world.select_only(_lst_boat)


		print("T: am Ufer — Rampe ", _ramp_name(sim, _lst_boat.id),
			" — can_unload: ", (sim.can_unload(_lst_boat.id) if sim.has_method("can_unload") else true))
		if _screenshot_path != "":
			world.center_on(_lst_boat.pos)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_rampe_offen.png")
		print("T: Entladen befohlen: ", world.unload_selected())
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 250:
		var out := 0
		for u in _lst_troop:
			if u.alive and sim.transport_of(u.id) < 0:
				out += 1
		print("T: ausgestiegen ", out, " von ", _lst_troop.size(), ", an Bord ", sim.cargo_weight(_lst_boat.id),
			" — Rampe ", _ramp_name(sim, _lst_boat.id))
		if _screenshot_path != "":
			world.center_on(_lst_boat.pos)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_entladen.png")

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
		_test_origin.x = loaded_again


		world.select_only(_lst_boat)
		var out_at_sea := _find_water_cell(Vector2i(_lst_boat.pos / ProtoWorld.CELL), 12, 40)
		if out_at_sea.x >= 0:
			world.order_move((Vector2(out_at_sea) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 75
		_test_tick = tick


	elif _test_step == 75 and (sim.ramp_state(_lst_boat.id) == 0 or tick >= _test_tick + 200):
		print("T: abgelegt bei ", Vector2i(_lst_boat.pos / ProtoWorld.CELL),
			" — Rampe ", _ramp_name(sim, _lst_boat.id))
		if _screenshot_path != "":
			world.center_on(_lst_boat.pos)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(_screenshot_path.get_basename() + "_rampe_zu.png")
		print("T: Rampenfolge ", _lst_ramp_seq)
		sim.destroy(_lst_boat.id)
		_test_step = 8
		_test_tick = tick
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
	_para_lz = lz
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


func _toward_map_center(from: Vector2i) -> Vector2i:
	var c := Vector2i(world.map_w / 2, world.map_h / 2)
	return Vector2i(signi(c.x - from.x), signi(c.y - from.y))


var _para_lz := Vector2i(-1, -1)
var _tran_heli = null
var _tran_troop: Array = []
var _tran_tries := 0
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

		var tnk = world.spawn_unit("2tnk" if world.type_ids.has("2tnk") else "1tnk", 0, origin + Vector2i(2, 6))
		if tnk != null and _cargo_apc != null:
			print("T: Panzer im MTW erlaubt: ", sim.can_load(_cargo_apc.id, tnk.id), " (erwartet false)")
			world.select_units([tnk])
			print("T: Panzer-Einsteigebefehl angenommen: ", world.order_enter_transport(_cargo_apc),
				" (erwartet false)")
		world.center_on((Vector2(origin) + Vector2(3, 3)) * ProtoWorld.CELL)
		print("T: Transporter ", "da" if _cargo_apc != null else "fehlt", ", Infanterie ", _cargo_troop.size())
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 20:
		world.select_only(_cargo_apc)
		print("T: leerer MTW — Radialeintrag Entladen: ", world.selection_can_unload(), " (erwartet false)")
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

		world.select_only(_cargo_apc)
		print("T: Radialeintrag Entladen mit Ladung: ", world.selection_can_unload(), " (erwartet true)")
		print("T: Entladen befohlen (wird gleich ersetzt): ", world.unload_selected())
		world.order_move((Vector2(_test_origin) + Vector2(4, 12)) * ProtoWorld.CELL)
		_test_step = 35
		_test_tick = tick
	elif _test_step == 35 and tick >= _test_tick + 120:
		print("T: nach dem Fahrbefehl noch an Bord: ", sim.cargo_weight(_cargo_apc.id), " (erwartet 5)")
		world.select_only(_cargo_apc)
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


func _run_test_toasts() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(10, 10)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_test_origin = origin
		_screenshot_tick = 1 << 30
		var i := 0
		var soviet := world.player_faction() == "soviet"
		for t in ["fact", "powr", "powr", "proc", "barr" if soviet else "tent", "weap"]:
			if world.type_ids.has(t):
				world.call("_add_building", t, 0, origin + Vector2i(-6 + i * 3, 4))
				i += 1
		sim.give_credits(0, 20000)
		world.center_on((Vector2(origin) + Vector2(0, 4)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
		return
	if _test_step < 1 or tick < _test_tick + 60:
		return
	_test_tick = tick

	for t in ["e1", "2tnk" if world.player_faction() != "soviet" else "3tnk"]:
		if world.type_ids.has(t):
			world.queue_build(world.type_ids[t])
	if world.type_ids.has("powr") and world.placing_type < 0:
		var q: PackedInt32Array = sim.queue_state(0, 0)
		if q.size() < 3 or q[2] != 1:
			world.queue_build(world.type_ids["powr"])
		else:

			_begin_placement(q[0])
			world.move_placement((Vector2(_test_origin) + Vector2(-8 + (_test_step % 7) * 3, 8)) * ProtoWorld.CELL)
			_confirm_placement()

	match _test_step % 8:
		1:
			_cmd_buttons["all"].pressed.emit()
		2:
			_cmd_buttons["add"].button_pressed = not _cmd_buttons["add"].button_pressed
			_cmd_buttons["add"].pressed.emit()
		3:
			_cmd_buttons["base"].pressed.emit()
		4:
			_set_click_mode("sell")
		5:
			_end_click_mode()
		6:
			_on_radial("scatter")
		7:
			_cmd_buttons["clear"].pressed.emit()
		0:
			_cmd_buttons["event"].pressed.emit()
	_test_step += 1

	if _screenshot_path != "" and _test_step in [4, 9, 14]:
		_shot("band%d" % _test_step)
	if tick >= _test_toasts_until:
		print("T --test-toasts: Ende bei Tick %d" % tick)
		print("T --test-toasts: Textband sichtbar in %d von %d Bildern (%.1f %%), Zeilen im Mittel %.2f, höchstens %d" % [
				_toast_frames_busy, _toast_frames,
				100.0 * _toast_frames_busy / maxi(_toast_frames, 1),
				float(_toast_line_sum) / maxi(_toast_frames_busy, 1), _toast_lines_max])
		HudTheme.log_summary()
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


var _test_defense_fire := false
var _df_turret = null
var _df_target = null
var _df_hp0 := 1.0
var _df_prev := 1.0
var _df_hits := 0
var _df_first := -1
var _df_hold := true
var _df_radial := false


func _df_watch() -> void:
	if _df_target == null:
		return
	var hp: float = _df_target.hp if _df_target.alive else 0.0
	if hp < _df_prev - 0.0001:
		_df_hits += 1
		if _df_first < 0:
			_df_first = world.sim.tick()
	_df_prev = hp


func _df_report(what: String, dead_expected: bool) -> void:
	var alive: bool = _df_target != null and _df_target.alive
	var hp: float = _df_target.hp if alive else 0.0
	var ok: bool = (not alive) if dead_expected else (hp < _df_hp0 - 0.001)
	print("T --test-defense-fire: %s Ziel-ID=%d erster Treffer bei Tick %d, %d Treffer, %.0f %% → %.0f %%, %s %s" % [
			what, _df_target.id if _df_target != null else -1, _df_first, _df_hits,
			_df_hp0 * 100.0, hp * 100.0, "zerstört" if not alive else "steht noch",
			"OK" if ok else "FEHLER"])


func _run_test_defense_fire() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		_screenshot_tick = 1 << 30
		var origin := _place_test_fact()
		_test_origin = origin
		sim.give_credits(0, 20000)
		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)

		world.call("_add_building", "powr", 0, origin + Vector2i(-8, 8))
		world.call("_add_building", "powr", 0, origin + Vector2i(-8, 11))
		_df_turret = world.call("_add_building", "ftur", 0, origin + Vector2i(0, 8))
		_df_target = world.call("_add_building", "barr", 1, origin + Vector2i(3, 8))
		if _df_turret == null or _df_turret.id < 0 or _df_target == null or _df_target.id < 0:
			print("T --test-defense-fire: Flammenturm oder Gegnergebäude nicht setzbar — abgebrochen")
			get_tree().quit()
			return
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		world.center_on(_df_turret.pos)
		_df_hp0 = _df_target.hp
		_df_prev = _df_hp0
		_df_hits = 0
		_df_first = -1
		print("T --test-defense-fire: Flammenturm ID=%d bei %s, feindliche Kaserne ID=%d bei %s" % [
				_df_turret.id, str(Vector2i(_df_turret.pos / ProtoWorld.CELL)),
				_df_target.id, str(Vector2i(_df_target.pos / ProtoWorld.CELL))])
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1:

		_df_watch()
		if _df_hits > 0 and _df_hits <= 2:
			_shot("auto")
		if (_df_target != null and not _df_target.alive) or tick >= _test_tick + 900:
			_df_report("automatisch auf feindliches Gebäude:", true)
			_shot("auto_ende")

			_df_target = world.call("_add_building", "powr", 0, _test_origin + Vector2i(3, 8))
			if _df_target == null or _df_target.id < 0:
				print("T --test-defense-fire: kein eigenes Gebäude setzbar — abgebrochen")
				get_tree().quit()
				return
			_df_hp0 = _df_target.hp
			_df_prev = _df_hp0
			_df_hits = 0
			_df_first = -1
			_df_hold = true
			world.select_only(_df_turret)
			world.center_on(_df_turret.pos)
			_on_long_press(world.world_to_screen(_df_target.pos))
			_df_radial = radial.visible and radial.ITEMS.has("force_attack")
			print("T --test-defense-fire: Ring am eigenen Gebäude offen=%s, Einträge=%s, Zwangsangriff=%s %s" % [
					radial.visible, str(radial.ITEMS), _df_radial, "OK" if _df_radial else "FEHLER"])
			_shot("ring")
			radial.cancel()
			_on_radial("force_attack")
			print("T --test-defense-fire: nach dem Ring force_attacking=%s (erwartet true) %s" % [
					sim.force_attacking(_df_turret.id), "OK" if sim.force_attacking(_df_turret.id) else "FEHLER"])
			_test_step = 2
			_test_tick = tick
	elif _test_step == 2:
		_df_watch()

		if _df_target != null and _df_target.alive and not sim.force_attacking(_df_turret.id):
			_df_hold = false
		if (_df_target != null and not _df_target.alive) or tick >= _test_tick + 900:
			_df_report("Zwangsfeuer aufs eigene Kraftwerk:", true)
			print("T --test-defense-fire: Befehl durchgehend gehalten=%s %s" % [
					_df_hold, "OK" if _df_hold else "FEHLER"])
			_shot("zwangsfeuer")

			_df_target = world.call("_add_building", "barr", 1, _test_origin + Vector2i(3, 8))
			if _df_target == null or _df_target.id < 0:
				print("T --test-defense-fire: zweites Gegnergebäude nicht setzbar — abgebrochen")
				get_tree().quit()
				return
			_df_hp0 = _df_target.hp
			_df_prev = _df_hp0
			_df_hits = 0
			_df_first = -1
			world.select_only(_df_turret)
			_on_tap(world.world_to_screen(_df_target.pos))
			print("T --test-defense-fire: Tipp auf Gegnergebäude → letzte Geste: %s" % _last_gesture)
			_test_step = 3
			_test_tick = tick
	elif _test_step == 3:
		_df_watch()
		if (_df_target != null and not _df_target.alive) or tick >= _test_tick + 900:
			_df_report("Fingertipp auf feindliches Gebäude:", true)
			_shot("tipp")

			_df_target = world.call("_add_building", "sbag", 0, _test_origin + Vector2i(3, 8))
			if _df_target == null or _df_target.id < 0:
				print("T --test-defense-fire: kein Sandsack setzbar — Zellteil übersprungen")
				get_tree().quit()
				return
			_df_hp0 = _df_target.hp
			_df_prev = _df_hp0
			_df_hits = 0
			_df_first = -1
			world.select_only(_df_turret)
			_on_radial("force_fire")
			_on_tap(world.world_to_screen(_df_target.pos))
			_test_step = 4
			_test_tick = tick
	elif _test_step == 4:
		_df_watch()
		if (_df_target != null and not _df_target.alive) or tick >= _test_tick + 600:
			_df_report("Zwangsfeuer auf die Zelle der eigenen Mauer:", true)
			_shot("zelle")
			get_tree().quit()


func _test_ui_types() -> Array:
	var args := OS.get_cmdline_user_args()
	var tk := args.find("--test-tab")
	var tab := int(args[tk + 1]) if tk >= 0 and tk + 1 < args.size() else 0
	if tab < 2:
		return ["fact", "powr", "proc"]
	var soviet := ProtoWorld.next_faction == "soviet"
	if soviet:


		return ["fact", "powr", "powr", "apwr", "proc", "barr", "weap", "stek", "tsla"]
	return ["fact", "powr", "apwr", "proc", "tent", "weap", "atek"]


func _run_test_eva() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _eva_power_flip < 0 and sim.power_drained(0) > sim.power_provided(0):
		_eva_power_flip = tick
		_eva_marks.append([tick, "Strombilanz kippt: %d bereitgestellt, %d verbraucht" % [
			sim.power_provided(0), sim.power_drained(0)]])
	match _eva_step:
		0:
			if tick < 5:
				return
			var origin := Vector2i(10, 10)
			for u in world.units:
				if u.alive and u.player == 0:
					origin = Vector2i(u.pos / ProtoWorld.CELL)
					break
			_eva_origin = origin
			world.call("_add_building", "fact", 0, origin)
			world.center_on(Vector2(origin + Vector2i(2, 2)) * ProtoWorld.CELL)
			sim.give_credits(0, 20000)
			_eva_marks.append([tick, "Bauhof steht (Startansage läuft noch)"])
			_eva_step = 1
			_eva_tick = tick
		1:

			if tick < _eva_tick + 25:
				return
			_eva_marks.append([tick, "erster Baubefehl: Kraftwerk (erwartet „abldgin1“)"])
			_eva_order_tick = tick
			world.queue_build(world.type_ids.get("powr", -1))
			_eva_step = 2
		2:
			if not _eva_queue_done():
				return
			_eva_marks.append([tick, "Kraftwerk fertig (erwartet „conscmp1“)"])
			_eva_place("powr")
			_eva_step = 3
			_eva_tick = tick
		3:
			if tick < _eva_tick + 25:
				return
			_eva_marks.append([tick, "zweiter Baubefehl: Kaserne"])
			world.queue_build(world.type_ids.get(_eva_barracks(), -1))
			_eva_step = 4
		4:
			if not _eva_queue_done():
				return
			_eva_marks.append([tick, "Kaserne fertig, wird gesetzt (erwartet „conscmp1“ + „newopt1“)"])
			_eva_place(_eva_barracks())


			for i in 3:
				world.call("_add_building", "dome", 0, _eva_origin + Vector2i(-8 + i * 4, 6))
			_eva_marks.append([tick, "drei Radarkuppeln gesetzt (erwartet „lopower1“)"])
			_eva_step = 5
			_eva_tick = tick
		5:
			if tick < _eva_tick + 250:
				return

			sim.set_resources(0, 0)
			sim.give_credits(0, -sim.cash(0))

			var best := -1
			var best_cost := -1
			for t in sim.buildable(0, 0):
				if sim.type_cost(t) > best_cost:
					best_cost = sim.type_cost(t)
					best = t
			_eva_marks.append([tick, "Konto geleert, %s (%d) bestellt (erwartet „nofunds1“)" % [
				world.type_names[best] if best >= 0 else "?", best_cost]])
			world.queue_build(best)
			_eva_step = 6
			_eva_tick = tick
		6:
			if tick < _eva_tick + 150:
				return
			_eva_report()
			_eva_step = 7
			get_tree().quit()


func _eva_barracks() -> String:
	return "barr" if world.type_ids.has("barr") and world.sim.buildable(0, 0).has(world.type_ids["barr"]) else "tent"


func _eva_queue_done() -> bool:
	var q: PackedInt32Array = world.sim.queue_state(0, 0)
	return q.size() >= 7 and q[2] == 1


func _eva_place(type_name: String) -> bool:
	var tid: int = world.type_ids.get(type_name, -1)
	if tid < 0:
		return false
	for r in range(2, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := _eva_origin + Vector2i(dx, dy)

				if world.sim.can_place(0, tid, c.x, c.y)[0] == 1:
					var ok: bool = world.sim.place_building(0, tid, c.x, c.y)
					if not ok:
						print("T-EVA: %s auf %s abgelehnt" % [type_name, c])
					return ok
	print("T-EVA: kein Platz für %s" % type_name)
	return false


func _eva_report() -> void:
	var tps := 25.0
	print("\n===== EVA-Protokoll (--test-eva) =====")
	var rows: Array = []
	for m in _eva_marks:
		rows.append([m[0], "MARKE", String(m[1]), "", 0.0, 0])
	for r in world.eva_records:
		rows.append([r[0], "EVA", String(r[1]), String(r[2]), float(r[3]), int(r[4])])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for r in rows:
		if r[1] == "MARKE":
			print("t=%5d  ---- %s" % [r[0], r[2]])
		else:
			print("t=%5d  EVA  %-9s %-9s (%d Kanal/Kanäle belegt, längste noch %.2f s)" % [
				r[0], r[2], r[3], r[5], r[4]])
	var played := func(n: String, after: int) -> int:
		for r in world.eva_records:
			if String(r[1]) == n and String(r[2]) in ["ab", "nachgezogen"] and int(r[0]) >= after:
				return int(r[0])
		return -1
	print("--- Sollwerte ---")
	var b: int = played.call("abldgin1", _eva_order_tick)
	print("„Building“ nach dem ersten Baubefehl (t=%d): %s" % [_eva_order_tick,
		("t=%d, +%d Ticks" % [b, b - _eva_order_tick]) if b >= 0 else "NICHT ABGESPIELT"])
	var no: int = played.call("newopt1", 0)
	print("„Neue Bauoptionen“: %s" % [("t=%d" % no) if no >= 0 else "NICHT ABGESPIELT"])
	var lp: int = played.call("lopower1", maxi(_eva_power_flip, 0))
	print("„Strom niedrig“ nach dem Kippen (t=%d): %s" % [_eva_power_flip,
		("t=%d, +%.2f s" % [lp, (lp - _eva_power_flip) / tps]) if lp >= 0 else "NICHT ABGESPIELT"])
	var nf: int = played.call("nofunds1", 0)
	print("„Nicht genug Geld“: %s" % [("t=%d" % nf) if nf >= 0 else "NICHT ABGESPIELT"])
	var stats := {}
	for r in world.eva_records:
		var key: String = String(r[2])
		stats[key] = int(stats.get(key, 0)) + 1
	print("Ergebnisse insgesamt: %s" % [stats])


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


		for t in _test_ui_types():
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
				"sammler", "sammler-doppelt":


					for u in world.units:
						if u.alive and u.player == 0 and world.types[u.type].get("refinery", false):
							world.spawn_unit("harv", 0, Vector2i(u.pos / ProtoWorld.CELL) + Vector2i(4, 3))
							break
					var hb: Button = _cmd_buttons["harv"]
					hb.button_down.emit()
					hb.pressed.emit()
					var erster := _last_harv_cmd
					if args2[mk + 1] == "sammler-doppelt":
						hb.button_down.emit()
						hb.pressed.emit()
					print("T: Sammler-Knopf sichtbar=%s in der Leiste=%s, eigene Sammler=%d, erster Tipp='%s', zuletzt='%s' (Sim kennt die Befehle: %s/%s)" % [
						hb.visible, "harv" in _cmd_order, world.own_harvester_count(), erster, _last_harv_cmd,
						world.sim.has_method("order_harvesters_return_to_base"),
						world.sim.has_method("order_harvesters_resume")])
					print("T: untere Reihe ausgeblendet=%s, sichtbare Knopffolge=%s" % [
						not BOTTOM_ROW_VISIBLE, _cmd_order])
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
						print("T: Reichweite gun=%.0f px, Baufläche im Bild=%s" % [
							world.weapon_range_px("gun"), world.build_area_in_view()])
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
				"erweitern", "verkaufen", "reparieren":


					var mid: String = {"erweitern": "add", "verkaufen": "sell", "reparieren": "repair"}[args2[mk + 1]]
					var mb: Button = _cmd_buttons[mid]


					mb.button_down.emit()
					if mid == "add":
						mb.set_pressed_no_signal(true)
					mb.pressed.emit()
					print("T: Modus %s: Rand sichtbar=%s Farbe=%s Erweitern=%s Klickmodus='%s'" % [
						args2[mk + 1], _mode_frame.visible, _mode_frame_col, world.additive_select, _click_mode])
				"modus-wechsel":


					var add_b: Button = _cmd_buttons["add"]
					for step in ["an", "aus", "an", "verkaufen", "an", "leeren"]:
						match step:
							"an", "aus":
								add_b.button_down.emit()
								add_b.set_pressed_no_signal(step == "an")
								add_b.pressed.emit()
							_:
								var b3: Button = _cmd_buttons["sell" if step == "verkaufen" else "clear"]
								b3.button_down.emit()
								b3.pressed.emit()
						print("T: modus-wechsel %s → Rand=%s Farbe=%s Erweitern=%s Klickmodus='%s' Knopf=%s" % [
							step, _mode_frame.visible, _mode_frame_col, world.additive_select,
							_click_mode, add_b.button_pressed])
				"ziele": _show_objectives()
				"radial": radial.open(get_viewport().get_visible_rect().size / 2.0, _unit_items())
				"zielleiste":


					var zo := Vector2i(10, 10)
					for u in world.units:
						if u.alive and u.player == 0:
							zo = Vector2i(u.pos / ProtoWorld.CELL)
							break
					var za := world.spawn_unit("2tnk", 0, zo + Vector2i(-3, 4))
					var zb := world.spawn_unit("2tnk", 0, zo + Vector2i(2, 4))
					if za != null and zb != null:
						world.select_only(za)
						world.center_on((za.pos + zb.pos) / 2.0)
						_on_tap(world.world_to_screen(zb.pos))
						print("T: Zielleiste offen=%s, Einträge=%s (Sollwert: 》Auswählen《 zuerst)" % [
							action_bar.visible, str(action_bar.ITEMS)])
					else:
						print("T: Zielleiste — konnte keine zwei Einheiten setzen")
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


		if _test_ready != "kette":
			get_tree().quit()


const ARM_WINDOW := 300
const ARM_COOLDOWN := 60
const ARM_CASES := [
	{"s": "4tnk", "t": "e1", "d": 4, "air": false, "w": "MammothTusk (120mm darf keine Infanterie treffen)", "min": 90.0},
	{"s": "4tnk", "t": "e1", "d": 6, "air": false, "w": "MammothTusk auf 6 Zellen (120mm reicht nur 4,75)", "min": 90.0},
	{"s": "4tnk", "t": "2tnk", "d": 4, "air": false, "w": "120mm (MammothTusk trifft nur Luft/Infanterie)", "min": 50.0},
	{"s": "ftrk", "t": "e1", "d": 4, "air": false, "w": "FLAK-23-AG", "min": 90.0},
	{"s": "ftrk", "t": "tran", "d": 4, "air": true, "w": "FLAK-23-AA", "min": 90.0},
	{"s": "e3", "t": "2tnk", "d": 4, "air": false, "w": "Dragon", "min": 25.0},
	{"s": "e3", "t": "tran", "d": 4, "air": true, "w": "RedEye", "min": 40.0},
	{"s": "1tnk", "t": "2tnk", "d": 4, "air": false, "w": "25mm (einzige Bewaffnung)", "min": 15.0},
]


func _run_test_armaments() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		for u in world.units:
			if u.alive and u.player == 0:
				_arm_origin = Vector2i(u.pos / ProtoWorld.CELL)
				break

		sim.set_enemy(0, 1, true)
		sim.set_enemy(1, 0, true)
		for n in ["4tnk", "ca", "ftrk", "e3", "1tnk"]:
			var t: Dictionary = world.types.get(n, {})
			print("T: %s Waffen: %s / %s" % [n, t.get("weapon", "-"), t.get("weapon_secondary", "-")])
		world.zoom_at(ProtoWorld.MAX_ZOOM / world.zoom, world.get_viewport_rect().size / 2.0)
		_test_step = 1
	elif _test_step == 1:
		if _arm_case >= ARM_CASES.size():
			_test_step = 5
			return
		var c: Dictionary = ARM_CASES[_arm_case]
		var sc: Vector2i = _arm_origin + Vector2i(ARM_GAP, 0)
		_arm_shooter = world.spawn_unit(c["s"], 0, sc)
		_arm_target = world.spawn_unit(c["t"], 1, sc + Vector2i(int(c["d"]), 0), -1, 100, bool(c["air"]))
		world.center_on((Vector2(sc) + Vector2(float(c["d"]) / 2.0, 0.5)) * ProtoWorld.CELL)
		if _arm_shooter == null or _arm_target == null:
			print("T: %s → %s: konnte nicht gesetzt werden (Typ fehlt oder Zelle belegt)" % [c["s"], c["t"]])
			_arm_fail += 1
			_arm_case += 1
			return
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2 and tick >= _test_tick + 5:
		_arm_hp[_arm_target.id] = _arm_target.hp
		_test_step = 3
		_test_tick = tick
	elif _test_step == 3 and tick >= _test_tick + ARM_WINDOW:
		var c: Dictionary = ARM_CASES[_arm_case]
		var now: float = _arm_target.hp if _arm_target.alive else 0.0
		var dmg: float = (float(_arm_hp[_arm_target.id]) - now) * 100.0
		var ok: bool = dmg >= float(c["min"])
		if ok:
			_arm_ok += 1
		else:
			_arm_fail += 1
		print("T: %s auf %d Zellen gegen %s → %.0f %% Schaden (erwartet ≥ %.0f %%, %s) %s" % [
				c["s"], int(c["d"]), c["t"], dmg, float(c["min"]), c["w"], "OK" if ok else "FEHLER"])
		sim.remove_actor(_arm_shooter.id)
		sim.remove_actor(_arm_target.id)
		_arm_case += 1
		_test_step = 4
		_test_tick = tick
	elif _test_step == 4 and tick >= _test_tick + ARM_COOLDOWN:


		_test_step = 1
	elif _test_step == 5:
		print("T: Bewaffnung — %d von %d Paarungen wie erwartet" % [_arm_ok, _arm_ok + _arm_fail])
		if _screenshot_path == "":
			get_tree().quit()
			return


		var o: Vector2i = _arm_origin + Vector2i(ARM_GAP, 0)
		world.spawn_unit("4tnk", 0, o)
		world.spawn_unit("e1", 1, o + Vector2i(4, 0))
		world.spawn_unit("2tnk", 1, o + Vector2i(-4, 0))
		world.spawn_unit("ftrk", 0, o + Vector2i(0, 4))
		world.spawn_unit("tran", 1, o + Vector2i(4, 4), -1, 100, true)
		world.center_on((Vector2(o) + Vector2(0.5, 2.5)) * ProtoWorld.CELL)
		_test_step = 6
		_test_tick = tick
	elif _test_step == 6 and tick >= _test_tick + 40:
		_test_step = 7
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("Screenshot: ", _screenshot_path)
		get_tree().quit()


const RETREAT_DIST := 16
const RETREAT_SHOT := 70
const RETREAT_WINDOW := 500
const RETREAT_STALL := 20
var _test_retreat := false
var _retreat_squad: Array = []
var _retreat_foes: Array = []
var _retreat_goal := Vector2i.ZERO
var _retreat_hp_spawn := 0.0
var _retreat_hp0 := 0.0
var _retreat_foe_hp0 := 0.0
var _retreat_stall := 0
var _retreat_back := 0
var _retreat_prev: Array = []
var _retreat_run: Array = []
var _retreat_shot := false


func _run_test_retreat() -> void:
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
		var base := origin + Vector2i(6, 0)
		for k in range(4):
			var u := world.spawn_unit("2tnk", 0, base + Vector2i(0, k))
			if u != null:
				_retreat_squad.append(u)
		for k in range(3):
			var f := world.spawn_unit("3tnk", 1, base + Vector2i(4, k))
			if f != null:


				sim.set_stance(f.id, 3)
				_retreat_foes.append(f)
		_retreat_hp_spawn = 0.0
		for u in _retreat_squad:
			_retreat_hp_spawn += u.hp
		if _retreat_squad.size() < 4 or _retreat_foes.is_empty():
			print("T: --test-retreat: Aufbau misslungen (%d Panzer, %d Gegner)" % [
				_retreat_squad.size(), _retreat_foes.size()])
			get_tree().quit()
			return
		_retreat_goal = base - Vector2i(RETREAT_DIST, 0)
		world.selection.clear()
		for u in _retreat_squad:
			u.selected = true
			world.selection.append(u)
		world.center_on((Vector2(base) + Vector2(1.0, 1.5)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 40:

		var ids := PackedInt32Array()
		_retreat_prev.clear()
		_retreat_run.clear()
		_retreat_hp0 = 0.0
		for u in _retreat_squad:
			ids.append(u.id)
			_retreat_prev.append(u.pos.x)
			_retreat_run.append(0)
			_retreat_hp0 += u.hp
		_retreat_foe_hp0 = 0.0
		for f in _retreat_foes:
			_retreat_foe_hp0 += (f.hp if f.alive else 0.0)
		world.order_move_ids(ids, _retreat_goal)
		print("T%d: --test-retreat: Rückzugsbefehl auf %s, Trupp bei %.0f %% Trefferpunkten" % [
			tick, str(_retreat_goal), _retreat_hp0 * 25.0])
		_test_step = 2
		_test_tick = tick
	elif _test_step == 2:


		var far: float = float(_retreat_goal.x + 3) * ProtoWorld.CELL
		for k in range(_retreat_squad.size()):
			var u = _retreat_squad[k]
			if not u.alive:
				continue
			var x: float = u.pos.x
			if x > far and not sim.has_move_order(u.id):
				_retreat_run[k] = int(_retreat_run[k]) + 1
				_retreat_stall = max(_retreat_stall, int(_retreat_run[k]))
			else:
				_retreat_run[k] = 0
			if x > float(_retreat_prev[k]) + 0.5 and x > far:
				_retreat_back += 1
			_retreat_prev[k] = x
		if not _retreat_shot and tick >= _test_tick + RETREAT_SHOT and _screenshot_path != "":
			_retreat_shot = true
			_retreat_snap()
		if tick >= _test_tick + RETREAT_WINDOW:
			_test_step = 4
	elif _test_step == 4:
		var arrived := 0
		var alive := 0
		var hp1 := 0.0
		for u in _retreat_squad:
			if u.alive:
				alive += 1
				hp1 += u.hp
				if u.pos.x <= float(_retreat_goal.x + 3) * ProtoWorld.CELL:
					arrived += 1
		var foe_hp := 0.0
		for f in _retreat_foes:
			foe_hp += (f.hp if f.alive else 0.0)
		var hurt: bool = hp1 < _retreat_hp_spawn - 0.001
		var returned: bool = foe_hp < _retreat_foe_hp0 - 0.001
		var no_halt: bool = _retreat_stall <= RETREAT_STALL and _retreat_back == 0
		print("T%d: --test-retreat: %d von %d am Ziel (%d am Leben), kein Halt=%s (längster Stillstand ohne Fahrbefehl %d Ticks, Rückwärts %d), "
			% [tick, arrived, _retreat_squad.size(), alive, str(no_halt), _retreat_stall, _retreat_back]
			+ "unter Feuer=%s (%.0f %% → %.0f %%), Türme haben in der Fahrt zurückgefeuert=%s (Gegner %.0f %% → %.0f %%)"
			% [str(hurt), _retreat_hp_spawn * 25.0, hp1 * 25.0, str(returned),
			_retreat_foe_hp0 * 33.3, foe_hp * 33.3])
		print("T: --test-retreat: %s" % ("OK" if (arrived == alive and alive >= 3
			and no_halt and hurt and returned) else "FEHLER"))
		_test_step = 5
		get_tree().quit()


func _retreat_snap() -> void:

	var mid := Vector2.ZERO
	var n := 0
	for u in _retreat_squad + _retreat_foes:
		if u.alive:
			mid += u.pos
			n += 1
	if n > 0:
		world.center_on(mid / float(n))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(_screenshot_path)
	print("Screenshot: ", _screenshot_path)


func _run_test_heal() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		_heal_units.clear()
		var col := 0
		for name in ["4tnk", "harv", "3tnk"]:
			var t: Dictionary = world.types.get(name, {})
			print("T: %s Regeln heal_step=%s heal_percent=%s heal_delay=%s heal_start_below=%s heal_damage_cooldown=%s hp=%s" % [
					name, t.get("heal_step", "-"), t.get("heal_percent", "-"), t.get("heal_delay", "-"),
					t.get("heal_start_below", "-"), t.get("heal_damage_cooldown", "-"), t.get("hp", "-")])
			if not world.type_ids.has(name):
				continue
			var u := world.spawn_unit(name, 0, origin + Vector2i(col * 3, 3), -1, 30)
			if u != null:
				_heal_units[name] = u.id
			col += 1
		world.center_on((Vector2(origin) + Vector2(2, 3)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1:
		if (tick - _test_tick) % 200 == 0 and tick != _heal_logged:
			_heal_logged = tick
			var line := "T%d --test-heal:" % tick
			for name in _heal_units:
				line += " %s=%d ‰" % [name, _heal_permille(name)]
			print(line)
		if tick >= _test_tick + 3400:
			var ok := true
			for name in _heal_units:
				var permille: int = _heal_permille(name)
				var expect: int = 500 if int(world.types.get(name, {}).get("heal_delay", 0)) > 0 else 300
				var good: bool = absi(permille - expect) <= 5
				ok = ok and good
				print("T%d --test-heal: %s bei %d ‰ (erwartet %d ‰) %s" % [tick, name, permille, expect,
						"OK" if good else "FEHLER"])
			print("T%d --test-heal: %s" % [tick, "OK" if ok else "FEHLER"])
			if _screenshot_path != "":
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
				print("Screenshot: ", _screenshot_path)
			get_tree().quit()


var _heal_units: Dictionary = {}
var _heal_logged := -1
var _iron_target := -1


func _heal_permille(name: String) -> int:
	var maxhp: int = maxi(1, int(world.types.get(name, {}).get("hp", 1)))
	return int(world.sim.actor_hp(_heal_units[name]) * 1000 / maxhp)


func _run_test_iron() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(20, 20)
		for u in world.units:
			if u.alive and u.player == 0:
				origin = Vector2i(u.pos / ProtoWorld.CELL)
				break
		sim.give_credits(0, 20000)


		for i in 8:
			world.call("_add_building", "powr", 0, origin + Vector2i(-6 - (i / 4) * 3, (i % 4) * 3))
		world.call("_add_building", "iron", 0, origin + Vector2i(6, 0))
		_test_origin = origin + Vector2i(1, 6)
		var u2 := world.spawn_unit("4tnk", 0, _test_origin)
		_iron_target = u2.id if u2 != null else -1
		world.center_on((Vector2(_test_origin) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
		_test_step = 1
		_test_tick = tick
	elif _test_step == 1 and tick >= _test_tick + 30:
		if _screenshot_path != "":
			await get_tree().process_frame
			var before: String = _screenshot_path.get_basename() + "_vorher.png"
			get_viewport().get_texture().get_image().save_png(before)
			print("T%d --test-iron: Vergleichsfoto ohne Vorhang %s" % [tick, before])
		_test_step = 15
	elif _test_step == 15:
		var ready := false
		for _i in 14000:
			sim.step()
			var st: PackedInt32Array = sim.support_powers(0)
			if st.size() >= 4 and st[1] == 1:
				ready = true
				break
		if not ready:
			print("T --test-iron: Eiserner Vorhang nicht rechtzeitig geladen")
			get_tree().quit()
			return
		if not world.activate_support_power(0, (Vector2(_test_origin) + Vector2(0.5, 0.5)) * ProtoWorld.CELL):
			print("T --test-iron: Auslösen fehlgeschlagen")
			get_tree().quit()
			return
		print("T%d --test-iron: ausgelöst auf %s" % [sim.tick(), _test_origin])
		_test_step = 2
		_test_tick = sim.tick()
	elif _test_step == 2 and tick >= _test_tick + 20:
		var state: PackedFloat32Array = sim.render_state(0.0)
		var stride := ProtoWorld.RENDER_STRIDE
		var found := false
		for i in range(0, state.size(), stride):
			if int(state[i]) != _iron_target:
				continue
			found = true
			var flags := int(state[i + 11])
			print("T%d --test-iron: Ziel-Flags %d, unverwundbar-Bit %d" % [tick, flags, (flags >> 9) & 1])
		if not found:
			print("T%d --test-iron: Ziel nicht im render_state" % tick)
		if _screenshot_path != "":
			await get_tree().process_frame
			var during: String = _screenshot_path.get_basename() + "_vorhang.png"
			get_viewport().get_texture().get_image().save_png(during)
			print("T%d --test-iron: Foto während der Wirkung %s" % [tick, during])
		get_tree().quit()


func _run_test_water() -> void:

	while world.sim == null or world.sim.tick() < 150:
		await get_tree().process_frame
	var patch := _find_water_and_land()
	if patch.is_empty():
		print("T --test-water: keine Küste gefunden — Karte mit Wasser wählen (z. B. --map tournament-island)")
		get_tree().quit()
		return
	var shore: Vector2i = patch["shore"]
	var land: Vector2i = patch["land"]
	var open_water: Vector2i = patch.get("open", shore)
	world.center_on((Vector2(shore + land) / 2.0 + Vector2(0.5, 0.5)) * ProtoWorld.CELL)


	world.paused = true
	await get_tree().process_frame
	var srect := _cell_rect(shore, 1.6)
	var lrect := _cell_rect(land, 1.0)
	var orect := _cell_rect(open_water, 1.6)
	print("T --test-water: Uferzelle %s, offenes Wasser %s, Landzelle %s (Terrain %d)" % [
			shore, open_water, land, world.terrain_type(land)])
	var shots: Array = []
	for k in 8:

		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		shots.append({
			"tick": int(world.sim.tick()), "phase": PaletteAtlas.water_phase(int(world.sim.tick())),
			"shore": _rect_signature(img, srect), "land": _rect_signature(img, lrect),
			"open": _rect_signature(img, orect),
		})
		if _screenshot_path != "" and k in [0, 1, 2, 7]:
			var p: String = "%s_t%d.png" % [_screenshot_path.get_basename(), k * 4]
			img.save_png(p)
			print("T --test-water: Bild nach %d Ticks (Phase %d) %s" % [k * 4, shots[k]["phase"], p])
		for _i in PaletteAtlas.WATER_ROTATION_TICKS:
			world.sim.step()
	var ok := true
	var seen := {}
	for k in 7:
		seen[shots[k]["shore"]] = true
	for k in range(1, 7):
		var differs: bool = shots[k]["shore"] != shots[0]["shore"]
		var land_same: bool = shots[k]["land"] == shots[0]["land"]
		ok = ok and differs and land_same
		print("T --test-water: nach %2d Ticks Phase %d — Ufer %s, offenes Wasser %s, Land %s" % [
				k * 4, shots[k]["phase"],
				"anders (OK)" if differs else "gleich (FEHLER)",
				"anders" if shots[k]["open"] != shots[0]["open"] else "gleich",
				"gleich (OK)" if land_same else "anders (FEHLER)"])
	var wrap: bool = shots[7]["shore"] == shots[0]["shore"] and shots[7]["land"] == shots[0]["land"]
	ok = ok and wrap
	print("T --test-water: nach 28 Ticks Phase %d — %s" % [shots[7]["phase"],
			"Bild wieder wie am Anfang (OK)" if wrap else "abweichend (FEHLER)"])


	print("T --test-water: %d verschiedene Uferbilder im Umlauf (7 erwartet)" % seen.size())
	print("T --test-water: %s" % ["OK" if ok else "FEHLER"])
	get_tree().quit()


func _cell_rect(cell: Vector2i, cells: float = 1.0) -> Rect2i:
	var c := world.world_to_screen((Vector2(cell) + Vector2(0.5, 0.5)) * ProtoWorld.CELL)
	var half := maxf(3.0, ProtoWorld.CELL * world.zoom * cells * 0.5)
	return Rect2i(Vector2i(c - Vector2(half, half)), Vector2i(int(half * 2), int(half * 2)))


func _rect_signature(img: Image, r: Rect2i) -> int:
	var sum := 0
	for y in range(maxi(0, r.position.y), mini(img.get_height(), r.end.y)):
		for x in range(maxi(0, r.position.x), mini(img.get_width(), r.end.x)):
			var c := img.get_pixel(x, y)
			sum += int(c.r * 255.0) + int(c.g * 255.0) * 257 + int(c.b * 255.0) * 66049
	return sum


func _find_water_and_land() -> Dictionary:
	var b := world.bounds
	var mid := Vector2(b.get_center())
	var shore_cells: Array = []
	for y in range(b.position.y + 4, b.end.y - 4):
		for x in range(b.position.x + 4, b.end.x - 4):
			var c := Vector2i(x, y)
			if world.terrain_type(c) != ProtoWorld.TER_WATER:
				continue

			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if world.terrain_type(c + d) != ProtoWorld.TER_WATER:
					shore_cells.append(c)
					break

	shore_cells.sort_custom(func(a, c): return (Vector2(a) - mid).length_squared() < (Vector2(c) - mid).length_squared())
	for c in shore_cells:
		var land := _near_cell(c, [ProtoWorld.TER_CLEAR, ProtoWorld.TER_ROAD, ProtoWorld.TER_ROCK], 1, 3, 6)
		if land == Vector2i(-1, -1):
			continue
		var open := _near_cell(c, [ProtoWorld.TER_WATER], 2, 3, 6)
		var out := {"shore": c, "land": land}
		if open != Vector2i(-1, -1):
			out["open"] = open
		return out
	return {}


func _near_cell(c: Vector2i, types: Array, r: int, dmin: int, dmax: int) -> Vector2i:
	for dy in range(-dmax, dmax + 1):
		for dx in range(-dmax, dmax + 1):
			if maxi(absi(dx), absi(dy)) < dmin:
				continue
			var t := c + Vector2i(dx, dy)
			if not world.bounds.has_point(t):
				continue
			if _all_cells(t, r, types):
				return t
	return Vector2i(-1, -1)


func _all_cells(c: Vector2i, r: int, types: Array) -> bool:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if not types.has(world.terrain_type(Vector2i(x, y))):
				return false
	return true


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
	var taps: int = GameSpeed.TIMESTEPS.size() - 1 - GameSpeed.DEFAULT_INDEX
	for _n in taps:
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

	var soll := 0.9 * 1000.0 / float(GameSpeed.TIMESTEPS[GameSpeed.index()])
	print("T: --test-speed-ui nach %dx Tipp auf Plus Index=%d (Knopf setzte %d) (%d ms) -> %.1f Ticks/s (%.2fs, %d Ticks) - erwartet >= %.0f - %s" % [
		taps, GameSpeed.index(), index_after_taps, GameSpeed.TIMESTEPS[GameSpeed.index()], rate1, dt1, dticks1,
		soll, "OK" if rate1 >= soll else "FEHLER"])
	get_tree().quit()


func _run_test_ai_start() -> void:
	while world == null or world.sim == null or world.map_data == null:
		await get_tree().process_frame
	var idx := _test_ai_start - 1
	var spawns: Array = world.map_data.spawns
	var fehler := 0
	if idx < 0 or idx >= spawns.size():
		print("T --test-ai-start: FEHLER — Startpunkt %d gibt es auf %s nicht (%d Startpunkte)" % [
			_test_ai_start, world.map_data.slug, spawns.size()])
		print("T --test-ai-start: 1 Befund(e) (Sollwert 0)")
		get_tree().quit()
		return
	var cell: Vector2i = spawns[idx]
	var ai_player: int = int(ProtoWorld.AI_PLAYER_INDICES[0])
	var mapped: int = int(world.player_map.get("Multi%d" % idx, -1))
	print("T --test-ai-start: Startpunkt %d (Zelle %d,%d) → Spieler %d (erwartet KI %d) — %s" % [
		_test_ai_start, cell.x, cell.y, mapped, ai_player, "OK" if mapped == ai_player else "FEHLER"])
	fehler += 0 if mapped == ai_player else 1

	var find_at := func(types: Array) -> Vector2i:
		for u in world.units:
			if u.alive and u.player == ai_player and u.type in types:
				return Vector2i(u.pos / ProtoWorld.CELL)
		return Vector2i(-1, -1)
	var mcv: Vector2i = find_at.call(["mcv", "fact"])
	print("T --test-ai-start: Start-Actor der KI auf Zelle %d,%d (erwartet %d,%d) — %s" % [
		mcv.x, mcv.y, cell.x, cell.y, "OK" if mcv == cell else "FEHLER"])
	fehler += 0 if mcv == cell else 1

	var fact := Vector2i(-1, -1)
	for _round in 60:
		for _t in 10:
			world.sim.step()
		await get_tree().process_frame
		fact = find_at.call(["fact"])
		if fact.x >= 0:
			break
	var nah: bool = fact.x >= 0 and absi(fact.x - cell.x) <= 2 and absi(fact.y - cell.y) <= 2
	print("T --test-ai-start: KI-Bauhof auf Zelle %d,%d (Startpunkt %d,%d, Abweichung ≤ 2 Zellen) — %s" % [
		fact.x, fact.y, cell.x, cell.y, "OK" if nah else "FEHLER"])
	fehler += 0 if nah else 1
	print("T --test-ai-start: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


func _run_test_ai_count() -> void:
	while world == null or world.sim == null or world.map_data == null:
		await get_tree().process_frame
	await get_tree().process_frame
	var wunsch := int(ProtoWorld.next_ai_players)
	var plaetze: int = world.map_data.spawns.size()
	var soll: int = clampi(wunsch, 0, maxi(mini(plaetze - 1, ProtoWorld.AI_PLAYER_INDICES.size()), 0))
	var fehler := 0
	var bestand: Array = []
	var bots: Array = []
	var kennt_bot: bool = world.sim.has_method("bot_enabled")
	for p in ProtoWorld.AI_PLAYER_INDICES:
		if int(world.sim.alive_count(p)) > 0:
			bestand.append(p)
		if kennt_bot and bool(world.sim.bot_enabled(p)):
			bots.append(p)
	print("T --test-ai-count: Karte %s — %d Startpunkte, gewünscht %d KI, Sollwert nach Deckelung %d" % [
		world.map_data.slug, plaetze, wunsch, soll])
	print("T --test-ai-count: Plätze mit Bestand %s (%d von %d) — %s" % [
		bestand, bestand.size(), soll, "OK" if bestand.size() == soll else "FEHLER"])
	fehler += 0 if bestand.size() == soll else 1
	if kennt_bot:
		print("T --test-ai-count: Plätze mit laufendem Bot %s (%d von %d) — %s" % [
			bots, bots.size(), soll, "OK" if bots.size() == soll else "FEHLER"])
		fehler += 0 if bots.size() == soll else 1
	else:
		print("T --test-ai-count: Brücke kennt `bot_enabled` nicht — Bot-Zahl nicht messbar")
	var zeilen := 0
	for e in world.player_roster:
		if str(e.get("kind", "human")) == "bot":
			zeilen += 1
	print("T --test-ai-count: Spielerliste %d Zeilen (davon %d KI, Sollwert %d) — %s" % [
		world.player_roster.size(), zeilen, soll, "OK" if zeilen == soll else "FEHLER"])
	fehler += 0 if zeilen == soll else 1


	var zellen := {}
	var doppelt := 0
	for name in world.player_map:
		var pid := int(world.player_map[name])
		if not ProtoWorld.AI_PLAYER_INDICES.has(pid) and pid != 0:
			continue
		if zellen.has(pid):
			doppelt += 1
		zellen[pid] = name
	print("T --test-ai-count: Startpunkt je Platz %s — %s" % [
		zellen, "OK" if doppelt == 0 else "FEHLER"])
	fehler += 0 if doppelt == 0 else 1

	for _round in 60:
		for _t in 10:
			world.sim.step()
		await get_tree().process_frame
	var mit_fact := {}
	for u in world.units:
		if u.alive and u.type == "fact" and ProtoWorld.AI_PLAYER_INDICES.has(int(u.player)):
			mit_fact[int(u.player)] = true
	print("T --test-ai-count: KI mit Bauhof nach 600 Ticks %s (%d von %d) — %s" % [
		mit_fact.keys(), mit_fact.size(), soll, "OK" if mit_fact.size() == soll else "FEHLER"])
	fehler += 0 if mit_fact.size() == soll else 1


	NetHub.hub().ensure_voice()
	_open_player_list()
	for _i in 3:
		await get_tree().process_frame
	var ui_rows: int = _player_list_rows().size()
	print("T --test-ai-count: Spielerliste im Pausenmenü %d Zeilen (Sollwert %d) — %s" % [
		ui_rows, soll + 1, "OK" if ui_rows == soll + 1 else "FEHLER"])
	fehler += 0 if ui_rows == soll + 1 else 1

	var panel := $UI.get_node_or_null("PlayerList")
	var funk: bool = panel != null and _findet_beschriftung(panel, tr("mp.voice_intro_again"))
	print("T --test-ai-count: Sprechfunk-Angabe in der Liste: %s (Sollwert false) — %s" % [
		funk, "FEHLER" if funk else "OK"])
	fehler += 1 if funk else 0
	_close_modals()
	print("T --test-ai-count: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


func _run_test_keys() -> void:
	while world.sim == null:
		await get_tree().process_frame
	for _n in 30:
		await get_tree().process_frame
	var fehler := 0
	var press := func(code: int, ctrl: bool) -> void:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code
			ev.physical_keycode = code
			ev.pressed = pressed
			ev.ctrl_pressed = ctrl
			Input.parse_input_event(ev)
			await get_tree().process_frame
			await get_tree().process_frame


	await press.call(KEY_ESCAPE, false)
	var auf := _menu_panel.visible
	await press.call(KEY_ESCAPE, false)
	var zu := not _menu_panel.visible
	fehler += 0 if (auf and zu) else 1
	print("T: --test-keys Escape - Pausenmenue auf %s, wieder zu %s - %s" % [
		auf, zu, "OK" if (auf and zu) else "FEHLER"])


	var n_all := world.select_all_units()
	await press.call(KEY_1, true)
	var n_group: int = groups.groups[0].size()
	world.select_units([])
	await press.call(KEY_1, false)
	var n_back: int = world.selection.size()
	var gruppe_ok := n_group > 0 and n_back == n_group
	fehler += 0 if gruppe_ok else 1
	print("T: --test-keys Ziffern - %d Einheiten gewaehlt, Strg+1 wies %d zu, 1 holte %d zurueck - %s" % [
		n_all, n_group, n_back, "OK" if gruppe_ok else "FEHLER"])


	if DisplayServer.get_name() == "headless":
		print("T: --test-keys F11 - headless, uebersprungen")
	else:
		var vorher := Desktop.fullscreen()
		await press.call(KEY_F11, false)
		var gewechselt := Desktop.fullscreen() != vorher
		await press.call(KEY_F11, false)
		var zurueck := Desktop.fullscreen() == vorher
		fehler += 0 if (gewechselt and zurueck) else 1
		print("T: --test-keys F11 - gewechselt %s, zurueck %s - %s" % [
			gewechselt, zurueck, "OK" if (gewechselt and zurueck) else "FEHLER"])
	print("T: --test-keys Ende: %d Fehler" % fehler)
	get_tree().quit()


func _run_test_desktop_scroll() -> void:
	while world.sim == null:
		await get_tree().process_frame
	for _n in 30:
		await get_tree().process_frame
	var fehler := 0
	var vs := get_viewport().get_visible_rect().size

	var mid := Vector2(world.bounds.position + world.bounds.size / 2) * ProtoWorld.CELL
	var cam := func() -> Vector2: return world.visible_world_rect().get_center()
	var reset := func() -> void:
		world.center_on(mid)
		world.end_camera_gesture(Vector2.ZERO)
		await get_tree().process_frame
	var pruefe := func(name: String, vorher: Vector2, nachher: Vector2, soll: Vector2) -> int:
		var d := nachher - vorher

		var ok := true
		for a in 2:
			if soll[a] == 0.0:
				ok = ok and absf(d[a]) < 1.0
			else:
				ok = ok and signf(d[a]) == soll[a] and absf(d[a]) > 1.0
		print("T: --test-desktop-scroll %s - Kamera %s -> %s (d=%s, erwartet %s) - %s" % [
			name, vorher.round(), nachher.round(), d.round(), soll, "OK" if ok else "FEHLER"])
		return 0 if ok else 1


	var rand := func(p: Vector2, frames: int) -> void:
		_scroller.probe = p
		_scroller.probe_on = true
		for _n in frames:
			await get_tree().process_frame
		_scroller.probe_on = false


	if _screenshot_path != "":
		await RenderingServer.frame_post_draw
		_shot("scroll_vorher")
		await rand.call(Vector2(vs.x - 2.0, vs.y / 2.0), 40)
		await RenderingServer.frame_post_draw
		_shot("scroll_nachher")


	await reset.call()
	var a0: Vector2 = cam.call()
	for _n in 3:
		var pg := InputEventPanGesture.new()
		pg.position = vs / 2.0
		pg.delta = Vector2(40.0, 30.0)
		get_viewport().push_input(pg)
		await get_tree().process_frame
	fehler += pruefe.call("Touchpad-Wisch (delta +40/+30)", a0, cam.call(), Vector2(1, 1))

	await reset.call()
	a0 = cam.call()
	for _n in 3:
		var pg2 := InputEventPanGesture.new()
		pg2.position = vs / 2.0
		pg2.delta = Vector2(-40.0, -30.0)
		get_viewport().push_input(pg2)
		await get_tree().process_frame
	fehler += pruefe.call("Touchpad-Wisch (delta -40/-30)", a0, cam.call(), Vector2(-1, -1))


	var rad := func(btn: int, ctrl: bool, at: Vector2) -> void:
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = btn
			mb.pressed = pressed
			mb.factor = 1.0
			mb.position = at
			mb.ctrl_pressed = ctrl
			Input.parse_input_event(mb)
			await get_tree().process_frame
	for fall in [[MOUSE_BUTTON_WHEEL_UP, "Rad hoch", Vector2(0, -1)],
			[MOUSE_BUTTON_WHEEL_DOWN, "Rad runter", Vector2(0, 1)],
			[MOUSE_BUTTON_WHEEL_LEFT, "Rad links", Vector2(-1, 0)],
			[MOUSE_BUTTON_WHEEL_RIGHT, "Rad rechts", Vector2(1, 0)]]:
		await reset.call()
		a0 = cam.call()
		for _n in 3:
			await rad.call(fall[0], false, vs / 2.0)
		fehler += pruefe.call(fall[1], a0, cam.call(), fall[2])


	await reset.call()
	var zeiger := Vector2(vs.x * 0.25, vs.y * 0.75)
	var welt_vorher := world.screen_to_world(zeiger)
	var z0 := world.zoom
	await rad.call(MOUSE_BUTTON_WHEEL_UP, true, zeiger)
	await get_tree().process_frame
	var welt_nachher := world.screen_to_world(zeiger)
	var haftet := welt_vorher.distance_to(welt_nachher) < 1.0
	var groesser := world.zoom > z0 + 0.001
	fehler += 0 if (haftet and groesser) else 1
	print("T: --test-desktop-scroll Strg+Rad hoch - Zoom %.3f -> %.3f, Weltpunkt unter dem Zeiger wandert %.2f px - %s" % [
		z0, world.zoom, welt_vorher.distance_to(welt_nachher), "OK" if (haftet and groesser) else "FEHLER"])
	z0 = world.zoom
	await rad.call(MOUSE_BUTTON_WHEEL_DOWN, true, zeiger)
	await get_tree().process_frame
	var kleiner := world.zoom < z0 - 0.001
	fehler += 0 if kleiner else 1
	print("T: --test-desktop-scroll Strg+Rad runter - Zoom %.3f -> %.3f - %s" % [
		z0, world.zoom, "OK" if kleiner else "FEHLER"])


	z0 = world.zoom
	var mg := InputEventMagnifyGesture.new()
	mg.position = vs / 2.0
	mg.factor = 1.15
	get_viewport().push_input(mg)
	await get_tree().process_frame
	var lupe_ok := world.zoom > z0 + 0.001
	fehler += 0 if lupe_ok else 1
	print("T: --test-desktop-scroll Aufziehen (Faktor 1,15) - Zoom %.3f -> %.3f - %s" % [
		z0, world.zoom, "OK" if lupe_ok else "FEHLER"])
	world.zoom_at(3.0 / world.zoom, vs / 2.0)


	for fall2 in [[Vector2(2.0, vs.y / 2.0), "Rand links", Vector2(-1, 0)],
			[Vector2(vs.x - 2.0, vs.y / 2.0), "Rand rechts", Vector2(1, 0)],
			[Vector2(vs.x / 2.0, 2.0), "Rand oben", Vector2(0, -1)],
			[Vector2(vs.x / 2.0, vs.y - 2.0), "Rand unten", Vector2(0, 1)],
			[Vector2(2.0, 2.0), "Ecke oben links", Vector2(-1, -1)],
			[Vector2(vs.x - 2.0, vs.y - 2.0), "Ecke unten rechts", Vector2(1, 1)],
			[vs / 2.0, "Mitte (kein Rand)", Vector2(0, 0)]]:
		await reset.call()
		a0 = cam.call()
		await rand.call(fall2[0], 20)
		fehler += pruefe.call(fall2[1], a0, cam.call(), fall2[2])


	await reset.call()
	var t0 := Time.get_ticks_msec()
	var vor_t: Vector2 = cam.call()
	await rand.call(Vector2(vs.x - 2.0, vs.y / 2.0), 30)
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	var strecke: float = absf(cam.call().x - vor_t.x) * world.zoom
	var soll_px := vs.x / Desktop.Scroller.EDGE_SECONDS * dt
	var tempo_ok: bool = soll_px <= 0.0 or absf(strecke - soll_px) < soll_px * 0.35 + 8.0
	fehler += 0 if tempo_ok else 1
	print("T: --test-desktop-scroll Tempo - %.0f Bildschirmpixel in %.2f s (Soll %.0f, %.0f px/s) - %s" % [
		strecke, dt, soll_px, vs.x / Desktop.Scroller.EDGE_SECONDS, "OK" if tempo_ok else "FEHLER"])


	await reset.call()
	var mini := minimap.get_global_rect()
	var unter_mini := Vector2(mini.position.x + mini.size.x * 0.5, vs.y - 1.0)
	a0 = cam.call()
	await rand.call(unter_mini, 20)
	fehler += pruefe.call("Fensterkante unter der Minimap", a0, cam.call(), Vector2(0, 1))

	var strip := Dp.px(Desktop.Scroller.EDGE_DP)
	var im_streifen: Array = []
	for c in $UI.get_children():
		if c is Control and c.visible and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 0.0 and (r.position.x < strip or r.position.y < strip
					or r.end.x > vs.x - strip or r.end.y > vs.y - strip):
				im_streifen.append(c.name)
	print("T: --test-desktop-scroll Randstreifen %.0f px - HUD-Flaechen darin: %s" % [
		strip, "keine" if im_streifen.is_empty() else ", ".join(im_streifen)])


	var taste := func(code: int, down: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().process_frame

	for fall3 in [[KEY_RIGHT, "Pfeil rechts", Vector2(1, 0)], [KEY_UP, "Pfeil hoch", Vector2(0, -1)],
			[KEY_LEFT, "Pfeil links", Vector2(-1, 0)], [KEY_DOWN, "Pfeil runter", Vector2(0, 1)]]:
		await reset.call()
		a0 = cam.call()
		await taste.call(fall3[0], true)
		for _n in 12:
			await get_tree().process_frame
		await taste.call(fall3[0], false)
		fehler += pruefe.call(fall3[1], a0, cam.call(), fall3[2])


	var halten := func(code: int, down: bool, shift: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		ev.shift_pressed = shift
		Input.parse_input_event(ev)
		await get_tree().process_frame
	var wasd := func(code: int, name2: String, soll: Vector2, shift: bool) -> int:
		await reset.call()
		var vor: Vector2 = cam.call()
		if shift:
			await halten.call(KEY_SHIFT, true, true)
		await halten.call(code, true, shift)
		for _n in 12:
			await get_tree().process_frame
		await halten.call(code, false, shift)
		if shift:
			await halten.call(KEY_SHIFT, false, false)
		return pruefe.call(name2, vor, cam.call(), soll)

	var vier: Array = [[KEY_D, Vector2(1, 0), "D"], [KEY_W, Vector2(0, -1), "W"],
			[KEY_A, Vector2(-1, 0), "A"], [KEY_S, Vector2(0, 1), "S"]]
	world.select_units([])
	_end_click_mode()
	await get_tree().process_frame
	for fall4 in vier:
		fehler += await wasd.call(fall4[0], "%s ohne Auswahl" % fall4[2], fall4[1], false)
	var kein_modus0: bool = _click_mode == "" and _order_mode == "" and _confirm_mode == ""
	fehler += 0 if kein_modus0 else 1
	print("T: --test-desktop-scroll WASD ohne Auswahl oeffnet keinen Modus - click_mode='%s' order_mode='%s' - %s" % [
		_click_mode, _order_mode, "OK" if kein_modus0 else "FEHLER"])


	world.select_all_units()
	await get_tree().process_frame
	for fall5 in vier:
		fehler += await wasd.call(fall5[0], "%s mit Auswahl" % fall5[2], fall5[1], false)

	for fall6 in vier:
		fehler += await wasd.call(fall6[0], "Umschalt+%s mit Auswahl" % fall6[2], fall6[1], true)
	var kein_modus: bool = _click_mode == "" and _order_mode == "" and _confirm_mode == ""
	fehler += 0 if kein_modus else 1
	print("T: --test-desktop-scroll WASD mit Auswahl oeffnet keinen Modus - click_mode='%s' order_mode='%s' confirm_mode='%s' - %s" % [
		_click_mode, _order_mode, _confirm_mode, "OK" if kein_modus else "FEHLER"])
	_end_placement("")
	_end_click_mode()
	world.select_units([])
	await get_tree().process_frame


	await reset.call()
	var zeile := LineEdit.new()
	$UI.add_child(zeile)
	zeile.grab_focus()
	for _n in 10:
		await get_tree().process_frame
	a0 = cam.call()
	await taste.call(KEY_RIGHT, true)
	for _n in 12:
		await get_tree().process_frame
	await taste.call(KEY_RIGHT, false)
	var chat_ok: bool = cam.call().distance_to(a0) < 1.0
	fehler += 0 if chat_ok else 1
	print("T: --test-desktop-scroll Eingabezeile im Fokus - Pfeil rechts bewegt die Karte nicht: %s (Weg %.2f px, Richtung=%s) - %s" % [
		chat_ok, cam.call().distance_to(a0), _scroller.key_direction(), "OK" if chat_ok else "FEHLER"])
	zeile.queue_free()
	await get_tree().process_frame


	await reset.call()
	_toggle_menu(true)
	await get_tree().process_frame
	a0 = cam.call()
	for _n in 3:
		await rad.call(MOUSE_BUTTON_WHEEL_DOWN, false, vs / 2.0)
	await rand.call(Vector2(vs.x - 2.0, vs.y / 2.0), 20)
	var menue_ok: bool = cam.call().distance_to(a0) < 1.0
	fehler += 0 if menue_ok else 1
	print("T: --test-desktop-scroll Pausenmenue offen - Kamera ruhig: %s - %s" % [
		menue_ok, "OK" if menue_ok else "FEHLER"])
	_toggle_menu(false)
	await get_tree().process_frame


	var half := get_viewport().get_visible_rect().size / world.zoom / 2.0
	var area := Rect2(Vector2(world.bounds.position) * ProtoWorld.CELL, Vector2(world.bounds.size) * ProtoWorld.CELL)
	var soll_ecke := area.position + half


	world.center_on(soll_ecke + Vector2(2.0, 2.0))
	world.end_camera_gesture(Vector2.ZERO)
	await get_tree().process_frame
	await rand.call(Vector2(2.0, 2.0), 60)
	var links_oben: Vector2 = cam.call()
	var geklemmt := links_oben.distance_to(soll_ecke) < 2.0
	fehler += 0 if geklemmt else 1
	print("T: --test-desktop-scroll Kartenrand - Kamera %s, Schranke %s - %s" % [
		links_oben.round(), soll_ecke.round(), "OK" if geklemmt else "FEHLER"])


	_place_test_fact()
	await get_tree().process_frame
	var bid: int = world.type_ids.get("powr", -1)
	if bid < 0:
		print("T: --test-desktop-scroll Platzierung - kein 'powr' in den Regeln, uebersprungen")
	else:
		await reset.call()
		_begin_placement(bid)
		world.move_placement(cam.call())
		await get_tree().process_frame
		var geist0: Vector2i = world.place_origin
		var laeuft0: int = world.placing_type
		a0 = cam.call()
		await taste.call(KEY_RIGHT, true)
		for _n in 12:
			await get_tree().process_frame
		await taste.call(KEY_RIGHT, false)
		fehler += pruefe.call("Platzierung: Pfeil rechts", a0, cam.call(), Vector2(1, 0))
		a0 = cam.call()
		fehler += await wasd.call(KEY_W, "Platzierung: W", Vector2(0, -1), false)
		await reset.call()
		world.move_placement(cam.call())
		await get_tree().process_frame
		geist0 = world.place_origin
		a0 = cam.call()
		await rand.call(Vector2(vs.x - 2.0, vs.y / 2.0), 20)
		fehler += pruefe.call("Platzierung: Randscrollen rechts", a0, cam.call(), Vector2(1, 0))
		a0 = cam.call()
		for _n in 3:
			var pg3 := InputEventPanGesture.new()
			pg3.position = vs / 2.0
			pg3.delta = Vector2(40.0, 30.0)
			get_viewport().push_input(pg3)
			await get_tree().process_frame
		fehler += pruefe.call("Platzierung: Touchpad-Wisch", a0, cam.call(), Vector2(1, 1))
		var z1 := world.zoom
		await rad.call(MOUSE_BUTTON_WHEEL_UP, true, vs / 2.0)
		await get_tree().process_frame
		var zoom_ok := world.zoom > z1 + 0.001
		fehler += 0 if zoom_ok else 1
		print("T: --test-desktop-scroll Platzierung: Strg+Rad zoomt - %.3f -> %.3f - %s" % [
			z1, world.zoom, "OK" if zoom_ok else "FEHLER"])
		var haelt: bool = world.placing_type == laeuft0 and world.place_origin == geist0
		fehler += 0 if haelt else 1
		print("T: --test-desktop-scroll Platzierung: Geistbild bleibt auf seiner Zelle %s (vorher %s), placing_type=%d - %s" % [
			world.place_origin, geist0, world.placing_type, "OK" if haelt else "FEHLER"])


		await taste.call(KEY_T, true)
		await taste.call(KEY_T, false)
		var gesperrt: bool = _order_mode == "" and world.placing_type == laeuft0
		fehler += 0 if gesperrt else 1
		print("T: --test-desktop-scroll Platzierung: T befiehlt nicht - order_mode='%s' placing_type=%d - %s" % [
			_order_mode, world.placing_type, "OK" if gesperrt else "FEHLER"])
		world.cancel_placement()
		_end_placement("")
		await get_tree().process_frame

	print("T: --test-desktop-scroll Ende: %d Fehler" % fehler)
	get_tree().quit()


func _run_test_desktop_input() -> void:
	while world.sim == null:
		await get_tree().process_frame
	for _n in 30:
		await get_tree().process_frame
	var fehler := 0
	var sagen := func(name: String, ok: bool, mehr: String = "") -> void:
		print("T: --test-desktop-input %s%s - %s" % [name, mehr, "OK" if ok else "FEHLER"])
	var taste := func(code: int) -> void:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code
			ev.physical_keycode = code
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await get_tree().process_frame
			await get_tree().process_frame


	var belegt := {}
	var doppelt: Array = []
	for row in Desktop.KEYS:
		for code in row["keys"]:
			if belegt.has(code):
				doppelt.append("%s/%s" % [belegt[code], row["id"]])
			belegt[code] = row["id"]
	var tabelle_ok: bool = doppelt.is_empty() and belegt.size() > 0
	fehler += 0 if tabelle_ok else 1
	sagen.call("Tabelle", tabelle_ok, " - %d Tasten, %d Zeilen, Doppelbelegung: %s" % [
		belegt.size(), Desktop.KEYS.size(), "keine" if doppelt.is_empty() else ", ".join(doppelt)])

	var ohne_text: Array = []
	for r in Desktop.key_rows():
		if String(r[1]).begins_with("keys."):
			ohne_text.append(r[1])
	fehler += 0 if ohne_text.is_empty() else 1
	sagen.call("Hilfetexte", ohne_text.is_empty(), " - ohne Uebersetzung: %s" % [
		"keine" if ohne_text.is_empty() else ", ".join(ohne_text)])


	for fall in [[KEY_R, "repair", "R"], [KEY_V, "sell", "V"]]:
		await taste.call(fall[0])
		var an: bool = _click_mode == fall[1] and _cmd_buttons[fall[1]].button_pressed
		await taste.call(fall[0])
		var aus: bool = _click_mode == ""
		fehler += 0 if (an and aus) else 1
		sagen.call("Taste %s" % fall[2], an and aus, " - Modus '%s' an %s, wieder aus %s" % [fall[1], an, aus])


	world.clear_selection()
	await taste.call(KEY_T)
	var leer_ok: bool = _order_mode == ""
	fehler += 0 if leer_ok else 1
	sagen.call("Taste T ohne Auswahl", leer_ok, " - kein Zielwahl-Modus: %s" % leer_ok)
	var n_all := world.select_all_units()
	for fall2 in [[KEY_T, "attack_move", "T"], [KEY_G, "guard", "G"]]:
		await taste.call(fall2[0])
		var gesetzt: bool = _order_mode == fall2[1]
		await taste.call(KEY_ESCAPE)
		var weg: bool = _order_mode == ""
		fehler += 0 if (gesetzt and weg) else 1
		sagen.call("Taste %s" % fall2[2], gesetzt and weg, " - Zielwahl '%s' an %s, Escape raeumt auf %s" % [
			fall2[1], gesetzt, weg])

	for code2 in [KEY_E, KEY_X, KEY_F]:
		await taste.call(code2)
	var sofort_ok: bool = _order_mode == "" and _confirm_mode == ""
	fehler += 0 if sofort_ok else 1
	sagen.call("Tasten E/X/F", sofort_ok, " - kein Modus haengengeblieben: %s" % sofort_ok)


	world.clear_selection()
	await taste.call(KEY_Q)
	var q_ok: bool = world.selection.size() == n_all and n_all > 0
	fehler += 0 if q_ok else 1
	sagen.call("Taste Q", q_ok, " - %d von %d Einheiten gewaehlt" % [world.selection.size(), n_all])
	await taste.call(KEY_ESCAPE)
	var esc_ok: bool = world.selection.is_empty() and not _menu_panel.visible
	fehler += 0 if esc_ok else 1
	sagen.call("Escape mit Auswahl", esc_ok, " - Auswahl leer %s, Pausenmenue zu %s" % [
		world.selection.is_empty(), not _menu_panel.visible])


	var z0 := world.zoom
	await taste.call(KEY_PLUS)
	var naeher: bool = world.zoom > z0 + 0.001
	await taste.call(KEY_MINUS)
	await taste.call(KEY_MINUS)
	var weiter: bool = world.zoom < z0 - 0.001
	await taste.call(KEY_PERIOD)
	var zurueck: bool = absf(world.zoom - 3.0) < 0.01
	fehler += 0 if (naeher and weiter and zurueck) else 1
	sagen.call("Zoom + / − / .", naeher and weiter and zurueck,
		" - naeher %s, weiter %s, zurueck auf %.2f %s" % [naeher, weiter, world.zoom, zurueck])


	var p_vorher := world.paused
	await taste.call(KEY_P)
	var p_an: bool = world.paused != p_vorher
	await taste.call(KEY_P)
	var p_aus: bool = world.paused == p_vorher
	fehler += 0 if (p_an and p_aus) else 1
	sagen.call("Taste P", p_an and p_aus, " - Pause an %s, wieder aus %s" % [p_an, p_aus])


	_test_origin = _place_test_fact()
	for _n in 20:
		await get_tree().process_frame


	var b_vorher := build_bar.visible
	await taste.call(KEY_B)
	var b_um: bool = build_bar.visible != b_vorher
	await taste.call(KEY_B)
	var b_zurueck: bool = build_bar.visible == b_vorher
	fehler += 0 if (b_um and b_zurueck) else 1
	sagen.call("Taste B", b_um and b_zurueck, " - Bauleiste umgeschaltet %s, zurueck %s" % [b_um, b_zurueck])
	build_bar.visible = true
	await get_tree().process_frame


	var reiter: Array = []
	for i in 6:
		await taste.call(KEY_F1 + i)
		reiter.append("%d:%d" % [i + 1, build_bar.kind])
	var f1_ok: bool = build_bar.kind >= 0
	await taste.call(KEY_F1)
	f1_ok = f1_ok and build_bar.kind == BuildBar.KIND_QUEUES[0]
	fehler += 0 if f1_ok else 1
	sagen.call("Tasten F1-F6", f1_ok, " - Reiter nach jedem Druck: %s, F1 landet auf Queue %d" % [
		", ".join(reiter), build_bar.kind])


	var vs := get_viewport().get_visible_rect().size
	var klick := func(btn: int, at: Vector2) -> void:
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = btn
			mb.pressed = pressed
			mb.position = at
			mb.global_position = at
			Input.parse_input_event(mb)
			await get_tree().process_frame
			await get_tree().process_frame
	var rechts := func(at: Vector2) -> void:
		await klick.call(MOUSE_BUTTON_RIGHT, at)
	var halten := func(code: int, pressed: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


	var stelle := func(ziel: Vector2) -> Vector2:
		var frei: Vector2 = vs * 0.5
		for k in [vs * 0.5, Vector2(vs.x * 0.5, vs.y * 0.35), Vector2(vs.x * 0.35, vs.y * 0.5),
				Vector2(vs.x * 0.6, vs.y * 0.4)]:
			if not _over_hud(k):
				frei = k
				break
		world.center_on(ziel + (vs * 0.5 - frei) / world.zoom)


		return vs * 0.5 + (ziel - world.visible_world_rect().get_center()) * world.zoom


	var dt_ms: int = gestures.double_tap_ms
	gestures.double_tap_ms = 0


	if _menu_panel != null and _menu_panel.visible:
		_toggle_menu(false)
	var ui_sichtbar: bool = $UI.visible
	$UI.visible = false
	await get_tree().process_frame

	var panzer = world.spawn_unit("2tnk", 0, _test_origin + Vector2i(6, 3))
	var kamerad = world.spawn_unit("e1", 0, _test_origin + Vector2i(9, 3))
	var gegner = world.spawn_unit("e1", 1, _test_origin + Vector2i(6, -7))
	world.sim.set_enemy(0, 1, true)
	world.sim.set_enemy(1, 0, true)
	world.sim.reveal(0, _test_origin.x + 6, _test_origin.y - 7, 10)
	for _n in 20:
		await get_tree().process_frame
	if panzer == null or kamerad == null or gegner == null:
		print("T: --test-desktop-input Maus - Aufbau unvollstaendig, uebersprungen")
	else:

		world.clear_selection()
		var p_panzer: Vector2 = stelle.call(panzer.pos)
		await klick.call(MOUSE_BUTTON_LEFT, p_panzer)
		var l_a: bool = world.selection.size() == 1 and world.selection[0].id == panzer.id
		fehler += 0 if l_a else 1
		sagen.call("Linksklick waehlt", l_a, " - Auswahl %d, Stelle %s (HUD frei %s)" % [
			world.selection.size(), p_panzer, not _over_hud(p_panzer)])


		var leer_pos: Vector2 = (Vector2(_test_origin) + Vector2(14.0, 10.0)) * ProtoWorld.CELL
		var p_leer: Vector2 = stelle.call(leer_pos)
		await klick.call(MOUSE_BUTTON_LEFT, p_leer)
		var l_b: bool = world.selection.is_empty() and not _menu_panel.visible
		fehler += 0 if l_b else 1
		sagen.call("Linksklick ins Leere", l_b, " - Auswahl leer %s, Pausenmenue zu %s" % [
			world.selection.is_empty(), not _menu_panel.visible])


		world.select_only(panzer)
		var p_ziel: Vector2 = stelle.call(leer_pos)
		await rechts.call(p_ziel)
		var l_c: bool = world.selection.size() == 1 and panzer.goal_kind == 0 \
			and panzer.goal.distance_to(leer_pos) < 3.0 * ProtoWorld.CELL
		fehler += 0 if l_c else 1
		sagen.call("Rechtsklick bewegt", l_c, " - Befehlsart %d (0=Bewegen), Ziel %.1f Zellen daneben, Auswahl %d" % [
			panzer.goal_kind, panzer.goal.distance_to(leer_pos) / ProtoWorld.CELL, world.selection.size()])


		world.select_only(panzer)
		var p_gegner: Vector2 = stelle.call(gegner.pos)
		await rechts.call(p_gegner)
		var l_d: bool = panzer.goal_kind == 2
		fehler += 0 if l_d else 1
		sagen.call("Rechtsklick greift an", l_d, " - Befehlsart %d (2=Angriff)" % panzer.goal_kind)


		world.select_only(panzer)
		var p_kamerad: Vector2 = stelle.call(kamerad.pos)
		await rechts.call(p_kamerad)
		var l_e: bool = panzer.goal_kind == 1 and world.selection.size() == 1 \
			and world.selection[0].id == panzer.id
		fehler += 0 if l_e else 1
		sagen.call("Rechtsklick bewacht", l_e, " - Befehlsart %d (1=Bewachen), Auswahl bleibt %s" % [
			panzer.goal_kind, world.selection.size() == 1 and world.selection[0].id == panzer.id])


		var mbf_setzen := func() -> ProtoWorld.Unit:
			var kandidaten: Array = []
			for dy in range(-20, 21, 4):
				for dx in range(-20, 21, 4):
					if absi(dx) >= 8 or absi(dy) >= 8:
						kandidaten.append(Vector2i(dx, dy))
			for off in kandidaten:
				var m = world.spawn_unit("mcv", 0, _test_origin + off)
				await get_tree().process_frame
				if m != null and world.sim.can_deploy(m.id):
					return m
				if m != null:
					world.sim.remove_actor(m.id)
					await get_tree().process_frame
			return null
		var mcv = await mbf_setzen.call()
		if mcv == null:
			fehler += 1
			sagen.call("Linksklick auf gewaehltes MBF klappt aus", false, " - keine freie Stelle gefunden")
		else:
			world.select_only(mcv)
			var facts0: int = _count_type("fact")
			await klick.call(MOUSE_BUTTON_LEFT, stelle.call(mcv.pos))
			var t_mcv: int = int(world.sim.tick())
			for _n in 3000:
				await get_tree().process_frame
				if _count_type("fact") > facts0 or int(world.sim.tick()) - t_mcv >= 200:
					break
			var l_e2: bool = _count_type("fact") == facts0 + 1
			fehler += 0 if l_e2 else 1
			sagen.call("Linksklick auf gewaehltes MBF klappt aus", l_e2, " - Bauhoefe %d -> %d" % [facts0, _count_type("fact")])
		var mcv2 = await mbf_setzen.call()
		if mcv2 == null:
			fehler += 1
			sagen.call("Rechtsklick auf gewaehltes MBF klappt aus", false, " - keine freie Stelle fuer das zweite MBF gefunden")
		else:
			world.select_only(mcv2)
			var facts1: int = _count_type("fact")
			await rechts.call(stelle.call(mcv2.pos))
			var t_mcv2: int = int(world.sim.tick())
			for _n in 3000:
				await get_tree().process_frame
				if _count_type("fact") > facts1 or int(world.sim.tick()) - t_mcv2 >= 200:
					break
			var l_e3: bool = _count_type("fact") == facts1 + 1
			fehler += 0 if l_e3 else 1
			sagen.call("Rechtsklick auf gewaehltes MBF klappt aus", l_e3, " - Bauhoefe %d -> %d" % [facts1, _count_type("fact")])


		world.select_only(panzer)
		var ziel_a: Vector2 = panzer.pos + Vector2(6.0, 0.0) * ProtoWorld.CELL
		var ziel_b: Vector2 = panzer.pos - Vector2(6.0, 0.0) * ProtoWorld.CELL
		var start_x: float = panzer.pos.x
		await rechts.call(stelle.call(ziel_a))
		await halten.call(KEY_SHIFT, true)
		await rechts.call(stelle.call(ziel_b))
		await halten.call(KEY_SHIFT, false)


		var tick0: int = int(world.sim.tick())
		for _n in 2000:
			await get_tree().process_frame
			if absf(panzer.pos.x - start_x) > 0.5 or int(world.sim.tick()) - tick0 >= 150:
				break
		var weg: float = panzer.pos.x - start_x
		var l_f: bool = weg > 0.5 and not world.queue_orders
		fehler += 0 if l_f else 1
		sagen.call("Umschalt+Rechtsklick haengt an", l_f, " - Weg %.1f px (>0 = erst zum ersten Ziel), Fahne zurueckgesetzt %s" % [
			weg, not world.queue_orders])


		world.select_only(panzer)
		panzer.goal_kind = 0
		var p_frei: Vector2 = stelle.call(kamerad.pos)
		await halten.call(KEY_CTRL, true)
		await rechts.call(p_frei)
		await halten.call(KEY_CTRL, false)
		var l_g: bool = panzer.goal_kind == 2
		fehler += 0 if l_g else 1
		sagen.call("Strg+Rechtsklick zwingt", l_g, " - Befehlsart %d (2=Angriff auf eigene Einheit)" % panzer.goal_kind)


		world.clear_selection()
		await rechts.call(stelle.call(leer_pos))
		var l_h: bool = world.selection.is_empty() and not _menu_panel.visible and _order_mode == ""
		fehler += 0 if l_h else 1
		sagen.call("Rechtsklick ohne Auswahl", l_h, " - nichts passiert: Pausenmenue zu %s, kein Modus %s" % [
			not _menu_panel.visible, _order_mode == ""])

	gestures.double_tap_ms = dt_ms
	$UI.visible = ui_sichtbar
	await get_tree().process_frame


	world.select_all_units()
	await taste.call(KEY_V)
	var v_an: bool = _click_mode == "sell"
	await taste.call(KEY_V)
	await taste.call(KEY_S)
	var s_leer: bool = _click_mode == "" and _order_mode == "" and _confirm_mode == ""
	fehler += 0 if (v_an and s_leer) else 1
	sagen.call("Tasten V / S", v_an and s_leer, " - V oeffnet den Verkauf %s, S oeffnet nichts %s" % [v_an, s_leer])

	var mitte: Vector2 = (Vector2(_test_origin) + Vector2(8.0, 8.0)) * ProtoWorld.CELL
	var wasd_fehler: Array = []
	for fall3 in [[KEY_W, Vector2(0.0, -1.0), "W"], [KEY_S, Vector2(0.0, 1.0), "S"],
			[KEY_A, Vector2(-1.0, 0.0), "A"], [KEY_D, Vector2(1.0, 0.0), "D"]]:
		world.center_on(mitte)
		await get_tree().process_frame
		var vorher3: Vector2 = world.visible_world_rect().get_center()
		await halten.call(fall3[0], true)
		for _n in 8:
			await get_tree().process_frame
		await halten.call(fall3[0], false)
		var d3: Vector2 = world.visible_world_rect().get_center() - vorher3
		if d3.dot(fall3[1]) <= 0.5:
			wasd_fehler.append("%s (%s)" % [fall3[2], d3])
	var wasd_ok: bool = wasd_fehler.is_empty() and world.selection.size() > 0 and _click_mode == ""
	fehler += 0 if wasd_ok else 1
	sagen.call("W A S D mit voller Auswahl", wasd_ok, " - %d Einheiten gewaehlt, kein Modus offen %s, ohne Wirkung: %s" % [
		world.selection.size(), _click_mode == "", "keine" if wasd_fehler.is_empty() else ", ".join(wasd_fehler)])


	var bar_mitte := build_bar.get_global_rect().get_center()
	var kamera_vorher := world.visible_world_rect().get_center()
	var rollbar: bool = build_bar.scroll_room() > 1.0
	var scroll0 := build_bar.scroll_value()
	for _n in 4:
		var pg := InputEventPanGesture.new()
		pg.position = bar_mitte
		pg.delta = Vector2(0.0, 30.0)
		get_viewport().push_input(pg)
		await get_tree().process_frame
	var gerollt: bool = build_bar.scroll_value() > scroll0 + 0.5
	var karte_ruhig: bool = world.visible_world_rect().get_center().distance_to(kamera_vorher) < 1.0
	var wisch_ok: bool = karte_ruhig and (gerollt or not rollbar)
	fehler += 0 if wisch_ok else 1
	sagen.call("Bauleiste: Touchpad-Wisch", wisch_ok, " - Rollweg %.0f px, gerollt %s (rollbar %s), Karte ruhig %s" % [
		build_bar.scroll_room(), gerollt, rollbar, karte_ruhig])
	var scroll1 := build_bar.scroll_value()
	var rad := func(btn: int, at: Vector2) -> void:
		for pressed in [true, false]:
			var mb2 := InputEventMouseButton.new()
			mb2.button_index = btn
			mb2.pressed = pressed
			mb2.factor = 1.0
			mb2.position = at
			mb2.global_position = at
			Input.parse_input_event(mb2)
			await get_tree().process_frame
	await rad.call(MOUSE_BUTTON_WHEEL_UP, bar_mitte)
	var rad_ok: bool = build_bar.scroll_value() < scroll1 - 0.5 or not rollbar
	fehler += 0 if rad_ok else 1
	sagen.call("Bauleiste: Mausrad", rad_ok, " - %.0f -> %.0f" % [scroll1, build_bar.scroll_value()])


	var powr: int = world.type_ids.get("powr", -1)
	if powr < 0:
		print("T: --test-desktop-input Bauleisten-Rechtsklick - kein 'powr' in den Regeln, uebersprungen")
	else:
		build_bar.select_queue(0)
		world.queue_build(powr)
		world.queue_build(powr)
		for _n in 60:
			await get_tree().process_frame
		var r_slot := build_bar.slot_rect_for("powr")
		if r_slot.size.x <= 0.0:
			print("T: --test-desktop-input Bauleisten-Rechtsklick - Cameo nicht sichtbar, uebersprungen")
		else:
			var anzahl0 := build_bar.slot_count("powr")
			await rechts.call(r_slot.get_center())
			for _n in 10:
				await get_tree().process_frame
			var haelt: bool = build_bar.slot_paused("powr")
			await rechts.call(r_slot.get_center())
			for _n in 10:
				await get_tree().process_frame
			var anzahl1 := build_bar.slot_count("powr")
			var weniger: bool = anzahl1 < anzahl0
			fehler += 0 if (haelt and weniger) else 1
			sagen.call("Bauleiste: Rechtsklick", haelt and weniger,
				" - 1. Klick haelt an %s, 2. Klick bricht ab (%d -> %d Auftraege)" % [haelt, anzahl0, anzahl1])

	print("T: --test-desktop-input Ende: %d Fehler" % fehler)
	get_tree().quit()


const HIT_PROFILES := [
	["Xperia", 2560, 1096, 420],
	["iPhone", 2556, 1179, 460],
	["iPad", 2360, 1640, 264],
]

const HIT_PROBE_DP := 2.0

var _test_hit := false
var _hit_last := ""


func _run_test_hit() -> void:
	if _resizer != null:
		_resizer.paused = true


	gestures.set_process_unhandled_input(false)
	gestures.set_process(false)

	var base := Vector2i(20, 20)
	for u in world.units:
		if u.alive and u.player == 0:
			base = Vector2i(u.pos / ProtoWorld.CELL)
			break
	world.sim.give_credits(0, 50000)
	var i := 0
	for t in ["fact", "powr", "proc", "tent", "weap", "dome", "mslo", "iron", "pdox", "atek"]:
		if world.type_ids.has(t):
			world.call("_add_building", t, 0, base + Vector2i(-8 + (i % 4) * 4, -8 + (i / 4) * 4))
			i += 1
	for _t in 60:
		world.sim.step()
	build_bar.visible = true
	await get_tree().process_frame
	var muted := _hit_mute()
	var toggles := {}
	for id in _cmd_buttons:
		toggles[_cmd_buttons[id]] = _cmd_buttons[id].button_pressed
	toggles[build_toggle] = build_toggle.button_pressed
	var total_fail := 0
	for prof in HIT_PROFILES:
		DisplayServer.window_set_size(Vector2i(prof[1], prof[2]))


		var last := Vector2i.ZERO
		var stable := 0
		for _f in 120:
			await get_tree().process_frame
			var now := DisplayServer.window_get_size()
			stable = stable + 1 if now == last else 0
			last = now
			if stable >= 10:
				break
		Dp.invalidate()
		Dp.set_forced_dpi(float(prof[3]))
		Dp.set_ui_scale(1.0)
		_layout_ui()
		for _f in 30:
			await get_tree().process_frame
		_layout_ui()
		var real := DisplayServer.window_get_size()
		total_fail += await _hit_profile("%s %dx%d@%d" % [prof[0], real.x, real.y, prof[3]])
		for b in toggles:
			b.set_pressed_no_signal(toggles[b])
	_hit_unmute(muted)
	print("T: --test-hit fertig — %d Fehlschläge" % total_fail)
	get_tree().quit()


func _hit_targets() -> Array:
	var out: Array = []
	_collect_buttons($UI, out)
	for i in ControlGroups.SLOTS:
		if not groups.is_visible_in_tree():
			break
		var r := Rect2(groups.global_position + Vector2(0, i * groups.step),
				Vector2(groups.size.x, groups.step))
		out.append({"name": "Gruppe %d" % (i + 1), "rect": r,
			"vis": Rect2(r.position + groups.get_meta("hit_pad", Vector2.ZERO),
				r.size - groups.get_meta("hit_pad", Vector2.ZERO) * 2.0), "group": i})
	return out


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).is_visible_in_tree():
		return
	if n is Button and (n as Button).size.x > 1.0 and (n as Button).size.y > 1.0:
		var b: Button = n
		out.append({"name": _hit_name(b), "rect": b.get_global_rect(),
			"vis": HudTheme.visible_rect(b), "node": b})
	for c in n.get_children():
		_collect_buttons(c, out)


func _hit_name(b: Button) -> String:
	for id in _cmd_buttons:
		if _cmd_buttons[id] == b:
			return "Knopfleiste " + str(id)
	for i in build_bar._tabs.size():
		if build_bar._tabs[i] == b:
			return "Reiter " + tr(BuildBar.KIND_KEYS[i])
	if b == build_toggle:
		return "Bau-Knopf"
	if b == music_toggle:
		return "Musik"
	if b == _menu_button:
		return "Menü"
	return b.name


func _hit_topmost(p: Vector2) -> String:
	var best := "—"
	var stack: Array = [$UI]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is Control:
			var c2: Control = n
			if c2.is_visible_in_tree() and c2.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c2.get_global_rect().has_point(p):
				best = "%s (%s)" % [c2.name, c2.get_class()]
	return best


func _hit_profile(label: String) -> int:
	var targets := _hit_targets()
	var d := Dp.device_px(HIT_PROBE_DP)
	var win := Rect2(Vector2.ZERO, Vector2(DisplayServer.window_get_size()))
	var inside_ok := 0
	var inside_total := 0
	var outside_ok := 0
	var outside_total := 0
	var smallest := Vector2(1e9, 1e9)
	var smallest_name := ""
	var fails: Array = []

	var conns: Array = []
	for t in targets:
		if t.has("node"):
			var b: Button = t["node"]
			var name: String = t["name"]
			var cb := func(): _hit_last = name
			b.button_down.connect(cb)
			conns.append([b, cb])
	for t in targets:


		if t.has("node"):
			var node: Control = t["node"]
			if not node.is_visible_in_tree():
				continue
			t["rect"] = node.get_global_rect()
			t["vis"] = HudTheme.visible_rect(node)
		var r: Rect2 = t["rect"]
		var dev := Vector2(Dp.to_device_dp(r.size.x), Dp.to_device_dp(r.size.y))
		if minf(dev.x, dev.y) < minf(smallest.x, smallest.y):
			smallest = dev
			smallest_name = t["name"]

		for probe in range(8):


			if t.has("node"):
				var nd: Control = t["node"]
				if not nd.is_visible_in_tree():
					break
				r = nd.get_global_rect()
			var c := r.get_center()
			var edge := probe / 2
			var want: bool = probe % 2 == 0
			var off_in := d if want else -d
			var p := Vector2.ZERO
			match edge:
				0: p = Vector2(r.position.x + off_in, c.y)
				1: p = Vector2(r.end.x - off_in, c.y)
				2: p = Vector2(c.x, r.position.y + off_in)
				3: p = Vector2(c.x, r.end.y - off_in)
			if not win.has_point(p):
				continue
			var got: bool = await _hit_probe(p, t)
			if want:
				inside_total += 1
				if got:
					inside_ok += 1
				else:
					fails.append("%s: innen %s löst nicht aus (zuletzt: %s, oben liegt: %s)" % [t["name"], p, _hit_last, _hit_topmost(p)])
			else:
				outside_total += 1
				if not got:
					outside_ok += 1
				else:
					fails.append("%s: außen %s löst trotzdem aus" % [t["name"], p])
	for c2 in conns:
		c2[0].button_down.disconnect(c2[1])
	for line in fails:
		print("T --test-hit %s: %s" % [label, line])
	if _diag:

		for t in targets:
			var rr: Rect2 = t["rect"]
			var vv: Rect2 = t["vis"]
			print("   %s: Tippfläche %.1f×%.1f dp, sichtbar %.1f×%.1f dp" % [t["name"],
				Dp.to_device_dp(rr.size.x), Dp.to_device_dp(rr.size.y),
				Dp.to_device_dp(vv.size.x), Dp.to_device_dp(vv.size.y)])
	var fail := (inside_total - inside_ok) + (outside_total - outside_ok)
	print("T --test-hit %s: %d Knöpfe, kleinste Tippfläche %.1f×%.1f echte dp (%s), innen %d/%d, außen %d/%d — %s" % [
		label, targets.size(), smallest.x, smallest.y, smallest_name,
		inside_ok, inside_total, outside_ok, outside_total, "OK" if fail == 0 else "%d FEHLER" % fail])
	return fail


func _hit_probe(p: Vector2, target: Dictionary) -> bool:
	_hit_last = ""
	if target.has("group"):
		groups._press_slot = -1
	var got := false
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = p
		ev.pressed = pressed
		Input.parse_input_event(ev)


		await get_tree().process_frame
		await get_tree().process_frame
		if pressed:
			got = groups._press_slot == int(target["group"]) if target.has("group") else _hit_last == target["name"]
			if target.has("group"):
				groups._press_slot = -1
	return got


func _hit_mute() -> Array:
	var saved: Array = []
	var buttons: Array = []
	_collect_buttons($UI, buttons)
	for t in buttons:
		var b: Button = t["node"]
		for sig in ["pressed", "toggled"]:
			for c in b.get_signal_connection_list(sig):
				b.disconnect(sig, c["callable"])
				saved.append([b, sig, c["callable"]])
	for sig2 in ["group_selected", "group_focused", "group_assigned"]:
		for c2 in groups.get_signal_connection_list(sig2):
			groups.disconnect(sig2, c2["callable"])
			saved.append([groups, sig2, c2["callable"]])


	for pair in [[build_bar, "build_requested"], [build_bar, "place_requested"],
			[build_bar, "cancel_requested"], [minimap, "navigate"], [minimap, "focus_base"]]:
		for c3 in pair[0].get_signal_connection_list(pair[1]):
			pair[0].disconnect(pair[1], c3["callable"])
			saved.append([pair[0], pair[1], c3["callable"]])
	return saved


func _hit_unmute(saved: Array) -> void:
	for e in saved:
		if not e[0].is_connected(e[1], e[2]):
			e[0].connect(e[1], e[2])


const LAYOUT_MATRIX := [
	[1096, 2560, 420], [2560, 1096, 420],
	[1080, 2400, 440], [1080, 1920, 420], [720, 1600, 320],
	[1600, 2560, 320], [2560, 1600, 320],
	[1640, 2360, 264], [2360, 1640, 264],
]


func _test_layout_info_unit() -> ProtoWorld.Unit:
	if world.type_ids.has("agun"):
		return world.call("_add_building", "agun", 0, Vector2i(10, 10))
	for u in world.units:
		if u.alive:
			return u
	return null


func _run_test_layout() -> void:
	if _resizer != null:
		_resizer.paused = true
	var total := 0
	var info_unit := _test_layout_info_unit()


	var sp_i := 0
	for t in ["mslo", "iron", "pdox", "atek"]:
		if world.type_ids.has(t):
			world.call("_add_building", t, 0, Vector2i(14 + sp_i * 4, 10))
			sp_i += 1
	for _t in 30:
		world.sim.step()
	for _f in 20:
		await get_tree().process_frame
	for e in LAYOUT_MATRIX:
		DisplayServer.window_set_size(Vector2i(e[0], e[1]))
		Dp.set_forced_dpi(float(e[2]))
		Dp.set_ui_scale(1.0)
		await get_tree().process_frame
		_layout_ui()
		for what in ["hud", "pause", "spieler", "optionen", "ziele", "help", "info"]:
			match what:
				"pause": _toggle_menu(true)


				"spieler":
					_toggle_menu(true)
					_show_player_list()
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


var _test_superwaffen := false

const SP_TEST_TYPES := ["iron", "pdox", "mslo", "atek"]


func _run_test_superwaffen() -> void:
	if _resizer != null:
		_resizer.paused = true
	var origin := Vector2i(20, 20)
	for u in world.units:
		if u.alive and u.player == 0:
			origin = Vector2i(u.pos / ProtoWorld.CELL)
			break
	world.sim.give_credits(0, 50000)


	for i in 8:
		world.call("_add_building", "powr", 0, origin + Vector2i(-6 - (i / 4) * 3, (i % 4) * 3))
	var total := 0
	await _sp_size(2560, 1096, 420)

	for i in SP_TEST_TYPES.size():
		if world.type_ids.has(SP_TEST_TYPES[i]):
			world.call("_add_building", SP_TEST_TYPES[i], 0, origin + Vector2i(6, i * 4))

		for _t in 600:
			world.sim.step()
		await _sp_settle(i + 1)
		total += _sp_check("stufe%d-zu" % (i + 1), i + 1)
		await _sp_shot("stufe%d-zu" % (i + 1))
		if i + 1 > SupportPowersPanel.MAX_TILES:
			_sp_panel.set_expanded(true)
			_layout_ui()
			await get_tree().process_frame
			total += _sp_check("stufe%d-auf" % (i + 1), i + 1)
			await _sp_shot("stufe%d-auf" % (i + 1))
			_sp_panel.set_expanded(false)
			_layout_ui()
			await get_tree().process_frame

	total += await _sp_tap_probe()

	total += await _sp_lead_switch()

	for e in LAYOUT_MATRIX:
		await _sp_size(e[0], e[1], e[2])
		var real := DisplayServer.window_get_size()
		var tag := "%dx%d@%d" % [real.x, real.y, e[2]]
		total += _sp_check(tag + " zu", _sp_panel.visible_kinds().size())
		await _sp_shot("%dx%d" % [real.x, real.y])
		_sp_panel.set_expanded(true)
		_layout_ui()
		await get_tree().process_frame
		total += _sp_check(tag + " auf", _sp_panel.visible_kinds().size())
		await _sp_shot("%dx%d_auf" % [real.x, real.y])
		_sp_panel.set_expanded(false)
		_layout_ui()
		await get_tree().process_frame
	print("T: --test-superwaffen fertig — %d Verstöße" % total)
	get_tree().quit()


func _sp_size(w: int, h: int, dpi: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	Dp.set_forced_dpi(float(dpi))
	Dp.set_ui_scale(1.0)
	var last := Vector2i.ZERO
	var stable := 0
	for _f in 120:
		await get_tree().process_frame
		var now := DisplayServer.window_get_size()
		stable = stable + 1 if now == last else 0
		last = now
		if stable >= 8:
			break
	_layout_ui()
	for _f in 4:
		await get_tree().process_frame
	_layout_ui()
	await get_tree().process_frame


func _sp_settle(n: int) -> void:
	for _f in 900:
		await get_tree().process_frame
		if _sp_panel != null:
			_sp_panel.refresh_now()
			if _sp_panel.visible_kinds().size() >= n:
				break
	_layout_ui()
	for _f in 3:
		await get_tree().process_frame


func _sp_shot(name: String) -> void:
	if _screenshot_path == "":
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_screenshot_path.get_basename(), name])


func _sp_visible_controls() -> Array:
	var out: Array = []
	for k in SupportPowersPanel.KINDS:
		var b: Button = _sp_panel.button_of(k)
		if b != null and b.visible:
			out.append(b)
	var more: Button = _sp_panel.more_button()
	if more != null and more.visible:
		out.append(more)
	return out


func _sp_check(tag: String, n: int) -> int:
	var info := _sp_panel.column_info()
	var expanded: bool = bool(info.get("expanded", false))
	var tiles: int = int(info.get("tiles", 0))
	var more: int = int(info.get("more", 0))
	var want_tiles: int = mini(n, SupportPowersPanel.MAX_TILES) if n <= SupportPowersPanel.MAX_TILES else 1
	var want_more: int = 0 if n <= SupportPowersPanel.MAX_TILES else n - 1
	var fail := 0
	if tiles != want_tiles or more != want_more:
		fail += 1


	var ref := HudTheme.visible_rect(build_toggle)
	var mus := HudTheme.visible_rect(music_toggle)
	var flucht := absf(mus.end.x - ref.end.x) <= 1.0 and absf(mus.size.x - ref.size.x) <= 1.0 \
		and absf(mus.size.y - ref.size.y) <= 1.0
	var column: Array = []
	for c in _sp_visible_controls():
		var r := HudTheme.visible_rect(c)
		if expanded and absf(r.end.x - ref.end.x) > 1.0:
			continue
		column.append([c, r])
		if absf(r.end.x - ref.end.x) > 1.0 or absf(r.size.x - ref.size.x) > 1.0 \
				or absf(r.size.y - ref.size.y) > 1.0:
			flucht = false

	column.sort_custom(func(a, b): return (a[1] as Rect2).position.y < (b[1] as Rect2).position.y)
	var senkrecht := true
	var prev := -1.0e9
	for it in column:
		var r: Rect2 = it[1]
		if r.position.y < prev - 1.0:
			senkrecht = false
		prev = r.end.y
	if column.size() > 0 and (column[column.size() - 1][1] as Rect2).end.y > ref.position.y + 1.0:
		senkrecht = false
	var min_hit := Vector2(1.0e9, 1.0e9)
	var parts := PackedStringArray()
	for c in _sp_visible_controls():
		var hit := (c as Control).get_global_rect()
		var vis := HudTheme.visible_rect(c)
		min_hit = Vector2(minf(min_hit.x, hit.size.x), minf(min_hit.y, hit.size.y))
		parts.append("%s %.0f,%.0f %.0fx%.0f" % [c.name, vis.position.x, vis.position.y,
			vis.size.x, vis.size.y])
	var ov := LayoutCheck.overlap_violations($UI, tag)
	var mv: Array = LayoutCheck.map_violations($UI, _map_rect, tag) if _map_rect.size.x > 0.0 else []
	for line in ov:
		print(line)
	for line in mv:
		print(line)
	fail += ov.size() + mv.size()
	if not flucht:
		fail += 1
	if not senkrecht:
		fail += 1
	if _sp_visible_controls().size() > 0 and Dp.to_device_dp(min_hit.y) < HudTheme.MIN_TOUCH_DP - 0.5:
		fail += 1
	print("T --test-superwaffen %s: %d Superwaffen, Kacheln=%d (Soll %d), Gruppe=+%d (Soll +%d), %s, Flucht=%s, senkrecht=%s, Fächer %d×%d, kleinste Tippfläche %.1f×%.1f echte dp, Überlappungen %d, Karte %d — %s" % [
		tag, n, tiles, want_tiles, more, want_more, "aufgefächert" if expanded else "zugeklappt",
		"ja" if flucht else "NEIN", "ja" if senkrecht else "NEIN",
		int(info.get("fan_rows", 0)), int(info.get("fan_per_row", 0)),
		Dp.to_device_dp(min_hit.x), Dp.to_device_dp(min_hit.y), ov.size(), mv.size(),
		"OK" if fail == 0 else "FEHLER"])
	print("T --test-superwaffen %s: Flucht Musik %.0f,%.0f %.0fx%.0f · %s · Bau %.0f,%.0f %.0fx%.0f" % [
		tag, mus.position.x, mus.position.y, mus.size.x, mus.size.y, ", ".join(parts),
		ref.position.x, ref.position.y, ref.size.x, ref.size.y])
	return fail


func _sp_touch(p: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = p
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame


func _sp_tap_probe() -> int:
	var more: Button = _sp_panel.more_button()
	if more == null or not more.visible:
		print("T --test-superwaffen Tippprobe: keine Gruppenanzeige sichtbar — FEHLER")
		return 1
	_sp_panel.set_expanded(false)
	_layout_ui()
	await get_tree().process_frame
	await _sp_touch(HudTheme.visible_rect(more).get_center())
	var opened := _sp_panel.expanded()
	var before_gesture := _last_gesture
	await _sp_touch(_map_rect.get_center())
	var closed := not _sp_panel.expanded()
	var no_order := _last_gesture == before_gesture

	await _sp_touch(HudTheme.visible_rect(more).get_center())
	var opened2 := _sp_panel.expanded()
	await _sp_touch(HudTheme.visible_rect(more).get_center())
	var closed2 := not _sp_panel.expanded()
	var ok := opened and closed and no_order and opened2 and closed2
	print("T --test-superwaffen Tippprobe: Tipp auf +N öffnet=%s, Tipp auf die Karte schließt=%s (ohne Kartenbefehl=%s, Geste „%s\u201c → „%s\u201c), zweiter Tipp auf +N öffnet=%s und schließt=%s — %s" % [
		opened, closed, no_order, before_gesture, _last_gesture, opened2, closed2,
		"OK" if ok else "FEHLER"])
	return 0 if ok else 1


func _sp_lead_switch() -> int:
	var before: int = _sp_panel.lead_kind()
	var target := Vector2.ZERO
	for u in world.units:
		if u.alive and u.player == 0 and not world.types[u.type].has("building"):
			target = u.pos
			break
	for _t in 4000:
		world.sim.step()
		var st: PackedInt32Array = world.sim.support_powers(0)
		if st.size() >= 8 and st[1] == 1 and st[5] == 1:
			break
	await _sp_settle(_sp_panel.visible_kinds().size())
	before = _sp_panel.lead_kind()
	var before_rem: int = _sp_panel.remaining_ticks(before) if before >= 0 else -1


	var cell := Vector2i((target / ProtoWorld.CELL).floor())
	var fired: bool = target != Vector2.ZERO \
		and world.sim.activate_support_power(0, 0, cell.x, cell.y, -1, -1)
	for _t in 120:
		world.sim.step()
	await _sp_settle(_sp_panel.visible_kinds().size())
	var after: int = _sp_panel.lead_kind()
	var ok := fired and before >= 0 and after >= 0 and after != before
	print("T --test-superwaffen Kachelwechsel: vorher %s (Rest %d Ticks), abgefeuert=%s, nachher %s (Rest %d Ticks) — %s" % [
		tr(SupportPowersPanel.LABELS[before]) if before >= 0 else "-", before_rem, fired,
		tr(SupportPowersPanel.LABELS[after]) if after >= 0 else "-",
		_sp_panel.remaining_ticks(after) if after >= 0 else -1,
		"OK" if ok else "FEHLER"])
	await _sp_shot("kachelwechsel")
	return 0 if ok else 1


const AUDIT_SPEED := {
	"foot":    [100, 89, 111, 111, 89, 89, 89, 0, 0, 0, 0, 0],
	"wheeled": [100, 50, 125, 125, 88, 88, 50, 0, 0, 0, 0, 0],
	"tracked": [100, 88, 125, 125, 88, 88, 88, 0, 0, 0, 0, 0],
	"naval":   [0, 0, 0, 0, 0, 0, 0, 100, 0, 0, 0, 0],
	"lcraft":  [0, 0, 0, 0, 0, 0, 70, 100, 0, 0, 0, 0],
}


func _audit_crate_pressure() -> void:
	if not world.type_ids.has("crate") or world.sim.crate_count() >= 8:
		return
	var placed := 0
	for u in world.units:
		if placed >= 2:
			break
		if not u.alive or u.player == 0 or u.player == ProtoWorld.PLAYER_NEUTRAL or u.player == ProtoWorld.PLAYER_CREEPS:
			continue
		if not u.moving:
			continue
		var goal := Vector2i((u.goal / ProtoWorld.CELL).floor())
		if goal == Vector2i((u.pos / ProtoWorld.CELL).floor()):
			continue
		if world.spawn_unit("crate", ProtoWorld.PLAYER_NEUTRAL, goal) != null:
			placed += 1


func _ai_audit(tag: String) -> int:
	if world == null or world.sim == null:
		return 0
	var actors: Dictionary = RulesDb.data().get("actors", {})
	var found := 0

	var produces := {}
	for u in world.units:
		if not u.alive:
			continue
		var td: Dictionary = actors.get(u.type, {})
		for q in td.get("produces", []):
			if not produces.has(u.player):
				produces[u.player] = {}
			produces[u.player][str(q)] = true
	for u in world.units:
		if not u.alive or _audit_seen.has(u.id):
			continue
		var td: Dictionary = actors.get(u.type, {})
		if td.is_empty() or td.has("aircraft") or td.has("crate"):
			continue


		var cell: Vector2i = world.sim.actor_cell(u.id)
		if cell.x < 0:
			continue
		var ter: int = world.sim.cell_terrain(cell.x, cell.y)
		var tname: String = ProtoWorld.TERRAIN_ORDER[ter] if ter >= 0 and ter < ProtoWorld.TERRAIN_ORDER.size() else "?"
		var msg := ""
		var bld = td.get("building", null)
		if bld is Dictionary:
			var wet: bool = ((bld as Dictionary).get("terrain_types", []) as Array).has("Water")
			var on_water: bool = ter == ProtoWorld.TER_WATER
			if wet and not on_water:
				msg = "Wassergebäude an Land"
			elif not wet and on_water:
				msg = "Landgebäude auf Wasser"
		else:
			var mob = td.get("mobile", null)
			if mob is Dictionary:
				var loco := str((mob as Dictionary).get("locomotor", "tracked"))
				if loco == "heavywheeled":
					loco = "wheeled"
				var row: Array = AUDIT_SPEED.get(loco, AUDIT_SPEED["tracked"])
				if ter < 0 or ter >= row.size() or int(row[ter]) == 0:
					msg = "%s-Einheit auf %s" % [loco, tname]
		if msg != "":
			_audit_seen[u.id] = true
			found += 1
			_audit_errors += 1
			print("AUDIT %s FEHLER: Spieler %d %s (id %d) bei %s auf %s — %s" % [tag, u.player, u.type, u.id, cell, tname, msg])
			continue


		var buildable = td.get("buildable", null)
		if buildable is Dictionary and u.player != ProtoWorld.PLAYER_NEUTRAL:
			var qs: Array = (buildable as Dictionary).get("queue", [])
			var mine: Dictionary = produces.get(u.player, {})
			var q0 := str(qs[0]) if not qs.is_empty() else ""
			if (q0 == "Ship" or q0 == "Boat") and not mine.has(q0):
				_audit_seen[u.id] = true
				_audit_notes += 1
				print("AUDIT %s HINWEIS: Spieler %d %s (id %d) bei %s auf %s — Warteschlange %s ohne eigene Werft" % [tag, u.player, u.type, u.id, cell, tname, q0])
	return found


func _ai_strategy_of(pl: int) -> String:
	for e in world.player_roster:
		if int(e.get("sim", -1)) == pl:
			var st := str(e.get("strategy", ""))
			if st != "":
				return st
	return "?"


func _ai_level_of(pl: int) -> String:
	for e in world.player_roster:
		if int(e.get("sim", -1)) == pl:
			return str(e.get("level", "?"))
	return "?"


const AI_VORHABEN_NAMES := ["spaeher", "erzueberfall", "panzerstoss", "belagerung", "infanterieflut",
	"luftschlag", "pionier", "kommando", "zange", "gegenstoss", "ausbau_wache",
	"atom_stoss", "vorhang_stoss", "igel", "wirtschaft"]

func _ai_vorhaben_name(i: int) -> String:
	return AI_VORHABEN_NAMES[i] if i >= 0 and i < AI_VORHABEN_NAMES.size() else "?"

func _ai_plan_name(pl: int) -> String:
	if world.sim == null or not world.sim.has_method("bot_vorhaben"):
		return "?"
	return _ai_vorhaben_name(world.sim.bot_vorhaben(pl))


const AI_STAT_KEYS := ["gebaut", "superwaffen", "trupps", "erster_angriff", "armee", "bargeld",
	"tuerme", "belagerer_verloren", "in_turmreichweite", "trupp_verluste", "schwere_verluste"]

func _ai_stats(pl: int) -> Dictionary:
	var sim = world.sim
	var out := {}
	for k in AI_STAT_KEYS:
		out[k] = -1
	if sim == null:
		return out
	if sim.has_method("bot_stats"):
		var d: Dictionary = sim.bot_stats(pl)
		for k in AI_STAT_KEYS:
			out[k] = int(d.get(k, -1))
		return out
	if sim.has_method("bot_stat"):
		for i in 4:
			out[AI_STAT_KEYS[i]] = int(sim.bot_stat(pl, i))
	return out


func _print_tournament_rows(tick: int) -> void:
	var sim = world.sim
	if sim == null:
		return
	var ws: int = world.win_state()
	for e in world.player_roster:
		if str(e.get("kind", "human")) != "bot":
			continue
		var pl := int(e.get("sim", -1))
		if pl < 0:
			continue
		var st := _ai_stats(pl)
		print("TURNIER tick=%d pl=%d strategie=%s staerke=%s plan=%s gebaut=%d superwaffen=%d trupps=%d erster_angriff=%d lebend=%d ertrag=%d credits=%d spieler_lebend=%d ausgang=%d armee=%d bargeld=%d belagerer_verloren=%d in_turmreichweite=%d tuerme=%d trupp_verluste=%d schwere_verluste=%d" % [
			tick, pl, _ai_strategy_of(pl), _ai_level_of(pl), _ai_plan_name(pl),
			st["gebaut"], st["superwaffen"], st["trupps"], st["erster_angriff"],
			sim.alive_count(pl), sim.earned(pl), sim.credits(pl), sim.alive_count(0), ws,
			st["armee"], st["bargeld"], st["belagerer_verloren"], st["in_turmreichweite"],
			st["tuerme"], st["trupp_verluste"], st["schwere_verluste"]])


func _run_test_harvest() -> void:
	var sim = world.sim
	var tick: int = sim.tick()
	if _test_step == 0 and tick >= 10:
		var origin := Vector2i(-1, -1)
		for u in world.units:
			if u.alive and u.player == 0:
				if u.type == "fact":
					origin = Vector2i(u.pos / ProtoWorld.CELL)
					break
				if origin.x < 0:
					origin = Vector2i(u.pos / ProtoWorld.CELL)
		if origin.x < 0:
			origin = Vector2i(20, 20)
		sim.give_credits(0, 20000)
		world.call("_add_building", "proc", 0, origin + Vector2i(6, 0))


		for k in 6:
			world.call("_add_building", "silo", 0, origin + Vector2i(-4 + k, -4))
		for k in 6:
			var u: ProtoWorld.Unit = world.spawn_unit("harv", 0, origin + Vector2i(3 + k, 5))
			if u != null:
				_harv_ids.append(u.id)
				_harv_last_cell[u.id] = Vector2i(u.pos / ProtoWorld.CELL)
				_harv_stall[u.id] = 0
				_harv_worst[u.id] = 0
		world.center_on(Vector2(origin + Vector2i(5, 3)) * ProtoWorld.CELL)
		print("T%d --test-harvest: %d Ernteeinheiten, 1 Raffinerie bei %s" % [tick, _harv_ids.size(), origin + Vector2i(6, 0)])
		_test_step = 1
		_test_tick = tick
		_harv_last_tick = tick
		return
	if _test_step != 1:
		return

	var dt: int = maxi(1, tick - _harv_last_tick)
	_harv_last_tick = tick
	for id in _harv_ids:
		var u: ProtoWorld.Unit = world.unit_by_id(id) if world.has_method("unit_by_id") else null
		var cell := Vector2i(-1, -1)
		if u != null and u.alive:
			cell = Vector2i(u.pos / ProtoWorld.CELL)
		if cell == _harv_last_cell.get(id, Vector2i(-1, -1)):
			_harv_stall[id] = int(_harv_stall.get(id, 0)) + dt
			if int(_harv_stall[id]) > int(_harv_worst.get(id, 0)):
				_harv_worst[id] = int(_harv_stall[id])
		else:
			_harv_stall[id] = 0
		_harv_last_cell[id] = cell
	if tick >= _test_tick + 500:
		_test_tick = tick
		var lines: Array[String] = []
		for id in _harv_ids:
			var st: int = sim.harvest_state(id) if sim.has_method("harvest_state") else -1
			var bl: int = sim.harvest_bales(id) if sim.has_method("harvest_bales") else -1
			lines.append("%d:%s z%d b%d/steht %d" % [id, _harv_last_cell.get(id, Vector2i(-1, -1)),
				st, bl, int(_harv_stall.get(id, 0))])
		print("T%d --test-harvest: Ertrag %d, Guthaben %d | %s" % [tick, sim.earned(0), sim.credits(0), ", ".join(lines)])


	if not _harv_parked and tick >= _test_harvest_until / 2:
		_harv_parked = true
		var ok: bool = bool(sim.apply_order(0, PackedInt32Array([25, 0, 0, 0, 0, 0])))
		print("T%d --test-harvest: Befehl „zur Basis“ (op 25) angenommen: %s" % [tick, "ja" if ok else "NEIN"])
	if not _harv_resumed and tick >= _test_harvest_until * 3 / 4:
		_harv_resumed = true
		var states: Array[int] = []
		for id in _harv_ids:
			states.append(int(sim.harvest_state(id)))
		var ok2: bool = bool(sim.apply_order(0, PackedInt32Array([26, 0, 0, 0, 0, 0])))
		print("T%d --test-harvest: Zustände beim Parken %s, Befehl „weitersammeln“ (op 26): %s" % [
			tick, states, "ja" if ok2 else "NEIN"])
	if tick >= _test_harvest_until:
		var worst := 0
		for id in _harv_ids:
			worst = maxi(worst, int(_harv_worst.get(id, 0)))
		print("T%d --test-harvest Ende: Ertrag %d, Guthaben %d, längster Stillstand %d Ticks" % [
			tick, sim.earned(0), sim.credits(0), worst])
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
	if _test_ai_audit and tick >= _audit_tick + 60:
		_audit_tick = tick
		_ai_audit("T%d" % tick)
		if tick >= _audit_crate_tick + 300:
			_audit_crate_tick = tick
			_audit_crate_pressure()
	if tick >= _test_tick + 1000:
		_test_tick = tick

		var per := {}
		for u in world.units:
			if u.alive and u.player != 0 and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS:
				if not per.has(u.player):
					per[u.player] = {}
				per[u.player][u.type] = per[u.player].get(u.type, 0) + 1
		for pl in per:


			var air_names: Array = []
			if sim.has_method("buildable"):
				for ti in sim.buildable(pl, ProtoWorld.Queue.AIRCRAFT):
					for nm in world.type_ids:
						if int(world.type_ids[nm]) == int(ti):
							air_names.append(str(nm))
							break
			var air_buildable: String = ",".join(PackedStringArray(air_names)) if not air_names.is_empty() else "-"


			var st := _ai_stats(int(pl))
			print("T%d KI%d [%s] luftbaubar=%s: %s credits=%d ertrag=%d squads=%d plan=%s armee=%d bargeld=%d belagerer_verloren=%d in_turmreichweite=%d tuerme=%d schwere_verluste=%d" % [
				tick, pl, _ai_strategy_of(pl), air_buildable,
				per[pl], sim.credits(pl), sim.earned(pl), sim.bot_squad_count(pl),
				_ai_plan_name(pl), st["armee"], st["bargeld"], st["belagerer_verloren"],
				st["in_turmreichweite"], st["tuerme"], st["schwere_verluste"]])


			if sim.has_method("bot_squad_info"):
				var info: Array = sim.bot_squad_info(int(pl))
				if not info.is_empty():
					var head: Dictionary = info[0]
					print("   KI%d Bestellungen=%s vh_pending=%d reserve=%d" % [
						pl, str(head.get("bestellungen", [])), int(head.get("vh_pending", -1)),
						int(head.get("reserve", 0))])
					for k in range(1, info.size()):
						var q: Dictionary = info[k]
						print("   KI%d Trupp typ=%d zustand=%s groesse=%d/%d sammel=(%d,%d) ziel=%d vorhaben=%d sturm=%d sammel_seit=%d regen_bis=%d sturm_ab=%d fuehrer=(%d,%d)" % [
							pl, int(q.get("typ", 0)),
							["IDLE", "ATTACK_MOVE", "ATTACK", "FLEE", "GATHER"][clampi(int(q.get("zustand", 0)), 0, 4)],
							int(q.get("groesse", 0)), int(q.get("start", 0)),
							int(q.get("sammel_x", -1)), int(q.get("sammel_y", -1)),
							int(q.get("ziel", -1)), int(q.get("vorhaben", -1)), int(q.get("sturm", 0)),
							int(q.get("sammel_seit", 0)), int(q.get("regen_bis", 0)),
							int(q.get("sturm_ab", 0)), int(q.get("fuehrer_x", -1)), int(q.get("fuehrer_y", -1))])


			if sim.has_method("bot_vorhaben_log"):
				var vlog: Array = sim.bot_vorhaben_log(int(pl))
				if not vlog.is_empty():
					var parts: PackedStringArray = []
					for e in vlog:
						parts.append("%s T%d-T%d %s" % [_ai_vorhaben_name(int(e.get("vorhaben", -1))),
							int(e.get("start", 0)), int(e.get("end", 0)),
							["laeuft", "erfolg", "fehlschlag"][clampi(int(e.get("result", 0)), 0, 2)]])
					print("   KI%d Vorhaben-Protokoll: %s" % [pl, "; ".join(parts)])
		print("T%d Spieler: %d | %d µs/Tick, %d Actors, %d Kisten" % [tick, sim.alive_count(0), sim.last_step_usec(), sim.actor_count(), sim.crate_count()])


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
			_print_tournament_rows(tick)
			if _test_ai_audit:
				_ai_audit("T%d" % tick)
				print("AUDIT Ende: %d Befund(e), %d Hinweis(e)" % [_audit_errors, _audit_notes])
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
	["pause.objectives", "_show_objectives"], ["pause.players", "_show_player_list"],
	["pause.save", "_show_slots_save"],
	["pause.load", "_show_slots_load"], ["menu.main.options", "_show_options"],
	["pause.restart", "_restart_battle"], ["pause.give_up", "_leave_battlefield"],
	["pause.quit_game", "_quit_game"],
]


const MP_PAUSE_GRID := [
	["pause.objectives", "_show_objectives"], ["pause.players", "_show_player_list"],
	["menu.main.options", "_show_options"], ["pause.give_up", "_mp_surrender"],
	["gameover.main_menu", "_mp_leave_battle"], ["pause.quit_game", "_quit_game"],
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
	if not _mp_active():
		box.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
				func(i): GameSpeed.set_index(i), self))
	var landscape: bool = Dp.safe_rect().size.x >= Dp.safe_rect().size.y
	var cell_w := Dp.px(200.0 if landscape else 260.0)
	var grid := GridContainer.new()
	grid.columns = 2 if landscape else 1
	grid.add_theme_constant_override("h_separation", int(Dp.px(8)))
	grid.add_theme_constant_override("v_separation", int(Dp.px(8)))


	var alle: Array = MP_PAUSE_GRID if _mp_active() else PAUSE_GRID


	var entries: Array = []
	for entry in alle:
		if str(entry[0]) == "pause.players" and world.player_roster.is_empty():
			continue
		entries.append(entry)
	for entry in entries:
		var b := Button.new()
		b.text = tr(entry[0])
		b.custom_minimum_size = Vector2(cell_w, Dp.px(42))
		HudTheme.plate_button_style(b, 14.0)
		b.pressed.connect(Callable(self, entry[1]))
		grid.add_child(b)
	var scroll := TouchList.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(grid)


	var rows := int(ceil(entries.size() / float(grid.columns)))
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


		var hp: Vector2 = get_parent().get_meta("hit_pad", Vector2.ZERO) if get_parent() != null else Vector2.ZERO
		var face := Rect2(hp, size - hp * 2.0)
		var pad := minf(face.size.x, face.size.y) * 0.22
		var w := maxf(2.0, minf(face.size.x, face.size.y) * 0.06)
		draw_line(face.position + Vector2(pad, face.size.y - pad),
			face.position + Vector2(face.size.x - pad, pad), Color(0.95, 0.25, 0.2, 0.9), w, true)


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


	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


	var music_now := Label.new()
	music_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	music_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_now.custom_minimum_size = Vector2(Dp.px(300), 0)
	music_now.add_theme_font_size_override("font_size", int(Dp.px(11)))
	music_now.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	var set_now := func() -> void:
		var t: String = str(world.music.current_title()) if world.music != null else ""
		music_now.text = (tr("options.music_now") % t) if t != "" else ""
		music_now.visible = t != ""
	set_now.call()
	music_btn.pressed.connect(func():
		_toggle_music()
		music_btn.text = _music_text()
		set_now.call())
	box.add_child(music_btn)
	box.add_child(music_now)


	if not _mp_active():
		box.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
				func(i): GameSpeed.set_index(i), self))
	for entry in [["master", "menu.options.master"], ["music", "menu.options.music"],
			["sfx", "menu.options.sfx"], ["voice", "menu.options.voice"]]:
		box.add_child(HudTheme.volume_row(entry[0], tr(entry[1]), self))


	if _mp_active() or _test_voice:
		box.add_child(HudTheme.volume_row("radio", tr("menu.options.radio"), self))
		box.add_child(HudTheme.choice_row(tr("menu.options.voice_chat"),
				[tr("word.off"), tr("word.on")], 1 if VoiceChat.enabled() else 0,
				func(i: int):
					VoiceChat.set_enabled(i == 1)
					var vc := _mp_voice()
					if i == 0 and vc != null:
						vc.set_mode(VoiceChat.Mode.OFF)
					_update_mic_button(), self))


		box.add_child(HudTheme.choice_row(tr("menu.options.headset"),
				[tr("word.auto"), tr("word.on"), tr("word.off")], AudioMix.headset_mode(),
				func(i: int): AudioMix.set_headset_mode(i), self))
		var vp := _mp_voice()
		if vp != null:
			box.add_child(HudTheme.mic_probe_row(vp, self))


	var controls_btn := Button.new()
	controls_btn.text = tr("menu.controls")
	controls_btn.custom_minimum_size = Vector2(Dp.px(300), Dp.px(44))
	HudTheme.plate_button_style(controls_btn, 15.0)
	controls_btn.pressed.connect(func(): _show_gesture_help(false))
	box.add_child(controls_btn)


	if Desktop.is_desktop():
		var fs_btn := Button.new()
		fs_btn.text = Desktop.fullscreen_text()
		fs_btn.custom_minimum_size = Vector2(Dp.px(300), Dp.px(44))
		HudTheme.plate_button_style(fs_btn, 15.0)
		fs_btn.pressed.connect(func():
			Desktop.toggle_fullscreen()
			fs_btn.text = Desktop.fullscreen_text())
		box.add_child(fs_btn)


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
	HudTheme.log_overlay("MISSIONSMELDUNG", _message_label.text, 8.0)
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
		HudTheme.log_overlay("ZIELZEILE", mtext.replace("\n", " | "))

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
			"cmd_clear": _cmd_buttons.get("clear"), "cmd_harv": _cmd_buttons.get("harv"),
			"cmd_base": _cmd_buttons.get("base"),
			"cmd_event": _cmd_buttons.get("event"), "cmd_sel": _cmd_buttons.get("sel"),
			"cmd_zoom_in": _cmd_buttons.get("zoom_in"), "cmd_zoom_out": _cmd_buttons.get("zoom_out"),
		}
	var target: Control = _hud_highlight_targets.get(_mission_highlight_id, null)


	if target != null and not target.is_visible_in_tree():
		return null
	return target


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


	world.paused = (open or _modal_open()) and not _mp_active()
	if open:
		_center_panel(_menu_panel)


func _exit_tree() -> void:
	if _test_toasts:
		HudTheme.log_summary()


func _notification(what: int) -> void:


	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave("pause")
		return
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	_go_back()


func _go_back() -> void:
	if is_instance_valid(_movie) and _movie.is_inside_tree():
		return
	if _mp_chat_panel != null and _mp_chat_panel.visible:
		_close_chat_input()
	elif _info_card != null:
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


func _unhandled_input(e: InputEvent) -> void:
	if Desktop.handle_fullscreen_key(e):
		get_viewport().set_input_as_handled()
		return
	if not Desktop.has_keyboard():
		return
	if e is InputEventMouseButton:
		if _desktop_mouse_button(e as InputEventMouseButton):
			get_viewport().set_input_as_handled()
		return
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return


	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var k: InputEventKey = e
	if k.keycode == KEY_ESCAPE:
		_escape_key()
		get_viewport().set_input_as_handled()
		return
	var slot := int(k.keycode) - int(KEY_1)
	if slot >= 0 and slot < ControlGroups.SLOTS:
		if k.ctrl_pressed or k.meta_pressed:
			groups.assign(slot)
		elif slot == _key_group_last and Time.get_ticks_msec() / 1000.0 - _key_group_time < ControlGroups.DOUBLE_TAP:
			_key_group_last = -1
			groups.focus(slot)
		else:
			_key_group_last = slot
			_key_group_time = Time.get_ticks_msec() / 1000.0
			groups.select(slot)
		get_viewport().set_input_as_handled()
		return


	if _scroller != null and _scroller.takes_key(e):
		return
	var act: Dictionary = Desktop.key_action(e)
	if act["id"] != "" and _do_key_action(act["id"], act["index"]):
		get_viewport().set_input_as_handled()


func _ui_layer_open() -> bool:
	if world == null:
		return true
	return (is_instance_valid(_movie) and _movie.is_inside_tree()) \
		or (_mp_chat_panel != null and _mp_chat_panel.visible) \
		or _info_card != null or radial.visible \
		or world.placing_type >= 0 or _confirm_mode != "" or _order_mode != "" \
		or _click_mode != "" or (_menu_panel != null and _menu_panel.visible)


func _escape_key() -> void:
	if not _ui_layer_open() and not world.selection.is_empty():
		_clear_selection_toast()
		return
	_go_back()


func _on_right_click_map() -> void:
	if world == null:
		return
	if _menu_panel != null and _menu_panel.visible:
		return
	if _ui_layer_open():
		_go_back()
		return
	if not world.selection.is_empty():
		_clear_selection_toast()


func _clear_selection_toast() -> void:
	world.clear_selection()
	_show_selection_info()
	_toast(tr("toast.selection_cleared"))


const DESKTOP_HOLD_MS := 400

var _tap_from_mouse := false
var _desktop_cmd := false
var _rmb_down := false
var _rmb_from := Vector2.ZERO
var _rmb_time := 0
var _rmb_consumed := false
var _radial_mouse := false
var _radial_sticky := false


func _desktop_select_first() -> bool:
	return Desktop.has_keyboard() and _tap_from_mouse and not _desktop_cmd


func _desktop_left_click(p: Vector2, hit: ProtoWorld.Unit) -> void:


	if hit != null and hit.alive and hit.player == world.local_player and hit.selected \
			and world.selection.size() == 1 and world.has_deploy_action(hit.type) \
			and not Input.is_key_pressed(KEY_SHIFT):
		_do_deploy_action(world.deploy_action(hit.type))
		_last_gesture = "Entfalten"
		return
	if hit != null and hit.alive and hit.player == world.local_player and world.selectable(hit):
		var vorher := world.additive_select
		if Input.is_key_pressed(KEY_SHIFT):
			world.additive_select = true
		_select_tapped(hit)
		world.additive_select = vorher
		_last_gesture = "Auswahl: %d" % world.selection.size()
		return
	if not world.selection.is_empty():
		world.clear_selection()
		_show_selection_info()
	if hit != null:
		_inspect(hit)
		_last_gesture = "Infozeile"
	else:
		_last_gesture = "Klick ins Leere"


func _desktop_right_click(p: Vector2) -> void:
	if world == null or world.sim == null or _scroll_blocked():
		return
	if _sp_panel != null and _sp_panel.expanded():
		_sp_panel.set_expanded(false)
		return
	if _ui_layer_open():
		_on_right_click_map()
		return
	if world.selection.is_empty():
		return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		_desktop_force_fire(p)
		return
	_desktop_cmd = true
	world.queue_orders = Input.is_key_pressed(KEY_SHIFT)
	_on_tap(p)
	world.queue_orders = false
	_desktop_cmd = false


func _desktop_force_fire(p: Vector2) -> void:
	var wp := world.screen_to_world(p)
	var hit := world.pick_unit(wp, Dp.px(HIT_RADIUS_DP) / world.zoom)
	if hit != null and world.selection_can_force_attack(hit) and world.order_attack(hit, true):
		_toast(tr("toast.attacking") % [_type_label(hit.type), world.selection.size()])
		_last_gesture = "Zwangsangriff (%d)" % world.selection.size()
		return
	_toast(tr("radial.action.force_fire") if world.order_attack_cell(wp) else tr("toast.force_fire_impossible"))
	_last_gesture = "Zwangsfeuer"


func _desktop_mouse_button(mb: InputEventMouseButton) -> bool:
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_desktop_open_radial(mb.position)
		elif _radial_mouse:
			_desktop_close_radial(mb.position, true)
		return true
	if mb.button_index == MOUSE_BUTTON_LEFT:


		if _radial_sticky and mb.pressed:
			_desktop_close_radial(mb.position, false)
			return true
		return false
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if mb.pressed:
		if _radial_sticky:
			_desktop_cancel_radial()
			return true
		_rmb_down = true
		_rmb_from = mb.position
		_rmb_time = Time.get_ticks_msec()
		_rmb_consumed = false
		return true
	if not _rmb_down:
		return false
	_rmb_down = false
	if _radial_mouse:
		_desktop_close_radial(mb.position, false)
		return true
	if _rmb_consumed:
		return true
	_desktop_right_click(mb.position)
	return true


func _desktop_mouse_tick() -> void:
	if _radial_sticky and not radial.visible:
		_radial_sticky = false
		gestures.input_blocked = false
	if not _rmb_down or _rmb_consumed or radial.visible:
		return
	if Time.get_ticks_msec() - _rmb_time < DESKTOP_HOLD_MS:
		return
	_desktop_open_radial(_rmb_from)


func _desktop_open_radial(p: Vector2) -> void:
	if world == null or world.sim == null or _scroll_blocked() or radial.visible:
		return
	if world.placing_type >= 0 or _order_mode != "" or _click_mode != "":
		return
	_rmb_from = p
	_rmb_consumed = true
	_on_long_press(p)
	_radial_mouse = radial.visible


func _desktop_close_radial(p: Vector2, allow_sticky: bool) -> void:
	_radial_mouse = false
	if allow_sticky and radial.visible and p.distance_to(_rmb_from) <= Dp.px(gestures.tap_slop_dp):
		_radial_sticky = true
		gestures.input_blocked = true
		return
	_radial_sticky = false
	gestures.input_blocked = false
	if radial.visible:
		radial.close(p)


func _desktop_cancel_radial() -> void:
	_radial_sticky = false
	_radial_mouse = false
	gestures.input_blocked = false
	radial.cancel()


const KEYS_WHILE_BUSY := ["zoom_in", "zoom_out", "zoom_reset", "base", "last_event", "to_selection", "pause", "music"]


func _do_key_action(id: String, index: int) -> bool:


	if _scroll_blocked():
		return false


	if (world.placing_type >= 0 or _confirm_mode != "" or _order_mode != "") and not KEYS_WHILE_BUSY.has(id):
		return false
	match id:
		"repair", "sell":
			_set_click_mode(id)
		"attack_move", "guard", "stop", "scatter":
			if world.selection.is_empty():
				_toast(tr("toast.nothing_selected"))
				return true
			_on_radial(id)
		"deploy":
			if world.selection.is_empty():
				_toast(tr("toast.nothing_selected"))
				return true


			var u = world.selection[0]
			if world.has_deploy_action(u.type):
				_do_deploy_action(world.deploy_action(u.type))
			else:
				_on_radial("deploy")
		"all_units":
			_end_click_mode()
			_toast(tr("toast.all_units_count") % world.select_all_units())
			_show_selection_info()
		"base":
			_jump_to_base()
		"last_event":
			if _has_event:
				world.center_on(_last_event_pos)
			else:
				_toast(tr("toast.no_event"))
		"to_selection":
			if world.selection.is_empty():
				_toast(tr("toast.nothing_selected"))
			else:
				world.center_on(world.selection_center())
		"zoom_in":
			_zoom_step(1.25)
		"zoom_out":
			_zoom_step(0.8)
		"zoom_reset":

			_zoom_step(3.0 / maxf(world.zoom, 0.001))
		"build_bar":
			_toggle_build_bar()
		"tabs":
			return build_bar.select_tab(index)
		"pause":
			return _toggle_pause_key()
		"music":
			_toggle_music()
		_:
			return false
	return true


func _toggle_pause_key() -> bool:
	if _mp_active():
		_toast(tr("toast.no_pause_mp"))
		return true
	world.paused = not world.paused
	_toast(tr("toast.paused") if world.paused else tr("toast.resumed"))
	return true


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
	_mp_scoreboard(box)
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
		_update_mode_frame()
	_update_mp_hud(delta)
	_update_voice_power()
	_check_game_over()
	_update_mission_ui()
	_update_toasts()
	_update_info()
	if Desktop.has_keyboard():
		_desktop_mouse_tick()
	_edge_scroll(delta)
	_step_pending_unload()
	_tick_auto_build_bar(delta)
	if _test_sell and world.sim != null:
		_run_test_sell()
	if _test_defense and world.sim != null:
		_run_test_defense()
	if _test_defense_fire and world.sim != null:
		_run_test_defense_fire()
	if _test_buildings and world.sim != null:
		_run_test_buildings()
	if _test_tesla and world.sim != null:
		_run_test_tesla()
	if _test_ttnk and world.sim != null:
		_run_test_ttnk()
	if _test_nuke and world.sim != null:
		_run_test_nuke()
	if _test_spy and world.sim != null:
		_run_test_spy()
	if _test_bridge and world.sim != null:
		_run_test_bridge()
	if _test_bridges and world.sim != null:
		_run_test_bridges()
	if _test_capture and world.sim != null:
		_run_test_capture()
	if _test_toasts and world.sim != null:
		_run_test_toasts()
	if _test_eva and world.sim != null:
		_run_test_eva()
	if _test_ui and world.sim != null:
		_run_test_ui()
	if _test_ai and world.sim != null:
		_run_test_ai()
	if _test_harvest and world.sim != null:
		_run_test_harvest()
	if _test_motion and world.sim != null:
		_run_test_motion()
	if _test_projectile and world.sim != null:
		_run_test_projectile()
	if _test_barrels and world.sim != null:
		_run_test_barrels()
	if _test_husk and world.sim != null:
		_run_test_husk()
	if _test_kaserne and world.sim != null:
		_run_test_kaserne()
	if _test_effects and world.sim != null:
		_run_test_effects()
	if _test_gap and world.sim != null:
		_run_test_gap()
	if _test_gps and world.sim != null:
		_run_test_gps()
	if _test_nebel and world.sim != null:
		_run_test_nebel()
	if _test_jammer and world.sim != null:
		_run_test_jammer()
	if _test_mech and world.sim != null:
		_run_test_mech()
	if _test_muzzle and world.sim != null:
		_run_test_muzzle()
	if _test_rotor and world.sim != null:
		_run_test_rotor()
	if _test_turret and world.sim != null:
		_run_test_turret()
	if _test_make and world.sim != null:
		_run_test_make()
	if _test_autotarget and world.sim != null:
		_run_test_autotarget()
	if _test_air and world.sim != null:
		_run_test_air()
	if _test_crash and world.sim != null:
		_run_test_crash()
	if _test_air_player and world.sim != null:
		_run_test_air_player()
	if _test_cargo and world.sim != null:
		_run_test_cargo()
	if _test_naval and world.sim != null:
		_run_test_naval()
	if _test_msub and world.sim != null:
		_run_test_msub()
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
	if _demo_battle > 0 and world.sim != null:
		_run_demo_battle()
	if _test_heal and world.sim != null:
		_run_test_heal()
	if _test_iron and world.sim != null:
		_run_test_iron()
	if _test_deploy and world.sim != null:
		_run_test_deploy()
	if _test_crate and world.sim != null:
		_run_test_crate()
	if _test_cratedrop and world.sim != null:
		_run_test_cratedrop()
	if _test_forcefire and world.sim != null:
		_run_test_forcefire()
	if _test_c4 and world.sim != null:
		_run_test_c4()
	if _test_wall and world.sim != null:
		_run_test_wall()
	if _test_build_area and world.sim != null:
		_run_test_build_area()
	if _test_retreat and world.sim != null:
		_run_test_retreat()
	if _test_placement_cancel and world.sim != null and _test_step == 0 and world.sim.tick() >= 10:
		_test_step = 1
		_run_test_placement_cancel()
	if _test_tap_orders and world.sim != null:
		_run_test_tap_orders()
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

	if _screenshot_path == "" or _test_voice or _test_players or _test_water or _test_ai or _test_harvest or _test_ui or _test_defense or _test_defense_fire or _test_buildings or _test_tesla or _test_ttnk or _test_nuke \
			or _test_superwaffen or _test_projectile or _test_barrels or _test_autotarget or _test_husk or _test_kaserne or _test_gap or _test_gps or _test_nebel or _test_jammer or _test_mech or _test_muzzle or _test_rotor or _test_air or _test_air_player or _test_cargo or _test_placement or _test_naval or _test_msub or _test_lst or _test_armaments or _test_turret or _test_make:
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


const NetHub := preload("res://scripts/net/net_hub.gd")
const ChatPanel := preload("res://scripts/ui/chat_panel.gd")
const NetOrders := preload("res://scripts/net/net_orders.gd")
const VoiceChat := preload("res://scripts/net/voice_chat.gd")

const MP_LINE_SECONDS := 12.0
const MP_LINES := 4


const PLAYER_ROW_DP := 439.0


const PLAYER_REL_COLORS := {
	"self": HudTheme.GOLD, "allied": HudTheme.READY_GREEN, "enemy": HudTheme.MODE_SELL,
}

var _mp: Node = null
var _mp_lines: Array = []
var _mp_chat_label: RichTextLabel
var _mp_ping: Label
var _mp_notice: Label
var _mp_notice_bg: Panel
var _mp_chat_btn: Button
var _mp_mic_btn: Button
var _mp_mic_label: Label
var _mp_speak_label: RichTextLabel


var _voice_power_was := false
var _voice_power_hold := 0
var _mp_chat_panel = null
var _mp_wait_since := -1.0
var _mp_over := ""
var _mp_autoplay := -1
var _mp_autoplay_step := 0


var _mp_shot_dir := ""
var _mp_shot_done := {}
var _mp_shot_armed := {}


var _mp_chat_every := 0
var _mp_chat_sent := 0
var _mp_chat_last := -1


var _voice_intro_pending := false


func _setup_multiplayer_hud() -> void:
	var hub := NetHub.hub()
	if hub == null or not (hub.active() or _test_voice):
		return
	_mp = hub

	_mp_chat_label = RichTextLabel.new()
	_mp_chat_label.bbcode_enabled = true
	_mp_chat_label.fit_content = true
	_mp_chat_label.scroll_active = false
	_mp_chat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_chat_label.add_theme_font_size_override("normal_font_size", int(Dp.px(13)))
	_mp_chat_label.add_theme_constant_override("outline_size", int(Dp.px(3)))
	_mp_chat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	$UI.add_child(_mp_chat_label)

	_mp_ping = Label.new()
	_mp_ping.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_ping.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_mp_ping.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	_mp_ping.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_mp_ping.add_theme_constant_override("outline_size", int(Dp.px(2)))
	$UI.add_child(_mp_ping)

	_mp_notice_bg = Panel.new()
	_mp_notice_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_notice_bg.add_theme_stylebox_override("panel", HudTheme.panel(HudTheme.PANEL_BG_SOLID, HudTheme.BORDER))
	_mp_notice_bg.visible = false
	$UI.add_child(_mp_notice_bg)
	_mp_notice = Label.new()
	_mp_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mp_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mp_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mp_notice.add_theme_font_size_override("font_size", int(Dp.px(15)))
	_mp_notice.add_theme_color_override("font_color", HudTheme.GOLD)
	_mp_notice.visible = false
	$UI.add_child(_mp_notice)

	_mp_chat_panel = ChatPanel.new()
	_mp_chat_panel.show_log = false
	_mp_chat_panel.draw_background = true
	_mp_chat_panel.visible = false
	_mp_chat_panel.input_focus.connect(func(on: bool): gestures.input_blocked = on)
	_mp_chat_panel.sent.connect(func(_t, _s): _close_chat_input())
	$UI.add_child(_mp_chat_panel)

	_mp_mic_label = Label.new()
	_mp_mic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_mic_label.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_mp_mic_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_mp_mic_label.add_theme_constant_override("outline_size", int(Dp.px(3)))
	_mp_mic_label.visible = false
	$UI.add_child(_mp_mic_label)
	_mp_speak_label = RichTextLabel.new()
	_mp_speak_label.bbcode_enabled = true
	_mp_speak_label.fit_content = true
	_mp_speak_label.scroll_active = false
	_mp_speak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mp_speak_label.add_theme_font_size_override("normal_font_size", int(Dp.px(13)))
	_mp_speak_label.add_theme_constant_override("outline_size", int(Dp.px(3)))
	_mp_speak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_mp_speak_label.visible = false
	$UI.add_child(_mp_speak_label)
	var v := _mp_voice()
	if v != null:
		v.speaking_changed.connect(func(_seat: int, _on: bool): _refresh_speakers())
		v.mode_changed.connect(func(_m: int): _update_mic_button())
		v.permission_denied.connect(func():
			_update_mic_button()
			_toast(tr("toast.voice_no_permission")))


		v.mic_trouble.connect(func(grund: String):


			_toast(tr(VoiceChat.trouble_text_key(grund, "toast.mic_")))
			print("Sprechfunk: %s (Frames %d, davon ≠0 %d, Spitze %.5f, Schwelle %.5f)" % [
					grund, v.stat_frames, v.stat_nonzero, v.stat_block_peak, v.open_threshold()]))
	_update_mic_button()


	if v != null and _mp.active() and VoiceChat.enabled():
		v.ensure_permission()

	_voice_intro_pending = _mp.active() and _voice_intro_due()
	_mp.chat_added.connect(_on_mp_chat)
	_mp.state_changed.connect(_on_mp_state)
	if _mp.session != null:
		_mp.session.waiting_changed.connect(_on_mp_waiting)
		_mp.session.desynced.connect(_on_mp_desync)
	var args := OS.get_cmdline_user_args()
	var ak := args.find("--mp-autoplay")
	if ak >= 0 and ak + 1 < args.size():
		_mp_autoplay = int(args[ak + 1])
	var ck := args.find("--mp-chat-every")
	if ck >= 0 and ck + 1 < args.size():
		_mp_chat_every = maxi(int(args[ck + 1]), 1)
	var sk := args.find("--mp-shot")
	if sk >= 0 and sk + 1 < args.size():
		_mp_shot_dir = args[sk + 1]
		DirAccess.make_dir_recursive_absolute(_mp_shot_dir)


	var vk := args.find("--mp-voice")
	if vk >= 0:
		var v2 := _mp_voice()
		if v2 != null:
			v2.test_tone = true
			var offen: bool = vk + 1 < args.size() and args[vk + 1] == "all"
			v2.set_mode(VoiceChat.Mode.ALL if offen else VoiceChat.Mode.TEAM)
			v2.speaking_changed.connect(func(seat: int, on: bool):
				print("MP-FUNK seat %d %s" % [seat, "an" if on else "aus"]))
			_update_mic_button()


	if (_mp_autoplay >= 0 or args.has("--mp-log")) and _mp.session != null:
		_mp.session.frame_done.connect(func(f: int, tick: int, h: String):
			if h != "":
				print("MP-FRAME %d tick %d hash %s" % [f, tick, h]))
	_layout_ui()


func _mp_active() -> bool:
	return _mp != null and _mp.active()


func _on_mp_chat(line: Dictionary) -> void:

	if _mp.session != null and not _mp.session.alive_seats.has(int(line.get("seat", -1))):
		if str(line.get("kind", "")) != "system":
			pass
	_mp_lines.append([ChatPanel.format_line(line), Time.get_ticks_msec() / 1000.0 + MP_LINE_SECONDS])
	while _mp_lines.size() > MP_LINES:
		_mp_lines.remove_at(0)
	_refresh_mp_lines()


func _refresh_mp_lines() -> void:
	if _mp_chat_label == null:
		return
	var out: Array = []
	for l in _mp_lines:
		out.append(str(l[0]))
	_mp_chat_label.text = "\n".join(PackedStringArray(out))
	_mp_chat_label.visible = not out.is_empty()


func _toggle_chat_input() -> void:
	if _mp_chat_panel == null:
		return
	if _mp_chat_panel.visible:
		_close_chat_input()
		return
	_mp_chat_panel.visible = true
	_mp_chat_panel.focus_input()
	gestures.input_blocked = true
	DisplayServer.virtual_keyboard_show("")


func _mp_voice() -> Node:
	var hub := NetHub.hub()
	return hub.voice if hub != null else null


func _list_voice() -> Node:
	return _mp_voice() if _mp_active() else null


func _toggle_mic(open_channel: bool) -> void:
	var v := _mp_voice()
	if v == null:
		return
	if not VoiceChat.enabled():
		_toast(tr("toast.voice_off_setting"))
		return


	if _voice_power_blocked() and int(v.mode) == int(VoiceChat.Mode.OFF):
		_toast(tr("toast.voice_no_power"))
		_update_mic_button()
		return
	var m: int = v.toggle_all() if open_channel else v.toggle_team()
	_update_mic_button()
	if m == VoiceChat.Mode.ALL:
		_toast(tr("toast.voice_all"))
	elif m == VoiceChat.Mode.TEAM:
		_toast(tr("toast.voice_team"))
	else:
		_toast(tr("toast.voice_off"))


func _voice_intro_text() -> String:
	return "[b]%s[/b]\n\n[color=#%s]●[/color] %s\n[color=#%s]●[/color] %s\n\n%s" % [
		tr("mp.voice_intro_title"),
		HudTheme.VOICE_TEAM.to_html(false), tr("mp.voice_intro_tap"),
		HudTheme.VOICE_ALL.to_html(false), tr("mp.voice_intro_hold"),
		tr("mp.voice_intro_more")]


func _show_voice_intro() -> void:
	var anchor := HudTheme.visible_rect(_mp_mic_btn) if _mp_mic_btn != null else Rect2()
	HudTheme.show_help_popup($UI, "", anchor, _voice_intro_text())


func _voice_intro_due() -> bool:
	return not VoiceChat.intro_seen()


func _voice_power_blocked() -> bool:
	return world != null and world.sim != null and world.low_power()


func _update_voice_power() -> void:
	if _mp_mic_btn == null:
		return
	var v := _mp_voice()
	if v == null:
		return
	var blocked := _voice_power_blocked()
	if blocked == _voice_power_was:
		return
	_voice_power_was = blocked
	if blocked:


		v.mute_receive(true)
		if int(v.mode) != int(VoiceChat.Mode.OFF):
			_voice_power_hold = int(v.mode)
			v.set_mode(VoiceChat.Mode.OFF)
			AudioMix.radio_dropout()
			_toast(tr("toast.voice_no_power"))
	else:
		v.mute_receive(false)
		if _voice_power_hold != int(VoiceChat.Mode.OFF):
			v.set_mode(_voice_power_hold)
			_voice_power_hold = int(VoiceChat.Mode.OFF)
			_toast(tr("toast.voice_power_back"))
	_update_mic_button()


func _update_mic_button() -> void:
	if _mp_mic_btn == null:
		return
	var v := _mp_voice()
	var m: int = int(v.mode) if v != null else int(VoiceChat.Mode.OFF)
	var col := HudTheme.VOICE_OFF
	var text := ""
	if m == VoiceChat.Mode.TEAM:
		col = HudTheme.VOICE_TEAM
		text = tr("mp.voice_team")
	elif m == VoiceChat.Mode.ALL:
		col = HudTheme.VOICE_ALL
		text = tr("mp.voice_all")


	var blocked := _voice_power_blocked()
	if blocked:
		col = HudTheme.VOICE_BLOCKED
		text = tr("status.power")
	for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		_mp_mic_btn.add_theme_color_override(state, col)
	_mp_mic_btn.add_theme_color_override("icon_pressed_color", col.darkened(0.3))


	_mp_mic_btn.modulate = Color(1, 1, 1, 1.0 if m != VoiceChat.Mode.OFF and not blocked
			else HudTheme.ICON_BUTTON_ALPHA)
	if _mp_mic_label != null:
		_mp_mic_label.text = text
		_mp_mic_label.add_theme_color_override("font_color", col)
		_mp_mic_label.visible = text != ""


func _refresh_speakers() -> void:
	if _mp_speak_label == null:
		return
	var v := _mp_voice()
	if v == null:
		_mp_speak_label.visible = false
		return
	var out: Array = []
	for seat in v.speaking_seats():
		var info: Dictionary = v.speaker_info(int(seat))
		var col: Color = ChatPanel.player_color(int(info.get("color", 0)))
		var mark := tr("mp.voice_all_mark") if str(info.get("scope", "team")) == "all" else ""
		out.append("[color=#%s]%s %s%s[/color]" % [col.to_html(false), tr("mp.voice_speaking"),
				str(info.get("name", "?")), mark])
	_mp_speak_label.text = "\n".join(PackedStringArray(out))
	_mp_speak_label.visible = not out.is_empty()


func _close_chat_input() -> void:
	if _mp_chat_panel == null:
		return
	_mp_chat_panel.release_input()
	_mp_chat_panel.visible = false
	gestures.input_blocked = false
	DisplayServer.virtual_keyboard_hide()


func _on_mp_waiting(on: bool, seats: Array) -> void:
	if not on:
		_mp_wait_since = -1.0
		return
	_mp_wait_since = Time.get_ticks_msec() / 1000.0
	var names: Array = []
	for s in seats:
		names.append(_mp.session.name_of_seat(int(s)))
	_mp_notice.set_meta("names", ", ".join(PackedStringArray(names)))


func _on_mp_desync(frame_no: int, hashes: Dictionary) -> void:
	_mp_over = "desync"
	_mp_notice.text = tr("mp.desync") % frame_no
	print("Mehrspieler: Desync bei Rahmen %d — %s" % [frame_no, JSON.stringify(hashes)])
	_save_desync_state(frame_no)


func _on_mp_state(what: String) -> void:
	if what == "closed":
		_mp_over = "lost"
		_mp_notice.text = tr("mp.lost")
		if _mp.session != null:
			_mp.session.drop("closed")


func _save_desync_state(frame_no: int) -> void:
	if world.sim == null or not world.sim.has_method("save_state"):
		return
	DirAccess.make_dir_recursive_absolute("user://logs")
	var path := "user://logs/desync-%s-%d.bin" % [str(_mp.code), int(_mp.my_seat)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(world.sim.save_state())
		f.close()
		print("Mehrspieler: Zustand nach %s geschrieben (Rahmen %d)" % [path, frame_no])


func _mp_surrender() -> void:
	world.issue(NetOrders.make(NetOrders.OP_SURRENDER))
	_toggle_menu(false)


func _show_player_list() -> void:
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.name = "PlayerList"
	panel.add_to_group("modal")
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var title := Label.new()
	title.text = tr("pause.players")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(Dp.px(18)))
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	var hint := Label.new()
	hint.text = tr("pause.players_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(Dp.px(PLAYER_ROW_DP), 0)
	hint.add_theme_font_size_override("font_size", int(Dp.px(11)))
	hint.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(hint)
	var rows := VBoxContainer.new()
	rows.name = "PlayerRows"
	rows.add_theme_constant_override("separation", int(Dp.px(3)))


	var order: Array = world.player_roster.duplicate()
	order.sort_custom(func(a, b):
		var ka: int = int(a.get("team", 0)) if int(a.get("team", 0)) > 0 else 99
		var kb: int = int(b.get("team", 0)) if int(b.get("team", 0)) > 0 else 99
		if ka != kb:
			return ka < kb
		return int(a.get("sim", 0)) < int(b.get("sim", 0)))
	var refreshers: Array = []
	for e in order:
		rows.add_child(_player_row(e, refreshers))
	if order.is_empty():
		var leer := Label.new()
		leer.text = tr("pause.players_none")
		leer.add_theme_font_size_override("font_size", int(Dp.px(12)))
		leer.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		rows.add_child(leer)
	box.add_child(rows)
	var vc := _list_voice()
	if _mp_active():

		var ct := Label.new()
		ct.text = tr("mp.chat_log")
		ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ct.add_theme_font_size_override("font_size", int(Dp.px(12)))
		ct.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		box.add_child(ct)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.custom_minimum_size = Vector2(Dp.px(320), Dp.px(120))
		rt.add_theme_font_size_override("normal_font_size", int(Dp.px(12)))
		for line in (_mp.chat if _mp != null else []):
			rt.append_text(ChatPanel.format_line(line) + "\n")
		box.add_child(rt)
	if vc != null:

		var again := Button.new()
		again.text = tr("mp.voice_intro_again")
		again.custom_minimum_size = Vector2(Dp.px(220), Dp.px(38))
		HudTheme.style_button(again, 11.0)
		again.pressed.connect(_show_voice_intro)
		var again_center := CenterContainer.new()
		again_center.add_child(again)
		box.add_child(again_center)
	var close := Button.new()
	close.text = tr("ui.back")
	close.custom_minimum_size = Vector2(Dp.px(160), Dp.px(44))
	HudTheme.plate_button_style(close, 14.0)
	close.pressed.connect(func():
		panel.queue_free()
		backdrop.queue_free()
		world.paused = _menu_panel.visible and not _mp_active())
	var close_center := CenterContainer.new()
	close_center.add_child(close)
	box.add_child(close_center)
	panel.add_child(box)
	$UI.add_child(panel)
	_center_panel(panel)


	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(func():
		for fn in refreshers:
			(fn as Callable).call())
	panel.add_child(timer)
	timer.start()


func _player_row(e: Dictionary, refreshers: Array) -> Control:
	var pid := int(e.get("sim", 0))
	var seat := int(e.get("seat", -1))
	var row := HBoxContainer.new()
	row.name = "Row%d" % pid

	row.set_meta("sim", pid)
	row.set_meta("seat", seat)
	row.set_meta("color", e.get("color", Color.WHITE))
	row.add_theme_constant_override("separation", int(Dp.px(5)))


	var dot := ColorRect.new()
	dot.color = e.get("color", Color.WHITE)
	dot.custom_minimum_size = Vector2(Dp.px(12), Dp.px(12))
	var dot_box := CenterContainer.new()
	dot_box.add_child(dot)
	row.add_child(dot_box)
	var name_lbl := Label.new()
	name_lbl.text = _roster_name(e)
	name_lbl.clip_text = true
	name_lbl.custom_minimum_size = Vector2(Dp.px(96), Dp.px(22))
	name_lbl.add_theme_font_size_override("font_size", int(Dp.px(12)))
	row.add_child(name_lbl)
	var human: bool = str(e.get("kind", "human")) == "human"
	var team := int(e.get("team", 0))
	row.add_child(_player_cell(tr("lobby.team") % str(team) if team > 0 else tr("lobby.team_none"),
			56.0, HudTheme.GOLD if team > 0 else HudTheme.TEXT_DIM))
	var rel_lbl := _player_cell("", 76.0, HudTheme.TEXT)
	row.add_child(rel_lbl)
	var state_lbl := _player_cell("", 104.0, HudTheme.TEXT)
	row.add_child(state_lbl)

	var vc := _list_voice()
	var mute_btn: Button = null
	if vc != null and seat >= 0 and human and _mp != null and seat != int(_mp.my_seat):
		mute_btn = Button.new()
		mute_btn.custom_minimum_size = Vector2(Dp.px(70), Dp.px(30))
		HudTheme.style_button(mute_btn, 10.0)
		mute_btn.pressed.connect(func():
			vc.set_muted(seat, not vc.is_muted(seat))
			for fn in refreshers:
				(fn as Callable).call()
			_refresh_speakers())
		row.add_child(mute_btn)
	var refresh := func():
		var st: Dictionary = world.roster_status(pid)
		var rel := str(st.get("relation", "enemy"))
		rel_lbl.text = tr("pause.rel_" + rel)
		rel_lbl.add_theme_color_override("font_color", PLAYER_REL_COLORS.get(rel, HudTheme.TEXT))


		var im_netz: bool = human and seat >= 0 and _mp_active() and _mp.session != null
		var gone: bool = im_netz and not _mp.session.alive_seats.has(seat)
		var stalled: bool = im_netz and _mp.session.waiting and _mp.session.waiting_seats.has(seat)


		var ws := int(st.get("win_state", 0))
		var alive := int(st.get("alive", 0))
		if gone:
			state_lbl.text = tr("pause.state_gone")
			state_lbl.add_theme_color_override("font_color", HudTheme.MODE_SELL)
		elif ws == 1:
			state_lbl.text = tr("mp.result_win")
			state_lbl.add_theme_color_override("font_color", HudTheme.READY_GREEN)
		elif ws == 2 or alive <= 0:
			state_lbl.text = tr("pause.state_defeated")
			state_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		elif stalled:
			state_lbl.text = tr("pause.state_stalled")
			state_lbl.add_theme_color_override("font_color", HudTheme.MODE_ADD)
		else:
			state_lbl.text = tr("pause.state_alive") % alive
			state_lbl.add_theme_color_override("font_color", HudTheme.TEXT)
		var dim: bool = gone or ws == 2 or alive <= 0
		name_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM if dim
				else (HudTheme.GOLD if rel == "self" else HudTheme.TEXT))
		if mute_btn != null:
			var muted: bool = vc.is_muted(seat)
			mute_btn.text = tr("mp.voice_muted_mark") if muted else tr("mp.voice_audible")
			mute_btn.add_theme_color_override("font_color",
					HudTheme.TEXT_DIM if muted else HudTheme.TEXT)
	refresh.call()
	refreshers.append(refresh)
	return row


func _player_cell(text: String, width_dp: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.custom_minimum_size = Vector2(Dp.px(width_dp), Dp.px(22))
	l.add_theme_font_size_override("font_size", int(Dp.px(11)))
	l.add_theme_color_override("font_color", col)
	return l


func _roster_name(e: Dictionary) -> String:
	if str(e.get("kind", "human")) == "bot":
		var lvl := str(e.get("level", "normal"))
		var key := "menu.skirmish.ai_" + lvl
		var lvl_text := tr(key)
		if lvl_text == key:
			lvl_text = lvl
		var no := int(e.get("bot_no", 0))
		var base: String = (tr("lobby.ai") % no) if no > 0 else tr("mp.bot")


		var strat := str(e.get("strategy", ""))
		if strat == "":
			return "%s (%s)" % [base, lvl_text]
		var skey := "menu.skirmish.strat_" + strat
		var stext := tr(skey)
		if stext == skey:
			stext = strat
		return "%s (%s, %s)" % [base, lvl_text, stext]
	var n := str(e.get("name", ""))
	if n == "":


		var cfg := ConfigFile.new()
		if cfg.load("user://settings.cfg") == OK:
			n = str(cfg.get_value("multiplayer", "name", ""))
	return n if n != "" else tr("lobby.you")


func _mp_scoreboard(box: VBoxContainer) -> void:
	if not _mp_active() or _mp.session == null:
		return
	for e in _mp.session.seats:
		var pid := int(e.get("sim", 0))
		var l := Label.new()
		var ws: int = world.sim.win_state(pid)
		var mark := tr("mp.result_win") if ws == 1 else (tr("mp.result_loss") if ws == 2 else tr("mp.result_open"))
		l.text = "%s — %s (%s)" % [str(e.get("name", "?")), mark, tr("faction." + str(e.get("faction", "allies")))]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(Dp.px(12)))
		l.add_theme_color_override("font_color", ChatPanel.player_color(int(e.get("color", 0))))
		box.add_child(l)


func _update_mp_hud(_delta: float) -> void:
	if not _mp_active():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for i in range(_mp_lines.size() - 1, -1, -1):
		if now >= float(_mp_lines[i][1]):
			_mp_lines.remove_at(i)
			changed = true
	if changed:
		_refresh_mp_lines()
	var s = _mp.session
	if _mp_ping != null:
		var ping: int = _mp.client.ping_ms if _mp.client != null else -1
		_mp_ping.text = "%s  %s" % [
			(tr("mp.ping") % ping) if ping >= 0 else tr("mp.ping_none"),
			tr("mp.lag") % s.lag_frames()]

	if _mp_over != "":

		_mp_notice.visible = false
		_mp_notice_bg.visible = false
		if not _game_over_shown:
			_mp_end_game()
	elif s != null and s.waiting:
		var secs := 0.0 if _mp_wait_since < 0.0 else now - _mp_wait_since
		var names: String = str(_mp_notice.get_meta("names", "?"))
		_mp_notice.text = tr("mp.waiting") % [names, secs]
		_mp_notice.visible = true
		_mp_notice_bg.visible = true
	else:
		_mp_notice.visible = false
		_mp_notice_bg.visible = false

	if _voice_intro_pending and s != null and s.frame >= 2:
		_voice_intro_pending = false
		VoiceChat.set_intro_seen(true)
		_show_voice_intro()
	if _mp_chat_every > 0 and s != null and s.frame / _mp_chat_every != _mp_chat_last:
		_mp_chat_last = s.frame / _mp_chat_every
		_mp_chat_sent += 1
		var quick: Array = ChatPanel.QUICK
		if _mp_chat_sent % 2 == 0:
			_mp.send_chat(str(quick[_mp_chat_sent % quick.size()]), "all")
		else:
			_mp.send_chat("Rahmen %d, Zeile %d" % [s.frame, _mp_chat_sent], "all")
	_mp_shot_tick(s)
	if _mp_autoplay >= 0 and s != null:
		_run_mp_autoplay(s)


func _mp_end_game() -> void:
	_game_over_shown = true
	var backdrop := HudTheme.dim_backdrop($UI)
	var panel := PanelContainer.new()
	panel.add_to_group("modal")
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	var l := Label.new()
	l.text = tr("mp.desync_title") if _mp_over == "desync" else tr("mp.lost")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(Dp.px(22)))
	l.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25))
	box.add_child(l)
	_mp_scoreboard(box)
	var menu_btn := Button.new()
	menu_btn.text = tr("gameover.main_menu")
	menu_btn.custom_minimum_size = Vector2(Dp.px(180), Dp.px(46))
	HudTheme.plate_button_style(menu_btn, 15.0)
	menu_btn.pressed.connect(func():
		if _mp != null:
			_mp.leave()
		_leave_battlefield())
	box.add_child(menu_btn)
	panel.add_child(box)
	$UI.add_child(panel)
	_center_panel(panel)


func _run_mp_autoplay(s) -> void:
	if s.frame >= _mp_autoplay:
		print("T: mp-autoplay fertig — Rahmen %d, Tick %d, Hash %s, Chatzeilen gesendet %d, empfangen %d" % [
				s.frame, world.sim.tick(), s.last_hash, _mp_chat_sent, _mp.chat.size()])


		var seen := {}
		for u in world.units:
			if u.alive and u.type != "" and u.player != world.local_player \
					and u.player != ProtoWorld.PLAYER_NEUTRAL and u.player != ProtoWorld.PLAYER_CREEPS:
				seen[u.player] = world.hostile(world.local_player, u.player)
		print("T: mp-bündnis — Spieler %d sieht %s (true = angreifbar)" % [world.local_player, seen])
		get_tree().quit()
		return
	var step := int(s.frame / 25)
	if step == _mp_autoplay_step:
		return
	_mp_autoplay_step = step


	var mid := Vector2i(world.map_w / 2, world.map_h / 2)
	match step % 4:
		1:
			if world.type_ids.has("powr"):
				world.issue(NetOrders.make(NetOrders.OP_QUEUE_BUILD, world.type_ids["powr"]))
		2:
			var ids := PackedInt32Array()
			for u in world.units:
				if u.alive and u.player == world.local_player and not world.types[u.type].get("building", false):
					ids.append(u.id)
			if ids.size() > 0:
				world.issue(NetOrders.make(NetOrders.OP_MOVE, mid.x, mid.y, 0, 0, ids))
		3:
			world.issue(NetOrders.make(NetOrders.OP_STOP, 0, 0, 0, 0, PackedInt32Array()))
		_:
			pass


func _layout_mp(safe: Rect2, m: float) -> void:
	if _mp_chat_label == null:
		return
	var off := safe.position
	var vs := safe.position + safe.size

	_mp_chat_label.position = Vector2(off.x + m + Dp.px(HudTheme.GROUP_BTN_W_DP) + m, off.y + m + Dp.px(TOP_ICON_BTN_DP) + m)
	_mp_chat_label.size = Vector2(Dp.px(320), Dp.px(80))
	if _mp_speak_label != null:
		_mp_speak_label.position = _mp_chat_label.position + Vector2(0, Dp.px(84))
		_mp_speak_label.size = Vector2(Dp.px(320), Dp.px(60))


	var anchor: Button = _mp_mic_btn if _mp_mic_btn != null else _mp_chat_btn
	if anchor != null:
		var r := HudTheme.visible_rect(anchor)
		_mp_ping.position = Vector2(r.end.x + m / 2.0, r.position.y + r.size.y / 2.0 - Dp.px(14))
		_mp_ping.size = Vector2(Dp.px(120), Dp.px(14))
		if _mp_mic_label != null:
			_mp_mic_label.position = Vector2(r.end.x + m / 2.0, r.position.y + r.size.y / 2.0 + Dp.px(2))
			_mp_mic_label.size = Vector2(Dp.px(120), Dp.px(14))
	var nw := minf(Dp.px(360), safe.size.x - 2 * m)
	var nh := Dp.px(56)
	var np := Vector2(off.x + (safe.size.x - nw) / 2.0, off.y + safe.size.y * 0.32)
	_mp_notice_bg.position = np
	_mp_notice_bg.size = Vector2(nw, nh)
	_mp_notice.position = np
	_mp_notice.size = Vector2(nw, nh)
	if _mp_chat_panel != null:
		var cw := minf(Dp.px(460), safe.size.x - 2 * m)
		_mp_chat_panel.size = Vector2(cw, Dp.px(92))
		_mp_chat_panel.position = Vector2(off.x + (safe.size.x - cw) / 2.0,
				vs.y - build_bar.size.y - Dp.px(100))


func _mp_leave_battle() -> void:
	if _mp != null:
		_mp.leave()
	_leave_battlefield()


func _mp_shot_tick(s) -> void:
	if _mp_shot_dir == "" or s == null:
		return
	var who := str(_mp.session.name_of_seat(int(_mp.my_seat))).to_lower()
	if s.frame >= 40:
		_mp_shot("spiel", who)
	if not _mp_lines.is_empty():
		_mp_shot("chat", who)
	if s.waiting:
		_mp_shot("warten", who)
	if _mp_over != "":
		_mp_shot("verbindung", who)

	if s.frame >= 60 and not _mp_shot_done.has("chateingabe"):
		if _mp_chat_panel != null and not _mp_chat_panel.visible:
			_mp_chat_panel.visible = true
			return
		_mp_shot("chateingabe", who)
		_mp_chat_panel.visible = false


func _run_test_sprechfunk() -> void:
	while world.sim == null or world.sim.tick() < 60:
		await get_tree().process_frame
	var hub := NetHub.hub()
	var v = hub.ensure_voice()
	v.test_tone = true
	var fehler := 0
	print("T --test-sprechfunk: Format %d Hz mono, %d ms je Paket (%d Abtastwerte), IMA-ADPCM 4 Bit" % [
			VoiceChat.RATE, VoiceChat.PACKET_MS, VoiceChat.SAMPLES])
	var st: Dictionary = VoiceChat.self_test()
	print("T --test-sprechfunk: Codec — %d Blöcke, %d Byte je Paket, %d Zeichen Base64, Rauschabstand %.1f dB" % [
			int(st["blocks"]), int(st["bytes"]), int(st["base64"]), float(st["snr_db"])])
	print("T --test-sprechfunk: Bandbreite je aktivem Sprecher %d Byte/s (%.1f kbit/s)" % [
			int(st["bytes_per_second"]), int(st["bytes_per_second"]) * 8.0 / 1000.0])
	if float(st["snr_db"]) < 18.0:
		fehler += 1
		print("T --test-sprechfunk: FEHLER — Rauschabstand unter 18 dB")
	if int(st["base64"]) > 4096:
		fehler += 1
		print("T --test-sprechfunk: FEHLER — Paket über der 16-KB-Grenze des Vermittlers")
	if _mp_mic_btn == null:
		print("T --test-sprechfunk: FEHLER — kein Mikrofonknopf im HUD")
		get_tree().quit()
		return

	var rq := HudTheme.visible_rect(_menu_button)
	var rc := HudTheme.visible_rect(_mp_chat_btn)
	var rm := HudTheme.visible_rect(_mp_mic_btn)
	var reihe: bool = rc.position.x > rq.position.x and rm.position.x > rc.position.x \
			and absf(rc.position.y - rq.position.y) < 2.0 and absf(rm.position.y - rq.position.y) < 2.0 \
			and rc.size.is_equal_approx(rq.size) and rm.size.is_equal_approx(rq.size)
	print("T --test-sprechfunk: Kopfzeile Menü %s → Chat %s → Mikrofon %s (je %s) — %s" % [
			rq.position, rc.position, rm.position, rq.size, "OK" if reihe else "FEHLER"])
	fehler += 0 if reihe else 1

	for paar in [["Chat", _mp_chat_btn], ["Mikrofon", _mp_mic_btn]]:
		var hit: Rect2 = (paar[1] as Button).get_global_rect()
		var w := Dp.to_device_dp(hit.size.x)
		var h := Dp.to_device_dp(hit.size.y)
		var gross: bool = w >= HudTheme.MIN_TOUCH_DP - 0.5 and h >= HudTheme.MIN_TOUCH_DP - 0.5
		print("T --test-sprechfunk: Tippfläche %s %.0f×%.0f Geräte-dp (Sollwert ≥ %d) — %s" % [
				paar[0], w, h, HudTheme.MIN_TOUCH_DP, "OK" if gross else "FEHLER"])
		fehler += 0 if gross else 1
	await _shot_voice("aus")
	print("T --test-sprechfunk: aus — Symbolfarbe %s" % _mp_mic_btn.get_theme_color("icon_normal_color").to_html(false))
	_toggle_mic(false)
	await _shot_voice("team")
	var team_ok: bool = int(v.mode) == int(VoiceChat.Mode.TEAM) \
			and _mp_mic_btn.get_theme_color("icon_normal_color").is_equal_approx(HudTheme.VOICE_TEAM)
	print("T --test-sprechfunk: Tipp → Team-Kanal, Farbe %s — %s" % [
			HudTheme.VOICE_TEAM.to_html(false), "OK" if team_ok else "FEHLER"])
	fehler += 0 if team_ok else 1
	_toggle_mic(true)
	await _shot_voice("alle")
	var all_ok: bool = int(v.mode) == int(VoiceChat.Mode.ALL) \
			and _mp_mic_btn.get_theme_color("icon_normal_color").is_equal_approx(HudTheme.VOICE_ALL)
	print("T --test-sprechfunk: Langdruck → offener Kanal, Farbe %s — %s" % [
			HudTheme.VOICE_ALL.to_html(false), "OK" if all_ok else "FEHLER"])
	fehler += 0 if all_ok else 1

	var pkt := VoiceChat.test_packet(300.0)
	var pkt2 := VoiceChat.test_packet(180.0)
	for i in 12:
		v.on_packet({"seat": 1, "name": "Jan", "color": 1, "scope": "team", "seq": i, "data": pkt})
		v.on_packet({"seat": 2, "name": "Ole", "color": 2, "scope": "all", "seq": i, "data": pkt2})
	_refresh_speakers()
	await _shot_voice("sprecher")
	var zwei: bool = v.speaking_seats().size() == 2 and _mp_speak_label.visible
	print("T --test-sprechfunk: zwei Sprecher angezeigt — %s (%s)" % [
			"OK" if zwei else "FEHLER", _mp_speak_label.text.replace("\n", " | ")])
	fehler += 0 if zwei else 1
	v.set_muted(1, true)
	for i in 12:
		v.on_packet({"seat": 1, "name": "Jan", "color": 1, "scope": "team", "seq": 20 + i, "data": pkt})
	var stumm: bool = not v.speaking_seats().has(1)
	print("T --test-sprechfunk: stummgeschalteter Platz wird verworfen — %s" % ["OK" if stumm else "FEHLER"])
	fehler += 0 if stumm else 1

	VoiceChat.set_enabled(false)
	v.set_mode(VoiceChat.Mode.OFF)
	var aus: bool = v.set_mode(VoiceChat.Mode.TEAM) == int(VoiceChat.Mode.OFF)
	VoiceChat.set_enabled(true)
	print("T --test-sprechfunk: abgeschaltet bleibt das Mikrofon aus — %s" % ["OK" if aus else "FEHLER"])
	fehler += 0 if aus else 1

	var intro_vorher := VoiceChat.intro_seen()
	VoiceChat.set_intro_seen(false)
	var faellig_vorher := _voice_intro_due()
	var locale_vorher := TranslationServer.get_locale()
	for sprache in ["de", "en"]:
		TranslationServer.set_locale(sprache)
		for n in get_tree().get_nodes_in_group("modal"):
			n.queue_free()
		await get_tree().process_frame
		_show_voice_intro()
		await _shot_voice("info_" + sprache)
		var tafel := $UI.get_node_or_null("HelpPopupOverlay")
		var steht: bool = tafel != null and tafel.visible
		print("T --test-sprechfunk: Erstinfo %s steht — %s" % [sprache, "OK" if steht else "FEHLER"])
		fehler += 0 if steht else 1
	TranslationServer.set_locale(locale_vorher)
	for n in get_tree().get_nodes_in_group("modal"):
		n.queue_free()
	await get_tree().process_frame

	_toggle_menu(true)
	_show_options()
	for _i in 4:
		await get_tree().process_frame

	for n in get_tree().get_nodes_in_group("modal"):
		_rolle_ans_ende(n)
	for _i in 3:
		await get_tree().process_frame
	await _shot_voice("optionen")


	var vpr := _mp_voice()
	if vpr != null:
		vpr.probe = true
		vpr.test_tone = false
		vpr.reset_gate()
		vpr.reset_stats()
		vpr.stat_frames = 4800
		vpr.stat_nonzero = 4700
		vpr.feed_level(0.001, 20)
		vpr.feed_level(0.030, 3)
		await _shot_voice("probe")
		print("T --test-sprechfunk: Mikrofonprobe zeigt Pegel %.4f, Schwelle %.4f, Schleuse %s" % [
				vpr.rms(), vpr.open_threshold(), "offen" if vpr.gate_open() else "zu"])
		vpr.probe = false
		vpr.test_tone = true
	var probe_da := false
	for n in get_tree().get_nodes_in_group("modal"):
		if str(n.name).find("Options") >= 0 or true:
			probe_da = probe_da or _findet_text(n, tr("menu.options.mic_probe"))
	print("T --test-sprechfunk: Mikrofonprobe steht in den Optionen — %s" % ["OK" if probe_da else "FEHLER"])
	fehler += 0 if probe_da else 1
	for n in get_tree().get_nodes_in_group("modal"):
		n.queue_free()
	_toggle_menu(false)
	await get_tree().process_frame

	VoiceChat.set_intro_seen(true)
	var faellig_nachher := _voice_intro_due()
	print("T --test-sprechfunk: Erstinfo fällig vor dem ersten Start %s, nach dem Merker %s — %s" % [
			faellig_vorher, faellig_nachher, "OK" if faellig_vorher and not faellig_nachher else "FEHLER"])
	fehler += 0 if (faellig_vorher and not faellig_nachher) else 1
	VoiceChat.set_intro_seen(intro_vorher)


	if _resizer != null:
		_resizer.paused = true
	var verstoesse := 0
	for e in LAYOUT_MATRIX:
		DisplayServer.window_set_size(Vector2i(e[0], e[1]))
		Dp.set_forced_dpi(float(e[2]))
		Dp.set_ui_scale(1.0)
		await get_tree().process_frame
		_layout_ui()
		for _i in 3:
			await get_tree().process_frame
		var real := DisplayServer.window_get_size()

		for seite in ["hud", "optionen"]:
			if seite == "optionen":
				_toggle_menu(true)
				_show_options()
				for _i in 4:
					await get_tree().process_frame
			var tag := "funk %s %dx%d@%d" % [seite, real.x, real.y, e[2]]
			for line in LayoutCheck.violations($UI, Dp.safe_rect(), tag):
				print(line)
				verstoesse += 1
			for line in LayoutCheck.overlap_violations($UI, tag):
				print(line)
				verstoesse += 1
			if seite == "hud" and _map_rect.size.x > 0.0:
				for line in LayoutCheck.map_violations($UI, _map_rect, tag):
					print(line)
					verstoesse += 1
			if seite == "optionen":
				for n in get_tree().get_nodes_in_group("modal"):
					n.queue_free()
				_toggle_menu(false)
				await get_tree().process_frame
	print("T --test-sprechfunk: Layout mit Mikrofonknopf — %d Verstöße (Sollwert 0)" % verstoesse)
	fehler += verstoesse


	DisplayServer.window_set_size(Vector2i(LAYOUT_MATRIX[0][0], LAYOUT_MATRIX[0][1]))
	Dp.set_forced_dpi(float(LAYOUT_MATRIX[0][2]))
	Dp.set_ui_scale(1.0)
	await get_tree().process_frame
	_layout_ui()
	await get_tree().process_frame
	var mp_rects := {}


	var soll_folge: Array = visible_cmd_order()
	for id in soll_folge:
		mp_rects[id] = HudTheme.visible_rect(_cmd_buttons[id])
	var gleiche_folge: bool = _cmd_order == soll_folge
	for b in [_mp_chat_btn, _mp_mic_btn]:
		if b != null:
			_cmd_buttons.erase("chat" if b == _mp_chat_btn else "mic")
			b.queue_free()
	_mp_chat_btn = null
	_mp_mic_btn = null
	_mp_mic_label.visible = false
	await get_tree().process_frame
	_layout_ui()
	await get_tree().process_frame
	var gleich := 0
	for id in soll_folge:
		var r_sp: Rect2 = HudTheme.visible_rect(_cmd_buttons[id])
		var r_mp: Rect2 = mp_rects[id]
		if r_sp.position.is_equal_approx(r_mp.position) and r_sp.size.is_equal_approx(r_mp.size):
			gleich += 1
		else:
			print("T --test-sprechfunk: FEHLER Knopf %s — Mehrspieler %s, Einzelspieler %s" % [id, r_mp, r_sp])
	print("T --test-sprechfunk: untere Leiste — Reihenfolge gleich %s, %d von %d Knöpfen deckungsgleich (Sollwert %d)" % [
			gleiche_folge, gleich, soll_folge.size(), soll_folge.size()])
	print("T --test-sprechfunk: erster Knopf %s, letzter Knopf %s" % [
			mp_rects[soll_folge[0]], mp_rects[soll_folge[soll_folge.size() - 1]]])
	fehler += (0 if gleiche_folge else 1) + (soll_folge.size() - gleich)
	print("T --test-sprechfunk: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


func _run_test_mikrofon() -> void:
	while world.sim == null or world.sim.tick() < 30:
		await get_tree().process_frame
	var hub := NetHub.hub()
	var v = hub.ensure_voice()
	v.test_tone = false
	print("T --test-mikrofon: Mischrate %d Hz, Eingabegerät '%s'" % [
			int(AudioServer.get_mix_rate()), AudioServer.input_device])
	print("T --test-mikrofon: Eingabegeräte: %s" % ", ".join(AudioServer.get_input_device_list()))
	print("T --test-mikrofon: Projekteinstellung audio/driver/enable_input = %s" % [
			ProjectSettings.get_setting("audio/driver/enable_input", false)])
	print("T --test-mikrofon: Freigabe (has_permission) %s, Zustand '%s' auf %s" % [
			VoiceChat.has_permission(), VoiceChat.permission_state(), OS.get_name()])


	for zeile in VoiceChat.AndroidPlugin.self_test():
		print("T --test-mikrofon: Attrappen %s" % zeile)


	print("T --test-mikrofon: Singleton '%s' geladen: %s, micStart nutzbar: %s" % [
			VoiceChat.PLUGIN_SINGLETON, VoiceChat.plugin_singleton() != null,
			VoiceChat.mic_plugin() != null])
	var gemeldet := {"v": ""}
	v.mic_trouble.connect(func(grund: String): gemeldet.v = grund)
	v.set_mode(VoiceChat.Mode.TEAM)
	var quelle_ok: bool = (v.source() == VoiceChat.Source.PLUGIN) == (VoiceChat.mic_plugin() != null)
	print("T --test-mikrofon: gewählte Quelle: %s %d Hz — %s" % [
			v.source_name(), int(v.source_rate()),
			"passt zur Verfügbarkeit (OK)" if quelle_ok else "FEHLER"])
	print("T --test-mikrofon: %s" % v.plugin_report())
	print("T --test-mikrofon: Aufnahme läuft: %s, Bus '%s' (stumm: %s)" % [
			v.recording(), VoiceChat.BUS_REC,
			AudioServer.is_bus_mute(AudioServer.get_bus_index(VoiceChat.BUS_REC))
					if AudioServer.get_bus_index(VoiceChat.BUS_REC) >= 0 else "—"])
	var ende := Time.get_ticks_msec() / 1000.0 + _test_mic_secs
	var naechste := 0.0
	while Time.get_ticks_msec() / 1000.0 < ende:
		await get_tree().process_frame
		var jetzt := Time.get_ticks_msec() / 1000.0
		if jetzt < naechste:
			continue
		naechste = jetzt + 1.0
		print("T --test-mikrofon: t=%.0fs Frames %d (%d Abholungen, davon ≠0: %d) · roh %.5f (Spitze %.5f) · Block %.5f (Spitze %.5f) · Rauschen %.5f · Schwelle %.5f · Schleuse %s · Blöcke %d · Pakete %d · gesendet %d" % [
				_test_mic_secs - (ende - jetzt), v.stat_frames, v.stat_pulls, v.stat_nonzero,
				v.raw_rms(), v.stat_raw_peak, v.rms(), v.stat_block_peak,
				v.noise_floor(), v.open_threshold(), "offen" if v.gate_open() else "zu",
				v.stat_blocks, v.stat_packets, v.stat_sent])
	var fehler := 0
	var frames: int = v.stat_frames
	var nonzero: int = v.stat_nonzero
	var pakete: int = v.stat_packets
	var befund := ""
	if frames == 0:
		befund = "kein Frame aus dem Aufnahmebus — die Aufnahme läuft nicht (enable_input? Bus? Gerät?)"
	elif nonzero == 0:
		befund = "durchgehend EXAKT 0 über %d Frames — kein Mikrofonsignal. Ein echtes Mikrofon rauscht immer; das ist digitale Stille. Auf macOS fehlt dann die Freigabe (Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon), auf Android RECORD_AUDIO" % frames
	elif pakete == 0:
		befund = "Signal kommt an (Spitze %.5f), aber die Schleuse hat nie geöffnet (Schwelle %.5f)" % [v.stat_block_peak, v.open_threshold()]
	else:
		befund = "Kette vollständig: %d Frames → %d Blöcke → %d Pakete (Spitze %.5f über Schwelle %.5f)" % [
				frames, v.stat_blocks, pakete, v.stat_block_peak, v.open_threshold()]
	print("T --test-mikrofon: BEFUND — %s" % befund)
	print("T --test-mikrofon: Notbremse meldete: %s" % ["(nichts)" if gemeldet.v == "" else gemeldet.v])


	var cap: AudioEffectCapture = v.capture_effect()
	if cap == null:
		print("T --test-mikrofon: kein Aufnahmepuffer — Gegenprobe übersprungen")
	else:
		v.reset_stats()
		v.reset_gate()
		var mix := AudioServer.get_mix_rate()


		var ton := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = mix
		gen.buffer_length = 0.2
		ton.stream = gen
		ton.bus = VoiceChat.BUS_REC
		add_child(ton)
		ton.play()
		var pb = ton.get_stream_playback()
		var phase := 0.0
		var geschoben := 0
		var soll := int(mix)
		while geschoben < soll:

			var platz: int = mini(pb.get_frames_available(), soll - geschoben)
			if platz > 0:
				var buf := PackedVector2Array()
				buf.resize(platz)
				for i in platz:
					phase += TAU * 300.0 / mix
					var wert := sin(phase) * 0.25
					buf[i] = Vector2(wert, wert)
				pb.push_buffer(buf)
				geschoben += platz
			await get_tree().process_frame
		for _i in 8:
			await get_tree().process_frame
		ton.stop()
		ton.queue_free()
		var kette_ok: bool = v.stat_packets > 0
		print("T --test-mikrofon: Gegenprobe — %d Frames Sinus (Effektivwert 0,177) in den Aufnahmepuffer geschoben" % geschoben)
		print("T --test-mikrofon: Kette: %d Frames gelesen (≠0: %d) → roher Effektivwert %.4f → Block %.4f (Spitze %.4f) → Schwelle %.4f → Schleuse %s → %d Blöcke, %d Pakete — %s" % [
				v.stat_frames, v.stat_nonzero, v.stat_raw_peak, v.rms(), v.stat_block_peak,
				v.open_threshold(), "offen" if v.gate_open() else "zu",
				v.stat_blocks, v.stat_packets,
				"ganze Aufnahmekette belegt (OK)" if kette_ok else "FEHLER"])
		if not kette_ok:
			fehler += 1


	v.set_mode(VoiceChat.Mode.OFF)
	v.probe = true
	v.reset_stats()
	v.reset_gate()
	var fremd_rate := 48000.0
	var fremd_phase := 0.0
	var fremd_bloecke := 0
	for _b in 20:
		var chunk := PackedFloat32Array()
		chunk.resize(int(fremd_rate / 20.0))
		for i in chunk.size():
			fremd_phase += TAU * 300.0 / fremd_rate
			chunk[i] = sin(fremd_phase) * 0.25
		v.call("_feed_mono", chunk, fremd_rate)
		fremd_bloecke += 1

	while int(v.get("_pcm").size()) >= VoiceChat.SAMPLES:
		var rest: PackedFloat32Array = v.get("_pcm")
		v.call("_send_block", rest.slice(0, VoiceChat.SAMPLES))
		v.set("_pcm", rest.slice(VoiceChat.SAMPLES))
	var fremd_ok: bool = v.stat_packets > 0 and v.stat_nonzero > 0
	print("T --test-mikrofon: Fremdquelle (%d Abholungen à 50 ms @ %d Hz) → %d Frames, Block %.4f, %d Pakete — %s" % [
			fremd_bloecke, int(fremd_rate), v.stat_frames, v.stat_block_peak, v.stat_packets,
			"Kette rechnet mit Fremdblöcken korrekt weiter (OK)" if fremd_ok else "FEHLER"])
	fehler += 0 if fremd_ok else 1

	var erwartet := VoiceChat.RATE
	var bekommen: int = v.stat_blocks * VoiceChat.SAMPLES
	var rate_ok: bool = absi(bekommen - erwartet) <= VoiceChat.SAMPLES
	print("T --test-mikrofon: eine Sekunde 48 kHz → %d Abtastwerte bei 8 kHz (erwartet %d ± %d) — %s" % [
			bekommen, erwartet, VoiceChat.SAMPLES, "OK" if rate_ok else "FEHLER"])
	fehler += 0 if rate_ok else 1
	v.probe = false

	v.set_mode(VoiceChat.Mode.OFF)
	v.probe = true
	print("T --test-mikrofon: Schleuse an eingespeisten Pegeln (20 Blöcke Grundrauschen, dann 10 Blöcke Pegel):")
	for fall in [[0.0, 0.0, false], [0.001, 0.0015, false], [0.001, 0.005, true],
			[0.001, 0.014, true], [0.001, 0.050, true], [0.005, 0.005, false],
			[0.005, 0.014, true], [0.005, 0.050, true]]:
		v.reset_gate()
		v.reset_stats()
		v.feed_level(float(fall[0]), 20)
		var vorher: int = v.stat_packets
		v.feed_level(float(fall[1]), 10)
		var raus: int = v.stat_packets - vorher
		var auf: bool = raus > 0
		var soll: bool = bool(fall[2])
		print("T --test-mikrofon:   Rauschen %.4f, Pegel %.4f → Schwelle %.5f, %d Pakete — %s" % [
				fall[0], fall[1], v.open_threshold(), raus,
				"OK" if auf == soll else ("FEHLER: sollte %s" % ["öffnen" if soll else "zubleiben"])])
		fehler += 0 if auf == soll else 1

	v.reset_gate()
	v.reset_stats()
	v.feed_level(0.001, 20)
	v.feed_level(0.05, 5)
	var nach: int = v.feed_level(0.0005, 30)
	var soll_nach := int(round(VoiceChat.GATE_HANG / (VoiceChat.PACKET_MS / 1000.0)))
	var nachlauf_ok: bool = nach >= soll_nach - 1 and nach <= soll_nach + 2
	print("T --test-mikrofon: Nachlauf nach dem letzten Laut — %d Pakete (erwartet %d±2) %s" % [
			nach, soll_nach, "OK" if nachlauf_ok else "FEHLER"])
	fehler += 0 if nachlauf_ok else 1
	v.probe = false


	for fall in [[0, 0, true, "no_input"], [48000, 0, false, "no_permission"],
			[48000, 0, true, "no_signal"], [48000, 40000, true, "too_quiet"]]:
		var grund: String = VoiceChat.trouble_reason(int(fall[0]), int(fall[1]), bool(fall[2]))
		var ok: bool = grund == str(fall[3])
		print("T --test-mikrofon: Notbremse bei Frames %d / ≠0 %d / Freigabe %s → %s (%s) — %s" % [
				fall[0], fall[1], fall[2], grund, tr("toast.mic_" + grund),
				"OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1


	for fall in [["iOS", "no_signal", "mp.mic_no_signal_ios"], ["iOS", "no_permission", "mp.mic_no_permission"],
			["iOS", "no_input", "mp.mic_no_input"], ["Android", "no_signal", "mp.mic_no_signal"],
			["macOS", "no_signal", "mp.mic_no_signal"]]:
		VoiceChat.AndroidPlugin.set_test_platform(str(fall[0]))
		var schluessel := VoiceChat.trouble_text_key(str(fall[1]))
		var ok: bool = schluessel == str(fall[2])
		var txt := str(TranslationServer.translate(schluessel))
		print("T --test-mikrofon: Meldung auf %-8s bei %-13s → %-22s (%s…) — %s" % [
				fall[0], fall[1], schluessel, txt.substr(0, 44),
				"OK" if ok else "FEHLER, erwartet " + str(fall[2])])
		fehler += 0 if ok else 1


		if txt == schluessel:
			print("T --test-mikrofon:   FEHLER — kein Text in strings.csv für %s" % schluessel)
			fehler += 1
		print("T --test-mikrofon:   Freigabezustand dort: '%s'" % VoiceChat.permission_state())
	VoiceChat.AndroidPlugin.set_test_platform("")
	print("T --test-mikrofon: Diagnosezeile hier: %s" % v.diagnose().replace("\n", " | "))


	v.set_mode(VoiceChat.Mode.TEAM)
	await get_tree().process_frame
	var reopen_vorher: int = v.stat_reopens
	var reopen_ok: bool = v.reopen_input() and v.stat_reopens == reopen_vorher + 1 and v.recording()
	print("T --test-mikrofon: Eingang neu geöffnet (%d → %d), Aufnahme läuft danach: %s — %s" % [
			reopen_vorher, v.stat_reopens, v.recording(), "OK" if reopen_ok else "FEHLER"])
	fehler += 0 if reopen_ok else 1


	v.stat_reopens = 0
	var versuche := 0
	for _i in 8:
		v.stat_frames = 48000
		v.stat_nonzero = 0
		v.set("_last_nonzero", Time.get_ticks_msec() / 1000.0 - VoiceChat.REOPEN_AFTER - 1.0)
		v.set("_last_reopen", Time.get_ticks_msec() / 1000.0 - VoiceChat.REOPEN_AFTER - 1.0)
		v.call("_watch_input")
		versuche = v.stat_reopens
	var waechter_ok: bool = versuche == VoiceChat.REOPEN_MAX
	print("T --test-mikrofon: Wächter bei durchgehend Null — %d Wiederöffnungen (Sollwert %d) — %s" % [
			versuche, VoiceChat.REOPEN_MAX, "OK" if waechter_ok else "FEHLER"])
	fehler += 0 if waechter_ok else 1
	print("T --test-mikrofon: Diagnosezeile der Mikrofonprobe: %s" % v.diagnose())
	v.set_mode(VoiceChat.Mode.OFF)


	print("T --test-mikrofon: Neustart möglich: %s (Plugin-Weg: %s, %s)" % [
			UpdateConfig.restart_supported(), UpdateConfig.android_restart_plugin() != null,
			OS.get_name()])
	print("T --test-mikrofon: %d Befund(e) in der Schleusenprüfung (Sollwert 0)" % fehler)
	get_tree().quit()


func _rolle_ans_ende(node: Node) -> void:
	if node is ScrollContainer:
		(node as ScrollContainer).scroll_vertical = 1 << 20
	for k in node.get_children():
		_rolle_ans_ende(k)


func _findet_beschriftung(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	if node is Button and (node as Button).text == text:
		return true
	for k in node.get_children():
		if _findet_beschriftung(k, text):
			return true
	return false


func _findet_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for k in node.get_children():
		if _findet_text(k, text):
			return true
	return false


func _shot_voice(tag: String) -> void:
	_update_mic_button()
	await get_tree().process_frame
	await get_tree().process_frame
	if _screenshot_path == "":
		return
	var path := "%s_%s.png" % [_screenshot_path.get_basename(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot: ", path)


func _run_test_spielerliste() -> void:
	while world.sim == null or world.sim.tick() < 60:
		await get_tree().process_frame
	var fehler := 0
	var locale_vorher := TranslationServer.get_locale()

	print("T --test-spielerliste: Gefecht — %d Plätze in der Liste" % world.player_roster.size())
	for e in world.player_roster:
		var pid := int(e.get("sim", 0))
		var soll: Color = world.player_colors[pid]
		var ok: bool = (e.get("color", Color.BLACK) as Color).is_equal_approx(soll)
		print("T --test-spielerliste: Gefecht Sim %d — %s, Farbe %s (Feld %s) — %s" % [
				pid, _roster_name(e), (e.get("color", Color.BLACK) as Color).to_html(false),
				soll.to_html(false), "OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1
	if world.player_roster.is_empty():
		print("T --test-spielerliste: FEHLER — im Gefecht steht kein Platz in der Liste")
		fehler += 1
	fehler += await _shot_players("gefecht", ["de", "en"])


	NetHub.hub().ensure_voice()
	_open_player_list()
	for _i in 3:
		await get_tree().process_frame
	var funk_panel := $UI.get_node_or_null("PlayerList")
	var funk: bool = funk_panel != null and _findet_beschriftung(funk_panel, tr("mp.voice_intro_again"))
	var stumm := 0
	for row in _player_list_rows():
		for kind in (row as Control).get_children():
			if kind is Button:
				stumm += 1
	print("T --test-spielerliste: Gefecht ohne Sprechfunk — Erstinfo %s, Stummschalter %d (Sollwert false/0) — %s" % [
			funk, stumm, "OK" if not funk and stumm == 0 else "FEHLER"])
	fehler += 0 if not funk and stumm == 0 else 1
	_close_modals()

	var hub := NetHub.hub()
	hub.ensure_voice()
	var slug := str(ProtoWorld.next_map)


	var clients: Array = [
		{"client_id": "c1", "seat": 0, "kind": "human", "name": "Tom", "faction": "soviet",
			"team": 1, "color": 0, "spawn": -1},
		{"client_id": "c2", "seat": 1, "kind": "human", "name": "Jan", "faction": "allies",
			"team": 1, "color": 1, "spawn": -1},
		{"client_id": "c3", "seat": 2, "kind": "human", "name": "Ole", "faction": "allies",
			"team": 2, "color": 2, "spawn": -1},
		{"client_id": "", "seat": 3, "kind": "bot", "name": "", "level": "hard",
			"faction": "soviet", "team": 2, "color": 3, "spawn": -1},
	]
	var setup: Dictionary = hub.build_setup(slug, clients, {"credits": 5000, "starting_units": "light"})
	hub.code = "TEST42"
	hub.my_seat = 0
	hub.host = true
	hub.host_seat = 0
	hub.setup = setup
	hub.in_game = true
	hub.session = NetHub.NetSession.new()

	hub.session.setup_from(setup, 0)
	hub.chat = [{"seat": 1, "name": "Jan", "color": 1, "scope": "all", "text": "#gg", "t_server": 0}]
	world._apply_setup(setup)
	_setup_multiplayer_hud()
	await get_tree().process_frame
	var seats: Array = setup.get("seats", [])
	var roster: Array = world.player_roster
	var vollzaehlig: bool = roster.size() == seats.size()
	print("T --test-spielerliste: Mehrspieler — %d von %d Plätzen in der Liste — %s" % [
			roster.size(), seats.size(), "OK" if vollzaehlig else "FEHLER"])
	fehler += 0 if vollzaehlig else 1
	for i in mini(roster.size(), seats.size()):
		var e: Dictionary = roster[i]
		var s: Dictionary = seats[i]


		var lobby_col: Color = ChatPanel.player_color(int(e.get("color_index", 0)))
		var col_ok: bool = (e.get("color", Color.BLACK) as Color).is_equal_approx(lobby_col) \
				and int(e.get("color_index", -1)) == int(s.get("color", 0))
		var team_ok: bool = int(e.get("team", -1)) == int(s.get("team", 0))
		var name_ok: bool = str(e.get("name", "")) == str(s.get("name", ""))
		var seat_ok: bool = int(e.get("seat", -1)) == int(s.get("seat", -1))

		var pid := int(e.get("sim", 0))
		var rel := str(world.roster_status(pid).get("relation", "?"))
		var soll_rel := "self"
		if pid != world.local_player:
			soll_rel = "enemy" if world.sim.hostile(world.local_player, pid) else "allied"
		var rel_ok: bool = rel == soll_rel
		var alles: bool = col_ok and team_ok and name_ok and seat_ok and rel_ok
		print("T --test-spielerliste: Platz %d (Sim %d) %s — Team %d, Farbe %s, %s — %s" % [
				int(s.get("seat", -1)), pid, _roster_name(e), int(e.get("team", 0)),
				(e.get("color", Color.BLACK) as Color).to_html(false), tr("pause.rel_" + rel),
				"OK" if alles else "FEHLER"])
		if not alles:
			print("T --test-spielerliste:   Farbe %s Team %s Name %s Sitz %s Verhältnis %s (Soll %s)" % [
					col_ok, team_ok, name_ok, seat_ok, rel_ok, soll_rel])
		fehler += 0 if alles else 1

	var erwartet := {0: "self", 1: "allied", 2: "enemy", 3: "enemy"}
	for e in roster:
		var want: String = str(erwartet.get(int(e.get("seat", -1)), "?"))
		var got := str(world.roster_status(int(e.get("sim", 0))).get("relation", "?"))
		if want != got:
			print("T --test-spielerliste: FEHLER Platz %d — Verhältnis %s statt %s" % [
					int(e.get("seat", -1)), got, want])
			fehler += 1

	var bot_sim := -1
	for e in roster:
		if int(e.get("seat", -1)) == 3:
			bot_sim = int(e.get("sim", -1))


	for runde in 6:
		for u in world.units:
			if u.alive and u.player == bot_sim:
				world.sim.destroy(u.id)
		await get_tree().process_frame
		await get_tree().process_frame
		if int(world.sim.alive_count(bot_sim)) == 0:
			break

	hub.session.on_peer_left(2)
	await get_tree().process_frame
	var st_bot: Dictionary = world.roster_status(bot_sim)
	var bot_ok: bool = int(st_bot.get("alive", 1)) == 0
	print("T --test-spielerliste: KI-Platz (Sim %d) ohne Actors — alive_count %d — %s" % [
			bot_sim, int(st_bot.get("alive", -1)), "OK" if bot_ok else "FEHLER"])
	fehler += 0 if bot_ok else 1


	world.sim.set_win_state(bot_sim, 2)
	var weg_ok: bool = not hub.session.alive_seats.has(2)
	print("T --test-spielerliste: Platz 2 abgemeldet — alive_seats %s — %s" % [
			hub.session.alive_seats, "OK" if weg_ok else "FEHLER"])
	fehler += 0 if weg_ok else 1
	fehler += await _shot_players("mehrspieler", ["de", "en"])

	TranslationServer.set_locale("de")
	_open_player_list()
	await get_tree().process_frame
	for row in _player_list_rows():
		var seat := int(row.get_meta("seat", -1))
		var texte: Array = []
		for c in row.get_children():
			if c is Label:
				texte.append((c as Label).text)
			elif c is Button:
				texte.append((c as Button).text)
		var zeile := " | ".join(PackedStringArray(texte))
		var soll := ""
		match seat:
			0: soll = tr("pause.rel_self")
			1: soll = tr("pause.rel_allied")
			2: soll = tr("pause.state_gone")
			3: soll = tr("pause.state_defeated")
		var ok: bool = soll != "" and zeile.contains(soll)
		print("T --test-spielerliste: Zeile Platz %d [%s] — erwartet %s — %s" % [
				seat, zeile, soll, "OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1

		var klecks: ColorRect = null
		for c in row.get_children():
			if c is CenterContainer and c.get_child_count() > 0 and c.get_child(0) is ColorRect:
				klecks = c.get_child(0)
		var klecks_ok: bool = klecks != null and klecks.color.is_equal_approx(row.get_meta("color", Color.BLACK))
		fehler += 0 if klecks_ok else 1
		if not klecks_ok:
			print("T --test-spielerliste: FEHLER Platz %d — Farbklecks fehlt oder falsch" % seat)

	var stumm_zeilen := 0
	for row in _player_list_rows():
		for c in row.get_children():
			if c is Button:
				stumm_zeilen += 1
				if int(row.get_meta("seat", -1)) == 1:
					(c as Button).pressed.emit()
	var vc := _mp_voice()
	var stumm_ok: bool = stumm_zeilen == 2 and vc != null and vc.is_muted(1)
	print("T --test-spielerliste: Stummschalter — %d Zeilen (Soll 2), Platz 1 stumm %s — %s" % [
			stumm_zeilen, vc != null and vc.is_muted(1), "OK" if stumm_ok else "FEHLER"])
	fehler += 0 if stumm_ok else 1
	if vc != null:
		vc.set_muted(1, false)
	_close_modals()

	if _resizer != null:
		_resizer.paused = true
	var verstoesse := 0
	for sprache in ["de", "en"]:
		TranslationServer.set_locale(sprache)
		for e in LAYOUT_MATRIX:
			DisplayServer.window_set_size(Vector2i(e[0], e[1]))
			Dp.set_forced_dpi(float(e[2]))
			Dp.set_ui_scale(1.0)
			await get_tree().process_frame
			_layout_ui()
			for _i in 3:
				await get_tree().process_frame
			var real := DisplayServer.window_get_size()
			_open_player_list()
			for _i in 3:
				await get_tree().process_frame
			var tag := "spieler %s %dx%d@%d" % [sprache, real.x, real.y, e[2]]
			for line in LayoutCheck.violations($UI, Dp.safe_rect(), tag):
				print(line)
				verstoesse += 1
			for line in LayoutCheck.overlap_violations($UI, tag):
				print(line)
				verstoesse += 1
			_close_modals()
			await get_tree().process_frame
	print("T --test-spielerliste: Layout der Spielerliste — %d Verstöße (Sollwert 0)" % verstoesse)
	fehler += verstoesse
	TranslationServer.set_locale(locale_vorher)
	print("T --test-spielerliste: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()


func _open_player_list() -> void:
	_close_modals()
	if not _menu_panel.visible:
		_toggle_menu(true)
	_show_player_list()


func _close_modals() -> void:


	for n in get_tree().get_nodes_in_group("modal"):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	for n in get_tree().get_nodes_in_group(HudTheme.DIM_GROUP):
		if n == _menu_backdrop:
			continue
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	if _menu_panel != null and _menu_panel.visible:
		_toggle_menu(false)


func _player_list_rows() -> Array:
	var panel := $UI.get_node_or_null("PlayerList")
	if panel == null:
		return []
	var rows := panel.find_child("PlayerRows", true, false)
	return rows.get_children() if rows != null else []


func _shot_players(tag: String, sprachen: Array) -> int:
	var fehler := 0
	for sprache in sprachen:
		TranslationServer.set_locale(str(sprache))
		_open_player_list()
		for _i in 3:
			await get_tree().process_frame
		var zeilen := _player_list_rows().size()
		var ok: bool = zeilen == world.player_roster.size() and zeilen > 0
		print("T --test-spielerliste: %s %s — %d Zeilen (Soll %d) — %s" % [
				tag, sprache, zeilen, world.player_roster.size(), "OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1
		if _screenshot_path != "":
			var path := "%s_%s_%s.png" % [_screenshot_path.get_basename(), tag, sprache]
			get_viewport().get_texture().get_image().save_png(path)
			print("Screenshot: ", path)
		_close_modals()
		await get_tree().process_frame
	return fehler


func _mp_shot(tag: String, who: String) -> void:
	if _mp_shot_done.has(tag):
		return


	if not _mp_shot_armed.has(tag):
		_mp_shot_armed[tag] = true
		return
	_mp_shot_done[tag] = true
	var path := "%s/%s-%s.png" % [_mp_shot_dir, tag, who]
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot: ", path)
