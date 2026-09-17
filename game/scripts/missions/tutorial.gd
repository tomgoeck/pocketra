

extends MissionScript


const ProtoMainScript := preload("res://scripts/proto/proto_main.gd")

var player := 0
var enemy := 1

var _steps: Array = []
var _step_i := -1
var _current_obj_id := -1
var _final_objective_id := -1
var _wave: Array = []
var _last_hint_key := ""
var _hide_scheduled := {}


var _group_target: Array = []


var _cmd_zoom_start := 0.0
var _cmd_sel_unit = null
var _all_target: Array = []


var _side_objectives_added := false
var _repair_obj := -1
var _sell_obj := -1
var _repair_done := false
var _sell_done := false


var _auto_walk := false
var _auto_walk_seen := {}


func world_loaded() -> void:
	player = api.player("Player")
	enemy = api.player("Enemy")
	init_objectives(player)
	var mcv := api.actor("PlayerMCV")
	if mcv != null:
		api.camera_target = mcv.pos
	_auto_walk = OS.get_cmdline_user_args().has("--test-tutorial-walk")
	_build_steps()
	_begin_step(0)


func tick() -> void:
	_tick_step()
	_tick_side_objectives()
	if _auto_walk:
		_tick_auto_walk()


func _build_steps() -> void:
	_steps = [

		{"text": "tutorial-ui-camera", "ack": true},
		{"text": "tutorial-ui-statusbar", "highlight": "status_bar", "ack": true},
		{"text": "tutorial-ui-menu", "highlight": "menu_button", "ack": true},
		{"text": "tutorial-ui-music", "highlight": "music_toggle", "ack": true},

		{"text": "tutorial-obj-deploy", "highlight": "deploy_mcv", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "fact").is_empty()},

		{"text": "tutorial-obj-power", "build": "powr", "objective": true, "voice": "NewOptions",
			"cond": func(): return not api.get_actors_by_type(player, "powr").is_empty()},

		{"text": "tutorial-obj-refinery", "build": "proc", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "proc").is_empty()},
		{"text": "tutorial-ui-economy", "ack": true},

		{"text": "tutorial-obj-barracks", "build": "tent", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "tent").is_empty()},
		{"text": "tutorial-obj-infantry", "highlight": "tab_infantry", "objective": true, "voice": "UnitReady",
			"cond": func(): return api.get_actors_by_type(player, "e1").size() >= 3},


		{"text": "tutorial-obj-group-assign", "highlight": "groups", "objective": true, "ack": true,
			"on_begin": func(): _group_target = api.get_actors_by_type(player, "e1"),
			"cond": func(): return _group1_has_target()},
		{"text": "tutorial-obj-group-select", "highlight": "groups", "objective": true, "ack": true,
			"cond": func(): return _selection_is_group_target()},

		{"text": "tutorial-obj-turret", "build": "pbox", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "pbox").is_empty()},


		{"text": "tutorial-ui-cmdbar-intro", "ack": true},


		{"text": "tutorial-ui-cmd-repair", "highlight": "cmd_repair", "objective": true, "ack": true,
			"on_begin": func(): _damage_bunker(),
			"cond": func(): return _bunker_repairing()},
		{"text": "tutorial-ui-cmd-sell", "highlight": "cmd_sell", "objective": true, "ack": true,
			"cond": func(): return api.get_actors_by_type(player, "pbox").is_empty()},


		{"text": "tutorial-ui-cmd-clear", "highlight": "cmd_clear", "objective": true, "ack": true,
			"on_begin": func(): api.world.select_units(api.get_actors_by_type(player, "e1")),
			"cond": func(): return api.world.selection.is_empty()},

		{"text": "tutorial-ui-cmd-add", "highlight": "cmd_add", "objective": true, "ack": true,
			"cond": func(): return api.world.selection.size() > 1},

		{"text": "tutorial-ui-cmd-clear2", "highlight": "cmd_clear", "objective": true, "ack": true,
			"cond": func(): return api.world.selection.is_empty()},


		{"text": "tutorial-ui-cmd-all", "highlight": "btn_all", "objective": true, "ack": true,
			"on_begin": func(): _capture_all_target(),
			"cond": func(): return not _all_target.is_empty() and _selections_equal(api.world.selection, _all_target)},
		{"text": "tutorial-ui-cmd-base", "highlight": "cmd_base", "objective": true, "ack": true,
			"on_begin": func(): _begin_camera_step(_base_pos()),
			"cond": func(): return _camera_near(_base_pos())},


		{"text": "tutorial-ui-cmd-event", "highlight": "cmd_event", "ack": true},
		{"text": "tutorial-ui-cmd-sel", "highlight": "cmd_sel", "objective": true, "ack": true,
			"on_begin": func(): _begin_sel_step(),
			"cond": func(): return _cmd_sel_unit != null and api.world.selection.has(_cmd_sel_unit) and _camera_near(_cmd_sel_unit.pos)},


		{"text": "tutorial-ui-cmd-zoom", "highlight": "cmd_zoom_in", "keep_without_highlight": true,
			"objective": true, "ack": true,
			"on_begin": func(): _cmd_zoom_start = api.world.zoom,
			"cond": func(): return not is_equal_approx(api.world.zoom, _cmd_zoom_start)},


		{"text": "tutorial-obj-warfactory", "build": "weap", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "weap").is_empty()},
		{"text": "tutorial-obj-tanks", "highlight": "tab_vehicle", "objective": true, "voice": "UnitReady",
			"cond": func(): return api.get_actors_by_type(player, "1tnk").size() >= 2},
		{"text": "tutorial-ui-superweapons", "ack": true},

		{"text": "tutorial-obj-dome", "build": "dome", "objective": true, "voice": "ConstructionComplete",
			"cond": func(): return not api.get_actors_by_type(player, "dome").is_empty()},


		{"text": "tutorial-ui-lowpower", "highlight": "status_bar", "ack": true},
		{"text": "tutorial-obj-apwr", "build": "apwr", "objective": true, "voice": "LowPower",
			"cond": func(): return api.world.sim.power_provided(player) - api.world.sim.power_drained(player) >= 0},
		{"text": "tutorial-ui-minimap", "highlight": "minimap", "ack": true},

		{"text": "tutorial-ui-radial-unit", "ack": true, "on_begin": func(): _highlight_first(player, "e1")},
		{"text": "tutorial-ui-radial-building", "ack": true, "on_begin": func(): _highlight_first(player, "tent")},
		{"text": "tutorial-ui-infocard", "ack": true},
		{"text": "tutorial-ui-selection-gestures", "ack": true},
		{"text": "tutorial-ui-attackmove", "ack": true},

		{"text": "tutorial-obj-defend", "objective": true, "voice": "ObjectiveMet",
			"on_begin": func(): _start_enemy_attack(),
			"cond": func(): return not _wave.is_empty() and _wave_defeated()},

		{"text": "tutorial-obj-attack", "highlight": "radial_attack", "primary": true,
			"cond": func(): return api.has_no_required_units(enemy)},
	]
	_drop_steps_for_hidden_buttons()


const _HIGHLIGHT_FOR_CMD := {
	"clear": "cmd_clear", "base": "cmd_base", "event": "cmd_event", "sel": "cmd_sel",
	"zoom_in": "cmd_zoom_in", "zoom_out": "cmd_zoom_out",
}


func _drop_steps_for_hidden_buttons() -> void:
	var gone: Array = []
	for id in ProtoMainScript.CMD_HIDDEN:
		gone.append(_HIGHLIGHT_FOR_CMD.get(id, id))
	if not ProtoMainScript.BOTTOM_ROW_VISIBLE:
		for id in ProtoMainScript.CMD_BOTTOM_ROW:
			gone.append(_HIGHLIGHT_FOR_CMD.get(id, id))
	if gone.is_empty():
		return
	var kept: Array = []
	for s in _steps:
		if s.has("highlight") and s["highlight"] in gone:


			if s.get("keep_without_highlight", false):
				s.erase("highlight")
				kept.append(s)
			continue
		kept.append(s)
	if kept.size() != _steps.size():
		print("Tutorial: %d Schritt(e) zu ausgeblendeten Knöpfen übersprungen (%s)" % [
				_steps.size() - kept.size(), ", ".join(PackedStringArray(gone))])
	_steps = kept


func _begin_step(i: int) -> void:
	_step_i = i
	_current_obj_id = -1
	_last_hint_key = ""
	if i >= _steps.size():
		api.clear_highlight()
		return
	var s: Dictionary = _steps[i]
	if s.has("on_begin"):
		s["on_begin"].call()
	if s.has("build"):
		_update_build_step(s)
	else:


		_show_hint(s["text"], s.get("objective", false) or s.get("primary", false))
		if s.has("highlight"):
			api.highlight_hud(s["highlight"])
		elif not s.has("on_begin"):
			api.clear_highlight()
	if s.get("ack", false):
		api.wait_for_tap()


	if s.get("primary", false):
		_current_obj_id = api.add_primary_objective(player, s["text"], false)
		_final_objective_id = _current_obj_id
	elif s.get("objective", false):
		_current_obj_id = api.add_secondary_objective(player, s["text"], false)


func _tick_step() -> void:
	if _step_i < 0 or _step_i >= _steps.size():
		return
	var s: Dictionary = _steps[_step_i]
	if s.has("build"):
		_update_build_step(s)
	var natural: bool = s["cond"].call() if s.has("cond") else false
	var acked: bool = s.get("ack", false) and not api.awaiting_ack
	if not (natural or acked):
		return
	if _current_obj_id >= 0:
		api.mark_completed_objective(player, _current_obj_id)
		_hide_objective_soon(_current_obj_id)


	_begin_step(_step_i + 1)


func _show_hint(key: String, dedupe: bool = false) -> void:
	api.set_mission_text("" if dedupe else api.get_message(key))
	if key != _last_hint_key:
		_last_hint_key = key
		_play_tutorial_voice(key)


const _TAB_HIGHLIGHT_FOR_KIND := {0: "tab_building", 1: "tab_infantry", 2: "tab_vehicle", 3: "tab_defense"}


func _update_build_step(s: Dictionary) -> void:
	var type_name: String = s["build"]
	var tid: int = api.world.type_ids.get(type_name, -1)
	if tid >= 0 and api.world.placing_type == tid:
		_show_hint("tutorial-hint-place")
		api.clear_highlight()
		return
	if not api.build_bar_open:
		_show_hint("tutorial-hint-openbar")
		api.highlight_hud("build_toggle")
		return
	var want_kind := int(api.world.types.get(type_name, {}).get("queue", 0))
	if api.build_bar_kind != want_kind:
		_show_hint("tutorial-hint-switchtab")
		api.highlight_hud(_TAB_HIGHLIGHT_FOR_KIND.get(want_kind, "tab_building"))
		return
	_show_hint(s["text"], s.get("objective", false) or s.get("primary", false))
	api.highlight_cameo(type_name)


func _highlight_first(owner: int, type: String) -> void:
	var list := api.get_actors_by_type(owner, type)
	if not list.is_empty():
		api.highlight_hud("unit", list[0])


func _group1_has_target() -> bool:
	if _group_target.is_empty():
		return false
	var g1: Array = api.control_groups[0] if api.control_groups.size() > 0 else []
	for u in _group_target:
		if not g1.has(u):
			return false
	return true


func _selection_is_group_target() -> bool:
	if _group_target.is_empty():
		return false
	var sel: Array = api.world.selection
	if sel.size() != _group_target.size():
		return false
	for u in _group_target:
		if not sel.has(u):
			return false
	return true


func _damage_bunker() -> void:
	var list := api.get_actors_by_type(player, "pbox")
	if not list.is_empty():
		api.set_health(list[0], maxi(1, api.max_health(list[0]) / 2))


func _bunker_repairing() -> bool:
	for u in api.get_actors_by_type(player, "pbox"):
		if u.repairing:
			return true
	return false


func _capture_all_target() -> void:
	var prev: Array = api.world.selection.duplicate()
	api.world.select_all_units()
	_all_target = api.world.selection.duplicate()
	api.world.select_units(prev)


func _selections_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for u in b:
		if not a.has(u):
			return false
	return true


func _base_pos() -> Vector2:
	var list := api.get_actors_by_type(player, "fact")
	return list[0].pos if not list.is_empty() else api.world.visible_world_rect().get_center()


func _camera_near(pos: Vector2, radius: float = 200.0) -> bool:
	return api.world.visible_world_rect().get_center().distance_to(pos) < radius


func _begin_camera_step(target: Vector2) -> void:
	api.set_camera(target + Vector2(4000, 4000))


func _begin_sel_step() -> void:
	var list := api.get_actors_by_type(player, "e1")
	_cmd_sel_unit = list[0] if not list.is_empty() else null
	if _cmd_sel_unit != null:
		api.world.select_units([_cmd_sel_unit])
		_begin_camera_step(_cmd_sel_unit.pos)


func _hide_objective_soon(id: int) -> void:
	if id < 0 or _hide_scheduled.has(id):
		return
	_hide_scheduled[id] = true
	api.after_delay(api.seconds(2.5), func(): _remove_objective(id))


func _remove_objective(id: int) -> void:
	var list: Array = api.objectives.get(player, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["id"] == id:
			list.remove_at(i)
			return


var _voice_player: AudioStreamPlayer


func _tutorial_voice_path(key: String) -> String:
	return "res://data/sfx/tutorial/%s/%s.ogg" % [Lang.code(), key]


const VOICE_DELAY_S := 1.5
var _voice_serial := 0


func _play_tutorial_voice(key: String) -> void:
	if _voice_player == null:
		if api.world == null:
			return
		_voice_player = AudioStreamPlayer.new()
		_voice_player.bus = Sfx.BUS_VOICE
		api.world.add_child(_voice_player)
	_voice_player.stop()
	var path := _tutorial_voice_path(key)
	if not ResourceLoader.exists(path):
		return


	_voice_serial += 1
	var serial := _voice_serial
	var tree := api.world.get_tree()
	if tree == null:
		return
	await tree.create_timer(VOICE_DELAY_S).timeout
	if serial != _voice_serial or _voice_player == null:
		return
	_voice_player.stream = load(path)
	_voice_player.play()
	print("Tutorial-Sprecher: %s" % key)


func _start_enemy_attack() -> void:
	var yard := api.actor("EnemyYard")
	var spawn := api.location(yard) if yard != null else Vector2i(81, 77)
	_wave = api.reinforce(enemy, ["e1", "e1", "e1", "jeep"], [spawn], 15, func(u): api.hunt(u))


func _wave_defeated() -> bool:
	for u in _wave:
		if u != null and u.alive:
			return false
	return true


func _tick_side_objectives() -> void:
	if not _side_objectives_added:
		if api.get_actors_by_type(player, "proc").is_empty():
			return
		_side_objectives_added = true
		_repair_obj = api.add_secondary_objective(player, "tutorial-side-repair", false)
		_sell_obj = api.add_secondary_objective(player, "tutorial-side-sell", false)
	if _repair_obj >= 0 and not _repair_done:
		for u in api.get_actors(player):
			if u.repairing:
				_repair_done = true
				api.mark_completed_objective(player, _repair_obj)
				_hide_objective_soon(_repair_obj)
				break
	if _sell_obj >= 0 and not _sell_done:
		for u in api.get_actors(player):
			if u.selling:
				_sell_done = true
				api.mark_completed_objective(player, _sell_obj)
				_hide_objective_soon(_sell_obj)
				break


func test_force() -> void:
	for u in api.get_actors(enemy):
		api.kill(u)
	if _final_objective_id < 0:
		_final_objective_id = api.add_primary_objective(player, "tutorial-obj-attack")
	api.mark_completed_objective(player, _final_objective_id)


func _tick_auto_walk() -> void:
	if _step_i < 0 or _step_i >= _steps.size():
		return
	if not _auto_walk_seen.has(_step_i):
		_auto_walk_seen[_step_i] = true
		print("WALK schritt=%d schluessel=%s text=\"%s\"" % [_step_i, _steps[_step_i].get("text", ""), api.mission_text])
	if api.awaiting_ack:
		api.confirm_ack()
		return
	var s: Dictionary = _steps[_step_i]
	if s.has("build"):
		var type_name: String = s["build"]
		if api.get_actors_by_type(player, type_name).is_empty():
			var fact := api.get_actors_by_type(player, "fact")
			if not fact.is_empty():
				api.create_actor(type_name, player, api.location(fact[0]) + Vector2i(3, 3))
		return
	match s.get("text", ""):
		"tutorial-obj-deploy":
			if api.get_actors_by_type(player, "fact").is_empty():
				var mcv := api.actor("PlayerMCV")
				if mcv != null:
					api.deploy(mcv)
		"tutorial-obj-infantry":
			var barr := api.get_actors_by_type(player, "tent")
			if not barr.is_empty():
				while api.get_actors_by_type(player, "e1").size() < 3:
					api.spawn_near("e1", player, api.location(barr[0]))
		"tutorial-obj-tanks":
			var weap := api.get_actors_by_type(player, "weap")
			if not weap.is_empty():
				while api.get_actors_by_type(player, "1tnk").size() < 2:
					api.spawn_near("1tnk", player, api.location(weap[0]))
		"tutorial-obj-defend":
			for u in _wave:
				if u != null and u.alive:
					api.kill(u)
		"tutorial-obj-attack":
			for u in api.get_actors(enemy):
				api.kill(u)
