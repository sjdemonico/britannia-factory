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

### NPC Systems

- **NPC definitions** -- single JSON file per NPC type, inline dialogue, stat blocks, personal inventories
- **Corpse system** -- NPCs drop lootable corpses on death, configurable decay, carriable
- **NPC movement** -- tile-based, passability-aware, synchronized with player actions
- **NPC pathfinding** -- A* with Chebyshev heuristic, configurable max path length
- **NPC scheduling** -- hour-based daily schedules, day-specific overrides, named waypoints, open activity strings
- **NPC tile registry** -- single occupant dictionary drives both passability checks and NPC lookup; no parallel structures

### Equipment and Items

- **Equipment slots** -- fully data-driven slot definitions, configurable instances per slot
- **Equip/unequip mechanics** -- from inventory screen, visual indicators, slot blocking messages
- **Equipment modifiers** -- stat modifiers applied and removed on equip/unequip
- **Item stacking** -- carriable items stack by object_id, quantity prompts, partial pickup, stack splitting via Get/Drop/Move

---

## Data-Driven Design

All game content is defined in JSON files under `res://data/`:

| Path | Contents |
|---|---|
| `data/config/game.json` | Global configuration: time, calendar, seasons, carry limits, corpse decay, NPC path length, level thresholds |
| `data/config/slots.json` | Equipment slot definitions |
| `data/config/tiles.json` | Tile type registry: passability, move-fail chance, transparency per tile type |
| `data/config/combat.json` | Combat configuration: unarmed damage, NPC turn pause, experience per kill |
| `data/objects/*.json` | WorldObject definitions |
| `data/npcs/*.json` | NPC definitions including dialogue, stats, inventory, schedule, group composition |
| `data/regions/*.json` | Region definitions: spawn points, waypoints, NPC placements, object placements, transitions |
| `data/stats/*.json` | Stat block definitions per entity type |
| `data/modifiers/modifiers.json` | Modifier registry |

---

## What Does Not Exist Yet

- Save/Load
- Dungeon scenes (underground regions)
- Magic
- Shops and economy
- Quests
- Factions
- Party system
- Crafting
- Art (all visuals are placeholders)
- Mouse support

---

## Project Status

Active development. Milestone tracking is internal. No release is planned.
