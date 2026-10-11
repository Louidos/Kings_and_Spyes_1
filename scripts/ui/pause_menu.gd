## PauseMenu
##
## Spielmenü (Esc): Fortsetzen, zurück zum Hauptmenü, Beenden.
## Speichern/Laden folgt in Phase 10.
extends CanvasLayer

signal closed

@onready var info_label: Label = %InfoLabel
@onready var resume_button: Button = %ResumeButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var quit_button: Button = %QuitButton

var is_open: bool = false


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(close)
	main_menu_button.pressed.connect(_on_main_menu)
	quit_button.pressed.connect(func() -> void: get_tree().quit())


func open() -> void:
	is_open = true
	visible = true
	var faction := GameSession.get_faction()
	var diff := GameSession.get_difficulty()
	var map_size := DataDB.get_map_size(GameSession.map_size_id)
	info_label.text = "Fraktion: %s\nSchwierigkeit: %s\nKarte: %s\nSeed: %s\n%s" % [
		faction.get("name", "?"), diff.get("name", "?"), map_size.get("name", "?"),
		GameSession.seed_text, GameClock.get_time_string()]
	resume_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("game_menu"):
		get_viewport().set_input_as_handled()
		close()


func _on_main_menu() -> void:
	GameClock.stop()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
