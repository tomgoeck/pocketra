

class_name OriginalContent
extends RefCounted

const PACKAGE := "net.pocketra.app"

static var _dir := ""
static var _searched := false


static func dir() -> String:
	if _searched:
		return _dir
	_searched = true
	var candidates: Array[String] = [OS.get_user_data_dir().path_join("original")]
	if OS.get_name() == "Android":
		candidates.append("/storage/emulated/0/Android/data/%s/files/original" % PACKAGE)
		candidates.append("/sdcard/Android/data/%s/files/original" % PACKAGE)
	for c in candidates:
		if DirAccess.dir_exists_absolute(c):
			_dir = c
			print("Original-Inhalte: ", c)
			return _dir
	print("Original-Inhalte: keine (gesucht: ", ", ".join(candidates), ")")
	return ""


static func available() -> bool:
	return dir() != ""


static func video(name: String) -> String:
	var d := dir()
	if d == "":
		return ""
	var base := name.get_basename()
	for p in [d.path_join("video").path_join(Lang.code()).path_join(base + ".ogv"),
			d.path_join("video").path_join(base + ".ogv")]:
		if FileAccess.file_exists(p):
			return p
	return ""


static func music() -> Dictionary:
	var out := {}
	var d := dir()
	if d == "":
		return out
	var md := DirAccess.open(d.path_join("music"))
	if md == null:
		return out
	for f in md.get_files():
		var ext := f.get_extension().to_lower()
		if ext == "mp3" or ext == "ogg":
			out[f.get_basename()] = d.path_join("music").path_join(f)
	return out


static func load_music(path: String) -> AudioStream:
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return AudioStreamMP3.load_from_file(path)
