

extends Control

const GAME_SCENE := "res://scenes/gesture_proto.tscn"

const LogView := preload("res://scripts/ui/log_view.gd")


const MultiplayerPage := preload("res://scripts/menu/multiplayer_page.gd")
const MultiplayerLobby := preload("res://scripts/menu/multiplayer_lobby.gd")
const NetHub := preload("res://scripts/net/net_hub.gd")
const NetClientScript := preload("res://scripts/net/net_client.gd")
const VoiceChat := preload("res://scripts/net/voice_chat.gd")
const NetNotify := preload("res://scripts/net/net_notify.gd")
const AppLogger := preload("res://scripts/app_logger.gd")
const SETTINGS := "user://settings.cfg"


const Desktop := preload("res://scripts/desktop.gd")

var _maps: Array = []
var _skirmish: Array = []
var _missions: Array = []
var _selected := -1
var _ai_players := 1
var _credits := 5000
var _faction := "allies"
var _ai_faction := "soviet"
var _faction_btn: Button
var _ai_faction_btn: Button
var _starting_units := "none"

var _crates := true
var _crates_btn: Button


var _explored_map := false
var _explored_map_btn: Button
var _fog := true
var _fog_btn: Button

var _ai_difficulty := "normal"
var _ai_difficulty_btn: Button
var _start_btn: Button

var _root: Control
var _pages := {}
var _map_buttons: Array = []
var _preview: TextureRect
var _info: Label
var _credits_label: Label
var _ai_label: Label


func _unhandled_input(e: InputEvent) -> void:
	if Desktop.handle_fullscreen_key(e):
		get_viewport().set_input_as_handled()

		if _page == "options":
			_rebuild_ui("options")


func _ready() -> void:


	var boot_args := OS.get_cmdline_user_args()
	if boot_args.has("--notify-demo") or boot_args.has("--test-layout") \
			or boot_args.has("--test-benachrichtigungen"):
		NetNotify.force_ui = true
	_scan_maps()
	_load_settings()
	_build_ui()
	_watch_multiplayer()


	_resizer = Desktop.watch_resize(self, _on_window_resized)
	var args := OS.get_cmdline_user_args()


	_apply_lobby_args(args)


	if UpdateConfig.blocked() and not args.has("--test-layout"):
		_show("blocked")
	elif not ContentManager.available() and not args.has("--menu-screenshot") and not args.has("--test-layout"):
		_show("content")
	else:
		_show("main")
	_start_update_service(args)


	if args.has("--fake-update-line"):
		_update_text = tr("update.ready")
		_update_action = "restart"
		_refresh_update_bar()


	if Desktop.want_test_window():
		_go_test_window.call_deferred()
	var k := args.find("--menu-screenshot")
	if k >= 0 and k + 1 < args.size():
		_shot_path = args[k + 1]
		if args.has("--page-skirmish"):
			_show("skirmish")
		var pk := args.find("--page")
		if pk >= 0 and pk + 1 < args.size() and _pages.has(args[pk + 1]):
			_show(args[pk + 1])

		if args.has("--show-disclaimer") and _content_page != null:
			_show("content")
			_content_page.show_disclaimer.call_deferred()
		var sk2 := args.find("--select")
		if sk2 >= 0 and sk2 + 1 < args.size() and _mission_buttons.has(args[sk2 + 1]):

			_mission_buttons[args[sk2 + 1]].pressed.emit.call_deferred()
	var lk := args.find("--load")
	if lk >= 0 and lk + 1 < args.size():
		_start_savegame.call_deferred(args[lk + 1])
		return


	if args.has("--mp-demo-create") and _mp_page != null:
		_mp_demo_mode = "create"
		_show("multiplayer")
		_mp_page.show_mode("create")
	if args.has("--mp-demo-join") and _mp_page != null:
		_mp_demo_join()
		_mp_demo_mode = "join"
		_show("multiplayer")
		_mp_page.show_mode("join")
	if args.has("--mp-demo-lobby"):
		_mp_demo_lobby()
		_show("mp_lobby")

		_mp_demo_zoom = args.has("--mp-demo-zoom")
		_mp_demo_picker = args.has("--mp-demo-mapchange")
	_mp_shot_setup(args)
	_apply_mp_args(args)
	_cycle = args.has("--test-cycle")
	if args.has("--test-lobby"):
		_shot_manual = true
		call_deferred("_run_test_lobby")

	if args.has("--test-voice-lobby"):
		_shot_manual = true
		call_deferred("_run_test_voice_lobby")
	if args.has("--test-maps-unlock"):
		_shot_manual = true
		call_deferred("_run_test_maps_unlock")
	if args.has("--test-layout"):
		call_deferred("_run_test_layout")
	if args.has("--test-benachrichtigungen"):
		call_deferred("_run_test_notify")
	if args.has("--test-content-fit"):
		call_deferred("_run_test_content_fit")
	if args.has("--test-touch-scroll"):
		call_deferred("_run_test_touch_scroll")
	if args.has("--autostart"):
		var mk := args.find("--map")
		if mk >= 0 and mk + 1 < args.size():
			for i in _skirmish.size():
				if _skirmish[i]["slug"] == args[mk + 1]:
					_on_map_selected(i)
		if _selected < 0 and _skirmish.size() > 0:
			_on_map_selected(0)


		var dk := args.find("--ai-difficulty")
		if dk >= 0 and dk + 1 < args.size() and ProtoWorld.AI_DIFFICULTIES.has(args[dk + 1]):
			_ai_difficulty = args[dk + 1]
		_slot_defaults()
		var sk := args.find("--ai-strategy")
		var sl := args.find("--ai-strategies")
		for i in _ai_slots.size():
			_ai_slots[i]["level"] = _ai_difficulty
			if sk >= 0 and sk + 1 < args.size() and ProtoWorld.AI_STRATEGIES.has(args[sk + 1]):
				_ai_slots[i]["strategy"] = args[sk + 1]
		if sl >= 0 and sl + 1 < args.size():
			var list: PackedStringArray = str(args[sl + 1]).split(",")
			for i in _ai_slots.size():
				if i < list.size() and ProtoWorld.AI_STRATEGIES.has(list[i]):
					_ai_slots[i]["strategy"] = list[i]
		_start_skirmish()


func _watch_multiplayer() -> void:
	var hub := NetHub.hub()
	if hub == null or hub.state_changed.is_connected(_on_net_state):
		return
	hub.state_changed.connect(_on_net_state)


func _on_net_state(what: String) -> void:
	if what != "started" or not is_inside_tree():
		return
	ProtoWorld.next_savegame = ""
	get_tree().change_scene_to_file(GAME_SCENE)


var _mp_players_wanted := 2
var _mp_started := false
var _mp_team := -1
var _mp_spawn := -2
var _mp_slot_tries := 0


func _apply_mp_args(args: PackedStringArray) -> void:
	var want_list := args.has("--mp-join-list")
	if not args.has("--mp-create") and args.find("--mp-join") < 0 and not want_list:
		return
	var hub := NetHub.hub()
	if hub == null:
		return
	_show("multiplayer")
	var slug := ProtoWorld.DEFAULT_MAP
	var mk := args.find("--map")
	if mk >= 0 and mk + 1 < args.size():
		slug = args[mk + 1]
	var pk := args.find("--mp-players")
	if pk >= 0 and pk + 1 < args.size():
		_mp_players_wanted = int(args[pk + 1])
	var tk := args.find("--mp-team")
	if tk >= 0 and tk + 1 < args.size():
		_mp_team = int(args[tk + 1])
	var sk := args.find("--mp-spawn")
	if sk >= 0 and sk + 1 < args.size():
		_mp_spawn = int(args[sk + 1])
	hub.connect_server("", NetClientScript.configured_name())
	hub.lobby_changed.connect(_on_mp_test_lobby)
	if args.has("--mp-create"):
		var seats: Array = NetHub.map_seats(slug)
		var public := args.has("--mp-public")
		var map_name := _map_title_of(slug)
		hub.map_slug = slug
		hub.settings = {"credits": _credits, "starting_units": _starting_units, "crates": _crates,
				"explored_map": _explored_map, "fog": _fog}
		hub.client.opened.connect(func():
			hub.client.create_room(slug, NetHub.map_sha256(slug), int(seats[1]), hub.settings,
					public, map_name),
			CONNECT_ONE_SHOT)
		hub.client.created.connect(func(code: String, _n: int):
			print("MP-CODE: %s (%s)" % [code, "öffentlich" if public else "privat"]))
	elif want_list:

		_mp_demo_mode = "join"
		if _mp_page != null:
			_mp_page.show_mode("join")
		hub.rooms_listed.connect(_on_mp_test_rooms)
	else:
		var jk := args.find("--mp-join")
		var code := args[jk + 1] if jk + 1 < args.size() else ""
		hub.client.opened.connect(func(): hub.client.join_room(code), CONNECT_ONE_SHOT)


func _map_title_of(slug: String) -> String:
	for m in _skirmish:
		if str(m.get("slug", "")) == slug:
			return str(m.get("title", slug))
	return slug


var _mp_list_done := false


func _on_mp_test_rooms(rooms: Array) -> void:
	if _mp_list_done or rooms.is_empty() or _mp_page == null:
		return
	_mp_list_done = true
	print("MP-LISTE: %d Raum/Räume — %s" % [rooms.size(), JSON.stringify(rooms)])
	for _i in 10:
		await get_tree().process_frame
	if _mp_shot_dir != "":
		var path := "%s/join-liste-%s.png" % [_mp_shot_dir,
				NetClientScript.configured_name().to_lower()]
		get_viewport().get_texture().get_image().save_png(path)
		print("Screenshot: ", path)
	print("MP-LISTE-TIPP: ", _mp_page.tap_first_room())


var _mp_shot_dir := ""
var _mp_shot_at := -1


func _mp_demo_lobby() -> void:
	var hub := NetHub.hub()
	if hub == null or _skirmish.is_empty():
		return

	var most := 0
	for i in _skirmish.size():
		if int(_skirmish[i]["players"]) > int(_skirmish[most]["players"]):
			most = i
	var slug := str(_skirmish[most]["slug"])
	var usable: int = int(NetHub.map_seats(slug)[1])
	var names := ["Tom", "Jan", "Ada", "Bo", "Kim", "Lea"]
	var clients: Array = []
	for seat in usable:
		var bot: bool = seat >= maxi(usable - 2, 1)
		var row := {"client_id": "demo%d" % seat, "seat": seat,
				"kind": "bot" if bot else "human",
				"name": ("KI %d" % (seat + 1)) if bot else names[seat % names.size()],
				"faction": "soviet" if seat % 2 else "allies", "team": 1 + seat % 2,
				"color": seat, "spawn": seat, "ready": bot or seat == 0,
				"ping": 18 + seat * 7}
		if bot:
			row["level"] = "normal"
		clients.append(row)
	hub.code = "KX7QP2"
	hub.map_slug = slug
	hub.host = true
	hub.host_seat = 0
	hub.my_seat = 0
	hub.seats_total = usable
	hub.settings = {"credits": 5000, "starting_units": "light", "crates": true,
			"explored_map": false, "fog": true, "ai_level": "normal"}
	hub.lobby = {"code": hub.code, "host_seat": 0, "map": slug, "seats_total": usable,
			"settings": hub.settings, "clients": clients}
	hub.chat = [{"seat": 1, "name": "Jan", "color": 1, "scope": "all", "text": "Bin da.", "t_server": 0},
			{"seat": 0, "name": "Tom", "color": 0, "scope": "all", "text": "Alle bereit?", "t_server": 0}]
	if _mp_lobby != null:
		_mp_lobby.refresh()


var _mp_demo_rooms: Array = []
var _mp_demo_mode := ""


func _mp_demo_join() -> void:
	if _mp_page == null or _skirmish.is_empty():
		return
	var rows: Array = []
	var namen := ["Tom", "Jan", "Ada", "Bo"]
	for i in mini(4, _skirmish.size()):
		var m: Dictionary = _skirmish[i]
		var slug := str(m.get("slug", ""))
		var total: int = int(NetHub.map_seats(slug)[1])
		rows.append({"code": ["KX7QP2", "M3RT8B", "QW42ZD", "TP9NHC"][i],
				"map": slug, "map_name": str(m.get("title", slug)),
				"seats_used": 1 + i % total, "seats_total": total,
				"started": i == 3, "host_name": namen[i], "public": true})
	_mp_demo_rooms = rows
	_mp_page.demo_rooms = rows


func _mp_shot_setup(args: PackedStringArray) -> void:
	var k := args.find("--mp-shot")
	if k >= 0 and k + 1 < args.size():
		_mp_shot_dir = args[k + 1]
		DirAccess.make_dir_recursive_absolute(_mp_shot_dir)


func _mp_shot_tick() -> void:
	if _mp_shot_dir == "" or _page != "mp_lobby":
		return
	if _mp_shot_at < 0:
		_mp_shot_at = Engine.get_process_frames() + 60


		var args := OS.get_cmdline_user_args()
		var ck := args.find("--mp-chat-lobby")
		if ck >= 0 and ck + 1 < args.size():
			var hub := NetHub.hub()
			if hub != null:
				hub.send_chat(args[ck + 1], "all")
		return
	if Engine.get_process_frames() != _mp_shot_at:
		return
	var path := "%s/lobby-%s.png" % [_mp_shot_dir, NetClientScript.configured_name().to_lower()]
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot: ", path)


func _on_mp_test_lobby(d: Dictionary) -> void:
	var hub := NetHub.hub()
	if hub == null or _mp_started:
		return
	var humans := 0
	var ready := 0
	var me_ready := false
	var me: Dictionary = {}
	for c in d.get("clients", []):
		if str(c.get("kind", "human")) != "human":
			continue
		humans += 1
		if bool(c.get("ready", false)):
			ready += 1
		if int(c.get("seat", -1)) == int(hub.my_seat):
			me = c
			if bool(c.get("ready", false)):
				me_ready = true


	if not me.is_empty() and (_mp_team >= 0 or _mp_spawn > -2) and _mp_slot_tries < 3:
		var want_team: int = _mp_team if _mp_team >= 0 else int(me.get("team", 0))
		var want_spawn: int = _mp_spawn if _mp_spawn > -2 else int(me.get("spawn", -1))
		if int(me.get("team", 0)) != want_team or int(me.get("spawn", -1)) != want_spawn:
			_mp_slot_tries += 1
			hub.client.set_slot(str(me.get("faction", "random")), want_team,
					int(me.get("color", 0)), want_spawn)
			return
		print("MP-PLATZ: Platz %d, Team %d, Startpunkt %d" % [int(hub.my_seat),
				int(me.get("team", 0)), int(me.get("spawn", -1))])
		_mp_slot_tries = 3
	if not me_ready:
		hub.client.set_ready(true)
		return
	if hub.host and humans >= _mp_players_wanted and ready >= humans:
		_mp_started = true
		var setup: Dictionary = hub.build_setup(str(hub.map_slug), d.get("clients", []), hub.settings)
		print("MP-START: %d Plätze, Seed %d" % [setup["seats"].size(), int(setup["seed"])])
		hub.client.start_game(setup)


func _scan_maps() -> void:
	var keep := ""
	if _selected >= 0 and _selected < _skirmish.size():
		keep = str(_skirmish[_selected].get("slug", ""))
	_maps = MapData.list_maps()
	_skirmish = []
	_missions = []
	_by_slug = {}
	for m in _maps:
		var cats: Array = m.get("categories", [])
		if cats.has("Campaign") or m.get("visibility", "") == "MissionSelector":
			_missions.append(m)
		elif int(m.get("players", 0)) >= 2 and _has_tileset(m.get("tileset", "")) and m.get("visibility", "") != "Shellmap":
			_skirmish.append(m)
	_selected = -1
	if keep != "":
		for i in _skirmish.size():
			if str(_skirmish[i].get("slug", "")) == keep:
				_selected = i
				break


func _on_content_unlocked() -> void:
	ContentPaths.refresh()


	var mp = get_node_or_null("/root/MusicPlayer")
	if mp != null:
		mp.rebuild()
	_scan_maps()
	_rebuild_ui(_page)


func _apply_lobby_args(args: PackedStringArray) -> void:
	var mk := args.find("--map")
	if mk >= 0 and mk + 1 < args.size():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == args[mk + 1]:
				_on_map_selected(i)
	var ak := args.find("--ai")
	if ak >= 0 and ak + 1 < args.size():
		_set_ai(int(args[ak + 1]))


const SHOT_FRAMES := 12
const SHOT_FRAMES_RESIZED := 120

var _shot_path := ""
var _shot_frames := 0
var _cycle := false
var _shot_manual := false
var _mp_demo_zoom := false
var _mp_demo_picker := false
var _cycle_frames := 0


func _process(_delta: float) -> void:
	_mp_shot_tick()
	if _cycle:
		_cycle_frames += 1
		if _cycle_frames == 25:
			match ProtoWorld.test_cycle_step:
				0:
					print("T: Zyklus startet Gefecht")
					_start_skirmish()
				1:
					print("T: Zyklus startet Mission allies-02")
					_on_mission_selected("allies-02")
					_start_mission()
				_:
					print("T: Zyklus fertig")
					get_tree().quit()
		return
	if _shot_path == "" or _shot_manual:
		return
	_shot_frames += 1

	if _shot_frames == 6 and _page == "options" and _options_scroll != null \
			and NetNotify.force_ui:
		_options_scroll.scroll_vertical = int(_options_scroll.get_v_scroll_bar().max_value)
	if _shot_frames == 6 and _mp_lobby != null:
		if _mp_demo_zoom:
			_mp_lobby.open_map_overlay()
		elif _mp_demo_picker:
			_mp_lobby.open_map_picker()
	if _shot_frames == (SHOT_FRAMES_RESIZED if Desktop.want_test_window() else SHOT_FRAMES):
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
		get_tree().quit()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_ai_players = int(cfg.get_value("skirmish", "ai_players", 1))
		_credits = int(cfg.get_value("skirmish", "credits", 5000))
		_faction = str(cfg.get_value("skirmish", "faction", "allies"))
		_ai_faction = str(cfg.get_value("skirmish", "ai_faction", "soviet"))
		_starting_units = str(cfg.get_value("skirmish", "starting_units", "none"))
		_crates = bool(cfg.get_value("skirmish", "crates", true))
		_explored_map = bool(cfg.get_value("skirmish", "explored_map", false))
		_fog = bool(cfg.get_value("skirmish", "fog", true))
		_ai_difficulty = str(cfg.get_value("skirmish", "ai_difficulty", "normal"))
		if not ProtoWorld.AI_DIFFICULTIES.has(_ai_difficulty):
			_ai_difficulty = "normal"
		var last: String = cfg.get_value("skirmish", "map", "")
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == last:
				_selected = i
		Music.enabled_default = bool(cfg.get_value("audio", "music", true))
		_player_team = int(cfg.get_value("skirmish", "player_team", 0))
		_spawn_choice = int(cfg.get_value("skirmish", "spawn", -1))


		var saved: Array = cfg.get_value("skirmish", "ai_slots", [])
		if saved is Array and not saved.is_empty():
			_ai_slots = saved.duplicate(true)
			_ai_slots.resize(mini(_ai_slots.size(), ProtoWorld.AI_PLAYER_INDICES.size()))
			for slot in _ai_slots:
				if not (slot is Dictionary):
					_ai_slots = []
					break
		_slot_defaults()
	if _selected < 0 and not _skirmish.is_empty():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == ProtoWorld.DEFAULT_MAP:
				_selected = i
		if _selected < 0:
			_selected = 0


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("skirmish", "ai_players", _ai_players)
	cfg.set_value("skirmish", "credits", _credits)
	cfg.set_value("skirmish", "faction", _faction)
	cfg.set_value("skirmish", "ai_faction", _ai_faction)
	cfg.set_value("skirmish", "starting_units", _starting_units)
	cfg.set_value("skirmish", "crates", _crates)
	cfg.set_value("skirmish", "explored_map", _explored_map)
	cfg.set_value("skirmish", "fog", _fog)
	cfg.set_value("skirmish", "ai_difficulty", _ai_difficulty)
	if _selected >= 0 and _selected < _skirmish.size():
		cfg.set_value("skirmish", "map", _skirmish[_selected]["slug"])
	cfg.set_value("audio", "music", Music.enabled_default)
	cfg.set_value("skirmish", "player_team", _player_team)
	cfg.set_value("skirmish", "spawn", _spawn_choice)
	cfg.set_value("skirmish", "ai_slots", _ai_slots)
	cfg.save(SETTINGS)


func _button(text: String, cb: Callable, w: float = 200.0, h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(w), Dp.px(h))
	HudTheme.style_button(b, 14.0)
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


func _menu_button(text: String, _icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(260), Dp.px(42))
	HudTheme.style_menu_button(b, 19.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


static var _icon_cache := {}
static func _keyed_icon(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.7 and c.b > 0.7 and c.g < 0.35:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.resize(96, 96, Image.INTERPOLATE_NEAREST)
	var out := ImageTexture.create_from_image(img)
	_icon_cache[path] = out
	return out


func _title(text: String, size_dp: float = 34.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(Dp.px(size_dp)))
	l.add_theme_color_override("font_color", HudTheme.GOLD)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", int(Dp.px(2)))
	return l


const VERSION := "v0.5"


func _build_ui() -> void:


	var bg := TextureRect.new()
	var vs := get_viewport().get_visible_rect().size
	var wide := vs.x / maxf(vs.y, 1.0) > 2.0
	var lang_code := Lang.code()
	var bg_path := "res://assets/ui/menu_bg_wide_%s.png" % lang_code
	if not (wide and ResourceLoader.exists(bg_path)):
		bg_path = "res://assets/ui/menu_bg_%s.png" % lang_code
	bg.texture = load(bg_path)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


	var lights := MenuBackground.new()
	lights.set_anchors_preset(Control.PRESET_FULL_RECT)
	lights.set_background(bg_path, bg.texture)
	add_child(lights)

	var safe := Dp.safe_rect()
	var subtitle := Label.new()
	subtitle.text = tr("menu.main.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", int(Dp.px(11)))
	subtitle.add_theme_color_override("font_color", HudTheme.GOLD)
	subtitle.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	subtitle.add_theme_constant_override("outline_size", int(Dp.px(1)))
	subtitle.modulate = Color(1, 1, 1, 0.7)
	subtitle.position = Vector2(safe.position.x, safe.end.y - Dp.px(40))
	subtitle.size = Vector2(safe.size.x, Dp.px(18))
	add_child(subtitle)
	var version := Label.new()
	version.text = "v" + UpdateConfig.app_version()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", int(Dp.px(12)))
	version.add_theme_color_override("font_color", HudTheme.GOLD)
	version.position = Vector2(safe.end.x - Dp.px(60), safe.end.y - Dp.px(22))
	version.size = Vector2(Dp.px(50), Dp.px(18))
	add_child(version)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_apply_update_reserve()


	var main := VBoxContainer.new()
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override("separation", int(Dp.px(4)))
	main.alignment = BoxContainer.ALIGNMENT_BEGIN
	var spacer := Control.new()
	main.add_child(spacer)


	var content_locked := not ContentManager.available() or UpdateConfig.blocked()


	var no_saves := SaveGame.list_all().is_empty()
	var tu_btn: Button = null
	if no_saves:
		tu_btn = _menu_button(tr("menu.main.tutorial"), "star", _start_tutorial)
		main.add_child(tu_btn)
	var sk_btn := _menu_button(tr("menu.main.skirmish"), "tank", func(): _show("skirmish"))

	var mp_btn := _menu_button(tr("menu.main.multiplayer"), "tank", func(): _show("multiplayer"))
	var mi_btn := _menu_button(tr("menu.main.missions"), "star", func(): _show("missions"))
	if content_locked:
		for b in [tu_btn, sk_btn, mp_btn, mi_btn]:
			if b != null:
				b.disabled = true
				b.tooltip_text = tr("content.locked_hint")
	main.add_child(sk_btn)
	main.add_child(mp_btn)
	main.add_child(mi_btn)
	if not no_saves:
		main.add_child(_menu_button(tr("menu.main.load"), "star", func(): _rebuild_ui("load")))
	main.add_child(_menu_button(tr("menu.main.options"), "gear", func(): _show("options")))

	if OS.get_name() not in ["Android", "iOS"]:
		main.add_child(_menu_button(tr("menu.main.quit"), "door", func(): get_tree().quit()))


	var vh := get_viewport().get_visible_rect().size.y
	var needed := (main.get_child_count() - 1) * (Dp.px(42) + Dp.px(4))
	spacer.custom_minimum_size = Vector2(0, clampf(vh - needed - Dp.px(24), 0.0, vh * 0.30))
	_pages["main"] = _center(main)


	var narrow := get_viewport().get_visible_rect().size.x < Dp.px(640)
	var sk: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	sk.add_theme_constant_override("separation", int(Dp.px(16)))
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(0 if narrow else Dp.px(260), 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
	left.add_child(_title(tr("menu.main.skirmish"), 18))

	var scroll := TouchList.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if narrow:

		scroll.custom_minimum_size = Vector2(0, get_viewport().get_visible_rect().size.y * 0.40)
	var listbox := VBoxContainer.new()
	listbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listbox.add_theme_constant_override("separation", int(Dp.px(4)))
	_map_scroll = scroll
	_map_buttons = []
	for i in _skirmish.size():
		var m: Dictionary = _skirmish[i]
		var b := Button.new()
		b.text = "%s  (%d, %s)" % [m["title"], int(m["players"]), _tileset_name(m["tileset"])]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, Dp.px(32))
		HudTheme.style_tab(b, 12.0)
		var idx := i
		b.pressed.connect(func():
			Sfx.click(self)
			_on_map_selected(idx))
		listbox.add_child(b)
		_map_buttons.append(b)
	if _skirmish.is_empty():


		var none := Label.new()
		none.text = tr("menu.skirmish.empty")
		none.add_theme_font_size_override("font_size", int(Dp.px(12)))
		none.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		listbox.add_child(none)
	scroll.add_child(listbox)
	left.add_child(scroll)
	sk.add_child(left)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", int(Dp.px(4)))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(Dp.px(160), Dp.px(84))
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_show_map_overlay())
	right.add_child(_preview)
	_info = Label.new()
	_info.add_theme_color_override("font_color", HudTheme.TEXT)
	_info.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	_ai_label = Label.new()
	_ai_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_ai_label.add_theme_color_override("font_color", HudTheme.TEXT)
	row.add_child(_button("−", func(): _set_ai(_ai_players - 1), 40, 34))
	row.add_child(_ai_label)
	row.add_child(_button("+", func(): _set_ai(_ai_players + 1), 40, 34))
	right.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", int(Dp.px(8)))
	_credits_label = Label.new()
	_credits_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_credits_label.add_theme_color_override("font_color", HudTheme.TEXT)
	row2.add_child(_button("−", func(): _set_credits(_credits - 2500), 40, 34))
	row2.add_child(_credits_label)
	row2.add_child(_button("+", func(): _set_credits(_credits + 2500), 40, 34))
	right.add_child(row2)

	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", int(Dp.px(4)))
	right.add_child(_slot_box)
	var row3 := HBoxContainer.new()
	row3.visible = false
	row3.add_theme_constant_override("separation", int(Dp.px(8)))
	_faction_btn = _button("", func(): pass, 130, 34)
	_faction_btn.pressed.connect(func():
		_faction = _next_faction_value(_faction)
		_update_factions())
	_ai_faction_btn = _button("", func(): pass, 130, 34)
	_ai_faction_btn.pressed.connect(func():
		_ai_faction = _next_faction_value(_ai_faction)
		_update_factions())
	row3.add_child(_faction_btn)
	row3.add_child(_ai_faction_btn)
	right.add_child(row3)
	_start_btn = _button("", func(): pass, 268, 34)
	_start_btn.pressed.connect(func():
		var order := ["none", "light", "heavy"]
		_starting_units = order[(order.find(_starting_units) + 1) % order.size()]
		_update_factions())
	right.add_child(_start_btn)
	_ai_difficulty_btn = null
	_crates_btn = _button("", func(): pass, 268, 34)
	_crates_btn.pressed.connect(func():
		_crates = not _crates
		_update_factions())
	right.add_child(_crates_btn)


	_explored_map_btn = _button("", func(): pass, 268, 34)
	_explored_map_btn.pressed.connect(func():
		_explored_map = not _explored_map
		_update_factions())
	right.add_child(_explored_map_btn)
	_fog_btn = _button("", func(): pass, 268, 34)
	_fog_btn.pressed.connect(func():
		_fog = not _fog
		_update_factions())
	right.add_child(_fog_btn)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(Dp.px(8)))
	actions.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	actions.add_child(_button(tr("menu.skirmish.start"), _start_skirmish, 168, 40))
	right_scroll.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(right_scroll)
	right_col.add_child(actions)
	sk.add_child(right_col)
	_pages["skirmish"] = _center(sk, true)


	_mp_page = MultiplayerPage.new()
	_mp_page.maps = _skirmish

	_mp_page.demo_rooms = _mp_demo_rooms
	_mp_page.back_pressed.connect(func(): _show("main"))
	_mp_page.lobby_entered.connect(func(): _show("mp_lobby"))
	_pages["multiplayer"] = _center(_mp_page, true)
	_mp_lobby = MultiplayerLobby.new()
	_mp_lobby.maps = _skirmish

	_mp_lobby.leave_pressed.connect(func():
		if _mp_page != null and _mp_demo_mode == "":
			_mp_page.show_start()
		_show("multiplayer"))
	_pages["mp_lobby"] = _center(_mp_lobby, true)


	var mi := VBoxContainer.new()
	mi.add_theme_constant_override("separation", int(Dp.px(6)))
	mi.add_child(_title(tr("menu.main.missions"), 18))
	var mscroll := TouchList.new()
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var mbox := VBoxContainer.new()
	mbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mbox.add_theme_constant_override("separation", int(Dp.px(3)))
	for c in Missions.campaigns():
		var maps: Array = c.get("maps", [])
		var done := 0
		var open_count := 0
		for slug in maps:
			if _completed(slug):
				done += 1
			if _mission_reason(slug) == "":
				open_count += 1
		var head := Label.new()
		head.text = tr("menu.missions.progress") % [_campaign_name(c.get("name", "")), open_count, maps.size(), done]
		head.add_theme_font_size_override("font_size", int(Dp.px(12)))
		head.add_theme_color_override("font_color", HudTheme.GOLD)
		mbox.add_child(head)
		for slug in maps:
			var reason := _mission_reason(slug)
			var b := Button.new()
			b.text = "%s%s%s" % ["✔ " if _completed(slug) else "", _mission_title(slug),
					"" if reason == "" else "   — %s" % _mission_short_reason(slug)]
			b.toggle_mode = true

			b.disabled = false
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, Dp.px(30))
			HudTheme.style_tab(b, 11.0)
			if reason != "":
				b.modulate = Color(1, 1, 1, 0.85)
			var sl: String = slug
			b.pressed.connect(func():
				Sfx.click(self)
				_on_mission_selected(sl))
			mbox.add_child(b)
			_mission_buttons[slug] = b
	mscroll.add_child(mbox)
	mi.add_child(mscroll)
	_mission_info = Label.new()
	_mission_info.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_mission_info.add_theme_color_override("font_color", HudTheme.TEXT)
	_mission_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mi.add_child(_mission_info)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", int(Dp.px(8)))
	_difficulty_btn = _button(tr("menu.missions.difficulty") % _difficulty_name("normal"), func(): _cycle_difficulty(), 190, 40)
	mrow.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	mrow.add_child(_difficulty_btn)
	mrow.add_child(_button(tr("menu.missions.start"), _start_mission, 168, 40))
	mi.add_child(mrow)
	_pages["missions"] = _center(mi, true)


	var ld := VBoxContainer.new()
	ld.add_theme_constant_override("separation", int(Dp.px(6)))
	ld.add_child(_title(tr("menu.main.load"), 18))
	var lscroll := TouchList.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbox.add_theme_constant_override("separation", int(Dp.px(4)))
	var saves := SaveGame.list_all()
	if saves.is_empty():
		var none := Label.new()
		none.text = tr("save.none")
		none.add_theme_font_size_override("font_size", int(Dp.px(13)))
		lbox.add_child(none)
	else:


		var latest_slot := str(saves[0]["slot"])
		var cont := _button("%s — %s" % [tr("menu.main.continue"), SaveGame.label(saves[0]).replace("\n", "  ")],
				func(): _start_savegame(latest_slot), 460, 52)
		cont.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cont.add_theme_color_override("font_color", HudTheme.GOLD)
		lbox.add_child(cont)
	for e in saves:
		var slot := str(e["slot"])
		var name := tr("save.slot_auto") if SaveGame.is_auto(slot) else tr("save.slot") % slot
		var b := _button("%s — %s" % [name, SaveGame.label(e).replace("\n", "  ")],
				func(): _start_savegame(slot), 460, 52)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(b)
	lscroll.add_child(lbox)
	ld.add_child(lscroll)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", int(Dp.px(8)))
	lrow.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	ld.add_child(lrow)
	_pages["load"] = _center(ld, true)


	var op_head := _title(tr("menu.main.options"), 18)
	var op_scroll := ScrollContainer.new()
	_options_scroll = op_scroll
	op_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	op_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := VBoxContainer.new()
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op.add_theme_constant_override("separation", int(Dp.px(8)))


	var lang_btn := _button("", func(): pass, 268, 34)
	lang_btn.text = tr("menu.options.language") % ("Deutsch" if Lang.is_de() else "English")
	lang_btn.pressed.connect(func():
		Lang.set_language("en" if Lang.is_de() else "de")
		_rebuild_ui("options"))
	op.add_child(lang_btn)


	if Desktop.is_desktop():
		var fs_btn := _button("", func(): pass, 268, 34)
		fs_btn.text = Desktop.fullscreen_text()
		fs_btn.pressed.connect(func():
			Desktop.toggle_fullscreen()
			fs_btn.text = Desktop.fullscreen_text())
		op.add_child(fs_btn)
	op.add_child(_build_content_section())


	var upd_btn := _button("", func(): pass, 268, 34)
	upd_btn.text = tr("update.check_on") if UpdateConfig.check_enabled() else tr("update.check_off")
	upd_btn.pressed.connect(func():
		UpdateConfig.set_check_enabled(not UpdateConfig.check_enabled())
		upd_btn.text = tr("update.check_on") if UpdateConfig.check_enabled() else tr("update.check_off"))
	op.add_child(upd_btn)
	op.add_child(_button(tr("update.check_now"), func():
		if _update != null:
			_update_text = tr("update.checking")
			_refresh_update_bar()
			_update.start(true), 268, 34))
	var ver_lbl := Label.new()
	ver_lbl.text = UpdateConfig.version_summary()
	ver_lbl.add_theme_font_size_override("font_size", int(Dp.px(11)))
	ver_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	op.add_child(ver_lbl)
	var music_btn := _button("", func(): pass)
	music_btn.text = _music_text()
	music_btn.pressed.connect(func():
		var mp = get_node_or_null("/root/MusicPlayer")
		if mp != null:
			mp.toggle()
		else:
			Music.enabled_default = not Music.enabled_default
		music_btn.text = _music_text()
		_refresh_music_title())
	op.add_child(music_btn)


	var mplayer = get_node_or_null("/root/MusicPlayer")
	if mplayer != null and mplayer.original_available():
		var src_btn := _button("", func(): pass, 268, 34)
		src_btn.text = _music_source_text()
		src_btn.pressed.connect(func():
			mplayer.set_source(Music.SOURCE_OWN if mplayer.source == Music.SOURCE_ORIGINAL else Music.SOURCE_ORIGINAL)
			src_btn.text = _music_source_text()
			_refresh_music_title())
		op.add_child(src_btn)


	_music_title_lbl = Label.new()
	_music_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_music_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_music_title_lbl.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_music_title_lbl.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	op.add_child(_music_title_lbl)
	_refresh_music_title()
	if mplayer != null and not mplayer.track_changed.is_connected(_on_track_changed):
		mplayer.track_changed.connect(_on_track_changed)

	op.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
			func(i): GameSpeed.set_index(i), self))
	for entry in [["master", tr("menu.options.master")], ["music", tr("menu.options.music")],
			["sfx", tr("menu.options.sfx")], ["voice", tr("menu.options.voice")],
			["video", tr("menu.options.video")], ["radio", tr("menu.options.radio")]]:
		op.add_child(_volume_row(entry[0], entry[1]))

	op.add_child(HudTheme.choice_row(tr("menu.options.voice_chat"), [tr("word.off"), tr("word.on")],
			1 if VoiceChat.enabled() else 0, func(i: int): VoiceChat.set_enabled(i == 1), self))


	op.add_child(HudTheme.choice_row(tr("menu.options.headset"),
			[tr("word.auto"), tr("word.on"), tr("word.off")], AudioMix.headset_mode(),
			func(i: int): AudioMix.set_headset_mode(i), self))


	var hub_v := NetHub.hub()
	if hub_v != null:
		op.add_child(HudTheme.mic_probe_row(hub_v.ensure_voice(), self))


	if NetNotify.supported():
		op.add_child(_notify_block())
	op_scroll.add_child(op)


	HudTheme.touch_scroll(op_scroll)

	var op_col := VBoxContainer.new()
	op_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	op_col.add_theme_constant_override("separation", int(Dp.px(6)))
	op_col.add_child(op_head)
	op_col.add_child(op_scroll)
	var op_foot := HBoxContainer.new()
	op_foot.add_theme_constant_override("separation", int(Dp.px(8)))
	op_foot.alignment = BoxContainer.ALIGNMENT_CENTER
	op_foot.add_child(_button(tr("menu.options.controls_button"), func(): _show("controls"), 220, 40))
	op_foot.add_child(_button(tr("ui.back"), func(): _show("main"), 140, 40))
	op_col.add_child(op_foot)
	_pages["options"] = _center(op_col, true)


	_content_page = ContentPage.new()
	_content_page.back_requested.connect(func(): _show(_content_return))

	_content_page.continue_requested.connect(func(): _rebuild_ui("main"))

	_content_page.unlocked.connect(_on_content_unlocked)

	_pages["content"] = _center(_content_page, true, false)


	_update_page = UpdatePage.new()
	_update_page.recheck_requested.connect(func():
		if _update != null:
			_update.start(true))
	_pages["blocked"] = _center(_update_page, true)


	_controls_box = VBoxContainer.new()
	_controls_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pages["controls"] = _center(_controls_box, true)


	var log_col := VBoxContainer.new()
	log_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_col.add_theme_constant_override("separation", int(Dp.px(6)))
	log_col.add_child(_title(tr("log.title"), 18))
	_log_view = LogView.new()
	log_col.add_child(_log_view)
	var log_foot := HBoxContainer.new()
	log_foot.alignment = BoxContainer.ALIGNMENT_CENTER
	log_foot.add_child(_button(tr("ui.back"), func(): _show(_log_return), 140, 40))
	log_col.add_child(log_foot)
	_pages["log"] = _center(log_col, true)

	_build_update_bar()

	if _selected >= 0:
		_on_map_selected(_selected)
	_update_mission_info()
	_set_ai(_ai_players)
	_set_credits(_credits)
	_update_factions()


func _volume_row(key: String, label: String) -> Control:
	return HudTheme.volume_row(key, label, self)


func _notify_block() -> Control:
	var box := VBoxContainer.new()
	box.name = "NotifyBlock"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(Dp.px(4)))

	var sub := VBoxContainer.new()
	sub.name = "NotifyEvents"
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_theme_constant_override("separation", int(Dp.px(4)))
	box.add_child(HudTheme.choice_row(tr("menu.options.notify"), [tr("word.off"), tr("word.on")],
			1 if NetNotify.enabled() else 0,
			func(i: int):
				NetNotify.set_enabled(i == 1)
				sub.visible = i == 1

				var h := NetHub.hub()
				if h != null:
					h.refresh_watch(), self))
	var hint := Label.new()
	hint.text = tr("menu.options.notify_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(Dp.px(240), 0)
	hint.add_theme_font_size_override("font_size", int(Dp.px(11)))
	hint.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(hint)
	for ev in NetNotify.EVENTS:
		var key := str(ev)
		sub.add_child(HudTheme.choice_row(tr("menu.options.notify_" + key),
				[tr("word.off"), tr("word.on")], 1 if NetNotify.event_enabled(key) else 0,
				func(i: int): NetNotify.set_event_enabled(key, i == 1), self))


	if not NetNotify.permission_ok():
		var perm := VBoxContainer.new()
		perm.add_theme_constant_override("separation", int(Dp.px(4)))
		var warn := Label.new()
		warn.text = tr("menu.options.notify_perm")
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(Dp.px(240), 0)
		warn.add_theme_font_size_override("font_size", int(Dp.px(11)))
		warn.add_theme_color_override("font_color", HudTheme.MODE_SELL)
		perm.add_child(warn)
		var ask := _button(tr("menu.options.notify_allow"), func():
			NetNotify.new().request_permission()


			await get_tree().create_timer(1.0).timeout
			if _page == "options":
				_rebuild_ui("options"), 220, 40)
		perm.add_child(ask)
		sub.add_child(perm)
	sub.visible = NetNotify.enabled()
	box.add_child(sub)
	return box


var _mission_slug := ""
var _mission_buttons := {}
var _mission_info: Label
var _difficulty_btn: Button
var _difficulty := ""
var _difficulties: Array = []


const CAMPAIGN_KEYS := {
	"Allied Campaign": "campaign.allied", "Soviet Campaign": "campaign.soviet",
	"Counterstrike Allied Missions": "campaign.counterstrike_allied",
	"Counterstrike Soviet Missions": "campaign.counterstrike_soviet",
	"Aftermath Allied Missions": "campaign.aftermath_allied",
	"Aftermath Soviet Missions": "campaign.aftermath_soviet",
	"OpenRA Originals": "campaign.openra_originals", "Ant Missions": "campaign.ant_missions",
}
const DIFFICULTY_KEYS := {"easy": "difficulty.easy", "normal": "difficulty.normal", "hard": "difficulty.hard", "tough": "difficulty.tough"}


func _campaign_name(name: String) -> String:
	return tr(CAMPAIGN_KEYS[name]) if CAMPAIGN_KEYS.has(name) else name


func _difficulty_name(d: String) -> String:
	return tr(DIFFICULTY_KEYS[d]) if DIFFICULTY_KEYS.has(d) else d


var _by_slug := {}
var _done_slugs := {}


func _map_entry(slug: String) -> Dictionary:
	if _by_slug.is_empty():
		for m in _maps:
			_by_slug[str(m.get("slug", ""))] = m
	return _by_slug.get(slug, {})


func _completed(slug: String) -> bool:
	if _done_slugs.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(Missions.PROGRESS) == OK and cfg.has_section("missions"):
			for k in cfg.get_section_keys("missions"):
				_done_slugs[k] = bool(cfg.get_value("missions", k, false))
		_done_slugs["__geladen__"] = true
	return bool(_done_slugs.get(slug, false))


func _mission_title(slug: String) -> String:
	var m := _map_entry(slug)
	return str(m.get("title", slug)) if not m.is_empty() else slug


func _mission_reason(slug: String) -> String:
	var m := _map_entry(slug)
	if m.is_empty():
		return tr("lock.map_missing")
	if not Missions.has_script(slug):

		var r := Missions.blocked_reason(slug)
		return r if r != "" else tr("lock.script_missing")
	var tileset := str(m.get("tileset", ""))
	if tileset != "" and not Missions.TILESETS.has(tileset):
		return tr("lock.tileset_missing") % tileset
	return ""


func _mission_short_reason(slug: String) -> String:
	var r := _mission_reason(slug)
	if r == "" or r.length() <= 22:
		return r
	return tr("lock.not_ported")


func _mission_difficulties(slug: String) -> Array:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d.get("difficulties", []) if d is Dictionary else []


func _mission_difficulty_default(slug: String) -> String:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return "normal"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return str(d.get("difficulty_default", "normal")) if d is Dictionary else "normal"


func _on_mission_selected(slug: String) -> void:
	_mission_slug = slug
	for k in _mission_buttons:
		_mission_buttons[k].button_pressed = k == slug
	_difficulties = _mission_difficulties(slug)
	_difficulty = _mission_difficulty_default(slug)
	_update_mission_info()


func _cycle_difficulty() -> void:
	if _difficulties.is_empty():
		return
	var i := _difficulties.find(_difficulty)
	_difficulty = _difficulties[(i + 1) % _difficulties.size()]
	_update_mission_info()


func _update_mission_info() -> void:
	var has_diff := not _difficulties.is_empty()
	_difficulty_btn.disabled = not has_diff
	_difficulty_btn.text = tr("menu.missions.difficulty") % (_difficulty_name(_difficulty) if has_diff else "—")
	if _mission_slug == "":
		_mission_info.text = tr("menu.missions.pick")
		return
	var lines := "%s%s" % [_mission_title(_mission_slug), tr("menu.missions.completed_suffix") if _completed(_mission_slug) else ""]
	var reason := _mission_reason(_mission_slug)
	if reason != "":
		_mission_info.text = tr("menu.missions.locked") % [lines, reason]
		return
	var brief := Missions.briefing(_mission_slug)
	if brief != "":
		lines += "\n" + brief.split("\n")[0]
	if not has_diff:
		lines += "\n" + tr("menu.missions.no_difficulty")
	_mission_info.text = lines


func _start_savegame(slot: String) -> void:
	if SaveGame.read(slot, false).is_empty():
		return
	ProtoWorld.next_savegame = slot
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_tutorial() -> void:
	ProtoWorld.next_map = "tutorial"
	ProtoWorld.next_mission = "tutorial"
	ProtoWorld.next_credits = 5000
	ProtoWorld.next_difficulty = ""
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_mission() -> void:
	if _mission_slug == "" or _mission_reason(_mission_slug) != "":
		return
	ProtoWorld.next_map = _mission_slug
	ProtoWorld.next_mission = _mission_slug
	ProtoWorld.next_credits = 5000
	ProtoWorld.next_difficulty = _difficulty if not _difficulties.is_empty() else ""
	get_tree().change_scene_to_file(GAME_SCENE)


func _faction_name(f: String) -> String:
	if f == "random":
		return tr("faction.random")
	return tr("faction.allies") if f == "allies" else tr("faction.soviet")


const FACTION_CYCLE := ["allies", "soviet", "random"]


func _next_faction_value(f: String) -> String:
	return FACTION_CYCLE[(FACTION_CYCLE.find(f) + 1) % FACTION_CYCLE.size()]


func _team_name(t: int) -> String:
	return tr("lobby.team") % (tr("lobby.team_none") if t <= 0 else str(t))


const STARTING_UNITS_KEYS := {"none": "menu.skirmish.units_none", "light": "menu.skirmish.units_light", "heavy": "menu.skirmish.units_heavy"}

const AI_DIFFICULTY_KEYS := {"easy": "menu.skirmish.ai_easy", "normal": "menu.skirmish.ai_normal", "hard": "menu.skirmish.ai_hard"}


const AI_STRATEGY_KEYS := {"normal": "menu.skirmish.strat_normal", "rush": "menu.skirmish.strat_rush",
		"turtle": "menu.skirmish.strat_turtle", "air": "menu.skirmish.strat_air",
		"naval": "menu.skirmish.strat_naval", "random": "menu.skirmish.strat_random"}


func _update_factions() -> void:
	if _faction_btn != null:
		_faction_btn.text = tr("menu.skirmish.mine") % _faction_name(_faction)
	if _ai_faction_btn != null:
		_ai_faction_btn.text = tr("menu.skirmish.ai_faction") % _faction_name(_ai_faction)
	_rebuild_slots()
	if _start_btn != null:
		_start_btn.text = tr("menu.skirmish.starting_units") % tr(STARTING_UNITS_KEYS.get(_starting_units, "menu.skirmish.units_none"))
	if _crates_btn != null:
		_crates_btn.text = tr("menu.skirmish.crates") % tr("word.on" if _crates else "word.off")
	if _explored_map_btn != null:
		_explored_map_btn.text = tr("menu.skirmish.explored_map") % tr("word.on" if _explored_map else "word.off")
	if _fog_btn != null:
		_fog_btn.text = tr("menu.skirmish.fog") % tr("word.on" if _fog else "word.off")
	if _ai_difficulty_btn != null:
		_ai_difficulty_btn.text = tr("menu.skirmish.ai_difficulty") % tr(AI_DIFFICULTY_KEYS.get(_ai_difficulty, "menu.skirmish.ai_normal"))


func _build_content_section() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(12.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	var head := Label.new()
	head.text = tr("menu.options.content_button")
	head.add_theme_font_size_override("font_size", int(Dp.px(15)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)
	var status := Label.new()
	status.name = "ContentStatus"
	status.text = "\n".join(ContentManager.status_lines())
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", int(Dp.px(11)))
	status.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_button(tr("content.reload"), func(): _show("content"), 190, 34))
	var del := _button(tr("content.delete_all"), func(): pass, 190, 34)
	row.add_child(del)
	box.add_child(row)


	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(_button(tr("content.disclaimer_read"), func():
		_show("content")
		if _content_page != null:
			_content_page.show_disclaimer(), 250, 34))
	box.add_child(row2)


	var confirm := VBoxContainer.new()
	confirm.name = "DeleteConfirm"
	confirm.add_theme_constant_override("separation", int(Dp.px(6)))
	confirm.visible = false
	var q := Label.new()
	q.text = tr("content.delete_all_confirm")
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.add_theme_font_size_override("font_size", int(Dp.px(12)))
	q.add_theme_color_override("font_color", HudTheme.TEXT)
	confirm.add_child(q)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", int(Dp.px(8)))
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_child(_button(tr("content.delete_all_yes"), func():
		AppLogger.info("Options", "Spielinhalte werden gelöscht (%s)" % ContentManager.format_mb(ContentManager.total_size_bytes()))
		ContentManager.delete_all()

		ContentPaths.refresh()
		var mpd = get_node_or_null("/root/MusicPlayer")
		if mpd != null:
			mpd.rebuild()
		confirm.visible = false
		status.text = "\n".join(ContentManager.status_lines())

		_rebuild_ui("options"), 150, 34))
	crow.add_child(_button(tr("ui.cancel"), func(): confirm.visible = false, 150, 34))
	confirm.add_child(crow)
	box.add_child(confirm)
	del.pressed.connect(func(): confirm.visible = not confirm.visible)
	return panel


func _center(content: Control, fill: bool = false, framed: bool = true) -> Control:
	var c := MarginContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

	var m := int(Dp.px(12))
	var vs := get_viewport().get_visible_rect().size
	var safe := Dp.safe_rect()
	c.add_theme_constant_override("margin_left", m + int(maxf(safe.position.x, 0.0)))
	c.add_theme_constant_override("margin_top", m + int(maxf(safe.position.y, 0.0)))
	c.add_theme_constant_override("margin_right", m + int(maxf(vs.x - safe.end.x, 0.0)))
	c.add_theme_constant_override("margin_bottom", m + int(maxf(vs.y - safe.end.y, 0.0)))
	if fill and not framed:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.add_child(content)
	elif fill:

		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", HudTheme.panel(Color(0.05, 0.05, 0.04, 0.88), HudTheme.BORDER_DIM, 8.0))
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var inner := MarginContainer.new()
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			inner.add_theme_constant_override(side, int(Dp.px(8)))
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(content)
		frame.add_child(inner)
		c.add_child(frame)
	else:
		var cc := CenterContainer.new()
		cc.add_child(content)
		c.add_child(cc)
	c.visible = false
	_root.add_child(c)
	return c


func _run_test_lobby() -> void:


	_show("skirmish")
	for _i in 12:
		await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	var mk := args.find("--map")
	if mk >= 0 and mk + 1 < args.size():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == args[mk + 1]:
				_on_map_selected(i)
	_set_ai(3)
	_slot_defaults()
	_player_team = 1
	_ai_slots[0]["team"] = 2
	_ai_slots[1]["team"] = 1
	_ai_slots[2]["team"] = 2
	_ai_slots[0]["faction"] = "soviet"
	_ai_slots[1]["faction"] = "allies"
	_ai_slots[2]["faction"] = "random"
	_faction = "random"
	_update_factions()
	for _i in 4:
		await get_tree().process_frame


	var before: Array = [str(_ai_slots[2]["faction"]), int(_ai_slots[2]["team"])]
	_set_ai(_max_ai())
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen" % [_ai_players, _slot_box.get_child_count() - 2])
	_set_ai(1)
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen" % [_ai_players, _slot_box.get_child_count() - 2])
	_set_ai(3)
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen, KI 3 unverändert: %s" % [_ai_players,
		_slot_box.get_child_count() - 2,
		before == [str(_ai_slots[2]["faction"]), int(_ai_slots[2]["team"])]])
	_show_map_overlay()
	for _i in 6:
		await get_tree().process_frame
	if _shot_path != "":
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
	_spawn_choice = 0
	_close_map_overlay()
	print("T: Lobby — Spieler Team %d, KI-Teams %s, Startpunkt %d" % [_player_team,
		[_ai_slots[0]["team"], _ai_slots[1]["team"], _ai_slots[2]["team"]], _spawn_choice])
	_start_skirmish()


const LAYOUT_MATRIX := [
	[1096, 2560, 420], [2560, 1096, 420],
	[1080, 2400, 440], [1080, 1920, 420], [720, 1600, 320],
	[1600, 2560, 320], [2560, 1600, 320],

	[2556, 1179, 460], [1179, 2556, 460],
	[2360, 1640, 264], [1640, 2360, 264],
]


const LAYOUT_PAGES := ["main", "skirmish", "multiplayer", "multiplayer:create", "multiplayer:join",
					   "mp_lobby", "missions", "load", "options",
					   "controls", "content", "blocked"]


func _run_test_layout() -> void:
	if _resizer != null:
		_resizer.paused = true
	var lang_before := Lang.code()
	var total := 0


	var most := _selected
	for i in _skirmish.size():
		if most < 0 or int(_skirmish[i]["players"]) > int(_skirmish[most]["players"]):
			most = i
	if most >= 0:
		_on_map_selected(most)
	_set_ai(ProtoWorld.AI_PLAYER_INDICES.size())


	_mp_demo_lobby()
	_mp_demo_join()


	_update_text = tr("update.ready")
	_update_action = "restart"
	for lang in ["de", "en"]:
		Lang.set_language(lang)
		for e in LAYOUT_MATRIX:
			DisplayServer.window_set_size(Vector2i(e[0], e[1]))
			Dp.set_forced_dpi(float(e[2]))
			Dp.set_ui_scale(1.0)
			await get_tree().process_frame
			_rebuild_ui("main", false)
			for page in LAYOUT_PAGES:
				var parts: PackedStringArray = str(page).split(":")
				_show(parts[0])
				if parts.size() > 1 and _mp_page != null:
					_mp_page.show_mode(parts[1])
				for _i in 6:
					await get_tree().process_frame
				var real := DisplayServer.window_get_size()
				var tag := "%s %s %dx%d@%d (UI ×%.2f)" % [lang, page, real.x, real.y, e[2], Dp.ui_scale()]
				var v := LayoutCheck.violations(self, Dp.safe_rect(), tag)
				for line in v:
					print(line)
				total += v.size()
				var o := _update_bar_overlaps(tag)
				for line in o:
					print(line)
				total += o.size()
	Lang.set_language(lang_before)
	_update_text = ""
	_update_action = ""
	_refresh_update_bar()
	print("T: Layout-Prüfung fertig — %d Verstöße" % total)
	get_tree().quit()


class NotifyProbe extends RefCounted:
	var shown: Array = []
	var watching := ""

	func show(title: String, text: String) -> void:
		shown.append([title, text])

	func start_watch(_url: String, code: String, _token: String, _room: String) -> void:
		watching = code

	func stop_watch() -> void:
		watching = ""


class ClientProbe extends RefCounted:
	var url := "wss://pruef.invalid/ws"
	var client_id := "PRUEF"


func _run_test_notify() -> void:


	var fails := [0]
	var pruefe := func(ok: bool, was: String) -> void:
		if not ok:
			fails[0] += 1
			print("FEHLER: " + was)
		else:
			print("  ok — " + was)

	var vorher := {"enabled": NetNotify.enabled()}
	for e in NetNotify.EVENTS:
		vorher[e] = NetNotify.event_enabled(e)

	print("T: 1. Speichern und Wiederlesen ([notify] in user://settings.cfg)")
	for on in [false, true]:
		NetNotify.set_enabled(on)
		pruefe.call(NetNotify.enabled() == on, "Hauptschalter %s" % ("an" if on else "aus"))
	for e in NetNotify.EVENTS:
		NetNotify.set_event_enabled(e, false)
		pruefe.call(not NetNotify.event_enabled(e), "Anlass %s aus" % e)
		NetNotify.set_event_enabled(e, true)
		pruefe.call(NetNotify.event_enabled(e), "Anlass %s an" % e)

	print("T: 2. Der Hauptschalter steht über den Anlässen")
	NetNotify.set_enabled(false)
	pruefe.call(not NetNotify.any_event(), "aus → kein Anlass mehr an")
	NetNotify.set_enabled(true)
	pruefe.call(NetNotify.any_event(), "an → die Anlässe gelten wieder")

	print("T: 3. Was der Vordergrunddienst mitbekommt (events_flags)")
	NetNotify.set_event_enabled("chat", false)
	var flags := NetNotify.events_flags()
	pruefe.call(flags.size() == NetNotify.EVENTS.size(), "drei Anlässe im JSON")
	pruefe.call(flags.get("chat", true) == false and flags.get("join", false) == true,
			"chat aus, join an")
	NetNotify.set_enabled(false)
	var flags_off := NetNotify.events_flags()
	pruefe.call(not flags_off.values().has(true), "Hauptschalter aus → alles aus")
	NetNotify.set_enabled(true)
	NetNotify.set_event_enabled("chat", true)

	print("T: 4. Ein abgeschalteter Anlass löst nichts aus (net_hub)")
	var hub := NetHub.hub()
	var probe := NotifyProbe.new()
	var alt_notify = hub.notify
	var alt_paused: bool = hub._app_paused
	var alt_seat: int = hub.my_seat
	var alt_chat: Array = hub.chat
	hub.notify = probe
	hub._app_paused = true
	hub.my_seat = 0
	for fall in [["join", true], ["chat", true], ["start", true],
			["join", false], ["chat", false], ["start", false]]:
		var ev := str(fall[0])
		var an: bool = fall[1]
		NetNotify.set_event_enabled(ev, an)
		probe.shown.clear()
		if ev == "chat":
			hub.chat = []
			hub._on_chat({"seat": 1, "name": "Gegner", "text": "hallo", "scope": "all"})
		else:
			hub._local_notify("Raum", "Text", ev)
		pruefe.call(probe.shown.size() == (1 if an else 0),
				"%s %s → %d Meldung(en)" % [ev, "an" if an else "aus", probe.shown.size()])
		NetNotify.set_event_enabled(ev, true)

	NetNotify.set_enabled(false)
	probe.shown.clear()
	for ev2 in NetNotify.EVENTS:
		hub._local_notify("Raum", "Text", str(ev2))
	pruefe.call(probe.shown.is_empty(), "Hauptschalter aus → gar keine Meldung")

	print("T: 5. Kein Vordergrunddienst, solange der Hauptschalter aus ist")
	var alt_client = hub.client
	var alt_code: String = hub.code
	var alt_token: String = hub.token
	hub.client = ClientProbe.new()
	hub.code = "TEST"
	hub.token = "geheim"
	probe.watching = ""
	hub._start_watch()
	pruefe.call(probe.watching == "", "aus → `startWatch` bleibt aus")
	NetNotify.set_enabled(true)
	hub._start_watch()
	pruefe.call(probe.watching == "TEST", "an → Dienst läuft für den Raum")
	NetNotify.set_enabled(false)
	hub.refresh_watch()
	pruefe.call(probe.watching == "", "Umlegen bei offenem Raum → Dienst endet sofort")
	NetNotify.set_enabled(true)
	hub.refresh_watch()
	pruefe.call(probe.watching == "TEST", "und wieder an → Dienst kommt zurück")
	hub.client = alt_client
	hub.code = alt_code
	hub.token = alt_token
	hub.notify = alt_notify
	hub._app_paused = alt_paused
	hub.my_seat = alt_seat
	hub.chat = alt_chat

	print("T: 6. Ohne Plugin steht der Abschnitt nicht in den Optionen")
	NetNotify.force_ui = false
	pruefe.call(not NetNotify.supported(), "supported() am Schreibtisch: nein")
	_rebuild_ui("options", false)
	await get_tree().process_frame
	pruefe.call(_find_notify_block() == null, "Optionen ohne Benachrichtigungs-Abschnitt")
	NetNotify.force_ui = true
	_rebuild_ui("options", false)
	for _i in 4:
		await get_tree().process_frame
	var block := _find_notify_block()
	pruefe.call(block != null, "mit Plugin: Abschnitt da")


	print("T: 7. Tippflächen der neuen Schalter gegen den Bestand der Optionsseite")
	var neu: Array = []
	if block != null:
		_collect_buttons(block, neu)
	var alt: Array = []
	_collect_buttons(_pages["options"], alt)
	var alt_min := 1e9
	for b in alt:
		if neu.has(b):
			continue
		alt_min = minf(alt_min, _touch_dp(b))
	var neu_min := 1e9
	for b in neu:
		neu_min = minf(neu_min, _touch_dp(b))
	pruefe.call(neu.size() >= 8, "%d Knöpfe im Abschnitt (drei/vier Zeilen mit −/+ und Erlauben)" % neu.size())
	pruefe.call(neu_min >= alt_min - 0.5,
			"kleinste neue Tippfläche %.1f dp, Bestand %.1f dp" % [neu_min, alt_min])


	NetNotify.set_enabled(bool(vorher["enabled"]))
	for e in NetNotify.EVENTS:
		NetNotify.set_event_enabled(e, bool(vorher[e]))
	print("T: --test-benachrichtigungen fertig — %d Befund(e) (Sollwert 0)" % fails[0])
	get_tree().quit()


func _find_notify_block() -> Control:
	var p: Control = _pages.get("options", null)
	if p == null:
		return null
	return p.find_child("NotifyBlock", true, false) as Control


func _touch_dp(b: Node) -> float:
	var r: Rect2 = (b as Control).get_global_rect()
	return minf(Dp.to_device_dp(r.size.x), Dp.to_device_dp(r.size.y))


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


const FIT_PROFILES := [
	["xperia-quer", 2560, 1096, 420], ["xperia-hoch", 1096, 2560, 420],
	["iphone-quer", 2556, 1179, 460], ["iphone-hoch", 1179, 2556, 460],
	["ipad-quer", 2360, 1640, 264], ["ipad-hoch", 1640, 2360, 264],
]


func _run_test_content_fit() -> void:
	if _resizer != null:
		_resizer.paused = true
	var args := OS.get_cmdline_user_args()
	var dir := ""
	var dk := args.find("--content-shots")
	if dk >= 0 and dk + 1 < args.size():
		dir = args[dk + 1]
		DirAccess.make_dir_recursive_absolute(dir)
	var lang_before := Lang.code()
	var total := 0
	for lang in ["de", "en"]:
		Lang.set_language(lang)
		for pr in FIT_PROFILES:
			DisplayServer.window_set_size(Vector2i(int(pr[1]), int(pr[2])))
			Dp.set_forced_dpi(float(pr[3]))
			Dp.set_ui_scale(1.0)
			await get_tree().process_frame
			_rebuild_ui("content", false)
			for _i in 8:
				await get_tree().process_frame
			var real := DisplayServer.window_get_size()
			var tag := "%s %s %dx%d@%d" % [lang, pr[0], real.x, real.y, int(pr[3])]
			var rollt: bool = _content_page != null and _content_page.scroll_needed()
			for pos in ["oben", "unten"]:
				if pos == "unten":
					if _content_page != null:
						_content_page.scroll_to_end()
					for _i in 4:
						await get_tree().process_frame
				var v := LayoutCheck.fit_violations(_pages["content"], Dp.safe_rect(), tag + " " + pos)
				for line in v:
					print(line)
				total += v.size()
				if dir != "" and lang == "de":
					var path := "%s/fit-%s-%s.png" % [dir, pr[0], pos]
					get_viewport().get_texture().get_image().save_png(path)
					print("Screenshot: ", path)


			if _content_page != null:
				_content_page.scroll_to_top()
				_content_page.show_disclaimer()
				for _i in 4:
					await get_tree().process_frame
				var vd := LayoutCheck.fit_violations(_pages["content"], Dp.safe_rect(), tag + " hinweis")
				for line in vd:
					print(line)
				total += vd.size()
				if dir != "" and lang == "de":
					var pathd := "%s/fit-%s-hinweis.png" % [dir, pr[0]]
					get_viewport().get_texture().get_image().save_png(pathd)
					print("Screenshot: ", pathd)
				_content_page.close_disclaimer()
				await get_tree().process_frame
			print("T: content-fit %s — rollbar: %s" % [tag, "ja" if rollt else "nein (passt ganz)"])
	Lang.set_language(lang_before)
	print("T: --test-content-fit fertig — %d Fehler" % total)
	get_tree().quit()


func _run_test_touch_scroll() -> void:
	if _resizer != null:
		_resizer.paused = true
	Input.set_emulate_touch_from_mouse(true)


	DisplayServer.window_set_size(Vector2i(1096, 1000))
	Dp.set_forced_dpi(420.0)
	Dp.set_ui_scale(1.0)
	await get_tree().process_frame
	var fehler := 0
	fehler += await _touch_scroll_page("Spielinhalte", "content")
	fehler += await _touch_scroll_page("Optionen", "options")
	fehler += await _touch_scroll_page("Protokoll", "log")
	print("T: --test-touch-scroll fertig — %d Fehler" % fehler)
	get_tree().quit()


func _touch_scroll_page(titel: String, page: String) -> int:
	_rebuild_ui(page, false)
	for _i in 8:
		await get_tree().process_frame
	var scroll := _touch_scroll_container(page)
	if scroll == null:
		print("FEHLER: %s — keine Rollfläche gefunden" % titel)
		return 1
	var bar := scroll.get_v_scroll_bar()
	if bar.max_value <= bar.page + 1.0:
		print("T: touch-scroll %s — passt ganz, nichts zu rollen" % titel)
		return 0
	var fehler := 0
	for probe in [["Text", "Label"], ["Karte", "PanelContainer"], ["Knopf", "Button"]]:
		var c := await _touch_scroll_pick(scroll, str(probe[1]))
		if c == null:
			print("T: touch-scroll %s %s — kein erreichbares Ziel (übersprungen)" % [titel, probe[0]])
			continue
		var d := await _touch_scroll_drag(scroll, c)
		var ok: bool = d >= 40
		if not ok:
			fehler += 1
		print("%s touch-scroll %s: Zug über %s „%s“ rollte %d px%s" % [
				"T:" if ok else "FEHLER:", titel, probe[0], _touch_scroll_name(c), d,
				"" if ok else " — erwartet mindestens 40 px"])

	var btn := await _touch_scroll_pick(scroll, "Button")
	if btn != null:
		var tipp := await _touch_scroll_press_count(scroll, btn as Button, false)
		var zug := await _touch_scroll_press_count(scroll, btn as Button, true)
		var ok2 := tipp == 1 and zug == 0
		if not ok2:
			fehler += 1
		print("%s touch-scroll %s: Tipp auf „%s“ löst aus (%d), Zug darüber nicht (%d)" % [
				"T:" if ok2 else "FEHLER:", titel, (btn as Button).text, tipp, zug])

	var slider := await _touch_scroll_pick(scroll, "HSlider")
	if slider != null:
		var ds := await _touch_scroll_drag(scroll, slider)
		var ok3 := ds == 0
		if not ok3:
			fehler += 1
		print("%s touch-scroll %s: Zug über dem Lautstärkeregler rollte %d px (erwartet 0)" % [
				"T:" if ok3 else "FEHLER:", titel, ds])
	return fehler


func _touch_scroll_container(page: String) -> ScrollContainer:
	if page == "content":
		return _content_page.scroll_node() if _content_page != null else null
	if page == "options":
		return _options_scroll
	if page == "log":
		return _log_view.scroll_node() if _log_view != null else null
	return null


func _touch_scroll_name(c: Control) -> String:
	if c is Button:
		return (c as Button).text
	if c is Label:
		return (c as Label).text.substr(0, 24)
	return c.get_class()


func _touch_scroll_candidates(scroll: ScrollContainer, cls: String) -> Array:
	var out: Array = []
	var stack: Array = []
	var kids := scroll.get_children()
	kids.reverse()
	for c in kids:
		if not (c is ScrollBar):
			stack.append(c)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c: Control = n
			if not c.is_visible_in_tree():
				continue
			var r := c.get_global_rect()
			if c.is_class(cls) and r.size.x >= 40.0 and r.size.y >= 20.0:
				out.append(c)
		var ch := n.get_children()
		ch.reverse()
		for x in ch:
			stack.append(x)
	return out


func _touch_scroll_pick(scroll: ScrollContainer, cls: String) -> Control:
	for c in _touch_scroll_candidates(scroll, cls):
		if await _touch_scroll_show(scroll, c) != Vector2.ZERO:
			return c
	return null


const _TS_ROOM := 200
const _TS_STEP := 14
const _TS_STEPS := 12


func _touch_scroll_show(scroll: ScrollContainer, c: Control) -> Vector2:
	var bar := scroll.get_v_scroll_bar()
	var maxs := int(maxf(bar.max_value - bar.page, 0.0))
	var view := scroll.get_global_rect()
	var soll := scroll.scroll_vertical + int(c.get_global_rect().get_center().y - (view.position.y + view.size.y * 0.3))
	scroll.scroll_vertical = clampi(soll, 0, maxi(maxs - _TS_ROOM, 0))
	for _i in 4:
		await get_tree().process_frame
	var inter := scroll.get_global_rect().intersection(c.get_global_rect())
	if inter.size.x < 40.0 or inter.size.y < 20.0:
		return Vector2.ZERO
	return inter.get_center()


func _touch_scroll_drag(scroll: ScrollContainer, c: Control) -> int:
	var p := await _touch_scroll_show(scroll, c)
	if p == Vector2.ZERO:
		return -1
	var vorher := scroll.scroll_vertical
	_touch(p, true)
	await get_tree().process_frame
	for i in _TS_STEPS:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p - Vector2(0, float(_TS_STEP * (i + 1)))
		d.relative = Vector2(0, -_TS_STEP)
		Input.parse_input_event(d)
		await get_tree().process_frame
	var strecke := scroll.scroll_vertical - vorher
	_touch(p - Vector2(0, _TS_STEP * _TS_STEPS), false)


	for _i in 30:
		await get_tree().process_frame
	return strecke


func _touch_scroll_press_count(scroll: ScrollContainer, btn: Button, ziehen: bool) -> int:
	var saved := btn.pressed.get_connections()
	for con in saved:
		btn.pressed.disconnect(con["callable"])
	var zaehler := [0]
	var counter := func(): zaehler[0] += 1
	btn.pressed.connect(counter)
	if ziehen:
		await _touch_scroll_drag(scroll, btn)
	else:
		var p := await _touch_scroll_show(scroll, btn)
		if p != Vector2.ZERO:
			_touch(p, true)
			await get_tree().process_frame
			_touch(p, false)
			await get_tree().process_frame
			await get_tree().process_frame
	btn.pressed.disconnect(counter)
	for con in saved:
		btn.pressed.connect(con["callable"], int(con.get("flags", 0)))
	return zaehler[0]


func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _update_bar_overlaps(tag: String) -> Array:
	var out: Array = []
	if _update_bar == null or not _update_bar.visible or _root == null:
		return out
	var bar := Rect2(_update_bar.global_position, _update_bar.size)
	var stack: Array = [_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c: Control = n
			if not c.is_visible_in_tree():
				continue

			if c is Button and c.size.x > 1.0 and c.size.y > 1.0 and not LayoutCheck.in_scroll(c):
				var r := HudTheme.visible_rect(c)
				var inter := r.intersection(bar)
				if inter.size.x > 1.0 and inter.size.y > 1.0:
					out.append("LAYOUT: %s %s (Button) liegt unter der Statuszeile: %s ∩ %s" % [tag, c.name, r, bar])
		for ch in n.get_children():
			stack.append(ch)
	return out


var _page := "main"
var _controls_box: VBoxContainer


var _controls_return := "main"
var _content_page: ContentPage

var _options_scroll: ScrollContainer
var _log_view: LogView

var _log_return := "content"


var _content_return := "main"


var _resizer: Desktop.Resizer


func _on_window_resized() -> void:
	Dp.set_ui_scale(1.0)
	_rebuild_ui(_page)


func _rebuild_ui(page: String, refit: bool = true) -> void:


	if _update != null and _update.get_parent() == self:
		remove_child(_update)


	if _resizer != null and _resizer.get_parent() == self:
		remove_child(_resizer)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_ui()
	if _update != null:
		add_child(_update)
	if _resizer != null:
		add_child(_resizer)
	_show(page, refit)


func _fit_page(page: String, tries: int = 3) -> void:
	if tries <= 0:
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree() or _page != page:
		return
	var safe := Dp.safe_rect()
	var root: Control = _pages.get(page, null)
	if root == null:
		return
	var need := root.get_combined_minimum_size()
	var f := Dp.ui_scale()
	if (need.y > safe.size.y or need.x > safe.size.x) and f > 0.8:
		var factor := minf(safe.size.y / maxf(need.y, 1.0), safe.size.x / maxf(need.x, 1.0))
		Dp.set_ui_scale(maxf(f * clampf(factor, 0.75, 0.99), 0.8))
		_rebuild_ui(page, false)
		await _fit_page(page, tries - 1)


func _show(page: String, refit: bool = true) -> void:


	if page == "skirmish" and _skirmish.is_empty() and ContentManager.available():
		ContentPaths.refresh()
		_scan_maps()
		if not _skirmish.is_empty():
			_rebuild_ui(page, refit)
			return


	if page == "controls" and _page != "controls":
		_controls_return = _page
	if page == "content" and _page != "content":
		_content_return = "main" if _page == "main" else "options"
	if page == "log" and _page != "log":
		_log_return = _page
	_page = page
	_refresh_update_bar()
	for k in _pages:
		_pages[k].visible = k == page

	if page == "controls":
		for c in _controls_box.get_children():
			_controls_box.remove_child(c)
			c.queue_free()
		var safe := Dp.safe_rect()
		_controls_box.add_child(GestureHelp.panel(tr("menu.controls"), tr("ui.back"), func(): _show(_controls_return),
				safe.size.y - Dp.px(40), safe.size.x - Dp.px(60)))
	if page == "content" and _content_page != null:
		_content_page.refresh_status()
	if page == "mp_lobby" and _mp_lobby != null:
		_mp_lobby.refresh()
	if page == "multiplayer" and _mp_page != null and _mp_demo_mode != "":
		_mp_page.show_mode(_mp_demo_mode)
	if page == "log" and _log_view != null:
		_log_view.refresh()
	if refit:
		_fit_page(page)


func _go_test_window() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Desktop.apply_test_window()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _page == "blocked":
		get_tree().quit()
	elif _page == "controls":
		_show(_controls_return)
	elif _page == "log":
		_show(_log_return)
	elif _page == "mp_lobby":
		_show("multiplayer")
	elif _page != "main":
		_show("main")
	else:
		get_tree().quit()


func _music_text() -> String:
	return tr("options.music_on") if Music.enabled_default else tr("options.music_off")


func _music_source_text() -> String:
	var mp = get_node_or_null("/root/MusicPlayer")
	var own: bool = mp != null and mp.source == Music.SOURCE_OWN
	return tr("options.music_source_own") if own else tr("options.music_source_original")


var _music_title_lbl: Label


func _on_track_changed(_name: String, _title: String) -> void:
	_refresh_music_title()


func _refresh_music_title() -> void:
	if _music_title_lbl == null or not is_instance_valid(_music_title_lbl):
		return
	var mp = get_node_or_null("/root/MusicPlayer")
	var t: String = str(mp.current_title()) if mp != null else ""
	_music_title_lbl.text = (tr("options.music_now") % t) if t != "" else ""
	_music_title_lbl.visible = t != ""


var _update: UpdateService
var _update_page: UpdatePage
var _update_bar: HBoxContainer

var _update_text := ""
var _update_action := ""
var _update_apk_url := ""


var _update_apk_label := ""
var _update_outcome := ""


var _app_avail := ""
var _app_dialog: Control


func _start_update_service(args: PackedStringArray) -> void:
	if args.has("--no-update-check"):
		return
	_update = UpdateService.new()
	add_child(_update)
	_update.status.connect(func(text: String):
		_update_text = text
		_refresh_update_bar())
	_update.update_ready.connect(func():
		_update_action = "restart"
		_refresh_update_bar())
	_update.needs_new_app.connect(func(url: String, label: String):
		_update_action = "apk"
		_update_apk_url = url
		_update_apk_label = label
		_refresh_update_bar())


	_update.new_app_available.connect(_on_new_app_available)


	_update.block_changed.connect(func():
		if _update_page != null:
			_update_page.rebuild()
		_rebuild_ui("blocked" if UpdateConfig.blocked() else "main"))
	_update.finished.connect(func(outcome: String):
		_update_outcome = outcome)

	_update.start.call_deferred(args.has("--test-update") or args.has("--update-url"))
	if args.has("--test-update"):
		_shot_manual = true
		_run_test_update.call_deferred()


func _build_update_bar() -> void:
	var safe := Dp.safe_rect()
	_update_bar = HBoxContainer.new()
	_update_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_update_bar.add_theme_constant_override("separation", int(Dp.px(8)))
	_update_bar.position = Vector2(safe.position.x, safe.end.y - Dp.px(UPDATE_BAR_RESERVE_DP - 4.0))
	_update_bar.size = Vector2(safe.size.x, Dp.px(30))
	_update_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_update_bar)
	_refresh_update_bar()


const UPDATE_BAR_RESERVE_DP := 70.0


func _apply_update_reserve() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var reserve := 0.0
	if _update_bar != null and is_instance_valid(_update_bar) and _update_bar.visible:
		var vs := get_viewport().get_visible_rect().size
		reserve = maxf(vs.y - (Dp.safe_rect().end.y - Dp.px(UPDATE_BAR_RESERVE_DP)), 0.0)
	_root.offset_bottom = -reserve


func _refresh_update_bar() -> void:
	if _update_bar == null or not is_instance_valid(_update_bar):
		return
	for c in _update_bar.get_children():
		_update_bar.remove_child(c)
		c.queue_free()

	var app_line := (tr("update.app_available") % _app_avail) if _app_avail != "" else ""


	if app_line != "" and _update_apk_label != "":
		app_line += " — %s" % _update_apk_label
	if (_update_text == "" and _update_action == "" and app_line == "") or _page != "main":
		_update_bar.visible = false
		_apply_update_reserve()
		return
	_update_bar.visible = true
	_apply_update_reserve()
	var l := Label.new()


	l.text = _update_text if app_line == "" else \
			(app_line if _update_text == "" else "%s · %s" % [_update_text, app_line])
	l.add_theme_font_size_override("font_size", int(Dp.px(12)))
	l.add_theme_color_override("font_color", HudTheme.GOLD)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", int(Dp.px(1)))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_update_bar.add_child(l)
	if _update_action == "restart":


		if UpdateConfig.restart_supported():
			_update_bar.add_child(_button(tr("update.restart_now"), func():
				Sfx.click(self)
				UpdateConfig.restart(get_tree()), 160, 26))
		else:
			var hint := Label.new()
			hint.text = tr("update.restart_hint")
			hint.add_theme_font_size_override("font_size", int(Dp.px(11)))
			hint.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_update_bar.add_child(hint)
	elif _update_action == "apk" and _update_apk_url != "":
		if _update_apk_label != "" and app_line == "":

			var flav := Label.new()
			flav.text = _update_apk_label
			flav.add_theme_font_size_override("font_size", int(Dp.px(11)))
			flav.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
			flav.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_update_bar.add_child(flav)


		_update_bar.add_child(_button(tr(UpdateConfig.get_app_key()), func():
			Sfx.click(self)
			OS.shell_open(_update_apk_url), 200, 26))


func _on_new_app_available(version: String, notes: String, apk_url: String, apk_label: String) -> void:
	_app_avail = version
	_update_apk_url = apk_url if apk_url != "" else _update_apk_url
	_update_apk_label = apk_label
	_refresh_update_bar()
	if UpdateConfig.apk_seen() == version:
		AppLogger.info("MainMenu", "Neue App %s — Fenster schon gezeigt, nur Statuszeile" % version)
		return
	UpdateConfig.set_apk_seen(version)
	_show_app_dialog(version, notes, apk_url, apk_label)


func _show_app_dialog(version: String, notes: String, apk_url: String, apk_label: String = "") -> void:
	if _app_dialog != null and is_instance_valid(_app_dialog):
		return
	var safe := Dp.safe_rect()
	_app_dialog = Control.new()
	_app_dialog.name = "AppUpdateDialog"
	_app_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_app_dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_app_dialog)
	HudTheme.dim_backdrop(_app_dialog)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(16.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(10)))
	panel.add_child(box)
	var head := Label.new()
	head.text = tr("update.app_new_title") % version
	head.add_theme_font_size_override("font_size", int(Dp.px(17)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var body := Label.new()


	body.text = notes if notes.strip_edges() != "" else tr("update.app_new_body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", int(Dp.px(13)))
	body.add_theme_color_override("font_color", HudTheme.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(minf(Dp.px(420), safe.size.x - Dp.px(60)), 0)
	box.add_child(body)


	if apk_label != "":
		var flavor := Label.new()
		flavor.text = tr("update.app_new_edition") % apk_label
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flavor.add_theme_font_size_override("font_size", int(Dp.px(12)))
		flavor.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.custom_minimum_size = Vector2(minf(Dp.px(420), safe.size.x - Dp.px(60)), 0)
		box.add_child(flavor)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(Dp.px(10)))
	if apk_url != "":
		row.add_child(_button(tr("update.app_new_get"), func():
			Sfx.click(self)
			OS.shell_open(apk_url)
			_close_app_dialog(), 180, 40))
	row.add_child(_button(tr("update.app_new_later"), func():
		Sfx.click(self)
		_close_app_dialog(), 160, 40))
	box.add_child(row)
	_app_dialog.add_child(panel)

	await get_tree().process_frame
	if _app_dialog == null or not is_instance_valid(_app_dialog):
		return
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = safe.position + (safe.size - sz) / 2.0
	AppLogger.info("MainMenu", "Hinweis auf die neue App-Version %s gezeigt" % version)


func _close_app_dialog() -> void:
	if _app_dialog != null and is_instance_valid(_app_dialog):
		_app_dialog.queue_free()
	_app_dialog = null


func _run_platform_matrix() -> void:
	var mager := {"apk_version": "9.9", "apk_url": "https://x/pocketra.apk", "apk_size": 122000000,
			"windows_url": "https://x/pocketra-windows-setup.exe", "windows_size": 210000000,
			"mac_url": "https://x/pocketra-macos.dmg", "mac_size": 190000000}
	var reich := mager.duplicate()
	reich["ios_version"] = "9.9"
	reich["ios_url"] = "https://testflight.apple.com/join/ABCDEFGH"
	var faelle := [

		["iOS", mager, "", "", false],
		["iOS", reich, "https://testflight.apple.com/join/ABCDEFGH", "9.9", false],
		["Android", mager, "https://x/pocketra.apk", "9.9", true],
		["Windows", mager, "https://x/pocketra-windows-setup.exe", "9.9", true],
		["macOS", mager, "https://x/pocketra-macos.dmg", "9.9", true],
	]
	var fehler := 0
	for f in faelle:
		UpdateConfig.set_test_platform(str(f[0]))
		var wahl := UpdateConfig.app_choice(f[1])
		var url := str(wahl.get("url", ""))
		var fern := UpdateConfig.remote_app_version(f[1])
		var paket := UpdateConfig.pack_enabled()
		var ok: bool = url == str(f[2]) and fern == str(f[3]) and paket == bool(f[4])

		var meldet := UpdateConfig.app_outdated(fern)
		if str(f[3]) == "" and meldet:
			ok = false
		print("T: Update — Weiche %-8s → Art %-7s URL %-46s Fernversion %-4s Paket %-5s meldet %-5s — %s" % [
				f[0], str(wahl.get("kind", "?")), url if url != "" else "(keine)",
				fern if fern != "" else "(keine)", str(paket), str(meldet),
				"OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1


	UpdateConfig.set_test_platform("")
	print("T: Update — Plattformweichen: %d Fehlschlag/Fehlschläge (Sollwert 0)" % fehler)


func _run_test_maps_unlock() -> void:
	var before := _skirmish.size()
	var off := ContentPaths.ATLAS + ".off"
	if DirAccess.dir_exists_absolute(off):
		DirAccess.rename_absolute(off, ContentPaths.ATLAS)
	_on_content_unlocked()
	_show("skirmish")
	for _i in 12:
		await get_tree().process_frame
	print("T: Karten — vorher %d, nachher %d (%s)" % [before, _skirmish.size(),
			"OK" if before == 0 and _skirmish.size() > 0 else "FEHLER"])
	if _shot_path != "":
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
	get_tree().quit(0 if before == 0 and _skirmish.size() > 0 else 1)


func _run_test_update() -> void:


	var until := Time.get_ticks_msec() + 120000
	while _update_outcome == "" and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	for _i in 8:
		await get_tree().process_frame
	print("T: Update — Ergebnis %s, eigenes Paket %d, Extension %s, gesperrt %s" % [
			_update_outcome if _update_outcome != "" else "keine Antwort",
			UpdateConfig.pack_version(), UpdateConfig.extension_version(), str(UpdateConfig.blocked())])

	print("T: Update — neue App gemeldet: %s, Fenster offen: %s, gemerkt: %s" % [
			_app_avail if _app_avail != "" else "nein",
			str(_app_dialog != null and is_instance_valid(_app_dialog)),
			UpdateConfig.apk_seen() if UpdateConfig.apk_seen() != "" else "nichts"])

	print("T: Update — eigene Fassung %s, angeboten %s, URL %s" % [
			UpdateConfig.edition_name(UpdateConfig.full_edition()),
			_update_apk_label if _update_apk_label != "" else "nichts",
			_update_apk_url if _update_apk_url != "" else "nichts"])


	print("T: Update — Plattform %s, Paket erlaubt: %s, Knopf '%s', Sperrtext '%s'" % [
			UpdateConfig.platform(), UpdateConfig.pack_enabled(),
			tr(UpdateConfig.get_app_key()), UpdateConfig.blocked_default_key()])
	_run_platform_matrix()
	if _shot_path != "":
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
	get_tree().quit()


static func _has_tileset(t: String) -> bool:
	return ContentPaths.has_atlas(t)


const TILESET_KEYS := {"temperat": "tileset.temperat", "snow": "tileset.snow", "desert": "tileset.desert", "interior": "tileset.interior"}


func _tileset_name(t: String) -> String:
	return tr(TILESET_KEYS[t]) if TILESET_KEYS.has(t) else t


var _mp_page: Control
var _mp_lobby: Control
var _map_scroll: ScrollContainer
var _slot_box: VBoxContainer
var _player_team := 0
var _spawn_choice := -1
var _map_overlay: Control


func _map_json(slug: String) -> Dictionary:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _show_map_overlay() -> void:
	if _selected < 0 or _map_overlay != null:
		return
	var m: Dictionary = _skirmish[_selected]
	var slug := str(m.get("slug", ""))
	var data := _map_json(slug)
	var bounds: Array = data.get("bounds", [0, 0, int(data.get("width", 64)), int(data.get("height", 64))])
	var spawns: Array = data.get("spawns", [])
	var safe := Dp.safe_rect()
	_map_overlay = Control.new()
	_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_overlay.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_close_map_overlay())
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_overlay.add_child(bg)
	var head := Label.new()
	var size_arr: Array = m.get("size", [0, 0])
	head.text = "%s — %d×%d — %d %s" % [m.get("title", slug), int(size_arr[0]), int(size_arr[1]),
			int(m.get("players", 0)), tr("lobby.slots")]
	head.add_theme_font_size_override("font_size", int(Dp.px(16)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	head.position = Vector2(safe.position.x + Dp.px(16), safe.position.y + Dp.px(8))
	head.size = Vector2(safe.size.x - Dp.px(32), Dp.px(24))
	_map_overlay.add_child(head)
	var hint := Label.new()
	hint.text = tr("lobby.map_hint")
	hint.add_theme_font_size_override("font_size", int(Dp.px(12)))
	hint.add_theme_color_override("font_color", HudTheme.TEXT)
	hint.position = Vector2(safe.position.x + Dp.px(16), safe.position.y + Dp.px(32))
	hint.size = Vector2(safe.size.x - Dp.px(32), Dp.px(20))
	_map_overlay.add_child(hint)

	var area := Rect2(safe.position + Vector2(Dp.px(16), Dp.px(58)),
			safe.size - Vector2(Dp.px(32), Dp.px(58 + 60)))
	var tex: Texture2D = _preview.texture
	var ar := 1.0
	if tex != null and tex.get_height() > 0:
		ar = float(tex.get_width()) / float(tex.get_height())
	var draw_size := Vector2(area.size.y * ar, area.size.y)
	if draw_size.x > area.size.x:
		draw_size = Vector2(area.size.x, area.size.x / ar)
	var draw_pos := area.position + (area.size - draw_size) / 2.0
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = draw_pos
	pic.size = draw_size
	_map_overlay.add_child(pic)

	var bx := float(bounds[0])
	var by := float(bounds[1])
	var bw := maxf(float(bounds[2]), 1.0)
	var bh := maxf(float(bounds[3]), 1.0)
	for i in spawns.size():
		var sp: Array = spawns[i]
		var rel := Vector2((float(sp[0]) - bx) / bw, (float(sp[1]) - by) / bh)
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(Dp.px(44), Dp.px(44))
		b.size = b.custom_minimum_size
		HudTheme.style_button(b, 14.0)
		if i == _spawn_choice:
			b.add_theme_color_override("font_color", HudTheme.GOLD)
		b.position = draw_pos + rel * draw_size - b.size / 2.0
		var idx := i
		b.pressed.connect(func():
			Sfx.click(self)
			_spawn_choice = -1 if _spawn_choice == idx else idx
			_close_map_overlay()
			_update_factions())
		_map_overlay.add_child(b)
	var back := _button(tr("ui.back"), func(): _close_map_overlay(), 140, 44)
	back.position = Vector2(safe.position.x + (safe.size.x - Dp.px(140)) / 2.0,
			safe.position.y + safe.size.y - Dp.px(52))
	back.size = Vector2(Dp.px(140), Dp.px(44))
	_map_overlay.add_child(back)
	add_child(_map_overlay)


func _close_map_overlay() -> void:
	if _map_overlay != null:
		_map_overlay.queue_free()
		_map_overlay = null

var _ai_slots: Array = []


func _slot_defaults() -> void:


	while _ai_slots.size() < ProtoWorld.AI_PLAYER_INDICES.size():
		_ai_slots.append({"faction": "random", "team": 0, "level": _ai_difficulty, "strategy": "normal"})


	for slot in _ai_slots:
		if slot is Dictionary and not slot.has("strategy"):
			slot["strategy"] = "normal"


func _rebuild_slots() -> void:
	if _slot_box == null:
		return
	_slot_defaults()
	for c in _slot_box.get_children():
		_slot_box.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = tr("lobby.slots")
	head.add_theme_font_size_override("font_size", int(Dp.px(12)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	_slot_box.add_child(head)

	var me := HBoxContainer.new()
	me.add_theme_constant_override("separation", int(Dp.px(6)))
	var me_label := Label.new()
	me_label.text = tr("lobby.you")
	me_label.custom_minimum_size = Vector2(Dp.px(52), 0)
	me_label.add_theme_font_size_override("font_size", int(Dp.px(12)))
	me_label.add_theme_color_override("font_color", HudTheme.TEXT)
	me.add_child(me_label)
	me.add_child(_button(_faction_name(_faction), func():
		_faction = _next_faction_value(_faction)
		_update_factions(), 110, 34))
	me.add_child(_button(_team_name(_player_team), func():
		_player_team = (_player_team + 1) % 5
		_update_factions(), 90, 34))
	me.add_child(_button(tr("lobby.spawn") % (str(_spawn_choice + 1) if _spawn_choice >= 0 else tr("lobby.spawn_random")),
			func(): _show_map_overlay(), 140, 34))
	_slot_box.add_child(me)
	for i in _ai_players:
		var slot: Dictionary = _ai_slots[i]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", int(Dp.px(6)))
		var l := Label.new()
		l.text = tr("lobby.ai") % (i + 1)
		l.custom_minimum_size = Vector2(Dp.px(46), 0)
		l.add_theme_font_size_override("font_size", int(Dp.px(12)))
		l.add_theme_color_override("font_color", HudTheme.TEXT)
		r.add_child(l)
		var idx := i


		r.add_child(_button(_faction_name(str(slot.get("faction", "random"))), func():
			_ai_slots[idx]["faction"] = _next_faction_value(str(_ai_slots[idx].get("faction", "random")))
			_update_factions(), 96, 34))
		r.add_child(_button(_team_name(int(slot.get("team", 0))), func():
			_ai_slots[idx]["team"] = (int(_ai_slots[idx].get("team", 0)) + 1) % 5
			_update_factions(), 76, 34))
		r.add_child(_button(tr(AI_DIFFICULTY_KEYS.get(str(slot.get("level", "normal")), "menu.skirmish.ai_normal")), func():
			var d: Array = ProtoWorld.AI_DIFFICULTIES
			_ai_slots[idx]["level"] = d[(d.find(str(_ai_slots[idx].get("level", "normal"))) + 1) % d.size()]
			_update_factions(), 96, 34))


		r.add_child(_button(tr(AI_STRATEGY_KEYS.get(str(slot.get("strategy", "normal")), "menu.skirmish.strat_normal")), func():
			var s: Array = ProtoWorld.AI_STRATEGIES
			_ai_slots[idx]["strategy"] = s[(s.find(str(_ai_slots[idx].get("strategy", "normal"))) + 1) % s.size()]
			_update_factions(), 96, 34))
		_slot_box.add_child(r)


func _on_map_selected(i: int) -> void:
	if i != _selected:
		_spawn_choice = -1
	_selected = i
	for k in _map_buttons.size():
		_map_buttons[k].button_pressed = k == i

	if _map_scroll != null and i >= 0 and i < _map_buttons.size():
		_map_scroll.ensure_control_visible.call_deferred(_map_buttons[i])
	var m: Dictionary = _skirmish[i]
	var path := "res://assets/maps/%s.png" % m["slug"]
	_preview.texture = load(path) if ResourceLoader.exists(path) else null
	var size: Array = m.get("size", [0, 0])
	_info.text = tr("menu.skirmish.map_info") % [m["title"], int(m["players"]), _tileset_name(m["tileset"]), int(size[0]), int(size[1])]
	_set_ai(_ai_players)


func _max_ai() -> int:
	var cap: int = ProtoWorld.AI_PLAYER_INDICES.size()
	if _selected >= 0:
		return maxi(1, mini(int(_skirmish[_selected]["players"]) - 1, cap))
	return 1


func _set_ai(n: int) -> void:
	_ai_players = clampi(n, 1, _max_ai())
	if _ai_label != null:
		_ai_label.text = tr("menu.skirmish.ai_count") % _ai_players


	_update_factions()


func _set_credits(c: int) -> void:
	_credits = clampi(c, 2500, 20000)
	_credits_label.text = tr("menu.skirmish.credits") % _credits


func _start_skirmish() -> void:
	if _selected < 0:
		return
	_save_settings()
	ProtoWorld.next_map = _skirmish[_selected]["slug"]
	ProtoWorld.next_mission = ""
	ProtoWorld.next_ai_players = _ai_players
	ProtoWorld.next_credits = _credits
	ProtoWorld.next_faction = _faction
	ProtoWorld.next_ai_faction = _ai_faction
	ProtoWorld.next_starting_units = _starting_units
	ProtoWorld.next_crates = _crates
	ProtoWorld.next_explored_map = _explored_map
	ProtoWorld.next_fog = _fog
	ProtoWorld.next_ai_difficulty = _ai_difficulty
	ProtoWorld.next_player_spawn = _spawn_choice
	ProtoWorld.next_player_team = _player_team
	ProtoWorld.next_ai_slots = _ai_slots.duplicate(true)
	get_tree().change_scene_to_file(GAME_SCENE)


func _run_test_voice_lobby() -> void:
	_mp_demo_lobby()
	_show("mp_lobby")
	for _i in 6:
		await get_tree().process_frame
	var fehler := 0
	var hub := NetHub.hub()
	var v = hub.ensure_voice()
	v.test_tone = true
	var btn: Button = _mp_lobby._mic_btn
	if btn == null:
		print("T --test-voice-lobby: FEHLER — kein Mikrofonknopf in der Lobby")
		print("T --test-voice-lobby: 1 Befund(e) (Sollwert 0)")
		get_tree().quit()
		return


	var alt: Array = []
	_collect_buttons(_pages["mp_lobby"], alt)
	var klein := Vector2(1e9, 1e9)
	for b in alt:
		if b == btn:
			continue
		var r: Vector2 = (b as Control).get_global_rect().size
		if r.x > 1.0 and r.y > 1.0:
			klein = Vector2(minf(klein.x, r.x), minf(klein.y, r.y))
	var groesse := btn.get_global_rect().size
	print("T --test-voice-lobby: Tippfläche %.0f×%.0f px (kleinster Knopf der Lobby %.0f×%.0f)" % [
			groesse.x, groesse.y, klein.x, klein.y])
	if groesse.x < klein.x - 0.5 or groesse.y < klein.y - 0.5:
		print("T --test-voice-lobby: FEHLER — Mikrofonknopf kleiner als der Bestand der Lobby")
		fehler += 1
	for fall in [{"hold": false, "mode": VoiceChat.Mode.TEAM, "col": HudTheme.VOICE_TEAM, "name": "Tipp → Team"},
			{"hold": true, "mode": VoiceChat.Mode.ALL, "col": HudTheme.VOICE_ALL, "name": "Langdruck → alle"}]:
		_mp_lobby._toggle_mic(bool(fall["hold"]))
		await get_tree().process_frame
		var ok: bool = int(v.mode) == int(fall["mode"]) \
				and btn.get_theme_color("icon_normal_color").is_equal_approx(fall["col"])
		print("T --test-voice-lobby: %s, Farbe %s — %s" % [fall["name"],
				(fall["col"] as Color).to_html(false), "OK" if ok else "FEHLER"])
		fehler += 0 if ok else 1

	AudioMix.settle()
	var musik := AudioServer.get_bus_index(AudioMix.BUSES["music"])
	var basis := linear_to_db(maxf(AudioMix.volume("music"), 0.0001))
	var ist := AudioServer.get_bus_volume_db(musik) if musik >= 0 else basis
	print("T --test-voice-lobby: Menümusik %+.1f dB (Regler %+.1f dB) — %s" % [ist, basis,
			AudioMix.state_line()])
	if ist >= basis - 1.0:
		print("T --test-voice-lobby: FEHLER — Menümusik wurde beim Funken nicht abgesenkt")
		fehler += 1

	var pkt := VoiceChat.test_packet(300.0)
	for i in 12:
		v.on_packet({"seat": 1, "name": "Jan", "color": 1, "scope": "team", "seq": i, "data": pkt})
		v.on_packet({"seat": 2, "name": "Ada", "color": 2, "scope": "all", "seq": i, "data": pkt})
	_mp_lobby._refresh_speakers()
	await get_tree().process_frame
	var zwei: bool = v.speaking_seats().size() == 2 and _mp_lobby._speak_lbl.visible
	print("T --test-voice-lobby: zwei Sprecher angezeigt — %s (%s)" % ["OK" if zwei else "FEHLER",
			_mp_lobby._speak_lbl.text.replace("\n", " | ")])
	fehler += 0 if zwei else 1
	v.set_muted(1, true)
	for i in 12:
		v.on_packet({"seat": 1, "name": "Jan", "color": 1, "scope": "team", "seq": 20 + i, "data": pkt})
	var stumm: bool = not v.speaking_seats().has(1)
	print("T --test-voice-lobby: Platz stumm geschaltet — %s" % ["OK" if stumm else "FEHLER"])
	fehler += 0 if stumm else 1
	v.set_muted(1, false)

	_mp_lobby._toggle_mic(true)
	AudioMix.settle()
	await get_tree().process_frame
	var zurueck: bool = int(v.mode) == int(VoiceChat.Mode.OFF) \
			and absf(AudioServer.get_bus_volume_db(musik) - basis) < 0.2
	print("T --test-voice-lobby: aus → Musik wieder %+.1f dB — %s" % [
			AudioServer.get_bus_volume_db(musik), "OK" if zurueck else "FEHLER"])
	fehler += 0 if zurueck else 1
	if _shot_path != "":
		_mp_lobby._toggle_mic(false)
		for _i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
	print("T --test-voice-lobby: %d Befund(e) (Sollwert 0)" % fehler)
	get_tree().quit()
