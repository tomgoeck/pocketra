

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

const EVA_SLOTS := 2
const EVA_WAIT_MAX := 3.0


const EVA_PRIORITY := {
	"baseatk1": 3, "alaunch1": 3,
	"lopower1": 2, "nofunds1": 2, "silond1": 2, "nopowr1": 2,
	"nodeply1": 2, "nobuild1": 2,
	"conscmp1": 1, "unitrdy1": 1, "newopt1": 1, "abldgin1": 1, "train1": 1,
	"unitlst1": 1, "strucap1": 1, "unitsto": 1,
}

var view_rect: Callable

var tesla_sounds: Dictionary = {}

var _streams: Array[AudioStream] = []
var _names: Dictionary = {}
var _pool: Array[AudioStreamPlayer2D] = []
var _local_players: Array[AudioStreamPlayer] = []
var _pool_gain: Array[float] = []
var _pool_sound: Array[int] = []
var _pool_pos: Array[Vector2] = []
var _voice_player: AudioStreamPlayer
var _eva_players: Array[AudioStreamPlayer] = []
var _eva_names: PackedStringArray = []
var _eva_wait := ""
var _eva_wait_prio := 0
var _eva_wait_since := 0.0

var eva_started: Callable
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
	for i in EVA_SLOTS:
		var ev := AudioStreamPlayer.new()
		ev.bus = BUS_VOICE
		add_child(ev)
		_eva_players.append(ev)
		_eva_names.append("")
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


func register(name: String) -> int:
	if _names.has(name):
		return _names[name]
	var path := ContentPaths.sfx(name)
	var stream: AudioStream = _load_wav(path)
	if stream == null:
		push_warning("Sound fehlt: " + path)
		_names[name] = -1
		return -1
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
	var stream := _load_wav(ContentPaths.sfx(name))
	if stream == null:
		return
	if _click_player == null or not is_instance_valid(_click_player):
		_click_player = AudioStreamPlayer.new()
		_click_player.bus = BUS_SFX
		_click_player.volume_db = -6.0
		node.get_tree().root.add_child(_click_player)
	_click_player.stream = stream
	_click_player.play()


static var _wav_cache := {}


static func _load_wav(path: String) -> AudioStream:
	if _wav_cache.has(path):
		return _wav_cache[path]
	var stream: AudioStream = null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			stream = load(path)
	elif FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(path)
	_wav_cache[path] = stream
	return stream


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


const HARVESTER_VOICE_DIRS := ["res://data/sfx/voice/harvester", "res://assets/sfx/voice/harvester"]


func play_harvester_voice(key: String) -> bool:
	var lang := Lang.code()
	for dir in HARVESTER_VOICE_DIRS:
		for l in [lang, "en"]:
			var path := "%s/%s/%s.wav" % [dir, l, key]
			var stream := _load_wav(path)
			if stream != null:
				_voice_player.stop()
				_voice_player.stream = stream
				_voice_player.play()
				return true
	return false


func play_eva(name: String, force: bool = false) -> String:
	var id := register(name)
	if id < 0:
		return "fehlt"
	if not force and _eva_running(name):
		return "doppelt"
	var slot := _free_eva_slot()
	if slot < 0 and force:
		slot = _oldest_eva_slot()
	if slot >= 0:
		_start_eva(slot, id, name)
		return "ab"


	var prio := int(EVA_PRIORITY.get(name, 0))
	if _eva_wait == "" or prio >= _eva_wait_prio:
		var pushed := _eva_wait
		_eva_wait = name
		_eva_wait_prio = prio
		_eva_wait_since = Time.get_ticks_msec() / 1000.0
		return "wartet" if pushed == "" else "verdrängt"
	return "verworfen"


func _eva_running(name: String) -> bool:
	for i in _eva_players.size():
		if _eva_players[i].playing and _eva_names[i] == name:
			return true
	return false


func _free_eva_slot() -> int:
	for i in _eva_players.size():
		if not _eva_players[i].playing:
			return i
	return -1


func _oldest_eva_slot() -> int:
	var best := 0
	var best_pos := -1.0
	for i in _eva_players.size():
		var pos := _eva_players[i].get_playback_position()
		if pos > best_pos:
			best_pos = pos
			best = i
	return best


func _start_eva(slot: int, id: int, name: String) -> void:
	_eva_players[slot].stream = _streams[id]
	_eva_players[slot].play()
	_eva_names[slot] = name


func _process(_delta: float) -> void:
	if _eva_wait == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _eva_wait_since > EVA_WAIT_MAX:
		_eva_wait = ""
		return
	var slot := _free_eva_slot()
	if slot < 0:
		return
	var name := _eva_wait
	_eva_wait = ""
	if not _eva_running(name):
		_start_eva(slot, register(name), name)
		if eva_started.is_valid():
			eva_started.call(name)


func eva_remaining() -> float:
	var rest := 0.0
	for p in _eva_players:
		if p.playing and p.stream != null:
			rest = maxf(rest, p.stream.get_length() - p.get_playback_position())
	return rest


func eva_busy() -> int:
	var n := 0
	for p in _eva_players:
		if p.playing:
			n += 1
	return n


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
		var id: int = events[i * 3]
		order.append([gain_for(pos), id, pos])


		if not tesla_sounds.is_empty() and tesla_sounds.has(id) and _in_view(pos):
			AudioMix.tesla_static()
	order.sort_custom(func(a, b): return a[0] > b[0])
	for e in order:
		play_at(e[1], e[2])


func _in_view(world_pos: Vector2) -> bool:
	if not view_rect.is_valid():
		return false
	var r: Rect2 = view_rect.call()
	return r.has_point(world_pos)


const SETTINGS := AudioMix.SETTINGS


static func volume(key: String) -> float:
	return AudioMix.volume(key)


static func set_volume(key: String, value: float) -> void:
	AudioMix.set_volume(key, value)


static func apply_volume(key: String) -> void:
	AudioMix.apply(key)


static func apply_volumes() -> void:
	AudioMix.apply_all()
