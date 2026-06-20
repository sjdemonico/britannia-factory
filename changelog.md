# Changelog

All notable changes to Britannia Factory are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
