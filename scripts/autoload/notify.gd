## Notify (Autoload)
##
## Meldungen an den Spieler ("Bau fertig", "Hungersnot!" ...). Systeme rufen
## nur Notify.info/good/warning/danger auf; die Anzeige übernimmt das HUD.
## Optional mit Weltposition – ein Klick auf die Meldung springt dorthin –
## oder mit einem Verweis auf ein Fenster (z. B. Heldenfenster bei einer Stufenwahl).
extends Node

## kind: "info", "good", "warning" oder "danger"; world_pos: Vector2, null oder
## ein Verweis {"window": "heroes", "hero_id": int, "pos": Vector2 (optional)}
signal posted(text: String, kind: String, world_pos: Variant)

## Gleiche Meldung innerhalb dieser Zeit (echte Sekunden) wird verworfen
const REPEAT_GUARD_SECONDS := 6.0

## Text -> Zeitpunkt der letzten Anzeige (ms)
var _last_shown: Dictionary = {}


## world_pos: Vector2 (Klick springt hin), null (Klick schliesst) oder ein Verweis
## {"window": Fenstername für das HUD, weitere Schlüssel je Fenster, "pos": Vector2 optional}
func post(text: String, kind: String = "info", world_pos: Variant = null) -> void:
	var now := Time.get_ticks_msec()
	if _last_shown.has(text) and now - int(_last_shown[text]) < REPEAT_GUARD_SECONDS * 1000.0:
		return
	_last_shown[text] = now
	posted.emit(text, kind, world_pos)


func info(text: String, world_pos: Variant = null) -> void:
	post(text, "info", world_pos)


func good(text: String, world_pos: Variant = null) -> void:
	post(text, "good", world_pos)


func warning(text: String, world_pos: Variant = null) -> void:
	post(text, "warning", world_pos)


func danger(text: String, world_pos: Variant = null) -> void:
	post(text, "danger", world_pos)
