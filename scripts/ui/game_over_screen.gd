## GameOverScreen
##
## Spielende-Bildschirm. Niederlage (open): der König des Spielers ist gefallen oder
## seine Burg zerstört – rote Schrift, Hauptmenü, Neustart oder Beenden.
## Sieg (open_victory, ab Phase 7): alle feindlichen Königreiche sind gefallen –
## goldene Schrift, Statistik und zusätzlich "Weiterspielen" (continue_pressed).
## Das Spiel ist solange pausiert.
class_name GameOverScreen
extends CanvasLayer

## "Weiterspielen" wurde gedrückt (nur beim Sieg sichtbar)
signal continue_pressed

const DEFEAT_TITLE_COLOR := Color(0.95, 0.4, 0.3)
const DEFEAT_DIM := Color(0.08, 0.0, 0.0, 0.7)
const VICTORY_TITLE_COLOR := Color("#f3d36b")
const VICTORY_DIM := Color(0.06, 0.05, 0.0, 0.7)

var _title: Label
var _info: Label
var _dim: ColorRect
var _menu_button: Button
var _continue_button: Button
var _victory := false


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = DEFEAT_DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", DEFEAT_TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	box.add_child(HSeparator.new())
	_continue_button = _make_button("Weiterspielen", box)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	_menu_button = _make_button("Zum Hauptmenü", box)
	_menu_button.pressed.connect(func() -> void:
		GameClock.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	var restart := _make_button("Neu starten (gleiche Karte)", box)
	restart.pressed.connect(func() -> void:
		# GameSession behält Fraktion, Schwierigkeit, Grösse und Seed
		GameClock.stop()
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	var quit := _make_button("Spiel beenden", box)
	quit.pressed.connect(func() -> void: get_tree().quit())


## Niederlage: rote Schrift, ohne "Weiterspielen"
func open(title: String, text: String) -> void:
	_victory = false
	_title.text = title
	_title.add_theme_color_override("font_color", DEFEAT_TITLE_COLOR)
	_dim.color = DEFEAT_DIM
	_info.text = text
	_continue_button.visible = false
	visible = true
	_menu_button.grab_focus()


## Sieg: goldene Schrift, "Weiterspielen" oben und vorgewählt
func open_victory(title: String, text: String) -> void:
	_victory = true
	_title.text = title
	_title.add_theme_color_override("font_color", VICTORY_TITLE_COLOR)
	_dim.color = VICTORY_DIM
	_info.text = text
	_continue_button.visible = true
	visible = true
	_continue_button.grab_focus()


func is_open() -> bool:
	return visible


## Zeigt der Bildschirm einen Sieg?
func is_victory() -> bool:
	return _victory


func _make_button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	parent.add_child(b)
	return b
