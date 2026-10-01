

extends MissionScript

var greece := 0
var ussr := 1
var badguy := 2


const TANYA_TYPES := {"easy": "e7", "normal": "e7.noautotarget", "hard": "e7.noautotarget"}
const REINFORCE_CASH := {"easy": 5000, "normal": 3500, "hard": 2250}
const SPECIAL_CAMERAS := {"easy": true, "normal": true, "hard": false}

const PRODUCTION_INTERVAL := {"easy": 625, "normal": 375, "hard": 125}


const GREECE_REINFORCEMENTS_1 := [
	{"types": ["2tnk", "2tnk", "2tnk", "2tnk", "2tnk"], "entry": "LSTLanding1"},
	{"types": ["e3", "e3", "e3", "e3", "e1"], "entry": "LSTLanding2"},
]
const GREECE_REINFORCEMENTS_2 := [
	{"types": ["arty", "arty", "jeep", "jeep"], "entry": "LSTLanding1"},
	{"types": ["e1", "e1", "e6", "e6", "e6"], "entry": "LSTLanding2"},
]

const TANYA_VOICES := ["tuffguy", "bombit", "laugh", "keepem"]
const DEATH_VOICES := ["death1", "death2", "death3"]
const SPY_VOICE := "sking"


const SOVIET_INFANTRY := ["e1", "e1", "e2"]
const SOVIET_VEHICLES := ["3tnk", "3tnk", "apc"]
const ATTACK_GROUP_SIZE := 10

var tanya_type := "e7.noautotarget"
var reinforce_cash := 3500
var special_cameras := true
var production_interval := 375

var spy = null
var tanya = null
var truk_path: Array = []
var sam_sites: Array = []
var dog_patrol: Array = []
var rifle_patrol: Array = []
var base_patrol: Array = []

var spy_camera_a = null
var spy_camera_b = null
var spy_camera_c = null
var spy_camera_hard = null
var prison_camera = null
var truk_reveal = null
var follow_truk := false
var greece_reinforcements_arrived := false
var attack_group: Array = []
var ai_active := false

var ussr_obj := -1
var main_obj := -1
var kill_all := -1
var inf_warfactory := -1
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
	badguy = api.player("BadGuy")
	tanya_type = TANYA_TYPES.get(difficulty, "e7.noautotarget")
	reinforce_cash = REINFORCE_CASH.get(difficulty, 3500)
	special_cameras = SPECIAL_CAMERAS.get(difficulty, true)
	production_interval = PRODUCTION_INTERVAL.get(difficulty, 375)

	truk_path = _locs(["TrukWaypoint1", "TrukWaypoint2", "TrukWaypoint3", "TrukWaypoint4",
			"TrukWaypoint5", "TrukWaypoint6", "TrukWaypoint7", "TrukWaypoint8", "TrukWaypoint9",
			"TrukWaypoint10"])

	sam_sites = api.actors(["Sam1", "Sam2", "Sam3", "Sam4", "Sam5", "Sam6"])
	dog_patrol = api.actors(["Dog1", "Dog2"])
	rifle_patrol = api.actors(["RiflePatrol1", "RiflePatrol2", "RiflePatrol3", "RiflePatrol4",
			"RiflePatrol5"])
	base_patrol = api.actors(["BasePatrol1", "BasePatrol2", "BasePatrol3"])


	api.messages["destroy-sam-sites-blocker-all"] = "Destroy all six SAM Sites blocking\nour reinforcements' helicopter from landing."

	init_objectives(greece)
	ussr_obj = api.add_primary_objective(ussr, "")
	main_obj = api.add_primary_objective(greece, "rescue-tanya")
	kill_all = api.add_primary_objective(greece, "eliminate-soviet-units")
	inf_warfactory = api.add_secondary_objective(greece, "infiltrate-warfactory")

	init_triggers()
	send_spy()
	api.after_delay(api.seconds(3), activate_patrols)


func send_spy() -> void:
	api.set_camera(api.cell_center(_loc("SpyEntry")))
	spy = api.spawn_near("spy", greece, _loc("SpyLoadout"))
	if spy != null:
		api.on_killed(spy, func(_u): api.mark_completed_objective(ussr, ussr_obj))
	if special_cameras:
		spy_camera_a = api.create_actor("camera", greece, _loc("SpyCamera1"))
		spy_camera_b = api.create_actor("camera", greece, _loc("SpyCamera2"))
		spy_camera_c = api.create_actor("camera", greece, _loc("SpyCamera3"))
	else:
		spy_camera_hard = api.create_actor("camera.small", greece, _loc("RiflePath1") + Vector2i(0, 3))
	api.after_delay(api.seconds(3), func():
		api.display_message(api.get_message("disguise-spy"), api.get_message("spy")))


func activate_patrols() -> void:
	api.after_delay(api.seconds(3), func():
		group_patrol(dog_patrol, _locs(["DogPatrolRally1", "SpyCamera2", "DogPatrolRally3"]), api.seconds(6))
		group_patrol(rifle_patrol, _locs(["RiflePath1", "RiflePath2", "RiflePath3"]), api.seconds(7))
		group_patrol(base_patrol, _locs(["BasePatrolPath1", "BasePatrolPath2", "BasePatrolPath3"]), api.seconds(6)))


func group_patrol(units: Array, waypoints: Array, delay: int) -> void:
	for u in units:
		api.patrol(u, waypoints, true, delay)


func init_triggers() -> void:
	var warfactory := api.actor("Warfactory")
	var truk := api.actor("Truk")
	api.on_infiltrated(warfactory, func(_b, _spy):
		if api.is_objective_completed(greece, inf_warfactory):
			return
		if api.is_dead(truk):
			if not api.is_objective_completed(greece, main_obj):
				api.mark_completed_objective(ussr, ussr_obj)
			return
		api.clear_all_for(spy)
		api.mark_completed_objective(greece, inf_warfactory)
		warfactory_infiltrated())

	api.on_killed(truk, func(_u):
		if not api.is_objective_completed(greece, inf_warfactory):
			api.mark_failed_objective(greece, inf_warfactory)
		elif follow_truk:
			api.mark_completed_objective(ussr, ussr_obj))

	api.on_infiltrated(api.actor("Prison"), func(_b, _spy): prison_infiltrated())


	api.on_entered_footprint([_loc("SpyJump")], func(a, id):
		if a == truk:
			api.remove_footprint_trigger(id)
			spawn_prison_spy())

	api.on_entered_footprint([_loc("TrukWaypoint10")], func(a, id):
		if a == truk:
			api.remove_footprint_trigger(id)
			api.stop(a)
			api.kill(a)
			var barrel := api.actor("ExplosiveBarrel")
			if not api.is_dead(barrel):
				api.kill(barrel))

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
			destroy_reveal(spy_camera_a); spy_camera_a = null
			destroy_reveal(spy_camera_b); spy_camera_b = null
			destroy_reveal(spy_camera_c); spy_camera_c = null)
	else:
		destroy_reveal(spy_camera_hard)
		spy_camera_hard = null


func spawn_prison_spy() -> void:
	follow_truk = false
	var prison := api.actor("Prison")
	spy = api.spawn_near("spy", greece, _loc("SpyJump"))
	if spy != null:
		api.disguise_as_type(spy, "e1", ussr)
		api.move(spy, _loc("SpyWaypoint"))
		api.after_delay(api.seconds(2), func():
			if not api.is_dead(spy) and not api.is_dead(prison):
				api.infiltrate(spy, prison))
		api.on_killed(spy, func(_u): api.mark_completed_objective(ussr, ussr_obj))
	api.play_speech_notification(greece, SPY_VOICE)
	if prison_camera == null:
		prison_camera = api.create_actor("camera" if special_cameras else "camera.small",
				greece, _loc("SpyJump") if special_cameras else api.location(prison) + Vector2i(1, 1))


func prison_infiltrated() -> void:
	if api.is_objective_completed(greece, main_obj):
		return
	if not api.is_objective_completed(greece, inf_warfactory):
		api.display_message(api.get_message("skip-heroics"), api.get_message("battlefield-control"))
		api.mark_completed_objective(greece, inf_warfactory)
	if prison_camera == null:
		var prison := api.actor("Prison")
		prison_camera = api.create_actor("camera" if special_cameras else "camera.small",
				greece, _loc("SpyJump") if special_cameras else api.location(prison) + Vector2i(1, 1))
	if special_cameras:

		destroy_reveal(spy_camera_a); spy_camera_a = null
		destroy_reveal(spy_camera_b); spy_camera_b = null
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
		api.on_killed(tanya, func(_u): api.mark_completed_objective(ussr, ussr_obj))
		if tanya_type == "e7.noautotarget":
			api.after_delay(api.seconds(1), func():
				api.display_message(api.get_message("tanya-rules-of-engagement"), api.get_message("tanya")))
	kill_sams = api.add_primary_objective(greece, "destroy-sam-sites-blocker-all")
	api.play_speech_notification(greece, "TargetFreed")
	if not special_cameras:
		destroy_reveal(prison_camera)
		prison_camera = null


func sams_destroyed() -> void:
	if kill_sams < 0:
		kill_sams = api.add_primary_objective(greece, "destroy-sam-sites-blocker-all")
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
	api.mark_completed_objective(greece, main_obj)
	destroy_reveal(prison_camera)
	prison_camera = null
	api.after_delay(api.seconds(2), send_reinforcements)


func send_reinforcements() -> void:
	greece_reinforcements_arrived = true
	api.set_camera(api.cell_center(_loc("SpyLoadout")))
	api.give_cash(greece, reinforce_cash)
	api.play_speech_notification(greece, "AlliedReinforcementsArrived")
	spawn_wave(GREECE_REINFORCEMENTS_1)
	api.after_delay(api.seconds(10), func():
		api.play_speech_notification(greece, "AlliedReinforcementsArrived")
		spawn_wave(GREECE_REINFORCEMENTS_2))
	activate_ai()


func spawn_wave(waves: Array) -> void:
	for wave in waves:
		var cell := _loc(wave["entry"])
		for t in wave["types"]:
			api.spawn_near(t, greece, cell)


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
	for b in api.actors_in_world():
		if b.player != ussr or not api.has_property(b, "StartBuildingRepairs"):
			continue
		api.on_damaged(b, func(building):
			if building.player == ussr and api.health(building) < api.max_health(building) * 3.0 / 4.0:
				api.start_building_repairs(building))
	produce_infantry()
	api.after_delay(api.minutes(2), produce_vehicles)
	var production := api.where(api.actors(["Conyard", "USSRBarracks", "USSRWarFactory"]), func(u): return not api.is_dead(u))
	if not production.is_empty():
		api.on_all_killed(production, func():
			for u in api.get_ground_attackers(ussr):
				api.hunt(u))


func send_attack_group() -> void:
	if attack_group.size() < ATTACK_GROUP_SIZE:
		return
	for u in attack_group:
		if not api.is_dead(u):
			api.hunt(u)
	attack_group = []


func produce_infantry() -> void:
	var barr := api.actor("USSRBarracks")
	if api.is_dead(barr) or barr.player != ussr:
		return
	api.build(ussr, [random(SOVIET_INFANTRY)], func(units: Array):
		if not units.is_empty():
			attack_group.append(units[0])
		send_attack_group()
		api.after_delay(production_interval, produce_infantry))


func produce_vehicles() -> void:
	var wf := api.actor("USSRWarFactory")
	if api.is_dead(wf) or wf.player != ussr:
		return
	api.build(ussr, [random(SOVIET_VEHICLES)], func(units: Array):
		if not units.is_empty():
			attack_group.append(units[0])
		send_attack_group()
		api.after_delay(production_interval, produce_vehicles))


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
		api.mark_completed_objective(ussr, ussr_obj)

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
			for p in [ussr, badguy]:
				for u in api.get_actors(p):
					api.kill(u)
			force_step = 5
