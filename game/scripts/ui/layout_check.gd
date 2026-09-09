

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
			var r := c.get_global_rect()
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
			out.append([c, c.get_global_rect()])
	for child in n.get_children():
		_collect(child, out)
