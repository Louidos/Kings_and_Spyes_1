## RefugeeDialog
##
## Kleiner Dialog für Flüchtlinge und Wanderer (Phase 8), oben mittig über den
## Fenstern: Titel, Geschichte, Personen mit Wohnraum vorher/nachher, Nahrungsbedarf,
## Geschenke, Warnung vor Spionen und Restzeit. Knöpfe "Aufnehmen", "Abweisen",
## "Später" und "Hinspringen". Schliesst sich selbst, wenn das Angebot verschwindet.
## Ruft nur EventSystem.accept_offer/reject_offer mit dem Spieler-Reich auf.
class_name RefugeeDialog
extends PanelContainer

const WIDTH := 460.0
const TOP := 120.0
const REFRESH_INTERVAL := 0.25

var game: Node
var _offer_id := 0
var _timer := 0.0
var _title: Label
var _story: Label
var _text: RichTextLabel
var _accept: Button
var _reject: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func setup(p_game: Node) -> void:
	game = p_game
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.085, 0.065, 0.97)
	st.border_color = Color(0.85, 0.78, 0.55)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 12
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(WIDTH, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	vbox.add_child(_title)
	_story = Label.new()
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.add_theme_font_size_override("font_size", 16)
	_story.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	vbox.add_child(_story)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	_accept = _button(row, "Aufnehmen", "Die Gruppe wird Teil deines Reichs (Bewohner)")
	_accept.add_theme_color_override("font_color", Color(0.55, 0.88, 0.5))
	_accept.pressed.connect(_on_accept_pressed)
	_reject = _button(row, "Abweisen", "Die Gruppe zieht weiter – zu einem Dorf, einem anderen Reich oder aus dem Land")
	_reject.pressed.connect(_on_reject_pressed)
	var later := _button(row, "Später", "Dialog schliessen – die Gruppe wartet noch (Ereignisleiste oben)")
	later.pressed.connect(close)
	var jump := _button(row, "Hinspringen", "Kamera zur Gruppe")
	jump.pressed.connect(_on_jump_pressed)
	get_viewport().size_changed.connect(_place)


func _button(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


func is_open() -> bool:
	return visible


func get_offer_id() -> int:
	return _offer_id


func open(offer_id: int) -> void:
	var offer: Dictionary = game.event_system.get_offer(offer_id)
	if offer.is_empty() or int(offer["target_id"]) != game.player.id:
		Notify.info("Die Gruppe ist nicht mehr da.")
		return
	_offer_id = offer_id
	visible = true
	set_process(true)
	_refresh()
	_place.call_deferred()


func close() -> void:
	visible = false
	set_process(false)
	_offer_id = 0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var es: EventSystem = game.event_system
	var offer := es.get_offer(_offer_id)
	if offer.is_empty() or str(offer["state"]) == "leaving" or int(offer["target_id"]) != game.player.id:
		close()
		return
	var def := DataDB.get_event(str(offer["event_id"]))
	var title := "%s bitten um Aufnahme" % str(def.get("name", "Fremde"))
	if _title.text != title:
		_title.text = title
	var story := str(offer.get("story", ""))
	if _story.text != story:
		_story.text = story
	_story.visible = not story.is_empty()
	var lines: PackedStringArray = []
	for line in es.get_offer_text(offer, game.player).split("\n"):
		if line.begins_with("Unter Fremden"):
			lines.append(ResearchTipButton.colored(line, Color(0.6, 0.58, 0.55)))
		elif line.contains("überfüllt"):
			lines.append(ResearchTipButton.colored(line, Color(1.0, 0.62, 0.22)))
		else:
			lines.append(ResearchTipButton.esc(line))
	var text := "\n".join(lines)
	if _text.text != text:
		_text.text = text


func _place() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	size = Vector2(WIDTH, get_combined_minimum_size().y)
	position = Vector2(floorf((vp.x - WIDTH) * 0.5), TOP)


## Aufnehmen (auch Rauchtest)
func _on_accept_pressed() -> void:
	var reason: String = game.event_system.accept_offer(game.player, _offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	close()


## Abweisen (auch Rauchtest)
func _on_reject_pressed() -> void:
	var reason: String = game.event_system.reject_offer(game.player, _offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	close()


func _on_jump_pressed() -> void:
	var es: EventSystem = game.event_system
	var offer := es.get_offer(_offer_id)
	if offer.is_empty():
		return
	for uid in offer["uids"]:
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit:
			game.camera.focus_on((u as Unit).position)
			return
