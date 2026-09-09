

extends MissionScript

var greece := 0
var ussr := 1

const CONVOY_UNITS := [
	["ftrk", "ftrk", "truk", "truk", "apc", "ftrk"],
	["ftrk", "3tnk", "truk", "truk", "apc"],
	["3tnk", "3tnk", "truk", "truk", "ftrk"],
]
const CONVOY_DELAYS := {
	"easy": [6000, 8000], "normal": [3750, 6000], "hard": [2250, 3750], "tough": [1500, 1875],
}
const CONVOYS := {"easy": 2, "normal": 3, "hard": 5, "tough": 10}
const PARADROP_DELAYS := {
	"easy": [1000, 2250], "normal": [750, 1750], "hard": [500, 1250], "tough": [250, 625],
}
const PARADROP_WAVES := {"easy": 4, "normal": 6, "hard": 10, "tough": 25}

const PARADROP_ITEMS := ["e1", "e1", "e1", "e2", "e2"]

const ATTACK_GROUP_SIZES := {"easy": 6, "normal": 8, "hard": 10, "tough": 12}
const ATTACK_DELAYS := {
	"easy": [100, 225], "normal": [50, 175], "hard": [25, 125], "tough": [25, 125],
}
const SOVIET_INFANTRY_TYPES := ["e1", "e1", "e2"]
const SOVIET_VEHICLE_TYPES := ["3tnk", "3tnk", "3tnk", "ftrk", "ftrk", "apc"]


const BOUNDS := Rect2i(37, 21, 56, 65)

var convoy_rally_points: Array = []
var paradrop_lzs: Array = []
var attack_rally_points: Array = []

var convoy_delay: Array = [3750, 6000]
var paradrop_delay: Array = [750, 1750]
var attack_delay: Array = [50, 175]
var attack_group_size := 8
var paradropped := 0
var convoys_sent := 0

var idling_units: Array = []
var attacking := false
var hold_production := false
var attack_ongoing := false
var harvester_killed := false


var base_buildings: Array = []
var initial_base: Array = []

var kill_ussr := -1
var destroy_convoys := -1


func _loc(name: String) -> Vector2i:
	var a := api.actor(name)
	return api.location(a) if a != null else Vector2i.ZERO


func world_loaded() -> void:
	greece = api.player("Greece")
	ussr = api.player("USSR")

	convoy_rally_points = [
		[_loc("SovietEntry1"), _loc("SovietRally1"), _loc("SovietRally3"), _loc("SovietRally5"),
			_loc("SovietRally4"), _loc("SovietRally6")],
		[_loc("SovietEntry2"), _loc("SovietRally10"), _loc("SovietRally11")],
	]
	paradrop_lzs = [_loc("ParadropPoint1"), _loc("ParadropPoint2"), _loc("ParadropPoint3")]
	attack_rally_points = [
		[_loc("SovietRally1"), _loc("SovietRally3"), _loc("SovietRally5"), _loc("SovietRally4"),
			_loc("SovietRally13"), _loc("PlayerBase")],
		[_loc("SovietRally7"), _loc("SovietRally10"), _loc("PlayerBase")],
		[_loc("SovietRally1"), _loc("SovietRally3"), _loc("SovietRally5"), _loc("SovietRally4"),
			_loc("SovietRally12"), _loc("PlayerBase")],
		[_loc("SovietRally7"), _loc("ParadropPoint1"), _loc("PlayerBase")],
		[_loc("SovietRally8"), _loc("SovietRally9"), _loc("ParadropPoint1"), _loc("PlayerBase")],
	]
	base_buildings = [
		{"name": "powr", "pos": Vector2i(47, 21), "prize": 500, "exists": true},
		{"name": "barr", "pos": Vector2i(53, 26), "prize": 400, "exists": true},
		{"name": "proc", "pos": Vector2i(54, 21), "prize": 1400, "exists": true},
		{"name": "weap", "pos": Vector2i(48, 28), "prize": 2000, "exists": true},
		{"name": "powr", "pos": Vector2i(51, 21), "prize": 500, "exists": true},
		{"name": "powr", "pos": Vector2i(46, 25), "prize": 500, "exists": true},
		{"name": "powr", "pos": Vector2i(49, 21), "prize": 500, "exists": true},

		{"name": "powr", "pos": Vector2i(56, 27), "prize": 600, "exists": true},
		{"name": "powr", "pos": Vector2i(51, 32), "prize": 600, "exists": true},
		{"name": "powr", "pos": Vector2i(54, 30), "prize": 600, "exists": true},
		{"name": "afld", "pos": Vector2i(43, 23), "prize": 500, "exists": true},
		{"name": "afld", "pos": Vector2i(43, 21), "prize": 500, "exists": true},
	]
	initial_base = api.actors(["Barracks", "Refinery", "PowerPlant1", "PowerPlant2", "PowerPlant3",
			"PowerPlant4", "Warfactory", "Flametur1", "Flametur2", "Flametur3", "Airfield1", "Airfield2"])

	api.camera_target = api.cell_center(_loc("AlliedConyard"))
	init_objectives(greece)
	kill_ussr = api.add_primary_objective(greece, "destroy-soviet-units-buildings")
	destroy_convoys = api.add_secondary_objective(greece, "destroy-convoys")

	convoy_delay = CONVOY_DELAYS.get(difficulty, CONVOY_DELAYS["normal"])
	paradrop_delay = PARADROP_DELAYS.get(difficulty, PARADROP_DELAYS["normal"])
	paradrop()
	send_convoys()
	api.after_delay(0, activate_ai)


func _drop_dir(cell: Vector2i) -> Vector2i:
	var edge := _edge_near(cell)
	var d := cell - edge
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x) if d.x != 0 else 1, 0)
	return Vector2i(0, signi(d.y) if d.y != 0 else 1)


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


func paradrop() -> void:
	api.after_delay(random_integer(paradrop_delay[0], paradrop_delay[1]), func():
		var lz: Vector2i = random(paradrop_lzs)
		for p in api.send_paratroopers(ussr, PARADROP_ITEMS, lz, _drop_dir(lz)):
			api.hunt(p)
		paradropped += 1
		if paradropped <= PARADROP_WAVES.get(difficulty, 6):
			paradrop())


func send_convoys() -> void:
	api.after_delay(random_integer(convoy_delay[0], convoy_delay[1]), func():
		var path: Array = random(convoy_rally_points)
		var types: Array = random(CONVOY_UNITS)
		var last: Vector2i = path[path.size() - 1]
		var units := api.reinforce(ussr, types, [path[0]], 25, func(u): setup_convoy_unit(u, path, last))
		var fp := api.on_entered_footprint([last], func(a, id):
			if a.player == ussr and units.has(a):

				api.stop(a)
				api.destroy(a)
				if a.type == "truk":
					api.mark_failed_objective(greece, destroy_convoys))


		api.after_delay(types.size() * 25 + 25, func():
			api.on_all_removed_from_world(units, func():
				api.remove_footprint_trigger(fp)
				convoys_sent += 1
				if convoys_sent <= CONVOYS.get(difficulty, 3):
					send_convoys()
				else:
					api.mark_completed_objective(greece, destroy_convoys)))
		api.play_speech_notification(greece, "ConvoyApproaching"))


func setup_convoy_unit(unit, path: Array, last: Vector2i) -> void:
	if unit.type == "truk":
		api.move_path(unit, path)
		api.on_idle(unit, func(u): api.move(u, last))
	else:
		api.patrol(unit, path)
		api.on_idle(unit, func(u): api.attack_move(u, last))


func activate_ai() -> void:
	attack_delay = ATTACK_DELAYS.get(difficulty, ATTACK_DELAYS["normal"])
	attack_group_size = ATTACK_GROUP_SIZES.get(difficulty, 8)
	init_ai_units()
	protect_harvester(api.actor("Harvester"))
	api.after_delay(api.seconds(10), func():
		produce_infantry()
		produce_vehicles())


func init_ai_units() -> void:
	idling_units = api.get_ground_attackers(ussr)
	defend_actor(api.actor("Conyard"))
	for i in initial_base.size():
		var v = initial_base[i]
		defend_actor(v)
		api.on_damaged(v, func(b):
			if b.player == ussr and api.health(b) < api.max_health(b) * 3.0 / 4.0:
				api.start_building_repairs(b))
		var idx := i
		api.on_killed(v, func(_u):
			if idx < base_buildings.size():
				base_buildings[idx]["exists"] = false)
	build_base()


func build_base() -> void:
	var conyard := api.actor("Conyard")
	if api.is_dead(conyard) or conyard.player != ussr:
		return
	if api.is_dead(api.actor("Harvester")) and api.resources(ussr) <= 299:
		return
	for v in base_buildings:
		if not v["exists"]:
			build_building(v)
			return
	api.after_delay(api.seconds(10), build_base)


func build_building(building: Dictionary) -> void:
	api.after_delay(api.build_time(building["name"]), func():
		var a = api.create_actor(building["name"], ussr, building["pos"])
		api.set_cash(ussr, api.cash(ussr) - int(building["prize"]))
		building["exists"] = true
		if a != null:
			api.on_killed(a, func(_u): building["exists"] = false)
			api.on_damaged(a, func(b):
				if b.player == ussr and api.health(b) < api.max_health(b) * 3.0 / 4.0:
					api.start_building_repairs(b)
					defend_actor(a))
		api.after_delay(api.seconds(10), build_base))


func setup_attack_group() -> Array:
	var units: Array = []
	for i in attack_group_size + 1:
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
	var units := setup_attack_group()
	var path: Array = random(attack_rally_points)
	for unit in units:
		api.patrol(unit, path)
		api.hunt(unit)
	api.on_all_removed_from_world(units, func():
		attacking = false
		hold_production = false)


func protect_harvester(unit) -> void:
	if unit == null:
		return
	defend_actor(unit)
	api.on_killed(unit, func(_u): harvester_killed = true)


func defend_actor(unit) -> void:
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


func produce_infantry() -> void:
	if hold_production:
		api.after_delay(api.minutes(1), produce_infantry)
		return
	var delay := random_integer(attack_delay[0], attack_delay[1])
	api.build(ussr, [random(SOVIET_INFANTRY_TYPES)], func(units: Array):
		if not units.is_empty():
			idling_units.append(units[0])
		api.after_delay(delay, produce_infantry)
		if idling_units.size() >= attack_group_size * 2.5:
			send_attack())


func produce_vehicles() -> void:
	if hold_production:
		api.after_delay(api.minutes(1), produce_vehicles)
		return
	var delay := random_integer(attack_delay[0], attack_delay[1])
	if harvester_killed:
		api.build(ussr, ["harv"], func(harv: Array):
			if not harv.is_empty():
				protect_harvester(harv[0])
			harvester_killed = false
			api.after_delay(delay, produce_vehicles))
	else:
		api.build(ussr, [random(SOVIET_VEHICLE_TYPES)], func(units: Array):
			if not units.is_empty():
				idling_units.append(units[0])
			api.after_delay(delay, produce_vehicles)
			if idling_units.size() >= attack_group_size * 2.5:
				send_attack())


func tick() -> void:
	if api.has_no_required_units(greece):
		api.mark_failed_objective(greece, kill_ussr)
	if api.has_no_required_units(ussr):
		api.mark_completed_objective(greece, kill_ussr)
		api.mark_completed_objective(greece, destroy_convoys)


func test_force() -> void:
	for u in api.get_actors(ussr):
		api.kill(u)
