

extends MissionScript

var greece := 0
var england := 1
var ussr := 1

var construction_vehicle_reinforcements := ["mcv"]
var construction_vehicle_path: Array = []
var jeep_reinforcements := ["e1", "e1", "e1", "jeep"]
var jeep_path: Array = []
var truck_reinforcements := ["truk", "truk", "truk"]
var truck_path: Array = []
var path_guards: Array = []
var soviet_base: Array = []
var idling_units: Array = []
var infantry_types: Array = []
var infantry_delay := 0
var vehicle_types: Array = []
var vehicle_delay := 0
var attack_group_size := 5
var timer_color := Color(1, 1, 1)
var harvester_killed := false
var convoy_on_site := false
var convoy_unharmed := false
var secure_objective := -1
var conquest_objective := -1
var convoy_objective := -1
var ussr_objective := -1


func world_loaded() -> void:
	greece = api.player("Greece")
	england = api.player("England")
	ussr = api.player("USSR")


	match difficulty:
		"easy":
			api.set_time_limit(api.minutes(10) + api.seconds(3))
		"hard":
			api.set_time_limit(api.minutes(3) + api.seconds(3))
			infantry_types = ["e1", "e1", "e1", "e2", "e2", "e1"]
			infantry_delay = api.seconds(10)
			vehicle_types = ["ftrk"]
			vehicle_delay = api.seconds(30)
			attack_group_size = 7
		"tough":
			api.set_time_limit(api.minutes(1) + api.seconds(3))
			construction_vehicle_reinforcements = ["jeep"]
			infantry_types = ["e1", "e1", "e1", "e2", "e2", "dog", "dog"]
			infantry_delay = api.seconds(10)
			vehicle_types = ["ftrk"]
			vehicle_delay = api.minutes(1) + api.seconds(10)
			attack_group_size = 5
		_:
			api.set_time_limit(api.minutes(5) + api.seconds(3))
			infantry_types = ["e1", "e1", "e1", "e2", "e2", "e1"]
			infantry_delay = api.seconds(18)
			attack_group_size = 5
	construction_vehicle_path = [api.location(api.actor("ReinforcementsEntryPoint")), api.location(api.actor("DeployPoint"))]
	jeep_path = [api.location(api.actor("ReinforcementsEntryPoint")), api.location(api.actor("ReinforcementsRallyPoint"))]
	truck_path = [api.location(api.actor("TruckEntryPoint")), api.location(api.actor("TruckRallyPoint"))]
	for i in range(1, 16):
		path_guards.append(api.actor("PathGuard%d" % i))
	soviet_base = api.actors(["SovietConyard", "SovietRefinery", "SovietPower1", "SovietPower2", "SovietSilo", "SovietKennel", "SovietBarracks", "SovietWarfactory"])

	init_objectives(greece)
	ussr_objective = api.add_primary_objective(ussr, "")
	secure_objective = api.add_primary_objective(greece, "secure-convoy")
	conquest_objective = api.add_primary_objective(greece, "eliminate-soviets")
	api.after_delay(api.seconds(1), func(): api.play_speech_notification(greece, "MissionTimerInitialised"))
	run_initial_activities()
	api.reinforce(greece, construction_vehicle_reinforcements, construction_vehicle_path)
	api.after_delay(api.seconds(5), send_jeep_reinforcements)
	api.after_delay(api.seconds(10), send_jeep_reinforcements)
	api.on_timer_expired(func():
		finish_timer()
		send_trucks())
	api.camera_target = api.cell_center(construction_vehicle_path[0])
	timer_color = api.player_color(greece)


func send_jeep_reinforcements() -> void:
	api.play_speech_notification(greece, "ReinforcementsArrived")
	api.reinforce(greece, jeep_reinforcements, jeep_path, api.seconds(1))


func run_initial_activities() -> void:
	var harvester := api.actor("Harvester")
	api.find_resources(harvester)
	api.on_killed(harvester, func(_u): harvester_killed = true)
	schedule_early_attackers()
	api.on_all_killed(path_guards, func():
		api.mark_completed_objective(greece, secure_objective)
		send_trucks())
	api.on_all_killed(soviet_base, func():
		var live_guards := path_guards.filter(func(pg): return not api.is_dead(pg))
		for unit in api.get_ground_attackers(ussr):
			if live_guards.has(unit):
				continue
			api.on_idle(unit, func(u): api.hunt(u)))
	if not infantry_types.is_empty():
		api.after_delay(infantry_delay, produce_infantry)
	if not vehicle_types.is_empty():
		api.after_delay(vehicle_delay, produce_vehicles)


func produce_infantry() -> void:
	if api.is_dead(api.actor("SovietBarracks")):
		return
	var to_build := [random(infantry_types)]


	if api.is_dead(api.actor("SovietKennel")) and to_build[0] == "dog":
		to_build = ["e1"]
	api.build(ussr, to_build, func(units: Array):
		if not units.is_empty():
			idling_units.append(units[0])
		api.after_delay(infantry_delay, produce_infantry)
		if idling_units.size() >= attack_group_size * 1.5:
			send_attack())


func produce_vehicles() -> void:
	if api.is_dead(api.actor("SovietWarfactory")):
		return
	if harvester_killed:
		api.build(ussr, ["harv"], func(units: Array):
			if not units.is_empty():
				api.find_resources(units[0])
				api.on_killed(units[0], func(_u): harvester_killed = true)
			harvester_killed = false
			produce_vehicles())
		return
	api.build(ussr, [random(vehicle_types)], func(units: Array):
		if not units.is_empty():
			idling_units.append(units[0])
		api.after_delay(vehicle_delay, produce_vehicles)
		if idling_units.size() >= attack_group_size * 1.5:
			send_attack())


func send_attack() -> void:
	var units: Array = []
	for i in range(0, attack_group_size + 1):
		if idling_units.is_empty():
			continue
		var n := random_integer(0, idling_units.size() - 1)
		var u = idling_units[n]
		if u != null and not api.is_dead(u):
			units.append(u)
			idling_units.remove_at(n)
	var deploy := api.actor("DeployPoint")
	for unit in units:
		if difficulty != "tough":
			api.attack_move(unit, api.location(deploy))
		api.on_idle(unit, func(u): api.hunt(u))


func test_force() -> void:
	for g in path_guards:
		api.kill(g)
	for b in soviet_base:
		api.kill(b)
	for u in api.get_actors(ussr):
		api.kill(u)


func tick() -> void:
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, conquest_objective)
	if api.has_no_required_units(greece):
		api.mark_completed_objective(ussr, ussr_objective)


func finish_timer() -> void:
	api.set_time_limit(0)
	for i in range(0, 6):
		var c := Color(1, 1, 1) if i % 2 == 0 else timer_color
		api.after_delay(api.seconds(i), func(): api.set_mission_text(api.get_message("convoy-arrived"), c))
	api.after_delay(api.seconds(6), func(): api.set_mission_text(""))


func send_trucks() -> void:
	if convoy_on_site:
		return
	convoy_on_site = true
	api.set_time_limit(0)
	api.set_mission_text("")
	convoy_objective = api.add_primary_objective(greece, "escort-convoy")
	api.play_speech_notification(greece, "ConvoyApproaching")
	api.after_delay(api.seconds(3), func():
		convoy_unharmed = true
		var exit_point := api.location(api.actor("TruckExitPoint"))
		var trucks := api.reinforce(england, truck_reinforcements, truck_path, api.seconds(1),
			func(truck): api.on_idle(truck, func(t): api.move(t, exit_point)))
		var count := [0]
		api.on_entered_footprint([exit_point], func(a, id):
			if a.player == england:
				count[0] += 1
				api.destroy(a)
				if count[0] == 3:
					api.mark_completed_objective(greece, convoy_objective)
					api.remove_footprint_trigger(id))
		api.on_any_killed(trucks, func(_u): convoy_casualties()))


func convoy_casualties() -> void:
	api.play_speech_notification(greece, "ConvoyUnitLost")
	if convoy_unharmed:
		convoy_unharmed = false
		api.after_delay(api.seconds(1), func(): api.mark_failed_objective(greece, convoy_objective))


func schedule_early_attackers() -> void:

	if difficulty == "tough":
		api.after_delay(api.seconds(12), send_early_attackers)
		return
	api.after_delay(api.seconds(6), func():
		if not api.has_prerequisites(greece, ["anypower"]):
			schedule_early_attackers()
			return
		send_early_attackers())


func send_early_attackers() -> void:
	var team := api.actors(["EarlyAttacker1", "EarlyAttacker2", "EarlyAttacker3", "EarlyAttacker4"])
	var dog_targets := api.get_actors_by_type(greece, "e1")
	for member in team:
		if api.is_dead(member):
			continue
		if member.type == "dog" and not dog_targets.is_empty():
			api.attack(member, random(dog_targets))
		api.on_idle(member, func(u): api.hunt(u))
