extends RefCounted

const UNAVAILABLE := "This folder is unavailable. Try refreshing or choose it again."

static func scan(path: String) -> Dictionary:
	var result: Dictionary
	if path.begins_with("content://"):
		var bridge := android_bridge()
		if bridge.is_empty(): return {"error": UNAVAILABLE}
		var bytes: PackedByteArray = bridge.helper.scan(bridge.activity, path)
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
		if not parsed is Dictionary: return {"error": UNAVAILABLE}
		result = parsed
	else:
		var directory := DirAccess.open(path)
		if directory == null or directory.list_dir_begin() != OK: return {"error": UNAVAILABLE}
		var entries: Array[Dictionary] = []
		var filename := directory.get_next()
		while not filename.is_empty():
			if not directory.current_is_dir() and filename.get_extension().nocasecmp_to("havu") == 0:
				entries.append({"name": filename, "path": path.path_join(filename)})
			filename = directory.get_next()
		directory.list_dir_end()
		var folder_name := path.trim_suffix("/").get_file()
		result = {"title": folder_name if not folder_name.is_empty() else path, "entries": entries}
	result.entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var order: int = a.name.naturalnocasecmp_to(b.name)
		return a.path < b.path if order == 0 else order < 0)
	return result

static func persist(path: String) -> bool:
	if not path.begins_with("content://"): return true
	var bridge := android_bridge()
	return not bridge.is_empty() and bridge.helper.persist(bridge.activity, path)

static func android_bridge() -> Dictionary:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"): return {}
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var helper = Engine.get_singleton("JavaClassWrapper").wrap("studio.havu.android.HavuProjectFolder")
	return {"activity": activity, "helper": helper} if activity != null and helper != null else {}
