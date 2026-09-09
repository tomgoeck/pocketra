

extends Node

signal opened()
signal welcomed(client_id: String, server: String)
signal created(code: String, seats: int)
signal lobby_changed(data: Dictionary)
signal started(setup: Dictionary)
signal frame_ready(frame: int, packets: Array)
signal waiting_for(frame: int, seats: Array)
signal chat_line(line: Dictionary)
signal voice_packet(line: Dictionary)
signal desync(frame: int, hashes: Dictionary)
signal peer_left(seat: int, frame: int, reason: String)
signal rooms_listed(rooms: Array)
signal server_error(code: String, text: String)
signal closed(reason: String)
signal ping_changed(ms: int)
signal session_ready(code: String, seat: int, token: String)
signal reconnecting(tries: int, max_tries: int)
signal resumed(seat: int)

const DEFAULT_URL := "wss://pocketra.net/mp"
const PROTO := 1


const RECONNECT_TRIES := 90
const RECONNECT_DELAY := 2.0

const PING_EVERY := 2.0

enum St { OFFLINE, CONNECTING, OPEN, CLOSED }

var url := DEFAULT_URL
var player_name := ""
var state: int = St.OFFLINE
var client_id := ""
var server_name := ""
var ping_ms := -1


var reconnect_in_lobby := true
var last_error := ""

var resume_code := ""
var resume_token := ""
var resume_s := 0
var my_seat := -1

var reconnect_active := false

var _ws: WebSocketPeer = null
var _tries := 0
var _retry_at := 0.0
var _ping_at := 0.0
var _ping_id := 0
var _ping_sent := {}
var _queue: Array = []
var _log_frames := false
var _paused_at := 0
var _resume_pending := false


func _ready() -> void:
	set_process(true)
	_log_frames = OS.get_cmdline_user_args().has("--mp-log")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_paused_at = Time.get_ticks_msec()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _paused_at == 0:
				return
			_paused_at = 0
			wake()


func wake() -> void:
	_tries = 0
	_retry_at = 0.0
	if _ws == null and state != St.OFFLINE and (reconnect_in_lobby or resume_token != ""):
		state = St.CLOSED
		_open()
	elif state == St.OPEN:
		_ping_at = 0.0


static func configured_url() -> String:
	var args := OS.get_cmdline_user_args()
	for flag in ["--mp-url", "--mp"]:
		var k := args.find(flag)
		if k >= 0 and k + 1 < args.size() and not args[k + 1].begins_with("--"):
			return args[k + 1]
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var u := str(cfg.get_value("multiplayer", "url", ""))
		if u != "":
			return u
	return DEFAULT_URL


static func configured_name() -> String:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--mp-name")
	if k >= 0 and k + 1 < args.size():
		return args[k + 1]
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var n := str(cfg.get_value("multiplayer", "name", ""))
		if n != "":
			return n
	return device_name()


static func device_name() -> String:
	var n := OS.get_model_name()
	if n == "" or n == "GenericDevice":
		n = OS.get_name()
	return n.substr(0, 24)


static func save_name(n: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("multiplayer", "name", n.substr(0, 24))
	cfg.save("user://settings.cfg")


func start(target_url: String = "", name_for_room: String = "") -> void:
	url = target_url if target_url != "" else configured_url()
	player_name = name_for_room if name_for_room != "" else configured_name()
	_tries = 0
	_open()


func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err != OK:


		state = St.CLOSED
		last_error = "connect %d" % err
		_retry_at = RECONNECT_DELAY
		if reconnect_in_lobby and _tries < RECONNECT_TRIES:
			reconnect_active = true
			reconnecting.emit(_tries + 1, RECONNECT_TRIES)
		else:
			reconnect_active = false
			closed.emit(last_error)
		return
	state = St.CONNECTING


func connected() -> bool:
	return state == St.OPEN


func stop(send_leave: bool = true) -> void:
	if state == St.OPEN and send_leave:
		send({"t": "leave"})
		_ws.poll()
	reconnect_in_lobby = false


	resume_code = ""
	resume_token = ""
	reconnect_active = false
	if _ws != null:
		_ws.close()
	state = St.OFFLINE
	_ws = null


func send(msg: Dictionary) -> void:
	if _log_frames:
		print("MP →: ", JSON.stringify(msg))
	if state != St.OPEN or _ws == null:
		_queue.append(msg)
		return
	_ws.send_text(JSON.stringify(msg))


func hello() -> void:
	send({"t": "hello", "proto": PROTO, "name": player_name,
		"app": UpdateConfig.app_version(), "pack": _pack_version(),
		"sim": _sim_version(), "state_version": _state_version(),
		"rules_hash": _rules_hash(), "rules_format": _rules_format()})


func create_room(map_slug: String, map_sha: String, seats: int, settings: Dictionary,
		public: bool = false, map_name: String = "") -> void:
	send({"t": "create", "map": map_slug, "map_sha256": map_sha, "seats": seats,
		"settings": settings, "public": public, "map_name": map_name})


func join_room(code: String, map_sha: String = "") -> void:
	send({"t": "join", "code": code.to_upper(), "map_sha256": map_sha})


func change_map(map_slug: String, map_sha: String, seats: int, settings: Dictionary = {},
		map_name: String = "") -> void:
	var m := {"t": "map", "map": map_slug, "map_sha256": map_sha, "seats": seats,
		"map_name": map_name}
	if not settings.is_empty():
		m["settings"] = settings
	send(m)


func set_slot(faction: String, team: int, color: int, spawn: int, seat: int = -1) -> void:
	var m := {"t": "slot", "faction": faction, "team": team, "color": color, "spawn": spawn}
	if seat >= 0:
		m["seat"] = seat
	send(m)


func add_bot(level: String, faction: String, team: int) -> void:
	send({"t": "bot", "op": "add", "level": level, "faction": faction, "team": team})


func remove_bot(seat: int) -> void:
	send({"t": "bot", "op": "remove", "seat": seat})


func kick(seat: int) -> void:
	send({"t": "kick", "seat": seat})


func list_rooms() -> void:
	send({"t": "list"})


func set_visibility(public: bool) -> void:
	send({"t": "visibility", "public": public})


func set_ready(on: bool) -> void:
	send({"t": "ready", "on": on})


func start_game(setup: Dictionary) -> void:
	send({"t": "start", "setup": setup})


func send_order(frame: int, cmds: Array, hash_text: String = "") -> void:
	var m := {"t": "order", "frame": frame, "cmds": cmds}
	if hash_text != "":
		m["hash"] = hash_text
	send(m)


func send_chat(text: String, scope: String = "all") -> void:
	send({"t": "chat", "text": text.substr(0, 200), "scope": scope})


func resume_seat() -> void:
	if resume_code != "" and resume_token != "":
		_resume_pending = true
		send({"t": "resume", "code": resume_code, "token": resume_token})


func send_voice(data: String, scope: String = "team", seq: int = 0, ende: bool = false) -> bool:
	if state != St.OPEN or _ws == null:
		return false
	var m := {"t": "voice", "scope": scope, "seq": seq, "data": data}
	if ende:
		m["end"] = true
	_ws.send_text(JSON.stringify(m))
	return true


func _process(delta: float) -> void:
	if _ws == null:
		if state == St.CLOSED and reconnect_in_lobby and _tries < RECONNECT_TRIES:
			_retry_at -= delta
			if _retry_at <= 0.0:
				_tries += 1
				reconnect_active = true
				reconnecting.emit(_tries, RECONNECT_TRIES)
				_open()
		return
	_ws.poll()
	var s := _ws.get_ready_state()
	if s == WebSocketPeer.STATE_OPEN:
		if state != St.OPEN:
			state = St.OPEN
			_tries = 0


			hello()
			resume_seat()
			var pending := _queue.duplicate()
			_queue.clear()
			for m in pending:
				send(m)
			opened.emit()
		while _ws.get_available_packet_count() > 0:
			_receive(_ws.get_packet().get_string_from_utf8())
		_ping_at -= delta
		if _ping_at <= 0.0:
			_ping_at = PING_EVERY
			_ping_id += 1
			_ping_sent[_ping_id] = Time.get_ticks_msec()


			send({"t": "ping", "id": _ping_id, "rtt": maxi(ping_ms, 0)} if ping_ms >= 0
					else {"t": "ping", "id": _ping_id})
	elif s == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		state = St.CLOSED
		_retry_at = RECONNECT_DELAY
		if reconnect_in_lobby and _tries < RECONNECT_TRIES:
			last_error = "reconnect %d/%d" % [_tries + 1, RECONNECT_TRIES]
			reconnect_active = true
			reconnecting.emit(_tries + 1, RECONNECT_TRIES)
		else:
			reconnect_active = false
			closed.emit("code %d" % code)


func _receive(text: String) -> void:
	var d = JSON.parse_string(text)
	if not (d is Dictionary):
		return


	if _log_frames and str(d.get("t", "")) != "voice":
		print("MP ←: ", text)
	match str(d.get("t", "")):
		"welcome":
			client_id = str(d.get("client_id", ""))
			server_name = str(d.get("server", ""))
			welcomed.emit(client_id, server_name)
		"created":
			created.emit(str(d.get("code", "")), int(d.get("seats", 0)))
		"session":

			var was_reconnect := reconnect_active
			resume_code = str(d.get("code", ""))
			resume_token = str(d.get("token", ""))
			resume_s = int(d.get("resume_s", 0))
			my_seat = int(d.get("seat", -1))
			reconnect_active = false
			_resume_pending = false
			session_ready.emit(resume_code, my_seat, resume_token)
			if was_reconnect:
				resumed.emit(my_seat)
		"lobby":
			lobby_changed.emit(d)
		"start":
			var setup = d.get("setup", {})
			started.emit(setup if setup is Dictionary else {})
		"frame":
			var packets = d.get("packets", [])
			frame_ready.emit(int(d.get("frame", 0)), packets if packets is Array else [])
		"waiting":
			var seats = d.get("seats", [])
			waiting_for.emit(int(d.get("frame", 0)), seats if seats is Array else [])
		"chat":
			chat_line.emit(d)
		"voice":
			voice_packet.emit(d)
		"desync":
			var h = d.get("hashes", {})
			desync.emit(int(d.get("frame", 0)), h if h is Dictionary else {})
		"peer_left":
			peer_left.emit(int(d.get("seat", -1)), int(d.get("frame", 0)), str(d.get("reason", "")))
		"rooms":
			var rooms = d.get("rooms", [])
			rooms_listed.emit(rooms if rooms is Array else [])
		"pong":
			var pid := int(d.get("id", 0))
			if _ping_sent.has(pid):
				ping_ms = Time.get_ticks_msec() - int(_ping_sent[pid])
				_ping_sent.erase(pid)
				ping_changed.emit(ping_ms)
		"error":
			last_error = str(d.get("code", "error"))
			if _resume_pending:


				_resume_pending = false
				resume_code = ""
				resume_token = ""
				reconnect_in_lobby = false
				reconnect_active = false
				server_error.emit(last_error, str(d.get("text", "")))
				closed.emit(last_error)
				return
			server_error.emit(last_error, str(d.get("text", "")))


func _pack_version() -> int:
	var f := FileAccess.open("user://update/state.json", FileAccess.READ)
	if f == null:
		return 0
	var d = JSON.parse_string(f.get_as_text())
	return int(d.get("pack_version", 0)) if d is Dictionary else 0


func _sim_version() -> String:
	if not ClassDB.class_exists("RaSim"):
		return ""
	var s = ClassDB.instantiate("RaSim")
	return str(s.version())


func _state_version() -> int:
	if not ClassDB.class_exists("RaSim"):
		return 0
	var s = ClassDB.instantiate("RaSim")
	return int(s.state_version()) if s.has_method("state_version") else 0


func _rules_hash() -> String:
	if not ClassDB.class_exists("RaSim"):
		return ""
	var s = ClassDB.instantiate("RaSim")
	return str(s.rules_hash()) if s.has_method("rules_hash") else ""


func _rules_format() -> int:
	var d: Dictionary = RulesDb.data()
	return int(d.get("rules_format", 0))
