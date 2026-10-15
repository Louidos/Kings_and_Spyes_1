## Lädt (kompiliert) alle Skripte und Szenen des Projekts einmal. Zusammen mit
## tests/check_scripts.sh werden dabei auch Warnungen als Fehler gemeldet.
## Aufruf: godot --headless res://tests/load_all.tscn
extends Node


func _ready() -> void:
	var files: Array = []
	_collect("res://scripts", ".gd", files)
	_collect("res://tests", ".gd", files)
	_collect("res://scenes", ".tscn", files)
	var failed := 0
	for path in files:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			failed += 1
			print("[load_all] FEHLER: ", path)
		elif res is GDScript and not (res as GDScript).can_instantiate():
			failed += 1
			print("[load_all] FEHLER (nicht kompilierbar): ", path)
	print("[load_all] %d Dateien geprüft, %d Fehler" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir_path: String, ext: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), ext, out)
	for f in dir.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
