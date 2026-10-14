## MainMenu
##
## Hauptmenü: Neues Spiel (Fraktion, Volk mit Stärken und Schwächen, Schwierigkeit,
## Kartengrösse, Seed), Laden (ab Phase 10), Einstellungen, Beenden.
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
@onready var edge_scroll_check: CheckBox = %EdgeScrollCheck
@onready var camera_speed_slider: HSlider = %CameraSpeedSlider
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var version_label: Label = %VersionLabel

var _selected_faction: String = "good"
## Volkswahl (Phase 8): Liste, Beschreibung, gewähltes Volk
var _people_option: OptionButton
var _people_text: RichTextLabel
var _selected_people := ""
## Einstellung "Tag-Nacht-Abdunklung" (im Code eingefügt)
var _tint_check: CheckBox


func _ready() -> void:
	GameClock.stop()
	_load_background()
	_build_people_picker()
	_build_faction_buttons()
	_fill_options()
	_build_tint_check()
	seed_edit.text = GameSession.random_seed_text()

	%NewGameButton.pressed.connect(_show.bind(new_game_panel))
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%BackButton.pressed.connect(_show.bind(main_buttons))
	%SettingsBackButton.pressed.connect(_close_settings)
	%RandomSeedButton.pressed.connect(func() -> void: seed_edit.text = GameSession.random_seed_text())
	%StartButton.pressed.connect(_start_game)

	var v := Engine.get_version_info()
	version_label.text = "Phase 8  ·  Godot %d.%d.%d" % [v.major, v.minor, v.patch]
	_show(main_buttons)


func _show(panel: Control) -> void:
	for p in [main_buttons, new_game_panel, settings_panel]:
		p.visible = p == panel


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


## Einstellung "Tag-Nacht-Abdunklung" vor dem Zurück-Knopf
func _build_tint_check() -> void:
	_tint_check = CheckBox.new()
	_tint_check.text = "Tag-Nacht-Abdunklung"
	_tint_check.tooltip_text = "Abends und nachts wird die Welt dunkler (die Oberfläche bleibt hell)"
	var back: Control = %SettingsBackButton
	back.get_parent().add_child(_tint_check)
	back.get_parent().move_child(_tint_check, back.get_index())


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
		_selected_people)
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------------------
# Einstellungen
# ---------------------------------------------------------------------------

func _open_settings() -> void:
	edge_scroll_check.button_pressed = Settings.edge_scroll
	camera_speed_slider.value = Settings.camera_speed
	fullscreen_check.button_pressed = Settings.fullscreen
	_tint_check.button_pressed = Settings.day_night_tint
	_show(settings_panel)


func _close_settings() -> void:
	Settings.edge_scroll = edge_scroll_check.button_pressed
	Settings.camera_speed = camera_speed_slider.value
	Settings.fullscreen = fullscreen_check.button_pressed
	Settings.day_night_tint = _tint_check.button_pressed
	Settings.save_settings()
	Settings.apply()
	_show(main_buttons)
