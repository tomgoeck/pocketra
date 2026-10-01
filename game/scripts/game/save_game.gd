

class_name SaveGame
extends RefCounted

const DIR := "user://saves"
const MAGIC := 0x31534152
const FILE_VERSION := 1

const SLOTS := ["1", "2", "3", "4", "5"]
const AUTO_SLOTS := ["a1", "a2", "a3"]


static func path_for(slot: String) -> String:
	return "%s/%s.ras" % [DIR, slot]


static func is_auto(slot: String) -> bool:
	return slot in AUTO_SLOTS


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func write(slot: String, header: Dictionary, sim_bytes: PackedByteArray, gd: Dictionary) -> bool:
	_ensure_dir()
	var head := header.duplicate(true)
	head["saved_at"] = int(Time.get_unix_time_from_system())
	head["sim_bytes"] = sim_bytes.size()


	var tmp := path_for(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Spielstand nicht schreibbar: " + tmp)
		return false
	f.store_32(MAGIC)
	f.store_32(FILE_VERSION)
	f.store_pascal_string(JSON.stringify(head))
	f.store_32(sim_bytes.size())
	var packed := sim_bytes.compress(FileAccess.COMPRESSION_ZSTD) if sim_bytes.size() > 0 else PackedByteArray()
	f.store_32(packed.size())
	if packed.size() > 0:
		f.store_buffer(packed)
	f.store_pascal_string(JSON.stringify(gd))
	f.close()
	var d := DirAccess.open(DIR)
	if d == null:
		return false
	if FileAccess.file_exists(path_for(slot)):
		d.remove(path_for(slot).get_file())
	return d.rename(tmp.get_file(), path_for(slot).get_file()) == OK


static func read(slot: String, with_data: bool = true) -> Dictionary:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_32() != MAGIC:
		push_warning("Kein Spielstand: " + path)
		return {}
	var version := f.get_32()
	if version > FILE_VERSION:
		push_warning("Spielstand aus einer neueren Fassung: " + path)
		return {}
	var head = JSON.parse_string(f.get_pascal_string())
	if not head is Dictionary:
		return {}
	var out := {"header": head, "sim": PackedByteArray(), "gd": {}, "slot": slot,
			"modified": FileAccess.get_modified_time(path)}
	if not with_data:
		return out
	var raw_size := f.get_32()
	var packed_size := f.get_32()
	if packed_size > 0:
		var packed := f.get_buffer(packed_size)
		out["sim"] = packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
		if out["sim"].size() != raw_size:
			push_warning("Spielstand beschädigt: " + path)
			return {}
	var gd = JSON.parse_string(f.get_pascal_string())
	out["gd"] = gd if gd is Dictionary else {}
	return out


static func list_all() -> Array:
	var out: Array = []
	for slot in SLOTS + AUTO_SLOTS:
		var e := read(slot, false)
		if not e.is_empty():
			out.append(e)
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out


static func latest_slot() -> String:
	var all := list_all()
	return str(all[0]["slot"]) if not all.is_empty() else ""


static func next_auto_slot() -> String:
	var oldest := AUTO_SLOTS[0]
	var oldest_time := 1 << 62
	for slot in AUTO_SLOTS:
		if not FileAccess.file_exists(path_for(slot)):
			return slot
		var t := int(FileAccess.get_modified_time(path_for(slot)))
		if t < oldest_time:
			oldest_time = t
			oldest = slot
	return oldest


static func erase(slot: String) -> void:
	var d := DirAccess.open(DIR)
	if d != null and FileAccess.file_exists(path_for(slot)):
		d.remove(path_for(slot).get_file())


static func label(entry: Dictionary) -> String:
	if entry.is_empty():
		return tr_key("save.slot_empty")
	var h: Dictionary = entry["header"]
	var secs := int(h.get("playtime", 0))
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var when := Time.get_datetime_dict_from_unix_time(int(h.get("saved_at", 0)) + bias)
	var mode := tr_key("save.mode_skirmish")
	if str(h.get("mode", "")) == "mission":
		mode = tr_key("save.mode_restart") if bool(h.get("restart_only", false)) else tr_key("save.mode_mission")
	return "%s — %s\n%d:%02d · %02d.%02d. %02d:%02d" % [
			str(h.get("map_title", h.get("map", "?"))), mode,
			secs / 60, secs % 60, when["day"], when["month"], when["hour"], when["minute"]]


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


static func playtime_of(tick: int) -> int:
	return tick / 25
