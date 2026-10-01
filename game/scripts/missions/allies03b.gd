

extends MissionScript

var greece := 0
var ussr := 1

const PRODUCTION_UNITS := ["e1", "e1", "e2"]

const PARADROP_ITEMS := ["e1", "e1", "e1", "e2", "e2"]
const ALLIED_ISLAND_REINFORCEMENTS := ["1tnk", "1tnk"]
const USSR_TANK_REINFORCEMENTS := ["3tnk", "3tnk", "3tnk"]

var production_buildings: Array = []
var first_ussr_base: Array = []
var second_ussr_base: Array = []
var prisoners: Array = []
var jail_barrels: Array = []
var guard_tanks: Array = []
var checkpoint_guards: Array = []
var checkpoint_guard_waypoints: Array = []
var jailed := {}
var jail_cells := {}

var truk_trigger_area: Array = []
var free_medi_trigger_area: Array = []
var camera_trigger_area: Array = []
var beach_trigger_area: Array = []
var paradrop_trigger_area: Array = []
var reinforcements_trigger_area: Array = []
var barracks3_trigger_area: Array = []
var jeep_trigger_area: Array = []

var tanya_type := "e7.noautotarget"
var tanya = null
var jeep = null
var jeep_camera = null
var teleport_jeep_camera := false
var base_camera = null
var large_cameras: Array = []
var first_base_alert := false
var barracks3_producing := false
var truk_triggered := false
var medi_freed := false
var beach_triggered := false
var paradrops_triggered := false
var reinforcements_triggered := false
var jeep_triggered := false
var engis_freed := false
var prisoner_died := false

var kill_bridges := -1
var tanya_survive := -1
var find_allies := -1
var free_prisoners := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func _line(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(Vector2i(c[0], c[1]))
	return out


func world_loaded() -> void:
	greece = api.player("Greece")
	ussr = api.player("USSR")

	production_buildings = api.actors(["USSRBarracks1", "USSRBarracks2", "USSRBarracks3"])
	first_ussr_base = api.actors(["USSRFlameTower1", "USSRFlameTower2", "USSRFlameTower3",
			"USSRBarracks1", "PGuard1", "PGuard2", "PGuard3", "PGuard4", "PGuard5"])


	second_ussr_base = api.actors(["USSRFlameTower4", "USSRFlameTower5", "USSRFlameTower6",
			"USSRRadarDome", "USSRBarracks2", "USSRPowerPlant", "USSRSubPen", "USSRBaseGuard1",
			"USSRBaseGuard2", "MediGuard"])
	jail_barrels = api.actors(["JeepBarrel1", "JeepBarrel2", "JeepBarrel3", "JeepBarrel4"])
	guard_tanks = api.actors(["Heavy1", "Heavy2", "Heavy3"])
	checkpoint_guards = api.actors(["USSRCheckpointGuard1", "USSRCheckpointGuard2"])
	checkpoint_guard_waypoints = [_loc("CheckpointGuardWaypoint1"), _loc("CheckpointGuardWaypoint2")]
	jeep = api.actor("Jeep")

	for x in range(51, 58):
		truk_trigger_area.append(Vector2i(x, 89))
	free_medi_trigger_area = _line([[56, 93], [56, 94], [57, 94], [57, 95], [57, 96], [57, 97],
			[57, 98], [57, 99], [57, 100], [57, 101], [57, 102]])
	camera_trigger_area = _line([[73, 88], [73, 87], [76, 92], [76, 93], [76, 94]])
	beach_trigger_area = _line([[111, 36], [112, 36], [112, 37], [113, 37], [113, 38], [114, 38],
			[114, 39], [115, 39], [116, 39], [116, 40], [117, 40], [118, 40], [119, 40], [119, 41]])
	for x in range(81, 88):
		paradrop_trigger_area.append(Vector2i(x, 66))
	paradrop_trigger_area += _line([[93, 64], [94, 64], [94, 63], [95, 63], [95, 62], [96, 62],
			[96, 61], [97, 61], [97, 60], [98, 60], [99, 60], [100, 60], [101, 60], [102, 60], [103, 60]])
	reinforcements_trigger_area = _line([[57, 46], [58, 46], [66, 35], [65, 35], [65, 36], [64, 36],
			[64, 37], [64, 38], [64, 39], [64, 40], [64, 41], [63, 41], [63, 42], [63, 43], [62, 43], [62, 44]])
	barracks3_trigger_area = _line([[69, 50], [69, 51], [69, 52], [69, 53], [69, 54], [61, 45],
			[62, 45], [62, 46], [62, 47], [62, 48], [63, 48], [57, 46], [58, 46]])
	jeep_trigger_area = _line([[75, 76], [76, 76], [77, 76], [78, 76], [79, 76], [80, 76], [81, 76],
			[82, 76], [91, 78], [92, 78], [93, 78], [95, 84], [96, 84], [97, 84], [98, 84], [99, 84], [100, 84]])

	tanya_type = "e7" if difficulty == "easy" else "e7.noautotarget"

	init_players()
	add_objectives()
	lock_up_prisoners()
	init_triggers()
	setup_allied_units()


func init_players() -> void:
	api.set_cash(ussr, 10000)


func add_objectives() -> void:
	init_objectives(greece)
	kill_bridges = api.add_primary_objective(greece, "destroy-bridges")
	tanya_survive = api.add_primary_objective(greece, "tanya-survive")
	find_allies = api.add_secondary_objective(greece, "find-lost-tanks")
	free_prisoners = api.add_secondary_objective(greece, "free-prisoners")


func lock_up_prisoners() -> void:
	for name in ["Jail1", "Jail2"]:
		var j := api.actor(name)
		if j != null:
			jail_cells[name] = api.location(j)


	for entry in [["PrisonedMedi", "Jail1"], ["PrisonedEngi1", "Jail2"], ["PrisonedEngi2", "Jail2"],
			["PrisonedEngi3", "Jail2"], ["PrisonedEngi4", "Jail2"]]:
		var u := api.actor(entry[0])
		if u == null:
			continue
		var cell := api.location(u)
		if not jail_cells.has(entry[1]):
			jail_cells[entry[1]] = cell
		jailed[entry[0]] = {"type": u.type, "cell": cell, "jail": entry[1]}
		api.destroy(u)
	for name in jail_cells:
		var cell: Vector2i = jail_cells[name]
		api.on_entered_proximity(api.cell_center(cell), 3.0, func(a, id):
			if a.player == greece:
				api.remove_proximity_trigger(id)
				open_jail(name))


func open_jail(jail: String) -> void:
	for id in jailed.keys():
		var d: Dictionary = jailed[id]
		if d["jail"] != jail:
			continue
		jailed.erase(id)
		var u = api.create_actor(d["type"], greece, d["cell"])
		if u == null:
			continue
		prisoners.append(u)
		api.on_killed(u, func(_x): prisoner_lost())


func prisoner_lost() -> void:
	if prisoner_died:
		return
	prisoner_died = true
	api.mark_failed_objective(greece, free_prisoners)


func setup_allied_units() -> void:
	tanya = api.create_actor(tanya_type, greece, _loc("TanyaWaypoint"))
	if tanya_type == "e7.noautotarget":
		api.after_delay(api.seconds(2), func():
			api.display_message(api.fluent_message("tanya-rules-of-engagement"),
					api.fluent_message("tanya")))
	if tanya != null:
		api.camera_target = tanya.pos
		api.on_killed(tanya, func(_u): api.mark_failed_objective(greece, tanya_survive))
	else:
		api.camera_target = api.cell_center(_loc("TanyaWaypoint"))


	var heli := api.actor("InsertionHeli")
	if heli != null:
		api.after_delay(api.seconds(2), func():
			if api.is_dead(heli):
				return
			var exit_wp := api.actor("InsertionHeliExit")
			if exit_wp != null:
				api.move(heli, api.location(exit_wp))
			api.after_delay(api.seconds(20), func(): api.destroy(heli)))


func setup_top_right_island() -> void:
	api.mark_completed_objective(greece, find_allies)
	api.play_speech_notification(greece, "AlliedReinforcementsArrived")
	api.reinforce(greece, ALLIED_ISLAND_REINFORCEMENTS,
			[_loc("AlliedIslandReinforcementsEntry"), _loc("IslandParadropReinforcementsDropzone")])
	send_ussr_paradrops(_loc("IslandParadropReinforcementsDropzone"))


func send_ussr_paradrops(dropzone: Vector2i) -> void:
	for p in api.send_paratroopers(ussr, PARADROP_ITEMS, dropzone, Vector2i(0, 1)):
		api.hunt(p)


func send_ussr_tank_reinforcements() -> void:
	var camera = api.create_actor("camera", greece, _loc("USSRReinforcementsCameraWaypoint"))
	var tanks := api.reinforce(ussr, USSR_TANK_REINFORCEMENTS, [_loc("USSRReinforcementsEntryWaypoint"),
			_loc("USSRReinforcementsCameraWaypoint") + Vector2i(1, -1), _loc("USSRReinforcementsRallyWaypoint")])

	api.after_delay(api.seconds(4), func():
		api.on_all_removed_from_world(tanks, func():
			api.after_delay(api.seconds(3), func():
				if camera != null and not camera.is_dead():
					camera.destroy())))


func jeep_checkpoint_move() -> void:
	if api.is_dead(jeep):
		return
	jeep_camera = api.create_actor("camera.jeep", greece, api.location(jeep))
	teleport_jeep_camera = true
	api.on_idle(jeep, func(j):
		if api.location(j) == _loc("JeepCheckpoint"):
			api.clear_all_for(j)
			for i in checkpoint_guards.size():
				if not api.is_dead(checkpoint_guards[i]) and i < checkpoint_guard_waypoints.size():
					api.move(checkpoint_guards[i], checkpoint_guard_waypoints[i])
		else:
			api.move(j, _loc("JeepCheckpoint")))


func jeep_suicide_move() -> void:
	if api.is_dead(jeep):
		return
	if jeep_camera == null:
		jeep_camera = api.create_actor("camera.jeep", greece, api.location(jeep))
		teleport_jeep_camera = true
	api.on_idle(jeep, func(j):
		if api.location(j) == _loc("JeepSuicideWaypoint"):
			api.clear_all_for(j)
			teleport_jeep_camera = false
			api.kill(j)
			var tower := api.actor("USSRFlameTower4")
			if not api.is_dead(tower):
				api.kill(tower)
			api.after_delay(api.seconds(1), func():
				if jeep_camera != null:
					jeep_camera.destroy())
		else:
			api.move(j, _loc("JeepSuicideWaypoint")))


func alert_first_base() -> void:
	if first_base_alert:
		return
	first_base_alert = true
	for unit in first_ussr_base:
		if api.has_property(unit, "Move"):
			api.hunt(unit)
	for i in 3:
		api.after_delay(api.seconds(i), func(): api.play_sound_notification(greece, "AlertBuzzer"))
	produce_units(api.actor("USSRBarracks1"), random_integer(4, 8))


func produce_units(factory, count: int) -> void:
	if api.is_producing(ussr, "e1"):
		api.after_delay(api.seconds(5), func(): produce_units(factory, count))
		return
	var units: Array = []
	for i in count + 1:
		units.append(random(PRODUCTION_UNITS))
	if api.is_dead(factory):
		return
	api.set_primary(factory)
	api.build(ussr, units, func(soldiers: Array):
		for unit in soldiers:
			api.hunt(unit))


func bridge_actors() -> Array:
	return api.where(api.actors_in_world(), func(a): return a.type == "bridge1" or a.type == "bridge2")


func init_triggers() -> void:
	for unit in api.get_ground_attackers(ussr):
		api.on_damaged(unit, func(u): api.hunt(u))

	api.on_killed(api.actor("MediHideaway"), func(_u):
		if not medi_freed:
			medi_freed = true
			prisoner_lost())


	api.on_killed(api.actor("ExplosiveBarrel"), func(_u):
		if reinforcements_triggered:
			return
		var bridges := bridge_actors()
		if not bridges.is_empty() and not api.is_dead(bridges[0]):
			api.kill(bridges[0])
		reinforcements_triggered = true
		api.after_delay(api.seconds(1), send_ussr_tank_reinforcements))

	api.on_killed(api.actor("ExplosiveBarrel2"), func(_u):
		var tower := api.actor("USSRFlameTower3")
		if not api.is_dead(tower):
			api.kill(tower))

	api.on_any_killed(jail_barrels, func(_u):
		for barrel in jail_barrels:
			if not api.is_dead(barrel):
				api.kill(barrel)
		for tank in guard_tanks:
			if not api.is_dead(tank):
				api.kill(tank)
		jeep_triggered = true
		jeep_suicide_move())

	for unit in first_ussr_base:
		api.on_damaged(unit, func(_u):
			if base_camera == null:
				base_camera = api.create_actor("camera", greece, _loc("BaseCameraWaypoint"))
			alert_first_base())
	api.on_all_killed_or_captured(first_ussr_base, func():
		if base_camera != null and base_camera.is_in_world():
			base_camera.destroy())

	api.on_damaged(api.actor("USSRBarracks3"), func(_u):
		if not barracks3_producing:
			barracks3_producing = true
			produce_units(api.actor("USSRBarracks3"), random_integer(2, 5)))

	api.on_capture(api.actor("USSRRadarDome"), func(_u):
		for name in ["LargeCameraWaypoint1", "LargeCameraWaypoint2", "LargeCameraWaypoint3"]:
			var c = api.create_actor("camera.verylarge", greece, _loc(name))
			if c != null:
				large_cameras.append(c))
	api.on_removed_from_world(api.actor("USSRRadarDome"), func(_u):
		for c in large_cameras:
			if c.is_in_world():
				c.destroy()
		large_cameras.clear())

	api.on_entered_footprint(truk_trigger_area, func(a, id):
		if a.player != greece or truk_triggered:
			return
		truk_triggered = true
		api.remove_footprint_trigger(id)
		var truk := api.actor("USSRTruk")
		if api.is_dead(truk):
			return
		api.on_idle(truk, func(t):
			if api.location(t) == _loc("BaseCameraWaypoint"):
				api.clear_all_for(t)
				var driver = api.create_actor("e1", ussr, api.location(t))
				if driver != null:
					var guard := api.actor("PGuard5")
					if not api.is_dead(guard):
						api.attack_move(driver, api.location(guard))
					else:
						api.scatter(driver)
					first_ussr_base.append(driver)
				api.after_delay(api.seconds(3), alert_first_base)
			else:
				api.move(t, _loc("BaseCameraWaypoint")))
		api.on_entered_proximity(api.cell_center(_loc("BaseCameraWaypoint")), 7.0, func(b, pid):
			if b.type == "truk" and base_camera == null:
				api.remove_proximity_trigger(pid)
				base_camera = api.create_actor("camera", greece, _loc("BaseCameraWaypoint"))))

	api.on_entered_footprint(free_medi_trigger_area, func(a, id):
		if a.player == greece and not medi_freed:
			medi_freed = true
			api.remove_footprint_trigger(id)
			api.reinforce(greece, ["medi"], [_loc("MediSpawnpoint"), _loc("MediRallypoint")]))
	api.on_entered_footprint(camera_trigger_area, func(a, id):
		if a.player == greece and base_camera == null:
			api.remove_footprint_trigger(id)
			base_camera = api.create_actor("camera", greece, _loc("BaseCameraWaypoint")))
	api.on_entered_footprint(beach_trigger_area, func(a, id):
		if a.player == greece and not beach_triggered:
			beach_triggered = true
			api.remove_footprint_trigger(id)
			setup_top_right_island())
	api.on_entered_footprint(paradrop_trigger_area, func(a, id):
		if a.player == greece and a.type != "jeep.mission" and not paradrops_triggered:
			paradrops_triggered = true
			api.remove_footprint_trigger(id)
			send_ussr_paradrops(_loc("ParadropReinforcementsDropzone")))
	api.on_entered_footprint(reinforcements_trigger_area, func(a, id):
		if a.player == greece and not reinforcements_triggered:
			reinforcements_triggered = true
			api.remove_footprint_trigger(id)
			api.after_delay(api.seconds(1), send_ussr_tank_reinforcements))
	api.on_entered_footprint(barracks3_trigger_area, func(a, id):
		if a.player == greece and not barracks3_producing:
			barracks3_producing = true
			api.remove_footprint_trigger(id)
			produce_units(api.actor("USSRBarracks3"), random_integer(2, 5)))
	api.on_entered_footprint(jeep_trigger_area, func(a, id):
		if a.player == greece and not jeep_triggered:
			jeep_triggered = true
			api.remove_footprint_trigger(id)
			jeep_checkpoint_move())


	api.on_exited_proximity(api.cell_center(_loc("BaseCameraWaypoint")), 7.0, func(a, id):
		if a.type == "e6" and not engis_freed:
			engis_freed = true
			api.remove_proximity_trigger(id))

	api.after_delay(0, func():
		api.on_all_killed(bridge_actors(), func():
			api.mark_completed_objective(greece, kill_bridges)
			api.mark_completed_objective(greece, tanya_survive)
			if medi_freed and api.is_dead(api.actor("MediGuard")) and engis_freed:
				api.mark_completed_objective(greece, free_prisoners)))


func tick() -> void:
	if teleport_jeep_camera and jeep_camera != null and not api.is_dead(jeep):
		jeep_camera.teleport(api.location(jeep))


func test_force() -> void:
	for b in bridge_actors():
		api.kill(b)
