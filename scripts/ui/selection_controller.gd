## SelectionController
##
## Auswahl per Linksklick in der Spielwelt: zuerst eine Einheit nahe der Maus,
## sonst das Gebäude auf der Kachel; Klick ins Leere hebt die Auswahl auf
## (ebenso Esc). Die Auswahl ist eine Liste – in Phase 2 mit höchstens einem
## Eintrag, ab Phase 3 kommt die Rahmenauswahl für Armeen dazu. Rechtsklick
## bleibt für Befehle (Phase 3) frei.
class_name SelectionController
extends Node

## Neue Auswahl (Liste aus Building/Unit, evtl. leer)
signal selection_changed(objs: Array)

## Klickradius für Einheiten in Bildschirmpixeln
const UNIT_PICK_RADIUS := 20.0

var game: Node
var selected: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	game.unit_system.unit_removed.connect(_on_object_removed)
	game.building_system.building_removed.connect(_on_object_removed)


## Erstes ausgewähltes Objekt oder null
func get_primary() -> Object:
	return selected[0] if not selected.is_empty() else null


func select(objs: Array, additive: bool = false) -> void:
	var new_list: Array = selected.duplicate() if additive else []
	for o in objs:
		if is_instance_valid(o) and not new_list.has(o):
			new_list.append(o)
	for o in selected:
		if is_instance_valid(o) and not new_list.has(o):
			o.selected = false
	for o in new_list:
		o.selected = true
	selected = new_list
	selection_changed.emit(selected)


func clear() -> void:
	if not selected.is_empty():
		select([])


func _on_object_removed(obj: Object) -> void:
	if selected.has(obj):
		selected.erase(obj)
		selection_changed.emit(selected)


func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.placement.is_active():
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos: Vector2 = game.world_map.get_global_mouse_position()
	var radius := UNIT_PICK_RADIUS / maxf(game.camera.zoom.x, 0.25)
	var u: Unit = game.unit_system.get_unit_at(pos, radius)
	if u != null:
		select([u], mb.shift_pressed)
	else:
		var b: Building = game.building_system.get_building_at(game.world.world_to_cell(pos))
		if b != null:
			select([b], mb.shift_pressed)
		elif not mb.shift_pressed:
			clear()
	get_viewport().set_input_as_handled()
