

class_name Sfx
extends Node2D

const POOL_SIZE := 32
const MAX_PER_SOUND := 3
const GROUP_CELLS := 2.7
const FADE_CELLS := 15.0
const CELL := 24.0
const MIN_GAIN := 0.04

const BUS_SFX := "Effekte"
const BUS_VOICE := "Stimme"

var view_rect: Callable

var _streams: Array[AudioStream] = []
var _names: Dictionary = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _local_players: Array[AudioStreamPlayer] = []
var _pool_gain: Array[float] = []
var _pool_sound: Array[int] = []
var _pool_pos: Array[Vector2] = []
var _voice_player: AudioStreamPlayer
var _eva_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer
var _tick_player: AudioStreamPlayer
var _bags: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()


		p.max_distance = 1.0e6
		p.attenuation = 0.0
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
		_pool_gain.append(0.0)
		_pool_sound.append(-1)
		_pool_pos.append(Vector2.ZERO)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = BUS_VOICE
	add_child(_voice_player)
	_eva_player = AudioStreamPlayer.new()
	_eva_player.bus = BUS_VOICE
	add_child(_eva_player)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_SFX
	_ui_player.volume_db = -6.0
	add_child(_ui_player)
	_tick_player = AudioStreamPlayer.new()
	_tick_player.bus = BUS_SFX
	_tick_player.volume_db = linear_to_db(0.33)
	add_child(_tick_player)
	for i in 4:
		var lp := AudioStreamPlayer.new()
		lp.bus = BUS_SFX
		add_child(lp)
		_local_players.append(lp)


static var _localized_announced := false


static func path(name: String) -> String:
	var lang := Lang.code()
	var localized := "res://assets/sfx/%s/%s.wav" % [lang, name]
	if ResourceLoader.exists(localized):
		if not _localized_announced:
			_localized_announced = true
			print("Sounds: Sprachfassung %s aus assets/sfx/%s/" % [lang, lang])
		return localized
	return "res://assets/sfx/%s.wav" % name


func register(name: String) -> int:
	if _names.has(name):
		return _names[name]
	var path := Sfx.path(name)
	if not ResourceLoader.exists(path):
		push_warning("Sound fehlt: " + path)
		_names[name] = -1
		return -1
	var stream: AudioStream = load(path)
	_streams.append(stream)
	var id := _streams.size() - 1
	_names[name] = id
	return id


func gain_for(world_pos: Vector2) -> float:
	if not view_rect.is_valid():
		return 1.0
	var r: Rect2 = view_rect.call()
	if r.has_point(world_pos):
		return 1.0
	var nearest := Vector2(clampf(world_pos.x, r.position.x, r.end.x), clampf(world_pos.y, r.position.y, r.end.y))
	var d := world_pos.distance_to(nearest) / (FADE_CELLS * CELL)
	return clampf(1.0 - d, 0.0, 1.0)


func play_at(id: int, world_pos: Vector2, gain_scale: float = 1.0) -> void:
	if id < 0 or id >= _streams.size():
		return
	var gain := gain_for(world_pos) * gain_scale
	if gain < MIN_GAIN:
		return


	var slot := -1
	var same := 0
	var weakest := -1
	var weakest_gain := INF
	var group := GROUP_CELLS * CELL
	for i in POOL_SIZE:
		if not _pool[i].playing:
			if slot < 0:
				slot = i
			continue
		if _pool_sound[i] == id and _pool_pos[i].distance_to(world_pos) <= group:
			same += 1
		if _pool_gain[i] < weakest_gain:
			weakest_gain = _pool_gain[i]
			weakest = i
	if same >= MAX_PER_SOUND:
		return
	if slot < 0:

		if weakest < 0 or gain <= weakest_gain:
			return
		slot = weakest

	var p := _pool[slot]
	p.stream = _streams[id]
	p.global_position = world_pos
	p.volume_db = linear_to_db(gain)
	p.play()
	_pool_gain[slot] = gain
	_pool_sound[slot] = id
	_pool_pos[slot] = world_pos


func play_local(name: String) -> void:
	var id := register(name)
	if id < 0:
		return
	for lp in _local_players:
		if not lp.playing:
			lp.stream = _streams[id]
			lp.play()
			return
	_local_players[0].stream = _streams[id]
	_local_players[0].play()


func play_ui(name: String) -> void:
	var id := register(name)
	if id < 0:
		return
	_ui_player.stream = _streams[id]
	_ui_player.play()


static var _click_player: AudioStreamPlayer


static func click(node: Node, name: String = "ramenu1") -> void:
	if node == null or not node.is_inside_tree():
		return
	var path := Sfx.path(name)
	if not ResourceLoader.exists(path):
		return
	if _click_player == null or not is_instance_valid(_click_player):
		_click_player = AudioStreamPlayer.new()
		_click_player.bus = BUS_SFX
		_click_player.volume_db = -6.0
		node.get_tree().root.add_child(_click_player)
	_click_player.stream = load(path)
	_click_player.play()


func _next_clip(key: String, clips: Array) -> String:
	if clips.is_empty():
		return ""
	if clips.size() == 1:
		return clips[0]
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		bag = clips.duplicate()
		bag.shuffle()
	var pick: String = bag.pop_back()
	_bags[key] = bag
	return pick


func play_voice(clips: Array, variants: Array = [], actor_id: int = 0, key: String = "") -> void:
	if clips.is_empty():
		return
	if _voice_player.playing:
		return
	var clip := _next_clip(key if key != "" else str(clips), clips)
	var name := clip
	if not variants.is_empty():
		var v: String = variants[abs(actor_id) % variants.size()]
		name = "%s_%s" % [clip, v.trim_prefix(".")]
	var id := register(name)
	if id < 0 and name != clip:
		id = register(clip)
	if id < 0:
		return
	_voice_player.stream = _streams[id]
	_voice_player.play()


func play_eva(name: String, force: bool = false) -> void:
	var id := register(name)
	if id < 0 or (_eva_player.playing and not force):
		return
	_eva_player.stream = _streams[id]
	_eva_player.play()


func play_ticker(name: String) -> void:
	var id := register(name)
	if id < 0:
		return
	_tick_player.stream = _streams[id]
	_tick_player.play()


func play_events(events: PackedInt32Array) -> void:
	var n := events.size() / 3
	var order: Array = []
	for i in n:
		var pos := Vector2(events[i * 3 + 1], events[i * 3 + 2])
		order.append([gain_for(pos), events[i * 3], pos])
	order.sort_custom(func(a, b): return a[0] > b[0])
	for e in order:
		play_at(e[1], e[2])


const SETTINGS := "user://settings.cfg"


const BUSES := {"master": "Master", "music": "Musik", "sfx": "Effekte", "voice": "Stimme", "video": "Video"}
const DEFAULT_VOLUMES := {"master": 1.0, "music": 0.5, "sfx": 0.5, "voice": 0.5, "video": 0.5}


static func volume(key: String) -> float:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return clampf(float(cfg.get_value("audio", key + "_volume", DEFAULT_VOLUMES.get(key, 1.0))), 0.0, 1.0)


static func set_volume(key: String, value: float) -> void:
	if not BUSES.has(key):
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", key + "_volume", clampf(value, 0.0, 1.0))
	cfg.save(SETTINGS)
	apply_volume(key)


static func apply_volume(key: String) -> void:
	var idx := AudioServer.get_bus_index(BUSES.get(key, ""))
	if idx < 0:
		return
	var v := volume(key)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


static func apply_volumes() -> void:
	for key in BUSES:
		apply_volume(key)
