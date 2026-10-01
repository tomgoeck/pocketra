

extends RefCounted


const AndroidPlugin := preload("res://scripts/android_plugin.gd")
const SINGLETON := AndroidPlugin.SINGLETON

var _watching := ""


static func plugin() -> Object:
	return AndroidPlugin.plugin()


func available() -> bool:
	return plugin() != null


func request_permission() -> bool:
	var p := AndroidPlugin.plugin_with(&"requestPermission")
	if p != null:
		return bool(p.requestPermission())
	if OS.get_name() == "Android":
		return OS.request_permission("android.permission.POST_NOTIFICATIONS")
	return false


func has_permission() -> bool:
	var p := AndroidPlugin.plugin_with(&"hasPermission")
	if p != null:
		return bool(p.hasPermission())
	return false


func show(title: String, text: String) -> void:
	var p := AndroidPlugin.plugin_with(&"showNotification")
	if p != null:
		p.showNotification(title, text)


func start_watch(url: String, code: String, token: String, room_title: String) -> void:
	var p := AndroidPlugin.plugin_with(&"startWatch")
	if p == null or _watching == code:
		return


	var texts := JSON.stringify({
		"connected": TranslationServer.translate("mp.notify_room"),
		"join": TranslationServer.translate("mp.notify_join"),
		"start": TranslationServer.translate("mp.notify_start"),


		"events": events_flags(),
	})
	p.startWatch(url, code, token, room_title, texts)
	_watching = code


func stop_watch() -> void:
	if _watching == "":
		return
	_watching = ""
	var p := AndroidPlugin.plugin_with(&"stopWatch")
	if p != null:
		p.stopWatch()


const SETTINGS := "user://settings.cfg"
const SECTION := "notify"
const PERMISSION := "android.permission.POST_NOTIFICATIONS"


const EVENTS := ["join", "chat", "start"]


static var force_ui := false


static func supported() -> bool:
	return force_ui or OS.get_name() == "Android"


static func enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value(SECTION, "enabled", true))


static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SECTION, "enabled", on)
	cfg.save(SETTINGS)


static func event_enabled(what: String) -> bool:
	if not enabled():
		return false
	if not EVENTS.has(what):
		return false
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return bool(cfg.get_value(SECTION, what, true))


static func set_event_enabled(what: String, on: bool) -> void:
	if not EVENTS.has(what):
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(SECTION, what, on)
	cfg.save(SETTINGS)


static func any_event() -> bool:
	for e in EVENTS:
		if event_enabled(e):
			return true
	return false


static func events_flags() -> Dictionary:
	var d := {}
	for e in EVENTS:
		d[e] = event_enabled(e)
	return d


static func permission_ok() -> bool:
	if force_ui:
		return false
	if OS.get_name() != "Android":
		return true
	return OS.get_granted_permissions().has(PERMISSION)
