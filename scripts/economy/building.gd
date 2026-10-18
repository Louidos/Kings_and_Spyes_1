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
## Ein Ausbau ist fertig (level ist schon die neue Stufe)
signal upgraded(building: Building)

## Eindeutige Nummer innerhalb der Partie (für Spielstände und Reihenfolgen)
var uid: int = 0
## Werte der aktuellen Stufe (DataDB.get_building_at_level; Stufe 1 = buildings.json)
var def: Dictionary = {}
## Ausbaustufe (1 = Grundstufe, buildings.json → levels)
var level := 1
## Ausbau auf level + 1 läuft (bezahlt; die Bauarbeiter leisten upgrade_progress)
var upgrading := false
## Geleistete Ausbauarbeit in Sekunden
var upgrade_progress := 0.0
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
## (z. B. Monsterhöhle: {"kinds", "size", "respawn", "last_fight"};
## Tor: {"locked"}; Turm: {"cd", "think", "target_uid"})
var extra: Dictionary = {}
## Wird gerade durch Zerstörung (Kampf, Untergang des Reichs) entfernt – nicht durch
## eigenen Abriss oder Abbruch; dann gibt es keine Erstattung der Warteschlange (Laufzeit)
var destroyed := false
## Mauerstück oder Tor (def.segment): zählt nicht als richtiges Gebäude (Phase 9)
var is_segment := false
## Befestigung: "wall", "gate", "tower" oder "" (def.fortification)
var fort_kind := ""

var _tile_size := 64
var _world: WorldData
var _texture: Texture2D
## Farbe des Platzhalters (buildings.json "color", Dorfgebäude in der Volksfarbe)
var _color := Color.GRAY


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
	level = 1
	is_segment = bool(def.get("segment", false))
	fort_kind = str(def.get("fortification", ""))
	max_hp = compute_max_hp(kingdom)
	hp = max_hp
	set_process(false)
	refresh_look()


## Höchstes Leben für dieses Reich: hp × Modifikator building_hp (Befestigungen
## zusätzlich × fort_hp, Forschung "Steinmauern")
func compute_max_hp(k: Kingdom) -> float:
	var mult := k.mod("building_hp") if k != null else 1.0
	if fort_kind != "" and k != null:
		mult *= k.mod("fort_hp")
	return maxf(float(def.get("hp", 300.0)) * mult, 1.0)


## Grafik und Platzhalterfarbe neu bestimmen (beim Aufbau und nach einem
## Besitzerwechsel). Dorfgebäude nutzen das Volk aus extra.people_id.
func refresh_look() -> void:
	var people := str(extra.get("people_id", kingdom.people_id if kingdom != null else ""))
	var faction := kingdom.faction_id if kingdom != null else ""
	_texture = Assets.texture(DataDB.get_building_sprite(def, faction, people))
	_color = def.get("color", Color.GRAY)
	if bool(def.get("people_color", false)) and not DataDB.get_people(people).is_empty():
		_color = DataDB.get_people(people).get("color", _color)
	queue_redraw()


func get_footprint() -> Rect2i:
	return Rect2i(cell, size)


## Mitte der Grundfläche in Weltpixeln
func get_center() -> Vector2:
	return (Vector2(cell) + Vector2(size) * 0.5) * _tile_size


## Blockiert das Gebäude die Bewegung? (Strassen nicht.) Tore blockieren im
## Grundzustand (Durchlass regelt NavGrid je Reich).
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


## Nötige Bauarbeit (buildings.json build_time; eigene Bauzeit in extra.build_time, z. B. Dorf-Baustellen)
func get_build_time() -> float:
	return maxf(float(extra.get("build_time", def.get("build_time", 1.0))), 0.01)


func get_progress_ratio() -> float:
	return 1.0 if constructed else clampf(progress / get_build_time(), 0.0, 1.0)


# --- Ausbaustufen ---

func get_def_id() -> String:
	return str(def.get("id", ""))


## Höchste Stufe dieses Gebäudetyps (1 = nicht ausbaubar)
func get_max_level() -> int:
	return DataDB.get_building_max_level(get_def_id())


## Eintrag aus levels für die nächste Stufe ({} = höchste Stufe erreicht)
func get_next_level_entry() -> Dictionary:
	return DataDB.get_building_level_entry(get_def_id(), level + 1)


## Nötige Ausbauarbeit für die nächste Stufe (Sekunden Arbeit eines Bauarbeiters)
func get_upgrade_time() -> float:
	return maxf(float(get_next_level_entry().get("build_time", 1.0)), 0.01)


func get_upgrade_ratio() -> float:
	return clampf(upgrade_progress / get_upgrade_time(), 0.0, 1.0) if upgrading else 0.0


## Wird gerade ausgebaut (fertiges Gebäude, Ausbau bezahlt)?
func is_upgrading() -> bool:
	return constructed and upgrading


## Stufe setzen: Werte der Stufe übernehmen, Leben behält seinen Anteil
func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, get_max_level())
	def = DataDB.get_building_at_level(get_def_id(), level)
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	max_hp = compute_max_hp(kingdom)
	hp = max_hp * ratio
	queue_redraw()


## Kosten, die bisher in das Gebäude geflossen sind: Baukosten und alle fertigen Ausbauten
## (für die Rückerstattung beim Abreissen)
func get_invested_cost() -> Dictionary:
	var total: Dictionary = (DataDB.get_building(get_def_id()).get("cost", {}) as Dictionary).duplicate()
	for lv in range(2, level + 1):
		var cost: Dictionary = DataDB.get_building_level_entry(get_def_id(), lv).get("cost", {})
		for res_id in cost:
			total[res_id] = float(total.get(res_id, 0.0)) + float(cost[res_id])
	return total


## Fügt Bauarbeit hinzu. Gibt true zurück, wenn der Bau (oder Ausbau) dadurch fertig wurde.
func add_work(amount: float) -> bool:
	if constructed:
		if not upgrading:
			return false
		upgrade_progress += amount
		queue_redraw()
		if upgrade_progress >= get_upgrade_time():
			complete_upgrade()
			return true
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


## Schliesst den laufenden Ausbau sofort ab (neue Stufe).
func complete_upgrade() -> void:
	if not is_upgrading():
		return
	upgrading = false
	upgrade_progress = 0.0
	set_level(level + 1)
	upgraded.emit(self)


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
	if get_max_level() > 1:
		parts.append("Stufe %s" % DataDB.level_numeral(level))
	if upgrading:
		parts.append("Ausbau %d %%" % roundi(get_upgrade_ratio() * 100.0))
	if fort_kind == "gate":
		parts.append("verriegelt" if bool(extra.get("locked", false)) else "offen")
	elif fort_kind == "tower":
		parts.append("Reichweite %s Felder" % String.num(get_tower_range(), 1).replace(".", ","))
	if get_worker_slots() > 0:
		parts.append("Arbeiter: %d/%d" % [workers.size(), get_worker_slots()])
	if int(def.get("housing", 0)) > 0:
		parts.append("Wohnraum: %d" % int(def["housing"]))
	return "Fertig" if parts.is_empty() else "  ·  ".join(parts)


## Turmreichweite in Feldern (tower.range + Zuschlag tower_range des Reichs; 0 ohne Turm)
func get_tower_range() -> float:
	var tw: Dictionary = def.get("tower", {})
	if tw.is_empty():
		return 0.0
	return float(tw.get("range", 0.0)) + (kingdom.bonus("tower_range") if kingdom != null else 0.0)


func _draw() -> void:
	var px := Vector2(size) * _tile_size
	var rect := Rect2(-px * 0.5, px)
	var tint := Color.WHITE if constructed else Color(1, 1, 1, 0.55)
	if fort_kind == "wall" or fort_kind == "gate":
		_draw_segment(rect, tint)
	else:
		SpriteDraw.draw_entity(self, _texture, rect, _color, DataDB.get_building_label(def, kingdom.faction_id),
				str(def.get("shape", "rect")), tint)
	if fort_kind == "tower" and selected:
		var range_px := get_tower_range() * _tile_size
		draw_arc(Vector2.ZERO, range_px, 0.0, TAU, 64, Color(0, 0, 0, 0.5), 4.0, true)
		draw_arc(Vector2.ZERO, range_px, 0.0, TAU, 64, Color(1, 1, 1, 0.85), 2.0, true)
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
	if constructed and get_max_level() > 1:
		_draw_level_badge(rect)
	if upgrading:
		SpriteDraw.draw_bar(self, Rect2(rect.position.x + 6, rect.end.y - 24, px.x - 12, 8),
				get_upgrade_ratio(), Color(0.45, 0.85, 1.0))
	if hit_flash > 0.0:
		draw_rect(rect, Color(1, 0.3, 0.2, 0.35), true)
	if constructed and Settings.shows_hp_bar(hp < max_hp, selected):
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


## Kleines Schild oben links mit der Stufe (I/II/III); beim Ausbau mit Pfeil zur nächsten
func _draw_level_badge(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(int(_tile_size * 0.28), 10)
	var text := DataDB.level_numeral(level)
	if upgrading:
		text += "›" + DataDB.level_numeral(level + 1)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(rect.position + Vector2(4, 4), text_size + Vector2(8, 2))
	var gold := Color(0.95, 0.8, 0.35) if level > 1 else Color(0.85, 0.85, 0.85)
	draw_rect(box, Color(0.08, 0.06, 0.04, 0.8), true)
	draw_rect(box, gold, false, 1.5)
	draw_string(font, box.position + Vector2(4, box.size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, gold)


## Mauerstück oder Tor: Pfeiler mit Bändern zu benachbarten Befestigungen desselben
## Reichs; Tor als Holztür (verriegelt mit rotem Riegel). Mit Grafik: Textur auf der
## Kachel, um 90° gedreht, wenn nur senkrechte Nachbarn da sind.
func _draw_segment(rect: Rect2, tint: Color) -> void:
	var ts := float(_tile_size)
	var n_e := _fort_neighbor(Vector2i(1, 0))
	var n_w := _fort_neighbor(Vector2i(-1, 0))
	var n_s := _fort_neighbor(Vector2i(0, 1))
	var n_n := _fort_neighbor(Vector2i(0, -1))
	if _texture != null:
		if (n_n or n_s) and not (n_e or n_w):
			draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
			draw_texture_rect(_texture, rect, false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(_texture, rect, false, tint)
		return
	var base := Color(_color, tint.a)
	var dark := Color(_color.darkened(0.45), tint.a)
	var band := 22.0 * ts / 64.0
	var half := ts * 0.5
	for d in [[n_e, Vector2(1, 0)], [n_w, Vector2(-1, 0)], [n_s, Vector2(0, 1)], [n_n, Vector2(0, -1)]]:
		if not bool(d[0]):
			continue
		var dir: Vector2 = d[1]
		var r := Rect2(Vector2(minf(0.0, dir.x * half), minf(0.0, dir.y * half)), Vector2.ZERO)
		r.size = Vector2(half if dir.x != 0.0 else band, half if dir.y != 0.0 else band)
		if dir.x != 0.0:
			r.position.y = -band * 0.5
		else:
			r.position.x = -band * 0.5
		draw_rect(r.grow(1.5), dark, true)
		draw_rect(r, base, true)
	var pillar := 28.0 * ts / 64.0
	var pr := Rect2(-Vector2(pillar, pillar) * 0.5, Vector2(pillar, pillar))
	draw_rect(pr.grow(2.0), dark, true)
	draw_rect(pr, base, true)
	if fort_kind == "gate":
		var door_size := 40.0 * ts / 64.0
		var door := Rect2(-Vector2(door_size, door_size) * 0.5, Vector2(door_size, door_size))
		var locked := bool(extra.get("locked", false))
		var wood := Color(0.5, 0.33, 0.18, tint.a) if locked else Color(0.68, 0.47, 0.26, tint.a)
		draw_rect(door.grow(2.0), Color(0.12, 0.08, 0.05, tint.a), true)
		draw_rect(door, wood, true)
		var iron := Color(0.25, 0.25, 0.27, tint.a)
		draw_rect(Rect2(door.position + Vector2(0, door_size * 0.22), Vector2(door_size, 3.0)), iron, true)
		draw_rect(Rect2(door.position + Vector2(0, door_size * 0.72), Vector2(door_size, 3.0)), iron, true)
		if locked:
			draw_rect(Rect2(Vector2(-door_size * 0.5 - 4.0, -3.0), Vector2(door_size + 8.0, 6.0)), Color(0.85, 0.15, 0.12, tint.a), true)


## Steht auf der Nachbarkachel eine Befestigung desselben Reichs?
func _fort_neighbor(dir: Vector2i) -> bool:
	if _world == null:
		return false
	var other: Object = _world.get_building_at(cell + dir)
	return other != null and other is Building and (other as Building).kingdom == kingdom \
			and (other as Building).fort_kind != ""


## Gespeicherter Zustand (Phase 10; Kopien, Arbeiter als uids). Wiederhergestellt
## wird über BuildingSystem.restore_building.
func to_dict() -> Dictionary:
	var worker_uids: Array = []
	for u in workers:
		if is_instance_valid(u):
			worker_uids.append(u.uid)
	return {"uid": uid, "def_id": str(def.get("id", "")), "kingdom_id": kingdom.id if kingdom != null else 0,
			"cell": cell, "constructed": constructed, "progress": progress, "hp": hp, "max_hp": max_hp,
			"last_damaged_at": last_damaged_at, "summon_queue": summon_queue.duplicate(true),
			"rally_point": rally_point, "has_rally": has_rally, "summon_count": summon_count,
			"loot_factor": loot_factor, "biome_efficiency": biome_efficiency, "extra": extra.duplicate(true),
			"worker_uids": worker_uids, "level": level, "upgrading": upgrading, "upgrade_progress": upgrade_progress}


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
