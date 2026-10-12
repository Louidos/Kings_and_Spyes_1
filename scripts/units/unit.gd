## Unit
##
## Eine Einheit auf der Karte: in Phase 2 der Bewohner, ab Phase 3 auch
## Späher, Kämpfer usw. Jede Einheit kann laufen (UnitSystem) und – wenn ihr
## Typ es erlaubt – einen Beruf ausüben (WorkSystem).
## Die Node hält nur Zustand und Darstellung; die Logik steckt in den Systemen.
class_name Unit
extends Node2D

## Arbeitszustand (vom WorkSystem gesetzt)
enum State { IDLE, MOVING, GATHERING, BUILDING, WORKING, WAITING }

## Eindeutige Nummer innerhalb der Partie (für Spielstände)
var uid: int = 0
var kingdom: Kingdom
## Daten des Einheitentyps aus units.json
var type_def: Dictionary = {}
var type_id: String = ""

# --- Bewegung (UnitSystem) ---
## Wegpunkte in Weltpixeln; der letzte ist das Ziel
var path := PackedVector2Array()
var path_index := 0
var moving := false
## Wartet auf eine Wegberechnung (Warteschlange im UnitSystem)
var path_pending := false
var path_target := Vector2.ZERO

## Befehl: "" (frei für Arbeit), "move", "attack_move", "attack", "hold" (steht
## und verteidigt), "flee" (Arbeiter flieht zur Burg)
var command: String = ""
## Zielpunkt des Befehls (Bewegung, Formationsplatz)
var command_pos := Vector2.ZERO
## Gebäude, in dem sich die Einheit gerade aufhält (dann unsichtbar), sonst null
var inside: Building = null

# --- Kampf (CombatSystem) ---
## Werte aus units.json, beim Erzeugen übernommen (schneller als Nachschlagen)
var role := "worker"
var attack := 0.0
var attack_interval := 1.0
## Reichweite in Kacheln
var attack_range := 0.8
var armor := 0.0
## Sichtweite für selbstständige Angriffe in Kacheln (0 = nie)
var aggro_range := 0.0
var regen := 0.0
var heal := 0.0
var heal_range := 0.0
var hp := 1.0
var max_hp := 1.0
## Angriffsziel: Unit oder Building (oder null)
var target: Object = null
var attack_cooldown := 0.0
## Spielzeit des letzten erlittenen Schadens (für Erholung)
var last_damaged_at := -1000.0
## Zeitgeber für Zielsuche und Neuplanung der Verfolgung
var think_timer := 0.0
var repath_timer := 0.0
var last_target_pos := Vector2.ZERO
## Monster: Heimatpunkt (Höhle), zu dem sie zurückkehren
var has_home := false
var home_pos := Vector2.ZERO
## Kurzes Aufblitzen nach einem Treffer (Echtzeit-Sekunden)
var hit_flash := 0.0

# --- Arbeit (WorkSystem) ---
var job_id: String = "idle":
	set(value):
		job_id = value
		queue_redraw()
var state: int = State.IDLE
## Was nach der Ankunft passieren soll ("gather", "dropoff", "build", "work", "wander")
var on_arrive: String = ""
var carry_res: String = "":
	set(value):
		carry_res = value
		queue_redraw()
var carry_amount := 0.0
## Reservierte Vorkommen-Kachel (-1,-1 = keine)
var target_cell := Vector2i(-1, -1)
## Gebäude-Baustelle, an der gearbeitet wird (oder null)
var target_building: Building = null
## Strassenbaustelle, an der gearbeitet wird ((-1,-1) = keine)
var target_road := Vector2i(-1, -1)
var dropoff: Building
var work_building: Building
## Zeitgeber in Spielsekunden (Sammeln, Warten ...)
var timer := 0.0
## Teilmengen beim Sammeln (bis eine ganze Einheit erreicht ist)
var work_acc := 0.0
## Aktuelle Tätigkeit als Text, z. B. "fällt Bäume"
var activity: String = ""
## Warum die Einheit nicht arbeiten kann (leer = alles in Ordnung)
var problem: String = ""
## Stand der Vorkommen/Gebäude bei der letzten erfolglosen Suche (-1 = keine)
var failed_search_version := -1

var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _texture: Texture2D
var _radius := 13.0


func setup(p_type_def: Dictionary, p_kingdom: Kingdom, p_uid: int) -> void:
	uid = p_uid
	type_def = p_type_def
	type_id = str(type_def.get("id", ""))
	kingdom = p_kingdom
	_radius = float(type_def.get("radius", 13.0))
	_texture = Assets.texture(DataDB.get_unit_sprite(type_def, kingdom.faction_id))
	role = str(type_def.get("role", "worker"))
	attack = float(type_def.get("attack", 0.0))
	attack_interval = maxf(float(type_def.get("attack_interval", 1.0)), 0.1)
	attack_range = float(type_def.get("range", 0.8))
	armor = float(type_def.get("armor", 0.0))
	aggro_range = float(type_def.get("aggro_range", 0.0))
	regen = float(type_def.get("regen", 0.0))
	heal = float(type_def.get("heal", 0.0))
	heal_range = float(type_def.get("heal_range", 0.0))
	max_hp = float(type_def.get("hp", 1.0)) * kingdom.mod("hp")
	hp = max_hp
	set_process(false)
	queue_redraw()


func can_work() -> bool:
	return bool(type_def.get("can_work", false))


## Rolle aus units.json: worker, king, combat, support, monster
func get_role() -> String:
	return role


func is_alive() -> bool:
	return hp > 0.0


## Kann angreifen (Schaden > 0)
func is_combatant() -> bool:
	return attack > 0.0


func can_heal() -> bool:
	return heal > 0.0


## Radius des Platzhalters in Pixeln (auch für Abstände im Kampf)
func get_radius() -> float:
	return _radius


func get_command_text() -> String:
	match command:
		"move":
			return "marschiert"
		"attack_move":
			return "marschiert kampfbereit"
		"attack":
			return "greift an"
		"hold":
			return "hält die Stellung"
		"flee":
			return "flieht zur Burg"
	return ""


func get_display_name() -> String:
	return str(type_def.get("name", "Einheit"))


## Beruf in der Einzahl ("Bergmann" statt "Bergleute")
func get_job_name() -> String:
	var job := DataDB.get_job(job_id)
	return str(job.get("singular", job.get("name", job_id)))


func get_status_text() -> String:
	if not command.is_empty() or not can_work():
		var t := get_command_text()
		if is_instance_valid(target) and target != null:
			t = "kämpft gegen %s" % target.get_display_name()
		return t if not t.is_empty() else "bereit"
	var text := get_job_name()
	if not activity.is_empty():
		text += " – " + activity
	if carry_amount >= 1.0 and not carry_res.is_empty():
		text += "\nTrägt %d %s" % [int(carry_amount), DataDB.get_resource(carry_res).get("name", carry_res)]
	if not problem.is_empty():
		text += "\n(!) " + problem
	return text


func _draw() -> void:
	var r := _radius
	var rect := Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
	if _texture != null:
		# Grafik etwas grösser als der Platzhalter, Füsse auf der Position
		var tex_size := r * 3.0
		rect = Rect2(Vector2(-tex_size * 0.5, -tex_size * 0.75), Vector2(tex_size, tex_size))
	if selected:
		draw_arc(Vector2(0, r * 0.35), r + 5.0, 0.0, TAU, 28, Color(1, 1, 0.6, 0.95), 2.5, true)
	# Buchstabe: Bewohner zeigen ihren Beruf, alle anderen ihren Typ
	var letter := str(type_def.get("letter", ""))
	if letter.is_empty():
		letter = str(DataDB.get_job(job_id).get("letter", ""))
	var color: Color = type_def.get("color", kingdom.color if kingdom else Color.WHITE)
	var tint := Color(1.6, 1.6, 1.6) if hit_flash > 0.0 else Color.WHITE
	SpriteDraw.draw_entity(self, _texture, rect, color, letter, "circle", tint)
	if get_role() == "king" and _texture == null:
		# Krone über dem König
		var crown := PackedVector2Array([Vector2(-r * 0.6, -r * 1.05), Vector2(-r * 0.6, -r * 1.45),
				Vector2(-r * 0.3, -r * 1.2), Vector2(0, -r * 1.55), Vector2(r * 0.3, -r * 1.2),
				Vector2(r * 0.6, -r * 1.45), Vector2(r * 0.6, -r * 1.05)])
		draw_colored_polygon(crown, Color(1.0, 0.82, 0.25))
		draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0.35, 0.22, 0.05), 1.5)
	if carry_amount >= 1.0 and not carry_res.is_empty():
		var c: Color = DataDB.get_resource(carry_res).get("color", Color.WHITE)
		var box := Rect2(Vector2(r * 0.35, -r * 1.05), Vector2(r * 0.8, r * 0.8))
		draw_rect(box, c, true)
		draw_rect(box, Color(0, 0, 0, 0.7), false, 1.5)
	# Lebensbalken, wenn verletzt oder ausgewählt
	if hp < max_hp or selected:
		var w := maxf(r * 2.2, 26.0)
		var bar := Rect2(Vector2(-w * 0.5, r + 4.0), Vector2(w, 5.0))
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var bar_color := Color(0.3, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.2) if ratio > 0.25 else Color(0.95, 0.25, 0.2))
		SpriteDraw.draw_bar(self, bar, ratio, bar_color)


## Kurz aufblitzen lassen (nach einem Treffer)
func flash() -> void:
	hit_flash = 0.15
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	# Trefferblitz abklingen lassen (reine Darstellung, Echtzeit)
	if hit_flash > 0.0:
		hit_flash -= delta
		if hit_flash <= 0.0:
			set_process(false)
			queue_redraw()
