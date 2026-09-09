

extends RefCounted


const OP_MOVE := 0
const OP_ATTACK_MOVE := 1
const OP_ATTACK := 2
const OP_ATTACK_CELL := 3
const OP_STOP := 4
const OP_SCATTER := 5
const OP_GUARD := 6
const OP_HARVEST := 7
const OP_DELIVER := 8
const OP_DEPLOY := 9
const OP_ENTER := 10
const OP_CAPTURE := 11
const OP_DEMOLISH := 12
const OP_INFILTRATE := 13
const OP_DISGUISE := 14
const OP_ENTER_TRANSPORT := 15
const OP_UNLOAD := 16
const OP_LAY_MINE := 17
const OP_DETONATE := 18
const OP_CHRONO := 19
const OP_REPAIR := 20
const OP_RESUPPLY := 21
const OP_LAND := 22
const OP_PARADROP := 23
const OP_SET_STANCE := 24

const OP_QUEUE_BUILD := 30
const OP_CANCEL_BUILD := 31
const OP_PAUSE_BUILD := 32
const OP_PLACE_BUILDING := 33
const OP_SELL := 34
const OP_TOGGLE_REPAIR := 35
const OP_SET_RALLY := 36
const OP_SET_PRIMARY := 37

const OP_SUPPORT_POWER := 40
const OP_SURRENDER := 50


const HEAD := 6


const NAMES := {
	0: "move", 1: "attack_move", 2: "attack", 3: "attack_cell", 4: "stop", 5: "scatter",
	6: "guard", 7: "harvest", 8: "deliver", 9: "deploy", 10: "enter", 11: "capture",
	12: "demolish", 13: "infiltrate", 14: "disguise", 15: "enter_transport", 16: "unload",
	17: "lay_mine", 18: "detonate", 19: "chrono", 20: "repair", 21: "resupply", 22: "land",
	23: "paradrop", 24: "set_stance", 30: "queue_build", 31: "cancel_build", 32: "pause_build",
	33: "place_building", 34: "sell", 35: "toggle_repair", 36: "set_rally", 37: "set_primary",
	40: "support_power", 50: "surrender",
}


static func make(op: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0,
		ids: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var cmd := PackedInt32Array([op, a, b, c, d, ids.size()])
	cmd.append_array(ids)
	return cmd


static func make_one(op: int, id: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0) -> PackedInt32Array:
	return make(op, a, b, c, d, PackedInt32Array([id]))


static func op_of(cmd: PackedInt32Array) -> int:
	return int(cmd[0]) if cmd.size() >= HEAD else -1


static func ids_of(cmd: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if cmd.size() < HEAD:
		return out
	var n := mini(int(cmd[5]), cmd.size() - HEAD)
	for i in n:
		out.append(int(cmd[HEAD + i]))
	return out


static func valid(cmd: PackedInt32Array) -> bool:
	if cmd.size() < HEAD:
		return false
	if not NAMES.has(int(cmd[0])):
		return false
	var n := int(cmd[5])
	return n >= 0 and cmd.size() == HEAD + n


static func to_array(cmd: PackedInt32Array) -> Array:
	var out: Array = []
	for v in cmd:
		out.append(int(v))
	return out


static func from_array(a) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not (a is Array):
		return out
	for v in a:
		out.append(int(v))
	return out


static func apply(sim, player: int, cmd: PackedInt32Array):
	if sim == null or not valid(cmd):
		return false

	if sim.has_method("apply_order"):
		return sim.apply_order(player, cmd)
	return _apply_legacy(sim, player, cmd)


static func _apply_legacy(sim, player: int, cmd: PackedInt32Array):
	var op := int(cmd[0])
	var a := int(cmd[1])
	var b := int(cmd[2])
	var c := int(cmd[3])
	var d := int(cmd[4])
	var ids := ids_of(cmd)
	var one := int(ids[0]) if ids.size() > 0 else -1
	match op:
		OP_MOVE:
			if ids.size() > 0:
				sim.order_move(ids, a, b, c != 0)
		OP_ATTACK_MOVE:
			if ids.size() > 0:
				sim.order_attack_move(ids, a, b, c != 0)
		OP_ATTACK:
			if ids.size() > 0:
				sim.order_attack(ids, a, b != 0, c != 0)
		OP_ATTACK_CELL:
			if ids.size() > 0 and sim.has_method("order_attack_cell"):
				sim.order_attack_cell(ids, a, b)
		OP_STOP:
			if ids.size() > 0:
				sim.order_stop(ids)
		OP_SCATTER:
			if ids.size() > 0:
				sim.order_scatter(ids)
		OP_GUARD:
			if ids.size() > 0 and sim.has_method("order_guard"):
				sim.order_guard(ids, a, b != 0)
		OP_HARVEST:
			if ids.size() > 0:
				sim.order_harvest(ids, a, b)
		OP_DELIVER:
			if ids.size() > 0 and sim.has_method("order_deliver"):
				sim.order_deliver(ids, a)
		OP_DEPLOY:
			if ids.size() > 0:
				sim.order_deploy(ids)
		OP_ENTER:
			if ids.size() > 0:
				sim.order_enter(ids, a)
		OP_CAPTURE:
			if ids.size() > 0:
				sim.order_capture(ids, a)
		OP_DEMOLISH:
			if ids.size() > 0:
				sim.order_demolish(ids, a)
		OP_INFILTRATE:
			if ids.size() > 0:
				sim.order_infiltrate(ids, a)
		OP_DISGUISE:
			if one >= 0 and sim.has_method("order_disguise"):
				return sim.order_disguise(one, a)
		OP_ENTER_TRANSPORT:
			if ids.size() > 0 and sim.has_method("order_enter_transport"):
				sim.order_enter_transport(ids, a)
		OP_UNLOAD:
			if ids.size() > 0 and sim.has_method("order_unload"):
				sim.order_unload(ids)
		OP_LAY_MINE:
			if ids.size() > 0:
				sim.order_lay_mine(ids)
		OP_DETONATE:
			if ids.size() > 0:
				sim.order_detonate(ids)
		OP_CHRONO:
			if ids.size() > 0:
				return sim.order_chrono(ids, a, b)
		OP_REPAIR:
			if ids.size() > 0:
				sim.order_repair(ids, a)
		OP_RESUPPLY:
			if ids.size() > 0 and sim.has_method("order_resupply"):
				sim.order_resupply(ids, a)
		OP_LAND:
			if ids.size() > 0 and sim.has_method("order_land"):
				sim.order_land(ids, a, b)
		OP_PARADROP:
			if one >= 0:
				sim.order_paradrop(one, a, b)
		OP_SET_STANCE:
			if one >= 0:
				sim.set_stance(one, a)
		OP_QUEUE_BUILD:
			return sim.queue_build(player, a)
		OP_CANCEL_BUILD:
			sim.cancel_build(player, a, b)
		OP_PAUSE_BUILD:
			sim.pause_build(player, a, b != 0)
		OP_PLACE_BUILDING:
			return sim.place_building(player, a, b, c)
		OP_SELL:
			if one >= 0:
				return sim.sell(one)
		OP_TOGGLE_REPAIR:
			if one >= 0:
				return sim.toggle_repair(one)
		OP_SET_RALLY:
			if one >= 0:
				return sim.set_rally(one, a, b)
		OP_SET_PRIMARY:
			if one >= 0:
				return sim.set_primary(one)
		OP_SUPPORT_POWER:

			var x2 := -1
			var y2 := -1
			if d >= 0:
				x2 = (d >> 16) & 0xFFFF
				y2 = d & 0xFFFF
			return sim.activate_support_power(player, a, b, c, x2, y2)
		OP_SURRENDER:

			if sim.has_method("set_win_state"):
				sim.set_win_state(player, 2)
			return true
	return true


static func pack_cell2(x: int, y: int) -> int:
	if x < 0 or y < 0:
		return -1
	return ((x & 0xFFFF) << 16) | (y & 0xFFFF)
