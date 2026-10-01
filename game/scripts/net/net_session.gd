

extends RefCounted

const NetOrders := preload("res://scripts/net/net_orders.gd")


const NET_FRAME_TICKS := 2
const ORDER_LATENCY := 3
const SYNC_EVERY := 10
const TICK_MS := 40
const TICK_LEN := TICK_MS / 1000.0


const WAIT_HINT := 0.5

const MAX_CATCHUP := 8

signal waiting_changed(on: bool, seats: Array)
signal desynced(frame: int, hashes: Dictionary)
signal frame_done(frame: int, tick: int, hash_text: String)

var client = null
var sim = null
var log_writer = null


var setup: Dictionary = {}
var seats: Array = []
var local_seat := 0
var local_sim := 0
var alive_seats: Array = []

var frame := 0
var waiting := false
var waiting_seats: Array = []
var last_hash := ""
var running := false

var _next_send := 0
var _pending: Array = []
var _buffer := {}
var _ticks_left := 0
var _accum := 0.0
var _wait_since := -1.0
var _dead := false


func setup_from(new_setup: Dictionary, my_seat: int) -> void:
	setup = new_setup
	seats = new_setup.get("seats", [])
	local_seat = my_seat
	local_sim = 0
	alive_seats = []
	for s in seats:
		if int(s.get("seat", -1)) == my_seat:
			local_sim = int(s.get("sim", 0))

		if str(s.get("kind", "human")) == "human":
			alive_seats.append(int(s.get("seat", -1)))
	alive_seats.sort()


func begin() -> void:
	frame = 0
	_next_send = 0
	_ticks_left = 0
	_accum = 0.0
	running = true
	_dead = false
	for i in ORDER_LATENCY:
		_send_orders([])
	if log_writer != null:
		log_writer.begin(str(setup.get("code", "")), setup)


func stop() -> void:
	running = false
	if log_writer != null:
		log_writer.close()


func queue(cmd: PackedInt32Array) -> void:
	if _dead:
		return
	_pending.append(NetOrders.to_array(cmd))


func on_frame(f: int, packets: Array) -> void:
	_buffer[f] = packets


func on_waiting(f: int, wseats: Array) -> void:
	if f == frame:
		_set_waiting(true, wseats)


func on_peer_left(seat: int) -> void:
	alive_seats.erase(seat)
	if log_writer != null:
		log_writer.note("peer_left seat %d bei Rahmen %d" % [seat, frame])


func on_desync(f: int, hashes: Dictionary) -> void:
	_dead = true
	running = false
	desynced.emit(f, hashes)
	if log_writer != null:
		log_writer.note("desync bei Rahmen %d: %s" % [f, JSON.stringify(hashes)])
		log_writer.close()


func drop(reason: String) -> void:
	_dead = true
	running = false
	if log_writer != null:
		log_writer.note("abgebrochen: " + reason)
		log_writer.close()


func alpha() -> float:
	return clampf(_accum / TICK_LEN, 0.0, 1.0)


func lag_frames() -> int:

	var n := 0
	for f in _buffer:
		if int(f) >= frame:
			n += 1
	return n


func pump(delta: float) -> int:
	if not running or sim == null or _dead:
		return 0
	_accum += delta
	var steps := 0
	while _accum >= TICK_LEN and steps < MAX_CATCHUP:
		if _ticks_left <= 0:
			if not _begin_frame():
				break
		sim.step()
		_ticks_left -= 1
		_accum -= TICK_LEN
		steps += 1

	if _ticks_left <= 0 and not _buffer.has(frame):
		_accum = minf(_accum, TICK_LEN)
	return steps


func _begin_frame() -> bool:
	if not _buffer.has(frame):
		if _wait_since < 0.0:
			_wait_since = Time.get_ticks_msec() / 1000.0
		elif Time.get_ticks_msec() / 1000.0 - _wait_since >= WAIT_HINT and not waiting:
			_set_waiting(true, _missing_seats())
		return false
	_wait_since = -1.0
	if waiting:
		_set_waiting(false, [])
	var packets: Array = _buffer[frame]
	_buffer.erase(frame)

	packets.sort_custom(func(a, b): return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	for p in packets:
		var seat := int(p.get("seat", -1))
		var player := _sim_of_seat(seat)
		if player < 0:
			continue
		for c in p.get("cmds", []):
			NetOrders.apply(sim, player, NetOrders.from_array(c))

	var hash_text := ""
	if frame % SYNC_EVERY == 0 and sim.has_method("state_hash"):
		hash_text = str(sim.state_hash())
		last_hash = hash_text
	_send_orders(_pending, hash_text)
	_pending = []
	if log_writer != null:
		log_writer.frame(frame, int(sim.tick()), packets, hash_text)
	frame_done.emit(frame, int(sim.tick()), hash_text)
	frame += 1
	_ticks_left = NET_FRAME_TICKS
	return true


func _send_orders(cmds: Array, hash_text: String = "") -> void:
	if client != null:
		client.send_order(_next_send, cmds, hash_text)
	_next_send += 1


func _sim_of_seat(seat: int) -> int:
	for s in seats:
		if int(s.get("seat", -1)) == seat:
			return int(s.get("sim", -1))
	return -1


func name_of_seat(seat: int) -> String:
	for s in seats:
		if int(s.get("seat", -1)) == seat:
			return str(s.get("name", "?"))
	return "?"


func _missing_seats() -> Array:


	var out: Array = []
	for s in alive_seats:
		if int(s) != local_seat:
			out.append(int(s))
	return out


func _set_waiting(on: bool, wseats: Array) -> void:
	if waiting == on and wseats == waiting_seats:
		return
	waiting = on
	waiting_seats = wseats
	waiting_changed.emit(on, wseats)
