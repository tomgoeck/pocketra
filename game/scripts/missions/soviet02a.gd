

extends MissionScript

var ussr := 0
var greece := 1
var camera_trigger_area: Array = []
var passing_bridge := [Vector2i(59, 56), Vector2i(60, 56)]
var cmd_atk: Array = []
var fleeing: Array = []
var hunting: Array = []
var attack_waypoints: Array = []
var attack_group: Array = []
var attack_group_size := 3
var allied_infantry := ["e1", "e1", "e3"]
var already_hunting := false
var command_center_intact := -1
var destroy_all_allied := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	ussr = api.player("USSR")
	greece = api.player("Greece")
	cmd_atk = api.actors(["Attacker1", "Attacker2", "Attacker3", "Attacker4"])
	fleeing = api.actors(["Fleeing1", "Fleeing2"])
	hunting = api.actors(["Hunter1", "Hunter2", "Hunter3", "Hunter4"])
	attack_waypoints = [_loc("AttackWaypoint1"), _loc("AttackWaypoint2")]
	for x in [42, 43, 44, 45, 46, 47, 48]:
		camera_trigger_area.append(Vector2i(x, 45))
	for y in [56, 57, 58, 59]:
		camera_trigger_area.append(Vector2i(48, y))
	for x in range(40, 48):
		camera_trigger_area.append(Vector2i(x, 63))

	init_objectives(ussr)
	command_center_intact = api.add_primary_objective(ussr, "protect-command-center")
	destroy_all_allied = api.add_primary_objective(ussr, "destroy-allied-units-structures")
	api.camera_target = api.cell_center(_loc("CameraWaypoint"))

	api.on_killed(api.actor("CommandCenter"), func(_u):
		api.mark_failed_objective(ussr, command_center_intact))


	api.after_delay(0, func():
		for a in api.get_actors(greece):
			if api.has_property(a, "StartBuildingRepairs"):
				api.on_damaged(a, func(b, attacker): _building_damaged(b, attacker)))


	api.after_delay(api.seconds(1), func():
		api.create_actor("camera", ussr, _loc("Box1"))
		for u in fleeing:
			api.move(u, _loc("RifleRetreat"))
		api.attack_move(api.actor("Follower"), _loc("RifleRetreat")))


	api.on_any_killed(api.actors(["BridgeBarrel1", "BridgeBarrel2"]), func(_u): _blow_bridge())
	api.on_entered_footprint(passing_bridge, func(unit, id):
		if unit.player != ussr:
			return
		api.remove_footprint_trigger(id)
		var barrel := api.actor("Barrel")
		if barrel == null or api.is_dead(barrel):
			return
		for f in fleeing:
			if not api.is_dead(f):

				api.attack(f, barrel, true, true)
				return)


	api.after_delay(api.seconds(24), func():
		for unit in cmd_atk:
			if api.is_dead(unit):
				continue
			api.attack_move(unit, attack_waypoints[0])
			api.on_idle(unit, func(u): api.hunt(u)))

	api.attack_move(api.actor("Hunter4"), attack_waypoints[1])
	for unit in hunting:
		if not api.is_dead(unit):
			api.on_idle(unit, func(u): api.hunt(u))


	api.on_any_killed(api.actors(["AlliedDome", "AlliedProc"]), func(_u): _paradrop())


	api.set_resources(greece, 2000)
	api.after_delay(api.seconds(30), produce_infantry)


func _building_damaged(b, attacker) -> void:
	if b.player != greece or api.health(b) >= api.max_health(b) * 0.8:
		return
	api.start_building_repairs(b)

	if already_hunting or (attacker != null and attacker.type == "yak"):
		return
	already_hunting = true
	for unit in api.get_ground_attackers(greece):
		api.on_idle(unit, func(u): api.hunt(u))


func _blow_bridge() -> void:
	var wp1 := api.actor("Box1")
	var wp2 := api.actor("Box2")
	if wp1 == null or wp2 == null:
		return
	for b in api.actors_in_box(api.location(wp1), api.location(wp2)):
		if b.type in ["br1", "br2", "bridge1", "bridge2"] and not api.is_dead(b):
			api.kill(b)


func _paradrop() -> void:
	var lz := _loc("ParadropLZ")
	api.send_paratroopers(ussr, ["e2", "e2", "e2", "e2", "e2"], lz, Vector2i(0, 1))
	api.after_delay(api.seconds(3), func():
		api.send_paratroopers(ussr, ["e2", "e2", "e2", "e2", "e2"], lz, Vector2i(1, 1)))
	api.play_speech_notification(ussr, "ReinforcementsArrived")


func send_attack_group() -> void:
	if attack_group.size() < attack_group_size:
		return
	var way: Vector2i = random(attack_waypoints)
	for unit in attack_group:
		if api.is_dead(unit):
			continue
		api.attack_move(unit, way)
		api.on_idle(unit, func(u): api.hunt(u))
	attack_group = []


func produce_infantry() -> void:
	if api.is_dead(api.actor("Tent")):
		return
	api.build(greece, [random(allied_infantry)], func(units: Array):
		if not units.is_empty():
			attack_group.append(units[0])
		send_attack_group()
		api.after_delay(api.seconds(10), produce_infantry))


func test_force() -> void:
	for u in api.get_actors(greece):
		api.kill(u)


func tick() -> void:
	if api.has_no_required_units(greece):
		api.mark_completed_objective(ussr, command_center_intact)
		api.mark_completed_objective(ussr, destroy_all_allied)
	if api.has_no_required_units(ussr):
		api.mark_failed_objective(ussr, destroy_all_allied)

