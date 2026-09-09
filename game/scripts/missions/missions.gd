

class_name Missions
extends RefCounted

const SCRIPTS := {
	"tutorial": "res://scripts/missions/tutorial.gd",
	"allies-01": "res://scripts/missions/allies01.gd",
	"allies-02": "res://scripts/missions/allies02.gd",
	"allies-03a": "res://scripts/missions/allies03a.gd",
	"allies-03b": "res://scripts/missions/allies03b.gd",
	"allies-04": "res://scripts/missions/allies04.gd",
	"soviet-01": "res://scripts/missions/soviet01.gd",
	"soviet-02a": "res://scripts/missions/soviet02a.gd",
	"soviet-02b": "res://scripts/missions/soviet02b.gd",
	"allies-13": "res://scripts/missions/allies13.gd",
	"soviet-04a": "res://scripts/missions/soviet04a.gd",
	"soviet-04b": "res://scripts/missions/soviet04b.gd",
	"soviet-05": "res://scripts/missions/soviet05.gd",
	"soviet-06a": "res://scripts/missions/soviet06a.gd",
	"soviet-06b": "res://scripts/missions/soviet06b.gd",
	"soviet-07": "res://scripts/missions/soviet07.gd",
	"allies-10b": "res://scripts/missions/allies10b.gd",
	"allies-05a": "res://scripts/missions/allies05a.gd",
	"allies-05b": "res://scripts/missions/allies05b.gd",
}


const BLOCKED := {


	"allies-06a": "lock.reason.allies_06a",
	"allies-06b": "lock.reason.allies_06b",
	"soviet-03": "lock.reason.soviet_03",
}


static func blocked_reason(slug: String) -> String:
	return TranslationServer.translate(BLOCKED[slug]) if BLOCKED.has(slug) else ""

const PROGRESS := "user://progress.cfg"
const CAMPAIGNS := "res://assets/maps/campaigns.json"

const TILESETS := ["temperat", "snow", "interior"]

static var _campaigns: Array = []


static func campaigns() -> Array:
	if _campaigns.is_empty() and FileAccess.file_exists(CAMPAIGNS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGNS))
		if d is Array:
			_campaigns = d
	return _campaigns


static func campaign_of(slug: String) -> String:
	for c in campaigns():
		if c["maps"].has(slug):
			return c["name"]
	return ""


static func completed(slug: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS) != OK:
		return false
	return bool(cfg.get_value("missions", slug, false))


static func mark_completed(slug: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS)
	cfg.set_value("missions", slug, true)
	cfg.save(PROGRESS)


static func next_after(slug: String) -> String:
	for c in campaigns():
		var maps: Array = c["maps"]
		var i := maps.find(slug)
		if i < 0:
			continue
		for j in range(i + 1, maps.size()):
			if playable(maps[j]):
				return maps[j]
		return ""
	return ""


static func has_script(slug: String) -> bool:
	return SCRIPTS.has(slug) and ResourceLoader.exists(SCRIPTS[slug])


static func status(slug: String) -> String:
	if not has_script(slug):
		var r := blocked_reason(slug)
		return r if r != "" else TranslationServer.translate("lock.script_missing")
	var tileset := _tileset(slug)
	if tileset != "" and not TILESETS.has(tileset):
		return TranslationServer.translate("lock.tileset_missing") % tileset
	return ""


static func playable(slug: String) -> bool:
	return status(slug) == ""


static func _tileset(slug: String) -> String:
	for m in MapData.list_maps():
		if m.get("slug", "") == slug:
			return m.get("tileset", "")
	return ""


static func create(slug: String) -> MissionScript:
	if not has_script(slug):
		return null
	var script = load(SCRIPTS[slug])
	return script.new() if script != null else null


static func briefing(slug: String) -> String:
	var path := "res://assets/maps/%s.map.ftl" % slug
	if not FileAccess.file_exists(path):
		return ""
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var out: Array = []
	var in_briefing := false
	for line in lines:
		if line.begins_with("briefing"):
			in_briefing = true
			var rest := line.get_slice("=", 1).strip_edges()
			if rest != "":
				out.append(rest)
			continue
		if in_briefing:
			if line.begins_with("    ") or line.strip_edges() == "":
				out.append(line.strip_edges())
			else:
				break
	return "\n".join(out).strip_edges()


static func video(slug: String, role: String) -> String:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return ""
	var name: String = d.get("mission_data", {}).get("videos", {}).get(role, "")
	if name == "" or not ResourceLoader.exists(Movie.path(name)):
		return ""
	return name
