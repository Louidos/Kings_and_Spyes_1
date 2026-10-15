## Notify (Autoload)
##
## Meldungen an den Spieler ("Bau fertig", "Hungersnot!" ...). Systeme rufen
## nur Notify.info/good/warning/danger auf; die Anzeige übernimmt das HUD.
## Optional mit Weltposition – ein Klick auf die Meldung springt dorthin –
## oder mit einem Verweis auf ein Fenster (z. B. Heldenfenster bei einer Stufenwahl).
## Alle gezeigten Meldungen landen im Protokoll (history, Taste M), das mit dem
## Spielstand gespeichert wird. Während ein Spielstand wiederhergestellt wird,
## sind Meldungen stumm (muted).
extends Node

## kind: "info", "good", "warning" oder "danger"; world_pos: Vector2, null oder
## ein Verweis {"window": "heroes", "hero_id": int, "pos": Vector2 (optional)}
signal posted(text: String, kind: String, world_pos: Variant)
## Das Protokoll hat sich geändert (neue Meldung oder geladen)
signal history_changed

## Gleiche Meldung innerhalb dieser Zeit (echte Sekunden) wird verworfen
const REPEAT_GUARD_SECONDS := 6.0
## Alle so vielen Meldungen werden alte Einträge der Wiederholungssperre gelöscht
const PRUNE_EVERY := 100

## Meldungen unterdrücken (beim Wiederherstellen eines Spielstands)
var muted := false
## Protokoll, älteste zuerst: {"t": Spielzeit, "time_text", "text", "kind", "pos": Vector2/Verweis/null}
var history: Array = []

## Text -> Zeitpunkt der letzten Anzeige (ms)
var _last_shown: Dictionary = {}
var _posts := 0


## world_pos: Vector2 (Klick springt hin), null (Klick schliesst) oder ein Verweis
## {"window": Fenstername für das HUD, weitere Schlüssel je Fenster, "pos": Vector2 optional}
func post(text: String, kind: String = "info", world_pos: Variant = null) -> void:
	if muted:
		return
	var now := Time.get_ticks_msec()
	if _last_shown.has(text) and now - int(_last_shown[text]) < REPEAT_GUARD_SECONDS * 1000.0:
		return
	_last_shown[text] = now
	_posts += 1
	if _posts % PRUNE_EVERY == 0:
		_prune(now)
	_add_history(text, kind, world_pos)
	posted.emit(text, kind, world_pos)


func info(text: String, world_pos: Variant = null) -> void:
	post(text, "info", world_pos)


func good(text: String, world_pos: Variant = null) -> void:
	post(text, "good", world_pos)


func warning(text: String, world_pos: Variant = null) -> void:
	post(text, "warning", world_pos)


func danger(text: String, world_pos: Variant = null) -> void:
	post(text, "danger", world_pos)


## Protokoll leeren (neue Partie)
func clear_history() -> void:
	history.clear()
	_last_shown.clear()
	history_changed.emit()


## Protokoll aus einem Spielstand übernehmen
func load_history(a: Array) -> void:
	history = a.duplicate(true)
	_trim()
	history_changed.emit()


func _add_history(text: String, kind: String, world_pos: Variant) -> void:
	var pos: Variant = null
	if world_pos is Vector2:
		pos = world_pos
	elif world_pos is Dictionary:
		pos = (world_pos as Dictionary).duplicate(true)
	history.append({"t": GameClock.game_time, "time_text": GameClock.get_time_string(), "text": text,
			"kind": kind, "pos": pos})
	_trim()
	history_changed.emit()


func _trim() -> void:
	var limit := maxi(int(DataDB.cfg("save.max_message_log", 300)), 1)
	if history.size() > limit:
		history = history.slice(history.size() - limit)


## Einträge der Wiederholungssperre, die älter als eine Minute sind, löschen
func _prune(now: int) -> void:
	for key in _last_shown.keys():
		if now - int(_last_shown[key]) > 60000:
			_last_shown.erase(key)
