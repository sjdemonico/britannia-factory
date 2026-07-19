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
- **Inventory** -- toggled screen, nested containers, tree navigation, weight tracking, cross-member item transfer with quantity selection and carry limit enforcement
- **Stat system** -- fully data-driven stats, derived stats, temporary modifiers, stat regeneration, equipment modifiers
- **Time system** -- action-based ticks, configurable calendar, day/night cycle, seasons
- **Rest system** -- player presses R and enters a duration in hours; `_process` advances game time at a configurable fast rate (`rest_ticks_per_second` in `time.json`); once per in-game hour `_check_rest_interrupt()` rolls a weighted chance against the current tile's `rest_interrupt_multiplier`; if it fires the rest is cancelled, a hostile group is spawned via `SpawnManager.spawn_for_rest_interrupt()`, and `CombatManager.initiate_combat_with_group()` starts the encounter; pressing Escape cancels rest cleanly
- **Light and vision** -- per-tile darkness overlay drawn in the map viewport; player vision radius stat driven by time of day (full visibility at noon, minimum at midnight); carriable light sources (torch, lantern) with finite duration, lit/extinguished toggle, and duration preserved on drop; fixed world light sources (wall sconces) illuminate independently; smooth 5-minute ambient transitions across dawn and dusk
- **Tile hazards and traps** -- `on_entry` and `continuous` hazard effects defined per tile type in `data/config/tiles.json`; `HazardProcessor` checks equipped item `hazard_immunity` arrays before applying damage or status effects to crossing party members; trap objects with `trigger_on_entry: true` execute their `use_actions` once on contact and self-destruct via `consume`
- **Save / load** -- named save slots, autosave rotation, save index with timestamps; full serialization of player stats, inventory, equipped items, active status-effect modifiers, region diffs (object and NPC state including charges, lit state, and duration), quest state, game time, and NPC party member spawn data; scheduled quest timers restored on load
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
- **SpellEffectExecutor** -- 17 effect types: `damage`, `heal`, `apply_modifier`, `dispel`, `spawn_object` (with optional duration), `transmute`, `unlock`, `teleport`, `displace`, `reveal`, `obscure`, `invisibility`, `charm`, `sleep`, `poison`, `paralyze`, `resurrect`; damage and heal driven by formula expressions over caster and target stats; stat deltas batched and applied after all effects; entity-loop mode for AE spells
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
- **Random monster spawning** -- `SpawnManager` reads a region's `spawn_config` (spawn rate, cap, and weighted NPC list) and schedules timed spawns on the viewport perimeter; spawned monsters use LOS-based pursuit with a configurable pursuit tick budget; freed on region exit, do not persist to the region cache
- **Quest-triggered NPC spawning** -- `spawn_effects` in quest definitions place named NPCs at configurable events (`quest_started`, `objective_complete`, `quest_complete`, `quest_failed`); location resolved by `fixed` tile, named `waypoint`, or `random` passable tile; spawns for the current region execute immediately, others queue until that region loads; quest spawn state persists across region transitions and save/load

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
- **Quest-triggered NPC spawning** -- `spawn_effects` array on a quest definition places named NPCs into the world at configurable trigger points; spawns persist across region transitions and survive save/load as pending fixed-tile entries
- **Rewards** -- quest-level and branch-level rewards: `experience`, `item` (inventory or ground drop on overweight), `stat` permanent increases, `class_change` (switches player class, enforces whitelist immediately), `faction_change` (modifies standing with a named faction)
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
- **Healer services** -- NPCs marked with healer flag offer paid services defined in `data/config/healer_service_types.json`; each entry specifies a label template, a `price_field` referencing the `HealerService` price property, and a `per_downed_member` flag; services with that flag generate one row per eligible downed party member with `{name}` substituted in the label; `HealerPanel` is scrollable to handle any number of rows; services are gated by the NPC's current schedule activity

### Faction System

- **`FactionManager` autoload** -- owns faction definitions, NPC membership, and standing values; loads from `data/config/factions.json`; 0–100 standing scale with five named tiers (Hostile / Unfriendly / Neutral / Friendly / Exalted); `modify_standing` clamps to scale bounds and emits `standing_changed(faction_id, old, new)`; standings serialized and restored across saves
- **Faction effects** -- faction standing gates dialogue keywords (`min_standing` entry returns alternate response and fires no hooks when threshold not met); shop buy prices multiplied by the owning faction's tier price multiplier (`price_multiplier` per tier, sell price unaffected); NPCs belonging to a faction are set hostile when standing enters the Hostile tier, and recover when it leaves; NPC death entries in `on_death_faction_changes` modify standing automatically
- **Standing change triggers** -- standing modified via `faction_change` quest reward, `modify_faction_standing` item use action, `currency_cost` dialogue keyword hook (deducts gold then fires `faction_changes` on success), and `faction_changes` arrays on dialogue keywords
- **Faction UI** -- character panel right column shows a Standing section below stats; lists all factions with non-default standing (sorted alphabetically); faction name left-justified, tier name right-justified and coloured by tier (dark red → bright green); scrollable with Up/Down when overflow; updates live via `standing_changed` signal while the panel is open; factions remain visible once modified even if standing returns to default

---

## Data-Driven Design

All game content is defined in JSON files under `res://data/`:

| Path | Contents |
|---|---|
| `data/config/game.json` | Global configuration: time, calendar, seasons, carry limits, corpse decay, NPC path length, level thresholds, tile atlas path, UI colour overrides |
| `data/config/slots.json` | Equipment slot definitions |
| `data/config/time.json` | Time configuration: ticks per hour, day length, clock format, rest speed, rest interrupt chance; per-period transition SFX and music tracks |
| `data/config/tiles.json` | Tile type registry: passability, move-fail chance, transparency, hazards, rest interrupt multiplier, atlas coordinates, footstep sound, hazard sound, and ambient loop per tile type |
| `data/config/sounds.json` | Sound event registry: 27 event IDs mapped to audio file paths; null values are silent; covers world, combat, UI, and music hooks |
| `data/config/combat.json` | Combat configuration: unarmed damage, NPC turn pause, experience per kill, reticle and frame colour overrides |
| `data/config/classes.json` | Class definitions: starting stats, stat allocation ranges, stat gains per level, equipment whitelist |
| `data/config/factions.json` | Faction definitions: standing scale, named tiers with price multipliers and tier label colours, faction-to-NPC membership |
| `data/config/healer_service_types.json` | Healer service definitions: label template (with `{name}` placeholder), price field reference, and `per_downed_member` flag; iterated by `HealerPanel` to build its service row list |
| `data/config/equipment_types.json` | Equipment type registry: id to display name mappings |
| `data/config/regions.json` | Region registry: scene path, data path, and tile dimensions for each game region |
| `data/config/npcs.json` | NPC index: flat list of all NPC IDs enumerable without filesystem scanning |
| `data/config/npc_defaults.json` | NPC behavioral field defaults and group-member schema reference |
| `data/config/spell_effect_types.json` | Spell effect type catalogue: all 17 `effect_type` IDs with their params schemas, plus `ae_shape` and `targeting_type` enumerations |
| `data/config/use_action_types.json` | Use-action type catalogue: all 14 action type IDs with their params schemas |
| `data/config/quest_condition_types.json` | Quest fail-condition and objective type schemas |
| `data/config/quest_reward_types.json` | Quest reward type schemas |
| `data/config/tile_trigger_schema.json` | Tile trigger entry structure and supported trigger type schemas |
| `data/objects/*.json` | WorldObject definitions |
| `data/shops/*.json` | Shop definitions: price multiplier, inventory stock, and per-item restock schedule |
| `data/npcs/*.json` | NPC definitions including dialogue, stats, inventory, schedule, group composition |
| `data/regions/*.json` | Region definitions: spawn points, waypoints, NPC placements, object placements, transitions, tile dimensions, region music track |
| `data/stats/player_stats.json` | Player stat block template |
| `data/stats/npc_default.json` | Default NPC stat block template |
| `data/modifiers/modifiers.json` | Modifier registry |
| `data/quests/quests.json` | Quest definitions: triggers, objectives, branches, rewards, fail conditions |
| `data/player/player.json` | Starting player state: inventory |

---

### Party System

- **Party data** -- `PartyMember` class; `PartyManager` autoload owns the ordered member list; player is always a member; up to 8 members supported; stats and inventory tracked per member
- **Party sidebar** -- live HUD sidebar shows one row per member with HP, MP, and up to 3 active detrimental status effect names; downed members rendered in grey with red border; updates on tick, stat change, and party signals
- **Party recruitment** -- NPCs with `recruitable: true` join via dialogue; dismissed via party management; max party size enforced
- **Party combat** -- all living party members enter the arena together; diamond formation placement with rotation for all four entry edges; per-member turn order; player controls each member in sequence; companion nodes placed as lightweight Node2D actors; SpellManager caster routing switches per turn; downed state (not death) when HP reaches 0; downed members block tiles, are skipped in initiative, and are ignored by enemy AI; party wipe triggers MORTIS; XP distributed to all living members; companion level-up
- **Resurrection** -- downed members restored to 1 HP with status effects cleared; triggered by `resurrect` spell, `scroll_resurrect` item, Shrine doodad, or Healer NPC service; multi-downed prompts member selection; `SpellManager._resurrect_target` carries selection into effect execution
- **Party order management** -- `O` key (world only) displays numbered current order and prompts for a new space-separated order; validates count, range, and uniqueness; updates sidebar and character panel immediately; disabled during combat
- **Cross-member inventory** -- inventory screen supports Left/Right to switch between party members; `M` key moves items to another member with optional quantity input and target-member selection; carry limit and container slot/weight limits enforced on transfer; equipped items cannot be moved

### Audio System

- **`SoundManager` autoload** — owns all audio playback; four configurable buses (Master, Music, SFX, Ambient) loaded from `audio/default_bus_layout.tres`; per-bus volume with persistence to `user://preferences.json`; bus volumes loaded from `game.json` as fallback defaults
- **Sound event registry** -- global map of event IDs to audio file paths defined in `data/config/sounds.json`; `SoundManager.play_event(id)` resolves and plays any registered event; null-path events are silent no-ops; 27 event hooks wired across world, combat, and UI systems
- **SFX** — one-shot playback via `SoundManager.play_sfx(path)` on the SFX bus; unlimited simultaneous channels; players self-destruct on finish; footstep sounds per tile type, hazard sounds per tile, NPC talk and death sounds, spell cast sounds, weapon swing and hit sounds, UI feedback sounds
- **Music priority system** — three-layer priority: combat (highest) > time-of-day > region (lowest); `SoundManager` tracks a path per layer and calls `_resolve_music()` whenever any layer changes; the highest non-empty path plays; crossfade handled by the existing `play_music()` crossfade system so the same track continues uninterrupted if it appears in multiple layers
- **Region music** — each region definition carries `music_path`; applied to the region layer on every region load (fresh and cached); null means silence on that layer
- **Time-of-day music** — each time period entry in `time.json` carries `music_path`; applied to the time layer on period change and on every region load (so initial period music is correct on game start)
- **Combat music** — `data/config/sounds.json` entry `combat_music`; applied to the combat layer when either `initiate_combat` path fires; cleared when `end_combat` fires, immediately crossfading back to the next-highest layer
- **Tile ambient loops** — each tile type carries `ambient_sound` in `tiles.json`; `SoundManager` maintains a dictionary of per-tile-type `AudioStreamPlayer` nodes so multiple ambient loops can coexist during crossfades; `on_player_tile_changed()` records the new tile type as pending; after a 3-second delay (resettable by rapid tile changes) `_switch_ambient()` crossfades out the old loop and in the new one; loops use `_crossfade_duration` seconds; returning to an already-playing tile type does not restart it; all ambient players cleared on region unload
- **Music crossfade** — `play_music()` crossfades between A/B players over `music_crossfade_duration` seconds (configurable in `game.json`); calling with the same path is a no-op; calling with an empty path stops music; in-progress crossfades are killed and reset before starting a new one

### Mouse and UI Input

- **Click-to-move** — left-click any world tile to path there; the pathfinder routes around obstacles; clicking an impassable tile snaps to the nearest passable fallback within a short search radius; Escape or any movement key cancels the active path mid-route
- **NPC mouse interaction** — first click selects an NPC (gold highlight); second click acts: adjacent hostile enters combat, far hostile paths and attacks on arrival, adjacent friendly opens dialogue, far friendly paths and talks on arrival; clicking elsewhere clears selection
- **Hover tooltips** — mousing over a world tile shows the NPC name, structural object name (with open/closed state), or terrain type; tiles outside player vision show nothing
- **Combat arena click** — left-click an enemy to attack if in weapon range, or path one step closer if not; left-click an empty arena tile to step toward it; during targeting, left-click confirms the reticle position
- **Command icon bar** — 10 clickable buttons (Talk, Look, Get, Use, Move, Attack, Cast, Rest, Save/Load, Quit) below the map viewport; clicking fires the same action as the keyboard shortcut; icons grey when the command is unavailable (cast greys with no spells or mana; most commands grey in combat)
- **Direction prompt mouse support** — active direction prompts show a yellow overlay on valid adjacent tiles and a cyan overlay on the player tile; left-click an adjacent tile to resolve the direction; left-click the player tile or anywhere else to cancel
- **Party sidebar click** — left-clicking a member row in the party sidebar opens the character panel at that member's index
- **Panel mouse navigation** — all panels (inventory, journal, spellbook, shop, healer, save/load, character) support hover-to-highlight and click-to-select; quantity fields and action menus navigable by mouse
- **Full mouse support in menus** — main menu, class selection, stat allocation, and load game all support hover and click; character creation requires no keyboard input

## What Does Not Exist Yet

- Art — all visuals are placeholders
- Authoring tools

---

## Project Status

Active development. Milestone tracking is internal. No release is planned.
