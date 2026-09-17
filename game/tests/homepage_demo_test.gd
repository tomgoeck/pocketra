

extends Node

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	_check_webgl_frame_packing()
	var scene: Node = load("res://scenes/gesture_proto.tscn").instantiate()
	add_child(scene)
	var w: ProtoWorld = scene.get_node("World")
	await get_tree().create_timer(2.0).timeout
	check(w.map_w == 48 and w.map_h == 40, "kleine Demo-Karte")
	check(w.player_factions.get(0, "") == "soviet" and w.player_factions.get(1, "") == "allies",
		"Sowjets gegen Alliierte")


	check(w.player_roster.is_empty(), "keine Spielerliste im Pausenmenü")
	var yard := false
	for u in w.units:
		if u.alive and u.player == 0 and u.type == "fact":
			yard = true
	check(yard, "Bauwagen entfaltet sich zum Bauhof")


	for b in [["powr", 18, 20], ["barr", 22, 20], ["proc", 26, 22], ["weap", 20, 28], ["dome", 25, 28]]:
		w._add_building(b[0], 0, Vector2i(b[1], b[2]))
	for i in 200:
		w.sim.step()
	var locked_seen := 0
	for name in w.types:
		if not w.type_ids.has(name):
			continue
		var t: Dictionary = w.types[name]
		if HomepageDemo.locked(name, t):
			locked_seen += 1
			check(not w.sim.queue_build(0, w.type_ids[name]), "Bausperre: " + name)
	check(locked_seen > 0, "es gibt überhaupt gesperrte Gebäude (%d)" % locked_seen)
	for name in HomepageDemo.BUILDINGS:
		check(w.type_ids[name] in w.sim.buildable(0, 0), "erlaubtes Gebäude: " + name)
	var camera := w._camera.position
	w.pan_screen(Vector2(30, 0))
	check(w._camera.position.x < camera.x, "Kamera folgt der Ziehrichtung")
	var enemies := 0
	for u in w.units:
		if u.alive and u.player == 1 and w.types[u.type].get("building", false):
			enemies += 1
	for i in 5000:
		w.sim.step()
	w._sync_new_actors(w.sim.render_state(1.0))
	var after := 0
	for u in w.units:
		if u.alive and u.player == 1 and w.types[u.type].get("building", false):
			after += 1
	check(enemies == after, "Gegner baut nie ein Gebäude nach (%d → %d)" % [enemies, after])
	print("DEMO TEST FAILURES: ", failures)
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func _check_webgl_frame_packing() -> void:
	var script := load("res://scripts/palette_atlas.gd")
	if not script.has_method("custom_data"):
		print("SKIP PaletteAtlas.custom_data fehlt noch — Web-Atlas nicht geprüft")
		return
	for frame in [0, 255, 256, 14509, 14540, 14572]:
		var packed: Color = script.call("custom_data", frame, 2)
		var unpacked := int(round(packed.r * 255.0)) + 256 * int(round(packed.g * 255.0))
		check(unpacked == frame and int(round(packed.b * 255.0)) - 1 == 2,
			"verlustfreie WebGL-Instanzdaten: " + str(frame))
