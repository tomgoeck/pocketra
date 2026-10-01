

class_name UpdatePage
extends VBoxContainer


signal recheck_requested

var _note: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(Dp.px(12)))
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var info := UpdateConfig.block_info()
	var head := Label.new()
	head.text = tr("update.blocked_title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", int(Dp.px(22)))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	add_child(head)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(20.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	_note = Label.new()
	var notes := str(info.get("notes", ""))


	_note.text = notes if notes != "" else tr(UpdateConfig.blocked_default_key())
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", int(Dp.px(13)))
	_note.add_theme_color_override("font_color", HudTheme.TEXT)
	box.add_child(_note)
	add_child(panel)


	var ver := Label.new()
	ver.text = UpdateConfig.version_summary()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", int(Dp.px(11)))
	ver.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	add_child(ver)


	var apk_label := str(info.get("apk_label", ""))
	if apk_label != "":
		var flavor := Label.new()
		flavor.text = tr("update.app_new_edition") % apk_label
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.add_theme_font_size_override("font_size", int(Dp.px(11)))
		flavor.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
		add_child(flavor)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(Dp.px(8)))


	var apk_url := str(info.get("apk_url", ""))
	if apk_url != "":
		row.add_child(_btn(tr(UpdateConfig.get_app_key()), func():
			Sfx.click(self)
			OS.shell_open(apk_url)))
	row.add_child(_btn(tr("update.recheck"), func():
		Sfx.click(self)
		recheck_requested.emit()))


	if not ["Android", "iOS"].has(UpdateConfig.platform()):
		row.add_child(_btn(tr("menu.main.quit"), func():
			Sfx.click(self)
			get_tree().quit()))
	add_child(row)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(Dp.px(180), Dp.px(42))
	HudTheme.plate_button_style(b, 15.0)
	b.pressed.connect(cb)
	return b
