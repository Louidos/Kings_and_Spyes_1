## Settings (Autoload)
##
## Benutzereinstellungen (nicht Teil des Spielstands). Werden in
## user://settings.cfg gespeichert und beim Start geladen (fehlende Schlüssel älterer
## Dateien behalten ihren Standardwert). Das Formular dazu (SettingsForm, Reiter Grafik ·
## Ton · Steuerung · Oberfläche · Spiel) steht im Hauptmenü und im Spielmenü; Änderungen
## wirken sofort (apply), gespeichert wird mit "Speichern und zurück". Ausnahme: die
## Tooltip-Verzögerung liest Godot nur beim Start – sie steht zusätzlich in
## user://project_override.cfg (project.godot → application/config/project_settings_override)
## und gilt ab dem nächsten Start.
extends Node

signal changed

## Audio-Busse (fehlende legt _ensure_buses an, Ausgang Master)
const BUSES := ["Master", "Music", "SFX", "UI"]
## Erlaubte Abstände für das automatische Speichern (Minuten, 0 = aus)
const AUTOSAVE_STEPS := [0, 5, 10, 15, 30]
## Bildrate-Grenzen (0 = unbegrenzt)
const FPS_STEPS := [30, 60, 120, 0]
## Lebensbalken über Einheiten und Gebäuden: immer, nur verletzte (und ausgewählte), nur ausgewählte
const HP_BAR_MODES := ["always", "damaged", "selected"]
const HP_BAR_NAMES := {"always": "immer", "damaged": "nur verletzt oder ausgewählt", "selected": "nur ausgewählt"}
## Anzeigedauer der Meldungen (Sekunden)
const NOTIFY_STEPS := [4.0, 6.0, 8.0, 12.0, 20.0]
## Datei mit Projekteinstellungen, die Godot beim Start liest (Tooltip-Verzögerung)
const OVERRIDE_PATH := "user://project_override.cfg"

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
## Vertikale Synchronisation
var vsync: bool = true
## Höchste Bildrate (0 = unbegrenzt)
var max_fps: int = 0
## Faktor auf das Zoomtempo (Mausrad, Q/E; 0.5 – 2.0)
var zoom_speed: float = 1.0
## Faktor auf das Tempo am Bildschirmrand (0.5 – 2.0), getrennt vom Kamera-Tempo der Tasten
var edge_scroll_speed: float = 1.0
## Lebensbalken: "always", "damaged" (Standard: verletzt oder ausgewählt), "selected"
var hp_bars: String = "damaged"
## Wie lange eine Meldung sichtbar bleibt (Sekunden, echte Zeit)
var notify_seconds: float = 8.0
## Grösse der Minikarte (Faktor 0.75 – 1.5)
var minimap_scale: float = 1.0
## Tempo zu Beginn einer neuen Partie (Index in GameClock.speed_steps, -1 = Standard aus game_config.json)
var start_speed_index: int = -1
## Rückfrage vor einer Kriegserklärung (zweiter Klick); aus = sofort
var confirm_war: bool = true
## Verzögerung, bis ein Tooltip erscheint (Sekunden; gilt ab dem nächsten Start)
var tooltip_delay: float = 0.5


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
	vsync = true
	max_fps = 0
	zoom_speed = 1.0
	edge_scroll_speed = 1.0
	hp_bars = "damaged"
	notify_seconds = 8.0
	minimap_scale = 1.0
	start_speed_index = -1
	confirm_war = true
	tooltip_delay = 0.5


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
	# Ab 1.3 (ältere Dateien haben die Schlüssel nicht: Standardwerte bleiben)
	vsync = bool(cf.get_value("display", "vsync", vsync))
	max_fps = int(cf.get_value("display", "max_fps", max_fps))
	if not FPS_STEPS.has(max_fps):
		max_fps = 0
	zoom_speed = clampf(float(cf.get_value("camera", "zoom_speed", zoom_speed)), 0.5, 2.0)
	edge_scroll_speed = clampf(float(cf.get_value("camera", "edge_speed", edge_scroll_speed)), 0.5, 2.0)
	hp_bars = str(cf.get_value("interface", "hp_bars", hp_bars))
	if not HP_BAR_MODES.has(hp_bars):
		hp_bars = "damaged"
	notify_seconds = clampf(float(cf.get_value("interface", "notify_seconds", notify_seconds)), 2.0, 60.0)
	minimap_scale = clampf(float(cf.get_value("interface", "minimap_scale", minimap_scale)), 0.75, 1.5)
	start_speed_index = int(cf.get_value("game", "start_speed_index", start_speed_index))
	confirm_war = bool(cf.get_value("game", "confirm_war", confirm_war))
	tooltip_delay = clampf(float(cf.get_value("game", "tooltip_delay", tooltip_delay)), 0.0, 2.0)


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
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "max_fps", max_fps)
	cf.set_value("camera", "zoom_speed", zoom_speed)
	cf.set_value("camera", "edge_speed", edge_scroll_speed)
	cf.set_value("interface", "hp_bars", hp_bars)
	cf.set_value("interface", "notify_seconds", notify_seconds)
	cf.set_value("interface", "minimap_scale", minimap_scale)
	cf.set_value("game", "start_speed_index", start_speed_index)
	cf.set_value("game", "confirm_war", confirm_war)
	cf.set_value("game", "tooltip_delay", tooltip_delay)
	cf.save(file_path)
	_save_override()


## Tooltip-Verzögerung für den nächsten Start (Godot liest sie nur beim Erzeugen des Fensters)
func _save_override() -> void:
	if file_path != "user://settings.cfg":
		return  # Rauchtest mit eigener Datei: die Datei des Benutzers bleibt unberührt
	var cf := ConfigFile.new()
	cf.set_value("gui", "timers/tooltip_delay_sec", tooltip_delay)
	cf.save(OVERRIDE_PATH)


## Tempo zu Beginn einer neuen Partie (Index in speed_steps; Standard aus game_config.json)
func get_start_speed_index(default_index: int, step_count: int) -> int:
	if start_speed_index < 0:
		return clampi(default_index, 0, maxi(step_count - 1, 0))
	return clampi(start_speed_index, 0, maxi(step_count - 1, 0))


## Alle Werte als Dictionary (Rauchtest: Vergleich mit den Standardwerten)
func values() -> Dictionary:
	return {"edge_scroll": edge_scroll, "camera_speed": camera_speed, "fullscreen": fullscreen, "ui_scale": ui_scale,
			"day_night_tint": day_night_tint, "volume": volume.duplicate(), "autosave_minutes": autosave_minutes,
			"compress_saves": compress_saves, "vsync": vsync, "max_fps": max_fps, "zoom_speed": zoom_speed,
			"edge_scroll_speed": edge_scroll_speed, "hp_bars": hp_bars, "notify_seconds": notify_seconds,
			"minimap_scale": minimap_scale, "start_speed_index": start_speed_index, "confirm_war": confirm_war,
			"tooltip_delay": tooltip_delay}


## Wird ein Lebensbalken gezeigt? (Einheiten und Gebäude)
func shows_hp_bar(damaged: bool, selected: bool) -> bool:
	match hp_bars:
		"always":
			return true
		"selected":
			return selected
	return damaged or selected


## Wendet die Einstellungen an und benachrichtigt alle Interessierten.
func apply() -> void:
	# Im Editor eingebettete Spielfenster (ab Godot 4.4) dürfen den Modus nicht wechseln.
	var embedded: bool = Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor")
	if DisplayServer.get_name() != "headless" and not embedded:
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		var vs := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != vs:
			DisplayServer.window_set_vsync_mode(vs)
	Engine.max_fps = max_fps
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
