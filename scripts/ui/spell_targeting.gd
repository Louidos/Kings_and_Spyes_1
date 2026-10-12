## SpellTargeting
##
## Zielmodus für Zauber: Kreis folgt der Maus, Linksklick zaubert, Rechtsklick
## oder Esc bricht ab. (Wird ausgebaut.)
class_name SpellTargeting
extends Node2D

## Zielmodus an/aus (spell_id leer = aus)
@warning_ignore("unused_signal")
signal targeting_changed(spell_id: String)

var game: Node
var spell_id := ""


func setup(p_game: Node) -> void:
	game = p_game


func is_active() -> bool:
	return not spell_id.is_empty()


func start(p_spell_id: String) -> void:
	spell_id = p_spell_id


func cancel() -> void:
	spell_id = ""
