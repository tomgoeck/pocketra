
extends Control

var kind := "tank"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := size
	var c := s / 2.0
	match kind:
		"tank":
			var dark := Color(0.15, 0.16, 0.10)
			var mid := Color(0.30, 0.34, 0.18)
			draw_rect(Rect2(s.x * 0.10, s.y * 0.50, s.x * 0.80, s.y * 0.22), mid)
			draw_rect(Rect2(s.x * 0.05, s.y * 0.68, s.x * 0.90, s.y * 0.20), dark)
			for i in 5:
				draw_circle(Vector2(s.x * (0.15 + 0.175 * i), s.y * 0.78), s.y * 0.07, Color(0.55, 0.55, 0.45))
			draw_rect(Rect2(s.x * 0.30, s.y * 0.30, s.x * 0.36, s.y * 0.22), mid)
			draw_rect(Rect2(s.x * 0.62, s.y * 0.36, s.x * 0.34, s.y * 0.07), dark)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := s.x * (0.46 if i % 2 == 0 else 0.20)
				var a := -PI / 2 + i * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0.98, 0.78, 0.20))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.55, 0.38, 0.05), maxf(1.0, s.x * 0.05))
		"gear":
			var col := Color(0.62, 0.60, 0.55)
			for i in 8:
				var a := i * PI / 4
				var p := c + Vector2(cos(a), sin(a)) * s.x * 0.36
				draw_rect(Rect2(p - Vector2(s.x * 0.10, s.x * 0.10), Vector2(s.x * 0.20, s.x * 0.20)), col)
			draw_circle(c, s.x * 0.30, col)
			draw_circle(c, s.x * 0.11, Color(0.22, 0.22, 0.20))
		"door":
			draw_rect(Rect2(s.x * 0.22, s.y * 0.12, s.x * 0.50, s.y * 0.78), Color(0.55, 0.35, 0.18))
			draw_rect(Rect2(s.x * 0.22, s.y * 0.12, s.x * 0.50, s.y * 0.78), Color(0.25, 0.15, 0.06), false, maxf(1.0, s.x * 0.05))
			draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.36, s.y * 0.20), Vector2(s.x * 0.62, s.y * 0.30), Vector2(s.x * 0.62, s.y * 0.95), Vector2(s.x * 0.36, s.y * 0.85)]), Color(0.75, 0.50, 0.25))
			draw_circle(Vector2(s.x * 0.56, s.y * 0.58), s.x * 0.04, Color(0.95, 0.85, 0.3))
