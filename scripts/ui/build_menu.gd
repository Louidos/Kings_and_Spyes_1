## BuildMenu
##
## Baumenü unten in der Mitte: ein Button je baubarem Gebäude (Reihenfolge wie
## in buildings.json) und zuletzt "Abreissen". Ein Klick startet die
## Bauvorschau (PlacementController); ein zweiter Klick auf denselben Button
## bricht sie ab. Der Button des aktiven Bauvorhabens bleibt eingedrückt.
## Gebäude, die gerade nicht bezahlbar sind, werden rötlich getönt – sie
## bleiben anklickbar, die Vorschau nennt dann den Grund.
class_name BuildMenu
extends PanelContainer

const REFRESH_INTERVAL := 0.25
## Höchstens so viele Buttons pro Zeile
const MAX_COLUMNS := 5
const BUTTON_MIN_WIDTH := 150.0
const FONT_SIZE := 16
const UNAFFORDABLE_TINT := Color(1.0, 0.75, 0.75)
const DEMOLISH_ID := "_demolish"

var game: Node

var _grid: GridContainer
## Gebäude-ID (oder DEMOLISH_ID) -> Button
var _buttons: Dictionary = {}
## Gebäude-ID -> Grundtext des Tooltips (ohne "Es fehlen")
var _base_tooltips: Dictionary = {}
## Baubare Gebäude in Datenreihenfolge
var _defs: Array = []
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	add_child(_grid)


func setup(p_game: Node) -> void:
	game = p_game
	for child in _grid.get_children():
		child.queue_free()
	_buttons.clear()
	_base_tooltips.clear()
	_defs.clear()
	for d in DataDB.buildings:
		var def: Dictionary = d
		if not bool(def.get("player_buildable", false)):
			continue
		var id := str(def.get("id", ""))
		var b := _make_button(str(def.get("name", id)))
		var tex := Assets.texture(DataDB.get_building_sprite(def, game.player.faction_id))
		if tex != null:
			b.icon = tex
		b.pressed.connect(_on_build_pressed.bind(def))
		_buttons[id] = b
		_base_tooltips[id] = build_tooltip(def)
		_defs.append(def)
	var demolish := _make_button("Abreissen (X)")
	demolish.tooltip_text = "Abreissen: Strassen anklicken oder mit gedrückter Maustaste überziehen.\nGebäude anklicken, um sie auszuwählen – abreissen dann im Auswahlfenster.\nRechtsklick oder Esc: beenden"
	demolish.pressed.connect(_on_demolish_pressed)
	_buttons[DEMOLISH_ID] = demolish
	# Möglichst zwei gleich lange Zeilen
	var count := _buttons.size()
	_grid.columns = clampi(ceili(count / 2.0), 1, MAX_COLUMNS)
	game.placement.placement_started.connect(_on_placement_started)
	game.placement.placement_ended.connect(_sync_pressed)
	_refresh()
	_sync_pressed()


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


## Bezahlbarkeit und Tooltips aktualisieren
func _refresh() -> void:
	var k: Kingdom = game.player
	if k == null:
		return
	for d in _defs:
		var def: Dictionary = d
		var id := str(def.get("id", ""))
		var b: Button = _buttons.get(id)
		if b == null:
			continue
		var cost: Dictionary = def.get("cost", {})
		var affordable := k.can_afford(cost)
		var tint := Color.WHITE if affordable else UNAFFORDABLE_TINT
		if b.modulate != tint:
			b.modulate = tint
		var tip := str(_base_tooltips.get(id, ""))
		if not affordable:
			tip += "\n" + k.missing_text(cost)
		if b.tooltip_text != tip:
			b.tooltip_text = tip


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BUTTON_MIN_WIDTH, 0)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.add_theme_constant_override("icon_max_width", 22)
	_grid.add_child(b)
	return b


func _on_build_pressed(def: Dictionary) -> void:
	var placement: PlacementController = game.placement
	if placement.mode != PlacementController.MODE_DEMOLISH and placement.is_active() \
			and str(placement.def.get("id", "")) == str(def.get("id", "")):
		placement.cancel()  # zweiter Klick: abbrechen
	else:
		placement.start(def)
	_sync_pressed()


func _on_demolish_pressed() -> void:
	var placement: PlacementController = game.placement
	if placement.mode == PlacementController.MODE_DEMOLISH:
		placement.cancel()
	else:
		placement.start_demolish()
	_sync_pressed()


func _on_placement_started(_def: Dictionary) -> void:
	_sync_pressed()


## Eingedrückt ist nur der Button des laufenden Bauvorhabens.
func _sync_pressed() -> void:
	if game == null:
		return
	var placement: PlacementController = game.placement
	var active_id := ""
	if placement.mode == PlacementController.MODE_DEMOLISH:
		active_id = DEMOLISH_ID
	elif placement.is_active():
		active_id = str(placement.def.get("id", ""))
	for id in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(id == active_id)


## Mehrzeiliger Tooltip aus den Gebäudedaten
static func build_tooltip(def: Dictionary) -> String:
	var lines: PackedStringArray = []
	var desc := str(def.get("description", ""))
	if not desc.is_empty():
		lines.append(desc)
	var cost_text := "Kosten: " + DataDB.cost_to_text(def.get("cost", {}))
	if str(def.get("placement", "")) == "line":
		cost_text += " je Feld"
	lines.append(cost_text)
	lines.append("Bauzeit: %d s" % roundi(float(def.get("build_time", 0.0))))
	var housing := int(def.get("housing", 0))
	if housing > 0:
		lines.append("Wohnraum: +%d" % housing)
	var territory := int(def.get("territory_radius", 0))
	if territory > 0:
		lines.append("Gebiet: +%d Felder" % territory)
	var dropoff: Array = def.get("dropoff", [])
	if not dropoff.is_empty():
		lines.append("Annahme: " + resource_names(dropoff))
	var gather := int(def.get("gather_radius", 0))
	if gather > 0:
		lines.append("Sammelradius: %d Felder" % gather)
	var bonus := float(def.get("gather_bonus", 0.0))
	if bonus > 0.0:
		lines.append("Sammeltempo: +%d %%" % roundi(bonus * 100.0))
	var workers := int(def.get("workers", 0))
	if workers > 0:
		var job_name := str(DataDB.get_job(str(def.get("job", ""))).get("name", ""))
		lines.append("Arbeitsplätze: %d%s" % [workers, (" (%s)" % job_name) if not job_name.is_empty() else ""])
	var production: Dictionary = def.get("production", {})
	for res_id in production:
		lines.append("Ertrag: %s %s pro Minute je Arbeiter" % [
			ResourceBar.format_number(float(production[res_id]) * 60.0), _res_name(str(res_id))])
	var base: Dictionary = def.get("base_production", {})
	for res_id in base:
		lines.append("Grundertrag: %s %s pro Minute (auch ohne Arbeiter)" % [
			ResourceBar.format_number(float(base[res_id]) * 60.0), _res_name(str(res_id))])
	var eff: Dictionary = def.get("biome_efficiency", {})
	if not eff.is_empty():
		var parts: PackedStringArray = []
		for biome_id in eff:
			parts.append("%s %d %%" % [_biome_name(str(biome_id)), roundi(float(eff[biome_id]) * 100.0)])
		lines.append("Ertrag je Gelände: " + ", ".join(parts))
	var dep_id := str(def.get("requires_deposit", ""))
	if not dep_id.is_empty():
		var dep_name := str(DataDB.get_deposit_by_id(dep_id).get("name", dep_id))
		var need := "Muss auf einer %s stehen" % dep_name
		if not desc.contains(need):
			lines.append(need)
	if str(def.get("placement", "")) == "line":
		lines.append("Maustaste halten und ziehen  ·  Rechtsklick: beenden")
	else:
		lines.append("Linksklick: bauen  ·  Umschalt: mehrere  ·  Rechtsklick: abbrechen")
	return "\n".join(lines)


## "Holz, Stein" aus einer Liste von Ressourcen-IDs
static func resource_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for res_id in ids:
		names.append(_res_name(str(res_id)))
	return ", ".join(names)


static func _res_name(res_id: String) -> String:
	return str(DataDB.get_resource(res_id).get("name", res_id))


static func _biome_name(biome_id: String) -> String:
	if not DataDB.biome_index_by_id.has(biome_id):
		return biome_id
	return str(DataDB.get_biome(int(DataDB.biome_index_by_id[biome_id])).get("name", biome_id))
