## Building
##
## Ein Gebäude oder eine Baustelle auf der Karte. Die Werte stammen aus
## buildings.json (def). Die Node liegt in der y-sortierten Ebene "Entities";
## ihre Position ist die Mitte der Grundfläche.
## Spiellogik (Platzieren, Bauen, Produktion) steckt im BuildingSystem –
## hier liegen nur der Zustand und die Darstellung.
class_name Building
extends Node2D

## Wird genau einmal ausgelöst, wenn der Bau fertig ist.
signal finished(building: Building)

## Eindeutige Nummer innerhalb der Partie (für Spielstände und Reihenfolgen)
var uid: int = 0
var def: Dictionary = {}
var kingdom: Kingdom
## Obere linke Kachel der Grundfläche
var cell := Vector2i.ZERO
var size := Vector2i(2, 2)
var constructed := false
## Geleistete Bauarbeit in Sekunden
var progress := 0.0
## Zugeteilte Einheiten (Berufe vom Typ "building")
var workers: Array = []
## Ertragsfaktor durch das Gelände unter dem Gebäude (biome_efficiency)
var biome_efficiency := 1.0
var selected := false:
	set(value):
		selected = value
		queue_redraw()

# --- Kampf und Beschwörung (Phase 3) ---
var hp := 1.0
var max_hp := 1.0
## Spielzeit des letzten erlittenen Schadens
var last_damaged_at := -1000.0
## Beschwörungen in Arbeit: Array von {"type_id", "progress", "time", "cost"}
var summon_queue: Array = []
## Sammelpunkt für neu beschworene Einheiten (Weltpixel)
var rally_point := Vector2.ZERO
var has_rally := false
## Anzahl bisher beschworener Einheiten (für ihre Aufstellung)
var summon_count := 0
## Kurzes Aufblitzen nach einem Treffer (Echtzeit-Sekunden)
var hit_flash := 0.0
## Faktor auf die Beute (Monsterhöhlen: stärkere Lager geben mehr)
var loot_factor := 1.0
## Zusätzlicher Zustand einzelner Systeme, der gespeichert werden muss
## (z. B. Monsterhöhle: {"kinds", "size", "respawn", "last_fight"})
var extra: Dictionary = {}

var _tile_size := 64
var _world: WorldData
var _texture: Texture2D


func setup(p_def: Dictionary, p_kingdom: Kingdom, p_cell: Vector2i, world: WorldData, p_uid: int) -> void:
	def = p_def
	kingdom = p_kingdom
	cell = p_cell
	uid = p_uid
	size = def.get("size", Vector2i(2, 2))
	_world = world
	_tile_size = world.tile_size
	name = "%s_%d_%d" % [def.get("id", "building"), cell.x, cell.y]
	position = get_center()
	_texture = Assets.texture(DataDB.get_building_sprite(def, kingdom.faction_id))
	max_hp = maxf(float(def.get("hp", 300.0)) * kingdom.mod("building_hp"), 1.0)
	hp = max_hp
	set_process(false)
	queue_redraw()


func get_footprint() -> Rect2i:
	return Rect2i(cell, size)


## Mitte der Grundfläche in Weltpixeln
func get_center() -> Vector2:
	return (Vector2(cell) + Vector2(size) * 0.5) * _tile_size


## Blockiert das Gebäude die Bewegung? (Strassen nicht, ab Phase 9 Tore)
func blocks_movement() -> bool:
	return bool(def.get("blocks_movement", true))


## Mitte der freien Nachbarkachel, die from_pos am nächsten liegt (dorthin
## laufen Einheiten zum Abliefern, Bauen und Arbeiten).
func get_approach_point(from_pos: Vector2) -> Vector2:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var ring := Rect2i(cell - Vector2i.ONE, size + Vector2i(2, 2))
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var c := Vector2i(x, y)
			if get_footprint().has_point(c) or not _world.in_bounds(c):
				continue
			var other: Object = _world.get_building_at(c)
			if other != null and other.blocks_movement():
				continue
			var d := _world.cell_to_world(c).distance_squared_to(from_pos)
			if d < best_d:
				best_d = d
				best = c
	if best.x >= 0:
		return _world.cell_to_world(best)
	return _edge_point(from_pos)


## Notlösung, wenn rundum alles verbaut ist: Punkt knapp am Rand
func _edge_point(from_pos: Vector2) -> Vector2:
	var rect := Rect2(Vector2(cell) * _tile_size, Vector2(size) * _tile_size).grow(_tile_size * 0.3)
	var p := Vector2(clampf(from_pos.x, rect.position.x, rect.end.x), clampf(from_pos.y, rect.position.y, rect.end.y))
	if rect.has_point(from_pos):
		# Von innen: zur nächsten Kante schieben
		var to_left := from_pos.x - rect.position.x
		var to_right := rect.end.x - from_pos.x
		var to_top := from_pos.y - rect.position.y
		var to_bottom := rect.end.y - from_pos.y
		var m := minf(minf(to_left, to_right), minf(to_top, to_bottom))
		if m == to_left:
			p.x = rect.position.x
		elif m == to_right:
			p.x = rect.end.x
		elif m == to_top:
			p.y = rect.position.y
		else:
			p.y = rect.end.y
	return p


func get_build_time() -> float:
	return maxf(float(def.get("build_time", 1.0)), 0.01)


func get_progress_ratio() -> float:
	return 1.0 if constructed else clampf(progress / get_build_time(), 0.0, 1.0)


## Fügt Bauarbeit hinzu. Gibt true zurück, wenn der Bau dadurch fertig wurde.
func add_work(amount: float) -> bool:
	if constructed:
		return false
	progress += amount
	queue_redraw()
	if progress >= get_build_time():
		complete()
		return true
	return false


## Schliesst den Bau sofort ab.
func complete() -> void:
	if constructed:
		return
	constructed = true
	progress = get_build_time()
	queue_redraw()
	finished.emit(self)


## Nimmt dieses (fertige) Gebäude die Ressource an?
func accepts(res_id: String) -> bool:
	return constructed and def.get("dropoff", []).has(res_id)


func get_gather_radius() -> int:
	return int(def.get("gather_radius", 0))


func get_gather_bonus() -> float:
	return float(def.get("gather_bonus", 0.0))


func get_worker_slots() -> int:
	return int(def.get("workers", 0))


func has_free_slot() -> bool:
	return constructed and workers.size() < get_worker_slots()


func get_display_name() -> String:
	return DataDB.get_building_name(def, kingdom.faction_id if kingdom != null else "")


func is_alive() -> bool:
	return hp > 0.0


## Halbe Kantenlänge in Pixeln (für Reichweiten im Kampf)
func get_radius() -> float:
	return minf(size.x, size.y) * _tile_size * 0.5


## Beute für den Zerstörer (Ressource -> Menge)
func get_loot() -> Dictionary:
	var loot := {}
	var base: Dictionary = def.get("loot", {})
	for res_id in base:
		loot[res_id] = roundf(float(base[res_id]) * loot_factor)
	return loot


## Einheitenstufen, die hier beschworen werden können (nur fertige Gebäude)
func get_summon_tiers() -> Array:
	return def.get("summons", []) if constructed else []


## Kurzer Zustandstext für Auswahl und Tooltip
func get_status_text() -> String:
	if not constructed:
		return "Im Bau: %d %%" % roundi(get_progress_ratio() * 100.0)
	var parts: PackedStringArray = []
	if get_worker_slots() > 0:
		parts.append("Arbeiter: %d/%d" % [workers.size(), get_worker_slots()])
	if int(def.get("housing", 0)) > 0:
		parts.append("Wohnraum: %d" % int(def["housing"]))
	return "Fertig" if parts.is_empty() else "  ·  ".join(parts)


func _draw() -> void:
	var px := Vector2(size) * _tile_size
	var rect := Rect2(-px * 0.5, px)
	var tint := Color.WHITE if constructed else Color(1, 1, 1, 0.55)
	SpriteDraw.draw_entity(self, _texture, rect, def.get("color", Color.GRAY), str(def.get("label", "")), "rect", tint)
	if not constructed:
		# Baugerüst andeuten und Fortschritt zeigen
		var scaffold := Color(0.45, 0.32, 0.18, 0.9)
		var step := px.x / 4.0
		for i in 5:
			var x := rect.position.x + i * step
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), scaffold, 2.0)
		draw_line(rect.position, rect.end, scaffold, 2.0)
		draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), scaffold, 2.0)
		SpriteDraw.draw_bar(self, Rect2(rect.position.x + 6, rect.end.y - 14, px.x - 12, 8),
				get_progress_ratio(), Color(0.95, 0.8, 0.3))
	if hit_flash > 0.0:
		draw_rect(rect, Color(1, 0.3, 0.2, 0.35), true)
	if constructed and (hp < max_hp or selected):
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var bar_color := Color(0.3, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.2) if ratio > 0.25 else Color(0.95, 0.25, 0.2))
		SpriteDraw.draw_bar(self, Rect2(rect.position.x + 6, rect.position.y - 12, px.x - 12, 7), ratio, bar_color)
	if not summon_queue.is_empty():
		# Fortschritt der laufenden Beschwörung
		var first: Dictionary = summon_queue[0]
		var r := clampf(float(first.get("progress", 0.0)) / maxf(float(first.get("time", 1.0)), 0.01), 0.0, 1.0)
		SpriteDraw.draw_bar(self, Rect2(rect.position.x + 6, rect.end.y - 12, px.x - 12, 6), r, Color(0.6, 0.5, 1.0))
	if selected:
		draw_rect(rect.grow(3.0), Color(1, 1, 0.6, 0.95), false, 3.0)


## Kurz aufblitzen lassen (nach einem Treffer)
func flash() -> void:
	hit_flash = 0.15
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if hit_flash > 0.0:
		hit_flash -= delta
		if hit_flash <= 0.0:
			set_process(false)
			queue_redraw()
