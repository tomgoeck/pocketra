

extends MissionScript

var greece := 0
var ussr := 1


const TANYA_TYPES := {"easy": "e7", "normal": "e7.noautotarget", "hard": "e7.noautotarget", "tough": "e7.noautotarget"}
const REINFORCE_CASH := {"easy": 5000, "normal": 2250, "hard": 2250, "tough": 1500}
const HOLD_AI_TIME := {"easy": 4500, "normal": 3000, "hard": 3000, "tough": 2250}
const SPECIAL_CAMERAS := {"easy": true, "normal": true, "hard": true, "tough": false}


const GREECE_REINFORCEMENTS := [
	{"types": ["2tnk", "2tnk", "2tnk", "arty", "arty"], "entry": "SpyLoadout"},
	{"types": ["e3", "e3", "e3", "e6", "e6"], "entry": "GreeceLoadout1"},
	{"types": ["jeep", "jeep", "e1", "e1", "2tnk"], "entry": "GreeceLoadout2"},
]

const TANYA_VOICES := ["tuffguy", "bombit", "laugh", "keepem"]
const DEATH_VOICES := ["death1", "death2", "death3"]
const SPY_VOICE := "sking"


const SOVIET_INFANTRY_TYPES := ["e1", "e1", "e2", "e4"]
const SOVIET_VEHICLE_TYPES := ["3tnk", "3tnk", "3tnk", "v2rl", "v2rl", "apc"]
const ATTACK_GROUP_SIZE := 6

var tanya_type := "e7.noautotarget"
var reinforce_cash := 2250
var hold_ai_time := 3000
var special_cameras := true

var spy = null
var tanya = null
var truk_path: Array = []
var sam_sites: Array = []
var dog_patrol: Array = []
var patrol_a: Array = []
var patrol_b: Array = []
var rallypoints: Array = []

var spy_camera_a = null
var spy_camera_b = null
var prison_camera = null
var truk_reveal = null
var follow_truk := false
var greece_reinforcements_arrived := false


var idling_units: Array = []
var hold_production := true
var attacking := false
var build_vehicles := true
var train_infantry := true
var attack_ongoing := false
var harvester_killed := false
var ai_active := false

var ussr_objective := -1
var rescue_tanya := -1
var kill_all := -1
var infiltrate_warfactory := -1
var kill_sams := -1
var extraction_ready := false


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func _locs(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append(_loc(n))
	return out


func world_loaded() -> void:
	greece = api.player("Greece")
	ussr = api.player("USSR")
	tanya_type = TANYA_TYPES.get(difficulty, "e7.noautotarget")
	reinforce_cash = REINFORCE_CASH.get(difficulty, 2250)
	hold_ai_time = HOLD_AI_TIME.get(difficulty, 3000)
	special_cameras = SPECIAL_CAMERAS.get(difficulty, true)

	truk_path = _locs(["TrukWaypoint1", "TrukWaypoint2", "TrukWaypoint3", "TrukWaypoint4",
			"TrukWaypoint5", "TrukWaypoint6"])
	sam_sites = api.actors(["Sam1", "Sam2", "Sam3", "Sam4"])
	dog_patrol = api.actors(["Dog1", "Dog2"])
	patrol_a = api.actors(["PatrolA1", "PatrolA2", "PatrolA3", "PatrolA4", "PatrolA5"])
	patrol_b = api.actors(["PatrolB1", "PatrolB2", "PatrolB3"])
	rallypoints = _locs(["VehicleRallypoint1", "VehicleRallypoint2", "VehicleRallypoint3",
			"VehicleRallypoint4", "VehicleRallypoint5"])

	init_objectives(greece)
	add_objectives()
	init_triggers()
	send_spy()
	api.after_delay(api.seconds(3), activate_patrols)


func add_objectives() -> void:
	ussr_objective = api.add_primary_objective(ussr, "")
	rescue_tanya = api.add_primary_objective(greece, "rescue-tanya")
	kill_all = api.add_primary_objective(greece, "eliminate-soviet-units")
	infiltrate_warfactory = api.add_secondary_objective(greece, "infiltrate-warfactory")


func send_spy() -> void:
	api.set_camera(api.cell_center(_loc("SpyEntry")))
	spy = api.spawn_near("spy", greece, _loc("SpyLoadout"))
	if spy != null:
		api.on_killed(spy, func(_u): api.mark_completed_objective(ussr, ussr_objective))
	if special_cameras:
		spy_camera_a = api.create_actor("camera", greece, _loc("SpyCamera1"))
		spy_camera_b = api.create_actor("camera", greece, _loc("SpyCamera2"))
	api.after_delay(api.seconds(3), func():
		api.display_message(api.get_message("disguise-spy"), api.get_message("spy")))


func activate_patrols() -> void:
	group_patrol(dog_patrol, _locs(["DogPatrolRally1", "DogPatrolRally2", "DogPatrolRally3"]), api.seconds(2))
	api.after_delay(api.seconds(3), func():
		group_patrol(patrol_a, _locs(["PatrolRally", "PatrolARally1", "PatrolARally2", "PatrolARally3"]), api.seconds(7))
		group_patrol(patrol_b, _locs(["PatrolBRally1", "PatrolBRally2", "PatrolBRally3", "PatrolRally"]), api.seconds(6)))


func group_patrol(units: Array, waypoints: Array, delay: int) -> void:
	for u in units:
		api.patrol(u, waypoints, true, delay)


func init_triggers() -> void:
	var warfactory := api.actor("Warfactory")
	var truk := api.actor("Truk")
	api.on_infiltrated(warfactory, func(_b, _spy):
		if api.is_objective_completed(greece, infiltrate_warfactory):
			return
		if api.is_dead(truk):
			if not api.is_objective_completed(greece, rescue_tanya):
				api.mark_completed_objective(ussr, ussr_objective)
			return
		api.clear_all_for(spy)
		api.mark_completed_objective(greece, infiltrate_warfactory)
		warfactory_infiltrated())

	api.on_killed(truk, func(_u):
		if not api.is_objective_completed(greece, infiltrate_warfactory):
			api.mark_failed_objective(greece, infiltrate_warfactory)
		elif follow_truk:
			api.mark_completed_objective(ussr, ussr_objective))

	api.on_infiltrated(api.actor("Prison"), func(_b, _spy): prison_infiltrated())


	var fp5 := api.on_entered_footprint([truk_path[4]], func(a, id):
		if a == truk:
			api.remove_footprint_trigger(id)
			spawn_prison_spy())

	api.on_entered_footprint([truk_path[5]], func(a, id):
		if a == truk:
			api.remove_footprint_trigger(id)
			api.remove_footprint_trigger(fp5)
			api.stop(a)
			api.kill(a)
			var barrel := api.actor("ExplosiveBarrel")
			if not api.is_dead(barrel):
				api.kill(barrel))


	if difficulty != "tough":
		api.on_killed(api.actor("Mammoth"), func(_u):
			api.after_delay(maxi(1, hold_ai_time - api.seconds(45)), func(): hold_production = false)
			api.after_delay(hold_ai_time, func(): attacking = true))

	api.on_killed(api.actor("FlameBarrel"), func(_u):
		var tower := api.actor("FlameTower")
		if not api.is_dead(tower):
			api.kill(tower))
	api.on_killed(api.actor("SamBarrel"), func(_u):
		var s := api.actor("Sam1")
		if not api.is_dead(s):
			api.kill(s))

	api.on_all_killed(sam_sites, func(): sams_destroyed())


func warfactory_infiltrated() -> void:
	follow_truk = true
	var truk := api.actor("Truk")
	if api.is_dead(truk):
		return
	truk_reveal = api.create_actor("camera.small", greece, api.location(truk))
	api.after_delay(api.seconds(1), func(): api.move_path(truk, truk_path))
	if special_cameras:
		api.after_delay(api.seconds(2), func():
			destroy_reveal(spy_camera_a)
			destroy_reveal(spy_camera_b)
			spy_camera_a = null
			spy_camera_b = null)


func spawn_prison_spy() -> void:
	follow_truk = false
	var prison := api.actor("Prison")
	spy = api.spawn_near("spy", greece, truk_path[4])
	if spy != null:
		api.disguise_as_type(spy, "e1", ussr)
		api.move(spy, _loc("SpyWaypoint"))
		api.after_delay(api.seconds(2), func():
			if not api.is_dead(spy) and not api.is_dead(prison):
				api.infiltrate(spy, prison))
		api.on_killed(spy, func(_u): api.mark_completed_objective(ussr, ussr_objective))
	api.play_speech_notification(greece, SPY_VOICE)
	if prison_camera == null:
		prison_camera = api.create_actor("camera" if special_cameras else "camera.small",
				greece, truk_path[4] if special_cameras else api.location(prison) + Vector2i(1, 1))


func prison_infiltrated() -> void:
	if api.is_objective_completed(greece, rescue_tanya):
		return
	if not api.is_objective_completed(greece, infiltrate_warfactory):
		api.display_message(api.get_message("skip-heroics"), api.get_message("battlefield-control"))
		api.mark_completed_objective(greece, infiltrate_warfactory)
	if prison_camera == null:
		var prison := api.actor("Prison")
		prison_camera = api.create_actor("camera" if special_cameras else "camera.small",
				greece, truk_path[4] if special_cameras else api.location(prison) + Vector2i(1, 1))
	if special_cameras:
		destroy_reveal(spy_camera_a)
		destroy_reveal(spy_camera_b)
		spy_camera_a = null
		spy_camera_b = null
	api.clear_all_for(spy)
	api.after_delay(api.seconds(2), miss_infiltrated)


func miss_infiltrated() -> void:
	var taunts := api.shuffle(TANYA_VOICES.duplicate())
	var deaths := api.shuffle(DEATH_VOICES.duplicate())
	for i in 4:
		var taunt: String = taunts[i]
		var death := ""
		if i == 1:
			death = deaths[0]
		elif i == 3:
			death = deaths[1]
		api.after_delay((i + 1) * 30, func():
			api.play_speech_notification(greece, taunt)
			if death != "":
				api.play_speech_notification(greece, death))
	api.after_delay(api.seconds(6), free_tanya)


func free_tanya() -> void:
	var prison := api.actor("Prison")
	if api.is_dead(prison):
		return
	tanya = api.create_actor(tanya_type, greece, api.location(prison) + Vector2i(1, 1))
	if tanya != null:

		api.demolish(tanya, prison)
		api.on_killed(tanya, func(_u): api.mark_completed_objective(ussr, ussr_objective))
		if tanya_type == "e7.noautotarget":
			api.after_delay(api.seconds(1), func():
				api.display_message(api.get_message("tanya-rules-of-engagement"), api.get_message("tanya")))
	kill_sams = api.add_primary_objective(greece, "destroy-sam-sites-blocker")
	api.play_speech_notification(greece, "TargetFreed")
	if not special_cameras:
		destroy_reveal(prison_camera)
		prison_camera = null


func sams_destroyed() -> void:
	if kill_sams < 0:
		kill_sams = api.add_primary_objective(greece, "destroy-sam-sites-blocker")
	api.mark_completed_objective(greece, kill_sams)
	var lz := _loc("ExtractionLZ")
	var flare = api.create_actor("flare", greece, lz + Vector2i(0, -1))
	api.after_delay(api.seconds(7), func(): destroy_reveal(flare))
	api.play_speech_notification(greece, "SignalFlare")
	prepare_extraction(lz)


func prepare_extraction(lz: Vector2i) -> void:
	if extraction_ready:
		return
	extraction_ready = true
	api.messages["extract-transport"] = "Escort Tanya to the signal flare."
	api.on_entered_proximity(api.cell_center(lz), 1.5, func(a, id):
		if a == tanya and not api.is_dead(a):
			api.remove_proximity_trigger(id)
			api.destroy(a)
			tanya_rescued())


func tanya_rescued() -> void:
	api.play_speech_notification(greece, "TanyaRescued")
	api.mark_completed_objective(greece, rescue_tanya)
	destroy_reveal(prison_camera)
	prison_camera = null
	api.after_delay(api.seconds(2), send_reinforcements)


func send_reinforcements() -> void:
	greece_reinforcements_arrived = true
	api.set_camera(api.cell_center(_loc("ReinforceCamera")))
	api.give_cash(greece, reinforce_cash)
	for wave in GREECE_REINFORCEMENTS:
		var cell := _loc(wave["entry"])
		for t in wave["types"]:
			api.spawn_near(t, greece, cell)
	api.play_speech_notification(greece, "AlliedReinforcementsArrived")
	activate_ai()


func destroy_reveal(a) -> void:
	if a == null:
		return
	if a is MissionApi.Reveal:
		a.destroy()
	elif not api.is_dead(a):
		api.destroy(a)


func activate_ai() -> void:
	if ai_active:
		return
	ai_active = true
	init_ai_units()
	init_ai_economy()
	init_production_buildings()
	api.after_delay(api.minutes(5), func():
		produce_infantry()
		produce_vehicles())


func init_ai_units() -> void:
	var top_left := _loc("MainBaseTopLeft")
	idling_units = api.where(api.get_ground_attackers(ussr), func(u): return api.location(u).y > top_left.y)
	for b in api.actors_in_world():
		if b.player != ussr or not api.has_property(b, "StartBuildingRepairs"):
			continue
		api.on_damaged(b, func(building):
			if building.player == ussr and api.health(building) < api.max_health(building) * 3.0 / 4.0:
				api.start_building_repairs(building))


func init_ai_economy() -> void:
	api.set_cash(ussr, 6000)
	var harv := api.actor("Harvester")
	if not api.is_dead(harv):
		api.find_resources(harv)
		protect_harvester(harv)


func init_production_buildings() -> void:
	var wf2 := api.actor("Warfactory2")
	if not api.is_dead(wf2):
		api.set_primary(wf2)
		api.on_killed(wf2, func(_u): build_vehicles = false)
	else:
		build_vehicles = false
	var barr2 := api.actor("Barracks2")
	var barr3 := api.actor("Barracks3")
	if not api.is_dead(barr2):
		api.set_primary(barr2)
		api.on_killed(barr2, func(_u):
			if not api.is_dead(barr3):
				api.set_primary(barr3)
			else:
				train_infantry = false)
	elif not api.is_dead(barr3):
		api.set_primary(barr3)
	else:
		train_infantry = false
	if not api.is_dead(barr3):
		api.on_killed(barr3, func(_u):
			if api.is_dead(barr2):
				train_infantry = false)


func setup_attack_group() -> Array:
	var units: Array = []
	for i in ATTACK_GROUP_SIZE + 1:
		if idling_units.is_empty():
			return units
		var number := random_integer(1, idling_units.size()) - 1
		if number < idling_units.size() and not api.is_dead(idling_units[number]):
			units.append(idling_units[number])
			idling_units.remove_at(number)
	return units


func send_attack() -> void:
	if attacking:
		return
	attacking = true
	hold_production = true
	for unit in setup_attack_group():
		api.hunt(unit)
	api.after_delay(api.minutes(1), func(): attacking = false)
	api.after_delay(api.minutes(2), func(): hold_production = false)


func protect_harvester(unit) -> void:
	if unit == null:
		return
	api.on_damaged(unit, func(self_actor):
		if attack_ongoing:
			return
		attack_ongoing = true
		var guards := setup_attack_group()
		if guards.is_empty():
			attack_ongoing = false
			return
		for u in guards:
			if not api.is_dead(self_actor):
				api.attack_move(u, api.location(self_actor))
			api.hunt(u)
		api.on_all_removed_from_world(guards, func(): attack_ongoing = false))
	api.on_killed(unit, func(_u): harvester_killed = true)


func produce_infantry() -> void:
	if not train_infantry:
		return
	if hold_production:
		api.after_delay(api.minutes(1), produce_infantry)
		return
	var delay := random_integer(api.seconds(3), api.seconds(9))
	api.build(ussr, [random(SOVIET_INFANTRY_TYPES)], func(units: Array):
		if not units.is_empty():
			idling_units.append(units[0])
		api.after_delay(delay, produce_infantry)
		if idling_units.size() >= ATTACK_GROUP_SIZE * 2.5:
			send_attack())


func produce_vehicles() -> void:
	if not build_vehicles:
		return
	if hold_production:
		api.after_delay(api.minutes(1), produce_vehicles)
		return
	var delay := random_integer(api.seconds(5), api.seconds(9))
	if harvester_killed:
		harvester_killed = false
		api.build(ussr, ["harv"], func(harv: Array):
			if not harv.is_empty():
				api.find_resources(harv[0])
				protect_harvester(harv[0])
			api.after_delay(delay, produce_vehicles))
		return
	api.build(ussr, [random(SOVIET_VEHICLE_TYPES)], func(units: Array):
		if not units.is_empty():
			idling_units.append(units[0])
		api.after_delay(delay, produce_vehicles)
		if idling_units.size() >= ATTACK_GROUP_SIZE * 2.5:
			send_attack())


func tick() -> void:
	if force_step > 0:
		tick_test_force()
	if follow_truk and truk_reveal != null:
		var truk := api.actor("Truk")
		if not api.is_dead(truk):
			api.set_camera(truk.pos)
			if truk_reveal is MissionApi.Reveal:
				truk_reveal.teleport(api.location(truk))
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, kill_all)
	if greece_reinforcements_arrived and api.has_no_required_units(greece):
		api.mark_completed_objective(ussr, ussr_objective)

	var cap := api.resource_capacity(ussr)
	if cap > 0 and api.resources(ussr) >= cap * 3 / 4:
		api.give_cash(ussr, api.resources(ussr) - cap / 4)
		api.set_resources(ussr, cap / 4)


func test_force() -> void:
	force_step = 1
	var wf := api.actor("Warfactory")
	if spy == null or api.is_dead(spy) or api.is_dead(wf):
		force_step = 3
		return
	api.teleport(spy, api.location(wf) + Vector2i(-1, 3))
	api.infiltrate(spy, wf)


var force_step := 0
var force_wait := 0


func tick_test_force() -> void:
	if force_wait > 0:
		force_wait -= 1
		return
	match force_step:
		1:

			if tanya != null:
				force_step = 2
				force_wait = api.seconds(3)
		2:
			for s in sam_sites:
				if not api.is_dead(s):
					api.kill(s)
			force_step = 3
			force_wait = api.seconds(2)
		3:
			if tanya != null and not api.is_dead(tanya):
				api.teleport(tanya, _loc("ExtractionLZ"))
			force_step = 4
			force_wait = api.seconds(2)
		4:
			for u in api.get_actors(ussr):
				api.kill(u)
			force_step = 5
