extends RefCounted
## The Android build compiles the editor into the APK. Only configuration and
## the completed UTF-8 value cross the bridge.

static func request(options: Dictionary, finished: Callable) -> bool:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"): return false
	var runtime = Engine.get_singleton("AndroidRuntime")
	var java = Engine.get_singleton("JavaClassWrapper")
	var activity = runtime.getActivity()
	if activity == null: return false
	var keyboard = java.wrap("studio.havu.android.HavuKeyboard")
	if keyboard == null: return false
	var limits: Vector2i = options.get("integer_range", Vector2i(1, 0))
	var editor = keyboard.open(activity, options.title.to_utf8_buffer(), options.text.to_utf8_buffer(),
		options.type, options.get("signed", false), options.get("max_length", 0), limits.x, limits.y)
	if editor == null or java.get_exception() != null: return false
	wait_for_result(editor, finished)
	return true

static func wait_for_result(editor, finished: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	while finished.is_valid():
		await tree.create_timer(0.1).timeout
		var result: PackedByteArray = editor.result()
		if result.is_empty(): continue
		finished.call(result[0] == 2, result.slice(1).get_string_from_utf8(), result[0] != 0)
		return
