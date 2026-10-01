

class_name AudioMix
extends Node


const AndroidPluginRef := preload("res://scripts/android_plugin.gd")

const SETTINGS := "user://settings.cfg"


const BUSES := {"master": "Master", "music": "Musik", "sfx": "Effekte", "voice": "Stimme",
	"video": "Video", "radio": "Funk"}
const DEFAULT_VOLUMES := {"master": 1.0, "music": 0.5, "sfx": 0.5, "voice": 0.5, "video": 0.5,
	"radio": 1.0}


const DUCK_KEYS := ["music", "sfx", "voice", "video"]
const RADIO_KEY := "radio"

const DUCK_HEADSET_DB := -12.0
const DUCK_SILENT_DB := -60.0
const RAMP := 0.2
const RAMP_SPAN := 60.0

enum Headset { AUTO, ON, OFF }


const CRACKLE_GAP := 3.0

static var _inst: AudioMix = null
static var _voice_on := false
static var _off := {}
static var _tgt := {}
static var _headset_cache := -1
static var _test_headset := -1
static var _crackle: AudioStreamWAV = null
static var _dropout: AudioStreamWAV = null
static var _last_crackle := -1000.0
static var _radio_player: AudioStreamPlayer = null


static var crackles_played := 0


static func mix() -> AudioMix:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	var root := (ml as SceneTree).root
	var n := root.get_node_or_null("AudioMix")
	if n is AudioMix:
		_inst = n
		return _inst
	_inst = AudioMix.new()
	_inst.name = "AudioMix"


	root.add_child.call_deferred(_inst)
	return _inst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_step(delta)


static var _vol := {}


static func volume(key: String) -> float:
	if _vol.has(key):
		return float(_vol[key])
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var v := clampf(float(cfg.get_value("audio", key + "_volume", DEFAULT_VOLUMES.get(key, 1.0))), 0.0, 1.0)
	_vol[key] = v
	return v


static func set_volume(key: String, value: float) -> void:
	if not BUSES.has(key):
		return
	var v := clampf(value, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", key + "_volume", v)
	cfg.save(SETTINGS)
	_vol[key] = v
	apply(key)


static func duck_db(key: String) -> float:
	return float(_off.get(key, 0.0))


static func apply(key: String) -> void:
	var idx := AudioServer.get_bus_index(BUSES.get(key, ""))
	if idx < 0:
		return
	var v := volume(key)


	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) + duck_db(key))


static func apply_all() -> void:
	for key in BUSES:
		apply(key)


static func set_voice_active(on: bool) -> void:
	if on == _voice_on:
		return
	_voice_on = on
	if on:


		refresh_headset()
	_retarget()


static func voice_active() -> bool:
	return _voice_on


static func _retarget() -> void:
	var duck := 0.0
	if _voice_on:
		duck = DUCK_HEADSET_DB if headset() else DUCK_SILENT_DB
	for key in DUCK_KEYS:
		_tgt[key] = duck

	var radio_base := linear_to_db(maxf(volume(RADIO_KEY), 0.0001))
	_tgt[RADIO_KEY] = maxf(0.0, -radio_base) if _voice_on else 0.0


	var m := mix()
	if m == null or not m.is_inside_tree():
		settle()


static func _step(delta: float) -> void:
	if delta <= 0.0:
		return
	var rate := RAMP_SPAN * delta / RAMP
	for key in _tgt:
		var ziel: float = float(_tgt[key])
		var ist: float = float(_off.get(key, 0.0))
		if is_equal_approx(ist, ziel):
			continue
		_off[key] = move_toward(ist, ziel, rate)
		apply(key)


static func ramping() -> bool:
	for key in _tgt:
		if not is_equal_approx(float(_off.get(key, 0.0)), float(_tgt[key])):
			return true
	return false


static func settle() -> void:
	for key in _tgt:
		_off[key] = float(_tgt[key])
		apply(key)


static var _mode_cache := -1


static func headset_mode() -> int:
	if _mode_cache < 0:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		_mode_cache = clampi(int(cfg.get_value("audio", "headset_mode", Headset.AUTO)), 0, 2)
	return _mode_cache


static func set_headset_mode(m: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("audio", "headset_mode", clampi(m, 0, 2))
	cfg.save(SETTINGS)
	_mode_cache = clampi(m, 0, 2)
	_headset_cache = -1
	_retarget()


static func headset() -> bool:
	if _test_headset >= 0:
		return _test_headset == 1
	match headset_mode():
		Headset.ON:
			return true
		Headset.OFF:
			return false
	if _headset_cache < 0:
		_headset_cache = 1 if detect_headset() else 0
	return _headset_cache == 1


static func refresh_headset() -> void:
	_headset_cache = -1


static func set_test_headset(v: int) -> void:
	_test_headset = v
	_retarget()


const HEADSET_WORDS := ["headset", "headphone", "kopfhörer", "kopfhoerer", "earphone", "earbud",
	"airpods", "bluetooth", "buds", "hörer", "hoerer"]


static func detect_headset() -> bool:

	var p := AndroidPluginRef.plugin_with(&"isHeadsetConnected")
	if p != null:
		return bool(p.isHeadsetConnected())

	var name := str(AudioServer.output_device).to_lower()
	for w in HEADSET_WORDS:
		if name.find(w) >= 0:
			return true
	return false


static func tesla_static() -> bool:
	if not _voice_on:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_crackle < CRACKLE_GAP:
		return false
	_last_crackle = now
	crackles_played += 1
	return _play_radio(_make_crackle(), -14.0)


static func radio_dropout() -> bool:
	return _play_radio(_make_dropout(), -10.0)


static func _play_radio(stream: AudioStream, db: float) -> bool:
	if stream == null:
		return false
	var m := mix()
	if m == null or not m.is_inside_tree():
		return false
	if _radio_player == null or not is_instance_valid(_radio_player):
		_radio_player = AudioStreamPlayer.new()
		_radio_player.name = "FunkGeraeusch"
		_radio_player.bus = "Funk" if AudioServer.get_bus_index("Funk") >= 0 else "Master"
		m.add_child(_radio_player)
	_radio_player.stream = stream
	_radio_player.volume_db = db
	_radio_player.play()
	return true


const SND_RATE := 22050


static func _make_crackle() -> AudioStreamWAV:
	if _crackle != null:
		return _crackle
	var n := int(SND_RATE * 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	var buf := PackedFloat32Array()
	buf.resize(n)


	var f := 2.0 * sin(PI * 1800.0 / SND_RATE)
	var q := 0.55
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / float(n)

		var env: float = exp(-7.0 * t) * minf(1.0, t * 60.0)
		if t > 0.30 and t < 0.36:
			env *= 2.2
		if t > 0.58 and t < 0.62:
			env *= 1.8
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - q * band
		band += f * high
		buf[i] = clampf(band * env * 0.9, -1.0, 1.0)
	_crackle = _to_wav(buf)
	return _crackle


static func _make_dropout() -> AudioStreamWAV:
	if _dropout != null:
		return _dropout
	var n := int(SND_RATE * 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var buf := PackedFloat32Array()
	buf.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / float(n)

		var f := 2.0 * sin(PI * lerpf(2200.0, 300.0, t) / SND_RATE)
		var env: float = minf(1.0, t * 40.0) * pow(1.0 - t, 1.6)
		var x := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := x - low - 0.8 * band
		band += f * high
		buf[i] = clampf(band * env * 0.8, -1.0, 1.0)
	_dropout = _to_wav(buf)
	return _dropout


static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(buf.size() * 2)
	for i in buf.size():
		var s := int(round(clampf(buf[i], -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SND_RATE
	w.stereo = false
	w.data = pcm
	return w


static func state_line() -> String:
	var teile := PackedStringArray(["Sprechfunk %s" % ("AN" if _voice_on else "aus"),
		"Headset %s (%s)" % ["ja" if headset() else "nein", _headset_source()]])
	for key in BUSES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx < 0:
			continue
		teile.append("%s %+.1f dB%s" % [BUSES[key], AudioServer.get_bus_volume_db(idx),
			" STUMM" if AudioServer.is_bus_mute(idx) else ""])
	return " · ".join(teile)


static func _headset_source() -> String:
	if _test_headset >= 0:
		return "Prüfhaken"
	match headset_mode():
		Headset.ON:
			return "Einstellung: ja"
		Headset.OFF:
			return "Einstellung: nein"
	return "erkannt"
