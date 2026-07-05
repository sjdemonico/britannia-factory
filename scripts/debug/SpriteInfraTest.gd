class_name SpriteInfraTest
extends RefCounted

static func run_static() -> void:
	var passed: int = 0
	var failed: int = 0

	# -- SpriteLoader.load_sprite --

	# 1. null path returns null
	if SpriteLoader.load_sprite(null) == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [1]: load_sprite(null) should return null")
		failed += 1

	# 2. empty string returns null
	if SpriteLoader.load_sprite("") == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [2]: load_sprite(\"\") should return null")
		failed += 1

	# 3. nonexistent path returns null
	if SpriteLoader.load_sprite("res://nonexistent_sprite_xyz.png") == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [3]: load_sprite(missing path) should return null")
		failed += 1

	# -- SpriteLoader.apply_to_node (Sprite2D) --

	# 4. null path leaves Sprite2D unchanged, returns false
	var s4 := Sprite2D.new()
	if not SpriteLoader.apply_to_node(s4, null, Constants.SPRITE_WORLD_SIZE):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [4]: apply_to_node with null path should return false")
		failed += 1
	if s4.texture == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [4b]: apply_to_node with null path should not set texture")
		failed += 1
	s4.free()

	# 5. missing file path returns false, leaves Sprite2D unchanged
	var s5 := Sprite2D.new()
	if not SpriteLoader.apply_to_node(s5, "res://nonexistent_xyz.png", Constants.SPRITE_WORLD_SIZE):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [5]: apply_to_node with missing file should return false")
		failed += 1
	if s5.texture == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [5b]: apply_to_node with missing file should not set texture")
		failed += 1
	s5.free()

	# 6. null path leaves TextureRect unchanged, returns false
	var tr6 := TextureRect.new()
	if not SpriteLoader.apply_to_node(tr6, null, Constants.SPRITE_ICON_SIZE):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [6]: apply_to_node(TextureRect) with null path should return false")
		failed += 1
	if tr6.texture == null:
		passed += 1
	else:
		print("FAIL SpriteInfraTest [6b]: apply_to_node(TextureRect) with null path should not set texture")
		failed += 1
	tr6.free()

	# -- Valid texture path (use built-in Godot icon if no project sprites yet) --
	const _TEST_SPRITE_PATH := "res://assets/sprites/object_carriable.png"
	if ResourceLoader.exists(_TEST_SPRITE_PATH):
		# 7. apply_to_node on Sprite2D with valid path: returns true, sets texture, correct scale, NEAREST filter
		var s7 := Sprite2D.new()
		if SpriteLoader.apply_to_node(s7, _TEST_SPRITE_PATH, Constants.SPRITE_WORLD_SIZE):
			passed += 1
		else:
			print("FAIL SpriteInfraTest [7]: apply_to_node with valid path should return true")
			failed += 1
		if s7.texture != null:
			passed += 1
		else:
			print("FAIL SpriteInfraTest [7b]: apply_to_node should set texture")
			failed += 1
		var expected_scale := Vector2(Constants.SPRITE_WORLD_SIZE) / Vector2(Constants.SPRITE_SOURCE_SIZE)
		if s7.scale.is_equal_approx(expected_scale):
			passed += 1
		else:
			print("FAIL SpriteInfraTest [7c]: scale should be ", expected_scale, " got ", s7.scale)
			failed += 1
		if s7.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST:
			passed += 1
		else:
			print("FAIL SpriteInfraTest [7d]: texture_filter should be NEAREST")
			failed += 1
		if s7.visible:
			passed += 1
		else:
			print("FAIL SpriteInfraTest [7e]: sprite should be set visible")
			failed += 1
		s7.free()

		# 8. apply_to_node on TextureRect with valid path: returns true, sets texture, NEAREST filter
		var tr8 := TextureRect.new()
		if SpriteLoader.apply_to_node(tr8, _TEST_SPRITE_PATH, Constants.SPRITE_ICON_SIZE):
			passed += 1
		else:
			print("FAIL SpriteInfraTest [8]: apply_to_node(TextureRect) with valid path should return true")
			failed += 1
		if tr8.texture != null:
			passed += 1
		else:
			print("FAIL SpriteInfraTest [8b]: apply_to_node(TextureRect) should set texture")
			failed += 1
		if tr8.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST:
			passed += 1
		else:
			print("FAIL SpriteInfraTest [8c]: TextureRect texture_filter should be NEAREST")
			failed += 1
		tr8.free()

	# -- Constants --

	# 9. SPRITE_SOURCE_SIZE
	if Constants.SPRITE_SOURCE_SIZE == Vector2i(64, 64):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [9]: SPRITE_SOURCE_SIZE should be Vector2i(64,64)")
		failed += 1

	# 10. SPRITE_WORLD_SIZE
	if Constants.SPRITE_WORLD_SIZE == Vector2i(32, 32):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [10]: SPRITE_WORLD_SIZE should be Vector2i(32,32)")
		failed += 1

	# 11. SPRITE_ICON_SIZE
	if Constants.SPRITE_ICON_SIZE == Vector2i(16, 16):
		passed += 1
	else:
		print("FAIL SpriteInfraTest [11]: SPRITE_ICON_SIZE should be Vector2i(16,16)")
		failed += 1

	print("SpriteInfraTest: ", passed, " passed, ", failed, " failed")
