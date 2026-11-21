extends RefCounted
## Binary splits let any tile become a row or column without flattening its neighbors.
const GAP := 6.0
const GRIP_HEIGHT := 26.0

static func leaves(node) -> Array:
	if node is String: return [node]
	if not node is Dictionary or node.is_empty(): return []
	return leaves(node.first) + leaves(node.second)

static func without(node, key: String):
	if node is String: return {} if node == key else node
	if node.is_empty(): return node
	var first = without(node.first, key)
	var second = without(node.second, key)
	if leaves(first).is_empty(): return second
	if leaves(second).is_empty(): return first
	return {"axis": node.axis, "first": first, "second": second}

static func insert(node, target: String, source: String, side: String):
	if node is String:
		if node != target: return node
		var before := side in ["left", "top"]
		return {"axis": 0 if side in ["left", "right"] else 1,
			"first": source if before else target, "second": target if before else source}
	return {"axis": node.axis, "first": insert(node.first, target, source, side),
		"second": insert(node.second, target, source, side)}

static func replace(node, old_key: String, new_key: String):
	if node is String: return new_key if node == old_key else node
	return {"axis": node.axis, "first": replace(node.first, old_key, new_key),
		"second": replace(node.second, old_key, new_key)}

static func vertical_stack(names: Array):
	var tree = names[0]
	for index in range(1, names.size()):
		tree = {"axis": 1, "first": tree, "second": names[index]}
	return tree

static func measure(node, dimensions: Dictionary) -> Vector2:
	if node is String: return dimensions.get(node, Vector2.ZERO)
	var first := measure(node.first, dimensions)
	var second := measure(node.second, dimensions)
	if not first.x: return second
	if not second.x: return first
	if node.axis == 0: return Vector2(first.x + GAP + second.x, maxf(first.y, second.y))
	return Vector2(maxf(first.x, second.x), first.y + GAP + second.y)

static func resize_split(node, key: String, axis: int, visible: Dictionary) -> Dictionary:
	if node is String: return {}
	if key in leaves(node.first):
		var inner := resize_split(node.first, key, axis, visible)
		if not inner.is_empty(): return inner
		if node.axis == axis and measure(node.second, visible).x > 0: return node
		return {}
	return resize_split(node.second, key, axis, visible)

static func place(node, bounds: Rect2, minimum: Dictionary, preferred: Dictionary, cells: Dictionary, resize := {}) -> void:
	if node is String:
		if minimum.has(node): cells[node] = bounds
		return
	var first_min := measure(node.first, minimum)
	var second_min := measure(node.second, minimum)
	if not first_min.x:
		place(node.second, bounds, minimum, preferred, cells, resize)
		return
	if not second_min.x:
		place(node.first, bounds, minimum, preferred, cells, resize)
		return
	var axis: int = node.axis
	var span := bounds.size[axis] - GAP
	var first_natural := measure(node.first, preferred)[axis]
	var second_natural := measure(node.second, preferred)[axis]
	var requested := span * first_natural / (first_natural + second_natural)
	if not resize.is_empty():
		requested = first_natural
		if is_same(node, resize.splits[axis]): requested += resize.delta[axis]
	var first_span := clampf(roundf(requested), first_min[axis], span - second_min[axis])
	var first := bounds
	var second := bounds
	first.size[axis] = first_span
	second.position[axis] += first_span + GAP
	second.size[axis] = span - first_span
	place(node.first, first, minimum, preferred, cells, resize)
	place(node.second, second, minimum, preferred, cells, resize)

static func valid_tree(node, names: Array, seen: Array) -> bool:
	if node is String:
		if node not in names or node in seen: return false
		seen.append(node)
		return true
	if not node is Dictionary or node.get("axis") not in [0, 1]: return false
	return valid_tree(node.get("first"), names, seen) and valid_tree(node.get("second"), names, seen)
