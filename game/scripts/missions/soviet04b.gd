

extends MissionScript

var ussr := 0
var greece := 1

const INFANTRY_REINF_GREECE := ["e1", "e1", "e1", "e1", "e1"]
const AVENGERS := ["jeep", "1tnk", "2tnk", "2tnk", "1tnk"]
const PATROL1_GROUP := ["jeep", "jeep", "2tnk", "2tnk"]
const PATROL2_GROUP := ["jeep", "1tnk", "1tnk", "1tnk"]
const ALLIED_INFANTRY_TYPES := ["e1", "e3"]
const ALLIED_ARMOR_TYPES := ["jeep", "jeep", "1tnk", "1tnk", "1tnk"]

var armor_reinf_greece := ["jeep", "jeep", "1tnk", "1tnk", "1tnk"]
var civs: Array = []
var village: Array = []
var guards: Array = []
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
	civs = api.actors(["civ1", "civ2", "civ3", "civ4"])
	village = api.actors(["civ1", "civ3", "civ4", "village1", "village3"])
	guards = api.actors(["Guard1", "Guard2", "Guard3"])
	attack_paths = [
		[_loc("CrossroadsPoint"), _loc("ToVillageRoadPoint"), _loc("VillagePoint")],
		[_loc("EntranceSouthPoint"), _loc("OrefieldSouthPoint")],
		[_loc("CrossroadsPoint"), _loc("ToBridgePoint")],
	]
	village_cam_area = [Vector2i(37, 58), Vector2i(37, 59), Vector2i(37, 60), Vector2i(38, 60),
		Vector2i(39, 60), Vector2i(40, 60), Vector2i(41, 60), Vector2i(35, 57), Vector2i(34, 57),
		Vector2i(33, 57), Vector2i(32, 57)]
	base_buildings = [
		{"type": "powr", "pos": Vector2i(-4, -2), "cost": 300, "exists": true, "name": "Powr"},
		{"type": "tent", "pos": Vector2i(-8, 1), "cost": 400, "exists": true, "name": "Barr"},
		{"type": "proc", "pos": Vector2i(-5, 1), "cost": 1400, "exists": true, "name": "Proc"},
		{"type": "weap", "pos": Vector2i(-12, -1), "cost": 2000, "exists": true, "name": "Weap"},
	]

	run_initial_activities()
	init_objectives(ussr)
	kill_all = api.add_primary_objective(ussr, "defeat-allied-forces")
	beat_ussr = api.add_primary_objective(greece, "")
	kill_radar = api.add_secondary_objective(ussr, "destroy-radar-dome-reinforcements")

	api.on_killed(api.actor("RadarDome"), func(_u):
		api.mark_completed_objective(ussr, kill_radar)
		api.play_speech_notification(ussr, "ObjectiveMet"))


	api.on_damaged(api.actor("Harvester"), func(_u):
		var harv := api.actor("Harvester")
		for unit in guards:
			if not api.is_dead(unit) and not api.is_dead(harv):
				api.attack_move(unit, api.location(harv)))

	api.camera_target = api.cell_center(_loc("StartCamPoint"))


func radar_alive() -> bool:
	var r := api.actor("RadarDome")
	return not api.is_dead(r) and r.player == greece


func run_initial_activities() -> void:
	api.find_resources(api.actor("Harvester"))

	var helper := api.actor("Helper")
	if helper != null:
		api.destroy(helper)
	idling_units()
	api.after_delay(api.seconds(1), func():
		bring_patrol1()
		api.after_delay(api.seconds(5), bring_patrol2)
		build_base())

	for a in api.named_actors():
		if a.player == greece and api.has_property(a, "StartBuildingRepairs"):
			api.on_damaged(a, func(b):
				if b.player == greece and b.hp < 0.75:
					api.start_building_repairs(b))

	for b in base_buildings:
		var entry: Dictionary = b
		api.on_killed(api.actor(b["name"]), func(_u): entry["exists"] = false)

	api.on_entered_footprint(village_cam_area, func(actor, id):
		if actor.player == ussr:
			api.remove_footprint_trigger(id)
			if not all_villagers_dead:
				village_camera = api.create_actor("camera", ussr, _loc("VillagePoint")))
	api.on_all_killed(village, func():
		if village_camera != null:
			village_camera.destroy()
			village_camera = null
		all_villagers_dead = true)
	api.on_any_killed(civs, func(_u):
		for c in civs:
			api.clear_all_for(c)
		api.reinforce(greece, AVENGERS, [_loc("NRoadPoint")], 0, func(u): api.hunt(u)))

	api.after_delay(api.minutes(1), produce_infantry)
	api.after_delay(api.minutes(2), produce_armor)

	if difficulty == "hard" or difficulty == "normal":
		api.after_delay(api.seconds(5), reinf_inf)
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
		var a = api.create_actor(building["type"], greece, api.location(gcy) + building["pos"])
		api.set_cash(greece, api.cash(greece) - int(building["cost"]))
		building["exists"] = true
		if a != null:
			api.on_killed(a, func(_u): building["exists"] = false)
			api.on_damaged(a, func(b):
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
	api.build(greece, [random(ALLIED_INFANTRY_TYPES)], func(units: Array):
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
	api.build(greece, [random(ALLIED_ARMOR_TYPES)], func(units: Array):
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


func reinf_path() -> Array:
	return [_loc("NRoadPoint"), _loc("CrossroadsPoint"), _loc("ToVillageRoadPoint"), _loc("VillagePoint")]


func reinf_inf() -> void:
	if not radar_alive():
		return
	api.reinforce(greece, INFANTRY_REINF_GREECE, reinf_path(), 0, func(s): api.hunt(s))


func reinf_armor() -> void:
	if radar_alive():
		rcheck = true
		api.reinforce(greece, armor_reinf_greece, reinf_path(), 0, func(s): api.hunt(s))


func bring_patrol1() -> void:
	if not radar_alive():
		return
	var path := [_loc("ToVillageRoadPoint"), _loc("ToBridgePoint"), _loc("InBasePoint")]
	var units := api.reinforce(greece, PATROL1_GROUP, [_loc("NRoadPoint")], 0,
			func(p): api.patrol(p, path, true, 250))
	api.on_all_killed(units, func(): api.after_delay(patrol_respawn(), bring_patrol1))


func bring_patrol2() -> void:
	if not radar_alive():
		return
	var path := [_loc("EntranceSouthPoint"), _loc("ToRadarBridgePoint"), _loc("IslandPoint"),
			_loc("ToRadarBridgePoint")]
	var units := api.reinforce(greece, PATROL2_GROUP, [_loc("NRoadPoint")], 0,
			func(p): api.patrol(p, path, true, 250))
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

	var cap := api.resource_capacity(greece)
	if cap > 0 and api.resources(greece) >= cap * 0.75:
		api.give_cash(greece, api.resources(greece) - int(cap * 0.25))
		api.set_resources(greece, int(cap * 0.25))
	if rcheck:
		rcheck = false

		var wait := api.minutes(5)
		if difficulty == "hard":
			wait = api.seconds(150)
		elif difficulty == "easy":
			wait = api.minutes(8)
		api.after_delay(wait, reinf_armor)
