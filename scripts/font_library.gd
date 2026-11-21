extends RefCounted

const BUNDLED_DIR := "res://assets/fonts/"
const IMPORT_DIR := "user://fonts"
const MAX_FONT_BYTES := 16 * 1024 * 1024
const CATEGORIES := ["Serif", "Sans serif", "Display", "Script", "Monospace", "Imported"]
const FACES := {
	"serif": ["Studio Serif", "Serif", "StudioSerif.ttf"],
	"sans": ["Studio Sans", "Sans serif", "StudioSans.ttf"],
	"lato_light": ["Lato Light", "Sans serif", "Lato-Light.ttf"],
	"lato_italic": ["Lato Italic", "Sans serif", "Lato-Italic.ttf"],
	"lato_bold": ["Lato Bold", "Sans serif", "Lato-Bold.ttf"],
	"lato_heavy": ["Lato Heavy", "Display", "Lato-Heavy.ttf"],
	"open_sans": ["Open Sans", "Sans serif", "OpenSans-Regular.ttf"],
	"open_sans_semibold": ["Open Sans Semibold", "Sans serif", "OpenSans-Semibold.ttf"],
	"open_sans_italic": ["Open Sans Italic", "Sans serif", "OpenSans-Italic.ttf"],
	"open_sans_extra_bold": ["Open Sans ExtraBold", "Display", "OpenSans-ExtraBold.ttf"],
	"stix_text": ["STIX Two Text", "Serif", "STIXTwoText-Regular.otf"],
	"stix_italic": ["STIX Two Text Italic", "Serif", "STIXTwoText-Italic.otf"],
	"stix_bold": ["STIX Two Text Bold", "Serif", "STIXTwoText-Bold.otf"],
	"stix_bold_italic": ["STIX Two Text Bold Italic", "Serif", "STIXTwoText-BoldItalic.otf"],
	"noto_sans": ["Noto Sans", "Sans serif", "NotoSans-Regular.ttf"],
	"noto_condensed_bold": ["Noto Sans Condensed Bold", "Display", "NotoSans-CondensedBold.ttf"],
	"noto_black": ["Noto Sans Black", "Display", "NotoSans-Black.ttf"],
	"noto_serif_bold": ["Noto Serif Bold", "Serif", "NotoSerif-Bold.ttf"],
	"noto_serif_italic": ["Noto Serif Italic", "Serif", "NotoSerif-Italic.ttf"],
	"cantarell": ["Cantarell", "Sans serif", "Cantarell-Regular.otf"],
	"cantarell_light": ["Cantarell Light", "Sans serif", "Cantarell-Light.otf"],
	"cantarell_extra_bold": ["Cantarell ExtraBold", "Display", "Cantarell-ExtraBold.otf"],
	"adwaita_sans": ["Adwaita Sans", "Sans serif", "AdwaitaSans-Regular.ttf"],
	"adwaita_sans_italic": ["Adwaita Sans Italic", "Sans serif", "AdwaitaSans-Italic.ttf"],
	"adwaita_mono": ["Adwaita Mono", "Monospace", "AdwaitaMono-Regular.ttf"],
	"adwaita_mono_bold": ["Adwaita Mono Bold", "Monospace", "AdwaitaMono-Bold.ttf"],
	"special_elite": ["Special Elite", "Display", "SpecialElite.ttf"],
	"vazirmatn": ["Vazirmatn", "Sans serif", "Vazirmatn.ttf"],
	"fraunces": ["Fraunces", "Serif", "Fraunces.ttf"],
	"spectral": ["Spectral", "Serif", "Spectral-Regular.ttf"],
	"cormorant_italic": ["Cormorant Garamond Italic", "Serif", "CormorantGaramond-Italic.ttf"],
	"playfair": ["Playfair Display", "Serif", "PlayfairDisplay.ttf"],
	"dm_serif_display": ["DM Serif Display", "Serif", "DMSerifDisplay-Regular.ttf"],
	"dm_serif_display_italic": ["DM Serif Display Italic", "Serif", "DMSerifDisplay-Italic.ttf"],
	"bodoni_moda": ["Bodoni Moda", "Serif", "BodoniModa.ttf"],
	"libre_baskerville": ["Libre Baskerville", "Serif", "LibreBaskerville.ttf"],
	"lora": ["Lora", "Serif", "Lora.ttf"],
	"young_serif": ["Young Serif", "Serif", "YoungSerif-Regular.ttf"],
	"bricolage": ["Bricolage Grotesque", "Sans serif", "BricolageGrotesque.ttf"],
	"dm_sans": ["DM Sans", "Sans serif", "DMSans.ttf"],
	"work_sans": ["Work Sans", "Sans serif", "WorkSans.ttf"],
	"archivo_narrow": ["Archivo Narrow", "Sans serif", "ArchivoNarrow.ttf"],
	"archivo_black": ["Archivo Black", "Display", "ArchivoBlack-Regular.ttf"],
	"anton": ["Anton", "Display", "Anton-Regular.ttf"],
	"bebas_neue": ["Bebas Neue", "Display", "BebasNeue-Regular.ttf"],
	"oswald": ["Oswald", "Display", "Oswald.ttf"],
	"barlow_condensed": ["Barlow Condensed", "Sans serif", "BarlowCondensed-Regular.ttf"],
	"barlow_condensed_bold": ["Barlow Condensed Bold", "Display", "BarlowCondensed-Bold.ttf"],
	"fredoka": ["Fredoka", "Display", "Fredoka.ttf"],
	"lobster": ["Lobster", "Script", "Lobster-Regular.ttf"],
	"pacifico": ["Pacifico", "Script", "Pacifico-Regular.ttf"],
	"caveat": ["Caveat", "Script", "Caveat.ttf"],
	"dancing_script": ["Dancing Script", "Script", "DancingScript.ttf"],
	"cinzel": ["Cinzel", "Display", "Cinzel.ttf"],
	"rubik_mono_one": ["Rubik Mono One", "Display", "RubikMonoOne-Regular.ttf"],
	"ibm_plex_mono": ["IBM Plex Mono", "Monospace", "IBMPlexMono-Regular.ttf"],
	"space_mono": ["Space Mono", "Monospace", "SpaceMono-Regular.ttf"],
	"space_mono_bold": ["Space Mono Bold", "Monospace", "SpaceMono-Bold.ttf"],
}

static var imported := {}
static var scanned := false
static var loaded := {}

static func valid_id(id) -> bool:
	return id is String and (FACES.has(id) or (
		id.length() == 71 and id.begins_with("custom_") and id.substr(7).is_valid_hex_number(false)
		and id == id.to_lower()))

static func bundled_path(id: String) -> String:
	return BUNDLED_DIR + FACES[id][2] if FACES.has(id) else ""

static func entry(id: String) -> Dictionary:
	if FACES.has(id):
		return {"id": id, "name": FACES[id][0], "category": FACES[id][1], "path": bundled_path(id)}
	scan_imports()
	return imported.get(id, {})

static func entries() -> Array[Dictionary]:
	scan_imports()
	var result: Array[Dictionary] = []
	for id in FACES: result.append(entry(id))
	result.append_array(imported.values())
	result.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return result

static func font_for(id: String) -> Font:
	if not loaded.has(id):
		var face := entry(id)
		if not face.is_empty():
			if FACES.has(id): loaded[id] = load(face.path)
			else: loaded[id] = decode_font(FileAccess.get_file_as_bytes(face.path))
	return loaded.get(id) if loaded.get(id) != null else preload("res://assets/fonts/StudioSans.ttf")

static func scan_imports() -> void:
	if scanned: return
	scanned = true
	var folder := DirAccess.open(IMPORT_DIR)
	if not folder: return
	for filename in folder.get_files():
		var id := "custom_" + filename.get_basename()
		if not valid_id(id) or filename.get_extension() not in ["ttf", "otf"]: continue
		var path := IMPORT_DIR.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if not file or file.get_length() > MAX_FONT_BYTES: continue
		var font := decode_font(file.get_buffer(file.get_length()))
		if font: imported[id] = custom_entry(id, path, font)

static func import_font(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return {"error": "Could not open the font file."}
	var length := file.get_length()
	if length < 12 or length > MAX_FONT_BYTES: return {"error": "Choose a .ttf or .otf font under 16 MB."}
	var bytes := file.get_buffer(length)
	var font := decode_font(bytes)
	if not font: return {"error": "This file could not be read as a .ttf or .otf font."}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var key := hash.finish().hex_encode()
	var id := "custom_" + key
	scan_imports()
	if imported.has(id): return imported[id]
	var filename := key + (".otf" if bytes.slice(0, 4).get_string_from_ascii() == "OTTO" else ".ttf")
	var destination := IMPORT_DIR.path_join(filename)
	var directory := ProjectSettings.globalize_path(IMPORT_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"error": "Could not create the font library."}
	var temporary := destination + ".tmp"
	var target := FileAccess.open(temporary, FileAccess.WRITE)
	if not target: return {"error": "Could not store the font in Havu."}
	target.store_buffer(bytes)
	target.flush()
	var result := target.get_error()
	target.close()
	if result == OK:
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"error": "Could not store the font in Havu."}
	imported[id] = custom_entry(id, destination, font)
	loaded[id] = font
	return imported[id]

static func custom_entry(id: String, path: String, font: Font) -> Dictionary:
	var style := font.get_font_style_name().strip_edges()
	var family := font.get_font_name().strip_edges().left(120)
	var name := family
	if not style.is_empty() and style.to_lower() != "regular": name += " " + style
	return {"id": id, "name": name.left(120), "category": "Imported", "path": path, "family": family,
		"weight": clampi(font.get_font_weight(), 1, 1000), "italic": (font.get_font_style() & TextServer.FONT_ITALIC) != 0}

static func apply_to_text(object: Dictionary, id: String) -> void:
	var face := entry(id)
	if face.is_empty() and object.get("font") == id: return
	object.font = id
	if face.get("category") == "Imported":
		object.font_label = face.name
		object.font_family = face.family
		object.font_weight = face.weight
		object.font_italic = face.italic
	else:
		for key in ["font_label", "font_family", "font_weight", "font_italic"]: object.erase(key)

static func decode_font(bytes: PackedByteArray) -> FontFile:
	if bytes.size() < 12 or bytes.size() > MAX_FONT_BYTES: return null
	var signature := bytes.slice(0, 4).hex_encode()
	if signature not in ["00010000", "4f54544f", "74727565"]: return null
	var tables := (bytes[4] << 8) | bytes[5]
	if tables == 0 or 12 + tables * 16 > bytes.size(): return null
	for index in tables:
		var at := 20 + index * 16
		var offset := be_u32(bytes, at)
		var length := be_u32(bytes, at + 4)
		if offset + length > bytes.size(): return null
	var font := FontFile.new()
	font.data = bytes
	return font if not font.get_font_name().strip_edges().is_empty() and font.get_face_count() == 1 else null

static func be_u32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]

static func svg_alias(id: String) -> String:
	match id:
		"serif": return "Havu Serif"
		"sans": return "Havu Sans"
		_: return "Havu " + id
