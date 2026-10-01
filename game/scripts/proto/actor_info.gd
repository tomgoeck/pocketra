

class_name ActorInfo
extends RefCounted

const CSV_PATH := "res://i18n/descriptions.csv"

static var _de := {}
static var _en := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("ActorInfo: %s fehlt" % CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0] != "":
			_de[row[0]] = row[1].replace("\\n", "\n")
			_en[row[0]] = row[2].replace("\\n", "\n")


static func description(key: String) -> String:
	_load()
	var table := _de if Lang.is_de() else _en
	return str(table.get(key, ""))
