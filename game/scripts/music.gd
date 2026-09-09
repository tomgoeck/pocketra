

class_name Music
extends Node

const DIR := "res://assets/music"

const VOLUME_FALLBACK := {
	"intro": 0.9, "map": 0.6, "score": 0.7, "credits": 0.9, "fac1226m": 0.85, "fogger1a": 0.8,
}
const HIDDEN_FALLBACK := ["intro", "map", "score"]
const SETTINGS := "user://settings.cfg"

static var enabled_default := true
var enabled := true
var _tracks: Array[String] = []
var _all: Array[String] = []
var _queue: Array[String] = []
var _player: AudioStreamPlayer
var _volumes := {}
var _hidden: Array = []
var _forced := ""
var _original := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:


	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		enabled_default = bool(cfg.get_value("audio", "music", enabled_default))
	enabled = enabled_default
	Sfx.apply_volumes()
	var m: Dictionary = RulesDb.data().get("music", {})
	_volumes = m.get("volume", VOLUME_FALLBACK)
	_hidden = m.get("hidden", HIDDEN_FALLBACK)
	_player = AudioStreamPlayer.new()
	_player.bus = "Musik"
	_player.finished.connect(_next)
	add_child(_player)

	_original = OriginalContent.music()
	if not _original.is_empty():
		for name in _original.keys():
			_all.append(name)
			if not _hidden.has(name):
				_tracks.append(name)
	else:
		var dir := DirAccess.open(DIR)
		if dir == null:
			print("Musik: kein Verzeichnis ", DIR)
			return
		for f in dir.get_files():

			if f.ends_with(".mp3") or f.ends_with(".mp3.import") or f.ends_with(".mp3.remap"):
				var name := f.get_file().split(".")[0]
				if not _all.has(name):
					_all.append(name)
					if not _hidden.has(name):
						_tracks.append(name)
	_all.sort()
	_tracks.sort()
	print("Musik: %d Titel (%d versteckt)%s" % [_tracks.size(), _all.size() - _tracks.size(), " aus Original-Ordner" if not _original.is_empty() else ""])


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
	if _original.has(name):
		stream = OriginalContent.load_music(_original[name])
	else:
		var path := "%s/%s.mp3" % [DIR, name]
		if ResourceLoader.exists(path):
			stream = load(path)
	if stream == null:

		if _forced == name:
			_forced = ""
		_next()
		return
	_player.stream = stream
	_player.volume_db = linear_to_db(float(_volumes.get(name, 0.7)))
	_player.play()
	_player.stream_paused = _paused
	print("Musik: ", name)


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
	_player.stop()


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


func toggle() -> void:
	set_enabled(not enabled)
