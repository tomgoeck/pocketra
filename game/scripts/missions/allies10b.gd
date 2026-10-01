

extends MissionScript

var greece := 0
var ussr := 1
var badguy := 2
var engineers: Array = []
var top_left_console := [Vector2i(49, 38), Vector2i(50, 38)]
var bottom_left_console := [Vector2i(48, 93)]
var top_right_console := [Vector2i(75, 40), Vector2i(76, 40)]
var middle_right_console := [Vector2i(81, 72), Vector2i(82, 72)]
var tanya_footprint := [Vector2i(71, 98), Vector2i(72, 98), Vector2i(73, 98), Vector2i(74, 98), Vector2i(87, 101), Vector2i(88, 101)]
var gren_team_footprint := [Vector2i(53, 69), Vector2i(54, 69), Vector2i(55, 69)]
var flamer_team_footprint := [Vector2i(74, 61), Vector2i(75, 61), Vector2i(76, 61)]
var timer_ticks := 0
var ticked := 0
var scientists: Array = []
var starting_rifles: Array = []
var assault_a: Array = []
var assault_b: Array = []
var assault_c: Array = []
var patrol_support: Array = []
var barrel_squad: Array = []
var scientist_consoles: Array = []
var explosion_check_team: Array = []
var patrol_a: Array = []
var patrol_b: Array = []
var timer_color := Color(1, 1, 1)
var top_left_triggered := false
var bottom_left_triggered := false
var top_right_triggered := false
var middle_right_triggered := false
var tanya_arrived := false
var tanya_survive := -1
var stop_nukes := -1
var paperclip := -1
var kill_greece := -1


func _names(prefix: String, n: int) -> Array:
	var out := []
	for i in range(1, n + 1):
		out.append("%s%d" % [prefix, i])
	return out


func _locs(names: Array) -> Array:
	var out := []
	for n in names:
		var a := api.actor(n)
		if a != null:
			out.append(api.location(a))
	return out


func world_loaded() -> void:
	greece = api.player("Greece")
	ussr = api.player("USSR")
	badguy = api.player("BadGuy")
	timer_color = api.player_color(ussr)
	timer_ticks = api.minutes(26)
	ticked = timer_ticks
	engineers = api.actors(_names("Engi", 3))
	scientists = api.actors(_names("Scientist", 10))
	starting_rifles = api.actors(_names("StartRifle", 5))
	assault_a = api.actors(_names("AssaultTeamA", 3))
	assault_b = api.actors(_names("AssaultTeamB", 3))
	assault_c = api.actors(_names("AssaultTeamC", 3))
	patrol_support = api.actors(_names("PatrolSupport", 6))
	barrel_squad = api.actors(_names("BarrelSquad", 5))
	scientist_consoles = _locs(["NWSilo1", "NWSilo2", "NESilo1", "NESilo2", "SESilo1", "SESilo2", "SWSilo1", "SWSilo2"])
	explosion_check_team = api.actors(_names("CheckTeam", 5))
	patrol_a = api.actors(_names("PatrolA", 4))
	patrol_b = api.actors(_names("PatrolB", 4))
	init_objectives(greece)
	kill_greece = api.add_primary_objective(ussr, "")
	stop_nukes = api.add_primary_objective(greece, "get-engineers-to-consoles")
	paperclip = api.add_secondary_objective(greece, "spare-the-scientists")
	api.after_delay(api.minutes(6), func(): api.play_speech_notification(greece, "TwentyMinutesRemaining"))
	api.after_delay(api.minutes(16), func(): api.play_speech_notification(greece, "TenMinutesRemaining"))
	api.after_delay(api.minutes(21), func(): api.play_speech_notification(greece, "WarningFiveMinutesRemaining"))
	api.after_delay(api.minutes(23), func(): api.play_speech_notification(greece, "WarningThreeMinutesRemaining"))
	api.after_delay(api.minutes(25), func(): api.play_speech_notification(greece, "WarningOneMinuteRemaining"))
	var cam := api.actor("DefaultCameraPosition")
	if cam != null:
		api.camera_target = cam.pos

	api.disguise_as_type(api.actor("Spy1"), "e1", ussr)
	api.disguise_as_type(api.actor("Spy2"), "e1", ussr)
	deactivate_missiles()
	tanya_sequence()
	opening_moves()
	misc_triggers()


func opening_moves() -> void:
	var cam := api.actor("DefaultCameraPosition")
	for a in starting_rifles:
		if cam != null:
			api.attack_move(a, api.location(cam))
	for s in scientists:
		scientist_patrol(s)
	group_patrol(patrol_a, _locs(_names("PatrolARally", 4)), api.seconds(5))
	group_patrol(patrol_b, _locs(_names("PatrolBRally", 4)), api.seconds(5))
	api.on_killed(api.actor("StartRifle1"), func(_u):
		for a in assault_a:
			api.hunt(a))
	api.on_killed(api.actor("StartRifle2"), func(_u):
		for b in assault_b:
			api.hunt(b))
	api.on_killed(api.actor("StartRifle3"), func(_u):
		for c in assault_c:
			api.hunt(c))


func scientist_patrol(scientist) -> void:
	api.on_idle(scientist, func(sci):
		if not scientist_consoles.is_empty():
			api.move(sci, random(scientist_consoles)))


func group_patrol(units: Array, waypoints: Array, delay: int) -> void:
	if waypoints.is_empty():
		return
	var state := {"i": 0, "stop": false}
	for unit in units:
		api.on_idle(unit, func(u):
			if state["stop"]:
				return
			if api.location(u) == waypoints[state["i"]]:
				if api.all_idle(units):
					state["stop"] = true
					state["i"] = (state["i"] + 1) % waypoints.size()
					api.after_delay(delay, func(): state["stop"] = false)
			else:
				api.attack_move(u, waypoints[state["i"]]))


func misc_triggers() -> void:
	api.on_any_killed(scientists, func(_u): api.mark_failed_objective(greece, paperclip))
	var console := api.actor("FlameTowerConsole")
	if console != null:
		api.on_entered_proximity(console.pos, 1.0, func(actor, id):
			if actor.player == greece:
				api.remove_proximity_trigger(id)
				var tower := api.actor("FlameTower")
				if not api.is_dead(tower):
					api.play_sound_notification(greece, "AlertBleep")
					api.display_message(api.get_message("flame-turret-deactivated"), api.get_message("console"))
					api.kill(tower))
	api.on_killed(api.actor("TankBarrel"), func(_u):
		if not api.is_dead(api.actor("BarrelTank")):
			api.kill(api.actor("BarrelTank")))
	api.on_killed(api.actor("CheckBarrel"), func(_u):
		for a in explosion_check_team:
			if not api.is_dead(a):
				api.hunt(a))
	api.on_killed(api.actor("SquadBarrel"), func(_u):
		for b in barrel_squad:
			if not api.is_dead(b):
				api.hunt(b))
	api.on_any_killed(patrol_a, func(_u):
		for sup in patrol_support:
			if not api.is_dead(sup):
				api.hunt(sup))
	var grens := [false]
	api.on_entered_footprint(gren_team_footprint, func(actor, id):
		if actor.player == greece and not grens[0]:
			api.remove_footprint_trigger(id)
			grens[0] = true
			api.after_delay(api.minutes(1), func():
				var west := api.actor("BunkerEntryWest")
				if west != null:
					api.reinforce(ussr, ["e2", "e2", "e2", "e2", "e2"], [api.location(west)], 0, func(u): api.hunt(u))))
	var flamers := [false]
	api.on_entered_footprint(flamer_team_footprint, func(actor, id):
		if actor.player == greece and not flamers[0]:
			api.remove_footprint_trigger(id)
			flamers[0] = true
			api.after_delay(api.minutes(1), func():
				var east := api.actor("BunkerEntryEast")
				if east != null:
					api.reinforce(ussr, ["e1", "e1", "e4", "e4", "e4"], [api.location(east)], 0, func(u): api.hunt(u))))
	var dogs := [false]
	api.on_entered_footprint(tanya_footprint, func(actor, id):
		if actor.type == "e7.noautotarget" and not dogs[0]:
			api.remove_footprint_trigger(id)
			dogs[0] = true
			var east := api.actor("BunkerEntryEast")
			if east != null:
				api.reinforce(ussr, ["dog", "dog", "dog", "dog", "dog"], [api.location(east)], 0, func(u): api.hunt(u)))


func tanya_sequence() -> void:
	var triggered := [false]
	api.on_entered_footprint(tanya_footprint, func(actor, id):
		if actor.player == greece and not triggered[0]:
			api.remove_footprint_trigger(id)
			triggered[0] = true
			api.hunt(api.actor("TankRoomDog"))
			var cam := api.actor("TankRoomCam")
			if cam != null:

				var handle = api.create_actor("camera", greece, api.location(cam))
				if handle != null:
					api.after_delay(api.minutes(1), func(): handle.destroy())
			api.play_sound_notification(greece, "laugh")
			var entry := api.actor("TanyaEntry")
			var gren_entry := api.actor("GrenEntry")
			api.after_delay(api.seconds(1), func():
				if entry == null:
					return
				api.reinforce(ussr, ["e2"], [api.location(entry), api.location(api.actor("DiePoint1"))], 25, func(one):
					api.play_sound("gun5")
					api.kill(one)))
			api.after_delay(api.seconds(3), func():
				if gren_entry == null:
					return
				api.reinforce(ussr, ["e2"], [api.location(gren_entry), api.location(api.actor("DiePoint2"))], 25, func(two):
					api.kill(two)
					api.play_sound("gun5")))
			api.after_delay(api.seconds(6), func():
				if entry == null or cam == null:
					return


				api.reinforce(greece, ["e7.noautotarget"], [api.location(entry), api.location(cam)], 25, func(tanya):
					tanya_arrived = true
					tanya_survive = api.add_primary_objective(greece, "tanya-survive")
					api.play_sound_notification(greece, "lefty")
					api.on_killed(tanya, func(_t): api.mark_failed_objective(greece, tanya_survive)))))


func tanya_objective_check() -> void:
	if tanya_arrived:
		api.mark_completed_objective(greece, tanya_survive)


func _console(cells: Array, flag_setter: Callable) -> void:
	api.on_entered_footprint(cells, func(actor, id):
		if actor.type == "e6":
			api.remove_footprint_trigger(id)
			flag_setter.call()
			api.play_speech_notification(greece, "ControlCenterDeactivated")
			api.display_message(api.get_message("nuclear-missile-deactivated"), api.get_message("console")))


func deactivate_missiles() -> void:
	api.on_all_killed(engineers, func(): api.mark_failed_objective(greece, stop_nukes))
	_console(top_left_console, func(): top_left_triggered = true)
	_console(bottom_left_console, func(): bottom_left_triggered = true)
	_console(top_right_console, func(): top_right_triggered = true)
	_console(middle_right_console, func(): middle_right_triggered = true)


func test_force() -> void:
	top_left_triggered = true
	bottom_left_triggered = true
	top_right_triggered = true
	middle_right_triggered = true


func tick() -> void:
	if api.has_no_required_units(greece):
		api.mark_failed_objective(greece, stop_nukes)
	if top_left_triggered and bottom_left_triggered and top_right_triggered and middle_right_triggered:
		api.mark_completed_objective(greece, stop_nukes)
		api.mark_completed_objective(greece, paperclip)
		tanya_objective_check()
	if ticked > 0:
		if ticked % api.seconds(1) == 0:
			api.set_mission_text(api.fluent_message("reach-target-in", {"time": api.format_time(ticked)}), timer_color)
		ticked -= 1
	elif ticked == 0:


		api.set_mission_text(api.get_message("we-are-too-late"), timer_color)
		api.mark_failed_objective(greece, stop_nukes)
		ticked = -1
