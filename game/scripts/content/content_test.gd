

class_name ContentTest
extends RefCounted


static func run(args: PackedStringArray, tree: SceneTree) -> void:
	var src := _arg(args, "--content-dir", ProjectSettings.globalize_path("res://").path_join("../content/ra"))
	var src_de := _arg(args, "--content-de", ProjectSettings.globalize_path("res://").path_join("../content/ra_de"))
	print("== Inhaltstest ==")
	print("Quelle: ", src)

	var c := RaContent.new()
	c.progress.connect(func(stage: String, f: float, detail: String) -> void:
		if stage == "atlas" and detail.ends_with("packen"):
			print("  ", detail, " %.0f%%" % (f * 100.0)))

	var t0 := Time.get_ticks_msec()
	var archives := c.open_dir(src)
	if archives == 0:
		print("FEHLER: ", c.last_error())
		tree.quit(1)
		return
	print("Archive: %d in %d ms" % [archives, Time.get_ticks_msec() - t0])

	var status := c.scan("")
	print("Bestand: ", status)


	t0 = Time.get_ticks_msec()
	var ok := c.build_atlases("", ContentPaths.ATLAS)
	var ms_atlas := Time.get_ticks_msec() - t0
	if not ok:
		print("FEHLER Atlas: ", c.last_error())
		tree.quit(1)
		return
	print("Atlanten: %d ms" % ms_atlas)
	for t in ["temperat", "snow", "interior"]:
		var base := ContentPaths.ATLAS.path_join("atlas_%s" % t)
		print("  atlas_%s.r8 %d KB, .json %d KB" % [t,
				FileAccess.get_file_as_bytes(base + ".r8").size() / 1024,
				FileAccess.get_file_as_bytes(base + ".json").size() / 1024])


	if DirAccess.dir_exists_absolute(src_de):
		var cde := RaContent.new()
		if cde.open_dir(src_de) > 0:
			cde.set_tilesets(PackedStringArray(["cameos_de"]))
			t0 = Time.get_ticks_msec()
			if cde.build_atlases("", ContentPaths.ATLAS):
				print("Cameos (deutsch): %d ms" % (Time.get_ticks_msec() - t0))
			else:
				print("Cameos (deutsch) fehlgeschlagen: ", cde.last_error())


	if not args.has("--no-sfx"):
		t0 = Time.get_ticks_msec()
		if not c.convert_sounds("", ContentPaths.SFX, PackedStringArray(), ""):
			print("FEHLER Sounds: ", c.last_error())
		print("Sounds: %d ms" % (Time.get_ticks_msec() - t0))

		if DirAccess.dir_exists_absolute(src_de):
			var cde2 := RaContent.new()
			if cde2.open_dir(src_de) > 0:
				t0 = Time.get_ticks_msec()
				if cde2.convert_sounds("", ContentPaths.SFX, PackedStringArray(), "de"):
					print("Sounds (deutsch): %d ms" % (Time.get_ticks_msec() - t0))
				else:
					print("Sounds (deutsch) fehlgeschlagen: ", cde2.last_error())

	c.write_manifest(ContentPaths.DIR, {"source": "test-content", "mix_dir": src})
	print("Manifest: ", ContentPaths.DIR, "/manifest.json")
	print("Status:   ", RaContent.content_status(ContentPaths.DIR))


	var movie := _arg(args, "--movie", "redintro")
	var data := c.movie_bytes(movie)
	if data.is_empty():
		print("Film ", movie, ": nicht im Inhalt")
	else:
		var v := VqaPlayer.new()
		if v.open_buffer(data):
			var frames := int(v.fps() * 2.0)
			t0 = Time.get_ticks_msec()
			var img := v.frame_image()
			var n := 0
			while n < frames and v.next_frame():
				v.blit_into(img)
				n += 1
			print("Film %s: %dx%d, %d Bilder, %.1f s Ton — %d Bilder in %d ms" %
					[movie, v.width(), v.height(), v.frame_count(), v.get_length(), n,
					Time.get_ticks_msec() - t0])
		else:
			print("Film ", movie, ": ", v.last_error())


	var tracks := c.list_music()
	print("Musiktitel im Archiv: ", tracks.size())
	var track := _arg(args, "--music", tracks[0] if tracks.size() > 0 else "")
	if track != "":
		var stream := c.aud_stream(track)
		if stream == null:
			print("Musik ", track, ": ", c.last_error())
		else:
			var p := AudioStreamPlayer.new()
			p.stream = stream
			tree.root.add_child.call_deferred(p)
			await tree.process_frame
			p.play()
			await tree.create_timer(2.0).timeout
			print("Musik %s: %d Hz, %.1f s, Position nach 2 s: %.2f s" %
					[track, stream.sample_rate(), stream.get_length(), p.get_playback_position()])
			p.stop()

	print("== fertig ==")
	tree.quit(0)


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var k := args.find(key)
	return args[k + 1] if k >= 0 and k + 1 < args.size() else fallback


const LANG_PROBES := {
	"ackno_v00": "allies.mix", "yessir1_v03": "allies.mix",
	"ackno_r00": "russian.mix", "await1_r01": "russian.mix",
	"eyessir1": "sounds.mix", "myessir1": "sounds.mix", "syessir1": "sounds.mix",
	"unitrdy1": "speech.mix (in REDALERT.MIX)", "conscmp1": "speech.mix (in REDALERT.MIX)",
}

const LANG_STUB_PROBES := ["girlokay", "guyyeah1"]

const LANG_BASE_NAMES := ["ackno.v00", "yessir1.v03", "ackno.r00", "await1.r01", "eyessir1.aud",
		"myessir1.aud", "syessir1.aud", "unitrdy1.aud", "conscmp1.aud", "girlokay.aud", "guyyeah1.aud"]


static func run_lang(args: PackedStringArray, tree: SceneTree) -> void:
	var res_dir := ProjectSettings.globalize_path("res://")
	var src_de := _arg(args, "--content-de", res_dir.path_join("../content/ra_de"))
	var src_en := _arg(args, "--content-dir", res_dir.path_join("../content/ra"))
	print("== Sprachausgabe-Test (deutsche CD) ==")
	print("Deutsche Quelle: ", src_de)
	var fails := 0
	var main_mix := src_de.path_join("cd1/MAIN.MIX")
	var redalert := src_de.path_join("REDALERT.MIX")
	if not FileAccess.file_exists(main_mix) or not FileAccess.file_exists(redalert):
		print("T: --test-content-lang ÜBERSPRUNGEN — ", main_mix, " / ", redalert, " fehlt")
		tree.quit(0)
		return


	var probe := RaContent.new()
	if not probe.open_mix(main_mix):
		print("FEHLER: MAIN.MIX nicht lesbar: ", probe.last_error())
		tree.quit(1)
		return
	var inside := probe.list(main_mix)
	for name in ContentPage.KEEP_FILES["german"]:

		var found := inside.has(name)
		if not found and name != "movies2.mix":
			print("FEHLER: %s steht nicht in der deutschen MAIN.MIX (Behaltensliste falsch)" % name)
			fails += 1
	if not inside.has("speech.mix"):
		print("Bestätigt: speech.mix liegt NICHT in MAIN.MIX (sondern in REDALERT.MIX)")
	else:
		print("FEHLER: speech.mix liegt doch in MAIN.MIX — Behaltensliste überdenken")
		fails += 1


	var root_existed := DirAccess.dir_exists_absolute(ContentManager.ROOT)
	var cd_existed := DirAccess.dir_exists_absolute(ContentManager.CD_DIR.path_join("german"))
	var sfx_existed := DirAccess.dir_exists_absolute(ContentPaths.SFX)
	var out_dir := ContentManager.CD_DIR.path_join("german")
	ContentManager.ensure_dir(out_dir)

	for name in ["sounds.mix", "allies.mix", "russian.mix"]:
		if not probe.extract(main_mix, name, out_dir.path_join(name)):
			print("FEHLER: extract(%s): %s" % [name, probe.last_error()])
			fails += 1


	DirAccess.copy_absolute(redalert, out_dir.path_join("REDALERT.MIX"))
	ContentManager.ensure_dir(ContentPaths.SFX)
	var base := RaContent.new()
	if base.open_dir(src_en) > 0:
		base.convert_sounds("", ContentPaths.SFX, PackedStringArray(LANG_BASE_NAMES), "")
	var base_n := 0
	var bd := DirAccess.open(ContentPaths.SFX)
	if bd != null:
		for f in bd.get_files():
			if f.ends_with(".wav"):
				base_n += 1
	print("Grundfassungen (englisch): %d Dateien in %s" % [base_n, ContentPaths.SFX])
	if base_n == 0:
		print("FEHLER: keine englische Grundfassung angelegt — der Rückfall lässt sich nicht prüfen")
		fails += 1


	var t0 := Time.get_ticks_msec()
	var n := ContentManager.build_language_sounds("de")
	print("build_language_sounds(\"de\"): %d Clips in %d ms" % [n, Time.get_ticks_msec() - t0])
	if n < 200:
		print("FEHLER: nur %d deutsche Clips (erwartet ~%d)" % [n, ContentPage.VOICE_FULL_COUNT])
		fails += 1


	TranslationServer.set_locale("de")
	ContentPaths.refresh()
	var de_dir := ContentPaths.SFX.path_join("de")
	for name in LANG_PROBES:
		var path := ContentPaths.sfx(name)
		if path.begins_with(de_dir):
			print("  %-12s → %s  (%s)" % [name, path, LANG_PROBES[name]])
		else:
			print("FEHLER: %s spielt %s statt der deutschen Fassung (%s)" % [name, path, LANG_PROBES[name]])
			fails += 1
	for name in LANG_STUB_PROBES:
		var path := ContentPaths.sfx(name)
		if path.begins_with(de_dir):
			print("FEHLER: %s ist auf der deutschen CD eine leere Hülle und müsste englisch bleiben" % name)
			fails += 1
		else:
			print("  %-12s → %s  (Stummel: keine deutsche Fassung, Rückfall greift)" % [name, path])

	var langs := ContentManager.installed_languages()
	if not langs.has("de"):
		print("FEHLER: installed_languages() meldet ", langs, " ohne „de“")
		fails += 1
	print("Sprachen laut ContentManager: ", langs)

	if not args.has("--keep"):
		if not root_existed:


			ContentManager.delete_all()
		else:
			if not cd_existed:
				ContentManager.delete_cd("german")
			if not sfx_existed:
				ContentManager._remove_dir_recursive(ContentPaths.SFX)
			else:
				ContentManager._remove_dir_recursive(de_dir)
	print("T: --test-content-lang %s — %d Fehler" % ["OK" if fails == 0 else "FEHLGESCHLAGEN", fails])
	tree.quit(1 if fails > 0 else 0)
