

extends RefCounted

const SINGLETON := "PocketRaPlugin"


static var _test_platform := ""


static func platform() -> String:
	if _test_platform != "":
		return _test_platform
	var args := OS.get_cmdline_user_args()
	var k := args.find("--force-platform")
	if k >= 0 and k + 1 < args.size():
		return args[k + 1]
	return OS.get_name()


static func set_test_platform(name: String) -> void:
	_test_platform = name

static var _looked_up := false
static var _plugin: Object = null
static var _can := {}


static func plugin() -> Object:
	if not _looked_up:
		_looked_up = true
		_plugin = Engine.get_singleton(SINGLETON) if Engine.has_singleton(SINGLETON) else null
	return _plugin


static func available() -> bool:
	return plugin() != null


static func can(method: StringName) -> bool:
	if not _can.has(method):
		_can[method] = _probe(plugin(), method)
	return bool(_can[method])


static func plugin_with(method: StringName) -> Object:
	return plugin() if can(method) else null


static func _probe(p: Object, method: StringName) -> bool:
	if p == null:
		return false


	if p.has_method(method):
		return true
	if p.has_method(&"has_java_method"):
		return bool(p.has_java_method(method))
	return false


static func set_test_plugin(p: Object) -> void:
	_plugin = p
	_looked_up = true
	_can.clear()


static func clear_test_plugin() -> void:
	_plugin = null
	_looked_up = false
	_can.clear()


static func report(methods: PackedStringArray) -> String:
	var p := plugin()
	if p == null:
		return "Plugin: nicht geladen"
	var ok := PackedStringArray()
	var fehlt := PackedStringArray()
	for m in methods:
		if can(m):
			ok.append(m)
		else:
			fehlt.append(m)
	var wie := "unbekannt"
	if p.has_method(&"has_java_method"):
		wie = "JNI"
	elif not ok.is_empty():
		wie = "Skript"
	var teile := PackedStringArray(["Plugin: geladen (%s)" % wie])
	teile.append("kann: %s" % (", ".join(ok) if not ok.is_empty() else "—"))
	if not fehlt.is_empty():
		teile.append("fehlt: %s" % ", ".join(fehlt))
	return " · ".join(teile)


class AttrappeJni extends RefCounted:
	var namen := PackedStringArray()

	func has_java_method(m: StringName) -> bool:
		return namen.has(String(m))


class AttrappeSkript extends RefCounted:
	func micStart() -> int:
		return 48000

	func showNotification(_titel: String, _text: String) -> void:
		pass


static func _pruefe(zeilen: Array, name: String, ist: Variant, soll: Variant) -> int:
	var ok: bool = ist == soll
	zeilen.append("  %s = %s (erwartet %s) — %s" % [name, ist, soll, "OK" if ok else "FEHLER"])
	return 0 if ok else 1


static func self_test() -> PackedStringArray:
	var zeilen: Array = []
	var fehler := 0


	set_test_plugin(null)
	zeilen.append("Fall 1: kein Singleton")
	fehler += _pruefe(zeilen, "available()", available(), false)
	fehler += _pruefe(zeilen, "can(micStart)", can(&"micStart"), false)
	fehler += _pruefe(zeilen, "plugin_with(micStart) == null", plugin_with(&"micStart") == null, true)
	fehler += _pruefe(zeilen, "report()", report(PackedStringArray(["micStart"])), "Plugin: nicht geladen")


	var jni := AttrappeJni.new()
	jni.namen = PackedStringArray(["micStart", "micRead", "showNotification", "restartApp"])
	set_test_plugin(jni)
	zeilen.append("Fall 2: JNISingleton-Attrappe (Methoden nur über has_java_method)")
	fehler += _pruefe(zeilen, "has_method(micStart) — der alte, falsche Test", jni.has_method("micStart"), false)
	fehler += _pruefe(zeilen, "can(micStart)", can(&"micStart"), true)
	fehler += _pruefe(zeilen, "can(showNotification)", can(&"showNotification"), true)
	fehler += _pruefe(zeilen, "can(restartApp)", can(&"restartApp"), true)
	fehler += _pruefe(zeilen, "can(micInfo) — nicht angemeldet", can(&"micInfo"), false)
	fehler += _pruefe(zeilen, "plugin_with(micStart) == Attrappe", plugin_with(&"micStart") == jni, true)
	fehler += _pruefe(zeilen, "plugin_with(micInfo) == null", plugin_with(&"micInfo") == null, true)
	zeilen.append("  report(): %s" % report(PackedStringArray(["micStart", "micInfo"])))


	set_test_plugin(AttrappeSkript.new())
	zeilen.append("Fall 3: gewöhnliches Objekt")
	fehler += _pruefe(zeilen, "can(micStart)", can(&"micStart"), true)
	fehler += _pruefe(zeilen, "can(showNotification)", can(&"showNotification"), true)
	fehler += _pruefe(zeilen, "can(micRead)", can(&"micRead"), false)

	clear_test_plugin()
	zeilen.append("Attrappe abgenommen, available() = %s" % available())
	zeilen.append("Fehlschläge: %d" % fehler)
	return PackedStringArray(zeilen)
