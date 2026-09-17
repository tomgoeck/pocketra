

class_name Music
extends Node


const DIR := "res://assets/music"

const VOLUME_FALLBACK := {
	"intro": 0.9, "map": 0.6, "score": 0.7, "credits": 0.9, "fac1226m": 0.85, "fogger1a": 0.8,
}
const HIDDEN_FALLBACK := ["intro", "map", "score"]


const ALT_OHNE_RECHTE := [
	"Iron Choir", "Iron Frontline", "Iron March", "Iron March 2", "Marching Machine",
	"Mechanical Advance", "Mechanical Warfare", "Mechanized Assault", "Neon Breakbeat",
	"Pre-Strike Tension", "Static Groove", "Tactical Assault",
]


const TITLE_FALLBACK := {
	"await_r": "Afterlife (Await)", "bigf226m": "Bigfoot", "crus226m": "Crush", "dense_r": "Dense",
	"fac1226m": "Face to the Enemy 1", "fac2226m": "Face to the Enemy 2", "fogger1a": "Fogger",
	"hell226m": "Hell March", "intro": "Intro", "map": "Map", "mud1a": "Mud", "radio2": "Radio 2",
	"credits": "Reload Fire (Credits)", "rollout": "Roll Out", "run1226m": "Run (For Your Life)",
	"score": "Militant Force (Scores)", "smsh226m": "Smash", "snake": "Snake",
	"terminat": "Terminate", "tren226m": "Trenches", "twin": "Twin Cannon", "vector1a": "Vector",
	"work226m": "Workmen",
}
const SETTINGS := "user://settings.cfg"

const SOURCE_ORIGINAL := "original"
const SOURCE_OWN := "own"

signal track_changed(name: String, title: String)

static var enabled_default := true
var enabled := true

var source := SOURCE_ORIGINAL
var _titles := {}
var _playing := ""
var _tracks: Array[String] = []
var _all: Array[String] = []
var _queue: Array[String] = []
var _player: AudioStreamPlayer
var _volumes := {}
var _hidden: Array = []
var _forced := ""
var _original := {}
var _scores := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:


	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		enabled_default = bool(cfg.get_value("audio", "music", enabled_default))
		source = str(cfg.get_value("audio", "music_source", SOURCE_ORIGINAL))
	enabled = enabled_default
	Sfx.apply_volumes()
	_player = AudioStreamPlayer.new()
	_player.bus = "Musik"
	_player.finished.connect(_next)
	add_child(_player)
	rebuild()


func rebuild() -> void:
	var m: Dictionary = RulesDb.data().get("music", {})
	_volumes = m.get("volume", VOLUME_FALLBACK)
	_hidden = m.get("hidden", HIDDEN_FALLBACK)
	_titles = m.get("title", {})
	if _titles.is_empty():
		_titles = TITLE_FALLBACK
	_tracks.clear()
	_all.clear()
	_queue.clear()
	_scores.clear()
	_original.clear()
	if source != SOURCE_OWN:


		var archives := ContentPaths.archives()
		if archives != null:
			for f in archives.list_music():
				_scores[String(f).get_basename().to_lower()] = f


		if _scores.is_empty() and not OS.has_feature("web"):
			_original = OriginalContent.music()
	for name in _scores.keys():
		_add_track(name)
	for name in _original.keys():
		_add_track(name)
	if _scores.is_empty() and _original.is_empty():
		var base := ContentPaths.music_dir()
		var dir := DirAccess.open(base)
		if dir == null:
			print("Musik: kein Verzeichnis ", base)
			return
		for f in dir.get_files():

			if f.ends_with(".mp3") or f.ends_with(".mp3.import") or f.ends_with(".mp3.remap"):
				var eigen := f.get_file().split(".")[0]
				if ALT_OHNE_RECHTE.has(eigen):
					continue
				_add_track(eigen)
	_all.sort()
	_tracks.sort()
	print("Musik: %d Titel (%d versteckt) %s" % [_tracks.size(), _all.size() - _tracks.size(), source_text()])


	if enabled and _playing != "" and not _all.has(_playing):
		if _forced != "":
			_start(_forced)
		else:
			_next()


func _add_track(name: String) -> void:
	if _all.has(name):
		return
	_all.append(name)
	if not _hidden.has(name):
		_tracks.append(name)


func original_available() -> bool:
	var archives := ContentPaths.archives()
	if archives != null and archives.list_music().size() > 0:
		return true

	return not OS.has_feature("web") and not OriginalContent.music().is_empty()


func set_source(new_source: String) -> void:
	if new_source == source:
		return
	source = new_source
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music_source", source)
	cfg.save(SETTINGS)
	rebuild()


func using_original() -> bool:
	return not _scores.is_empty() or not _original.is_empty()


func source_text() -> String:
	if not _scores.is_empty():
		return String(TranslationServer.translate("music.src_scores"))
	if not _original.is_empty():
		return String(TranslationServer.translate("music.src_folder"))
	return String(TranslationServer.translate("music.src_own"))


func title(name: String) -> String:
	if name == "":
		return ""
	if _titles.has(name):
		return str(_titles[name])


	if name.is_valid_int():
		return String(TranslationServer.translate("music.own_track")) % name
	return name.capitalize()


func track_titles() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _tracks:
		out.append(title(n))
	return out


func current_title() -> String:
	return title(_playing) if _player != null and _player.playing else ""


var _scene := "?"


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene


	if cs == null:
		return
	var path: String = cs.scene_file_path
	if path == "" or path == _scene:
		return
	_scene = path
	if path.ends_with("main_menu.tscn") or path.ends_with("intro.tscn"):
		play_track("intro")
	else:
		resume_playlist()


func victory_track() -> String:
	return RulesDb.data().get("music", {}).get("victory", "score")


func defeat_track() -> String:
	return RulesDb.data().get("music", {}).get("defeat", "map")


func _next() -> void:
	if not enabled or _tracks.is_empty():
		return
	if _forced != "":

		_start(_forced)
		return
	if _queue.is_empty():
		_queue = _tracks.duplicate()
		_queue.shuffle()
	_start(_queue.pop_back())


func _start(name: String) -> void:
	var stream: AudioStream = null
	if _scores.has(name):
		var archives := ContentPaths.archives()
		if archives != null:
			stream = archives.aud_stream(_scores[name])
	elif _original.has(name):
		stream = OriginalContent.load_music(_original[name])
	else:
		var path := "%s/%s.mp3" % [ContentPaths.music_dir(), name]
		if ResourceLoader.exists(path):
			stream = load(path)
		elif FileAccess.file_exists(path):


			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			if mp3.data.size() > 0:
				stream = mp3
	if stream == null:

		if _forced == name:
			_forced = ""
		_next()
		return
	_player.stream = stream
	_player.volume_db = linear_to_db(float(_volumes.get(name, 0.7)))
	_player.play()
	_player.stream_paused = _paused
	_playing = name
	print("Musik: ", name, " (", title(name), ")")
	track_changed.emit(name, title(name))


func play_track(name: String, loop: bool = true) -> void:


	var same := _forced == name and _player.playing
	_forced = name if loop else ""
	if name == "":
		_forced = ""
		_next()
		return
	if not enabled:
		return
	if same:
		return
	_start(name)


func stop() -> void:
	_forced = ""
	_playing = ""
	_player.stop()
	track_changed.emit("", "")


func resume_playlist() -> void:
	_forced = ""
	_next()


var _paused := false


func set_paused(paused: bool) -> void:
	_paused = paused
	if _player != null:
		_player.stream_paused = paused


func set_enabled(on: bool) -> void:
	enabled = on
	enabled_default = on
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "music", on)
	cfg.save(SETTINGS)
	if enabled:
		_next()
	else:
		_player.stop()
		_playing = ""
		track_changed.emit("", "")


func toggle() -> void:
	set_enabled(not enabled)
