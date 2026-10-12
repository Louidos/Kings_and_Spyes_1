## MainMenu
##
## Hauptmenü: Neues Spiel (Fraktion, Schwierigkeit, Kartengrösse, Seed),
## Laden (ab Phase 10), Einstellungen, Beenden.
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


func _ready() -> void:
	GameClock.stop()
	_load_background()
	_build_faction_buttons()
	_fill_options()
	seed_edit.text = GameSession.random_seed_text()

	%NewGameButton.pressed.connect(_show.bind(new_game_panel))
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%BackButton.pressed.connect(_show.bind(main_buttons))
	%SettingsBackButton.pressed.connect(_close_settings)
	%RandomSeedButton.pressed.connect(func() -> void: seed_edit.text = GameSession.random_seed_text())
	%StartButton.pressed.connect(_start_game)

	var v := Engine.get_version_info()
	version_label.text = "Phase 2  ·  Godot %d.%d.%d" % [v.major, v.minor, v.patch]
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
		seed_edit.text)
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------------------
# Einstellungen
# ---------------------------------------------------------------------------

func _open_settings() -> void:
	edge_scroll_check.button_pressed = Settings.edge_scroll
	camera_speed_slider.value = Settings.camera_speed
	fullscreen_check.button_pressed = Settings.fullscreen
	_show(settings_panel)


func _close_settings() -> void:
	Settings.edge_scroll = edge_scroll_check.button_pressed
	Settings.camera_speed = camera_speed_slider.value
	Settings.fullscreen = fullscreen_check.button_pressed
	Settings.save_settings()
	Settings.apply()
	_show(main_buttons)
