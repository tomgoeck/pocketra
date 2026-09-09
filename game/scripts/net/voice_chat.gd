

extends Node

signal speaking_changed(seat: int, on: bool)
signal mode_changed(mode: int)
signal permission_denied()
signal mic_trouble(reason: String)

enum Mode { OFF, TEAM, ALL }


const RATE := 8000
const PACKET_MS := 60
const SAMPLES := RATE * PACKET_MS / 1000
const CODEC := "adpcm8"

const BUS_PLAY := "Funk"
const BUS_REC := "FunkAufnahme"


const NOISE_MIN := 0.0006
const NOISE_MAX := 0.05
const NOISE_DOWN := 0.35
const NOISE_UP := 0.03
const OPEN_FACTOR := 2.5
const OPEN_MIN := 0.0030
const OPEN_MAX := 0.0150
const CLOSE_RATIO := 0.6
const GATE_HANG := 0.45


const REOPEN_AFTER := 2.5
const REOPEN_MAX := 3


const TROUBLE_AFTER := 4.0


const JITTER_START := 0.12
const JITTER_MAX := 1.2
const SPEAK_HOLD := 0.6

const SETTINGS := "user://settings.cfg"
const PERMISSION := "android.permission.RECORD_AUDIO"


enum Source { ENGINE, PLUGIN }


const AndroidPlugin := preload("res://scripts/android_plugin.gd")
const PLUGIN_SINGLETON := AndroidPlugin.SINGLETON


const STEP_TABLE := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253,
	279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166,
	1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
	4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289,
	16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

var mode: int = Mode.OFF
var client = null


var test_tone := false

var probe := false
var muted_seats := {}


var stat_frames := 0
var stat_pulls := 0
var stat_blocks := 0
var stat_packets := 0
var stat_sent := 0
var stat_raw_peak := 0.0


var stat_nonzero := 0
var stat_block_peak := 0.0

var _mic: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _rec_bus := -1
var _source: int = Source.ENGINE
var _plugin_rate := 0.0


var stat_plugin_start := -1
var _pcm := PackedFloat32Array()
var _res_sum := 0.0
var _res_n := 0
var _res_carry := 0.0
var _enc_pred := 0
var _enc_index := 0
var _seq := 0
var _gate_open := false
var _gate_hang := 0.0
var _noise := 0.01
var _last_rms := 0.0
var _raw_rms := 0.0
var _mic_since := 0.0
var _warned := ""
var _last_nonzero := 0.0
var _last_reopen := 0.0
var stat_reopens := 0
var _tone_phase := 0.0
var _last_level := 0.0


var _voices := {}
var _speaking := {}


static func enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value("multiplayer", "voice", true))


static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("multiplayer", "voice", on)
	cfg.save(SETTINGS)


static func intro_seen() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value("multiplayer", "voice_intro", false))


static func set_intro_seen(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("multiplayer", "voice_intro", on)
	cfg.save(SETTINGS)


static func bytes_per_second() -> int:
	var payload := 4 + SAMPLES / 2
	var b64 := int(ceil(payload / 3.0)) * 4
	return int(round((b64 + 50) * 1000.0 / PACKET_MS))


static func has_permission() -> bool:
	if AndroidPlugin.platform() != "Android":
		return true


	var p := AndroidPlugin.plugin_with(&"micHasPermission")
	if p != null:
		return bool(p.micHasPermission())
	return OS.get_granted_permissions().has(PERMISSION)


func request_permission() -> bool:
	if has_permission():
		return true


	if AndroidPlugin.platform() != "Android":
		return false
	var tree := get_tree()
	if tree != null and tree.has_signal("on_request_permissions_result") \
			and not tree.is_connected("on_request_permissions_result", _on_permission_result):
		tree.connect("on_request_permissions_result", _on_permission_result)
	OS.request_permission(PERMISSION)
	return false


func ensure_permission() -> bool:
	if has_permission():
		return true
	return request_permission()


static func permission_state() -> String:
	if AndroidPlugin.platform() != "Android":
		return "unbekannt"
	return "ja" if has_permission() else "nein"


static func trouble_text_key(reason: String, praefix: String = "mp.mic_") -> String:
	if reason == "no_signal" and AndroidPlugin.platform() == "iOS":
		return praefix + "no_signal_ios"
	return praefix + reason


func _on_permission_result(permission: String, granted: bool) -> void:
	if not permission.ends_with("RECORD_AUDIO"):
		return
	if granted:


		if _mic != null and _mic.playing:
			reopen_input()
		elif mode != Mode.OFF or probe:
			_start_capture()
	else:
		mode = Mode.OFF
		mode_changed.emit(mode)
		permission_denied.emit()


func toggle_team() -> int:
	return set_mode(Mode.OFF if mode == Mode.TEAM else Mode.TEAM)


func toggle_all() -> int:
	return set_mode(Mode.OFF if mode == Mode.ALL else Mode.ALL)


func set_mode(new_mode: int) -> int:
	if new_mode != Mode.OFF and not enabled():
		return mode
	if new_mode == mode:
		return mode
	if new_mode != Mode.OFF and not test_tone and not request_permission():

		mode = new_mode
		mode_changed.emit(mode)
		return mode
	mode = new_mode
	if mode == Mode.OFF:
		_stop_capture()
	else:
		_start_capture()
	mode_changed.emit(mode)
	return mode


func scope() -> String:
	return "team" if mode == Mode.TEAM else "all"


func level() -> float:
	return _last_level


func rms() -> float:
	return _last_rms


func raw_rms() -> float:
	return _raw_rms


func noise_floor() -> float:
	return _noise


func open_threshold() -> float:
	return clampf(_noise * OPEN_FACTOR, OPEN_MIN, OPEN_MAX)


func close_threshold() -> float:
	return open_threshold() * CLOSE_RATIO


func gate_open() -> bool:
	return _gate_open


func recording() -> bool:
	if _source == Source.PLUGIN:
		return _plugin_rate > 0.0
	return _mic != null and _mic.playing


func input_device() -> String:
	return str(AudioServer.input_device)


func diagnose() -> String:
	var laufzeit := maxf(Time.get_ticks_msec() / 1000.0 - _mic_since, 0.001)
	var liste := AudioServer.get_input_device_list()
	var namen := ", ".join(PackedStringArray(liste.slice(0, mini(liste.size(), 3))))
	if liste.size() > 3:
		namen += " …"


	var ein_rate := 0
	if AudioServer.has_method(&"get_input_mix_rate"):
		ein_rate = int(AudioServer.get_input_mix_rate())
	return "%s · Plattform %s · Quelle: %s %d Hz (Eingang %s) · %s · %.0f F/s · ≠0 %d%% · roh %.4f · Neu %d\n%s\nGeräte (%d): %s" % [
		"Freigabe " + permission_state(), AndroidPlugin.platform(),
		source_name(), int(source_rate()), (str(ein_rate) + " Hz") if ein_rate > 0 else "?",
		input_device(), stat_frames / laufzeit,
		int(round(100.0 * stat_nonzero / maxf(float(stat_frames), 1.0))),
		stat_raw_peak, stat_reopens, plugin_report(), liste.size(), namen]


func reset_stats() -> void:
	stat_frames = 0
	stat_pulls = 0
	stat_blocks = 0
	stat_packets = 0
	stat_sent = 0
	stat_raw_peak = 0.0
	stat_block_peak = 0.0
	stat_nonzero = 0
	stat_reopens = 0
	_last_nonzero = Time.get_ticks_msec() / 1000.0
	_last_reopen = _last_nonzero
	_warned = ""
	_mic_since = Time.get_ticks_msec() / 1000.0


func reset_gate() -> void:
	_noise = 0.01
	_gate_open = false
	_gate_hang = 0.0


func start_probe() -> void:
	if probe:
		return
	probe = true
	if mode == Mode.OFF:
		_start_capture()
	reset_stats()


func stop_probe() -> void:
	if not probe:
		return
	probe = false
	if mode == Mode.OFF:
		_stop_capture()


func capture_effect() -> AudioEffectCapture:
	return _capture


func feed_level(level_rms: float, blocks: int) -> int:
	var vorher := stat_packets
	var block := PackedFloat32Array()
	block.resize(SAMPLES)
	var phase := 0.0
	var amp := level_rms * sqrt(2.0)
	for _b in blocks:
		for i in SAMPLES:
			phase += TAU * 300.0 / RATE
			block[i] = sin(phase) * amp
		_send_block(block)
	return stat_packets - vorher


func speaking_seats() -> Array:
	return _speaking.keys()


func speaker_info(seat: int) -> Dictionary:
	var v = _voices.get(seat)
	return v if v is Dictionary else {}


func set_muted(seat: int, on: bool) -> void:
	if on:
		muted_seats[seat] = true
		_drop_voice(seat)
	else:
		muted_seats.erase(seat)


func is_muted(seat: int) -> bool:
	return muted_seats.has(seat)


func _ensure_record_bus() -> int:
	var idx := AudioServer.get_bus_index(BUS_REC)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_REC)
	AudioServer.set_bus_send(idx, "Master")


	AudioServer.set_bus_mute(idx, true)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.25
	AudioServer.add_bus_effect(idx, cap)
	return idx


static func mic_plugin() -> Object:
	return AndroidPlugin.plugin_with(&"micStart")


static func plugin_singleton() -> Object:
	return AndroidPlugin.plugin()


func plugin_report() -> String:
	var basis := AndroidPlugin.report(PackedStringArray([
			"micStart", "micRead", "micInfo", "showNotification", "restartApp"]))
	if not AndroidPlugin.available():
		return basis
	var teile := PackedStringArray()
	if not AndroidPlugin.can(&"micStart"):
		teile.append("micStart nicht nutzbar")
	elif _source == Source.PLUGIN:
		teile.append("micStart=%d" % stat_plugin_start)
	elif stat_plugin_start == 0:
		teile.append("micStart=0")
	else:
		teile.append("micStart nicht versucht")


	var p := AndroidPlugin.plugin_with(&"micInfo")
	if p != null:
		teile.append(str(p.micInfo()))
	return basis + " · " + " · ".join(teile)


func source() -> int:
	return _source


func source_rate() -> float:
	return _plugin_rate if _source == Source.PLUGIN else AudioServer.get_mix_rate()


func source_name() -> String:
	return "Plugin" if _source == Source.PLUGIN else "Engine"


func _start_capture() -> void:
	_pcm = PackedFloat32Array()
	_res_sum = 0.0
	_res_n = 0
	_res_carry = 0.0
	_enc_pred = 0
	_enc_index = 0
	_gate_open = false
	_gate_hang = 0.0
	_noise = 0.01
	_tone_phase = 0.0
	reset_stats()
	if test_tone:
		return


	_source = Source.ENGINE
	_plugin_rate = 0.0
	stat_plugin_start = -1
	var plug := mic_plugin()
	if plug != null:
		var rate_hz := int(plug.micStart())
		stat_plugin_start = rate_hz
		if rate_hz > 0:
			_source = Source.PLUGIN
			_plugin_rate = float(rate_hz)
			return
	_rec_bus = _ensure_record_bus()
	_capture = AudioServer.get_bus_effect(_rec_bus, 0) as AudioEffectCapture
	if _capture != null:
		_capture.clear_buffer()
	if _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.name = "MikrofonEingang"
		_mic.stream = AudioStreamMicrophone.new()
		_mic.bus = BUS_REC
		add_child(_mic)
	_mic.play()


func _stop_capture() -> void:
	if _source == Source.PLUGIN:
		var plug := mic_plugin()
		if plug != null:
			plug.micStop()
		_source = Source.ENGINE
		_plugin_rate = 0.0
	if _mic != null and _mic.playing:
		_mic.stop()
	_gate_open = false
	_last_level = 0.0


func _process(delta: float) -> void:
	if mode != Mode.OFF or probe:
		_collect(delta)
		_watch_input()
		_check_trouble()
	_play_queues()
	_expire_speakers(delta)


func reopen_input() -> bool:
	if test_tone:
		return false
	if _source == Source.PLUGIN:
		var plug := mic_plugin()
		if plug == null:
			return false
		stat_reopens += 1
		_last_reopen = Time.get_ticks_msec() / 1000.0
		_last_nonzero = _last_reopen
		plug.micStop()
		var r := int(plug.micStart())
		_plugin_rate = float(r)
		if r <= 0:
			_source = Source.ENGINE
			_start_capture()
		_pcm = PackedFloat32Array()
		_res_sum = 0.0
		_res_n = 0
		_res_carry = 0.0
		return true
	if _mic == null:
		return false
	stat_reopens += 1
	_last_reopen = Time.get_ticks_msec() / 1000.0
	_last_nonzero = _last_reopen
	_mic.stop()
	_mic.play()
	if _capture != null:
		_capture.clear_buffer()
	_pcm = PackedFloat32Array()
	_res_sum = 0.0
	_res_n = 0
	_res_carry = 0.0
	return true


func _watch_input() -> void:
	if test_tone or stat_frames == 0:
		return
	if _source == Source.ENGINE and _capture == null:
		return
	var jetzt := Time.get_ticks_msec() / 1000.0
	if stat_nonzero > 0:
		_last_nonzero = jetzt
		return
	if jetzt - _last_nonzero < REOPEN_AFTER or jetzt - _last_reopen < REOPEN_AFTER:
		return
	if stat_reopens >= REOPEN_MAX:
		return
	reopen_input()


func _check_trouble() -> void:
	if probe or test_tone or _warned != "" or stat_packets > 0:
		return
	if Time.get_ticks_msec() / 1000.0 - _mic_since < TROUBLE_AFTER:
		return

	if stat_frames > 0 and stat_nonzero == 0 and stat_reopens < REOPEN_MAX:
		return
	_warned = trouble_reason(stat_frames, stat_nonzero, has_permission())
	mic_trouble.emit(_warned)


static func trouble_reason(frames: int, nonzero: int, erlaubt: bool = true) -> String:
	if frames == 0:
		return "no_input"
	if nonzero == 0:
		return "no_permission" if not erlaubt else "no_signal"
	return "too_quiet"


func _collect(delta: float) -> void:
	if test_tone:

		var n := int(round(delta * RATE))
		for i in n:
			_tone_phase += TAU * 440.0 / RATE
			_pcm.append(sin(_tone_phase) * 0.5)
	elif _source == Source.PLUGIN:
		var plug := mic_plugin()
		if plug == null:
			return


		var pcm: PackedFloat32Array = plug.micRead(int(_plugin_rate * 0.5))
		if pcm.is_empty():
			return
		stat_pulls += 1
		_feed_mono(pcm, _plugin_rate)
	else:
		if _capture == null:
			return
		var avail := _capture.get_frames_available()
		if avail <= 0:
			return
		var buf := _capture.get_buffer(avail)
		stat_pulls += 1

		var mono := PackedFloat32Array()
		mono.resize(buf.size())
		for i in buf.size():
			mono[i] = (buf[i].x + buf[i].y) * 0.5
		_feed_mono(mono, AudioServer.get_mix_rate())
	while _pcm.size() >= SAMPLES:
		var block := _pcm.slice(0, SAMPLES)
		_pcm = _pcm.slice(SAMPLES)
		_send_block(block)


func _feed_mono(samples: PackedFloat32Array, src_rate: float) -> void:
	if samples.is_empty():
		return
	stat_frames += samples.size()
	var ratio: float = maxf(src_rate, 1.0) / float(RATE)
	var roh := 0.0
	for mono in samples:
		if mono != 0.0:
			stat_nonzero += 1
		roh += mono * mono
		_res_sum += mono
		_res_n += 1
		_res_carry += 1.0
		if _res_carry >= ratio:
			_res_carry -= ratio
			_pcm.append(_res_sum / maxf(float(_res_n), 1.0))
			_res_sum = 0.0
			_res_n = 0
	_raw_rms = sqrt(roh / float(samples.size()))
	stat_raw_peak = maxf(stat_raw_peak, _raw_rms)


func _send_block(block: PackedFloat32Array) -> void:
	var sum := 0.0
	for s in block:
		sum += s * s
	var rms_wert := sqrt(sum / float(block.size()))
	_last_rms = rms_wert

	_last_level = clampf(rms_wert / 0.08, 0.0, 1.0)
	stat_blocks += 1
	stat_block_peak = maxf(stat_block_peak, rms_wert)


	if rms_wert < _noise:
		_noise = lerpf(_noise, rms_wert, NOISE_DOWN)
	elif not _gate_open:
		_noise = lerpf(_noise, rms_wert, NOISE_UP)
	_noise = clampf(_noise, NOISE_MIN, NOISE_MAX)
	var auf := open_threshold()
	if rms_wert >= auf:
		_gate_open = true
		_gate_hang = GATE_HANG
	elif _gate_open:
		if rms_wert < auf * CLOSE_RATIO:
			_gate_hang -= PACKET_MS / 1000.0
			if _gate_hang <= 0.0:
				_gate_open = false
				stat_packets += 1
				_send_packet(_encode(block), true)
				return
		else:
			_gate_hang = GATE_HANG
	if not _gate_open:
		return
	stat_packets += 1
	_send_packet(_encode(block), false)


func _send_packet(data: PackedByteArray, ende: bool) -> void:
	if probe or client == null:
		return
	_seq += 1
	if client.send_voice(Marshalls.raw_to_base64(data), scope(), _seq, ende):
		stat_sent += 1


func _encode(block: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4 + (block.size() + 1) / 2)
	var pred := _enc_pred
	var index := _enc_index
	out[0] = pred & 0xFF
	out[1] = (pred >> 8) & 0xFF
	out[2] = index & 0xFF
	out[3] = 0
	var byte := 4
	var high := false
	var packed := 0
	for i in block.size():
		var s := int(clampf(block[i], -1.0, 1.0) * 32767.0)
		var diff := s - pred
		var sign := 0
		if diff < 0:
			sign = 8
			diff = -diff
		var step: int = STEP_TABLE[index]
		var delta := 0
		var vpdiff := step >> 3
		if diff >= step:
			delta = 4
			diff -= step
			vpdiff += step
		if diff >= (step >> 1):
			delta |= 2
			diff -= step >> 1
			vpdiff += step >> 1
		if diff >= (step >> 2):
			delta |= 1
			vpdiff += step >> 2
		pred = clampi(pred - vpdiff if sign != 0 else pred + vpdiff, -32768, 32767)
		index = clampi(index + INDEX_TABLE[delta | sign], 0, STEP_TABLE.size() - 1)
		var nibble := delta | sign
		if high:
			out[byte] = packed | (nibble << 4)
			byte += 1
			high = false
		else:
			packed = nibble
			high = true
	if high:
		out[byte] = packed
	_enc_pred = pred
	_enc_index = index
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if data.size() < 5:
		return out
	var pred := data[0] | (data[1] << 8)
	if pred >= 32768:
		pred -= 65536
	var index := clampi(data[2], 0, STEP_TABLE.size() - 1)
	out.resize((data.size() - 4) * 2)
	var k := 0
	for i in range(4, data.size()):
		var b := data[i]
		for half in 2:
			var nibble := (b & 0x0F) if half == 0 else (b >> 4)
			var step: int = STEP_TABLE[index]
			var vpdiff := step >> 3
			if nibble & 4:
				vpdiff += step
			if nibble & 2:
				vpdiff += step >> 1
			if nibble & 1:
				vpdiff += step >> 2
			pred = clampi(pred - vpdiff if (nibble & 8) else pred + vpdiff, -32768, 32767)
			index = clampi(index + INDEX_TABLE[nibble], 0, STEP_TABLE.size() - 1)
			out[k] = pred / 32768.0
			k += 1
	return out


static func self_test(samples: int = 4800) -> Dictionary:
	var src := PackedFloat32Array()
	src.resize(samples)
	var phase := 0.0
	for i in samples:
		phase += TAU * 440.0 / RATE
		src[i] = sin(phase) * 0.5
	var node = (load("res://scripts/net/voice_chat.gd") as GDScript).new()
	var raw := PackedByteArray()
	var back := PackedFloat32Array()
	var blocks := 0
	var pos := 0
	while pos + SAMPLES <= samples:
		var block := src.slice(pos, pos + SAMPLES)
		var enc: PackedByteArray = node._encode(block)
		if raw.is_empty():
			raw = enc
		back.append_array(decode(enc))
		blocks += 1
		pos += SAMPLES
	node.free()
	var sig := 0.0
	var err := 0.0
	for i in back.size():
		sig += src[i] * src[i]
		var d: float = src[i] - back[i]
		err += d * d
	var snr := 10.0 * log(maxf(sig, 1e-9) / maxf(err, 1e-12)) / log(10.0)
	return {"blocks": blocks, "bytes": raw.size(),
			"base64": Marshalls.raw_to_base64(raw).length(), "snr_db": snr,
			"bytes_per_second": bytes_per_second()}


static func test_packet(freq: float = 300.0) -> String:
	var block := PackedFloat32Array()
	block.resize(SAMPLES)
	var phase := 0.0
	for i in SAMPLES:
		phase += TAU * freq / RATE
		block[i] = sin(phase) * 0.4
	var node = (load("res://scripts/net/voice_chat.gd") as GDScript).new()
	var enc: PackedByteArray = node._encode(block)
	node.free()
	return Marshalls.raw_to_base64(enc)


func on_packet(line: Dictionary) -> void:
	if not enabled():
		return
	var seat := int(line.get("seat", -1))
	if seat < 0 or muted_seats.has(seat):
		return
	var v = _voices.get(seat)
	if v == null:
		v = _new_voice(seat)
	v["name"] = str(line.get("name", v.get("name", "?")))
	v["color"] = int(line.get("color", v.get("color", 0)))
	v["scope"] = str(line.get("scope", "all"))
	var raw := Marshalls.base64_to_raw(str(line.get("data", "")))
	if raw.size() >= 5:
		var pcm := decode(raw)
		var q: PackedVector2Array = v["queue"]
		for s in pcm:
			q.append(Vector2(s, s))

		var maxlen := int(JITTER_MAX * RATE)
		if q.size() > maxlen:
			q = q.slice(q.size() - maxlen)
		v["queue"] = q
	v["last"] = SPEAK_HOLD
	if not _speaking.has(seat):
		_speaking[seat] = SPEAK_HOLD
		speaking_changed.emit(seat, true)
	else:
		_speaking[seat] = SPEAK_HOLD
	if bool(line.get("end", false)):
		v["last"] = 0.15


func _new_voice(seat: int) -> Dictionary:
	var p := AudioStreamPlayer.new()
	p.name = "Funk%d" % seat
	p.bus = BUS_PLAY if AudioServer.get_bus_index(BUS_PLAY) >= 0 else "Master"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	p.stream = gen
	add_child(p)
	p.play()
	var v := {"player": p, "playback": p.get_stream_playback(),
			"queue": PackedVector2Array(), "started": false, "last": SPEAK_HOLD,
			"name": "?", "color": 0, "scope": "all"}
	_voices[seat] = v
	return v


func _play_queues() -> void:
	for seat in _voices:
		var v: Dictionary = _voices[seat]
		var pb = v["playback"]
		if pb == null:
			continue
		var q: PackedVector2Array = v["queue"]
		if not v["started"]:
			if q.size() < int(JITTER_START * RATE):
				continue
			v["started"] = true
		var room: int = pb.get_frames_available()
		if room <= 0 or q.is_empty():
			if q.is_empty():
				v["started"] = false
			continue
		var n: int = mini(room, q.size())
		pb.push_buffer(q.slice(0, n))
		v["queue"] = q.slice(n)


func _expire_speakers(delta: float) -> void:
	for seat in _speaking.keys():
		var left: float = float(_speaking[seat]) - delta
		if left <= 0.0:
			_speaking.erase(seat)
			speaking_changed.emit(int(seat), false)
		else:
			_speaking[seat] = left


func _drop_voice(seat: int) -> void:
	var v = _voices.get(seat)
	if v == null:
		return
	var p: AudioStreamPlayer = v["player"]
	if is_instance_valid(p):
		p.stop()
		p.queue_free()
	_voices.erase(seat)
	if _speaking.erase(seat):
		speaking_changed.emit(seat, false)


func shutdown() -> void:
	set_mode(Mode.OFF)
	for seat in _voices.keys():
		_drop_voice(int(seat))
	_speaking.clear()
	muted_seats.clear()
