

class_name MissionApi
extends RefCounted

const WIN_WON := 1
const WIN_LOST := 2

var world: ProtoWorld
var sim: RefCounted
var players := {}
var player_names := {}
var by_map_id := {}
var messages := {}
var map_notifications := {}
var mission_text := ""
var time_limit := 0
var time_left := 0
var objectives := {}
var _next_objective := 1


var _delays: Array = []
var _on_killed: Array = []
var _on_all_killed: Array = []
var _on_any_killed: Array = []
var _on_damaged: Array = []
var _on_idle: Array = []
var _footprints := {}
var _proximity := {}
var _on_timer_expired: Array = []
var _on_removed: Array = []
var _on_all_gone: Array = []
var _builds: Array = []
var _next_trigger_id := 1
var _last_units_count := 0
var _hunters := {}
var _prev_alive := {}
var _walkers: Array = []
var _api_units := {}
var _marker_reveals := {}
var _on_added: Array = []
var _on_removed_one: Array = []
var _on_capture: Array = []
var _on_infiltrated: Array = []
var _on_sold: Array = []
var _on_won: Array = []
var _on_lost: Array = []
var _win_seen := 0
var _time_warn := {}
var camera_target := Vector2.ZERO
var mission_color := Color(1, 1, 1)
var countdown_text := ""
var time_notification := ""
var skip_timer_expired := false
var difficulty := "normal"


func setup(w: ProtoWorld) -> void:
	world = w
	sim = w.sim


	messages = RulesDb.data().get("lua_messages", {}).duplicate()
	if world.map_data != null:
		messages.merge(_load_ftl("res://assets/maps/%s.map.ftl" % world.map_data.slug), true)
		map_notifications = world.map_data.notifications.duplicate()
		var tl: Dictionary = world.map_data.time_limit
		countdown_text = tl.get("countdown_text", "")
		time_notification = tl.get("notification", "")
		skip_timer_expired = bool(tl.get("skip_expired", false))
		difficulty = world.map_data.difficulty_default
	for u in world.units:
		if u.map_id != "":
			by_map_id[u.map_id] = u
	_last_units_count = world.units.size()
	_apply_initial_stances()


func _apply_initial_stances() -> void:
	if world.map_data == null:
		return
	var over: Dictionary = world.map_data.rules_override.get("actors", {})
	if over.is_empty():
		return
	for u in world.units:
		if not u.alive or u.player == 0:
			continue
		var st: String = over.get(u.type, {}).get("auto_target_ai", "")
		if st != "":
			set_stance(u, st)


func _load_ftl(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var key := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var m := RegEx.create_from_string("^([a-z0-9\\-]+)\\s*=\\s*(.*)$").search(line)
		if m != null:
			key = m.get_string(1)
			out[key] = m.get_string(2).strip_edges()
		elif key != "" and line.begins_with("    "):
			out[key] = (String(out[key]) + "\n" + line.strip_edges()).strip_edges()
		else:
			key = ""
	return out


func player_color(owner: int) -> Color:
	if owner >= 0 and owner < world.player_colors.size():
		return world.player_colors[owner]
	return Color(1, 1, 1)


func lobby_option(id: String, default_value: String) -> String:
	return difficulty if id == "difficulty" else default_value


func player(name: String) -> int:
	return players.get(name, -1)


func actor(map_id: String) -> ProtoWorld.Unit:
	return by_map_id.get(map_id, null)


func actors(ids: Array) -> Array:
	var out := []
	for i in ids:
		var u := actor(i)
		if u != null:
			out.append(u)
	return out


func is_dead(u) -> bool:
	return u == null or not u.alive


func location(u) -> Vector2i:
	return world._cell_of(u.pos)


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * ProtoWorld.CELL


func facing_between(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var d := Vector2(to_cell - from_cell)
	if d == Vector2.ZERO:
		return -1
	return wrapi(int(round(atan2(-d.x, -d.y) / TAU * 1024.0)), 0, 1024)


static func _call_cb(cb: Callable, args: Array) -> void:
	var n := cb.get_argument_count()
	cb.callv(args.slice(0, mini(n, args.size())))


var _by_id := {}
var _by_id_count := -1


func actor_by_id(id: int):
	if id < 0:
		return null
	if _by_id_count != world.units.size():
		_by_id.clear()
		for u in world.units:
			_by_id[u.id] = u
		_by_id_count = world.units.size()
	return _by_id.get(id, null)


func _guess_attacker(victim):
	if sim.has_method("last_attacker"):
		var a = actor_by_id(int(sim.last_attacker(victim.id)))
		if a != null:
			return a
	var best = null
	var best_d := INF
	for o in world.units:
		if not o.alive or o == victim or not world.hostile(victim.player, o.player):
			continue
		if not o.firing and not world.types[o.type].get("building", false):
			continue
		var d: float = victim.pos.distance_squared_to(o.pos)
		if d < best_d and sqrt(d) <= maxf(_weapon_range(o), ProtoWorld.CELL * 2.0):
			best_d = d
			best = o
	return best


func attacker(victim):
	if victim == null:
		return null
	return _guess_attacker(victim)


func attacker_owner(victim) -> int:
	if sim.has_method("last_attacker_owner"):
		return int(sim.last_attacker_owner(victim.id))
	var a = _guess_attacker(victim)
	return a.player if a != null else -1


const ORDER_GRACE := 25
var _order_tick := {}


func _mark_ordered(u) -> void:
	_order_tick[u.id] = int(sim.tick())


func move(u, cell: Vector2i, queued: bool = false) -> void:
	if is_dead(u):
		return
	if not queued:
		_hunters.erase(u.id)
	_mark_ordered(u)
	sim.order_move(PackedInt32Array([u.id]), cell.x, cell.y, queued)


func attack_move(u, cell: Vector2i, queued: bool = false) -> void:
	if is_dead(u):
		return
	_mark_ordered(u)
	sim.order_attack_move(PackedInt32Array([u.id]), cell.x, cell.y, queued)


func attack(u, target, allow_move: bool = true, _force: bool = true, queued: bool = false) -> void:
	if is_dead(u) or is_dead(target):
		return
	if not allow_move and u.pos.distance_to(target.pos) > _weapon_range(u):
		return
	_mark_ordered(u)
	sim.order_attack(PackedInt32Array([u.id]), target.id, queued)


func _weapon_range(u) -> float:
	var t: Dictionary = world.types[u.type]
	var best := 0.0
	for a in t.get("armaments", []):
		var w: Dictionary = RulesDb.data().get("weapons", {}).get(a.get("weapon", ""), {})

		best = maxf(best, float(w.get("range", 0)) / 1024.0 * ProtoWorld.CELL)
	return best


func attack_cell(u, cell: Vector2i) -> void:
	if not is_dead(u):
		_mark_ordered(u)
		sim.order_attack_cell(PackedInt32Array([u.id]), cell.x, cell.y)


func stop(u) -> void:
	if is_dead(u):
		return
	_hunters.erase(u.id)
	_order_tick.erase(u.id)
	_walkers = _walkers.filter(func(w): return w["u"] != u)
	sim.order_stop(PackedInt32Array([u.id]))


func hunt(u) -> void:
	if is_dead(u):
		return
	_hunters[u.id] = true
	_hunt_step(u)


const HUNT_INTERVAL := 12
var _hunt_last := {}


func _hunt_step(u) -> void:
	var now := int(sim.tick())
	if now - int(_hunt_last.get(u.id, -1000)) < HUNT_INTERVAL:
		return
	_hunt_last[u.id] = now
	var target := nearest_enemy(u)
	if target != null:
		attack_move(u, location(target))


func nearest_enemy(u) -> ProtoWorld.Unit:
	var best: ProtoWorld.Unit = null
	var best_d := INF
	for o in world.units:
		if not o.alive or o == u or not world.hostile(u.player, o.player):
			continue
		if not world.types[o.type].get("targetable", true):
			continue
		var d: float = u.pos.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


func kill(u) -> void:
	if not is_dead(u):
		sim.destroy(u.id)


func destroy(u) -> void:
	if is_dead(u):
		return
	if sim.has_method("remove_actor") and sim.remove_actor(u.id):
		return
	kill(u)


func find_resources(u) -> void:
	if not is_dead(u):
		_mark_ordered(u)
		sim.order_harvest(PackedInt32Array([u.id]), location(u).x, location(u).y)


func scatter(u) -> void:
	if not is_dead(u):
		sim.order_scatter(PackedInt32Array([u.id]))


func panic(u) -> void:
	scatter(u)


func deploy(u) -> void:
	if not is_dead(u):
		sim.order_deploy(PackedInt32Array([u.id]))


func sell_actor(u) -> void:
	if not is_dead(u):
		sim.sell(u.id)


func max_health(u) -> int:
	return int(world.types[u.type].get("hp", 1)) if u != null else 0


func health(u) -> int:
	if is_dead(u):
		return 0
	return int(sim.actor_hp(u.id))


func set_health(u, value: int) -> bool:
	if is_dead(u) or not sim.has_method("set_health"):
		return false
	return sim.set_health(u.id, value)


func set_owner(u, owner: int) -> bool:
	if u == null:
		return false
	if u is Reveal:
		return u.set_owner(owner)


	if u.id < 0 and _is_reveal_only(u.type):
		var r = _marker_reveals.get(u.map_id)
		if r != null:
			return r.set_owner(owner)
		r = create_actor(u.type, owner, location(u))
		_marker_reveals[u.map_id] = r
		return r != null
	if is_dead(u) or not sim.has_method("set_owner"):
		return false
	if not sim.set_owner(u.id, owner):
		return false
	u.player = owner
	if u.selected and owner != 0:
		u.selected = false
		world.selection.erase(u)
	return true


func on_infiltrated(u, cb: Callable) -> void:
	if u == null or is_dead(u) or sim == null or not sim.has_method("infiltrated_count"):
		return
	_on_infiltrated.append([u, cb, sim.infiltrated_count(u.id)])


func infiltrate(u, target) -> bool:
	if is_dead(u) or is_dead(target) or sim == null or not sim.has_method("order_infiltrate"):
		return false
	var ids := PackedInt32Array([u.id])
	sim.order_infiltrate(ids, target.id)
	return true


func demolish(u, target) -> bool:
	if is_dead(u) or is_dead(target) or sim == null or not sim.has_method("order_demolish"):
		return false
	var ids := PackedInt32Array([u.id])
	sim.order_demolish(ids, target.id)
	return true


func capture(u, target) -> bool:
	if is_dead(u) or is_dead(target) or sim == null or not sim.has_method("order_enter"):
		return false
	var ids := PackedInt32Array([u.id])
	sim.order_enter(ids, target.id)
	return true


func disguise_as_type(u, type_name: String, owner: int) -> bool:
	if is_dead(u) or sim == null or not sim.has_method("set_disguise"):
		return false
	if not world.type_ids.has(type_name):
		return false
	return sim.set_disguise(u.id, world.type_ids[type_name], owner)


func has_property(u, name: String) -> bool:
	if u == null:
		return false
	var t: Dictionary = world.types[u.type]
	match name:
		"StartBuildingRepairs", "StopBuildingRepairs":
			return t.has("repair_step")
		"Sell":
			return t.get("building", false)
		"FindResources":
			return t.get("harvester", false)
		"Deploy":
			return t.has("transforms")
		"Attack", "AttackMove", "Hunt":
			return t.get("combat", false)
		"Move", "Scatter":
			return t.has("speed")
		"Produce":
			return t.has("produces")
	return false


const STANCES := ["HoldFire", "ReturnFire", "Defend", "AttackAnything"]


func set_stance(u, stance: String) -> bool:
	if is_dead(u):
		return false
	sim.set_stance(u.id, maxi(0, STANCES.find(stance)))
	return true


func stance(u) -> String:
	if is_dead(u):
		return "Defend"
	return STANCES[clampi(int(sim.stance(u.id)), 0, 3)]


func set_stance_all(list: Array, stance_name: String) -> void:
	for u in list:
		set_stance(u, stance_name)


func teleport(u, cell: Vector2i) -> bool:
	if is_dead(u):
		return false
	if sim.has_method("teleport") and sim.teleport(u.id, cell.x, cell.y):
		u.pos = cell_center(cell)
		u.goal = u.pos
		return true
	u.pos = cell_center(cell)
	return false


func call_func(cb: Callable) -> void:
	after_delay(0, cb)


func wait(ticks: int, cb: Callable) -> void:
	after_delay(ticks, cb)


func is_idle(u) -> bool:
	if is_dead(u) or u.moving or u.firing:
		return false
	return int(sim.tick()) - int(_order_tick.get(u.id, -10000)) >= ORDER_GRACE


func get_ground_attackers(owner: int) -> Array:
	var out := []
	for u in world.units:
		if u.alive and u.player == owner and world.types[u.type].get("combat", false) and not world.types[u.type].get("building", false):
			out.append(u)
	return out


func get_actors_by_type(owner: int, type: String) -> Array:
	var out := []
	for u in world.units:
		if u.alive and u.player == owner and u.type == type:
			out.append(u)
	return out


func get_actors(owner: int) -> Array:
	var out := []
	for u in world.units:
		if u.alive and u.player == owner:
			out.append(u)
	return out


func has_no_required_units(owner: int) -> bool:
	for u in world.units:
		if u.alive and u.player == owner and world.types[u.type].has("must_be_destroyed"):
			return false
	return true


func has_prerequisites(owner: int, tokens: Array) -> bool:
	for t in tokens:
		if not sim.has_prerequisite(owner, t):
			return false
	return true


func is_producing(owner: int, type: String) -> bool:
	var base := base_type(type)
	if not world.type_ids.has(base):
		return false
	var tid: int = world.type_ids[base]
	for kind in 4:
		var q: PackedInt32Array = sim.queue_state(owner, kind)
		for i in q.size() / 7:
			if q[i * 7] == tid:
				return true
	return false


func set_primary(u) -> void:
	if not is_dead(u):
		sim.set_primary(u.id)


func build(owner: int, types: Array, cb: Callable) -> bool:
	var remaining: Array = []
	for t in types:
		if world.type_ids.has(t) and sim.queue_build(owner, world.type_ids[t]):
			remaining.append(t)
	if remaining.is_empty():
		return false
	_builds.append([owner, remaining, [], cb])
	return true


func add_objective(owner: int, text_key: String, primary: bool = true, announce: bool = true) -> int:
	var id := _next_objective
	_next_objective += 1
	var text := get_message(text_key) if text_key != "" else ""
	objectives.get_or_add(owner, []).append({"id": id, "text": text, "primary": primary, "state": "open"})

	if announce and owner == 0 and text != "":
		display_message(text, get_message("new-primary-objective" if primary else "new-secondary-objective"))
	return id


func add_primary_objective(owner: int, text_key: String, announce: bool = true) -> int:
	return add_objective(owner, text_key, true, announce)


func add_secondary_objective(owner: int, text_key: String, announce: bool = true) -> int:
	return add_objective(owner, text_key, false, announce)


func _objective(owner: int, id: int) -> Dictionary:
	for o in objectives.get(owner, []):
		if o["id"] == id:
			return o
	return {}


func is_objective_completed(owner: int, id: int) -> bool:
	return _objective(owner, id).get("state", "") == "done"


func is_objective_failed(owner: int, id: int) -> bool:
	return _objective(owner, id).get("state", "") == "failed"


func cash(owner: int) -> int:
	return int(sim.cash(owner))


func credits(owner: int) -> int:
	return int(sim.credits(owner))


func set_cash(owner: int, value: int) -> void:
	sim.give_credits(owner, value - cash(owner))


func give_cash(owner: int, value: int) -> void:
	sim.give_credits(owner, value)


func resources(owner: int) -> int:
	return int(sim.resources_stored(owner))


func resource_capacity(owner: int) -> int:
	return int(sim.storage_capacity(owner))


func set_resources(owner: int, value: int) -> void:
	if sim.has_method("set_resources"):
		sim.set_resources(owner, value)
		return
	var diff := value - resources(owner)
	if diff > 0:
		sim.give_credits(owner, diff)


func mark_completed_objective(owner: int, id: int) -> void:
	var o := _objective(owner, id)
	if o.is_empty() or o["state"] != "open":
		return
	o["state"] = "done"
	if owner == 0:
		if o["text"] != "":
			display_message(o["text"], get_message("objective-completed"))
		_check_player_objectives()
	else:

		if o["primary"] and world.hostile(0, owner):
			var all_done := true
			for e in objectives.get(owner, []):
				if e["primary"] and e["state"] != "done":
					all_done = false
			if all_done:
				sim.set_win_state(0, WIN_LOST)


func mark_failed_objective(owner: int, id: int) -> void:
	var o := _objective(owner, id)
	if o.is_empty() or o["state"] == "failed":
		return
	o["state"] = "failed"
	if owner == 0:
		if o["text"] != "":
			display_message(o["text"], get_message("objective-failed"))
		if o["primary"]:
			sim.set_win_state(0, WIN_LOST)


func _check_player_objectives() -> void:
	var any_primary := false
	for o in objectives.get(0, []):
		if o["primary"]:
			any_primary = true
			if o["state"] != "done":
				return
	if any_primary:
		sim.set_win_state(0, WIN_WON)


func after_delay(ticks: int, cb: Callable) -> void:
	_delays.append([maxi(ticks, 0), cb])


func on_killed(u, cb: Callable) -> void:
	if u != null:
		_on_killed.append([u, cb, false])


func on_all_killed(list: Array, cb: Callable) -> void:
	_on_all_killed.append([list, cb, false])


func on_any_killed(list: Array, cb: Callable) -> void:
	_on_any_killed.append([list, cb, false])


func on_all_killed_or_captured(list: Array, cb: Callable) -> void:
	var owners: Array = []
	for u in list:
		owners.append(u.player if u != null else -1)
	_on_all_gone.append([list, owners, cb, false])


func on_killed_or_captured(u, cb: Callable) -> void:
	if u != null:
		on_all_killed_or_captured([u], cb)


func on_all_removed_from_world(list: Array, cb: Callable) -> void:
	_on_removed.append([list, cb, false])


func on_removed_from_world(u, cb: Callable) -> void:
	if u != null:
		_on_removed_one.append([u, cb, false])


func on_added_to_world(type: String, owner: int, cb: Callable) -> void:
	_on_added.append([type, owner, cb])


func on_capture(u, cb: Callable) -> void:
	if u != null:
		_on_capture.append([u, cb, u.player])


func on_sold(u, cb: Callable) -> void:
	if u != null:
		_on_sold.append([u, cb, false])


func on_player_won(cb: Callable) -> void:
	_on_won.append(cb)


func on_player_lost(cb: Callable) -> void:
	_on_lost.append(cb)


func on_damaged(u, cb: Callable) -> void:
	if u != null:
		_on_damaged.append([u, cb, u.hp])


func on_idle(u, cb: Callable) -> void:
	if u != null:
		_on_idle.append([u, cb, false])


func on_entered_footprint(cells: Array, cb: Callable) -> int:
	var id := _next_trigger_id
	_next_trigger_id += 1
	_footprints[id] = {"cells": cells, "cb": cb, "inside": {}}
	return id


func remove_footprint_trigger(id: int) -> void:
	_footprints.erase(id)


func on_entered_proximity(pos: Vector2, range_cells: float, cb: Callable) -> int:
	var id := _next_trigger_id
	_next_trigger_id += 1
	_proximity[id] = {"pos": pos, "range": range_cells * ProtoWorld.CELL, "cb": cb, "inside": {}, "exit": false}
	return id


func on_exited_proximity(pos: Vector2, range_cells: float, cb: Callable) -> int:
	var id := _next_trigger_id
	_next_trigger_id += 1
	_proximity[id] = {"pos": pos, "range": range_cells * ProtoWorld.CELL, "cb": cb, "inside": {}, "exit": true}
	return id


func remove_proximity_trigger(id: int) -> void:
	_proximity.erase(id)


func on_timer_expired(cb: Callable) -> void:
	_on_timer_expired.append(cb)


func set_time_limit(ticks: int, text: String = "", notification: String = "") -> void:
	time_limit = ticks
	time_left = ticks
	_time_warn.clear()
	if text != "":
		countdown_text = text
	if notification != "":
		time_notification = notification


func shutdown() -> void:
	clear_all()
	_builds.clear()
	_on_won.clear()
	_on_lost.clear()
	_hunters.clear()
	_hunt_last.clear()
	_order_tick.clear()
	_prev_alive.clear()
	_api_units.clear()
	for r in _marker_reveals.values():
		if r != null:
			r.destroy()
	_marker_reveals.clear()
	_by_id.clear()
	_by_id_count = -1
	by_map_id.clear()
	objectives.clear()
	messages.clear()
	map_notifications.clear()
	_time_warn.clear()
	world = null
	sim = null


func clear_all() -> void:
	_transports.clear()
	_leaving.clear()
	_delays.clear()
	_on_killed.clear()
	_on_all_killed.clear()
	_on_any_killed.clear()
	_on_damaged.clear()
	_on_idle.clear()
	_footprints.clear()
	_proximity.clear()
	_on_timer_expired.clear()
	_on_removed.clear()
	_on_all_gone.clear()
	_on_removed_one.clear()
	_on_added.clear()
	_on_capture.clear()
	_on_infiltrated.clear()
	_on_sold.clear()
	_walkers.clear()


func reinforce(owner: int, types: Array, path: Array, interval: int = 25, cb: Callable = Callable()) -> Array:
	var out: Array = []
	for i in types.size():
		var t: String = types[i]
		var facing := facing_between(path[0], path[1]) if path.size() > 1 else -1
		after_delay(i * interval, func():
			var u = spawn_near(base_type(t), owner, path[0], facing)
			if u == null:
				return
			_api_units[u.id] = true
			_apply_variant(u, t)
			out.append(u)
			if path.size() > 1:
				_walk(u, path.slice(1), cb, false, 0)
			elif cb.is_valid():
				cb.call(u))
	return out


func _walk(u, path: Array, cb: Callable, attack: bool, wait_ticks: int, loop: bool = false) -> void:
	if is_dead(u) or path.is_empty():
		if cb.is_valid() and not is_dead(u):
			cb.call(u)
		return
	_walkers = _walkers.filter(func(w): return w["u"] != u)
	_walkers.append({"u": u, "path": path, "i": 0, "cb": cb, "attack": attack, "wait": wait_ticks,
					 "loop": loop, "delay": 0, "issued": false, "idle": 0})


func attack_move_path(u, path: Array, cb: Callable = Callable()) -> void:
	_walk(u, path, cb, true, 0)


func move_path(u, path: Array, wait_ticks: int = 0, cb: Callable = Callable()) -> void:
	_walk(u, path.duplicate(), cb, false, wait_ticks)


func patrol(u, path: Array, loop: bool = true, delay: int = 0) -> void:
	if is_dead(u) or path.is_empty():
		return
	_walk(u, path.duplicate(), Callable(), true, delay, loop)


const WALK_TOLERANCE := 2.0


const WALK_STALL := 50


func _walker_step(w: Dictionary) -> bool:
	var u = w["u"]
	if is_dead(u):
		return true
	if w["delay"] > 0:
		w["delay"] -= 1
		return false
	var target: Vector2i = w["path"][w["i"]]
	var near: bool = location(u) == target or u.pos.distance_to(cell_center(target)) < ProtoWorld.CELL * WALK_TOLERANCE
	if not near and is_idle(u):
		w["idle"] += 1
		near = w["idle"] > WALK_STALL
	elif not near:
		w["idle"] = 0
	if near:
		w["i"] += 1
		w["idle"] = 0
		if w["i"] >= w["path"].size():
			if w["loop"]:
				w["i"] = 0
				w["issued"] = false
				w["delay"] = w["wait"]
				return false
			if w["cb"].is_valid():
				w["cb"].call(u)
			return true
		if w["wait"] > 0:
			w["issued"] = false
			w["delay"] = w["wait"]
		return false
	if not w["issued"]:
		w["issued"] = true
		w["idle"] = 0

		var last: int = w["path"].size() - 1 if w["wait"] <= 0 else w["i"]
		for k in range(w["i"], last + 1):
			var c: Vector2i = w["path"][k]
			if w["attack"]:
				attack_move(u, c, k > w["i"])
			else:
				move(u, c, k > w["i"])
	return false


func type_cost(type: String) -> int:
	var base := base_type(type)
	return int(sim.type_cost(world.type_ids[base])) if world.type_ids.has(base) else 0


func build_time(type: String) -> int:
	if not world.type_ids.has(type):
		return 25
	return sim.build_time(world.type_ids[type])


func clear_all_for(u) -> void:
	if u == null:
		return
	_on_killed = _on_killed.filter(func(t): return t[0] != u)
	_on_damaged = _on_damaged.filter(func(t): return t[0] != u)
	_on_idle = _on_idle.filter(func(t): return t[0] != u)
	_on_removed_one = _on_removed_one.filter(func(t): return t[0] != u)
	_on_capture = _on_capture.filter(func(t): return t[0] != u)
	_on_infiltrated = _on_infiltrated.filter(func(t): return t[0] != u)
	_on_sold = _on_sold.filter(func(t): return t[0] != u)
	_on_all_killed = _on_all_killed.filter(func(t): return not t[0].has(u))
	_on_any_killed = _on_any_killed.filter(func(t): return not t[0].has(u))
	_on_removed = _on_removed.filter(func(t): return not t[0].has(u))
	_walkers = _walkers.filter(func(w): return w["u"] != u)
	_hunters.erase(u.id)


func actors_with_tag(tag: String) -> Array:
	var out: Array = []
	for u in by_map_id.values():
		if u != null and u.tags.has(tag):
			out.append(u)
	return out


func named_actors() -> Array:
	return by_map_id.values()


func actors_in_world() -> Array:
	var out: Array = []
	for u in world.units:
		if u.alive:
			out.append(u)
	return out


func actors_in_box(a: Vector2i, b: Vector2i) -> Array:
	var r := Rect2i(mini(a.x, b.x), mini(a.y, b.y), absi(a.x - b.x) + 1, absi(a.y - b.y) + 1)
	var out: Array = []
	for u in world.units:
		if u.alive and r.has_point(location(u)):
			out.append(u)
	return out


func actors_in_circle(center: Vector2, range_cells: float) -> Array:
	var out: Array = []
	for u in world.units:
		if u.alive and u.pos.distance_to(center) <= range_cells * ProtoWorld.CELL:
			out.append(u)
	return out


func center_of_cell(c: Vector2i) -> Vector2:
	return cell_center(c)


func where(list: Array, pred: Callable) -> Array:
	return list.filter(pred)


func shuffle(list: Array) -> Array:
	var out := list.duplicate()
	out.shuffle()
	return out


class Reveal extends RefCounted:
	var api: MissionApi
	var handle := -1
	var alive := true
	var owner := 0
	var cells := 10
	var at := Vector2i(-1, -1)

	func destroy() -> void:
		alive = false
		if handle >= 0 and api != null:
			api.sim.remove_reveal_source(handle)
			handle = -1

	func is_dead() -> bool:
		return not alive

	func is_in_world() -> bool:
		return alive


	func set_owner(new_owner: int) -> bool:
		if not alive or api == null:
			return false
		if new_owner == owner:
			return true
		owner = new_owner
		if handle >= 0:
			api.sim.remove_reveal_source(handle)
			handle = int(api.sim.reveal_source(owner, at.x, at.y, cells))
		return true


	func teleport(cell: Vector2i) -> void:
		if not alive or api == null or cell == at:
			return
		if handle >= 0:
			api.sim.remove_reveal_source(handle)
		handle = int(api.sim.reveal_source(owner, cell.x, cell.y, cells))
		at = cell


func base_type(type: String) -> String:
	if world.types.has(type):
		return type
	var base := type.get_slice(".", 0)
	return base if world.types.has(base) else type


func _apply_variant(u, type: String) -> void:
	if u != null and type.ends_with(".noautotarget"):
		set_stance(u, "HoldFire")


func _reveal_cells(type: String) -> int:
	var raw: Dictionary = world.rules.actors.get(type, {})
	var cells := int(ceil(float(raw.get("reveals", 0)) / 1024.0))
	if cells > 0:
		return cells
	return 3 if type.begins_with("flare") else 10


func _is_reveal_only(type: String) -> bool:
	if type.begins_with("camera") or type.begins_with("flare"):
		return true
	var raw: Dictionary = world.rules.actors.get(type, {})
	return int(raw.get("reveals", 0)) > 0 and not raw.has("hp")


func spawn_near(type: String, owner: int, cell: Vector2i, facing: int = -1, radius: int = 6):
	var u := world.spawn_unit(type, owner, cell, facing)
	if u != null:
		return u
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				u = world.spawn_unit(type, owner, cell + Vector2i(dx, dy), facing)
				if u != null:
					return u
	return null


func create_actor(type: String, owner: int, cell: Vector2i):
	if _is_reveal_only(type):
		var r := Reveal.new()
		r.api = self
		r.owner = owner if owner >= 0 else 0
		r.cells = _reveal_cells(type)
		r.at = cell
		r.handle = int(sim.reveal_source(r.owner, cell.x, cell.y, r.cells))
		return r
	var base := base_type(type)
	if not world.types.has(base):
		return null
	var u: ProtoWorld.Unit
	if world.types[base].get("building", false):
		u = world._add_building(base, owner, cell)
	else:
		u = spawn_near(base, owner, cell)
	if u != null:
		_api_units[u.id] = true
		_apply_variant(u, type)
	return u


func start_building_repairs(u) -> void:
	if not is_dead(u) and not u.repairing:
		sim.toggle_repair(u.id)


func all_idle(list: Array) -> bool:
	for u in list:
		if not is_dead(u) and not is_idle(u):
			return false
	return true


const MISSIONS_DE_CSV := "res://i18n/missions_de.csv"


const MISSIONS_DE_EXTRA_CSVS := ["res://i18n/missions_tutorial_de.csv"]
static var _missions_de := {}
static var _missions_de_loaded := false


static func _load_missions_de_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			_missions_de[row[0]] = row[1]


static func _load_missions_de() -> void:
	if _missions_de_loaded:
		return
	_missions_de_loaded = true
	_load_missions_de_csv(MISSIONS_DE_CSV)
	for path in MISSIONS_DE_EXTRA_CSVS:
		_load_missions_de_csv(path)


func get_message(key: String) -> String:
	if Lang.is_de():
		_load_missions_de()
		if _missions_de.has(key):
			return _missions_de[key]
	return messages.get(key, key)


func display_message(text: String, prefix: String = "") -> void:
	world.mission_message.emit(text, prefix)


var hud_highlight := ""
var highlight_unit = null


var highlight_cameo_type := ""


func highlight_hud(id: String, unit = null) -> void:
	hud_highlight = id
	highlight_unit = unit
	highlight_cameo_type = ""


func highlight_cameo(type_name: String) -> void:
	hud_highlight = "cameo"
	highlight_cameo_type = type_name
	highlight_unit = null


func clear_highlight() -> void:
	hud_highlight = ""
	highlight_unit = null
	highlight_cameo_type = ""


var build_bar_open := false
var build_bar_kind := -1


var control_groups: Array = []


var awaiting_ack := false


func wait_for_tap() -> void:
	awaiting_ack = true


func confirm_ack() -> void:
	awaiting_ack = false


func set_camera(pos: Vector2) -> void:
	camera_target = pos
	if world != null and world.is_inside_tree():
		world.center_on(pos)


func set_mission_text(text: String, color: Color = Color(1, 1, 1)) -> void:
	mission_text = text
	mission_color = color


func fluent_message(key: String, args: Dictionary = {}) -> String:
	var text := get_message(key)
	for k in args:
		text = text.replace("{ $%s }" % k, str(args[k])).replace("{%s}" % k, str(args[k]))
	return text


func play_movie_fullscreen(name: String, cb: Callable = Callable()) -> bool:
	var m := Movie.play(world, name)
	if m == null:
		if cb.is_valid():
			cb.call()
		return false
	var was_paused := world.paused
	world.paused = true
	m.finished.connect(func():
		world.paused = was_paused
		if cb.is_valid():
			cb.call())
	return true


func play_movie_in_radar(name: String, cb: Callable = Callable()) -> bool:
	var m := Movie.play(world, name)
	if m == null:
		if cb.is_valid():
			cb.call()
		return false
	if cb.is_valid():
		m.finished.connect(func(): cb.call())
	return true


func play_music(name: String = "") -> void:
	var mp := world.get_node_or_null("/root/MusicPlayer")
	if mp != null:
		mp.play_track(name)


func stop_music() -> void:
	var mp := world.get_node_or_null("/root/MusicPlayer")
	if mp != null:
		mp.stop()


func notification_sound(name: String) -> String:
	if map_notifications.has(name):
		return String(map_notifications[name])
	return String(RulesDb.data().get("notifications", {}).get(name, ""))


func play_speech_notification(owner: int, name: String) -> void:
	if owner != 0 and owner != -1:
		return
	var snd := notification_sound(name)
	if snd != "":
		world.eva(snd, 0.0)


func play_sound(name: String) -> void:
	world.sfx.play_local(name.get_basename())


func play_sound_notification(owner: int, name: String) -> void:
	if owner != 0 and owner != -1:
		return
	var snd := notification_sound(name)
	if snd == "":
		snd = String(RulesDb.data().get("ui_sounds", {}).get(name, name))
	play_sound(snd)


func seconds(n: float) -> int:
	return int(n * 25)


func minutes(n: float) -> int:
	return int(n * 1500)


func format_time(ticks: int, leading_minute_zero: bool = true) -> String:
	var s := int(ceil(float(maxi(ticks, 0)) / 25.0))
	if leading_minute_zero:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


var _leaving: Array = []

var _transports: Array = []


func reinforce_with_transport(owner: int, type: String, cargo_types: Array, entry_path: Array,
		exit_path: Array = [], action_cb: Callable = Callable(), exit_cb: Callable = Callable(),
		drop_range: int = 3, cargo_cb: Callable = Callable()) -> Array:
	if entry_path.is_empty():
		return [null, []]
	var facing := facing_between(entry_path[0], entry_path[1]) if entry_path.size() > 1 else -1
	var transport = _create_air_actor(type, owner, entry_path[0], facing)
	if transport == null:


		return [null, reinforce(owner, cargo_types, entry_path, seconds(0.5), cargo_cb)]
	var cargo: Array = []
	for ct in cargo_types:
		var pass_unit = create_actor(base_type(ct), owner, entry_path[0])
		if pass_unit == null:
			continue
		if world.sim.load_passenger(transport.id, pass_unit.id):
			cargo.append(pass_unit)
			if cargo_cb.is_valid():
				cargo_cb.call(pass_unit)
		else:
			destroy(pass_unit)
	_transports.append({"u": transport, "path": entry_path.slice(1), "i": 0, "cargo": cargo,
			"action": action_cb, "exit": exit_path.duplicate(), "exit_cb": exit_cb,
			"range": drop_range, "state": 0, "wait": 0})
	return [transport, cargo]


func send_paratroopers(owner: int, types: Array, target: Vector2i, dir: Vector2i = Vector2i(1, 0),
		plane: String = "badr") -> Array:
	var step := Vector2i(signi(dir.x), signi(dir.y))
	if step == Vector2i.ZERO:
		step = Vector2i(1, 0)
	var reach := world.map_w + world.map_h
	var entry := target - step * reach
	var exitp := target + step * reach
	entry = Vector2i(clampi(entry.x, -1, world.map_w), clampi(entry.y, -1, world.map_h))
	exitp = Vector2i(clampi(exitp.x, -1, world.map_w), clampi(exitp.y, -1, world.map_h))
	var badger = _create_air_actor(plane, owner, entry, facing_between(entry, exitp))
	if badger == null:

		return reinforce(owner, types, [entry, target], seconds(0.5))
	var cargo: Array = []
	for t in types:
		var u = create_actor(base_type(t), owner, entry)
		if u != null and world.sim.load_passenger(badger.id, u.id):
			cargo.append(u)
	world.sim.order_paradrop(badger.id, target.x, target.y)
	move(badger, exitp)
	_leaving.append(badger)
	return cargo


func create_air_actor(type: String, owner: int, cell: Vector2i, facing: int = -1):
	return _create_air_actor(type, owner, cell, facing)


func land(u, cell: Vector2i) -> void:
	if is_dead(u) or not world.sim.has_method("order_land"):
		return
	_mark_ordered(u)
	world.sim.order_land(PackedInt32Array([u.id]), cell.x, cell.y)


func _create_air_actor(type: String, owner: int, cell: Vector2i, facing: int = -1):
	var base := base_type(type)
	if not world.types.has(base) or not world.type_ids.has(base):
		return null
	if not world.types[base].get("aircraft", false):
		return create_actor(base, owner, cell)

	var u = world.spawn_unit(base, owner, cell, facing, 100, true)
	if u != null:
		_api_units[u.id] = true
	return u


func _step_transports() -> void:
	for t in _transports.duplicate():
		var u = t["u"]
		if is_dead(u):
			_transports.erase(t)
			continue
		if t["wait"] > 0:
			t["wait"] -= 1
			continue
		match t["state"]:
			0:
				if t["i"] >= t["path"].size():
					t["state"] = 1
					continue
				var goal: Vector2i = t["path"][t["i"]]
				if location(u) == goal or u.pos.distance_to(cell_center(goal)) < ProtoWorld.CELL * 1.5:
					t["i"] += 1
					continue
				if is_idle(u):
					move(u, goal)
			1:
				if t["action"].is_valid():
					t["state"] = 2
					t["action"].call(u, t["cargo"])
				elif t["cargo"].is_empty():
					t["state"] = 2
				elif world.sim.has_method("can_unload") and not world.sim.can_unload(u.id):


					t["tries"] = int(t.get("tries", 0)) + 1
					t["wait"] = 5
					if t["tries"] % 20 == 0 and not t["path"].is_empty():
						move(u, t["path"][t["path"].size() - 1])
					if t["tries"] == 200:
						push_warning("Transport %s kommt am Absetzpunkt %s nicht zum Entladen" % [
								u.type, t["path"][t["path"].size() - 1] if not t["path"].is_empty() else "?"])
				else:
					t["state"] = 2
					world.sim.order_unload(PackedInt32Array([u.id]))
					t["wait"] = 25
			2:
				if world.sim.cargo_weight(u.id) > 0:
					continue
				t["state"] = 3
				if t["exit_cb"].is_valid():
					t["exit_cb"].call(u)
					_transports.erase(t)
				elif t["exit"].is_empty():
					_transports.erase(t)
				else:
					for k in t["exit"].size():
						move(u, t["exit"][k], k > 0)
					_leaving.append(u)
					_transports.erase(t)
	for u in _leaving.duplicate():
		if is_dead(u):
			_leaving.erase(u)
			continue
		var c := location(u)
		if c.x < -1 or c.y < -1 or c.x > world.map_w or c.y > world.map_h:
			_leaving.erase(u)
			world.sim.remove_actor(u.id)


func tick() -> void:

	if world.units.size() > _last_units_count:
		for i in range(_last_units_count, world.units.size()):
			var u: ProtoWorld.Unit = world.units[i]
			for t in _on_added:
				if t[0] == u.type and (t[1] < 0 or t[1] == u.player):
					_call_cb(t[2], [u])
			if _api_units.has(u.id):
				continue
			for b in _builds:
				if b[0] == u.player and b[1].has(u.type):
					b[1].erase(u.type)
					b[2].append(u)
					break
		_last_units_count = world.units.size()
	_step_transports()
	for b in _builds.duplicate():
		if b[1].is_empty():
			_builds.erase(b)
			b[3].call(b[2])


	var fire: Array = []
	for d in _delays:
		d[0] -= 1
		if d[0] <= 0:
			fire.append(d)
	for d in fire:
		_delays.erase(d)
		d[1].call()


	if time_limit > 0:
		time_left -= 1
		for m in [1, 2, 3, 4, 5, 10]:
			if time_left == m * 1500 and not _time_warn.has(m) and time_notification != "":
				_time_warn[m] = true
				display_message(time_notification.replace("{0}", str(m)).replace("{1}", "s" if m > 1 else ""))
		if time_left <= 0:
			time_limit = 0
			var cbs := _on_timer_expired.duplicate()
			for cb in cbs:
				cb.call()


	var ws := int(sim.win_state(0))
	if ws != 0 and _win_seen == 0:
		_win_seen = ws
		for cb in (_on_won if ws == WIN_WON else _on_lost).duplicate():
			cb.call()


	for w in _walkers.duplicate():
		if _walker_step(w):
			_walkers.erase(w)


	for t in _on_killed:
		if not t[2] and not t[0].alive:
			t[2] = true
			if not t[0].selling:
				_call_cb(t[1], [t[0], _guess_attacker(t[0])])
	for t in _on_all_killed:
		if t[2]:
			continue
		var all_dead := true
		for u in t[0]:
			if u != null and u.alive:
				all_dead = false
				break
		if all_dead and not t[0].is_empty():
			t[2] = true
			t[1].call()
	for t in _on_any_killed:
		if t[2]:
			continue
		for u in t[0]:
			if u != null and not u.alive and not u.selling:
				t[2] = true
				_call_cb(t[1], [u, _guess_attacker(u)])
				break
	for t in _on_removed:
		if t[2]:
			continue
		var all_gone := true
		for u in t[0]:
			if u != null and u.alive:
				all_gone = false
		if all_gone and not t[0].is_empty():
			t[2] = true
			t[1].call()

	for t in _on_all_gone:
		if t[3]:
			continue
		var all_gone2 := true
		for i in t[0].size():
			var u = t[0][i]
			if u != null and u.alive and u.player == t[1][i]:
				all_gone2 = false
				break
		if all_gone2 and not t[0].is_empty():
			t[3] = true
			t[2].call()

	for t in _on_damaged:
		if t[0].alive and t[0].hp < t[2] - 0.0005:
			var dmg := int(round((t[2] - t[0].hp) * max_health(t[0])))
			t[2] = t[0].hp
			_call_cb(t[1], [t[0], _guess_attacker(t[0]), dmg])
		elif t[0].alive:
			t[2] = t[0].hp
	for t in _on_removed_one:
		if not t[2] and not t[0].alive:
			t[2] = true
			_call_cb(t[1], [t[0]])

	for t in _on_capture:
		if t[0].alive and t[0].player != t[2]:
			var old_owner: int = t[2]
			t[2] = t[0].player
			_call_cb(t[1], [t[0], null, old_owner, t[0].player])

	if sim != null and sim.has_method("infiltrated_count"):
		for t in _on_infiltrated:
			if not t[0].alive:
				continue
			var n: int = sim.infiltrated_count(t[0].id)
			if n > t[2]:
				t[2] = n
				_call_cb(t[1], [t[0], actor_by_id(sim.infiltrated_by(t[0].id))])
	for t in _on_sold:
		if not t[2] and t[0].selling:
			t[2] = true
			_call_cb(t[1], [t[0]])


	for t in _on_idle:
		var u = t[0]
		if not u.alive:
			continue
		if is_idle(u):
			_call_cb(t[1], [u])
	for id in _hunters.keys():
		var u := _find(id)
		if u == null or not u.alive:
			_hunters.erase(id)
		elif is_idle(u):
			_hunt_step(u)

	for id in _footprints.keys():
		var f: Dictionary = _footprints[id]
		for u in world.units:
			if not u.alive or world.types[u.type].get("building", false):
				continue
			var inside: bool = f["cells"].has(location(u))
			var was: bool = f["inside"].get(u.id, false)
			if inside and not was:
				f["inside"][u.id] = true
				_call_cb(f["cb"], [u, id])
				if not _footprints.has(id):
					break
			elif not inside and was:
				f["inside"].erase(u.id)
	for id in _proximity.keys():
		var p: Dictionary = _proximity[id]
		for u in world.units:
			if not u.alive:
				continue
			var inside: bool = u.pos.distance_to(p["pos"]) <= p["range"]
			var was: bool = p["inside"].get(u.id, false)
			if inside and not was:
				p["inside"][u.id] = true
				if not p["exit"]:
					_call_cb(p["cb"], [u, id])
					if not _proximity.has(id):
						break
			elif not inside and was:
				p["inside"].erase(u.id)
				if p["exit"]:
					_call_cb(p["cb"], [u, id])
					if not _proximity.has(id):
						break


func _find(id: int) -> ProtoWorld.Unit:
	for u in world.units:
		if u.id == id:
			return u
	return null
