

extends RefCounted


static var _cached: Node = null


static func node() -> Node:
	if _cached != null and is_instance_valid(_cached):
		return _cached
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		_cached = (ml as SceneTree).root.get_node_or_null("AppLog")
	return _cached


static func info(tag: String, msg: String) -> void:
	var n := node()
	if n != null:
		n.info(tag, msg)
	else:
		print("%s: %s" % [tag, msg])


static func warn(tag: String, msg: String) -> void:
	var n := node()
	if n != null:
		n.warn(tag, msg)
	else:
		push_warning("%s: %s" % [tag, msg])


static func error(tag: String, msg: String) -> void:
	var n := node()
	if n != null:
		n.error(tag, msg)
	else:
		push_error("%s: %s" % [tag, msg])


static func text(count: int = 200) -> String:
	var n := node()
	if n != null:
		return String(n.text(count))
	return TranslationServer.translate("log.unavailable")


static func path() -> String:
	var n := node()
	if n != null:
		return String(n.path())
	return ""
