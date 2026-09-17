

extends MissionScript

var ussr := 0
var greece := 1

const ENEMY_REINFORCEMENTS := {
	"easy": [["e1", "e1", "e3"], ["e1", "e3", "jeep"], ["e1", "jeep", "1tnk"]],
	"normal": [["e1", "e1", "e3", "e3"], ["e1", "e3", "jeep", "jeep"], ["e1", "jeep", "1tnk", "2tnk"]],
	"hard": [["e1", "e1", "e3", "e3", "e1"], ["e1", "e3", "jeep", "jeep", "1tnk"],
		["e1", "jeep", "1tnk", "2tnk", "arty"]],
}
const ENEMY_ATTACK_DELAY := {"easy": 7500, "normal": 4000, "hard": 2250}
const ALLIED_INFANTRY_TYPES := ["e1", "e1", "e3"]
const ALLIED_ARMOR_TYPES := ["jeep", "jeep", "1tnk", "1tnk", "2tnk", "2tnk", "arty"]

var enemy_paths: Array = []
var attack_paths: Array = []
var goal_cells: Array = []
var base_blueprints: Array = []
var inf_attack: Array = []
var armor_attack: Array = []
var wave := 0
var mcv_deployed := false
var goal_triggered := false

var kill_trucks := -1
var escort_convoy := -1
var disrupt_dome := -1
var save_all_trucks := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func _line(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(Vector2i(c[0], c[1]))
	return out


func world_loaded() -> void:
	ussr = api.player("USSR")
	greece = api.player("Greece")
	enemy_paths = [[_loc("EnemyEntry1"), _loc("EnemyRally1")], [_loc("EnemyEntry2"), _loc("EnemyRally2")]]
	attack_paths = [[_loc("AttackWaypoint1")], [_loc("AttackWaypoint2")]]
	goal_cells = _line([[83, 7], [83, 8], [83, 9], [83, 10], [84, 10], [84, 11], [84, 12], [85, 12],
		[86, 12], [87, 12], [87, 13], [88, 13], [89, 13], [90, 13], [90, 14], [90, 15], [91, 15],
		[92, 15], [93, 15], [94, 15]])
	base_blueprints = [
		{"type": "apwr", "name": "Apwr1", "cost": 500, "shape": Vector2i(3, 3), "location": Vector2i(18, 12)},
		{"type": "apwr", "name": "Apwr2", "cost": 500, "shape": Vector2i(3, 3), "location": Vector2i(27, 6)},
		{"type": "tent", "name": "Tent", "cost": 400, "shape": Vector2i(2, 3), "location": Vector2i(29, 16), "on_built": "infantry"},
		{"type": "proc", "name": "Proc", "cost": 1400, "shape": Vector2i(3, 4), "location": Vector2i(24, 9)},
		{"type": "weap", "name": "Weap", "cost": 2000, "shape": Vector2i(3, 3), "location": Vector2i(22, 15), "on_built": "armor"},
		{"type": "powr", "name": "Powr1", "cost": 300, "shape": Vector2i(2, 3), "location": Vector2i(20, 2)},
		{"type": "powr", "name": "Powr2", "cost": 300, "shape": Vector2i(2, 3), "location": Vector2i(25, 2)},
		{"type": "gun", "name": "Gun4", "cost": 800, "shape": Vector2i(1, 1), "location": Vector2i(28, 23)},
		{"type": "hbox", "name": "Hbox2", "cost": 600, "shape": Vector2i(1, 1), "location": Vector2i(29, 23)},
		{"type": "gun", "name": "Gun3", "cost": 800, "shape": Vector2i(1, 1), "location": Vector2i(20, 23)},
		{"type": "hbox", "name": "Hbox1", "cost": 600, "shape": Vector2i(1, 1), "location": Vector2i(19, 23)},
		{"type": "gap", "name": "Gap", "cost": 800, "shape": Vector2i(1, 1), "location": Vector2i(24, 22)},
	]
	for b in base_blueprints:
		b["actor"] = api.actor(b["name"])

	prepare_reveals()
	prepare_objectives()
	api.camera_target = api.cell_center(_loc("CameraStart"))
	api.find_resources(api.actor("Harvester"))
	begin_base_maintenance()


	api.on_removed_from_world(api.actor("Mcv"), func(_u):
		if mcv_deployed:
			return
		mcv_deployed = true
		build_base()
		send_reinforcements()
		api.after_delay(api.minutes(1), func(): produce_infantry(_blueprint("Tent")))
		api.after_delay(api.minutes(2), func(): produce_armor(_blueprint("Weap")))
		api.after_delay(api.minutes(2), func():
			for n in ["BaseAttacker1", "BaseAttacker2"]:
				api.hunt(api.actor(n))))


	if difficulty != "easy":
		prepare_response_cruiser()
		api.after_delay(1, func(): prepare_bridge_breakers())
	if difficulty == "hard":
		build_navy_patrol()
	prepare_trucks()
	begin_intro()
	prepare_idle_guards()


func prepare_response_cruiser() -> void:
	var ordered := [false]
	for n in ["Apwr1", "Apwr2", "Powr1", "Powr2", "Weap", "Tent"]:
		var b = api.actor(n)
		if b == null:
			continue
		api.on_damaged(b, func(_u):
			if ordered[0] or api.is_objective_completed(ussr, disrupt_dome):
				return
			ordered[0] = true
			order_response_cruiser())


func order_response_cruiser() -> void:
	var cruiser = api.actor("ResponseCruiser")
	if api.is_dead(cruiser):
		return
	api.on_idle(cruiser, func(u): api.attack_move(u, _loc("waypoint0")))
	api.on_damaged(cruiser, func(u):
		var foe = api.attacker(u)
		if foe == null or api.is_dead(foe):
			return
		api.attack(u, foe)
		api.scatter(u))


func prepare_bridge_breakers() -> void:
	var target = null
	for u in api.actors_in_circle(api.cell_center(_loc("waypoint78")), 1.5):
		if u.type == "br3":
			target = u
			break
	if target == null:
		return
	var sent := [false]
	api.after_delay(api.seconds(30), func():
		sent[0] = true
		order_bridge_breakers(target, false))
	var entry := _line([[75, 30], [76, 30], [77, 30]])
	api.on_entered_footprint(entry, func(a, id):
		if a.player != ussr:
			return
		api.remove_footprint_trigger(id)
		if not sent[0]:
			sent[0] = true
			order_bridge_breakers(target, true))


func order_bridge_breakers(target, reveal: bool) -> void:
	if api.is_dead(target):
		return
	for n in ["BridgeBreaker1", "BridgeBreaker2"]:
		var b = api.actor(n)
		if api.is_dead(b):
			continue
		api.stop(b)
		api.attack(b, target, false, true)
	if not reveal:
		return
	var cam = api.create_actor("camera", ussr, api.location(target))
	api.on_killed(target, func(_u):
		api.after_delay(api.seconds(2), func():
			if cam != null:
				cam.destroy()))


func build_navy_patrol() -> void:
	var path := [_loc("NavyPatrol1"), _loc("NavyPatrol2"), _loc("NavyPatrol3"), _loc("NavyPatrol4")]
	api.build(greece, ["dd", "dd"], func(units: Array):
		for u in units:
			api.patrol(u, path, true, 100)
		api.on_all_killed(units, func():
			if not api.has_prerequisites(greece, ["syrd", "dome"]):
				return
			build_navy_patrol()))


func _blueprint(name: String) -> Dictionary:
	for b in base_blueprints:
		if b["name"] == name:
			return b
	return {}


func prepare_reveals() -> void:
	var barrier_cells := _line([[65, 39], [65, 40], [66, 40], [66, 41], [67, 41], [67, 42],
		[68, 42], [68, 43], [68, 44]])
	var base_cells := _line([[53, 42], [54, 42], [54, 41], [55, 41], [56, 41], [56, 40], [57, 40],
		[57, 39], [58, 39], [59, 39], [59, 38], [60, 38], [61, 38]])
	var barrier_done := [false]
	var base_done := [false]

	api.on_entered_footprint(barrier_cells, func(a, id):
		if barrier_done[0] or a.player != ussr:
			return
		barrier_done[0] = true
		api.remove_footprint_trigger(id)
		var cam = api.create_actor("camera", ussr, _loc("CameraBarrier"))
		api.after_delay(api.seconds(12), func():
			if cam != null:
				cam.destroy()))

	api.on_entered_footprint(base_cells, func(a, id):
		if base_done[0] or a.player != ussr:
			return
		base_done[0] = true
		api.remove_footprint_trigger(id)
		var cams: Array = []
		for n in ["CameraBase1", "CameraBase2", "CameraBase3", "CameraBase4"]:
			var c = api.create_actor("camera", ussr, _loc(n))
			if c != null:
				cams.append(c)
		api.after_delay(api.minutes(1), func():
			for c in cams:
				c.destroy()))


func prepare_objectives() -> void:
	init_objectives(ussr)
	kill_trucks = api.add_primary_objective(greece, "")
	escort_convoy = api.add_primary_objective(ussr, "escort-convoy")
	disrupt_dome = api.add_secondary_objective(ussr, "destroy-capture-radar-dome-reinforcements")
	save_all_trucks = api.add_secondary_objective(ussr, "keep-trucks-alive")

	api.on_killed_or_captured(api.actor("Dome"), func():
		api.after_delay(api.seconds(2), func():
			api.mark_completed_objective(ussr, disrupt_dome)
			api.play_speech_notification(ussr, "ObjectiveMet")))


func prepare_trucks() -> void:
	var trucks := api.actors(["Truck1", "Truck2"])
	api.on_entered_footprint(goal_cells, func(a):
		if not goal_triggered and a.player == ussr and a.type == "truk":
			goal_triggered = true
			api.mark_completed_objective(ussr, escort_convoy)
			api.mark_completed_objective(ussr, save_all_trucks))
	api.on_all_killed(trucks, func(): api.mark_completed_objective(greece, kill_trucks))
	api.on_any_killed(trucks, func(_u): api.mark_failed_objective(ussr, save_all_trucks))


func begin_intro() -> void:
	api.move(api.actor("Mcv"), _loc("McvWaypoint"))
	for n in ["IntroEnemy1", "IntroEnemy2", "IntroEnemy3"]:
		api.hunt(api.actor(n))
	api.reinforce_with_transport(ussr, "apc", ["e6", "e6", "e6", "e6", "e6"],
			[_loc("McvWaypoint"), _loc("APCWaypoint1")])
	api.reinforce_with_transport(ussr, "apc", ["e4", "e4", "e2", "e2", "e2"],
			[_loc("McvWaypoint"), _loc("APCWaypoint2")])


func prepare_idle_guards() -> void:
	for unit in api.get_ground_attackers(greece):

		if unit.type == "ca" or unit.type == "arty":
			continue
		var fired := [false]
		api.on_damaged(unit, func(u):
			if fired[0]:
				return
			fired[0] = true
			api.hunt(u))


func send_reinforcements() -> void:
	api.after_delay(ENEMY_ATTACK_DELAY.get(difficulty, 4000), func():
		var dome := api.actor("Dome")
		if api.is_dead(dome) or dome.player != greece:
			return
		wave += 1
		if wave > 3:
			wave = 1
		var types: Array = ENEMY_REINFORCEMENTS.get(difficulty, ENEMY_REINFORCEMENTS["normal"])[wave - 1]
		var path: Array = enemy_paths[0] if wave == 1 else enemy_paths[1]
		var transport := "tran" if wave == 1 else "lst"
		api.reinforce_with_transport(greece, transport, types, path, [path[0]],
				Callable(), Callable(), 3, func(u): api.hunt(u))
		send_reinforcements())


func produce_infantry(barracks: Dictionary) -> void:
	if barracks.is_empty() or api.is_dead(barracks.get("actor")) or barracks["actor"].player != greece:
		return
	if greece_money() <= 299 and harvester_missing():
		return
	var delay := random_integer(api.seconds(3), api.seconds(9))
	var path: Array = random(attack_paths)
	api.build(greece, [random(ALLIED_INFANTRY_TYPES)], func(units: Array):
		if not units.is_empty():
			inf_attack.append(units[0])
		if inf_attack.size() >= 10:
			send_units(inf_attack, path)
			inf_attack = []
			api.after_delay(api.minutes(2), func(): produce_infantry(barracks))
		else:
			api.after_delay(delay, func(): produce_infantry(barracks)))


func produce_armor(factory: Dictionary) -> void:
	var delay := random_integer(api.seconds(12), api.seconds(17))
	if factory.is_empty() or api.is_dead(factory.get("actor")) or factory["actor"].player != greece:
		return
	if harvester_missing():
		produce_harvester(factory, delay)
		return
	var path: Array = random(attack_paths)
	api.build(greece, [random(ALLIED_ARMOR_TYPES)], func(units: Array):
		if not units.is_empty():
			armor_attack.append(units[0])
		if armor_attack.size() >= 6:
			send_units(armor_attack, path)
			armor_attack = []
			api.after_delay(api.minutes(3), func(): produce_armor(factory))
		else:
			api.after_delay(delay, func(): produce_armor(factory)))


func produce_harvester(factory: Dictionary, delay: int) -> void:
	if greece_money() < api.type_cost("harv"):
		return
	api.build(greece, ["harv"], func(_units: Array):
		api.after_delay(delay, func(): produce_armor(factory)))


func send_units(units: Array, path: Array) -> void:
	for unit in units:
		if not api.is_dead(unit):
			api.patrol(unit, path, false)
			api.hunt(unit)


func harvester_missing() -> bool:
	return api.get_actors_by_type(greece, "harv").is_empty()


func greece_money() -> int:
	return api.cash(greece) + api.resources(greece)


func build_base() -> void:
	for b in base_blueprints:
		if api.is_dead(b.get("actor")):
			b["actor"] = null
			build_blueprint(b)
			return
	api.after_delay(api.seconds(10), build_base)


func build_blueprint(blueprint: Dictionary) -> void:
	api.after_delay(api.build_time(blueprint["type"]), func():
		var cyard := api.actor("CYard")
		if api.is_dead(cyard) or cyard.player != greece:
			return
		if greece_money() <= 299 and harvester_missing():
			return
		if build_area_blocked(blueprint):
			api.after_delay(api.seconds(5), func(): build_blueprint(blueprint))
			return
		var a = api.create_actor(blueprint["type"], greece, blueprint["location"])
		on_blueprint_built(a, blueprint)
		api.after_delay(api.seconds(10), build_base))


func on_blueprint_built(a, blueprint: Dictionary) -> void:
	api.set_cash(greece, api.cash(greece) - int(blueprint["cost"]))
	blueprint["actor"] = a
	maintain_building(a, blueprint, 0.75)
	if a != null and blueprint.has("on_built"):
		api.after_delay(1, func():
			if blueprint["on_built"] == "infantry":
				produce_infantry(blueprint)
			else:
				produce_armor(blueprint))


func build_area_blocked(blueprint: Dictionary) -> bool:
	var tl: Vector2i = blueprint["location"]
	var shape: Vector2i = blueprint["shape"]
	var blockers: Array = []
	for a in api.actors_in_box(tl, tl + shape - Vector2i(1, 1)):
		if api.has_property(a, "StartBuildingRepairs") or api.max_health(a) <= 0:
			continue
		if a.type == "silo" and a.player == greece:
			continue
		blockers.append(a)
	if blockers.is_empty():
		return false
	for a in blockers:
		if api.is_idle(a) and a.player == greece and api.has_property(a, "Scatter"):
			api.scatter(a)
	return true


func begin_base_maintenance() -> void:
	for b in base_blueprints:
		maintain_building(b.get("actor"), b, 0.0)
	for a in api.get_actors(greece):
		if api.has_property(a, "StartBuildingRepairs"):
			maintain_building(a, {}, 0.75)


func maintain_building(a, blueprint: Dictionary, repair_threshold: float) -> void:
	if a == null:
		return
	if not blueprint.is_empty():
		api.on_killed(a, func(_u): blueprint["actor"] = null)
		api.on_sold(a, func(_u): blueprint["actor"] = null)
	if repair_threshold > 0.0:
		var original: int = a.player
		api.on_damaged(a, func(b):
			if b.player != original or b.hp > repair_threshold:
				return
			api.start_building_repairs(b))


func test_force() -> void:
	var truck := api.actor("Truck1")
	if api.is_dead(truck):
		truck = api.actor("Truck2")
	if not api.is_dead(truck):
		api.teleport(truck, goal_cells[0])


func tick() -> void:
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, kill_trucks)
	var cap := api.resource_capacity(greece)
	if cap > 0 and api.resources(greece) >= cap * 0.75:
		api.give_cash(greece, api.resources(greece) - int(cap * 0.25))
		api.set_resources(greece, int(cap * 0.25))
