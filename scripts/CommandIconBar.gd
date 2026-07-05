class_name CommandIconBar
extends Control

const _COLOR_AVAILABLE := Color(1.0, 1.0, 1.0, 1.0)
const _COLOR_GREYED    := Color(1.0, 1.0, 1.0, 0.4)

# Maps command string -> the clickable Panel node
var _icon_buttons: Dictionary = {}

# Maps command string -> the input action to fire
const _ACTION_MAP: Dictionary = {
	"talk":      "talk",
	"look":      "look",
	"get":       "get",
	"use":       "use",
	"move":      "move",
	"attack":    "attack",
	"cast":      "toggle_spellbook",
	"rest":      "rest",
	"save_load": "toggle_save_load",
	"quit":      "quit_game",
}

func _ready() -> void:
	_load_and_build()
	update_icon_states()

func _process(_delta: float) -> void:
	update_icon_states()

func _load_and_build() -> void:
	var data: Dictionary = Constants.load_json(Constants.COMMAND_ICONS_CONFIG_PATH)
	if data.is_empty() or not data.has("icons"):
		push_error("CommandIconBar: failed to load command_icons.json")
		return
	var icons: Array = data["icons"]
	_build_layout(icons)

func _build_layout(icons: Array) -> void:
	const COLS: int = 5
	const BTN_W: float = 160.0
	const BTN_H: float = 75.0
	var total_w: float = float(Constants.MAP_PIXEL_WIDTH)
	var total_h: float = float(Constants.BELOW_MAP_HEIGHT)
	var rows: int = ceili(float(icons.size()) / float(COLS))
	var gap_x: float = (total_w - BTN_W * COLS) / float(COLS + 1)
	var gap_y: float = (total_h - BTN_H * float(rows)) / float(rows + 1)

	for i in range(icons.size()):
		var entry: Dictionary = icons[i]
		var cmd: String = entry.get("command", "")
		var label_text: String = entry.get("label", cmd)
		var key_hint: String = entry.get("key", "")
		var icon_path = entry.get("icon_path", null)

		var col: int = i % COLS
		var row: int = floori(float(i) / COLS)
		var bx: float = gap_x + float(col) * (BTN_W + gap_x)
		var by: float = gap_y + float(row) * (BTN_H + gap_y)

		# Panel is the clickable container; children are free-positioned on top of it.
		var panel := Panel.new()
		panel.name = "Btn_" + cmd
		panel.position = Vector2(bx, by)
		panel.size = Vector2(BTN_W, BTN_H)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		# Icon area fills the entire button — placeholder until M23 art is supplied.
		_add_icon_area(panel, icon_path, BTN_W, BTN_H)

		# Label near the bottom, passes clicks through to the panel.
		var lbl := Label.new()
		lbl.text = label_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(2.0, BTN_H - 34.0)
		lbl.size = Vector2(BTN_W - 4.0, 20.0)
		if GameManager.get_font(Constants.FONT_BODY_ROLE):
			lbl.add_theme_font_override("font", GameManager.get_font(Constants.FONT_BODY_ROLE))
		lbl.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_BODY_ROLE))
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(lbl)

		# Key hint at bottom-right corner.
		var key_lbl := Label.new()
		key_lbl.text = "[" + key_hint + "]"
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_lbl.position = Vector2(2.0, BTN_H - 14.0)
		key_lbl.size = Vector2(BTN_W - 6.0, 12.0)
		if GameManager.get_font(Constants.FONT_KEY_HINT_ROLE):
			key_lbl.add_theme_font_override("font", GameManager.get_font(Constants.FONT_KEY_HINT_ROLE))
		key_lbl.add_theme_font_size_override("font_size", GameManager.get_font_size(Constants.FONT_KEY_HINT_ROLE))
		key_lbl.modulate = Color(0.7, 0.7, 0.7, 1.0)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(key_lbl)

		var cmd_cap: String = cmd
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_on_icon_clicked(cmd_cap)
		)

		add_child(panel)
		_icon_buttons[cmd] = panel

func _add_icon_area(panel: Panel, icon_path, btn_w: float, btn_h: float) -> void:
	if icon_path != null and icon_path != "":
		if ResourceLoader.exists(icon_path):
			var tex = load(icon_path)
			if tex is Texture2D:
				var sprite := TextureRect.new()
				sprite.texture = tex
				sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sprite.position = Vector2.ZERO
				sprite.size = Vector2(btn_w, btn_h)
				sprite.mouse_filter = Control.MOUSE_FILTER_PASS
				panel.add_child(sprite)
				return
		push_warning("CommandIconBar: icon not found at '" + str(icon_path) + "', using text label")
	var placeholder := ColorRect.new()
	placeholder.color = Color(0.2, 0.2, 0.2, 1.0)
	placeholder.position = Vector2.ZERO
	placeholder.size = Vector2(btn_w, btn_h)
	placeholder.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(placeholder)

func _on_icon_clicked(command: String) -> void:
	var action: String = _ACTION_MAP.get(command, "")
	if action.is_empty():
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)

func update_icon_states() -> void:
	var in_combat: bool = CombatManager.in_combat
	var no_mana: bool = PlayerStats.get_effective_value("mana") == 0
	var no_spells: bool = SpellManager._local_known_spells.is_empty()

	for cmd in _icon_buttons:
		var btn: Control = _icon_buttons[cmd]
		var greyed: bool = _is_greyed(cmd, in_combat, no_mana, no_spells)
		btn.modulate = _COLOR_GREYED if greyed else _COLOR_AVAILABLE

func _is_greyed(cmd: String, in_combat: bool, no_mana: bool, no_spells: bool) -> bool:
	match cmd:
		"talk":      return in_combat
		"look":      return false
		"get":       return false
		"use":       return in_combat
		"move":      return in_combat
		"attack":    return false
		"cast":      return no_spells or no_mana
		"rest":      return in_combat
		"save_load": return in_combat
		"quit":      return false
		_:           return false
