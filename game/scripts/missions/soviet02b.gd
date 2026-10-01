

extends MissionScript

var ussr := 0
var greece := 1

var intro_attackers: Array = []
var bridge_shroud := [Vector2i(63, 71), Vector2i(64, 71), Vector2i(65, 71), Vector2i(69, 65), Vector2i(70, 65), Vector2i(71, 65)]
var bridge_explosion := [Vector2i(66, 69), Vector2i(67, 69), Vector2i(68, 69)]
var transport_trigger := [Vector2i(75, 58)]
var enemy_base_shroud: Array = []
var parachute_trigger: Array = []
var enemy_base_entrance_shroud: Array = []
var attack_waypoints: Array = []
var attack_group: Array = []
var attack_group_size := 3
var allied_infantry := ["e1", "e1", "e3"]
var transport_triggered := false
var allied_objective := -1
var soviet_objective1 := -1
var soviet_objective2 := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	ussr = api.player("USSR")
	greece = api.player("Greece")
	intro_attackers = api.actors(["IntroSoldier1", "IntroSoldier2", "IntroSoldier3"])
	for y in range(52, 65):
		enemy_base_shroud.append(Vector2i(64, y))
	for x in range(80, 90):
		parachute_trigger.append(Vector2i(x, 66))
		enemy_base_entrance_shroud.append(Vector2i(x, 73))
	attack_waypoints = [_loc("AttackWaypoint1"), _loc("AttackWaypoint2")]

	init_objectives(ussr)
	allied_objective = api.add_primary_objective(greece, "")
	soviet_objective1 = api.add_primary_objective(ussr, "protect-command-center")
	soviet_objective2 = api.add_primary_objective(ussr, "destroy-allied-units-structures")

	for a in intro_attackers:
		if not api.is_dead(a):
			api.hunt(a)


	api.after_delay(0, func():
		for a in api.get_actors(greece):
			if api.has_property(a, "StartBuildingRepairs"):
				api.on_damaged(a, func(b):
					if b.player == greece and api.health(b) < api.max_health(b) * 0.8:
						api.start_building_repairs(b)))

	_footprint_camera(bridge_shroud, "CameraBridge")
	_footprint_camera(enemy_base_entrance_shroud, "CameraBaseEntrance")
	_footprint_camera(enemy_base_shroud, "CameraBase1", "CameraBase2")

	var bridge_blown := [false]
	api.on_entered_footprint(bridge_explosion, func(a, id):
		if a.player == ussr and not bridge_blown[0]:
			bridge_blown[0] = true
			api.remove_footprint_trigger(id)
			var barrel := api.actor("BarrelBridge")
			if not api.is_dead(barrel):
				api.kill(barrel))

	var chutes := [false]
	api.on_entered_footprint(parachute_trigger, func(a, id):
		if a.player == ussr and not chutes[0]:
			chutes[0] = true
			api.remove_footprint_trigger(id)
			_paradrop([_loc("ParachuteBaseEntrance")])
			api.play_speech_notification(ussr, "ReinforcementsArrived"))

	api.on_entered_footprint(transport_trigger, func(a, _id):
		if transport_triggered or a.type != "truk":
			return
		transport_triggered = true
		var truck := api.actor("TransportTruck")
		if not api.is_dead(truck):

			api.after_delay(api.seconds(5), func():
				api.move_path(truck, [_loc("TransportWaypoint2"), _loc("TransportWaypoint3"),
						_loc("TransportWaypoint1")], api.seconds(5)))
		api.after_delay(api.seconds(10), func(): transport_triggered = false))

	api.on_killed(api.actor("BarrelBase"), func(_u):
		_paradrop([_loc("ParachuteBase1"), _loc("ParachuteBase2")])
		api.play_speech_notification(ussr, "ReinforcementsArrived"))


	api.on_killed(api.actor("BarrelBridge"), func(_u):
		var c1 := api.actor("BridgeCheck1")
		var c2 := api.actor("BridgeCheck2")
		if c1 == null or c2 == null:
			return
		for b in api.actors_in_box(api.location(c1), api.location(c2)):
			if b.type == "br1" and not api.is_dead(b):
				api.kill(b)
				return)


	api.on_killed(api.actor("Church1"), func(_u):
		api.create_actor("moneycrate", ussr, _loc("TransportWaypoint3")))
	api.on_killed(api.actor("Church2"), func(u):
		api.create_actor("healcrate", ussr, api.location(u)))

	api.on_killed(api.actor("ForwardCommand"), func(_u):
		api.mark_completed_objective(greece, allied_objective))

	api.on_killed(api.actor("IntroSoldier1"), func(_u):
		var cam = api.create_actor("camera", ussr, _loc("CameraStart"))
		if cam != null:
			api.after_delay(api.seconds(15), func(): cam.destroy()))


	api.set_resources(greece, 2000)
	api.after_delay(api.seconds(30), produce_infantry)
	api.camera_target = api.cell_center(_loc("CameraStart"))


func _footprint_camera(cells: Array, a: String, b: String = "") -> void:
	var fired := [false]
	api.on_entered_footprint(cells, func(actor, id):
		if actor.player != ussr or fired[0]:
			return
		fired[0] = true
		api.remove_footprint_trigger(id)
		var handles := []
		for name in ([a, b] if b != "" else [a]):
			var h = api.create_actor("camera", ussr, _loc(name))
			if h != null:
				handles.append(h)
		api.after_delay(api.seconds(15), func():
			for h in handles:
				h.destroy()))


func _paradrop(zones: Array) -> void:
	for z in zones:
		api.send_paratroopers(ussr, ["e1", "e1", "e1", "e3", "e3"], z, Vector2i(0, 1))


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
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, allied_objective)
	if api.has_no_required_units(greece):
		api.mark_completed_objective(ussr, soviet_objective1)
		api.mark_completed_objective(ussr, soviet_objective2)


	pass
