## RecruitDialog
##
## Bewerberfenster (RecruitSystem), oben mittig in der Ebene der Flüchtlinge: Name, Beruf,
## Wunschberuf (Fachkraft mit Bonus), jede Bedingung mit ✓ oder ✗ und die Restzeit.
## "Aufnehmen" geht nur, wenn alle Bedingungen erfüllt sind; "Abweisen" immer; dazu "Später"
## und "Hinspringen". Öffnet sich über die Meldung oder den Bewerber im Auswahlfenster und
## schliesst sich, wenn der Bewerber weiterzieht. Ruft nur RecruitSystem.accept/reject mit dem
## Spieler-Reich auf (dieselben Funktionen nutzt die KI).
class_name RecruitDialog
extends PanelContainer

const WIDTH := 460.0
const TOP := 120.0
const REFRESH_INTERVAL := 0.25
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_DIM := Color(0.74, 0.71, 0.66)

var game: Node
var _recruit_id := 0
var _timer := 0.0
var _title: Label
var _sub: Label
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
	st.border_color = Color(0.62, 0.78, 0.9)
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
	_title.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	vbox.add_child(_title)
	_sub = Label.new()
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	vbox.add_child(_sub)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	_accept = _button(row, "Aufnehmen", "")
	_accept.add_theme_color_override("font_color", COLOR_GOOD)
	_accept.pressed.connect(_on_accept_pressed)
	_reject = _button(row, "Abweisen", "Der Bewerber zieht weiter")
	_reject.pressed.connect(_on_reject_pressed)
	var later := _button(row, "Später", "Fenster schliessen – der Bewerber wartet noch (Reichsfenster L, Reiter Bewerber)")
	later.pressed.connect(close)
	var jump := _button(row, "Hinspringen", "Kamera zum Bewerber")
	jump.pressed.connect(_on_jump_pressed)
	get_viewport().size_changed.connect(_place)
	Settings.changed.connect(_place)


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


func get_recruit_id() -> int:
	return _recruit_id


func open(recruit_id: int) -> void:
	var rec: Dictionary = game.recruit_system.get_recruit(recruit_id)
	if rec.is_empty() or int(rec["target_id"]) != game.player.id or str(rec["state"]) == "leaving":
		Notify.info("Der Bewerber ist nicht mehr da.")
		return
	_recruit_id = recruit_id
	visible = true
	set_process(true)
	_refresh()
	_place.call_deferred()


func close() -> void:
	visible = false
	set_process(false)
	_recruit_id = 0


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var rs: RecruitSystem = game.recruit_system
	var rec := rs.get_recruit(_recruit_id)
	if rec.is_empty() or str(rec["state"]) == "leaving" or int(rec["target_id"]) != game.player.id:
		close()
		return
	var title := "Bewerber: " + rs.describe(rec)
	if _title.text != title:
		_title.text = title
	var sub := rs.job_text(rec)
	if _sub.text != sub:
		_sub.text = sub
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Bedingungen[/b]"]
	for res in Requirements.check_all(rec["reqs"], game.player, game):
		lines.append(tip.colored(("✓ " if bool(res["ok"]) else "✗ ") + str(res["text"]), COLOR_GOOD if bool(res["ok"]) else COLOR_BAD))
	if str(rec["state"]) == "waiting":
		lines.append(tip.colored("Wartet noch %d s, dann zieht er weiter." % ceili(maxf(float(rec["expires"]) - GameClock.game_time, 0.0)), COLOR_DIM))
	else:
		lines.append(tip.colored("Ist noch unterwegs zum Rand deines Gebiets.", COLOR_DIM))
	var text := "\n".join(lines)
	if _text.text != text:
		_text.text = text
	var reason := rs.can_accept(game.player, _recruit_id)
	_accept.disabled = not reason.is_empty()
	_accept.tooltip_text = "Wird dein Bewohner im Wunschberuf (Geschenke werden bezahlt)" if reason.is_empty() \
			else "Noch nicht möglich – %s" % reason


func _place() -> void:
	if not visible:
		return
	UiStyle.place_window(self, WIDTH, TOP)


## Aufnehmen (auch Rauchtest)
func _on_accept_pressed() -> void:
	var reason: String = game.recruit_system.accept(game.player, _recruit_id)
	if not reason.is_empty():
		Notify.warning(reason)
		return
	close()


## Abweisen (auch Rauchtest)
func _on_reject_pressed() -> void:
	var reason: String = game.recruit_system.reject(game.player, _recruit_id)
	if not reason.is_empty():
		Notify.warning(reason)
	close()


func _on_jump_pressed() -> void:
	var rec: Dictionary = game.recruit_system.get_recruit(_recruit_id)
	if rec.is_empty():
		return
	var u: Variant = game.find_by_uid(int(rec["uid"]))
	if u is Unit:
		game.camera.focus_on((u as Unit).position)
