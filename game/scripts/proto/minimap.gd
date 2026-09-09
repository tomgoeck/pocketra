

class_name Minimap
extends Control

signal navigate(world_pos: Vector2)

signal focus_base()


const PING_SECONDS := 10.0


const RADAR_FRAME_W := 136
const RADAR_FRAME_H := 117
const RADAR_FRAMES := 21
const IDLE_FIRST := 0
const IDLE_LAST := 7
const SWITCH_SECONDS := 0.6
const IDLE_MS := 380

var world: ProtoWorld
var _dragging := false
var _pings: Array = []
var _last_tap := -10.0
var _shroud_img: Image
var _shroud_tex: ImageTexture
var _shroud_version := -1
var _radar_tex: Texture2D
var _radar_on := false
var _switch_t := 99.0
var _res_img: Image
var _res_tex: ImageTexture
var _res_version := -1
var _res_next_ms := 0
var _terr_img: Image
var _terr_tex: ImageTexture
var _terr_version := -1


func _terrain_palette() -> PackedColorArray:
	var cols := PackedColorArray()
	var meta: Dictionary = {}
	if world.atlas() != null:
		meta = world.atlas().meta.get("terrain_colors", {})

	var fallback := Color.html(str(meta.get("Clear", "284428")))
	for name in ProtoWorld.TERRAIN_ORDER:
		cols.append(Color.html(str(meta[name])) if meta.has(name) else fallback)
	return cols


func _update_terrain() -> void:
	if world == null or world.sim == null:
		return
	var ter: PackedByteArray = world.terrain_map()
	if ter.size() != world.map_w * world.map_h or world.terrain_version == _terr_version:
		return
	_terr_version = world.terrain_version
	if _terr_img == null or _terr_img.get_width() != world.map_w or _terr_img.get_height() != world.map_h:
		_terr_img = Image.create(world.map_w, world.map_h, false, Image.FORMAT_RGBA8)
		_terr_tex = null
	var cols := _terrain_palette()
	var r8 := PackedByteArray()
	var g8 := PackedByteArray()
	var b8 := PackedByteArray()
	for c: Color in cols:
		r8.append(c.r8)
		g8.append(c.g8)
		b8.append(c.b8)
	var px := PackedByteArray()
	px.resize(ter.size() * 4)
	for i in ter.size():
		var t: int = ter[i] if ter[i] < r8.size() else 0
		px[i * 4] = r8[t]
		px[i * 4 + 1] = g8[t]
		px[i * 4 + 2] = b8[t]
		px[i * 4 + 3] = 255
	_terr_img.set_data(world.map_w, world.map_h, false, Image.FORMAT_RGBA8, px)
	if _terr_tex == null:
		_terr_tex = ImageTexture.create_from_image(_terr_img)
	else:
		_terr_tex.update(_terr_img)


const ORE_COLOR := Color8(0x94, 0x80, 0x60)
const GEM_COLOR := Color8(0x9C, 0x78, 0xE8)

const RES_ALPHA := 128


func _update_resources() -> void:
	if world == null or world.sim == null:
		return
	var v: int = world.sim.resource_version()
	if v == _res_version and _res_img != null \
			and _res_img.get_width() == world.map_w and _res_img.get_height() == world.map_h:
		return


	var now := Time.get_ticks_msec()
	if now < _res_next_ms and _res_img != null:
		return
	_res_next_ms = now + 500
	var map: PackedByteArray = world.sim.resource_map()
	if map.size() != world.map_w * world.map_h:
		return
	_res_version = v
	if _res_img == null or _res_img.get_width() != world.map_w or _res_img.get_height() != world.map_h:
		_res_img = Image.create(world.map_w, world.map_h, false, Image.FORMAT_RGBA8)
		_res_tex = null
	var px := PackedByteArray()
	px.resize(map.size() * 4)


	for i in map.size():
		if (map[i] & 0x0F) == 0:
			continue
		var c: Color = GEM_COLOR if (map[i] >> 4) == 2 else ORE_COLOR
		px[i * 4] = int(c.r8)
		px[i * 4 + 1] = int(c.g8)
		px[i * 4 + 2] = int(c.b8)
		px[i * 4 + 3] = RES_ALPHA
	_res_img.set_data(world.map_w, world.map_h, false, Image.FORMAT_RGBA8, px)
	if _res_tex == null:
		_res_tex = ImageTexture.create_from_image(_res_img)
	else:
		_res_tex.update(_res_img)


func _update_shroud() -> void:
	if world == null or world.sim == null:
		return
	var vis: PackedByteArray = world.vis_map()
	if vis.size() != world.map_w * world.map_h or world.vis_version() == _shroud_version:
		return
	_shroud_version = world.vis_version()
	if _shroud_img == null or _shroud_img.get_width() != world.map_w or _shroud_img.get_height() != world.map_h:
		_shroud_img = Image.create(world.map_w, world.map_h, false, Image.FORMAT_RGBA8)
		_shroud_tex = null
	var px := PackedByteArray()
	px.resize(vis.size() * 4)
	for i in vis.size():
		var v := vis[i]
		px[i * 4 + 3] = 0 if v == 2 else (255 if v == 0 else 128)
	_shroud_img.set_data(world.map_w, world.map_h, false, Image.FORMAT_RGBA8, px)
	if _shroud_tex == null:
		_shroud_tex = ImageTexture.create_from_image(_shroud_img)
	else:
		_shroud_tex.update(_shroud_img)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var s := Dp.px(120)
	custom_minimum_size = Vector2(s, s)
	size = custom_minimum_size


func _map_rect() -> Rect2:
	if world == null:
		return Rect2(0, 0, 64 * ProtoWorld.CELL, 64 * ProtoWorld.CELL)
	return Rect2(Vector2(world.bounds.position) * ProtoWorld.CELL, Vector2(world.bounds.size) * ProtoWorld.CELL)


func _to_world(local: Vector2) -> Vector2:
	var r := _map_rect()
	return r.position + local / size * r.size


func add_ping(world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for p in _pings:
		if p[0].distance_to(world_pos) < ProtoWorld.CELL * 4:
			p[1] = now + PING_SECONDS
			return
	_pings.append([world_pos, now + PING_SECONDS])
	while _pings.size() > 6:
		_pings.pop_front()


func _tapped() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap < 0.3:
		_last_tap = -10.0
		focus_base.emit()
	else:
		_last_tap = now


func _gui_input(e: InputEvent) -> void:
	if not _radar_on:


		accept_event()
		return
	if e is InputEventScreenTouch:
		_dragging = e.pressed
		if e.pressed:
			navigate.emit(_to_world(e.position))
			_tapped()
		accept_event()
	elif e is InputEventScreenDrag and _dragging:
		navigate.emit(_to_world(e.position))
		accept_event()


func _process(delta: float) -> void:
	if world != null:
		var on := world.has_radar()
		if on != _radar_on:
			_radar_on = on
			_switch_t = 0.0

			if world.sfx != null:
				world.sfx.play_ui("radaron2" if on else "radardn1")
		else:
			_switch_t += delta
	queue_redraw()


func _radar_sheet() -> Texture2D:
	if _radar_tex == null and world != null:
		var path := "res://assets/ui/radar_%s.png" % ("soviet" if world.player_faction() == "soviet" else "allies")
		if ResourceLoader.exists(path):
			_radar_tex = load(path)
	return _radar_tex


func _radar_phase() -> float:
	if _switch_t < SWITCH_SECONDS:
		var t := _switch_t / SWITCH_SECONDS

		return lerpf(20.0, 10.0 if _radar_on else float(IDLE_FIRST), t)

	var span := float(IDLE_LAST - IDLE_FIRST)
	var p := fmod(Time.get_ticks_msec() / float(IDLE_MS), span * 2.0)
	return IDLE_FIRST + (p if p <= span else span * 2.0 - p)


static var _scan_tex: ImageTexture


static func _scanlines() -> ImageTexture:
	if _scan_tex == null:
		var img := Image.create(1, 2, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color(0, 0, 0, 0))
		img.set_pixel(0, 1, Color(0, 0, 0, 0.40))
		_scan_tex = ImageTexture.create_from_image(img)
	return _scan_tex


static var _vignette_tex: ImageTexture


static func _vignette() -> ImageTexture:
	if _vignette_tex == null:
		var d := 32
		var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
		var c := (d - 1) / 2.0
		for y in d:
			for x in d:
				var r := Vector2(x - c, y - c).length() / c
				img.set_pixel(x, y, Color(0, 0, 0, clampf((r - 0.55) * 1.1, 0.0, 0.75)))
		_vignette_tex = ImageTexture.create_from_image(img)
	return _vignette_tex


func _draw_radar_screen() -> void:
	var tex := _radar_sheet()
	var rect := Rect2(Vector2.ZERO, size)
	if tex == null:
		draw_rect(rect, Color(0.05, 0.06, 0.05, 0.95), true)
		return
	draw_rect(rect, Color(0.02, 0.03, 0.02, 1.0), true)
	var phase := clampf(_radar_phase(), 0.0, RADAR_FRAMES - 1.0)
	var f0 := int(floor(phase))
	var f1 := mini(f0 + 1, RADAR_FRAMES - 1)
	var mix := phase - f0
	var scale := maxf(size.x / RADAR_FRAME_W, size.y / RADAR_FRAME_H)
	var dest := Rect2((size - Vector2(RADAR_FRAME_W, RADAR_FRAME_H) * scale) / 2.0,
			Vector2(RADAR_FRAME_W, RADAR_FRAME_H) * scale)

	var tint := Color(0.52, 0.66, 0.50)
	draw_texture_rect_region(tex, dest, Rect2(f0 * RADAR_FRAME_W, 0, RADAR_FRAME_W, RADAR_FRAME_H), tint)
	if mix > 0.01 and f1 != f0:
		var t2 := tint
		t2.a = mix
		draw_texture_rect_region(tex, dest, Rect2(f1 * RADAR_FRAME_W, 0, RADAR_FRAME_W, RADAR_FRAME_H), t2)
	draw_texture_rect(_scanlines(), rect, true, Color(1, 1, 1, 1))
	draw_texture_rect(_vignette(), rect, false)


func _draw() -> void:
	if world == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.28, 0.14, 0.95))
		return
	if not _radar_on or _switch_t < SWITCH_SECONDS:
		_draw_radar_screen()
		draw_rect(Rect2(Vector2.ZERO, size), HudTheme.BORDER, false, maxf(1.0, Dp.px(1.5)))
		return
	var r := _map_rect()
	var k := size / r.size
	var dot := maxf(Dp.px(2), 2.0)
	var src := Rect2(Vector2(world.bounds.position), Vector2(world.bounds.size))
	var dst := Rect2(Vector2.ZERO, size)


	_update_terrain()
	if _terr_tex != null:
		draw_texture_rect_region(_terr_tex, dst, src, Color.WHITE, false)
	else:
		draw_rect(dst, Color(0.22, 0.28, 0.14, 0.95))


	_update_resources()
	if _res_tex != null:
		draw_texture_rect_region(_res_tex, dst, src, Color.WHITE, false)


	var vis_ready: bool = world.vis_map().size() == world.map_w * world.map_h


	for u in world.units:
		var t: Dictionary = world.types[u.type]
		if not u.alive or not u.visible or t.get("decoration", false):
			continue
		if not vis_ready and u.player != 0:
			continue
		var c: Color = world.player_colors[u.player] if u.player < world.player_colors.size() else Color.WHITE
		if u.selected:
			c = Color.WHITE
		if t.get("building", false):


			var rows: PackedStringArray = str(t.get("footprint", "x")).split(" ")
			var fw: int = maxi(1, rows[0].length())
			var origin := u.pos / ProtoWorld.CELL - Vector2(fw / 2.0, float(t.get("sprite_h", 1)) / 2.0)
			for fy in rows.size():
				for fx in rows[fy].length():
					if rows[fy][fx] == "_":
						continue
					var cell := (origin + Vector2(fx, fy)) * ProtoWorld.CELL
					draw_rect(Rect2((cell - r.position) * k, Vector2(ProtoWorld.CELL, ProtoWorld.CELL) * k), c)
		else:
			draw_rect(Rect2((u.pos - r.position) * k - Vector2(dot, dot) / 2.0, Vector2(dot, dot)), c)


	_update_shroud()
	if _shroud_tex != null:
		draw_texture_rect_region(_shroud_tex, dst, src, Color.WHITE, false)

	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_pings.size() - 1, -1, -1):
		if _pings[i][1] < now:
			_pings.remove_at(i)
			continue
		var c: Vector2 = (_pings[i][0] - r.position) * k
		var phase := fposmod(now, 1.0)
		draw_arc(c, Dp.px(4) + phase * Dp.px(8), 0, TAU, 20, Color(1.0, 0.2, 0.15, 1.0 - phase), maxf(1.0, Dp.px(1.5)))


	for n in world.nuke_targets():
		var nc: Vector2 = (n["pos"] - r.position) * k
		var nphase := fposmod(now * 1.1, 1.0)
		draw_arc(nc, Dp.px(3) + nphase * Dp.px(6), 0, TAU, 16, Color(1.0, 0.15, 0.1, 1.0), maxf(1.0, Dp.px(1.8)))
		draw_circle(nc, Dp.px(1.6), Color(1.0, 0.85, 0.25))
	var v := world.visible_world_rect()
	draw_rect(Rect2((v.position - r.position) * k, v.size * k), Color.WHITE, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), HudTheme.BORDER, false, maxf(1.0, Dp.px(1.5)))
