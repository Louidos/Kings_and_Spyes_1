## JobPanel
##
## Arbeitsverteilung oben links: zuerst die Unbeschäftigten, dann je Beruf
## Anzahl (bei Gebäude-Berufen "belegt/Plätze") mit "−" und "+".
## "+" nimmt einen Unbeschäftigten, "−" macht einen Arbeiter unbeschäftigt.
## Findet ein Beruf nichts zu tun, erscheint ein orangefarbenes "(!)" mit dem
## Grund als Tooltip. Haben Arbeiter eines Berufs gerade einen Befehl (Marsch,
## Halt …), steht hinter der Anzahl "(n pausiert)". Ein-/Ausblenden mit J (toggle()).
class_name JobPanel
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const COLOR_TITLE := Color(1.0, 0.86, 0.55)
const COLOR_WARN := Color(1.0, 0.62, 0.22)
const COLOR_NORMAL := Color(0.95, 0.92, 0.85)
const FONT_SIZE := 16
const SMALL_BUTTON_SIZE := 28.0
const NO_IDLE_TIP := "Keine unbeschäftigten Bewohner – drücke zuerst bei einer anderen Arbeit „−“"
const IDLE_TIP := "Unbeschäftigte Bewohner (beschworene Einheiten zählen nicht)"
const PAUSED_TIP := "Haben einen Befehl – im Auswahlfenster „Zur Arbeit“ drücken"
const COLOR_PAUSED := Color(0.85, 0.75, 0.55)

var game: Node

var _grid: GridContainer
## Eine Zeile je Beruf: {id, type, name, name_box, warn, count, paused, minus, plus}
var _rows: Array = []
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	var title := Label.new()
	title.text = "Arbeitsverteilung (J)"
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_grid)


func setup(p_game: Node) -> void:
	game = p_game
	for child in _grid.get_children():
		child.queue_free()
	_rows.clear()
	for j in DataDB.jobs:
		var job: Dictionary = j
		_add_row(job)
	game.work_system.jobs_changed.connect(_on_jobs_changed)
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _on_jobs_changed(kingdom: Kingdom) -> void:
	if kingdom == game.player and is_visible_in_tree():
		_refresh()


func _add_row(job: Dictionary) -> void:
	var id := str(job.get("id", ""))
	var type := str(job.get("type", ""))
	var job_name := str(job.get("name", id))
	var row := {"id": id, "type": type, "name": job_name}

	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 4)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var name_label := _make_label(job_name)
	name_box.add_child(name_label)
	var warn := _make_label("")
	warn.add_theme_color_override("font_color", COLOR_WARN)
	warn.custom_minimum_size = Vector2(26, 0)
	name_box.add_child(warn)
	_grid.add_child(name_box)

	# Anzahl, dahinter (nur bei Bedarf) "(n pausiert)"
	var count_box := HBoxContainer.new()
	count_box.add_theme_constant_override("separation", 4)
	count_box.alignment = BoxContainer.ALIGNMENT_END
	count_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(count_box)
	var count := _make_label("0")
	count.custom_minimum_size = Vector2(46, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_STOP
	count_box.add_child(count)
	var paused := _make_label("")
	paused.add_theme_font_size_override("font_size", 14)
	paused.add_theme_color_override("font_color", COLOR_PAUSED)
	paused.mouse_filter = Control.MOUSE_FILTER_STOP
	paused.tooltip_text = PAUSED_TIP
	paused.visible = false
	count_box.add_child(paused)
	row["name_box"] = name_box
	row["warn"] = warn
	row["count"] = count
	row["paused"] = paused

	if type == "idle":
		name_box.tooltip_text = IDLE_TIP
		count.tooltip_text = name_box.tooltip_text
		# Leere Zellen statt Buttons
		for _i in 2:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(SMALL_BUTTON_SIZE, SMALL_BUTTON_SIZE)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.add_child(spacer)
	else:
		var minus := make_small_button("−", self)
		minus.tooltip_text = "Einen Arbeiter abziehen (wird unbeschäftigt)"
		minus.pressed.connect(_on_minus_pressed.bind(id))
		_grid.add_child(minus)
		var plus := make_small_button("+", self)
		plus.pressed.connect(_on_plus_pressed.bind(id))
		_grid.add_child(plus)
		row["minus"] = minus
		row["plus"] = plus
	_rows.append(row)


func _refresh() -> void:
	if game == null:
		return
	var k: Kingdom = game.player
	if k == null:
		return
	var ws: WorkSystem = game.work_system
	var idle := ws.get_idle_count(k)
	# Einheiten mit Befehl je Beruf (ein Durchlauf für alle Zeilen)
	var paused_by_job := {}
	for u in k.units:
		var cmd: String = u.command
		if not cmd.is_empty():
			var job_id: String = u.job_id
			paused_by_job[job_id] = int(paused_by_job.get(job_id, 0)) + 1
	for r in _rows:
		var row: Dictionary = r
		var id := str(row["id"])
		var count_label: Label = row["count"]
		var warn: Label = row["warn"]
		var name_box: Control = row["name_box"]
		if str(row["type"]) == "idle":
			_set_text(count_label, str(idle))
			_set_color(count_label, COLOR_WARN if idle > 0 else COLOR_NORMAL)
			continue
		var n := ws.get_job_count(k, id)
		var cap := ws.get_job_capacity(k, id)
		_set_text(count_label, "%d/%d" % [n, cap] if cap >= 0 else str(n))
		var paused_label: Label = row["paused"]
		var paused := int(paused_by_job.get(id, 0))
		_set_text(paused_label, "(%d pausiert)" % paused if paused > 0 else "")
		paused_label.visible = paused > 0
		var job := DataDB.get_job(id)
		var problem := ws.get_job_problem(k, id)
		_set_text(warn, "" if problem.is_empty() else "(!)")
		var tip := problem
		if tip.is_empty():
			var activity := str(job.get("activity", ""))
			tip = str(row["name"]) + ((" – " + activity) if not activity.is_empty() else "")
		if name_box.tooltip_text != tip:
			name_box.tooltip_text = tip
			count_label.tooltip_text = tip

		var minus: Button = row["minus"]
		minus.disabled = n == 0
		var plus: Button = row["plus"]
		var plus_tip := "Einen unbeschäftigten Bewohner als %s einsetzen" % str(row["name"])
		var can_add := true
		if idle == 0:
			can_add = false
			plus_tip = NO_IDLE_TIP
		elif str(row["type"]) == "building" and not ws.has_free_slot(k, id):
			can_add = false
			plus_tip = str(job.get("hint", "Kein freier Platz."))
		plus.disabled = not can_add
		if plus.tooltip_text != plus_tip:
			plus.tooltip_text = plus_tip


func _on_plus_pressed(job_id: String) -> void:
	game.work_system.assign_job(game.player, job_id)
	_refresh()


func _on_minus_pressed(job_id: String) -> void:
	game.work_system.unassign_job(game.player, job_id)
	_refresh()


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _set_color(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


## Kleiner, quadratischer Button (z. B. "−" / "+") mit schmalen Innenabständen.
## ref liefert die Theme-Stile (muss im Baum sein).
static func make_small_button(text: String, ref: Control, side: float = SMALL_BUTTON_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(side, side)
	b.add_theme_font_size_override("font_size", 17)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := ref.get_theme_stylebox(style_name, "Button")
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = 2.0
		style.content_margin_right = 2.0
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0
		b.add_theme_stylebox_override(style_name, style)
	return b
