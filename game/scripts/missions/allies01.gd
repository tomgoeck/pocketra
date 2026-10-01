

extends MissionScript

var greece := 0
var england := 1
var ussr := 2

var insertion_path: Array = []
var jeep_reinforcements := ["jeep", "jeep"]
var tanya_reinforcements := ["e7.noautotarget"]
var opening_attack: Array = []
var responders: Array = []
var lab_guards: Array = []
var soviet_army: Array = []
var einstein = null
var collateral_damage := false
var extraction_ready := false
var einstein_extracted := false

var find_einstein := -1
var tanya_survive := -1
var einstein_survive := -1
var civil_protection := -1
var extract_objective := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	greece = api.player("Greece")
	england = api.player("England")
	ussr = api.player("USSR")
	insertion_path = [_loc("InsertionEntry"), _loc("InsertionLZ")]
	opening_attack = api.actors(["Patrol1", "Patrol2", "Patrol3", "Patrol4"])
	responders = api.actors(["Response1", "Response2", "Response3", "Response4", "Response5"])
	lab_guards = api.actors(["LabGuard1", "LabGuard2", "LabGuard3"])

	init_objectives(greece)
	find_einstein = api.add_primary_objective(greece, "find-einstein")
	tanya_survive = api.add_primary_objective(greece, "tanya-survive")
	einstein_survive = api.add_primary_objective(greece, "einstein-survive")
	civil_protection = api.add_secondary_objective(greece, "protect-civilians")

	run_initial_activities()

	api.on_killed(api.actor("Lab"), func(_u): lab_destroyed())
	api.on_killed(api.actor("OilPump"), func(_u): api.after_delay(api.seconds(5), send_jeeps))

	soviet_army = api.get_ground_attackers(ussr)
	api.on_all_killed(lab_guards, lab_guards_killed)

	collateral_damage = false
	var civilians := api.actors(["Civilian1", "Civilian2"])
	api.on_any_killed(civilians, func(_u): civilians_killed())
	api.on_killed(api.actor("Civilian1"), func(_u): lost_mate())

	set_unit_stances()
	api.after_delay(api.seconds(5), func(): api.create_actor("camera", greece, _loc("BaseCameraPoint")))
	api.camera_target = api.cell_center(_loc("InsertionLZ"))


func send_insertion_helicopter() -> void:
	api.reinforce(greece, tanya_reinforcements, insertion_path, 0, func(tanya):
		api.on_killed(tanya, func(_u): tanya_killed_in_action()))
	api.after_delay(api.seconds(4), func():
		api.display_message(api.get_message("tanya-rules-of-engagement"), api.get_message("tanya")))


func send_jeeps() -> void:
	api.reinforce(greece, jeep_reinforcements, insertion_path, api.seconds(2))
	api.play_speech_notification(greece, "ReinforcementsArrived")


func run_initial_activities() -> void:
	send_insertion_helicopter()
	for a in opening_attack:
		api.hunt(a)
	api.on_killed(api.actor("Patrol3"), func(_u):
		var civ := api.actor("Civilian1")
		if not api.is_dead(civ):
			api.move(civ, _loc("CivMove")))
	api.on_killed(api.actor("BarrelPower"), func(_u):
		var civ := api.actor("Civilian2")
		if not api.is_dead(civ):
			api.move(civ, _loc("CivMove"))
		for r in responders:
			if not api.is_dead(r):
				api.hunt(r))


func lab_guards_killed() -> void:
	create_einstein()
	api.after_delay(api.seconds(2), func():
		api.create_actor("flare", england, _loc("ExtractionFlarePoint"))
		api.play_speech_notification(greece, "SignalFlareNorth")
		prepare_extraction())
	api.after_delay(api.seconds(10), func():
		api.play_speech_notification(greece, "AlliedReinforcementsArrived")
		api.create_actor("camera", greece, _loc("CruiserCameraPoint")))
	api.after_delay(api.seconds(12), func():
		for i in range(0, 3):
			api.after_delay(api.seconds(i), func(): api.play_sound_notification(greece, "AlertBuzzer"))
		for a in soviet_army:
			if not api.is_dead(a) and api.has_property(a, "Hunt"):
				api.hunt(a))


func prepare_extraction() -> void:
	if extraction_ready:
		return
	extraction_ready = true
	var lz := _loc("ExtractionLZ")
	api.on_entered_proximity(api.cell_center(lz), 1.5, func(a, id):
		if a == einstein and not api.is_dead(a):
			api.remove_proximity_trigger(id)
			einstein_extracted = true
			api.kill(a)
			einstein_rescued())


func einstein_rescued() -> void:
	api.play_speech_notification(greece, "TargetRescued")
	api.after_delay(api.seconds(1), func():
		api.mark_completed_objective(greece, extract_objective)
		api.mark_completed_objective(greece, einstein_survive)
		if not api.is_objective_failed(greece, tanya_survive):
			api.mark_completed_objective(greece, tanya_survive)
		if not collateral_damage:
			api.mark_completed_objective(greece, civil_protection))


func lab_destroyed() -> void:
	if einstein == null:
		rescue_failed()


func rescue_failed() -> void:
	api.play_speech_notification(greece, "ObjectiveNotMet")
	api.mark_failed_objective(greece, einstein_survive)


func tanya_killed_in_action() -> void:
	api.play_speech_notification(greece, "ObjectiveNotMet")
	api.mark_failed_objective(greece, tanya_survive)


func civilians_killed() -> void:
	api.mark_failed_objective(greece, civil_protection)
	api.play_speech_notification(greece, "ObjectiveNotMet")
	collateral_damage = true


func lost_mate() -> void:
	var civ := api.actor("Civilian2")
	if not api.is_dead(civ):
		api.panic(civ)


func create_einstein() -> void:
	api.mark_completed_objective(greece, find_einstein)
	api.play_speech_notification(greece, "ObjectiveMet")
	einstein = api.create_actor("einstein", greece, _loc("EinsteinSpawnPoint"))
	if einstein != null:
		api.scatter(einstein)
		api.on_killed(einstein, func(_u):
			if not einstein_extracted:
				rescue_failed())

	api.messages["extract-einstein-helicopter"] = "Escort Einstein to the signal flare."
	extract_objective = api.add_primary_objective(greece, "extract-einstein-helicopter")
	api.after_delay(api.seconds(1), func(): api.play_speech_notification(greece, "TargetFreed"))


func test_force() -> void:
	for u in api.get_actors(ussr):
		if u.map_id != "Lab":
			api.kill(u)
	api.after_delay(api.seconds(3), func():
		if einstein != null and not api.is_dead(einstein):
			api.move(einstein, _loc("ExtractionLZ")))


func set_unit_stances() -> void:
	for a in api.named_actors():
		if a.player == greece:
			api.set_stance(a, "Defend")
