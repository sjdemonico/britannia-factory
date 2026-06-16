# Changelog

All notable changes to Britannia Factory are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
