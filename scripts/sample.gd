extends RefCounted
## Hand-authored vector menu; every element is editable.
static func populate(document) -> void:
	document.blank()
	document.title = "The little green café"
	document.layers = [document.new_layer("Background"), document.new_layer("Botanical illustration"), document.new_layer("Menu & lettering"), document.new_layer("Your brushwork")]
	document.active = 0
	shape(document, "rect", [44, 44], [812, 1012], "#e8ede2")
	shape(document, "rect", [47, 47], [806, 1006], "#faf8f1")
	shape(document, "rect", [90, 438], [720, 2], "#b0baaa")
	shape(document, "rect", [90, 858], [720, 2], "#b0baaa")
	document.active = 1
	# Drawn botanical sprigs, a cup and saucer. No generated imagery.
	for mirror in [false, true]:
		var base = Vector2(180, 390) if not mirror else Vector2(720, 390)
		var direction = 1.0 if not mirror else -1.0
		var stem_points = []
		for i in range(22):
			var t = float(i) / 21
			stem_points.append([base.x + direction * sin(t * 1.8) * 82, base.y - t * 210, 0.5, "#547c60"])
		document.add({"kind": "stroke", "brush": "ink", "size": 3.0, "points": stem_points, "color": "#547c60", "opacity": 1.0})
		for i in range(7):
			var t = 0.16 + i * 0.11
			var p = Vector2(base.x + direction * sin(t * 1.8) * 82, base.y - t * 210)
			var side = 1 if i % 2 == 0 else -1
			var leaf = []
			var tip = p + Vector2(direction * side * 44, -34)
			for k in range(25):
				var s = float(k) / 24
				var mid = p.lerp(tip, s)
				var offset = Vector2(12, 10) * sin(s * PI)
				leaf.append([mid.x + offset.x, mid.y + offset.y])
			for k in range(24, -1, -1):
				var s = float(k) / 24
				var mid = p.lerp(tip, s)
				var offset = Vector2(12, 10) * sin(s * PI)
				leaf.append([mid.x - offset.x, mid.y - offset.y])
			document.add({"kind": "polygon", "vertices": leaf, "color": "#547c60" if i % 2 == 0 else "#9eaf8b", "opacity": 0.9})
	shape(document, "ellipse", [336, 754], [225, 24], "#d8dfce")
	shape(document, "ellipse", [493, 678], [58, 58], "#517560")
	shape(document, "ellipse", [504, 689], [34, 34], "#faf8f1")
	document.add({"kind": "polygon", "vertices": [[353, 678], [506, 678], [488, 741], [471, 757], [387, 757], [369, 741]], "color": "#517560", "opacity": 1.0})
	shape(document, "ellipse", [353, 667], [153, 25], "#b4c3a4")
	shape(document, "ellipse", [364, 673], [131, 14], "#785a41")
	for dx in [0, 30, 60]:
		var points = []
		for i in range(24): points.append([400 + dx + sin(i * 0.24) * 5, 653 - i * 1.7, 0.45, "#b2bda6"])
		document.add({"kind": "stroke", "brush": "ink", "size": 2.5, "points": points, "color": "#b2bda6", "opacity": 0.8})
	document.active = 2
	text(document, "S L O W  M O R N I N G S  ·  G O O D  C O F F E E", [229, 111], 13, "sans", "#6f7e68")
	text(document, "the little", [333, 196], 45, "serif")
	text(document, "green café", [246, 268], 69, "serif")
	text(document, "Freshly made. Thoughtfully served.", [286, 319], 19, "sans", "#71836d")
	text(document, "A little taste of the season", [263, 403], 27, "serif")
	text(document, "S O M E T H I N G  T O  S I P", [100, 489], 14, "sans", "#6f7e68")
	for entry in [["Flat white", "3.80", 540], ["Matcha latte", "4.50", 586], ["Slow-brewed filter", "3.20", 632]]:
		text(document, entry[0], [100, entry[2]], 25, "serif")
		text(document, entry[1], [727, entry[2]], 24, "sans")
	text(document, "A moment, just for you.", [304, 822], 24, "serif", "#6b8164")
	text(document, "S O M E T H I N G  S W E E T", [100, 909], 14, "sans", "#6f7e68")
	text(document, "Cardamom bun", [100, 958], 26, "serif")
	text(document, "3.50", [727, 958], 24, "sans")
	text(document, "Baked here, every morning.", [100, 987], 16, "sans", "#71836d")
	text(document, "M A D E  W I T H  A  L I T T L E  L O V E", [292, 1030], 11, "sans", "#71836d")
	document.active = 3
	document.selection = ""
	document.history.clear()
	document.dirty = false
	document.changed.emit()

static func shape(document, kind, pos, extent, color) -> void:
	document.add({"kind": kind, "pos": pos, "extent": extent, "color": color, "opacity": 1.0})
static func text(document, content, pos, size, font = "serif", color = "#284c39") -> void:
	document.add({"kind": "text", "text": content, "pos": pos, "font_size": float(size), "font": font, "color": color, "opacity": 1.0})
