## HeroPanel
##
## Heldenfenster (Taste G, Button "Helden (G)" oben; G, Esc oder × schliesst).
## Gleiche Bauart wie das Forschungsfenster (eigene Ebene, Mitte oben); das
## Spiel läuft weiter.
## - Reiter "Meine Helden": links die Liste (Porträt, Name, Stufe, Zustand,
##   Markierung bei offener Stufenwahl), rechts der gewählte Held: Name, Typ,
##   Stufe mit EP-Balken, Leben, Werte und Führung, die drei Fähigkeiten mit Rang
##   (I–III), Abklingzeit und "selbst auslösen" (Rechtsklick), Talente, offene
##   Stufenwahl (zwei Karten zum Anklicken), Ausbildung, Wiederbelebung,
##   Hinspringen und Entlassen (zweiter Klick bestätigt). Im F3-Modus Knöpfe
##   "+1 Stufe", "Abklingzeiten", "Sofort wiederbeleben", "Held fällt".
## - Reiter "Anwerben": die Helden des Reichs mit Kosten (jeder weitere Held
##   kostet mehr), Dauer und dem Grund, falls es nicht geht (keine Halle, zu viele
##   Helden, schon vorhanden, Rohstoffe); laufende Anwerbung.
## Zeigt nur an und ruft das HeroSystem auf. Aktualisiert wird bei Signalen und
## alle 0.25 s, solange das Fenster offen ist; Knöpfe werden nur neu gebaut, wenn
## sich die Heldenliste bzw. die Angebote ändern.
class_name HeroPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const TAB_HEROES := "heroes"
const TAB_RECRUIT := "recruit"
const DESIGN_WIDTH := 1000.0
const TOP := 92.0
const MARGIN_X := 16.0
const MARGIN_Y := 12.0
const REFRESH_INTERVAL := 0.25
## So lange (ms) gilt der erste Klick auf "Entlassen"
const CONFIRM_MS := 3000
const LIST_WIDTH := 236.0
const PAGE_HEIGHT := 700.0
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_WARN := Color(1.0, 0.82, 0.35)

var game: Node

var _accent := ResearchPanel.GOOD_ACCENT
var _light := ResearchPanel.GOOD_LIGHT
var _evil := false
var _tab := TAB_HEROES
var _timer := 0.0
## Gewählter Held im Reiter "Meine Helden" (Eintrags-id, 0 = keiner)
var _hero_id := 0
## Entlassen: Held und Zeitpunkt des ersten Klicks
var _confirm_hero := 0
var _confirm_ms := 0
var _refresh_queued := false

var _tab_heroes: ResearchTipButton
var _tab_recruit: ResearchTipButton
var _count_label: Label
var _heroes_page: HBoxContainer
var _recruit_page: VBoxContainer
var _footer: Label

# Liste links
var _list: VBoxContainer
var _list_ids: Array = []
## hero_id -> {"button", "portrait", "name", "sub", "state"}
var _list_entries: Dictionary = {}
var _empty_label: Label

# Einzelheiten rechts
var _detail: VBoxContainer
var _portrait: HeroPortrait
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _state_label: Label
var _level_label: Label
var _xp_bar: HpBar
var _hp_bar: HpBar
var _stats_label: Label
var _lead_label: Label
## Je Fähigkeit: {"id", "button": AbilityButton, "name": Label, "values": Label, "state": Label}
var _ability_rows: Array = []
var _ability_box: VBoxContainer
var _shown_type := ""
var _talents_label: Label
var _choice_panel: PanelContainer
var _choice_title: Label
var _option_buttons: Array[ResearchTipButton] = []
var _train_button: ResearchTipButton
var _revive_button: ResearchTipButton
var _jump_button: Button
var _dismiss_button: Button
var _action_info: RichTextLabel
var _debug_row: HBoxContainer

# Anwerben
var _recruit_status: Label
var _queue_label: Label
var _hall_button: Button
var _offer_list: VBoxContainer
var _offer_ids: PackedStringArray = []
## type_id -> {"portrait", "cost": RichTextLabel, "time": Label, "button": ResearchTipButton, "reason": Label}
var _offer_entries: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Aufbauen (das Fenster muss schon im Baum hängen)
func setup(p_game: Node) -> void:
	game = p_game
	var k: Kingdom = game.player
	_evil = k.faction_id == "evil"
	_accent = ResearchPanel.EVIL_ACCENT if _evil else ResearchPanel.GOOD_ACCENT
	_light = ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_LIGHT
	add_theme_stylebox_override("panel", _panel_style())
	_build()
	var hs: HeroSystem = game.hero_system
	hs.heroes_changed.connect(_on_heroes_changed)
	hs.xp_gained.connect(_on_xp_gained)
	game.summon_system.queue_changed.connect(_on_queue_changed)
	get_viewport().size_changed.connect(_place)
	_show_tab(TAB_HEROES)


func is_open() -> bool:
	return visible


## Öffnen, optional auf einem Reiter (TAB_HEROES / TAB_RECRUIT) und bei einem Helden
func open(tab: String = "", hero_id: int = 0) -> void:
	if hero_id != 0:
		_hero_id = hero_id
	if not tab.is_empty():
		_show_tab(tab)
	if visible:
		_refresh()
		return
	visible = true
	set_process(true)
	_timer = 0.0
	_refresh()
	_place()
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	_confirm_hero = 0
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func get_tab() -> String:
	return _tab


## Gewählter Held im Fenster (0 = keiner)
func get_hero_id() -> int:
	return _hero_id


## Etwas zu tun? (offene Stufenwahl oder ein Held kann wiederbelebt werden)
static func needs_attention(hs: HeroSystem, k: Kingdom) -> bool:
	for rec in hs.get_heroes(k):
		if int(rec["pending"]) > 0:
			return true
		if bool(rec["dead"]) and hs.can_revive(k, int(rec["id"])).is_empty():
			return true
	return false


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	if _confirm_hero != 0 and Time.get_ticks_msec() - _confirm_ms > CONFIRM_MS:
		_confirm_hero = 0
	_refresh()


func _on_heroes_changed(k: Kingdom) -> void:
	_on_player_changed(k)


func _on_xp_gained(k: Kingdom, _hero_id_gained: int, _amount: int, _reason: String) -> void:
	_on_player_changed(k)


func _on_queue_changed(b: Building) -> void:
	if b.kingdom == game.player and bool(b.def.get("hero_hall", false)):
		_on_player_changed(b.kingdom)


## Signale gelten für alle Reiche – nur der Spieler zählt; höchstens einmal pro Bild
func _on_player_changed(k: Kingdom) -> void:
	if visible and k == game.player and not _refresh_queued:
		_refresh_queued = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	_refresh()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Titelzeile: Wappen, Titel, Anzahl, Reiter, Schliessen
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_row)
	var emblem := ResearchPanel.Emblem.new()
	emblem.evil = _evil
	emblem.color = _evil_or(ResearchPanel.EVIL_LIGHT, ResearchPanel.GOOD_ACCENT)
	emblem.custom_minimum_size = Vector2(26, 26)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(emblem)
	var title := _label(25, _evil_or(ResearchPanel.EVIL_LIGHT, ResearchPanel.GOOD_ACCENT))
	title.text = "Helden · %s" % ("Schatten" if _evil else "Licht")
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("outline_size", 4)
	title_row.add_child(title)
	_count_label = _label(16, COLOR_DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_count_label)
	var group := ButtonGroup.new()
	_tab_heroes = _make_tab("Meine Helden", group)
	_tab_heroes.badge_color = HeroUI.COLOR_PENDING
	_tab_heroes.tooltip_text = "Eigene Helden: Stufenwahl, Ausbildung, Wiederbelebung"
	_tab_heroes.pressed.connect(_show_tab.bind(TAB_HEROES))
	title_row.add_child(_tab_heroes)
	_tab_recruit = _make_tab("Anwerben", group)
	_tab_recruit.tooltip_text = "Neue Helden in der Heldenhalle anwerben"
	_tab_recruit.pressed.connect(_show_tab.bind(TAB_RECRUIT))
	title_row.add_child(_tab_recruit)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Schliessen (G oder Esc)"
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.custom_minimum_size = Vector2(40, 36)
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	var title_line := ColorRect.new()
	title_line.color = Color(_accent, 0.55)
	title_line.custom_minimum_size = Vector2(0, 1)
	title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_line)

	# Seiten (gleich hoch: das Fenster springt beim Reiterwechsel nicht)
	var pages := MarginContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	root.add_child(pages)
	_heroes_page = HBoxContainer.new()
	_heroes_page.add_theme_constant_override("separation", 14)
	_heroes_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(_heroes_page)
	_build_heroes_page()
	_recruit_page = VBoxContainer.new()
	_recruit_page.add_theme_constant_override("separation", 10)
	_recruit_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(_recruit_page)
	_build_recruit_page()

	_footer = _label(15, COLOR_DIM)
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_footer)


func _build_heroes_page() -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heroes_page.add_child(left)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_list)
	_empty_label = _label(16, COLOR_DIM)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.text = "Noch keine Helden.\nReiter „Anwerben“: Helden in der Heldenhalle anwerben."
	left.add_child(_empty_label)

	var sep := ColorRect.new()
	sep.color = Color(_accent, 0.3)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heroes_page.add_child(sep)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heroes_page.add_child(_detail)

	# Kopf: Porträt, Name, Typ, Beschreibung, Zustand
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(head)
	_portrait = HeroPortrait.new()
	_portrait.custom_minimum_size = Vector2(100, 100)
	head.add_child(_portrait)
	var head_text := VBoxContainer.new()
	head_text.add_theme_constant_override("separation", 2)
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_text)
	_name_label = _label(23, _light)
	head_text.add_child(_name_label)
	_type_label = _label(16, _accent.lightened(0.2))
	head_text.add_child(_type_label)
	_desc_label = _wrap_label(15, COLOR_DIM)
	head_text.add_child(_desc_label)
	_state_label = _label(16, COLOR_TEXT)
	_state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_text.add_child(_state_label)

	# Stufe und Leben
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 10)
	level_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(level_row)
	_level_label = _label(18, _light)
	_level_label.custom_minimum_size = Vector2(90, 0)
	level_row.add_child(_level_label)
	_xp_bar = HpBar.new()
	_xp_bar.fill_color = HeroUI.COLOR_XP
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_row.add_child(_xp_bar)
	_hp_bar = HpBar.new()
	_hp_bar.custom_minimum_size = Vector2(220, 20)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_row.add_child(_hp_bar)
	_stats_label = _wrap_label(15, COLOR_TEXT)
	_detail.add_child(_stats_label)
	_lead_label = _wrap_label(15, COLOR_DIM)
	_detail.add_child(_lead_label)

	# Fähigkeiten
	var abil_title := _label(17, _accent.lightened(0.2))
	abil_title.text = "Fähigkeiten"
	_detail.add_child(abil_title)
	_ability_box = VBoxContainer.new()
	_ability_box.add_theme_constant_override("separation", 5)
	_ability_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_ability_box)
	_talents_label = _wrap_label(15, COLOR_TEXT)
	_detail.add_child(_talents_label)

	# Stufenwahl: zwei Karten
	_choice_panel = PanelContainer.new()
	_choice_panel.add_theme_stylebox_override("panel", _info_style(HeroUI.COLOR_PENDING))
	_choice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_choice_panel)
	var choice_box := VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 6)
	choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_panel.add_child(choice_box)
	_choice_title = _label(17, HeroUI.COLOR_PENDING)
	choice_box.add_child(_choice_title)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_box.add_child(options)
	for i in 2:
		var b := ResearchTipButton.new()
		b.add_theme_font_size_override("font_size", 15)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 62)
		b.pressed.connect(_on_option_pressed.bind(i))
		options.add_child(b)
		_option_buttons.append(b)

	# Aktionen
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(actions)
	_train_button = _tip_button("Ausbilden")
	_train_button.tip_source = _train_tip
	_train_button.pressed.connect(_on_train_pressed)
	actions.add_child(_train_button)
	_revive_button = _tip_button("Wiederbeleben")
	_revive_button.tip_source = _revive_tip
	_revive_button.pressed.connect(_on_revive_pressed)
	actions.add_child(_revive_button)
	_jump_button = _plain_button("Hinspringen")
	_jump_button.tooltip_text = "Held auswählen und die Kamera hinbewegen (Fenster schliesst sich)"
	_jump_button.pressed.connect(_on_jump_pressed)
	actions.add_child(_jump_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(gap)
	_dismiss_button = _plain_button("Entlassen")
	_dismiss_button.custom_minimum_size = Vector2(170, 0)
	_dismiss_button.pressed.connect(_on_dismiss_pressed)
	actions.add_child(_dismiss_button)
	_action_info = RichTextLabel.new()
	_action_info.bbcode_enabled = true
	_action_info.fit_content = true
	_action_info.scroll_active = false
	_action_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_info.add_theme_font_size_override("normal_font_size", 15)
	_action_info.add_theme_color_override("default_color", COLOR_DIM)
	_detail.add_child(_action_info)

	# Debug (F3)
	_debug_row = HBoxContainer.new()
	_debug_row.add_theme_constant_override("separation", 6)
	_debug_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_debug_row)
	var debug_title := _label(14, COLOR_WARN)
	debug_title.text = "Debug:"
	_debug_row.add_child(debug_title)
	for entry in [["+1 Stufe", "level"], ["Abklingzeiten", "cooldowns"], ["Sofort wiederbeleben", "revive"],
			["Held fällt", "kill"]]:
		var b := _plain_button(str(entry[0]))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(debug_action.bind(str(entry[1])))
		_debug_row.add_child(b)


func _build_recruit_page() -> void:
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recruit_page.add_child(status_row)
	_recruit_status = _wrap_label(17, COLOR_TEXT)
	_recruit_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_recruit_status)
	_hall_button = _plain_button("")
	_hall_button.tooltip_text = "Bauvorschau starten (Fenster schliesst sich)"
	_hall_button.pressed.connect(_on_build_hall_pressed)
	status_row.add_child(_hall_button)
	_queue_label = _label(16, COLOR_WARN)
	_recruit_page.add_child(_queue_label)
	_offer_list = VBoxContainer.new()
	_offer_list.add_theme_constant_override("separation", 10)
	_offer_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recruit_page.add_child(_offer_list)


func _make_tab(text: String, group: ButtonGroup) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(150, 36)
	var pressed := _flat(_evil_or(ResearchPanel.EVIL_MID, Color(0.62, 0.47, 0.2)), _light, 1, 4)
	pressed.content_margin_left = 14
	pressed.content_margin_right = 14
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	return b


func _show_tab(tab: String) -> void:
	_tab = TAB_RECRUIT if tab == TAB_RECRUIT else TAB_HEROES
	var recruit := _tab == TAB_RECRUIT
	_tab_heroes.set_pressed_no_signal(not recruit)
	_tab_recruit.set_pressed_no_signal(recruit)
	_heroes_page.visible = not recruit
	_recruit_page.visible = recruit
	_footer.text = ("Anwerben in der Heldenhalle · jeder weitere Held kostet mehr  ·  G / Esc: schliessen" if recruit else
			"Fähigkeiten: Klick wirkt, Rechtsklick = selbst auslösen  ·  Stufenwahl: Karte anklicken  ·  G / Esc: schliessen")
	_confirm_hero = 0
	if visible:
		_refresh()


## Mitte oben; bei kleinem Fenster verkleinert, aber nie ausserhalb
func _place() -> void:
	var vp := get_viewport_rect().size
	var want := Vector2(DESIGN_WIDTH, get_combined_minimum_size().y)
	size = want
	var s := minf(1.0, minf((vp.x - 16.0) / want.x, (vp.y - TOP - 8.0) / want.y))
	s = maxf(s, 0.4)
	scale = Vector2(s, s)
	var top := clampf(TOP, 8.0, maxf(vp.y - want.y * s - 8.0, 8.0))
	position = Vector2(floorf((vp.x - want.x * s) * 0.5), floorf(top))


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if game == null or not visible:
		return
	var k: Kingdom = game.player
	var hs: HeroSystem = game.hero_system
	_set_text(_count_label, "%d von %d Helden" % [hs.count_heroes(k), hs.max_heroes(k)], COLOR_DIM)
	_tab_heroes.badge_visible = needs_attention(hs, k)
	if _tab == TAB_HEROES:
		_refresh_heroes(k)
	else:
		_refresh_recruit(k)


func _refresh_heroes(k: Kingdom) -> void:
	var hs: HeroSystem = game.hero_system
	var ids: Array = []
	for rec in hs.get_heroes(k):
		ids.append(int(rec["id"]))
	if ids != _list_ids:
		_rebuild_list(ids)
	if not ids.has(_hero_id):
		_hero_id = int(ids[0]) if not ids.is_empty() else 0
	_empty_label.visible = ids.is_empty()
	for hid in ids:
		_refresh_list_entry(k, int(hid))
	_detail.visible = _hero_id != 0
	if _hero_id != 0:
		_refresh_detail(k, hs.get_record(k, _hero_id))


func _rebuild_list(ids: Array) -> void:
	_list_ids = ids.duplicate()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_list_entries.clear()
	var hs: HeroSystem = game.hero_system
	for hid in ids:
		var rec := hs.get_record(game.player, int(hid))
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(LIST_WIDTH, 70)
		b.pressed.connect(_on_list_pressed.bind(int(hid)))
		_list.add_child(b)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6.0
		row.offset_top = 5.0
		row.offset_right = -6.0
		row.offset_bottom = -5.0
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var portrait := HeroPortrait.new()
		portrait.custom_minimum_size = Vector2(56, 56)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.setup(hs.get_type(rec))
		row.add_child(portrait)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.alignment = BoxContainer.ALIGNMENT_CENTER
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(texts)
		var name_label := _label(17, _light)
		texts.add_child(name_label)
		var sub := _label(14, COLOR_DIM)
		texts.add_child(sub)
		var state := _label(14, COLOR_TEXT)
		state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		texts.add_child(state)
		_list_entries[int(hid)] = {"button": b, "portrait": portrait, "name": name_label, "sub": sub, "state": state}


func _refresh_list_entry(k: Kingdom, hero_id: int) -> void:
	var hs: HeroSystem = game.hero_system
	var rec := hs.get_record(k, hero_id)
	var e: Dictionary = _list_entries.get(hero_id, {})
	if rec.is_empty() or e.is_empty():
		return
	var dead := bool(rec["dead"])
	var pending := int(rec["pending"])
	(e["portrait"] as HeroPortrait).set_state(dead, int(rec["level"]), pending > 0)
	_set_text(e["name"], str(rec["name"]), HeroUI.COLOR_DEAD if dead else _light)
	_set_text(e["sub"], "%s · Stufe %d" % [str(hs.get_type(rec).get("name", "")), int(rec["level"])], COLOR_DIM)
	var state := "Stufenwahl offen!" if pending > 0 else HeroUI.state_text(hs, rec, hs.get_unit(k, hero_id))
	if dead:
		var wait := hs.revive_ready_in(rec)
		state = "Gefallen · noch %d s" % ceili(wait) if wait > 0.0 else "Gefallen · Wiederbeleben"
	var color := HeroUI.COLOR_PENDING if pending > 0 and not dead else (COLOR_BAD if dead else COLOR_TEXT)
	_set_text(e["state"], state, color)
	var b: Button = e["button"]
	if b.button_pressed != (hero_id == _hero_id):
		b.set_pressed_no_signal(hero_id == _hero_id)


func _refresh_detail(k: Kingdom, rec: Dictionary) -> void:
	if rec.is_empty():
		return
	var hs: HeroSystem = game.hero_system
	var hid := int(rec["id"])
	var htype := hs.get_type(rec)
	var u := hs.get_unit(k, hid)
	var dead := bool(rec["dead"])
	var pending := int(rec["pending"])
	if str(rec["type_id"]) != _shown_type:
		_shown_type = str(rec["type_id"])
		_portrait.setup(htype)
		_build_ability_rows(htype)
	_portrait.set_state(dead, 0, pending > 0)
	_set_text(_name_label, str(rec["name"]), HeroUI.COLOR_DEAD if dead else _light)
	var type_text := str(htype.get("name", ""))
	if not str(htype.get("title", "")).is_empty():
		type_text += " – " + str(htype["title"])
	_set_text(_type_label, type_text, _accent.lightened(0.2))
	_set_text(_desc_label, str(htype.get("description", "")), COLOR_DIM)
	_set_text(_state_label, HeroUI.state_text(hs, rec, u), COLOR_BAD if dead else COLOR_TEXT)

	_set_text(_level_label, "Stufe %d" % int(rec["level"]), _light)
	var need := hs.xp_for_next(rec)
	_xp_bar.set_value(float(rec["xp"]) if need > 0 else 1.0, float(need) if need > 0 else 1.0, HeroUI.xp_text(hs, rec))
	_hp_bar.visible = u != null
	if u != null:
		_hp_bar.set_value(u.hp, u.max_hp)
	_set_text(_stats_label, _stats_text(rec, u), COLOR_TEXT)
	_set_text(_lead_label, _leadership_text(rec), COLOR_DIM)

	# Fähigkeiten
	var st: SpellTargeting = game.spell_targeting
	for row in _ability_rows:
		var r: Dictionary = row
		var aid := str(r["id"])
		var def := DataDB.get_ability(aid)
		var rank := hs.get_rank(rec, aid)
		var passive := HeroUI.is_passive(aid)
		var cd := hs.cooldown_left(rec, aid)
		var total := maxf(float(hs.get_ability_values(rec, aid).get("cooldown", 0.0)), 0.01)
		var reason := "Der Held lebt nicht" if u == null else hs.can_use(u, aid)
		var castable := rank > 0 and not passive and HeroUI.is_ready_reason(reason)
		var button: AbilityButton = r["button"]
		button.set_state(rank > 0, cd / total, ceili(cd), false, u != null and st.is_ability_targeting(u.uid, aid), castable)
		button.set_extra(rank, hs.is_autocast(rec, aid))
		var title := str(def.get("name", aid))
		title += "  ·  Rang %s" % HeroUI.roman(rank) if rank > 0 else "  ·  noch nicht gelernt"
		_set_text(r["name"], title, SpellButton._bright(def.get("color", Color.WHITE)) if rank > 0 else COLOR_DIM)
		var values := HeroUI.values_text(aid, hs.get_ability_values(rec, aid))
		_set_text(r["values"], values, COLOR_DIM)
		var state := ""
		var state_color := COLOR_GOOD
		if passive:
			state = "passiv – wirkt von selbst" if rank > 0 else "passiv"
		elif rank <= 0:
			state = "bei einer Stufenwahl wählbar"
			state_color = COLOR_DIM
		elif cd > 0.0:
			state = "Abklingzeit: noch %d s" % ceili(cd)
			state_color = COLOR_WARN
		elif not HeroUI.is_ready_reason(reason):
			state = reason
			state_color = COLOR_BAD
		else:
			state = "bereit"
		if rank > 0 and HeroUI.can_autocast(aid):
			state += "  ·  selbst auslösen: %s" % ("an" if hs.is_autocast(rec, aid) else "aus")
		_set_text(r["state"], state, state_color)

	var talents := HeroUI.talents_text(hs, rec)
	_set_text(_talents_label, "Talente: " + (talents if not talents.is_empty() else "noch keine"), COLOR_TEXT)

	# Stufenwahl
	var options := hs.get_levelup_options(k, hid)
	_choice_panel.visible = not options.is_empty()
	if not options.is_empty():
		var choice_level := int(rec["level"]) - pending + 1
		var title := "Stufenwahl für Stufe %d – wähle eine Verbesserung" % choice_level
		if pending > 1:
			title += " (noch %d offen)" % pending
		_set_text(_choice_title, title, HeroUI.COLOR_PENDING)
		for i in _option_buttons.size():
			var b := _option_buttons[i]
			b.visible = i < options.size()
			if not b.visible:
				continue
			var o: Dictionary = options[i]
			var text := "%s\n%s" % [str(o["name"]), str(o["text"])]
			if b.text != text:
				b.text = text
			b.tooltip_text = ("Fähigkeit: " if str(o["kind"]) == "ability" else "Talent: ") + str(o["name"])

	# Aktionen
	_train_button.visible = not dead
	if not dead:
		var train_reason := hs.can_train(k, hid)
		_set_button_text(_train_button, "Ausbilden (+%d EP)" % int(DataDB.hero_cfg("training.xp", 80)))
		if _train_button.disabled == train_reason.is_empty():
			_train_button.disabled = not train_reason.is_empty()
	_revive_button.visible = dead
	if dead:
		var revive_reason := hs.can_revive(k, hid)
		var wait := hs.revive_ready_in(rec)
		_set_button_text(_revive_button, "Wiederbeleben (noch %d s)" % ceili(wait) if wait > 0.0 else "Wiederbeleben")
		if _revive_button.disabled == revive_reason.is_empty():
			_revive_button.disabled = not revive_reason.is_empty()
	_jump_button.disabled = u == null and not is_instance_valid(k.castle)
	_set_button_text(_jump_button, "Hinspringen" if u != null else "Zur Burg")
	var confirm := _confirm_hero == hid
	_set_button_text(_dismiss_button, "Wirklich entlassen?" if confirm else "Entlassen")
	_dismiss_button.tooltip_text = "Der Held verlässt dein Reich (nichts wird erstattet). Zum Bestätigen zweimal klicken."
	var info := _action_info_text(k, rec)
	if _action_info.text != info:
		_action_info.text = info
	var hud: Node = game.hud
	_debug_row.visible = hud.has_method("is_debug_visible") and bool(hud.call("is_debug_visible"))


## Ausbildung bzw. Wiederbelebung: Kosten (fehlende rot) und Grund
func _action_info_text(k: Kingdom, rec: Dictionary) -> String:
	var hs: HeroSystem = game.hero_system
	var hid := int(rec["id"])
	var tip := ResearchTipButton
	if bool(rec["dead"]):
		var revive_reason := hs.can_revive(k, hid)
		var revive_text := "Wiederbelebung in der Burg: " + HeroUI.cost_bbcode(k, hs.revive_cost(rec))
		if not revive_reason.is_empty():
			revive_text += "  ·  " + tip.colored(revive_reason, COLOR_BAD)
		return revive_text
	var reason := hs.can_train(k, hid)
	var text := "Ausbildung (bis Stufe %d): %s" % [hs.train_cap(k), HeroUI.cost_bbcode(k, DataDB.hero_cfg("training.cost", {}))]
	if not reason.is_empty():
		text += "  ·  " + tip.colored(reason, COLOR_WARN if reason.begins_with("Nächste") else COLOR_BAD)
	else:
		text += "  ·  " + tip.colored("bereit", COLOR_GOOD)
	return text


## "Leben 520 · Angriff 32 · Rüstung 35 % · Reichweite Nahkampf · Tempo 2,4"
func _stats_text(rec: Dictionary, u: Unit) -> String:
	if u != null:
		var reach := "Nahkampf" if u.attack_range < SelectionPanel.MELEE_RANGE else "%s Felder" % HeroUI.num(u.attack_range)
		return "Leben %d · Angriff %s · Rüstung %d %% · Reichweite %s · Tempo %s" % [roundi(u.max_hp),
				HeroUI.num(u.attack), roundi(u.armor * 100.0), reach, HeroUI.num(u.speed)]
	var stats: Dictionary = game.hero_system.get_type(rec).get("stats", {})
	return "Grundwerte: Leben %d · Angriff %s · Rüstung %d %%" % [int(stats.get("hp", 0)),
			HeroUI.num(float(stats.get("attack", 0.0))), roundi(float(stats.get("armor", 0.0)) * 100.0)]


## Führung: "+9 % Angriff für eigene Truppen im Umkreis von 6 Feldern · <Eigenschaft>"
func _leadership_text(rec: Dictionary) -> String:
	var mult := float(DataDB.hero_cfg("leadership.attack_base", 0.05)) \
			+ float(DataDB.hero_cfg("leadership.attack_per_level", 0.01)) * int(rec["level"])
	var factor := 1.0 + mult
	for t in game.hero_system.get_talents(rec):
		var lead: Dictionary = (t as Dictionary).get("leadership", {})
		if str(lead.get("key", "")) == "attack":
			factor *= float(lead.get("mult", 1.0))
	var text := "Führung: +%d %% Angriff für eigene Truppen im Umkreis von %d Feldern" % [
			roundi((factor - 1.0) * 100.0), int(DataDB.hero_cfg("leadership.radius", 6))]
	var trait_text := str(game.hero_system.get_type(rec).get("leadership_text", ""))
	if not trait_text.is_empty():
		text += " · " + trait_text
	return text


func _build_ability_rows(htype: Dictionary) -> void:
	for child in _ability_box.get_children():
		_ability_box.remove_child(child)
		child.queue_free()
	_ability_rows.clear()
	var abilities: Array = htype.get("abilities", [])
	for i in abilities.size():
		var aid := str(abilities[i])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ability_box.add_child(row)
		var b := AbilityButton.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.setup_ability(DataDB.get_ability(aid), str(HeroUI.ABILITY_KEYS[i]) if i < HeroUI.ABILITY_KEYS.size() else "")
		b.tip_source = _ability_tip.bind(aid, i)
		b.pressed.connect(_on_ability_pressed.bind(aid))
		b.autocast_requested.connect(_on_autocast_requested)
		row.add_child(b)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.alignment = BoxContainer.ALIGNMENT_CENTER
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(texts)
		var name_label := _label(16, COLOR_TEXT)
		texts.add_child(name_label)
		var values := _label(14, COLOR_DIM)
		values.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		texts.add_child(values)
		var state := _label(14, COLOR_GOOD)
		texts.add_child(state)
		_ability_rows.append({"id": aid, "button": b, "name": name_label, "values": values, "state": state})


func _refresh_recruit(k: Kingdom) -> void:
	var hs: HeroSystem = game.hero_system
	var offers := hs.get_offers(k)
	var ids := PackedStringArray()
	for o in offers:
		ids.append(str((o as Dictionary).get("id", "")))
	if ids != _offer_ids:
		_rebuild_offers(ids)
	var hall_def := DataDB.get_building("hero_hall")
	var hall_name := DataDB.get_building_name(hall_def, k.faction_id)
	var hall := hs.get_hall(k)
	var hall_text := ""
	var show_build := false
	if hall != null:
		hall_text = "%s bereit" % hall_name
	else:
		var site: Building = null
		for b in k.buildings:
			if bool(b.def.get("hero_hall", false)):
				site = b
		if site != null:
			hall_text = "%s im Bau: %d %%" % [hall_name, roundi(site.get_progress_ratio() * 100.0)]
		else:
			hall_text = "Keine %s – Helden werden dort angeworben" % hall_name
			show_build = true
	_set_text(_recruit_status, "Helden: %d von %d (gefallene und angeworbene zählen mit)  ·  %s" % [
			hs.count_heroes(k), hs.max_heroes(k), hall_text], COLOR_TEXT)
	_hall_button.visible = show_build
	if show_build:
		var build_reason: String = game.building_system.can_build_type(hall_def, k)
		_set_button_text(_hall_button, "%s bauen" % hall_name)
		_hall_button.disabled = not build_reason.is_empty()
		_hall_button.tooltip_text = build_reason if not build_reason.is_empty() else "Bauvorschau starten (Fenster schliesst sich)"
	# Laufende Anwerbung
	var queue_text := ""
	if hall != null and not hall.summon_queue.is_empty():
		var first: Dictionary = hall.summon_queue[0]
		var left := (float(first.get("time", 0.0)) - float(first.get("progress", 0.0))) / maxf(k.mod("summon"), 0.01)
		queue_text = "Wird angeworben: %s – noch %d s" % [str(DataDB.get_unit_type(str(first.get("type_id", ""))).get("name", "?")),
				maxi(ceili(left), 0)]
	_set_text(_queue_label, queue_text, COLOR_WARN)
	_queue_label.visible = not queue_text.is_empty()
	for type_id in _offer_entries:
		_refresh_offer(k, str(type_id))


func _rebuild_offers(ids: PackedStringArray) -> void:
	_offer_ids = ids
	for child in _offer_list.get_children():
		_offer_list.remove_child(child)
		child.queue_free()
	_offer_entries.clear()
	for type_id in ids:
		var htype := DataDB.get_hero_type(type_id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _info_style(_accent))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_offer_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var portrait := HeroPortrait.new()
		portrait.custom_minimum_size = Vector2(96, 96)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.setup(htype)
		row.add_child(portrait)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(texts)
		var title := _label(19, _light)
		title.text = str(htype.get("name", type_id))
		if not str(htype.get("title", "")).is_empty():
			title.text += " – " + str(htype["title"])
		texts.add_child(title)
		var desc := _wrap_label(15, COLOR_DIM)
		desc.text = str(htype.get("description", ""))
		texts.add_child(desc)
		var stats: Dictionary = htype.get("stats", {})
		var stat_label := _wrap_label(14, COLOR_TEXT)
		stat_label.text = "Leben %d · Angriff %s · Rüstung %d %% · Reichweite %s · Tempo %s" % [int(stats.get("hp", 0)),
				HeroUI.num(float(stats.get("attack", 0.0))), roundi(float(stats.get("armor", 0.0)) * 100.0),
				HeroUI.num(float(stats.get("range", 0.0))), HeroUI.num(float(stats.get("speed", 0.0)))]
		texts.add_child(stat_label)
		var names: PackedStringArray = []
		for aid in htype.get("abilities", []):
			var adef := DataDB.get_ability(str(aid))
			names.append("%s%s" % [str(adef.get("name", aid)), " (passiv)" if str(adef.get("kind", "")) != "active" else ""])
		var abil_label := _wrap_label(14, COLOR_TEXT)
		abil_label.text = "Fähigkeiten: " + ", ".join(names)
		texts.add_child(abil_label)
		var lead := str(htype.get("leadership_text", ""))
		if not lead.is_empty():
			var lead_label := _wrap_label(14, COLOR_DIM)
			lead_label.text = "Führung: " + lead
			texts.add_child(lead_label)

		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 4)
		side.custom_minimum_size = Vector2(250, 0)
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(side)
		var cost := RichTextLabel.new()
		cost.bbcode_enabled = true
		cost.fit_content = true
		cost.scroll_active = false
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.add_theme_font_size_override("normal_font_size", 15)
		cost.add_theme_color_override("default_color", COLOR_TEXT)
		side.add_child(cost)
		var time := _label(14, COLOR_DIM)
		side.add_child(time)
		var button := _tip_button("Anwerben")
		button.tip_source = _offer_tip.bind(type_id)
		button.pressed.connect(_on_recruit_pressed.bind(type_id))
		side.add_child(button)
		var reason := _wrap_label(14, COLOR_BAD)
		side.add_child(reason)
		_offer_entries[type_id] = {"cost": cost, "time": time, "button": button, "reason": reason}


func _refresh_offer(k: Kingdom, type_id: String) -> void:
	var e: Dictionary = _offer_entries[type_id]
	var hs: HeroSystem = game.hero_system
	var cost_text := "Kosten: " + HeroUI.cost_bbcode(k, hs.recruit_cost(k, type_id))
	var cost: RichTextLabel = e["cost"]
	if cost.text != cost_text:
		cost.text = cost_text
	var seconds := float(DataDB.get_unit_type(type_id).get("summon_time", 30.0)) / maxf(k.mod("summon"), 0.01)
	_set_text(e["time"], "Dauer: %d s" % ceili(seconds), COLOR_DIM)
	var reason := recruit_reason(type_id)
	var button: ResearchTipButton = e["button"]
	if button.disabled == reason.is_empty():
		button.disabled = not reason.is_empty()
	_set_text(e["reason"], reason.get_slice("\n", 0), COLOR_BAD)


## Warum dieser Held gerade nicht angeworben werden kann ("" = es geht)
func recruit_reason(type_id: String) -> String:
	var k: Kingdom = game.player
	var hs: HeroSystem = game.hero_system
	var reason := hs.can_recruit(k, type_id)
	if not reason.is_empty():
		return reason
	var hall := hs.get_hall(k)
	if hall == null:
		return "Die %s ist noch im Bau" % DataDB.get_building_name(DataDB.get_building("hero_hall"), k.faction_id)
	return game.summon_system.can_summon(hall, type_id)


# ---------------------------------------------------------------------------
# Tooltips
# ---------------------------------------------------------------------------

func _ability_tip(ability_id: String, index: int) -> String:
	var hs: HeroSystem = game.hero_system
	var rec := hs.get_record(game.player, _hero_id)
	var key := str(HeroUI.ABILITY_KEYS[index]) if index < HeroUI.ABILITY_KEYS.size() else ""
	return HeroUI.ability_tip(hs, rec, ability_id, hs.get_unit(game.player, _hero_id), key)


func _train_tip() -> String:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var lines: PackedStringArray = ["[b]Ausbildung in der Heldenhalle[/b]: +%d EP" % int(DataDB.hero_cfg("training.xp", 80))]
	lines.append("Kosten: " + HeroUI.cost_bbcode(k, DataDB.hero_cfg("training.cost", {})))
	lines.append("Bis Stufe %d (Forschung Heldenlehre: höher), danach nur noch im Kampf." % hs.train_cap(k))
	lines.append("Danach %d s Pause." % int(DataDB.hero_cfg("training.cooldown", 60)))
	var reason := hs.can_train(k, _hero_id)
	if not reason.is_empty():
		lines.append(ResearchTipButton.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _revive_tip() -> String:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var rec := hs.get_record(k, _hero_id)
	if rec.is_empty():
		return ""
	var lines: PackedStringArray = ["[b]Wiederbeleben[/b] an der Burg (Stufe %d bleibt)" % int(rec["level"])]
	lines.append("Kosten: " + HeroUI.cost_bbcode(k, hs.revive_cost(rec)))
	var reason := hs.can_revive(k, _hero_id)
	if not reason.is_empty():
		lines.append(ResearchTipButton.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _offer_tip(type_id: String) -> String:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var htype := DataDB.get_hero_type(type_id)
	var lines: PackedStringArray = ["[b]%s[/b] anwerben" % ResearchTipButton.esc(str(htype.get("name", type_id)))]
	lines.append("Kosten: " + HeroUI.cost_bbcode(k, hs.recruit_cost(k, type_id)))
	lines.append("Jeder weitere Held kostet mehr. Höchstens %d Helden." % hs.max_heroes(k))
	var reason := recruit_reason(type_id)
	if not reason.is_empty():
		lines.append(ResearchTipButton.colored(reason, COLOR_BAD))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Klicks
# ---------------------------------------------------------------------------

func _on_list_pressed(hero_id: int) -> void:
	_hero_id = hero_id
	_confirm_hero = 0
	_refresh()


## Stufenwahl: Option index der aktuellen Wahl
func choose_option(index: int) -> bool:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var options := hs.get_levelup_options(k, _hero_id)
	if index < 0 or index >= options.size():
		return false
	var o: Dictionary = options[index]
	if not hs.choose_upgrade(k, _hero_id, str(o["id"])):
		return false
	Notify.good("%s: %s" % [str(hs.get_record(k, _hero_id).get("name", "")), str(o["name"])])
	_refresh()
	return true


func _on_option_pressed(index: int) -> void:
	choose_option(index)


func _on_ability_pressed(ability_id: String) -> void:
	var u := HeroUI.hero_unit(game, _hero_id)
	if u == null:
		Notify.warning("Der Held lebt nicht")
		return
	if HeroUI.is_passive(ability_id):
		Notify.info("%s wirkt von selbst (passiv)" % str(DataDB.get_ability(ability_id).get("name", "")))
		return
	# Mit Ziel: Fenster schliessen, damit die Welt anklickbar ist
	if game.spell_targeting.start_ability(u, ability_id) and game.spell_targeting.is_active():
		close()
	_refresh()


func _on_autocast_requested(ability_id: String) -> void:
	var u := HeroUI.hero_unit(game, _hero_id)
	if u == null:
		return
	HeroSelectionBox.toggle_autocast(game, u, ability_id)
	_refresh()


func _on_train_pressed() -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	if hs.train(k, _hero_id):
		Notify.good("Ausbildung: %s erhält Erfahrung" % str(hs.get_record(k, _hero_id).get("name", "")))
	else:
		Notify.warning(hs.can_train(k, _hero_id))
	_refresh()


func _on_revive_pressed() -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	if not hs.revive(k, _hero_id):
		Notify.warning(hs.can_revive(k, _hero_id))
	_refresh()


func _on_jump_pressed() -> void:
	var k: Kingdom = game.player
	var u := HeroUI.hero_unit(game, _hero_id)
	if u != null:
		game.selection.select([u])
		game.camera.focus_on(u.position)
	elif is_instance_valid(k.castle):
		game.selection.select([k.castle])
		game.camera.focus_on(k.castle.get_center())
	close()


## Entlassen: erster Klick fragt nach, zweiter (innerhalb von 3 s) entlässt
func _on_dismiss_pressed() -> void:
	if _confirm_hero == _hero_id and Time.get_ticks_msec() - _confirm_ms <= CONFIRM_MS:
		_confirm_hero = 0
		game.hero_system.dismiss(game.player, _hero_id)
	else:
		_confirm_hero = _hero_id
		_confirm_ms = Time.get_ticks_msec()
	_refresh()


func _on_recruit_pressed(type_id: String) -> void:
	var reason := recruit_reason(type_id)
	if not reason.is_empty() or not game.hero_system.recruit(game.player, type_id):
		if reason.is_empty():
			reason = "Anwerben nicht möglich"
		Notify.warning(reason.get_slice("\n", 0))
	_refresh()


func _on_build_hall_pressed() -> void:
	close()
	game.placement.start(DataDB.get_building("hero_hall"))


## Debug-Knöpfe (F3): "level", "cooldowns", "revive", "kill"
func debug_action(action: String) -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	if _hero_id == 0:
		return
	match action:
		"level":
			hs.debug_level_up(k, _hero_id)
		"cooldowns":
			hs.debug_reset_cooldowns(k, _hero_id)
		"revive":
			hs.debug_revive_now(k, _hero_id)
		"kill":
			hs.debug_kill(k, _hero_id)
	_refresh()


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var bg := Color(0.07, 0.045, 0.1, 0.97) if _evil else Color(0.1, 0.085, 0.065, 0.97)
	var st := _flat(bg, _accent, 2, 8)
	st.content_margin_left = MARGIN_X
	st.content_margin_right = MARGIN_X
	st.content_margin_top = MARGIN_Y
	st.content_margin_bottom = MARGIN_Y
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	if _evil:
		st.border_blend = true
	return st


func _info_style(border: Color) -> StyleBoxFlat:
	var st := _flat(Color(1, 1, 1, 0.03), Color(border, 0.35), 1, 6)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return st


static func _flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_width)
	st.set_corner_radius_all(radius)
	st.anti_aliasing = true
	return st


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _wrap_label(font_size: int, color: Color) -> Label:
	var label := _label(font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _tip_button(text: String) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 36)
	return b


func _plain_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 36)
	return b


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text


func _evil_or(evil_color: Color, good_color: Color) -> Color:
	return evil_color if _evil else good_color
