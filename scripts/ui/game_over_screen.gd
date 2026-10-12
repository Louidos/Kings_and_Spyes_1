## GameOverScreen
##
## Wird gezeigt, wenn der König des Spielers fällt. Das Spiel ist pausiert;
## man kann zum Hauptmenü zurück oder beenden. (Siegbedingungen: Phase 7)
class_name GameOverScreen
extends CanvasLayer

var _title: Label
var _info: Label
var _menu_button: Button


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.0, 0.0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
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
	_title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	box.add_child(HSeparator.new())
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


func open(title: String, text: String) -> void:
	_title.text = title
	_info.text = text
	visible = true
	_menu_button.grab_focus()


func is_open() -> bool:
	return visible


func _make_button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	parent.add_child(b)
	return b
