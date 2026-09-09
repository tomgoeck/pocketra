

class_name PaletteAtlas
extends RefCounted

const REMAP_FIRST := 80
const REMAP_COUNT := 16

var atlas_texture: ImageTexture
var frame_table_texture: ImageTexture
var palette_texture: ImageTexture

var dim_offset: int = 0

var invuln_offset: int = 0

var husk_offset: int = 0

var submerged_row: int = 0


var terrain_row: int = 0
var _raw: PackedByteArray
var _width := 0
var _height := 0
var _frames: Array = []
var _palette_img: Image
var frame_count: int = 0
var palette_rows: int = 0

var sprite_first_frame: Dictionary = {}
var sprite_frame_count: Dictionary = {}

var sprite_frame_size: Dictionary = {}
var meta: Dictionary = {}


var cameo_override: PaletteAtlas = null


static func load_from(atlas_path: String, palette_path: String, player_colors: Array[Color]) -> PaletteAtlas:
	var pa := PaletteAtlas.new()
	pa._load_atlas(atlas_path)
	pa._load_palette(palette_path, player_colors)
	return pa


func _load_atlas(base: String) -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	var width: int = meta["width"]
	var height: int = meta["height"]
	var raw := FileAccess.get_file_as_bytes(base + ".r8")
	assert(raw.size() == width * height, "Atlasgröße passt nicht zu den Metadaten")

	var img := Image.create_from_data(width, height, false, Image.FORMAT_R8, raw)
	atlas_texture = ImageTexture.create_from_image(img)
	_raw = raw
	_width = width
	_height = height
	_frames = meta["frames"]

	var frames: Array = meta["frames"]
	frame_count = frames.size()
	var table := Image.create(frame_count, 2, false, Image.FORMAT_RGBAF)
	for i in frame_count:
		var f: Dictionary = frames[i]
		table.set_pixel(i, 0, Color(f["x"] / float(width), f["y"] / float(height),
			f["w"] / float(width), f["h"] / float(height)))
		table.set_pixel(i, 1, Color(f["w"], f["h"], 0.0, 0.0))
		var name: String = f["sprite"]
		if not sprite_first_frame.has(name):
			sprite_first_frame[name] = i
			sprite_frame_count[name] = 0
			sprite_frame_size[name] = Vector2i(int(f["w"]), int(f["h"]))
		sprite_frame_count[name] += 1
	frame_table_texture = ImageTexture.create_from_image(table)


const DIM := 0.55


const IRON_TINT := Color(128.0 / 255.0, 0.0, 0.0)
const IRON_ALPHA := 128.0 / 255.0


const HUSK := 1.0 - 180.0 / 255.0


const SUBMERGED_TINT := Color(0.0, 0.0, 0.0)
const SUBMERGED_ALPHA := 140.0 / 255.0


func _load_palette(path: String, player_colors: Array[Color]) -> void:
	var raw := FileAccess.get_file_as_bytes(path)
	assert(raw.size() == 1024, "Palette muss 256×RGBA sein")


	dim_offset = player_colors.size()
	invuln_offset = dim_offset * 2
	terrain_row = dim_offset * 3
	husk_offset = terrain_row + 1
	submerged_row = husk_offset + dim_offset
	palette_rows = submerged_row + 1
	var img := Image.create(256, palette_rows, false, Image.FORMAT_RGBA8)
	for row in dim_offset:
		for i in 256:
			img.set_pixel(i, row, Color8(raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]))
		_apply_remap(img, row, player_colors[row])
		for i in 256:
			var c := img.get_pixel(i, row)

			img.set_pixel(i, row + dim_offset, Color(c.r * DIM, c.g * DIM, c.b * DIM, c.a))

			img.set_pixel(i, row + invuln_offset, Color(
					lerpf(c.r, IRON_TINT.r, IRON_ALPHA),
					lerpf(c.g, IRON_TINT.g, IRON_ALPHA),
					lerpf(c.b, IRON_TINT.b, IRON_ALPHA), c.a))

			img.set_pixel(i, row + husk_offset, Color(c.r * HUSK, c.g * HUSK, c.b * HUSK, c.a))


	for i in 256:
		img.set_pixel(i, submerged_row, Color(SUBMERGED_TINT.r, SUBMERGED_TINT.g, SUBMERGED_TINT.b,
				SUBMERGED_ALPHA * (raw[i * 4 + 3] / 255.0)))


	for i in 256:
		img.set_pixel(i, terrain_row, Color8(raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2], raw[i * 4 + 3]))
	palette_texture = ImageTexture.create_from_image(img)
	_palette_img = img


func make_rgba_texture(sprite: String, frame: int, player_row: int = 0) -> ImageTexture:
	if cameo_override != null and cameo_override.sprite_first_frame.has(sprite):
		return cameo_override.make_rgba_texture(sprite, frame, player_row)
	var f: Dictionary = _frames[frame_index(sprite, frame)]
	var w: int = f["w"]
	var h: int = f["h"]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row_off: int = (int(f["y"]) + y) * _width + int(f["x"])
		for x in w:
			var idx := _raw[row_off + x]
			if idx == 0:
				continue
			if idx == 4:
				img.set_pixel(x, y, Color(0, 0, 0, 0.55))
			else:
				img.set_pixel(x, y, _palette_img.get_pixel(idx, player_row))
	return ImageTexture.create_from_image(img)


static func _apply_remap(img: Image, row: int, base: Color) -> void:
	var lin := base.srgb_to_linear()
	for i in REMAP_COUNT:
		var orig := img.get_pixel(REMAP_FIRST + i, row).srgb_to_linear()
		var value := maxf(orig.r, maxf(orig.g, orig.b))
		var c := Color.from_hsv(lin.h, lin.s, value * lin.v, 1.0)
		img.set_pixel(REMAP_FIRST + i, row, c.linear_to_srgb())


func frame_index(sprite: String, frame: int) -> int:
	return int(sprite_first_frame[sprite]) + frame


const WATER_ROTATION_BASE := 96
const WATER_ROTATION_RANGE := 7
const WATER_ROTATION_TICKS := 4


static func water_phase(tick: int) -> int:
	return int(tick / WATER_ROTATION_TICKS) % WATER_ROTATION_RANGE
