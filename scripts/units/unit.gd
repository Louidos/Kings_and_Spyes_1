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

## Befehl des Spielers (ab Phase 3: "move", "attack" ...). Leer = frei für Arbeit.
var command: String = ""
## Gebäude, in dem sich die Einheit gerade aufhält (dann unsichtbar), sonst null
var inside: Building = null

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
	queue_redraw()


func can_work() -> bool:
	return bool(type_def.get("can_work", false))


func get_display_name() -> String:
	return str(type_def.get("name", "Einheit"))


## Beruf in der Einzahl ("Bergmann" statt "Bergleute")
func get_job_name() -> String:
	var job := DataDB.get_job(job_id)
	return str(job.get("singular", job.get("name", job_id)))


func get_status_text() -> String:
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
	var letter := str(DataDB.get_job(job_id).get("letter", ""))
	SpriteDraw.draw_entity(self, _texture, rect, kingdom.color if kingdom else Color.WHITE, letter, "circle")
	if carry_amount >= 1.0 and not carry_res.is_empty():
		var c: Color = DataDB.get_resource(carry_res).get("color", Color.WHITE)
		var box := Rect2(Vector2(r * 0.35, -r * 1.05), Vector2(r * 0.8, r * 0.8))
		draw_rect(box, c, true)
		draw_rect(box, Color(0, 0, 0, 0.7), false, 1.5)
