

class_name LayoutCheck
extends RefCounted


const KINDS := ["Button", "HSlider", "Label"]
const GROUP := "layout_hud"


static func violations(root: Node, safe: Rect2, page: String, tolerance: float = 1.0) -> Array:
	var out: Array = []
	_walk(root, safe, page, tolerance, out)
	return out


static func _walk(n: Node, safe: Rect2, page: String, tol: float, out: Array) -> void:
	if n is Control:
		var c: Control = n
		if not c.is_visible_in_tree():
			return
		if _is_checked(c) and c.size.x > 1.0 and c.size.y > 1.0:
			var r := HudTheme.visible_rect(c)
			if r.position.x < safe.position.x - tol or r.position.y < safe.position.y - tol \
					or r.end.x > safe.end.x + tol or r.end.y > safe.end.y + tol:

				if not _in_scroll(c):
					out.append("LAYOUT: %s %s (%s) ragt heraus: %s außerhalb %s" % [
						page, c.name, c.get_class(), r, safe])
	for child in n.get_children():
		_walk(child, safe, page, tol, out)


static func _is_checked(c: Control) -> bool:
	if c.is_in_group(GROUP):
		return true
	for k in KINDS:
		if c.is_class(k):
			return true
	return false


static func in_scroll(c: Control) -> bool:
	return _in_scroll(c)


static func _in_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


static func overlap_violations(root: Node, page: String, tolerance: float = 1.0) -> Array:
	var items: Array = []
	_collect(root, items)
	var out: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i][0]
			var b: Control = items[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra: Rect2 = items[i][1]
			var rb: Rect2 = items[j][1]
			var inter := ra.intersection(rb)
			if inter.size.x > tolerance and inter.size.y > tolerance:
				out.append("LAYOUT: %s %s (%s) überlappt %s (%s): %s ∩ %s" % [
					page, a.name, a.get_class(), b.name, b.get_class(), ra, rb])
	return out


static func map_violations(root: Node, map: Rect2, page: String, tolerance: float = 1.0) -> Array:
	var items: Array = []
	_collect(root, items)
	var out: Array = []
	for it in items:
		var c: Control = it[0]
		var r: Rect2 = it[1]
		var inter := r.intersection(map)
		if inter.size.x > tolerance and inter.size.y > tolerance:
			out.append("LAYOUT: %s %s (%s) ragt in die Karte: %s ∩ %s = %s" % [
				page, c.name, c.get_class(), r, map, inter])
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is Control:
		var c: Control = n
		if not c.is_visible_in_tree():
			return
		if c.is_in_group(GROUP) and c.size.x > 1.0 and c.size.y > 1.0 and not _in_scroll(c):
			out.append([c, HudTheme.visible_rect(c)])
	for child in n.get_children():
		_collect(child, out)


const MIN_FONT_DP := 10.0


static func fit_violations(root: Node, safe: Rect2, page: String, tolerance: float = 1.0) -> Array:
	var out: Array = []
	_walk_fit(root, safe, page, tolerance, out)
	return out


static func _walk_fit(n: Node, safe: Rect2, page: String, tol: float, out: Array) -> void:
	if n is Control:
		var c: Control = n
		if not c.is_visible_in_tree():
			return
		if (c is Label or c is Button) and c.size.x > 1.0 and c.size.y > 1.0:
			var need := c.get_combined_minimum_size()
			if need.y > c.size.y + tol:
				out.append("FEHLER: %s %s (%s) abgeschnitten: braucht %.0f px Höhe, hat %.0f — Text „%s“" % [
					page, c.name, c.get_class(), need.y, c.size.y, _text_of(c).left(40)])
			if need.x > c.size.x + tol:
				out.append("FEHLER: %s %s (%s) abgeschnitten: braucht %.0f px Breite, hat %.0f — Text „%s“" % [
					page, c.name, c.get_class(), need.x, c.size.x, _text_of(c).left(40)])
			var r := HudTheme.visible_rect(c)
			var card = _card_rect(c)
			if card != null and not _inside(r, card as Rect2, tol):
				out.append("FEHLER: %s %s (%s) ragt aus der Karte: %s außerhalb %s — Text „%s“" % [
					page, c.name, c.get_class(), r, card, _text_of(c).left(40)])
			if not _in_scroll(c) and not _inside(r, safe, tol):
				out.append("FEHLER: %s %s (%s) ragt aus der sicheren Fläche: %s außerhalb %s" % [
					page, c.name, c.get_class(), r, safe])
			var font_px := float(c.get_theme_font_size("font_size"))
			if font_px > 0.0 and Dp.to_device_dp(font_px) < MIN_FONT_DP - 0.5:
				out.append("FEHLER: %s %s (%s) Schrift zu klein: %.1f Geräte-dp (mindestens %.0f)" % [
					page, c.name, c.get_class(), Dp.to_device_dp(font_px), MIN_FONT_DP])
			if c is Button and Dp.to_device_dp(r.size.y) < HudTheme.MIN_TOUCH_DP - 0.5:
				out.append("FEHLER: %s %s (Button) Tippfläche zu klein: %.1f × %.1f Geräte-dp (mindestens %.0f hoch) — „%s“" % [
					page, c.name, Dp.to_device_dp(r.size.x), Dp.to_device_dp(r.size.y),
					HudTheme.MIN_TOUCH_DP, _text_of(c).left(30)])
	for child in n.get_children():
		_walk_fit(child, safe, page, tol, out)


static func _text_of(c: Control) -> String:
	if c is Label:
		return (c as Label).text.replace("\n", " ")
	if c is Button:
		return (c as Button).text
	return ""


static func _inside(inner: Rect2, outer: Rect2, tol: float) -> bool:
	return inner.position.x >= outer.position.x - tol and inner.position.y >= outer.position.y - tol \
			and inner.end.x <= outer.end.x + tol and inner.end.y <= outer.end.y + tol


static func _card_rect(c: Control):
	var p := c.get_parent()
	while p != null:
		if p is PanelContainer:
			var pc: PanelContainer = p
			var sb := pc.get_theme_stylebox("panel")
			var r := Rect2(pc.global_position, pc.size)
			if sb != null:
				r.position += Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
				r.size -= Vector2(sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT),
						sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM))
			return r
		if p is ScrollContainer:
			return null
		p = p.get_parent()
	return null
