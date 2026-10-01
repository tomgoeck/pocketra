extends SceneTree


const Client := preload("res://scripts/ai/commander_client.gd")

var fails := 0
var got: Array = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1


func _on_decision(player: int, tick: int, d: Dictionary) -> void:
	got.append([player, tick, d])


func _wait(seconds: float, until: Callable = Callable()) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if until.is_valid() and until.call():
			return
		await process_frame


func _run() -> void:
	var url := "http://127.0.0.1:8765/decide"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--url="):
			url = a.substr(6)
	var example_path := ProjectSettings.globalize_path("res://").path_join("../tools/laya/beispiel_anfrage.json")
	var example: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(example_path))
	var summary: Dictionary = example["summary"]
	var questions: Array = example["questions"]

	var c: Node = Client.new()
	root.add_child(c)
	c.decision.connect(_on_decision)


	check(c.request_body(summary, questions) == JSON.stringify(example["request"], "", false),
		"Anfrage gleich kommandeur_format.py (samt Reihenfolge)")
	c.state_format = "json"
	check(typeof(c.build_request(summary, questions)["state"]) == TYPE_DICTIONARY, "JSON-Format reicht summary durch")
	c.state_format = "text"


	c.url = url
	c.request(0, summary, questions, 400)
	await _wait(5.0, func(): return got.size() > 0)
	check(got.size() == 1, "Entscheidung kommt an")
	if got.size() == 1:
		var d: Dictionary = got[0][2]
		print("  decision=", JSON.stringify(d, "", false))
		check(got[0][0] == 0 and got[0][1] == 400, "Spieler und Tick zurück")
		var s := 0.0
		for k in d["doctrine"]:
			s += d["doctrine"][k]

		check(absf(s - 1.0) < 0.01 and d["doctrine"].size() == 5, "doctrine: 5 Wahrscheinlichkeiten, Summe 1")
		check(d["economy"].size() == 3 and d["stance"].size() == 4, "economy/stance vollständig")
		check(d["keep_using_air"] >= 0.0 and d["keep_using_air"] <= 1.0, "keep_using_air in 0..1")
		check(d["base_threat"] >= 0.0 and d["base_threat"] <= 1.0, "base_threat in 0..1")
		check(d["source"] == "laya" and d["latency_ms"] > 0, "source und latency_ms")
		print("  latenz_ms=", d["latency_ms"])
	check(c.failures == 0 and c.successes == 1, "Zähler nach Erfolg")


	got.clear()
	c.request(1, summary, questions, 500)
	c.request(1, summary, questions, 600)
	check(c.pending(1), "eine offene Anfrage für Spieler 1")
	await _wait(5.0, func(): return got.size() > 0)
	await _wait(0.5)
	check(got.size() == 1 and got[0][1] == 500, "nur die laufende Anfrage antwortet")
	check(c.busy == 1 and c.replaced == 0, "busy-Zähler")


	got.clear()
	var f0: int = c.failures
	c.url = "http://127.0.0.1:1/decide"
	c.request(2, summary, questions, 700)
	await _wait(2.5, func(): return c.failures > f0)
	check(c.failures == f0 + 1 and got.is_empty(), "toter Port: Fehler gezählt, kein Signal")


	c.timeout_s = 1.0
	var srv := TCPServer.new()
	var port := 18799
	check(srv.listen(port, "127.0.0.1") == OK, "stummer Server lauscht")
	var peers: Array = []
	f0 = c.failures
	c.url = "http://127.0.0.1:%d/decide" % port
	var t0 := Time.get_ticks_msec()
	c.request(3, summary, questions, 800)
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and c.failures == f0:
		if srv.is_connection_available():
			peers.append(srv.take_connection())
		await process_frame
	var waited := Time.get_ticks_msec() - t0
	check(c.failures == f0 + 1 and got.is_empty(), "Zeitlimit: Fehler gezählt, kein Signal")
	check(waited >= 900 and waited < 2000, "Zeitlimit greift nach ~1 s (%d ms)" % waited)
	srv.stop()


	c.url = url
	var many: Array = []
	for i in 20:
		many.append({"id": "q%d" % i, "type": "noul", "options": ["false", "true"]})
	f0 = c.failures
	c.request(4, summary, many, 900)
	await _wait(3.0, func(): return c.failures > f0)
	check(c.failures == f0 + 1 and got.is_empty(), "HTTP 413: Fehler gezählt, kein Signal")
	f0 = c.failures
	c.request(5, summary, [{"id": "x", "type": "choice", "options": []}], 1000)
	check(c.failures == f0 + 1, "kaputte Frage: sofort Fehler")


	c.url = ""
	f0 = c.failures
	c.request(6, summary, questions, 1100)
	check(not c.pending(6) and c.failures == f0, "leere url: nichts passiert")

	await _test_settings()
	await _test_reconnect(url, summary, questions)
	await _test_generic(url, summary, questions)

	print("KOMMANDEUR-CLIENT-TEST fehler=%d fehlschlaege=%d erfolge=%d" % [fails, c.failures, c.successes])
	quit(fails)


func _test_settings() -> void:
	var path := "user://commander_client_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var none := PackedStringArray()
	check(not Client.setting_enabled(path), "Einstellung: ohne Datei aus")
	check(Client.setting_url(path) == Client.DEFAULT_URL, "Einstellung: Vorgabeadresse")
	check(Client.resolve_url(none, path) == str(ProjectSettings.get_setting("pocketra/commander_url", "")),
		"Einstellung aus: Projekteinstellung gilt")
	Client.set_setting("enabled", true, path)
	check(Client.resolve_url(none, path) == Client.DEFAULT_URL, "Einstellung an: Vorgabeadresse gilt")
	Client.set_setting("url", "http://10.0.0.5:9000/decide", path)
	check(Client.resolve_url(none, path) == "http://10.0.0.5:9000/decide", "Einstellung an: eigene Adresse")
	var args := PackedStringArray(["--test-ai", "--commander-url", "http://127.0.0.1:1234/decide"])
	check(Client.resolve_url(args, path) == "http://127.0.0.1:1234/decide", "Startargument gewinnt")
	Client.set_setting("url", "  ", path)
	check(Client.setting_url(path) == Client.DEFAULT_URL, "leere Adresse: Vorgabe")
	Client.set_setting("enabled", false, path)
	check(Client.resolve_url(none, path) == "", "Einstellung wieder aus: Client aus")
	var cfg := ConfigFile.new()
	check(cfg.load(path) == OK and cfg.has_section_key("commander", "enabled"), "Datei hat [commander]")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_reconnect(url: String, summary: Dictionary, questions: Array) -> void:
	var c: Node = Client.new()
	root.add_child(c)
	c.decision.connect(_on_decision)
	c.backoff_s = 1.5
	c.url = "http://127.0.0.1:1/decide"
	for i in 5:
		var f0: int = c.failures
		c.request(7, summary, questions, 2000 + i)
		await _wait(2.5, func(): return c.failures > f0)
	check(c.failures == 5 and c.state() == "pause", "fünf Fehler: Pause (%s)" % c.state())
	var f1: int = c.failures
	c.request(7, summary, questions, 2100)
	c.request(8, summary, questions, 2100)
	check(c.skipped == 2 and c.failures == f1 and not c.pending(7), "Pause: Anfragen still ausgelassen")
	check(int(c.fallbacks_by_player.get(7, 0)) == 6, "Rückfälle je Spieler gezählt")
	c.url = url
	await _wait(1.7)
	got.clear()
	c.request(7, summary, questions, 2200)
	check(c.pending(7), "nach der Pause: Probeanfrage geht hinaus")
	await _wait(5.0, func(): return got.size() > 0)
	check(got.size() == 1 and c.state() == "ok" and c.successes == 1, "wieder verbunden (%s)" % c.state())
	check(c.last_latency_ms > 0 and c.last_error == "", "last_latency_ms gesetzt, kein Fehler")
	c.queue_free()


func _sim_questions(questions: Array) -> Array:
	if ClassDB.class_exists("RaSim"):
		var sim = ClassDB.instantiate("RaSim")
		var qs: Array = sim.bot_commander_questions()
		return qs
	return questions.duplicate(true)


func _test_generic(url: String, summary: Dictionary, questions: Array) -> void:
	var c: Node = Client.new()
	root.add_child(c)
	c.decision.connect(_on_decision)
	c.url = url
	var nine: Array = _sim_questions(questions)
	check(nine.size() == 9, "neun Fragen")
	var req: Dictionary = c.build_request(summary, nine)
	check(req.get("questions", {}).size() == 9, "Anfrage mit neun Fragen")
	var ctr: Dictionary = nine[5]
	check(str(req["questions"]["counter"]["instructions"]) == str(ctr.get("instructions", "")), "Anweisung aus der Frage gewinnt")
	var ok_tab := true
	for q in nine:
		if q.has("instructions"):
			ok_tab = ok_tab and str(q["instructions"]) == str(Client.INSTRUCTIONS.get(q["id"], ""))
	check(ok_tab, "Tabelle im Client = Text der Sim-Fragen")
	var bare: Dictionary = c.build_request(summary, [{"id": "counter", "type": "choice", "options": ["none"]}])
	check(str(bare["questions"]["counter"]["instructions"]) == Client.INSTRUCTIONS["counter"], "Frage ohne Text: Tabelle")
	var odd: Dictionary = c.build_request(summary, [{"id": "mystery_q", "type": "noul", "options": ["false", "true"]}])
	check(str(odd["questions"]["mystery_q"]["instructions"]).contains("mystery_q"), "unbekannte Frage: allgemeine Anweisung")
	got.clear()
	c.request(9, summary, nine, 3000)
	await _wait(6.0, func(): return got.size() > 0)
	check(got.size() == 1, "Entscheidung zu neun Fragen kommt an (%d Fehler)" % c.failures)
	if got.size() == 1:
		var d: Dictionary = got[0][2]
		var ok := true
		for q in nine:
			ok = ok and d.has(q["id"]) and d["confidence"].has(q["id"])
		check(ok, "alle neun ids in der Entscheidung")
		var s := 0.0
		for k in d["counter"]:
			s += d["counter"][k]
		check(d["counter"].size() == 6 and absf(s - 1.0) < 0.01, "counter: 6 Wahrscheinlichkeiten, Summe 1")
		check(d["special_op"] is Dictionary and d["special_op"].size() == 5, "special_op: 5 Optionen")
		var words: PackedInt32Array = Client.op60_words(nine, d)
		check(words.size() == 38, "op 60 aus der Antwort: 38 Wörter (%d)" % words.size())
		var d14: Dictionary = d.duplicate(true)
		d14.erase("special_op")
		check(Client.op60_words(nine, d14).size() == 14, "ohne special_op: 14 Wörter")
		print("  neun_fragen_latenz_ms=", d["latency_ms"])
	c.queue_free()
