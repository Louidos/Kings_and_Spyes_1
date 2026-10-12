## CombatEffects
##
## Kampfeffekte in der Spielwelt (reine Darstellung): Geschosse, Treffer,
## Gefallene, Sammelpunkt-Fahne und Befehlsmarkierungen. (Wird ausgebaut.)
class_name CombatEffects
extends Node2D

var game: Node


func setup(p_game: Node) -> void:
	game = p_game
