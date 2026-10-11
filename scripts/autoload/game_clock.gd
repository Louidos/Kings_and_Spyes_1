## GameClock (Autoload)
##
## Zentrale Spielzeit: Pause, Spieltempo (0.5x, 1x, 2x, 3x), Tag und Uhrzeit.
##
## Wichtig für alle Spielsysteme:
## - Nichts in der Spielwelt nutzt das rohe `delta` aus `_process`, sondern
##   `GameClock.frame_delta` (bereits mit Tempo multipliziert, 0 bei Pause).
## - Logik, die nicht jeden Frame laufen muss (Wirtschaft, KI, Zufriedenheit ...),
##   hängt sich an das Signal `sim_tick`. Das läuft mit fester Rate in Spielzeit
##   und ist damit unabhängig von der Bildrate.
## - Kamera und Benutzeroberfläche laufen immer in Echtzeit weiter.
extends Node

## Pause oder Tempo hat sich geändert.
signal speed_changed(paused: bool, speed: float)
## Fester Simulationsschritt. `dt` ist in Spielsekunden.
signal sim_tick(dt: float)
## Eine volle Spielstunde ist vergangen (für Tag/Nacht, Ereignisse ...).
signal hour_passed(day: int, hour: int)
## Ein neuer Spieltag hat begonnen.
signal day_passed(day: int)

var speed_steps: Array = [0.5, 1.0, 2.0, 3.0]
var speed_index: int = 1
var paused: bool = false
## Läuft gerade eine Partie? (Im Hauptmenü steht die Uhr.)
var running: bool = false
## Vergangene Spielsekunden seit Beginn der Partie
var game_time: float = 0.0
## Mit Tempo skaliertes Delta des aktuellen Frames (0 bei Pause)
var frame_delta: float = 0.0

var seconds_per_day: float = 600.0
var start_hour: float = 8.0
var sim_tick_interval: float = 0.1
## Schutz gegen Ruckel-Spiralen: höchstens so viele Ticks pro Frame
var max_ticks_per_frame: int = 12

var _tick_accumulator: float = 0.0
var _last_total_hours: int = 0


func _ready() -> void:
	# Die Uhr muss vor allen Spielobjekten aktualisiert werden.
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	seconds_per_day = float(DataDB.cfg("time.seconds_per_day", seconds_per_day))
	start_hour = float(DataDB.cfg("time.start_hour", start_hour))
	sim_tick_interval = 1.0 / maxf(float(DataDB.cfg("time.sim_ticks_per_second", 10)), 1.0)
	speed_steps = DataDB.cfg("time.speed_steps", speed_steps)


## Setzt die Uhr für eine neue Partie zurück und startet sie.
func start_new_game() -> void:
	game_time = 0.0
	_tick_accumulator = 0.0
	_last_total_hours = _total_hours()
	speed_index = clampi(int(DataDB.cfg("time.default_speed_index", 1)), 0, speed_steps.size() - 1)
	paused = false
	running = true
	speed_changed.emit(paused, get_speed())


func stop() -> void:
	running = false
	frame_delta = 0.0


func _process(delta: float) -> void:
	frame_delta = 0.0
	if not running or paused:
		return
	var gd := delta * get_speed()
	frame_delta = gd
	game_time += gd

	# Feste Simulationsschritte
	_tick_accumulator += gd
	var ticks := 0
	while _tick_accumulator >= sim_tick_interval and ticks < max_ticks_per_frame:
		_tick_accumulator -= sim_tick_interval
		ticks += 1
		sim_tick.emit(sim_tick_interval)
	if ticks >= max_ticks_per_frame:
		_tick_accumulator = 0.0  # Rückstand verwerfen statt hinterherzulaufen

	# Stunden- und Tageswechsel melden
	var hours := _total_hours()
	while _last_total_hours < hours:
		_last_total_hours += 1
		var hour := _last_total_hours % 24
		var day := int(_last_total_hours / 24.0) + 1
		hour_passed.emit(day, hour)
		if hour == 0:
			day_passed.emit(day)


# ---------------------------------------------------------------------------
# Tempo und Pause
# ---------------------------------------------------------------------------

func get_speed() -> float:
	return float(speed_steps[speed_index])


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, speed_steps.size() - 1)
	paused = false
	speed_changed.emit(paused, get_speed())


func faster() -> void:
	set_speed_index(speed_index + 1)


func slower() -> void:
	set_speed_index(speed_index - 1)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	speed_changed.emit(paused, get_speed())


func toggle_pause() -> void:
	set_paused(not paused)


# ---------------------------------------------------------------------------
# Kalender
# ---------------------------------------------------------------------------

## Aktueller Spieltag (beginnt bei 1)
func get_day() -> int:
	return int(_total_hours() / 24.0) + 1


## Uhrzeit als Kommazahl 0.0 – 24.0
func get_hour_float() -> float:
	return fmod(start_hour + game_time / seconds_per_day * 24.0, 24.0)


## Fortschritt im Tag 0.0 – 1.0 (0.5 = Mittag); nützlich für Tag/Nacht ab Phase 8
func get_day_fraction() -> float:
	return get_hour_float() / 24.0


func get_time_string() -> String:
	var h := get_hour_float()
	var minutes := int(h * 60.0) % 60
	return "Tag %d  ·  %02d:%02d" % [get_day(), int(h), minutes]


func _total_hours() -> int:
	return int(floor(start_hour + game_time / seconds_per_day * 24.0))


# ---------------------------------------------------------------------------
# Speichern / Laden (wird in Phase 10 vom Speichersystem genutzt)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"game_time": game_time, "speed_index": speed_index, "paused": paused}


func from_dict(d: Dictionary) -> void:
	game_time = float(d.get("game_time", 0.0))
	speed_index = clampi(int(d.get("speed_index", 1)), 0, speed_steps.size() - 1)
	paused = bool(d.get("paused", false))
	_tick_accumulator = 0.0
	_last_total_hours = _total_hours()
	speed_changed.emit(paused, get_speed())
