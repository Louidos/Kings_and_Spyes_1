## UiStyle
##
## Gemeinsame Hilfen der Oberfläche (Phase 10):
## - UI-Grösse (Einstellung "Grösse der Oberfläche"): registrierte Ebenen werden
##   skaliert, ihre Wurzel bekommt die Grösse Viewport / Faktor (Klicks stimmen so).
## - Fenster im gleichen Stil (Titel, Schliessen-Knopf) und Tooltips mit BBCode.
class_name UiStyle
extends RefCounted

const TITLE_FONT_SIZE := 22
const GROUP := "ui_scale"


## Ebene für die UI-Grösse anmelden (root: Control, die die ganze Ebene füllt)
static func register_scaled_layer(layer: CanvasLayer, root: Control) -> void:
	layer.add_to_group(GROUP)
	layer.set_meta("ui_root", root)
	if layer.is_inside_tree():
		_apply_layer(layer, Settings.ui_scale)


## UI-Grösse auf alle angemeldeten Ebenen anwenden (nach Settings.changed und bei Fenstergrösse)
static func apply_ui_scale(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		if node is CanvasLayer:
			_apply_layer(node as CanvasLayer, Settings.ui_scale)


static func _apply_layer(layer: CanvasLayer, s: float) -> void:
	var root: Variant = layer.get_meta("ui_root", null)
	if not (root is Control) or not is_instance_valid(root):
		return
	var c: Control = root
	if is_equal_approx(s, 1.0) and not layer.has_meta("ui_scaled"):
		return  # nie skaliert: nichts anfassen
	layer.set_meta("ui_scaled", true)
	layer.scale = Vector2(s, s)
	var vp := layer.get_viewport().get_visible_rect().size
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = vp / s


## Fenstertitel mit Schliessen-Knopf "✕" rechts (gleicher Stil in allen neuen Fenstern)
static func make_title_bar(title: String, on_close: Callable) -> HBoxContainer:
	var bar := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(label)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Schliessen (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(on_close)
	bar.add_child(close)
	return bar


## Tooltip mit BBCode (für _make_custom_tooltip)
static func make_rich_tooltip(bbcode: String, max_width: float = 420.0) -> Control:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(max_width, 0)
	label.text = bbcode
	return label
