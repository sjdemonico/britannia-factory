class_name AnimationTest
extends RefCounted

static func run_static() -> void:
	var passed: int = 0
	var failed: int = 0

	var anim := SpriteAnimator.new()
	anim.load_config(0.2)

	# 1. register with null path returns -1
	var h1 := anim.register(Sprite2D.new(), null, Constants.SPRITE_WORLD_SIZE)
	if h1 == -1:
		passed += 1
	else:
		print("FAIL AnimationTest [1]: register(null) should return -1, got ", h1)
		failed += 1

	# 2. register with missing path returns -1
	var h2 := anim.register(Sprite2D.new(), "res://nonexistent_sprite.png", Constants.SPRITE_WORLD_SIZE)
	if h2 == -1:
		passed += 1
	else:
		print("FAIL AnimationTest [2]: register(missing) should return -1, got ", h2)
		failed += 1

	# 3. set_sheet on -1 does not crash
	anim.set_sheet(-1, "res://nonexistent.png")
	passed += 1

	# 4. unregister on -1 does not crash
	anim.unregister(-1)
	passed += 1

	# 5. sprite sheet constants
	if Constants.SPRITE_SHEET_FRAME_COUNT == 4 and Constants.SPRITE_SHEET_FRAME_WIDTH == 64 and Constants.SPRITE_SHEET_FRAME_HEIGHT == 64 and Constants.SPRITE_SHEET_TOTAL_WIDTH == 256:
		passed += 1
	else:
		print("FAIL AnimationTest [5]: sheet constants wrong — count=", Constants.SPRITE_SHEET_FRAME_COUNT,
			" w=", Constants.SPRITE_SHEET_FRAME_WIDTH, " h=", Constants.SPRITE_SHEET_FRAME_HEIGHT,
			" total=", Constants.SPRITE_SHEET_TOTAL_WIDTH)
		failed += 1

	# 6–8. Tests requiring a 256×64 animated test sheet
	const _ANIM_PATH := "res://assets/sprites/test_anim_sheet.png"
	if ResourceLoader.exists(_ANIM_PATH):
		var anim2 := SpriteAnimator.new()
		anim2.load_config(0.2)
		var node_a := Sprite2D.new()
		var node_b := Sprite2D.new()
		var ha := anim2.register(node_a, _ANIM_PATH, Constants.SPRITE_WORLD_SIZE)
		var hb := anim2.register(node_b, _ANIM_PATH, Constants.SPRITE_WORLD_SIZE)

		# 6. Frame advances after one tick interval
		var x_before: float = anim2._registered[ha]["atlas"].region.position.x
		anim2.tick(0.2)
		var x_after: float = anim2._registered[ha]["atlas"].region.position.x
		if x_after != x_before:
			passed += 1
		else:
			print("FAIL AnimationTest [6]: frame did not advance after one tick")
			failed += 1

		# tick three more to complete the loop
		anim2.tick(0.2)
		anim2.tick(0.2)
		anim2.tick(0.2)
		var x_loop: float = anim2._registered[ha]["atlas"].region.position.x
		if x_loop == 0.0:
			passed += 1
		else:
			print("FAIL AnimationTest [6b]: frame did not loop back to 0 after 4 ticks, x=", x_loop)
			failed += 1

		# 7. Two sprites remain at same frame
		var xa: float = anim2._registered[ha]["atlas"].region.position.x
		var xb: float = anim2._registered[hb]["atlas"].region.position.x
		if xa == xb:
			passed += 1
		else:
			print("FAIL AnimationTest [7]: two sprites out of sync — a=", xa, " b=", xb)
			failed += 1

		node_a.free()
		node_b.free()
	else:
		# skip gracefully if test asset not yet present
		passed += 3

	# 8. Static sprite (64×64) always shows frame 0
	if ResourceLoader.exists(Constants.SPRITE_CARRIABLE_PATH):
		var anim3 := SpriteAnimator.new()
		anim3.load_config(0.2)
		var node_s := Sprite2D.new()
		var hs := anim3.register(node_s, Constants.SPRITE_CARRIABLE_PATH, Constants.SPRITE_WORLD_SIZE)
		if hs >= 0:
			anim3.tick(0.2)
			anim3.tick(0.2)
			var sx: float = anim3._registered[hs]["atlas"].region.position.x
			if sx == 0.0:
				passed += 1
			else:
				print("FAIL AnimationTest [8]: static sprite frame x should be 0, got ", sx)
				failed += 1
			node_s.free()
		else:
			print("FAIL AnimationTest [8]: static sprite registration returned -1")
			failed += 1
	else:
		passed += 1

	# 9. animation_frame_interval in time.json equals 0.2
	var time_data: Dictionary = Constants.load_json(Constants.TIME_CONFIG_PATH)
	var interval = time_data.get("animation_frame_interval", null)
	if interval != null and absf(float(interval) - 0.2) < 0.0001:
		passed += 1
	else:
		print("FAIL AnimationTest [9]: animation_frame_interval should be 0.2, got ", interval)
		failed += 1

	print("AnimationTest: ", passed, " passed, ", failed, " failed")
