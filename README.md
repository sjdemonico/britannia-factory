> This "software" is provided as-is with minimal documentation and is unlikely to be fit for human consumption.

# Britannia Factory

A systems sandbox built in Godot 4.3+, inspired by the Ultima series. The long-term intent is a toolkit for building Ultima-like worlds: data-driven, configurable, and generic enough that designers can build a wide variety of games on top of it. Test content uses Ultima III/IV conventions but no system is hardcoded to that setting.

This is a personal learning project in active development. It is not a game. It is not ready for use by anyone.

---

## Technical Overview

- **Engine:** Godot 4.3+, Compatibility renderer
- **Language:** GDScript
- **Resolution:** 1280×1024 (5:4) window — internal viewport 1280×853, stretched vertically to simulate the rectangular pixel aspect ratio of period CRT displays
- **Tile size:** 32×32px
- **Map viewport:** 27×21 tiles

---

## What Exists

### Core Systems

- **Tile-based movement** -- 8-directional, hold-to-run, camera snap, strict grid
- **Region system** -- named regions load from JSON; region cache preserves NPC positions and object state across transitions; walk-on and enter transition types supported
- **NPC dialogue** -- keyword system, highlighted keywords, direction-targeted talk
- **World object system** -- universal entity model with passability, movability, transparency, and carriability flags
- **Container interaction** -- open, close, deposit, spill on look
- **Inventory** -- toggled screen, nested containers, tree navigation, weight tracking
- **Stat system** -- fully data-driven stats, derived stats, temporary modifiers, stat regeneration, equipment modifiers
- **Time system** -- action-based ticks, configurable calendar, day/night cycle, seasons
- **Light and vision** -- per-tile darkness overlay drawn in the map viewport; player vision radius stat driven by time of day (full visibility at noon, minimum at midnight); carriable light sources (torch, lantern) with finite duration, lit/extinguished toggle, and duration preserved on drop; fixed world light sources (wall sconces) illuminate independently; smooth 5-minute ambient transitions across dawn and dusk
- **Save / load** -- named save slots, autosave rotation, save index with timestamps; full serialization of player stats, inventory, equipped items, region diffs (object and NPC state), quest state, and game time; scheduled quest timers restored on load
- **Message log** -- scrollable, all world feedback posted here
- **Line-of-sight** -- Bresenham ray cast checks terrain opacity and object transparency flags; used by talk and combat targeting

### Combat System

- **Turn-based combat arena** -- separate scene, configurable dimensions, tile-type inherited from world encounter tile
- **Initiative and turn order** -- stat-driven initiative roll, player-first tiebreak
- **Attack resolution** -- hit/miss and damage driven by formula expressions over stat and equipment variables
- **Ranged combat** -- ammo-type weapons consume quiver stack; projectile animation; range enforcement
- **Flee mechanics** -- player can flee to a cardinal edge; NPCs can also flee; pursuit system returns hostile NPCs to the world map
- **Experience and levelling** -- configurable XP per kill, threshold-based level-up, stat gains per level defined in config
- **NPC groups** -- encounter spawns weighted NPC groups from JSON definitions; survivor count preserved on flee

### Spell System

- **SpellManager autoload** -- loads spell definitions from `data/config/spells.json`; tracks known spells; `can_cast` validates context, stat cost, and reagents; `attempt_cast` consumes resources and dispatches to `SpellEffectExecutor`; `cast_spell` handles targeting-type dispatch (none/self/point_blank/targeted); `spell_targeting_requested` signal decouples spellbook from scene
- **SpellEffectExecutor** -- 16 effect types: `damage`, `heal`, `apply_modifier`, `dispel`, `spawn_object` (with optional duration), `transmute`, `unlock`, `teleport`, `displace`, `reveal`, `obscure`, `invisibility`, `charm`, `sleep`, `poison`, `paralyze`; damage and heal driven by formula expressions over caster and target stats; stat deltas batched and applied after all effects; entity-loop mode for AE spells
- **AEShapeCalculator** -- pure static class; `get_circle_tiles` (Chebyshev radius), `get_line_tiles` (Bresenham + perpendicular width), `get_cone_tiles` (widens 2N-1 at distance N)
- **SpellTargeting** -- `compute_ae_tiles` dispatches on `ae_shape`; optional LOS filter via Bresenham ray cast; `get_spell_range` reads range from spell definition
- **Targeting reticle** -- orange cursor tile + red AE fill drawn in CombatArena; moves with directional input; AE preview updates live; range-clamped
- **Spellbook panel** (`B`) -- scrollable list of known spells; stat cost and reagent display; invokes `SpellManager.cast_spell` on confirm
- **NPC spell casting** -- `CombatAI.choose_action_entry` evaluates a priority list of condition/action entries (AND/OR/NOT operators, stat comparisons including `threshold_percent`); `execute_cast_spell` validates mana, computes AE, applies faction filter, consumes mana, and posts the `npc_cast_spell` message
- **Faction-aware AE** -- `CombatArena.filter_affected_entities` returns combatants on AE tiles whose faction differs from the caster; player spells hit enemies, NPC spells hit the player; friendly-fire excluded by construction

### NPC Systems

- **NPC definitions** -- single JSON file per NPC type, inline dialogue, stat blocks, personal inventories
- **Corpse system** -- NPCs drop lootable corpses on death, configurable decay, carriable
- **NPC movement** -- tile-based, passability-aware, synchronized with player actions
- **NPC pathfinding** -- A* with Chebyshev heuristic, configurable max path length
- **NPC scheduling** -- hour-based daily schedules, day-specific overrides, named waypoints, open activity strings
- **NPC tile registry** -- single occupant dictionary drives both passability checks and NPC lookup; no parallel structures

### Quest System

- **Quest registry** -- all quests defined in a single JSON file; loaded at startup by `QuestManager` autoload
- **Quest triggers** -- quests start via dialogue keyword, region entry, tile step, or reading a world object
- **Objective types** -- `talk`, `kill`, `reach_region`, `reach_location` (region or tile), `action` (manual/branch-resolved)
- **Prerequisites and visibility** -- objectives can require prior objectives to complete; hidden objectives reveal themselves when prerequisites are met; `initial_status` overrides computed state
- **Kill tracking** -- `any_of_group` flag matches kills by NPC id prefix; individual combatant deaths reported from `CombatManager`
- **Quest branches** -- non-linear resolution; branches can close competing branches, activate or complete objectives, and grant additional rewards; `auto_trigger` or player-initiated (via item use or dialogue delivery)
- **Item-triggered branches** -- `quest_branch_trigger` field on item data fires a branch on consume
- **Delivery via dialogue** -- NPC dialogue blocks with `quest_delivery` take items from inventory and trigger a branch or complete an objective
- **Fail conditions** -- `npc_dead` and `time_elapsed` (scheduled via `GameTime`); timed conditions cancelled on completion or manual failure
- **Rewards** -- quest-level and branch-level rewards: `experience`, `item` (inventory or ground drop on overweight), `stat` permanent increases, `class_change` (switches player class, enforces whitelist immediately)
- **Journal** -- timestamped narrative entries written on objective completion and quest resolution
- **Journal UI** -- `J` key opens a panel listing active, completed, and failed quests; cursor navigation; expand quests to see objective status; detail pane shows description and journal log

### Character Creation and Class System

- **Character creation flow** -- name entry → class selection → stat allocation, all inline in the main menu; back-navigation preserves name and class selection; save slot created only after all steps complete
- **Class registry** -- classes defined in `data/config/classes.json`; each class specifies starting stats, allocatable stat ranges, stat gains per level, and an equipment type whitelist
- **Stat allocation** -- `StatAllocator` enforces per-class min/max ranges and an optional point budget; hidden stats (karma, vision_radius, experience) excluded from the allocation screen
- **Class change** -- `class_change` quest reward type changes the player's class mid-game; incompatible equipped items force-unequipped immediately; stat values preserved; level-up gains switch to the new class's definition on the next level up
- **Class display** -- current class shown in the HUD sidebar and character panel; updates immediately on class change via signal

### Equipment and Items

- **Equipment slots** -- fully data-driven slot definitions, configurable instances per slot
- **Equip/unequip mechanics** -- from inventory screen, visual indicators, slot blocking messages
- **Equipment modifiers** -- stat modifiers applied and removed on equip/unequip
- **Equipment restrictions** -- each class defines an equipment type whitelist (`blade`, `blunt`, `cloth`, `accessory`, etc.); items with no `equipment_type` cannot be equipped; class mismatches rejected with a message; class change force-unequips incompatible items
- **Item stacking** -- carriable items stack by object_id, quantity prompts, partial pickup, stack splitting via Get/Drop/Move; objects with `stackable: false` always create separate inventory entries regardless of object_id
- **Lock system** -- `LockManager` owns all lock/unlock logic; keys open matching locks by `lock_id`/`lock_ids`; lockpicks attempt unlock via stat roll against `success_stat` and `success_threshold` with per-fail `break_chance`; class restriction enforced at use time; `unlock` spell bypasses key and roll checks; locked doors block toggle_passability; lock state persists through region transitions and save/load

### Economy and Shops

- **Currency** -- `gold` stat tracked in the stat block; no upper cap; configurable via `currency_stat_id` and `currency_display_name` in `data/config/game.json`
- **`base_price` field** on all world object definitions -- 0 means the item cannot be sold; buy price applies `ceili(base_price × shop_multiplier)`; sell price applies `floori(base_price × 0.5)`
- **Shop definitions** (`data/shops/shops.json`) -- each shop specifies a `price_multiplier` and an inventory list with per-item `stock_count`, `restock_interval` (days), and `restock_amount`; unlimited stock flagged with `stock_count: -1`
- **ShopManager** -- instantiated per shop at startup; tracks stock independently per item; per-item restock timers scheduled via `GameTime.schedule` with repeat; stock levels and restock timer remaining ticks persisted and restored across saves
- **`shop_id` field on NPCs** -- non-empty value marks the NPC as a shop operator; opening a shop requires the NPC's current schedule activity to be `"shopkeeper"`
- **ShopPanel** -- opened by talking to a shopkeeper NPC; Buy and Sell tabs navigated with Left/Right; item list shows Name, Type, Stock, and Price columns; out-of-stock items greyed and non-selectable; unlimited stock displayed as `--`; detail pane shows item description and class usability for equippable items; Enter enters quantity mode (Left/Right adjusts, Enter confirms, Escape cancels); transactions validate gold balance, carry weight, and stock level; mutual exclusion with all other panels

---

## Data-Driven Design

All game content is defined in JSON files under `res://data/`:

| Path | Contents |
|---|---|
| `data/config/game.json` | Global configuration: time, calendar, seasons, carry limits, corpse decay, NPC path length, level thresholds |
| `data/config/slots.json` | Equipment slot definitions |
| `data/config/tiles.json` | Tile type registry: passability, move-fail chance, transparency per tile type |
| `data/config/combat.json` | Combat configuration: unarmed damage, NPC turn pause, experience per kill |
| `data/config/classes.json` | Class definitions: starting stats, stat allocation ranges, stat gains per level, equipment whitelist |
| `data/config/equipment_types.json` | Equipment type registry: id to display name mappings |
| `data/objects/*.json` | WorldObject definitions |
| `data/shops/*.json` | Shop definitions: price multiplier, inventory stock, and per-item restock schedule |
| `data/npcs/*.json` | NPC definitions including dialogue, stats, inventory, schedule, group composition |
| `data/regions/*.json` | Region definitions: spawn points, waypoints, NPC placements, object placements, transitions |
| `data/stats/*.json` | Stat block definitions per entity type |
| `data/modifiers/modifiers.json` | Modifier registry |
| `data/quests/quests.json` | Quest definitions: triggers, objectives, branches, rewards, fail conditions |
| `data/player/player.json` | Starting player state: inventory |

---

## What Does Not Exist Yet

- Party system (M19)
- Virtue, reputation, and faction system (M20)
- Mouse and scroll wheel support (M21)
- Art — all visuals are placeholders (M22)
- Sound (M23)
- Authoring tools (M24)

---

## Project Status

Active development. Milestone tracking is internal. No release is planned.
