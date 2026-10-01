extends Node


signal decision(player: int, tick: int, decision: Dictionary)


var url := ""


var timeout_s := 4.0

var state_format := "text"

var failures := 0
var successes := 0
var replaced := 0

var busy := 0

var skipped := 0

var last_latency_ms := -1

var last_error := ""


var fallbacks_by_player := {}

var backoff_after := 5
var backoff_s := 30.0
var _fail_streak := 0
var _next_try_ms := 0

const SETTINGS := "user://settings.cfg"
const SETTINGS_SECTION := "commander"
const DEFAULT_URL := "http://127.0.0.1:8765/decide"


const INSTRUCTIONS := {
	"doctrine": "Which overall strategy should this AI commander follow for the next minute?",
	"economy": "What should the commander do with the economy right now?",
	"stance": "Which stance should the commander's army take right now?",
	"keep_using_air": "Should the commander keep building and using aircraft?",
	"base_threat": "How strongly is the commander's own base threatened right now?",
	"counter": "Which threat should the commander counter first?",
	"defense_sector": "Where around the base should the next defenses go?",
	"economy_fix": "Which economy problem should be fixed first?",
	"special_op": "Which special operation should the commander launch?",
}


const TEXT_KEYS := [
	["map", "Map"], ["doctrine", "Current doctrine"], ["doctrine_age_s", "Doctrine age in seconds"],
	["credits", "Money"], ["income", "Income"], ["refineries", "Refineries"], ["power", "Power"],
	["army", "Own army"], ["enemy", "Enemy seen"], ["air_losses_60s", "Aircraft lost in last 60 s"],
	["kills_60s", "Enemy units killed in last 60 s"], ["base_damage_60s", "Damage to own base in last 60 s"],
]

var _open := {}


var max_inflight := 1
var max_queue := 2
var timeouts := 0
var _queue: Array = []


func request(player: int, summary: Dictionary, questions: Array, tick: int) -> void:
	if url == "":
		return

	if _fail_streak >= backoff_after and Time.get_ticks_msec() < _next_try_ms:
		skipped += 1
		fallbacks_by_player[player] = int(fallbacks_by_player.get(player, 0)) + 1
		return


	if _open.has(player) and Time.get_ticks_msec() - int(_open[player]["t0"]) < int(timeout_s * 1000.0) + 500:
		busy += 1
		return
	if _open.has(player):
		var old: HTTPRequest = _open[player]["req"]
		old.cancel_request()
		old.queue_free()
		_open.erase(player)
		replaced += 1
	if build_request(summary, questions).is_empty():
		_fail(player, tick, "fragen_ungueltig")
		return
	for i in range(_queue.size()):
		if int(_queue[i]["player"]) == player:
			_queue.remove_at(i)
			replaced += 1
			break
	_queue.append({"player": player, "summary": summary, "questions": questions.duplicate(true), "tick": tick})
	while _queue.size() > max_queue:
		var dropped: Dictionary = _queue.pop_front()
		skipped += 1
		fallbacks_by_player[int(dropped["player"])] = int(fallbacks_by_player.get(int(dropped["player"]), 0)) + 1
	_pump()


func _pump() -> void:
	while _open.size() < max_inflight and not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		var player := int(e["player"])
		var req := HTTPRequest.new()
		req.timeout = timeout_s
		add_child(req)
		var t0 := Time.get_ticks_msec()
		req.request_completed.connect(_on_completed.bind(player, int(e["tick"]), req, e["questions"], t0))
		var err := req.request(url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, request_body(e["summary"], e["questions"]))
		if err != OK:
			req.queue_free()
			_fail(player, int(e["tick"]), "request_%d" % err, true)
			continue
		_open[player] = {"req": req, "tick": int(e["tick"]), "t0": t0}


func pending(player: int) -> bool:
	if _open.has(player):
		return true
	for e in _queue:
		if int(e["player"]) == player:
			return true
	return false


func request_body(summary: Dictionary, questions: Array) -> String:
	return JSON.stringify(build_request(summary, questions), "", false)


func build_request(summary: Dictionary, questions: Array) -> Dictionary:
	var qs := {}
	for q in questions:
		if typeof(q) != TYPE_DICTIONARY or not q.has("id") or not q.has("type"):
			return {}
		var qid := String(q["id"])
		var opts: Array = q.get("options", [])
		var descs: Array = q.get("descriptions", [])
		var ins := String(q.get("instructions", instructions_for(qid)))
		var def := {"type": String(q["type"]), "instructions": ins}
		match String(q["type"]):
			"choice":
				if opts.is_empty():
					return {}
				var crit := {}
				for i in opts.size():
					crit[String(opts[i])] = String(descs[i]) if i < descs.size() else ""
				def["criteria"] = crit
			"score":
				if opts.is_empty():
					return {}
				var levels := []
				for i in opts.size():
					var d := String(descs[i]) if i < descs.size() else ""
					levels.append(String(opts[i]) + (": " + d if d != "" else ""))
				def["criteria"] = levels
			"noul":
				if descs.size() >= 2:


					var flip := opts.size() >= 2 and String(opts[0]).to_lower() in ["yes", "true"]
					def["criteria"] = {"false": String(descs[1] if flip else descs[0]),
						"true": String(descs[0] if flip else descs[1])}
			_:
				return {}
		qs[qid] = def
	var state: Variant = summary_text(summary) if state_format == "text" else summary
	return {"state": state, "questions": qs}


static func op60_words(questions: Array, decision: Dictionary) -> PackedInt32Array:
	var words := PackedInt32Array()
	var base := PackedInt32Array()
	var complete := true
	for i in questions.size():
		var q: Dictionary = questions[i]
		var qid := str(q.get("id", ""))
		var ans = decision.get(qid, null)
		var part := PackedInt32Array()
		match str(q.get("type", "")):
			"choice":
				var sum := 0
				for opt in q.get("options", []):
					var v := 0.0
					if ans is Dictionary:
						v = float(ans.get(str(opt), 0.0))
					var w := clampi(int(round(v * 1000.0)), 0, 1000)
					sum += w
					part.append(w)
				if i >= 5 and (not (ans is Dictionary) or sum == 0):
					complete = false
			"noul":
				part.append(clampi(int(round(float(ans if ans != null else 1.0) * 1000.0)), 0, 1000))
			"score":
				part.append(clampi(int(round(float(ans if ans != null else 0.0) * 1000.0)), 0, 1000))
			_:
				complete = false
		words.append_array(part)
		if i == 4:
			base = words.duplicate()
	if complete and words.size() == 38:
		return words
	return base


static func instructions_for(qid: String) -> String:
	return String(INSTRUCTIONS.get(qid, "Answer the question '%s' for this game state." % qid))


static func summary_text(summary: Dictionary) -> String:
	var parts := PackedStringArray()
	var seen := {}
	for kv in TEXT_KEYS:
		var key: String = kv[0]
		if summary.has(key):
			parts.append("%s: %s." % [kv[1], _value_text(summary[key])])
			seen[key] = true
	var rest := summary.keys()
	rest.sort()
	for key in rest:
		if not seen.has(key):
			parts.append("%s: %s." % [String(key).replace("_", " "), _value_text(summary[key])])
	return "Real-time strategy battle, AI commander report. " + " ".join(parts)


static func _value_text(v: Variant) -> String:
	if typeof(v) == TYPE_DICTIONARY:
		var bits := PackedStringArray()
		for k in v:
			bits.append("%s %s" % [String(k).replace("_", " "), _value_text(v[k])])
		return ", ".join(bits)
	if typeof(v) == TYPE_FLOAT and v == floor(v):
		return str(int(v))
	return str(v)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		player: int, tick: int, req: HTTPRequest, questions: Array, t0: int) -> void:
	req.queue_free()
	if not _open.has(player) or _open[player]["req"] != req:
		return
	_open.erase(player)
	call_deferred("_pump")
	if result == HTTPRequest.RESULT_TIMEOUT:
		timeouts += 1
		_fail(player, tick, "timeout", false)
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(player, tick, "result_%d" % result, true)
		return
	if code != 200:
		_fail(player, tick, "http_%d" % code, code >= 500)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("answers")) != TYPE_DICTIONARY:
		_fail(player, tick, "antwort_kaputt")
		return
	var d := parse_answers(data["answers"], questions)
	if d.is_empty():
		_fail(player, tick, "antwort_unvollstaendig")
		return
	d["source"] = "laya"
	d["latency_ms"] = Time.get_ticks_msec() - t0
	successes += 1
	last_latency_ms = int(d["latency_ms"])
	last_error = ""
	if _fail_streak >= backoff_after:
		print("KOMMANDEUR-CLIENT verbunden url=%s nach %d fehlern" % [url, _fail_streak])
	_fail_streak = 0
	decision.emit(player, tick, d)


static func parse_answers(answers: Dictionary, questions: Array) -> Dictionary:
	var d := {}
	var conf := {}
	for q in questions:
		var qid := String(q["id"])
		var a: Variant = answers.get(qid)
		if typeof(a) != TYPE_DICTIONARY:
			return {}
		match String(q["type"]):
			"choice":
				var probs: Variant = a.get("probabilities")
				if typeof(probs) != TYPE_DICTIONARY:
					return {}
				var out := {}
				for opt in q.get("options", []):
					out[String(opt)] = float(probs.get(String(opt), 0.0))
				d[qid] = out
			"noul":
				d[qid] = float(a.get("noul", 0.5))
			"score":
				var k: int = max(2, q.get("options", []).size())
				d[qid] = clampf(float(a.get("score", 0.0)) / float(k - 1), 0.0, 1.0)
		conf[qid] = float(a.get("answer_confidence", 0.0))
	d["confidence"] = conf
	return d


func _fail(player: int, tick: int, reason: String, network: bool = false) -> void:
	failures += 1
	last_error = reason
	fallbacks_by_player[player] = int(fallbacks_by_player.get(player, 0)) + 1
	print("KOMMANDEUR-CLIENT fehler=%s spieler=%d tick=%d fehlschlaege=%d" % [reason, player, tick, failures])
	if not network:
		return
	_fail_streak += 1
	if _fail_streak >= backoff_after:
		_next_try_ms = Time.get_ticks_msec() + int(backoff_s * 1000.0)
		print("KOMMANDEUR-CLIENT pause=%ds nach %d fehlern in folge, naechster versuch dann (url=%s)"
			% [int(backoff_s), _fail_streak, url])


func state() -> String:
	if _fail_streak >= backoff_after:
		return "pause"
	return "ok" if successes > 0 else "wartet"


static func setting(key: String, default: Variant, path: String = SETTINGS) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return default
	return cfg.get_value(SETTINGS_SECTION, key, default)


static func set_setting(key: String, value: Variant, path: String = SETTINGS) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(SETTINGS_SECTION, key, value)
	cfg.save(path)


static func setting_enabled(path: String = SETTINGS) -> bool:
	return bool(setting("enabled", false, path))


static func setting_url(path: String = SETTINGS) -> String:
	var u := String(setting("url", DEFAULT_URL, path)).strip_edges()
	return u if u != "" else DEFAULT_URL


static func resolve_url(args: PackedStringArray, path: String = SETTINGS) -> String:
	var k := args.find("--commander-url")
	if k >= 0 and k + 1 < args.size():
		return String(args[k + 1])
	if setting_enabled(path):
		return setting_url(path)
	return str(ProjectSettings.get_setting("pocketra/commander_url", ""))
