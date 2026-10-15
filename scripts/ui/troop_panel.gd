## TroopPanel
##
## Armeefenster (Taste T, Knopf "Armee" oben; T, Esc oder × schliesst). Gleiche
## Bauart wie Forschungs-, Helden-, Diplomatie- und Reichsfenster (eigene Ebene, Mitte
## oben, immer nur eines offen); das Spiel läuft weiter.
## Links: alle eigenen Truppen nach Einheitentyp (Bild, Anzahl, Leben gesamt und Ø,
## wie viele untätig / im Kampf / unterwegs / bei der Arbeit sind), die Helden einzeln
## und die Armeen 1–9 (Anzahl, Stärke, Ort, Befehl). Je Zeile: "Wählen" (die Einheiten
## werden ausgewählt und zur Befehlsgruppe), "Hin" (Kamera), bei Armeen "✕" (auflösen).
## Mit "Bewohner und König zeigen" erscheinen auch sie in der Liste.
## Rechts: Auswahl (alle Krieger – auch Strg+A –, Untätige, Verwundete, Auswahl → Armee N)
## und Befehle an die Befehlsgruppe: Sammeln an der Burg, Rückzug zur Burg (Erholung),
## Angreifend vorrücken / Bewegen / Patrouille (danach Klick auf die Karte – derselbe
## Zielmodus wie "Angriff-Vorrücken" im Auswahlfenster), Halten, Formation (Block, Linie,
## Keil, Kreis – die Gruppe stellt sich an ihrem Ort neu auf) und Haltung (aggressiv,
## verteidigend, passiv). Alle Befehle laufen über die öffentlichen Funktionen des
## CommandSystem, die auch die KI benutzen kann.
## Aktualisiert alle 0.5 s, solange offen; Zeilen werden nur neu angelegt, wenn sich
## Typen, Helden oder Armeen ändern.
class_name TroopPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const DESIGN_WIDTH := 1220.0
const TOP := 92.0
const LIST_HEIGHT := 560.0
const REFRESH_INTERVAL := 0.5
## Unter so viel Leben (Anteil) gilt eine Einheit als verwundet
const WOUNDED_RATIO := 0.7
const ICON_SIZE := 30.0
const ROW_FONT := 15
const NAME_WIDTH := 145.0
const COUNT_WIDTH := 40.0
const BAR_WIDTH := 175.0
const INFO_WIDTH := 220.0
const SIDE_WIDTH := 340.0
## Innenabstand links/rechts der Knöpfe
const BUTTON_MARGIN := 7.0
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_FIGHT := Color(1.0, 0.45, 0.38)

## Befehlsgruppen (für wen die Befehle rechts gelten)
const GROUP_ALL := "all"
const GROUP_SELECTION := "selection"
const GROUP_TYPE := "type"
const GROUP_HERO := "hero"
const GROUP_ARMY := "army"
const GROUP_IDLE := "idle"
const GROUP_WOUNDED := "wounded"

## Zustand einer Einheit für die Übersicht (unit_state)
const STATE_IDLE := "idle"
const STATE_FIGHTING := "fighting"
const STATE_MARCHING := "marching"
const STATE_WORKING := "working"
const MARCH_COMMANDS := ["move", "attack_move", "patrol", "retreat", "flee", "return", "travel", "cast"]
## Befehle mit Zielklick auf der Karte (Zielmodus des SelectionController)
const TARGET_ORDER_NAMES := {"attack_move": "Angreifend vorrücken", "move": "Bewegen", "patrol": "Patrouille"}
const COMPASS := ["östlich", "südöstlich", "südlich", "südwestlich", "westlich", "nordwestlich", "nördlich", "nordöstlich"]

var game: Node
var _evil := false
var _accent := ResearchPanel.GOOD_ACCENT
var _timer := 0.0
var _show_civilians := false
var _group_kind := GROUP_ALL
var _group_key := ""

var _summary: Label
var _civ_check: CheckBox
var _type_grid: GridContainer
var _hero_grid: GridContainer
var _army_grid: GridContainer
var _type_empty: Label
var _hero_empty: Label
var _army_empty: Label
## Schlüssel der Zeilen beim letzten Aufbau (Typ-ids, Helden-ids, Armee-Nummern)
var _type_keys: Array = []
var _hero_keys: Array = []
var _army_keys: Array = []
## Schlüssel -> {"icon", "name", "count", "bar", "info", "select", "jump", …}
var _type_rows: Dictionary = {}
var _hero_rows: Dictionary = {}
var _army_rows: Dictionary = {}
var _group_label: Label
## Knöpfe nach Namen (auch für den Rauchtest): "all", "idle", "wounded", "gather",
## "retreat", "attack_move", "move", "patrol", "hold"
var buttons: Dictionary = {}
var _army_assign: Array = []
var _formation_buttons: Dictionary = {}
var _stance_buttons: Dictionary = {}
var _stance_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Aufbauen (das Fenster muss schon im Baum hängen)
func setup(p_game: Node) -> void:
	game = p_game
	_evil = game.player.faction_id == "evil"
	_accent = ResearchPanel.EVIL_ACCENT if _evil else ResearchPanel.GOOD_ACCENT
	add_theme_stylebox_override("panel", _panel_style())
	custom_minimum_size = Vector2(DESIGN_WIDTH, 0)
	_build()
	game.formation_changed.connect(func(_f: String) -> void:
		if visible:
			_refresh_side())
	get_viewport().size_changed.connect(_place)
	Settings.changed.connect(_place)
	minimum_size_changed.connect(func() -> void:
		if visible:
			_place.call_deferred())


func is_open() -> bool:
	return visible


## Öffnen: sind eigene Einheiten ausgewählt, gelten die Befehle zuerst ihnen
func open() -> void:
	if visible:
		refresh()
		return
	if not game.selection.get_own_units().is_empty():
		_group_kind = GROUP_SELECTION
		_group_key = ""
	elif _group_kind == GROUP_SELECTION:
		_group_kind = GROUP_ALL
	visible = true
	set_process(true)
	_timer = 0.0
	refresh()
	_place()
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	refresh()


# ---------------------------------------------------------------------------
# Daten (statisch, auch für die obere Leiste und den Rauchtest)
# ---------------------------------------------------------------------------

## Zustand einer Einheit: STATE_FIGHTING (hat ein Ziel), STATE_MARCHING (unterwegs),
## STATE_WORKING (Beruf) oder STATE_IDLE (steht, hält, ruht)
static func unit_state(u: Unit) -> String:
	if is_instance_valid(u.target) and u.target != null:
		return STATE_FIGHTING
	if u.command.is_empty() and u.can_work() and (u.job_id != "idle" or u.inside != null):
		return STATE_WORKING
	if MARCH_COMMANDS.has(u.command) or u.moving or u.path_pending or u.follow_leader != null:
		return STATE_MARCHING
	return STATE_IDLE


## Zustände einer Liste zählen: {"idle", "fighting", "marching", "working"}
static func count_states(units: Array) -> Dictionary:
	var counts := {STATE_IDLE: 0, STATE_FIGHTING: 0, STATE_MARCHING: 0, STATE_WORKING: 0}
	for u in units:
		var s := unit_state(u)
		counts[s] = int(counts[s]) + 1
	return counts


## "3 untätig · 1 im Kampf · 2 unterwegs" (nur Zustände, die vorkommen)
static func states_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for entry in [[STATE_IDLE, "untätig"], [STATE_FIGHTING, "im Kampf"], [STATE_MARCHING, "unterwegs"],
			[STATE_WORKING, "bei der Arbeit"]]:
		var n := int(counts.get(entry[0], 0))
		if n > 0:
			parts.append("%d %s" % [n, str(entry[1])])
	return " · ".join(parts) if not parts.is_empty() else "–"


## Kampfkraft einer Liste (wie bei den Dörfern: Leben × Schaden pro Sekunde, grob)
static func strength_of(units: Array) -> int:
	var total := 0.0
	for u in units:
		total += VillageSystem.unit_power(u)
	return roundi(total)


static func centroid_of(units: Array) -> Vector2:
	var c := Vector2.ZERO
	for u in units:
		c += (u as Unit).position
	return c / maxf(float(units.size()), 1.0)


## Häufigster Befehl einer Liste als Text ("hält die Stellung", "bei der Arbeit", "bereit")
static func order_text(units: Array) -> String:
	var counts := {}
	for u in units:
		var cmd: String = (u as Unit).command
		counts[cmd] = int(counts.get(cmd, 0)) + 1
	var best := ""
	var best_n := -1
	for cmd in counts:
		if int(counts[cmd]) > best_n:
			best_n = int(counts[cmd])
			best = str(cmd)
	if best.is_empty():
		return "bei der Arbeit" if not units.is_empty() and (units[0] as Unit).can_work() else "bereit"
	var text := CommandSystem.get_command_text(best)
	if counts.size() > 1:
		text += " (%d von %d)" % [best_n, units.size()]
	return text


# ---------------------------------------------------------------------------
# Befehlsgruppe
# ---------------------------------------------------------------------------

## Gruppe setzen und ihre Einheiten auswählen (Knöpfe "Wählen", "Alle Krieger" …).
## Gibt die Einheiten zurück (leer = keine; dann bleibt die Auswahl unverändert).
func choose_group(kind: String, key: String = "") -> Array:
	_group_kind = kind
	_group_key = key
	var units := group_units()
	if units.is_empty():
		Notify.info("%s: keine Einheiten" % group_name())
	else:
		game.selection.select(units)
	if visible:
		refresh()
	return units


## Einheiten der Befehlsgruppe (lebend, eigene)
func group_units() -> Array:
	var k: Kingdom = game.player
	var cs: CommandSystem = game.command_system
	match _group_kind:
		GROUP_SELECTION:
			return game.selection.get_own_units()
		GROUP_TYPE:
			var list: Array = []
			for u in k.units:
				if is_instance_valid(u) and u.is_alive() and u.hero_id == 0 and u.type_id == _group_key:
					list.append(u)
			return list
		GROUP_HERO:
			var hu: Unit = game.hero_system.get_unit(k, int(_group_key))
			return [hu] if hu != null and hu.is_alive() else []
		GROUP_ARMY:
			return cs.get_army(k, int(_group_key))
		GROUP_IDLE:
			var idle: Array = []
			for u in cs.get_warriors(k):
				if unit_state(u) == STATE_IDLE:
					idle.append(u)
			return idle
		GROUP_WOUNDED:
			var hurt: Array = []
			for u in cs.get_warriors(k):
				if u.hp < u.max_hp * WOUNDED_RATIO:
					hurt.append(u)
			return hurt
	return cs.get_warriors(k)


func get_group_kind() -> String:
	return _group_kind


## Name der Befehlsgruppe ("Alle Krieger", "Armee 3", "Schwertkämpfer" …)
func group_name() -> String:
	match _group_kind:
		GROUP_SELECTION:
			return "Aktuelle Auswahl"
		GROUP_TYPE:
			return str(DataDB.get_unit_type(_group_key).get("name", _group_key))
		GROUP_HERO:
			var rec: Dictionary = game.hero_system.get_record(game.player, int(_group_key))
			return game.hero_system.get_title(rec) if not rec.is_empty() else "Held"
		GROUP_ARMY:
			return "Armee %s" % _group_key
		GROUP_IDLE:
			return "Untätige Krieger"
		GROUP_WOUNDED:
			return "Verwundete Krieger"
	return "Alle Krieger"


# ---------------------------------------------------------------------------
# Befehle (über das CommandSystem – dieselben Funktionen kann die KI nutzen)
# ---------------------------------------------------------------------------

## Befehl an die Befehlsgruppe: "gather", "retreat", "hold", "attack_move", "move",
## "patrol" (die letzten drei warten auf einen Klick in die Karte). true = gegeben.
func order(kind: String) -> bool:
	var units := group_units()
	if units.is_empty():
		Notify.info("%s: keine Einheiten für den Befehl" % group_name())
		return false
	var cs: CommandSystem = game.command_system
	match kind:
		"gather":
			cs.order_gather(units)
			Notify.info("%s sammeln sich an der Burg" % group_name())
		"retreat":
			cs.order_retreat(units)
			Notify.info("%s ziehen sich zur Burg zurück" % group_name())
		"hold":
			cs.order_stop(units)
		"attack_move", "move", "patrol":
			# Zielmodus des SelectionController: der nächste Klick in die Karte gibt den Befehl
			game.selection.select(units)
			game.selection.arm_order(kind)
			close()
			Notify.info("%s: Ziel auf der Karte anklicken (Esc bricht ab)" % str(TARGET_ORDER_NAMES[kind]))
		_:
			return false
	if visible:
		refresh()
	return true


## Formation setzen (gilt für die nächsten Marschbefehle) und die Gruppe darin aufstellen
func set_formation(formation: String) -> void:
	game.set_formation(formation)
	var units := group_units()
	if not units.is_empty():
		game.command_system.order_reform(units, formation)
	_refresh_side()


## Haltung der Befehlsgruppe setzen
func set_stance(stance: String) -> void:
	var units := group_units()
	if units.is_empty():
		Notify.info("%s: keine Einheiten" % group_name())
		return
	game.command_system.set_stance(units, stance)
	Notify.info("%s: Haltung %s" % [group_name(), CommandSystem.get_stance_name(stance)])
	_refresh_side()


## Ausgewählte eigene Einheiten als Armee n speichern (wie Strg+n)
func assign_selection_to_army(n: int) -> void:
	var units: Array = []
	for u in game.selection.get_own_units():
		if (u as Unit).role != "king":
			units.append(u)
	if units.is_empty():
		Notify.info("Armee %d: zuerst eigene Einheiten auswählen" % n)
		return
	game.command_system.set_army(game.player, n, units)
	Notify.info("Armee %d gespeichert (%d Einheiten)" % [n, units.size()])
	refresh()


func dissolve_army(n: int) -> void:
	game.command_system.dissolve_army(game.player, n)
	Notify.info("Armee %d aufgelöst" % n)
	if _group_kind == GROUP_ARMY and int(_group_key) == n:
		_group_kind = GROUP_ALL
	refresh()


func _jump_to(units: Array) -> void:
	if units.is_empty():
		return
	game.camera.focus_on(centroid_of(units))


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var title_row := UiStyle.window_header(root, "Armee", _evil, "Schliessen (T oder Esc)", close)
	_summary = _label(17, COLOR_TEXT)
	_summary.clip_text = true
	UiStyle.header_add(title_row, _summary, true)
	_civ_check = CheckBox.new()
	_civ_check.text = "Bewohner und König zeigen"
	_civ_check.focus_mode = Control.FOCUS_NONE
	_civ_check.tooltip_text = "Auch Bewohner und den König in der Liste zeigen (Befehle mit „Wählen“ gelten dann auch für sie)"
	_civ_check.add_theme_font_size_override("font_size", 15)
	_civ_check.toggled.connect(func(on: bool) -> void:
		_show_civilians = on
		refresh())
	UiStyle.header_add(title_row, _civ_check)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(_section("Einheitentypen"))
	_type_empty = _label(ROW_FONT, COLOR_DIM)
	_type_empty.text = "Noch keine Truppen – in der Kaserne Kämpfer und Schützen beschwören."
	list.add_child(_type_empty)
	_type_grid = _grid(7)
	list.add_child(_type_grid)
	list.add_child(_section("Helden"))
	_hero_empty = _label(ROW_FONT, COLOR_DIM)
	_hero_empty.text = "Keine Helden – Heldenfenster (G) → Anwerben."
	list.add_child(_hero_empty)
	_hero_grid = _grid(7)
	list.add_child(_hero_grid)
	list.add_child(_section("Armeen"))
	_army_empty = _label(ROW_FONT, COLOR_DIM)
	_army_empty.text = "Keine Armeen – Einheiten auswählen und rechts „Auswahl → Armee“ oder Strg+1…9."
	list.add_child(_army_empty)
	_army_grid = _grid(8)
	list.add_child(_army_grid)
	body.add_child(_build_side())

	var footer := _label(15, COLOR_DIM)
	footer.text = "Befehle gelten für die Befehlsgruppe („Wählen“)  ·  Strg+A: alle Krieger  ·  T / Esc: schliessen"
	root.add_child(footer)


## Rechte Spalte: Auswahl, Befehle, Formation, Haltung
func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_theme_constant_override("separation", 6)
	side.add_child(_section("Auswahl"))
	var all := _button("Alle Krieger auswählen (Strg+A)", "Alle eigenen Truppen und Helden auswählen – ohne Bewohner und König")
	all.pressed.connect(choose_group.bind(GROUP_ALL, ""))
	side.add_child(all)
	buttons["all"] = all
	var row := _hbox(side)
	var idle := _button("Untätige", "Krieger auswählen, die gerade nichts tun (stehen, halten, ruhen)")
	idle.pressed.connect(choose_group.bind(GROUP_IDLE, ""))
	idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(idle)
	buttons["idle"] = idle
	var hurt := _button("Verwundete", "Krieger unter %d %% Leben auswählen (z. B. für den Rückzug zur Burg)" % roundi(WOUNDED_RATIO * 100.0))
	hurt.pressed.connect(choose_group.bind(GROUP_WOUNDED, ""))
	hurt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hurt)
	buttons["wounded"] = hurt
	_group_label = _label(15, COLOR_TEXT)
	_group_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_group_label.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_child(_group_label)
	var assign_label := _label(14, COLOR_DIM)
	assign_label.text = "Auswahl als Armee speichern:"
	side.add_child(assign_label)
	var assign_row := _hbox(side)
	assign_row.add_theme_constant_override("separation", 3)
	for n in range(1, 10):
		var b := _button(str(n), "Ausgewählte eigene Einheiten als Armee %d speichern (wie Strg+%d)" % [n, n])
		b.custom_minimum_size = Vector2(28, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(assign_selection_to_army.bind(n))
		assign_row.add_child(b)
		_army_assign.append(b)

	side.add_child(_section("Befehle an die Gruppe"))
	var grid := _grid(2)
	side.add_child(grid)
	for entry in [["gather", "Sammeln an der Burg", "Die Gruppe marschiert in Formation zum Sammelplatz vor der Burg und hält dort"],
			["retreat", "Rückzug zur Burg", "Ohne zu kämpfen zur Burg; dort erholen sich die Einheiten deutlich schneller"],
			["attack_move", "Angreifend vorrücken …", "Danach Ziel auf der Karte anklicken: die Gruppe marschiert und kämpft unterwegs (Esc bricht ab)"],
			["move", "Bewegen …", "Danach Ziel auf der Karte anklicken: die Gruppe marschiert, ohne Feinde anzugreifen (Esc bricht ab)"],
			["patrol", "Patrouille …", "Danach Ziel auf der Karte anklicken: die Gruppe läuft zwischen ihrem Ort und dem Ziel hin und her und kämpft unterwegs"],
			["hold", "Halten", "Stehen bleiben und den Platz verteidigen (je nach Haltung)"]]:
		var b := _button(str(entry[1]), str(entry[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(order.bind(str(entry[0])))
		grid.add_child(b)
		buttons[str(entry[0])] = b

	side.add_child(_section("Formation"))
	var frow := _hbox(side)
	for f in CommandSystem.FORMATIONS:
		var fname := CommandSystem.get_formation_name(f)
		var b := _button(fname, "Formation %s für die nächsten Marschbefehle (auch Taste F); die Gruppe stellt sich an ihrem Ort so auf" % fname)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_formation.bind(str(f)))
		frow.add_child(b)
		_formation_buttons[f] = b

	side.add_child(_section("Haltung"))
	var srow := _hbox(side)
	for s in CommandSystem.STANCES:
		var b := _button(CommandSystem.get_stance_name(s), str(CommandSystem.STANCE_TIPS[s]))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_stance.bind(str(s)))
		srow.add_child(b)
		_stance_buttons[s] = b
	_stance_label = _label(14, COLOR_DIM)
	side.add_child(_stance_label)
	return side


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func refresh() -> void:
	if game == null:
		return
	var k: Kingdom = game.player
	var by_type := {}
	var heroes: Array = []
	var warriors := 0
	var fighting := 0
	for u in k.units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var unit: Unit = u
		var warrior := CommandSystem.is_warrior(unit)
		if warrior:
			warriors += 1
			if unit_state(unit) == STATE_FIGHTING:
				fighting += 1
		if unit.hero_id != 0:
			heroes.append(unit)
			continue
		if not warrior and not (_show_civilians and (unit.role == "worker" or unit.role == "king")):
			continue
		if not by_type.has(unit.type_id):
			by_type[unit.type_id] = []
		(by_type[unit.type_id] as Array).append(unit)
	var armies := 0
	for n in k.armies:
		if not game.command_system.get_army(k, int(n)).is_empty():
			armies += 1
	_set_label(_summary, "%d Krieger · %d im Kampf · %d Helden · %d Armeen" % [warriors, fighting, heroes.size(), armies])
	_refresh_types(by_type)
	_refresh_heroes()
	_refresh_armies()
	_refresh_side()


func _refresh_types(by_type: Dictionary) -> void:
	var keys: Array = by_type.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ua: Unit = (by_type[a] as Array)[0]
		var ub: Unit = (by_type[b] as Array)[0]
		if ua.formation_rank != ub.formation_rank:
			return ua.formation_rank < ub.formation_rank
		return ua.get_display_name() < ub.get_display_name())
	if keys != _type_keys:
		_type_keys = keys
		_clear(_type_grid)
		_type_rows.clear()
		for key in keys:
			var first: Unit = (by_type[key] as Array)[0]
			var icon := UnitIcon.new()
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.setup(first.type_def, game.player)
			var type_name := first.get_display_name()
			_type_rows[key] = _add_row(_type_grid, icon, type_name,
					"Alle %s auswählen – die Befehle rechts gelten dann für sie" % type_name,
					choose_group.bind(GROUP_TYPE, str(key)), _jump_type.bind(str(key)))
	_type_empty.visible = keys.is_empty()
	_type_grid.visible = not keys.is_empty()
	for key in keys:
		var units: Array = by_type[key]
		var row: Dictionary = _type_rows[key]
		var hp := 0.0
		var max_hp := 0.0
		for u in units:
			hp += (u as Unit).hp
			max_hp += (u as Unit).max_hp
		_set_label(row["count"], "%d" % units.size())
		(row["bar"] as HpBar).set_value(hp, max_hp, "%d / %d (Ø %d)" % [ceili(hp), roundi(max_hp), ceili(hp / units.size())])
		_set_info(row["info"], states_text(count_states(units)))
		_mark_group(row, _group_kind == GROUP_TYPE and _group_key == str(key))


func _refresh_heroes() -> void:
	var k: Kingdom = game.player
	var hs: HeroSystem = game.hero_system
	var records: Array = hs.get_heroes(k)
	var keys: Array = []
	for rec in records:
		keys.append(int(rec["id"]))
	if keys != _hero_keys:
		_hero_keys = keys
		_clear(_hero_grid)
		_hero_rows.clear()
		for rec in records:
			var portrait := HeroPortrait.new()
			portrait.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			portrait.setup(hs.get_type(rec))
			var title := hs.get_title(rec)
			_hero_rows[int(rec["id"])] = _add_row(_hero_grid, portrait, title,
					"%s auswählen – die Befehle rechts gelten dann für ihn" % title,
					choose_group.bind(GROUP_HERO, str(rec["id"])), _jump_hero.bind(int(rec["id"])))
	_hero_empty.visible = keys.is_empty()
	_hero_grid.visible = not keys.is_empty()
	var cs: CommandSystem = game.command_system
	for rec in records:
		var row: Dictionary = _hero_rows[int(rec["id"])]
		var u: Unit = hs.get_unit(k, int(rec["id"]))
		var dead := bool(rec["dead"]) or u == null
		(row["icon"] as HeroPortrait).set_state(dead, int(rec["level"]), int(rec["pending"]) > 0)
		_set_label(row["count"], "St. %d" % int(rec["level"]))
		var bar: HpBar = row["bar"]
		if dead:
			bar.set_value(0.0, 1.0, "gefallen")
		else:
			bar.set_value(u.hp, u.max_hp)
		var info := HeroUI.state_text(hs, rec, u)
		if not dead:
			var n := cs.get_army_number(u)
			if n > 0:
				info += " · Armee %d" % n
			if u.stance != CommandSystem.DEFAULT_STANCE:
				info += " · " + CommandSystem.get_stance_name(u.stance)
		_set_info(row["info"], info)
		(row["select"] as Button).disabled = dead
		(row["jump"] as Button).disabled = dead
		_mark_group(row, _group_kind == GROUP_HERO and _group_key == str(rec["id"]))


func _refresh_armies() -> void:
	var k: Kingdom = game.player
	var cs: CommandSystem = game.command_system
	var keys: Array = []
	var lists := {}
	for n in range(1, ArmyBar.MAX_ARMIES + 1):
		if not k.armies.has(n):
			continue
		var units := cs.get_army(k, n)
		if units.is_empty():
			continue
		keys.append(n)
		lists[n] = units
	if keys != _army_keys:
		_army_keys = keys
		_clear(_army_grid)
		_army_rows.clear()
		for n in keys:
			var badge := _label(18, ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_ACCENT)
			badge.text = str(n)
			badge.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var row := _add_row(_army_grid, badge, "Armee %d" % n,
					"Armee %d auswählen (wie Taste %d) – die Befehle rechts gelten dann für sie" % [n, n],
					choose_group.bind(GROUP_ARMY, str(n)), _jump_army.bind(n))
			var dissolve := _button("✕", "Armee %d auflösen (die Einheiten bleiben, wo sie sind)" % n)
			dissolve.pressed.connect(dissolve_army.bind(n))
			_army_grid.add_child(dissolve)
			row["dissolve"] = dissolve
			_army_rows[n] = row
	_army_empty.visible = keys.is_empty()
	_army_grid.visible = not keys.is_empty()
	for n in keys:
		var units: Array = lists[n]
		var row: Dictionary = _army_rows[n]
		var hp := 0.0
		var max_hp := 0.0
		for u in units:
			hp += (u as Unit).hp
			max_hp += (u as Unit).max_hp
		_set_label(row["count"], "%d" % units.size())
		(row["bar"] as HpBar).set_value(hp, max_hp, "Stärke %d" % strength_of(units))
		_set_info(row["info"], "%s · %s" % [location_text(centroid_of(units)), order_text(units)])
		_mark_group(row, _group_kind == GROUP_ARMY and _group_key == str(n))


## Befehlsgruppe, Formation und Haltung (gedrückt = gilt für die ganze Gruppe)
func _refresh_side() -> void:
	var units := group_units()
	var text := "Befehlsgruppe: %s – %s" % [group_name(), "keine Einheiten" if units.is_empty()
			else ("1 Einheit" if units.size() == 1 else "%d Einheiten" % units.size())]
	_set_label(_group_label, text)
	for f in _formation_buttons:
		(_formation_buttons[f] as Button).set_pressed_no_signal(game.player.formation == f)
	var stances := {}
	for u in units:
		stances[(u as Unit).stance] = true
	for s in _stance_buttons:
		(_stance_buttons[s] as Button).set_pressed_no_signal(stances.size() == 1 and stances.has(s))
	_set_label(_stance_label, "Haltung gemischt" if stances.size() > 1 else "")
	var has_selection: bool = not game.selection.get_own_units().is_empty()
	for b in _army_assign:
		(b as Button).disabled = not has_selection
	for key in ["gather", "retreat", "attack_move", "move", "patrol", "hold"]:
		(buttons[key] as Button).disabled = units.is_empty()


## Ort als Text: "Eigenes Gebiet, 12 Kacheln nordöstlich der Burg"
func location_text(pos: Vector2) -> String:
	var world: WorldData = game.world
	var k: Kingdom = game.player
	var owner_id := world.get_owner(world.world_to_cell(pos))
	var area := "Niemandsland"
	if owner_id == k.id:
		area = "Eigenes Gebiet"
	elif owner_id != 0:
		var other: Kingdom = game.get_kingdom(owner_id)
		area = "Gebiet: %s" % (other.display_name if other != null else "fremd")
	if not is_instance_valid(k.castle):
		return area
	var d := pos - k.castle.get_center()
	var tiles := roundi(d.length() / float(world.tile_size))
	if tiles <= 6:
		return area + ", bei der Burg"
	var dir: String = COMPASS[posmod(roundi(d.angle() / (TAU / 8.0)), 8)]
	return "%s, %d Kacheln %s der Burg" % [area, tiles, dir]


func _jump_type(type_id: String) -> void:
	var list: Array = []
	for u in game.player.units:
		if is_instance_valid(u) and u.is_alive() and u.hero_id == 0 and u.type_id == type_id:
			list.append(u)
	_jump_to(list)


func _jump_hero(hero_id: int) -> void:
	var u: Unit = game.hero_system.get_unit(game.player, hero_id)
	if u != null:
		_jump_to([u])


func _jump_army(n: int) -> void:
	_jump_to(game.command_system.get_army(game.player, n))


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Eine Zeile in grid: Bild, Name, Anzahl, Lebensbalken, Infotext, "Wählen", "Hin"
func _add_row(grid: GridContainer, icon: Control, title: String, select_tip: String,
		on_select: Callable, on_jump: Callable) -> Dictionary:
	grid.add_child(icon)
	var name_label := _label(ROW_FONT, COLOR_TEXT)
	name_label.text = title
	name_label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	name_label.clip_text = true
	grid.add_child(name_label)
	var count := _label(ROW_FONT, COLOR_TEXT)
	count.custom_minimum_size = Vector2(COUNT_WIDTH, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(count)
	var bar := HpBar.new()
	bar.custom_minimum_size = Vector2(BAR_WIDTH, 20)
	bar.font_size = 13
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(bar)
	var info := _label(14, COLOR_DIM)
	info.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	info.clip_text = true
	# Langer Text: ganz im Tooltip
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(info)
	var select := _button("Wählen", select_tip)
	select.pressed.connect(on_select)
	grid.add_child(select)
	var jump := _button("Hin", "Kamera zu diesen Einheiten")
	jump.pressed.connect(on_jump)
	grid.add_child(jump)
	return {"icon": icon, "name": name_label, "count": count, "bar": bar, "info": info, "select": select, "jump": jump}


## Zeile der Befehlsgruppe hervorheben (Name in Akzentfarbe)
func _mark_group(row: Dictionary, on: bool) -> void:
	var label: Label = row["name"]
	var color := (ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_ACCENT) if on else COLOR_TEXT
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _clear(grid: GridContainer) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grid


func _hbox(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


func _place() -> void:
	if not visible:
		return
	UiStyle.place_window(self, DESIGN_WIDTH, TOP)


func _panel_style() -> StyleBoxFlat:
	return UiStyle.window_style(_evil)


func _section(text: String) -> Label:
	var l := _label(18, ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_ACCENT)
	l.text = text
	return l


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Schmaler Innenabstand (wie die Armeeleiste): viele Knöpfe nebeneinander
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := b.get_theme_stylebox(style_name, "Button")
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = BUTTON_MARGIN
		style.content_margin_right = BUTTON_MARGIN
		b.add_theme_stylebox_override(style_name, style)
	return b


func _set_label(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


## Infotext einer Zeile (auch als Tooltip, falls er abgeschnitten wird)
func _set_info(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
		label.tooltip_text = text
