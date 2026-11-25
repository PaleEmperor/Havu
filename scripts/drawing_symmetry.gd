extends RefCounted

const Art = preload("res://scripts/artwork.gd")

enum Mode { OFF, VERTICAL, HORIZONTAL, FOUR_WAY, RADIAL }

static func poses(mode: int, arms: int, pivot: Vector2) -> Array[Transform2D]:
	var result: Array[Transform2D] = []
	match mode:
		Mode.VERTICAL:
			result.append(Transform2D(Vector2.LEFT, Vector2.DOWN, Vector2.ZERO))
		Mode.HORIZONTAL:
			result.append(Transform2D(Vector2.RIGHT, Vector2.UP, Vector2.ZERO))
		Mode.FOUR_WAY:
			result.append(Transform2D(Vector2.LEFT, Vector2.DOWN, Vector2.ZERO))
			result.append(Transform2D(Vector2.RIGHT, Vector2.UP, Vector2.ZERO))
			result.append(Transform2D(PI, Vector2.ZERO))
		Mode.RADIAL:
			arms = clampi(arms, 2, 12)
			for arm in range(1, arms):
				result.append(Transform2D(TAU * arm / arms, Vector2.ZERO))
	for index in result.size():
		var pose := result[index]
		pose.origin = pivot - pose.basis_xform(pivot)
		result[index] = pose
	return result

static func stroke_instance(stroke: Dictionary, pose: Transform2D) -> Dictionary:
	var copy := stroke.duplicate()
	var mirrored := pose.determinant() < 0.0
	var angle := (-pose.x if mirrored else pose.x).angle()
	copy.pos = [pose.origin.x, pose.origin.y]
	if not is_zero_approx(angle): copy.angle = angle
	if mirrored: copy.mirrored = true
	# Selection and alpha masks belong to the layer. Map their outlines into
	# each copy's local space so the same document-space restriction applies.
	var inverse := pose.affine_inverse()
	if stroke.has("clip"):
		copy.clip = Art.pack_contours([inverse * Art.unpack_polygon(stroke.clip)])[0]
	if stroke.has("paint_mask"):
		var regions: Array[PackedVector2Array] = []
		for region in stroke.paint_mask: regions.append(inverse * Art.unpack_polygon(region))
		copy.paint_mask = Art.pack_contours(regions)
	return copy
