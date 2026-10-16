## BuildMenu
##
## Baumenü unten in der Mitte: ein Button je baubarem Gebäude (Reihenfolge wie
## in buildings.json) und zuletzt "Abreissen". Ein Klick startet die
## Bauvorschau (PlacementController); ein zweiter Klick auf denselben Button
## bricht sie ab. Der Button des aktiven Bauvorhabens bleibt eingedrückt.
## Gebäude, die gerade nicht bezahlbar sind, werden rötlich getönt – sie
## bleiben anklickbar, die Vorschau nennt dann den Grund.
## Gebäude, die erst erforscht werden müssen (def.requires) oder eine höhere Burgstufe brauchen
## (def.requires_castle_level), sehen gesperrt aus (grau mit Schloss); der Tooltip nennt, was
## fehlt, ein Klick nennt nur den Grund statt die Vorschau zu starten.
## Phase 9: Reiter "Dorf", "Militär & Wissen", "Verteidigung" (def.menu); "Abreissen (X)"
## steht in jedem Reiter. Startet eine Platzierung von anderswo, springt der Reiter mit.
class_name BuildMenu
extends PanelContainer

const REFRESH_INTERVAL := 0.25
## Höchstens so viele Buttons pro Zeile
const MAX_COLUMNS := 6
const BUTTON_MIN_WIDTH := 150.0
const FONT_SIZE := 16
const UNAFFORDABLE_TINT := Color(1.0, 0.75, 0.75)
const DEMOLISH_ID := "_demolish"
const LOCKED_MODULATE := Color(0.62, 0.6, 0.6)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_HINT := Color(0.74, 0.71, 0.66)
## Reiter des Baumenüs (buildings.json menu) und ihre Beschriftung
const TABS := [["economy", "Dorf", "Wohnen, Rohstoffe, Lager, Nahrung, Mana und Strassen"],
		["military", "Militär & Wissen", "Kaserne, Forschung, Heldenhalle, Spionage und weitere Truppengebäude"],
		["defense", "Verteidigung", "Mauern, Tore, Türme und Belagerungswerkstatt"]]


## Button des Baumenüs: farbiger Tooltip, bei gesperrten Gebäuden ein Schloss
class BuildButton:
	extends ResearchTipButton
	var locked := false:
		set(value):
			if locked != value:
				locked = value
				queue_redraw()

	func _draw() -> void:
		super()
		if not locked:
			return
		# Kleines Vorhängeschloss links (der gesperrte Stil lässt dort Platz)
		var c := Vector2(14.0, size.y * 0.5 - 1.0)
		var body := Rect2(c + Vector2(-6.0, -1.0), Vector2(12.0, 9.0))
		var col := Color(0.86, 0.84, 0.8)
		draw_arc(c + Vector2(0.0, -1.0), 4.0, PI, TAU, 10, Color(0.05, 0.05, 0.05, 0.8), 3.4, true)
		draw_arc(c + Vector2(0.0, -1.0), 4.0, PI, TAU, 10, col, 1.8, true)
		draw_rect(body.grow(1.0), Color(0.05, 0.05, 0.05, 0.8))
		draw_rect(body, col)
		draw_rect(Rect2(c + Vector2(-1.0, 2.0), Vector2(2.0, 3.0)), Color(0.15, 0.13, 0.12))

var game: Node
## Höchstbreite (0 = beliebig), siehe set_max_width
var _max_width := 0.0

var _grid: GridContainer
## Gebäude-ID (oder DEMOLISH_ID) -> Button
var _buttons: Dictionary = {}
## Gebäude-ID -> Grundtext des Tooltips (ohne "Es fehlen")
var _base_tooltips: Dictionary = {}
## Gebäude-ID -> Def (für Tooltip und Klick)
var _defs_by_id: Dictionary = {}
## Baubare Gebäude in Datenreihenfolge
var _defs: Array = []
var _timer := 0.0
## Aktiver Reiter und seine Knöpfe (Reiter-id -> Button)
var _tab := "economy"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in TABS:
		var t := Button.new()
		t.text = str(entry[1])
		t.tooltip_text = "Baumenü: %s" % str(entry[2])
		t.toggle_mode = true
		t.button_group = group
		t.focus_mode = Control.FOCUS_NONE
		t.add_theme_font_size_override("font_size", 15)
		t.pressed.connect(select_tab.bind(str(entry[0])))
		tabs.add_child(t)
		_tab_buttons[str(entry[0])] = t
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)


func setup(p_game: Node) -> void:
	game = p_game
	for child in _grid.get_children():
		child.queue_free()
	_buttons.clear()
	_base_tooltips.clear()
	_defs.clear()
	_defs_by_id.clear()
	for d in DataDB.buildings:
		var def: Dictionary = d
		if not bool(def.get("player_buildable", false)):
			continue
		var id := str(def.get("id", ""))
		var b := _make_button(DataDB.get_building_name(def, game.player.faction_id))
		var tex := Assets.texture(DataDB.get_building_sprite(def, game.player.faction_id))
		if tex != null:
			b.icon = tex
		b.pressed.connect(_on_build_pressed.bind(def))
		b.tip_source = _build_tip.bind(id)
		_buttons[id] = b
		_base_tooltips[id] = build_tooltip(def)
		_defs.append(def)
		_defs_by_id[id] = def
	var demolish := _make_button("Abreissen (X)")
	demolish.tooltip_text = "Abreissen: Strassen anklicken oder mit gedrückter Maustaste überziehen.\nGebäude anklicken, um sie auszuwählen – abreissen dann im Auswahlfenster.\nRechtsklick oder Esc: beenden"
	demolish.pressed.connect(_on_demolish_pressed)
	_buttons[DEMOLISH_ID] = demolish
	game.placement.placement_started.connect(_on_placement_started)
	game.placement.placement_ended.connect(_sync_pressed)
	game.research_system.research_completed.connect(_on_research_completed)
	select_tab(_tab)
	_refresh()
	_sync_pressed()


## Reiter wählen ("economy", "military", "defense"): nur dessen Knöpfe und "Abreissen"
func select_tab(menu: String) -> void:
	_tab = menu if _tab_buttons.has(menu) else "economy"
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).set_pressed_no_signal(id == _tab)
	var n := 0
	for id in _buttons:
		var shown: bool = id == DEMOLISH_ID or str((_defs_by_id.get(id, {}) as Dictionary).get("menu", "economy")) == _tab
		(_buttons[id] as Button).visible = shown
		if shown:
			n += 1
	# Möglichst zwei gleich lange Zeilen – aber nie breiter als der Platz zwischen
	# linker Spalte und Minikarte (dann eine Zeile mehr)
	var cols := clampi(ceili(n / 2.0), 1, MAX_COLUMNS)
	if _max_width > 0.0:
		var sep := float(_grid.get_theme_constant("h_separation"))
		var fit := floori((_max_width - 40.0 + sep) / (BUTTON_MIN_WIDTH + 12.0 + sep))
		cols = clampi(mini(cols, fit), 2, MAX_COLUMNS)
	_grid.columns = cols
	reset_size()


## Höchstbreite (vom HUD: Platz zwischen linker Spalte und Minikarte)
func set_max_width(w: float) -> void:
	if not is_equal_approx(w, _max_width):
		_max_width = w
		select_tab(_tab)


## Aktiver Reiter
func get_tab() -> String:
	return _tab


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


## Sperre und Bezahlbarkeit aktualisieren (der Tooltip entsteht erst beim Zeigen)
func _refresh() -> void:
	var k: Kingdom = game.player
	if k == null:
		return
	for d in _defs:
		var def: Dictionary = d
		var id := str(def.get("id", ""))
		var b: BuildButton = _buttons.get(id)
		if b == null:
			continue
		var locked := not lock_reason(def, k).is_empty()
		var tint := Color.WHITE
		if locked:
			tint = LOCKED_MODULATE
		elif not k.can_afford(def.get("cost", {})):
			tint = UNAFFORDABLE_TINT
		if b.modulate != tint:
			b.modulate = tint
		if b.locked != locked:
			b.locked = locked
			_set_locked_style(b, locked)


func _on_research_completed(k: Kingdom, _id: String) -> void:
	if k == game.player:
		_refresh()


## "Braucht Burgstufe 3 (Stadt) · für Dorf: noch 4 Bewohner" oder "Benötigt Forschung: Heilkunde"
## (wie BuildingSystem.can_build_type), "" = freigeschaltet
static func lock_reason(def: Dictionary, k: Kingdom) -> String:
	var castle_reason := BuildingSystem.castle_lock_reason(int(def.get("requires_castle_level", 1)), k, true)
	if not castle_reason.is_empty():
		return castle_reason
	var requires: Array = def.get("requires", [])
	if requires.is_empty() or k.has_all_unlocks(requires):
		return ""
	return "Benötigt Forschung: %s" % DataDB.describe_requirement(requires, k.faction_id)


## Wo man die Sperre aufhebt
static func _lock_hint(reason: String) -> String:
	if reason.begins_with("Braucht Burgstufe"):
		return "Burg ausbauen: Burg auswählen oder Reichsfenster (L), Reiter Burg"
	return "Forschungsfenster: R"


## Gesperrt: sieht aus wie ein abgeschalteter Button (mit Platz für das
## Schloss links), bleibt aber anklickbar
func _set_locked_style(b: Button, locked: bool) -> void:
	if locked:
		var st := b.get_theme_stylebox("disabled").duplicate() as StyleBox
		st.content_margin_left = 26.0
		st.content_margin_right = 8.0
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		var c: Color = b.get_theme_color("font_disabled_color")
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_hover_color", c)
	else:
		for style_name in ["normal", "hover", "pressed"]:
			b.remove_theme_stylebox_override(style_name)
		b.remove_theme_color_override("font_color")
		b.remove_theme_color_override("font_hover_color")


## Tooltip (BBCode): gesperrt/fehlende Rohstoffe rot, dann die Gebäudedaten
func _build_tip(id: String) -> String:
	var k: Kingdom = game.player
	var def: Dictionary = _defs_by_id.get(id, {})
	var lines: PackedStringArray = []
	var reason := lock_reason(def, k)
	if not reason.is_empty():
		lines.append(ResearchTipButton.colored(reason, COLOR_BAD))
		lines.append(ResearchTipButton.colored(_lock_hint(reason), COLOR_HINT))
	lines.append(ResearchTipButton.esc(str(_base_tooltips.get(id, ""))))
	var missing := k.missing_text(def.get("cost", {}))
	if not missing.is_empty():
		lines.append(ResearchTipButton.colored(missing, COLOR_BAD))
	return "\n".join(lines)


func _make_button(text: String) -> BuildButton:
	var b := BuildButton.new()
	b.tip_max_width = 420.0
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
	# Noch nicht erforscht: nur den Grund nennen, keine Vorschau
	var reason := lock_reason(def, game.player)
	if not reason.is_empty():
		Notify.warning("%s: %s (%s)" % [DataDB.get_building_name(def, game.player.faction_id), reason, _lock_hint(reason)])
		_sync_pressed()
		return
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


func _on_placement_started(p_def: Dictionary) -> void:
	# Reiter springt mit (Platzierung über einen Verweis)
	if not p_def.is_empty():
		var menu := str(p_def.get("menu", "economy"))
		if menu != _tab:
			select_tab(menu)
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
	var castle_level := int(def.get("requires_castle_level", 1))
	if castle_level > 1:
		lines.append("Ab Burgstufe %d (%s)" % [castle_level, DataDB.castle_level_name(castle_level)])
	var max_level := DataDB.get_building_max_level(str(def.get("id", "")))
	if max_level > 1:
		lines.append("Ausbaubar bis Stufe %s (Auswahlfenster)" % DataDB.level_numeral(max_level))
	var housing := int(def.get("housing", 0))
	if housing > 0:
		lines.append("Wohnraum: +%d" % housing)
	if str(def.get("fortification", "")) != "":
		lines.append("Leben %d · Rüstung %d %%" % [roundi(float(def.get("hp", 0.0))), roundi(float(def.get("armor", 0.0)) * 100.0)])
	var tw: Dictionary = def.get("tower", {})
	if not tw.is_empty():
		lines.append("Schaden %d alle %s s · Reichweite %s Felder" % [roundi(float(tw.get("attack", 0.0))),
			String.num(float(tw.get("interval", 1.0)), 1).replace(".", ","), String.num(float(tw.get("range", 0.0)), 1).replace(".", ",")])
	if str(def.get("fortification", "")) == "gate":
		lines.append("Eigene und Verbündete gehen hindurch")
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
	var sat: Dictionary = def.get("satisfaction", {})
	if not sat.is_empty():
		lines.append("Zufriedenheit %+d für bis zu %d Bewohner" % [roundi(float(sat.get("bonus", 0))), int(sat.get("capacity", 0))])
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
