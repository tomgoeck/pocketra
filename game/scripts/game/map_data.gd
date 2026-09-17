

class_name MapData
extends RefCounted

var slug := ""
var title := ""
var tileset := "temperat"
var width := 0
var height := 0
var bounds := Rect2i()
var categories: Array = []
var players: Array = []
var spawns: Array = []
var actors: Array = []
var scripts: Array = []

var mission_data: Dictionary = {}
var default_cash := -1
var time_limit: Dictionary = {}
var notifications: Dictionary = {}
var rules_override: Dictionary = {}


var rules_format := ""
var campaign := false
var difficulties: Array = []
var difficulty_default := "normal"

var start_notification := ""


var game_over_delay := 0
var _tiles := PackedByteArray()
var _resources := PackedByteArray()


static var _gemeldet := false


static func list_maps() -> Array:
	var path := ContentPaths.maps_dir().path_join("index.json")
	if not FileAccess.file_exists(path):
		return []
	var idx = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Array = idx if idx is Array else []


	if not _gemeldet:
		_gemeldet = true
		print("Karten: %d aus %s" % [out.size(), path.get_base_dir()])
	return out


static func load(map_slug: String) -> MapData:
	var path := ContentPaths.maps_dir().path_join("%s.json" % map_slug)
	if not FileAccess.file_exists(path):
		push_error("Karte fehlt: " + path)
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return null
	var m := MapData.new()
	m.slug = d.get("slug", map_slug)
	m.title = d.get("title", map_slug)
	m.tileset = d.get("tileset", "temperat")
	m.width = int(d["width"])
	m.height = int(d["height"])
	var b: Array = d.get("bounds", [0, 0, m.width, m.height])
	m.bounds = Rect2i(int(b[0]), int(b[1]), int(b[2]), int(b[3]))
	m.categories = d.get("categories", [])
	m.players = d.get("players", [])
	for s in d.get("spawns", []):
		m.spawns.append(Vector2i(int(s[0]), int(s[1])))
	m.actors = d.get("actors", [])
	m.scripts = d.get("scripts", [])
	m.mission_data = d.get("mission_data", {})
	m.default_cash = int(d.get("default_cash", -1))
	m.time_limit = d.get("time_limit", {})
	m.notifications = d.get("notifications", {})
	m.rules_override = d.get("rules_override", {})
	m.rules_format = str(d.get("rules_format", ""))
	m.campaign = bool(d.get("campaign", false))
	m.difficulties = d.get("difficulties", [])
	m.difficulty_default = d.get("difficulty_default", "normal")
	m.start_notification = d.get("start_notification", "")
	m.game_over_delay = int(d.get("game_over_delay", 0))
	m._tiles = Marshalls.base64_to_raw(d["tiles"])
	m._resources = Marshalls.base64_to_raw(d["resources"])
	return m


func video(role: String) -> String:
	return String(mission_data.get("videos", {}).get(role, ""))


func template_at(x: int, y: int) -> int:
	var k := (y * width + x) * 3
	return _tiles[k] | (_tiles[k + 1] << 8)


func index_at(x: int, y: int) -> int:
	return _tiles[(y * width + x) * 3 + 2]


func set_tile(x: int, y: int, template: int, index: int) -> void:
	var k := (y * width + x) * 3
	_tiles[k] = template & 0xFF
	_tiles[k + 1] = (template >> 8) & 0xFF
	_tiles[k + 2] = index & 0xFF


func resource_type_at(x: int, y: int) -> int:
	return _resources[(y * width + x) * 2]


func resource_index_at(x: int, y: int) -> int:
	return _resources[(y * width + x) * 2 + 1]


func in_bounds(x: int, y: int) -> bool:
	return bounds.has_point(Vector2i(x, y))
