class_name UIArtTest

static func run_static() -> void:
	var passed := 0
	var failed := 0

	# 1. THEME_PATH_KEY constant value
	if Constants.THEME_PATH_KEY == "theme_path":
		passed += 1
		print("UIArtTest PASS 1: THEME_PATH_KEY == 'theme_path'")
	else:
		failed += 1
		print("UIArtTest FAIL 1: THEME_PATH_KEY is '%s'" % Constants.THEME_PATH_KEY)

	# 2. FONT_BODY_ROLE constant value
	if Constants.FONT_BODY_ROLE == "body":
		passed += 1
		print("UIArtTest PASS 2: FONT_BODY_ROLE == 'body'")
	else:
		failed += 1
		print("UIArtTest FAIL 2: FONT_BODY_ROLE is '%s'" % Constants.FONT_BODY_ROLE)

	# 3. FONT_HEADER_ROLE constant value
	if Constants.FONT_HEADER_ROLE == "header":
		passed += 1
		print("UIArtTest PASS 3: FONT_HEADER_ROLE == 'header'")
	else:
		failed += 1
		print("UIArtTest FAIL 3: FONT_HEADER_ROLE is '%s'" % Constants.FONT_HEADER_ROLE)

	# 4. FONT_KEY_HINT_ROLE constant value
	if Constants.FONT_KEY_HINT_ROLE == "key_hint":
		passed += 1
		print("UIArtTest PASS 4: FONT_KEY_HINT_ROLE == 'key_hint'")
	else:
		failed += 1
		print("UIArtTest FAIL 4: FONT_KEY_HINT_ROLE is '%s'" % Constants.FONT_KEY_HINT_ROLE)

	# 5. body size default
	if GameManager.get_font_size(Constants.FONT_BODY_ROLE) == 16:
		passed += 1
		print("UIArtTest PASS 5: get_font_size('body') == 16")
	else:
		failed += 1
		print("UIArtTest FAIL 5: get_font_size('body') == %d" % GameManager.get_font_size(Constants.FONT_BODY_ROLE))

	# 6. header size default
	if GameManager.get_font_size(Constants.FONT_HEADER_ROLE) == 20:
		passed += 1
		print("UIArtTest PASS 6: get_font_size('header') == 20")
	else:
		failed += 1
		print("UIArtTest FAIL 6: get_font_size('header') == %d" % GameManager.get_font_size(Constants.FONT_HEADER_ROLE))

	# 7. key_hint size default
	if GameManager.get_font_size(Constants.FONT_KEY_HINT_ROLE) == 11:
		passed += 1
		print("UIArtTest PASS 7: get_font_size('key_hint') == 11")
	else:
		failed += 1
		print("UIArtTest FAIL 7: get_font_size('key_hint') == %d" % GameManager.get_font_size(Constants.FONT_KEY_HINT_ROLE))

	# 8. body font null (no path configured)
	if GameManager.get_font(Constants.FONT_BODY_ROLE) == null:
		passed += 1
		print("UIArtTest PASS 8: get_font('body') == null")
	else:
		failed += 1
		print("UIArtTest FAIL 8: get_font('body') is not null")

	# 9. header font null
	if GameManager.get_font(Constants.FONT_HEADER_ROLE) == null:
		passed += 1
		print("UIArtTest PASS 9: get_font('header') == null")
	else:
		failed += 1
		print("UIArtTest FAIL 9: get_font('header') is not null")

	# 10. key_hint font null
	if GameManager.get_font(Constants.FONT_KEY_HINT_ROLE) == null:
		passed += 1
		print("UIArtTest PASS 10: get_font('key_hint') == null")
	else:
		failed += 1
		print("UIArtTest FAIL 10: get_font('key_hint') is not null")

	# 11. unknown role returns null font
	if GameManager.get_font("nonexistent_role") == null:
		passed += 1
		print("UIArtTest PASS 11: get_font('nonexistent_role') == null")
	else:
		failed += 1
		print("UIArtTest FAIL 11: get_font('nonexistent_role') is not null")

	# 12. unknown role returns 16 size fallback
	if GameManager.get_font_size("nonexistent_role") == 16:
		passed += 1
		print("UIArtTest PASS 12: get_font_size('nonexistent_role') == 16")
	else:
		failed += 1
		print("UIArtTest FAIL 12: get_font_size('nonexistent_role') == %d" % GameManager.get_font_size("nonexistent_role"))

	print("UIArtTest: %d passed, %d failed" % [passed, failed])
