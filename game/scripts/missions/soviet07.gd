

extends MissionScript

var ussr := 0
var spain := 1


var deactivate_security := -1
var free_dogs := -1
var rescue_engineers := -1
var get_engineers_to_coolant := -1
var reprogram_security := -1
var save_reactor := -1


var rocket_retreated := false


const TIME_LIMITS := {"easy": 7, "normal": 6, "hard": 5}
var remaining_time := 0
var timer_color := Color(1, 1, 1)
var countdown_enabled := false


const UNSTABLE_DELAY := [40, 60]

const REVEAL_ON_DEATH := 75

var dogs: Array = []
var engineers: Array = []
var prisoner_guards: Array = []
var entrance_guards: Array = []
var reactor_guards: Array = []
var security_center_guards: Array = []
const STARTING_UNITS_REINFORCEMENTS := ["e1", "e1", "e1", "e1"]
var starting_units: Array = []


func _names(prefix: String, n: int, start: int = 1) -> Array:
	var out := []
	for i in range(start, start + n):
		out.append("%s%d" % [prefix, i])
	return out


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func _cells(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


func is_soviet(a) -> bool:
	return a != null and a.player == ussr


func is_soviet_human(a) -> bool:
	return a != null and a.player == ussr and a.type != "dog"


func is_engineer(a) -> bool:
	return a != null and a.type == "e6"


func mark_allied_victory() -> void:
	if deactivate_security < 0:
		deactivate_security = api.add_primary_objective(ussr, "deactivate-security-system")
	for p in [deactivate_security, rescue_engineers, get_engineers_to_coolant, save_reactor]:
		if p >= 0 and not api.is_objective_completed(ussr, p):
			api.mark_failed_objective(ussr, p)


func update_timer_text() -> void:
	api.set_mission_text(api.fluent_message("time-until-meltdown",
			{"time": api.format_time(remaining_time)}), timer_color)


func footprint_once(cells: Array, filter: Callable, action: Callable) -> void:
	var activated := [false]
	api.on_entered_footprint(cells, func(actor, id):
		if activated[0] or not filter.call(actor):
			return
		activated[0] = true
		action.call()
		api.remove_footprint_trigger(id))


func reveal_area(tag: String) -> void:
	for c in api.actors_with_tag(tag):
		api.set_owner(c, ussr)


func prepare_basic_reveals() -> void:
	var reveals := [
		[_cells([[83, 71], [84, 71]]), "Security Control Center"],
		[_cells([[74, 66], [75, 66], [76, 66], [77, 66]]), "Reactor Room"],
		[_cells([[62, 59], [62, 60], [62, 62], [62, 63]]), "West Coolant Stations"],
		[_cells([[90, 59], [90, 60], [90, 62], [90, 63]]), "East Coolant Stations"],
		[_cells([[67, 82], [67, 83]]), "Flame Tower South"],
		[_cells([[57, 70], [58, 70], [59, 70], [60, 70]]), "Flame Tower West"],
	]
	for r in reveals:
		var tag: String = r[1]
		footprint_once(r[0], is_soviet, func(): reveal_area(tag))


func spawn_friendly_flames() -> void:
	var a = api.create_actor("ftur", ussr, _loc("FriendlyTower1Goal"))
	var b = api.create_actor("ftur", ussr, _loc("FriendlyTower2Goal"))
	var center := _loc("CameraGoalCenter2")
	api.set_camera(api.cell_center(center))
	reveal_area("Reactor Room")
	for guard in reactor_guards:
		if not api.is_dead(guard):
			api.attack_move_path(guard, [_loc("FriendlyTower1Goal"), center])
	var tanya := api.actor("Tanya")
	if not api.is_dead(tanya):
		demolish(tanya, [a, b], 0)
	api.mark_completed_objective(ussr, reprogram_security)


func demolish(u, targets: Array, i: int) -> void:
	if api.is_dead(u) or i >= targets.size():
		return
	var target = targets[i]
	if api.is_dead(target):
		demolish(u, targets, i + 1)
		return
	if not api.demolish(u, target):
		demolish(u, targets, i + 1)
		return
	api.on_killed(target, func(_t): demolish(u, targets, i + 1))


func prepare_security_center() -> void:
	var cells := _cells([[87, 67], [88, 67]])
	api.on_killed(api.actor("SecurityCenterBarrel"), func(_u):
		reveal_area("Security Control Center")
		for g in security_center_guards:
			api.hunt(g))
	footprint_once(cells, is_soviet_human, func():
		for name in ["FlameTowerPrison", "FlameTowerWest", "FlameTowerEast", "FlameTowerSouth"]:
			api.kill(api.actor(name))
		if rescue_engineers < 0:
			rescue_engineers = api.add_primary_objective(ussr, "rescue-engineers")
		api.mark_completed_objective(ussr, deactivate_security))
	footprint_once(cells, is_engineer, spawn_friendly_flames)


func prepare_final_station() -> void:
	var cells := _cells([[73, 51], [74, 51], [75, 51], [76, 51], [77, 51], [78, 51]])
	footprint_once(cells, is_engineer, func():
		countdown_enabled = false
		timer_color = Color("90ee90")
		update_timer_text()
		api.set_time_limit(0)
		api.mark_completed_objective(ussr, save_reactor))


func prepare_engineer_stations() -> void:
	var stations := [
		_cells([[65, 58], [66, 58], [67, 58], [65, 59], [66, 59], [67, 59]]),
		_cells([[65, 64], [66, 64], [67, 64], [65, 65], [66, 65], [67, 65]]),
		_cells([[86, 57], [87, 57], [88, 57], [86, 58], [87, 58], [88, 58]]),
		_cells([[86, 64], [87, 64], [88, 64], [86, 65], [87, 65], [88, 65]]),
	]
	var marks := ["CoolantMarkNorthWest", "CoolantMarkSouthWest", "CoolantMarkNorthEast", "CoolantMarkSouthEast"]
	var coolant_count := [0]
	for i in stations.size():
		var mark: String = marks[i]
		footprint_once(stations[i], is_engineer, func():
			api.play_speech_notification(ussr, "ControlCenterDeactivated")


			api.create_actor("flare", ussr, _loc(mark))
			coolant_count[0] += 1
			if coolant_count[0] < stations.size():
				return
			save_reactor = api.add_primary_objective(ussr, "engineer-reactor-core")
			api.mark_completed_objective(ussr, get_engineers_to_coolant)
			api.after_delay(api.seconds(2), prepare_final_station))


func prepare_rocket_soldiers() -> void:
	var rockets := api.actors(["Rocket1", "Rocket2"])
	var first_traps := api.actors(["RocketTrap1", "RocketTrap2"])
	var trap_cells := _cells([[72, 72], [72, 73], [72, 74]])
	var retreat_trap_cells := _cells([[66, 72], [66, 73], [66, 74]])
	var retreat := _loc("RocketRetreat")
	var retreat_trap := api.actor("RocketRetreatTrap")
	var maze_trap := api.actor("CrateMazeTrap")
	footprint_once(trap_cells, is_soviet, func():
		for i in rockets.size():
			if i < first_traps.size() and not api.is_dead(rockets[i]) and not api.is_dead(first_traps[i]):
				api.attack(rockets[i], first_traps[i])
		reveal_area("Rocket Soldiers"))
	api.on_any_killed(first_traps, func():

		if api.is_dead(maze_trap):
			return
		for r in rockets:
			if not api.is_dead(r):
				api.move(r, retreat))
	api.on_entered_proximity(api.cell_center(retreat), 1.0, func(a, id):
		if a.type == "e3":
			rocket_retreated = true
			api.remove_proximity_trigger(id))
	api.on_entered_footprint(retreat_trap_cells, func(a, id):
		if not rocket_retreated or not is_soviet(a):
			return
		for r in rockets:
			if api.is_dead(r) or api.is_dead(retreat_trap):
				continue
			api.attack(r, retreat_trap)
		api.remove_footprint_trigger(id))
	api.on_killed(retreat_trap, func(_u):
		for r in rockets:
			api.hunt(r))


func prepare_crate_maze_guard() -> void:
	var guard := api.actor("CrateMazeGuard")
	var trap := api.actor("CrateMazeTrap")
	var execution_barrel := api.actor("ExecutionBarrel")
	var trap_cells := _cells([[51, 73], [51, 74]])
	var move_goals := [_loc("CrateMazeWaypoint1"), _loc("CrateMazeWaypoint2"),
			_loc("CrateMazeWaypoint3"), _loc("ExecutionWaypoint")]
	var goal_count := [0]
	var wait_time := api.seconds(2) if difficulty == "hard" else api.seconds(6)
	footprint_once(trap_cells, is_soviet, func():
		if not api.is_dead(trap):
			api.attack(guard, trap)
		api.move(guard, move_goals[0])
		reveal_area("Crate Maze"))
	var proximity := api.on_entered_proximity(api.cell_center(move_goals[3]), 0.5, func(a):
		if a == guard and not api.is_dead(execution_barrel):
			api.attack(a, execution_barrel))
	var foot := api.on_entered_footprint(move_goals, func(a):
		if a != guard:
			return
		api.after_delay(wait_time, func():
			if api.is_dead(guard):
				return
			goal_count[0] += 1
			if goal_count[0] < move_goals.size():
				api.move(guard, move_goals[goal_count[0]])))
	api.on_killed(guard, func(_u):
		api.remove_proximity_trigger(proximity)
		api.remove_footprint_trigger(foot))


func prepare_prison_guards() -> void:
	var tower := api.actor("FlameTowerPrison")
	var tower_and_guards: Array = ([tower] if tower != null else []) + prisoner_guards
	var execution_barrel := api.actor("ExecutionBarrel")
	for guard in prisoner_guards:
		api.on_killed(guard, func(_u):

			if not api.is_objective_completed(ussr, deactivate_security):
				return
			for g in prisoner_guards:
				api.hunt(g))
	api.on_all_killed(tower_and_guards, func():

		if api.is_dead(execution_barrel):
			return
		for e in engineers:
			api.set_owner(e, ussr)
		api.set_owner(api.actor("Prisoner6"), ussr)
		get_engineers_to_coolant = api.add_primary_objective(ussr, "engineers-coolant-station")
		reprogram_security = api.add_secondary_objective(ussr, "engineer-reprogram-security")

		if rescue_engineers < 0:
			rescue_engineers = api.add_primary_objective(ussr, "rescue-engineers")
		api.mark_completed_objective(ussr, rescue_engineers))


func prepare_lab_explosions() -> void:
	var limit := remaining_time
	api.after_delay(limit - api.seconds(153), func(): destabilize(api.actor("EastLab")))
	api.after_delay(limit - api.seconds(63), func(): destabilize(api.actor("WestLab")))


func destabilize(lab) -> void:
	if api.is_dead(lab):
		return
	api.set_health(lab, maxi(1, api.max_health(lab) * 20 / 100))
	var cam = api.create_actor("camera", ussr, api.location(lab))
	api.after_delay(random_integer(UNSTABLE_DELAY[0], UNSTABLE_DELAY[1] + 1), func():
		api.kill(lab)
		api.after_delay(REVEAL_ON_DEATH, func():
			if cam != null:
				cam.destroy()))


func intro_sequence() -> void:
	starting_units = api.reinforce(ussr, STARTING_UNITS_REINFORCEMENTS,
			[_loc("StartingUnitsSpawn"), _loc("EntranceTrapWaypoint1")], 0)
	var countdown_delay := api.seconds(5)
	api.set_time_limit(remaining_time)
	api.after_delay(countdown_delay, func():
		api.play_speech_notification(ussr, "TimerStarted")
		remaining_time -= countdown_delay
		countdown_enabled = true
		update_timer_text())
	api.after_delay(api.seconds(3), func():
		var trap := api.actor("EntranceTrap")
		for a in entrance_guards:
			if api.is_dead(a):
				continue
			if not api.is_dead(trap):
				api.attack(a, trap)
			api.attack_move_path(a, [_loc("EntranceTrapWaypoint1"), _loc("EntranceTrapWaypoint2"),
					_loc("EntranceTrapWaypoint3")], func(u): api.hunt(u)))
	api.on_all_killed(starting_units, func():
		if deactivate_security < 0:
			deactivate_security = api.add_primary_objective(ussr, "deactivate-security-system")
		if not api.is_objective_completed(ussr, deactivate_security):
			mark_allied_victory())
	footprint_once(_cells([[97, 68], [97, 69], [97, 70]]), is_soviet, func():
		deactivate_security = api.add_primary_objective(ussr, "deactivate-security-system")
		free_dogs = api.add_secondary_objective(ussr, "free-dogs")
		reveal_area("Flame Tower East"))


func world_loaded() -> void:
	ussr = api.player("USSR")
	spain = api.player("Spain")
	dogs = api.actors(_names("Dog", 19))
	engineers = api.actors(_names("Prisoner", 5))
	prisoner_guards = api.actors(_names("PrisonerGuard", 3))
	entrance_guards = api.actors(_names("EntranceGuard", 8))
	reactor_guards = api.actors(_names("ReactorGuard", 4))
	security_center_guards = api.actors(_names("SecurityCenterGuard", 4))
	remaining_time = api.minutes(TIME_LIMITS.get(difficulty, 6))
	timer_color = api.player_color(ussr)

	api.camera_target = api.cell_center(_loc("EntranceTrapWaypoint1"))
	reveal_area("Entrance")
	init_objectives(ussr)

	intro_sequence()
	prepare_lab_explosions()
	prepare_basic_reveals()
	prepare_security_center()
	prepare_rocket_soldiers()
	prepare_crate_maze_guard()
	prepare_prison_guards()
	prepare_engineer_stations()

	api.on_killed(api.actor("PillboxBarrel"), func(_u):
		api.kill(api.actor("Pillbox"))
		for d in dogs:
			api.set_owner(d, ussr)
		api.mark_completed_objective(ussr, free_dogs))

	api.on_all_killed(engineers, func():

		if rescue_engineers < 0:
			rescue_engineers = api.add_primary_objective(ussr, "rescue-engineers")
		mark_allied_victory())

	api.on_timer_expired(func():
		api.set_mission_text(api.get_message("too-late"), timer_color)
		mark_allied_victory())


func test_force() -> void:
	var greece := api.player("Greece")
	for u in api.get_actors(greece):
		api.kill(u)
	destabilize(api.actor("EastLab"))
	destabilize(api.actor("WestLab"))
	var soldier = null
	for u in starting_units:
		if not api.is_dead(u):
			soldier = u
			break
	if soldier == null:
		return
	api.after_delay(5, func(): _force_to(soldier, [Vector2i(97, 68), Vector2i(97, 69)]))
	api.after_delay(20, func(): _force_to(soldier, [Vector2i(87, 67), Vector2i(88, 67)]))
	api.after_delay(35, func():
		var stations := [
			[Vector2i(65, 58), Vector2i(66, 58), Vector2i(67, 58)],
			[Vector2i(65, 64), Vector2i(66, 64), Vector2i(67, 64)],
			[Vector2i(86, 57), Vector2i(87, 57), Vector2i(88, 57)],
			[Vector2i(86, 64), Vector2i(87, 64), Vector2i(88, 64)],
		]
		for i in stations.size():
			if i < engineers.size():
				_force_to(engineers[i], stations[i]))
	api.after_delay(120, func():
		for e in engineers:
			if _force_to(e, [Vector2i(75, 51), Vector2i(76, 51), Vector2i(74, 51)]):
				return)


func _force_to(u, cells: Array) -> bool:
	if api.is_dead(u):
		return false
	for c in cells:
		if api.teleport(u, c):
			return true
	return false


func tick() -> void:
	if api.has_no_required_units(ussr) and countdown_enabled:
		mark_allied_victory()
	if remaining_time > 0 and countdown_enabled:
		if remaining_time % api.seconds(1) == 0:
			update_timer_text()
		remaining_time -= 1
