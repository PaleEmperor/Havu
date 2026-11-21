extends Control

const FloatingPanel = preload("res://scripts/floating_panel.gd")
const TAB_SIZE := Vector2(40, 38)
const GAP := 2.0

var tabs := {}
var panels: Dictionary
var group_grips: Dictionary
var refresh_pending := false

func configure(workspace_panels: Dictionary, grips: Dictionary, icon: Texture2D, skin: StyleBox) -> void:
	panels = workspace_panels
	group_grips = grips
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_refresh)
	visibility_changed.connect(queue_refresh)
	get_parent().child_order_changed.connect(queue_refresh)
	for key in panels:
		var panel = panels[key]
		var tab := PanelContainer.new()
		tab.tooltip_text = "Drag to uncover " + key
		tab.mouse_default_cursor_shape = CURSOR_DRAG
		tab.size = TAB_SIZE
		tab.add_theme_stylebox_override("panel", skin)
		var handle := TextureRect.new()
		handle.texture = icon
		handle.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		handle.mouse_filter = MOUSE_FILTER_IGNORE
		tab.add_child(handle)
		add_child(tab)
		tab.hide()
		tab.gui_input.connect(func(event):
			if panel.start_gesture(event, "move", tab):
				tab.accept_event()
				tab.hide())
		tabs[key] = tab
		panel.item_rect_changed.connect(queue_refresh)
		panel.visibility_changed.connect(queue_refresh)
	queue_refresh()

func queue_refresh() -> void:
	if refresh_pending or not is_visible_in_tree(): return
	refresh_pending = true
	refresh.call_deferred()

func refresh() -> void:
	refresh_pending = false
	if not is_visible_in_tree(): return
	var work := FloatingPanel.work_area(get_parent(), false)
	var ordered := panels.keys().filter(func(key): return panels[key].is_visible_in_tree())
	ordered.sort_custom(func(a, b): return panels[a].get_index() > panels[b].get_index())
	var occupied: Array[Rect2] = []
	for key in ordered: occupied.append(panels[key].get_rect())
	for grip in group_grips.values():
		if grip.is_visible_in_tree(): occupied.append(grip.get_rect())

	var covers: Array[Rect2] = []
	var placed: Array[Rect2] = []
	var shown := {}
	for key in ordered:
		var panel = panels[key]
		var bounds: Rect2 = panel.get_rect()
		if panel.gesture.is_empty() and bounds.has_area() and fully_covered(bounds, covers):
			var position_near_header := bounds.position + Vector2(16, 3)
			var slot := find_slot(work, Rect2(position_near_header, TAB_SIZE), occupied, GAP)
			# A full workspace can leave no room outside the covering panels.
			if not slot.has_area(): slot = find_slot(work, Rect2(position_near_header, TAB_SIZE), placed, GAP)
			if slot.has_area():
				var tab: Control = tabs[key]
				tab.position = slot.position
				shown[key] = true
				placed.append(slot)
				occupied.append(slot)
		covers.append(bounds)
	for key in tabs: tabs[key].visible = shown.has(key)
	if not placed.is_empty() and get_index() < get_parent().get_child_count() - 1:
		move_to_front()

func fully_covered(bounds: Rect2, covers: Array[Rect2]) -> bool:
	var exposed: Array[Rect2] = [bounds]
	for cover in covers:
		var remaining: Array[Rect2] = []
		for rect in exposed:
			var overlap := rect.intersection(cover)
			if not overlap.has_area():
				remaining.append(rect)
				continue
			for piece in [
				Rect2(rect.position.x, rect.position.y, rect.size.x, overlap.position.y - rect.position.y),
				Rect2(rect.position.x, overlap.end.y, rect.size.x, rect.end.y - overlap.end.y),
				Rect2(rect.position.x, overlap.position.y, overlap.position.x - rect.position.x, overlap.size.y),
				Rect2(overlap.end.x, overlap.position.y, rect.end.x - overlap.end.x, overlap.size.y),
			]:
				if piece.has_area(): remaining.append(piece)
		if remaining.is_empty(): return true
		exposed = remaining
	return false

static func find_slot(work: Rect2, desired: Rect2, occupied: Array[Rect2], gap: float,
		headers: Array[Rect2] = [], allow_overlap := false) -> Rect2:
	var last := work.end - desired.size
	if last.x < work.position.x or last.y < work.position.y: return Rect2()
	var preferred := desired.position.clamp(work.position, last)
	var xs: Array[float] = [preferred.x, work.position.x, last.x]
	var ys: Array[float] = [preferred.y, work.position.y, last.y]
	for rect in occupied + headers:
		xs.append_array([rect.position.x - desired.size.x - gap, rect.end.x + gap])
		ys.append_array([rect.position.y - desired.size.y - gap, rect.end.y + gap])
	var best := Rect2()
	var best_score := Vector3(INF, INF, INF)
	for x in xs:
		if x < work.position.x or x > last.x: continue
		for y in ys:
			if y < work.position.y or y > last.y: continue
			var point := Vector2(x, y)
			var candidate := Rect2(point, desired.size)
			var distance := point.distance_squared_to(preferred)
			if not allow_overlap:
				if distance >= best_score.z or occupied.any(func(rect): return rect.grow(gap).intersects(candidate)): continue
				best_score.z = distance
			else:
				var covered := 0.0
				var overlap := 0.0
				for header in headers: covered += candidate.intersection(header).get_area()
				for rect in occupied: overlap += candidate.intersection(rect).get_area()
				var score := Vector3(covered, overlap, distance)
				if score >= best_score: continue
				best_score = score
			best = candidate
	return best
