

extends Node

const NetClient := preload("res://scripts/net/net_client.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const OrderLog := preload("res://scripts/net/order_log.gd")
const NetNotify := preload("res://scripts/net/net_notify.gd")
const VoiceChat := preload("res://scripts/net/voice_chat.gd")


const SIM_SEATS := [0, 1, 4, 5, 6, 7, 8, 9]


const STRATEGIES := ["normal", "rush", "turtle", "air", "naval"]
const MAX_SEATS := 6

signal lobby_changed(data: Dictionary)
signal chat_added(line: Dictionary)
signal state_changed(what: String)
signal rooms_listed(rooms: Array)

var client = null
var session = null
var voice = null
var code := ""
var host := false
var host_seat := -1
var my_seat := -1
var map_slug := ""
var seats_total := 0
var room_public := false
var lobby: Dictionary = {}
var settings: Dictionary = {}
var chat: Array = []
var setup: Dictionary = {}
var last_error := ""
var in_game := false
var quick_keys := ["#attack", "#help", "#yes", "#no", "#wait", "#gg"]


var token := ""
var reconnecting := false

var notify = null
var _app_paused := false
var _known_seats := {}


static func hub() -> Node:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	var root := (ml as SceneTree).root
	var n := root.get_node_or_null("Net")
	if n != null:
		return n
	n = (load("res://scripts/net/net_hub.gd") as GDScript).new()
	n.name = "Net"
	root.add_child(n)
	return n


func ensure_voice() -> Node:
	if voice == null:
		voice = VoiceChat.new()
		voice.name = "VoiceChat"
		add_child(voice)
	return voice


func active() -> bool:
	return in_game and session != null


func connect_server(url: String = "", player_name: String = "") -> void:
	if client != null:
		client.stop(false)
		client.queue_free()
	client = NetClient.new()
	client.name = "NetClient"
	add_child(client)
	client.created.connect(_on_created)
	client.lobby_changed.connect(_on_lobby)
	client.started.connect(_on_started)
	client.chat_line.connect(_on_chat)
	client.server_error.connect(_on_error)
	client.closed.connect(_on_closed)
	client.rooms_listed.connect(func(rooms: Array): rooms_listed.emit(rooms))
	client.session_ready.connect(_on_session)
	client.reconnecting.connect(_on_reconnecting)
	client.resumed.connect(_on_resumed)

	ensure_voice().client = client
	client.voice_packet.connect(voice.on_packet)
	client.start(url, player_name)


func when_open(fn: Callable) -> void:
	if client != null and client.connected():
		fn.call()
		return
	if client == null:
		connect_server("", NetClient.configured_name())
	client.opened.connect(fn, CONNECT_ONE_SHOT)


func browse_refresh() -> void:
	when_open(func():
		if client != null:
			client.list_rooms())


func leave() -> void:
	_stop_watch()
	if voice != null:
		voice.shutdown()
		voice.client = null
	if session != null:
		session.stop()
		session = null
	if client != null:
		client.stop()
		client.queue_free()
		client = null
	code = ""
	host = false
	my_seat = -1
	room_public = false
	token = ""
	reconnecting = false
	lobby = {}
	chat = []
	setup = {}
	in_game = false
	_known_seats = {}


func seat_name(seat: int) -> String:
	if session != null:
		var n: String = session.name_of_seat(seat)
		if n != "?":
			return n
	for c in lobby.get("clients", []):
		if int(c.get("seat", -1)) == seat:
			return str(c.get("name", "?"))
	return "?"


func other_human_seats() -> Array:
	var out: Array = []
	if session != null:
		for s in session.seats:
			if str(s.get("kind", "human")) == "human" and int(s.get("seat", -1)) != my_seat:
				out.append(int(s.get("seat", -1)))
	else:
		for c in lobby.get("clients", []):
			if str(c.get("kind", "human")) == "human" and int(c.get("seat", -1)) != my_seat:
				out.append(int(c.get("seat", -1)))
	out.sort()
	return out


func send_chat(text: String, scope: String = "all") -> void:
	if client != null and text.strip_edges() != "":
		client.send_chat(text.strip_edges(), scope)


static func quick_text(key: String) -> String:
	return TranslationServer.translate("chat.quick." + key.substr(1))


static func display_text(line: Dictionary) -> String:
	var t := str(line.get("text", ""))
	if t.begins_with("#"):
		var q := quick_text(t)
		if q != "chat.quick." + t.substr(1):
			t = q
	if str(line.get("scope", "all")) == "team":
		t = "[%s] %s" % [TranslationServer.translate("chat.team"), t]
	return t


func _on_created(new_code: String, seats: int) -> void:
	code = new_code
	host = true
	seats_total = seats
	state_changed.emit("created")


func _on_session(new_code: String, seat: int, new_token: String) -> void:
	code = new_code
	token = new_token
	my_seat = seat
	reconnecting = false
	_start_watch()
	state_changed.emit("session")


func _on_reconnecting(tries: int, _max_tries: int) -> void:
	if reconnecting and tries > 1:
		return
	reconnecting = true
	state_changed.emit("reconnecting")


func _on_resumed(_seat: int) -> void:
	reconnecting = false
	state_changed.emit("resumed")


func _start_watch() -> void:
	if notify == null:
		notify = NetNotify.new()
	if code == "" or token == "" or client == null:
		return


	if not NetNotify.enabled():
		notify.stop_watch()
		return
	notify.start_watch(client.url, code, token, _room_title())


func _stop_watch() -> void:
	if notify != null:
		notify.stop_watch()


func refresh_watch() -> void:
	if in_game or code == "" or not NetNotify.enabled():
		_stop_watch()
		return
	_start_watch()


func _room_title() -> String:
	var title := str(lobby.get("map_name", ""))
	return title if title != "" else str(map_slug)


func _local_notify(title: String, text: String, what: String) -> void:
	if notify != null and _app_paused and NetNotify.event_enabled(what):
		notify.show(title, text)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_app_paused = true
		NOTIFICATION_APPLICATION_RESUMED:
			_app_paused = false


func _on_lobby(d: Dictionary) -> void:

	var seen := {}
	for c in d.get("clients", []):
		var cid := str(c.get("client_id", ""))
		if cid == "" or bool(c.get("absent", false)):
			continue
		seen[cid] = str(c.get("name", "?"))
		if not _known_seats.has(cid) and not _known_seats.is_empty() and cid != _my_client_id():
			_local_notify(_room_title(), tr("mp.notify_join") % seen[cid], "join")
	_known_seats = seen
	lobby = d
	code = str(d.get("code", code))
	host_seat = int(d.get("host_seat", -1))
	seats_total = int(d.get("seats_total", seats_total))
	room_public = bool(d.get("public", room_public))
	map_slug = str(d.get("map", map_slug))
	var st = d.get("settings", {})
	if st is Dictionary and not st.is_empty():
		settings = st
	for c in d.get("clients", []):
		if str(c.get("client_id", "")) == client.client_id:
			my_seat = int(c.get("seat", -1))
	host = my_seat >= 0 and my_seat == host_seat
	lobby_changed.emit(d)
	state_changed.emit("joined")


func _on_started(new_setup: Dictionary) -> void:
	setup = new_setup
	in_game = true
	session = NetSession.new()
	session.client = client
	session.log_writer = OrderLog.new()
	session.setup_from(new_setup, my_seat)

	client.reconnect_in_lobby = false
	client.frame_ready.connect(session.on_frame)
	client.waiting_for.connect(session.on_waiting)
	client.peer_left.connect(func(seat, _f, _r): session.on_peer_left(seat))
	client.desync.connect(session.on_desync)

	_stop_watch()
	state_changed.emit("started")


func _my_client_id() -> String:
	return str(client.client_id) if client != null else ""


func _on_chat(line: Dictionary) -> void:
	chat.append(line)
	if chat.size() > 200:
		chat.remove_at(0)
	if int(line.get("seat", -1)) != my_seat:
		_local_notify(str(line.get("name", "?")), display_text(line), "chat")
	chat_added.emit(line)


func _on_error(codename: String, text: String) -> void:
	last_error = codename if text == "" else "%s: %s" % [codename, text]
	state_changed.emit("error")


func _on_closed(reason: String) -> void:
	last_error = reason
	state_changed.emit("closed")


static func map_sha256(slug: String) -> String:
	var path := ContentPaths.maps_dir().path_join("%s.json" % slug)
	if not FileAccess.file_exists(path):
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


static func map_json(slug: String) -> Dictionary:
	var path := ContentPaths.maps_dir().path_join("%s.json" % slug)
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func map_seats(slug: String) -> Array:
	var d := map_json(slug)
	var spawns: Array = d.get("spawns", [])
	var total := maxi(spawns.size(), 2)
	return [total, mini(total, MAX_SEATS)]


func build_setup(slug: String, clients: Array, room_settings: Dictionary) -> Dictionary:
	var data := map_json(slug)
	var spawns: Array = data.get("spawns", [])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_value := int(rng.seed & 0x7FFFFFFF)
	rng.seed = seed_value
	var starting_units := str(room_settings.get("starting_units", "none"))
	var taken: Array = []
	var free: Array = []
	for i in spawns.size():
		free.append(i)
	var out_seats: Array = []
	var vis: Array = []
	var used_sim: Array = []
	for c in clients:
		if out_seats.size() >= MAX_SEATS:
			break
		var seat := int(c.get("seat", out_seats.size()))
		var sim_index: int = SIM_SEATS[out_seats.size()]
		used_sim.append(sim_index)


		var want := int(c.get("spawn", -1))
		var k := free.find(want)
		if k < 0:
			k = _pick_spawn(spawns, free, taken, rng)
		var spawn_index := 0
		if k >= 0 and k < free.size():
			spawn_index = free[k]
			free.remove_at(k)
		var cell: Array = spawns[spawn_index] if spawn_index < spawns.size() else [8, 8]
		taken.append(Vector2i(int(cell[0]), int(cell[1])))
		var faction := str(c.get("faction", "random"))
		if faction == "random" or faction == "":
			faction = "allies" if rng.randi() % 2 == 0 else "soviet"
		var kind := str(c.get("kind", "human"))
		var entry := {
			"seat": seat, "sim": sim_index, "kind": kind,
			"client": str(c.get("client_id", "")), "name": str(c.get("name", "")),
			"faction": faction, "team": int(c.get("team", 0)), "color": int(c.get("color", out_seats.size())),
			"spawn": spawn_index, "spawn_cell": [int(cell[0]), int(cell[1])],
			"start_units": _start_units(faction, starting_units, Vector2i(int(cell[0]), int(cell[1])), rng),
		}
		if kind == "bot":
			entry["level"] = str(c.get("level", "normal"))


			var strat := str(c.get("strategy", "normal"))
			if strat == "random" or strat == "" or not STRATEGIES.has(strat):
				strat = STRATEGIES[rng.randi() % (STRATEGIES.size())]
			entry["strategy"] = strat
		out_seats.append(entry)

		if kind == "human":
			vis.append(sim_index)
	var alliances: Array = []
	for i in out_seats.size():
		for j in range(i + 1, out_seats.size()):
			var ti := int(out_seats[i].get("team", 0))
			var tj := int(out_seats[j].get("team", 0))
			if ti > 0 and ti == tj:
				alliances.append([int(out_seats[i]["sim"]), int(out_seats[j]["sim"])])
	return {
		"map": slug, "map_sha256": map_sha256(slug), "seed": seed_value,
		"tick_ms": 40, "net_frame_ticks": 2, "order_latency": 3, "sync_every": 10,
		"credits": int(room_settings.get("credits", 5000)),
		"starting_units": starting_units,
		"crates": bool(room_settings.get("crates", true)),
		"explored_map": bool(room_settings.get("explored_map", false)),
		"fog": bool(room_settings.get("fog", true)),
		"conquest_victory": true,
		"seats": out_seats, "alliances": alliances, "visibility_players": vis,
		"code": code,
	}


func _pick_spawn(spawns: Array, free: Array, taken: Array, rng: RandomNumberGenerator) -> int:
	if free.is_empty():
		return -1
	if taken.is_empty():
		return rng.randi_range(0, free.size() - 1)
	var best := 0
	var best_d := -1.0
	for i in free.size():
		var sp: Array = spawns[int(free[i])]
		var p := Vector2(float(sp[0]), float(sp[1]))
		var d := 0.0
		for t in taken:
			d += p.distance_squared_to(Vector2(t))
		if d > best_d:
			best_d = d
			best = i
	return best


func _start_units(faction: String, mode: String, cell: Vector2i, rng: RandomNumberGenerator) -> Array:
	var out: Array = [{"type": "mcv", "cell": [cell.x, cell.y], "facing": -1}]
	var support: Array = ProtoWorld.STARTING_UNITS.get(mode, {}).get(faction, [])
	var used := {cell: true}
	for type in support:
		for _try in 40:
			var r := rng.randf_range(4.0, 5.0)
			var ang := rng.randf() * TAU
			var c := cell + Vector2i(int(round(cos(ang) * r)), int(round(sin(ang) * r)))
			if used.has(c):
				continue
			used[c] = true
			out.append({"type": type, "cell": [c.x, c.y], "facing": -1})
			break
	return out
