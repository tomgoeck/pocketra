

extends VBoxContainer

const AppLogger := preload("res://scripts/app_logger.gd")


const DEFAULT_LINES := 200

var _text: Label
var _scroll: ScrollContainer
var _hint: Label
var _lines := DEFAULT_LINES


func _init(lines_count: int = DEFAULT_LINES) -> void:
	_lines = lines_count


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", int(Dp.px(6)))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(10.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, Dp.px(120))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text = Label.new()


	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.add_theme_font_size_override("font_size", int(Dp.px(10)))
	_text.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	_scroll.add_child(_text)


	HudTheme.touch_scroll(_scroll)
	panel.add_child(_scroll)
	add_child(panel)

	_hint = Label.new()
	_hint.text = AppLogger.path()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", int(Dp.px(9)))
	_hint.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_small_button(tr("log.copy"), func(): _copy()))
	row.add_child(_small_button(tr("log.refresh"), func(): refresh()))
	add_child(row)
	refresh()


func scroll_node() -> ScrollContainer:
	return _scroll


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, Dp.px(34))
	HudTheme.plate_button_style(b, 12.0, 8.0)
	b.pressed.connect(func(): Sfx.click(self); cb.call())
	return b


func refresh() -> void:
	if _text == null:
		return
	_text.text = AppLogger.text(_lines)

	await get_tree().process_frame
	if is_inside_tree() and _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _copy() -> void:
	DisplayServer.clipboard_set(AppLogger.text(_lines))
	if _hint != null:
		_hint.text = tr("log.copied") % _lines
