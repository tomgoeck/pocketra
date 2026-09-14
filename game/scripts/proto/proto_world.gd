

class_name ProtoWorld
extends Node2D

const CELL := 24

static var next_map := ""
static var next_ai_players := 1
static var next_credits := 5000
static var next_starting_units := "none"

static var next_crates := true


static var next_crate_action := -1


static var next_explored_map := false
static var next_fog := true

const STARTING_UNITS := {
	"light": {"allies": ["e1", "e1", "e1", "e3", "e3", "jeep", "1tnk"], "soviet": ["e1", "e1", "e1", "e3", "e3", "apc", "ftrk"]},
	"heavy": {"allies": ["e1", "e1", "e1", "e3", "e3", "jeep", "1tnk", "2tnk", "2tnk", "2tnk"],
			  "soviet": ["e1", "e1", "e1", "e3", "e3", "apc", "ftrk", "3tnk", "3tnk"]},
}
var paused := false
const DEFAULT_MAP := "keep-off-the-grass-2"
var map_data: MapData
var map_w := 64
var map_h := 64
var bounds := Rect2i(0, 0, 64, 64)
var types := {}

const TERRAIN_ORDER := ["Clear", "Rough", "Road", "Bridge", "Ore", "Gems", "Beach", "Water", "River", "Rock", "Tree", "Wall"]
const TER_CLEAR := 0
const TER_ROAD := 2
const TER_BEACH := 6
const TER_WATER := 7
const TER_ROCK := 9
const PLAYER_NEUTRAL := 2
const PLAYER_CREEPS := 3
const MIN_ZOOM := 2.0
const MAX_ZOOM := 5.0


const PLAYER_COLORS: Array[Color] = [
	Color(0.949, 0.737, 0.094),
	Color(0.961, 0.024, 0.024),
	Color(0.78, 0.78, 0.72),
	Color(0.55, 0.60, 0.50),
	Color(0.184, 0.525, 0.949),
	Color(0.024, 0.969, 0.224),
	Color(0.780, 0.094, 0.949),
	Color(0.961, 0.463, 0.024),
	Color(0.973, 0.380, 0.643),
	Color(0.204, 0.729, 0.576),
]


const MAX_SIM_PLAYERS := 10


const AI_PLAYER_INDICES := [1, 4, 5, 6, 7, 8, 9]

enum Armor { NONE, WOOD, LIGHT, HEAVY, CONCRETE }

var rules: RulesDb
static var next_faction := "allies"
static var next_ai_faction := "soviet"

var player_factions := {}
static var next_mission := ""
static var next_difficulty := ""
static var test_cycle_step := 0
var _markers := {}
var mission: MissionScript
var mission_api: MissionApi
var player_map := {}
var player_colors: Array[Color] = []


var player_roster: Array = []
signal mission_message(text: String, prefix: String)

signal notify_event(kind: int)

signal under_attack(pos: Vector2)


enum Queue { BUILDING = 0, INFANTRY = 1, VEHICLE = 2, DEFENSE = 3, AIRCRAFT = 4, SHIP = 5 }

const START_CREDITS := 5000


const AI_DIFFICULTIES := ["easy", "normal", "hard"]
const AI_HANDICAPS := {"easy": 50, "normal": 0, "hard": 0}

const AI_RUSH_OFF := 100000


const AI_LEVELS := {
	"easy": {
		"reaction_min_ticks": 100, "reaction_max_ticks": 200,
		"difficulty": 0,
		"strategy_interval": 400, "attack_force_interval": 150,
		"gather_max_ticks": 1000, "regen_ticks": 2500,
		"min_first_attack_tick": 8000,
		"allow_raid": 0, "allow_siege": 0, "allow_support_powers": 0,
		"allow_air_squad": 0, "allow_counterattack": 0, "allow_pincer": 0,


		"max_running_vorhaben": 1, "vorhaben_random_percent": 40, "counter_interval": 0,
		"squad_size_percent": 200, "rush": false,
	},
	"normal": {
		"reaction_min_ticks": 50, "reaction_max_ticks": 100,
		"difficulty": 1,
		"strategy_interval": 200, "attack_force_interval": 75,
		"gather_max_ticks": 600, "regen_ticks": 1500,
		"min_first_attack_tick": 0,
		"allow_raid": 1, "allow_siege": 1, "allow_support_powers": 1,
		"allow_air_squad": 1, "allow_counterattack": 0, "allow_pincer": 0,
		"max_running_vorhaben": 2, "vorhaben_random_percent": 25, "counter_interval": 750,
		"squad_size_percent": 100, "rush": true,
	},
	"hard": {
		"reaction_min_ticks": 25, "reaction_max_ticks": 60,
		"difficulty": 2,
		"strategy_interval": 100, "attack_force_interval": 50,
		"gather_max_ticks": 400, "regen_ticks": 1000,
		"min_first_attack_tick": 0,
		"allow_raid": 1, "allow_siege": 1, "allow_support_powers": 1,

		"max_running_vorhaben": 3, "vorhaben_random_percent": 20, "counter_interval": 500,
		"allow_air_squad": 1, "allow_counterattack": 1, "allow_pincer": 1,
		"squad_size_percent": 75, "rush": true,
	},
}

const AI_LEVEL_LOCAL_KEYS := ["squad_size_percent", "rush"]
static var next_ai_difficulty := "normal"


const AI_STRATEGIES := ["normal", "rush", "turtle", "air", "naval", "random"]
const AI_PERSONALITY_IDS := {"normal": 0, "rush": 1, "turtle": 2, "air": 3, "naval": 4, "random": 5}

const AI_STRATEGY_BOT_TYPES := {"normal": "normal", "rush": "rush", "turtle": "turtle",
		"air": "air", "naval": "naval"}
static var next_ai_strategy := "normal"


static var next_player_spawn := -1
static var next_player_team := 0
static var next_ai_slots: Array = []


static var next_savegame := ""


static var next_seed := -1


const NOTIFY_SOUNDS := ["abldgin1", "progres1", "conscmp1", "unitrdy1", "nofunds1", "nobuild1", "cancld1", "newopt1", "lopower1",
						"strusld1", "repair1", "pribldg1", "unitrep1", "misnwon1", "misnlst1", "silond1", "nodeply1",
						"bldginf1", "credit1",


						"slcttgt1", "nopowr1", "ironchg1", "ironrdy1", "chrochr1", "chrordy1", "aprep1", "aready1", "alaunch1",
						"satlnch1",


						"strucap1", "unitsto", "unitlst1",


						""]

const ENTER_NONE := 0
const ENTER_DEMOLISH := 3

const ENTER_LABELS := {1: "toast.capturing", 2: "toast.repairing_building", 3: "toast.demolishing",
		4: "toast.infiltrating", 5: "toast.repairing_bridge"}


const RENDER_STRIDE := 19


class Unit:
	var id: int
	var type: String
	var player: int
	var pos: Vector2
	var facing: int = 0
	var moving := false
	var alive := true
	var hp := 1.0
	var cargo := 0.0
	var goal: Vector2
	var goal_time := -100.0
	var goal_kind := 0
	var selected := false
	var repairing := false
	var selling := false
	var primary := false
	var unpowered := false
	var demolishing := false
	var demolish_left := 0
	var rally := Vector2i.ZERO
	var visible := true
	var firing := false
	var rank := 0
	var altitude := 0.0
	var passengers := 0
	var cargo_max := 0
	var ammo := 0
	var ammo_max := 0
	var map_id := ""
	var tags: Array = []


const NetOrders := preload("res://scripts/net/net_orders.gd")
const NetHub := preload("res://scripts/net/net_hub.gd")
const OrderLog := preload("res://scripts/net/order_log.gd")


var local_player := 0

var net_session = null

static var next_setup: Dictionary = {}

var order_log = null

var sim: RefCounted = null
var sim_text := "Sim: keine GDExtension"
var units: Array[Unit] = []
var selection: Array[Unit] = []
var zoom := 3.0
var sfx: Sfx
var music: Music
var type_ids := {}
var weapon_ids := {}
var type_names := {}


var additive_select := false

var placing_type := -1
var place_origin := Vector2i.ZERO
var place_armed := false
var _place_cells := PackedByteArray()
var _place_ok := false


var _place_area_ok := false
var _ghost: ImageTexture
var _ghost_overlay: ImageTexture


const EVA_COOLDOWN := 0.0


const EVA_COOLDOWNS := {
	"baseatk1": 30.0,
}
var _eva_last := {}
var _display_credits := 0.0
var _cash_tick_accum := 0.0

var _tick_len := 0.04
var _sim_accum := 0.0
var _target_zoom := 3.0
var _momentum := Vector2.ZERO
var _box_active := false
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _terrain_types := PackedByteArray()


var terrain_version := 0
var _terrain_mm: MultiMesh = null

var _atlas: PaletteAtlas
var _terrain: PaletteAtlas
var _unit_mm: MultiMesh
var _ore_mm: MultiMesh
var _ore_version := -1


var _smudge_mm: MultiMesh
var _smudge_version := -1
var _smudge_names := {}
var _camera: Camera2D
var _overlay: Node2D
var _nuke_layer: Node2D


var _nukes: Array = []


const NUKE_FLASH_SEC := 0.8
var _nuke_flash := 0.0


var _nuke_seen := {}
var _fog: Sprite2D
var _fog_img: Image
var _fog_tex: ImageTexture
var _fog_frame := 0
var _vis := PackedByteArray()
var _vis_version := 0
var _seed := -1
var _reveal_all := false


var _fog_off := false


var _frozen := {}
var _frozen_key := ""

var _gps_dots: Array = []
var _gps_active := false


var _palette_materials: Array[ShaderMaterial] = []
var _water_phase := -1


const MAX_FLING := 1200.0


static var _args_applied := false


func _apply_cmdline_args() -> void:
	var args := OS.get_cmdline_user_args()

	_diag = args.has("--diag")
	eva_logging = args.has("--test-eva")
	_reveal_all = args.has("--reveal")
	if next_seed >= 0:
		_seed = next_seed
	var sk := args.find("--seed")
	if sk >= 0 and sk + 1 < args.size():
		_seed = int(args[sk + 1])


	for mode in ["gd", "static"]:
		if args.has("--units-" + mode):
			_unit_mode = mode
	_unit_redraw = args.has("--units-redraw")

	if _args_applied:
		return
	_args_applied = true
	var mk := args.find("--mission")
	if mk >= 0 and mk + 1 < args.size():
		next_mission = args[mk + 1]
		next_map = args[mk + 1]
	var mapk := args.find("--map")
	if mapk >= 0 and mapk + 1 < args.size():
		next_map = args[mapk + 1]
		next_mission = ""
	var aik := args.find("--ai")
	if aik >= 0 and aik + 1 < args.size():
		next_ai_players = int(args[aik + 1])
	var fk := args.find("--faction")
	if fk >= 0 and fk + 1 < args.size():
		next_faction = args[fk + 1]
	var afk := args.find("--ai-faction")
	if afk >= 0 and afk + 1 < args.size():
		next_ai_faction = args[afk + 1]
	var suk := args.find("--starting-units")
	if suk >= 0 and suk + 1 < args.size():
		next_starting_units = args[suk + 1]
	var ck := args.find("--credits")
	if ck >= 0 and ck + 1 < args.size():
		next_credits = int(args[ck + 1])
	var krk := args.find("--crates")
	if krk >= 0 and krk + 1 < args.size():
		next_crates = args[krk + 1] not in ["0", "aus", "off", "false"]
	var kak := args.find("--crate-type")
	if kak >= 0 and kak + 1 < args.size():
		next_crate_action = CRATE_ACTION_ALIASES.get(args[kak + 1].to_lower(), -1)
		if next_crate_action < 0:
			push_warning("--crate-type %s unbekannt (%s)" % [args[kak + 1], ", ".join(CRATE_ACTION_ALIASES.keys())])
	elif args.has("--test-crate"):
		next_crate_action = 2
	var emk := args.find("--explored-map")
	if emk >= 0 and emk + 1 < args.size():
		next_explored_map = args[emk + 1] not in ["0", "aus", "off", "false"]
	var fgk := args.find("--fog")
	if fgk >= 0 and fgk + 1 < args.size():
		next_fog = args[fgk + 1] not in ["0", "aus", "off", "false"]
	var adk := args.find("--ai-difficulty")
	if adk >= 0 and adk + 1 < args.size() and AI_DIFFICULTIES.has(args[adk + 1]):
		next_ai_difficulty = args[adk + 1]


	var ask := args.find("--ai-strategy")
	if ask >= 0 and ask + 1 < args.size() and AI_STRATEGIES.has(args[ask + 1]):
		next_ai_strategy = args[ask + 1]
		next_ai_slots = []
	var asl := args.find("--ai-strategies")
	if asl >= 0 and asl + 1 < args.size():
		next_ai_slots = []
		for s in str(args[asl + 1]).split(","):
			next_ai_slots.append({"faction": "random", "team": 0,
					"level": next_ai_difficulty, "strategy": s if AI_STRATEGIES.has(s) else "normal"})


	var ast := args.find("--ai-starts")
	if ast >= 0 and ast + 1 < args.size():
		var nums := str(args[ast + 1]).split(",")
		while next_ai_slots.size() < nums.size():
			next_ai_slots.append({"faction": "random", "team": 0,
					"level": next_ai_difficulty, "strategy": "normal"})
		for i in nums.size():
			next_ai_slots[i]["spawn"] = maxi(int(nums[i]), 0) - 1

	var tas := args.find("--test-ai-start")
	if tas >= 0:
		var n := 3
		if tas + 1 < args.size() and str(args[tas + 1]).is_valid_int():
			n = int(args[tas + 1])
		next_ai_players = maxi(next_ai_players, 1)
		while next_ai_slots.size() < next_ai_players:
			next_ai_slots.append({"faction": "random", "team": 0,
					"level": next_ai_difficulty, "strategy": "normal"})
		next_ai_slots[0]["spawn"] = maxi(n, 1) - 1


func _ready() -> void:
	_read_savegame()
	_apply_cmdline_args()
	_attach_multiplayer()
	map_data = MapData.load(next_map if next_map != "" else DEFAULT_MAP)
	if map_data == null:
		push_error("Keine Karte — tools/mapconvert.py ausführen")
		return
	map_w = map_data.width
	map_h = map_data.height
	bounds = map_data.bounds
	_assign_players()


	_atlas = PaletteAtlas.load_from(ContentPaths.atlas(map_data.tileset),
			ContentPaths.palette(map_data.tileset), player_colors)


	if Lang.code() == "de" and ContentPaths.has_atlas("cameos_de"):
		_atlas.cameo_override = PaletteAtlas.load_from(ContentPaths.atlas("cameos_de"),
				ContentPaths.palette(map_data.tileset), player_colors)
	_terrain = _atlas
	rules = RulesDb.new()
	rules.build(_atlas, map_data.rules_override, map_data.campaign, map_data.rules_format)
	types = rules.types

	_build_map()
	_build_terrain(_terrain)


	_smudge_mm = MultiMesh.new()
	_smudge_mm.transform_format = MultiMesh.TRANSFORM_2D
	_smudge_mm.use_custom_data = true
	_smudge_mm.mesh = _unit_quad()
	var smudge_node := MultiMeshInstance2D.new()
	smudge_node.multimesh = _smudge_mm
	smudge_node.material = _make_material(_terrain)
	add_child(smudge_node)


	_ore_mm = MultiMesh.new()
	_ore_mm.transform_format = MultiMesh.TRANSFORM_2D
	_ore_mm.use_custom_data = true
	_ore_mm.mesh = _unit_quad()
	var ore_node := MultiMeshInstance2D.new()
	ore_node.multimesh = _ore_mm
	ore_node.material = _make_material(_terrain)
	add_child(ore_node)

	_unit_mm = MultiMesh.new()
	_unit_mm.transform_format = MultiMesh.TRANSFORM_2D
	_unit_mm.use_custom_data = true
	_unit_mm.mesh = _unit_quad()
	_unit_node = MultiMeshInstance2D.new()
	_unit_node.multimesh = _unit_mm
	_unit_node.material = _make_material(_atlas)
	add_child(_unit_node)


	_unit_mm.custom_aabb = AABB(Vector3(-256, -256, -1), Vector3(map_w * 24 + 512, map_h * 24 + 512, 2))


	_fog_img = Image.create(map_w, map_h, false, Image.FORMAT_R8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	_fog = Sprite2D.new()
	_fog.centered = false
	_fog.texture = _fog_tex
	_fog.scale = Vector2(CELL, CELL)
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = load("res://shaders/fog.gdshader")
	fog_mat.set_shader_parameter("vis", _fog_tex)
	_fog.material = fog_mat
	_fog.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_fog)

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


	move_child(_overlay, _fog.get_index())


	_nuke_layer = Node2D.new()
	_nuke_layer.draw.connect(_draw_nuke_beacons)
	add_child(_nuke_layer)

	_camera = Camera2D.new()
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	add_child(_camera)
	_camera.make_current()

	_camera.position = Vector2(30, 24) * CELL
	_apply_zoom(zoom)
	var listener := AudioListener2D.new()
	_camera.add_child(listener)
	listener.make_current()

	sfx = Sfx.new()
	sfx.view_rect = visible_world_rect
	if eva_logging:
		sfx.eva_started = func(n: String): _log_eva(n, "nachgezogen")
	add_child(sfx)
	music = get_node_or_null("/root/MusicPlayer")
	if music == null:
		music = Music.new()
		add_child(music)

	_start_sim()
	_start_multiplayer()
	for n in ["baseatk1", "cashup1", "cashdn1", "unitlst1", "enmyapp1", "train1", "nodeply1",
			"strucap1", "unitsto", "bctrinit", "placbldg", "build5", "cashturn", "onhold1"]:
		sfx.register(n)
	for n in NOTIFY_SOUNDS:
		sfx.register(n)


	var start_note: String = map_data.start_notification if map_data != null else ""
	if start_note != "":
		var snd: String = RulesDb.data().get("notifications", {}).get(start_note, "")
		if snd != "":
			sfx.register(snd)
			eva(snd)
	else:
		eva("bctrinit")


func _exit_tree() -> void:
	if mission_api != null:
		mission_api.shutdown()
	mission = null
	mission_api = null


func atlas() -> PaletteAtlas:
	return _atlas


func eva(name: String, cooldown: float = -1.0, force: bool = false) -> void:
	if name == "":
		return
	var cd := float(EVA_COOLDOWNS.get(name, EVA_COOLDOWN)) if cooldown < 0.0 else cooldown
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_eva_last.get(name, -1000.0)) < cd:
		_log_eva(name, "sperre")
		return
	_eva_last[name] = now
	if _diag:
		print("EVA: ", name)
	_log_eva(name, sfx.play_eva(name, force))


var eva_logging := false
var eva_records: Array = []


func _log_eva(name: String, status: String) -> void:
	if eva_logging:
		eva_records.append([sim.tick() if sim != null else -1, name, status, sfx.eva_remaining(), sfx.eva_busy()])


func _make_material(atlas: PaletteAtlas) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/palette_sprite.gdshader")
	mat.set_shader_parameter("atlas", atlas.atlas_texture)
	mat.set_shader_parameter("palette", atlas.palette_texture)
	mat.set_shader_parameter("frame_table", atlas.frame_table_texture)
	mat.set_shader_parameter("palette_rows", float(atlas.palette_rows))
	mat.set_shader_parameter("water_base", float(PaletteAtlas.WATER_ROTATION_BASE))
	mat.set_shader_parameter("water_range", float(PaletteAtlas.WATER_ROTATION_RANGE))
	mat.set_shader_parameter("water_phase", float(maxi(_water_phase, 0)))
	_palette_materials.append(mat)
	return mat


func _update_water_phase() -> void:
	if sim == null:
		return
	var p := PaletteAtlas.water_phase(int(sim.tick()))
	if p == _water_phase:
		return
	_water_phase = p
	for mat in _palette_materials:
		mat.set_shader_parameter("water_phase", float(p))


func _build_map() -> void:
	_terrain_types.resize(map_w * map_h)
	_terrain_types.fill(TER_ROCK)
	var templates: Dictionary = _atlas.meta.get("templates", {})
	var names: Array = _atlas.meta.get("terrain_types", [])

	var default_terrain: int = int(_atlas.meta.get("default_terrain", maxi(0, names.find("Clear"))))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tpl: Dictionary = templates.get(str(map_data.template_at(x, y)), {})
			var tiles: Dictionary = tpl.get("tiles", {})
			var ti: int = map_data.index_at(x, y)
			var local: int = int(tiles.get(str(ti), default_terrain))
			var tname: String = names[local] if local < names.size() else "Clear"
			var t := TERRAIN_ORDER.find(tname)
			_terrain_types[y * map_w + x] = t if t >= 0 else TER_ROCK
	terrain_version += 1


func terrain_map() -> PackedByteArray:
	return _terrain_types


func terrain_type(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= map_w or c.y >= map_h:
		return TER_ROCK
	return _terrain_types[c.y * map_w + c.x]


func _build_terrain(terrain: PaletteAtlas) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _unit_quad()
	mm.instance_count = bounds.size.x * bounds.size.y
	var templates: Dictionary = terrain.meta.get("templates", {})
	var i := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(x, y) * CELL))
			var tpl: Dictionary = templates.get(str(map_data.template_at(x, y)), {})
			var image: String = tpl.get("image", "clear1")
			var ti: int = map_data.index_at(x, y)
			if not terrain.sprite_frame_count.has(image):
				image = "clear1"
			var n: int = terrain.sprite_frame_count[image]
			mm.set_instance_custom_data(i, Color(terrain.frame_index(image, ti % maxi(n, 1)), terrain.terrain_row, 0, 0))
			i += 1
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = _make_material(terrain)
	add_child(node)
	_terrain_mm = mm


var _bridges: Array = []


var _bridge_cell: Dictionary = {}


func bridge_spans() -> Array:
	return _bridges


func _build_bridges() -> void:
	var templates: Dictionary = _atlas.meta.get("templates", {})
	var by_template := {}
	for name in types:
		var br: Dictionary = types[name].get("bridge", {})
		if not br.is_empty() and type_ids.has(name) and int(br.get("template", 0)) > 0:
			by_template[int(br["template"])] = name
	if by_template.is_empty():
		return
	var owner: int = player_map.get("Neutral", PLAYER_NEUTRAL)
	var taken := {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var tpl := map_data.template_at(x, y)
			if taken.has(cell) or not by_template.has(tpl):
				continue
			var meta: Dictionary = templates.get(str(tpl), {})
			var tw: int = maxi(1, int(meta.get("w", 1)))
			var th: int = maxi(1, int(meta.get("h", 1)))

			var ti := map_data.index_at(x, y)
			var origin := Vector2i(x - ti % tw, y - ti / tw)
			var cells: Array = []
			for ind in range(tw * th):
				var c := Vector2i(origin.x + ind % tw, origin.y + ind / tw)
				if c.x < 0 or c.y < 0 or c.x >= map_w or c.y >= map_h:
					continue
				if map_data.template_at(c.x, c.y) != tpl or map_data.index_at(c.x, c.y) != ind:
					continue
				cells.append(c)
				taken[c] = true
			if cells.is_empty():
				continue
			var tname: String = by_template[tpl]
			var u := _add_building(tname, owner, origin)
			if u.id < 0:
				continue
			_bridges.append({"unit": u, "origin": origin, "cells": cells,
					"bridge": types[tname]["bridge"], "current": tpl})
			for c: Vector2i in cells:
				_bridge_cell[c] = u


func _update_bridges() -> void:
	for b in _bridges:
		var u: Unit = b["unit"]
		var br: Dictionary = b["bridge"]
		var want := int(br.get("template", 0))
		if not u.alive:
			want = int(br.get("destroyed_template", 0))
		elif u.hp < 0.5 and int(br.get("damaged_template", 0)) > 0:
			want = int(br["damaged_template"])
		if want <= 0 or want == int(b["current"]):
			continue
		b["current"] = want
		_set_bridge_template(b, want)


func _set_bridge_template(b: Dictionary, tpl: int) -> void:
	var meta: Dictionary = _atlas.meta.get("templates", {}).get(str(tpl), {})
	if meta.is_empty():
		return
	var tw: int = maxi(1, int(meta.get("w", 1)))
	var tiles: Dictionary = meta.get("tiles", {})
	var names: Array = _atlas.meta.get("terrain_types", [])
	var default_terrain: int = int(_atlas.meta.get("default_terrain", maxi(0, names.find("Clear"))))
	var image: String = meta.get("image", "clear1")
	if not _terrain.sprite_frame_count.has(image):
		image = "clear1"
	var frames: int = maxi(1, int(_terrain.sprite_frame_count.get(image, 1)))
	var origin: Vector2i = b["origin"]
	for c: Vector2i in b["cells"]:
		var ind: int = (c.y - origin.y) * tw + (c.x - origin.x)
		map_data.set_tile(c.x, c.y, tpl, ind)
		var local: int = int(tiles.get(str(ind), default_terrain))
		var lname: String = names[local] if local < names.size() else "Clear"
		var t := TERRAIN_ORDER.find(lname)
		if t < 0:
			t = TER_ROCK
		_terrain_types[c.y * map_w + c.x] = t
		if sim.has_method("set_terrain_cell"):
			sim.set_terrain_cell(c.x, c.y, t)
		if _terrain_mm != null and bounds.has_point(c):
			var i: int = (c.y - bounds.position.y) * bounds.size.x + (c.x - bounds.position.x)
			_terrain_mm.set_instance_custom_data(i, Color(_terrain.frame_index(image, ind % frames), _terrain.terrain_row, 0, 0))
	terrain_version += 1


func _start_sim() -> void:
	if not ClassDB.class_exists("RaSim"):
		push_error("RaSim-GDExtension nicht geladen")
		return
	sim = ClassDB.instantiate("RaSim")


	_tick_len = GameSpeed.tick_seconds()


	if _atlas != null and sim.has_method("set_palette_dim_offset"):
		sim.set_palette_dim_offset(_atlas.dim_offset)
	if _atlas != null and sim.has_method("set_palette_invuln_offset"):
		sim.set_palette_invuln_offset(_atlas.invuln_offset)


	if _atlas != null and sim.has_method("set_palette_husk_offset"):
		sim.set_palette_husk_offset(_atlas.husk_offset)
	if _atlas != null and sim.has_method("set_palette_submerged_row"):
		sim.set_palette_submerged_row(_atlas.submerged_row)
	sim.set_terrain(map_w, map_h, _terrain_types)


	sim.set_neutral_player(player_map.get("Neutral", -1))
	if next_mission == "":
		sim.set_non_combatant(PLAYER_NEUTRAL, true)
		sim.set_non_combatant(PLAYER_CREEPS, true)
		if next_setup.is_empty():
			sim.set_faction(0, next_faction)
	else:
		sim.set_conquest_victory(false)
		for p in map_data.players:
			var idx: int = player_map.get(p["name"], -1)
			if idx < 0:
				continue
			var pf: String = "soviet" if p.get("faction", "") in ["soviet", "russia", "ukraine"] else "allies"
			player_factions[idx] = pf
			sim.set_faction(idx, pf)
			sim.set_non_combatant(idx, p.get("non_combatant", false))
		for p in map_data.players:
			var idx: int = player_map.get(p["name"], -1)
			for ally in p.get("allies", []):
				var other: int = player_map.get(ally, -1)
				if idx >= 0 and other >= 0:
					sim.set_alliance(idx, other, true)


		for p in map_data.players:
			var idx: int = player_map.get(p["name"], -1)
			for foe in p.get("enemies", []):
				var other: int = player_map.get(foe, -1)
				if idx >= 0 and other >= 0:
					sim.set_enemy(idx, other, true)


	var effect_ids := {}
	for key in rules.effects:
		var e: Dictionary = rules.effects[key]
		if not _atlas.sprite_frame_count.has(e["sprite"]):
			continue
		var size: Vector2i = _atlas.sprite_frame_size[e["sprite"]]

		var frames := PackedInt32Array()
		for rf in e.get("frames", []):
			frames.append(_atlas.frame_index(e["sprite"], int(rf)))
		effect_ids[key] = sim.define_effect({
			"first_frame": _atlas.frame_index(e["sprite"], e["start"]), "length": e["length"],
			"ticks_per_frame": e["ticks"], "frame_w": size.x, "frame_h": size.y,

			"offset_x": int(e.get("offset_x", 0)), "offset_y": int(e.get("offset_y", 0)),
			"zoffset": int(e.get("zoffset", 0)), "flipx": bool(e.get("flipx", false)),

			"owner_palette": bool(e.get("owner_palette", false)),
			"frames": frames,
		})


	weapon_ids.clear()
	for pass_ in 2:
		for name in rules.weapons:
			if weapon_ids.has(name):
				continue
			var cluster_name: String = rules.weapons[name].get("cluster_weapon", "")
			if pass_ == 0 and cluster_name != "" and rules.weapons.has(cluster_name):
				continue
			var w: Dictionary = rules.weapons[name].duplicate()
			w["cluster_weapon"] = weapon_ids.get(cluster_name, -1) if cluster_name != "" else -1


			var groups: Array = []
			for g in w.get("impacts", []):
				var gd: Dictionary = (g as Dictionary).duplicate()
				var fx_ids := PackedInt32Array()
				for key in gd.get("effects", []):
					var fid: int = effect_ids.get(key, -1)
					if fid >= 0:
						fx_ids.append(fid)
				gd["effects"] = fx_ids
				gd["sound"] = sfx.register(gd["sound"]) if str(gd.get("sound", "")) != "" else -1
				if fx_ids.is_empty() and int(gd["sound"]) < 0:
					continue
				groups.append(gd)
			w["impacts"] = groups
			w["report_sound"] = sfx.register(w["report"]) if w["report"] != "" else -1


			if int(w.get("zap_duration", 0)) > 0 and int(w["report_sound"]) >= 0:
				sfx.tesla_sounds[int(w["report_sound"])] = true
			w["impact_sound"] = sfx.register(w["impact_sound"]) if w["impact_sound"] != "" else -1

			w["zap_bright"] = effect_ids.get(w.get("zap_bright", ""), -1)
			w["zap_dim"] = effect_ids.get(w.get("zap_dim", ""), -1)

			w["missile_trail_effect"] = effect_ids.get(w.get("missile_trail_effect", ""), -1)
			if w["sprite"] != "":
				var size: Vector2i = _atlas.sprite_frame_size[w["sprite"]]

				w["frame"] = _atlas.frame_index(w["sprite"], int(w.get("sprite_start", 0)))
				w["facings"] = int(w.get("sprite_facings", 1))
				w["classic"] = bool(w.get("sprite_classic", false))
				w["frame_w"] = size.x
				w["frame_h"] = size.y
			weapon_ids[name] = sim.define_weapon(w)


	var order: Array = []
	for pass_ in 5:
		for name in types:
			var t: Dictionary = types[name]
			var is_building: bool = t.get("building", false)
			var group: int
			if t.get("crate", false):
				group = 4
			elif is_building:
				group = 2 if t.has("free_actor") else 0
			else:
				group = 3 if t.has("transforms") else 1
			if group == pass_:
				order.append(name)
	for name in order:
		var t: Dictionary = types[name]
		var body: String = t["body"]

		var invisible: bool = t.get("invisible", false)
		var size: Vector2i = Vector2i(CELL, CELL) if invisible else _atlas.sprite_frame_size[body]
		var death_ids: Array = []
		for key in t.get("death_effects", []):
			death_ids.append(effect_ids.get(key, -1))
		var def := {
			"speed": t.get("speed", 0), "turn_rate": t.get("turn_rate", 20), "infantry": t.get("infantry", false),
			"hp": t["hp"], "armor": t["armor"], "weapon": weapon_ids.get(t.get("weapon", ""), -1),

			"weapon_secondary": weapon_ids.get(t.get("weapon_secondary", ""), -1),

			"weapon_tertiary": weapon_ids.get(t.get("weapon_tertiary", ""), -1),
			"turreted": t.get("turreted", false), "turret_turn": t.get("turret_turn", 512),
			"hit_radius": t.get("hit_radius", 0), "death_effects": death_ids,
			"death_sound": sfx.register(t["death_sound"]) if t.has("death_sound") else -1,

			"damaged_sound": sfx.register(t["damaged_sounds"][0]) if not t.get("damaged_sounds", []).is_empty() else -1,
			"destroyed_sound": sfx.register(t["destroyed_sounds"][0]) if not t.get("destroyed_sounds", []).is_empty() else -1,
			"death_weapon": weapon_ids.get(t.get("death_weapon", ""), -1),

			"sp_weapon": weapon_ids.get(t.get("sp_weapon", ""), -1),
			"sp_sound": sfx.register(t["sp_sound"]) if t.has("sp_sound") else -1,

			"sp_launch_effect": effect_ids.get(str(t.get("sp_launch_effect", "")), -1),
			"sp_impact_effect": effect_ids.get(str(t.get("sp_impact_effect", "")), -1),
			"crush_sound": sfx.register(t["crush_sound"]) if t.has("crush_sound") else -1,
			"charge_sound": sfx.register(t["charge_sound"]) if t.has("charge_sound") else -1,
			"facings": t.get("facings", 1), "classic": t.get("classic", false),
			"first_frame": -1 if invisible else _atlas.frame_index(body, 0),
			"run_start": t.get("run_start", -1), "run_len": t.get("run_len", 0),
			"shoot_start": t.get("shoot_start", -1), "shoot_len": t.get("shoot_len", 0),
			"empty_start": t.get("empty_start", -1),
			"turret_first": t.get("turret_first", -1),
			"offset_x": t.get("offset_x", 0), "offset_y": t.get("offset_y", 0),

			"z_offset": t.get("z_offset", 0),
			"frame_w": size.x, "frame_h": size.y,
		}
		for key in ["footprint", "sprite_h", "refinery", "dock_dx", "dock_dy", "dock_angle", "damaged_frame", "idle_len",
					"stage_len", "resource_stages",
					"seeds_resource", "seed_interval", "seed_max_range", "cash_interval", "cash_amount",
					"mine", "mine_immune", "cloak", "cloak_initial_delay", "cloak_delay", "cloak_types", "uncloak_on", "detect_range", "detect_types",
					"cloak_pause_critical", "turret_offsets", "arm_turrets", "initial_stance", "initial_stance_ai",

					"turret_w", "turret_h", "turret_off_x", "turret_off_y", "turret_facings", "turret_classic",
					"support_power", "sp_charge", "sp_duration", "sp_dim_w", "sp_dim_h", "sp_footprint", "sp_flight", "sp_notify_charging", "sp_notify_ready",
					"sp_notify_launch", "sp_reveal_delay", "sp_one_shot", "sp_camera_range", "harvester", "capacity", "bale_load_delay", "bale_unload_delay", "search_from_proc",
					"search_from_harv", "harvest_facings", "harvest_start", "harvest_len", "dock_start", "dock_len", "loop_len",
					"cost", "queue", "prerequisites", "prerequisites_not", "prerequisites_hidden", "palette_order", "provides", "provides_factions", "provides_requires", "power", "produces",
					"build_duration", "build_duration_pct",
					"exit_dx", "exit_dy", "exit_facing", "exit_ox", "exit_oy", "rally_dx", "rally_dy", "free_dx", "free_dy", "sell_value", "adjacent",
					"terrain_mask", "scale_power_with_health", "needs_power", "wait_duration", "base_provider", "base_range", "requires_base_provider", "ai_building_fraction", "ai_building_limit",
					"ai_building_delay", "ai_unit_share", "ai_unit_limit", "exclude_from_squads", "defense", "gives_buildable_area",
					"auto_target_mask", "repairs_units", "repair_hp_step", "repair_interval", "repair_value_percent", "sellable",
					"repairable", "active_start", "active_len", "active_tick", "active_damaged_start", "facing_tolerance", "targetable", "locomotor", "repair_step",
					"transforms_dx", "transforms_dy",

					"mad_charge_delay", "mad_detonation_delay", "mad_thump_interval",
					"mad_frames", "mad_len",
					"detonate_on_deploy", "chrono_charge_delay", "chrono_max_distance",
					"required_short_game", "reveal_cells", "reveal_range", "reveal_gap_range",

					"creates_shroud_range", "jammer_range", "provides_radar", "gps_dot",
					"wall", "captures", "capturable", "storage", "door_len", "build_limit",
					"capture_types", "capturable_types", "capture_delay", "instantly_repairs", "instantly_repairable",
					"repairs_bridges",
					"demolition_delay", "demolishable", "infiltrates", "infiltrates_ally", "infil_transform",
					"capture_health", "disguise", "ignores_disguise",
					"infil_cash", "infil_cash_percent", "infil_cash_min", "infil_cash_max", "infil_explore",
					"infil_power", "infil_power_duration", "infil_support", "infil_proxy", "infil_reset",
					"producible_prereqs", "producible_levels",
					"range_radius", "target_types", "target_types_damaged", "target_types_underwater", "crushes", "crush_classes",
					"max_charges", "charge_reload", "initial_charge_delay", "charge_delay",
					"takes_cover", "prone_duration", "prone_speed", "no_auto_target",
					"idle1_start", "idle1_len", "idle2_start", "idle2_len", "idle_anim_ticks",
					"xp_required", "ranks", "gives_experience",
					"elite_heal_step", "elite_heal_percent", "elite_heal_delay", "elite_heal_start_below", "elite_heal_cooldown",


					"heal_step", "heal_percent", "heal_delay", "heal_start_below", "heal_damage_cooldown",


					"leap", "leap_speed", "leap_lock_ticks", "jump_frames", "jump_len",
					"realign_delay", "shoot_frames", "shoot2_start", "shoot2_len", "shoot2_frames",

					"cargo_max_weight", "cargo_types", "before_unload_delay", "between_unload_delay",
					"after_unload_delay", "after_load_delay", "cargo_eject_on_death", "passenger_weight", "passenger_type",

					"ramp_terrain", "ramp_ticks", "ramp_open", "ramp_close", "ramp_hold",
					"aircraft", "cruise_altitude", "altitude_velocity", "can_hover", "vtol", "idle_behavior",
					"landable_terrain", "ammo_max", "ammo_reload", "air_attack_type", "fall_rate",

					"falls_to_earth", "fall_moves", "fall_velocity", "fall_max_spin",

					"reservable",
					"target_types_airborne"]:
			if t.has(key):
				def[key] = t[key]
		if t.has("levelup_sound") and str(t["levelup_sound"]) != "":
			def["levelup_sound"] = sfx.register(str(t["levelup_sound"]))
		if t.has("levelup_effect"):
			def["levelup_effect"] = effect_ids.get(str(t["levelup_effect"]), -1)
		if t.get("crate", false):
			def["crate"] = true
			def["crate_duration"] = int(t.get("crate_duration", 0))
			def["crate_actions"] = _crate_actions(t.get("crate_actions", []), weapon_ids, effect_ids)

		if t.has("rotors") and not t["rotors"].is_empty():
			var rot_defs: Array = []
			for rt in t["rotors"]:


				var rsize: Vector2i = _atlas.sprite_frame_size[rt["sprite"]]
				var rd := {
					"air_first": _atlas.frame_index(rt["sprite"], rt["start"]), "air_len": rt["len"],
					"air_ticks": rt["ticks"], "ox": rt["ox"], "oy": rt["oy"], "oz": rt["oz"],
					"w": rsize.x, "h": rsize.y,
					"off_x": rt.get("off_x", 0), "off_y": rt.get("off_y", 0),
				}
				if rt.has("ground_sprite"):
					rd["ground_first"] = _atlas.frame_index(rt["ground_sprite"], rt["ground_start"])
					rd["ground_len"] = rt["ground_len"]
					rd["ground_ticks"] = rt["ground_ticks"]
				rot_defs.append(rd)
			def["rotors"] = rot_defs
		if t.has("weapon_secondary"):
			def["weapon_secondary"] = weapon_ids.get(t["weapon_secondary"], -1)
		if t.has("weapon_tertiary"):
			def["weapon_tertiary"] = weapon_ids.get(t["weapon_tertiary"], -1)

		if t.has("cloak_sound_name"):
			def["cloak_sound"] = sfx.register(str(t["cloak_sound_name"]))
		if t.has("rearm_sound"):
			def["rearm_sound"] = sfx.register(t["rearm_sound"])


		if t.has("fall_weapon"):
			def["fall_weapon"] = weapon_ids.get(str(t["fall_weapon"]), -1)

		if t.has("rearm_actors"):
			var rearm_ids: Array = []
			for rn in t["rearm_actors"]:
				if type_ids.has(rn):
					rearm_ids.append(type_ids[rn])
			if not rearm_ids.is_empty():
				def["rearm_actors"] = rearm_ids
		if t.has("free_actor") and type_ids.has(t["free_actor"]):
			def["free_actor"] = type_ids[t["free_actor"]]
		if t.has("transforms") and type_ids.has(t["transforms"]):
			def["transforms_into"] = type_ids[t["transforms"]]

		if t.has("mad_charge_delay"):
			def["mad_thump_weapon"] = weapon_ids.get(str(t.get("mad_thump_weapon", "")), -1)
			def["mad_detonation_weapon"] = weapon_ids.get(str(t.get("mad_detonation_weapon", "")), -1)
			def["mad_charge_sound"] = sfx.register(str(t["mad_charge_sound"])) if str(t.get("mad_charge_sound", "")) != "" else -1
			def["mad_detonation_sound"] = sfx.register(str(t["mad_detonation_sound"])) if str(t.get("mad_detonation_sound", "")) != "" else -1
		if t.has("chrono_charge_delay"):
			def["chrono_sound"] = sfx.register(str(t["chrono_sound"])) if str(t.get("chrono_sound", "")) != "" else -1
		if t.get("building", false):
			def["sell_sound"] = sfx.register("cashturn")
		if t.has("overlay_sprite"):
			def["overlay_first"] = _atlas.frame_index(t["overlay_sprite"], t["overlay_start"])
			def["overlay_len"] = t["overlay_len"]
			if t.has("overlay_damaged_sprite"):
				def["overlay_damaged_first"] = _atlas.frame_index(t["overlay_damaged_sprite"], t["overlay_damaged_start"])
				def["overlay_damaged_len"] = t["overlay_damaged_len"]

		if t.has("burn_sprite") and _atlas.sprite_frame_count.has(t["burn_sprite"]):
			var bsize: Vector2i = _atlas.sprite_frame_size[t["burn_sprite"]]
			def["burn_first"] = _atlas.frame_index(t["burn_sprite"], int(t.get("burn_start", 0)))
			def["burn_len"] = int(t.get("burn_len", 1))
			def["burn_ticks"] = int(t.get("burn_ticks", 1))
			def["burn_off_x"] = int(t.get("burn_off_x", 0))
			def["burn_off_y"] = int(t.get("burn_off_y", 0))
			def["burn_w"] = bsize.x
			def["burn_h"] = bsize.y
		for key in ["husk", "husk_terrain", "husk_probability"]:
			if t.has(key):
				def[key] = t[key]

		if t.has("muzzle_sprite") and _atlas.sprite_frame_count.has(t["muzzle_sprite"]):
			var msize: Vector2i = _atlas.sprite_frame_size[t["muzzle_sprite"]]
			def["muzzle_first"] = _atlas.frame_index(t["muzzle_sprite"], int(t.get("muzzle_start", 0)))
			def["muzzle_len"] = int(t.get("muzzle_len", 1))
			def["muzzle_ox"] = int(t.get("muzzle_ox", 0))
			def["muzzle_oy"] = int(t.get("muzzle_oy", 0))
			def["muzzle_oz"] = int(t.get("muzzle_oz", 0))
			def["muzzle_turret"] = bool(t.get("muzzle_turret", false))
			def["muzzle_w"] = msize.x
			def["muzzle_h"] = msize.y
		if t.has("make"):
			def["make_first"] = _atlas.frame_index(t["make"], 0)
			def["make_len"] = _atlas.sprite_frame_count[t["make"]]
			def["make_ticks"] = _atlas.sprite_frame_count[t["make"]] * 2


			var make_size: Vector2i = _atlas.sprite_frame_size[t["make"]]
			def["make_w"] = make_size.x
			def["make_h"] = make_size.y
			def["make_off_x"] = int(t.get("make_off_x", 0))
			def["make_off_y"] = int(t.get("make_off_y", 0))
		type_ids[name] = sim.define_type(def)
		type_names[type_ids[name]] = name


	var cs: Dictionary = RulesDb.data().get("world", {}).get("crate_spawner", {})
	if not cs.is_empty() and type_ids.has("crate"):
		var ground := 0
		for tn in cs.get("valid_ground", []):
			var ti: int = TERRAIN_ORDER.find(str(tn))
			if ti >= 0:
				ground |= 1 << ti


		var deliver: int = type_ids.get(str(cs.get("delivery_aircraft", "")), -1)
		sim.set_crate_spawner({
			"enabled": next_crates and next_mission == "",
			"crate_type": type_ids["crate"],
			"minimum": int(cs.get("minimum", 1)), "maximum": int(cs.get("maximum", 3)),
			"spawn_interval": int(cs.get("spawn_interval", 3000)),
			"initial_delay": int(cs.get("initial_delay", 1500)), "valid_ground": ground,
			"delivery_type": deliver,
			"quantized_facings": int(cs.get("quantized_facings", 16)),
			"cordon": int(cs.get("cordon", 5120)),
		})


	if sim.has_method("set_parachute_sprite") and _atlas.sprite_frame_count.has("parach"):
		var psize: Vector2i = _atlas.sprite_frame_size["parach"]
		sim.set_parachute_sprite(_atlas.frame_index("parach", 5), psize.x, psize.y)


	for name in types:
		var mt: Dictionary = types[name]
		if mt.has("minelayer_mine") and type_ids.has(name) and type_ids.has(mt["minelayer_mine"]):
			sim.set_minelayer(type_ids[name], type_ids[mt["minelayer_mine"]])

		if mt.has("mad_driver") and type_ids.has(name) and type_ids.has(mt["mad_driver"]) \
				and sim.has_method("set_mad_driver"):
			sim.set_mad_driver(type_ids[name], type_ids[mt["mad_driver"]])


	if sim.has_method("set_husk_actor"):
		for name in types:
			var ht: Dictionary = types[name]
			var hn: String = str(ht.get("husk_actor", ""))


			if hn != "" and type_ids.has(name) and type_ids.has(hn) and types[hn].get("husk", false):
				sim.set_husk_actor(type_ids[name], type_ids[hn])


	if sim.has_method("set_capture_actor"):
		for name in types:
			var ct: Dictionary = types[name]
			var cn: String = str(ct.get("capture_into", ""))
			if cn != "" and type_ids.has(name) and type_ids.has(cn):
				sim.set_capture_actor(type_ids[name], type_ids[cn], int(ct.get("capture_health", 0)))


	if sim.has_method("set_land_actors"):
		for name in types:
			var at: Dictionary = types[name]
			if not at.get("aircraft", false) or not type_ids.has(name):
				continue
			var pads := PackedInt32Array()
			for rn in at.get("rearm_actors", []):
				if type_ids.has(rn) and not pads.has(type_ids[rn]):
					pads.append(type_ids[rn])
			var mark: String = str(at.get("at_production", ""))
			if mark != "":
				for bn in types:
					var bt: Dictionary = types[bn]
					if not bt.get("reservable", false) or not type_ids.has(bn):
						continue
					if not bt.get("produces_types", []).has(mark) or pads.has(type_ids[bn]):
						continue
					pads.append(type_ids[bn])
			if not pads.is_empty():
				sim.set_land_actors(type_ids[name], pads)


	_setup_smudges()


	if sim.has_method("set_repair_actors"):
		for name in types:
			var rt: Dictionary = types[name]
			if not rt.has("repair_actors") or not type_ids.has(name):
				continue
			var depot_ids := PackedInt32Array()
			for dn in rt["repair_actors"]:
				if type_ids.has(dn):
					depot_ids.append(type_ids[dn])
			if not depot_ids.is_empty():
				sim.set_repair_actors(type_ids[name], depot_ids)

	_place_resources()
	_build_bridges()


	if next_mission == "":
		_place_players()
		_place_map_actors()
	else:
		_place_map_actors()
		_start_mission()


	if _reveal_all or (next_mission == "" and next_explored_map):
		sim.reveal(local_player, map_w / 2, map_h / 2, map_w + map_h)


	_fog_off = next_mission == "" and not next_fog
	if sim.has_method("set_fog_enabled"):
		sim.set_fog_enabled(not _fog_off)


	_apply_savegame()


var _pending_save := {}
var loaded_from_slot := ""


func _read_savegame() -> void:
	_pending_save = {}
	if next_savegame == "":
		return
	var slot := next_savegame
	next_savegame = ""
	var data := SaveGame.read(slot)
	if data.is_empty():
		push_error("Spielstand %s nicht lesbar" % slot)
		return
	var h: Dictionary = data["header"]
	next_map = str(h.get("map", next_map))
	next_mission = str(h.get("mission", ""))
	next_faction = str(h.get("faction", next_faction))
	next_ai_faction = str(h.get("ai_faction", next_ai_faction))
	next_ai_players = int(h.get("ai_players", next_ai_players))
	next_ai_difficulty = str(h.get("ai_difficulty", next_ai_difficulty))
	next_ai_strategy = str(h.get("ai_strategy", next_ai_strategy))
	next_credits = int(h.get("credits", next_credits))
	next_starting_units = str(h.get("starting_units", next_starting_units))
	next_crates = bool(h.get("crates", next_crates))
	next_explored_map = bool(h.get("explored_map", next_explored_map))
	next_fog = bool(h.get("fog", next_fog))
	next_difficulty = str(h.get("difficulty", next_difficulty))
	next_seed = int(h.get("seed", -1))
	loaded_from_slot = slot

	if bool(h.get("restart_only", false)):
		return
	_pending_save = data


func _apply_savegame() -> void:
	if _pending_save.is_empty() or sim == null:
		return
	if not load_state_bytes(_pending_save.get("sim", PackedByteArray())):
		push_error("Spielstand passt nicht zu dieser Karte (andere Regeln?) — Partie beginnt neu")
		_pending_save = {}
		return
	_apply_view_state(_pending_save.get("gd", {}))
	print("Spielstand %s geladen: Tick %d, %d Actors, %d Credits" % [
			loaded_from_slot, sim.tick(), sim.actor_count(), sim.credits(local_player)])


func load_state_bytes(bytes: PackedByteArray) -> bool:
	if sim == null or bytes.is_empty() or not sim.load_state(bytes):
		return false


	var meta := {}
	for u in units:
		if u.map_id != "" or not u.tags.is_empty():
			meta[u.id] = u
	units.clear()
	selection.clear()
	_sync_new_actors(sim.render_state(1.0))
	for u in units:
		if meta.has(u.id):
			u.map_id = meta[u.id].map_id
			u.tags = meta[u.id].tags
	_ore_version = -1
	_smudge_version = -1
	_display_credits = float(sim.credits(local_player))
	_update_bridges()
	return true


func loaded_view_state() -> Dictionary:
	return _pending_save.get("gd", {}) if not _pending_save.is_empty() else {}


func _apply_view_state(gd: Dictionary) -> void:
	var cam: Array = gd.get("camera", [])
	if cam.size() == 2 and _camera != null:
		_camera.position = Vector2(float(cam[0]), float(cam[1]))
	zoom = clampf(float(gd.get("zoom", zoom)), MIN_ZOOM, MAX_ZOOM)
	_target_zoom = zoom
	_apply_zoom(zoom)
	_clamp_camera()
	for id in gd.get("selection", []):
		var u := unit_by_id(int(id))
		if u != null and u.alive:
			u.selected = true
			selection.append(u)


func unit_by_id(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func view_state(groups: Array = []) -> Dictionary:
	var sel: Array = []
	for u in selection:
		if u.alive:
			sel.append(u.id)
	var gr: Array = []
	for g in groups:
		var ids: Array = []
		for u in g:
			if u != null and u.alive:
				ids.append(u.id)
		gr.append(ids)
	return {
		"camera": [_camera.position.x, _camera.position.y] if _camera != null else [],
		"zoom": zoom,
		"selection": sel,
		"groups": gr,
	}


func save_header() -> Dictionary:
	var tick: int = sim.tick() if sim != null else 0
	return {
		"map": next_map if next_map != "" else DEFAULT_MAP,
		"map_title": map_data.title if map_data != null else "",
		"mission": next_mission,
		"mode": "mission" if next_mission != "" else "skirmish",
		"restart_only": next_mission != "",
		"faction": next_faction,
		"ai_faction": next_ai_faction,
		"ai_players": next_ai_players,
		"ai_difficulty": next_ai_difficulty,
		"ai_strategy": next_ai_strategy,
		"credits": next_credits,
		"starting_units": next_starting_units,
		"crates": next_crates,
		"explored_map": next_explored_map,
		"fog": next_fog,
		"difficulty": next_difficulty,
		"seed": _seed,
		"tick": tick,
		"playtime": SaveGame.playtime_of(tick),
		"sim_version": sim.state_version() if sim != null else 0,
		"rules_hash": sim.rules_hash() if sim != null else "",
	}


func save_to_slot(slot: String, groups: Array = []) -> bool:
	if sim == null:
		return false
	var header := save_header()
	var bytes := PackedByteArray() if next_mission != "" else sim.save_state() as PackedByteArray
	return SaveGame.write(slot, header, bytes, view_state(groups))


func _start_mission() -> void:


	var cash := map_data.default_cash if map_data.default_cash >= 0 else 0
	for name in player_map:
		var idx: int = player_map[name]
		if idx >= 0:
			sim.give_credits(idx, cash)
	mission_api = MissionApi.new()
	mission_api.setup(self)
	mission_api.players = player_map
	for name in _markers:
		mission_api.by_map_id[name] = _markers[name]
	mission = Missions.create(next_mission)
	if mission == null:
		push_error("Kein Missionsskript für " + next_mission)
		return
	mission.api = mission_api

	if next_difficulty != "" and world_difficulties().has(next_difficulty):
		mission_api.difficulty = next_difficulty
	mission.difficulty = mission_api.difficulty
	mission.world_loaded()
	if mission_api.camera_target != Vector2.ZERO:
		center_on(mission_api.camera_target)
	else:
		for u in units:
			if u.alive and u.player == 0:
				center_on(u.pos)
				break


func hostile(a: int, b: int) -> bool:
	if a == b:
		return false
	return sim.hostile(a, b) if sim != null else true


func _roster_add(pid: int, seat: int, disp: String, faction: String, team: int,
		kind: String, level: String, color_index: int = -1, strategy: String = "") -> void:
	var bot_no := 0
	if kind == "bot":
		for r in player_roster:
			if str(r.get("kind", "human")) == "bot":
				bot_no += 1
		bot_no += 1
	player_roster.append({
		"sim": pid, "seat": seat, "name": disp, "faction": faction, "team": team,
		"kind": kind, "level": level, "strategy": strategy, "bot_no": bot_no, "color_index": color_index,
		"color": player_colors[pid] if pid >= 0 and pid < player_colors.size() else PLAYER_COLORS[0],
	})


func roster_status(pid: int) -> Dictionary:
	if sim == null:
		return {"alive": 0, "win_state": 0, "relation": "self" if pid == local_player else "enemy"}
	var rel := "self"
	if pid != local_player:
		rel = "enemy" if hostile(local_player, pid) else "allied"
	return {"alive": int(sim.alive_count(pid)), "win_state": int(sim.win_state(pid)), "relation": rel}


const CRATE_ACTION_KINDS := {
	"GiveCashCrateAction": 0, "LevelUpCrateAction": 1, "ExplodeCrateAction": 2,
	"HideMapCrateAction": 3, "HealActorsCrateAction": 4, "RevealMapCrateAction": 5,
	"DuplicateUnitCrateAction": 6, "GiveUnitCrateAction": 7, "GiveBaseBuilderCrateAction": 8,
}

const CRATE_ACTION_ALIASES := {
	"cash": 0, "geld": 0, "levelup": 1, "rang": 1, "explode": 2, "explosion": 2,
	"hidemap": 3, "heal": 4, "revealmap": 5, "duplicate": 6, "unit": 7, "basebuilder": 8,
}


func _crate_actions(list: Array, weapon_ids: Dictionary, effect_ids: Dictionary) -> Array:
	var out: Array = []
	for ca in list:
		var kind: int = CRATE_ACTION_KINDS.get(str(ca.get("action", "")), -1)
		if kind < 0:
			continue
		if next_crate_action >= 0 and kind != next_crate_action:
			continue
		var units: Array = []
		var missing := false
		for u in ca.get("units", []):


			if not type_ids.has(u):
				missing = true
				break
			units.append(type_ids[u])
		if missing or ((kind == 7 or kind == 8) and units.is_empty()):
			continue
		var weapon: int = weapon_ids.get(str(ca.get("weapon", "")), -1)
		if kind == 2 and weapon < 0:
			continue
		var amount: int = int(ca.get("levels", 1)) if kind == 1 else int(ca.get("amount", 0))
		var seq := str(ca.get("sequence", ""))
		var effect: int = -1
		if seq != "":
			effect = effect_ids.get("%s/%s" % [str(ca.get("image", "crate-effects")), seq], -1)
		out.append({
			"kind": kind, "shares": int(ca.get("shares", 10)),
			"no_base_shares": int(ca.get("no_base_shares", 1000)),
			"amount": amount, "min_amount": int(ca.get("min_amount", 1)),
			"max_amount": int(ca.get("max_amount", 2)), "max_value": int(ca.get("max_value", -1)),
			"max_radius": int(ca.get("max_radius", 4)), "weapon": weapon,
			"time_delay": int(ca.get("time_delay", 0)),
			"sound": sfx.register(str(ca["sound"])) if str(ca.get("sound", "")) != "" else -1,
			"effect": effect, "units": units,
			"factions": ca.get("factions", []), "prerequisites": ca.get("prerequisites", []),
		})
	return out


func _place_resources() -> void:
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var t := map_data.resource_type_at(x, y)

			var terr: int = _terrain_types[y * map_w + x]
			if t == 0 or (terr != TER_CLEAR and terr != TER_ROAD):
				continue
			var adjacent := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < map_w and ny < map_h and map_data.resource_type_at(nx, ny) == t:
						adjacent += 1
			var max_density := 12 if t == 1 else 3
			sim.set_resource(x, y, t, maxi(max_density * adjacent / 9, 1))


func _place_map_actors() -> void:
	for a in map_data.actors:
		var type: String = a["type"]
		if type in ["waypoint", "mpspawn", "camera", "flare"]:


			if type in ["camera", "flare"] and next_mission != "" \
					and _owner_index(str(a.get("owner", "Neutral"))) == 0:
				sim.reveal(0, int(a["x"]), int(a["y"]), 10 if type == "camera" else 3)
			var wp := Unit.new()
			wp.type = type
			wp.player = PLAYER_NEUTRAL
			wp.id = -1
			wp.alive = false
			wp.pos = (Vector2(int(a["x"]), int(a["y"])) + Vector2(0.5, 0.5)) * CELL
			wp.map_id = str(a.get("id", ""))
			wp.tags = a.get("tags", [])
			_markers[wp.map_id] = wp
			continue
		var variant := ""
		if not types.has(type) and "." in type and types.has(type.get_slice(".", 0)):
			variant = type
			type = type.get_slice(".", 0)
		if not types.has(type):
			continue
		var owner := _owner_index(str(a.get("owner", "Neutral")))
		if owner < 0:
			continue
		var cell := Vector2i(int(a["x"]), int(a["y"]))

		var facing := int(a.get("facing", -1))
		var health := int(a.get("health", 100))
		var u: Unit
		if types[type].get("building", false):
			u = _add_building(type, owner, cell, health)
		else:
			u = spawn_unit(type, owner, cell, facing, health)
		if u != null and u.id >= 0:
			u.map_id = str(a.get("id", ""))
			u.tags = a.get("tags", [])


			if variant.ends_with(".noautotarget"):
				sim.set_stance(u.id, 0)


func _assign_players() -> void:
	player_colors = PLAYER_COLORS.duplicate()
	player_map = {"Neutral": PLAYER_NEUTRAL, "Creeps": PLAYER_CREEPS}
	if next_mission == "":
		return
	player_map = {}
	player_colors = []
	var others: Array = []
	for p in map_data.players:

		if p.get("playable", false) and not player_map.values().has(0):
			player_map[p["name"]] = 0
			player_colors.append(_map_color(p, PLAYER_COLORS[0]))
		else:
			others.append(p)
	for p in others:
		var idx := player_colors.size()
		if idx >= MAX_SIM_PLAYERS:
			break
		player_map[p["name"]] = idx
		player_colors.append(_map_color(p, PLAYER_COLORS[mini(idx, PLAYER_COLORS.size() - 1)]))


func _map_color(p: Dictionary, fallback: Color) -> Color:
	var c: String = p.get("color", "")
	return Color.html("#" + c) if c.length() >= 6 else fallback


func _owner_index(name: String) -> int:
	return player_map.get(name, -1)


func spawn_unit(type: String, owner: int, cell: Vector2i, facing: int = -1, health_percent: int = 100,
		airborne: bool = false) -> Unit:
	if not type_ids.has(type) or types[type].get("building", false):
		return null
	var u := Unit.new()
	u.type = type
	u.player = owner
	u.id = sim.spawn(type_ids[type], owner, cell.x, cell.y, facing, health_percent, airborne)
	if u.id < 0:
		return null
	u.pos = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	u.goal = u.pos
	units.append(u)
	return u


func _spawn_start(player: int, cell: Vector2i, faction: String = "allies") -> void:
	if types.has("mcv"):
		spawn_unit("mcv", player, cell)
	else:
		_add_building("fact", player, cell - Vector2i(1, 1))
	var support: Array = STARTING_UNITS.get(next_starting_units, {}).get(faction, [])
	if support.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(cell) + str(player))
	var used := {cell: true}
	for type in support:
		if not types.has(type):
			continue

		for _try in 40:
			var r := rng.randf_range(4.0, 5.0)
			var ang := rng.randf() * TAU
			var c := cell + Vector2i(int(round(cos(ang) * r)), int(round(sin(ang) * r)))
			if used.has(c) or not bounds.has_point(c) or _terrain_types[c.y * map_w + c.x] == TER_ROCK:
				continue
			if spawn_unit(type, player, c) != null:
				used[c] = true
				break


func _bot_params(difficulty: String, strategy: String = "") -> Dictionary:
	var p: Dictionary = {}
	if strategy == "" or not AI_STRATEGY_BOT_TYPES.has(strategy):
		strategy = "normal"
	p["personality"] = int(AI_PERSONALITY_IDS.get(strategy, 0))
	var bot: Dictionary = rules.ai.get("bots", {}).get(AI_STRATEGY_BOT_TYPES.get(strategy, "normal"), {})
	var src: Dictionary = bot.get("params", {})
	for k in src:
		p[k] = int(src[k])


	p["initial_harvesters"] = mini(int(p.get("initial_harvesters", 3)), 3)
	p["additional_min_refineries"] = maxi(int(p.get("additional_min_refineries", 3)), 3)


	p["squad_size"] = maxi(4, int(src.get("squad_size", 40)) * 7 / 10)


	p["squad_size_random_bonus"] = maxi(1, int(p["squad_size"]) / 2)

	var lvl: Dictionary = AI_LEVELS.get(difficulty, AI_LEVELS["normal"])
	for k in lvl:
		if not AI_LEVEL_LOCAL_KEYS.has(k):
			p[k] = int(lvl[k])
	p["squad_size"] = maxi(4, int(p["squad_size"]) * int(lvl.get("squad_size_percent", 100)) / 100)
	if not bool(lvl.get("rush", true)):
		p["rush_interval"] = AI_RUSH_OFF
	const TABLE_DEFAULTS := {"building_fraction": -1, "building_limit": 2147483647, "building_delay": 0,
							 "unit_share": -1, "unit_limit": 2147483647}
	const TABLE_SOURCES := {"building_fraction": "building_fractions", "building_limit": "building_limits",
							"building_delay": "building_delays", "unit_share": "units_to_build", "unit_limit": "unit_limits"}
	for key in TABLE_DEFAULTS:
		var arr := PackedInt32Array()
		arr.resize(type_ids.size())
		arr.fill(int(TABLE_DEFAULTS[key]))
		for name in bot.get(TABLE_SOURCES[key], {}):
			if type_ids.has(name):
				arr[int(type_ids[name])] = int(bot[TABLE_SOURCES[key]][name])
		p[key] = arr


	const AI_ECONOMY := {
		"normal": [3, 4, 3000, 100, 1],
		"rush":   [2, 3, 2000,  60, 1],
		"turtle": [3, 4, 3000, 150, 1],
		"air":    [3, 3, 3000, 100, 1],
		"naval":  [3, 4, 3000, 100, 1],
	}
	var eco: Array = AI_ECONOMY.get(strategy, AI_ECONOMY["normal"])
	p["harvesters_per_refinery"] = int(eco[0])
	p["max_conyards"] = int(eco[1])
	p["surplus_cash"] = int(eco[2])
	p["defense_budget_percent"] = int(eco[3])
	p["sell_on_loss"] = int(eco[4])


	if difficulty == "easy":
		p["harvesters_per_refinery"] = mini(int(p["harvesters_per_refinery"]), 2)
		p["max_conyards"] = mini(int(p["max_conyards"]), 2)
		p["surplus_cash"] = maxi(int(p["surplus_cash"]), 5000)
		p["defense_budget_percent"] = int(p["defense_budget_percent"]) / 2
		p["sell_on_loss"] = 0
	elif difficulty == "hard":
		p["surplus_cash"] = mini(int(p["surplus_cash"]), 2000)
		p["defense_budget_percent"] = maxi(int(p["defense_budget_percent"]), 100)
	return p


func _pick_spawn(free: Array, taken: Array, rng: RandomNumberGenerator) -> int:
	if taken.is_empty():
		return rng.randi_range(0, free.size() - 1)
	var best := 0
	var best_d := -1.0
	for i in free.size():
		var d := 0.0
		for t in taken:
			d += Vector2(free[i] - t).length_squared()
		if d > best_d:
			best_d = d
			best = i
	return best


func _resolve_faction(f: String, rng: RandomNumberGenerator) -> String:
	if f == "random" or f == "":
		return "allies" if rng.randi() % 2 == 0 else "soviet"
	return f


func _resolve_strategy(want: String) -> String:
	var s := want
	if s == "random" or s == "" or not AI_STRATEGY_BOT_TYPES.has(s):
		if s != "random" and s != "":
			return "normal"
		var pick: int = sim.pick_bot_personality() if sim != null else 0
		s = str(AI_STRATEGIES[clampi(pick, 0, AI_STRATEGIES.size() - 2)])
	if s == "naval" and not _map_has_water():
		return "normal"
	return s


func _map_has_water() -> bool:
	var water := 0
	for t in _terrain_types:
		if int(t) == TER_WATER:
			water += 1
			if water > 200:
				return true
	return false


func _pick_team_spawn(spawns: Array, anchor: Vector2i, near: bool) -> int:
	var best := 0
	var best_d := -1.0
	for i in spawns.size():
		var d: float = Vector2(spawns[i] - anchor).length()
		if best_d < 0.0 or (d < best_d if near else d > best_d):
			best_d = d
			best = i
	return best


func _place_players() -> void:


	if not next_setup.is_empty():
		_apply_setup(next_setup)
		return
	var spawns: Array = map_data.spawns.duplicate()
	if spawns.is_empty():
		spawns = [Vector2i(bounds.position) + Vector2i(6, 6), Vector2i(bounds.end) - Vector2i(8, 8)]

	var spawn_index := {}
	for i in spawns.size():
		spawn_index[spawns[i]] = i
	var rng := RandomNumberGenerator.new()


	if _seed < 0:
		rng.randomize()
		_seed = int(rng.seed & 0x7FFFFFFF)
	rng.seed = _seed
	var taken: Array = []

	var mine := -1
	if next_player_spawn >= 0:
		for i in spawns.size():
			if spawn_index.get(spawns[i], -1) == next_player_spawn:
				mine = i
	if mine < 0:
		mine = _pick_spawn(spawns, taken, rng)
	var player_spawn: Vector2i = spawns[mine]
	var my_faction := _resolve_faction(next_faction, rng)
	taken.append(player_spawn)
	spawns.remove_at(mine)
	player_map["Multi%d" % spawn_index[player_spawn]] = 0
	_spawn_start(0, player_spawn, my_faction)
	player_factions[0] = my_faction
	next_faction = my_faction
	sim.set_faction(0, my_faction)
	sim.give_credits(0, next_credits)
	sim.reveal(0, player_spawn.x, player_spawn.y, 5)


	player_roster = []
	_roster_add(0, -1, "", my_faction, next_player_team, "human", "")
	var used_players: Array = [0]
	var ai_max: int = mini(spawns.size(), AI_PLAYER_INDICES.size())
	var ai_count: int = clampi(next_ai_players, 0, ai_max)
	if next_ai_players > ai_max:
		print("Karte hat nur %d weitere Startpunkte — KI-Gegner auf %d begrenzt (angefordert: %d)" % [
			ai_max, ai_count, next_ai_players])
	var teams := {0: next_player_team}
	for i in ai_count:
		var slot: Dictionary = next_ai_slots[i] if i < next_ai_slots.size() else {}
		var team := int(slot.get("team", 0))


		var want_spawn := int(slot.get("spawn", -1))
		var k := -1
		if want_spawn >= 0:
			for j in spawns.size():
				if int(spawn_index.get(spawns[j], -1)) == want_spawn:
					k = j
					break
		if k < 0:

			if team > 0 and team == next_player_team:
				k = _pick_team_spawn(spawns, player_spawn, true)
			elif next_player_team > 0 or team > 0:
				k = _pick_team_spawn(spawns, player_spawn, false)
			else:
				k = _pick_spawn(spawns, taken, rng)
		var idx: int = AI_PLAYER_INDICES[i]
		var want: String = str(slot.get("faction", next_ai_faction if i == 0 else ("allies" if next_ai_faction == "soviet" else "soviet")))
		var ai_faction := _resolve_faction(want, rng)
		var level: String = str(slot.get("level", next_ai_difficulty))

		var strategy: String = _resolve_strategy(str(slot.get("strategy", next_ai_strategy)))
		teams[idx] = team
		player_map["Multi%d" % spawn_index[spawns[k]]] = idx
		_spawn_start(idx, spawns[k], ai_faction)
		player_factions[idx] = ai_faction
		taken.append(spawns[k])
		spawns.remove_at(k)
		sim.give_credits(idx, next_credits)
		sim.set_faction(idx, ai_faction)
		sim.enable_bot(idx, _bot_params(level, strategy))
		sim.set_handicap(idx, int(AI_HANDICAPS.get(level, 0)))
		used_players.append(idx)
		_roster_add(idx, -1, "", ai_faction, team, "bot", level, -1, strategy)


	for a in used_players:
		for b in used_players:
			if a == b:
				continue
			var ta := int(teams.get(a, 0))
			var tb := int(teams.get(b, 0))
			if ta > 0 and ta == tb:
				sim.set_alliance(a, b, true)
				sim.set_enemy(a, b, false)
				continue
			sim.set_enemy(a, b, true)
		sim.set_enemy(PLAYER_CREEPS, a, true)
		sim.set_enemy(a, PLAYER_CREEPS, true)

	var any_team := false
	for p in teams:
		if int(teams[p]) > 0:
			any_team = true
	if any_team:
		var lines: Array = []
		for p in used_players:
			var foes: Array = []
			for o in used_players:
				if o != p and sim.hostile(p, o):
					foes.append(o)
			lines.append("Spieler %d (Team %d, %s) Gegner: %s" % [p, int(teams.get(p, 0)),
					player_factions.get(p, "?"), foes])
		print("Lobby: Startpunkt %d — %s" % [spawn_index.get(player_spawn, -1), "; ".join(PackedStringArray(lines))])
	center_on((Vector2(player_spawn) + Vector2(0.5, 0.5)) * CELL)


func _attach_multiplayer() -> void:
	next_setup = {}
	net_session = null
	var hub := NetHub.hub()
	if hub == null or not hub.active():

		if OS.get_cmdline_user_args().has("--mp-log"):
			order_log = OrderLog.new()
			order_log.begin("einzel", {"map": next_map})
		return
	next_setup = hub.setup
	net_session = hub.session
	next_map = str(next_setup.get("map", next_map))
	next_mission = ""
	next_credits = int(next_setup.get("credits", next_credits))
	next_starting_units = str(next_setup.get("starting_units", next_starting_units))
	next_crates = bool(next_setup.get("crates", true))
	next_explored_map = bool(next_setup.get("explored_map", false))
	next_fog = bool(next_setup.get("fog", true))
	next_savegame = ""
	_pending_save = {}
	_seed = int(next_setup.get("seed", 0))


func _start_multiplayer() -> void:
	if net_session == null or sim == null:
		return
	net_session.sim = sim
	net_session.begin()

	_tick_len = float(int(next_setup.get("tick_ms", 40))) / 1000.0


func _apply_setup(setup: Dictionary) -> void:
	var seats: Array = setup.get("seats", [])
	var spawns: Array = map_data.spawns
	var spawn_index := {}
	for i in spawns.size():
		spawn_index[spawns[i]] = i

	if sim.has_method("set_rng_seed"):
		sim.set_rng_seed(int(setup.get("seed", 0)))
	if sim.has_method("set_visibility_players"):
		var mask := 0
		for pl in setup.get("visibility_players", []):
			mask |= 1 << int(pl)
		sim.set_visibility_players(mask)

	local_player = 0
	var my_seat: int = net_session.local_seat if net_session != null else 0
	for e in seats:
		if int(e.get("seat", -1)) == my_seat:
			local_player = int(e.get("sim", 0))
	if sim.has_method("set_local_player"):
		sim.set_local_player(local_player)
	var used: Array = []
	var teams := {}
	var my_cell := Vector2i.ZERO
	player_roster = []
	for e in seats:
		var pid := int(e.get("sim", 0))
		var faction := str(e.get("faction", "allies"))
		var cell_arr: Array = e.get("spawn_cell", [8, 8])
		var cell := Vector2i(int(cell_arr[0]), int(cell_arr[1]))
		player_map["Multi%d" % int(e.get("spawn", spawn_index.get(cell, 0)))] = pid
		player_factions[pid] = faction
		teams[pid] = int(e.get("team", 0))
		used.append(pid)


		_roster_add(pid, int(e.get("seat", -1)), str(e.get("name", "")), faction,
				int(e.get("team", 0)), str(e.get("kind", "human")), str(e.get("level", "")),
				int(e.get("color", -1)), str(e.get("strategy", "")))

		for su in e.get("start_units", []):
			var sc: Array = su.get("cell", [cell.x, cell.y])
			var type := str(su.get("type", "mcv"))
			var scell := Vector2i(int(sc[0]), int(sc[1]))
			if type == "mcv" and not types.has("mcv"):
				_add_building("fact", pid, scell - Vector2i(1, 1))
			elif types.has(type):
				spawn_unit(type, pid, scell, int(su.get("facing", -1)))
		sim.set_faction(pid, faction)
		sim.give_credits(pid, int(setup.get("credits", 5000)))
		sim.reveal(pid, cell.x, cell.y, 5)
		if str(e.get("kind", "human")) == "bot":
			var level := str(e.get("level", "normal"))


			var strategy := str(e.get("strategy", "normal"))
			if strategy == "naval" and not _map_has_water():
				strategy = "normal"
			sim.enable_bot(pid, _bot_params(level, strategy))
			sim.set_handicap(pid, int(AI_HANDICAPS.get(level, 0)))
		if pid == local_player:
			my_cell = cell
			next_faction = faction

	for a in used:
		for b in used:
			if a == b:
				continue
			var ta := int(teams.get(a, 0))
			var tb := int(teams.get(b, 0))
			if ta > 0 and ta == tb:
				sim.set_alliance(a, b, true)
				sim.set_enemy(a, b, false)
				continue
			sim.set_enemy(a, b, true)
		sim.set_enemy(PLAYER_CREEPS, a, true)
		sim.set_enemy(a, PLAYER_CREEPS, true)
	center_on((Vector2(my_cell) + Vector2(0.5, 0.5)) * CELL)
	print("Mehrspieler: Platz %d (Sim %d), %d Plätze, Seed %d" % [my_seat, local_player,
			seats.size(), int(setup.get("seed", 0))])


	var team_lines: Array = []
	for p in used:
		var foes: Array = []
		for o in used:
			if o != p and sim.hostile(p, o):
				foes.append(o)
		team_lines.append("Sim %d (Team %d) Gegner: %s" % [p, int(teams.get(p, 0)), foes])
	print("Mehrspieler-Teams: %s" % "; ".join(PackedStringArray(team_lines)))


func _add_building(type: String, player: int, origin: Vector2i, health_percent: int = 100) -> Unit:
	var u := Unit.new()
	u.type = type
	u.player = player
	u.id = sim.spawn_building(type_ids[type], player, origin.x, origin.y, health_percent)
	var rows: PackedStringArray = types[type]["footprint"].split(" ")
	u.pos = (Vector2(origin) + Vector2(rows[0].length() / 2.0, types[type]["sprite_h"] / 2.0)) * CELL
	u.goal = u.pos


	if u.id < 0:
		return u
	units.append(u)
	return u


func _sync_new_actors(state: PackedFloat32Array) -> void:
	var n := state.size() / RENDER_STRIDE
	while units.size() < n:
		var k := units.size() * RENDER_STRIDE
		var u := Unit.new()
		u.id = int(state[k])
		u.type = type_names[int(state[k + 1])]
		u.player = int(state[k + 2])
		u.pos = Vector2(state[k + 3], state[k + 4])
		u.goal = u.pos
		units.append(u)
		if types[u.type].get("building", false):
			_ore_version = -1


func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func visible_world_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(_camera.position - size / 2.0, size)


func pan_screen(delta: Vector2) -> void:
	_momentum = Vector2.ZERO
	_camera.position -= delta / zoom
	_clamp_camera()


func _screen_to_world_now(p: Vector2) -> Vector2:
	return _camera.position + (p - get_viewport_rect().size / 2.0) / zoom


func zoom_at(factor: float, screen_center: Vector2) -> void:
	var before := _screen_to_world_now(screen_center)
	_apply_zoom(clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM))
	_target_zoom = zoom
	_camera.position = before - (screen_center - get_viewport_rect().size / 2.0) / zoom
	_clamp_camera()


func end_camera_gesture(velocity: Vector2) -> void:
	_momentum = velocity.limit_length(MAX_FLING)
	_target_zoom = zoom


func center_on(world_pos: Vector2) -> void:
	_momentum = Vector2.ZERO
	_camera.position = world_pos
	_clamp_camera()


func _apply_zoom(z: float) -> void:
	zoom = z
	_camera.zoom = Vector2(z, z)


func _clamp_camera() -> void:
	var half := get_viewport_rect().size / zoom / 2.0
	var area := Rect2(Vector2(bounds.position) * CELL, Vector2(bounds.size) * CELL)
	var p := _camera.position
	p.x = clampf(p.x, area.position.x + half.x, area.end.x - half.x) if area.size.x > half.x * 2 else area.get_center().x
	p.y = clampf(p.y, area.position.y + half.y, area.end.y - half.y) if area.size.y > half.y * 2 else area.get_center().y
	_camera.position = p


func unit_rect(u: Unit) -> Rect2:
	var b: Vector2 = types[u.type]["bounds"]


	return Rect2(u.pos - b / 2.0 - Vector2(0.0, u.altitude), b)


func vis_map() -> PackedByteArray:
	return _vis


func vis_version() -> int:
	return _vis_version


func visibility_at(world_pos: Vector2) -> int:
	if _vis.size() != map_w * map_h:
		return 2
	var c := _cell_of(world_pos)
	if c.x < 0 or c.y < 0 or c.x >= map_w or c.y >= map_h:
		return 2
	return _vis[c.y * map_w + c.x]


func actor_shown(u: Unit) -> bool:
	if u == null or not u.alive:
		return false
	if u.player == local_player:
		return true
	if types[u.type].get("building", false):


		return u.visible and visibility_at(u.pos) > 0
	return u.visible


const TARGET_BARREL := 1 << 17


const TARGET_TREES := 1 << 9
const TARGET_NO_AUTO := 1 << 10


func pickable(u: Unit) -> bool:
	var t: Dictionary = types[u.type]


	if t.get("crate", false):
		return false


	if t.get("husk", false):
		return false


	if t.get("mine", false):
		return false


	if not t.get("bridge", {}).is_empty():
		return false


	return int(t.get("target_types", 0)) & ~(TARGET_TREES | TARGET_NO_AUTO) != 0


func pick_bridge(world_pos: Vector2, repair_only: bool = true) -> Unit:
	if repair_only:
		var any := false
		for u in selection:
			if u.alive and types[u.type].get("repairs_bridges", false):
				any = true
				break
		if not any:
			return null


	var u: Unit = _bridge_cell.get(_cell_of(world_pos))
	if u == null or not (u.alive and u.visible):
		return null
	if repair_only and u.hp >= 1.0:
		return null
	return u


func pick_unit(world_pos: Vector2, radius: float) -> Unit:
	var hit: Unit = null
	for u in units:
		if not (u.alive and u.visible and pickable(u) and unit_rect(u).has_point(world_pos)):
			continue
		if hit == null:
			hit = u
			continue


		var hit_building: bool = types[hit.type].get("building", false)
		if types[u.type].get("building", false):
			if not hit_building:
				continue
		elif hit_building:
			hit = u
			continue
		if u.pos.y > hit.pos.y:
			hit = u
	if hit != null:
		return hit
	var best: Unit = null
	var best_key := INF
	for u in units:
		if not u.alive or not u.visible or not pickable(u):
			continue
		var r := unit_rect(u)
		var nearest := Vector2(clampf(world_pos.x, r.position.x, r.end.x), clampf(world_pos.y, r.position.y, r.end.y))
		var d := world_pos.distance_to(nearest)
		if d > radius:
			continue
		var prio := 0 if (u.player == local_player and types[u.type]["combat"]) else (1 if u.player == local_player else 2)
		var key := prio * 10000.0 + d
		if key < best_key:
			best_key = key
			best = u
	return best


func selectable(u: Unit) -> bool:
	return u != null and not types[u.type].get("interactable_only", false)


func select_only(u: Unit) -> void:
	if additive_select and u != null:

		if u.selected:
			u.selected = false
			selection.erase(u)
			return
		u.selected = true
		selection.append(u)
		_voice("select")
		return
	clear_selection()
	if u != null:
		u.selected = true
		selection.append(u)
	_voice("select")


func select_exclusive(u: Unit) -> void:
	clear_selection()
	if u == null or not selectable(u):
		return
	u.selected = true
	selection.append(u)
	_voice("select")


func select_append(u: Unit) -> bool:
	if u == null or not selectable(u) or u.selected:
		return false
	u.selected = true
	selection.append(u)
	_voice("select")
	return true


func select_all_units() -> int:
	clear_selection()
	var best_prio := -1
	for u in units:

		if u.alive and u.player == local_player and not types[u.type].get("building", false) and pickable(u):
			best_prio = maxi(best_prio, int(types[u.type].get("select_priority", 10)))
	for u in units:
		if u.alive and u.player == local_player and not types[u.type].get("building", false) and pickable(u) \
				and int(types[u.type].get("select_priority", 10)) == best_prio:
			u.selected = true
			selection.append(u)
	if not selection.is_empty():
		_voice("select")
	return selection.size()


func select_same_type_visible(u: Unit) -> void:
	clear_selection()
	var view := visible_world_rect()
	for o in units:
		if o.alive and o.player == u.player and o.type == u.type and view.has_point(o.pos):
			o.selected = true
			selection.append(o)
	_voice("select")


func clear_selection() -> void:
	for u in selection:
		u.selected = false
	selection.clear()


func begin_box(screen_pos: Vector2) -> void:
	_box_active = true
	_box_a = screen_to_world(screen_pos)
	_box_b = _box_a


func update_box(screen_pos: Vector2) -> void:
	_box_b = screen_to_world(screen_pos)


func end_box() -> int:
	_box_active = false
	var r := Rect2(_box_a, Vector2.ZERO).expand(_box_b).abs()
	var hit: Array[Unit] = []
	var best_tier := 3
	for u in units:
		if u.alive and u.player == local_player and u.visible and r.has_point(u.pos) and pickable(u):
			hit.append(u)
			best_tier = mini(best_tier, _select_tier(u))
	if not additive_select:
		clear_selection()
	for u in hit:
		if _select_tier(u) != best_tier or u.selected:
			continue
		u.selected = true
		selection.append(u)
	if not selection.is_empty():
		_voice("select")
	return selection.size()


func _select_tier(u: Unit) -> int:
	if types[u.type].get("building", false):
		return 2
	return 0 if types[u.type]["combat"] else 1


func cancel_box() -> void:
	_box_active = false


func _voice(kind: String) -> void:
	for u in selection:
		var g := voice_lines(u, kind)
		var clips: Array = g.get("clips", [])
		if clips.is_empty():
			continue
		sfx.play_voice(clips, g.get("variants", []), u.id, "%s/%s" % [types[u.type].get("voice", ""), kind])
		return


var _diag := false
var _unit_node: MultiMeshInstance2D
var _unit_mode := "rs"
var _unit_redraw := false
var _unit_static_done := false


func _draw_units(alpha: float) -> void:
	if _unit_mode == "rs":
		sim.fill_multimesh(_unit_mm.get_rid(), alpha)
	elif _unit_mode == "gd" or (_unit_mode == "static" and not _unit_static_done):
		var b: PackedFloat32Array = sim.render_buffer(alpha)
		var n := b.size() / 12
		if n == 0:
			return
		_unit_static_done = true
		if _unit_mm.instance_count < n:
			_unit_mm.instance_count = maxi(n, _unit_mm.instance_count * 2)
		for i in n:
			var k := i * 12
			_unit_mm.set_instance_transform_2d(i, Transform2D(Vector2(b[k], b[k + 4]), Vector2(b[k + 1], b[k + 5]), Vector2(b[k + 3], b[k + 7])))
			_unit_mm.set_instance_custom_data(i, Color(b[k + 8], b[k + 9], b[k + 10], b[k + 11]))
		_unit_mm.visible_instance_count = n
	if _unit_redraw:
		_unit_node.queue_redraw()
var _diag_time := 0.0
var _diag_probe: MultiMeshInstance2D


func _diag_tick(delta: float) -> void:
	_diag_time += delta
	if _diag_probe == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = _unit_quad()
		mm.instance_count = 2
		var at := _camera.position
		mm.set_instance_transform_2d(0, Transform2D(0.0, at + Vector2(-60, 0)))
		mm.set_instance_custom_data(0, Color(_atlas.frame_index("fact", 0) if _atlas.sprite_frame_count.has("fact") else 0, 0, 0, 0))
		mm.set_instance_transform_2d(1, Transform2D(0.0, at + Vector2(60, 0)))
		mm.set_instance_custom_data(1, Color(_atlas.frame_index("mcv", 0) if _atlas.sprite_frame_count.has("mcv") else 0, 1, 0, 0))
		_diag_probe = MultiMeshInstance2D.new()
		_diag_probe.multimesh = mm
		_diag_probe.material = _make_material(_atlas)
		add_child(_diag_probe)
	if fmod(_diag_time, 5.0) < delta:
		var buf: PackedFloat32Array = _unit_mm.buffer
		var head := []
		for i in mini(24, buf.size()):
			head.append(snappedf(buf[i], 0.01))
		print("DIAG adapter=", RenderingServer.get_video_adapter_name(), " atlas=", _atlas.atlas_texture.get_size(),
			" table=", _atlas.frame_table_texture.get_size(), " palette=", _atlas.palette_texture.get_size(),
			" instances=", _unit_mm.instance_count, " visible=", _unit_mm.visible_instance_count, " aabb=", _unit_mm.get_aabb(), " buffer=", buf.size(), " head=", head,
			" cam=", _camera.position, " zoom=", zoom, " units=", units.size(), " kisten=", sim.crate_count())


func _refresh_units_fast(state: PackedFloat32Array = PackedFloat32Array()) -> void:
	if state.is_empty():
		state = sim.render_state(1.0)
	var n := mini(units.size(), state.size() / RENDER_STRIDE)
	for i in n:
		var u := units[i]
		var k := i * RENDER_STRIDE
		u.pos = Vector2(state[k + 3], state[k + 4])
		u.moving = state[k + 6] > 0.5
		u.alive = state[k + 7] > 0.5
		u.hp = state[k + 8] / 1000.0
		u.firing = state[k + 9] > 0.5


		u.selling = int(state[k + 11]) & 2 != 0
		u.altitude = state[k + 14]
		u.passengers = int(state[k + 15])
		u.cargo_max = int(state[k + 16])
		u.ammo = int(state[k + 17])
		u.ammo_max = int(state[k + 18])


const VOICE_ORDERS := ["move", "attack", "attack_move", "build", "kill", "demolish"]


const DEATH_VOICE_KEYS := ["DefaultDeath", "BulletDeath", "SmallExplosionDeath", "ExplosionDeath",
		"FireDeath", "ElectricityDeath", "DefaultDeath"]


func voice_lines(u: Unit, kind: String) -> Dictionary:
	var t: Dictionary = types[u.type]
	var set_name: String = t.get("voice", "")
	var group := kind
	if VOICE_ORDERS.has(kind):
		group = String(t.get("voice_overrides", {}).get(kind, "Action")).to_lower()
	var faction: String = String(player_factions.get(u.player, next_faction if u.player == local_player else next_ai_faction))
	if next_mission != "":
		for p in map_data.players:
			if player_map.get(p["name"], -1) == u.player:
				faction = "soviet" if p.get("faction", "") in ["soviet", "russia", "ukraine"] else "allies"
	var sets: Dictionary = rules.voices.get(set_name, {}).get(faction, {})
	var g: Dictionary = sets.get(group, {})
	if g.get("clips", []).is_empty() and group != "action":
		g = sets.get("action", {})
	return g if not g.is_empty() else {"clips": [], "variants": []}


func deploy_selected() -> bool:
	var ids := PackedInt32Array()
	var any := false
	var undeploy := false
	for u in selection:
		if u.alive and types[u.type].has("transforms"):
			any = true
			if sim.can_deploy(u.id):
				ids.append(u.id)
				undeploy = undeploy or types[u.type].get("building", false)
	if ids.is_empty():
		if any:
			eva("nodeply1")
		return false
	issue(NetOrders.make(NetOrders.OP_DEPLOY, 0, 0, 0, 0, ids))


	if undeploy:
		sfx.play_local("cashturn")
	else:
		_play_build_sounds()
	_voice("action")
	_ore_version = -1
	return true


func support_powers() -> PackedInt32Array:
	return sim.support_powers(local_player)


func activate_support_power(kind: int, at: Vector2, at2: Vector2 = Vector2.ZERO) -> bool:
	var c := Vector2i((at / CELL).floor())

	var packed := -1
	if at2 != Vector2.ZERO:
		var c2 := Vector2i((at2 / CELL).floor())
		packed = NetOrders.pack_cell2(c2.x, c2.y)
	return issue(NetOrders.make(NetOrders.OP_SUPPORT_POWER, kind, c.x, c.y, packed))


func selection_can_lay_mine() -> bool:
	for u in selection:
		if u.alive and types[u.type].has("minelayer_mine") and sim.can_lay_mine(u.id):
			return true
	return false


func lay_mine_selected() -> bool:
	var ids := PackedInt32Array()
	for u in selection:
		if u.alive and types[u.type].has("minelayer_mine") and sim.can_lay_mine(u.id):
			ids.append(u.id)
	if ids.is_empty():
		return false
	issue(NetOrders.make(NetOrders.OP_LAY_MINE, 0, 0, 0, 0, ids))
	return true


func selection_can_deploy() -> bool:
	for u in selection:
		if u.alive and types[u.type].has("transforms"):
			return true
	return false


func has_deploy_action(type_name: String) -> bool:
	var t: Dictionary = types.get(type_name, {})
	return t.has("transforms") or t.has("minelayer_mine") or t.has("mad_charge_delay") \
			or t.get("detonate_on_deploy", false) or t.has("chrono_charge_delay")


func deploy_action(type_name: String) -> String:
	var t: Dictionary = types.get(type_name, {})
	if t.has("transforms"):
		return "deploy"
	if t.has("minelayer_mine"):
		return "mine"
	if t.has("mad_charge_delay"):
		return "detonate"
	if t.get("detonate_on_deploy", false):
		return "demolish"
	if t.has("chrono_charge_delay"):
		return "chrono"
	return ""


func selection_can_detonate() -> bool:
	for u in selection:
		if u.alive and _detonator(u) and sim.can_detonate(u.id):
			return true
	return false


func _detonator(u: Unit) -> bool:
	var t: Dictionary = types[u.type]
	return t.has("mad_charge_delay") or t.get("detonate_on_deploy", false)


func detonate_selected() -> bool:
	var ids := PackedInt32Array()
	for u in selection:
		if u.alive and _detonator(u) and sim.can_detonate(u.id):
			ids.append(u.id)
	if ids.is_empty():
		return false
	issue(NetOrders.make(NetOrders.OP_DETONATE, 0, 0, 0, 0, ids))
	_voice("action")
	return true


func selection_can_chrono() -> bool:
	for u in selection:
		if u.alive and types[u.type].has("chrono_charge_delay") and sim.can_chrono(u.id):
			return true
	return false


func chrono_range_cells() -> int:
	for u in selection:
		if u.alive and types[u.type].has("chrono_charge_delay"):
			return sim.chrono_max_cells(u.id)
	return 0


func chrono_charge_ratio(u: Unit) -> float:
	var t: Dictionary = types.get(u.type, {})
	var total: int = int(t.get("chrono_charge_delay", 0))
	if total <= 0:
		return 1.0
	return clampf(1.0 - float(sim.chrono_charge_left(u.id)) / float(total), 0.0, 1.0)


func chrono_selected(world_pos: Vector2) -> bool:
	var ids := PackedInt32Array()
	for u in selection:
		if u.alive and types[u.type].has("chrono_charge_delay") and sim.can_chrono(u.id):
			ids.append(u.id)
	if ids.is_empty():
		return false
	var cell := _cell_of(world_pos)
	if not issue(NetOrders.make(NetOrders.OP_CHRONO, cell.x, cell.y, 0, 0, ids)):
		return false
	_voice("action")
	_ore_version = -1
	return true


func issue(cmd: PackedInt32Array) -> bool:
	if sim == null:
		return false
	if order_log != null:
		order_log.local(int(sim.tick()), cmd)
	if net_session != null:
		net_session.queue(cmd)
		return true
	var r = NetOrders.apply(sim, local_player, cmd)
	return true if r == null else bool(r)


func multiplayer_active() -> bool:
	return net_session != null


func _selection_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for u in selection:
		if u.alive:
			ids.append(u.id)
	return ids


func _cell_of(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / CELL)


var queue_orders := false


func _queued() -> int:
	return 1 if queue_orders else 0


func order_move_ids(ids: PackedInt32Array, cell: Vector2i) -> void:
	if sim != null and ids.size() > 0:
		issue(NetOrders.make(NetOrders.OP_MOVE, cell.x, cell.y, 0, 0, ids))


func order_attack_move(world_target: Vector2) -> void:
	if sim == null or selection.is_empty():
		return
	var cell := _cell_of(world_target)
	issue(NetOrders.make(NetOrders.OP_ATTACK_MOVE, cell.x, cell.y, _queued(), 0, _selection_ids()))
	_set_goals((Vector2(cell) + Vector2(0.5, 0.5)) * CELL, 1)
	_voice("attack_move")


func order_move(world_target: Vector2) -> void:
	if sim == null or selection.is_empty():
		return
	var cell := _cell_of(world_target)
	issue(NetOrders.make(NetOrders.OP_MOVE, cell.x, cell.y, _queued(), 0, _selection_ids()))
	_set_goals((Vector2(cell) + Vector2(0.5, 0.5)) * CELL)
	_voice("move")


func order_enter(target: Unit) -> String:
	if sim == null or target == null or selection.is_empty() or not sim.has_method("enter_kind_for"):
		return ""
	var ids := PackedInt32Array()
	var kind := ENTER_NONE
	for u in selection:
		if not u.alive:
			continue
		var k: int = sim.enter_kind_for(u.id, target.id)
		if k == ENTER_NONE:
			continue
		if kind == ENTER_NONE:
			kind = k
		if k == kind:
			ids.append(u.id)
	if ids.is_empty():
		return ""
	issue(NetOrders.make(NetOrders.OP_ENTER, target.id, 0, 0, 0, ids))
	show_enter_effect(unit_rect(target).get_center())


	_set_goals(target.pos, 4 if kind == ENTER_DEMOLISH else 0)


	_voice("demolish" if kind == ENTER_DEMOLISH else "action")
	return ENTER_LABELS.get(kind, "")


func order_disguise(target: Unit) -> bool:
	if sim == null or not sim.has_method("order_disguise"):
		return false
	var any := false
	for u in selection:
		if u.alive and types[u.type].get("disguise", false) and issue(NetOrders.make_one(NetOrders.OP_DISGUISE, u.id, -1 if target == null else target.id)):
			any = true
	if any:
		_voice("action")
	return any


func enter_kind(target: Unit) -> int:
	if sim == null or target == null or not sim.has_method("enter_kind_for"):
		return ENTER_NONE
	for u in selection:
		if u.alive:
			var k: int = sim.enter_kind_for(u.id, target.id)
			if k != ENTER_NONE:
				return k
	return ENTER_NONE


func has_disguiser() -> bool:
	for u in selection:
		if u.alive and types[u.type].get("disguise", false):
			return true
	return false


func board_ids(target: Unit) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if target == null or not target.alive or target.player != local_player or sim == null:
		return ids
	if not sim.has_method("order_enter_transport") or int(types[target.type].get("cargo_max_weight", 0)) <= 0:
		return ids
	for u in selection:
		if u == target or not u.alive:
			continue
		if int(types[u.type].get("passenger_weight", 0)) <= 0:
			continue
		if not sim.can_load(target.id, u.id):
			continue
		ids.append(u.id)
	return ids


func can_board(target: Unit) -> bool:
	return not board_ids(target).is_empty()


func order_enter_transport(target: Unit) -> bool:
	var ids := board_ids(target)
	if ids.is_empty():
		return false
	issue(NetOrders.make(NetOrders.OP_ENTER_TRANSPORT, target.id, 0, 0, 0, ids))
	_set_goals(target.pos, 0)
	_voice("move")
	return true


func selection_can_unload() -> bool:
	for u in selection:
		if u.alive and u.player == local_player and u.passengers > 0:
			return true
	return false


func selection_unload_blocked() -> bool:
	if sim == null or not sim.has_method("can_unload"):
		return false
	for u in selection:
		if u.alive and u.player == local_player and u.passengers > 0 and sim.can_unload(u.id):
			return false
	return true


func loaded_ids(ready_only: bool = true) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if sim == null or not sim.has_method("order_unload"):
		return ids
	for u in selection:
		if u.alive and u.player == local_player and u.passengers > 0:
			if ready_only and sim.has_method("can_unload") and not sim.can_unload(u.id):
				continue
			ids.append(u.id)
	return ids


func unload_ids(ids: PackedInt32Array) -> bool:
	if sim == null or ids.is_empty() or not sim.has_method("order_unload"):
		return false
	issue(NetOrders.make(NetOrders.OP_UNLOAD, 0, 0, 0, 0, ids))
	_voice("move")
	return true


func unload_selected() -> bool:
	return unload_ids(loaded_ids())


func order_attack(target: Unit, force: bool = false) -> bool:
	if sim == null or selection.is_empty() or target == null:
		return false
	issue(NetOrders.make(NetOrders.OP_ATTACK, target.id, _queued(), 1 if force else 0, 0, _selection_ids()))
	_set_goals(target.pos, 2)
	_voice("attack")
	return true


func selection_armed() -> bool:
	for u in selection:
		if u.alive and u.player == local_player and str(types.get(u.type, {}).get("weapon", "")) != "":
			return true
	return false


func selection_can_force_attack(target: Unit) -> bool:
	if sim == null or target == null or not target.alive or selection.is_empty():
		return false
	if not sim.has_method("force_attacking"):
		return false
	for u in selection:
		if u.alive and u.id != target.id and str(types.get(u.type, {}).get("weapon", "")) != "":
			return true
	return false


func order_harvest(world_target: Vector2) -> bool:
	if sim == null:
		return false
	var ids := PackedInt32Array()
	for u in selection:
		if u.alive and types[u.type].get("harvester", false):
			ids.append(u.id)
	if ids.is_empty():
		return false
	var cell := _cell_of(world_target)
	issue(NetOrders.make(NetOrders.OP_HARVEST, cell.x, cell.y, 0, 0, ids))
	_set_goals((Vector2(cell) + Vector2(0.5, 0.5)) * CELL, 3)
	_voice("action")
	return true


func has_ore(world_pos: Vector2) -> bool:
	var cell := _cell_of(world_pos)
	return sim != null and sim.resource_density(cell.x, cell.y) > 0


func queue_build(type_id: int) -> void:
	if sim == null:
		return
	var t: Dictionary = types.get(type_names.get(type_id, ""), {})
	var q := int(t.get("queue", -1))


	var before: int = sim.queue_state(local_player, q).size() if q >= 0 else 0
	if not issue(NetOrders.make(NetOrders.OP_QUEUE_BUILD, type_id)):
		return
	if net_session == null and q >= 0 and sim.queue_state(local_player, q).size() <= before:
		return
	if q == Queue.INFANTRY:
		eva("train1")
	elif q == Queue.VEHICLE or q == Queue.SHIP or q == Queue.AIRCRAFT:
		eva("abldgin1")


func cancel_build(kind: int, type_id: int) -> void:
	if sim != null:
		issue(NetOrders.make(NetOrders.OP_CANCEL_BUILD, kind, type_id))


func begin_placement(type_id: int) -> void:
	placing_type = type_id
	place_armed = false
	var name: String = type_names[type_id]
	var t: Dictionary = types[name]
	_ghost = _atlas.make_rgba_texture(t.get("body", name), 0)


	_ghost_overlay = _atlas.make_rgba_texture(t["overlay_sprite"], t["overlay_start"]) if t.has("overlay_sprite") else null
	move_placement(visible_world_rect().get_center())


func placement_origin_for(world_pos: Vector2) -> Vector2i:
	return placement_origin_of(type_names[placing_type], world_pos)


func placement_origin_of(type_name: String, world_pos: Vector2) -> Vector2i:
	var bounds_v: Vector2 = types[type_name].get("bounds", Vector2(CELL, CELL))
	var p: Vector2 = (world_pos - bounds_v / 2.0) / CELL + Vector2(0.5, 0.5)
	return Vector2i(floori(p.x), floori(p.y))


func placement_pos_for(type_name: String, origin: Vector2i) -> Vector2:
	return Vector2(origin) * CELL + types[type_name].get("bounds", Vector2(CELL, CELL)) / 2.0


func ghost_draw_pos(type_name: String, origin: Vector2i, texture_size: Vector2) -> Vector2:
	var t: Dictionary = types[type_name]
	var bounds_v: Vector2 = t.get("bounds", Vector2(CELL, CELL))
	var center: Vector2 = Vector2(origin) * CELL + bounds_v / 2.0
	var off := Vector2(t.get("offset_x", 0), t.get("offset_y", 0))
	return center - texture_size / 2.0 + off


func move_placement(world_pos: Vector2) -> void:
	if placing_type < 0:
		return
	place_origin = placement_origin_for(world_pos)
	var res: PackedByteArray = sim.can_place(local_player, placing_type, place_origin.x, place_origin.y)
	_place_ok = res.size() > 0 and res[0] == 1
	_place_cells = res.slice(1)
	_place_area_ok = footprint_in_build_area(placing_type, place_origin)


const BUILD_AREA_TTL := 0.5

var _area_mask := PackedByteArray()
var _area_adjacent := -1
var _area_time := -100.0
var _area_outline := PackedVector2Array()


func build_adjacent(type_id: int) -> int:
	return int(types[type_names[type_id]].get("adjacent", 2))


func build_area_mask(adjacent: int) -> PackedByteArray:
	if sim == null:
		return PackedByteArray()
	var now := Time.get_ticks_msec() / 1000.0
	if adjacent != _area_adjacent or now - _area_time > BUILD_AREA_TTL:
		_area_adjacent = adjacent
		_area_time = now
		_area_mask = sim.build_area(local_player, adjacent)
		_area_outline = _build_area_outline(_area_mask)
	return _area_mask


func footprint_in_build_area(type_id: int, origin: Vector2i) -> bool:
	var t: Dictionary = types[type_names[type_id]]
	var rows: PackedStringArray = t["footprint"].split(" ")
	var mask := build_area_mask(build_adjacent(type_id))
	if mask.size() != map_w * map_h:
		return false
	for y in rows.size():
		for x in rows[0].length():
			var c := origin + Vector2i(x, y)
			if c.x >= 0 and c.y >= 0 and c.x < map_w and c.y < map_h and mask[c.y * map_w + c.x] == 1:
				return true
	return false


func build_area_in_view(adjacent: int = 2) -> bool:
	var mask := build_area_mask(adjacent)
	if mask.size() != map_w * map_h:
		return false
	var view := visible_world_rect()
	var x0 := maxi(0, int(floor(view.position.x / CELL)))
	var y0 := maxi(0, int(floor(view.position.y / CELL)))
	var x1 := mini(map_w - 1, int(floor(view.end.x / CELL)))
	var y1 := mini(map_h - 1, int(floor(view.end.y / CELL)))
	for y in range(y0, y1 + 1):
		var row := y * map_w
		for x in range(x0, x1 + 1):
			if mask[row + x] == 1:
				return true
	return false


func _build_area_outline(mask: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	if mask.size() != map_w * map_h:
		return out
	for y in map_h:
		var row := y * map_w
		for x in map_w:
			if mask[row + x] != 1:
				continue
			var p := Vector2(x, y) * CELL
			if x == 0 or mask[row + x - 1] != 1:
				out.append(p); out.append(p + Vector2(0, CELL))
			if x == map_w - 1 or mask[row + x + 1] != 1:
				out.append(p + Vector2(CELL, 0)); out.append(p + Vector2(CELL, CELL))
			if y == 0 or mask[row - map_w + x] != 1:
				out.append(p); out.append(p + Vector2(CELL, 0))
			if y == map_h - 1 or mask[row + map_w + x] != 1:
				out.append(p + Vector2(0, CELL)); out.append(p + Vector2(CELL, CELL))
	return out


func _play_build_sounds() -> void:
	sfx.play_local("placbldg")
	sfx.play_local("build5")


func _play_random_at(list: Array, pos: Vector2) -> void:
	if list.is_empty():
		return
	sfx.play_at(sfx.register(String(list[randi() % list.size()])), pos)


func _tap_hits_ghost(world_pos: Vector2) -> bool:
	var t: Dictionary = types[type_names[placing_type]]
	var rows: PackedStringArray = t["footprint"].split(" ")
	var cell := _cell_of(world_pos)
	if cell.x >= place_origin.x and cell.x < place_origin.x + rows[0].length() \
			and cell.y >= place_origin.y and cell.y < place_origin.y + rows.size():
		return true
	if _ghost != null:
		var pos := ghost_draw_pos(type_names[placing_type], place_origin, Vector2(_ghost.get_size()))
		if Rect2(pos, Vector2(_ghost.get_size())).has_point(world_pos):
			return true
	return false


func tap_placement(world_pos: Vector2) -> bool:
	if placing_type < 0:
		return false
	if place_armed and _tap_hits_ghost(world_pos):
		if _place_ok:
			return confirm_placement()
		eva("nodeply1")
		return false
	move_placement(world_pos)
	place_armed = true
	return false


func placement_ok() -> bool:
	return placing_type >= 0 and _place_ok


func confirm_placement() -> bool:
	if placing_type < 0 or not _place_ok:
		return false


	var res: PackedByteArray = sim.can_place(local_player, placing_type, place_origin.x, place_origin.y)
	var ok: bool = res.size() > 0 and res[0] == 1
	if ok:
		issue(NetOrders.make(NetOrders.OP_PLACE_BUILDING, placing_type, place_origin.x, place_origin.y))
		_play_build_sounds()
		placing_type = -1
		_ore_version = -1
	return ok


func cancel_placement() -> void:
	placing_type = -1


var _pending_ghost: ImageTexture
var _pending_ghost_type := -1


func _draw_pending_place() -> void:
	if sim == null:
		return
	for k in 2:
		var pp: PackedInt32Array = sim.pending_place(local_player, k)
		if pp.size() < 3:
			continue
		var type_id: int = pp[0]
		if type_id < 0 or type_id >= type_names.size():
			continue
		var origin := Vector2i(pp[1], pp[2])
		var name: String = type_names[type_id]
		var t: Dictionary = types[name]
		if _pending_ghost_type != type_id:
			_pending_ghost_type = type_id
			_pending_ghost = _atlas.make_rgba_texture(t.get("body", name), 0)
		var rows: PackedStringArray = t["footprint"].split(" ")
		for y in rows.size():
			for x in rows[0].length():
				var r := Rect2(Vector2(origin + Vector2i(x, y)) * CELL, Vector2(CELL, CELL))
				_overlay.draw_rect(r, Color(1.0, 0.85, 0.25, 0.18), true)
				_overlay.draw_rect(r, Color(1.0, 0.85, 0.25, 0.35), false, 1.0)
		if _pending_ghost != null:
			_overlay.draw_texture(_pending_ghost,
					ghost_draw_pos(name, origin, Vector2(_pending_ghost.get_size())), Color(1, 1, 1, 0.35))


func _draw_placement() -> void:
	if placing_type < 0:
		return
	var t: Dictionary = types[type_names[placing_type]]
	var rows: PackedStringArray = t["footprint"].split(" ")
	var w := rows[0].length()


	build_area_mask(build_adjacent(placing_type))
	if not _area_outline.is_empty():
		_overlay.draw_multiline(_area_outline, Color(1, 1, 1, 0.30), 1.0 / zoom)


	for y in rows.size():
		for x in w:
			var i := y * w + x
			var cell_ok: bool = _place_area_ok and (i >= _place_cells.size() or _place_cells[i] == 1)
			var col := Color(0.2, 1.0, 0.3, 0.4) if cell_ok else Color(1.0, 0.2, 0.2, 0.45)
			_overlay.draw_rect(Rect2(Vector2(place_origin + Vector2i(x, y)) * CELL, Vector2(CELL, CELL)), col, true)
			_overlay.draw_rect(Rect2(Vector2(place_origin + Vector2i(x, y)) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, 0.35), false, 1.0)


	var bounds_v: Vector2 = t.get("bounds", Vector2(CELL, CELL))
	var center: Vector2 = Vector2(place_origin) * CELL + bounds_v / 2.0
	if _ghost != null:
		var pos := ghost_draw_pos(type_names[placing_type], place_origin, Vector2(_ghost.get_size()))
		_overlay.draw_texture(_ghost, pos, Color(1, 1, 1, 0.65))


		if _ghost_overlay != null:
			_overlay.draw_texture(_ghost_overlay, pos, Color(1, 1, 1, 0.65))


	var name: String = type_names[placing_type]
	var lw := 2.0 / zoom
	if t.get("defense", false):
		_draw_range_circle(center, weapon_range_px(name), Color(0.95, 0.25, 0.20, 0.5), lw)


func display_credits() -> int:
	return int(_display_credits)


func selected_building() -> Unit:
	if selection.size() != 1:
		return null
	var u := selection[0]
	return u if (u.alive and u.player == local_player and types[u.type].get("building", false)) else null


func selected_buildings() -> Array:
	var out: Array = []
	for u in selection:
		if u.alive and u.player == local_player and types[u.type].get("building", false):
			out.append(u)
	return out


func player_faction() -> String:
	if next_mission == "":
		return next_faction
	for p in map_data.players:
		if player_map.get(p["name"], -1) == 0:
			return "soviet" if p.get("faction", "") in ["soviet", "russia", "ukraine"] else "allies"
	return next_faction


func base_buildings() -> Array:
	var out: Array = []
	for u in units:
		if u.alive and u.player == local_player and is_producer(u):
			out.append(u)
	return out


func is_producer(u: Unit) -> bool:
	return u != null and types[u.type].has("produces")


func producer_kind(u: Unit) -> int:
	if not is_producer(u):
		return -1
	return types[u.type]["produces"][0]


func available_queues() -> Array[int]:
	var out: Array[int] = []
	for u in units:
		if not u.alive or u.player != local_player:
			continue
		for q in types[u.type].get("produces", []):
			if not out.has(q):
				out.append(q)
	return out


func set_rally(world_pos: Vector2) -> bool:
	var b := selected_building()
	if sim == null or not is_producer(b):
		return false
	var c := _cell_of(world_pos)
	return issue(NetOrders.make_one(NetOrders.OP_SET_RALLY, b.id, c.x, c.y))


func sell_refund() -> int:
	if sim == null:
		return 0
	var sum := 0
	for b in selected_buildings():
		sum += sim.sell_value(b.id)
	return sum


func sell_selected() -> bool:
	var any := false
	for b in selected_buildings():
		any = sell_unit(b) or any
	return any


func toggle_repair_selected() -> bool:
	var any := false
	for b in selected_buildings():
		any = toggle_repair_unit(b) or any
	return any


func sell_unit(b: Unit) -> bool:
	if sim == null or b == null or b.player != local_player or not types[b.type].get("building", false):
		return false
	return issue(NetOrders.make_one(NetOrders.OP_SELL, b.id))


func toggle_repair_unit(b: Unit) -> bool:
	if sim == null or b == null or b.player != local_player or not types[b.type].get("building", false):
		return false
	return issue(NetOrders.make_one(NetOrders.OP_TOGGLE_REPAIR, b.id))


func set_primary_selected() -> bool:
	var b := selected_building()
	if sim == null or not is_producer(b):
		return false
	return issue(NetOrders.make_one(NetOrders.OP_SET_PRIMARY, b.id))


const ENTER_FX_SECONDS := 0.5
var _enter_fx: Array = []


func show_enter_effect(center: Vector2) -> void:
	_enter_fx.append([center, Time.get_ticks_msec() / 1000.0])
	while _enter_fx.size() > 8:
		_enter_fx.pop_front()


func _draw_enter_fx() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_enter_fx.size() - 1, -1, -1):
		var age: float = now - _enter_fx[i][1]
		if age > ENTER_FX_SECONDS:
			_enter_fx.remove_at(i)
			continue
		var c: Vector2 = _enter_fx[i][0]
		var t := age / ENTER_FX_SECONDS
		var dist: float = lerpf(CELL * 1.4, CELL * 0.35, t)
		var col := Color(0.25, 0.95, 0.30, 1.0 - t * 0.6)
		var s := CELL * 0.34
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var tip: Vector2 = c + dir * dist
			var back: Vector2 = tip + dir * s
			var side := Vector2(-dir.y, dir.x) * s * 0.55
			_overlay.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)


func _draw_deploy_hint() -> void:
	if selection.is_empty() or sim == null:
		return
	for u in selection:
		if not u.alive or not types[u.type].has("transforms"):
			return
	var pulse := 0.5 - 0.5 * cos(Time.get_ticks_msec() / 1000.0 * TAU / DEPLOY_HINT_SECONDS)
	var dist: float = lerpf(CELL * 1.15, CELL * 0.55, pulse)
	var s := CELL * 0.3
	for u in selection:
		var free: bool = sim.can_deploy(u.id)

		var col := Color(1.0, 0.94, 0.7, 0.55 + 0.45 * (1.0 - pulse)) if free 				else Color(0.85, 0.25, 0.2, 0.4 + 0.25 * (1.0 - pulse))
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var tip: Vector2 = u.pos + dir * dist
			var back: Vector2 = tip + dir * s
			var side := Vector2(-dir.y, dir.x) * s * 0.55
			_overlay.draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)


func _draw_deploy_badge() -> void:
	if selection.is_empty() or sim == null:
		return
	var pulse := 0.5 - 0.5 * cos(Time.get_ticks_msec() / 1000.0 * TAU / DEPLOY_BADGE_SECONDS)
	for u in selection:
		if not u.alive or not actor_shown(u):
			continue
		var action := deploy_action(u.type)

		if action == "" or action == "deploy":
			continue
		var ready := deploy_ready(u, action)
		var r := unit_rect(u)
		var c := Vector2(r.get_center().x, r.position.y - CELL * 0.42)
		var sz := CELL * 0.17
		var col := Color(0.25, 1.0, 0.35, 0.35 + 0.65 * pulse) if ready \
				else Color(0.65, 0.65, 0.65, 0.30)

		var wdt := maxf(1.0, 1.6 / zoom)
		for k in 2:
			var y: float = c.y + k * sz * 0.55
			_overlay.draw_polyline(PackedVector2Array([
					Vector2(c.x - sz, y), Vector2(c.x, y + sz * 0.6), Vector2(c.x + sz, y)]), col, wdt)

		if action == "chrono" and not ready:
			var ratio := chrono_charge_ratio(u)
			var bar := Rect2(c.x - sz, c.y - sz * 0.6, sz * 2.0, maxf(1.0, 2.0 / zoom))
			_overlay.draw_rect(bar, Color(0, 0, 0, 0.6), true)
			_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
					Color(0.85, 0.3, 0.9), true)


func deploy_ready(u: Unit, action: String) -> bool:
	match action:
		"deploy": return sim.can_deploy(u.id)
		"mine": return sim.can_lay_mine(u.id)
		"detonate", "demolish": return sim.can_detonate(u.id)
		"chrono": return sim.can_chrono(u.id)
	return false


func deliver_ids(refinery: Unit) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if sim == null or refinery == null or refinery.player != local_player or not types[refinery.type].get("refinery", false):
		return ids
	for u in selection:
		if u.alive and types[u.type].get("harvester", false):
			ids.append(u.id)
	return ids


func can_deliver_to(refinery: Unit) -> bool:
	return not deliver_ids(refinery).is_empty()


func order_deliver(refinery: Unit) -> bool:
	var ids := deliver_ids(refinery)
	if ids.is_empty():
		return false
	if sim.has_method("order_deliver"):
		issue(NetOrders.make(NetOrders.OP_DELIVER, refinery.id, 0, 0, 0, ids))
	else:

		var t: Dictionary = types[refinery.type]
		var cell := _cell_of(refinery.pos) + Vector2i(int(t.get("dock_dx", 0)), int(t.get("dock_dy", 0)))
		issue(NetOrders.make(NetOrders.OP_MOVE, cell.x, cell.y, 0, 0, ids))
	show_enter_effect(unit_rect(refinery).get_center())
	_voice("action")
	return true


func land_ids(pad: Unit) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if sim == null or pad == null or pad.player != local_player or not sim.has_method("order_resupply"):
		return ids
	for u in selection:
		if u.alive and types[u.type].get("aircraft", false) and sim.can_resupply_at(u.id, pad.id):
			ids.append(u.id)
	return ids


func can_land_at(pad: Unit) -> bool:
	return not land_ids(pad).is_empty()


func order_land_at(pad: Unit) -> bool:
	var ids := land_ids(pad)
	if ids.is_empty():
		return false
	issue(NetOrders.make(NetOrders.OP_RESUPPLY, pad.id, 0, 0, 0, ids))
	_set_goals(pad.pos, 0)
	_voice("move")
	return true


func can_repair_at(depot: Unit) -> bool:
	return not repair_ids(depot).is_empty()


func repair_ids(depot: Unit) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if sim == null or depot == null or not types[depot.type].get("repairs_units", false):
		return ids
	for u in selection:
		if not u.alive or not types[u.type].get("repairable", false):
			continue


		var depots: Array = types[u.type].get("repair_actors", [])
		if not depots.is_empty() and not depots.has(depot.type):
			continue
		ids.append(u.id)
	return ids


func order_repair(depot: Unit) -> bool:
	var ids := repair_ids(depot)
	if ids.is_empty():
		return false
	issue(NetOrders.make(NetOrders.OP_REPAIR, depot.id, 0, 0, 0, ids))
	show_enter_effect(unit_rect(depot).get_center())
	_voice("action")
	return true


func low_power() -> bool:
	if sim == null:
		return false
	return sim.power_drained(local_player) > sim.power_provided(local_player)


func has_radar() -> bool:
	if sim == null:
		return false
	if low_power():
		return false
	for u in units:
		if u.alive and u.player == local_player and not u.selling and types[u.type].get("provides_radar", false):

			if sim.has_method("actor_jammed") and sim.actor_jammed(u.id):
				continue
			return true
	return false


func radar_jammed() -> bool:
	if sim == null or not sim.has_method("actor_jammed"):
		return false
	if low_power():
		return false
	var any := false
	for u in units:
		if not u.alive or u.player != local_player or u.selling or not types[u.type].get("provides_radar", false):
			continue
		any = true
		if not sim.actor_jammed(u.id):
			return false
	return any


func world_difficulties() -> Array:
	return map_data.difficulties if map_data != null else []


func order_guard(target: Unit) -> bool:
	if sim == null or target == null or selection.is_empty() or not sim.has_method("order_guard"):
		return false
	issue(NetOrders.make(NetOrders.OP_GUARD, target.id, _queued(), 0, 0, _selection_ids()))
	_set_goals(target.pos, 1)
	_voice("attack_move")
	return true


func order_attack_cell(world_target: Vector2) -> bool:
	if sim == null or selection.is_empty() or not sim.has_method("order_attack_cell"):
		return false
	var cell := _cell_of(world_target)
	issue(NetOrders.make(NetOrders.OP_ATTACK_CELL, cell.x, cell.y, 0, 0, _selection_ids()))
	_set_goals((Vector2(cell) + Vector2(0.5, 0.5)) * CELL, 2)
	_voice("attack")
	return true


func win_state() -> int:
	return sim.win_state(local_player) if sim != null else 0


func select_units(list: Array) -> int:
	clear_selection()
	for u in list:
		if u is Unit and u.alive and u.player == local_player:
			u.selected = true
			selection.append(u)
	if not selection.is_empty():
		_voice("select")
	return selection.size()


func selection_center() -> Vector2:
	var c := Vector2.ZERO
	if selection.is_empty():
		return c
	for u in selection:
		c += u.pos
	return c / selection.size()


func order_stop() -> void:
	if sim != null:
		issue(NetOrders.make(NetOrders.OP_STOP, 0, 0, 0, 0, _selection_ids()))
		_voice("action")


func order_scatter() -> void:
	if sim != null:
		issue(NetOrders.make(NetOrders.OP_SCATTER, 0, 0, 0, 0, _selection_ids()))
		_voice("action")


func order_harvesters_return() -> bool:
	return issue(NetOrders.make(NetOrders.OP_HARVESTERS_RETURN))


func order_harvesters_resume() -> bool:
	return issue(NetOrders.make(NetOrders.OP_HARVESTERS_RESUME))


func own_harvester_count() -> int:
	var n := 0
	for u in units:
		if u.alive and u.player == local_player and types[u.type].get("harvester", false):
			n += 1
	return n


func _set_goals(goal: Vector2, kind: int = 0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for u in selection:
		u.goal = goal
		u.goal_time = now
		u.goal_kind = kind


func _process(delta: float) -> void:
	if _momentum.length() > 1.0:
		_camera.position -= _momentum * delta / zoom
		_momentum *= pow(0.0005, delta)
		_clamp_camera()
	if not is_equal_approx(zoom, _target_zoom):
		_apply_zoom(lerpf(zoom, _target_zoom, minf(delta * 12.0, 1.0)))

	if _diag and sim != null:
		_diag_tick(delta)
	_update_water_phase()


	if sim != null and (not paused or net_session != null):

		var want := GameSpeed.tick_seconds()
		if not is_equal_approx(want, _tick_len):
			_tick_len = want
		_sim_accum += delta
		var steps := 0


		var max_steps := GameSpeed.max_catchup()


		if net_session != null:
			_sim_accum = 0.0
			steps = net_session.pump(delta)
		else:
			while _sim_accum >= _tick_len and steps < max_steps:
				sim.step()
				_sim_accum -= _tick_len
				steps += 1
				if mission != null:

					var snap: PackedFloat32Array = sim.render_state(1.0)
					_sync_new_actors(snap)
					_refresh_units_fast(snap)
					mission_api.tick()
					mission.tick()
		var alpha: float = net_session.alpha() if net_session != null else clampf(_sim_accum / _tick_len, 0.0, 1.0)


		_draw_units(alpha)

		if sim.resource_version() != _ore_version:
			_ore_version = sim.resource_version()
			_rebuild_ore()

		if _smudge_mm != null and sim.has_method("smudge_version") and sim.smudge_version() != _smudge_version:
			_smudge_version = sim.smudge_version()
			_rebuild_smudges()

		sfx.play_events(sim.drain_sounds())


		var state: PackedFloat32Array = sim.render_state(alpha)
		_sync_new_actors(state)
		_fog_frame += 1
		if _fog_frame % 6 == 0:
			var vis: PackedByteArray = sim.visibility_map(local_player)
			if vis.size() == map_w * map_h:


				_vis = vis
				_vis_version += 1
				if _diag and _vis_version % 40 == 1:


					var c0 := 0
					var c1 := 0
					var c2 := 0
					for b in vis:
						if b == 0: c0 += 1
						elif b == 1: c1 += 1
						else: c2 += 1
					print("Shroud: unerkundet %d, Nebel %d, sichtbar %d (reveal=%s, Nebel aus=%s)" % [
							c0, c1, c2, _reveal_all, _fog_off])
				_fog_img.set_data(map_w, map_h, false, Image.FORMAT_R8, vis)
				_fog_tex.update(_fog_img)
			_poll_frozen_and_gps()


		var nukes_raw: PackedInt32Array = sim.pending_nukes()
		_nukes.clear()
		var nuke_now := {}
		var nk := 0
		while nk + 3 < nukes_raw.size():
			var npos := Vector2(nukes_raw[nk + 1], nukes_raw[nk + 2])
			_nukes.append({"owner": nukes_raw[nk], "pos": npos, "ticks": nukes_raw[nk + 3]})
			nuke_now["%d:%d:%d" % [nukes_raw[nk], nukes_raw[nk + 1], nukes_raw[nk + 2]]] = nukes_raw[nk + 3]
			nk += 4


		for key in _nuke_seen:
			if not nuke_now.has(key) and int(_nuke_seen[key]) <= 2:
				_nuke_flash = NUKE_FLASH_SEC
		_nuke_seen = nuke_now
		_nuke_layer.queue_redraw()


		var cash_ticks: PackedInt32Array = sim.drain_cash_ticks()
		var ct := 0
		while ct + 3 < cash_ticks.size():
			if cash_ticks[ct] == 0:
				show_float_text(Vector2(cash_ticks[ct + 2], cash_ticks[ct + 3]), "+%d" % cash_ticks[ct + 1])
			ct += 4
		for n in sim.drain_notifications(local_player):
			if n < 0 or n >= NOTIFY_SOUNDS.size():
				continue
			if n == 13 or n == 14:


				eva(NOTIFY_SOUNDS[n], 0.0, true)
				notify_event.emit(n)
				continue
			if NOTIFY_SOUNDS[n] != "":
				eva(NOTIFY_SOUNDS[n])
			notify_event.emit(n)
		var dead_selected := false

		for i in mini(units.size(), state.size() / RENDER_STRIDE):
			var u := units[i]
			var k := i * RENDER_STRIDE
			u.pos = Vector2(state[k + 3], state[k + 4])
			u.facing = int(state[k + 5])
			u.moving = state[k + 6] > 0.5
			var alive := state[k + 7] > 0.5
			var flags := int(state[k + 11])
			var selling := flags & 2 != 0


			var tid := int(state[k + 1])
			if tid >= 0 and tid < type_names.size() and type_names[tid] != u.type:
				u.type = type_names[tid]
				if types[u.type].get("husk", false) and u.selected:
					u.selected = false
					selection.erase(u)
			var tt: Dictionary = types[u.type]
			if u.alive and not alive and not (selling or u.selling) and tt.get("death_voice", false):


				var dgroup := "die"
				if sim.has_method("last_damage_type"):
					var dkey: String = DEATH_VOICE_KEYS[clampi(int(sim.last_damage_type(u.id)), 0, DEATH_VOICE_KEYS.size() - 1)]
					dgroup = String(tt.get("death_voices", {}).get(dkey, "Die")).to_lower()
				var dies: Dictionary = voice_lines(u, dgroup)
				var dclips: Array = dies.get("clips", [])
				if not dclips.is_empty():
					var dname: String = dclips[randi() % dclips.size()]
					var dvars: Array = dies.get("variants", [])
					if not dvars.is_empty():
						dname = "%s_%s" % [dname, String(dvars[abs(u.id) % dvars.size()]).trim_prefix(".")]
					sfx.play_at(sfx.register(dname), u.pos)
			if u.alive and not alive and u.player == local_player and not (selling or u.selling):
				eva("unitlst1")
			var hp := state[k + 8] / 1000.0


			var by_self := sim.has_method("last_attacker_owner") and int(sim.last_attacker_owner(u.id)) == u.player
			if u.player == local_player and hp < u.hp and alive and not selling and not u.selling and not by_self and tt.get("building", false):
				eva("baseatk1")
				under_attack.emit(u.pos)
			elif u.player == local_player and hp < u.hp and alive and tt.get("harvester", false):
				under_attack.emit(u.pos)


			if alive and hp < 0.5 and u.hp >= 0.5 and tt.has("damaged_sounds"):
				_play_random_at(tt["damaged_sounds"], u.pos)
			elif u.alive and not alive and tt.has("destroyed_sounds") and not (selling or u.selling):
				_play_random_at(tt["destroyed_sounds"], u.pos)


			var owner := int(state[k + 2])
			if alive and owner != u.player:
				u.player = owner
			if u.alive and not alive and tt.get("building", false):
				_ore_version = -1
			u.alive = alive
			u.hp = hp
			u.firing = state[k + 9] > 0.5
			u.cargo = state[k + 10] / 1000.0
			u.repairing = flags & 1 != 0
			u.selling = selling
			u.primary = flags & 4 != 0
			u.visible = flags & 8 != 0
			u.rank = (flags >> 4) & 7
			u.unpowered = flags & 128 != 0
			u.demolishing = flags & 256 != 0
			u.demolish_left = (flags >> 10) & 127
			u.rally = Vector2i(int(state[k + 12]), int(state[k + 13]))
			u.altitude = state[k + 14]
			u.passengers = int(state[k + 15])
			u.cargo_max = int(state[k + 16])
			u.ammo = int(state[k + 17])
			u.ammo_max = int(state[k + 18])
			if not u.alive and u.selected:
				dead_selected = true
		if dead_selected:
			for u in selection.duplicate():
				if not u.alive:
					u.selected = false
					selection.erase(u)

		if not _bridges.is_empty():
			_update_bridges()


		var real := float(sim.credits(local_player))
		if not is_equal_approx(_display_credits, real):

			var diff := absf(real - _display_credits)
			var step := clampf(diff * 0.07, 37.0, diff)
			var before := _display_credits
			_display_credits = move_toward(_display_credits, real, step)
			_cash_tick_accum += delta
			var up := _display_credits > before
			if _cash_tick_accum >= (0.07 if up else 0.14):
				_cash_tick_accum = 0.0
				sfx.play_ticker("cashup1" if up else "cashdn1")

		if _diag:
			sim_text = "Credits: %d   Strom: %d/%d   Sim: C++ v%s  Tick %d  %d µs/Tick  eigene %d  Gegner %d" % [
			int(_display_credits), sim.power_provided(local_player), sim.power_drained(local_player), sim.version(), sim.tick(),
			sim.last_step_usec(), sim.alive_count(local_player), sim.alive_count(1)]

	_overlay.queue_redraw()


func _setup_smudges() -> void:
	_smudge_names = {}
	if not sim.has_method("set_smudge_sprites"):
		return
	for kind in RulesDb.SMUDGE_SPRITES:
		var names: Array = []
		var depth := 1
		for stem in RulesDb.SMUDGE_SPRITES[kind]:
			if not _terrain.sprite_frame_count.has(stem):
				continue
			names.append(stem)
			depth = maxi(depth, _terrain.sprite_frame_count[stem])
		_smudge_names[kind] = names


		sim.set_smudge_sprites(kind, names.size(), depth)


func _rebuild_smudges() -> void:
	var list: PackedInt32Array = sim.smudges()
	var n: int = list.size() / 5
	var instances: Array = []
	for i in n:
		var k: int = i * 5
		var kind: int = list[k + 2]
		var names: Array = _smudge_names.get(kind, [])
		if names.is_empty():
			continue
		var stem: String = names[list[k + 3] % names.size()]
		var frames: int = _terrain.sprite_frame_count[stem]
		var depth: int = clampi(list[k + 4], 0, frames - 1)
		instances.append([Vector2(list[k], list[k + 1]) * CELL, _terrain.frame_index(stem, depth)])
	_smudge_mm.instance_count = instances.size()
	for i in instances.size():
		_smudge_mm.set_instance_transform_2d(i, Transform2D(0.0, instances[i][0]))
		_smudge_mm.set_instance_custom_data(i, Color(instances[i][1], _terrain.terrain_row, 0, 0))


func _rebuild_ore() -> void:
	var map: PackedByteArray = sim.resource_map()
	var instances: Array = []
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var v := map[y * map_w + x]
			var density := v & 0x0F
			var rtype := v >> 4
			if density == 0:
				continue
			var variant := ("gem0%d" if rtype == 2 else "gold0%d") % (((x * 7 + y * 13) % 4) + 1)
			if not _terrain.sprite_frame_count.has(variant):
				continue
			var n: int = _terrain.sprite_frame_count[variant]
			var max_density := 3 if rtype == 2 else 12
			var frame := _terrain.frame_index(variant, (n - 1) * mini(density, max_density) / max_density)
			instances.append([Vector2(x, y) * CELL, frame])
	for u in units:
		var t: Dictionary = types[u.type]
		if not t.has("bib"):
			continue


		if not (actor_shown(u) or _frozen.has(u.id)):
			continue
		var bib: String = t["bib"]
		if not _terrain.sprite_frame_count.has(bib):
			continue
		var rows: PackedStringArray = t["footprint"].split(" ")
		var bib_w := rows[0].length()


		var bib_rows: int = _terrain.sprite_frame_count[bib] / bib_w
		var bib_row := rows.size() - bib_rows
		var origin := Vector2i((u.pos / CELL) - Vector2(bib_w / 2.0, t["sprite_h"] / 2.0))
		for i in _terrain.sprite_frame_count[bib]:
			var cell := origin + Vector2i(i % bib_w, bib_row + i / bib_w)
			instances.append([Vector2(cell) * CELL, _terrain.frame_index(bib, i)])
	_ore_mm.instance_count = instances.size()
	for i in instances.size():
		_ore_mm.set_instance_transform_2d(i, Transform2D(0.0, instances[i][0]))


		_ore_mm.set_instance_custom_data(i, Color(instances[i][1], _terrain.terrain_row, 0, 0))


func nuke_targets() -> Array:
	return _nukes


func _poll_frozen_and_gps() -> void:
	if sim.has_method("frozen_actors"):
		var raw: PackedInt32Array = sim.frozen_actors()
		var seen := {}
		var key := ""
		var i := 0
		while i + 5 < raw.size():
			if raw[i + 5] >= 0:
				seen[raw[i]] = true
				key += "%d," % raw[i]
			i += 6
		if key != _frozen_key:
			_frozen_key = key
			_frozen = seen
			_ore_version = -1
	if sim.has_method("gps_dots"):
		_gps_active = sim.gps_active()
		var d: PackedInt32Array = sim.gps_dots()
		_gps_dots.clear()
		var k := 0
		while k + 3 < d.size():
			_gps_dots.append([Vector2(d[k], d[k + 1]), d[k + 2], d[k + 3] != 0])
			k += 4


func _draw_gps_dots() -> void:
	if _gps_dots.is_empty():
		return
	var r := maxf(2.0, 3.0 / zoom)
	var w := maxf(1.0, 1.0 / zoom)
	for d in _gps_dots:
		var pos: Vector2 = d[0]
		var col: Color = player_colors[d[1]] if d[1] < player_colors.size() else Color.WHITE
		if d[2]:
			_nuke_layer.draw_rect(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), col)
			_nuke_layer.draw_rect(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), Color(0, 0, 0, 0.7), false, w)
		else:
			_nuke_layer.draw_circle(pos, r, col)
			_nuke_layer.draw_arc(pos, r, 0, TAU, 12, Color(0, 0, 0, 0.7), w)


func gps_dots() -> Array:
	return _gps_dots


func nuke_flash() -> float:
	return _nuke_flash


func _draw_nuke_beacons() -> void:
	_draw_gps_dots()

	if _nuke_flash > 0.0:
		_nuke_flash = maxf(0.0, _nuke_flash - get_process_delta_time())
		_nuke_layer.draw_rect(visible_world_rect().grow(CELL),
				Color(1, 1, 1, clampf(_nuke_flash / NUKE_FLASH_SEC, 0.0, 1.0)))
		_nuke_layer.queue_redraw()
	if _nukes.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var w := maxf(1.0, 2.0 / zoom)
	for n in _nukes:
		var pos: Vector2 = n["pos"]
		var phase := fposmod(now * 1.1, 1.0)
		var ring_col := Color(1.0, 0.25, 0.15, 1.0 - phase)
		_nuke_layer.draw_arc(pos, CELL * (1.5 + phase * 1.6), 0, TAU, 28, ring_col, w * 1.5)
		HudTheme.draw_atom(_nuke_layer, pos, CELL * 1.05, Color(1.0, 0.85, 0.25, 0.92), w)


func _draw_overlay() -> void:
	var w := 2.0 / zoom
	for u in selection:
		if not u.alive or not actor_shown(u):
			continue
		var r := unit_rect(u).grow(2.0)
		var l := minf(r.size.x, r.size.y) * 0.3
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := -1.0 if c.x > r.get_center().x else 1.0
			var sy := -1.0 if c.y > r.get_center().y else 1.0
			_overlay.draw_line(c, c + Vector2(sx * l, 0), Color.WHITE, w)
			_overlay.draw_line(c, c + Vector2(0, sy * l), Color.WHITE, w)


		var age := Time.get_ticks_msec() / 1000.0 - u.goal_time
		if u.moving and age < 600.0:


			var gc: Color = [Color.WHITE, Color(1.0, 0.85, 0.2), Color(0.95, 0.3, 0.25),
					Color(0.3, 0.9, 0.3), Color(0.86, 0.16, 0.16)][clampi(u.goal_kind, 0, 4)]
			gc.a = 0.55
			_overlay.draw_line(u.pos, u.goal, gc, w)


	for u in units:
		if not u.alive or (not u.selected and u.hp >= 0.999) or not actor_shown(u) or not pickable(u):
			continue
		var r := unit_rect(u)
		var bar := Rect2(r.position.x, r.position.y - 4.0, r.size.x, 2.0)
		_overlay.draw_rect(bar, Color(0, 0, 0, 0.7), true)
		var col := Color.GREEN if u.hp > 0.5 else (Color.YELLOW if u.hp > 0.25 else Color.RED)
		_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * u.hp, bar.size.y)), col, true)

		if u.selected and types[u.type].get("harvester", false):
			var pips := 7
			var filled := int(round(u.cargo * pips))
			for p in pips:
				var pr := Rect2(r.position.x + 1.0 + p * 4.0, r.end.y - 3.0, 3.0, 2.0)
				_overlay.draw_rect(pr, Color(0, 0, 0, 0.7), true)
				if p < filled:
					_overlay.draw_rect(pr.grow(-0.5), Color(1.0, 0.85, 0.2), true)

		if u.selected and u.cargo_max > 0:
			for p in mini(u.cargo_max, 8):
				var pr := Rect2(r.position.x + 1.0 + p * 4.0, r.end.y - 3.0, 3.0, 2.0)
				_overlay.draw_rect(pr, Color(0, 0, 0, 0.7), true)
				if p < u.passengers:
					_overlay.draw_rect(pr.grow(-0.5), Color(0.4, 0.9, 1.0), true)

		if u.selected and u.ammo_max > 0:
			var apips := mini(u.ammo_max, 6)
			var afilled := int(ceil(float(u.ammo) * apips / float(u.ammo_max)))
			for p in apips:
				var pr := Rect2(r.position.x + 1.0 + p * 4.0, r.end.y - 6.0, 3.0, 2.0)
				_overlay.draw_rect(pr, Color(0, 0, 0, 0.7), true)
				if p < afilled:
					_overlay.draw_rect(pr.grow(-0.5), Color(1.0, 0.4, 0.3), true)


		var rpips := int(types[u.type].get("resource_pips", 0))
		if u.selected and rpips > 0 and sim != null:
			var cap: int = sim.storage_capacity(u.player)
			var filled: int = (int(sim.resources_stored(u.player)) * rpips / cap) if cap > 0 else 0
			for p in rpips:
				var pr := Rect2(r.position.x + 1.0 + p * 4.0, r.end.y - 3.0, 3.0, 2.0)
				_overlay.draw_rect(pr, Color(0, 0, 0, 0.7), true)
				if p < filled:
					_overlay.draw_rect(pr.grow(-0.5), Color(1.0, 0.85, 0.2), true)
	_draw_ranks()


	if sim != null and sim.has_method("enter_progress"):
		for u in units:
			if not u.alive or not actor_shown(u):
				continue
			var prog: int = sim.enter_progress(u.id)
			if prog < 0:
				continue
			var pr := unit_rect(u)
			var pb := Rect2(pr.position.x, pr.position.y - 7.0, pr.size.x, 2.0)
			_overlay.draw_rect(pb, Color(0, 0, 0, 0.7), true)
			_overlay.draw_rect(Rect2(pb.position, Vector2(pb.size.x * prog / 1000.0, pb.size.y)), Color(1.0, 0.65, 0.0), true)
	_draw_building_decorations(w)
	_draw_detection_circles(w)
	_draw_c4_markers(w)
	_draw_enter_fx()
	_draw_deploy_hint()
	_draw_deploy_badge()
	_draw_float_texts()
	if _box_active:
		var r := Rect2(_box_a, Vector2.ZERO).expand(_box_b).abs()
		_overlay.draw_rect(r, Color(1, 1, 1, 0.12), true)
		_overlay.draw_rect(r, Color.WHITE, false, w)
	_draw_pending_place()
	_draw_placement()


var _flag_frames: Array[ImageTexture] = []
var _rank_frames: Array[ImageTexture] = []


func _draw_ranks() -> void:
	if _rank_frames.is_empty():
		if not _atlas.sprite_frame_count.has("rank"):
			return
		for f in mini(4, _atlas.sprite_frame_count["rank"]):
			_rank_frames.append(_atlas.make_rgba_texture("rank", f, 0))
	for u in units:
		if u.rank <= 0 or not u.alive or not actor_shown(u):
			continue
		var tex: ImageTexture = _rank_frames[mini(u.rank, _rank_frames.size()) - 1]
		var r := unit_rect(u)
		_overlay.draw_texture(tex, Vector2(r.end.x - tex.get_width() - 1.0, r.end.y - tex.get_height() - 1.0))


var _range_px := {}


func weapon_range_px(type_name: String) -> float:
	if _range_px.has(type_name):
		return _range_px[type_name]
	var t: Dictionary = types.get(type_name, {})
	var wname: String = t.get("weapon", "")
	var rng: float = float(rules.weapons.get(wname, {}).get("range", 0)) / 1024.0 * CELL if wname != "" else 0.0
	_range_px[type_name] = rng
	return rng


func _draw_range_circle(center: Vector2, radius: float, col: Color, w: float) -> void:
	if radius <= 0.0:
		return
	_overlay.draw_arc(center, radius, 0.0, TAU, 72, col, w, true)


var _c4_targets: Array = []
var _c4_scan := -1.0


const C4_FUSE_TICKS := 45


const FLOAT_SECONDS := 1.2
const DEPLOY_HINT_SECONDS := 1.1
const DEPLOY_BADGE_SECONDS := 0.8
var _float_texts: Array = []
var floats_shown := 0


func show_float_text(pos: Vector2, text: String, col: Color = Color(1.0, 0.85, 0.25)) -> void:
	floats_shown += 1
	_float_texts.append([pos, text, col, Time.get_ticks_msec() / 1000.0])
	while _float_texts.size() > 12:
		_float_texts.pop_front()


func _draw_float_texts() -> void:
	if _float_texts.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var font := ThemeDB.fallback_font
	var fs := 10
	for i in range(_float_texts.size() - 1, -1, -1):
		var age: float = now - _float_texts[i][3]
		if age > FLOAT_SECONDS:
			_float_texts.remove_at(i)
			continue
		var t := age / FLOAT_SECONDS
		var pos: Vector2 = _float_texts[i][0] + Vector2(0, -CELL * 0.5 - t * CELL)
		var col: Color = _float_texts[i][2]
		col.a = 1.0 - t * t
		var text: String = _float_texts[i][1]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := pos - Vector2(tw / 2.0, 0)
		_overlay.draw_string(font, at + Vector2(0.7, 0.7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, col.a))
		_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func c4_marker_count() -> int:
	return _c4_targets.size()


func _draw_c4_icon(center: Vector2, alpha: float, w: float, ratio: float = -1.0) -> void:
	const GOLD := Color(1.0, 0.84, 0.25)
	const DARK := Color(0.12, 0.09, 0.03)
	var r := 4.6
	var col := GOLD
	col.a = alpha
	var dark := DARK
	dark.a = alpha

	_overlay.draw_circle(center, r, col)
	_overlay.draw_arc(center, r, 0.0, TAU, 24, dark, w, true)

	_overlay.draw_line(center + Vector2(2.0, -3.8), center + Vector2(3.3, -6.2), dark, w * 1.4)
	_overlay.draw_line(center + Vector2(3.3, -6.2), center + Vector2(5.4, -7.4), col, w)
	var spark := Color(1.0, 0.45, 0.15, alpha)
	_overlay.draw_circle(center + Vector2(5.4, -7.4), 1.5, spark)

	var t: float = 1.0 if ratio < 0.0 else clampf(ratio, 0.0, 1.0)
	_overlay.draw_line(center, center + Vector2(0, -r * 0.62), dark, w)
	_overlay.draw_line(center, center + Vector2.from_angle(-PI / 2.0 + (1.0 - t) * TAU) * (r * 0.52), dark, w)

	if ratio >= 0.0:
		var ring := Color(1.0, 0.35, 0.2, alpha)
		_overlay.draw_arc(center, r + 2.4, -PI / 2.0, -PI / 2.0 + t * TAU, 28, ring, w * 1.6, true)


func _draw_c4_markers(w: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if sim != null and sim.has_method("enter_kind_for") and now - _c4_scan > 0.25:
		_c4_scan = now
		_c4_targets.clear()
		var has_demo := false
		for u in selection:
			if u.alive and types[u.type].has("demolition_delay"):
				has_demo = true
		if has_demo:
			for u in units:


				if u.alive and u.player != local_player and actor_shown(u) and pickable(u) \
						and enter_kind(u) == ENTER_DEMOLISH:
					_c4_targets.append(u)
	for u in _c4_targets:
		if u.alive:
			_draw_c4_icon(unit_rect(u).get_center() + Vector2(0, -CELL * 0.6), 0.45, w)


	for u in units:
		if u.alive and u.demolishing and actor_shown(u):
			_draw_c4_icon(unit_rect(u).get_center(), 0.95, w,
					clampf(float(u.demolish_left) / float(C4_FUSE_TICKS), 0.0, 1.0))


func _draw_detection_circles(w: float) -> void:
	for u in selection:
		if not u.alive or u.player != local_player or not types[u.type].get("render_detect_circle", false):
			continue
		var rng: float = float(types[u.type].get("detect_range", 0)) / 1024.0 * CELL
		if rng <= 0.0:
			continue
		_draw_range_circle(unit_rect(u).get_center(), rng, Color(0.25, 0.8, 0.95, 0.45), w * 0.8)


func _draw_building_decorations(w: float) -> void:
	var font := ThemeDB.fallback_font
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for u in units:
		if not u.alive or u.player != local_player or not types[u.type].get("building", false):
			continue
		var r := unit_rect(u)

		var ut: Dictionary = types[u.type]


		if ut.get("defense", false):
			_draw_range_circle(r.get_center(), weapon_range_px(u.type),
					Color(0.95, 0.25, 0.20, 0.5 if u.selected else 0.25), w)


		if u.repairing:
			_draw_repair_icon(r.get_center())
		if u.primary and u.selected:
			var fs := 8
			var text := "PRIMÄR"
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var at := Vector2(r.get_center().x - tw / 2.0, r.position.y - 6.0)
			_overlay.draw_string(font, at + Vector2(0.5, 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
			_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.2))
		if u.selected and is_producer(u):
			if _flag_frames.is_empty() and _atlas.sprite_frame_count.has("flagfly"):
				for f in _atlas.sprite_frame_count["flagfly"]:
					_flag_frames.append(_atlas.make_rgba_texture("flagfly", f, 0))
			var target := (Vector2(u.rally) + Vector2(0.5, 0.5)) * CELL
			_overlay.draw_line(r.get_center(), target, Color(1, 1, 1, 0.5), w)
			if not _flag_frames.is_empty():
				var tex := _flag_frames[int(Time.get_ticks_msec() / 100) % _flag_frames.size()]

				_overlay.draw_texture(tex, target + Vector2(11, -5) - Vector2(tex.get_width(), tex.get_height()) / 2.0)
			else:
				_overlay.draw_circle(target, 3.0, Color(1.0, 0.85, 0.2))


const REPAIR_ICON := "res://assets/ui/repair_wrench.png"
const REPAIR_FRAMES := 5
const REPAIR_TICK_MS := 160
var _repair_tex: Texture2D
var _repair_loaded := false


func _draw_repair_icon(center: Vector2) -> void:
	if not _repair_loaded:
		_repair_loaded = true
		if ResourceLoader.exists(REPAIR_ICON):
			_repair_tex = load(REPAIR_ICON)
	if _repair_tex == null:
		_draw_wrench(center, 6.0, 2.0 / zoom)
		return
	var fw := _repair_tex.get_width() / REPAIR_FRAMES
	var fh := _repair_tex.get_height()
	var f := int(Time.get_ticks_msec() / REPAIR_TICK_MS) % REPAIR_FRAMES
	_overlay.draw_texture_rect_region(_repair_tex,
			Rect2(center - Vector2(fw, fh) / 2.0, Vector2(fw, fh)),
			Rect2(f * fw, 0, fw, fh))


func _draw_wrench(c: Vector2, size: float, w: float) -> void:
	var col := Color(1.0, 0.85, 0.2)
	_overlay.draw_circle(c, size * 1.3, Color(0, 0, 0, 0.6))
	_overlay.draw_line(c + Vector2(-size, size), c + Vector2(size * 0.4, -size * 0.4), col, w * 2.0)
	_overlay.draw_arc(c + Vector2(size * 0.6, -size * 0.6), size * 0.5, -PI * 0.75, PI * 0.75, 10, col, w * 1.5)


static func _unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
