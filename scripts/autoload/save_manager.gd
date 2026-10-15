## SaveManager (Autoload)
##
## Spielstanddateien in user://saves/: Liste, Kopf lesen, Daten lesen (auch im
## Lade-Thread), schreiben (atomar, auf Wunsch im Hintergrund), löschen, Speicherplätze
## für Schnell- und Autospeichern. Den Inhalt eines Spielstands kennt SaveGame.
##
## Aufbau einer .save-Datei:
##   Zeile 1: KOENIGREICHE-SAVE 1            (Kennung + Dateiformat)
##   Zeile 2: Kopf als einzeiliges JSON      (Metadaten für die Liste)
##   Rest:    SaveCodec-JSON (UTF-8), zstd-komprimiert oder roh (Kopf: compression, payload_*)
## Geschrieben wird nach <slot>.save.tmp; die alte Datei wird zu <slot>.save.bak, dann
## wird umbenannt (auch unter Windows sicher).
extends Node

## Ein Speichervorgang ist fertig (ok = false: message nennt den Fehler)
signal save_finished(slot: String, ok: bool, message: String)
## Die Liste der Spielstände hat sich geändert (gespeichert, gelöscht)
signal saves_changed

const SAVE_DIR := "user://saves/"
const EXT := ".save"
const QUICK_SLOT := "quicksave"
const AUTO_PREFIX := "autosave_"
const MAX_NAME_LENGTH := 40

## Ordner der Spielstände (der Rauchtest nutzt einen eigenen)
var save_dir := SAVE_DIR

var _busy := false
var _task_id := -1


func is_busy() -> bool:
	return _busy


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


# ---------------------------------------------------------------------------
# Speicherplätze
# ---------------------------------------------------------------------------

func slot_path(slot: String) -> String:
	return save_dir + slot + EXT


func exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Bereinigter Dateiname aus einem Anzeigenamen ("Mein Spiel" -> "mein_spiel"). Die Namen
## der Schnell- und Autospeicherplätze sind gesperrt (Präfix "spiel_").
func slot_for_name(display_name: String) -> String:
	var s := display_name.strip_edges().to_lower()
	s = s.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("é", "e").replace("è", "e").replace("à", "a")
	s = s.replace(" ", "_")
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	out = out.left(MAX_NAME_LENGTH)
	if out.is_empty():
		out = "spiel"
	if out == QUICK_SLOT or out.begins_with(AUTO_PREFIX):
		out = "spiel_" + out
	return out


## Nächster Autospeicherplatz: ein fehlender, sonst der älteste
func next_autosave_slot() -> String:
	var n := maxi(int(DataDB.cfg("save.autosave_slots", 3)), 1)
	var oldest := ""
	var oldest_time := 9223372036854775807
	for i in range(1, n + 1):
		var slot := "%s%d" % [AUTO_PREFIX, i]
		if not exists(slot):
			return slot
		var t := FileAccess.get_modified_time(slot_path(slot))
		var h: Dictionary = read_header(slot_path(slot)).get("header", {})
		if h.has("saved_at"):
			t = int(h["saved_at"])
		if t < oldest_time:
			oldest_time = t
			oldest = slot
	return oldest


## Alle Spielstände, neueste zuerst: {"slot", "path", "header", "error" (Datei defekt),
## "reason" (nicht ladbar), "data_changed", "bytes", "backup_path" ("" = keine Sicherung)}
func list_saves() -> Array:
	var list: Array = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return list
	for f in DirAccess.get_files_at(save_dir):
		if not f.ends_with(EXT):
			continue
		var slot := f.trim_suffix(EXT)
		var path := slot_path(slot)
		var res := read_header(path)
		var header: Dictionary = res.get("header", {})
		var entry := {"slot": slot, "path": path, "header": header, "error": str(res.get("error", "")),
				"reason": "", "data_changed": false, "bytes": _file_size(path), "backup_path": ""}
		if FileAccess.file_exists(path + ".bak"):
			entry["backup_path"] = path + ".bak"
		if entry["error"] == "":
			entry["reason"] = check_compatible(header)
			entry["data_changed"] = SaveMigration.data_changed(header)
		else:
			entry["reason"] = str(entry["error"])
		list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int((a["header"] as Dictionary).get("saved_at", 0)) > int((b["header"] as Dictionary).get("saved_at", 0)))
	return list


## Neuester ladbarer Spielstand ({} = keiner)
func most_recent() -> Dictionary:
	for entry in list_saves():
		if str(entry["reason"]).is_empty():
			return entry
	return {}


func check_compatible(header: Dictionary) -> String:
	return SaveMigration.check_compatible(header)


func delete_save(slot: String) -> bool:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var ok := DirAccess.remove_absolute(path) == OK
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	saves_changed.emit()
	return ok


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := int(f.get_length())
	f.close()
	return n


# ---------------------------------------------------------------------------
# Lesen (threadfähig: keine Nodes, keine Signale)
# ---------------------------------------------------------------------------

## Nur die ersten zwei Zeilen: {"header": {...}, "error": ""}
func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"header": {}, "error": "Datei nicht lesbar"}
	var first := f.get_line()
	var second := f.get_line()
	f.close()
	if not first.begins_with(SaveMigration.MAGIC):
		return {"header": {}, "error": "Keine gültige Spielstanddatei"}
	var json := JSON.new()
	if json.parse(second) != OK or not (json.data is Dictionary):
		return {"header": {}, "error": "Kopf defekt"}
	var header: Dictionary = SaveCodec.decode(json.data)
	return {"header": header, "error": ""}


## Ganze Datei: {"header", "data", "error"}. Prüft md5, entpackt, decodiert und migriert.
func read_data(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "Spielstand nicht lesbar: %s" % path}
	var first := f.get_line()
	var second := f.get_line()
	if not first.begins_with(SaveMigration.MAGIC):
		f.close()
		return {"error": "Keine gültige Spielstanddatei"}
	var json := JSON.new()
	if json.parse(second) != OK or not (json.data is Dictionary):
		f.close()
		return {"error": "Kopf des Spielstands defekt"}
	var header: Dictionary = SaveCodec.decode(json.data)
	var reason := SaveMigration.check_compatible(header)
	if not reason.is_empty():
		f.close()
		return {"error": reason}
	var stored := f.get_buffer(int(header.get("payload_bytes", 0)))
	f.close()
	if stored.size() != int(header.get("payload_bytes", -1)):
		return {"error": "Spielstand unvollständig"}
	if _md5(stored) != str(header.get("payload_md5", "")):
		return {"error": "Spielstand beschädigt (Prüfsumme falsch)"}
	var raw := stored
	if str(header.get("compression", "none")) == "zstd":
		raw = stored.decompress(int(header.get("payload_size", 0)), FileAccess.COMPRESSION_ZSTD)
		if raw.size() != int(header.get("payload_size", -1)):
			return {"error": "Spielstand lässt sich nicht entpacken"}
	var data := SaveCodec.from_json(raw.get_string_from_utf8())
	if data.is_empty():
		return {"error": "Spielstand lässt sich nicht lesen"}
	data = SaveMigration.migrate(data, int(header.get("save_version", SaveGame.SAVE_VERSION)))
	return {"header": header, "data": data, "error": ""}


func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


# ---------------------------------------------------------------------------
# Schreiben
# ---------------------------------------------------------------------------

## Schreibt einen Spielstand (Daten aus SaveGame.collect, schon Kopien). async: Codieren,
## Packen und Schreiben im WorkerThreadPool, Ergebnis über save_finished. Gibt "" zurück,
## wenn der Vorgang gestartet (bzw. synchron erfolgreich) war, sonst den Fehler.
func write_save(slot: String, header: Dictionary, data: Dictionary, async: bool = true) -> String:
	if _busy:
		return "Es wird gerade gespeichert"
	DirAccess.make_dir_recursive_absolute(save_dir)
	_busy = true
	var compress := Settings.compress_saves
	if async:
		_task_id = WorkerThreadPool.add_task(_write_task.bind(slot, header, data, compress), false, "Spielstand speichern")
		return ""
	var err := _write_file(slot_path(slot), header, data, compress)
	_finish_write(slot, err)
	return err


func _write_task(slot: String, header: Dictionary, data: Dictionary, compress: bool) -> void:
	var err := _write_file(slot_path(slot), header, data, compress)
	_finish_write.call_deferred(slot, err)


func _finish_write(slot: String, err: String) -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_busy = false
	save_finished.emit(slot, err.is_empty(), err if not err.is_empty() else "Gespeichert")
	saves_changed.emit()


## Codieren, packen, Prüfsumme, atomar schreiben ("" = ok)
func _write_file(path: String, header: Dictionary, data: Dictionary, compress: bool) -> String:
	var raw := SaveCodec.to_json(data).to_utf8_buffer()
	var stored := raw
	var h := header.duplicate(true)
	h["compression"] = "none"
	if compress:
		stored = raw.compress(FileAccess.COMPRESSION_ZSTD)
		h["compression"] = "zstd"
	h["payload_size"] = raw.size()
	h["payload_bytes"] = stored.size()
	h["payload_md5"] = _md5(stored)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Datei nicht schreibbar (%s)" % error_string(FileAccess.get_open_error())
	f.store_string("%s %d\n" % [SaveMigration.MAGIC, SaveMigration.FORMAT_VERSION])
	f.store_string(JSON.stringify(SaveCodec.encode(h)) + "\n")
	f.store_buffer(stored)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		return "Schreibfehler (%s)" % error_string(write_err)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "Umbenennen fehlgeschlagen (%s)" % error_string(err)
	return ""


# ---------------------------------------------------------------------------
# Laden anstossen
# ---------------------------------------------------------------------------

## Kopf prüfen, Sitzung übernehmen und den Spielstand für die Spielszene vormerken.
## slot_or_path: Speicherplatz oder Pfad (z. B. eine .bak-Sicherung). "" = ok.
## Danach die Spielszene (neu) laden.
func request_load(slot_or_path: String) -> String:
	var path := slot_or_path if slot_or_path.begins_with("user://") or slot_or_path.begins_with("/") \
			else slot_path(slot_or_path)
	var res := read_header(path)
	if not str(res.get("error", "")).is_empty():
		return str(res["error"])
	var header: Dictionary = res["header"]
	var reason := check_compatible(header)
	if not reason.is_empty():
		return reason
	GameSession.apply_session(header)
	GameSession.pending_load_path = path
	GameSession.pending_load_name = str(header.get("name", ""))
	return ""
