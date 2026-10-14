## Settings (Autoload)
##
## Benutzereinstellungen (nicht Teil des Spielstands). Werden in
## user://settings.cfg gespeichert und beim Start geladen.
extends Node

signal changed

const FILE_PATH := "user://settings.cfg"

## Bildschirmrand-Scrollen der Kamera
var edge_scroll: bool = true
## Faktor auf die Kamerageschwindigkeit (0.5 – 2.0)
var camera_speed: float = 1.0
var fullscreen: bool = false
## Welt bei Nacht und in der Dämmerung abdunkeln (Phase 8)
var day_night_tint: bool = true


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(FILE_PATH) != OK:
		return  # Noch keine Datei: Standardwerte behalten
	edge_scroll = cf.get_value("camera", "edge_scroll", edge_scroll)
	camera_speed = cf.get_value("camera", "speed", camera_speed)
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	day_night_tint = cf.get_value("display", "day_night_tint", day_night_tint)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("camera", "edge_scroll", edge_scroll)
	cf.set_value("camera", "speed", camera_speed)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "day_night_tint", day_night_tint)
	cf.save(FILE_PATH)


## Wendet die Einstellungen an und benachrichtigt alle Interessierten.
func apply() -> void:
	# Im Editor eingebettete Spielfenster (ab Godot 4.4) dürfen den Modus nicht wechseln.
	var embedded: bool = Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor")
	if DisplayServer.get_name() != "headless" and not embedded:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()
