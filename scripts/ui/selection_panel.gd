## SelectionPanel
##
## Auswahlfenster unten links (über dem Infobereich). Zeigt das erste
## ausgewählte Objekt (SelectionController.get_primary()):
## - Gebäude: Name, Baufortschritt, Wohnraum, Annahme, Sammelradius,
##   Produktion, Arbeiter (−/+) und Abreissen/Bau abbrechen (mit Bestätigung).
## - Bewohner: Zustand und Beruf (Auswahlliste).
## Bedienelemente gibt es nur für eigene Gebäude und Einheiten.
## Ohne Auswahl ist das Fenster ausgeblendet.
class_name SelectionPanel
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const CONFIRM_SECONDS := 3.0
const PANEL_WIDTH := 420.0
const COLOR_TITLE := Color(1.0, 0.86, 0.55)
const COLOR_WARN := Color(1.0, 0.62, 0.22)
const COLOR_DIM := Color(0.8, 0.78, 0.72)
const FONT_SIZE := 16

var game: Node

## Angezeigtes Objekt (Building oder Unit) oder null
var _target: Object = null
var _title: Label
var _status: Label
var _warn: Label
var _facts: Label
var _worker_row: HBoxContainer
var _worker_label: Label
var _worker_minus: Button
var _worker_plus: Button
var _job_row: HBoxContainer
var _job_option: OptionButton
## Beruf-IDs in der Reihenfolge der Auswahlliste
var _job_ids: PackedStringArray = []
var _demolish_button: Button
## Restzeit der Abriss-Bestätigung (Echtzeit, 0 = keine Bestätigung offen)
var _confirm_left := 0.0
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_title = _make_label(vbox, 20, COLOR_TITLE)
	_status = _make_label(vbox, FONT_SIZE, COLOR_DIM)
	_warn = _make_label(vbox, FONT_SIZE, COLOR_WARN)
	_facts = _make_label(vbox, FONT_SIZE, Color(0.95, 0.92, 0.85))

	# Bedienelemente stehen unten, damit sie bei wechselnder Textlänge
	# nicht unter dem Mauszeiger verrutschen (das Fenster wächst nach oben).
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
	_job_option.tooltip_text = "Beruf dieses Bewohners ändern"
	_job_option.item_selected.connect(_on_job_selected)
	_job_row.add_child(_job_option)

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
	_on_selection_changed(game.selection.selected)


func _process(delta: float) -> void:
	if game == null:
		return
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_confirm_left = 0.0
			_refresh()
	if not visible:
		return
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _on_selection_changed(_objs: Array) -> void:
	var primary: Object = game.selection.get_primary()
	if primary != _target:
		_confirm_left = 0.0
	_target = primary
	_timer = 0.0
	_refresh()


func _refresh() -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null
	visible = _target != null
	if _target == null:
		return
	if _target is Building:
		_show_building(_target as Building)
	elif _target is Unit:
		_show_unit(_target as Unit)
	else:
		visible = false


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
	_set_text(_title, title + _more_suffix())

	var status := ""
	var warn := ""
	if not b.constructed:
		status = "Im Bau: %d %%" % roundi(b.get_progress_ratio() * 100.0)
		if own and ws.get_job_count(k, "builder") == 0:
			warn = "Wartet auf Bauarbeiter – weise Bauarbeiter zu (J)"
	elif not own:
		status = "Gehört zu: %s" % b.kingdom.display_name
	_set_text(_status, status)
	_set_text(_warn, warn)

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
	_set_text(_facts, "\n".join(facts))

	# Arbeiter
	var show_workers := b.constructed and slots > 0
	_worker_row.visible = show_workers
	if show_workers:
		_set_text(_worker_label, "Arbeiter: %d/%d" % [b.workers.size(), slots])
		_worker_minus.visible = own
		_worker_plus.visible = own
		if own:
			_worker_minus.disabled = b.workers.is_empty()
			var idle := ws.get_idle_count(k)
			var tip := "Einen unbeschäftigten Bewohner hier arbeiten lassen"
			if idle == 0:
				tip = JobPanel.NO_IDLE_TIP
			elif not b.has_free_slot():
				tip = "Alle Arbeitsplätze sind besetzt."
			_worker_plus.disabled = idle == 0 or not b.has_free_slot()
			_worker_plus.tooltip_text = tip
	_job_row.visible = false

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
		var u: Unit = w
		if is_instance_valid(u) and u.state == Unit.State.WORKING:
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
	var b := _target as Building
	if b != null and is_instance_valid(b):
		game.work_system.assign_worker_to_building(b)
	_refresh()


func _on_worker_minus() -> void:
	var b := _target as Building
	if b != null and is_instance_valid(b):
		game.work_system.remove_worker_from_building(b)
	_refresh()


func _on_demolish_pressed() -> void:
	var b := _target as Building
	if b == null or not is_instance_valid(b):
		return
	if _confirm_left > 0.0:
		_confirm_left = 0.0
		game.building_system.cancel_or_demolish(b)
	else:
		_confirm_left = CONFIRM_SECONDS
	_refresh()


# ---------------------------------------------------------------------------
# Einheiten
# ---------------------------------------------------------------------------

func _show_unit(u: Unit) -> void:
	var k: Kingdom = game.player
	var own := u.kingdom == k
	_set_text(_title, u.get_display_name() + _more_suffix())
	# Das Warnzeichen fehlt in manchen Schriften – "(!)" ist überall lesbar
	_set_text(_status, u.get_status_text().replace("⚠", "(!)"))
	_set_text(_warn, "" if own else "Gehört zu: %s" % u.kingdom.display_name)
	_set_text(_facts, "")
	_worker_row.visible = false
	_demolish_button.visible = false
	_job_row.visible = own and u.can_work()
	if not _job_row.visible or _job_option.get_popup().visible:
		return
	var ws: WorkSystem = game.work_system
	for i in _job_ids.size():
		var id := _job_ids[i]
		var job := DataDB.get_job(id)
		var blocked := str(job.get("type", "")) == "building" and id != u.job_id and not ws.has_free_slot(k, id)
		if _job_option.is_item_disabled(i) != blocked:
			_job_option.set_item_disabled(i, blocked)
	var current := _job_ids.find(u.job_id)
	if current >= 0 and _job_option.selected != current:
		_job_option.select(current)


func _on_job_selected(index: int) -> void:
	var u := _target as Unit
	if u == null or not is_instance_valid(u) or index < 0 or index >= _job_ids.size():
		return
	var id := _job_ids[index]
	if id != u.job_id and not game.work_system.set_unit_job(u, id):
		# Hat nicht geklappt (z. B. kein freier Platz): Auswahl zurücksetzen
		_job_option.select(_job_ids.find(u.job_id))
	_refresh()


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## " (+2 weitere)" bei Mehrfachauswahl
func _more_suffix() -> String:
	var n: int = game.selection.selected.size()
	return "  (+%d weitere)" % (n - 1) if n > 1 else ""


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Setzt den Text und blendet leere Labels aus
func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text
