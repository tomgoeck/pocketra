

extends MissionScript

var ussr := 0
var greece := 1
var goodguy := 2
var france := 3

const SOVIET_START_REINF := ["e2", "e2"]
const INFANTRY_REINF_GREECE := ["e1", "e1", "e1", "e1", "e1"]
const ALLIED_INFANTRY_TYPES := ["e1", "e3"]

const PARADROP_ITEMS := ["e1", "e1", "e1", "e2", "e2"]

const BOUNDS := Rect2i(20, 42, 90, 50)

var armor_reinf_greece := ["jeep", "jeep", "1tnk", "1tnk", "1tnk"]
var greece_inf_attack: Array = []
var infantry_waypoints: Array = []
var base_established := false
var rcheck := false
var expansion_check := false

var capture_objective := -1
var kill_all := -1
var beat_ussr := -1
var hold_objective := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	ussr = api.player("USSR")
	greece = api.player("Greece")
	goodguy = api.player("GoodGuy")
	france = api.player("France")
	if difficulty == "easy":
		armor_reinf_greece = ["jeep", "1tnk", "1tnk"]
	infantry_waypoints = [_loc("CrossroadPoint"), _loc("NWOrefieldPoint"), _loc("AtUSSRBasePoint"),
			_loc("SovietBasePoint")]

	init_objectives(ussr)
	capture_objective = api.add_primary_objective(ussr, "capture-radar-dome")
	kill_all = api.add_primary_objective(ussr, "defeat-allied-forces")
	beat_ussr = api.add_primary_objective(greece, "")

	run_initial_activities()


	api.on_damaged(api.actor("mcvGG"), func(_u): expand())
	api.on_damaged(api.actor("mcvtransport"), func(_u): expand())

	api.on_killed(api.actor("RadarDome"), func(_u):
		if not api.is_objective_completed(ussr, capture_objective):
			api.mark_failed_objective(ussr, capture_objective)
		if hold_objective >= 0:
			api.mark_failed_objective(ussr, hold_objective))

	api.on_capture(api.actor("RadarDome"), func(dome):
		if api.is_objective_completed(ussr, kill_all):
			api.mark_completed_objective(ussr, capture_objective)
			return
		hold_objective = api.add_primary_objective(ussr, "defend-radar-dome")
		api.mark_completed_objective(ussr, capture_objective)
		if difficulty == "easy":
			api.create_actor("camera", ussr, _loc("MCVDeploy"))
			api.display_message(api.fluent_message("allied-expansion-movement-detected"))
		else:
			api.create_actor("mcv.cam", ussr, _loc("MCVDeploy"))
			api.display_message(api.fluent_message("coordinates-allied-expansion-discovered"))
		if not expansion_check:
			expand()
			expansion_check = true
		api.reinforce(greece, armor_reinf_greece, [_loc("ReinfRoadPoint"), _loc("CrossroadPoint"),
				_loc("GreeceBaseEPoint"), _loc("GreeceBasePoint")], 0, func(s): api.hunt(s))
		api.clear_all_for(dome)
		api.after_delay(0, func():
			api.on_removed_from_world(dome, func(_u):
				api.mark_failed_objective(ussr, hold_objective))))

	api.on_entered_proximity(api.cell_center(_loc("USSRExpansionPoint")), 4.0, func(unit, id):
		var dome := api.actor("RadarDome")
		if unit.player != ussr or api.is_dead(dome) or dome.player != ussr:
			return
		api.remove_proximity_trigger(id)
		para(_loc("USSRExpansionPoint"))

		api.reinforce(ussr, ["mcv", "3tnk", "3tnk", "e1", "e1"],
				[_loc("USSRlstPoint")], 25, func(u):
					if u.type == "mcv":
						api.move(u, _loc("USSRExpansionPoint"))
					else:
						api.attack_move(u, _loc("USSRExpansionPoint")))
		api.play_speech_notification(ussr, "ReinforcementsArrived"))

	api.camera_target = api.cell_center(_loc("StartCamPoint"))


func run_initial_activities() -> void:

	expansion_check = difficulty == "hard"
	if expansion_check:
		expand()

	api.after_delay(1, func():
		api.find_resources(api.actor("Harvester"))
		idling_units()
		api.play_speech_notification(ussr, "ReinforcementsArrived")
		for a in api.actors_in_world():
			if a.player == greece and api.has_property(a, "StartBuildingRepairs"):
				api.on_damaged(a, func(b):
					if b.player == greece and b.hp < 0.75:
						api.start_building_repairs(b)))

	api.reinforce(ussr, SOVIET_START_REINF, [_loc("StartPoint"), _loc("SovietBasePoint")], 0,
			func(s): api.attack_move(s, _loc("SovietBasePoint")))
	api.create_actor("camera", ussr, _loc("GreeceBasePoint"))
	api.create_actor("camera", ussr, _loc("SovietBasePoint"))

	api.move(api.actor("startmcv"), _loc("MCVStartMovePoint"))
	for n in ["Runner1", "Runner2", "Runner3"]:
		api.move(api.actor(n), _loc("RunnerPoint"))

	produce_infantry()

	if difficulty == "hard" or difficulty == "normal":
		api.after_delay(api.seconds(25), reinf_inf)
	api.after_delay(api.minutes(2), reinf_inf)
	api.after_delay(api.minutes(5), reinf_inf)


func expand() -> void:
	if expansion_check or api.is_dead(api.actor("mcvtransport")) or api.is_dead(api.actor("mcvGG")):
		return
	expansion_check = true
	api.display_message(api.fluent_message("allied-mcv-island"))


func idling_units() -> void:
	for unit in api.actors_in_world():
		if unit.player == greece and api.has_property(unit, "Hunt"):
			api.on_damaged(unit, func(u):
				api.clear_all_for(u)
				api.after_delay(0, func(): api.hunt(u)))


func para(target: Vector2i) -> void:
	var entry := _edge_near(target)
	api.reinforce(ussr, PARADROP_ITEMS, [entry, target], api.seconds(0.5))


func _edge_near(cell: Vector2i) -> Vector2i:
	var left := cell.x - BOUNDS.position.x
	var right := BOUNDS.end.x - 1 - cell.x
	var top := cell.y - BOUNDS.position.y
	var bottom := BOUNDS.end.y - 1 - cell.y
	var best := mini(mini(left, right), mini(top, bottom))
	if best == left:
		return Vector2i(BOUNDS.position.x, cell.y)
	if best == right:
		return Vector2i(BOUNDS.end.x - 1, cell.y)
	if best == top:
		return Vector2i(cell.x, BOUNDS.position.y)
	return Vector2i(cell.x, BOUNDS.end.y - 1)


func reinf_inf() -> void:
	api.reinforce(greece, INFANTRY_REINF_GREECE, [_loc("ReinfRoadPoint")], 0, func(s): api.hunt(s))


func reinf_armor() -> void:
	rcheck = false
	api.reinforce(greece, armor_reinf_greece, [_loc("ReinfRoadPoint")], 0, func(s): api.hunt(s))


func produce_infantry() -> void:
	if api.is_dead(api.actor("Barr")):
		return
	var delay := random_integer(api.seconds(3), api.seconds(9))
	api.build(greece, [random(ALLIED_INFANTRY_TYPES)], func(units: Array):
		if not units.is_empty():
			greece_inf_attack.append(units[0])
		if greece_inf_attack.size() >= 7:
			send_units(greece_inf_attack, infantry_waypoints)
			greece_inf_attack = []
			api.after_delay(api.minutes(2), produce_infantry)
		else:
			api.after_delay(delay, produce_infantry))


func send_units(units: Array, waypoints: Array) -> void:
	for unit in units:
		if not api.is_dead(unit):
			api.attack_move_path(unit, waypoints, func(u): api.hunt(u))


func check_for_base() -> bool:
	var count := 0
	for a in api.actors_in_box(_loc("BaseRectTL"), _loc("BaseRectBR")):
		if (a.type == "fact" or a.type == "powr") and a.player == ussr:
			count += 1
	return count >= 2


func test_force() -> void:
	var dome := api.actor("RadarDome")
	for owner in [greece, goodguy, france]:
		for u in api.get_actors(owner):
			if u != dome:
				api.kill(u)
	if not api.is_dead(dome):
		var eng = api.spawn_near("e6", ussr, api.location(dome) + Vector2i(0, 2))
		if eng != null:
			var ids := PackedInt32Array()
			ids.append(eng.id)
			api.sim.order_capture(ids, dome.id)


func tick() -> void:
	if api.has_no_required_units(greece) and api.has_no_required_units(goodguy):
		api.mark_completed_objective(ussr, kill_all)
		if hold_objective >= 0:
			api.mark_completed_objective(ussr, hold_objective)
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, beat_ussr)


	for p in [greece, goodguy]:
		var cap := api.resource_capacity(p)
		if cap > 0 and api.resources(p) >= cap * 0.75:
			api.give_cash(p, api.resources(p) - int(cap * 0.25))
			api.set_resources(p, int(cap * 0.25))

	if not base_established and check_for_base():
		base_established = true
		para(_loc("ParaPoint"))

	if not rcheck:
		rcheck = true

		var wait := api.minutes(4)
		if difficulty == "easy":
			wait = api.minutes(6)
		elif difficulty == "hard":
			wait = api.minutes(3)
		api.after_delay(wait, reinf_armor)
