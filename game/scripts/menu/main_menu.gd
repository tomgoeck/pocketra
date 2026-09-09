

extends Control

const GAME_SCENE := "res://scenes/gesture_proto.tscn"
const SETTINGS := "user://settings.cfg"

var _maps: Array = []
var _skirmish: Array = []
var _missions: Array = []
var _selected := -1
var _ai_players := 1
var _credits := 5000
var _faction := "allies"
var _ai_faction := "soviet"
var _faction_btn: Button
var _ai_faction_btn: Button
var _starting_units := "none"

var _crates := true
var _crates_btn: Button


var _explored_map := false
var _explored_map_btn: Button
var _fog := true
var _fog_btn: Button

var _ai_difficulty := "normal"
var _ai_difficulty_btn: Button
var _start_btn: Button

var _root: Control
var _pages := {}
var _map_buttons: Array = []
var _preview: TextureRect
var _info: Label
var _credits_label: Label
var _ai_label: Label


func _ready() -> void:
	_maps = MapData.list_maps()
	for m in _maps:
		var cats: Array = m.get("categories", [])
		if cats.has("Campaign") or m.get("visibility", "") == "MissionSelector":
			_missions.append(m)
		elif int(m.get("players", 0)) >= 2 and _has_tileset(m.get("tileset", "")) and m.get("visibility", "") != "Shellmap":
			_skirmish.append(m)
	_load_settings()
	_build_ui()
	_show("main")
	var args := OS.get_cmdline_user_args()


	_apply_lobby_args(args)
	var k := args.find("--menu-screenshot")
	if k >= 0 and k + 1 < args.size():
		_shot_path = args[k + 1]
		if args.has("--page-skirmish"):
			_show("skirmish")
		var pk := args.find("--page")
		if pk >= 0 and pk + 1 < args.size() and _pages.has(args[pk + 1]):
			_show(args[pk + 1])
		var sk2 := args.find("--select")
		if sk2 >= 0 and sk2 + 1 < args.size() and _mission_buttons.has(args[sk2 + 1]):

			_mission_buttons[args[sk2 + 1]].pressed.emit.call_deferred()
	var lk := args.find("--load")
	if lk >= 0 and lk + 1 < args.size():
		_start_savegame.call_deferred(args[lk + 1])
		return
	_cycle = args.has("--test-cycle")
	if args.has("--test-lobby"):
		_shot_manual = true
		call_deferred("_run_test_lobby")
	if args.has("--test-layout"):
		call_deferred("_run_test_layout")
	if args.has("--autostart"):
		var mk := args.find("--map")
		if mk >= 0 and mk + 1 < args.size():
			for i in _skirmish.size():
				if _skirmish[i]["slug"] == args[mk + 1]:
					_on_map_selected(i)
		if _selected < 0 and _skirmish.size() > 0:
			_on_map_selected(0)
		_start_skirmish()


func _apply_lobby_args(args: PackedStringArray) -> void:
	var mk := args.find("--map")
	if mk >= 0 and mk + 1 < args.size():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == args[mk + 1]:
				_on_map_selected(i)
	var ak := args.find("--ai")
	if ak >= 0 and ak + 1 < args.size():
		_set_ai(int(args[ak + 1]))


var _shot_path := ""
var _shot_frames := 0
var _cycle := false
var _shot_manual := false
var _cycle_frames := 0


func _process(_delta: float) -> void:
	if _cycle:
		_cycle_frames += 1
		if _cycle_frames == 25:
			match ProtoWorld.test_cycle_step:
				0:
					print("T: Zyklus startet Gefecht")
					_start_skirmish()
				1:
					print("T: Zyklus startet Mission allies-02")
					_on_mission_selected("allies-02")
					_start_mission()
				_:
					print("T: Zyklus fertig")
					get_tree().quit()
		return
	if _shot_path == "" or _shot_manual:
		return
	_shot_frames += 1
	if _shot_frames == 12:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
		get_tree().quit()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_ai_players = int(cfg.get_value("skirmish", "ai_players", 1))
		_credits = int(cfg.get_value("skirmish", "credits", 5000))
		_faction = str(cfg.get_value("skirmish", "faction", "allies"))
		_ai_faction = str(cfg.get_value("skirmish", "ai_faction", "soviet"))
		_starting_units = str(cfg.get_value("skirmish", "starting_units", "none"))
		_crates = bool(cfg.get_value("skirmish", "crates", true))
		_explored_map = bool(cfg.get_value("skirmish", "explored_map", false))
		_fog = bool(cfg.get_value("skirmish", "fog", true))
		_ai_difficulty = str(cfg.get_value("skirmish", "ai_difficulty", "normal"))
		if not ProtoWorld.AI_DIFFICULTIES.has(_ai_difficulty):
			_ai_difficulty = "normal"
		var last: String = cfg.get_value("skirmish", "map", "")
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == last:
				_selected = i
		Music.enabled_default = bool(cfg.get_value("audio", "music", true))
		_player_team = int(cfg.get_value("skirmish", "player_team", 0))
		_spawn_choice = int(cfg.get_value("skirmish", "spawn", -1))


		var saved: Array = cfg.get_value("skirmish", "ai_slots", [])
		if saved is Array and not saved.is_empty():
			_ai_slots = saved.duplicate(true)
			_ai_slots.resize(mini(_ai_slots.size(), ProtoWorld.AI_PLAYER_INDICES.size()))
			for slot in _ai_slots:
				if not (slot is Dictionary):
					_ai_slots = []
					break
		_slot_defaults()
	if _selected < 0 and not _skirmish.is_empty():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == ProtoWorld.DEFAULT_MAP:
				_selected = i
		if _selected < 0:
			_selected = 0


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("skirmish", "ai_players", _ai_players)
	cfg.set_value("skirmish", "credits", _credits)
	cfg.set_value("skirmish", "faction", _faction)
	cfg.set_value("skirmish", "ai_faction", _ai_faction)
	cfg.set_value("skirmish", "starting_units", _starting_units)
	cfg.set_value("skirmish", "crates", _crates)
	cfg.set_value("skirmish", "explored_map", _explored_map)
	cfg.set_value("skirmish", "fog", _fog)
	cfg.set_value("skirmish", "ai_difficulty", _ai_difficulty)
	if _selected >= 0 and _selected < _skirmish.size():
		cfg.set_value("skirmish", "map", _skirmish[_selected]["slug"])
	cfg.set_value("audio", "music", Music.enabled_default)
	cfg.set_value("skirmish", "player_team", _player_team)
	cfg.set_value("skirmish", "spawn", _spawn_choice)
	cfg.set_value("skirmish", "ai_slots", _ai_slots)
	cfg.save(SETTINGS)


func _button(text: String, cb: Callable, w: float = 200.0, h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(w), Dp.px(h))
	HudTheme.style_button(b, 14.0)
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


func _menu_button(text: String, _icon: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(260), Dp.px(42))
	HudTheme.style_menu_button(b, 19.0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): Sfx.click(self))
	b.pressed.connect(cb)
	return b


static var _icon_cache := {}
static func _keyed_icon(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.7 and c.b > 0.7 and c.g < 0.35:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.resize(96, 96, Image.INTERPOLATE_NEAREST)
	var out := ImageTexture.create_from_image(img)
	_icon_cache[path] = out
	return out


func _title(text: String, size_dp: float = 34.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(Dp.px(size_dp)))
	l.add_theme_color_override("font_color", HudTheme.GOLD)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", int(Dp.px(2)))
	return l


const VERSION := "v0.5"


func _build_ui() -> void:


	var bg := TextureRect.new()
	var vs := get_viewport().get_visible_rect().size
	var wide := vs.x / maxf(vs.y, 1.0) > 2.0
	var lang_code := Lang.code()
	var bg_path := "res://assets/ui/menu_bg_wide_%s.png" % lang_code
	if not (wide and ResourceLoader.exists(bg_path)):
		bg_path = "res://assets/ui/menu_bg_%s.png" % lang_code
	bg.texture = load(bg_path)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


	var lights := MenuBackground.new()
	lights.set_anchors_preset(Control.PRESET_FULL_RECT)
	lights.set_background(bg_path, bg.texture)
	add_child(lights)

	var safe := Dp.safe_rect()
	var subtitle := Label.new()
	subtitle.text = tr("menu.main.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", int(Dp.px(11)))
	subtitle.add_theme_color_override("font_color", HudTheme.GOLD)
	subtitle.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	subtitle.add_theme_constant_override("outline_size", int(Dp.px(1)))
	subtitle.modulate = Color(1, 1, 1, 0.7)
	subtitle.position = Vector2(safe.position.x, safe.end.y - Dp.px(40))
	subtitle.size = Vector2(safe.size.x, Dp.px(18))
	add_child(subtitle)
	var version := Label.new()
	version.text = VERSION
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", int(Dp.px(12)))
	version.add_theme_color_override("font_color", HudTheme.GOLD)
	version.position = Vector2(safe.end.x - Dp.px(60), safe.end.y - Dp.px(22))
	version.size = Vector2(Dp.px(50), Dp.px(18))
	add_child(version)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)


	var main := VBoxContainer.new()
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override("separation", int(Dp.px(4)))
	main.alignment = BoxContainer.ALIGNMENT_BEGIN
	var spacer := Control.new()
	main.add_child(spacer)


	var no_saves := SaveGame.list_all().is_empty()
	if no_saves:
		main.add_child(_menu_button(tr("menu.main.tutorial"), "star", _start_tutorial))
	main.add_child(_menu_button(tr("menu.main.skirmish"), "tank", func(): _show("skirmish")))
	main.add_child(_menu_button(tr("menu.main.missions"), "star", func(): _show("missions")))
	if not no_saves:
		main.add_child(_menu_button(tr("menu.main.load"), "star", func(): _rebuild_ui("load")))
	main.add_child(_menu_button(tr("menu.main.options"), "gear", func(): _show("options")))
	main.add_child(_menu_button(tr("menu.main.quit"), "door", func(): get_tree().quit()))


	var vh := get_viewport().get_visible_rect().size.y
	var needed := (main.get_child_count() - 1) * (Dp.px(42) + Dp.px(4))
	spacer.custom_minimum_size = Vector2(0, clampf(vh - needed - Dp.px(24), 0.0, vh * 0.30))
	_pages["main"] = _center(main)


	var narrow := get_viewport().get_visible_rect().size.x < Dp.px(640)
	var sk: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	sk.add_theme_constant_override("separation", int(Dp.px(16)))
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(0 if narrow else Dp.px(260), 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL
	left.add_child(_title(tr("menu.main.skirmish"), 18))

	var scroll := TouchList.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if narrow:

		scroll.custom_minimum_size = Vector2(0, get_viewport().get_visible_rect().size.y * 0.40)
	var listbox := VBoxContainer.new()
	listbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listbox.add_theme_constant_override("separation", int(Dp.px(4)))
	_map_scroll = scroll
	_map_buttons = []
	for i in _skirmish.size():
		var m: Dictionary = _skirmish[i]
		var b := Button.new()
		b.text = "%s  (%d, %s)" % [m["title"], int(m["players"]), _tileset_name(m["tileset"])]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, Dp.px(32))
		HudTheme.style_tab(b, 12.0)
		var idx := i
		b.pressed.connect(func():
			Sfx.click(self)
			_on_map_selected(idx))
		listbox.add_child(b)
		_map_buttons.append(b)
	scroll.add_child(listbox)
	left.add_child(scroll)
	sk.add_child(left)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", int(Dp.px(4)))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(Dp.px(160), Dp.px(84))
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_show_map_overlay())
	right.add_child(_preview)
	_info = Label.new()
	_info.add_theme_color_override("font_color", HudTheme.TEXT)
	_info.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	_ai_label = Label.new()
	_ai_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_ai_label.add_theme_color_override("font_color", HudTheme.TEXT)
	row.add_child(_button("−", func(): _set_ai(_ai_players - 1), 40, 34))
	row.add_child(_ai_label)
	row.add_child(_button("+", func(): _set_ai(_ai_players + 1), 40, 34))
	right.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", int(Dp.px(8)))
	_credits_label = Label.new()
	_credits_label.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_credits_label.add_theme_color_override("font_color", HudTheme.TEXT)
	row2.add_child(_button("−", func(): _set_credits(_credits - 2500), 40, 34))
	row2.add_child(_credits_label)
	row2.add_child(_button("+", func(): _set_credits(_credits + 2500), 40, 34))
	right.add_child(row2)

	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", int(Dp.px(4)))
	right.add_child(_slot_box)
	var row3 := HBoxContainer.new()
	row3.visible = false
	row3.add_theme_constant_override("separation", int(Dp.px(8)))
	_faction_btn = _button("", func(): pass, 130, 34)
	_faction_btn.pressed.connect(func():
		_faction = _next_faction_value(_faction)
		_update_factions())
	_ai_faction_btn = _button("", func(): pass, 130, 34)
	_ai_faction_btn.pressed.connect(func():
		_ai_faction = _next_faction_value(_ai_faction)
		_update_factions())
	row3.add_child(_faction_btn)
	row3.add_child(_ai_faction_btn)
	right.add_child(row3)
	_start_btn = _button("", func(): pass, 268, 34)
	_start_btn.pressed.connect(func():
		var order := ["none", "light", "heavy"]
		_starting_units = order[(order.find(_starting_units) + 1) % order.size()]
		_update_factions())
	right.add_child(_start_btn)
	_ai_difficulty_btn = null
	_crates_btn = _button("", func(): pass, 268, 34)
	_crates_btn.pressed.connect(func():
		_crates = not _crates
		_update_factions())
	right.add_child(_crates_btn)


	_explored_map_btn = _button("", func(): pass, 268, 34)
	_explored_map_btn.pressed.connect(func():
		_explored_map = not _explored_map
		_update_factions())
	right.add_child(_explored_map_btn)
	_fog_btn = _button("", func(): pass, 268, 34)
	_fog_btn.pressed.connect(func():
		_fog = not _fog
		_update_factions())
	right.add_child(_fog_btn)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(Dp.px(8)))
	actions.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	actions.add_child(_button(tr("menu.skirmish.start"), _start_skirmish, 168, 40))
	right_scroll.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(right_scroll)
	right_col.add_child(actions)
	sk.add_child(right_col)
	_pages["skirmish"] = _center(sk, true)


	var mi := VBoxContainer.new()
	mi.add_theme_constant_override("separation", int(Dp.px(6)))
	mi.add_child(_title(tr("menu.main.missions"), 18))
	var mscroll := TouchList.new()
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var mbox := VBoxContainer.new()
	mbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mbox.add_theme_constant_override("separation", int(Dp.px(3)))
	for c in Missions.campaigns():
		var maps: Array = c.get("maps", [])
		var done := 0
		var open_count := 0
		for slug in maps:
			if _completed(slug):
				done += 1
			if _mission_reason(slug) == "":
				open_count += 1
		var head := Label.new()
		head.text = tr("menu.missions.progress") % [_campaign_name(c.get("name", "")), open_count, maps.size(), done]
		head.add_theme_font_size_override("font_size", int(Dp.px(12)))
		head.add_theme_color_override("font_color", HudTheme.GOLD)
		mbox.add_child(head)
		for slug in maps:
			var reason := _mission_reason(slug)
			var b := Button.new()
			b.text = "%s%s%s" % ["✔ " if _completed(slug) else "", _mission_title(slug),
					"" if reason == "" else "   — %s" % _mission_short_reason(slug)]
			b.toggle_mode = true

			b.disabled = false
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, Dp.px(30))
			HudTheme.style_tab(b, 11.0)
			if reason != "":
				b.modulate = Color(1, 1, 1, 0.85)
			var sl: String = slug
			b.pressed.connect(func():
				Sfx.click(self)
				_on_mission_selected(sl))
			mbox.add_child(b)
			_mission_buttons[slug] = b
	mscroll.add_child(mbox)
	mi.add_child(mscroll)
	_mission_info = Label.new()
	_mission_info.add_theme_font_size_override("font_size", int(Dp.px(11)))
	_mission_info.add_theme_color_override("font_color", HudTheme.TEXT)
	_mission_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mi.add_child(_mission_info)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", int(Dp.px(8)))
	_difficulty_btn = _button(tr("menu.missions.difficulty") % _difficulty_name("normal"), func(): _cycle_difficulty(), 190, 40)
	mrow.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	mrow.add_child(_difficulty_btn)
	mrow.add_child(_button(tr("menu.missions.start"), _start_mission, 168, 40))
	mi.add_child(mrow)
	_pages["missions"] = _center(mi, true)


	var ld := VBoxContainer.new()
	ld.add_theme_constant_override("separation", int(Dp.px(6)))
	ld.add_child(_title(tr("menu.main.load"), 18))
	var lscroll := TouchList.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbox.add_theme_constant_override("separation", int(Dp.px(4)))
	var saves := SaveGame.list_all()
	if saves.is_empty():
		var none := Label.new()
		none.text = tr("save.none")
		none.add_theme_font_size_override("font_size", int(Dp.px(13)))
		lbox.add_child(none)
	else:


		var latest_slot := str(saves[0]["slot"])
		var cont := _button("%s — %s" % [tr("menu.main.continue"), SaveGame.label(saves[0]).replace("\n", "  ")],
				func(): _start_savegame(latest_slot), 460, 52)
		cont.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cont.add_theme_color_override("font_color", HudTheme.GOLD)
		lbox.add_child(cont)
	for e in saves:
		var slot := str(e["slot"])
		var name := tr("save.slot_auto") if SaveGame.is_auto(slot) else tr("save.slot") % slot
		var b := _button("%s — %s" % [name, SaveGame.label(e).replace("\n", "  ")],
				func(): _start_savegame(slot), 460, 52)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(b)
	lscroll.add_child(lbox)
	ld.add_child(lscroll)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", int(Dp.px(8)))
	lrow.add_child(_button(tr("ui.back"), func(): _show("main"), 100, 40))
	ld.add_child(lrow)
	_pages["load"] = _center(ld, true)


	var op_head := _title(tr("menu.main.options"), 18)
	var op_scroll := ScrollContainer.new()
	op_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	op_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var op := VBoxContainer.new()
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op.add_theme_constant_override("separation", int(Dp.px(8)))


	var lang_btn := _button("", func(): pass, 268, 34)
	lang_btn.text = tr("menu.options.language") % ("Deutsch" if Lang.is_de() else "English")
	lang_btn.pressed.connect(func():
		Lang.set_language("en" if Lang.is_de() else "de")
		_rebuild_ui("options"))
	op.add_child(lang_btn)
	var music_btn := _button("", func(): pass)
	music_btn.text = _music_text()
	music_btn.pressed.connect(func():
		var mp = get_node_or_null("/root/MusicPlayer")
		if mp != null:
			mp.toggle()
		else:
			Music.enabled_default = not Music.enabled_default
		music_btn.text = _music_text())
	op.add_child(music_btn)

	op.add_child(HudTheme.choice_row(tr("menu.options.game_speed"), GameSpeed.names(), GameSpeed.index(),
			func(i): GameSpeed.set_index(i), self))
	for entry in [["master", tr("menu.options.master")], ["music", tr("menu.options.music")],
			["sfx", tr("menu.options.sfx")], ["voice", tr("menu.options.voice")], ["video", tr("menu.options.video")]]:
		op.add_child(_volume_row(entry[0], entry[1]))
	op_scroll.add_child(op)

	var op_col := VBoxContainer.new()
	op_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	op_col.add_theme_constant_override("separation", int(Dp.px(6)))
	op_col.add_child(op_head)
	op_col.add_child(op_scroll)
	var op_foot := HBoxContainer.new()
	op_foot.add_theme_constant_override("separation", int(Dp.px(8)))
	op_foot.alignment = BoxContainer.ALIGNMENT_CENTER
	op_foot.add_child(_button(tr("menu.options.controls_button"), func(): _show("controls"), 220, 40))
	op_foot.add_child(_button(tr("ui.back"), func(): _show("main"), 140, 40))
	op_col.add_child(op_foot)
	_pages["options"] = _center(op_col, true)


	_controls_box = VBoxContainer.new()
	_controls_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pages["controls"] = _center(_controls_box, true)

	if _selected >= 0:
		_on_map_selected(_selected)
	_update_mission_info()
	_set_ai(_ai_players)
	_set_credits(_credits)
	_update_factions()


func _volume_row(key: String, label: String) -> Control:
	return HudTheme.volume_row(key, label, self)


var _mission_slug := ""
var _mission_buttons := {}
var _mission_info: Label
var _difficulty_btn: Button
var _difficulty := ""
var _difficulties: Array = []


const CAMPAIGN_KEYS := {
	"Allied Campaign": "campaign.allied", "Soviet Campaign": "campaign.soviet",
	"Counterstrike Allied Missions": "campaign.counterstrike_allied",
	"Counterstrike Soviet Missions": "campaign.counterstrike_soviet",
	"Aftermath Allied Missions": "campaign.aftermath_allied",
	"Aftermath Soviet Missions": "campaign.aftermath_soviet",
	"OpenRA Originals": "campaign.openra_originals", "Ant Missions": "campaign.ant_missions",
}
const DIFFICULTY_KEYS := {"easy": "difficulty.easy", "normal": "difficulty.normal", "hard": "difficulty.hard", "tough": "difficulty.tough"}


func _campaign_name(name: String) -> String:
	return tr(CAMPAIGN_KEYS[name]) if CAMPAIGN_KEYS.has(name) else name


func _difficulty_name(d: String) -> String:
	return tr(DIFFICULTY_KEYS[d]) if DIFFICULTY_KEYS.has(d) else d


var _by_slug := {}
var _done_slugs := {}


func _map_entry(slug: String) -> Dictionary:
	if _by_slug.is_empty():
		for m in _maps:
			_by_slug[str(m.get("slug", ""))] = m
	return _by_slug.get(slug, {})


func _completed(slug: String) -> bool:
	if _done_slugs.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(Missions.PROGRESS) == OK and cfg.has_section("missions"):
			for k in cfg.get_section_keys("missions"):
				_done_slugs[k] = bool(cfg.get_value("missions", k, false))
		_done_slugs["__geladen__"] = true
	return bool(_done_slugs.get(slug, false))


func _mission_title(slug: String) -> String:
	var m := _map_entry(slug)
	return str(m.get("title", slug)) if not m.is_empty() else slug


func _mission_reason(slug: String) -> String:
	var m := _map_entry(slug)
	if m.is_empty():
		return tr("lock.map_missing")
	if not Missions.has_script(slug):

		var r := Missions.blocked_reason(slug)
		return r if r != "" else tr("lock.script_missing")
	var tileset := str(m.get("tileset", ""))
	if tileset != "" and not Missions.TILESETS.has(tileset):
		return tr("lock.tileset_missing") % tileset
	return ""


func _mission_short_reason(slug: String) -> String:
	var r := _mission_reason(slug)
	if r == "" or r.length() <= 22:
		return r
	return tr("lock.not_ported")


func _mission_difficulties(slug: String) -> Array:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d.get("difficulties", []) if d is Dictionary else []


func _mission_difficulty_default(slug: String) -> String:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return "normal"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return str(d.get("difficulty_default", "normal")) if d is Dictionary else "normal"


func _on_mission_selected(slug: String) -> void:
	_mission_slug = slug
	for k in _mission_buttons:
		_mission_buttons[k].button_pressed = k == slug
	_difficulties = _mission_difficulties(slug)
	_difficulty = _mission_difficulty_default(slug)
	_update_mission_info()


func _cycle_difficulty() -> void:
	if _difficulties.is_empty():
		return
	var i := _difficulties.find(_difficulty)
	_difficulty = _difficulties[(i + 1) % _difficulties.size()]
	_update_mission_info()


func _update_mission_info() -> void:
	var has_diff := not _difficulties.is_empty()
	_difficulty_btn.disabled = not has_diff
	_difficulty_btn.text = tr("menu.missions.difficulty") % (_difficulty_name(_difficulty) if has_diff else "—")
	if _mission_slug == "":
		_mission_info.text = tr("menu.missions.pick")
		return
	var lines := "%s%s" % [_mission_title(_mission_slug), tr("menu.missions.completed_suffix") if _completed(_mission_slug) else ""]
	var reason := _mission_reason(_mission_slug)
	if reason != "":
		_mission_info.text = tr("menu.missions.locked") % [lines, reason]
		return
	var brief := Missions.briefing(_mission_slug)
	if brief != "":
		lines += "\n" + brief.split("\n")[0]
	if not has_diff:
		lines += "\n" + tr("menu.missions.no_difficulty")
	_mission_info.text = lines


func _start_savegame(slot: String) -> void:
	if SaveGame.read(slot, false).is_empty():
		return
	ProtoWorld.next_savegame = slot
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_tutorial() -> void:
	ProtoWorld.next_map = "tutorial"
	ProtoWorld.next_mission = "tutorial"
	ProtoWorld.next_credits = 5000
	ProtoWorld.next_difficulty = ""
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_mission() -> void:
	if _mission_slug == "" or _mission_reason(_mission_slug) != "":
		return
	ProtoWorld.next_map = _mission_slug
	ProtoWorld.next_mission = _mission_slug
	ProtoWorld.next_credits = 5000
	ProtoWorld.next_difficulty = _difficulty if not _difficulties.is_empty() else ""
	get_tree().change_scene_to_file(GAME_SCENE)


func _faction_name(f: String) -> String:
	if f == "random":
		return tr("faction.random")
	return tr("faction.allies") if f == "allies" else tr("faction.soviet")


const FACTION_CYCLE := ["allies", "soviet", "random"]


func _next_faction_value(f: String) -> String:
	return FACTION_CYCLE[(FACTION_CYCLE.find(f) + 1) % FACTION_CYCLE.size()]


func _team_name(t: int) -> String:
	return tr("lobby.team") % (tr("lobby.team_none") if t <= 0 else str(t))


const STARTING_UNITS_KEYS := {"none": "menu.skirmish.units_none", "light": "menu.skirmish.units_light", "heavy": "menu.skirmish.units_heavy"}

const AI_DIFFICULTY_KEYS := {"easy": "menu.skirmish.ai_easy", "normal": "menu.skirmish.ai_normal", "hard": "menu.skirmish.ai_hard"}


func _update_factions() -> void:
	if _faction_btn != null:
		_faction_btn.text = tr("menu.skirmish.mine") % _faction_name(_faction)
	if _ai_faction_btn != null:
		_ai_faction_btn.text = tr("menu.skirmish.ai_faction") % _faction_name(_ai_faction)
	_rebuild_slots()
	if _start_btn != null:
		_start_btn.text = tr("menu.skirmish.starting_units") % tr(STARTING_UNITS_KEYS.get(_starting_units, "menu.skirmish.units_none"))
	if _crates_btn != null:
		_crates_btn.text = tr("menu.skirmish.crates") % tr("word.on" if _crates else "word.off")
	if _explored_map_btn != null:
		_explored_map_btn.text = tr("menu.skirmish.explored_map") % tr("word.on" if _explored_map else "word.off")
	if _fog_btn != null:
		_fog_btn.text = tr("menu.skirmish.fog") % tr("word.on" if _fog else "word.off")
	if _ai_difficulty_btn != null:
		_ai_difficulty_btn.text = tr("menu.skirmish.ai_difficulty") % tr(AI_DIFFICULTY_KEYS.get(_ai_difficulty, "menu.skirmish.ai_normal"))


func _center(content: Control, fill: bool = false) -> Control:
	var c := MarginContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

	var m := int(Dp.px(12))
	var vs := get_viewport().get_visible_rect().size
	var safe := Dp.safe_rect()
	c.add_theme_constant_override("margin_left", m + int(maxf(safe.position.x, 0.0)))
	c.add_theme_constant_override("margin_top", m + int(maxf(safe.position.y, 0.0)))
	c.add_theme_constant_override("margin_right", m + int(maxf(vs.x - safe.end.x, 0.0)))
	c.add_theme_constant_override("margin_bottom", m + int(maxf(vs.y - safe.end.y, 0.0)))
	if fill:

		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", HudTheme.panel(Color(0.05, 0.05, 0.04, 0.88), HudTheme.BORDER_DIM, 8.0))
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var inner := MarginContainer.new()
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			inner.add_theme_constant_override(side, int(Dp.px(8)))
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inner.add_child(content)
		frame.add_child(inner)
		c.add_child(frame)
	else:
		var cc := CenterContainer.new()
		cc.add_child(content)
		c.add_child(cc)
	c.visible = false
	_root.add_child(c)
	return c


func _run_test_lobby() -> void:


	_show("skirmish")
	for _i in 12:
		await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	var mk := args.find("--map")
	if mk >= 0 and mk + 1 < args.size():
		for i in _skirmish.size():
			if _skirmish[i]["slug"] == args[mk + 1]:
				_on_map_selected(i)
	_set_ai(3)
	_slot_defaults()
	_player_team = 1
	_ai_slots[0]["team"] = 2
	_ai_slots[1]["team"] = 1
	_ai_slots[2]["team"] = 2
	_ai_slots[0]["faction"] = "soviet"
	_ai_slots[1]["faction"] = "allies"
	_ai_slots[2]["faction"] = "random"
	_faction = "random"
	_update_factions()
	for _i in 4:
		await get_tree().process_frame


	var before: Array = [str(_ai_slots[2]["faction"]), int(_ai_slots[2]["team"])]
	_set_ai(_max_ai())
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen" % [_ai_players, _slot_box.get_child_count() - 2])
	_set_ai(1)
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen" % [_ai_players, _slot_box.get_child_count() - 2])
	_set_ai(3)
	await get_tree().process_frame
	print("T: Lobby — %d KI, %d Platzzeilen, KI 3 unverändert: %s" % [_ai_players,
		_slot_box.get_child_count() - 2,
		before == [str(_ai_slots[2]["faction"]), int(_ai_slots[2]["team"])]])
	_show_map_overlay()
	for _i in 6:
		await get_tree().process_frame
	if _shot_path != "":
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Screenshot: ", _shot_path)
	_spawn_choice = 0
	_close_map_overlay()
	print("T: Lobby — Spieler Team %d, KI-Teams %s, Startpunkt %d" % [_player_team,
		[_ai_slots[0]["team"], _ai_slots[1]["team"], _ai_slots[2]["team"]], _spawn_choice])
	_start_skirmish()


const LAYOUT_MATRIX := [
	[1096, 2560, 420], [2560, 1096, 420],
	[1080, 2400, 440], [1080, 1920, 420], [720, 1600, 320],
	[1600, 2560, 320], [2560, 1600, 320],
]
const LAYOUT_PAGES := ["main", "skirmish", "missions", "load", "options", "controls"]


func _run_test_layout() -> void:
	var lang_before := Lang.code()
	var total := 0


	var most := _selected
	for i in _skirmish.size():
		if most < 0 or int(_skirmish[i]["players"]) > int(_skirmish[most]["players"]):
			most = i
	if most >= 0:
		_on_map_selected(most)
	_set_ai(ProtoWorld.AI_PLAYER_INDICES.size())
	for lang in ["de", "en"]:
		Lang.set_language(lang)
		for e in LAYOUT_MATRIX:
			DisplayServer.window_set_size(Vector2i(e[0], e[1]))
			Dp.set_forced_dpi(float(e[2]))
			Dp.set_ui_scale(1.0)
			await get_tree().process_frame
			_rebuild_ui("main", false)
			for page in LAYOUT_PAGES:
				_show(page)
				for _i in 6:
					await get_tree().process_frame
				var real := DisplayServer.window_get_size()
				var tag := "%s %s %dx%d@%d (UI ×%.2f)" % [lang, page, real.x, real.y, e[2], Dp.ui_scale()]
				var v := LayoutCheck.violations(self, Dp.safe_rect(), tag)
				for line in v:
					print(line)
				total += v.size()
	Lang.set_language(lang_before)
	print("T: Layout-Prüfung fertig — %d Verstöße" % total)
	get_tree().quit()


var _page := "main"
var _controls_box: VBoxContainer


var _controls_return := "main"


func _rebuild_ui(page: String, refit: bool = true) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build_ui()
	_show(page, refit)


func _fit_page(page: String, tries: int = 3) -> void:
	if tries <= 0:
		return
	await get_tree().process_frame
	if _page != page:
		return
	var safe := Dp.safe_rect()
	var root: Control = _pages.get(page, null)
	if root == null:
		return
	var need := root.get_combined_minimum_size()
	var f := Dp.ui_scale()
	if (need.y > safe.size.y or need.x > safe.size.x) and f > 0.8:
		var factor := minf(safe.size.y / maxf(need.y, 1.0), safe.size.x / maxf(need.x, 1.0))
		Dp.set_ui_scale(maxf(f * clampf(factor, 0.75, 0.99), 0.8))
		_rebuild_ui(page, false)
		await _fit_page(page, tries - 1)


func _show(page: String, refit: bool = true) -> void:


	if page == "controls" and _page != "controls":
		_controls_return = _page
	_page = page
	for k in _pages:
		_pages[k].visible = k == page

	if page == "controls":
		for c in _controls_box.get_children():
			_controls_box.remove_child(c)
			c.queue_free()
		var safe := Dp.safe_rect()
		_controls_box.add_child(GestureHelp.panel(tr("menu.controls"), tr("ui.back"), func(): _show(_controls_return),
				safe.size.y - Dp.px(40), safe.size.x - Dp.px(60)))
	if refit:
		_fit_page(page)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if _page == "controls":
		_show(_controls_return)
	elif _page != "main":
		_show("main")
	else:
		get_tree().quit()


func _music_text() -> String:
	return tr("options.music_on") if Music.enabled_default else tr("options.music_off")


static func _has_tileset(t: String) -> bool:
	return FileAccess.file_exists("res://assets/atlas/atlas_%s.json" % t)


const TILESET_KEYS := {"temperat": "tileset.temperat", "snow": "tileset.snow", "desert": "tileset.desert", "interior": "tileset.interior"}


func _tileset_name(t: String) -> String:
	return tr(TILESET_KEYS[t]) if TILESET_KEYS.has(t) else t


var _map_scroll: ScrollContainer
var _slot_box: VBoxContainer
var _player_team := 0
var _spawn_choice := -1
var _map_overlay: Control


func _map_json(slug: String) -> Dictionary:
	var path := "res://assets/maps/%s.json" % slug
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _show_map_overlay() -> void:
	if _selected < 0 or _map_overlay != null:
		return
	var m: Dictionary = _skirmish[_selected]
	var slug := str(m.get("slug", ""))
	var data := _map_json(slug)
	var bounds: Array = data.get("bounds", [0, 0, int(data.get("width", 64)), int(data.get("height", 64))])
	var spawns: Array = data.get("spawns", [])
	var safe := Dp.safe_rect()
	_map_overlay = Control.new()
	_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_overlay.gui_input.connect(func(e):
		if e is InputEventScreenTouch and e.pressed:
			_close_map_overlay())
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_overlay.add_child(bg)
	var head := Label.new()
	var size_arr: Array = m.get("size", [0, 0])
	head.text = "%s — %d×%d — %d %s" % [m.get("title", slug), int(size_arr[0]), int(size_arr[1]),
			int(m.get("players", 0)), tr("lobby.slots")]
	head.add_theme_font_size_override("font_size", int(Dp.px(16)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	head.position = Vector2(safe.position.x + Dp.px(16), safe.position.y + Dp.px(8))
	head.size = Vector2(safe.size.x - Dp.px(32), Dp.px(24))
	_map_overlay.add_child(head)
	var hint := Label.new()
	hint.text = tr("lobby.map_hint")
	hint.add_theme_font_size_override("font_size", int(Dp.px(12)))
	hint.add_theme_color_override("font_color", HudTheme.TEXT)
	hint.position = Vector2(safe.position.x + Dp.px(16), safe.position.y + Dp.px(32))
	hint.size = Vector2(safe.size.x - Dp.px(32), Dp.px(20))
	_map_overlay.add_child(hint)

	var area := Rect2(safe.position + Vector2(Dp.px(16), Dp.px(58)),
			safe.size - Vector2(Dp.px(32), Dp.px(58 + 60)))
	var tex: Texture2D = _preview.texture
	var ar := 1.0
	if tex != null and tex.get_height() > 0:
		ar = float(tex.get_width()) / float(tex.get_height())
	var draw_size := Vector2(area.size.y * ar, area.size.y)
	if draw_size.x > area.size.x:
		draw_size = Vector2(area.size.x, area.size.x / ar)
	var draw_pos := area.position + (area.size - draw_size) / 2.0
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = draw_pos
	pic.size = draw_size
	_map_overlay.add_child(pic)

	var bx := float(bounds[0])
	var by := float(bounds[1])
	var bw := maxf(float(bounds[2]), 1.0)
	var bh := maxf(float(bounds[3]), 1.0)
	for i in spawns.size():
		var sp: Array = spawns[i]
		var rel := Vector2((float(sp[0]) - bx) / bw, (float(sp[1]) - by) / bh)
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(Dp.px(44), Dp.px(44))
		b.size = b.custom_minimum_size
		HudTheme.style_button(b, 14.0)
		if i == _spawn_choice:
			b.add_theme_color_override("font_color", HudTheme.GOLD)
		b.position = draw_pos + rel * draw_size - b.size / 2.0
		var idx := i
		b.pressed.connect(func():
			Sfx.click(self)
			_spawn_choice = -1 if _spawn_choice == idx else idx
			_close_map_overlay()
			_update_factions())
		_map_overlay.add_child(b)
	var back := _button(tr("ui.back"), func(): _close_map_overlay(), 140, 44)
	back.position = Vector2(safe.position.x + (safe.size.x - Dp.px(140)) / 2.0,
			safe.position.y + safe.size.y - Dp.px(52))
	back.size = Vector2(Dp.px(140), Dp.px(44))
	_map_overlay.add_child(back)
	add_child(_map_overlay)


func _close_map_overlay() -> void:
	if _map_overlay != null:
		_map_overlay.queue_free()
		_map_overlay = null

var _ai_slots: Array = []


func _slot_defaults() -> void:


	while _ai_slots.size() < ProtoWorld.AI_PLAYER_INDICES.size():
		_ai_slots.append({"faction": "random", "team": 0, "level": _ai_difficulty})


func _rebuild_slots() -> void:
	if _slot_box == null:
		return
	_slot_defaults()
	for c in _slot_box.get_children():
		_slot_box.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = tr("lobby.slots")
	head.add_theme_font_size_override("font_size", int(Dp.px(12)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	_slot_box.add_child(head)

	var me := HBoxContainer.new()
	me.add_theme_constant_override("separation", int(Dp.px(6)))
	var me_label := Label.new()
	me_label.text = tr("lobby.you")
	me_label.custom_minimum_size = Vector2(Dp.px(52), 0)
	me_label.add_theme_font_size_override("font_size", int(Dp.px(12)))
	me_label.add_theme_color_override("font_color", HudTheme.TEXT)
	me.add_child(me_label)
	me.add_child(_button(_faction_name(_faction), func():
		_faction = _next_faction_value(_faction)
		_update_factions(), 110, 34))
	me.add_child(_button(_team_name(_player_team), func():
		_player_team = (_player_team + 1) % 5
		_update_factions(), 90, 34))
	me.add_child(_button(tr("lobby.spawn") % (str(_spawn_choice + 1) if _spawn_choice >= 0 else tr("lobby.spawn_random")),
			func(): _show_map_overlay(), 140, 34))
	_slot_box.add_child(me)
	for i in _ai_players:
		var slot: Dictionary = _ai_slots[i]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", int(Dp.px(6)))
		var l := Label.new()
		l.text = tr("lobby.ai") % (i + 1)
		l.custom_minimum_size = Vector2(Dp.px(52), 0)
		l.add_theme_font_size_override("font_size", int(Dp.px(12)))
		l.add_theme_color_override("font_color", HudTheme.TEXT)
		r.add_child(l)
		var idx := i
		r.add_child(_button(_faction_name(str(slot.get("faction", "random"))), func():
			_ai_slots[idx]["faction"] = _next_faction_value(str(_ai_slots[idx].get("faction", "random")))
			_update_factions(), 110, 34))
		r.add_child(_button(_team_name(int(slot.get("team", 0))), func():
			_ai_slots[idx]["team"] = (int(_ai_slots[idx].get("team", 0)) + 1) % 5
			_update_factions(), 90, 34))
		r.add_child(_button(tr(AI_DIFFICULTY_KEYS.get(str(slot.get("level", "normal")), "menu.skirmish.ai_normal")), func():
			var d: Array = ProtoWorld.AI_DIFFICULTIES
			_ai_slots[idx]["level"] = d[(d.find(str(_ai_slots[idx].get("level", "normal"))) + 1) % d.size()]
			_update_factions(), 140, 34))
		_slot_box.add_child(r)


func _on_map_selected(i: int) -> void:
	if i != _selected:
		_spawn_choice = -1
	_selected = i
	for k in _map_buttons.size():
		_map_buttons[k].button_pressed = k == i

	if _map_scroll != null and i >= 0 and i < _map_buttons.size():
		_map_scroll.ensure_control_visible.call_deferred(_map_buttons[i])
	var m: Dictionary = _skirmish[i]
	var path := "res://assets/maps/%s.png" % m["slug"]
	_preview.texture = load(path) if ResourceLoader.exists(path) else null
	var size: Array = m.get("size", [0, 0])
	_info.text = tr("menu.skirmish.map_info") % [m["title"], int(m["players"]), _tileset_name(m["tileset"]), int(size[0]), int(size[1])]
	_set_ai(_ai_players)


func _max_ai() -> int:
	var cap: int = ProtoWorld.AI_PLAYER_INDICES.size()
	if _selected >= 0:
		return maxi(1, mini(int(_skirmish[_selected]["players"]) - 1, cap))
	return 1


func _set_ai(n: int) -> void:
	_ai_players = clampi(n, 1, _max_ai())
	if _ai_label != null:
		_ai_label.text = tr("menu.skirmish.ai_count") % _ai_players


	_update_factions()


func _set_credits(c: int) -> void:
	_credits = clampi(c, 2500, 20000)
	_credits_label.text = tr("menu.skirmish.credits") % _credits


func _start_skirmish() -> void:
	if _selected < 0:
		return
	_save_settings()
	ProtoWorld.next_map = _skirmish[_selected]["slug"]
	ProtoWorld.next_mission = ""
	ProtoWorld.next_ai_players = _ai_players
	ProtoWorld.next_credits = _credits
	ProtoWorld.next_faction = _faction
	ProtoWorld.next_ai_faction = _ai_faction
	ProtoWorld.next_starting_units = _starting_units
	ProtoWorld.next_crates = _crates
	ProtoWorld.next_explored_map = _explored_map
	ProtoWorld.next_fog = _fog
	ProtoWorld.next_ai_difficulty = _ai_difficulty
	ProtoWorld.next_player_spawn = _spawn_choice
	ProtoWorld.next_player_team = _player_team
	ProtoWorld.next_ai_slots = _ai_slots.duplicate(true)
	get_tree().change_scene_to_file(GAME_SCENE)
