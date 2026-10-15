## SelectionPanel
##
## Auswahlfenster unten links (über der Armeeleiste und dem Infobereich).
## Je nach Auswahl (SelectionController) zeigt es:
## - eine eigene Einheit: Name (+ Armee), Leben, Kampfwerte, Zustand, Boni,
##   Beruf (wenn sie arbeiten kann) und Befehle (Halt, Zur Arbeit,
##   Angriff-Vorrücken); beim König zusätzlich, dass er im Reich bleibt.
## - mehrere eigene Einheiten: Anzahl je Typ, gesamtes Leben, Befehle, Formation.
## - ein eigenes Gebäude: Bauzustand, Wohnraum, Annahme, Produktion, Leben,
##   Arbeiter (−/+), Beschwören mit Warteschlange und Sammelpunkt, Abreissen.
## - Fremdes (Monsterhöhle, Monster, Gegner): nur Anzeige – Reich, Leben,
##   Kampfwerte bzw. was im Lager wartet. Feindliche Königreiche (Phase 7) je nach
##   Kundschaft: ohne Bericht "?" statt Werten, Wirkungen erst bei genauer
##   Kundschaft; ihre Burg zeigt die Zusammenfassung des Reichs. Enttarnte fremde
##   Spione tragen "(enttarnt)" im Titel.
## - Eigene Spione: Stufe, Erfahrung, Auftrag, Fortschritt, Entdeckungsgefahr und
##   der Knopf "Auftrag (K)" (öffnet das Spionagefenster beim Spion).
## - Helden (auch der aktive Held einer gemischten Auswahl): Stufe, Erfahrung,
##   Stufenwahl und die Fähigkeitsknöpfe C / V / B (HeroSelectionBox); Burg:
##   gefallene Helden wiederbeleben; Heldenhalle: Ausbildung.
## - Truppen (TroopSelectionBox): Rang, Erfahrung, Wertepunkte, Aussehen; mehrere
##   Einheiten: "Punkte automatisch verteilen"; Schmiede: Waffen- und Rüstungsstufen.
## - Magie: bei einer Einheit laufende Zauberwirkungen (Restzeit, in der
##   Zauberfarbe), "Getarnt" und bei beschworenen Wächtern die Restzeit;
##   bei der Forschungsstätte die laufende Forschung und "Forschung öffnen (R)".
## - Neutrale Dörfer (Dorfgebäude, Milizen, Boten): Volk, Ruf zum Spieler mit
##   Stufe, Vertrag, Produktion, Miliz und der Knopf "Diplomatie (N)"; Boten:
##   von wem zu wem. Eigene aufgenommene Dorfzentren: Ertrag des Dorfs.
## Aktualisiert wird bei Auswahlwechsel, bei Signalen (Warteschlange,
## Ressourcen, Formation) und alle 0.25 s, solange das Fenster sichtbar ist.
## Bedienelemente stehen unten und behalten ihre Höhe, damit sie nicht unter
## dem Mauszeiger verrutschen (das Fenster wächst nach oben).
class_name SelectionPanel
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const DIRTY_INTERVAL := 0.1
const CONFIRM_SECONDS := 3.0
const PANEL_WIDTH := 420.0
const COLOR_TITLE := Color(1.0, 0.86, 0.55)
const COLOR_WARN := Color(1.0, 0.62, 0.22)
const COLOR_DIM := Color(0.8, 0.78, 0.72)
const COLOR_GREY := Color(0.64, 0.62, 0.58)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const FONT_SIZE := 16
const SMALL_FONT_SIZE := 15
const QUEUE_SLOTS := 5
const QUEUE_SLOT_SIZE := 40.0
## Unter dieser Reichweite (Kacheln) heisst es "Nahkampf"
const MELEE_RANGE := 1.5
## Feste Zeilenumbrüche: sonst bricht die Zeile mitten in "F: Formation"
const MULTI_HINT := "Rechtsklick: bewegen/angreifen\nStrg+Rechtsklick: angreifend vorrücken\nStrg+1–9: Armee speichern · F: Formation"
const KING_NOTE := "Der König verlässt sein Reich nicht."
const NO_JOB_TIP := "Kein Beruf – wähle oben einen Beruf"
const ATTACK_MOVE_TIP := "Nächster Rechtsklick: angreifend vorrücken (auch Strg+Rechtsklick)"
const CANCEL_TIP := "Abbrechen – Kosten werden erstattet"
## Höchstens so viele Zeilen mit Zauberwirkungen
const MAGIC_LINES := 4
const COLOR_RESEARCH := Color(0.45, 0.64, 1.0)
## Durch Forschung oder Zauber gestärkter Wert
const COLOR_UP := Color(0.62, 0.94, 0.55)

var game: Node

## Angezeigtes Hauptobjekt (Building oder Unit) oder null
var _target: Object = null
## "unit", "units" (mehrere eigene), "building" oder ""
var _mode := ""
var _title: Label
var _owner: Label
var _hp_bar: HpBar
var _stats_grid: GridContainer
## Schlüssel- und Wert-Labels der Kampfwerte (je 4)
var _stat_keys: Array[Label] = []
var _stat_values: Array[Label] = []
var _status: Label
var _warn: Label
var _facts: Label
var _bonus: Label
var _note: Label
## Zauberwirkungen, Tarnung, Restzeit beschworener Einheiten (eine Zeile je Eintrag)
var _magic_box: VBoxContainer
var _magic_lines: Array[Label] = []
# Forschungsstätte
var _research_label: Label
var _research_bar: HpBar
var _research_button: Button

# Beschwören
var _summon_box: VBoxContainer
var _summon_header: Label
## Sammelpunkt-Zeile (bei der Heldenhalle aus: Helden erscheinen an der Halle)
var _rally_row: HBoxContainer
var _summon_list: VBoxContainer
## Je Einheitentyp: {"id", "def", "button", "row", "costs": {res_id: [Label, Menge]}}
var _summon_entries: Array = []
## Gebäude, für das die Beschwörungs-Buttons gebaut wurden
var _summon_building: Object = null
var _summon_ids: PackedStringArray = []
var _queue_slots: Array[Button] = []
var _queue_icons: Array[UnitIcon] = []
var _queue_label: Label
var _rally_label: Label
var _rally_clear: Button

var _worker_row: HBoxContainer
var _worker_label: Label
var _worker_minus: Button
var _worker_plus: Button
var _job_row: HBoxContainer
var _job_option: OptionButton
## Beruf-IDs in der Reihenfolge der Auswahlliste
var _job_ids: PackedStringArray = []

# Befehle
var _actions: GridContainer
var _halt_button: Button
var _work_button: Button
var _attack_move_button: Button
var _formation_button: Button

## Helden-Abschnitt (Stufe, Fähigkeiten; Burg: Wiederbeleben; Halle: Ausbildung)
var _hero_box: HeroSelectionBox
## Truppen-Abschnitt (Rang, Wertepunkte, Aussehen; Schmiede)
var _troop_box: TroopSelectionBox
## Dorf-Zeile: Knopf "Diplomatie (N)" für Dorfgebäude, Milizen und Boten
var _village_row: HBoxContainer
var _diplo_button: Button
## Eigener Spion: Knopf "Auftrag (K)"
var _spy_row: HBoxContainer
var _spy_button: Button
## Dorf des angezeigten Objekts (für den Knopf; 0 = keins)
var _village_id := 0
## Eigenes Tor: Knopf "Verriegeln"/"Öffnen" (Phase 9)
var _gate_row: HBoxContainer
var _gate_button: Button

var _demolish_button: Button
## Zufriedenheit eines Bewohners bzw. Ø der Auswahl (Phase 8) und Flüchtlinge aufnehmen
var _mood_row: ResourceBar.TipBox
var _mood_icon: MoodIcon
var _mood_label: Label
var _refugee_row: HBoxContainer
var _refugee_offer_id := 0
## Restzeit der Abriss-Bestätigung (Echtzeit, 0 = keine Bestätigung offen)
var _confirm_left := 0.0
var _timer := 0.0
## Ein Signal hat eine Änderung gemeldet: im nächsten Bild neu aufbauen
var _dirty := false
## Zwischenspeicher der Mehrfachauswahl (-1 = neu zählen)
var _multi_size := -1
var _multi_counts := ""
var _multi_workers := 0
var _multi_with_job := 0
var _multi_army := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_title = _make_label(vbox, 20, COLOR_TITLE)
	_owner = _make_label(vbox, 15, COLOR_DIM)
	_hp_bar = HpBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(_hp_bar)
	_build_stats_grid(vbox)
	_status = _make_label(vbox, FONT_SIZE, COLOR_DIM)
	_warn = _make_label(vbox, FONT_SIZE, COLOR_WARN)
	_facts = _make_label(vbox, FONT_SIZE, COLOR_TEXT)
	_research_label = _make_label(vbox, FONT_SIZE, COLOR_TEXT)
	_research_bar = HpBar.new()
	_research_bar.fill_color = COLOR_RESEARCH
	_research_bar.visible = false
	vbox.add_child(_research_bar)
	_bonus = _make_label(vbox, SMALL_FONT_SIZE, COLOR_GREY)
	_build_mood_row(vbox)
	_magic_box = VBoxContainer.new()
	_magic_box.add_theme_constant_override("separation", 0)
	_magic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_magic_box.visible = false
	vbox.add_child(_magic_box)
	for i in MAGIC_LINES:
		var line := _make_label(_magic_box, SMALL_FONT_SIZE, COLOR_TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.visible = false
		_magic_lines.append(line)
	_note = _make_label(vbox, SMALL_FONT_SIZE, COLOR_GREY)

	# Bedienelemente stehen unten, damit sie bei wechselnder Textlänge
	# nicht unter dem Mauszeiger verrutschen (das Fenster wächst nach oben).
	_build_summon_box(vbox)

	_worker_row = HBoxContainer.new()
	_worker_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_worker_row)
	_worker_label = Label.new()
	_worker_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_worker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_worker_row.add_child(_worker_label)
	_worker_minus = JobPanel.make_small_button("−", self)
	_worker_minus.tooltip_text = "Einen Arbeiter abziehen (wird unbeschäftigt)"
	_worker_minus.pressed.connect(_on_worker_minus)
	_worker_row.add_child(_worker_minus)
	_worker_plus = JobPanel.make_small_button("+", self)
	_worker_plus.pressed.connect(_on_worker_plus)
	_worker_row.add_child(_worker_plus)

	_job_row = HBoxContainer.new()
	_job_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_job_row)
	var job_label := Label.new()
	job_label.text = "Beruf:"
	job_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_job_row.add_child(job_label)
	_job_option = OptionButton.new()
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) die Liste öffnen
	_job_option.focus_mode = Control.FOCUS_NONE
	_job_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_option.add_theme_font_size_override("font_size", FONT_SIZE)
	_job_option.tooltip_text = "Beruf dieser Einheit ändern"
	_job_option.item_selected.connect(_on_job_selected)
	_job_row.add_child(_job_option)

	_hero_box = HeroSelectionBox.new()
	vbox.add_child(_hero_box)

	_troop_box = TroopSelectionBox.new()
	vbox.add_child(_troop_box)

	_village_row = HBoxContainer.new()
	_village_row.add_theme_constant_override("separation", 6)
	_village_row.visible = false
	vbox.add_child(_village_row)
	_diplo_button = Button.new()
	_diplo_button.text = "Diplomatie (N)"
	_diplo_button.focus_mode = Control.FOCUS_NONE
	_diplo_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_diplo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diplo_button.tooltip_text = "Diplomatiefenster bei diesem Dorf öffnen: Geschenke, Handel, Verträge, Aufnahme"
	_diplo_button.pressed.connect(_on_diplo_pressed)
	_village_row.add_child(_diplo_button)

	_spy_row = HBoxContainer.new()
	_spy_row.add_theme_constant_override("separation", 6)
	_spy_row.visible = false
	vbox.add_child(_spy_row)
	_spy_button = Button.new()
	_spy_button.text = "Auftrag (K)"
	_spy_button.focus_mode = Control.FOCUS_NONE
	_spy_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_spy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spy_button.tooltip_text = "Spionagefenster bei diesem Spion öffnen: Auskundschaften, Dorf oder Rivalen aufhetzen"
	_spy_button.pressed.connect(_on_spy_pressed)
	_spy_row.add_child(_spy_button)

	_build_refugee_row(vbox)

	_gate_row = HBoxContainer.new()
	_gate_row.visible = false
	vbox.add_child(_gate_row)
	_gate_button = Button.new()
	_gate_button.focus_mode = Control.FOCUS_NONE
	_gate_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_gate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gate_button.tooltip_text = "Verriegelt: nur eigene und verbündete Einheiten. Feinde kommen nie hindurch."
	_gate_button.pressed.connect(_on_gate_pressed)
	_gate_row.add_child(_gate_button)

	_build_actions(vbox)

	_research_button = Button.new()
	_research_button.text = "Forschung öffnen (R)"
	_research_button.focus_mode = Control.FOCUS_NONE
	_research_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_research_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_button.tooltip_text = "Forschungsfenster öffnen: Forschungen wählen, Warteschlange, Mana-Verbesserungen"
	_research_button.visible = false
	_research_button.pressed.connect(_on_research_pressed)
	vbox.add_child(_research_button)

	_demolish_button = Button.new()
	_demolish_button.focus_mode = Control.FOCUS_NONE
	_demolish_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_demolish_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_demolish_button.custom_minimum_size = Vector2(170, 0)
	_demolish_button.pressed.connect(_on_demolish_pressed)
	vbox.add_child(_demolish_button)


func setup(p_game: Node) -> void:
	game = p_game
	_job_option.clear()
	_job_ids.clear()
	for j in DataDB.jobs:
		var job: Dictionary = j
		_job_ids.append(str(job.get("id", "")))
		_job_option.add_item(str(job.get("name", job.get("id", ""))))
	game.selection.selection_changed.connect(_on_selection_changed)
	game.selection.attack_move_armed_changed.connect(_on_attack_move_armed_changed)
	game.summon_system.queue_changed.connect(_on_queue_changed)
	game.formation_changed.connect(_on_formation_changed)
	game.player.resources_changed.connect(_on_resources_changed)
	game.work_system.jobs_changed.connect(_on_jobs_changed)
	game.command_system.armies_changed.connect(_on_armies_changed)
	_hero_box.setup(game)
	_troop_box.setup(game)
	game.troop_system.troops_changed.connect(_on_troops_changed)
	game.selection.focus_hero_changed.connect(_on_focus_hero_changed)
	game.hero_system.heroes_changed.connect(_on_heroes_changed)
	_on_selection_changed(game.selection.selected)


func _process(delta: float) -> void:
	if game == null:
		return
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_confirm_left = 0.0
			_dirty = true
	if not visible and not _dirty:
		return
	_timer += delta
	# Gemeldete Änderungen höchstens zehnmal pro Sekunde, sonst alle 0.25 s
	if (_dirty and _timer >= DIRTY_INTERVAL) or _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_dirty = false
		_refresh()


func _on_selection_changed(_objs: Array) -> void:
	# Untypisiert übernehmen: ein bereits gelöschtes Objekt darf nicht in eine
	# typisierte Variable
	var primary: Variant = game.selection.get_primary()
	if not is_instance_valid(primary):
		primary = null
	if primary != _target:
		_confirm_left = 0.0
	_target = primary
	_multi_size = -1
	_timer = 0.0
	_dirty = false
	_refresh()


func _on_queue_changed(b: Building) -> void:
	if b == _target:
		_dirty = true


## Ressourcen ändern sich sehr oft (jede Lieferung) – nur vormerken
func _on_resources_changed() -> void:
	if _mode == "building" and _summon_box.visible:
		_dirty = true


## Berufe oder Armeen geändert: Zusammensetzung der Mehrfachauswahl neu zählen
func _on_jobs_changed(k: Kingdom) -> void:
	if k == game.player and _mode != "":
		_multi_size = -1
		_dirty = true


func _on_armies_changed(k: Kingdom) -> void:
	if k == game.player and _mode != "":
		_multi_size = -1
		_dirty = true


## Tab: anderer aktiver Held der Auswahl
func _on_focus_hero_changed(_u: Unit) -> void:
	if _mode != "":
		_dirty = true


## Helden geändert (Stufe, Wahl, Tod, Wiederbelebung …)
func _on_heroes_changed(k: Kingdom) -> void:
	if k == game.player and _mode != "":
		_dirty = true


## Schmiede, Wertepunkte, Aussehen oder Rang geändert
func _on_troops_changed(k: Kingdom) -> void:
	if k == game.player and _mode != "":
		_dirty = true


func _on_formation_changed(_formation: String) -> void:
	_update_formation_button()


func _on_attack_move_armed_changed(armed: bool) -> void:
	_attack_move_button.set_pressed_no_signal(armed)


func _refresh() -> void:
	# Zuerst prüfen, ob das Objekt noch existiert – erst dann den Typ
	if not is_instance_valid(_target) or not _target.is_alive():
		_target = null
	_gate_row.visible = false
	# Mehrfachauswahl nur prüfen, wenn mehr als ein Objekt gewählt ist
	var sel: Array = game.selection.selected
	var own_units: Array = _own_units(sel) if sel.size() > 1 else []
	if own_units.size() > 1:
		_mode = "units"
		visible = true
		_show_units(own_units)
	elif _target is Unit:
		_mode = "unit"
		visible = true
		_show_unit(_target as Unit)
	elif _target is Building:
		_mode = "building"
		visible = true
		_show_building(_target as Building)
	else:
		_mode = ""
		visible = false
		_hero_box.hide_box()
		_troop_box.hide_box()
	if _mode != "unit" and _mode != "building":
		_show_village_row(null)
	if _mode != "unit" and _spy_row.visible:
		_spy_row.visible = false


# ---------------------------------------------------------------------------
# Gebäude
# ---------------------------------------------------------------------------

func _show_building(b: Building) -> void:
	var k: Kingdom = game.player
	var ws: WorkSystem = game.work_system
	var own := b.kingdom == k
	var title := b.get_display_name()
	if not b.constructed:
		title += " (Baustelle)"
	_set_text(_title, title)
	_show_owner(b.kingdom)
	_stats_grid.visible = false
	_set_text(_bonus, "")
	_set_text(_note, "")
	_job_row.visible = false
	_actions.visible = false
	_mood_row.visible = false
	_refugee_row.visible = false

	# Leben: fremde Gebäude, beschädigte und solche, die Einheiten beschwören (Befestigungen immer)
	var summons: Array = b.get_summon_tiers()
	_hp_bar.visible = b.constructed and (not own or b.hp < b.max_hp or not summons.is_empty() or b == k.castle
			or b.fort_kind != "")
	if _hp_bar.visible:
		_hp_bar.set_value(b.hp, b.max_hp)

	var status := ""
	var warn := ""
	if not b.constructed:
		status = "Im Bau: %d %%" % roundi(b.get_progress_ratio() * 100.0)
		if own and ws.get_job_count(k, "builder") == 0:
			warn = "Wartet auf Bauarbeiter – weise Bauarbeiter zu (J)"
	_set_text(_status, status)
	_set_text(_warn, warn)

	var vs: VillageSystem = game.village_system
	if game.monster_system.lairs.has(b):
		_set_text(_facts, _lair_text(b))
	elif vs.is_village(b.kingdom):
		_set_text(_facts, vs.get_summary_text(b.kingdom, k))
	elif b.fort_kind != "":
		_set_text(_facts, game.siege_system.get_building_facts(b))
		# Eigenes Tor: verriegeln oder öffnen
		if own and b.fort_kind == "gate":
			_gate_row.visible = true
			_set_button_text(_gate_button, "Öffnen" if game.siege_system.is_gate_locked(b) else "Verriegeln")
	elif b.kingdom.controller == "ai":
		# Feindliches Königreich: öffentlich sind nur Name und Leben; die Burg zeigt,
		# was die Kundschaft über das Reich weiss
		# (ohne die erste Zeile "Kundschaft: …" – die steht schon beim Reich)
		var summary := ""
		if b == b.kingdom.castle:
			summary = game.espionage_system.get_kingdom_summary(b.kingdom, k)
			summary = summary.substr(summary.find("\n") + 1) if summary.contains("\n") else ""
		_set_text(_facts, summary)
	else:
		var facts := _building_facts(b)
		var annexed := vs.get_annexed_text(b) if own else ""
		if not annexed.is_empty():
			facts = annexed if facts.is_empty() else facts + "\n" + annexed
		_set_text(_facts, facts)
	_show_village_row(b.kingdom if vs.is_village(b.kingdom) else null)
	_magic_box.visible = false
	_show_research(b, own)
	_hero_box.show_building(b if own else null)
	_troop_box.show_building(b if own else null)

	# Beschwören (nur eigene, fertige Gebäude)
	# Heldenhalle: Anwerben über dieselben Knöpfe (Angebote vom HeroSystem), ohne Sammelpunkt
	var hero_hall := bool(b.def.get("hero_hall", false))
	var can_summon := own and b.constructed and (not summons.is_empty() or hero_hall)
	_summon_box.visible = can_summon
	if can_summon:
		_set_label_text(_summon_header, "Helden anwerben" if hero_hall else "Beschwören")
		_rally_row.visible = not hero_hall
		_refresh_summons(b)

	# Arbeiter
	var slots := b.get_worker_slots()
	var show_workers := own and b.constructed and slots > 0
	_worker_row.visible = show_workers
	if show_workers:
		_set_text(_worker_label, "Arbeiter: %d/%d" % [b.workers.size(), slots])
		_worker_minus.disabled = b.workers.is_empty()
		var idle := ws.get_idle_count(k)
		var tip := "Einen unbeschäftigten Bewohner hier arbeiten lassen"
		if idle == 0:
			tip = JobPanel.NO_IDLE_TIP
		elif not b.has_free_slot():
			tip = "Alle Arbeitsplätze sind besetzt."
		_worker_plus.disabled = idle == 0 or not b.has_free_slot()
		_worker_plus.tooltip_text = tip

	# Abreissen / Bau abbrechen (nicht für die Burg)
	var can_remove := own and b != b.kingdom.castle
	_demolish_button.visible = can_remove
	if can_remove:
		if _confirm_left > 0.0:
			_set_button_text(_demolish_button, "Wirklich? (Klick)")
		else:
			_set_button_text(_demolish_button, "Abreissen" if b.constructed else "Bau abbrechen")
		var refund := float(DataDB.eco("demolish_refund", 0.5)) if b.constructed else float(DataDB.eco("cancel_refund", 1.0))
		_demolish_button.tooltip_text = "%s – du erhältst %d %% der Kosten zurück.\nZum Bestätigen zweimal klicken." % [
			"Gebäude abreissen" if b.constructed else "Baustelle aufgeben", roundi(refund * 100.0)]


## Wohnraum, Annahme, Sammelradius, Produktion … (Phase-2-Inhalt)
func _building_facts(b: Building) -> String:
	var ws: WorkSystem = game.work_system
	var facts: PackedStringArray = []
	var def := b.def
	var housing := int(def.get("housing", 0))
	if housing > 0:
		facts.append("Wohnraum: %d" % housing if b.constructed else "Wohnraum: +%d (wenn fertig)" % housing)
	var dropoff: Array = def.get("dropoff", [])
	if not dropoff.is_empty():
		facts.append("Annahme: " + BuildMenu.resource_names(dropoff))
		if b.constructed:
			facts.append("Liefern hier an: %d" % ws.get_delivering_count(b))
	var gather := b.get_gather_radius()
	if gather > 0:
		var gather_text := "Sammelradius: %d Felder" % gather
		if b.get_gather_bonus() > 0.0:
			gather_text += " (+%d %% Sammeltempo)" % roundi(b.get_gather_bonus() * 100.0)
		facts.append(gather_text)
	var production := _production_text(b)
	if not production.is_empty():
		facts.append(production)
	var eff_table: Dictionary = def.get("biome_efficiency", {})
	if not eff_table.is_empty() and not is_equal_approx(b.biome_efficiency, 1.0):
		facts.append("Ertrag Gelände: %d %%" % roundi(b.biome_efficiency * 100.0))
	var slots := b.get_worker_slots()
	if slots > 0 and not b.constructed:
		facts.append("Arbeitsplätze: %d (wenn fertig)" % slots)
	var sat: Dictionary = def.get("satisfaction", {})
	if not sat.is_empty():
		var line := "Versorgt bis zu %d Bewohner: %+d Zufriedenheit" % [int(sat.get("capacity", 0)), roundi(float(sat.get("bonus", 0)))]
		if b.constructed and b.kingdom != null:
			var n := 0
			for u in b.kingdom.units:
				if bool(u.type_def.get("needs_housing", false)):
					n += 1
			line += " (Abdeckung %d %%)" % roundi(minf(1.0, float(sat.get("capacity", 0)) / maxf(float(n), 1.0)) * 100.0)
		facts.append(line)
	var aura: Dictionary = def.get("heal_aura", {})
	if b.constructed and not aura.is_empty():
		facts.append("Heilt eigene Einheiten im Umkreis von %d Feldern (%s Leben/s)" % [
			int(aura.get("radius", 0)), ResourceBar.format_number(float(aura.get("hp_per_sec", 0.0)))])
	return "\n".join(facts)


## Was im Monsterlager wartet (MonsterSystem.get_lair_info)
func _lair_text(lair: Building) -> String:
	var info: Dictionary = game.monster_system.get_lair_info(lair)
	if info.is_empty():
		return ""
	var lines: PackedStringArray = []
	var monsters: Dictionary = info.get("monsters", {})
	lines.append("Monster: " + (_count_text(monsters) if not monsters.is_empty() else "keine"))
	var next_spawn: float = info.get("next_spawn", -1.0)
	lines.append("Lager voll" if next_spawn < 0.0 else "Nachwuchs in %d s" % ceili(next_spawn))
	var loot: Dictionary = info.get("loot", {})
	lines.append("Beute: " + (DataDB.cost_to_text(loot) if not loot.is_empty() else "keine"))
	var points := int(lair.def.get("kill_points", 0))
	if points > 0:
		lines.append("Kampfpunkte: %d" % points)
	var recommended: int = info.get("recommended", 1)
	lines.append("Empfohlen: mindestens %d Kämpfer" % recommended)
	return "\n".join(lines)


## Produktion pro Minute: (Grundertrag + Ertrag je Arbeiter × arbeitende) × Gelände
func _production_text(b: Building) -> String:
	var per_worker: Dictionary = b.def.get("production", {})
	var base: Dictionary = b.def.get("base_production", {})
	if per_worker.is_empty() and base.is_empty():
		return ""
	if not b.constructed:
		return ""
	var working := 0
	for w in b.workers:
		if is_instance_valid(w) and (w as Unit).state == Unit.State.WORKING:
			working += 1
	var res_ids: Array = per_worker.keys()
	for res_id in base:
		if not res_ids.has(res_id):
			res_ids.append(res_id)
	var parts: PackedStringArray = []
	for res_id in res_ids:
		var amount := (float(base.get(res_id, 0.0)) + float(per_worker.get(res_id, 0.0)) * working) \
				* b.biome_efficiency * 60.0
		parts.append("%s %s" % [ResourceBar.format_number(amount),
				str(DataDB.get_resource(str(res_id)).get("name", res_id))])
	return "Produktion: %s pro Minute" % ", ".join(parts)


func _on_worker_plus() -> void:
	var b := _valid_building()
	if b != null:
		game.work_system.assign_worker_to_building(b)
	_refresh()


func _on_worker_minus() -> void:
	var b := _valid_building()
	if b != null:
		game.work_system.remove_worker_from_building(b)
	_refresh()


## Tor verriegeln bzw. öffnen
func _on_gate_pressed() -> void:
	var b: Variant = _target
	if b is Building and is_instance_valid(b) and (b as Building).kingdom == game.player:
		game.siege_system.set_gate_locked(b, not game.siege_system.is_gate_locked(b))
		_dirty = true


func _on_demolish_pressed() -> void:
	var b := _valid_building()
	if b == null:
		return
	if _confirm_left > 0.0:
		_confirm_left = 0.0
		game.building_system.cancel_or_demolish(b)
	else:
		_confirm_left = CONFIRM_SECONDS
	_refresh()


# ---------------------------------------------------------------------------
# Beschwören
# ---------------------------------------------------------------------------

func _build_summon_box(parent: Control) -> void:
	_summon_box = VBoxContainer.new()
	_summon_box.add_theme_constant_override("separation", 4)
	parent.add_child(_summon_box)
	_summon_header = _make_label(_summon_box, 15, COLOR_TITLE)
	_summon_header.text = "Beschwören"
	_summon_list = VBoxContainer.new()
	_summon_list.add_theme_constant_override("separation", 4)
	_summon_box.add_child(_summon_list)

	# Warteschlange: immer fünf Plätze, damit die Höhe gleich bleibt
	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 4)
	_summon_box.add_child(queue_row)
	for i in QUEUE_SLOTS:
		var slot := JobPanel.make_small_button("", self, QUEUE_SLOT_SIZE)
		slot.pressed.connect(_on_queue_slot_pressed.bind(i))
		var icon := UnitIcon.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4.0
		icon.offset_top = 4.0
		icon.offset_right = -4.0
		icon.offset_bottom = -4.0
		slot.add_child(icon)
		queue_row.add_child(slot)
		_queue_slots.append(slot)
		_queue_icons.append(icon)
	# Text neben den Plätzen: immer genau zwei Zeilen hoch (siehe _fix_two_lines),
	# sonst verschöbe ein längerer Text die Beschwören-Buttons darüber.
	_queue_label = Label.new()
	_queue_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_queue_label.add_theme_color_override("font_color", COLOR_DIM)
	_queue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_queue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_row.add_child(_queue_label)
	_fix_two_lines(_queue_label)

	# Sammelpunkt: Hinweis und (falls gesetzt) "löschen"; feste Höhe, auch wenn
	# der Löschen-Button erscheint und der Hinweis dadurch umbricht
	_rally_row = HBoxContainer.new()
	var rally_row := _rally_row
	rally_row.add_theme_constant_override("separation", 6)
	rally_row.custom_minimum_size = Vector2(0, 42)
	_summon_box.add_child(rally_row)
	_rally_label = Label.new()
	_rally_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_rally_label.add_theme_color_override("font_color", COLOR_GREY)
	_rally_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rally_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rally_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rally_row.add_child(_rally_label)
	_fix_two_lines(_rally_label)
	_rally_clear = _make_compact_button("Sammelpunkt löschen", SMALL_FONT_SIZE)
	_rally_clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rally_clear.tooltip_text = "Neue Einheiten stellen sich wieder vor dem Gebäude auf"
	_rally_clear.pressed.connect(_on_rally_clear_pressed)
	rally_row.add_child(_rally_clear)


## Baut die Buttons neu, wenn sich Gebäude oder Auswahl der Einheitentypen ändern
func _ensure_summon_buttons(b: Building) -> void:
	var options: Array = game.summon_system.get_options(b)
	var ids := PackedStringArray()
	for o in options:
		ids.append(str((o as Dictionary).get("id", "")))
	if is_instance_valid(_summon_building) and _summon_building == b and ids == _summon_ids:
		return
	_summon_building = b
	_summon_ids = ids
	# Sofort aus dem Baum nehmen, sonst stünden alte und neue Buttons ein Bild lang untereinander
	for child in _summon_list.get_children():
		_summon_list.remove_child(child)
		child.queue_free()
	_summon_entries.clear()
	for o in options:
		_summon_entries.append(_make_summon_button(o as Dictionary, b.kingdom))


## Ein Button je Einheitentyp: Bild, Name, Kosten (Symbol + Zahl), Dauer
func _make_summon_button(def: Dictionary, k: Kingdom) -> Dictionary:
	var id := str(def.get("id", ""))
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 38)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_summon_pressed.bind(id))
	_summon_list.add_child(button)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_right = -10.0
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := UnitIcon.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.setup(def, k)
	row.add_child(icon)
	var name_label := _make_label(row, FONT_SIZE, COLOR_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text = str(def.get("name", id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var costs := {}
	# Helden: wirkliche Kosten (jeder weitere Held kostet mehr)
	var cost: Dictionary = game.summon_system.get_cost(k, id)
	for r in DataDB.resources:
		var res_id := str(r["id"])
		var amount := float(cost.get(res_id, 0.0))
		if amount <= 0.0:
			continue
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 2)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pair)
		var res_icon := ResourceIcon.new()
		res_icon.setup(res_id, 16.0)
		pair.add_child(res_icon)
		var amount_label := _make_label(pair, SMALL_FONT_SIZE, COLOR_TEXT)
		amount_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.text = str(ceili(amount))
		costs[res_id] = [amount_label, amount]
	var time_label := _make_label(row, SMALL_FONT_SIZE, COLOR_DIM)
	time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.custom_minimum_size = Vector2(34, 0)
	time_label.text = "%d s" % ceili(_summon_seconds(def, k))
	return {"id": id, "def": def, "button": button, "row": row, "costs": costs, "time": time_label}


func _refresh_summons(b: Building) -> void:
	_ensure_summon_buttons(b)
	var k := b.kingdom
	var ss: SummonSystem = game.summon_system
	for e in _summon_entries:
		var entry: Dictionary = e
		var def: Dictionary = entry["def"]
		var button: Button = entry["button"]
		var reason := ss.can_summon(b, str(entry["id"]))
		var ok := reason.is_empty()
		if button.disabled == ok:
			button.disabled = not ok
		var row: Control = entry["row"]
		var tint := Color.WHITE if ok else Color(1, 1, 1, 0.55)
		if row.modulate != tint:
			row.modulate = tint
		# Fehlende Ressourcen rot
		var costs: Dictionary = entry["costs"]
		var cost: Dictionary = ss.get_cost(k, str(entry["id"]))
		for res_id in costs:
			var pair: Array = costs[res_id]
			var label: Label = pair[0]
			# Heldenkosten steigen mit jedem Helden: Zahl nachführen
			pair[1] = float(cost.get(res_id, 0.0))
			_set_label_text(label, str(ceili(float(pair[1]))))
			_set_color(label, COLOR_BAD if k.get_amount(str(res_id)) + 0.0001 < float(pair[1]) else COLOR_TEXT)
		var time_label: Label = entry["time"]
		_set_label_text(time_label, "%d s" % ceili(_summon_seconds(def, k)))
		var tip := _summon_tooltip(def, k)
		if not ok:
			tip += "\n\n" + reason
		if button.tooltip_text != tip:
			button.tooltip_text = tip

	# Warteschlange
	var queue: Array = b.summon_queue
	for i in QUEUE_SLOTS:
		var slot := _queue_slots[i]
		var icon := _queue_icons[i]
		if i < queue.size():
			var item: Dictionary = queue[i]
			var type_id := str(item.get("type_id", ""))
			var def := DataDB.get_unit_type(type_id)
			if str(slot.get_meta("type_id", "")) != type_id:
				slot.set_meta("type_id", type_id)
				icon.setup(def, k)
			var ratio := clampf(float(item.get("progress", 0.0)) / maxf(float(item.get("time", 1.0)), 0.01), 0.0, 1.0)
			icon.set_progress(ratio if i == 0 else -1.0)
			slot.disabled = false
			var tip := str(def.get("name", type_id))
			if i == 0:
				tip += " – %d %%" % floori(ratio * 100.0)
			tip += "\n" + CANCEL_TIP
			if slot.tooltip_text != tip:
				slot.tooltip_text = tip
		else:
			if str(slot.get_meta("type_id", "")) != "":
				slot.set_meta("type_id", "")
				icon.clear()
			slot.disabled = true
			slot.tooltip_text = "Freier Platz der Warteschlange (Einheit oben anklicken)"
	# Beide Fassungen haben genau zwei kurze Zeilen (Höhe bleibt gleich)
	var queue_text := "Warteschlange leer\nEinheit oben anklicken"
	if not queue.is_empty():
		var first: Dictionary = queue[0]
		var first_def := DataDB.get_unit_type(str(first.get("type_id", "")))
		var left := (float(first.get("time", 0.0)) - float(first.get("progress", 0.0))) / maxf(k.mod("summon"), 0.01)
		queue_text = "%s\nnoch %d s" % [str(first_def.get("name", "?")), maxi(ceili(left), 0)]
		if queue.size() > 1:
			queue_text += " · %d weitere" % (queue.size() - 1)
	_set_label_text(_queue_label, queue_text)

	# Sammelpunkt
	_set_label_text(_rally_label, "Rechtsklick in die Welt: Sammelpunkt %s" % ("versetzen" if b.has_rally else "setzen"))
	_rally_clear.visible = b.has_rally


## Dauer in Spielsekunden (Beschwörungstempo des Reichs eingerechnet)
func _summon_seconds(def: Dictionary, k: Kingdom) -> float:
	return float(def.get("summon_time", 10.0)) / maxf(k.mod("summon"), 0.01)


## Grundwert eines Einheitentyps mit den Faktoren des Reichs (wie Unit._stat; auch je Klasse – Schmiede)
func _type_stat(def: Dictionary, k: Kingdom, key: String) -> float:
	return float(def.get(key, 0.0)) * k.mod(key) * k.mod(key + "." + str(def.get("tier", ""))) \
			* k.mod(key + "#" + str(def.get("class", "")))


func _summon_tooltip(def: Dictionary, k: Kingdom) -> String:
	var lines: PackedStringArray = []
	lines.append(str(def.get("name", "?")))
	lines.append("Kosten: " + DataDB.cost_to_text(game.summon_system.get_cost(k, str(def.get("id", "")))))
	lines.append("Dauer: %d s" % ceili(_summon_seconds(def, k)))
	var stats: PackedStringArray = []
	stats.append("Leben %d" % roundi(_type_stat(def, k, "hp")))
	var heal := _type_stat(def, k, "heal")
	if heal > 0.0:
		stats.append("Heilung %s/s" % ResourceBar.format_number(heal))
		stats.append("Reichweite %s" % _range_text(_type_stat(def, k, "heal_range")))
	else:
		stats.append("Angriff %s" % ResourceBar.format_number(_type_stat(def, k, "attack")))
		stats.append("Rüstung %d %%" % roundi(_type_stat(def, k, "armor") * 100.0))
		stats.append("Reichweite %s" % _range_text(_type_stat(def, k, "range")))
	stats.append("Tempo %s" % ResourceBar.format_number(_type_stat(def, k, "speed")))
	lines.append(" · ".join(stats))
	if str(def.get("role", "")) != "hero":
		lines.append(TroopRules.class_line(def))
	if not str(def.get("description", "")).is_empty():
		lines.append(str(def["description"]))
	if bool(def.get("can_work", false)):
		lines.append("Kann auch einen Beruf ausüben (braucht dann Wohnraum)")
	return "\n".join(lines)


func _on_summon_pressed(type_id: String) -> void:
	var b := _valid_building()
	if b == null:
		return
	if not game.summon_system.summon(b, type_id):
		var reason: String = game.summon_system.can_summon(b, type_id)
		if not reason.is_empty():
			Notify.warning(reason.get_slice("\n", 0))
	_refresh()


func _on_queue_slot_pressed(index: int) -> void:
	var b := _valid_building()
	if b != null:
		game.summon_system.cancel(b, index)
	_refresh()


func _on_rally_clear_pressed() -> void:
	var b := _valid_building()
	if b != null:
		game.summon_system.clear_rally(b)
	_refresh()


# ---------------------------------------------------------------------------
# Einheiten
# ---------------------------------------------------------------------------

func _show_unit(u: Unit) -> void:
	var own: bool = u.kingdom == game.player
	var title := u.get_display_name()
	if own:
		var army: int = game.command_system.get_army_number(u)
		if army > 0:
			title += " · Armee %d" % army
	var esp: EspionageSystem = game.espionage_system
	var spies: SpySystem = game.spy_system
	if not own and spies.is_spy(u) and not u.stealthed:
		title += " (enttarnt)"
	_set_text(_title, title)
	_show_owner(u.kingdom)
	# Kundschaft über feindliche Königreiche: ohne Bericht (Stufe 2) keine Werte, Wirkungen
	# erst genau (3); Monster, Dörfer und eigene Einheiten immer
	var intel := 3
	if u.kingdom.controller == "ai" and not esp.details_visible(game.player, u.kingdom, 2):
		intel = esp.get_intel_level(game.player, u.kingdom)
	_hp_bar.visible = true
	_hp_bar.set_value(u.hp, u.max_hp, "" if intel >= 2 else "?")
	_fill_stats(u)
	_set_text(_warn, "")
	var caravan: bool = game.trade_route_system.is_caravan(u)
	var facts := _village_unit_text(u)
	if intel < 2:
		_stats_grid.visible = false
		facts = "Werte unbekannt – schicke Späher oder Spione in die Nähe"
	elif own and spies.is_spy(u):
		facts = spies.get_spy_text(u)
	elif caravan:
		facts = game.trade_route_system.get_caravan_text(u)
	_set_text(_facts, facts)
	var spy_row := own and spies.is_spy(u)
	if _spy_row.visible != spy_row:
		_spy_row.visible = spy_row
	_show_village_row(u.kingdom if game.village_system.is_village(u.kingdom) else null)
	_summon_box.visible = false
	_worker_row.visible = false
	_demolish_button.visible = false
	if own:
		# Das Warnzeichen fehlt in manchen Schriften – "(!)" ist überall lesbar.
		# Befehlstexte beginnen klein ("hält die Stellung"), als Zeile gross.
		_set_text(_status, _capitalize(u.get_status_text().replace("⚠", "(!)")))
		_set_text(_bonus, _join_bonus(game.combat_system.get_bonus_text(u), _terrain_text(u)))
		_set_text(_note, KING_NOTE if u.role == "king" else "")
	else:
		_set_text(_status, "")
		_set_text(_bonus, _terrain_text(u))
		_set_text(_note, "")
	_show_unit_phase8(u, own)
	if intel >= 3:
		_show_magic(u)
	else:
		_magic_box.visible = false
	_hide_research()
	if own and u.hero_id != 0:
		_hero_box.show_hero(u, false)
	else:
		_hero_box.hide_box()
	if intel >= 2 and not caravan:
		_troop_box.show_unit(u, own)
	else:
		_troop_box.hide_box()
	_job_row.visible = own and u.can_work()
	if _job_row.visible:
		_update_job_options(u)

	_actions.visible = own and not caravan
	if not own or caravan:
		_job_row.visible = false
		return
	_halt_button.visible = true
	_halt_button.tooltip_text = "Stehen bleiben und den Platz verteidigen"
	_work_button.visible = u.can_work() and not spy_row
	if _work_button.visible:
		var no_job := u.job_id == "idle"
		_work_button.disabled = no_job
		_work_button.tooltip_text = NO_JOB_TIP if no_job else "Befehl aufheben – arbeitet weiter als %s" % u.get_job_name()
	_attack_move_button.visible = true
	_attack_move_button.set_pressed_no_signal(game.selection.is_attack_move_armed())
	_formation_button.visible = false
	_layout_actions()


## Mehrere eigene Einheiten: Anzahl je Typ, gesamtes Leben, Befehle
func _show_units(units: Array) -> void:
	# Zusammensetzung nur neu zählen, wenn sich Auswahl, Anzahl oder Berufe
	# geändert haben (grosse Armeen); das Leben in jedem Durchgang
	if units.size() != _multi_size:
		_multi_size = units.size()
		var counts := {}
		_multi_workers = 0
		_multi_with_job = 0
		for o in units:
			var u: Unit = o
			var n := u.get_display_name()
			counts[n] = int(counts.get(n, 0)) + 1
			if u.can_work():
				_multi_workers += 1
				if u.job_id != "idle":
					_multi_with_job += 1
		_multi_counts = _count_text(counts)
		_multi_army = _army_of(units)
	var hp := 0.0
	var max_hp := 0.0
	for o in units:
		hp += (o as Unit).hp
		max_hp += (o as Unit).max_hp
	var workers := _multi_workers
	var with_job := _multi_with_job
	var title := "%d Einheiten" % units.size()
	if _multi_army > 0:
		title += " · Armee %d" % _multi_army
	_set_text(_title, title)
	_owner.visible = false
	_hp_bar.visible = true
	_hp_bar.set_value(hp, max_hp)
	_stats_grid.visible = false
	_set_text(_status, "")
	_set_text(_warn, "")
	var unsupplied := 0
	for o in units:
		for e in (o as Unit).effects:
			if str(e.get("id", "")) == SupplySystem.EFFECT_ID:
				unsupplied += 1
				break
	_set_text(_facts, _multi_counts if unsupplied == 0 else _multi_counts + "\n%d ohne Versorgung (keine Erholung)" % unsupplied)
	_set_text(_bonus, "")
	_set_text(_note, MULTI_HINT)
	_show_units_mood(units)
	_magic_box.visible = false
	_hide_research()
	# Aktiver Held der Auswahl (Tab wechselt): Fähigkeiten auch mit der ganzen Armee
	_hero_box.show_hero(game.selection.get_focus_hero(), true)
	_troop_box.show_units(units)
	_summon_box.visible = false
	_worker_row.visible = false
	_job_row.visible = false
	_demolish_button.visible = false

	_actions.visible = true
	_halt_button.visible = true
	_halt_button.tooltip_text = "Alle bleiben stehen und verteidigen ihren Platz"
	# Immer sichtbar (2×2-Raster bleibt gleich), ohne Beruf gesperrt
	_work_button.visible = true
	_work_button.disabled = with_job == 0
	if workers == 0:
		_work_button.tooltip_text = "Keine dieser Einheiten kann einen Beruf ausüben"
	elif with_job == 0:
		_work_button.tooltip_text = NO_JOB_TIP
	else:
		_work_button.tooltip_text = "Befehl aufheben – Einheiten mit Beruf arbeiten weiter, die anderen halten ihren Platz"
	_attack_move_button.visible = true
	_attack_move_button.set_pressed_no_signal(game.selection.is_attack_move_armed())
	_formation_button.visible = true
	_update_formation_button()
	_layout_actions()


func _build_stats_grid(parent: Control) -> void:
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 8)
	_stats_grid.add_theme_constant_override("v_separation", 0)
	# STOP, damit der Tooltip mit den Einzelheiten erscheint
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_stats_grid)
	for i in 4:
		var key := _make_label(_stats_grid, 15, COLOR_GREY)
		key.autowrap_mode = TextServer.AUTOWRAP_OFF
		var value := _make_label(_stats_grid, 15, COLOR_TEXT)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		# Zweite Spalte etwas breiter, damit die Paare sauber untereinander stehen
		value.custom_minimum_size = Vector2(118 if i % 2 == 0 else 0, 0)
		_stat_keys.append(key)
		_stat_values.append(value)


## Kampfwerte: Angriff (Heiler: Heilung), Rüstung, Reichweite, Tempo.
## Gestärkte Werte grün, geschwächte rot (Forschung, Zauber, Flüche).
func _fill_stats(u: Unit) -> void:
	_stats_grid.visible = true
	var pairs: Array = []
	if u.can_heal():
		pairs.append(["Heilung", "%s/s" % ResourceBar.format_number(u.heal), _trend(u, "heal", u.heal)])
	else:
		pairs.append(["Angriff", ResourceBar.format_number(u.attack), _trend(u, "attack", u.attack)])
	pairs.append(["Rüstung", _stat_value(u.armor, true, ""), _trend(u, "armor", u.armor)])
	if u.can_heal():
		pairs.append(["Reichweite", _range_text(u.heal_range), _trend(u, "heal_range", u.heal_range)])
	else:
		pairs.append(["Reichweite", _range_text(u.attack_range), _trend(u, "range", u.attack_range)])
	pairs.append(["Tempo", ResourceBar.format_number(u.speed), _trend(u, "speed", u.speed)])
	for i in 4:
		var pair: Array = pairs[i]
		_set_label_text(_stat_keys[i], str(pair[0]))
		_set_label_text(_stat_values[i], str(pair[1]))
		var trend := int(pair[2])
		_set_color(_stat_values[i], COLOR_TEXT if trend == 0 else (COLOR_UP if trend > 0 else COLOR_BAD))
	var tip: PackedStringArray = []
	if u.is_combatant():
		tip.append("Angriff: %s Schaden alle %s s (%s pro Sekunde)" % [_num(u.attack),
				_num(u.attack_interval), _num(u.attack / u.attack_interval)])
	if u.can_heal():
		tip.append("Heilung: %s Leben pro Sekunde im Umkreis von %s Feldern" % [_num(u.heal),
				_num(u.heal_range)])
	# Ein Fluch kann die Rüstung unter 0 drücken: dann nimmt die Einheit mehr Schaden
	if u.armor < -0.005:
		tip.append("Rüstung: %d %% mehr Schaden" % roundi(-u.armor * 100.0))
	else:
		tip.append("Rüstung: %d %% weniger Schaden" % roundi(u.armor * 100.0))
	tip.append("Reichweite: %s Felder" % _num(u.attack_range))
	tip.append("Tempo: %s Felder pro Sekunde" % _num(u.speed))
	if u.aggro_range > 0.0:
		tip.append("Greift Feinde im Umkreis von %s Feldern selbst an" % _num(u.aggro_range))
	if u.regen > 0.0:
		tip.append("Erholung: %s Leben pro Sekunde ausser Kampf" % _num(u.regen))
	# Grundwert → jetzt, mit allen Quellen (Forschung, Zauber, Flüche)
	tip.append("")
	if u.can_heal():
		tip.append(_stat_source_line(u, "heal", "Heilung", u.heal, false))
	else:
		tip.append(_stat_source_line(u, "attack", "Angriff", u.attack, false))
	var interval := _stat_source_line(u, "attack_interval", "Angriffspause", u.attack_interval, false, " s")
	if interval.contains("("):
		tip.append(interval)
	tip.append(_stat_source_line(u, "armor", "Rüstung", u.armor, true))
	tip.append(_stat_source_line(u, "hp", "Leben", u.max_hp, false))
	tip.append(_stat_source_line(u, "speed", "Tempo", u.speed, false))
	var text := "\n".join(tip)
	if _stats_grid.tooltip_text != text:
		_stats_grid.tooltip_text = text


## +1 = besser als der Grundwert aus units.json, −1 = schlechter, 0 = gleich
static func _trend(u: Unit, key: String, value: float) -> int:
	var base := float(u.type_def.get(key, 0.0))
	if value > base * 1.001 + 0.0001:
		return 1
	if value < base * 0.999 - 0.0001:
		return -1
	return 0


## "Angriff 12 → 13,2 (Waffenschmiede +10 %, Lichtsegen +25 %)": Grundwert aus
## units.json, jetziger Wert der Einheit und alle Quellen – Faktoren des Reichs
## (Schlüssel, Schlüssel.Stufe, Schlüssel@Rolle wie Unit._stat) und Wirkungen
## auf der Einheit. as_percent: Wert ist ein Anteil (Rüstung 0.2 = 20 %).
func _stat_source_line(u: Unit, key: String, label: String, value: float, as_percent: bool,
		unit_suffix: String = "") -> String:
	var base := float(u.type_def.get(key, 0.0))
	var parts: PackedStringArray = []
	var k := u.kingdom
	if k != null:
		var keys: PackedStringArray = [key, key + "." + u.tier, key + "@" + u.role, key + "#" + u.unit_class]
		for source in k.modifier_sources:
			var entry: Dictionary = k.modifier_sources[source]
			for mod_key in keys:
				if entry.has(mod_key):
					parts.append("%s %s" % [_source_name(str(source)), _factor_text(float(entry[mod_key]), key)])
	# Gelände des Volks (Phase 8): erlittener Schaden als Verteidigung
	var terrain_key := key
	if not u.terrain_mods.is_empty() and u.terrain_mods.has(terrain_key):
		var biome_name := str(DataDB.get_biome(u.terrain_biome).get("name", "")) if u.terrain_biome >= 0 else ""
		parts.append("Gelände %s %s" % [biome_name, _factor_text(float(u.terrain_mods[terrain_key]), key)])
	# Helden: Stufe, Talente und passive Fähigkeiten (Unit.hero_mods); Truppen: Rang und
	# Wertepunkte (Unit.vet_mods, gleicher Aufbau)
	for mods: Dictionary in [u.hero_mods, u.vet_mods]:
		if not mods.has(key):
			continue
		for part in (mods[key] as Dictionary).get("parts", []):
			var p: Array = part
			if not is_equal_approx(float(p[2]), 1.0):
				parts.append("%s %s" % [str(p[0]), _factor_text(float(p[2]), key)])
			if absf(float(p[1])) > 0.0001:
				var hero_add := ("%+d %%" % roundi(float(p[1]) * 100.0)) if as_percent else ("%s%s" % ["+" if float(p[1]) > 0.0 else "−", _num(absf(float(p[1])))])
				parts.append("%s %s" % [str(p[0]), hero_add.replace("-", "−")])
	for e in u.effects:
		var eff: Dictionary = e
		if str(eff.get("key", "")) != key:
			continue
		var source_name := _source_name(str(eff.get("source", "")))
		var mult := float(eff.get("mult", 1.0))
		var add := float(eff.get("add", 0.0))
		if not is_equal_approx(mult, 1.0):
			parts.append("%s %s" % [source_name, _factor_text(mult, key)])
		if absf(add) > 0.0001:
			var add_text := ("%+d %%" % roundi(add * 100.0)) if as_percent else ("%s%s" % ["+" if add > 0.0 else "−", _num(absf(add))])
			parts.append("%s %s" % [source_name, add_text.replace("-", "−")])
	var text := "%s %s" % [label, _stat_value(base, as_percent, unit_suffix)]
	if not parts.is_empty() or absf(value - base) > 0.0001:
		text += " → " + _stat_value(value, as_percent, unit_suffix)
	if not parts.is_empty():
		text += " (" + ", ".join(parts) + ")"
	return text


static func _stat_value(v: float, as_percent: bool, unit_suffix: String) -> String:
	if as_percent:
		# Typografisches Minus wie in den übrigen Texten
		return ("%d %%" % roundi(v * 100.0)).replace("-", "−")
	return _num(v) + unit_suffix


## Faktor als Text: Rüstung "×1,3", sonst "+10 %" / "−25 %"
static func _factor_text(factor: float, key: String) -> String:
	if key == "armor":
		return "×" + String.num(factor, 2).replace(".", ",")
	var p := roundi((factor - 1.0) * 100.0)
	return ("+%d %%" % p) if p >= 0 else ("−%d %%" % -p)


## Lesbarer Name einer Quelle ("research:x" -> Forschung, "spell:x" -> Zauber)
static func _source_name(source: String) -> String:
	if source == "difficulty":
		return "Schwierigkeit"
	return DataDB.describe_effect_source(source)


## Zahl mit Komma: "13,2", "2,2", "12"
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")


func _range_text(tiles: float) -> String:
	return "Nahkampf" if tiles < MELEE_RANGE else "%s Felder" % ResourceBar.format_number(tiles)


## Berufsliste: Einträge sperren, die diese Einheit nicht annehmen kann (Grund als Tooltip)
func _update_job_options(u: Unit) -> void:
	if _job_option.get_popup().visible:
		return
	var ws: WorkSystem = game.work_system
	for i in _job_ids.size():
		var id := _job_ids[i]
		var reason := ""
		if id != u.job_id:
			reason = ws.get_job_block_reason(u, id)
			var job := DataDB.get_job(id)
			if reason.is_empty() and str(job.get("type", "")) == "building" and not ws.has_free_slot(u.kingdom, id):
				reason = str(job.get("hint", "Kein freier Arbeitsplatz."))
		var blocked := not reason.is_empty()
		if _job_option.is_item_disabled(i) != blocked:
			_job_option.set_item_disabled(i, blocked)
		if _job_option.get_item_tooltip(i) != reason:
			_job_option.set_item_tooltip(i, reason)
	var current := _job_ids.find(u.job_id)
	if current >= 0 and _job_option.selected != current:
		_job_option.select(current)


func _on_job_selected(index: int) -> void:
	var u := _valid_unit()
	if u == null or index < 0 or index >= _job_ids.size():
		return
	var id := _job_ids[index]
	if id != u.job_id and not game.work_system.set_unit_job(u, id):
		# Hat nicht geklappt (z. B. kein freier Platz): Auswahl zurücksetzen
		_job_option.select(_job_ids.find(u.job_id))
	_refresh()


# ---------------------------------------------------------------------------
# Befehle
# ---------------------------------------------------------------------------

func _build_actions(parent: Control) -> void:
	_actions = GridContainer.new()
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	parent.add_child(_actions)
	_halt_button = _make_action_button("Halt")
	_halt_button.pressed.connect(_on_halt_pressed)
	_work_button = _make_action_button("Zur Arbeit")
	_work_button.pressed.connect(_on_work_pressed)
	_attack_move_button = _make_action_button("Angriff-Vorrücken")
	_attack_move_button.toggle_mode = true
	_attack_move_button.tooltip_text = ATTACK_MOVE_TIP
	_attack_move_button.pressed.connect(_on_attack_move_pressed)
	_formation_button = _make_action_button("Formation: Block")
	_formation_button.tooltip_text = "Formation für die nächsten Marschbefehle wechseln (F)"
	_formation_button.pressed.connect(_on_formation_pressed)


func _make_action_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	_actions.add_child(b)
	return b


## Bis zu drei Buttons in einer Reihe, vier als 2×2
func _layout_actions() -> void:
	var n := 0
	for child in _actions.get_children():
		if (child as Control).visible:
			n += 1
	var cols := 2 if n == 4 else maxi(n, 1)
	if _actions.columns != cols:
		_actions.columns = cols


func _update_formation_button() -> void:
	if game == null or game.player == null:
		return
	_set_button_text(_formation_button, "Formation: %s" % CommandSystem.get_formation_name(game.player.formation))


func _on_halt_pressed() -> void:
	game.command_system.order_stop(_command_units())
	_refresh()


func _on_work_pressed() -> void:
	game.command_system.order_return_to_work(_command_units())
	_refresh()


func _on_attack_move_pressed() -> void:
	if game.selection.is_attack_move_armed():
		game.selection.cancel_arm()
	else:
		game.selection.arm_attack_move()
	_attack_move_button.set_pressed_no_signal(game.selection.is_attack_move_armed())


func _on_formation_pressed() -> void:
	game.toggle_formation()
	_update_formation_button()


## Eigene, lebende Einheiten der Auswahl (Befehle gelten nur für sie)
func _command_units() -> Array:
	return game.selection.get_own_units()


# ---------------------------------------------------------------------------
# Magie und Forschung
# ---------------------------------------------------------------------------

## Laufende Zauberwirkungen ("Lichtsegen · 12 s" in der Zauberfarbe, ohne
## Ablauf "bis zum Ende"), Tarnung ("Getarnt · Lichtschleier · 40 s") und die
## Restzeit beschworener Einheiten ("Verschwindet in 34 s")
func _show_magic(u: Unit) -> void:
	var texts: PackedStringArray = []
	var colors: Array[Color] = []
	var stealth_named := false
	for entry in game.magic_system.get_active_effects(u):
		var e: Dictionary = entry
		var line := "%s · %s" % [str(e.get("name", "")), _seconds_text(float(e.get("seconds", -1.0)))]
		if u.stealthed and _has_stealth_from(u, str(e.get("source", ""))):
			line = "Getarnt · " + line
			stealth_named = true
		texts.append(line)
		colors.append(_spell_text_color(e.get("color", Color.WHITE)))
	# Getarnt ohne Zauber (z. B. ab Phase 7 Spione)
	if u.stealthed and not stealth_named:
		texts.insert(0, "Getarnt – für Feinde unsichtbar")
		colors.insert(0, COLOR_DIM)
	if u.expires_at >= 0.0:
		texts.append("Verschwindet in %d s" % maxi(ceili(u.expires_at - GameClock.game_time), 0))
		colors.append(COLOR_WARN)
	_magic_box.visible = not texts.is_empty()
	for i in MAGIC_LINES:
		var label := _magic_lines[i]
		if i < texts.size():
			_set_text(label, texts[i])
			_set_color(label, colors[i])
		else:
			label.visible = false


## Tarnt diese Quelle ("spell:<id>") die Einheit?
static func _has_stealth_from(u: Unit, source: String) -> bool:
	for e in u.effects:
		var eff: Dictionary = e
		if str(eff.get("key", "")) == "stealth" and str(eff.get("source", "")) == source:
			return true
	return false


static func _seconds_text(seconds: float) -> String:
	return "bis zum Ende" if seconds < 0.0 else "%d s" % ceili(seconds)


## Forschungsstätte: laufende Forschung mit Fortschritt und "Forschung öffnen (R)"
func _show_research(b: Building, own: bool) -> void:
	if not (own and b.constructed and bool(b.def.get("research", false))):
		_hide_research()
		return
	var rs: ResearchSystem = game.research_system
	var k := b.kingdom
	_research_button.visible = true
	var active := rs.get_active(k)
	if active.is_empty():
		_set_text(_research_label, "Keine Forschung aktiv – wähle eine im Forschungsfenster.")
		_set_color(_research_label, COLOR_DIM)
		_research_bar.visible = false
		return
	var text := "Erforscht: %s" % str(DataDB.get_research(active).get("name", active))
	var waiting := k.research_queue.size() - 1
	if waiting > 0:
		text += "  ·  %d weitere in der Warteschlange" % waiting
	_set_text(_research_label, text)
	_set_color(_research_label, COLOR_TEXT)
	var ratio := rs.get_progress_ratio(k)
	var left := rs.get_remaining_seconds(k)
	var bar_text := "%d %%" % floori(ratio * 100.0)
	if not is_inf(left):
		bar_text += "  ·  noch %d s" % ceili(left)
	_research_bar.visible = true
	_research_bar.set_value(ratio * 100.0, 100.0, bar_text)


func _hide_research() -> void:
	_research_label.visible = false
	_research_bar.visible = false
	_research_button.visible = false


## Öffnet das Forschungsfenster (nur wenn es noch zu ist)
func _on_research_pressed() -> void:
	var hud: Node = game.hud
	if hud.has_method("is_research_open") and bool(hud.call("is_research_open")):
		return
	if hud.has_method("toggle_research"):
		hud.call("toggle_research")


## Dunkle Zauberfarben (Flüche, Schatten) auf dem dunklen Fenster lesbar machen
static func _spell_text_color(c: Color) -> Color:
	return c.lightened(0.4) if c.get_luminance() < 0.45 else c


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Eigene, lebende Einheiten der Auswahl (gelöschte zuerst aussortieren)
func _own_units(sel: Array) -> Array:
	var list: Array = []
	var k: Kingdom = game.player
	for o in sel:
		if is_instance_valid(o) and o is Unit and (o as Unit).kingdom == k and (o as Unit).is_alive():
			list.append(o)
	return list


## Nummer der Armee, die genau aus diesen Einheiten besteht (0 = keine)
func _army_of(units: Array) -> int:
	var n: int = game.command_system.get_army_number(units[0])
	if n <= 0:
		return 0
	var uids: Array = game.player.armies.get(n, [])
	if uids.size() != units.size():
		return 0
	var lookup := {}
	for uid in uids:
		lookup[uid] = true
	for u in units:
		if not lookup.has((u as Unit).uid):
			return 0
	return n


## Reich des Objekts (nur bei fremden): Name in Reichsfarbe, ggf. "feindlich".
## Dörfer: "Zwergendorf Eisenhall · Freundlich (+42)" in der Stufenfarbe, dazu Krieg/Bündnis.
func _show_owner(k: Kingdom) -> void:
	if k == null or k == game.player:
		_owner.visible = false
		return
	var text := k.display_name
	var color := k.color.lightened(0.25)
	if game.village_system.is_village(k):
		var rep: float = game.diplomacy_system.get_reputation(k, game.player)
		var tier := DiplomacySystem.tier_for(rep)
		text += "  ·  %s (%s)" % [DiplomacySystem.tier_name(tier), ResourceBar.format_signed(roundf(rep))]
		color = DiplomacySystem.tier_color(tier).lightened(0.15)
		if game.are_hostile(game.player, k):
			text += "  ·  Krieg"
		elif game.are_allied(game.player, k):
			text += "  ·  Bündnis"
	elif k.controller == "ai":
		text += "  ·  %s  ·  %s" % ["feindlich" if game.are_hostile(game.player, k) else "Frieden",
				game.espionage_system.get_intel_text(game.player, k)]
	elif game.are_hostile(game.player, k):
		text += "  ·  feindlich"
	_set_text(_owner, text)
	_set_color(_owner, color)


## Dorf-Zeile zeigen (Dorf-Reich) oder verstecken (null)
func _show_village_row(v: Kingdom) -> void:
	_village_id = v.id if v != null else 0
	if _village_row.visible != (v != null):
		_village_row.visible = v != null


## Zeile für Einheiten eines Dorfs: Bote "Bote von … nach …", Miliz "Dorfwache"
func _village_unit_text(u: Unit) -> String:
	var vs: VillageSystem = game.village_system
	if u.role == "messenger":
		var rec: Dictionary = game.messenger_system.get_record(u)
		if rec.is_empty():
			return ""
		var sender: Kingdom = game.get_kingdom(int(rec["sender_id"]))
		var receiver: Kingdom = game.get_kingdom(int(rec["receiver_id"]))
		var text := "Bote von %s nach %s" % [sender.display_name if sender != null else "?",
				"dir" if receiver == game.player else (receiver.display_name if receiver != null else "?")]
		var about: Kingdom = game.get_kingdom(int(rec["about_id"]))
		if about == game.player:
			text += "\nMeldet deinen Angriff – fange ihn ab!"
		return text
	if vs.is_village(u.kingdom):
		return "Dorfwache von %s (%s)" % [u.kingdom.display_name, str(vs.get_people(u.kingdom).get("name", "?"))]
	return ""


## "Auftrag (K)": Spionagefenster beim gewählten Spion
func _on_spy_pressed() -> void:
	if is_instance_valid(_target) and _target is Unit and game.hud != null and game.hud.has_method("open_espionage"):
		game.hud.call("open_espionage", EspionagePanel.TAB_SPIES, 0, (_target as Unit).uid)


func _on_diplo_pressed() -> void:
	if _village_id != 0 and game.hud != null and game.hud.has_method("open_diplomacy"):
		game.hud.call("open_diplomacy", _village_id)


## "3× Schwertkämpfer, 2× Bogenschütze" (häufigste zuerst)
func _count_text(counts: Dictionary) -> String:
	var names: Array = counts.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ca := int(counts[a])
		var cb := int(counts[b])
		return ca > cb if ca != cb else str(a) < str(b))
	var parts: PackedStringArray = []
	for n in names:
		parts.append("%d× %s" % [int(counts[n]), str(n)])
	return ", ".join(parts)


## Erster Buchstabe gross ("kämpft gegen Wolf" -> "Kämpft gegen Wolf")
static func _capitalize(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## Angezeigtes Gebäude, falls es noch existiert
func _valid_building() -> Building:
	if not is_instance_valid(_target) or not (_target is Building):
		return null
	return _target as Building


func _valid_unit() -> Unit:
	if not is_instance_valid(_target) or not (_target is Unit):
		return null
	return _target as Unit


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Kleiner Button mit schmalen Innenabständen (z. B. "Sammelpunkt löschen")
func _make_compact_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := get_theme_stylebox(style_name, "Button")
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 3.0
		style.content_margin_bottom = 3.0
		b.add_theme_stylebox_override(style_name, style)
	return b


## Setzt den Text und blendet leere Labels aus
func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


## Feste Höhe von zwei Zeilen, egal wie lang der Text ist: höchstens zwei
## Zeilen zählen für die Höhe (max_lines_visible), einzeilige Texte bekommen
## dieselbe Höhe über custom_minimum_size. Kein Kürzen mit "…": dann fiele die
## Mindesthöhe auf eine Zeile und die zweite Zeile verschwände, sobald die
## Schrift (Fenstergrösse) etwas höher rechnet als hier geschätzt.
## Muss nach add_child aufgerufen werden (Schrift aus dem Theme).
func _fix_two_lines(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var h := font.get_height(font_size) * 2.0 + float(label.get_theme_constant("line_spacing"))
	# Etwas Luft, damit Rundung je nach Fenstergrösse die Höhe nicht ändert
	label.custom_minimum_size.y = ceilf(h) + 4.0


## Setzt nur den Text (Label bleibt sichtbar)
func _set_label_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text


func _set_color(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Zufriedenheit, Gelände, Überläufer und Flüchtlinge (Phase 8)
# ---------------------------------------------------------------------------

func _build_mood_row(parent: Control) -> void:
	_mood_row = ResourceBar.TipBox.new()
	_mood_row.add_theme_constant_override("separation", 6)
	_mood_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_mood_row.rich = true
	_mood_row.visible = false
	parent.add_child(_mood_row)
	_mood_icon = MoodIcon.new()
	_mood_icon.custom_minimum_size = Vector2(18, 18)
	_mood_row.add_child(_mood_icon)
	_mood_label = Label.new()
	_mood_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_mood_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mood_row.add_child(_mood_label)


func _build_refugee_row(parent: Control) -> void:
	_refugee_row = HBoxContainer.new()
	_refugee_row.add_theme_constant_override("separation", 6)
	_refugee_row.visible = false
	parent.add_child(_refugee_row)
	var label := Label.new()
	label.text = "Bitten um Aufnahme:"
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refugee_row.add_child(label)
	var accept := _make_compact_button("Aufnehmen", FONT_SIZE)
	accept.tooltip_text = "Die Gruppe wird Teil deines Reichs (Bewohner)"
	accept.pressed.connect(_on_refugee_accept)
	_refugee_row.add_child(accept)
	var reject := _make_compact_button("Abweisen", FONT_SIZE)
	reject.tooltip_text = "Die Gruppe zieht weiter"
	reject.pressed.connect(_on_refugee_reject)
	_refugee_row.add_child(reject)


## "Wald (Hochelfen): +10 % Angriff" (Geländebonus des Volks) oder ""
func _terrain_text(u: Unit) -> String:
	var ps: Variant = game.get("people_system")
	return str(ps.get_terrain_text(u)) if ps != null else ""


static func _join_bonus(a: String, b: String) -> String:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	return a + " · " + b


## Eigener Bewohner: Zufriedenheit; Überläufer: Status; Gruppe mit Angebot: Aufnehmen/Abweisen
func _show_unit_phase8(u: Unit, own: bool) -> void:
	var ss: Variant = game.get("satisfaction_system")
	var es: Variant = game.get("event_system")
	_mood_row.visible = false
	_refugee_row.visible = false
	_refugee_offer_id = 0
	if ss == null:
		return
	if own and bool(u.type_def.get("needs_housing", false)) and u.satisfaction >= 0.0:
		var tier := SatisfactionSystem.tier_for(u.satisfaction)
		var work := roundi((u.work_mult - 1.0) * 100.0)
		var text := "Zufriedenheit %d · %s" % [roundi(u.satisfaction), str(tier["name"])]
		if work != 0:
			text += (" · Arbeit %+d %%" % work).replace("-", "−")
		_mood_icon.set_value(u.satisfaction)
		_set_label_text(_mood_label, text)
		_set_color(_mood_label, tier["color"])
		_mood_row.source = _unit_mood_tip.bind(u)
		_mood_row.visible = true
		if ss.is_defector(u):
			_set_text(_status, str(ss.get_defector_text(u)))
	if es != null and not own:
		var offer: Dictionary = es.get_offer_of_unit(u)
		if not offer.is_empty() and int(offer["target_id"]) == game.player.id and str(offer["state"]) != "leaving":
			_refugee_offer_id = int(offer["id"])
			_refugee_row.visible = true
			_set_text(_facts, str(es.get_offer_text(offer, game.player)))


## Mehrere Einheiten: Ø-Zufriedenheit der Bewohner darunter
func _show_units_mood(units: Array) -> void:
	_refugee_row.visible = false
	var total := 0.0
	var n := 0
	for o in units:
		var u: Unit = o
		if bool(u.type_def.get("needs_housing", false)) and u.satisfaction >= 0.0:
			total += u.satisfaction
			n += 1
	_mood_row.visible = n > 0
	if n == 0:
		return
	var avg := total / n
	_mood_icon.set_value(avg)
	_set_label_text(_mood_label, "Zufriedenheit Ø %d" % roundi(avg))
	_set_color(_mood_label, SatisfactionSystem.tier_for(avg)["color"])
	_mood_row.source = Callable()
	_mood_row.tooltip_text = "Durchschnitt der %d ausgewählten Bewohner" % n


func _unit_mood_tip(u: Unit) -> String:
	if not is_instance_valid(u):
		return ""
	var ss: SatisfactionSystem = game.satisfaction_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Zufriedenheit %d[/b] (Ziel %d)" % [roundi(u.satisfaction), roundi(ss.get_target(u))]]
	for p in ss.get_unit_breakdown(u):
		var v := float(p["value"])
		if absf(v) < 0.5:
			continue
		lines.append(tip.colored(("%+d %s" % [roundi(v), str(p["cause"])]).replace("-", "−"), COLOR_UP if v > 0.0 else COLOR_BAD))
	lines.append("Arbeitsleistung ×%s" % String.num(u.work_mult, 2).replace(".", ","))
	return "\n".join(lines)


func _on_refugee_accept() -> void:
	var reason: String = game.event_system.accept_offer(game.player, _refugee_offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	_dirty = true


func _on_refugee_reject() -> void:
	var reason: String = game.event_system.reject_offer(game.player, _refugee_offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	_dirty = true
