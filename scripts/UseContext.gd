class_name UseContext
extends RefCounted

var actor: Node
var target: Variant    # WorldObject for world use; inventory item Dictionary for inventory use
var inventory: Node    # null for world use; PlayerInventory autoload for inventory use
