

class_name RulesDb
extends RefCounted

enum Armor { NONE, WOOD, LIGHT, HEAVY, CONCRETE, TREE }
enum Queue { BUILDING = 0, INFANTRY = 1, VEHICLE = 2, DEFENSE = 3, AIRCRAFT = 4, SHIP = 5 }

const DEATH_TYPES := ["DefaultDeath", "BulletDeath", "SmallExplosionDeath", "ExplosionDeath", "FireDeath", "ElectricityDeath"]
const ARMOR_NAMES := ["None", "Wood", "Light", "Heavy", "Concrete", "Tree"]

const TARGET_TYPES := ["GroundActor", "WaterActor", "AirborneActor", "Infantry", "Vehicle", "Structure", "Defense",
	"Wall", "Mine", "Trees", "NoAutoTarget", "Heal", "Repair", "Ship", "Submarine", "Underwater",
	"C4", "Barrel", "Crate", "Disguise", "Ant", "Bridge", "Husk", "DetonateAttack",
	"SpyInfiltrate", "ThiefInfiltrate", "Mission Objectives"]

const CAPTURE_TYPES := ["building", "vehicle", "aircraft", "husk"]

const CRUSH_CLASSES := ["infantry", "wall", "heavywall", "mine", "crate"]
const DETECTION_TYPES := ["Cloak", "Mine", "Underwater"]
const UNCLOAK_ON := ["Attack", "Move", "Unload", "Infiltrate", "Demolish", "Load", "Heal", "Dock"]
const SP_KINDS := ["ironcurtain", "chronoshift", "nuke", "gps"]

const SP_NOTIFY := {"IronCurtainCharging": 21, "IronCurtainReady": 22, "ChronosphereCharging": 23, "ChronosphereReady": 24,
					"AbombPrepping": 25, "AbombReady": 26, "SatelliteLaunched": 28}


const LOCO_CRUSHES := {
	"naval": ["crate"],
	"lcraft": ["crate"],
	"foot": ["mine", "crate"],
	"wheeled": ["mine", "crate"],
	"heavywheeled": ["wall", "mine", "crate", "infantry"],
	"lighttracked": ["wall", "mine", "crate"],
	"tracked": ["wall", "infantry", "mine", "crate"],
	"heavytracked": ["wall", "infantry", "mine", "crate", "heavywall"],
}

const PRONE_TRIGGER := "TriggerProne"
const PRONE_MODIFIER := "Prone50Percent"


const QUEUE_NAMES := {"Building": Queue.BUILDING, "Infantry": Queue.INFANTRY, "Vehicle": Queue.VEHICLE,
	"Defense": Queue.DEFENSE, "Aircraft": Queue.AIRCRAFT, "Ship": Queue.SHIP,
	"Boat": Queue.SHIP, "Submarine": Queue.SHIP}

const TERRAIN_NAMES := ["Clear", "Rough", "Road", "Bridge", "Ore", "Gems", "Beach", "Water", "River", "Rock", "Tree", "Wall"]


const SELECT_PRIORITY_OVERRIDE := {"harv": 6, "mcv": 8, "mnly": 8, "truk": 8, "e6": 8, "thf": 8}
const CELL := 24

static var _data: Dictionary = {}

var actors: Dictionary
var types := {}
var weapons := {}
var effects := {}
var voices := {}
var ai := {}
var _atlas: PaletteAtlas
var _weapon_defs := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var path := "res://assets/rules.json"
		if FileAccess.file_exists(path):
			_data = JSON.parse_string(FileAccess.get_file_as_string(path))
		else:
			push_error("assets/rules.json fehlt — tools/rules2json.py ausführen")
	return _data


func build(atlas: PaletteAtlas, overrides: Dictionary = {}, campaign: bool = false,
		map_format: String = "") -> void:
	_atlas = atlas
	var d := data()
	var rules_format := str(d.get("rules_format", ""))
	if not overrides.is_empty() and map_format != rules_format:
		var msg := ("Kartenregeln veraltet: Karte und rules.json stammen aus verschiedenen Ständen von "
			+ "tools/rules2json.py (Karte %s, rules.json %s). Die Kartenregeln sind unvollständig — "
			+ "python3 tools/rules2json.py && python3 tools/mapconvert.py") % [
				map_format if map_format != "" else "ohne Stempel", rules_format]
		push_warning(msg)
		print("WARNUNG: " + msg)
	actors = d.get("actors", {}).duplicate()
	var weapon_defs: Dictionary = d.get("weapons", {}).duplicate()


	if campaign:
		_apply_actor_overrides(d.get("actors_campaign", {}))
	_apply_actor_overrides(overrides.get("actors", {}))
	for name in overrides.get("weapons", {}):
		weapon_defs[name] = overrides["weapons"][name]
	ai = d.get("ai", {})
	_weapon_defs = weapon_defs
	_build_weapons(weapon_defs)

	for name in actors:
		for arm in actors[name].get("armaments", []):
			var wn: String = arm.get("weapon", "")
			if weapons.has(wn) and arm.get("relationships", ["Enemy"]).has("Ally"):
				weapons[wn]["relation"] = 1
				weapons[wn]["ground"] = true
				weapons[wn]["air_only"] = false
	_build_voices(d.get("voices", {}))
	for name in actors:
		var a: Dictionary = actors[name]
		if not a.get("supported", false):
			continue
		var t := _build_type(name, a)
		if not t.is_empty():
			types[name] = t

	for name in types:
		var t: Dictionary = types[name]
		if t.has("free_actor") and not types.has(t["free_actor"]):
			t.erase("free_actor")
		if t.has("transforms") and not types.has(t["transforms"]):
			t.erase("transforms")


func _apply_actor_overrides(over_actors: Dictionary) -> void:
	for name in over_actors:
		var base: Dictionary = actors.get(name, {})
		var over: Dictionary = over_actors[name].duplicate()
		over["supported"] = base.get("supported", over.get("supported", true))
		if over.get("sequences", {}).is_empty() and not base.is_empty():
			over["sequences"] = base.get("sequences", {})
		actors[name] = over


func _has_sprite(stem: String) -> bool:
	return _atlas.sprite_frame_count.has(stem)


func _add_frame_list(t: Dictionary, key: String, seq: Dictionary, body: String) -> void:
	var raw: Array = seq.get("frames", [])
	if raw.is_empty():
		return
	var stem := _stem(str(seq.get("file", body + ".shp")))
	if not _has_sprite(stem):
		return
	var arr: Array = []
	for rf in raw:
		arr.append(_atlas.frame_index(stem, int(rf)))
	t[key] = arr


func _add_facing_frame_list(t: Dictionary, key: String, len_key: String, seq: Dictionary, body: String) -> void:
	if seq.is_empty():
		return
	var stem := _stem(str(seq.get("file", body + ".shp")))
	if not _has_sprite(stem):
		return
	var start := int(seq.get("start", 0))
	var length := int(seq.get("length", 1))
	var facings := int(seq.get("facings", 1))
	if length <= 0 or facings <= 0:
		return
	var arr: Array = []
	for fc in range(facings):
		for fr in range(length):
			arr.append(_atlas.frame_index(stem, start + fc * length + fr))
	t[key] = arr
	t[len_key] = length


static func _stem(file: String) -> String:
	return file.get_basename().get_file().to_lower()


static func _mask(names: Array, table: Array) -> int:
	var m := 0
	for n in names:
		var i: int = table.find(str(n))
		if i >= 0:
			m |= 1 << i
	return m


static func _hit_radius(a: Dictionary) -> int:
	var hs: Dictionary = a.get("hit_shape", {})
	if hs.is_empty():
		var bounds: Array = a.get("bounds", [1024, 1024])
		return int(bounds[0]) / 2
	if hs.get("type", "Circle") == "Circle":
		return int(hs.get("radius", 426))
	var br: Array = hs.get("bottom_right", [512, 512])
	return maxi(int(br[0]), int(br[1]) if br.size() > 1 else 0)


func _seq(a: Dictionary, name: String) -> Dictionary:
	return a.get("sequences", {}).get(name, {})


func effect_key(image: String, seq: String) -> String:
	var key := "%s/%s" % [image, seq]
	if effects.has(key):
		return key
	var e: Dictionary = data().get("effects", {}).get(key, {})
	if e.is_empty():
		return ""
	var stem := _stem(e["file"])
	if not _has_sprite(stem):
		return ""
	var n: int = _atlas.sprite_frame_count[stem]
	var start: int = e.get("start", 0)
	var length: int = e.get("length", -1)
	if length < 0:
		length = n - start
	effects[key] = {"sprite": stem, "start": start, "length": maxi(1, mini(length, n - start)), "ticks": maxi(1, int(round(float(e.get("tick", 40)) / 40.0)))}
	return key


func _build_weapons(src: Dictionary) -> void:
	for name in src:
		var w: Dictionary = src[name]


		var dmg := {}
		var damage := 0
		var valid := 0
		var invalid := 0
		for wh in w.get("warheads", []):
			if wh["type"] != "SpreadDamage" and wh["type"] != "TargetDamage":
				continue
			if dmg.is_empty():
				dmg = wh
			if int(wh.get("spread", 0)) == int(dmg.get("spread", 0)):
				damage += int(wh.get("damage", 0))
			valid |= _mask(wh.get("valid_targets", []), TARGET_TYPES)
			invalid |= _mask(wh.get("invalid_targets", []), TARGET_TYPES)


		var extra_groups: Array = []
		for wh in w.get("warheads", []):
			if wh["type"] != "SpreadDamage" and wh["type"] != "TargetDamage":
				continue
			if int(wh.get("spread", 0)) == int(dmg.get("spread", 0)):
				continue
			var spread: int = int(wh.get("spread", 0))
			var g = null
			for existing in extra_groups:
				if int(existing["spread"]) == spread:
					g = existing
					break
			if g == null:
				g = {"spread": spread, "delay": int(wh.get("delay", 0)), "damage": 0, "dmg": wh, "valid": 0, "invalid": 0}
				extra_groups.append(g)
			g["damage"] += int(wh.get("damage", 0))
			g["valid"] |= _mask(wh.get("valid_targets", []), TARGET_TYPES)
			g["invalid"] |= _mask(wh.get("invalid_targets", []), TARGET_TYPES)
		var extra_warheads: Array = []
		for g in extra_groups:
			var g_dtypes: Array = g["dmg"].get("damage_types", [])
			var g_versus: Array = [100, 100, 100, 100, 100, 100]
			var g_vs: Dictionary = g["dmg"].get("versus", {})
			for i in ARMOR_NAMES.size():
				if g_vs.has(ARMOR_NAMES[i]):
					g_versus[i] = int(g_vs[ARMOR_NAMES[i]])
			var g_falloff: Array = g["dmg"].get("falloff", [])
			if g_falloff.is_empty():
				g_falloff = [100, 37, 14, 5, 0]
			extra_warheads.append({
				"delay": int(g["delay"]), "spread": maxi(1, int(g["spread"])), "damage": int(g["damage"]),
				"falloff": g_falloff.slice(0, 8), "versus": g_versus,
				"valid_targets": int(g["valid"]), "invalid_targets": int(g["invalid"]),
				"trigger_prone": g_dtypes.has(PRONE_TRIGGER), "prone_damage": 50 if g_dtypes.has(PRONE_MODIFIER) else 100,
			})


		var destroy_resource: Array = []
		for wh in w.get("warheads", []):
			if wh["type"] == "DestroyResource":
				destroy_resource.append({"delay": int(wh.get("delay", 0)), "size": int(wh.get("size", 0))})
		var fx: Array = []
		var impact_sound := ""
		for wh in w.get("warheads", []):
			if wh["type"] == "CreateEffect" and fx.is_empty():
				var image: String = wh.get("image", "explosion")

				for ex_name in wh.get("explosions", []):
					var key := effect_key(image, ex_name)
					if key != "":
						fx.append(key)
				var snd: Array = wh.get("impact_sounds", [])
				if not snd.is_empty():
					impact_sound = snd[0]
		var versus: Array = [100, 100, 100, 100, 100, 100]
		var vs: Dictionary = dmg.get("versus", {})
		for i in ARMOR_NAMES.size():
			if vs.has(ARMOR_NAMES[i]):
				versus[i] = int(vs[ARMOR_NAMES[i]])
		var damage_type := 0
		var dtypes: Array = dmg.get("damage_types", [])
		for dt in dtypes:
			var k := DEATH_TYPES.find(dt)
			if k >= 0:
				damage_type = k


		var cluster_weapon := ""
		var cluster_offsets := PackedInt32Array()
		for wh in w.get("warheads", []):
			if wh["type"] != "FireCluster" or cluster_weapon != "":
				continue
			cluster_weapon = String(wh.get("weapon", ""))
			var dims: Array = wh.get("dimensions", [1, 1])
			var dw: int = int(dims[0])
			var dh: int = int(dims[1]) if dims.size() > 1 else 1
			var fp: String = String(wh.get("footprint", "")).replace(" ", "")
			for j in dh:
				for k in dw:
					var idx: int = j * dw + k
					if idx < fp.length() and fp[idx] == "X":
						cluster_offsets.append(k - (dw - 1) / 2)
						cluster_offsets.append(j - (dh - 1) / 2)
		var pj: Dictionary = w.get("projectile", {})
		var ptype: String = pj.get("type", "Bullet")
		var speed: int = int(pj.get("speed", 0)) if ptype in ["Bullet", "Missile"] else 0
		var sprite := _stem(str(pj.get("image", "")))


		var zap_bright := ""
		var zap_dim := ""
		var zap_duration := 0
		if ptype == "TeslaZap":
			var zap_image: String = str(pj.get("image", ""))
			if zap_image == "":
				zap_image = "litning"
			zap_bright = effect_key(zap_image, "bright")
			zap_dim = effect_key(zap_image, "dim")
			zap_duration = 2


		var missile: bool = ptype == "Missile"
		var trail_effect := ""
		if missile and str(pj.get("trail_image", "")) != "":
			trail_effect = effect_key(str(pj.get("trail_image", "")), "idle")
		var reports: Array = w.get("report", [])
		var delays: Array = w.get("burst_delays", [5])

		var falloff: Array = dmg.get("falloff", [])
		if falloff.is_empty():
			falloff = [100, 37, 14, 5, 0]
		falloff = falloff.slice(0, 8)
		var wvalid: Array = w.get("valid_targets", [])
		weapons[name] = {
			"range": int(w.get("range", 0)), "reload": int(w.get("reload", 1)), "burst": int(w.get("burst", 1)),
			"burst_delay": int(delays[0]) if not delays.is_empty() else 5,
			"min_range": int(w.get("min_range", 0)),
			"damage": damage, "spread": maxi(1, int(dmg.get("spread", 128))), "versus": versus,
			"falloff": falloff,


			"delay": int(dmg.get("delay", 0)),
			"valid_targets": valid, "invalid_targets": invalid, "relation": 0,
			"trigger_prone": dtypes.has(PRONE_TRIGGER), "prone_damage": 50 if dtypes.has(PRONE_MODIFIER) else 100,
			"damage_type": damage_type, "speed": speed, "inaccuracy": int(pj.get("inaccuracy", 0)),
			"sprite": sprite if sprite != "" and _has_sprite(sprite) else "",
			"zap_bright": zap_bright, "zap_dim": zap_dim, "zap_duration": zap_duration,
			"missile": missile,
			"missile_turn_rate": int(pj.get("turn_rate", 20)),
			"missile_range_limit": int(pj.get("range_limit", 0)),
			"missile_arm": int(pj.get("arm", 0)),
			"missile_lock_on_probability": int(pj.get("lock_on_probability", 100)),
			"missile_lock_on_inaccuracy": int(pj.get("lock_on_inaccuracy", -1)),
			"missile_close_enough": int(pj.get("close_enough", 298)),
			"missile_trail_effect": trail_effect,
			"missile_trail_interval": int(pj.get("trail_interval", 2)),
			"extra_warheads": extra_warheads,
			"destroy_resource": destroy_resource,


			"sprite_start": int(pj.get("start", 0)),
			"sprite_facings": maxi(1, int(pj.get("facings", 1))),
			"sprite_classic": bool(pj.get("classic", false)),
			"impacts": fx, "impact": fx[0] if not fx.is_empty() else "",
			"cluster_weapon": cluster_weapon, "cluster_offsets": cluster_offsets,
			"report": reports[0] if not reports.is_empty() else "", "impact_sound": impact_sound,

			"ground": valid == 0 or (valid & ~((1 << TARGET_TYPES.find("AirborneActor")) | (1 << TARGET_TYPES.find("WaterActor")) | (1 << TARGET_TYPES.find("Underwater")) | (1 << TARGET_TYPES.find("Submarine")) | (1 << TARGET_TYPES.find("Ship")))) != 0,
			"air_only": valid != 0 and (valid & ~(1 << TARGET_TYPES.find("AirborneActor"))) == 0,
		}
		if wvalid.has("AirborneActor") and not (wvalid.has("GroundActor") or wvalid.has("Ground")):
			weapons[name]["air_only"] = true
			weapons[name]["ground"] = false


func _build_voices(src: Dictionary) -> void:
	for set_name in src:
		var v: Dictionary = src[set_name]
		var per_faction := {}
		for faction in ["allies", "soviet"]:
			var variants: Array = v.get("variants", {}).get(faction, [])
			var out := {}
			for kind in v.get("voices", {}):
				var names: Array = v.get("voices", {})[kind]
				var use_variants: Array = [] if v.get("disable_variants", []).has(kind) else variants
				out[String(kind).to_lower()] = {"clips": names.duplicate(), "variants": use_variants.duplicate()}
			per_faction[faction] = out
		voices[set_name] = per_faction


func _primary_weapon(a: Dictionary) -> String:
	for arm in a.get("armaments", []):
		if arm.get("requires", "") != "":
			continue
		var w: String = arm.get("weapon", "")
		if weapons.has(w) and weapons[w]["ground"] and not weapons[w]["air_only"]:
			return w


	for arm in a.get("armaments", []):
		if arm.get("requires", "") != "":
			continue
		var wa: String = arm.get("weapon", "")
		if weapons.has(wa) and weapons[wa]["air_only"]:
			return wa
	if a.get("attack", {}).get("type", "") == "garrisoned":

		for want_name in ["garrisoned", ""]:
			for unit in a.get("cargo_initial", []):
				var occ: Dictionary = actors.get(unit, {})
				for arm in occ.get("armaments", []):
					if want_name != "" and arm.get("name", "") != want_name:
						continue
					var w: String = arm.get("weapon", "")
					if weapons.has(w) and weapons[w]["ground"] and not weapons[w]["air_only"]:
						return w
	return ""


func _rotors(a: Dictionary, seqs: Dictionary) -> Array:
	var air := {}
	var ground := {}
	for ov in a.get("idle_overlays", []):
		var req: String = str(ov.get("requires", ""))
		var key := str(ov.get("offset", [0, 0, 0]))
		if req.begins_with("!airborne"):
			ground[key] = ov
		elif req.begins_with("airborne"):
			air[key] = ov
	var out: Array = []
	for key in air:
		var entry := _rotor_seq(seqs, str(air[key].get("sequence", "rotor")))
		if entry.is_empty():
			continue
		var off: Array = air[key].get("offset", [0, 0, 0])
		entry["ox"] = int(off[0])
		entry["oy"] = int(off[1]) if off.size() > 1 else 0
		entry["oz"] = int(off[2]) if off.size() > 2 else 0
		var g: Dictionary = _rotor_seq(seqs, str(ground.get(key, {}).get("sequence", ""))) if ground.has(key) else {}
		if not g.is_empty():
			entry["ground_sprite"] = g["sprite"]
			entry["ground_start"] = g["start"]
			entry["ground_len"] = g["len"]
			entry["ground_ticks"] = g["ticks"]
		out.append(entry)
	return out


func _rotor_seq(seqs: Dictionary, name: String) -> Dictionary:
	var sq: Dictionary = seqs.get(name, {})
	if sq.is_empty():
		return {}
	var stem := _stem(str(sq.get("file", name + ".shp")))
	if not _has_sprite(stem):
		return {}
	return {"sprite": stem, "start": int(sq.get("start", 0)), "len": maxi(1, int(sq.get("length", 1))),
			"ticks": maxi(1, int(round(float(sq.get("tick", 40)) / 40.0)))}


func _death_effect(actor: String, suffix: String, sq: Dictionary, body: String) -> String:
	if sq.is_empty():
		return ""
	var stem := _stem(str(sq.get("file", body + ".shp")))
	if not _has_sprite(stem):
		return ""
	var n: int = _atlas.sprite_frame_count[stem]
	var start: int = int(sq.get("start", 0))
	var length: int = int(sq.get("length", 1))
	if length < 0:
		length = n - start
	length = mini(length, n - start)
	if length <= 0:
		return ""
	var key := "%s/%s" % [actor, suffix]
	if not effects.has(key):
		effects[key] = {"sprite": stem, "start": start, "length": length,
						"ticks": maxi(1, int(round(float(sq.get("tick", 40)) / 40.0)))}
	return key


func _build_bridge_type(name: String, a: Dictionary) -> Dictionary:
	var bd: Dictionary = a.get("building", {})
	var dims: Array = bd.get("dimensions", [1, 1])
	var w: int = int(dims[0])
	var h: int = int(dims[1]) if dims.size() > 1 else 1
	return {
		"name": name, "display_name": a.get("display_name", name), "body": "", "invisible": true,
		"hp": int(a.get("hp", 1)), "armor": maxi(0, ARMOR_NAMES.find(a.get("armor", "None"))),
		"building": true, "decoration": true, "wall": false, "combat": false,
		"footprint": bd.get("footprint", "x"), "sprite_h": h,
		"bounds": Vector2(w * CELL, h * CELL),
		"hit_radius": w * 512, "range_radius": (w - 1) * 512,
		"targetable": true,
		"target_types": _mask(a.get("target_types", []), TARGET_TYPES),
		"target_types_damaged": 0,
		"idle_len": 1, "damaged_frame": 0, "death_effects": [],
		"gives_buildable_area": false, "defense": false,
		"voice": "", "voice_overrides": {}, "death_voices": {},
		"reveals": 0, "reveal_cells": 0, "reveal_range": 0,
		"required_short_game": 0, "must_be_destroyed": false,
		"captures": false, "capturable": false,
		"destroyed_sounds": a.get("destroyed_sounds", []),
		"bridge": a["bridge"],
	}


static func _seq_offset(seq: Dictionary) -> Vector2i:
	var off: Array = seq.get("offset", [0, 0])
	return Vector2i(int(off[0]) if off.size() > 0 else 0, int(off[1]) if off.size() > 1 else 0)


func _build_type(name: String, a: Dictionary) -> Dictionary:


	if a.has("bridge"):
		return _build_bridge_type(name, a)
	var seqs: Dictionary = a.get("sequences", {})
	var idle: Dictionary = seqs.get("idle", seqs.get("stand", {}))
	var body := _stem(str(idle.get("file", a.get("image", name) + ".shp")))
	if not _has_sprite(body):
		body = _stem(a.get("image", name) + ".shp")
	if not _has_sprite(body):
		return {}
	var size: Vector2i = _atlas.sprite_frame_size[body]
	var bounds: Array = a.get("bounds", [1024, 1024])
	var t := {
		"name": name, "display_name": a.get("display_name", name), "body": body,
		"hp": int(a.get("hp", 1)), "armor": maxi(0, ARMOR_NAMES.find(a.get("armor", "None"))),
		"bounds": Vector2(float(bounds[0]) * CELL / 1024.0, float(bounds[1]) * CELL / 1024.0),

		"hit_radius": _hit_radius(a), "combat": false, "targetable": a.has("hp") and a.has("target_types"),


		"select_priority": int(SELECT_PRIORITY_OVERRIDE.get(name, 10)),
		"target_types": _mask(a.get("target_types", []), TARGET_TYPES),
		"target_types_damaged": _mask(a.get("target_types_damaged", []), TARGET_TYPES),

		"target_types_underwater": _mask(a.get("target_types_underwater", []), TARGET_TYPES),

		"offset_x": int(_seq_offset(idle).x), "offset_y": int(_seq_offset(idle).y),

		"target_types_airborne": _mask(a.get("target_types_airborne", []), TARGET_TYPES),
		"voice": a.get("voice", ""), "reveals": int(a.get("reveals", 0)),
		"required_short_game": 1 if a.get("must_be_destroyed", false) else 0,
		"must_be_destroyed": a.has("must_be_destroyed"),
		"captures": a.get("captures", false), "capturable": a.get("capturable", false),
		"capture_types": _mask(a.get("capture_types", []), CAPTURE_TYPES),
		"capturable_types": _mask(a.get("capturable_types", []), CAPTURE_TYPES),
		"capture_delay": int(a.get("capture_delay", 200)),

		"instantly_repairs": a.get("instantly_repairs", false),
		"instantly_repairable": a.get("instantly_repairable", false),
		"demolition_delay": int(a.get("demolition_delay", -1)),
		"demolishable": a.get("demolishable", false),
		"infiltrates": _mask(a.get("infiltrates", []), TARGET_TYPES),
		"disguise": a.get("disguise", false),
		"ignores_disguise": a.get("ignores_disguise", false),
		"infil_cash": _mask(a.get("infil_cash", []), TARGET_TYPES),
		"infil_cash_percent": int(a.get("infil_cash_percent", 50)),
		"infil_cash_min": int(a.get("infil_cash_min", -1)),
		"infil_explore": _mask(a.get("infil_explore", []), TARGET_TYPES),
		"infil_power": _mask(a.get("infil_power", []), TARGET_TYPES),
		"infil_power_duration": int(a.get("infil_power_duration", 500)),
		"infil_support": _mask(a.get("infil_support", []), TARGET_TYPES),
		"infil_proxy": a.get("infil_proxy", ""),
		"producible_prereqs": a.get("producible_prereqs", []),
		"producible_levels": int(a.get("producible_levels", 1)),
		"reveal_cells": int(ceil(float(a.get("reveals", 0)) / 1024.0)),
		"reveal_range": int(a.get("reveals", 0)),


		"voice_overrides": a.get("voice_overrides", {}),

		"death_voices": a.get("death_voices", {}),
	}


	var gx: Dictionary = a.get("gains_experience", {})
	var xp_levels: Array = gx.get("levels", [])
	if not xp_levels.is_empty():
		t["xp_required"] = xp_levels
		var ranks: Array = []
		for i in xp_levels.size():
			var m: Dictionary = gx.get("modifiers", {}).get(str(i + 1), {})
			ranks.append([int(m.get("FirepowerMultiplier", 100)), int(m.get("DamageMultiplier", 100)),
					int(m.get("SpeedMultiplier", 100)), int(m.get("ReloadDelayMultiplier", 100))])
		t["ranks"] = ranks
		var sh: Dictionary = gx.get("self_healing", {})
		if not sh.is_empty():
			t["elite_heal_step"] = int(sh.get("step", 0))
			t["elite_heal_percent"] = int(sh.get("percentage_step", 0))
			t["elite_heal_delay"] = int(sh.get("delay", 0))
			t["elite_heal_start_below"] = int(sh.get("start_if_below", 100))
			t["elite_heal_cooldown"] = int(sh.get("damage_cooldown", 0))

		t["levelup_sound"] = data().get("ui_sounds", {}).get(str(gx.get("notification", "")), "")
		t["levelup_effect"] = "%s/%s" % [gx.get("image", ""), gx.get("sequence", "levelup")]


	var sh2: Dictionary = a.get("self_healing", {})
	if not sh2.is_empty():
		t["heal_step"] = int(sh2.get("step", 0))
		t["heal_percent"] = int(sh2.get("percentage_step", 0))
		t["heal_delay"] = int(sh2.get("delay", 0))
		t["heal_start_below"] = int(sh2.get("start_if_below", 50))
		t["heal_damage_cooldown"] = int(sh2.get("damage_cooldown", 0))

	t["gives_experience"] = int(a.get("gives_experience", -1)) if a.has("gives_experience") else 0

	if a.has("damaged_sounds"):
		t["damaged_sounds"] = a["damaged_sounds"]
	if a.has("destroyed_sounds"):
		t["destroyed_sounds"] = a["destroyed_sounds"]


	if int(a.get("cost", 0)) > 0:
		t["cost"] = int(a["cost"])
	if a.get("sellable", false):
		t["sellable"] = true
	var b: Dictionary = a.get("buildable", {})
	var queue := -1
	if not b.is_empty():
		for q in b.get("queue", []):
			if QUEUE_NAMES.has(q):
				queue = QUEUE_NAMES[q]
		var prereqs: Array = []
		for p in b.get("prerequisites", []):
			if p == "disabled":
				queue = -1
			prereqs.append(p)
		if queue >= 0 and int(a.get("cost", 0)) > 0:
			t["queue"] = queue
			t["prerequisites"] = prereqs
			if not b.get("prerequisites_not", []).is_empty():
				t["prerequisites_not"] = b["prerequisites_not"]


			if not b.get("prerequisites_hidden", []).is_empty():
				t["prerequisites_hidden"] = b["prerequisites_hidden"]
			t["build_duration"] = int(b.get("duration", -1))
			t["build_duration_pct"] = int(b.get("duration_modifier", 60))
			t["palette_order"] = int(b.get("order", 9999))
			if int(b.get("limit", 0)) > 0:
				t["build_limit"] = int(b["limit"])
			var icon: Dictionary = seqs.get("icon", {})
			var icon_stem := _stem(str(icon.get("file", name + "icon.shp")))
			if _has_sprite(icon_stem):
				t["icon"] = icon_stem
	var provides: Array = []
	var provides_factions: Array = []
	var provides_requires: Array = []
	for p in a.get("provides", []):
		provides.append(p["prerequisite"])
		provides_factions.append(",".join(p.get("factions", [])))
		provides_requires.append(",".join(p.get("requires", [])))
	if not provides.is_empty():
		t["provides"] = provides
		t["provides_factions"] = provides_factions
		t["provides_requires"] = provides_requires
	if a.has("power"):
		t["power"] = int(a["power"])
	if a.get("provides_radar", false):
		t["provides_radar"] = true
	if a.has("sell_value"):
		t["sell_value"] = int(a["sell_value"])
	if a.has("adjacent"):
		t["adjacent"] = int(a["adjacent"])
	if a.get("scale_power_with_health", false):
		t["scale_power_with_health"] = true
	if a.get("needs_power", false):
		t["needs_power"] = true

	if ai.get("building_fractions", {}).has(name):
		t["ai_building_fraction"] = int(ai["building_fractions"][name])
	if ai.get("building_limits", {}).has(name):
		t["ai_building_limit"] = int(ai["building_limits"][name])
	if ai.get("building_delays", {}).has(name):
		t["ai_building_delay"] = int(ai["building_delays"][name])
	if ai.get("units_to_build", {}).has(name):
		t["ai_unit_share"] = int(ai["units_to_build"][name])
	if ai.get("unit_limits", {}).has(name):
		t["ai_unit_limit"] = int(ai["unit_limits"][name])
	if ai.get("exclude_from_squads", []).has(name):
		t["exclude_from_squads"] = true

	var weapon := _primary_weapon(a)
	if weapon != "":
		t["weapon"] = weapon
		t["combat"] = true


		for arm in a.get("armaments", []):
			if str(arm.get("name", "primary")) == "garrisoned" or str(arm.get("requires", "")) != "":
				continue
			var w2: String = str(arm.get("weapon", ""))
			if w2 != "" and w2 != weapon and weapons.has(w2):
				t["weapon_secondary"] = w2
				break


	var arms: Array = []
	for arm in a.get("armaments", []):
		if arm.get("weapon", "") != "":
			arms.append({"name": arm.get("name", ""), "weapon": arm["weapon"]})
	if not arms.is_empty():
		t["armaments"] = arms


	var empty: Dictionary = seqs.get("empty-idle", {})
	if not empty.is_empty() and _stem(str(empty.get("file", body + ".shp"))) == body:
		for arm in a.get("armaments", []):
			if str(arm.get("reloading_condition", "")) != "":
				t["empty_start"] = int(empty.get("start", 0))
				break
	var attack: Dictionary = a.get("attack", {})
	if a.has("turret"):
		t["turreted"] = true
		t["turret_turn"] = int(a["turret"].get("turn_speed", 512))
		t["realign_delay"] = int(a["turret"].get("realign_delay", 40))
		var ts: Dictionary = seqs.get("turret", {})
		if not ts.is_empty():
			var tstem := _stem(str(ts.get("file", body + ".shp")))
			if _has_sprite(tstem):


				t["turret_first"] = _atlas.frame_index(tstem, int(ts.get("start", 0)))
	elif attack.get("type", "") == "frontal":


		t["facing_tolerance"] = int(attack.get("facing_tolerance", 128))
	elif attack.get("type", "") in ["omni", "garrisoned", "charges", "tesla", "leap"]:
		t["facing_tolerance"] = 1024
	if attack.get("type", "") == "tesla":

		t["max_charges"] = int(attack.get("max_charges", 1))
		t["charge_reload"] = int(attack.get("reload_delay", 120))
		t["initial_charge_delay"] = int(attack.get("initial_charge_delay", 22))
		t["charge_delay"] = int(attack.get("charge_delay", 3))

		if str(attack.get("charge_audio", "")) != "":
			t["charge_sound"] = str(attack["charge_audio"])
	if attack.get("type", "") == "leap":


		t["leap"] = true
		t["leap_speed"] = int(attack.get("leap_speed", 426))
		t["leap_lock_ticks"] = int(attack.get("eat_delay", 0))

	if not a.has("auto_target"):
		t["no_auto_target"] = true


	t["auto_target_mask"] = _mask(a.get("auto_target_valid", []), TARGET_TYPES)

	if int(a.get("cargo", 0)) > 0:
		t["cargo_max_weight"] = int(a["cargo"])
		t["cargo_types"] = _mask(a.get("cargo_types", []), TARGET_TYPES)
		var cd: Array = a.get("cargo_delays", [8, 0, 25])
		t["before_unload_delay"] = int(cd[0])
		t["between_unload_delay"] = int(cd[1]) if cd.size() > 1 else 0
		t["after_unload_delay"] = int(cd[2]) if cd.size() > 2 else 25
		t["cargo_eject_on_death"] = a.get("cargo_eject_on_death", false)
	if a.has("passenger"):
		var pg: Dictionary = a["passenger"]
		t["passenger_weight"] = int(pg.get("weight", 1))
		t["passenger_type"] = _mask([pg.get("type", "")], TARGET_TYPES)

	if a.has("fall_rate"):
		t["fall_rate"] = int(a["fall_rate"])

	if a.has("mine"):
		t["mine"] = true
		t["crush_classes"] = _mask(a["mine"].get("crush_classes", ["mine"]), CRUSH_CLASSES)
	if a.get("mine_immune", false):
		t["mine_immune"] = true
	if a.has("minelayer"):
		t["minelayer_mine"] = String(a["minelayer"].get("mine", "minv"))
		if a.has("ammo_pool"):
			t["ammo_max"] = int(a["ammo_pool"].get("ammo", 5))

	if a.has("cloak") and typeof(a["cloak"]) == TYPE_DICTIONARY:
		var ck: Dictionary = a["cloak"]
		t["cloak"] = true
		t["cloak_initial_delay"] = int(ck.get("initial_delay", 10))
		t["cloak_delay"] = int(ck.get("cloak_delay", 30))
		t["cloak_types"] = _mask(ck.get("detection_types", ["Cloak"]), DETECTION_TYPES)
		t["uncloak_on"] = _mask(ck.get("uncloak_on", ["Attack"]), UNCLOAK_ON)
	if a.has("detect_cloaked"):
		t["detect_range"] = int(a["detect_cloaked"].get("range", 0))
		t["detect_types"] = _mask(a["detect_cloaked"].get("types", ["Cloak"]), DETECTION_TYPES)
	if a.has("crushable"):
		var cr: Dictionary = a["crushable"]
		t["crush_classes"] = _mask(cr.get("classes", ["infantry"]), CRUSH_CLASSES)
		if cr.get("sound", "") != "":
			t["crush_sound"] = cr["sound"]
	if a.has("take_cover"):
		t["takes_cover"] = true
		t["prone_duration"] = int(a["take_cover"].get("duration", 100))
		t["prone_speed"] = int(a["take_cover"].get("speed", 50))


	var death_effects: Array = []
	var death_any := ""
	var dw: String = a.get("death_weapon", "")
	if dw != "" and weapons.has(dw):
		t["death_weapon"] = dw
	if dw != "" and _weapon_defs.has(dw):
		var wd: Dictionary = _weapon_defs[dw]
		for wh in wd.get("warheads", []):
			if wh["type"] == "CreateEffect":
				var ex: Array = wh.get("explosions", [])
				if not ex.is_empty() and death_any == "":
					death_any = effect_key(wh.get("image", "explosion"), ex[0])
				var snd: Array = wh.get("impact_sounds", [])
				if not snd.is_empty() and not t.has("death_sound"):
					t["death_sound"] = snd[0]
	if a.has("death_animation"):
		var da: Dictionary = a["death_animation"]
		var dtypes: Dictionary = da.get("types", {})


		var suffix: bool = da.get("suffix", true)
		for i in DEATH_TYPES.size():
			var idx := int(dtypes.get(DEATH_TYPES[i], 0))
			var sname: String = "%s%d" % [da.get("sequence", "die"), idx] if suffix else str(da.get("sequence", "die"))
			var key := _death_effect(name, "die%d" % idx if suffix else "dead", seqs.get(sname, {}), body)
			if suffix and idx <= 0:
				key = ""
			if key == "":
				key = death_any
			death_effects.append(key)
		t["death_voice"] = true

		death_effects.append(_death_effect(name, "crushed", seqs.get(str(da.get("crushed", "")), {}), body))
	else:
		for i in DEATH_TYPES.size() + 1:
			death_effects.append(death_any)
	t["death_effects"] = death_effects

	if a.has("building"):
		var bd: Dictionary = a["building"]
		var dims: Array = bd.get("dimensions", [1, 1])
		t["building"] = true
		t["footprint"] = bd.get("footprint", "x")


		var coff: Array = bd.get("center_offset", [0, 0, 0])
		var coff_y: int = int(coff[1]) if coff.size() > 1 else 0
		t["sprite_h"] = maxi(1, (int(dims[1]) if dims.size() > 1 else 1) + int(floor(coff_y / 512.0)))
		t["defense"] = a.get("target_types", []).has("Defense")

		t["gives_buildable_area"] = a.get("gives_buildable_area", false)
		t["decoration"] = not t.has("queue") and not a.has("produces") and not a.has("base_provider")
		t["wall"] = a.get("wall", false)
		t["bounds"] = Vector2(int(dims[0]) * CELL, t["sprite_h"] * CELL)
		t["hit_radius"] = int(dims[0]) * 512

		t["range_radius"] = (int(dims[0]) - 1) * 512
		t["idle_len"] = maxi(1, int(idle.get("length", 1)))
		var dmg: Dictionary = seqs.get("damaged-idle", {})
		t["damaged_frame"] = int(dmg.get("start", 0)) if not dmg.is_empty() else 0


		if a.has("resource_level_sequence"):
			var rseq: String = str(a["resource_level_sequence"])
			var stages: Dictionary = seqs.get(rseq, {})
			if not stages.is_empty() and int(stages.get("length", 0)) > 0:
				t["stage_len"] = int(stages.get("length", 1))
				t["resource_stages"] = maxi(1, int(a.get("resource_level_stages", 10)))


				var dstages: Dictionary = seqs.get("damaged-" + rseq, {})
				if not dstages.is_empty():
					t["damaged_frame"] = int(dstages.get("start", 0))
		if a.has("resource_pips"):


			t["resource_pips"] = int(a["resource_pips"])
		var mk: Dictionary = seqs.get("make", {})
		if not mk.is_empty() and a.get("make_animation", false):
			var mstem := _stem(str(mk.get("file", name + "make.shp")))
			if _has_sprite(mstem):
				t["make"] = mstem


		for pair in [["build-top", "damaged-build-top", true], ["idle-top", "damaged-idle-top", false]]:
			var ov: Dictionary = seqs.get(pair[0], {})
			if ov.is_empty() or int(ov.get("length", 0)) == 0:
				continue
			var ostem := _stem(str(ov.get("file", name + ".shp")))
			if not _has_sprite(ostem):
				continue
			var olen: int = int(ov.get("length", 1))
			if olen < 0:
				olen = _atlas.sprite_frame_count[ostem] - int(ov.get("start", 0))
			t["overlay_sprite"] = ostem
			t["overlay_start"] = int(ov.get("start", 0))
			t["overlay_len"] = maxi(1, olen)
			if pair[2]:
				t["door_len"] = t["overlay_len"]
			var dov: Dictionary = seqs.get(pair[1], {})
			var dstem := _stem(str(dov.get("file", ostem + ".shp"))) if not dov.is_empty() else ""
			if dstem != "" and _has_sprite(dstem):
				t["overlay_damaged_sprite"] = dstem
				t["overlay_damaged_start"] = int(dov.get("start", 0))
				t["overlay_damaged_len"] = maxi(1, int(dov.get("length", 1)))
			break
		var act: Dictionary = seqs.get("active", {})
		if not act.is_empty() and int(act.get("length", 0)) > 0:
			t["active_start"] = int(act.get("start", 0))
			t["active_len"] = int(act.get("length", 1))
			t["active_tick"] = maxi(1, int(act.get("tick", 40)))
			var dact: Dictionary = seqs.get("damaged-active", {})
			if not dact.is_empty() and int(dact.get("length", 0)) > 0:
				t["active_damaged_start"] = int(dact.get("start", 0))
		if a.has("bib"):
			var bw := int(dims[0])
			t["bib"] = "bib3" if bw <= 2 else ("bib2" if bw == 3 else "bib1")
			if a["bib"].get("minibib", false):
				t.erase("bib")
		if a.has("base_provider"):
			t["base_provider"] = true
			t["base_range"] = int(a["base_provider"].get("range", 10240))
		if a.has("produces"):
			var qs: Array = []
			for q in a["produces"]:
				if QUEUE_NAMES.has(q):
					qs.append(QUEUE_NAMES[q])
			if not qs.is_empty():
				t["produces"] = qs

		var terr := 0
		for tn in bd.get("terrain_types", []):
			var ti: int = TERRAIN_NAMES.find(str(tn))
			if ti >= 0:
				terr |= 1 << ti
		if terr != 0:
			t["terrain_mask"] = terr
		if a.has("exit"):
			var ec: Array = a["exit"].get("cell", [1, 2])
			t["exit_dx"] = int(ec[0])
			t["exit_dy"] = int(ec[1]) if ec.size() > 1 else 2
			t["exit_facing"] = int(a["exit"].get("facing", 0))


			var eo: Array = a["exit"].get("offset", [0, 0, 0])
			t["exit_ox"] = int(eo[0]) if eo.size() > 0 else 0
			t["exit_oy"] = int(eo[1]) if eo.size() > 1 else 0


		var rp: Array = a.get("rally", [])
		if rp.size() >= 2:
			t["rally_dx"] = int(rp[0])
			t["rally_dy"] = int(rp[1])
		else:
			t["rally_dx"] = t.get("exit_dx", 1)
			t["rally_dy"] = t.get("exit_dy", 2) + 1
		if a.has("support_power"):
			var sp: Dictionary = a["support_power"]
			t["support_power"] = SP_KINDS.find(str(sp.get("kind", "")))
			t["sp_charge"] = int(sp.get("charge_interval", 3000))
			t["sp_duration"] = int(sp.get("duration", 400))
			var sp_dims: Array = sp.get("dimensions", [1, 1])
			t["sp_dim_w"] = int(sp_dims[0])
			t["sp_dim_h"] = int(sp_dims[1])
			t["sp_footprint"] = str(sp.get("footprint", ""))
			t["sp_flight"] = int(sp.get("flight_delay", 400)) + int(sp.get("missile_delay", 0))
			if str(sp.get("missile_weapon", "")) != "":
				t["sp_weapon"] = str(sp["missile_weapon"])
			if str(sp.get("on_fire_sound", "")) != "":
				t["sp_sound"] = str(sp["on_fire_sound"])
			t["sp_notify_charging"] = int(SP_NOTIFY.get(str(sp.get("begin_notification", "")), -1))
			t["sp_notify_ready"] = int(SP_NOTIFY.get(str(sp.get("end_notification", "")), -1))

			t["sp_notify_launch"] = int(SP_NOTIFY.get(str(sp.get("launch_notification", "")), -1))
			t["sp_reveal_delay"] = int(sp.get("reveal_delay", 0))
			t["sp_one_shot"] = bool(sp.get("one_shot", false))

			t["sp_camera_range"] = int(sp.get("camera_range", 0))
		if a.has("cash_trickler"):
			t["cash_interval"] = int(a["cash_trickler"].get("interval", 50))
			t["cash_amount"] = int(a["cash_trickler"].get("amount", 15))
		if a.has("seeds_resource"):
			var sr: Dictionary = a["seeds_resource"]
			t["seeds_resource"] = 2 if String(sr.get("type", "Ore")) == "Gems" else 1
			t["seed_interval"] = int(sr.get("interval", 75))
			t["seed_max_range"] = int(sr.get("max_range", 100))
		if a.get("refinery", false):
			t["refinery"] = true
		if a.has("storage"):
			t["storage"] = int(a["storage"])
		if a.has("dock"):


			var off: Array = a["dock"].get("offset", [0, 1024])
			t["dock_dx"] = int(floor((int(dims[0]) * 512 + int(coff[0]) + int(off[0])) / 1024.0))
			var oy: int = int(off[1]) if off.size() > 1 else 0
			var cy: int = coff_y
			t["dock_dy"] = int(floor((int(dims[1]) * 512 + cy + oy) / 1024.0))
			t["dock_angle"] = int(a["dock"].get("angle", 0))
		if a.has("free_actor"):
			t["free_actor"] = a["free_actor"].get("actor", "")
			var fo: Array = a["free_actor"].get("offset", [0, 0])
			t["free_dx"] = int(fo[0])
			t["free_dy"] = int(fo[1]) if fo.size() > 1 else 0
		if a.has("repairs_units"):


			t["repairs_units"] = true
			t["repair_hp_step"] = int(a["repairs_units"].get("hp_per_step", 10))
			t["repair_interval"] = int(a["repairs_units"].get("interval", 24))
			t["repair_value_percent"] = int(a["repairs_units"].get("value_percent", 20))
		if a.has("repairable_building"):
			t["repair_step"] = int(a["repairable_building"].get("step", 7))
	elif a.has("crate"):


		t["crate"] = true
		t["crate_duration"] = int(a["crate"].get("duration", 0))
		t["crush_classes"] = _mask(["crate"], CRUSH_CLASSES)
		t["targetable"] = false
		t["no_auto_target"] = true
		t["facings"] = 1
		t["crate_actions"] = a.get("crate_actions", [])
	elif a.has("mobile"):
		var m: Dictionary = a["mobile"]
		t["speed"] = int(m.get("speed", 1))
		t["turn_rate"] = int(m.get("turn_speed", 512))
		t["locomotor"] = m.get("locomotor", "tracked")


		t["crushes"] = _mask(LOCO_CRUSHES.get(t["locomotor"], []), CRUSH_CLASSES)
		t["infantry"] = a.get("infantry", false)
		if t["infantry"]:
			t["turn_rate"] = 1024
			t["facings"] = 8
			var run: Dictionary = seqs.get("run", seqs.get("walk", {}))
			if not run.is_empty():
				t["run_start"] = int(run.get("start", 0))
				t["run_len"] = int(run.get("length", 1))


			var shoot_name := "shoot"
			var shoot2_name := ""
			var arm_seqs: Array = []
			for arm in t.get("armaments", []):
				if str(arm.get("weapon", "")) == weapon:
					arm_seqs = a.get("attack_sequences", {}).get(str(arm.get("name", "")), [])
					break
			if not arm_seqs.is_empty():
				shoot_name = str(arm_seqs[0])
				if arm_seqs.size() > 1:
					shoot2_name = str(arm_seqs[1])
			elif a.has("default_attack_sequence"):
				shoot_name = str(a["default_attack_sequence"])
			var shoot: Dictionary = seqs.get(shoot_name, {})
			if not shoot.is_empty():
				t["shoot_start"] = int(shoot.get("start", 0))
				t["shoot_len"] = int(shoot.get("length", 1))
				_add_frame_list(t, "shoot_frames", shoot, body)
			if shoot2_name != "":
				var shoot2: Dictionary = seqs.get(shoot2_name, {})
				if not shoot2.is_empty():
					t["shoot2_start"] = int(shoot2.get("start", 0))
					t["shoot2_len"] = int(shoot2.get("length", 1))
					_add_frame_list(t, "shoot2_frames", shoot2, body)

			var idles: Array = []
			for n in ["idle1", "idle2"]:
				var iq: Dictionary = seqs.get(n, {})
				if iq.is_empty() or int(iq.get("length", 0)) <= 0:
					continue
				if _stem(str(iq.get("file", body + ".shp"))) != body:
					continue
				idles.append({"start": int(iq.get("start", 0)), "len": int(iq.get("length", 1)),
							"ticks": maxi(1, int(round(float(iq.get("tick", 120)) / 40.0)))})
			if not idles.is_empty():
				t["idle1_start"] = idles[0]["start"]
				t["idle1_len"] = idles[0]["len"]
				t["idle2_start"] = idles[-1]["start"]
				t["idle2_len"] = idles[-1]["len"]
				t["idle_anim_ticks"] = idles[0]["ticks"]
			if t.get("leap", false):


				var jump: Dictionary = seqs.get("jump", {})
				if not jump.is_empty():
					_add_facing_frame_list(t, "jump_frames", "jump_len", jump, body)
		else:
			t["facings"] = int(idle.get("facings", 32))
			t["classic"] = idle.get("classic", false) or t["facings"] == 32
		if a.has("harvester"):
			var h: Dictionary = a["harvester"]
			t["harvester"] = true
			t["capacity"] = int(h.get("capacity", 20))
			t["bale_load_delay"] = int(h.get("bale_load_delay", 4))
			t["bale_unload_delay"] = int(h.get("bale_unload_delay", 4))
			t["search_from_proc"] = int(h.get("search_from_proc", 24))
			t["search_from_harv"] = int(h.get("search_from_harv", 12))
			t["wait_duration"] = int(h.get("wait_duration", 25))
			var hv: Dictionary = seqs.get("harvest", {})
			if not hv.is_empty():
				t["harvest_facings"] = int(h.get("facings", 0)) if int(h.get("facings", 0)) > 0 else int(hv.get("facings", 8))
				t["harvest_start"] = int(hv.get("start", 0))
				t["harvest_len"] = int(hv.get("length", 1))
			var dk: Dictionary = seqs.get("dock", {})
			var dl: Dictionary = seqs.get("dock-loop", {})
			if not dk.is_empty():
				t["dock_start"] = int(dk.get("start", 0))
				t["dock_len"] = int(dk.get("length", 1))
				t["loop_len"] = int(dl.get("length", 1)) if not dl.is_empty() else 1
		if a.has("repairable"):
			t["repairable"] = true
		if a.has("transforms"):
			var tr: Dictionary = a["transforms"]
			t["transforms"] = tr.get("into", "")
			var off: Array = tr.get("offset", [0, 0])
			t["transforms_dx"] = int(off[0])
			t["transforms_dy"] = int(off[1]) if off.size() > 1 else 0
	elif a.has("aircraft"):

		var ac: Dictionary = a["aircraft"]
		t["aircraft"] = true
		t["speed"] = int(ac.get("speed", 1))
		t["turn_rate"] = int(ac.get("turn_speed", 512))
		t["cruise_altitude"] = int(ac.get("cruise_altitude", 1280))
		t["altitude_velocity"] = int(ac.get("altitude_velocity", 43))
		t["can_hover"] = ac.get("can_hover", false)
		t["vtol"] = ac.get("vtol", false)
		t["idle_behavior"] = ["None", "Land", "ReturnToBase", "LeaveMap"].find(str(ac.get("idle_behavior", "None")))
		var lt := 0
		for tn in ac.get("landable", []):
			var li: int = TERRAIN_NAMES.find(str(tn))
			if li >= 0:
				lt |= 1 << li
		t["landable_terrain"] = lt
		t["facings"] = int(idle.get("facings", 32))
		t["classic"] = idle.get("classic", false) or t["facings"] == 32

		if a.has("ammo_pool"):
			var ap: Dictionary = a["ammo_pool"]
			t["ammo_max"] = int(ap.get("ammo", 0))
			t["ammo_reload"] = int(ap.get("reload_delay", 50))
			if ap.get("rearm_sound", "") != "":
				t["rearm_sound"] = ap["rearm_sound"]

		var at: Dictionary = a.get("attack", {})
		t["air_attack_type"] = {"Default": 0, "Hover": 1, "Strafe": 2}.get(str(at.get("attack_type", "Default")), 0)
		t["facing_tolerance"] = int(at.get("facing_tolerance", 80))

		var rearm: Array = []
		for name_r in a.get("rearm_actors", []):
			rearm.append(str(name_r))
		if not rearm.is_empty():
			t["rearm_actors"] = rearm


		t["rotors"] = _rotors(a, seqs)
	else:
		return {}
	return t
