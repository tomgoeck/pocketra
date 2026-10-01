

class_name ContentPaths
extends RefCounted

const DIR := "user://content"
const MIX := DIR + "/mix"
const MIX_DE := DIR + "/mix_de"
const ATLAS := DIR + "/atlas"
const SFX := DIR + "/sfx"


const CD := DIR + "/cd"
const CD_IDS := ["allied", "soviet", "german"]

static var _status := {}
static var _checked := false


static func status() -> Dictionary:
	if not _checked:
		_checked = true
		_status = RaContent.content_status(DIR)
		if bool(_status.get("ready", false)):
			print("Inhalte: ", DIR, " (", _status.get("atlases", []), ", ",
					_status.get("sfx", 0), " Sounds, Sprachen ", _status.get("languages", []), ")")
	return _status


static func refresh() -> Dictionary:
	_checked = false
	_content = null
	_content_tried = false
	return status()


static func ready() -> bool:
	return bool(status().get("ready", false))


static func _has_atlas_pixels(base: String) -> bool:
	if FileAccess.file_exists(base + ".r8"):
		return true
	return FileAccess.file_exists(base + "_web.json") and FileAccess.file_exists(base + "_web_0.r8")


static func atlas(name: String) -> String:
	var p := ATLAS.path_join("atlas_%s" % name)
	if FileAccess.file_exists(p + ".json") and _has_atlas_pixels(p):
		return p
	return "res://assets/atlas/atlas_%s" % name


static func has_atlas(name: String) -> bool:
	return FileAccess.file_exists(atlas(name) + ".json")


static func palette(name: String) -> String:
	var p := ATLAS.path_join("%s.rgba" % name)
	if FileAccess.file_exists(p):
		return p
	return "res://assets/atlas/%s.rgba" % name


static func sfx(name: String) -> String:
	var lang := Lang.code()


	var lang_paths := [SFX.path_join(lang).path_join(name + ".wav"),
			"res://data/sfx/%s/%s.wav" % [lang, name], "res://assets/sfx/%s/%s.wav" % [lang, name]]
	var base_paths := [SFX.path_join(name + ".wav"), "res://data/sfx/%s.wav" % name]
	for p in lang_paths + base_paths:
		if p.begins_with("res://"):
			if ResourceLoader.exists(p):
				return p
		elif FileAccess.file_exists(p):
			return p
	return "res://assets/sfx/%s.wav" % name


const EXTRAS := "user://extras"
const EXTRAS_MUSIC := EXTRAS + "/music"
const EXTRAS_MAPS := EXTRAS + "/maps"


static func music_dir() -> String:
	if DirAccess.dir_exists_absolute(EXTRAS_MUSIC) and FileAccess.file_exists(EXTRAS_MUSIC.path_join("1.mp3")):
		return EXTRAS_MUSIC
	return "res://assets/music"


static func maps_dir() -> String:
	if FileAccess.file_exists(EXTRAS_MAPS.path_join("index.json")):
		return EXTRAS_MAPS
	return "res://assets/maps"


static func mix_dir() -> String:
	return MIX if DirAccess.dir_exists_absolute(MIX) else ""


static func mix_dir_de() -> String:
	if DirAccess.dir_exists_absolute(MIX_DE):
		return MIX_DE
	var g := CD.path_join("german")
	return g if DirAccess.dir_exists_absolute(g) else ""


static func cd_dirs() -> Array[String]:
	var out: Array[String] = []
	for id in CD_IDS:
		var d: String = CD.path_join(id)
		if DirAccess.dir_exists_absolute(d):
			out.append(d)
	return out


static var _content: RaContent = null
static var _content_tried := false


static func archives() -> RaContent:
	if _content_tried:
		return _content
	_content_tried = true
	var d := mix_dir()
	var cds := cd_dirs()
	if d == "" and cds.is_empty():
		return null
	var c := RaContent.new()
	var opened := 0


	var de := mix_dir_de()
	if de != "" and Lang.code() == "de":
		opened += c.open_dir(de)


	for cd_dir in cds:
		if cd_dir == de:
			continue
		opened += c.open_dir(cd_dir)
	if d != "":
		opened += c.open_dir(d)
	if opened == 0:
		print("Inhalte: keine Archive in ", d, " / ", cds, " (", c.last_error(), ")")
		return null
	_content = c
	return _content
