# Changelog

All notable changes to Britannia Factory are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased] — 2026-06-27

### Added (M22e — Mouse Support Gaps)

- **`MouseGapsTest`** (`scripts/debug/MouseGapsTest.gd`) — 15-test suite (8 static, 7 integration); static tests cover `TargetingReticle.activate` sets fields, `move_to` updates `current_tile`, `set_ae_tiles` stores tiles, in-range click returns true and updates tile, out-of-range click returns false and holds origin, boundary click at exactly the range limit returns true, `deactivate` clears state; integration tests cover arena not-player-turn guard, `_on_arena_clicked` reticle branch, and panel open/close via sidebar row click; wired into `GameManager._ready()` (static) and `_run_world_tests()` (integration)
- **`GameManager.open_character_panel_at(index)`** (`autoloads/GameManager.gd`) — public method delegating to `character_panel.open_at_index(index)`; called by the new sidebar row `gui_input` handler

### Changed (M22e — Mouse Support Gaps)

- **`PartySidebar` rows respond to mouse clicks** (`scripts/PartySidebar.gd`) — `_build_row_node` sets `row.mouse_filter = Control.MOUSE_FILTER_STOP` and connects a `gui_input` lambda; left-click calls `GameManager.open_character_panel_at(idx)` to open the character panel at that member's index
- **`GameManager._run_world_tests()` closes all panels before running `CommandIconTest`** (`autoloads/GameManager.gd`) — calls `_close()`/`close()` on all six managed panels (character, spellbook, journal, save_load, shop, healer) before invoking `CommandIconTest.run()`; prevents `_is_any_panel_open()` from blocking `Input.parse_input_event` dispatches in the test suite if a panel was opened by the new sidebar click handler during world setup
- **`CommandIconBar.update_icon_states()` reads `SpellManager._local_known_spells` directly** (`scripts/CommandIconBar.gd`) — previously called `SpellManager.get_known_spells()` which reads `player.known_spells` when a player node exists; `CommandIconTest._test_cast_greyed_no_spells` reassigns `_local_known_spells = saved_spells` (reference swap, not mutation), permanently decoupling `player.known_spells`; using `_local_known_spells.is_empty()` directly is safe because `SaveManager` always mutates the spell list in-place via the property

### Fixed (M22e — Mouse Support Gaps)

- **`SHADOWED_GLOBAL_IDENTIFIER` warning** (`scripts/TargetingReticle.gd`) — parameter `range` in `activate()` shadowed the built-in `range()` function; renamed to `valid_range` throughout signature and body; no call-site changes needed (positional arguments)
- **`SHADOWED_VARIABLE_BASE_CLASS` warning** (`scripts/CombatArena.gd`) — local variable `tr` in `_setup_tileset()` shadowed `Object.tr`; renamed to `tile_reg` throughout the local scope
- **`INTEGER_DIVISION` warnings** (`scripts/ArenaGenerator.gd`) — `var cx: int = width / 2` and `var cy: int = height / 2` triggered GDScript 4 integer-division warnings; changed to `int(width / 2.0)` and `int(height / 2.0)`
- **`MessageRegistry` missing-key errors during startup** (`autoloads/MessageRegistry.gd`) — `GameManager` is autoload #6, `MessageRegistry` is autoload #8; `GameManager._ready()` called `run_static()` test suites before `MessageRegistry._ready()` had loaded `messages.json`, causing `push_error` for any key accessed from a static test; changed `_ready()` to `_init()` so the JSON is loaded at object construction, before any `_ready()` runs
- **Click-to-move rejected tiles adjacent to the player in combat** (`scripts/CombatArena.gd`) — `_move_one_step_toward` checked `path.size() < 2` and computed direction as `path[1] - path[0]`; `Pathfinder.reconstruct_path` does not include the start node, so a one-step path returns `[goal]` (size 1), failing the guard even when the target was reachable; fixed by checking `path.is_empty()` and computing direction as `path[0] - _active_combatant.current_tile`; consistent with all other callers of `Pathfinder.find_path` which treat `path[0]` as the next tile

---

### Added (M22d — Command Icons and Direction Prompt Mouse Support)

- **`CommandIconBar`** (`scripts/CommandIconBar.gd`) — new `Control` instantiated in `HUD._ready()` and positioned in the below-viewport area (x=0, y=672, 864×181 px); loads `command_icons.json` on `_ready`, builds two rows of five `Panel`-based buttons (Talk, Look, Get, Use, Move / Attack, Cast, Rest, Save/Load, Quit); each button's icon area fills the entire button face (full-size `ColorRect` placeholder; replaced with `TextureRect` when `icon_path` is non-null and the resource exists); command label and key-hint overlaid as `MOUSE_FILTER_PASS` children so clicks fall through to the panel; clicking fires the corresponding input action via `Input.parse_input_event(InputEventAction)`
- **`CommandIconBar.update_icon_states()`** (`scripts/CommandIconBar.gd`) — called every `_process` tick; greys (`modulate.a = 0.4`) or restores (`modulate.a = 1.0`) each button based on availability: `talk`, `use`, `move`, `rest`, `save_load` greyed during combat; `cast` greyed when no known spells or mana == 0; `look`, `get`, `attack`, `quit` never greyed
- **`data/config/command_icons.json`** — defines the 10 command icon entries (command id, display label, key hint, optional `icon_path`); loaded by `CommandIconBar._load_and_build()`; `icon_path: null` uses text-label-only placeholder; non-null path loads `Texture2D` with fallback to placeholder and a `push_warning` on missing resource
- **`Constants.COMMAND_ICONS_CONFIG_PATH`** (`autoloads/Constants.gd`) — `"res://data/config/command_icons.json"`
- **`DirectionPromptOverlay`** (`scripts/DirectionPromptOverlay.gd`) — new `Node2D` added to `SubViewport` with `z_index = 101` (above `DarknessOverlay` at 100); hidden by default; `show_prompt(player_tile)` shows the node and calls `queue_redraw()`; `hide_prompt()` hides the node; `_draw()` fills each of the 8 adjacent in-bounds tiles with `Color(1, 1, 0, 0.3)` (yellow) and the player tile itself with `Color(0, 1, 1, 0.3)` (cyan); tile bounds checked against `GameManager.get_region_bounds()`
- **`Player._direction_prompt_active`** (`scripts/Player.gd`) — `bool` flag set `true` in `prompt_direction()` alongside `_awaiting_prompt`; cleared in `_resolve_prompt()` and `_cancel_prompt()`; read by `GameManager._on_map_clicked` to route map clicks to the direction prompt handler instead of normal path-finding
- **`Player._on_direction_prompt_map_click(tile)`** (`scripts/Player.gd`) — called by `GameManager._on_map_clicked` when `_direction_prompt_active` is true; hides the overlay; resolves to `Vector2i.ZERO` if the tile is the player tile, resolves to the delta if the tile is adjacent (Chebyshev ≤ 1), cancels otherwise
- **`GameManager.direction_overlay` / `GameManager.command_icon_bar`** (`autoloads/GameManager.gd`) — nullable references wired by `HUD._ready()`; `direction_overlay` is used by `Player.prompt_direction` / `_resolve_prompt` / `_cancel_prompt`; `command_icon_bar` is passed to `CommandIconTest.run()` in debug builds
- **`CommandIconTest`** (`scripts/debug/CommandIconTest.gd`) — 22-test suite (8 static, 14 integration); static tests cover icon count, row 1/row 2 command membership, label matching against JSON, invalid-path fallback (ColorRect), valid-path texture (TextureRect), and direction delta math; integration tests cover Talk/Look icon clicks activating direction prompt, never-greyed commands, combat-greyed commands, cast grey with no spells/mana/both, direction overlay visible on prompt, adjacent/diagonal/self click resolution, non-adjacent click cancels, keyboard input during active overlay, and icon state toggling across combat transitions; wired into `GameManager._ready()` (static) and `_run_world_tests()` (integration)

### Changed (M22d — Command Icons and Direction Prompt Mouse Support)

- **`prompt_direction()` shows direction overlay** (`scripts/Player.gd`) — calls `GameManager.direction_overlay.show_prompt(tile_pos)` after setting `_awaiting_prompt`; `_resolve_prompt` and `_cancel_prompt` both call `hide_prompt()` so the overlay is always dismissed on any prompt resolution or cancellation, including keyboard input
- **`_on_map_clicked` routes direction prompt clicks before all other guards** (`autoloads/GameManager.gd`) — computes the world tile once from `sub_viewport.get_mouse_position()` + `canvas_transform.affine_inverse()`, then checks `_direction_prompt_active` first; direction prompt clicks bypass the combat guard so direction prompts remain functional in combat; the unused `mouse_position` parameter renamed `_mouse_position` to suppress the lint warning
- **`HUD._ready()` creates and wires `DirectionPromptOverlay` and `CommandIconBar`** (`scripts/HUD.gd`) — `DirectionPromptOverlay` added to `SubViewport` (hidden, z=101); `CommandIconBar` added directly to the HUD `Control` at `(0, MAP_PIXEL_HEIGHT)` with explicit `size = (MAP_PIXEL_WIDTH, BELOW_MAP_HEIGHT)`; both references assigned to `GameManager`
- **`CommandIconBar` button icon area fills entire button** (`scripts/CommandIconBar.gd`) — icon `ColorRect`/`TextureRect` is sized to the full button dimensions (`160 × 75 px`) rather than a fixed 32×32 square, making the whole face available for designer-supplied art in M23; label and key-hint sit on top as free-positioned overlays with `MOUSE_FILTER_PASS`

### Fixed (M22d — Command Icons and Direction Prompt Mouse Support)

- **Direction overlay draws in world coordinates using region bounds** (`scripts/DirectionPromptOverlay.gd`) — bounds checked against `GameManager.get_region_bounds()` rather than the spec's viewport tile constants (27×21), which are viewport dimensions, not world map size; consistent with `DarknessOverlay`

---

### Fixed (scroll / spell bugs)

- **Learning a spell from a scroll posted two blank lines** (`autoloads/GameManager.gd`) — `_action_learn_spell` posted `MessageLog.post_blank()` on its success path, then `_action_consume` (the next action in the chain) posted another; removed the redundant blank from the success path; error paths that return `false` and stop the chain retain their blank because `consume` does not run in those cases
- **Resurrection scroll cast the resurrect effect instead of teaching the spell** (`data/objects/objects.json`) — `scroll_resurrect` used `cast_effect` / `resurrect` as its sole use action and had no `spell_id` field; changed to `"spell_id": "resurrect"` with `["learn_spell", "consume"]` use actions, matching the pattern of all other spell scrolls

---

## [Unreleased] — 2026-06-26

### Added (M22c — World Map Mouse Support)

- **`DarknessOverlay.is_tile_visible(tile)`** (`scripts/DarknessOverlay.gd`) — public method mirroring the per-tile visibility logic used by `_draw()`; returns `true` if the tile is within the player's Chebyshev vision radius AND in line of sight, or within any fixed light source's radius AND in LOS; used by hover tooltip to suppress info about unseen tiles
- **`_last_hovered_tile` field** (`autoloads/GameManager.gd`) — tracks the most recent tile the mouse hovered over; prevents redundant tooltip rebuilds on stationary mouse; reset to `Vector2i(-1,-1)` when hover is cleared or the tile is dark, forcing a recheck on the next frame so tooltips appear immediately when the player moves into range
- **`_update_map_hover()` / `_is_valid_map_tile()` / `_is_any_panel_open()`** (`autoloads/GameManager.gd`) — hover processing runs in `_process` each frame; `_is_valid_map_tile` checks tile against `terrain_layer.get_used_rect()` bounds; `_is_any_panel_open` checks all six panel references
- **`_on_map_clicked(mouse_position)`** (`autoloads/GameManager.gd`) — dispatches left-clicks from the SubViewportContainer; converts viewport pixel → world tile via `canvas_transform.affine_inverse()`; guards on combat, open panels, and player busy states; routes NPC tiles to `_on_npc_clicked`, player tile clears selection, other tiles start a mouse path
- **`_on_npc_clicked(player_node, npc)`** (`autoloads/GameManager.gd`) — two-click NPC interaction: first click highlights the NPC and sets `_selected_npc`; second click acts (hostile + adjacent → combat, hostile + far → path with `_attack_target_on_arrival`; friendly + adjacent → dialogue, friendly + far → path with `_talk_target_on_arrival`)
- **`_start_mouse_path_to_tile()` / `_compute_path()` / `_find_nearest_reachable()` / `_find_adjacent_to()`** (`autoloads/GameManager.gd`) — path helpers; `_compute_path` wraps `Pathfinder.find_path` with a 200-step limit; `_find_nearest_reachable` performs a Chebyshev ring search at radii 1–5 to find a passable fallback for impassable click targets; `_find_adjacent_to` finds the passable neighbour of an NPC tile closest to the player (Manhattan distance)
- **`_run_world_tests()`** (`autoloads/GameManager.gd`) — called deferred after `load_region` in debug builds; retrieves the live player node, runs `WorldMouseTest.run(player_node)`, teleports player to [10,10] after tests complete
- **`_on_map_gui_input(event)` in HUD** (`scripts/HUD.gd`) — connected to `SubViewportContainer.gui_input` in `_ready()`; forwards left mouse button presses to `GameManager._on_map_clicked(mb.position)` and calls `set_input_as_handled()`
- **`on_tile_hovered()` / `_build_tile_tooltip()`** (`scripts/TooltipManager.gd`) — `on_tile_hovered` builds tooltip content from a world tile and calls `on_item_hovered`; `_build_tile_tooltip` applies Look's three-tier priority: NPC > structural object > terrain; structural objects suppress terrain display; toggleable structural objects append their open/closed state using `look_is_open`/`look_is_closed` message keys; non-structural objects listed in description under terrain
- **`_tooltip_entry()` helper** (`scripts/TooltipManager.gd`) — returns a tooltip content dictionary with all required keys; consolidates the three return paths in `_build_tile_tooltip`
- **Mouse path state variables** (`scripts/Player.gd`) — `_mouse_path: Array[Vector2i]`, `_mouse_pathing: bool`, `_attack_target_on_arrival: Node`, `_talk_target_on_arrival: Node`, `_selected_npc: Node`
- **Mouse path stepping in `_process`** (`scripts/Player.gd`) — inserted before the keyboard movement block; when `_mouse_pathing` is true, checks dialogue/inventory/panel/moving/combat guards, pre-validates next tile passability (cancels on failure), calls `attempt_move`, advances the path when the tile is reached, calls `_finish_mouse_path` when empty
- **`start_mouse_path()` / `cancel_mouse_path()` / `set_selected_npc()` / `start_dialogue_with_npc()` / `_finish_mouse_path()`** (`scripts/Player.gd`) — public/private helpers; `cancel_mouse_path` clears path, targets, and selection without consuming the `ui_cancel` event; `set_selected_npc` applies/removes the gold highlight (`Color(1.5, 1.5, 0.4, 1.0)`) via `modulate`; `_finish_mouse_path` executes the deferred action (attack or dialogue) then clears state
- **Escape and keyboard cancel for mouse path** (`scripts/Player.gd`) — `ui_cancel` in `_unhandled_input` calls `cancel_mouse_path()` without `set_input_as_handled()` so Escape remains available to other handlers; any movement direction key also cancels the active mouse path
- **`WorldMouseTest`** (`scripts/debug/WorldMouseTest.gd`) — 14-test suite split into 5 pure static tests (tooltip position normal/flip-x/flip-y, hover timer reset, hover timer inactive) and 9 integration tests (cancel/start path state, target cleanup, escape/keyboard cancel, NPC select/clear, path to passable tile, impassable nearest-reachable fallback, player-tile tooltip empty, terrain tooltip name); static entry point called in `_ready()`, integration entry point called after region load

### Changed (M22c — World Map Mouse Support)

- **Tile coordinate calculation now accounts for camera transform** (`autoloads/GameManager.gd`) — both `_update_map_hover` and `_on_map_clicked` apply `sub_viewport.canvas_transform.affine_inverse()` to convert SubViewport pixel coordinates to world coordinates before dividing by `TILE_SIZE`; previously the raw pixel position was divided directly, causing all tile lookups to land near world origin regardless of camera position (tooltip always showed "Grass"; click-to-move diverged from actual target the further from spawn)
- **Click tile clamped to actual region bounds** (`autoloads/GameManager.gd`) — `_on_map_clicked` now clamps the computed tile to `get_region_bounds()` (from `terrain_layer.get_used_rect()`) rather than to `Constants.MAP_TILES_WIDE/TALL`; `MAP_TILES_WIDE = 27` and `MAP_TILES_TALL = 21` are viewport tile dimensions, not world map size; clamping to them prevented click-to-move from targeting the eastern and southern thirds of the Wilderness map (40 × 30 tiles)
- **`_on_map_clicked` uses SubViewport mouse position** (`autoloads/GameManager.gd`) — previously passed `mb.position` (SubViewportContainer local space); now reads `sub_viewport.get_mouse_position()` directly; when `SubViewportContainer.stretch = true` the container and viewport coordinate spaces differ under scaling
- **Tooltip respects Look priority** (`scripts/TooltipManager.gd`) — `_build_tile_tooltip` previously always showed terrain name as the header and appended all objects; rewritten to: return NPC display name if an NPC occupies the tile; return structural object name (with open/closed state) if one is present; fall through to terrain name + non-structural object description only when no NPC or structural object is found; matches the three-tier precedence of `_post_look_at` in `Player.gd`
- **Tooltip suppressed for tiles outside player vision** (`autoloads/GameManager.gd`) — `_update_map_hover` calls `darkness_overlay.is_tile_visible(tile)` before posting to `TooltipManager`; dark tiles clear the tooltip and reset `_last_hovered_tile` to force re-evaluation on the next frame; tiles the player cannot see show no information regardless of terrain or occupants
- **Mouse support added to main menu, class selection, stat allocation, and load game** (`scripts/MainMenu.gd`, `scripts/LoadGameScene.gd`):
  - Main menu option labels wired with `mouse_entered` (hover-to-highlight) and `gui_input` (click-to-activate); disabled Load Game option ignores both
  - Class list items wired with `mouse_entered` (hover-to-preview detail panel) and `gui_input` (click the already-hovered item to confirm; click a different item to preview only)
  - Stat allocation rows wired with `mouse_entered` (hover moves cursor) and `<`/`>` label click handlers (decrement/increment the stat for that row); a `[Confirm]` label added at the end of the stat list with hover-highlight and click-to-confirm; all rebuild calls from mouse handlers use `call_deferred` to avoid freeing a node during `gui_input` dispatch
  - Load game save rows wired with `gui_input` (click in BROWSING mode selects and opens the action menu; clicking a different row while action menu is open returns to BROWSING and re-selects); action menu labels wired with `mouse_entered` (hover highlights) and `gui_input` (click executes); action execution deferred via `call_deferred` to avoid freeing during dispatch

### Added (M22b — Panel Mouse Support)

- **`_is_any_panel_open()` helper** (`scripts/Player.gd`) — returns `true` if any of the six managed panels (journal, character, spellbook, save/load, shop, healer) is currently visible; checked in `_unhandled_input` and `_process` to suppress movement input while a panel is open
- **`_world_target_member: PartyMember`** (`autoloads/SpellManager.gd`) — stores the party member selected as the target of a world-context targeted spell; parallel to `_active_caster`; cleared automatically in `attempt_cast()` after effects execute or on early return
- **`spell_prompt_caster` / `spell_prompt_target` / `spell_member_cannot_cast` message keys** (`data/config/messages.json`) — `"Who casts {name}?"`, `"On whom?"`, and `"That party member cannot cast this spell."` respectively; control the text shown during the two-stage party-member selection flow for world-context spells
- **`custom_minimum_size = Vector2(180, 0)` on `Tooltip` root `PanelContainer`** (`scenes/ui/Tooltip.tscn`) — enforces a minimum width at the container level so the panel never collapses to zero width when only `NameLabel` is visible; previously `DescLabel` carried the minimum, which had no effect when it was hidden

### Changed (M22b — Panel Mouse Support)

- **`prompt_party_member` accepts optional label** (`scripts/Player.gd`) — new third parameter `prompt_label: String = "Who?"` replaces the hardcoded prefix; the posted message becomes `"{prompt_label}  1. Alice  2. Bob"`; all existing callers that omit the parameter retain the previous `"Who?"` behaviour
- **Caster and target prompts now show spell-specific text** (`autoloads/SpellManager.gd`) — `cast_spell()` passes `spell_prompt_caster` (e.g. `"Who casts Heal?"`) when prompting for the caster; `_do_cast_spell()` passes `spell_prompt_target` (`"On whom?"`) when prompting for the target
- **World targeted spells prompt for a target party member** (`autoloads/SpellManager.gd`) — `_do_cast_spell` for `targeting_type: "targeted"` in world context previously called `attempt_cast` immediately (self-cast only); now calls a second `prompt_party_member` when the party has more than one living member, sets `_world_target_member`, then calls `attempt_cast`; cancel clears `_active_caster` so resources are not left stranded
- **`SpellEffectExecutor._get_stat_block` / `_get_combatant_name` consult `_world_target_member`** (`scripts/SpellEffectExecutor.gd`) — when `node` is not an NPC and `SpellManager._world_target_member` is set, both helpers use that member's `stat_block` / `display_name` instead of falling through to `PlayerStats`; allows effects (heal, damage, etc.) to correctly target any living party member in world context
- **`NameLabel` autowrap removed** (`scenes/ui/Tooltip.tscn`) — `autowrap_mode = 3` on `NameLabel` caused item names to render as a vertical column of individual characters when the container had no minimum width; names are single-line and do not need wrapping
- **`Label.mouse_filter` set to `MOUSE_FILTER_PASS`** (`scripts/JournalPanel.gd`, `scripts/SpellbookPanel.gd`) — Godot 4 `Label` nodes default to `MOUSE_FILTER_IGNORE`, silently dropping all `gui_input` and `mouse_entered` signals; setting `MOUSE_FILTER_PASS` in `_rebuild_list()` restores click-to-select and hover-to-tooltip behaviour

### Fixed (M22b — Panel Mouse Support)

- **"Object is locked" crash on second click** (`scripts/InventoryScreen.gd`, `scripts/JournalPanel.gd`, `scripts/SpellbookPanel.gd`, `scripts/HealerPanel.gd`) — Godot locks a node during `gui_input` dispatch; calling `child.free()` synchronously inside the handler raises this error; all confirm/rebuild paths that free list children now use `call_deferred` to push the operation past the dispatch frame
- **Journal click not expanding quest details** (`scripts/JournalPanel.gd`) — root cause was `MOUSE_FILTER_IGNORE` on the row labels; see `mouse_filter` change above
- **SpellbookPanel hover tooltips not firing** (`scripts/SpellbookPanel.gd`) — same `MOUSE_FILTER_IGNORE` root cause; `mouse_entered` never fired; fixed alongside the click issue
- **Arrow keys moving player while panels are open** (`scripts/Player.gd`) — `_unhandled_input` previously only blocked movement for `_inventory_open`; the six other panels opened without setting that flag, so arrow keys simultaneously navigated the panel and moved the player; fixed by the `_is_any_panel_open()` guard in both `_unhandled_input` and `_process`
- **Casting a targeted spell in world context did nothing after caster selection** (`autoloads/SpellManager.gd`) — two separate causes: (1) selecting a companion who does not know the spell caused `can_cast` to fail silently; now posts `spell_member_cannot_cast`; (2) the subsequent `attempt_cast` always passed `target = null`, self-casting regardless of party size; resolved by the two-prompt target selection flow

---

## [Unreleased] — 2026-06-25

### Added (M22a — Scroll Wheel and Message Log)

- **`ScrollableList`** (`scripts/ScrollableList.gd`) — new `RefCounted` class managing windowed scroll state for any list: `_items`, `_scroll_offset`, `_visible_rows`, optional `_scrollbar_node`; methods: `setup`, `reset`, `set_items`, `scroll_up`, `scroll_down`, `scroll_to_index`, `scroll_to_bottom`, `get_visible_items`, `needs_scroll`, `update_scrollbar`; clamps offset on every mutation
- **Visual scrollbar in MessageLog** (`scripts/MessageLog.gd`) — programmatic `Control` + `ColorRect` thumb added as child of `$Clip`; anchored right, `MOUSE_FILTER_IGNORE`; hidden when content fits; thumb position and height computed from `ScrollableList.update_scrollbar()`
- **`message_log_max_lines`** (`data/config/game.json`) — configurable line cap (default 200) loaded by `MessageLog._load_config()`; lines beyond cap are dropped from the front
- **`cursor_path`** (`data/config/game.json`) — optional path to a custom cursor image; loaded in `GameManager._load_config()` and applied via `Input.set_custom_mouse_cursor()`; `null` disables custom cursor
- **`ScrollTest`** (`scripts/debug/ScrollTest.gd`) — 11-test suite for `ScrollableList`: covers `get_visible_items`, up/down clamping, `scroll_to_index` forward/backward, `scroll_to_bottom`, `needs_scroll` true/false, `reset`, `set_items` offset clamping, and visible-rows-exceed-items; runs via `ScrollTest.run()` which prints results to Godot console
- **`use_key_prompt` / `use_lockpick_prompt` removed in favour of `use_prompt`** — direction-requiring use actions now post the existing `"use_prompt"` ("Use - Direction?") message, matching the pattern used by attack, get, look, and other directional world actions

### Changed (M22a — Scroll Wheel and Message Log)

- **`MessageLog` rewritten to windowed rendering** (`scripts/MessageLog.gd`) — stores all lines in `_all_lines: Array[String]`; computes visible row count from panel height; rebuilds `VBoxContainer` children from `ScrollableList.get_visible_items()` on each change; scroll wheel (`MOUSE_BUTTON_WHEEL_UP/DOWN`) handled in `_gui_input`; `resized` signal triggers `_update_visible_rows`; `post()` always scrolls to bottom; `update_last()` replaces the final line in place
- **`JournalPanel` scroll-to-cursor** (`scripts/JournalPanel.gd`) — `_rebuild_list()` now calls `_scroll_to_cursor()` at the end; deferred `_do_scroll_to_cursor()` calls `Constants.scroll_list_to_row` on `$Panel/Content/QuestScroll`
- **`SpellbookPanel` scroll-to-cursor** (`scripts/SpellbookPanel.gd`) — same pattern as JournalPanel; scrolls `$Panel/Content/SpellScroll` to the selected spell row after each rebuild
- **`CharacterPanel` faction list uses `ScrollableList`** (`scripts/CharacterPanel.gd`) — replaced `_faction_scroll_offset: int` and `_faction_visible_rows: int` with `var _faction_scroll: ScrollableList`; `_open()` calls `setup(8)` and `reset()`; wheel events in `_unhandled_input` call `scroll_up/down` on the list; `_build_faction_section()` uses `set_items` / `get_visible_items`
- **`ScrollTest.run()` called at startup in debug builds** (`autoloads/GameManager.gd`) — added at end of `_ready()` under `if OS.is_debug_build()`; output goes to Godot console via `print()`

### Fixed (Inventory use — direction-prompt items)

- **Lockpick use no longer shows "cannot equip" message** (`autoloads/GameManager.gd`) — `_action_use_lockpick` was checking the class equipment whitelist for type `"lockpick"`, which is never present; the erroneous class restriction block is removed; all classes can now attempt to use lockpicks
- **Treasury key direction prompt now resolves** (`scripts/Player.gd`, `scripts/InventoryScreen.gd`) — `_action_use_key` and `_action_use_lockpick` call `actor.prompt_direction()`, but Player's `_unhandled_input` returned early at `if _inventory_open: return` before reaching the `_awaiting_prompt` handler; `prompt_direction()` now closes the inventory immediately when open so the prompt can receive input; `InventoryScreen._on_use()` skips `_rebuild_keep_cursor` if the panel was closed during `execute_use`
- **Direction-requiring use actions post `use_prompt`** (`autoloads/GameManager.gd`) — `_action_use_key` and `_action_use_lockpick` now post `"Use - Direction?"` before calling `prompt_direction`, matching the pattern of all other directional world actions

---

## [Unreleased] — 2026-06-25

### Added (Rest Interrupt — D-02)

- **`rest_interrupt_base_chance`** (`data/config/time.json`) — base probability (0.1) that a rest is interrupted per in-game hour; loaded by `GameTime._load_config()` and exposed via `GameTime.get_rest_interrupt_base_chance()`
- **`rest_interrupt_check_interval`** (`data/config/time.json`) — documents the check cadence ("hourly"); read by future callers that need to know the scheduling contract
- **`rest_interrupt_multiplier`** on every tile type (`data/config/tiles.json`) — scales the per-hour interrupt chance by terrain difficulty: grass/dirt/water 1.0×, hill 1.2×, mountain 1.3×, forest 1.5×, swamp 2.0×, lava 3.0×
- **`rest_interrupted_combat`** message key (`data/config/messages.json`) — "Enemies attack while you sleep!"
- **`SpawnManager.spawn_for_rest_interrupt() -> Array`** (`scripts/SpawnManager.gd`) — picks a weighted NPC from the region's spawn config using the existing `_pick_spawn_npc_id()` and returns `[{"npc_id": npc_id}]`; returns empty if no spawn config is loaded
- **`CombatManager.initiate_combat_with_group(group: Array, _player_initiated: bool)`** (`autoloads/CombatManager.gd`) — initiates combat from a pre-built group array of `{npc_id}` dicts; resolves group members per entry via `_resolve_group_members`; selects a random entry edge (north/south/east/west); posts `combat_begins`; guards on empty group and already-in-combat state; leaves `_pre_combat_source_npc_id` empty so `end_combat` does not attempt to find a world NPC to remove

### Changed (Rest Interrupt — D-02)

- **Rest loop restructured to hourly interrupt checks** (`scripts/Player.gd`) — `_process` now decrements `_rest_ticks_this_hour` in parallel with `_rest_ticks_remaining`; when the hourly counter reaches zero `_on_rest_hour_advanced()` fires and the counter resets to `hours_to_ticks(1)`; the previous per-tick `_check_rest_interrupt()` call is removed; three new `Player` vars added: `_rest_ticks_this_hour: int`, `_rest_interrupt_base_chance: float`, `_rest_interrupt_tile_mults: Dictionary`
- **`_begin_rest()` caches interrupt config** (`scripts/Player.gd`) — on rest start, reads `GameTime.get_rest_interrupt_base_chance()` into `_rest_interrupt_base_chance` and calls `_load_tile_interrupt_mults()` to build a `tile_id → multiplier` dict from `tiles.json`; avoids repeated file reads during the rest loop
- **`_check_rest_interrupt() -> bool`** (`scripts/Player.gd`) — stub (`pass`) replaced with full implementation: looks up the current tile's multiplier, rolls `randf()` against `base_chance × tile_mult`, calls `interrupt_rest()` and posts `rest_interrupted_combat` on a hit, spawns a group via `SpawnManager`, initiates combat via `CombatManager.initiate_combat_with_group`, and returns whether the interrupt fired; signature changed from `-> void` to `-> bool`
- **`_on_rest_hour_advanced()` added** (`scripts/Player.gd`) — thin wrapper that calls `_check_rest_interrupt()` and returns immediately if the interrupt fires; entry point for any future per-hour rest logic
- **`_load_tile_interrupt_mults() -> Dictionary` added** (`scripts/Player.gd`) — reads `tiles.json` via `Constants.load_json`, iterates the `tiles` array, and returns a dict keyed by tile id; called once per rest session in `_begin_rest`

---

## [Unreleased] — 2026-06-25

### Added (Full Codebase Audit)

- **`level_thresholds` array** (`data/config/game.json`) — XP thresholds for each level; required by `LevelManager.check_level_up()`; previously missing, causing level-up detection to silently fail with an empty threshold list
- **`Constants.token_start` / `Constants.token_end`** (`autoloads/Constants.gd`) — single-source constants for the `{` / `}` delimiters used in `MessageRegistry.get_message()` template substitution; all hardcoded occurrences across `MessageRegistry.gd` updated to use them
- **`Constants.CONFIRM_KEYS`** (`autoloads/Constants.gd`) — array `[KEY_ENTER, KEY_KP_ENTER]` replacing inline comparisons in dialogue and prompt input handlers
- **`Constants.sell_multiplier`** (`autoloads/Constants.gd`) — `0.5` float constant replacing the hardcoded literal in `ShopManager.get_sell_price()`

### Changed (Full Codebase Audit)

- **StatBlock modifier registry lookups cached** (`scripts/StatBlock.gd`) — `get_value()` and `get_max()` previously called `ModifierRegistry.get_modifier(id)` on every frame for every active modifier; results now cached in a static `Dictionary` keyed by modifier id, populated on first lookup per session; eliminates repeated JSON parsing in stat-heavy per-tick calls (P-01)
- **SpellEffectExecutor tracks GameTime handles for timed status effects** (`scripts/SpellEffectExecutor.gd`) — `_effect_charm`, `_effect_sleep`, and `_effect_paralyze` now store the `GameTime.schedule` handle returned when applying a timed modifier; the handle is cancelled via `GameTime.cancel()` when the effect is overwritten or the combatant dies; prevents ghost tick callbacks from firing on freed nodes after combat ends (SL-01 / M-01)
- **`SpellEffectExecutor` modifier_id defaults** (`scripts/SpellEffectExecutor.gd`) — `_effect_reveal` / `_effect_obscure` / `_effect_invisibility` / `_effect_poison` each fell back on an empty `modifier_id` when the field was absent from the spell definition; each now has a named default (`spell_reveal_vision`, `spell_obscure_vision`, `spell_invisibility`, `spell_poison`) matching the modifier registry entries (H-05)
- **Key repeat delays read from `game.json`** (`autoloads/GameManager.gd`) — `key_initial_delay` and `key_repeat_interval` fields loaded from config on startup; `Player.INITIAL_DELAY` and `Player.REPEAT_INTERVAL` set from `GameManager` in `_ready()` rather than hardcoded (H-09)

### Fixed (Full Codebase Audit)

- **Unused variable warning in `SaveManager._migrate_save_data()`** (`autoloads/SaveManager.gd`) — `var from_version: int` was declared but never read; renamed to `_from_version` to suppress the warning without removing the variable (which documents intent)

### Removed (Full Codebase Audit)

- **`QuestManager._get_callback_for_label()`** (`autoloads/QuestManager.gd`) — dead method with no callers; removed (D-01)
- **Legacy save format blocks in `SaveManager`** (`autoloads/SaveManager.gd`) — compatibility shims for pre-SAVE_VERSION data formats removed from `_migrate_save_data()`; migration now only handles the current version bump path (D-03)
- **`ClassRegistry.get_weapon_whitelist()` deprecation warning** (`scripts/ClassRegistry.gd`) — `push_error` emitted whenever a class definition contained the removed `weapon_whitelist` key; class definitions no longer carry the key and the guard is deleted (D-04)
- **F10 / F11 / F12 debug hotkeys** (`scripts/Player.gd`) — inline debug triggers for quest start, objective completion, and class change removed; no replacement (H-08)

---

## [Unreleased] — 2026-06-24

### Added (M21d — Quest-Triggered NPC Spawning)

- **`spawn_effects` block in quest definitions** (`data/quests/quests.json`) — array on any quest specifying NPC spawns triggered by quest events; each effect carries `trigger_event` (`quest_started`, `objective_complete`, `quest_complete`, `quest_failed`), optional `trigger_objective_id`, `npc_id`, `region_id`, `location_type` (`fixed`, `waypoint`, or `random`), `location` (tile array, waypoint name, or omitted), and a unique `instance_id`; `test_quest_01` gains an effect that places `bandit_leader` at the `bandit_camp` waypoint on quest start
- **`_emit_spawn_effects()` helper** (`autoloads/QuestManager.gd`) — called from `start_quest`, `complete_objective`, `_check_quest_completion`, and `fail_quest`; iterates the quest definition's `spawn_effects` array and emits `quest_spawn_triggered(effect)` for each entry matching the current event and objective; signal connected to `SpawnManager.handle_quest_spawn` at startup in `GameManager._ready`
- **Quest spawn lifecycle in `SpawnManager`** (`scripts/SpawnManager.gd`) — `handle_quest_spawn(effect)` is idempotent (no-op if `instance_id` already active); immediately calls `execute_quest_spawn` if `region_id` matches the current region, otherwise queues into `_pending_quest_spawns`; `execute_quest_spawn` resolves the tile by `location_type` (`fixed` → index array, `waypoint` → `WaypointManager.get_waypoint` with silent random fallback when the manager is unavailable, default → `_pick_random_passable_tile` scanning full region bounds), instantiates the NPC with `is_quest_spawn = true` and `quest_spawn_instance_id` set before `add_child`, sets `availability = "hostile"`, and registers in `_quest_spawns`; `execute_pending_for_region(region_id)` partitions the pending list and executes matching entries; `on_region_exit` nulls `npc_node` refs for the exiting region without clearing metadata; `on_quest_spawn_killed(instance_id)` erases the entry; `reregister_quest_spawn` re-links node refs after cache restore; `get_serializable_quest_spawns` and `restore_quest_spawns` handle save/load, converting active entries to pending with `location_type: "fixed"` on restore
- **`is_quest_spawn` and `quest_spawn_instance_id` fields on NPC** (`scripts/NPC.gd`) — set before `add_child`; `die()` calls `GameManager.notify_quest_spawn_killed(quest_spawn_instance_id)` when `is_quest_spawn` is true
- **`SpawnManager` made persistent** (`autoloads/GameManager.gd`) — field initialised at declaration; `_setup_spawn_manager(region_id)` calls `load_config()` on the existing instance rather than creating/destroying; `_snapshot_and_unload` and `_clear_region` call `spawn_manager.on_region_exit(_current_region_id)` instead of `clear_all_spawns`; `load_region` phase 2 calls `spawn_manager.execute_pending_for_region(region_id)` after setup; `_restore_from_cache` re-links quest spawn NPCs via `reregister_quest_spawn`; `_snapshot_region` includes `is_quest_spawn` and `quest_spawn_instance_id` in NPC snapshot entries; `notify_quest_spawn_killed(instance_id)` added
- **Quest spawn save/load** (`autoloads/SaveManager.gd`) — `quest_spawns` key in save file; `_serialize_quest_spawns()` delegates to `SpawnManager.get_serializable_quest_spawns()`; `_deserialize_quest_spawns()` delegates to `SpawnManager.restore_quest_spawns()`; `_reset_all_state()` calls `spawn_manager.clear_all_spawns()`
- **`bandit_leader.json` updated** (`data/npcs/bandit_leader.json`) — factions, `on_death_faction_changes`, stat overrides, `pursuit_ticks`, and combat priority list added; static placement in `wilderness.json` removed (replaced by quest spawn)
- **`bandit_camp` waypoint** (`data/regions/wilderness.json`) — waypoint at [15, 21]; static `bandit_leader` NPC entry removed

---

## [Unreleased] — 2026-06-24

### Added (M21c — Random Monster Spawning)

- **`SpawnManager`** (`scripts/SpawnManager.gd`) — `RefCounted`; one instance per active region, owned by `GameManager.spawn_manager`; `load_config(config)` reads `spawn_rate_ticks`, `max_spawns`, and `spawn_list` from the region's `spawn_config` dict and schedules a repeating timer via `GameTime.schedule`; `attempt_spawn()` filters freed nodes, enforces the cap, picks an NPC id by weighted random, picks a valid perimeter tile, and instantiates the NPC scene with `is_spawned_monster = true` before `add_child()`; `clear_all_spawns()` frees all tracked nodes, clears occupants, and cancels the timer; `on_spawn_killed(node)` removes a node from `_active_spawns`; `get_active_spawn_count()` returns the live-instance count; `_pick_spawn_npc_id()` builds a cumulative weight array and picks via `randf()`; `_pick_spawn_tile()` generates all viewport-perimeter candidates (top/bottom rows + left/right interior columns), shuffles them, and returns the first passable non-player tile inside region bounds
- **`is_spawned_monster` and `_last_known_player_tile` fields** (`scripts/NPC.gd`) — `is_spawned_monster: bool` set before `add_child()` so `_ready()` does not override it; `_last_known_player_tile` retains the last observed player position across pursuit ticks
- **Spawned-monster tick behavior** (`scripts/NPC.gd`) — `_on_tick_advanced` routes to `_spawned_monster_tick()` when `is_spawned_monster` is set; each tick: checks combat initiation, tests `_tile_in_viewport` + `LineOfSight.has_line_of_sight`; if both true, enters/refreshes pursuit and moves toward the player; if pursuing without LOS, decrements `_pursuit_ticks_remaining` and moves toward `_last_known_player_tile` until timeout; otherwise random-walks; `_move_toward_tile` uses `Pathfinder.find_path`; `_random_walk` shuffles four cardinal directions and takes the first passable step; `_get_tilemap()` retrieves the region's `TerrainLayer`
- **`GameManager` spawn integration** (`autoloads/GameManager.gd`) — `spawn_manager: SpawnManager` field; `_setup_spawn_manager(region_id)` loads the region JSON, reads `spawn_config`, and instantiates a `SpawnManager` if the config is non-empty; called during region-load phase 2 between `_register_fixed_light_sources()` and `_place_player_at_spawn()`; `_snapshot_and_unload()` and `_clear_region()` both call `spawn_manager.clear_all_spawns()` at the top before any other teardown; `_snapshot_region()` skips NPCs with `is_spawned_monster = true` so monsters do not persist across region transitions; `notify_spawn_killed(npc_node)` delegates to `spawn_manager.on_spawn_killed()`
- **`spawn_config` in wilderness** (`data/regions/wilderness.json`) — `spawn_rate_ticks: 200`, `max_spawns: 3`, `spawn_list`: `goblin_grunt` weight 3, `goblin_chief` weight 1
- **`pursuit_ticks: 20`** (`data/npcs/goblin_grunt.json`, `data/npcs/goblin_chief.json`) — raised from 0 so spawned goblins sustain pursuit for 20 ticks after losing LOS
- **SpawnTest** (`scripts/debug/SpawnTest.gd`) — 19 assertions across 12 tests: spawn_config_loads (3), spawn_cap_enforced (1), weighted_selection (2), spawn_tile_on_perimeter (1), random_walk_behavior (1), pursuit_trigger (1), pursuit_timeout (1), pursuit_timeout_reset (2), cap_freed_on_kill (2), despawn_on_region_exit (1), corpse_on_spawned_death (2), combat_initiation (2); wired into `GameManager._run_tests()`

### Fixed (M21c — Random Monster Spawning)

- **Open doors blocking line of sight** (`scripts/LineOfSight.gd`) — `has_line_of_sight` previously used `WorldState.get_objects_at()` which returns string IDs and has no runtime state; switched to `GameManager.get_objects_at()` which returns live `WorldObject` nodes; toggleable objects (`wo.toggleable and wo.is_open`) are now skipped in the LOS check so open doors and portcullises are treated as transparent
- **Darkness overlay not updating after door use** (`scripts/DarknessOverlay.gd`) — overlay previously only set `_needs_redraw` when the player's tile changed; connected to `GameTime.tick_advanced` so any world-state change that consumes a tick (e.g. opening a door) triggers an immediate redraw; correct sequence: tick fires → `_needs_redraw = true` → door `is_open` flips → `_process` queues redraw → `_draw` reflects the new open state

---

## [Unreleased] — 2026-06-24

### Added (M21b — Terrain Hazards and Traps)

- **Tile hazards** (`data/config/tiles.json`) — `hazards` array added to swamp and new lava tile definitions; each hazard entry specifies `trigger` (`on_entry` | `continuous`), `type` (`damage` | `apply_status`), and an optional `immunity_id`; swamp applies `hazard_poison` status on entry; lava deals 5 HP damage each continuous tick
- **`hazard_poison` modifier** (`data/modifiers/modifiers.json`) — detrimental status effect; `hp −2`, `exclusive_per_source` stacking, 3 ticks per application, 30-tick max lifetime; `is_status_effect: true`, `is_detrimental: true`
- **`hazard_immunity` and `trigger_on_entry` object defaults** (`data/config/object_defaults.json`) — `hazard_immunity: []` lists immunity ids granted by an equipped item; `trigger_on_entry: false` marks a WorldObject as a once-on-entry trap
- **`HazardProcessor`** (`scripts/HazardProcessor.gd`) — `RefCounted`; `process_tile_entry(entity, tile)` fires `on_entry` tile hazards and any trap objects on the tile; `process_tile_tick(entity, tile)` fires `continuous` tile hazards; checks `_is_immune(entity, immunity_id)` against all equipped items' `hazard_immunity` arrays before applying an effect; `_has_status_effect_active(entity, modifier_id)` prevents double-application of status hazards; trap objects execute each `use_action` via its own `UseContext` (`damage_target` targets the entity, `consume` targets the WorldObject)
- **`TileRegistry` hazard storage and accessor** (`scripts/TileRegistry.gd`) — `hazards` array stored per tile entry alongside existing fields; `get_hazards(tile_id) -> Array` public accessor
- **`damage_target` use action** (`autoloads/GameManager.gd`) — registered at startup; reads `damage` from params; calls `modify_stat("hp", -damage)` on `context.target`
- **Hazard wiring on the world map** (`autoloads/GameManager.gd`) — `hazard_processor` field and `_hazard_last_player_tile` tracking added to `_on_world_tick`; tile change fires `process_tile_entry` for all living party members; same-tile fires `process_tile_tick`; skipped during combat
- **Hazard wiring in combat arena** (`scripts/CombatArena.gd`) — `process_tile_entry` called after every `_move_active_combatant_to`
- **Hazard wiring in combat turn advance** (`scripts/CombatManager.gd`) — `process_tile_tick` called for the active combatant after each `await` in `_advance_turn` (living, non-fled combatants only)
- **`swamp_boots`** (`data/objects/objects.json`) — light_armor; equip slot: feet; `hazard_immunity: ["swamp"]`; applies `boots_leather_dex` modifier; `base_price: 40`; placed in wilderness at [7, 7]
- **`spike_trap`** (`data/objects/objects.json`) — structural; `trigger_on_entry: true`; `use_actions`: `damage_target` (10 damage) then `consume` (self-destructs on trigger); placed in wilderness at [8, 8]
- **3 hazard messages** (`data/config/messages.json`) — `hazard_poison_applied`, `hazard_lava_damage`, `trap_triggered`
- **HazardTest** (`scripts/debug/HazardTest.gd`) — 20 assertions across 9 tests: lava hazard in tile registry (4), swamp hazard in tile registry (4), swamp_boots immunity data (2), spike_trap trigger_on_entry and use_actions (4), damage_target registered (1), damage_target reduces HP (1), lava damage reduces HP (1), status not reapplied when active (2), no immunity without equipped item (1); wired into `GameManager._run_tests()`

### Fixed (M21b — Terrain Hazards and Traps)

- **Player spawn location after test suite** (`autoloads/GameManager.gd`) — `_run_tests()` teleports the player to [10, 10] after all suites complete so the player lands on a passable tile for manual testing; previously the player remained at [0, 0] due to deferred test timing

### Fixed (Darkness Overlay — M21a follow-up)

- **LOS shadows absent at full daylight** (`scripts/DarknessOverlay.gd`) — removed `if _player_vision_radius >= _max_vision_radius: return` early return from `_draw()`; at max vision (radius 27, inner zone 26) all in-range tiles render at opacity 0 unless blocked by LOS, so wall shadows apply at any time of day; `_max_vision_radius` field and its `_ready()` initialization removed as no longer used
- **Fixed light sources illuminating tiles outside player LOS** (`scripts/DarknessOverlay.gd`) — torches and sconces now only brighten tiles the player has direct LOS to; `player_los` bool computed once per tile and gates the fixed-source illumination path, preventing partially-lit tiles from appearing in dark areas around corners
- **Falloff zone narrowed from 2 tiles to 1** (`scripts/DarknessOverlay.gd`) — `_opacity_at` inner zone changed from `radius − 2.0` to `radius − 1.0`; for integer Chebyshev distances this produces binary visible/dark results, eliminating erratic partial-opacity tiles at vision boundaries near walls and windows

### Changed (Darkness Overlay tests — M21a follow-up)

- **`_test_skip_at_max_radius` replaced with `_test_full_day_inner_zone`** (`scripts/DarknessOverlayTest.gd`) — new test validates that `_opacity_at` returns 0.0 for center and inner-boundary tiles at max radius, confirming the overlay renders correctly at full daylight instead of bailing out early
- **`_test_opacity_falloff` updated** (`scripts/DarknessOverlayTest.gd`) — falloff midpoint now tested at `dist=4.5, radius=5` (→ 0.5) and boundary at `dist=4.0, radius=5` (→ 0.0), reflecting the narrowed 1-tile falloff zone

---

## [Unreleased] — 2026-06-24

### Changed (M21a — Darkness Overlay Refactor)

- **`DarknessOverlay._draw()` rewritten** (`scripts/DarknessOverlay.gd`) — now uses Chebyshev distance for per-tile radius culling (replacing Euclidean); tiles within radius are then tested with `LineOfSight.has_line_of_sight()` before computing opacity; tiles with blocked LOS are rendered fully dark regardless of distance; fixed light sources use the same Chebyshev + LOS pass against the source tile
- **Underground region support** (`autoloads/GameManager.gd`) — `_apply_underground_state(is_underground)` called at the end of both `_fresh_load_region` and `_restore_from_cache`; on entering an underground region: ambient suppressed, vision_radius set to 1 via an `exclusive_per_source` modifier tagged `UNDERGROUND_LIGHT_SOURCE_TAG`; on exit: underground modifier removed, ambient re-evaluated; no-op when the underground flag is unchanged
- **`GameTime.suppress_ambient()` / `unsuppress_ambient()`** (`autoloads/GameTime.gd`) — `suppress_ambient` sets `_ambient_suppressed`, removes the ambient modifier immediately; `unsuppress_ambient` clears the flag and calls `_on_half_hour_ambient()` to restore the time-of-day modifier; `_on_half_hour_ambient` is a no-op while suppressed
- **`is_underground` field** (`data/regions/wilderness.json`, `data/regions/town.json`) — added to all region JSON files; `false` for surface regions; underground regions use `true` to trigger the suppressed-ambient / min-vision path on load
- **`UNDERGROUND_LIGHT_SOURCE_TAG`** (`autoloads/Constants.gd`) — new constant `"underground_light"` used as the source tag for the underground vision modifier

### Added (M21a — Darkness Overlay Refactor)

- **`window` object** (`data/objects/objects.json`) — structural, `passable: false`, `transparent: true`; blocks movement but allows line-of-sight through it
- **LOS test enclosure in wilderness** (`data/regions/wilderness.json`) — four objects added: `wall_stone` at [17,11], [17,12], [17,14] (instance ids `los_wall_01–03`) and `window` at [17,13] (`los_window_01`); used by the test suite to verify wall-blocked and window-transparent LOS from the player spawn at [5,5]
- **DarknessOverlayTest** (`scripts/DarknessOverlayTest.gd`) — 17 assertions across 10 tests: `_opacity_at` inner zone (2 assertions), `_opacity_at` at and beyond radius (2), `_opacity_at` falloff midpoint, Chebyshev diagonal-in-radius, Chebyshev outside-radius, skip-draw condition at max vision (2), LOS blocked by wall at [17,11], LOS clear through window at [17,13], underground modifier clamps vision_radius to 1 and is reversible (2), suppress/unsuppress ambient restores vision_radius (2); wired into `GameManager.on_hud_ready()` via `call_deferred`

---

## [Unreleased] — 2026-06-24

### Added (M20 — Faction System)

- **`FactionManager` autoload** (`autoloads/FactionManager.gd`) — owns faction definitions, NPC membership, and standing values; loaded from `data/config/factions.json`; 0–100 standing scale with five named tiers (Hostile 0–20, Unfriendly 21–40, Neutral 41–60, Friendly 61–80, Exalted 81–100); `get_standing` / `set_standing` / `modify_standing` with clamp; `set_standing` emits `standing_changed(faction_id, old, new)`; `get_tier` / `get_tier_name` / `get_faction_name` / `is_hostile` / `get_factions_for_npc`; `get_modified_factions()` returns factions with non-default standing sorted alphabetically; `get_serializable_standings` / `restore_standings` for save support; registered in `project.godot` after `PartyManager`
- **`data/config/factions.json`** — standing scale and tier definitions with `price_multiplier` per tier (Hostile 2.0 / Unfriendly 1.5 / Neutral 1.0 / Friendly 0.8 / Exalted 0.6); two factions: `merchants` (Merchants Guild, default 50) and `bandits` (Bandits, default 20)
- **`FACTIONS_CONFIG_PATH` constant** (`autoloads/Constants.gd`)
- **`factions` and `on_death_faction_changes` fields** on all NPC definitions — `innkeeper_01` and `armorer_01` in `merchants`; `goblin_grunt`, `goblin_chief`, and `goblin_shaman` in `bandits`; all others carry empty arrays
- **Faction save / load** (`autoloads/SaveManager.gd`) — `faction_standings` serialized into save; `_reset_all_state` calls `FactionManager.initialize_standings()`; `_deserialize_faction_standings` restores standings silently
- **Dialogue keyword gating** (`scripts/DialogueManager.gd`) — `min_standing` entry on a keyword returns `alternate_response` (or `dialogue_faction_gated` fallback) and fires no hooks when threshold not met
- **`currency_cost` dialogue hook** (`scripts/DialogueManager.gd`) — dict with `amount` and `response_insufficient`; checked after `min_standing` gate; deducts gold on success, returns refusal response if insufficient; hook execution order: flag_require → flag_set/flag_clear → `meets_min_standing` → `currency_cost` → quest triggers/delivery → `faction_changes` → return response
- **`faction_changes` on dialogue keywords** — array of `{faction_id, amount}` entries applied via `FactionManager.modify_standing` after delivery check
- **Shop faction pricing** — shops carry `faction_id`; `ShopManager.get_buy_price` applies tier `price_multiplier` as a second `ceili` pass after the shop multiplier; sell price unaffected; `general_store` and `armory` affiliated with `merchants`
- **NPC hostility on tier crossing** (`autoloads/GameManager.gd`) — `_on_standing_changed` iterates current-region Actors; NPCs in the faction set `availability = "hostile"` on entering the Hostile tier; recover to `"default"` and re-evaluate schedule on exit; no-op on same-tier change
- **`availability = "hostile"` combat path** (`scripts/NPC.gd`) — `_check_combat_initiation` triggers combat for `availability == "hostile"` in addition to `hostile == true`
- **On-death faction changes** (`autoloads/QuestManager.gd`) — `_on_npc_died` applies `on_death_faction_changes` entries after quest logic; `goblin_grunt` bandits −2; `goblin_chief` bandits −5
- **`faction_change` quest reward type** (`autoloads/QuestManager.gd`) — `_apply_reward_faction_change` modifies standing and posts `faction_standing_changed` message
- **`modify_faction_standing` use action** (`autoloads/GameManager.gd`) — registered at startup; reads `faction_id` and `amount` from params; posts `faction_standing_changed` message
- **`merchant_token` item** (`data/objects/objects.json`) — use actions: `modify_faction_standing` merchants +5 then `consume`; placed in wilderness at [5, 3]
- **`donate` keyword on `innkeeper_01`** — `currency_cost` 50 gold; on success applies merchants +10
- **`faction_change` reward on `return_ledger` quest branch** (`data/quests/quests.json`) — merchants +15
- **Faction UI** (`scripts/CharacterPanel.gd`, `scenes/ui/CharacterPanel.tscn`) — Standing section below stats in character panel right column; lists factions with non-default standing sorted alphabetically; faction name left-justified, tier name right-justified coloured by tier (Hostile #8B0000 → Exalted #00CC00); scrollable with Up/Down; updates live via `standing_changed` while panel is open; `TIER_COLORS` constant dict in `CharacterPanel`
- **Character panel stat layout** (`scripts/CharacterPanel.gd`) — stats reformatted to two columns; row 1: name | class; row 2: level | experience; remaining visible stats paired left-justified / right-justified per column; stat names read from stat block definition, not hardcoded
- **3 new messages** (`data/config/messages.json`) — `dialogue_faction_gated`, `faction_standing_changed`, `faction_donation_received`

### Fixed

- **`bool()` constructor error** (`autoloads/QuestManager.gd`) — replaced all `bool(dict.get(...))` calls with direct expressions; `bool()` is not a valid constructor in Godot 4.3 GDScript at runtime
- **Stat reward id** (`data/quests/quests.json`) — corrected `"strength"` to `"str"` in `return_ledger` branch stat reward
- **Level-up skips gracefully when class not yet set** (`scripts/CombatManager.gd`) — removed spurious `push_error` from `_apply_level_up` when `current_class_id` is empty; condition is expected during early load order and already handled by `continue`

---

## [Unreleased] — 2026-06-21

### Added

- **Cross-member inventory** — inventory screen now supports switching between party members with Left/Right (`move_left`/`move_right`); title label updates to show the current member's name; weight bar reflects the viewed member's carry limit and inventory weight; pressing `M` with a multi-member party starts a cross-member move flow instead of the old within-inventory container move
- **Cross-member move flow** (`scripts/InventoryScreen.gd`) — equipped items are rejected with a message; stacked items prompt for quantity (same `inventory_quantity_label` format); after quantity entry the screen enters target-member mode showing the target's top-level inventory and containers; Left/Right cycles through other party members as target; Enter confirms; Escape cancels and returns to the source member; on success the screen stays on the target member's view
- **Carry limit and container enforcement** — `_confirm_member_move()` checks that the target member's total inventory weight plus the transfer weight does not exceed their `carry_limit` (`str * 5`); container transfers additionally check slot count and per-container weight limit before any items are removed from source; blocked transfers post a message and return to source member without modifying either inventory
- **`carry_limit` stat on NPC default** (`data/stats/npc_default.json`) — derived stat `str * 5`, same formula as the player, so all party companions have a functioning carry limit
- **`class_name InventoryScreen`** (`scripts/InventoryScreen.gd`) — added so the class is accessible by name; `_ui_initialized` flag set in `_ready()` guards all UI-node writes so the class can be instantiated headlessly in tests
- **4 new messages** (`data/config/messages.json`) — `inventory_move_unequip_first`, `inventory_move_select_target`, `inventory_move_carry_limit`, `inventory_move_complete`

### Changed

- **`move_left` / `move_right` replace `ui_left` / `ui_right` in normal inventory mode** — container expand/collapse removed; Left/Right now cycles the viewed party member; within-inventory container moves still reachable via `M` key when party size is 1

---

## [Unreleased] — 2026-06-21

### Added

- **Party order management** — player presses O (world only) to view and reassign party member order; current order is posted as a numbered list, player enters new order as space-separated numbers, Enter confirms, Escape cancels; invalid input (wrong count, out-of-range index, duplicates) re-prompts; single-member party posts an informational message with no prompt; O is disabled during combat
- **`party_order` input action** (`project.godot`) — bound to O
- **`Player.prompt_party_order()`** (`scripts/Player.gd`) — posts numbered current order and a prompt line; awaits space-separated numeric input; `_confirm_party_order()` validates count, range, and uniqueness, re-prompts on failure, calls callback with a typed `Array[int]` on success; `_cancel_party_order()` clears state and fires the cancel callable; `class_name Player` added to expose the class to the test suite
- **`GameManager` O handler** (`autoloads/GameManager.gd`) — on `party_order` action: retrieves Player node, calls `prompt_party_order`; callback maps 1-based indices to member IDs, calls `PartyManager.set_order()`, posts `party_order_confirmed`; cancel callback posts `party_order_cancelled`
- **`PartyManager.order_changed` signal** (`autoloads/PartyManager.gd`) — emitted at the end of `set_order()`; used by PartySidebar to refresh display order without requiring a game tick
- **PartySidebar order refresh** (`scripts/PartySidebar.gd`) — connected `PartyManager.order_changed` to `_refresh` so the sidebar row order updates immediately after reorder
- **5 new messages** (`data/config/messages.json`) — `party_order_single`, `party_order_prompt`, `party_order_invalid`, `party_order_confirmed`, `party_order_cancelled`
- **PartyOrderTest** (`scripts/debug/PartyOrderTest.gd`) — 20 assertions across 10 tests: single-member no-prompt, valid 3-member reorder, invalid wrong count, invalid out-of-range, invalid duplicates, cancel, disabled-in-combat guard, sidebar row order after reorder, character panel index 0 after reorder, combat formation member order after reorder; wired into `GameManager.on_hud_ready()`

### Fixed

- **ResurrectionTest unused variable** (`scripts/debug/ResurrectionTest.gd`) — removed dead `sb` / `player_sb` declarations in `_test_remove_all_status_effects`
- **`cast_effect` inner executor shadow** (`autoloads/GameManager.gd`) — renamed inner `exec` to `res_exec` in the resurrect branch of `_action_cast_effect` to eliminate the GDScript variable-shadow warning

---

## [Unreleased] — 2026-06-20

### Added

- **Resurrection mechanic** — downed party members can be returned to life with 1 HP via spell, item, doodad, or healer NPC; cleared of all status effects on revival
- **`resurrect` spell** (`data/config/spells.json`) — targeted spell; costs 20 mana; requires mandrake_root + garlic reagents; works in any context (world and combat); effects array contains a single `resurrect` effect
- **`resurrect` effect handler** (`scripts/SpellEffectExecutor.gd`) — in combat, finds the downed combatant whose `node == target` or `current_tile == target_tile`, sets `is_downed = false`, restores HP to 1, calls `remove_all_status_effects()`, syncs the linked `PartyMember`; in world, reads `SpellManager._resurrect_target` (set by caller), applies the same restoration sequence
- **Downed guard on combat effects** (`scripts/SpellEffectExecutor.gd`) — `_is_combatant_downed(target)` helper checks `CombatManager.in_combat` and scans `_turn_order` for a matching downed combatant; early-return guard added to `_effect_damage`, `_effect_heal`, `_effect_apply_modifier`, `_effect_dispel`, `_effect_poison`, `_effect_paralyze` so downed combatants cannot be affected by anything other than resurrection
- **`StatBlock.remove_all_status_effects()`** (`scripts/StatBlock.gd`) — iterates all active modifiers, collects instance IDs where the modifier registry entry has `is_status_effect: true`, then removes them; used by resurrection and by the healer's cure service
- **`PartyManager.get_downed_members()`** (`autoloads/PartyManager.gd`) — returns a typed array of all `PartyMember` entries where `is_downed == true`
- **World resurrect flow** (`autoloads/SpellManager.gd`) — `_spell_has_resurrect_effect(spell_id)` inspects a spell's effects array; `cast_spell()` detects resurrect + world context, checks for downed members, calls `Player.prompt_party_member_for_resurrect()` if multiple are downed, sets `_resurrect_target`, then calls `_do_cast_spell()` which bypasses tile targeting and invokes `attempt_cast()` directly; `_resurrect_target` is cleared both after `execute_effects` returns and on early can_cast failure
- **`Player.prompt_party_member_for_resurrect()`** (`scripts/Player.gd`) — posts a numbered member list to the MessageLog; single-downed-member shortcut fires the callback immediately; multi-member waits for numeric key input; callback receives the selected `PartyMember`
- **`cast_effect` use action** (`autoloads/GameManager.gd`) — registered in `UseActionRegistry`; reads an `effects` array from item params; if the array contains a resurrect effect and the context is world, calls `Player.prompt_party_member_for_resurrect()` async, sets `_resurrect_target`, then executes effects; always returns `true` so a chained `consume` action runs after
- **Out-of-combat party wipe detection** (`autoloads/GameManager.gd`) — `_on_world_tick` connected to `GameTime.tick_advanced`; when not in combat, a region is loaded, and `PartyManager.is_party_wiped()` is true, calls `CombatManager.show_mortis()`
- **`scroll_resurrect`** (`data/objects/objects.json`) — carriable scroll; `use_actions`: `cast_effect` (effects: resurrect) then `consume`; `base_price: 200`
- **`doodad` object (Shrine)** (`data/objects/objects.json`) — immovable structural object; `use_actions`: `cast_effect` (effects: resurrect); placed in Wilderness at [1, 11]
- **Healer NPC service** — `NPC.gd` gains `healer_service` bool and `heal_all_price`/`cure_all_price`/`resurrect_price` int fields; `HealerService` (`scripts/HealerService.gd`) is a `RefCounted` holding the three prices, loaded from an NPC via `load_from_npc(npc)`
- **`try_open_healer(npc)`** (`autoloads/GameManager.gd`) — validates `npc.healer_service`, builds a `HealerService`, closes all other panels, posts the greeting message, and opens `HealerPanel`; `Player._start_dialogue()` calls it before `try_open_shop()`
- **HealerPanel** (`scripts/HealerPanel.gd`, `scenes/ui/HealerPanel.tscn`) — CanvasLayer panel; `_build_rows()` creates a Heal All row, a Cure All row, and one Resurrect row per downed member; `_purchase()` deducts gold then applies the effect (heal_all: `set_stat("hp", get_max("hp"))` for each living member; cure_all: `remove_all_status_effects()` for all members; resurrect: `is_downed=false`, `set_stat("hp",1)`, `remove_all_status_effects()` for the named member); Up/Down navigation, Enter to purchase, Escape to close; mutual exclusion with all other panels
- **`healer_01.json`** (`data/npcs/healer_01.json`) — Sister Theresa; `healer_service: true`; `heal_all_price: 50`, `cure_all_price: 30`, `resurrect_price: 200`; placed in Wilderness at tile [2, 12]
- **5 new messages** (`data/config/messages.json`) — `resurrect_success` ("{name} is restored to life!"), `resurrect_no_target`, `healer_greeting`, `healer_service_heal_all`, `healer_service_cure_all`
- **Wilderness test placements** (`data/regions/wilderness.json`) — Shrine doodad at [1,11], scroll_resurrect at [1,12], healer_01 NPC at [2,12]
- **ResurrectionTest** (`scripts/debug/ResurrectionTest.gd`) — 11 assertions: `remove_all_status_effects` removes only status modifiers; resurrect world restores HP to 1, clears `is_downed`, clears status effects; resurrect combat syncs PartyMember; damage/heal/apply_modifier guards reject downed combatants; `_spell_has_resurrect_effect` detection; `cast_effect` action registered; `get_downed_members` returns correct members; wired into `GameManager.on_hud_ready()`

---

## [Unreleased] — 2026-06-20

### Added

- **Party combat integration** — all living party members enter the combat arena together; enemies continue to appear on the opposite side of the arena as before
- **Diamond formation placement** (`scripts/CombatArena.gd`) — eight formation offsets define positions relative to the entry-edge center tile; `_apply_formation_transform()` rotates the offset table for all four entry edges (south, north, west, east); if a formation tile is impassable or already occupied, `_find_nearest_passable()` locates the nearest free tile via spiral search; the party leader is placed at the entry center, companions at increasing depth offsets
- **Companion arena nodes** (`scripts/CombatArena.gd`) — each non-player party member receives a lightweight `Node2D` added to the `Actors` group at their formation tile; position is updated directly on move; the actual `$Actors/Player` node remains the camera anchor
- **`_active_combatant` tracking** (`scripts/CombatArena.gd`) — replaces the previously hardcoded `_player_combatant` reference in all input handlers (move, reticle aim, reticle confirm, attack, spell targeting, point-blank spell); updated at the start of each party member's turn via `start_player_turn(combatant)`
- **Per-member SpellManager caster routing** (`scripts/CombatArena.gd`) — `start_player_turn()` calls `SpellManager.set_caster(member)` when a companion's turn begins so that mana and reagent consumption draws from that member's stat block and inventory; `_end_player_turn()` calls `SpellManager.clear_caster()` to restore player-defaults
- **`combat_member_turn` message** (`data/config/messages.json`, `scripts/CombatManager.gd`) — posted at the start of each player-faction combatant's turn so the player knows which party member they are controlling
- **Downed state for party members** (`scripts/Combatant.gd`, `scripts/CombatManager.gd`) — when a party member's HP reaches 0, `_handle_death()` sets `combatant.is_downed = true` and `PartyMember.is_downed = true` (instead of triggering MORTIS); emits `PartyManager.member_downed`; posts `combat_member_downed` message; the combatant remains on its tile and continues to block movement for all other combatants
- **`combat_member_downed` message** (`data/config/messages.json`) — posted when a party member is downed in combat
- **Downed combatants skipped in initiative** (`scripts/CombatManager.gd`) — `_advance_turn()` skips any combatant with `is_downed == true`; downed members do not act and are not awakened mid-combat (resurrection deferred to M19e)
- **Enemy AI ignores downed party members** (`scripts/CombatManager.gd`) — `_get_player_combatant()` now skips downed members when selecting an NPC attack target; NPCs will only pursue and attack living party members
- **Downed members block movement** (`scripts/CombatArena.gd`) — `_is_tile_blocked()` scans the full combatant list and returns true for any non-fled, non-dead combatant (including downed) occupying the target tile; used by player movement and by NPC pathfinding via the new public `is_tile_occupied_in_arena()` method
- **Party wipe detection** (`scripts/CombatManager.gd`) — `_is_party_wiped()` returns true if all player-faction combatants are downed; `_check_party_wipe()` calls `show_mortis()` when detected; checked after every party member death
- **Downed members carried on flee** — `PartyManager` is not cleared by `end_combat()`; downed party members remain in the party after fleeing the arena and retain their downed state on the world map until resurrected (M19e)
- **XP distributed to all living party members** (`scripts/CombatManager.gd`) — `_award_xp_to_party(xp)` iterates `PartyManager.get_living_members()` and applies the full kill XP to every member's stat block; replaces the old single-player `grant_experience()` path; `grant_experience()` is preserved as a public alias
- **Companion level-up** (`scripts/CombatManager.gd`) — `_check_companion_level_up()` uses `LevelManager.check_level_up()` to detect threshold crossings; increments the companion's `level` stat and applies class-based stat cap raises if `class_id` is set; posts the `level_up` message per level gained
- **`experience` and `level` stats on NPC default** (`data/stats/npc_default.json`) — added so party companions (who load from this file) can accumulate XP and track their level; base values 0 and 1 respectively
- **`party_member_id` and `is_downed` on Combatant** (`scripts/Combatant.gd`) — `party_member_id` links a player-faction combatant back to its `PartyMember` for downed state sync and SpellManager routing; `is_downed` tracks the fallen-but-not-dead state used by initiative, movement blocking, and wipe detection
- **`class_name CombatArena`** (`scripts/CombatArena.gd`) — added so the formation helpers are accessible by name from the test suite
- **`max_party_size` increased to 8** (`data/config/game.json`) — supports parties of up to 8 members in combat formation
- **PartyCombatTest** (`scripts/debug/PartyCombatTest.gd`) — 31 assertions across 10 tests: formation offsets for south entry, formation rotation for west entry, all members present in initiative order, active combatant switching, party member downed state, downed tile blocking, party wipe detection, downed members carried on flee, XP distributed to all members, companion level-up; wired into `GameManager.on_hud_ready()`

### Changed

- **`PartyDataTest` test 4** (`scripts/debug/PartyDataTest.gd`) — party size limit test now uses `PartyManager.get_max_party_size()` dynamically instead of the previously hardcoded value of 4

---

## [Unreleased] — 2026-06-20

### Added

- **`is_status_effect` / `is_detrimental` flags** (`data/modifiers/modifiers.json`) — added to all 24 modifier definitions; detrimental status effects (spell_paralyze, spell_sleep, spell_poison, spell_obscure_vision) are `true/true`; beneficial status effects (spell_charm, spell_invisibility, spell_reveal_vision) are `true/false`; all equipment, potion, wand, and passive modifiers are `false/false`
- **`StatBlock.get_active_modifiers()` flag passthrough** — now includes `is_status_effect` and `is_detrimental` from the modifier registry; dynamic modifiers not in the JSON registry default both to `false`
- **PartyManager signals** (`autoloads/PartyManager.gd`) — `member_added(member)`, `member_removed(member_id)`, `member_downed(member_id)`, `member_revived(member_id)`; `add_member()` and `remove_member()` emit the appropriate signal; `set_member_downed()` toggles `is_downed` and emits downed/revived
- **Non-player member tick** (`autoloads/PartyManager.gd`) — `_on_tick_advanced()` calls `stat_block.tick()` on every living non-player party member each game tick, enabling regen and per-tick modifiers for companions
- **PartySidebar** (`scripts/PartySidebar.gd`) — replaces old stat display in `scenes/ui/Sidebar.tscn`; shows one row per party member with HP, MP (if applicable), and up to 3 detrimental status effect names; downed members rendered in grey with a red border; refreshes on tick, stat change, and all four PartyManager signals; reconnects to `stat_block.stat_changed` when `initialize_player()` replaces the player's stat block reference
- **CharacterPanel member navigation** (`scripts/CharacterPanel.gd`, `scenes/ui/CharacterPanel.tscn`) — Left/Right arrow keys cycle through all party members while the panel is open; title bar shows the current member's name and class; slot occupancy and stats read from `member.inventory` / `member.stat_block` rather than always using the player; signals reconnect on each navigate
- **`Player.prompt_party_member()`** (`scripts/Player.gd`) — prompts the player to select a party member by number; with only one living member the callback fires immediately; input is consumed until a valid number or 0/Escape is pressed
- **Get command party routing** (`scripts/Player.gd`) — after resolving direction and quantity, `prompt_party_member()` is called; the picked-up item goes into the selected member's inventory; player member routes through `PlayerInventory.add_stacked` (for light-state tracking), companions use their own `Inventory` directly; carry-limit check uses `member.stat_block.get_effective_value("carry_limit")`
- **SpellManager multi-member casting** (`autoloads/SpellManager.gd`) — `set_caster(member)` / `clear_caster()` override which member's resources are checked and consumed; `cast_spell()` calls `prompt_party_member()` in world context when the party has more than one living member; `can_cast()` and `consume_cast_resources()` route to the active caster's stat_block and inventory; caster is cleared after `attempt_cast()` executes
- **PartyWorldMapTest** (`scripts/debug/PartyWorldMapTest.gd`) — 36 assertions across 11 tests; covers sidebar row counts, downed display, status effect filtering (MAX 3), character panel navigation wrap, party member prompt (single/multiple/cancel), companion spell resource deduction, per-tick HP regen for companions, and `is_status_effect`/`is_detrimental` flag values; wired into `GameManager.on_hud_ready()`

### Changed

- **`Sidebar.tscn`** — script changed from old stat display to `PartySidebar.gd`; inner `VBoxContainer` renamed to `PartySummary`
- **`HUD.gd`** — exposes `sidebar` node reference to `GameManager.sidebar` on `_ready()`
- **`GameManager.gd`** — added `var sidebar` field; runs `PartyWorldMapTest` at end of `on_hud_ready()`

---

## [Unreleased] — 2026-06-20

### Added

- **Currency system** — `gold` stat in `data/stats/player.json` (base 200, max `INT_MAX`, no regen); `currency_stat_id` and `currency_display_name` fields in `data/config/game.json` and read by `GameManager`; no upper cap enforced, allowing unlimited accumulation
- **`base_price` field** (`data/config/object_defaults.json`, `data/objects/objects.json`) — added to the global object defaults (0 = unsellable) and set on 27 items: weapons, armour, ammo, consumables, reagents, and tools; items with `base_price: 0` are silently excluded from shop sell tabs
- **`data/shops/shops.json`** — shop registry; each entry specifies `shop_id`, `price_multiplier`, and an `inventory` list with `object_id`, `stock_count` (−1 = unlimited), `restock_interval` (days), and `restock_amount`; two shops defined: `general_store` (1.0×, stocks torch×20, lantern×5, lockpick×10, arrow unlimited, potion_strength×3) and `armory` (1.2×, stocks sword_iron×3, shield_wooden×3, helmet_leather×5, boots_leather×5, bow_short×2)
- **`Constants.SHOPS_DATA_PATH`** — path constant for the shops registry file
- **ShopManager** (`scripts/ShopManager.gd`) — `RefCounted`; loaded from a shop definition dict; `get_buy_price` applies `ceili(base_price × multiplier)`; `get_sell_price` returns `floori(base_price × 0.5)`, 0 for `base_price: 0` items; `deplete_stock` skips unlimited items; `_schedule_restock` uses `GameTime.schedule` with repeat for automatic per-item restocking; `get_inventory()` returns `{object_id, stock_count, buy_price, sell_price}` for all stocked items
- **`shop_id` field on NPC** (`scripts/NPC.gd`, `data/npcs/innkeeper_01.json`, `data/npcs/armorer_01.json`) — optional string field; non-empty marks the NPC as a shop operator; `shop_id: "general_store"` added to `innkeeper_01`
- **`armorer_01.json`** (`data/npcs/`) — new NPC; display name "Armorer"; `shop_id: "armory"`; schedule: `shopkeeper` activity 07:00–19:00, sleeping otherwise; placed in Town at tile [14, 19] (adjacent to player spawn)
- **Shop registry and open flow** (`autoloads/GameManager.gd`) — `_load_shops()` instantiates a `ShopManager` per entry at startup; `_reset_shop_state()` cancels restock timers and reloads (called on new game reset); `get_shop(shop_id)` public accessor; `try_open_shop(npc)` validates `_current_activity == "shopkeeper"` and non-empty `shop_id`, closes all other open panels, posts the greeting message, and opens `ShopPanel`; `shop_ui_pending` field preserved for backwards compatibility
- **Shop state persistence** (`autoloads/SaveManager.gd`) — `_serialize_shop_state()` saves per-shop per-item stock levels; `_serialize_game_time()` includes a `scheduled_shops` array of `{shop_id, object_id, remaining_ticks}`; `_deserialize_shop_state()` restores stock counts and reschedules restock timers with remaining ticks, cancelling any existing handles first
- **ShopPanel** (`scripts/ShopPanel.gd`, `scenes/ui/ShopPanel.tscn`) — CanvasLayer; UI constructed in `_ready()` (Panel + VBoxContainer + tab bar + column header + ScrollContainer/ItemList + detail pane + instruction label); `open(shop, npc_name)` populates Buy and Sell tabs and shows the panel; `close()` hides and clears state
  - **Buy tab** — all shop inventory items sorted by type then name; out-of-stock items (`stock_count: 0`) greyed and non-selectable; unlimited stock displayed as `--`
  - **Sell tab** — player inventory items with `sell_price > 0` (items where `base_price ≤ 1` and thus `floori(base_price × 0.5) == 0` are excluded); sorted by type then name
  - **Detail pane** — shows item description and, for equippable items, which classes have the `equipment_type` in their whitelist
  - **Input** — Left/Right switches tabs; Up/Down navigates list; Enter enters quantity mode; in quantity mode Left/Right adjusts quantity, Enter confirms, Escape exits quantity mode; Escape (outside quantity mode) closes panel; `I` (inventory) closes shop and lets inventory open
  - **Buy transaction** — validates gold ≥ total cost, carry weight, and stock; deducts gold, calls `PlayerInventory.add_stacked`, calls `ShopManager.deplete_stock`
  - **Sell transaction** — calls `PlayerInventory.take_from_stack`, adds gold
- **`PlayerInventory.would_exceed_carry_limit_for(object_id, quantity)`** — weight check for buying multiple items without a WorldObject instance; returns false when carry_limit is 0 (no limit)
- **Shop messages** (`data/config/messages.json`) — `shop_greeting`, `shop_restocked` (reserved), `shop_buy_success`, `shop_sell_success`, `shop_cannot_afford`, `shop_out_of_stock`, `shop_carry_limit`
- **ShopPanel registered in HUD** (`scenes/ui/HUD.tscn`, `scripts/HUD.gd`) — added as 10th CanvasLayer child; registered to `GameManager.shop_panel` in `_ready()`
- **Mutual exclusion** — `try_open_shop()` closes inventory, character, journal, save/load, and spellbook panels when the shop opens; all panel toggle handlers in `GameManager._unhandled_input` close the shop panel before opening another

---

## [Unreleased] — 2026-06-19

### Added

- **LockManager** (`scripts/LockManager.gd`) — new instantiable class; owns all lock/unlock logic; `attempt_unlock(actor, target, key_item)` handles key unlock (checks lock_ids), lockpick unlock (stat roll + break chance), and spell unlock (direct, no roll); `attempt_lock(actor, target, key_item)` closes an open door before locking; `_roll_lockpick_success()` compares player's success_stat against success_threshold with probabilistic fallback; `_roll_lockpick_break()` removes one from the lockpick stack on break
- **Lock data model** (`data/config/object_defaults.json`) — six new fields on all WorldObjects: `is_locked` (bool, default false), `lock_id` (String, identifies which lock this object is), `lock_ids` (Array, which locks a key opens), `success_stat` (String, stat used for lockpick rolls), `success_threshold` (int, guaranteed-success floor), `break_chance` (float, per-fail lockpick destruction probability)
- **`key` object type** (`data/config/object_types.json`) — carriable, movable, passable, transparent, weight 0.1
- **`lockpick` object type** (`data/config/object_types.json`) — same as key plus `equippable: true`, `equipment_type: "lockpick"`
- **`lockpick` equipment type** (`data/config/equipment_types.json`) — display name "Lockpick"; class whitelist enforcement blocks use if class does not include it
- **`treasury_key`** (`data/objects/objects.json`) — stackable: false, lock_ids: ["treasury_lock"], use_actions: use_key
- **`lockpick`** (`data/objects/objects.json`) — success_stat: "dex", success_threshold: 15, break_chance: 0.3, use_actions: use_lockpick
- **`door_oak_locked`** (`data/objects/objects.json`) — like door_oak but is_locked: true, lock_id: "treasury_lock"
- **Wilderness placements** — treasury_door (door_oak_locked) at [13,8], treasury_key at [6,7], lockpick stack of 3 at [7,7]
- **`use_key` action** (`autoloads/GameManager.gd`) — prompts direction; finds lockable WorldObject on target tile; calls `attempt_lock` if unlocked, `attempt_unlock` if locked; posts appropriate messages
- **`use_lockpick` action** (`autoloads/GameManager.gd`) — class restriction check before direction prompt; prompts direction; calls `attempt_unlock` with lockpick context; class without "lockpick" in equipment_whitelist is blocked with `equip_class_restricted` message
- **`_find_lockable_object(tile)`** (`autoloads/GameManager.gd`) — helper returning the first WorldObject with a non-empty lock_id at a tile
- **`WorldObject` lock fields** (`scripts/WorldObject.gd`) — `is_locked`, `lock_id`, `lock_ids`, `success_stat`, `success_threshold`, `break_chance` declared and initialized from object data in `_ready()`
- **Lock state persistence** — `is_locked` included in region snapshot, restored from cache, compared in `_object_differs_from_baseline` (against baseline value, not hardcoded false), and applied by `apply_diff`
- **Stackable guard** (`scripts/Inventory.gd`) — `add_stacked` skips stack merge when object data has `stackable: false`; keys with `stackable: false` now correctly create separate inventory entries
- **Lock messages** (`data/config/messages.json`) — `lock_not_locked`, `lock_wrong_key`, `lock_cannot_lock`, `lock_unlocked_key`, `lock_unlocked_spell`, `lock_locked`, `lock_already_locked`, `lock_picked`, `lock_pick_failed`, `lock_pick_broken`, `lock_nothing_there`, `lock_door_locked`

### Changed

- **`SpellEffectExecutor._effect_unlock`** — rewritten to use `LockManager.attempt_unlock` (spell context); now targets WorldObjects with a non-empty `lock_id` rather than any toggleable object; posts `lock_nothing_there` if no lockable object found instead of a push_warning
- **`GameManager._action_toggle_passability`** — checks `obj.is_locked` before toggling; posts `lock_door_locked` and returns false if locked, preventing the door from being opened while locked
- **`EquipmentTypeRegistry`** — `lockpick` type added; validated against class equipment whitelists at startup

---

## [Unreleased] — 2026-06-19

### Added

- **SpellManager autoload** (`autoloads/SpellManager.gd`) — loads spell definitions from `data/config/spells.json`; tracks known spells (`_known_spells`); `can_cast(spell_id, context)` validates context restriction, stat cost, and reagent availability; `attempt_cast` consumes resources and delegates to `SpellEffectExecutor`; `cast_spell` dispatches on `targeting_type`: `none`/`self` execute immediately, `point_blank` and `targeted` emit `spell_targeting_requested` for the active scene to handle; `consume_cast_resources` deducts the casting stat and burns one of each required reagent; `get_missing_reagents` returns unfulfilled reagent ids; `default_casting_stat` configurable per-registry (default `mana`)
- **SpellEffectExecutor** (`scripts/SpellEffectExecutor.gd`) — 16 registered effect types dispatched by `effect_type` string: `damage` (hit/miss via `CombatResolver`, formula-driven stat delta), `heal` (formula-driven HP restore, no hit check), `apply_modifier` (applies a named modifier to target stat block), `dispel` (removes modifiers by source tag), `spawn_object` (with optional `duration_ticks`), `transmute` (replaces one object type with another at a tile), `unlock` (sets toggleable object `is_open`), `teleport` (region warp, blocked in combat), `displace` (pushes caster or target N tiles in a cardinal direction), `reveal` / `obscure` (vision modifiers), `invisibility` (triggers NPC flee in combat), `charm` (temporary NPC hostility toggle), `sleep` (sets NPC to unconscious availability), `poison` (applies poison modifier), `paralyze` (sets `is_paralyzed` for a duration); stat deltas batched and applied after all effects in a call; `execute_effects` accepts an `affected_entities: Array` of `Combatant` refs for AE multi-target mode — when non-empty, effects run per-entity with per-entity delta tracking
- **AEShapeCalculator** (`scripts/AEShapeCalculator.gd`) — pure static class; `get_circle_tiles(center, radius)` returns all tiles within Chebyshev distance; `get_line_tiles(origin, target, width)` uses Bresenham line with perpendicular half-width expansion; `get_cone_tiles(origin, direction, length)` widens 2N-1 tiles at distance N
- **SpellTargeting** (`scripts/SpellTargeting.gd`) — `compute_ae_tiles(spell, caster_tile, target_tile, terrain_layer)` dispatches on `ae_shape` (`circle`, `line`, `cone`, `earthquake`); optional LOS filter enabled by `los_filter: true` on the spell; `get_spell_range(spell)` reads the `range` field; `earthquake` shape returns all passable tiles in the arena
- **TargetingReticle** (`scripts/TargetingReticle.gd`) — Node2D drawn in CombatArena; orange cursor rect on the active tile, red filled rects on AE tiles; `activate(tile)`, `move_to(tile)`, `set_ae_tiles(tiles)`, `deactivate()`
- **SpellbookPanel** — CanvasLayer panel (`B` key); lists known spells with casting stat cost; confirm invokes `SpellManager.cast_spell`; closes on Escape or spell cast; mutual exclusion with Inventory, Character, and Journal panels
- **`data/config/spells.json`** — spell registry; `default_casting_stat: "mana"`; spells: `fireball` (AE circle-3 damage, combat-only), `heal` (self HP restore), `sleep`, `charm`, `teleport`, `unlock`, `transmute_wall` (wall_stone → door_oak), `earthquake` (AE all-passable damage, combat-only)
- **`data/stats/npc_default.json`** — `mana` stat added: base 30, max 30, regen 1/10 ticks
- **`data/npcs/goblin_shaman.json`** — new NPC; stat overrides `hp: 30`, `int: 14`, `mana: 50`; combat priority list: cast `fireball` when `mana >= 15`, flee when `hp < 30%`; `experience_value: 25`
- **`data/npcs/goblins.json`** — `goblin_shaman` added to group members with weight 1 and `max_count: 1`
- **`data/config/messages.json`** — spell message keys added: `spell_learned`, `spell_already_known`, `spell_no_spell_on_scroll`, `spell_unknown_spell`, `spell_cast`, `spell_insufficient_stat`, `spell_missing_reagents`, `spell_wrong_context`, `spellbook_empty`, `spell_unlock`, `spell_charm_success`, `spell_sleep_success`, `spell_paralyze_success`, `spell_dispel_success`, `spell_transmute_no_target`, `spell_displace_blocked`, `cast_prompt_target`, `spell_cancelled`, `spell_no_target`, `spell_healed`, `npc_cast_spell`

### Changed

- **`CombatAI.gd`** — `evaluate()` replaced by `choose_action_entry(combatant, target, arena) -> Dictionary`; returns the first priority-list entry whose conditions pass (AND/OR/NOT operators; `threshold_percent` for percent-of-max comparisons), or a default `{action}` dict; `execute_cast_spell(combatant, target, spell_id, arena)` validates mana, resolves target tile by `targeting_type`, computes AE tiles, applies faction filter, consumes mana, executes effects, and posts the `npc_cast_spell` message; skips effect execution if no entities and no valid target node
- **`CombatManager.gd`** — `_execute_npc_turn` calls `choose_action_entry` (Dictionary) instead of `evaluate` (String); dispatches `"cast_spell"` action to `combatant.ai.execute_cast_spell`
- **`CombatArena.gd`** — `get_entities_on_tile(tile)` returns all living, non-fled combatants on a tile; `filter_affected_entities(ae_tiles, caster_faction)` returns combatants on any AE tile whose faction differs from the caster's; `cast_point_blank_spell` rewritten to use a single `execute_effects` call with filtered entities instead of a per-combatant loop; `_handle_reticle_confirm` passes filtered entities to `SpellManager.attempt_cast`; spell targeting mode connected to `SpellManager.spell_targeting_requested` signal
- **`SpellManager.attempt_cast`** — signature extended with `affected_entities: Array = []`; passed through to `SpellEffectExecutor.execute_effects`

---

## [Unreleased] — 2026-06-16

### Added

- **ClassRegistry** — loads `data/config/classes.json`; provides per-class starting stats, stat allocation ranges, stat gains per level, and equipment type whitelist; validated against `PlayerStats` and `EquipmentTypeRegistry` at startup
- **EquipmentTypeRegistry** — loads `data/config/equipment_types.json`; maps equipment type IDs to display names; registered types: `blade`, `blunt`, `ranged`, `heavy_armor`, `light_armor`, `cloth`, `accessory`, `ammo`
- **`data/config/classes.json`** — two classes defined: `fighter` (blade, blunt, ranged, heavy_armor, light_armor, accessory, ammo) and `mage` (blunt, cloth, accessory); each specifies `starting_stats`, `stat_ranges`, `stat_gains_per_level`, and `equipment_whitelist`
- **`data/config/equipment_types.json`** — eight equipment type definitions with display names
- **StatAllocator** — manages stat point allocation during character creation; respects per-class min/max ranges and optional point budget; methods: `load_class()`, `can_increment()`, `can_decrement()`, `increment()`, `decrement()`, `get_budget_remaining()`, `is_valid()`, `apply_to_player()`
- **Character creation flow** — name entry → class selection → stat allocation, all inline in the main menu (no separate scenes); back-navigation preserves the entered name and previously selected class
  - Class selection panel: scrollable list (left) + detail pane (right) showing class name, description, visible starting stats, and equipment whitelist
  - Stat allocation panel: `<` / `>` controls per stat, live budget display, range indicators, validation error on submit
  - Hidden stats (karma, vision_radius, experience) excluded from both panels
  - Save slot created after all steps complete, not after name entry
- **Equipment restrictions** — `equipment_type` field required on all equippable objects; `Inventory._check_equipment_restriction()` enforces the class whitelist before slot checks in `equip_item()`; items with `equipment_type: null` post "You cannot equip that."; class mismatches post "Your class cannot equip that."
- **`equipment_type` field** added to all equippable objects in `objects.json`; `ring_silver` and `ring_gold` set to `"accessory"`; ammo object type defaults include `"equipment_type": "ammo"`; `accessory` and `ammo` types added to `equipment_types.json`
- **Class change mechanic** — `class_change` quest reward type; `GameManager.apply_class_change(new_class_id)` validates the new class, force-unequips incompatible items (posting "Your [item] has been unequipped." per item), calls `PlayerStats.set_current_class()`, posts "You are now a [class].", and updates the save slot metadata; player stat values unchanged; new class starting stats not applied; level-up gains switch to the new class immediately
- **`PlayerInventory.force_unequip_restricted(new_class_id)`** — unequips all equipped items whose `equipment_type` is not in the new class whitelist; items with `equipment_type: null` are skipped; recalculates light modifier; emits `equip_changed` if anything changed
- **Sidebar class display** — class name shown in HUD sidebar below character name; updated immediately via `PlayerStats.class_changed` signal
- **Class column in Load Game screen** — `LoadGameScene` shows a `Class` column between Name and Timestamp in the save list
- **`PlayerStats.current_class_id`** persisted in save files under `player.current_class_id`; restored on load, class name display updates automatically
- **`PlayerStats.get_stat_display_name(stat_id)`** — returns the human-readable name for a stat from the stat block definition
- **`PlayerStats.is_stat_visible(stat_id)`** — returns whether a stat has `"visible": true` in the stat block definition
- **`SaveManager.save_new_game(player_name, class_id)`** — creates the first save slot at the end of character creation after all steps are complete
- **`SaveManager._update_save_slot_class(new_class_id)`** — patches the most recent non-autosave slot's `class_id` and `class_name` in `index.json` on mid-game class change; autosave slots updated on next autosave
- **Test quest `test_class_change`** — "The Path Changes"; F11 (debug) starts, F12 (debug) completes its single objective, triggering a `class_change` reward to mage; tests the full class change flow including force-unequip

### Changed

- `MainMenu.gd` rewritten to support a four-step character creation flow (`MAIN_MENU → NAME_INPUT → CLASS_SELECT → STAT_ALLOC`); `MainMenu.tscn` extended with `ClassPanel` and `StatPanel` subtrees; menu chrome (spacers, options) hidden during panel steps to give panels full vertical space
- `SaveManager._update_index()` parameter renamed from `class_name` to `cls_name` to avoid the GDScript reserved keyword; `save()` and `autosave()` now pass class id and display name to the index
- `GameManager.apply_class_starting_stats()` calls `PlayerStats.set_current_class()` after setting stats, triggering the `class_changed` signal for immediate sidebar/panel refresh
- `ClassRegistry.load_from_file()` logs a deprecation warning when a class entry contains the removed `weapon_whitelist` field
- `GameManager._validate_registries()` updated to remove the stale `get_weapon_whitelist` validation loop

### Removed

- `ClassRegistry.get_weapon_whitelist()` — replaced by the unified `get_equipment_whitelist()`
- Separate `weapon_whitelist` field in class definitions — collapsed into `equipment_whitelist`

---

## [Unreleased] — 2026-06-12

### Added

- **Light and vision system** (`DarknessOverlay`) — per-tile darkness rendered in the SubViewport as a Node2D (z_index 100); opacity computed from Euclidean distance to the player and each fixed light source; 2-tile falloff zone around the lit boundary; minimum draw radius of 3 tiles so the player and adjacent tiles are always visible at full night
- **`vision_radius` stat** — base 27 (full daylight / full viewport), minimum 1 (deep night with no light); `visible: false` so it never appears in the status window
- **Ambient light** — `GameTime` schedules `_on_half_hour_ambient` every 5 game-minutes; ambient radius interpolated linearly across dawn (5–7 AM) and dusk (19–21) transitions; applied as an `exclusive_per_source` modifier tagged `AMBIENT_LIGHT_SOURCE_TAG`; at full daylight `_draw()` returns immediately, skipping all per-tile work
- **Carriable light sources** — `light_source_toggle` use action registered on `GameManager`; per-instance state tracked in `PlayerInventory._light_states` (lit, duration remaining, timer handle, radius); duration decrements each game tick via `GameTime.schedule`; burnout removes the item from inventory; dropping a lit item calls `GameManager.spawn_with_duration` to preserve remaining duration on the world object
  - **Torch** — radius 6, duration 500 ticks
  - **Lantern** — radius 10, duration 2000 ticks (`lantern.json`, new object)
- **Fixed light sources** — registered at region load via `GameManager._register_fixed_light_sources`; illuminate independently of player position; duration −1 = permanent
  - **Wall Sconce** — radius 5, permanent (`wall_sconce.json`, new object)
- **`GameManager.region_loaded` signal** — emitted after fixed light sources are registered each region load; `DarknessOverlay` subscribes to refresh its source list
- **`GameTime.restore_ticks(ticks)`** — sets `total_ticks`, recalculates ambient modifier, and emits `time_restored`; replaces direct `total_ticks` assignment in `SaveManager` to fix stale clock and wrong vision radius after loading a save
- **`GameTime.time_restored` signal** — distinct from `tick_advanced` to avoid spurious NPC tick handler invocations on load; consumed by `ClockDisplay`
- **`GameTime.recalculate_ambient()`** — public entry point for ambient recomputation without advancing time
- **`StatBlock.is_derived(stat_id)`** — public helper; used by `SaveManager` to skip restoring computed stats (e.g. `attack`) on load
- **`StatBlock.apply_dynamic_modifier(def, source_tag)`** — applies a modifier from a runtime-built definition dict, bypassing the static registry; used for ambient and carried-light modifiers whose magnitudes are computed at runtime
- **`duration` and `light_radius` fields** — added to all 31 object JSON files; `null` for non-light items
- **`AMBIENT_LIGHT_SOURCE_TAG` and `CARRIED_LIGHT_SOURCE_TAG`** — new string constants in `Constants.gd`
- **Test placements in `wilderness.json`** — lantern at [7, 8]; wall sconces at [14, 8] and [16, 8]

### Changed

- `PlayerInventory.remove_object_anywhere` and `take_from_stack` call `_handle_light_removal` before removing a lit item so the vision modifier is cleared immediately
- `Player._resolve_drop` reads `get_pending_drop_duration` before `take_from_stack` to preserve lit-item duration on drop
- `SaveManager._deserialize_game_time` calls `GameTime.restore_ticks()` instead of setting `total_ticks` directly
- `SaveManager._deserialize_player` skips derived stats during restoration (previously emitted a `set_stat` warning for `attack` on every load)
- `get_active_modifiers()` result now includes `stat_visible` per entry; `Sidebar` filters out modifiers on non-visible stats, hiding the ambient light modifier from the status window
- Ambient update interval changed from 30 game-minutes to 5 game-minutes for smoother dusk/dawn gradient

### Fixed

- Fixed-source opacity in `DarknessOverlay` was comparing raw distances rather than computing per-source opacity independently; a nearby sconce (radius 5) would override the player's daytime vision (radius 27) and darken large map areas. Each source now contributes its own opacity and the per-tile minimum is used
- At full daylight (`vision_radius == max`), `_draw()` now returns immediately, eliminating diagonal darkness bands when the player was near a corner of a larger-than-viewport region
- Clock display was not refreshed on save load until the first game tick
- Ambient vision modifier was not recalculated on save load, leaving the darkness overlay in the wrong state until the next scheduled ambient tick

---

## [Unreleased] — 2026-06-10

### Added

- **QuestManager autoload** — loads quest definitions from `data/quests/quests.json`; tracks per-quest state (active, complete, failed) and per-objective state (hidden, inactive, active, complete, skipped)
- **Quest triggers** — quests start via dialogue keyword (`check_dialogue_triggers`), region entry (`check_region_entry_triggers`), tile step (`check_tile_triggers`), or reading a world object (`_action_read`)
- **Objective types** — `talk`, `kill`, `reach_region`, `reach_location` (with `region_enter` or `tile_step` sub-trigger), and `action` (branch-resolved)
- **Kill objective tracking** — `CombatManager._handle_death` captures each combatant's `npc_id` before `queue_free` and calls `QuestManager._on_npc_died`; `any_of_group` flag matches kills by NPC id prefix (supports NPC groups)
- **Prerequisite and visibility system** — objectives with `prerequisite_id` start hidden or inactive; they activate automatically when the prerequisite completes; `hidden_until_prerequisite` and `initial_status` fields control initial state
- **Quest branches** — `trigger_branch()` sets `triggered_branch_id`, closes competing branches (skipping their unstarted objectives), activates or completes listed objectives, starts a followup quest if specified, and calls `_check_quest_completion`; `auto_trigger` branches fire automatically from `_evaluate_branches` after every `complete_objective`
- **Item-triggered branches** — `quest_branch_trigger` field on item data fires `trigger_branch` after `_action_consume`
- **Dialogue quest delivery** — NPC keyword blocks support a `quest_delivery` dict; `check_deliver_objective` deducts the item from inventory and either triggers a branch (`trigger_branch_id`) or completes a specific objective
- **Quest rewards** — `_distribute_rewards` collects quest-level and triggered-branch rewards; `_apply_reward` handles `experience` (via `CombatManager.grant_experience`), `item` (inventory or tile drop on overweight), and `stat` (via `PlayerStats.modify_stat`)
- **Fail conditions** — `npc_dead` checked in `_on_npc_died`; `time_elapsed` scheduled via `GameTime.schedule` on quest start and cancelled on completion or failure
- **Journal entries** — timestamped entries written to `journal_updates` on objective completion (`"Objective complete: …"`), new objective reveal (ordered quests), and quest resolution
- **`GameTime.get_timestamp_string()`** — returns `"Day N, HH:MM"` using the existing `format_clock()`
- **`QuestManager.get_all_objective_states(quest_id)`** and **`get_journal_updates(quest_id)`** — query API for UI consumers
- **JournalPanel** (`J`) — CanvasLayer panel listing active, completed, and failed quests; up/down cursor navigation skips category headers; Enter expands/collapses a quest to show non-hidden objectives with `[ ]`/`[x]`/`[-]` markers; lower pane shows quest description and timestamped journal log for the selected quest; Escape closes
- **Panel mutual exclusion** — opening the Journal closes the Character panel and vice versa; opening Inventory closes the Journal
- **Panel centering** — all three overlay panels (Character, Journal, Inventory) are now centered over the 864×672 map viewport at uniform 780×600 dimensions
- **`toggle_journal` input action** — bound to `J` (physical_keycode 74)
- **Test quest content** — three quests in `data/quests/quests.json`: `test_quest_01` (The Missing Merchant — branching, kill, delivery), `test_quest_02` (Deliver the Letter — region travel), `test_quest_03` (Goblin Slayer — kill count)
- **New NPCs and items** — `quest_merchant.json` (Tarvo), `bandit_leader.json`; `merchants_ledger.json` with `quest_branch_trigger`; `data/player/player.json` with starting inventory
- **Quest-aware dialogue** — `innkeeper_01` (Olwen) and `quest_merchant` (Tarvo) updated with keyword chains that guide the player through `test_quest_01`

### Changed

- `complete_objective` posts `"Objective complete: …"` to the message log and writes a timestamped journal entry; ordered quests also post and journal the next revealed objective
- `_check_quest_completion` posts `"Quest complete: …"` and writes a journal entry; repeatable quests erase their state to allow restart
- `start_quest` posts `"New quest: …"` to the message log
- `InventoryScreen` panel resized from 520×400 to 780×600 and repositioned to center over the map viewport

---

## [Unreleased] — 2026-06-07

### Added

- `Constants.tile_to_world()` static helper; all callers (Player, NPC, WorldObject, CombatArena, CombatManager) updated and local copies deleted
- `Constants.natural_list()` static helper; local copy in Player deleted, InventoryScreen updated
- `Constants.apply_camera_limits()` static helper; applied in Town, Wilderness, and CombatArena, replacing 12 inline `cam.limit_*` assignments
- `Constants.load_json()` static helper for uniform JSON loading
- Eight new string constants: `MODIFIER_REGISTRY_PATH`, `NPC_SCENE_PATH`, `WORLD_OBJECT_SCENE_PATH`, `LOOK_DESCRIPTION_LAYER`, `EXPERIENCE_STAT_ID`, `SPRITE_CORPSE_PATH`, `SPRITE_CARRIABLE_PATH`, `SPRITE_NONCARRIABLE_PATH`
- `GameManager.configure_spawns()` public API; RegionLoader now calls it instead of mutating `_spawn_points`/`_default_spawn` directly
- `GameManager._REGION_SCENE_PATHS` const dictionary replacing runtime string-building in `_region_id_to_scene_path()`
- `Combatant.get_weapon_range()` and `Combatant.get_equipped_weapon()` — canonical implementations on the class that owns the data; private copies in CombatManager, CombatResolver, and CombatAI deleted
- Player attack input (`_on_attack()`, `_resolve_attack()`) added to Player.gd with directional prompt
- `ClockDisplay` change-guard: `_on_tick_advanced` now skips `_update_display()` when hour, minute, day, month, and year are all unchanged
- Weight-limit check in `Inventory.move_to_container()`, matching the guard already present in `add_to_container()`
- Null check for `$Sprite2D` in WorldObject before setting texture
- `object_id` field added to `portal.json` and `town_marker.json` (all 24 object data files now carry the field)

### Changed

- `WorldState.is_tile_occupied_by_npc()` and `get_npc_at_tile()` rewritten to query `tile_occupants` directly; stale-node eviction preserved
- All hardcoded string literals and scene paths replaced with the new `Constants.*` fields throughout Player, StatBlock, PlayerStats, CharacterPanel, InventoryScreen, Town, Wilderness, CombatArena, RegionLoader, and GameManager
- `LineOfSight.has_line_of_sight()` now uses `WorldState.get_objects_at()` (O(1) dict lookup) instead of `GameManager.get_objects_at()` (O(n) child scan)
- NPC JSON files `guard_01.json`, `innkeeper_01.json`, `goblins.json` updated with `hostile`, `experience_value`, and `corpse_name` fields
- Seven equipment JSON files (`boots_leather`, `helmet_leather`, `ring_gold`, `ring_silver`, `shield_wooden`, `sword_iron`, `sword_twohanded`) rewritten with complete schema, including the `type` field required by combat variable resolution

### Fixed

- `GameManager.is_tile_transparent()` was using `tile_data.get_collision_polygons_count(0) > 0`, which always returns 0 for procedurally-built tiles, making all terrain transparent to line-of-sight and talk checks. Now delegates to `tile_registry.is_transparent(type_id)`
- `GameManager.is_tile_passable()` null-guards `tile_registry` before calling `is_passable()`, preventing a crash during scene load before the registry is ready
- Attack input and F9 debug XP cheat removed from `GameManager._unhandled_input`; attack input lives in Player, debug cheat is gone entirely

### Removed

- `WorldState._npc_by_tile` dictionary and `register_npc_tile()` / `unregister_npc_tile()` methods; all call sites in NPC.gd (×6) and CombatManager.gd (×4) removed
- Dead methods: `GameTime.format_clock_line()`, `WorldState.clear_item_tile()`, `WorldState.is_tile_blocked_by_object()`, `WorldState.clear_npc_registry()`
- Hardcoded `_NPC_SCENE` and `_WORLD_OBJECT_SCENE` local constants from CombatArena and RegionLoader
- Private `_get_weapon_range()` and `_get_equipped_weapon()` / `_get_player_weapon_range()` copies from CombatManager, CombatResolver, and CombatAI

---

## [0.1.0] — initial commit

- Milestone 1: player walks a tile-grid map (wilderness and town scenes)
- Autoloads: Constants, WorldState, PlayerInventory, PlayerStats, GameTime, GameManager, MessageLog, CombatManager
- Tile-based movement, camera limits, look command, basic NPC scheduling and pathfinding
- Turn-based combat arena with initiative order, ranged/melee resolution, experience and levelling
- Inventory system with equipment slots, containers, and weight limits
- Region cache for preserving world state across area transitions
- Dialogue system, corpse decay, clock display
