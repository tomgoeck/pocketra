

class_name ContentPage
extends PanelContainer


const AppLogger := preload("res://scripts/app_logger.gd")
const LogView := preload("res://scripts/ui/log_view.gd")


const WebFiles := preload("res://scripts/content/web_files.gd")

signal back_requested

signal continue_requested


signal unlocked


const KEEP_FILES := {
	"allied": ["movies1.mix", "scores.mix"],
	"soviet": ["movies2.mix", "scores.mix"],
	"german": ["movies1.mix", "movies2.mix", "scores.mix", "sounds.mix", "allies.mix", "russian.mix"],
}


const LANG_JOB := "lang_"


const VOICE_FULL_COUNT := 277
const CD_IDS := ["allied", "soviet", "german"]
const CD_TITLE_KEYS := {"allied": "content.cd_allied", "soviet": "content.cd_soviet", "german": "content.cd_german"}

const LOG_TAG := "ContentPage"

const TEST_MODES := {
	"--test-content-ui": "ok", "--test-content-ui-cancel": "cancel",
	"--test-content-ui-badsum": "badsum", "--test-content-ui-error": "error",
	"--test-content-ui-queue": "queue", "--test-content-delete": "delete",
	"--test-music": "music", "--test-content-disclaimer": "disclaimer",
	"--test-web-paths": "webpaths",
}

const STALL_MS := 45000

const ERR_RED := Color(1.0, 0.42, 0.36)


const MIN_FONT_DP := 10.0


const TWO_COLUMN_DP := 620.0
const THREE_COLUMN_DP := 940.0

var _http: HTTPRequest
var _busy := false
var _cancel_requested := false
var _current_job := ""
var _download_target := ""
var _last_failed_job := ""


var _queue: Array[String] = []
var _queue_total := 0
var _queue_done := 0

var _freeware_status: Label
var _freeware_btn: Button
var _freeware_row: HBoxContainer
var _freeware_prog: VBoxContainer
var _cd_rows := {}

var _voice_row: HBoxContainer
var _voice_status: Label
var _voice_btn: Button
var _voice_prog: VBoxContainer
var _busy_hint: Label
var _queue_label: Label
var _continue_btn: Button
var _pick_btn: Button
var _pick_list: VBoxContainer


var _err_panel: PanelContainer
var _err_label: Label
var _err_detail: Label
var _retry_btn: Button


var _log_btn: Button
var _log_view: LogView
var _log_panel: PanelContainer
var _scroll: ScrollContainer


var _dl_last_bytes := 0
var _dl_last_ms := 0
var _dl_speed := 0.0
var _dl_started_ms := 0


var _bg_thread: Thread = null
var _bg_mutex := Mutex.new()
var _bg_stage := ""
var _bg_frac := 0.0
var _bg_detail := ""
var _bg_running := false
var _bg_result := {}
var _bg_logged_step := -1


var _bg_stepped := false


var _dl_sources: Array[String] = []
var _dl_source_index := 0


var _from_picked_file := false


var _url_override := ""
var _sha1_override := ""
var _cd_url_override := ""


static var _test_started := false

static var _test_unlocked := false
static var _test_reported := false


var _shot_dir := ""
var _shot_frames := 0
var _shot_n := 0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


	add_theme_stylebox_override("panel", HudTheme.panel_style(14.0))
	var args := OS.get_cmdline_user_args()
	var uk := args.find("--content-url")
	if uk >= 0 and uk + 1 < args.size():
		_url_override = args[uk + 1]
	var sk := args.find("--content-sha1")
	if sk >= 0 and sk + 1 < args.size():
		_sha1_override = args[sk + 1]
	var ck := args.find("--content-cd-url")
	if ck >= 0 and ck + 1 < args.size():
		_cd_url_override = args[ck + 1]
	var shk := args.find("--content-shots")
	if shk >= 0 and shk + 1 < args.size():
		_shot_dir = args[shk + 1]
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	_build_ui()
	_purge_stale_partials()
	_refresh_status()
	if _test_started:


		if _test_unlocked and not _test_reported:
			call_deferred("_report_unlocked")
		return
	for flag in TEST_MODES:
		if args.has(flag):
			_test_started = true
			call_deferred("_run_test_content_ui", TEST_MODES[flag])
			break


func _exit_tree() -> void:


	if _bg_thread != null and _bg_thread.is_started():
		_bg_thread.wait_to_finish()
		_bg_thread = null


func _bg_busy() -> bool:
	return _bg_thread != null or _bg_stepped


func _process(_dt: float) -> void:
	_maybe_shoot()
	if _bg_busy():
		_poll_background()
		return
	if not _busy or _http == null:
		return
	_poll_download()


func _maybe_shoot() -> void:
	if _shot_dir == "":
		return
	_shot_frames += 1
	if _shot_frames % 40 != 0 or not (_busy or _bg_busy()):
		return
	_shoot("%s/%02d.png" % [_shot_dir, _shot_n])
	_shot_n += 1


func _shoot(path: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.get_texture().get_image().save_png(path)
	print("Screenshot: ", path)


func _card(into: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(12.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", _font(15))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)
	into.add_child(panel)
	return box


func _font(dp: float) -> int:
	return int(round(maxf(Dp.px(dp), Dp.device_px(MIN_FONT_DP))))


func _wrapped_label(text: String, dim: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


	l.add_theme_font_size_override("font_size", _font(11))
	l.add_theme_color_override("font_color", HudTheme.TEXT_DIM if dim else HudTheme.TEXT)
	return l


func _progress_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ProgressRow"
	box.add_theme_constant_override("separation", int(Dp.px(4)))
	box.visible = false

	var phase := Label.new()
	phase.name = "Phase"
	phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase.add_theme_font_size_override("font_size", _font(13))
	phase.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(phase)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(Dp.px(100), Dp.px(18))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = HudTheme.GOLD
	fg.set_corner_radius_all(int(Dp.px(3)))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.11, 0.09, 0.9)
	bg.border_color = HudTheme.BORDER_DIM
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(Dp.px(3)))
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var pct := Label.new()
	pct.name = "Pct"
	pct.custom_minimum_size = Vector2(Dp.px(44), 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.add_theme_font_size_override("font_size", _font(12))
	pct.add_theme_color_override("font_color", HudTheme.TEXT)
	row.add_child(pct)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = tr("ui.cancel")
	HudTheme.plate_button_style(cancel, 12.0, 8.0)
	cancel.add_theme_font_size_override("font_size", _font(12.0))
	cancel.pressed.connect(func(): Sfx.click(self); _cancel_job())
	row.add_child(cancel)
	box.add_child(row)

	var detail := Label.new()
	detail.name = "Detail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", _font(11))
	detail.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(detail)
	return box


func _action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, maxf(Dp.px(36), HudTheme.min_touch_px()))
	HudTheme.plate_button_style(b, 13.0)
	b.add_theme_font_size_override("font_size", _font(13.0))
	b.pressed.connect(func(): Sfx.click(self); cb.call())
	return b


func _build_ui() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_cd_rows.clear()
	_http = HTTPRequest.new()
	_http.use_threads = true


	_http.timeout = 0.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(Dp.px(8)))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(col)

	var head := Label.new()
	head.text = tr("content.title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", _font(19))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	col.add_child(head)

	_build_error_panel(col)


	_queue_label = Label.new()
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_label.add_theme_font_size_override("font_size", _font(12))
	_queue_label.add_theme_color_override("font_color", HudTheme.GOLD)
	_queue_label.visible = false
	col.add_child(_queue_label)


	_scroll = ScrollContainer.new()
	var scroll := _scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_scrollbar(scroll)


	var vs := get_viewport().get_visible_rect().size
	var landscape := vs.x > vs.y
	var cols := 1
	if landscape and vs.x >= Dp.px(THREE_COLUMN_DP):
		cols = 3
	elif landscape and vs.x >= Dp.px(TWO_COLUMN_DP):
		cols = 2
	var inner: BoxContainer = HBoxContainer.new() if cols > 1 else VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(Dp.px(10)))
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	col.add_child(scroll)
	if cols == 3:

		var c1 := _column(inner, 1.0)
		var c2 := _column(inner, 1.15)
		var c3 := _column(inner, 1.0)
		_build_why_card(c1)
		_build_freeware_card(c1)
		_build_cd_card(c2)
		_build_pick_card(c3)
		_build_log_card(c3)
	elif cols == 2:
		var left := _column(inner, 1.0)
		var right := _column(inner, 1.15)
		_build_why_card(left)
		_build_freeware_card(left)
		_build_pick_card(left)
		_build_log_card(left)
		_build_cd_card(right)
	else:
		_build_why_card(inner)
		_build_freeware_card(inner)
		_build_cd_card(inner)
		_build_pick_card(inner)
		_build_log_card(inner)

	_busy_hint = _wrapped_label("")
	_busy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_busy_hint.visible = false
	col.add_child(_busy_hint)


	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", int(Dp.px(10)))
	_log_btn = Button.new()
	_log_btn.text = tr("content.log_show")
	_log_btn.custom_minimum_size = Vector2(Dp.px(150), maxf(Dp.px(38), HudTheme.min_touch_px()))
	HudTheme.style_button(_log_btn, 13.0)
	_log_btn.add_theme_font_size_override("font_size", _font(13.0))
	_log_btn.pressed.connect(func(): Sfx.click(self); _set_log_visible(not _log_panel.visible))
	foot.add_child(_log_btn)
	var back := Button.new()
	back.text = tr("ui.back")
	back.custom_minimum_size = Vector2(Dp.px(130), maxf(Dp.px(38), HudTheme.min_touch_px()))
	HudTheme.style_button(back, 14.0)
	back.add_theme_font_size_override("font_size", _font(14.0))
	back.pressed.connect(func(): Sfx.click(self); back_requested.emit())
	foot.add_child(back)
	_continue_btn = Button.new()
	_continue_btn.text = tr("content.continue")
	_continue_btn.custom_minimum_size = Vector2(Dp.px(130), maxf(Dp.px(38), HudTheme.min_touch_px()))
	HudTheme.style_button(_continue_btn, 14.0)
	_continue_btn.add_theme_font_size_override("font_size", _font(14.0))
	_continue_btn.pressed.connect(func(): Sfx.click(self); continue_requested.emit())
	foot.add_child(_continue_btn)
	col.add_child(foot)


	HudTheme.touch_scroll(scroll)


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(maxf(Dp.px(8), Dp.device_px(6.0)), 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.10, 0.08, 0.65)
	track.set_corner_radius_all(int(Dp.px(3)))
	var grab := StyleBoxFlat.new()
	grab.bg_color = HudTheme.BORDER_DIM
	grab.set_corner_radius_all(int(Dp.px(3)))
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = HudTheme.GOLD
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hi)


func _column(into: BoxContainer, ratio: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", int(Dp.px(10)))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	into.add_child(c)
	return c


func _build_why_card(parent: Control) -> void:
	var box := _card(parent, tr("content.why_title"))
	box.add_child(_wrapped_label(tr("content.why")))
	box.add_child(_wrapped_label(tr("content.why2")))


	box.add_child(_wrapped_label(tr("content.disclaimer_short")))


func _build_error_panel(parent: Control) -> void:
	_err_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.06, 0.05, 0.92)
	sb.border_color = ERR_RED
	sb.set_border_width_all(int(maxf(1.0, Dp.px(1.5))))
	sb.set_corner_radius_all(int(Dp.px(4)))
	sb.content_margin_left = Dp.px(10)
	sb.content_margin_right = Dp.px(10)
	sb.content_margin_top = Dp.px(8)
	sb.content_margin_bottom = Dp.px(8)
	_err_panel.add_theme_stylebox_override("panel", sb)
	_err_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_err_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_err_label = Label.new()
	_err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_err_label.add_theme_font_size_override("font_size", _font(13))
	_err_label.add_theme_color_override("font_color", ERR_RED)
	box.add_child(_err_label)
	_err_detail = Label.new()
	_err_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_err_detail.add_theme_font_size_override("font_size", _font(10))
	_err_detail.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(_err_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Dp.px(8)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_retry_btn = Button.new()
	_retry_btn.text = tr("content.retry")
	_retry_btn.custom_minimum_size = Vector2(0, maxf(Dp.px(32), HudTheme.min_touch_px()))
	HudTheme.plate_button_style(_retry_btn, 12.0, 8.0)
	_retry_btn.add_theme_font_size_override("font_size", _font(12.0))
	_retry_btn.pressed.connect(func(): Sfx.click(self); _retry())
	row.add_child(_retry_btn)
	var show_log := Button.new()
	show_log.text = tr("content.log_show")
	show_log.custom_minimum_size = Vector2(0, maxf(Dp.px(32), HudTheme.min_touch_px()))
	HudTheme.plate_button_style(show_log, 12.0, 8.0)
	show_log.add_theme_font_size_override("font_size", _font(12.0))
	show_log.pressed.connect(func(): Sfx.click(self); _set_log_visible(true))
	row.add_child(show_log)
	box.add_child(row)
	_err_panel.add_child(box)
	parent.add_child(_err_panel)


func _build_freeware_card(parent: Control) -> void:
	var box := _card(parent, tr("content.freeware_title"))
	box.add_child(_wrapped_label(tr("content.freeware_hint"), false))


	box.add_child(_wrapped_label(tr("content.freeware_src_web" if ContentManager.web() else "content.freeware_src")))
	_freeware_row = HBoxContainer.new()
	_freeware_row.add_theme_constant_override("separation", int(Dp.px(8)))
	_freeware_status = _wrapped_label("", false)
	_freeware_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_freeware_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_freeware_row.add_child(_freeware_status)
	_freeware_btn = _action_button("", func(): _on_freeware_button())
	_freeware_row.add_child(_freeware_btn)
	box.add_child(_freeware_row)
	_freeware_prog = _progress_box()
	box.add_child(_freeware_prog)


func _build_cd_card(parent: Control) -> void:
	var box := _card(parent, tr("content.cd_title"))
	box.add_child(_wrapped_label(tr("content.cd_hint"), false))


	if not ContentManager.cd_downloads_supported():
		box.add_child(_wrapped_label(tr("content.cd_web_unavailable")))
		return
	box.add_child(_wrapped_label(tr("content.cd_src")))
	for id in CD_IDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(Dp.px(8)))


		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", int(Dp.px(1)))
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_lbl := _wrapped_label(tr(CD_TITLE_KEYS[id]), false)
		texts.add_child(name_lbl)
		var what := _wrapped_label(tr("content.cd_" + id + "_what"))
		what.add_theme_font_size_override("font_size", _font(10))
		texts.add_child(what)
		var status := _wrapped_label("", false)
		texts.add_child(status)
		row.add_child(texts)
		var btn := _action_button("", func(): _on_cd_button(id))
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		box.add_child(row)
		var prog := _progress_box()
		box.add_child(prog)
		_cd_rows[id] = {"status": status, "btn": btn, "row": row, "prog": prog}
	_build_voice_row(box)


func _build_voice_row(box: Control) -> void:
	_voice_row = HBoxContainer.new()
	_voice_row.add_theme_constant_override("separation", int(Dp.px(8)))
	_voice_status = _wrapped_label("", false)
	_voice_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_row.add_child(_voice_status)
	_voice_btn = _action_button(tr("content.voice_build"), func(): _on_voice_button())
	_voice_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_row.add_child(_voice_btn)
	box.add_child(_voice_row)
	_voice_prog = _progress_box()
	box.add_child(_voice_prog)


func _build_pick_card(parent: Control) -> void:


	var web := ContentManager.web()
	var box := _card(parent, tr("content.pick_title_web" if web else "content.pick_title"))
	box.add_child(_wrapped_label(tr("content.pick_hint_web" if web else "content.pick_hint")))
	if _native_dialog_available():
		_pick_btn = _action_button(tr("content.pick_file_web" if web else "content.pick_file"),
				func(): _on_pick_file())
		box.add_child(_pick_btn)
	else:
		box.add_child(_wrapped_label(tr("content.pick_folder_hint") % _pick_folder_display()))
		_pick_btn = _action_button(tr("content.pick_scan"), func(): _on_scan_folder())
		box.add_child(_pick_btn)
	_pick_list = VBoxContainer.new()
	_pick_list.add_theme_constant_override("separation", int(Dp.px(4)))
	box.add_child(_pick_list)
	box.add_child(_wrapped_label(tr("content.lang_hint")))


func _build_log_card(parent: Control) -> void:
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", HudTheme.panel_style(12.0))
	_log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(6)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_panel.add_child(box)
	var head := Label.new()
	head.text = tr("log.title")
	head.add_theme_font_size_override("font_size", _font(15))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)
	_log_view = LogView.new()
	_log_view.custom_minimum_size = Vector2(0, Dp.px(150))
	box.add_child(_log_view)
	parent.add_child(_log_panel)


func _set_log_visible(on: bool) -> void:
	if _log_view == null or _log_panel == null:
		return
	_log_panel.visible = on
	_log_view.visible = on
	if _log_btn != null:
		_log_btn.text = tr("content.log_hide") if on else tr("content.log_show")
	if on:
		_log_view.refresh()


func _prog_for(job: String) -> VBoxContainer:
	if job == "freeware":
		return _freeware_prog
	if job.begins_with(LANG_JOB):
		return _voice_prog
	if job.begins_with("cd_"):
		var id := job.substr(3)
		if _cd_rows.has(id):
			return _cd_rows[id]["prog"]


		return _freeware_prog
	return null


func _row_visible_for(job: String, on: bool) -> void:
	var prog := _prog_for(job)
	if prog != null:
		prog.visible = on
	if job == "freeware":
		if _freeware_row != null:
			_freeware_row.visible = not on
	elif job.begins_with("cd_") and not _cd_rows.has(job.substr(3)):

		if _freeware_row != null:
			_freeware_row.visible = not on
	elif job.begins_with(LANG_JOB):
		if _voice_row != null:
			_voice_row.visible = not on
	elif job.begins_with("cd_"):
		var id := job.substr(3)
		if _cd_rows.has(id):
			_cd_rows[id]["row"].visible = not on


func _set_progress(phase: String, frac: float, detail: String, cancelable: bool = true) -> void:
	var prog := _prog_for(_current_job)
	if prog == null:
		return
	prog.get_node("Phase").text = phase
	var bar: ProgressBar = prog.get_node("Row/Bar")
	var pct: Label = prog.get_node("Row/Pct")
	if frac >= 0.0:
		bar.value = clampf(frac, 0.0, 1.0) * 100.0
		pct.text = "%d %%" % int(clampf(frac, 0.0, 1.0) * 100.0)
	else:
		bar.value = 0.0
		pct.text = ""
	prog.get_node("Detail").text = detail
	var cancel: Button = prog.get_node("Row/Cancel")
	cancel.disabled = not cancelable


func _show_error(msg: String, detail: String, job: String) -> void:
	_last_failed_job = job
	if _err_panel == null:
		return
	_err_label.text = msg
	_err_detail.text = detail
	_err_detail.visible = detail != ""
	_retry_btn.visible = job != ""
	_err_panel.visible = true


func _clear_error() -> void:
	_last_failed_job = ""
	if _err_panel != null:
		_err_panel.visible = false


func _retry() -> void:
	var job := _last_failed_job
	_clear_error()
	if job == "":
		return
	_enqueue(job)


var _disclaimer: Control = null
var _disclaimer_job := ""


func _needs_disclaimer(job: String) -> bool:
	if ContentManager.disclaimer_accepted():
		return false
	_show_disclaimer(job)
	return true


func show_disclaimer() -> void:
	_show_disclaimer("")


func _show_disclaimer(job: String) -> void:
	_disclaimer_job = job
	if _disclaimer != null and is_instance_valid(_disclaimer):
		_disclaimer.queue_free()
	var nur_lesen := job == "" and ContentManager.disclaimer_accepted()
	AppLogger.info(LOG_TAG, "Haftungsausschluss gezeigt (%s)" % ("nur lesen" if nur_lesen else "vor " + job))
	_disclaimer = Control.new()
	_disclaimer.name = "Disclaimer"
	_disclaimer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_disclaimer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disclaimer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disclaimer.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(14.0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(Dp.px(8)))
	panel.add_child(box)

	var head := Label.new()
	head.text = tr("content.disclaimer_title")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", _font(17))
	head.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(head)


	var safe := Dp.safe_rect()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(minf(Dp.px(460), safe.size.x - Dp.px(70)),
			minf(Dp.px(300), safe.size.y * 0.52))
	_style_scrollbar(scroll)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", int(Dp.px(7)))
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in ["content.disclaimer_1", "content.disclaimer_2", "content.disclaimer_3",
			"content.disclaimer_4", "content.disclaimer_5", "content.disclaimer_6"]:
		var l := _wrapped_label(tr(key), false)
		l.custom_minimum_size = Vector2(scroll.custom_minimum_size.x - Dp.px(14), 0)
		l.add_theme_font_size_override("font_size", _font(12))
		texts.add_child(l)
	scroll.add_child(texts)
	HudTheme.touch_scroll(scroll)
	box.add_child(scroll)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(Dp.px(10)))
	if nur_lesen:
		_disclaimer_ok = _action_button(tr("content.disclaimer_close"), func(): _close_disclaimer())
		row.add_child(_disclaimer_ok)
	else:
		_disclaimer_ok = _action_button(tr("content.disclaimer_accept"), func(): _accept_disclaimer())
		row.add_child(_disclaimer_ok)
		_disclaimer_cancel = _action_button(tr("ui.cancel"), func():
			AppLogger.info(LOG_TAG, "Haftungsausschluss abgelehnt — kein Download")
			_disclaimer_job = ""
			_close_disclaimer())
		row.add_child(_disclaimer_cancel)
	box.add_child(row)


var _disclaimer_ok: Button
var _disclaimer_cancel: Button


func _accept_disclaimer() -> void:
	ContentManager.set_disclaimer_accepted(true)
	AppLogger.info(LOG_TAG, "Haftungsausschluss angenommen")
	var job := _disclaimer_job
	_disclaimer_job = ""
	_close_disclaimer()
	if job != "":
		_enqueue(job)


func _close_disclaimer() -> void:
	if _disclaimer != null and is_instance_valid(_disclaimer):
		_disclaimer.queue_free()
	_disclaimer = null
	_disclaimer_ok = null
	_disclaimer_cancel = null


func close_disclaimer() -> void:
	_disclaimer_job = ""
	_close_disclaimer()


func disclaimer_visible() -> bool:
	return _disclaimer != null and is_instance_valid(_disclaimer) and _disclaimer.visible


func _enqueue(job: String) -> void:
	if job == _current_job or _queue.has(job):
		return


	if _needs_disclaimer(job):
		return
	if job.begins_with("cd_") and not _check_free_space():
		return
	_queue.append(job)
	if not _busy and _queue_total == 0:
		_queue_done = 0
	_queue_total += 1
	AppLogger.info(LOG_TAG, "Auftrag eingereiht: %s (%d in der Warteschlange)" % [job, _queue.size()])
	_refresh_status()
	_update_queue_label()
	if not _busy:
		_start_next()


func _start_next() -> void:
	if _queue.is_empty():
		_queue_total = 0
		_queue_done = 0
		_update_queue_label()
		_refresh_status()
		return
	var job := str(_queue.pop_front())
	_update_queue_label()
	if job == "freeware":
		_start_freeware_download()
	elif job.begins_with("cd_"):
		_start_cd_download(job.substr(3))


func _update_queue_label() -> void:
	if _queue_label == null:
		return
	if _queue_total <= 1:
		_queue_label.visible = false
		return
	_queue_label.visible = true
	_queue_label.text = tr("content.queue_pos") % [mini(_queue_done + 1, _queue_total), _queue_total]


func _clear_queue() -> void:
	if not _queue.is_empty():
		AppLogger.info(LOG_TAG, "Warteschlange verworfen (%d Aufträge)" % _queue.size())
	_queue.clear()
	_queue_total = 0
	_queue_done = 0
	_update_queue_label()


func refresh_status() -> void:
	_refresh_status()


func _refresh_status() -> void:


	if _bg_busy():
		return
	if ContentManager.dev_bundled():
		_freeware_status.text = tr("content.dev_bundled")
		_freeware_btn.visible = false
	elif ContentManager.has_freeware():
		var c := ContentManager.component("freeware")
		_freeware_status.text = tr("content.installed") % ContentManager.format_mb(int(c.get("size_bytes", 0)))
		_freeware_btn.text = tr("content.delete")
		_freeware_btn.visible = true
		_freeware_btn.disabled = false
	elif _queue.has("freeware"):
		_freeware_status.text = tr("content.queued")
		_freeware_btn.text = tr("content.freeware_get") if not ContentManager.freeware_download_supported() else tr("content.download") % ("%.1f" % ContentManager.FREEWARE_LABEL_MB)
		_freeware_btn.visible = true
		_freeware_btn.disabled = true
	else:
		_freeware_status.text = tr("content.not_installed")
		_freeware_btn.text = tr("content.freeware_get") if not ContentManager.freeware_download_supported() else tr("content.download") % ("%.1f" % ContentManager.FREEWARE_LABEL_MB)
		_freeware_btn.visible = true
		_freeware_btn.disabled = false
	for id in _cd_rows.keys():
		var r: Dictionary = _cd_rows[id]
		var job := "cd_" + str(id)
		if ContentManager.has_cd(id):
			var c := ContentManager.component(job)
			r["status"].text = tr("content.installed") % ContentManager.format_mb(int(c.get("size_bytes", 0)))
			r["btn"].text = tr("content.delete")
			r["btn"].disabled = false
		elif _queue.has(job):
			r["status"].text = tr("content.queued")
			r["btn"].text = tr("content.cd_download")
			r["btn"].disabled = true
		else:
			r["status"].text = tr("content.not_installed")
			r["btn"].text = tr("content.cd_download")
			r["btn"].disabled = false
	_refresh_voice_row()
	if _continue_btn != null:


		_continue_btn.disabled = not ContentManager.available()


func _refresh_voice_row() -> void:
	if _voice_status == null:
		return
	var lang := "de"
	var n := ContentManager.sfx_lang_count(lang)
	var have_cd := ContentManager.lang_source_dir(lang) != ""
	if n > 0:
		_voice_status.text = tr("content.voice_de") % n
	elif have_cd:
		_voice_status.text = tr("content.voice_missing")
	else:
		_voice_status.text = tr("content.voice_en")
	_voice_btn.visible = have_cd
	_voice_btn.disabled = _busy or _bg_busy()
	_voice_btn.text = tr("content.voice_rebuild") if n > 0 else tr("content.voice_build")


func _on_freeware_button() -> void:
	if ContentManager.has_freeware():
		AppLogger.info(LOG_TAG, "Freeware-Paket wird gelöscht")
		ContentManager.delete_freeware()
		_content_changed()
		_clear_error()
		_refresh_status()
		return


	if not ContentManager.freeware_download_supported():
		AppLogger.info(LOG_TAG, "Freeware-Paket wird vom Browser geladen: %s" % ContentManager.FREEWARE_URL)
		WebFiles.download(ContentManager.FREEWARE_URL, "ra-quickinstall.zip")
		return
	_enqueue("freeware")


func _freeware_sources() -> Array[String]:
	if _url_override != "":
		var one: Array[String] = [_url_override]
		return one
	return ContentManager.freeware_sources()


func _start_freeware_download() -> void:
	_clear_error()
	_busy = true
	_cancel_requested = false
	_current_job = "freeware"
	_row_visible_for("freeware", true)
	_dl_sources = _freeware_sources()
	_dl_source_index = 0
	if _dl_sources.is_empty():


		AppLogger.warn(LOG_TAG, "Keine erreichbare Quelle für das Freeware-Paket")
		_job_failed(tr("content.err_no_source"), "", "freeware")
		return
	_request_freeware_source()


func _request_freeware_source() -> void:
	_reset_download_stats()
	ContentManager.ensure_dir("user://content")
	_download_target = "user://content/freeware_download.zip.tmp"
	_drop_partial(_download_target)
	var url: String = _dl_sources[_dl_source_index]
	_set_progress(tr("content.phase_download"), -1.0, url)
	AppLogger.info(LOG_TAG, "Freeware-Download startet (Quelle %d von %d): %s" % [
		_dl_source_index + 1, _dl_sources.size(), url])
	_set_download_target()
	var err := _http.request(url)
	if err != OK:
		AppLogger.warn(LOG_TAG, "HTTPRequest.request() = %d für %s" % [err, url])
		if _next_freeware_source():
			return
		_job_failed(tr("content.err_request") % err, "%s (Error %d)" % [url, err], "freeware")


func _next_freeware_source() -> bool:
	if _dl_source_index + 1 >= _dl_sources.size():
		return false
	_dl_source_index += 1
	AppLogger.info(LOG_TAG, "Quelle nicht erreichbar — nächste wird versucht")
	_request_freeware_source()
	return true


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _current_job == "":
		return
	var job := _current_job
	if _cancel_requested:
		_cleanup_tmp()
		_job_done(false, tr("content.cancelled"))
		return
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 0):
		var got := 0
		if _download_target != "":
			var f := FileAccess.open(ProjectSettings.globalize_path(_download_target), FileAccess.READ)
			if f != null:
				got = int(f.get_length())
				f.close()
		_cleanup_tmp()
		AppLogger.warn(LOG_TAG, "Download fehlgeschlagen (Ergebnis %d, Code %d, %d Byte geladen)" % [result, code, got])
		if job == "freeware" and _next_freeware_source():
			return
		var msg := ContentManager.http_error_text(result, code)


		if job == "freeware" and ContentManager.web():
			msg = tr("content.err_web_download")
		_job_failed(msg, tr("content.err_code") % [result, code], job)
		return
	AppLogger.info(LOG_TAG, "Download fertig (%s)" % _current_job)


	if ContentManager.web() and not _store_downloaded_body(body):
		_cleanup_tmp()
		if job == "freeware" and _next_freeware_source():
			return
		_job_failed(tr("content.err_web_download"), tr("content.err_code") % [result, code], job)
		return
	if job == "freeware":
		_start_freeware_processing()
	elif job.begins_with("cd_"):
		_start_cd_processing(job.substr(3), ProjectSettings.globalize_path(_download_target), true)


func _set_download_target() -> void:
	_http.download_file = "" if ContentManager.web() else ProjectSettings.globalize_path(_download_target)


func _store_downloaded_body(body: PackedByteArray) -> bool:
	if body.is_empty():
		AppLogger.warn(LOG_TAG, "Antwort ohne Inhalt — nichts zu speichern")
		return false
	var f := FileAccess.open(_download_target, FileAccess.WRITE)
	if f == null:
		AppLogger.warn(LOG_TAG, "Zieldatei nicht schreibbar: %s" % _download_target)
		return false
	f.store_buffer(body)
	f.close()
	AppLogger.info(LOG_TAG, "%s aus der Antwort nach %s geschrieben" % [
		ContentManager.format_mb(body.size()), _download_target])
	return true


func _cleanup_tmp() -> void:
	var abs := ProjectSettings.globalize_path(_download_target)
	if _download_target != "" and FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	_download_target = ""


func _drop_partial(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		return
	var size := 0
	var f := FileAccess.open(abs, FileAccess.READ)
	if f != null:
		size = int(f.get_length())
		f.close()
	DirAccess.remove_absolute(abs)
	AppLogger.info(LOG_TAG, "Teil-Download verworfen: %s (%s)" % [path.get_file(), ContentManager.format_mb(size)])


func _purge_stale_partials() -> void:
	var d := DirAccess.open(ContentManager.ROOT)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".tmp"):
			_drop_partial(ContentManager.ROOT.path_join(f))
		f = d.get_next()
	d.list_dir_end()


func _reset_download_stats() -> void:
	_dl_last_bytes = 0
	_dl_last_ms = Time.get_ticks_msec()
	_dl_started_ms = _dl_last_ms
	_dl_speed = 0.0


func _poll_download() -> void:
	var total := _http.get_body_size()
	var got := _http.get_downloaded_bytes()
	var now := Time.get_ticks_msec()
	if got > _dl_last_bytes:
		var dt := float(now - _dl_last_ms) / 1000.0
		if dt > 0.25:
			var inst := float(got - _dl_last_bytes) / dt
			_dl_speed = inst if _dl_speed <= 0.0 else lerpf(_dl_speed, inst, 0.3)
			_dl_last_bytes = got
			_dl_last_ms = now
	elif now - _dl_last_ms > STALL_MS:


		var job := _current_job
		_cancel_requested = true
		_http.cancel_request()
		_cleanup_tmp()
		AppLogger.warn(LOG_TAG, "Download steht seit %d s still — abgebrochen" % int(STALL_MS / 1000))
		_job_failed(tr("content.err_stalled") % int(STALL_MS / 1000), "", job)
		return
	var detail := ""
	if total > 0:
		detail = "%s / %s" % [ContentManager.format_mb(got), ContentManager.format_mb(total)]
	else:
		detail = ContentManager.format_mb(got)
	if _dl_speed > 0.0:
		detail += "  ·  " + tr("content.speed") % ContentManager.format_mb(int(_dl_speed))
	_set_progress(tr("content.phase_download"), (float(got) / float(total)) if total > 0 else -1.0, detail)


static func _tt(key: String) -> String:
	return String(TranslationServer.translate(key))


func _bg_progress(stage: String, fraction: float, detail: String) -> void:
	_bg_mutex.lock()
	_bg_stage = stage
	_bg_frac = fraction
	_bg_detail = detail
	_bg_mutex.unlock()


func _bg_set(stage: String, fraction: float, detail: String) -> void:
	_bg_progress(stage, fraction, detail)


func _bg_finish(result: Dictionary) -> void:
	_bg_mutex.lock()
	_bg_result = result
	_bg_running = false
	_bg_mutex.unlock()


func _bg_begin(first_phase: String) -> void:
	_bg_mutex.lock()
	_bg_stage = ""
	_bg_frac = -1.0
	_bg_detail = ""
	_bg_result = {}
	_bg_running = true
	_bg_mutex.unlock()
	_bg_logged_step = -1
	_set_progress(first_phase, -1.0, "", false)


func _start_bg(job_fn: Callable, first_phase: String) -> void:
	_bg_begin(first_phase)


	if ContentManager.single_threaded():
		AppLogger.info(LOG_TAG, "Keine Threads (Browser) — Bau läuft blockierend")
		job_fn.call()
		_finish_bg()
		return
	_bg_thread = Thread.new()
	if _bg_thread.start(job_fn) != OK:


		AppLogger.warn(LOG_TAG, "Thread.start() fehlgeschlagen — Bau läuft blockierend im Hauptthread")
		_bg_thread = null
		job_fn.call()
		_finish_bg()


func _start_bg_stepped(job_fn: Callable, first_phase: String) -> void:
	_bg_begin(first_phase)
	_bg_stepped = true
	job_fn.call()


func _bg_yield() -> void:
	await get_tree().process_frame


func _poll_background() -> void:
	_bg_mutex.lock()
	var stage := _bg_stage
	var frac := _bg_frac
	var detail := _bg_detail
	var running := _bg_running
	_bg_mutex.unlock()
	_set_progress(_phase_text(stage, detail), frac, detail, false)
	var step := int(frac * 10.0)
	if step != _bg_logged_step and frac >= 0.0:
		_bg_logged_step = step
		AppLogger.info(LOG_TAG, "%s %d %% %s" % [stage, int(frac * 100.0), detail])
	if running:
		return
	if _bg_thread != null:
		_bg_thread.wait_to_finish()
		_bg_thread = null
	_bg_stepped = false
	_finish_bg()


func _phase_text(stage: String, detail: String) -> String:
	match stage:
		"sha1":
			return tr("content.phase_checksum")
		"zip":
			return tr("content.phase_unzip")
		"atlas":

			var set_name := detail.split(":")[0].strip_edges()
			return tr("content.phase_atlas") % set_name if set_name != "" else tr("content.phase_atlas") % "…"
		"sfx":
			return tr("content.phase_sfx")
		"iso":
			return tr("content.phase_iso")
		"copy":

			return tr("content.phase_copy")
	return tr("content.phase_unzip")


func _finish_bg() -> void:
	_bg_mutex.lock()
	var res := _bg_result.duplicate(true)
	_bg_mutex.unlock()
	if _current_job == "freeware":
		_finish_freeware_assets(res)
	elif _current_job.begins_with(LANG_JOB):
		_finish_language_sounds(_current_job.substr(LANG_JOB.length()), res)
	elif _current_job.begins_with("cd_"):
		_finish_cd_component(_current_job.substr(3), res)


func _start_freeware_processing() -> void:

	if ContentManager.single_threaded():
		_start_bg_stepped(_web_freeware, tr("content.phase_checksum"))
		return
	_start_bg(_bg_freeware, tr("content.phase_checksum"))


func _bg_freeware() -> void:
	var abs := ProjectSettings.globalize_path(_download_target)
	var expect := _sha1_override if _sha1_override != "" else ContentManager.FREEWARE_SHA1
	_bg_set("sha1", -1.0, "")
	var got := ContentManager.sha1_hex(abs)
	if got != expect:
		AppLogger.warn(LOG_TAG, "Prüfsumme falsch: erwartet %s, gelesen %s" % [expect, got])
		_bg_finish({"ok": false, "msg": _tt("content.err_checksum") % [expect, got], "detail": abs.get_file()})
		return

	_bg_set("zip", 0.0, "")
	var zip := ZIPReader.new()
	if zip.open(abs) != OK:
		AppLogger.warn(LOG_TAG, "ZIPReader.open fehlgeschlagen: %s" % abs)
		_bg_finish({"ok": false, "msg": _tt("content.err_zip"), "detail": abs.get_file()})
		return
	ContentManager.ensure_dir(ContentManager.MIX_DIR)
	var files := zip.get_files()
	var count := 0
	for i in files.size():
		var path := files[i]
		if path.ends_with("/"):
			continue
		_bg_set("zip", float(i) / float(maxi(1, files.size())), path)
		var data := zip.read_file(path)


		var out_path := ContentManager.MIX_DIR.path_join(path)
		var out_abs := ProjectSettings.globalize_path(out_path)
		ContentManager.ensure_dir(out_abs.get_base_dir())
		var f := FileAccess.open(out_abs, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(data)
		f.close()
		count += 1
	zip.close()
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	AppLogger.info(LOG_TAG, "%d Dateien nach %s entpackt" % [count, ContentManager.MIX_DIR])
	if count == 0:
		_bg_finish({"ok": false, "msg": _tt("content.err_zip"), "detail": ""})
		return
	if not ContentBackend.available():


		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": "", "mix_count": count})
		return
	_bg_set("atlas", 0.0, "")
	var atlas_ok := ContentBackend.build_atlases(ContentManager.MIX_DIR, ContentManager.ATLAS_DIR, _bg_progress)
	if not atlas_ok:
		var e := ContentBackend.last_error()
		AppLogger.warn(LOG_TAG, "build_atlases fehlgeschlagen: %s" % e)
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": e, "mix_count": count})
		return
	_bg_set("sfx", 0.0, "")
	var sfx_ok := ContentBackend.convert_sounds(ContentManager.MIX_DIR, ContentManager.SFX_DIR,
			PackedStringArray(), "", _bg_progress)
	if not sfx_ok:
		AppLogger.warn(LOG_TAG, "convert_sounds: %s (Atlanten trotzdem übernommen)" % ContentBackend.last_error())
	_bg_finish({"ok": true, "mix_count": count, "sfx_ok": sfx_ok})


func _web_freeware() -> void:
	var abs := ProjectSettings.globalize_path(_download_target)
	var expect := _sha1_override if _sha1_override != "" else ContentManager.FREEWARE_SHA1
	var got := await _web_sha1(abs)
	if got != expect:
		if _from_picked_file:


			AppLogger.warn(LOG_TAG, "Prüfsumme der gewählten Datei weicht ab (%s statt %s) — wird trotzdem gelesen" % [got, expect])
		else:
			AppLogger.warn(LOG_TAG, "Prüfsumme falsch: erwartet %s, gelesen %s" % [expect, got])
			_bg_finish({"ok": false, "msg": _tt("content.err_checksum") % [expect, got], "detail": abs.get_file()})
			return

	_bg_set("zip", 0.0, "")
	await _bg_yield()
	var zip := ZIPReader.new()
	if zip.open(abs) != OK:
		AppLogger.warn(LOG_TAG, "ZIPReader.open fehlgeschlagen: %s" % abs)
		_bg_finish({"ok": false, "msg": _tt("content.err_zip"), "detail": abs.get_file()})
		return
	ContentManager.ensure_dir(ContentManager.MIX_DIR)
	var files := zip.get_files()
	var count := 0
	for i in files.size():
		var path := files[i]
		if path.ends_with("/"):
			continue
		_bg_set("zip", float(i) / float(maxi(1, files.size())), path)
		await _bg_yield()
		var data := zip.read_file(path)
		var out_abs := ProjectSettings.globalize_path(ContentManager.MIX_DIR.path_join(path))
		ContentManager.ensure_dir(out_abs.get_base_dir())
		var f := FileAccess.open(out_abs, FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(data)
		f.close()
		count += 1
	zip.close()
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	AppLogger.info(LOG_TAG, "%d Dateien nach %s entpackt" % [count, ContentManager.MIX_DIR])
	if count == 0:
		_bg_finish({"ok": false, "msg": _tt("content.err_zip"), "detail": ""})
		return
	if not ContentBackend.available():
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": "", "mix_count": count})
		return


	ContentBackend.set_web_pages(true)


	ContentBackend.reset_built()
	if ContentBackend.open_dir(ContentManager.MIX_DIR) == 0:
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"),
				"detail": ContentBackend.last_error(), "mix_count": count})
		return
	var tilesets := ["temperat", "snow", "interior"]
	for i in tilesets.size():
		var base := float(i) / float(tilesets.size())
		_bg_set("atlas", base, tilesets[i])
		await _bg_yield()
		ContentBackend.set_tilesets(PackedStringArray([tilesets[i]]))


		var ok := ContentBackend.build_atlases("", ContentManager.ATLAS_DIR,
				func(stage: String, frac: float, detail: String) -> void:
					_bg_progress(stage, base + maxf(frac, 0.0) / float(tilesets.size()), detail))
		if not ok:
			var e := ContentBackend.last_error()
			AppLogger.warn(LOG_TAG, "build_atlases(%s) fehlgeschlagen: %s" % [tilesets[i], e])
			ContentBackend.set_tilesets(PackedStringArray(tilesets))
			_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": e, "mix_count": count})
			return
		await _bg_yield()
	ContentBackend.set_tilesets(PackedStringArray(tilesets))


	var names := _sound_names()
	var sfx_ok := false
	var step := 40
	var done := 0
	while done < names.size():
		var slice := PackedStringArray(names.slice(done, mini(done + step, names.size())))
		_bg_set("sfx", float(done) / float(maxi(1, names.size())), "")
		await _bg_yield()
		if ContentBackend.convert_sounds("", ContentManager.SFX_DIR, slice, "", Callable()):
			sfx_ok = true
		done += step
	if not sfx_ok:
		AppLogger.warn(LOG_TAG, "convert_sounds: %s (Atlanten trotzdem übernommen)" % ContentBackend.last_error())
	_bg_finish({"ok": true, "mix_count": count, "sfx_ok": sfx_ok})


func _web_sha1(path_abs: String) -> String:
	var f := FileAccess.open(path_abs, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	var total := int(f.get_length())
	var done := 0
	while done < total:
		var budget := 0
		while budget < 2 * 1024 * 1024 and done < total:
			var chunk := f.get_buffer(65536)
			if chunk.is_empty():
				done = total
				break
			ctx.update(chunk)
			budget += chunk.size()
			done += chunk.size()
		_bg_set("sha1", float(done) / float(maxi(1, total)), "")
		await _bg_yield()
	f.close()
	return ctx.finish().hex_encode()


func _sound_names() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists("res://data/sounds.txt"):
		return out
	for line in FileAccess.get_file_as_string("res://data/sounds.txt").split("\n", false):
		var t := line.strip_edges()
		if t != "" and not t.begins_with("#"):
			out.append(t)
	return out


func _finish_freeware_assets(res: Dictionary) -> void:
	_download_target = ""
	if not bool(res.get("ok", false)):
		_job_failed(str(res.get("msg", tr("content.err_backend"))), str(res.get("detail", "")), "freeware")
		return
	ContentBackend.write_manifest(ContentManager.ROOT, {"freeware_sha1":
			_sha1_override if _sha1_override != "" else ContentManager.FREEWARE_SHA1})
	var total_size := ContentManager.dir_size_bytes(ContentManager.ATLAS_DIR) + ContentManager.dir_size_bytes(ContentManager.SFX_DIR)


	ContentManager.set_component("freeware", {
		"installed": true,
		"sha1": _sha1_override if _sha1_override != "" else ContentManager.FREEWARE_SHA1,
		"installed_at": int(Time.get_unix_time_from_system()),
		"size_bytes": total_size,
		"verify_files": [],
	})
	AppLogger.info(LOG_TAG, "Freeware-Paket eingerichtet (%s)" % ContentManager.format_mb(total_size))
	_content_changed()
	_job_done(true, tr("content.done"))


	_test_unlocked = true


	if _queue.is_empty():
		unlocked.emit()


func _on_cd_button(id: String) -> void:
	if ContentManager.has_cd(id):
		AppLogger.info(LOG_TAG, "CD-Inhalt %s wird gelöscht" % id)
		ContentManager.delete_cd(id)
		_content_changed()
		_clear_error()
		_refresh_status()
		return
	_enqueue("cd_" + id)


func _content_changed() -> void:
	ContentPaths.refresh()
	var mp := get_node_or_null("/root/MusicPlayer")
	if mp != null:
		mp.rebuild()


func _check_free_space() -> bool:
	var free := ContentManager.free_space_bytes(ContentManager.ROOT)
	var need := ContentManager.CD_MIN_FREE_BYTES
	if free < 0:
		_busy_hint.text = tr("content.space_unknown") % ContentManager.format_mb(need)
		_busy_hint.visible = true
		AppLogger.info(LOG_TAG, "Freier Speicher nicht ermittelbar — Prüfung übersprungen")
		return true
	if free < need:
		AppLogger.warn(LOG_TAG, "Zu wenig Speicher: %s frei, nötig %s" % [
			ContentManager.format_mb(free), ContentManager.format_mb(need)])
		_show_error(tr("content.err_space") % [ContentManager.format_mb(free), ContentManager.format_mb(need)],
				"", "")
		return false
	AppLogger.info(LOG_TAG, "Freier Speicher: %s (nötig %s)" % [
		ContentManager.format_mb(free), ContentManager.format_mb(need)])
	return true


func _start_cd_download(id: String) -> void:
	_clear_error()
	if not _check_free_space():
		_job_done(false, "")
		return
	_busy = true
	_cancel_requested = false
	_current_job = "cd_" + id
	_row_visible_for(_current_job, true)
	_reset_download_stats()
	ContentManager.ensure_dir(ContentManager.ROOT)
	_download_target = "user://content/%s_download.iso.tmp" % id
	_drop_partial(_download_target)
	var url: String = _cd_url_override if _cd_url_override != "" else str(ContentManager.CD_URLS[id])
	_set_progress(tr("content.phase_download"), -1.0, url)
	AppLogger.info(LOG_TAG, "CD-Download %s startet: %s" % [id, url])


	_set_download_target()
	var err := _http.request(url)
	if err != OK:
		AppLogger.warn(LOG_TAG, "HTTPRequest.request() = %d für %s" % [err, url])
		_job_failed(tr("content.err_request") % err, "Error %d" % err, _current_job)


func _start_cd_processing(id: String, iso_abs: String, delete_after: bool) -> void:
	if not _busy:
		_busy = true
		_current_job = "cd_" + id
		_cancel_requested = false
		_row_visible_for(_current_job, true)
	_start_bg(_bg_cd_import.bind(id, iso_abs, delete_after), tr("content.phase_iso"))


func _bg_cd_import(id: String, iso_abs: String, delete_after: bool) -> void:
	if not ContentBackend.available():
		_delete_iso(iso_abs, delete_after)
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": "", "kept": []})
		return
	var wanted := ["MAIN.MIX"]
	if id == "german":
		wanted.append("INSTALL/REDALERT.MIX")
	var out_dir := ContentManager.CD_DIR.path_join(id)
	ContentManager.ensure_dir(out_dir)
	var main_mix := out_dir.path_join("MAIN.MIX")
	var iso_ok := true
	for entry in wanted:
		var target := out_dir.path_join(entry.get_file())
		_bg_set("iso", -1.0, entry)
		if not ContentBackend.iso_extract(iso_abs, entry, target, _bg_progress):
			AppLogger.warn(LOG_TAG, "iso_extract(%s): %s" % [entry, ContentBackend.last_error()])
			iso_ok = iso_ok and entry != "MAIN.MIX"


	_delete_iso(iso_abs, delete_after)
	if not iso_ok or not FileAccess.file_exists(ProjectSettings.globalize_path(main_mix)):
		_bg_finish({"ok": false, "msg": _tt("content.err_iso"), "detail": iso_abs.get_file(), "kept": []})
		return
	var kept_paths: Array = []
	var names: Array = KEEP_FILES.get(id, [])
	for i in names.size():
		var name: String = names[i]
		_bg_set("iso", float(i) / float(maxi(1, names.size())), name)
		var target := out_dir.path_join(name.get_file())
		ContentManager.ensure_dir(target.get_base_dir())
		if ContentBackend.extract(main_mix, name, target):
			kept_paths.append(target)
		else:
			AppLogger.warn(LOG_TAG, "extract(%s): %s" % [name, ContentBackend.last_error()])

	var main_abs := ProjectSettings.globalize_path(main_mix)
	if FileAccess.file_exists(main_abs):
		var mm := FileAccess.open(main_abs, FileAccess.READ)
		var mm_size := int(mm.get_length()) if mm != null else 0
		if mm != null:
			mm.close()
		DirAccess.remove_absolute(main_abs)
		AppLogger.info(LOG_TAG, "MAIN.MIX gelöscht (%s frei)" % ContentManager.format_mb(mm_size))
	_bg_finish({"ok": not kept_paths.is_empty(), "msg": _tt("content.err_iso"), "detail": "",
			"kept": kept_paths, "voices": _bg_language_sounds(id)})


func _delete_iso(iso_abs: String, delete_after: bool) -> void:
	if iso_abs == "" or not FileAccess.file_exists(iso_abs):
		return
	if not (delete_after or ContentManager.is_own_file(iso_abs)):
		AppLogger.info(LOG_TAG, "Gewähltes Abbild bleibt unangetastet: %s" % iso_abs.get_file())
		return
	var f := FileAccess.open(iso_abs, FileAccess.READ)
	var size := int(f.get_length()) if f != null else 0
	if f != null:
		f.close()
	DirAccess.remove_absolute(iso_abs)
	AppLogger.info(LOG_TAG, "Abbild gelöscht: %s (%s frei)" % [iso_abs.get_file(), ContentManager.format_mb(size)])


func _native_dialog_available() -> bool:


	if OS.get_cmdline_user_args().has("--force-no-file-dialog"):
		return false
	if OS.get_name() == "iOS":
		return false


	if ContentManager.web():
		return true
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


func _on_pick_file() -> void:
	if ContentManager.web():
		_web_pick()
		return
	if not _native_dialog_available():
		_on_scan_folder()
		return
	DisplayServer.file_dialog_show(tr("content.pick_file"), "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.iso,*.mix ; ISO/MIX"]),
			_on_file_picked)


func _web_pick() -> void:
	if _busy or _bg_busy():
		_busy_hint.text = tr("content.busy_pick")
		_busy_hint.visible = true
		return
	_clear_error()
	_busy_hint.text = tr("content.pick_waiting")
	_busy_hint.visible = true
	WebFiles.pick(".zip,.mix")
	_web_pick_wait()


func _web_pick_wait() -> void:


	var patience := 5 * 60 * 10
	var state := ""
	var info := {}
	while patience > 0:
		for _i in 6:
			await _bg_yield()
		if not is_inside_tree():
			return
		info = WebFiles.pick_state()
		state = str(info.get("state", "idle"))
		if state == "ready" or state == "cancel" or state == "error":
			break
		patience -= 1
	_busy_hint.visible = false
	if state == "error":
		AppLogger.warn(LOG_TAG, "Dateiauswahl im Browser fehlgeschlagen: %s" % str(info.get("error", "")))
		_show_error(tr("content.err_pick"), str(info.get("error", "")), "")
		WebFiles.pick_reset()
		return
	if state != "ready":
		WebFiles.pick_reset()
		return
	if _busy or _bg_busy():
		WebFiles.pick_reset()
		return

	var file_name := str(info.get("name", ""))
	var size := int(info.get("size", 0))
	var is_mix := file_name.to_lower().ends_with(".mix")
	AppLogger.info(LOG_TAG, "Datei im Browser gewählt: %s (%s)" % [file_name, ContentManager.format_mb(size)])
	_busy = true
	_current_job = "cd_allied" if is_mix else "freeware"
	_row_visible_for(_current_job, true)
	_bg_begin(tr("content.phase_copy"))
	_bg_stepped = true
	ContentManager.ensure_dir(ContentManager.ROOT)
	var target := "user://content/picked.mix.tmp" if is_mix else "user://content/freeware_download.zip.tmp"
	var copied := await _web_copy_picked(target, size, file_name)
	WebFiles.pick_reset()
	if not copied:
		_bg_finish({"ok": false, "msg": _tt("content.err_pick"), "detail": file_name})
		return
	if is_mix:


		_bg_mix_direct("allied", target)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
		return
	_from_picked_file = true
	_download_target = target
	await _web_freeware()


func _web_copy_picked(target: String, size: int, file_name: String) -> bool:
	var abs := ProjectSettings.globalize_path(target)
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		AppLogger.warn(LOG_TAG, "Zieldatei nicht schreibbar: %s" % abs)
		return false
	var offset := 0
	while offset < size:
		var want := mini(WebFiles.CHUNK, size - offset)
		if not WebFiles.read_chunk(offset, want):
			f.close()
			return false
		var data := PackedByteArray()


		var waited := 600
		while data.is_empty() and waited > 0:
			await _bg_yield()
			data = WebFiles.take_chunk()
			waited -= 1
		if data.is_empty():
			AppLogger.warn(LOG_TAG, "Kein Häppchen bei Byte %d von %s" % [offset, file_name])
			f.close()
			return false
		f.store_buffer(data)
		offset += data.size()
		_bg_set("copy", float(offset) / float(maxi(1, size)), file_name)
	f.close()
	AppLogger.info(LOG_TAG, "%s nach %s kopiert" % [ContentManager.format_mb(offset), target])
	return true


func _on_file_picked(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	if not status or selected_paths.is_empty():
		return
	_use_local_file(String(selected_paths[0]))


static func pick_folders() -> Array[String]:
	var out: Array[String] = [OS.get_user_data_dir().path_join("original"), OS.get_user_data_dir()]
	if OS.get_name() == "Android":
		out.append("/storage/emulated/0/Android/data/%s/files/original" % OriginalContent.PACKAGE)
		out.append("/sdcard/Android/data/%s/files/original" % OriginalContent.PACKAGE)
	return out


func _pick_folder_display() -> String:
	return "original/"


func _on_scan_folder() -> void:
	for c in _pick_list.get_children():
		_pick_list.remove_child(c)
		c.queue_free()
	var found: Array[String] = []
	for folder in pick_folders():
		var d := DirAccess.open(folder)
		if d == null:
			continue
		for f in d.get_files():
			var ext := f.get_extension().to_lower()
			if ext == "iso" or ext == "mix":
				var full := folder.path_join(f)
				if not found.has(full):
					found.append(full)
	AppLogger.info(LOG_TAG, "Ordner geprüft: %d Abbilder gefunden (%s)" % [found.size(), ", ".join(pick_folders())])
	if found.is_empty():
		_busy_hint.text = tr("content.pick_none") % _pick_folder_display()
		_busy_hint.visible = true
		return
	_busy_hint.visible = false
	for full in found:
		var b := _action_button(tr("content.pick_use") % full.get_file(), func(): _use_local_file(full))
		_pick_list.add_child(b)


func _use_local_file(path: String) -> void:
	AppLogger.info(LOG_TAG, "Datei gewählt: %s" % path)
	if _busy:
		_busy_hint.text = tr("content.busy_pick")
		_busy_hint.visible = true
		return
	_clear_error()
	if path.get_extension().to_lower() == "mix":
		_busy = true
		_current_job = "cd_allied"
		_row_visible_for(_current_job, true)
		_start_bg(_bg_mix_direct.bind("allied", path), tr("content.phase_iso"))
	else:
		_start_cd_processing("allied", path, false)


func _bg_mix_direct(id: String, mix_path: String) -> void:
	if not ContentBackend.available():
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": "", "kept": []})
		return
	var out_dir := ContentManager.CD_DIR.path_join(id)
	ContentManager.ensure_dir(out_dir)
	var kept_paths: Array = []
	var names: Array = KEEP_FILES.get(id, [])
	for i in names.size():
		var name: String = names[i]
		_bg_set("iso", float(i) / float(maxi(1, names.size())), name)
		var target := out_dir.path_join(name.get_file())
		ContentManager.ensure_dir(target.get_base_dir())
		if ContentBackend.extract(mix_path, name, target):
			kept_paths.append(target)
		else:
			AppLogger.warn(LOG_TAG, "extract(%s): %s" % [name, ContentBackend.last_error()])
	_bg_finish({"ok": not kept_paths.is_empty(), "msg": _tt("content.err_iso"), "detail": "",
			"kept": kept_paths, "voices": _bg_language_sounds(id)})


func _bg_language_sounds(cd_id: String) -> int:
	var lang := _lang_of_cd(cd_id)
	if lang == "":
		return 0
	_bg_set("sfx", 0.0, lang)
	var n := ContentManager.build_language_sounds(lang, _bg_progress)
	if n == 0:
		AppLogger.warn(LOG_TAG, "Sprachausgabe %s nicht gewandelt: %s" % [lang, ContentBackend.last_error()])
	else:
		AppLogger.info(LOG_TAG, "Sprachausgabe %s: %d Clips nach %s" % [lang, n,
				ContentManager.SFX_DIR.path_join(lang)])
	return n


func _lang_of_cd(cd_id: String) -> String:
	for lang in ContentManager.LANG_CD:
		if str(ContentManager.LANG_CD[lang]) == cd_id:
			return str(lang)
	return ""


func _finish_cd_component(id: String, res: Dictionary) -> void:
	_download_target = ""
	var kept_paths: Array = res.get("kept", [])
	var total_size := 0
	var verify: Array = []
	for p in kept_paths:
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			var size := f.get_length()
			total_size += size
			verify.append({"path": p, "size": size})
	ContentManager.set_component("cd_" + id, {
		"installed": not kept_paths.is_empty(), "installed_at": int(Time.get_unix_time_from_system()),
		"size_bytes": total_size, "verify_files": verify,
	})
	if not bool(res.get("ok", false)) or kept_paths.is_empty():
		_job_failed(str(res.get("msg", tr("content.err_iso"))), str(res.get("detail", "")), "cd_" + id)
	else:
		AppLogger.info(LOG_TAG, "CD-Inhalt %s eingerichtet (%s)" % [id, ContentManager.format_mb(total_size)])

		_content_changed()
		var mp := get_node_or_null("/root/MusicPlayer")
		AppLogger.info(LOG_TAG, "Musik: %s" % (mp.source_text() if mp != null else "—"))
		var voices := int(res.get("voices", 0))
		if voices > 0:
			AppLogger.info(LOG_TAG, "Sprachausgabe aus %s: %d Clips" % [id, voices])
		_job_done(true, tr("content.done"))


func _on_voice_button() -> void:
	if _busy or _bg_thread != null:
		_busy_hint.text = tr("content.busy_pick")
		_busy_hint.visible = true
		return
	var lang := "de"
	if ContentManager.lang_source_dir(lang) == "":
		return
	_clear_error()
	_busy = true
	_cancel_requested = false
	_current_job = LANG_JOB + lang
	_row_visible_for(_current_job, true)
	AppLogger.info(LOG_TAG, "Sprachausgabe %s wird nachträglich ausgelesen" % lang)
	_start_bg(_bg_lang_only.bind(lang), tr("content.phase_sfx"))


func _bg_lang_only(lang: String) -> void:
	if not ContentBackend.available():
		_bg_finish({"ok": false, "msg": _tt("content.err_backend"), "detail": "", "voices": 0})
		return
	_bg_set("sfx", 0.0, lang)
	var n := ContentManager.build_language_sounds(lang, _bg_progress)
	_bg_finish({"ok": n > 0, "msg": _tt("content.err_voice"),
			"detail": ContentBackend.last_error() if n == 0 else "", "voices": n})


func _finish_language_sounds(lang: String, res: Dictionary) -> void:
	var n := int(res.get("voices", 0))
	if not bool(res.get("ok", false)):
		_job_failed(str(res.get("msg", tr("content.err_voice"))), str(res.get("detail", "")), "")
		return
	AppLogger.info(LOG_TAG, "Sprachausgabe %s nachgetragen: %d Clips" % [lang, n])


	_content_changed()


	_job_done(true, tr("content.voice_done") % n)
	if n < VOICE_FULL_COUNT and _busy_hint != null:
		_busy_hint.text = tr("content.voice_partial") % [n, VOICE_FULL_COUNT]
		_busy_hint.visible = true


func _cancel_job() -> void:
	if not _busy:
		_clear_queue()
		return
	if _bg_thread != null:


		return
	AppLogger.info(LOG_TAG, "Abbruch durch Nutzer (%s)" % _current_job)
	_cancel_requested = true
	_clear_queue()
	_http.cancel_request()
	_cleanup_tmp()
	_job_done(false, tr("content.cancelled"))


func _job_failed(msg: String, detail: String = "", job: String = "") -> void:
	AppLogger.warn(LOG_TAG, msg + ((" — " + detail) if detail != "" else ""))
	_job_done(false, "")
	_show_error(msg, detail, job)


func _job_done(success: bool, msg: String) -> void:
	var job := _current_job
	_busy = false
	_current_job = ""
	_download_target = ""


	_from_picked_file = false
	_row_visible_for(job, false)
	if _busy_hint != null:
		_busy_hint.text = msg
		_busy_hint.visible = msg != ""
	if success:
		_clear_error()
	if job != "" and _queue_total > 0:
		_queue_done += 1
	_refresh_status()
	if _log_view != null and _log_view.visible:
		_log_view.refresh()

	if not _queue.is_empty():
		call_deferred("_start_next")
	else:
		_queue_total = 0
		_queue_done = 0
		_update_queue_label()


		if _test_unlocked and ContentManager.available():
			unlocked.emit()


func _notification(what: int) -> void:


	if what == MainLoop.NOTIFICATION_APPLICATION_PAUSED and _busy:
		AppLogger.info(LOG_TAG, "App pausiert während „%s“ (%s geladen)" % [
			_current_job, ContentManager.format_mb(_dl_last_bytes)])
	elif what == MainLoop.NOTIFICATION_APPLICATION_RESUMED and _busy:
		AppLogger.info(LOG_TAG, "App wieder aktiv während „%s“" % _current_job)
		_dl_last_ms = Time.get_ticks_msec()


func _run_test_web_paths() -> void:


	var status := ContentBackend.content_status(ContentManager.ROOT)
	print("T: content_status ready=%s atlases=%s sfx=%s" % [status.get("ready"), status.get("atlases"), status.get("sfx")])
	print("T: ContentManager.available() = ", ContentManager.available())
	var ad := DirAccess.open(ContentManager.ATLAS_DIR)
	print("T: user://content/atlas: ", ad.get_files() if ad != null else "kein Zugriff")
	var p := "user://content/probe.tmp"
	var abs := ProjectSettings.globalize_path(p)
	var dir_abs := ProjectSettings.globalize_path(ContentManager.ROOT)
	print("T: OS.get_user_data_dir()   = ", OS.get_user_data_dir())
	print("T: globalize(user://…)      = ", abs)
	print("T: is_userfs_persistent     = ", OS.is_userfs_persistent())
	ContentManager.ensure_dir(ContentManager.ROOT)
	print("T: dir_exists(user://)      = ", DirAccess.dir_exists_absolute(ContentManager.ROOT))
	print("T: dir_exists(global)       = ", DirAccess.dir_exists_absolute(dir_abs))
	var w := FileAccess.open(p, FileAccess.WRITE)
	print("T: open(user://, WRITE)     = ", w != null)
	if w != null:
		w.store_buffer(PackedByteArray([1, 2, 3, 4]))
		w.close()
	print("T: file_exists(user://)     = ", FileAccess.file_exists(p))
	print("T: file_exists(global)      = ", FileAccess.file_exists(abs))
	var r1 := FileAccess.open(p, FileAccess.READ)
	print("T: open(user://, READ)      = ", r1 != null, " Länge ", (int(r1.get_length()) if r1 != null else -1))
	if r1 != null:
		r1.close()
	var r2 := FileAccess.open(abs, FileAccess.READ)
	print("T: open(global, READ)       = ", r2 != null, " Länge ", (int(r2.get_length()) if r2 != null else -1))
	if r2 != null:
		r2.close()
	var w2 := FileAccess.open(abs + "2", FileAccess.WRITE)
	print("T: open(global, WRITE)      = ", w2 != null)
	if w2 != null:
		w2.store_buffer(PackedByteArray([1, 2, 3, 4]))
		w2.close()
	print("T: SHA1 über user://        = „", ContentManager.sha1_hex(p), "“")
	print("T: SHA1 über global         = „", ContentManager.sha1_hex(abs), "“")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(abs + "2")

	if _url_override != "":
		await _probe_download("user://content/probe_dl_user.tmp", "download_file")
		await _probe_body("user://content/probe_dl_body.tmp", "Rumpf selbst schreiben")
	print("T: --test-web-paths fertig")
	get_tree().quit()


func _probe_download(target: String, label: String) -> void:
	_http.download_file = target
	var err := _http.request(_url_override)
	print("T: Download (%s) request() = %d" % [label, err])
	if err != OK:
		return
	var res: Array = await _http.request_completed
	var f := FileAccess.open(target, FileAccess.READ)
	print("T: Download (%s) Ergebnis %d Code %d, Datei %s, Länge %d" % [label, int(res[0]), int(res[1]),
			"da" if f != null else "FEHLT", int(f.get_length()) if f != null else -1])
	var body: PackedByteArray = res[3]
	print("T: Download (%s) Rumpf im Signal %d Byte, geladen %d, Rumpfgröße %d, download_file „%s“" % [
			label, body.size(), _http.get_downloaded_bytes(), _http.get_body_size(), _http.download_file])
	var d := DirAccess.open("user://content")
	print("T: Inhalt user://content: ", d.get_files() if d != null else "kein Zugriff")
	if f != null:
		f.close()
	DirAccess.remove_absolute(target)


func _probe_body(target: String, label: String) -> void:
	_http.download_file = ""
	var err := _http.request(_url_override)
	print("T: %s request() = %d" % [label, err])
	if err != OK:
		return
	var res: Array = await _http.request_completed
	var body: PackedByteArray = res[3]
	var w := FileAccess.open(target, FileAccess.WRITE)
	if w != null:
		w.store_buffer(body)
		w.close()
	var f := FileAccess.open(target, FileAccess.READ)
	print("T: %s Ergebnis %d Code %d, Rumpf %d Byte, Datei %s, Länge %d" % [label, int(res[0]), int(res[1]),
			body.size(), "da" if f != null else "FEHLT", int(f.get_length()) if f != null else -1])
	if f != null:
		print("T: %s SHA1 = %s" % [label, ContentManager.sha1_hex(target)])
		f.close()
	DirAccess.remove_absolute(target)


func _run_test_content_ui(mode: String) -> void:


	for _i in 12:
		await get_tree().process_frame
		if not is_inside_tree():
			return

	if mode != "disclaimer":
		ContentManager.set_disclaimer_accepted(true)
	if _url_override == "" and mode != "error" and mode != "delete" and mode != "music" \
			and mode != "webpaths":
		print("T: --test-content-ui braucht --content-url (lokaler Testserver)")
		get_tree().quit()
		return
	match mode:
		"cancel":
			_enqueue("freeware")
			for _i in 2:
				await get_tree().process_frame
				if not is_inside_tree():
					return
			_cancel_job()
			await get_tree().process_frame
			if not is_inside_tree():
				return
			var ok := not ContentManager.has_freeware() and _download_target == "" and _queue.is_empty()
			print("T: --test-content-ui-cancel ", "OK" if ok else "FEHLGESCHLAGEN")
		"badsum":
			_sha1_override = "0000000000000000000000000000000000000badd"
			_enqueue("freeware")
			if not await _wait_job_done():
				return
			var ok2 := not ContentManager.has_freeware() and _err_panel.visible \
					and _err_label.text.find(tr("content.err_checksum").split("%")[0]) >= 0
			print("T: --test-content-ui-badsum ", "OK" if ok2 else "FEHLGESCHLAGEN (" + _err_label.text + ")")
		"error":


			if _url_override == "":
				_url_override = "https://nicht-erreichbar.invalid/ra-quickinstall.zip"
			_enqueue("freeware")
			if not await _wait_job_done():
				return
			var cd_btn: Button = _cd_rows["allied"]["btn"]
			var usable: bool = not _freeware_btn.disabled and not cd_btn.disabled

			_set_log_visible(true)
			var ok4: bool = _err_panel.visible and _err_label.text != "" and _retry_btn.visible and usable
			print("T: --test-content-ui-error ", "OK" if ok4 else "FEHLGESCHLAGEN",
					" — „%s“ / „%s“, Knöpfe bedienbar: %s" % [_err_label.text, _err_detail.text, usable])
		"queue":
			await _run_test_queue()
		"delete":
			await _run_test_delete()
		"music":
			await _run_test_music()
		"disclaimer":
			await _run_test_disclaimer()
		"webpaths":
			_run_test_web_paths()
			return
		_:
			_enqueue("freeware")
			var alive := await _wait_job_done()
			var mix_count := _count_mix()
			var ok3 := mix_count > 0 and (_test_unlocked or not ContentBackend.available())
			print("T: --test-content-ui ", "OK" if ok3 else "FEHLGESCHLAGEN",
					" — %d MIX-Dateien entpackt, Atlanten/Sounds: %s%s" % [mix_count,
					"ja" if _test_unlocked else "nein", "" if alive else ", Seite nach unlocked neu aufgebaut"])
			if not alive:


				Engine.get_main_loop().quit()
				return
	if _shot_dir != "" and is_inside_tree():
		for _i in 3:
			await get_tree().process_frame
		_shoot("%s/final.png" % _shot_dir)
	if is_inside_tree():
		get_tree().quit()


func _run_test_queue() -> void:
	_enqueue("freeware")
	await get_tree().process_frame
	_enqueue("cd_allied")
	var queued := _queue_total == 2 and _queue.has("cd_allied")
	var label_ok := _queue_label.visible and _queue_label.text != ""
	var label_text := _queue_label.text

	var live: bool = not (_cd_rows["soviet"]["btn"] as Button).disabled
	while (_busy or _bg_thread != null or not _queue.is_empty()) and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	var iso_left := FileAccess.file_exists(ProjectSettings.globalize_path(
			"user://content/allied_download.iso.tmp"))
	var cd_ok := ContentManager.has_cd("allied")
	var ok: bool = queued and label_ok and live and not iso_left and _queue_total == 0
	print("T: --test-content-ui-queue ", "OK" if ok else "FEHLGESCHLAGEN",
			" — eingereiht: %s, Zeile „%s“, Knöpfe bedienbar: %s, CD-Auszug: %s, Abbild gelöscht: %s"
			% [queued, label_text, live, "ja" if cd_ok else "nein", not iso_left])


func _run_test_music() -> void:
	var mp := get_node_or_null("/root/MusicPlayer")
	if mp == null:
		print("T: --test-music FEHLGESCHLAGEN — kein MusicPlayer-Autoload")
		return
	if _cd_url_override == "":
		print("T: --test-music braucht --content-cd-url (lokaler Testserver)")
		return

	ContentManager.delete_cd("allied")
	_content_changed()
	mp.set_source(Music.SOURCE_ORIGINAL)
	var vorher_quelle: String = mp.source_text()
	var vorher: int = mp.track_titles().size()
	_enqueue("cd_allied")
	if not await _wait_job_done():
		return
	var installiert := ContentManager.has_cd("allied")
	var titel: PackedStringArray = mp.track_titles()
	var hat_hell := Array(titel).has("Hell March")
	var hat_big := Array(titel).has("Bigfoot")
	var quelle: String = mp.source_text()

	var archives := ContentPaths.archives()
	var stream_ok := false
	if archives != null:
		for f in archives.list_music():
			if String(f).to_lower().begins_with("hell226m"):
				stream_ok = archives.aud_stream(f) != null

	mp.set_source(Music.SOURCE_OWN)
	var eigene: int = mp.track_titles().size()
	var eigene_quelle: String = mp.source_text()
	mp.set_source(Music.SOURCE_ORIGINAL)
	var zurueck: bool = Array(mp.track_titles()).has("Hell March")

	ContentManager.delete_cd("allied")
	_content_changed()
	var nachher: int = mp.track_titles().size()
	var ok: bool = installiert and hat_hell and hat_big and stream_ok and zurueck \
			and eigene == vorher and nachher == vorher
	print("T: --test-music ", "OK" if ok else "FEHLGESCHLAGEN",
			" — vorher %d Titel (%s), nach der CD %d Titel (%s): Hell March %s, Bigfoot %s, "
			% [vorher, vorher_quelle, titel.size(), quelle, "ja" if hat_hell else "nein",
			"ja" if hat_big else "nein"],
			"abspielbar %s; Schalter „Eigene“ %d Titel (%s), zurück auf Original %s; "
			% ["ja" if stream_ok else "nein", eigene, eigene_quelle, "ja" if zurueck else "nein"],
			"nach dem Löschen %d Titel" % nachher)


func _run_test_disclaimer() -> void:
	ContentManager.set_disclaimer_accepted(false)

	_enqueue("freeware")
	await get_tree().process_frame
	var kommt := disclaimer_visible() and not _busy and _queue.is_empty()

	if _disclaimer_cancel != null:
		_disclaimer_cancel.pressed.emit()
	await get_tree().process_frame
	var abbruch := not disclaimer_visible() and not _busy and _queue.is_empty() \
			and not ContentManager.disclaimer_accepted()

	_enqueue("freeware")
	await get_tree().process_frame
	var wieder := disclaimer_visible()
	if _disclaimer_ok != null:
		_disclaimer_ok.pressed.emit()
	await get_tree().process_frame
	var gemerkt := ContentManager.disclaimer_accepted()
	var laeuft := _busy or not _queue.is_empty()
	_cancel_job()
	if not await _wait_job_done():
		return

	_enqueue("freeware")
	await get_tree().process_frame
	var still := not disclaimer_visible() and (_busy or not _queue.is_empty())
	_cancel_job()
	var ok := kommt and abbruch and wieder and gemerkt and laeuft and still
	print("T: --test-content-disclaimer ", "OK" if ok else "FEHLGESCHLAGEN",
			" — Fenster vor dem ersten Download: %s, Abbrechen lädt nichts: %s, zweiter Anlauf zeigt es wieder: %s, "
			% [kommt, abbruch, wieder],
			"Zustimmung gemerkt: %s, Auftrag läuft an: %s, danach kein Fenster mehr: %s"
			% [gemerkt, laeuft, still])


func _run_test_delete() -> void:
	ContentManager.set_component("freeware", {"installed": true, "size_bytes": 1,
			"verify_files": [{"path": "user://content/manifest.json", "size": -1}]})
	ContentManager.set_component("cd_allied", {"installed": true, "size_bytes": 1})
	var before := ContentManager.has_cd("allied")
	ContentManager.delete_all()
	var after_locked := not ContentManager.available()
	var gone := not DirAccess.dir_exists_absolute(ContentManager.ROOT) \
			and not ContentManager.has_cd("allied") and not ContentManager.has_freeware()
	var ok := before and gone and after_locked
	print("T: --test-content-delete ", "OK" if ok else "FEHLGESCHLAGEN",
			" — vorher installiert: %s, danach gelöscht: %s, Erststart-Sperre wieder aktiv: %s"
			% [before, gone, after_locked])


func _report_unlocked() -> void:
	_test_reported = true
	var mix_count := _count_mix()
	print("T: --test-content-ui ", "OK" if mix_count > 0 else "FEHLGESCHLAGEN",
			" — %d MIX-Dateien entpackt, Atlanten/Sounds gebaut, Seite nach unlocked neu aufgebaut" % mix_count)
	if _shot_dir != "":
		for _i in 6:
			await get_tree().process_frame
		if is_inside_tree():
			_shoot("%s/final.png" % _shot_dir)
	if is_inside_tree():
		get_tree().quit()


static func _count_mix() -> int:
	var n := 0
	var d := DirAccess.open(ContentManager.MIX_DIR)
	if d == null:
		return 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != ".." and not d.current_is_dir():
			n += 1
		f = d.get_next()
	d.list_dir_end()
	return n


func _wait_job_done() -> bool:
	while _busy or _bg_thread != null:
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	return is_inside_tree()


func scroll_to_end() -> void:
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = int(maxf(bar.max_value - bar.page, 0.0))


func scroll_to_top() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = 0


func scroll_node() -> ScrollContainer:
	return _scroll


func scroll_needed() -> bool:
	if _scroll == null:
		return false
	var bar := _scroll.get_v_scroll_bar()
	return bar.max_value > bar.page + 1.0
