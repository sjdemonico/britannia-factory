class_name RegionDiff
extends RefCounted

var region_id: String = ""
var added: Array = []    # objects present at runtime but not in the JSON baseline
var modified: Array = [] # objects present in both with at least one changed field
var removed: Array = []  # instance_ids of baseline objects absent from the runtime scene
var npc_states: Array = [] # {npc_id, removed: true} for each killed/despawned NPC

func to_dict() -> Dictionary:
	return {
		"region_id": region_id,
		"added":      added.duplicate(true),
		"modified":   modified.duplicate(true),
		"removed":    removed.duplicate(),
		"npc_states": npc_states.duplicate(true)
	}

func from_dict(data: Dictionary) -> void:
	region_id  = str(data.get("region_id", ""))
	added      = data.get("added",      []).duplicate(true)
	modified   = data.get("modified",   []).duplicate(true)
	removed    = data.get("removed",    []).duplicate()
	npc_states = data.get("npc_states", []).duplicate(true)
