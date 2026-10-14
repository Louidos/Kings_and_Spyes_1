## PauseMenu
##
## Spielmenü (Esc): Fortsetzen, Speichern, Laden, Einstellungen, Hilfe, zurück zum
## Hauptmenü, Beenden. Speichern, Laden und Einstellungen sind Unterseiten im selben
## Fenster (Esc führt zurück zur Hauptseite). Vor dem Verlassen mit ungespeichertem
## Fortschritt fragt das Menü nach ("Speichern und beenden" schnellspeichert vorher).
extends CanvasLayer

signal closed

@onready var info_label: Label = %InfoLabel
@onready var resume_button: Button = %ResumeButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var settings_button: Button = %SettingsButton
@onready var help_button: Button = %HelpButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var quit_button: Button = %QuitButton
@onready var _main_box: VBoxContainer = $Root/Center/Panel/VBox
@onready var _panel: PanelContainer = $Root/Center/Panel

var is_open: bool = false
var game: Node = null

var _save_panel: SaveLoadPanel
var _load_panel: SaveLoadPanel
var _settings_form: SettingsForm
var _confirm: ConfirmationDialog
## Nach der Rückfrage: "menu" oder "quit"
var _leave_action := ""


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(close)
	save_button.pressed.connect(_show_page.bind("save"))
	load_button.pressed.connect(_show_page.bind("load"))
	settings_button.pressed.connect(_show_page.bind("settings"))
	help_button.pressed.connect(_on_help)
	main_menu_button.pressed.connect(_ask_leave.bind("menu"))
	quit_button.pressed.connect(_ask_leave.bind("quit"))
	_save_panel = SaveLoadPanel.new()
	_save_panel.closed.connect(_show_page.bind("main"))
	_panel.add_child(_save_panel)
	_load_panel = SaveLoadPanel.new()
	_load_panel.closed.connect(_show_page.bind("main"))
	_load_panel.load_requested.connect(_on_load_requested)
	_panel.add_child(_load_panel)
	_settings_form = SettingsForm.new()
	_settings_form.closed.connect(_show_page.bind("main"))
	_panel.add_child(_settings_form)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Rückfrage"
	_confirm.cancel_button_text = "Abbrechen"
	_confirm.ok_button_text = "Ohne Speichern"
	_confirm.add_button("Speichern und beenden", true, "save_quit")
	_confirm.confirmed.connect(func() -> void: _leave(false))
	_confirm.custom_action.connect(func(_a: StringName) -> void:
		_confirm.hide()
		_leave(true))
	add_child(_confirm)
	UiStyle.register_scaled_layer(self, $Root as Control)
	_show_page("main")


func open(p_game: Node = null) -> void:
	if p_game != null:
		game = p_game
	is_open = true
	visible = true
	_show_page("main")
	_refresh_info()
	resume_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()


## "main", "save", "load" oder "settings"
func _show_page(page: String) -> void:
	_main_box.visible = page == "main"
	_save_panel.visible = page == "save"
	_load_panel.visible = page == "load"
	_settings_form.visible = page == "settings"
	_save_panel.game = game
	_load_panel.game = game
	match page:
		"save":
			_save_panel.open_mode("save")
		"load":
			_load_panel.open_mode("load")
		"settings":
			_settings_form.refresh()
		_:
			_refresh_info()


## Aktuelle Unterseite (Rauchtest)
func get_page() -> String:
	if _save_panel.visible:
		return "save"
	if _load_panel.visible:
		return "load"
	if _settings_form.visible:
		return "settings"
	return "main"


func get_save_panel() -> SaveLoadPanel:
	return _save_panel


func get_load_panel() -> SaveLoadPanel:
	return _load_panel


func get_settings_form() -> SettingsForm:
	return _settings_form


func show_page(page: String) -> void:
	_show_page(page)


func _refresh_info() -> void:
	if info_label == null:
		return
	var faction := GameSession.get_faction()
	var map_size := DataDB.get_map_size(GameSession.map_size_id)
	var who := str(faction.get("name", "?"))
	if not GameSession.people_id.is_empty():
		who += " · " + DataDB.get_people_name(GameSession.people_id)
	var saved := "noch nicht gespeichert"
	if game != null and game.has_method("seconds_since_save"):
		var since := float(game.seconds_since_save())
		if not GameSession.last_save_name.is_empty() or since < GameClock.game_time:
			saved = "Zuletzt gespeichert: vor %d min (Spielzeit)" % int(since / 60.0)
	info_label.text = "Fraktion: %s\nSchwierigkeit: %s\n%s\nKarte: %s · Seed: %s\n%s\n%s" % [
		who, str(GameSession.get_difficulty().get("name", "?")), Difficulty.short_text(GameSession.difficulty_id),
		map_size.get("name", "?"), GameSession.seed_text, GameClock.get_time_string(), saved]
	var reason: String = game.can_save() if game != null else "Kein Spiel"
	save_button.disabled = not reason.is_empty()
	save_button.tooltip_text = "Partie unter einem Namen speichern" if reason.is_empty() else reason


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("game_menu"):
		get_viewport().set_input_as_handled()
		if get_page() != "main":
			if get_page() == "settings":
				Settings.save_settings()
			_show_page("main")
		else:
			close()


func _on_help() -> void:
	if game != null and game.hud != null and game.hud.has_method("open_help"):
		game.hud.call("open_help")


func _on_load_requested(slot: String) -> void:
	var err := SaveManager.request_load(slot)
	if not err.is_empty():
		Notify.danger("Laden nicht möglich: " + err)
		return
	is_open = false
	visible = false
	if game != null and game.has_method("request_reload"):
		game.call("request_reload")
	else:
		get_tree().change_scene_to_file("res://scenes/game.tscn")


## Verlassen mit Rückfrage, wenn seit dem Speichern mehr als eine Minute Spielzeit vergangen ist
func _ask_leave(action: String) -> void:
	_leave_action = action
	var since := float(game.seconds_since_save()) if game != null and game.has_method("seconds_since_save") else 0.0
	if since <= float(DataDB.cfg("save.unsaved_warning_seconds", 60)) or game == null or not str(game.can_save()).is_empty():
		_leave(false)
		return
	_confirm.dialog_text = "Ungespeicherter Fortschritt (%d min) geht verloren." % maxi(int(since / 60.0), 1)
	_confirm.popup_centered()


func _leave(save_first: bool) -> void:
	if save_first and game != null:
		game.call("quick_save", false)
	GameClock.stop()
	if _leave_action == "quit":
		get_tree().quit()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
