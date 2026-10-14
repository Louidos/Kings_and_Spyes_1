## SaveMigration
##
## Prüft, ob ein Spielstand zu dieser Spielversion passt, und hebt ältere
## Spielstände Schritt für Schritt auf den aktuellen Stand (SaveGame.SAVE_VERSION).
## Regel: Ein Feld wird umbenannt oder umgedeutet → SAVE_VERSION + 1 und ein Schritt
## _vN_to_vN+1 hier. Neue Felder brauchen keinen Schritt (from_dict nimmt Standardwerte).
## Ergibt der Weltgenerator mit gleichem Seed eine andere Welt → WorldGenerator.VERSION + 1.
class_name SaveMigration
extends RefCounted

## Erste Zeile jeder Spielstanddatei
const MAGIC := "KOENIGREICHE-SAVE"
const FORMAT := "koenigreiche-save"
const FORMAT_VERSION := 1


## "" = ladbar, sonst der Grund (für die Liste)
static func check_compatible(header: Dictionary) -> String:
	if str(header.get("format", "")) != FORMAT or int(header.get("format_version", 0)) != FORMAT_VERSION:
		return "Keine gültige Spielstanddatei"
	if int(header.get("save_version", 0)) > SaveGame.SAVE_VERSION:
		return "Spielstand aus einer neueren Version (%s)" % str(header.get("game_version", "?"))
	if int(header.get("generator_version", 0)) != WorldGenerator.VERSION:
		return "Weltgenerator geändert – Spielstand nicht mehr ladbar"
	if DataDB.get_faction(str(header.get("faction_id", ""))).is_empty():
		return "Unbekannte Fraktion: %s" % str(header.get("faction_id", ""))
	return ""


## Wurden die Spieldaten seit dem Speichern geändert? (kein Fehler, nur ein Hinweis)
static func data_changed(header: Dictionary) -> bool:
	return str(header.get("data_fingerprint", "")) != DataDB.data_fingerprint


## Daten von from_version auf SaveGame.SAVE_VERSION heben (läuft im Lade-Thread)
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data
	var v := from_version
	while v < SaveGame.SAVE_VERSION:
		match v:
			# Beispiel für spätere Versionen: 1: d = _v1_to_v2(d)
			_:
				pass
		v += 1
	return d
