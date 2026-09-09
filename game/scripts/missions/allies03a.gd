

extends MissionScript

var greece := 0
var ussr := 1

const PRODUCTION_UNITS := ["e1", "e1", "e2"]
const TRANSPORT_REINFORCEMENTS := ["e1", "e1", "e1", "e2", "e2"]

const PARADROP_ITEMS := ["e1", "e1", "e1", "e2", "e2"]

var production_buildings: Array = []
var first_ussr_base: Array = []
var second_ussr_base: Array = []
var prisoners: Array = []
var jailed := {}
var prisoner_died := false
var camera_trigger_area: Array = []
var water_transport_trigger_area: Array = []
var paradrop_trigger_area: Array = []
var reinforcements_trigger_area: Array = []

var tanya_type := "e7.noautotarget"
var base_camera = null
var first_base_alert := false
var second_base_alert := false
var water_transport_triggered := false
var paradrops_triggered := false
var reinforcements_triggered := false
var base_trigger := -1

var kill_bridges := -1
var tanya_survive := -1
var kill_ussr := -1
var free_prisoners := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	greece = api.player("Greece")
	ussr = api.player("USSR")

	production_buildings = api.actors(["USSRBarracks1", "USSRBarracks2"])
	first_ussr_base = api.actors(["USSRFlameTower1", "USSRBarracks1", "USSRPowerPlant1", "USSRPowerPlant2",
			"USSRConstructionYard1", "USSRTechCenter", "USSRBaseGuard1", "USSRBaseGuard2", "USSRBaseGuard3",
			"USSRBaseGuard4", "USSRBaseGuard5", "USSRBaseGuard6", "USSRBaseGuard7", "USSRBaseGuard8"])
	second_ussr_base = api.actors(["USSRBarracks2", "USSRKennel", "USSRRadarDome", "USSRBaseGuard10",
			"USSRBaseGuard11", "USSRBaseGuard12", "USSRBaseGuard13", "USSRBaseGuard14"])
	lock_up_prisoners()
	for x in range(43, 48):
		camera_trigger_area.append(Vector2i(x, 64))
	for x in range(39, 46):
		water_transport_trigger_area.append(Vector2i(x, 54))
	for x in range(81, 84):
		paradrop_trigger_area.append(Vector2i(x, 60))
	for x in range(63, 73):
		paradrop_trigger_area.append(Vector2i(x, 63))
	reinforcements_trigger_area = [Vector2i(96, 55), Vector2i(97, 55), Vector2i(97, 56), Vector2i(98, 56)]


	tanya_type = "e7" if difficulty == "easy" else "e7.noautotarget"

	init_players()
	init_objectives(greece)
	add_objectives()
	init_triggers()
	send_allied_units()


func lock_up_prisoners() -> void:
	for id in ["PrisonedMedi1", "PrisonedMedi2", "PrisonedEngi"]:
		var u := api.actor(id)
		if u == null:
			continue
		jailed[id] = {"type": u.type, "cell": api.location(u)}
		api.destroy(u)


func open_jail(ids: Array) -> void:
	for id in ids:
		if not jailed.has(id):
			continue
		var d: Dictionary = jailed[id]
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


func init_players() -> void:

	api.set_cash(ussr, 10000)


func add_objectives() -> void:
	kill_bridges = api.add_primary_objective(greece, "destroy-bridges")
	tanya_survive = api.add_primary_objective(greece, "tanya-survive")
	kill_ussr = api.add_secondary_objective(greece, "destroy-oilpumps")
	free_prisoners = api.add_secondary_objective(greece, "free-prisoners")


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


func send_allied_units() -> void:
	api.camera_target = api.cell_center(_loc("TanyaWaypoint"))
	var entry := _loc("AlliedUnitsEntry")
	var artillery = api.create_actor("arty", greece, entry)
	var tanya = api.create_actor(tanya_type, greece, entry)

	if tanya_type == "e7.noautotarget":
		api.after_delay(api.seconds(2), func():
			api.display_message(api.fluent_message("tanya-rules-of-engagement"),
					api.fluent_message("tanya")))
	if artillery != null:
		api.set_stance(artillery, "HoldFire")
		api.move(artillery, _loc("ArtilleryWaypoint"))
	if tanya != null:
		api.move(tanya, _loc("TanyaWaypoint"))
		api.on_killed(tanya, func(_u): api.mark_failed_objective(greece, tanya_survive))


func send_ussr_paradrops() -> void:
	var lz := _loc("ParadropLZ")
	for dir in [Vector2i(0, 1), Vector2i(1, 0)]:
		for p in api.send_paratroopers(ussr, PARADROP_ITEMS, lz, dir):
			api.hunt(p)


func send_ussr_water_transport() -> void:
	api.reinforce(ussr, TRANSPORT_REINFORCEMENTS, [_loc("WaterTransportLoadout")], api.seconds(0.5),
			func(u): api.hunt(u))


func send_ussr_tank_reinforcements() -> void:
	var camera = api.create_actor("camera", greece, _loc("USSRReinforcementsCameraWaypoint"))
	api.reinforce(ussr, ["3tnk"], [_loc("USSRReinforcementsEntryWaypoint"),
			_loc("USSRReinforcementsRallyWaypoint1"), _loc("USSRReinforcementsRallyWaypoint2")], 25,
			func(tank):
				api.on_removed_from_world(tank, func(_u):
					api.after_delay(api.seconds(3), func():
						if camera != null and not camera.is_dead():
							camera.destroy())))


func init_triggers() -> void:
	for unit in api.get_ground_attackers(ussr):
		api.on_damaged(unit, func(u): api.hunt(u))

	for p in prisoners:
		api.on_killed(p, func(_u): prisoner_lost())

	api.on_killed(api.actor("USSRTechCenter"), func(_u):
		api.create_actor("moneycrate", ussr, _loc("USSRMoneyCrateSpawn")))


	api.on_killed(api.actor("ExplosiveBarrel"), func(_u):
		var bridges := bridge_actors()
		if not bridges.is_empty() and not api.is_dead(bridges[0]):
			api.kill(bridges[0]))

	base_trigger = api.on_entered_footprint(camera_trigger_area, func(a, id):
		if a.player == greece and base_camera == null:
			api.remove_footprint_trigger(id)
			base_camera = api.create_actor("camera", greece, _loc("BaseCameraWaypoint")))

	for unit in first_ussr_base:
		api.on_damaged(unit, func(_u): first_base_damaged())
	api.on_all_killed_or_captured(first_ussr_base, func():
		if base_camera != null and base_camera.is_in_world():
			base_camera.destroy())

	for unit in second_ussr_base:
		api.on_damaged(unit, func(_u): second_base_damaged())


	api.on_capture(api.actor("USSRRadarDome"), func(self_actor):
		var large_camera = api.create_actor("camera.verylarge", greece, _loc("LargeCameraWaypoint"))
		api.clear_all_for(self_actor)
		api.after_delay(api.seconds(1), func():
			api.on_removed_from_world(self_actor, func(_u):
				api.clear_all_for(self_actor)
				if large_camera != null and large_camera.is_in_world():
					large_camera.destroy())))

	api.on_entered_footprint(water_transport_trigger_area, func(a, id):
		if a.player == greece and not water_transport_triggered:
			water_transport_triggered = true
			api.remove_footprint_trigger(id)
			send_ussr_water_transport())
	api.on_entered_footprint(paradrop_trigger_area, func(a, id):
		if a.player == greece and not paradrops_triggered:
			paradrops_triggered = true
			api.remove_footprint_trigger(id)
			send_ussr_paradrops())
	api.on_entered_footprint(reinforcements_trigger_area, func(a, id):
		if a.player == greece and not reinforcements_triggered:
			reinforcements_triggered = true
			api.remove_footprint_trigger(id)
			api.after_delay(api.seconds(1), send_ussr_tank_reinforcements))

	api.after_delay(0, func():
		api.on_all_killed(bridge_actors(), func():
			api.mark_completed_objective(greece, kill_bridges)
			api.mark_completed_objective(greece, tanya_survive)

			if api.is_dead(api.actor("PGuard1")) and api.is_dead(api.actor("PGuard2")):
				api.mark_completed_objective(greece, free_prisoners))
		api.on_all_killed(api.get_actors_by_type(ussr, "v19"), func():
			api.mark_completed_objective(greece, kill_ussr)))


	api.on_killed(api.actor("Jail1Barrel"), func(_u): open_jail(["PrisonedMedi1"]))
	api.on_killed(api.actor("Jail2Barrel"), func(_u): open_jail(["PrisonedMedi2", "PrisonedEngi"]))


func bridge_actors() -> Array:
	return api.where(api.actors_in_world(), func(a): return a.type == "bridge1")


func first_base_damaged() -> void:
	if first_base_alert:
		return
	first_base_alert = true
	if base_camera == null:
		base_camera = api.create_actor("camera", greece, _loc("BaseCameraWaypoint"))
		api.remove_footprint_trigger(base_trigger)
	for unit in first_ussr_base:
		if api.has_property(unit, "Move"):
			api.hunt(unit)
	alert_buzzer()
	produce_units(api.actor("USSRBarracks1"), random_integer(4, 8))


func second_base_damaged() -> void:
	if second_base_alert:
		return
	second_base_alert = true
	for unit in second_ussr_base:
		if api.has_property(unit, "Move"):
			api.hunt(unit)
	alert_buzzer()
	produce_units(api.actor("USSRBarracks2"), random_integer(5, 7))


func alert_buzzer() -> void:
	for i in 3:
		api.after_delay(api.seconds(i), func(): api.play_sound_notification(greece, "AlertBuzzer"))


func test_force() -> void:
	for b in bridge_actors():
		api.kill(b)
