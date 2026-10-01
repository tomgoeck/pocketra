

class_name MenuBackground
extends Control

var _time := 0.0
var _tex_size := Vector2.ZERO
var _origins: Array = []


const ORIGINS := {
	"menu_bg_de": [Vector2(0.260, 0.520), Vector2(0.734, 0.558)],
	"menu_bg_en": [Vector2(0.260, 0.520), Vector2(0.734, 0.558)],
	"menu_bg_wide_de": [Vector2(0.281, 0.474), Vector2(0.802, 0.432)],
	"menu_bg_wide_en": [Vector2(0.281, 0.466), Vector2(0.802, 0.455)],
}
const FALLBACK_ORIGINS := [Vector2(0.26, 0.52), Vector2(0.734, 0.558)]


const LIGHTS := [
	{"base_deg": -11.0, "period": 17.0, "amp_deg": 13.0, "dir": 1.0, "phase": 0.0},
	{"base_deg": 11.0, "period": 23.0, "amp_deg": 13.0, "dir": -1.0, "phase": 1.7},
]

const CONE_HALF_WIDTH_DEG := 4.5
const LAYER_WIDTHS := [1.0, 0.66, 0.40, 0.20]


const BASE_ALPHA := 0.15
const LIGHT_COLOR := Color(1.0, 0.95, 0.62)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	set_process(true)


func set_background(path: String, texture: Texture2D) -> void:
	_tex_size = texture.get_size() if texture != null else Vector2.ZERO
	var key := path.get_file().get_basename()
	_origins = ORIGINS.get(key, FALLBACK_ORIGINS)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _image_to_screen(rel: Vector2) -> Vector2:
	var vs := size
	if _tex_size.x <= 0.0 or _tex_size.y <= 0.0:
		return Vector2(rel.x * vs.x, rel.y * vs.y)
	var s := maxf(vs.x / _tex_size.x, vs.y / _tex_size.y)
	var drawn := _tex_size * s
	return (vs - drawn) * 0.5 + rel * drawn


func _draw() -> void:
	var vs := size
	if vs.x <= 1.0 or vs.y <= 1.0:
		return
	var origins: Array = _origins if _origins.size() >= LIGHTS.size() else FALLBACK_ORIGINS
	for i in LIGHTS.size():
		var l: Dictionary = LIGHTS[i]
		var origin := _image_to_screen(origins[i])

		var length := (maxf(origin.y, 0.0) + vs.y * 0.25) * 1.4
		var sway := sin(_time * TAU / float(l["period"]) + float(l["phase"]))
		var angle := deg_to_rad(float(l["base_deg"]) + sway * float(l["amp_deg"]) * float(l["dir"]))
		var per_layer := BASE_ALPHA / float(LAYER_WIDTHS.size())
		var col_base := Color(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, per_layer)
		var col_tip := Color(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, 0.0)
		for w in LAYER_WIDTHS:
			var half := deg_to_rad(CONE_HALF_WIDTH_DEG * float(w))
			var dir_a := Vector2.UP.rotated(angle - half)
			var dir_b := Vector2.UP.rotated(angle + half)
			draw_polygon(
				PackedVector2Array([origin, origin + dir_a * length, origin + dir_b * length]),
				PackedColorArray([col_base, col_tip, col_tip]))
		_draw_lamp(origin, vs.y * 0.006)


func _draw_lamp(origin: Vector2, radius: float) -> void:
	var pts := PackedVector2Array([origin])
	var cols := PackedColorArray([Color(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, BASE_ALPHA * 1.6)])
	var edge := Color(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, 0.0)
	for i in 13:
		var a := PI * float(i) / 12.0
		pts.append(origin + Vector2(-cos(a), -sin(a)) * radius)
		cols.append(edge)
	draw_polygon(pts, cols)
