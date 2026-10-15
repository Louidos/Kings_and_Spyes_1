## Settings (Autoload)
##
## Benutzereinstellungen (nicht Teil des Spielstands). Werden in
## user://settings.cfg gespeichert und beim Start geladen. Das Formular dazu
## (SettingsForm) steht im Hauptmenü und im Spielmenü; Änderungen wirken sofort
## (apply), gespeichert wird mit "Speichern und zurück".
extends Node

signal changed

## Audio-Busse (fehlende legt _ensure_buses an, Ausgang Master)
const BUSES := ["Master", "Music", "SFX", "UI"]
## Erlaubte Abstände für das automatische Speichern (Minuten, 0 = aus)
const AUTOSAVE_STEPS := [0, 5, 10, 15, 30]

## Datei der Einstellungen (der Rauchtest setzt eine eigene, die Benutzerdatei bleibt unberührt)
var file_path := "user://settings.cfg"

## Bildschirmrand-Scrollen der Kamera
var edge_scroll: bool = true
## Faktor auf die Kamerageschwindigkeit (0.5 – 2.0)
var camera_speed: float = 1.0
var fullscreen: bool = false
## Grösse der Oberfläche (0.75 – 1.5)
var ui_scale: float = 1.0
## Tag-Nacht-Abdunklung der Karte (ab Phase 8)
var day_night_tint: bool = true
## Lautstärken 0..1 je Bus
var volume := {"Master": 0.8, "Music": 0.7, "SFX": 0.8, "UI": 0.8}
## Automatisch speichern alle so viele Minuten echter Spielzeit (0 = aus)
var autosave_minutes: int = 10
## Spielstände mit zstd komprimieren
var compress_saves: bool = true


func _ready() -> void:
	load_settings()
	apply()


## Standardwerte (Knopf "Standard")
func reset_defaults() -> void:
	edge_scroll = true
	camera_speed = 1.0
	fullscreen = false
	ui_scale = 1.0
	day_night_tint = true
	volume = {"Master": 0.8, "Music": 0.7, "SFX": 0.8, "UI": 0.8}
	autosave_minutes = 10
	compress_saves = true


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(file_path) != OK:
		return  # Noch keine Datei: Standardwerte behalten
	edge_scroll = bool(cf.get_value("camera", "edge_scroll", edge_scroll))
	camera_speed = clampf(float(cf.get_value("camera", "speed", camera_speed)), 0.5, 2.0)
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	ui_scale = clampf(float(cf.get_value("display", "ui_scale", ui_scale)), 0.75, 1.5)
	day_night_tint = bool(cf.get_value("display", "day_night_tint", day_night_tint))
	for bus in BUSES:
		volume[bus] = clampf(float(cf.get_value("audio", str(bus).to_lower(), volume.get(bus, 0.8))), 0.0, 1.0)
	autosave_minutes = maxi(int(cf.get_value("game", "autosave_minutes", autosave_minutes)), 0)
	compress_saves = bool(cf.get_value("game", "compress_saves", compress_saves))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("camera", "edge_scroll", edge_scroll)
	cf.set_value("camera", "speed", camera_speed)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "ui_scale", ui_scale)
	cf.set_value("display", "day_night_tint", day_night_tint)
	for bus in BUSES:
		cf.set_value("audio", str(bus).to_lower(), float(volume.get(bus, 0.8)))
	cf.set_value("game", "autosave_minutes", autosave_minutes)
	cf.set_value("game", "compress_saves", compress_saves)
	cf.save(file_path)


## Wendet die Einstellungen an und benachrichtigt alle Interessierten.
func apply() -> void:
	# Im Editor eingebettete Spielfenster (ab Godot 4.4) dürfen den Modus nicht wechseln.
	var embedded: bool = Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor")
	if DisplayServer.get_name() != "headless" and not embedded:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	_apply_audio()
	changed.emit()


## Lautstärke eines Busses (0..1)
func get_volume(bus: String) -> float:
	return float(volume.get(bus, 0.8))


func set_volume(bus: String, v: float) -> void:
	volume[bus] = clampf(v, 0.0, 1.0)


## Busse anlegen (falls nötig) und Lautstärken setzen – funktioniert auch ohne Audiodateien
func _apply_audio() -> void:
	_ensure_buses()
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(str(bus))
		if idx < 0:
			continue
		var v := get_volume(str(bus))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(str(bus)) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, str(bus))
		AudioServer.set_bus_send(idx, "Master")
