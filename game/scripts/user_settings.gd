class_name UserSettings


const PATH := "user://settings.cfg"

static var _guard := -1
static var _shadow := ""
static var _has_shadow := false


static func guarded() -> bool:
	if _guard < 0:
		_guard = 0
		for a in OS.get_cmdline_user_args():
			if a == "--autostart" or a.begins_with("--test"):
				_guard = 1
				break
	return _guard == 1


static func read(cfg: ConfigFile, path: String = PATH) -> Error:
	if path == PATH and _has_shadow:
		cfg.clear()
		return cfg.parse(_shadow)
	return cfg.load(path)


static func write(cfg: ConfigFile, path: String = PATH) -> Error:
	if path == PATH and guarded():
		_shadow = cfg.encode_to_text()
		_has_shadow = true
		return OK
	return cfg.save(path)
