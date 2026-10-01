

class_name StatusBar
extends Control

var world: ProtoWorld
var credits := 0
var provided := 0
var drained := 0
var stored := 0
var capacity := 0
var _refresh := 0.0


var _frame: StyleBoxTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = HudTheme.panel_style()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh < 0.05 or world == null or world.sim == null:
		return
	_refresh = 0.0
	credits = world.display_credits()
	provided = world.sim.power_provided(world.local_player)
	drained = world.sim.power_drained(world.local_player)

	if world.sim.has_method("resources_stored"):
		stored = world.sim.resources_stored(world.local_player)
		capacity = world.sim.storage_capacity(world.local_player)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var gap := Dp.px(4)
	var row_h := (size.y - gap) / 2.0


	var fs := maxi(1, int(row_h * 0.56))
	var pad := Dp.px(8)
	var label_w := Dp.px(52)


	var r1 := Rect2(0, 0, size.x, row_h)
	_panel(r1)


	draw_string(font, Vector2(pad, r1.position.y + row_h / 2.0 + fs / 2.5), tr("status.credits"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.TEXT)


	var cfs := maxi(1, int(row_h * 0.52))
	var ctext := str(credits)
	var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
	draw_string(font, Vector2(r1.end.x - pad - cw, r1.position.y + row_h / 2.0 + cfs / 2.5 - Dp.px(1.5)),
			ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, HudTheme.GOLD)


	if capacity > 0:
		var frac := clampf(float(stored) / float(capacity), 0.0, 1.0)
		var sb := Rect2(pad + label_w, r1.end.y - Dp.px(5), r1.size.x - pad * 2 - label_w, Dp.px(3.5))
		draw_rect(sb, Color(0, 0, 0, 0.7), true)
		draw_rect(sb, HudTheme.BORDER_DIM, false, 1.0)
		var scol := Color(0.3, 0.9, 0.3)
		if frac > 0.98:
			scol = Color(0.95, 0.25, 0.2)
		elif frac > 0.8:
			scol = Color(0.95, 0.85, 0.3)
		draw_rect(Rect2(sb.position, Vector2(sb.size.x * frac, sb.size.y)), scol, true)
		var stext := tr("status.storage") % [stored, capacity]
		var sfs := maxi(1, int(row_h * 0.42))
		var sw := font.get_string_size(stext, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		var sat := Vector2(sb.position.x + sb.size.x * 0.42 - sw / 2.0, r1.position.y + row_h * 0.52)
		draw_string(font, sat + Vector2(1, 1), stext, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color.BLACK)
		draw_string(font, sat, stext, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, HudTheme.TEXT)


	var r2 := Rect2(0, row_h + gap, size.x, row_h)
	_panel(r2)
	draw_string(font, Vector2(pad, r2.position.y + row_h / 2.0 + fs / 2.5), tr("status.power"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudTheme.TEXT)
	var bar := Rect2(pad + label_w, r2.position.y + row_h * 0.22, size.x - pad * 2 - label_w, row_h * 0.56)
	HudTheme.draw_panel(self, bar, Color(0.03, 0.03, 0.03, 0.9), HudTheme.BORDER_DIM, 3.0)
	var ref := maxf(maxf(float(provided), float(drained)), 1.0) * 1.25
	var col := Color(0.3, 0.9, 0.3)
	if drained > provided:
		col = Color(0.95, 0.25, 0.2)
	elif drained > provided * 0.8:
		col = Color(0.95, 0.85, 0.3)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * minf(provided / ref, 1.0), bar.size.y)), col, true)
	var mark := bar.position.x + bar.size.x * minf(drained / ref, 1.0)
	draw_line(Vector2(mark, bar.position.y - 2), Vector2(mark, bar.end.y + 2), Color.WHITE, Dp.px(1.5))

	var ptext := tr("status.power_detail") % [drained, provided]
	var small := maxi(1, int(row_h * 0.45))
	var pw := font.get_string_size(ptext, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	draw_string(font, Vector2(bar.get_center().x - pw / 2.0 + 0.5, bar.get_center().y + small / 2.5 + 0.5), ptext, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.BLACK)
	draw_string(font, Vector2(bar.get_center().x - pw / 2.0, bar.get_center().y + small / 2.5), ptext, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color.WHITE)


func _panel(r: Rect2) -> void:
	_frame.draw(get_canvas_item(), r)
