

@tool
extends EditorPlugin

const PLUGIN_NAME := "PocketRaPlugin"
const BIN_DIR := "res://addons/pocketra_plugin/bin"

var _export: EditorExportPlugin = null


func _enter_tree() -> void:
	_export = AndroidExportPlugin.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export != null:
		remove_export_plugin(_export)
		_export = null


class AndroidExportPlugin extends EditorExportPlugin:


	const NAME := "PocketRaPlugin"
	const BIN := "res://addons/pocketra_plugin/bin"

	func _get_name() -> String:
		return NAME

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var name := "pocketra_plugin-debug.aar" if debug else "pocketra_plugin-release.aar"
		var path := "%s/%s" % [BIN, name]
		if not FileAccess.file_exists(path):
			push_warning("PocketRaPlugin: %s fehlt — tools/plugin_build.sh laufen lassen." % path)
			return PackedStringArray()
		return PackedStringArray([path])


	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.squareup.okhttp3:okhttp:4.12.0"])
