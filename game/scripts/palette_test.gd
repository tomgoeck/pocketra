

extends Node2D

const SCALE := 2.0
const PLAYER_COLORS: Array[Color] = [
	Color(0.90, 0.75, 0.20),
	Color(0.85, 0.10, 0.10),
	Color(0.15, 0.35, 0.90),
	Color(0.15, 0.70, 0.25),
]

var _screenshot_path := ""


func _ready() -> void:
	var atlas := PaletteAtlas.load_from("res://assets/atlas/vehicles", "res://assets/atlas/temperat.rgba", PLAYER_COLORS)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/palette_sprite.gdshader")
	atlas.bind_atlases(mat)
	mat.set_shader_parameter("palette", atlas.palette_texture)
	mat.set_shader_parameter("frame_table", atlas.frame_table_texture)
	mat.set_shader_parameter("palette_rows", float(atlas.palette_rows))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = _unit_quad()


	var facings := 16
	var sprites := ["2tnk", "harv"]
	mm.instance_count = facings * PLAYER_COLORS.size() * sprites.size()

	var i := 0
	var y := 16.0
	for s in sprites:
		var size: Vector2i = atlas.sprite_frame_size[s]
		var step_x := size.x * SCALE + 6.0
		for row in PLAYER_COLORS.size():
			for f in facings:
				var xf := Transform2D(0.0, Vector2(SCALE, SCALE), 0.0, Vector2(16.0 + f * step_x, y))
				mm.set_instance_transform_2d(i, xf)
				mm.set_instance_custom_data(i, PaletteAtlas.custom_data(atlas.frame_index(s, f * 2), row))
				i += 1
			y += size.y * SCALE + 6.0
		y += 24.0

	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	add_child(node)

	var args := OS.get_cmdline_user_args()
	var k := args.find("--screenshot")
	if k >= 0 and k + 1 < args.size():
		_screenshot_path = args[k + 1]


func _process(_delta: float) -> void:
	if _screenshot_path != "" and Engine.get_process_frames() >= 3:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		print("Screenshot: ", _screenshot_path)
		_screenshot_path = ""
		get_tree().quit()


static func _unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
