

class_name HomepageDemo
extends RefCounted


const BUILDINGS := ["powr", "barr", "proc", "weap", "dome"]


static func enabled() -> bool:
	return OS.has_feature("homepage_demo") or OS.get_cmdline_user_args().has("--homepage-demo")


static func locked(name: String, definition: Dictionary) -> bool:
	return definition.get("building", false) and int(definition.get("queue", -1)) >= 0 \
			and name not in BUILDINGS


static func configure() -> void:
	ProtoWorld.next_mission = ""
	ProtoWorld.next_setup = {}
	ProtoWorld.next_savegame = ""
	ProtoWorld.next_faction = "soviet"
	ProtoWorld.next_ai_faction = "allies"
	ProtoWorld.next_ai_players = 1
	ProtoWorld.next_ai_slots = []
	ProtoWorld.next_player_spawn = -1
	ProtoWorld.next_player_team = 0
	ProtoWorld.next_crates = false
	ProtoWorld.next_explored_map = true
	ProtoWorld.next_fog = false


static func make_map() -> MapData:
	var m := MapData.new()
	m.slug = "homepage-demo"
	m.title = "PocketRA Demo"
	m.tileset = "temperat"
	m.width = 48
	m.height = 40
	m.bounds = Rect2i(2, 2, 44, 36)
	m.spawns = [Vector2i(12, 23), Vector2i(35, 10)]
	m._tiles.resize(m.width * m.height * 3)
	m._resources.resize(m.width * m.height * 2)
	for y in m.height:
		for x in m.width:
			var k := y * m.width + x
			m._tiles[k * 3] = 255
			m._tiles[k * 3 + 2] = (x * 7 + y * 11) % 16


			if Vector2(x - 10, y - 12).length() < 4.5 or Vector2(x - 36, y - 28).length() < 4.0:
				m._resources[k * 2] = 1
				m._resources[k * 2 + 1] = 12
	return m


static func populate(w: ProtoWorld) -> void:


	w.player_map["Multi0"] = 0
	w.player_map["Multi1"] = 1
	w.player_factions = {0: "soviet", 1: "allies"}
	w.sim.set_faction(0, "soviet")
	w.sim.set_faction(1, "allies")
	w.sim.set_enemy(0, 1, true)
	w.sim.set_enemy(1, 0, true)
	w.sim.give_credits(0, 8000)


	w.sim.set_handicap(1, 50)
	var mcv := w.spawn_unit("mcv", 0, Vector2i(12, 23))
	for c in [Vector2i(8, 20), Vector2i(9, 19), Vector2i(10, 18), Vector2i(11, 19)]:
		w.spawn_unit("e1", 0, c)
	w.spawn_unit("3tnk", 0, Vector2i(15, 20))
	w.spawn_unit("ftrk", 0, Vector2i(16, 21))
	for b in [["fact", 34, 8], ["powr", 39, 8], ["tent", 34, 13], ["proc", 39, 14]]:
		w._add_building(b[0], 1, Vector2i(b[1], b[2]))
	for c in [Vector2i(30, 13), Vector2i(31, 14), Vector2i(32, 15), Vector2i(33, 16)]:
		w.spawn_unit("e1", 1, c)
	w.spawn_unit("jeep", 1, Vector2i(37, 18))


	w._apply_zoom(2.0)
	w._target_zoom = 2.0
	w.center_on(Vector2(17, 23) * ProtoWorld.CELL)


	if mcv != null:
		w.get_tree().create_timer(0.7, false).timeout.connect(func():
			if is_instance_valid(w) and w.sim != null:
				w.sim.order_deploy(PackedInt32Array([mcv.id])))
