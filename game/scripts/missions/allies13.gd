

extends MissionScript

var greece := 0
var ussr := 1
var turkey := 2
var england := 3
var engineers: Array = []
var heavy_tank_cam_footprint := [Vector2i(11, 46), Vector2i(12, 47), Vector2i(12, 48), Vector2i(12, 49)]
var tank_rifles: Array = []
var mrj_cam_footprint := [Vector2i(16, 53), Vector2i(16, 54), Vector2i(16, 55)]
var doom_room_footprint := [Vector2i(78, 70), Vector2i(79, 70), Vector2i(80, 70)]
var v2_room_footprint := [Vector2i(64, 71), Vector2i(65, 71), Vector2i(66, 71)]
var core_room_footprint := [Vector2i(55, 60), Vector2i(55, 61), Vector2i(55, 62), Vector2i(65, 52), Vector2i(66, 52), Vector2i(67, 52), Vector2i(75, 58), Vector2i(75, 59), Vector2i(75, 60)]
var generators: Array = []
var charge_placed := [false, false, false, false, false, false, false, false]
var flame_consoles: Array = []
var flame_towers: Array = []
var dual_tower_actors: Array = []
var doom_footprint := [Vector2i(75, 77), Vector2i(76, 77), Vector2i(77, 77), Vector2i(78, 77), Vector2i(79, 77), Vector2i(80, 77), Vector2i(81, 77)]
var doom_patrol: Array = []
var v2s: Array = []
var rifles_sent := false
var place_explosives := -1
var take_money := -1
var stop_allies := -1


func _names(prefix: String, n: int, start: int = 1) -> Array:
	var out := []
	for i in range(start, start + n):
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
	turkey = api.player("Turkey")
	england = api.player("England")
	engineers = api.actors(_names("Engi", 4))
	tank_rifles = api.actors(_names("TankRifle", 3))
	generators = api.actors(_names("Generator", 8))
	flame_consoles = api.actors(_names("FlameConsole", 8))
	flame_towers = api.actors(_names("FlameTower", 8))
	dual_tower_actors = api.actors(["DualTower1", "DualTower2", "DoomBarrel"])
	doom_patrol = api.actors(_names("DoomGren", 5) + _names("DoomRifle", 5) + _names("DoomFlamer", 5))
	v2s = api.actors(_names("V2", 8))
	init_objectives(greece)
	place_explosives = api.add_primary_objective(greece, "place-explosive-charges")
	take_money = api.add_secondary_objective(greece, "steal-supplies")
	stop_allies = api.add_primary_objective(ussr, "")
	var gas := api.actor("GasSpawn")
	if gas != null:
		var g := api.location(gas)

		for e in [[7, Vector2i(1, 0)], [7, Vector2i(0, -1)], [17, Vector2i(2, 0)], [17, Vector2i(2, -1)],
				[22, Vector2i(1, -1)], [22, Vector2i(0, 0)]]:
			var off: Vector2i = e[1]
			api.after_delay(api.minutes(e[0]), func(): api.create_actor("flare", england, g + off))
	var cam := api.actor("DefaultCameraPosition")
	if cam != null:
		api.camera_target = cam.pos
	mission_triggers()
	place_charges()
	flame_tower_triggers()
	camera_triggers()
	group_patrol(api.actors(_names("CorePatrol", 3)), _locs(["CorePathA", "CorePathB", "CorePathC", "CorePathD"]), api.seconds(5))
	group_patrol(api.actors(_names("DogPatrolA", 3)), _locs(["PatrolPath1", "MRJCamera", "PatrolPath2", "PatrolPath3"]), api.seconds(5))
	group_patrol(api.actors(_names("DogPatrolB", 3)), _locs(["PatrolPath4", "DoomRoomCam", "PatrolPath5", "DoomRoomCam", "PatrolPath4", "CorePathA"]), api.seconds(5))
	group_patrol(api.actors(_names("RiflePatrolA", 2)), _locs(["PatrolPath6", "PatrolPath7", "PatrolPath2", "MRJCamera", "PatrolPath1", "PatrolPath3", "PatrolPath7", "CorePathC"]), api.seconds(8))
	group_patrol(api.actors(_names("RiflePatrolB", 2)), _locs(["PatrolPath8", "Generator4", "PatrolPath8", "CorePathB"]), api.seconds(8))
	group_patrol(api.actors(_names("RiflePatrolC", 2)), _locs(["PatrolPath9", "PatrolPath10", "CorePathD", "PatrolPath11"]), api.seconds(8))

	var limit := 27
	if difficulty == "easy":
		limit = 32
	elif difficulty == "hard":
		limit = 22
	api.set_time_limit(api.minutes(limit))


func mission_triggers() -> void:
	api.on_all_killed(engineers, func(): api.mark_completed_objective(ussr, stop_allies))
	api.on_all_killed(v2s, func():
		var south := api.actor("ReinforcementsSouth")
		var stop := api.actor("SouthTeamStop")
		if south != null and stop != null:
			api.reinforce(greece, ["e1", "e1", "e1", "medi"], [api.location(south), api.location(stop)], 0)
		api.play_speech_notification(greece, "ReinforcementsArrived"))
	var doom_triggered := [false]
	api.on_entered_footprint(doom_footprint, func(actor, id):
		if actor.player == greece and not doom_triggered[0]:
			api.remove_footprint_trigger(id)
			doom_triggered[0] = true
			for u in doom_patrol:
				api.hunt(u))
	var money := api.actor("MoneyCrates")
	if money != null:
		api.on_entered_proximity(money.pos, 1.0, func(actor, id):
			if actor.player == greece:
				api.remove_proximity_trigger(id)
				api.mark_completed_objective(greece, take_money))
	for u in api.get_actors_by_type(ussr, "ftur"):
		api.on_damaged(u, func(b):
			if b.hp < 0.9:
				api.start_building_repairs(b))
	api.on_timer_expired(func():
		api.set_time_limit(0)

		api.after_delay(1, func(): api.set_mission_text("We're too late!", api.player_color(ussr)))
		api.mark_completed_objective(ussr, stop_allies))


func place_charges() -> void:
	for i in generators.size():
		var gen = generators[i]
		var idx := i
		api.on_entered_proximity(gen.pos, 1.0, func(actor, id):
			if actor.type == "e6":
				api.remove_proximity_trigger(id)
				charge_placed[idx] = true
				api.create_actor("flare", greece, api.location(gen) + Vector2i(0, -1))
				api.play_speech_notification(greece, "ExplosiveChargePlaced")
				api.display_message(api.get_message("explosive-charge-placed"), api.get_message("engineer")))


func flame_tower_triggers() -> void:
	for i in flame_consoles.size():
		var console = flame_consoles[i]
		var idx := i
		api.on_entered_proximity(console.pos, 1.0, func(actor, id):
			if actor.type == "e6":
				api.remove_proximity_trigger(id)
				if idx < flame_towers.size() and not api.is_dead(flame_towers[idx]):
					api.display_message(api.get_message("flame-turret-deactivated"), api.get_message("console"))
					api.kill(flame_towers[idx])
					api.play_sound_notification(greece, "AngryBleep"))
	var turncoat := api.actor("TurncoatConsole")
	var turncoat_pos := api.actor("TurncoatFlameTurret")
	if turncoat != null and turncoat_pos != null:
		api.on_entered_proximity(turncoat.pos, 1.0, func(actor, id):
			if actor.type == "e6":
				api.remove_proximity_trigger(id)
				api.create_actor("ftur", turkey, api.location(turncoat_pos)))
	var two := api.actor("TwoTowerConsole")
	if two != null:
		api.on_entered_proximity(two.pos, 1.0, func(actor, id):
			if actor.type == "e6":
				api.remove_proximity_trigger(id)
				api.display_message(api.get_message("flame-turret-deactivated"), api.get_message("console"))
				for a in dual_tower_actors:
					if not api.is_dead(a):
						api.kill(a))

	for u in api.get_actors(ussr):
		if api.has_property(u, "StartBuildingRepairs"):
			api.on_damaged(u, func(b):
				if b.player == ussr and b.hp < 0.99:
					api.start_building_repairs(b))


func _camera_trigger(cells: Array, cam_name: String, message_key: String = "", message_from: String = "",
		extra: Callable = Callable(), destroy_after: int = 0) -> void:
	var triggered := [false]
	api.on_entered_footprint(cells, func(actor, id):
		if actor.player == greece and not triggered[0]:
			api.remove_footprint_trigger(id)
			triggered[0] = true
			var cam := api.actor(cam_name)
			if cam != null:
				var handle = api.create_actor("camera", greece, api.location(cam))
				if destroy_after > 0 and handle != null:
					api.after_delay(destroy_after, func(): handle.destroy())
			if message_key != "":
				api.display_message(api.get_message(message_key), api.get_message(message_from))
			if extra.is_valid():
				extra.call())


func camera_triggers() -> void:

	var hunt_tank_rifles := func():
		for u in tank_rifles:
			api.hunt(u)
	_camera_trigger(heavy_tank_cam_footprint, "HeavyTankCam", "old-flametowers", "engineer",
		hunt_tank_rifles, api.minutes(1))
	_camera_trigger(mrj_cam_footprint, "MRJCamera", "", "", Callable(), api.minutes(1))
	_camera_trigger(v2_room_footprint, "TurncoatFlameTurret", "", "", Callable(), api.minutes(1))
	var gas := api.actor("GasSpawn")
	if gas != null:
		var gl := api.location(gas)
		var core_triggered := [false]
		api.on_entered_footprint(core_room_footprint, func(actor, id):
			if actor.player == greece and not core_triggered[0]:
				api.remove_footprint_trigger(id)
				core_triggered[0] = true
				api.create_actor("camera", greece, gl + Vector2i(1, 0)))
	var alert := func(): api.play_sound_notification(greece, "AlertBleep")
	_camera_trigger(doom_room_footprint, "DoomRoomCam", "be-sneaky", "soldier", alert, api.minutes(1))


func send_rifles() -> void:
	rifles_sent = true
	api.after_delay(api.seconds(2), func():
		var west := api.actor("ReinforcementsWest")
		var mrj := api.actor("MRJCamera")
		if west != null and mrj != null:
			api.reinforce(greece, ["e1", "e1", "e1"], [api.location(west), api.location(mrj)], 0)
		api.play_speech_notification(greece, "ReinforcementsArrived"))


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


func test_force() -> void:
	for i in charge_placed.size():
		charge_placed[i] = true


func tick() -> void:
	api.set_cash(ussr, 5000)
	var all := true
	for c in charge_placed:
		if not c:
			all = false
	if all:
		api.mark_completed_objective(greece, place_explosives)
		if not api.is_objective_completed(greece, take_money):
			api.mark_failed_objective(greece, take_money)
	if charge_placed[0] and charge_placed[1] and not rifles_sent:
		send_rifles()
