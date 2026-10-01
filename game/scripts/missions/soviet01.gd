

extends MissionScript

var ussr := 0
var france := 1
var germany := 2
var house_damaged := false
var village_raid_objective := -1


func world_loaded() -> void:
	ussr = api.player("USSR")
	france = api.player("France")
	germany = api.player("Germany")
	init_objectives(ussr)
	village_raid_objective = api.add_primary_objective(ussr, "raze-village")

	api.on_all_removed_from_world(api.actors(["Airfield1", "Airfield2", "Airfield3"]), func():
		api.mark_failed_objective(ussr, village_raid_objective))
	jeep_demolishing_bridge()
	paratroopers()


	api.after_delay(api.seconds(2), insert_yaks)
	api.on_damaged(api.actor("HayHouse"), func(_u): panic_attack())
	api.on_killed(api.actor("PillboxBarrel1"), func(_u):
		if not api.is_dead(api.actor("Pillbox1")):
			api.kill(api.actor("Pillbox1")))
	api.on_killed(api.actor("PillboxBarrel2"), func(_u):
		if not api.is_dead(api.actor("Pillbox2")):
			api.kill(api.actor("Pillbox2")))
	var start := api.actor("StartJeep")
	if start != null:
		api.camera_target = start.pos


func jeep_demolishing_bridge() -> void:
	var start_jeep := api.actor("StartJeep")
	var move_point := api.actor("StartJeepMovePoint")
	if start_jeep == null or move_point == null:
		return
	api.move(start_jeep, api.location(move_point))
	api.on_entered_footprint([api.location(move_point)], func(a, id):
		if a.player == france and not api.is_dead(api.actor("BridgeBarrel")):
			api.remove_footprint_trigger(id)
			api.kill(api.actor("BridgeBarrel"))
		kill_bridge())


func kill_bridge() -> void:
	var wp := api.actor("BridgeWaypoint")
	var af := api.actor("Airfield1")
	if wp == null or af == null:
		return
	for b in api.actors_in_box(api.location(wp), api.location(af)):
		if b.type == "bridge1" and not api.is_dead(b):
			api.kill(b)
			return


func paratroopers() -> void:
	for name in ["StartJeep", "Church", "ParaHut"]:
		api.on_killed(api.actor(name), func(_u):
			api.play_speech_notification(ussr, "ReinforcementsArrived")
			paradrop())


func paradrop() -> void:
	var target := api.actor("StartJeepMovePoint")
	if target == null:
		return
	api.send_paratroopers(ussr, ["e1", "e1", "e1", "e2", "e2"], api.location(target), Vector2i(1, 0))


func insert_yaks() -> void:
	var entry := api.actor("YakEntry")
	var target := api.actor("StartJeepMovePoint")
	if entry == null or target == null:
		return
	for i in 3:
		var start := api.location(entry) + Vector2i(0, i * 2)
		var yak = api.create_air_actor("yak", ussr, start, api.facing_between(start, api.location(target)))
		if yak == null:
			return
		api.move(yak, api.location(target))
		var field := api.actor("Airfield%d" % (i + 1))
		if field != null:
			api.land(yak, api.location(field))


func panic_attack() -> void:
	if not house_damaged:
		var spawn := api.actor("CivSpawn")
		if spawn != null:

			api.reinforce(france, ["c3", "c6", "c9"], [api.location(spawn)], 0, func(a):
				api.move(a, api.location(a) + Vector2i(-1, -1))
				api.panic(a))
	house_damaged = true


func test_force() -> void:
	for u in api.get_actors(france) + api.get_actors(germany):
		api.kill(u)


func tick() -> void:
	if api.has_no_required_units(france) and api.has_no_required_units(germany):
		api.mark_completed_objective(ussr, village_raid_objective)
