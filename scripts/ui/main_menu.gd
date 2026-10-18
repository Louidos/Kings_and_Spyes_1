## MainMenu
##
## Hauptmenü: Fortsetzen (neuester Spielstand), Neues Spiel (Fraktion, Volk mit Stärken und
## Schwächen, Schwierigkeit, Kartengrösse, Seed, "Tipps/Tutorial anzeigen"), Tutorial (geführte
## Partie mit festem Seed aus tutorial.json), Laden (Liste der Spielstände), Einstellungen, Beenden.
## Fraktionen, Schwierigkeitsgrade und Kartengrössen kommen aus /data.
extends Control

const GAME_SCENE := "res://scenes/game.tscn"
## Optionales Hintergrundbild; fehlt es, bleibt der Farbverlauf
const BACKGROUND_IMAGE := "res://assets/ui/menu_background.png"

@onready var background_image: TextureRect = %BackgroundImage
@onready var main_buttons: Control = %MainButtons
@onready var new_game_panel: Control = %NewGamePanel
@onready var settings_panel: Control = %SettingsPanel
@onready var faction_buttons: HBoxContainer = %FactionButtons
@onready var faction_description: Label = %FactionDescription
@onready var difficulty_option: OptionButton = %DifficultyOption
@onready var map_size_option: OptionButton = %MapSizeOption
@onready var seed_edit: LineEdit = %SeedEdit
@onready var version_label: Label = %VersionLabel

var _selected_faction: String = "good"
## Volkswahl (Phase 8): Liste, Beschreibung, gewähltes Volk
var _people_option: OptionButton
var _people_text: RichTextLabel
var _selected_people := ""
## Seite "Laden" (Liste der Spielstände) und Formular der Einstellungen
var load_panel: SaveLoadPanel
var settings_form: SettingsForm
var _continue_button: Button
var _error_label: Label
var _difficulty_hint: Label
## Knopf "Tutorial" und Haken "Tipps/Tutorial anzeigen" im Dialog "Neues Spiel"
var _tutorial_button: Button
var _tutorial_check: CheckBox
## Optionen des neuen Spiels (game_config.json → new_game): Schlüssel -> OptionButton
var _game_options := {}
## Rollbereich um den Inhalt der Menütafel (passt sich der Bildschirmhöhe an)
var _scroll: ScrollContainer
## Beschriftung und Tooltip je Option
const GAME_OPTION_TEXTS := {
	"ai_kingdoms": ["Gegnerreiche", "Wie viele gegnerische Königreiche es gibt (Standard: nach Schwierigkeit und Kartengrösse; höchstens so viele, wie die Karte Plätze hat)"],
	"villages": ["Neutrale Dörfer", "Wie viele neutrale Dörfer auf der Karte liegen (Standard: klein 6, mittel 10, gross 16)"],
	"resources": ["Startvorräte", "Holz, Stein, Nahrung und Mana zu Beginn – für dich und die Gegner"],
	"monsters": ["Monster", "Monsterlager auf der Karte (aus: keine Monster, keine Streifzüge, keine Monsterwellen)"],
	"events": ["Zufallsereignisse", "Dürre, Seuche, Magiesturm, Monsterwellen, Flüchtlinge, Erntedank …"],
}


func _ready() -> void:
	GameClock.stop()
	_load_background()
	_build_people_picker()
	_build_faction_buttons()
	_fill_options()
	seed_edit.text = GameSession.random_seed_text()

	%NewGameButton.pressed.connect(_show.bind(new_game_panel))
	%LoadButton.pressed.connect(_open_load)
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%BackButton.pressed.connect(_show.bind(main_buttons))
	%RandomSeedButton.pressed.connect(func() -> void: seed_edit.text = GameSession.random_seed_text())
	%StartButton.pressed.connect(_start_game)
	%NewGameButton.tooltip_text = "Neue Partie: Fraktion, Volk, Schwierigkeit, Karte, Seed und weitere Optionen"
	%SettingsButton.tooltip_text = "Grafik, Ton, Steuerung, Oberfläche, Spiel"
	%QuitButton.tooltip_text = "Spiel schliessen"
	%RandomSeedButton.tooltip_text = "Zufälligen Seed würfeln"
	%StartButton.tooltip_text = "Partie mit diesen Einstellungen starten"
	%BackButton.tooltip_text = "Zurück zum Hauptmenü"
	difficulty_option.tooltip_text = Difficulty.describe(GameSession.difficulty_id)
	map_size_option.tooltip_text = "Grösse der Welt"

	# Fortsetzen (neuester ladbarer Spielstand) über "Neues Spiel"
	_continue_button = Button.new()
	_continue_button.text = "Fortsetzen"
	_continue_button.custom_minimum_size = Vector2(0, 46)
	_continue_button.add_theme_font_size_override("font_size", 22)
	_continue_button.pressed.connect(_continue_game)
	main_buttons.add_child(_continue_button)
	main_buttons.move_child(_continue_button, 0)
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.custom_minimum_size.x = 420
	_error_label.visible = false
	main_buttons.add_child(_error_label)
	main_buttons.move_child(_error_label, 0)
	if not GameSession.last_error.is_empty():
		_error_label.text = GameSession.last_error
		_error_label.visible = true
		GameSession.last_error = ""
	# Kurztext zur Schwierigkeit unter der Auswahl
	_difficulty_hint = Label.new()
	_difficulty_hint.add_theme_font_size_override("font_size", 14)
	_difficulty_hint.add_theme_color_override("font_color", Color(0.8, 0.77, 0.7))
	var grid := difficulty_option.get_parent()
	var spacer := Control.new()
	grid.add_child(spacer)
	grid.move_child(spacer, difficulty_option.get_index() + 1)
	grid.add_child(_difficulty_hint)
	grid.move_child(_difficulty_hint, spacer.get_index() + 1)
	difficulty_option.item_selected.connect(func(_i: int) -> void: _update_difficulty_hint())
	_update_difficulty_hint()
	_build_tutorial_controls()
	_build_game_options()
	# Seiten: Laden und Einstellungen
	load_panel = SaveLoadPanel.new()
	load_panel.visible = false
	load_panel.closed.connect(_show.bind(main_buttons))
	load_panel.load_requested.connect(_on_load_requested)
	main_buttons.get_parent().add_child(load_panel)
	main_buttons.get_parent().move_child(load_panel, settings_panel.get_index())
	settings_form = SettingsForm.new()
	settings_form.closed.connect(_close_settings)
	settings_panel.add_child(settings_form)
	_wrap_in_scroll()
	Settings.changed.connect(_apply_ui_scale)
	_apply_ui_scale()

	version_label.text = "Version %s  ·  Godot %d.%d.%d" % [str(ProjectSettings.get_setting("application/config/version", "1.0.0")),
			Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch]
	_refresh_continue()
	_show(main_buttons)


func _exit_tree() -> void:
	# Im Spiel skalieren die Ebenen selbst (UiStyle); der Faktor des Fensters gilt nur hier
	if is_inside_tree():
		get_tree().root.content_scale_factor = 1.0


func _apply_ui_scale() -> void:
	if is_inside_tree():
		get_tree().root.content_scale_factor = Settings.ui_scale
		_fit_panel.call_deferred()


## Inhalt der Menütafel in einen Rollbereich: Der Dialog „Neues Spiel“ ist bei grosser Oberfläche
## höher als der Bildschirm – dann lässt er sich rollen, statt oben und unten abgeschnitten zu werden
func _wrap_in_scroll() -> void:
	var vbox := $Center/Panel/VBox as Control
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	$Center/Panel.add_child(_scroll)
	vbox.reparent(_scroll, false)
	vbox.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_fit_panel, CONNECT_DEFERRED)


## Höhe des Rollbereichs: so hoch wie der Inhalt, höchstens der Bildschirm (mit Rand)
func _fit_panel() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var vbox := _scroll.get_child(0) as Control
	var need := vbox.get_combined_minimum_size()
	var avail := get_viewport().get_visible_rect().size.y - 60.0
	var h := minf(need.y, maxf(avail, 200.0))
	# Mit Rollbalken etwas breiter, damit er nichts verdeckt
	var bar := _scroll.get_v_scroll_bar().get_combined_minimum_size().x + 6.0 if h < need.y else 0.0
	_scroll.custom_minimum_size = Vector2(need.x + bar, h)


func _show(panel: Control) -> void:
	for p in [main_buttons, new_game_panel, settings_panel, load_panel]:
		if p != null:
			p.visible = p == panel
	if _scroll != null:
		_scroll.scroll_vertical = 0
	_fit_panel.call_deferred()
	if panel == main_buttons:
		_refresh_continue()


func _update_difficulty_hint() -> void:
	var id := str(difficulty_option.get_selected_metadata())
	_difficulty_hint.text = Difficulty.short_text(id)
	difficulty_option.tooltip_text = Difficulty.describe(id)
	_difficulty_hint.tooltip_text = Difficulty.describe(id)


## "Fortsetzen" nur, wenn es einen ladbaren Spielstand gibt
func _refresh_continue() -> void:
	if _continue_button == null:
		return
	var entry := SaveManager.most_recent()
	_continue_button.visible = not entry.is_empty()
	if not entry.is_empty():
		var h: Dictionary = entry["header"]
		_continue_button.tooltip_text = "%s – gespeichert %s" % [str(h.get("name", "")), SaveGame.format_date(int(h.get("saved_at", 0)))]


func _continue_game() -> void:
	var entry := SaveManager.most_recent()
	if not entry.is_empty():
		_on_load_requested(str(entry["slot"]))


func _open_load() -> void:
	_show(load_panel)
	load_panel.open_mode("load")


func _on_load_requested(slot: String) -> void:
	var err := SaveManager.request_load(slot)
	if not err.is_empty():
		_error_label.text = "Laden nicht möglich: " + err
		_error_label.visible = true
		_show(main_buttons)
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _load_background() -> void:
	var img := PlaceholderArt.load_image(BACKGROUND_IMAGE)
	if img != null:
		background_image.texture = ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Neues Spiel
# ---------------------------------------------------------------------------

func _build_faction_buttons() -> void:
	for child in faction_buttons.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	for f in DataDB.factions:
		if not f.get("playable", false):
			continue
		var b := Button.new()
		b.text = f.get("name", "?")
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(150, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", f["color"])
		b.add_theme_color_override("font_hover_color", f["color"].lightened(0.3))
		b.pressed.connect(_select_faction.bind(f["id"]))
		faction_buttons.add_child(b)
		if f["id"] == GameSession.faction_id:
			b.button_pressed = true
	_select_faction(GameSession.faction_id)


func _select_faction(id: String) -> void:
	_selected_faction = id
	if _tutorial_button != null:
		_tutorial_button.tooltip_text = _tutorial_tooltip()
	var f := DataDB.get_faction(id)
	var names: Array = DataDB.get_peoples_of_faction(id).map(func(p): return p["name"])
	faction_description.text = "%s\nVölker: %s" % [f.get("description", ""), ", ".join(names)]
	_fill_people(id)


## Zeile "Dein Volk:" mit Liste und darunter Beschreibung, Gelände, Stärken (grün)
## und Schwächen (rot) – direkt unter der Fraktionsbeschreibung
func _build_people_picker() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Dein Volk:"
	row.add_child(label)
	_people_option = OptionButton.new()
	_people_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_people_option.item_selected.connect(_on_people_selected)
	row.add_child(_people_option)
	_people_text = RichTextLabel.new()
	_people_text.bbcode_enabled = true
	_people_text.fit_content = true
	_people_text.scroll_active = false
	_people_text.custom_minimum_size = Vector2(0, 120)
	_people_text.add_theme_font_size_override("normal_font_size", 16)
	var parent := faction_description.get_parent()
	parent.add_child(row)
	parent.move_child(row, faction_description.get_index() + 1)
	parent.add_child(_people_text)
	parent.move_child(_people_text, row.get_index() + 1)


## Völker der Fraktion in die Liste; das bisherige Volk bleibt gewählt, sonst das erste
func _fill_people(faction_id: String) -> void:
	if _people_option == null:
		return
	var list := DataDB.get_peoples_of_faction(faction_id)
	_people_option.clear()
	var select := 0
	for i in list.size():
		var p: Dictionary = list[i]
		_people_option.add_item(str(p.get("name", "?")))
		_people_option.set_item_metadata(i, str(p["id"]))
		if str(p["id"]) == _selected_people or (_selected_people.is_empty() and str(p["id"]) == GameSession.people_id):
			select = i
	if list.is_empty():
		_selected_people = ""
		_people_text.text = ""
		return
	_people_option.select(select)
	_on_people_selected(select)


func _on_people_selected(index: int) -> void:
	_selected_people = str(_people_option.get_item_metadata(index))
	_people_text.text = people_text(DataDB.get_people(_selected_people))


## Beschreibung eines Volks als BBCode: Text, bevorzugtes Gelände, Stärken, Schwächen
static func people_text(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	var lines: PackedStringArray = [ResearchTipButton.esc(str(p.get("description", "")))]
	var biome_names: PackedStringArray = []
	for biome_id in p.get("preferred_biomes", []):
		var index := int(DataDB.biome_index_by_id.get(str(biome_id), -1))
		biome_names.append(str(DataDB.get_biome(index).get("name", biome_id)) if index >= 0 else str(biome_id))
	if not biome_names.is_empty():
		lines.append("Gelände: " + ", ".join(biome_names))
	for s in p.get("strengths", []):
		lines.append(ResearchTipButton.colored("+ " + str(s), Color(0.55, 0.88, 0.5)))
	for s in p.get("weaknesses", []):
		lines.append(ResearchTipButton.colored("− " + str(s), Color(1.0, 0.5, 0.42)))
	return "\n".join(lines)


func _fill_options() -> void:
	difficulty_option.clear()
	for d in DataDB.difficulties:
		difficulty_option.add_item(d.get("name", "?"))
		difficulty_option.set_item_metadata(difficulty_option.item_count - 1, d["id"])
		if d["id"] == GameSession.difficulty_id:
			difficulty_option.select(difficulty_option.item_count - 1)
	map_size_option.clear()
	for s in DataDB.cfg("map.sizes", []):
		map_size_option.add_item(s.get("name", "?"))
		map_size_option.set_item_metadata(map_size_option.item_count - 1, s["id"])
		if s["id"] == GameSession.map_size_id:
			map_size_option.select(map_size_option.item_count - 1)


func _start_game() -> void:
	GameSession.setup_new_game(
		_selected_faction,
		str(difficulty_option.get_selected_metadata()),
		str(map_size_option.get_selected_metadata()),
		seed_edit.text,
		_selected_people,
		get_game_options())
	GameSession.start_tutorial = _tutorial_check != null and _tutorial_check.button_pressed
	get_tree().change_scene_to_file(GAME_SCENE)


## Gewählte Optionen des neuen Spiels: Schlüssel -> id (nur von "standard" abweichende)
func get_game_options() -> Dictionary:
	var result := {}
	for key in _game_options:
		var id := str((_game_options[key] as OptionButton).get_selected_metadata())
		if id != "standard":
			result[key] = id
	return result


## Weitere Optionen unter Schwierigkeit und Kartengrösse, je mit "Standard" (= bisheriges Verhalten),
## in zwei Spalten, damit der Dialog auch bei grosser Oberfläche auf den Bildschirm passt
func _build_game_options() -> void:
	var main_grid := difficulty_option.get_parent() as GridContainer
	var grid := GridContainer.new()
	grid.name = "OptionsGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	new_game_panel.add_child(grid)
	new_game_panel.move_child(grid, main_grid.get_index() + 1)
	for key in GameSession.OPTION_KEYS:
		var texts: Array = GAME_OPTION_TEXTS.get(key, [key, ""])
		var label := Label.new()
		label.text = str(texts[0])
		label.tooltip_text = str(texts[1])
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(label)
		var option := OptionButton.new()
		option.name = "Option_" + str(key)
		option.tooltip_text = str(texts[1])
		option.focus_mode = Control.FOCUS_NONE
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for e in DataDB.cfg("new_game." + str(key), []):
			option.add_item(str((e as Dictionary).get("name", "?")))
			option.set_item_metadata(option.item_count - 1, str((e as Dictionary).get("id", "")))
			if str((e as Dictionary).get("id", "")) == "standard":
				option.select(option.item_count - 1)
		grid.add_child(option)
		_game_options[key] = option


## Rauchtest: Option setzen (id aus game_config.json → new_game)
func set_game_option(key: String, id: String) -> void:
	var option: OptionButton = _game_options.get(key)
	if option == null:
		return
	for i in option.item_count:
		if str(option.get_item_metadata(i)) == id:
			option.select(i)


# ---------------------------------------------------------------------------
# Tutorial
# ---------------------------------------------------------------------------

## Knopf "Tutorial" unter "Neues Spiel" und Haken im Dialog "Neues Spiel"
func _build_tutorial_controls() -> void:
	_tutorial_button = Button.new()
	_tutorial_button.name = "TutorialButton"
	_tutorial_button.text = "Tutorial"
	_tutorial_button.custom_minimum_size = Vector2(0, 46)
	_tutorial_button.add_theme_font_size_override("font_size", 22)
	_tutorial_button.tooltip_text = _tutorial_tooltip()
	_tutorial_button.pressed.connect(_start_tutorial)
	main_buttons.add_child(_tutorial_button)
	main_buttons.move_child(_tutorial_button, (%NewGameButton as Control).get_index() + 1)
	_tutorial_check = CheckBox.new()
	_tutorial_check.name = "TutorialCheck"
	_tutorial_check.text = "Tipps/Tutorial anzeigen"
	_tutorial_check.tooltip_text = "Die Partie beginnt mit dem Tutorial (Schritt für Schritt; Gegner und Ereignisse verschonen dich, solange es läuft)"
	_tutorial_check.focus_mode = Control.FOCUS_NONE
	var grid := difficulty_option.get_parent()
	var label := Label.new()
	label.text = "Tutorial"
	grid.add_child(label)
	grid.add_child(_tutorial_check)


func _tutorial_tooltip() -> String:
	var faction := str(DataDB.get_faction(_selected_faction).get("name", _selected_faction))
	var diff := str(DataDB.get_difficulty(str(DataDB.tut("game.difficulty", "easy"))).get("name", ""))
	var map_size := str(DataDB.get_map_size(str(DataDB.tut("game.map_size", "small"))).get("name", ""))
	return "Geführte Partie zum Lernen: Seed „%s“, %s, Karte %s.\nFraktion: %s (unter „Neues Spiel“ wählbar).\nGegner und Ereignisse verschonen dich, solange das Tutorial läuft." % [
			str(DataDB.tut("game.seed", "")), diff, map_size, faction]


## Knopf "Tutorial": feste Partie aus tutorial.json mit der gewählten Fraktion
func _start_tutorial() -> void:
	GameSession.setup_tutorial_game(_selected_faction, _selected_people)
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------------------
# Einstellungen
# ---------------------------------------------------------------------------

func _open_settings() -> void:
	settings_form.refresh()
	_show(settings_panel)


## Das Formular hat schon gespeichert
func _close_settings() -> void:
	_show(main_buttons)
