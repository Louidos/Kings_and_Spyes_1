## EventBanner
##
## Ereignisleiste unter der oberen Leiste, mittig (Phase 8): eine Karte je Ereignis,
## das den Spieler betrifft, je Magiesturm in der Nähe und je offenem Angebot von
## Flüchtlingen oder Wanderern. Inhalt: Symbol (Grafik oder Farbkreis mit Buchstabe),
## Name und Restzeit ("6:12", Welle: "9 Monster", Angebot: "wartet 2:35"); Rand rot
## bzw. grün (gute Ereignisse). Tooltip mit allen Wirkungen. Klick: Kamera zur Stelle
## und Reichsübersicht (Reiter "Ereignisse"), bei Angeboten der Flüchtlingsdialog.
## Neuaufbau nur bei Signalen des EventSystems, Texte alle 0,5 s.
class_name EventBanner
extends HBoxContainer

const REFRESH_INTERVAL := 0.5
const COLOR_BAD := Color(0.9, 0.35, 0.28)
const COLOR_GOOD := Color(0.45, 0.82, 0.4)
const COLOR_OFFER := Color(0.85, 0.78, 0.55)


## Kreis in der Ereignisfarbe mit Buchstabe (oder die Grafik des Ereignisses)
class ChipIcon:
	extends Control
	var color := Color.WHITE
	var letter := ""
	var texture: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		if texture != null:
			draw_texture_rect(texture, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
			return
		draw_circle(c, r, Color(0.05, 0.04, 0.03, 0.9))
		draw_circle(c, r - 1.5, color)
		var font := ThemeDB.fallback_font
		var fs := 15
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.04))


## Eine Karte der Leiste (anklickbar, farbiger Tooltip)
class Chip:
	extends PanelContainer
	signal pressed
	var tip_source := Callable()
	var label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _get_tooltip(_at_position: Vector2) -> String:
		return str(tip_source.call()) if tip_source.is_valid() else ""

	func _make_custom_tooltip(for_text: String) -> Object:
		return ResearchTipButton.make_rich_tooltip(for_text, 380.0)


var game: Node
var hud: Node
var _timer := 0.0
var _dirty := true
## Karten: [{"chip": Chip, "type": "event"|"offer", "id": int}]
var _chips: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_game: Node, p_hud: Node) -> void:
	game = p_game
	hud = p_hud
	var es: EventSystem = game.event_system
	es.event_started.connect(func(_ev: Dictionary) -> void: _dirty = true)
	es.event_ended.connect(func(_ev: Dictionary, _r: String) -> void: _dirty = true)
	es.offer_created.connect(func(_o: Dictionary) -> void: _dirty = true)
	es.offer_resolved.connect(func(_o: Dictionary, _a: bool) -> void: _dirty = true)
	_rebuild()


## Anzahl der Karten (Rauchtest)
func get_chip_count() -> int:
	if _dirty:
		_rebuild()
	return _chips.size()


func _process(delta: float) -> void:
	if game == null:
		return
	_timer += delta
	if _dirty:
		_rebuild()
	elif _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		# Stürme ziehen: Neuaufbau, wenn sich die Menge der Karten ändert
		if _entries().size() != _chips.size():
			_rebuild()
		else:
			_refresh_texts()


## Was die Leiste zeigt: [{"type", "id", "ev"/"offer"}]
func _entries() -> Array:
	var es: EventSystem = game.event_system
	var player: Kingdom = game.player
	var list: Array = []
	var radius := float(DataDB.evt("player_notify_radius", 30)) * float(game.world.tile_size)
	var home := player.castle.get_center() if is_instance_valid(player.castle) else Vector2(-1.0e9, -1.0e9)
	for ev in es.active:
		var kind := str(ev["kind"])
		if kind == "refugees" or kind == "wanderers":
			continue
		var near := kind == "magic_storm" and home.distance_to(ev["pos"]) <= float(ev["radius"]) + radius
		if es.affects(ev, player) or near:
			list.append({"type": "event", "id": int(ev["uid"]), "ev": ev})
	for offer in es.get_offers(player):
		list.append({"type": "offer", "id": int(offer["id"]), "offer": offer})
	return list


func _rebuild() -> void:
	_dirty = false
	_timer = 0.0
	for c in _chips:
		(c["chip"] as Control).queue_free()
	_chips.clear()
	if game == null:
		return
	for entry in _entries():
		var is_offer := str(entry["type"]) == "offer"
		var event_id := str((entry["offer"] as Dictionary)["event_id"]) if is_offer else str((entry["ev"] as Dictionary)["event_id"])
		var def := DataDB.get_event(event_id)
		var chip := Chip.new()
		var border := COLOR_OFFER if is_offer else (COLOR_GOOD if bool(def.get("positive", false)) else COLOR_BAD)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.09, 0.075, 0.06, 0.88)
		st.border_color = border
		st.set_border_width_all(2)
		st.set_corner_radius_all(6)
		st.content_margin_left = 6
		st.content_margin_right = 8
		st.content_margin_top = 3
		st.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", st)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)
		var icon := ChipIcon.new()
		icon.color = def.get("color", Color.WHITE)
		icon.letter = str(def.get("letter", "?"))
		icon.texture = Assets.texture(str(def.get("icon", "")))
		row.add_child(icon)
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 15)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		chip.label = label
		var id := int(entry["id"])
		if is_offer:
			chip.tip_source = _offer_tip.bind(id)
			chip.pressed.connect(_on_offer_pressed.bind(id))
		else:
			chip.tip_source = _event_tip.bind(id)
			chip.pressed.connect(_on_event_pressed.bind(id))
		add_child(chip)
		_chips.append({"chip": chip, "type": str(entry["type"]), "id": id})
	_refresh_texts()


func _refresh_texts() -> void:
	var es: EventSystem = game.event_system
	for c in _chips:
		var chip: Chip = c["chip"]
		var text := ""
		if str(c["type"]) == "offer":
			var offer := es.get_offer(int(c["id"]))
			if offer.is_empty():
				_dirty = true
				continue
			var def := DataDB.get_event(str(offer["event_id"]))
			if str(offer["state"]) == "waiting":
				text = "%s · wartet %s" % [str(def.get("name", "")), EventSystem.time_text(maxf(float(offer["expires"]) - GameClock.game_time, 0.0))]
			else:
				text = "%s · %d nähern sich" % [str(def.get("name", "")), (offer["uids"] as Array).size()]
		else:
			var ev := _find_event(int(c["id"]))
			if ev.is_empty():
				_dirty = true
				continue
			var def := DataDB.get_event(str(ev["event_id"]))
			text = str(def.get("name", ""))
			if str(ev["kind"]) == "monster_wave":
				var raid: Dictionary = game.monster_system.get_raid(int((ev["data"] as Dictionary).get("raid_id", 0)))
				text += " · %d Monster" % (raid.get("uids", []) as Array).size()
			else:
				var rest := es.get_remaining(ev)
				if rest >= 0.0:
					text += " · " + EventSystem.time_text(rest)
		if chip.label.text != text:
			chip.label.text = text


func _find_event(uid: int) -> Dictionary:
	for ev in game.event_system.active:
		if int(ev["uid"]) == uid:
			return ev
	return {}


func _event_tip(uid: int) -> String:
	var ev := _find_event(uid)
	if ev.is_empty():
		return ""
	var es: EventSystem = game.event_system
	var lines: PackedStringArray = es.describe(ev, game.player).split("\n")
	var out: PackedStringArray = ["[b]%s[/b]" % ResearchTipButton.esc(lines[0])]
	for i in range(1, lines.size()):
		out.append(ResearchTipButton.esc(lines[i]))
	out.append(ResearchTipButton.colored("Klick: hinspringen, Reichsübersicht (L)", Color(0.74, 0.71, 0.66)))
	return "\n".join(out)


func _offer_tip(id: int) -> String:
	var es: EventSystem = game.event_system
	var offer := es.get_offer(id)
	if offer.is_empty():
		return ""
	var def := DataDB.get_event(str(offer["event_id"]))
	var lines: PackedStringArray = ["[b]%s bitten um Aufnahme[/b]" % ResearchTipButton.esc(str(def.get("name", "")))]
	if not str(offer.get("story", "")).is_empty():
		lines.append(ResearchTipButton.esc(str(offer["story"])))
	lines.append(ResearchTipButton.esc(es.get_offer_text(offer, game.player)))
	lines.append(ResearchTipButton.colored("Klick: Aufnehmen oder Abweisen", Color(0.74, 0.71, 0.66)))
	return "\n".join(lines)


func _on_event_pressed(uid: int) -> void:
	var ev := _find_event(uid)
	if ev.is_empty():
		return
	game.camera.focus_on(ev["pos"])
	if hud != null and hud.has_method("open_kingdom"):
		hud.call("open_kingdom", "events")


func _on_offer_pressed(id: int) -> void:
	if hud != null and hud.has_method("open_refugee_dialog"):
		hud.call("open_refugee_dialog", id)
