extends RefCounted
## Composite a sequence of editable marks with nested opacity scopes.
var scopes: Array = []
var colors: Array[Color]

func _init(background := Color.TRANSPARENT) -> void:
	colors = [background]

static func shared_depth(previous: Array, next: Array) -> int:
	var shared := 0
	while shared < mini(previous.size(), next.size()) and previous[shared] == next[shared]:
		shared += 1
	return shared

func add(color: Color, groups: Array) -> void:
	var shared := shared_depth(scopes, groups)
	close_to(shared)
	for index in range(shared, groups.size()):
		scopes.append(groups[index])
		colors.append(Color.TRANSPARENT)
	colors[-1] = colors[-1].blend(color)

func close_to(depth: int) -> void:
	while scopes.size() > depth:
		var top: Color = colors.pop_back()
		var group: Dictionary = scopes.pop_back()
		top.a *= group.opacity
		colors[-1] = colors[-1].blend(top)

func result() -> Color:
	close_to(0)
	return colors[0]
