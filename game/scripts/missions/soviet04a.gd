

extends MissionScript

var ussr := 0
var greece := 1
var civs: Array = []
var village: Array = []
var soviet_mcv := ["mcv"]
var infantry_reinf_greece := ["e1", "e1", "e1", "e1", "e1"]
var avengers := ["jeep", "1tnk", "2tnk", "2tnk", "1tnk"]
var patrol1_group := ["jeep", "jeep", "2tnk", "2tnk"]
var patrol2_group := ["jeep", "1tnk", "1tnk", "1tnk"]
var allied_infantry_types := ["e1", "e3"]
var allied_armor_types := ["jeep", "jeep", "1tnk", "1tnk", "1tnk"]
var armor_reinf_greece := ["jeep", "jeep", "1tnk", "1tnk", "1tnk"]
var inf_attack: Array = []
var armor_attack: Array = []
var attack_paths: Array = []
var village_cam_area: Array = []
var base_buildings: Array = []
var all_villagers_dead := false
var village_camera = null
var rcheck := false
var kill_all := -1
var beat_ussr := -1
var kill_radar := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	ussr = api.player("USSR")
	greece = api.player("Greece")

	if difficulty == "easy":
		armor_reinf_greece = ["jeep", "1tnk", "1tnk"]
	civs = api.actors(["civ1", "civ2", "civ3"])
	village = api.actors(["civ1", "civ2", "civ3", "village1", "village2", "village5"])
	attack_paths = [[_loc("VillageEntrancePoint")], [_loc("BridgeEntrancePoint"), _loc("NERoadTurnPoint"), _loc("CrossroadsEastPoint")]]
	for x in range(68, 69):
		for y in range(75, 83):
			village_cam_area.append(Vector2i(x, y))
	base_buildings = [
		{"type": "powr", "pos": Vector2i(0, 4), "cost": 300, "exists": false},
		{"type": "tent", "pos": Vector2i(-9, 6), "cost": 400, "exists": true, "name": "Barr"},
		{"type": "proc", "pos": Vector2i(4, 7), "cost": 1400, "exists": true, "name": "Proc"},
		{"type": "weap", "pos": Vector2i(8, -1), "cost": 2000, "exists": true, "name": "Weap"},
	]
	run_initial_activities()
	init_objectives(ussr)
	kill_all = api.add_primary_objective(ussr, "defeat-allied-forces")
	beat_ussr = api.add_primary_objective(greece, "")
	kill_radar = api.add_secondary_objective(ussr, "destroy-radar-dome-reinforcements")
	api.on_killed(api.actor("RadarDome"), func(_u):
		api.mark_completed_objective(ussr, kill_radar)
		api.play_speech_notification(ussr, "ObjectiveMet"))
	api.camera_target = api.cell_center(_loc("StartCamPoint"))


func radar_alive() -> bool:
	var r := api.actor("RadarDome")
	return not api.is_dead(r) and r.player == greece


func run_initial_activities() -> void:
	api.find_resources(api.actor("Harvester"))
	idling_units()
	api.after_delay(10, func():
		bring_patrol1()
		bring_patrol2()
		build_base())

	for a in api.named_actors():
		if a.player == greece and api.has_property(a, "StartBuildingRepairs"):
			api.on_damaged(a, func(b):
				if b.player == greece and b.hp < 0.75:
					api.start_building_repairs(b))
	api.reinforce(ussr, soviet_mcv, [_loc("StartPoint"), _loc("SovietBasePoint")], 0, func(mcv): api.move(mcv, _loc("StartCamPoint")))
	api.play_speech_notification(ussr, "ReinforcementsArrived")
	for b in base_buildings:
		if b.has("name"):
			var entry = b
			api.on_killed(api.actor(b["name"]), func(_u): entry["exists"] = false)
	api.on_entered_footprint(village_cam_area, func(actor, id):
		if actor.player == ussr:
			api.remove_footprint_trigger(id)
			if not all_villagers_dead:
				village_camera = api.create_actor("camera", ussr, _loc("VillagePoint")))

	api.on_all_killed(village, func():
		all_villagers_dead = true
		if village_camera != null:
			village_camera.destroy()
			village_camera = null)
	api.on_any_killed(civs, func(_u):
		for c in civs:
			api.clear_all_for(c)
		var units := api.reinforce(greece, avengers, [_loc("SWRoadPoint")], 0, func(u): api.hunt(u))
		units.size())
	api.move(api.actor("Runner1"), _loc("CrossroadsEastPoint"))
	api.move(api.actor("Runner2"), _loc("InVillagePoint"))
	api.move(api.actor("Tank5"), _loc("V2MovePoint"))
	api.after_delay(api.seconds(2), func():
		for n in ["Tank1", "Tank2", "Tank3", "Tank4", "Tank5"]:
			api.stop(api.actor(n))
		api.after_delay(1, func():
			api.move(api.actor("Tank1"), _loc("SovietBaseEntryPointNE"))
			api.move(api.actor("Tank2"), _loc("SovietBaseEntryPointW"))
			api.move(api.actor("Tank3"), _loc("SovietBaseEntryPointNE"))
			api.move(api.actor("Tank4"), _loc("SovietBaseEntryPointW"))
			api.move(api.actor("Tank5"), _loc("V2MovePoint"))))
	api.after_delay(api.minutes(1), produce_infantry)
	api.after_delay(api.minutes(2), produce_armor)

	if difficulty == "hard" or difficulty == "normal":
		api.after_delay(api.seconds(15), reinf_inf)
	api.after_delay(api.minutes(1), reinf_inf)
	api.after_delay(api.minutes(3), reinf_inf)
	api.after_delay(api.minutes(2), reinf_armor)


func idling_units() -> void:
	for unit in api.get_ground_attackers(greece):
		api.on_damaged(unit, func(u):
			api.clear_all_for(u)
			api.after_delay(0, func(): api.hunt(u)))


func build_base() -> void:
	for b in base_buildings:
		if not b["exists"]:
			build_building(b)
			return
	api.after_delay(api.seconds(10), build_base)


func build_building(building: Dictionary) -> void:
	api.after_delay(api.build_time(building["type"]), func():
		var cyard := api.actor("CYard")
		var gcy := api.actor("GreeceCYard")
		if api.is_dead(cyard) or cyard.player != greece or gcy == null:
			return
		if api.is_dead(api.actor("Harvester")) and api.resources(greece) <= 299:
			return
		var actor = api.create_actor(building["type"], greece, api.location(gcy) + building["pos"])
		api.sim.give_credits(greece, -building["cost"])
		building["exists"] = true
		if actor != null:
			api.on_killed(actor, func(_u): building["exists"] = false)
			api.on_damaged(actor, func(b):
				if b.player == greece and b.hp < 0.75:
					api.start_building_repairs(b))
		api.after_delay(api.seconds(10), build_base))


func produce_infantry() -> void:
	if not base_buildings[1]["exists"]:
		return
	if api.is_dead(api.actor("Harvester")) and api.resources(greece) <= 299:
		return
	var delay := random_integer(api.seconds(3), api.seconds(9))
	var path: Array = random(attack_paths)
	api.build(greece, [random(allied_infantry_types)], func(units: Array):
		if not units.is_empty():
			inf_attack.append(units[0])
		if inf_attack.size() >= 10:
			send_units(inf_attack, path)
			inf_attack = []
			api.after_delay(api.minutes(2), produce_infantry)
		else:
			api.after_delay(delay, produce_infantry))


func produce_armor() -> void:
	if not base_buildings[3]["exists"]:
		return
	if api.is_dead(api.actor("Harvester")) and api.resources(greece) <= 599:
		return
	var delay := random_integer(api.seconds(12), api.seconds(17))
	var path: Array = random(attack_paths)
	api.build(greece, [random(allied_armor_types)], func(units: Array):
		if not units.is_empty():
			armor_attack.append(units[0])
		if armor_attack.size() >= 6:
			send_units(armor_attack, path)
			armor_attack = []
			api.after_delay(api.minutes(3), produce_armor)
		else:
			api.after_delay(delay, produce_armor))


func send_units(units: Array, waypoints: Array) -> void:
	for unit in units:
		if not api.is_dead(unit):
			api.attack_move_path(unit, waypoints, func(u): api.hunt(u))


func reinf_inf() -> void:
	if not radar_alive():
		return
	api.reinforce(greece, infantry_reinf_greece, [_loc("SWRoadPoint"), _loc("InVillagePoint")], 0, func(s): api.hunt(s))


func reinf_armor() -> void:
	if radar_alive():
		rcheck = true
		api.reinforce(greece, armor_reinf_greece, [_loc("NRoadPoint"), _loc("CrossroadsNorthPoint")], 0, func(s): api.hunt(s))


func bring_patrol1() -> void:
	if not radar_alive():
		return
	var path := [_loc("NearRadarPoint"), _loc("ToRadarPoint"), _loc("InVillagePoint"), _loc("ToRadarPoint")]
	var units := api.reinforce(greece, patrol1_group, [_loc("SWRoadPoint")], 0, func(p): api.patrol(p, path, true, 250))


	api.on_all_killed(units, func(): api.after_delay(patrol_respawn(), bring_patrol1))


func bring_patrol2() -> void:
	if not radar_alive():
		return
	var path := [_loc("BridgeEntrancePoint"), _loc("NERoadTurnPoint"), _loc("CrossroadsEastPoint"), _loc("BridgeEntrancePoint")]
	var units := api.reinforce(greece, patrol2_group, [_loc("NRoadPoint")], 0, func(p): api.patrol(p, path, true, 250))
	api.on_all_killed(units, func(): api.after_delay(patrol_respawn(), bring_patrol2))


func patrol_respawn() -> int:
	return api.minutes(4) if difficulty == "hard" else api.minutes(7)


func test_force() -> void:
	for u in api.get_actors(greece):
		api.kill(u)


func tick() -> void:
	if api.has_no_required_units(greece):
		api.mark_completed_objective(ussr, kill_all)
		api.mark_completed_objective(ussr, kill_radar)
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, beat_ussr)


	if rcheck:
		rcheck = false

		var wait := api.minutes(5)
		if difficulty == "hard":
			wait = api.seconds(150)
		elif difficulty == "easy":
			wait = api.minutes(8)
		api.after_delay(wait, reinf_armor)
