## TradeRouteList
##
## Handelsliste (Phase 9): eigene Handelswege mit Partnerdorf, Art, Zustand (mit Grund und
## Restzeit bei abgeschnittenen Wegen), Karawane (unterwegs, Ladung, Leben) und Zählern;
## Knöpfe "Hinspringen" und "Weg freigeben" (im F3-Modus zusätzlich "Karawane überfallen
## (Test)" und "Abschneiden (Test)"). Darunter gesichtete fremde Wege und die Versorgung.
## Steckt im Diplomatiefenster (Reiter "Handelswege"; ab Phase 8 im Reichsfenster). Zeigt
## nur an und ruft das TradeRouteSystem mit dem Spieler-Reich auf.
class_name TradeRouteList
extends VBoxContainer

## Kamera soll zu pos springen
signal jump_requested(pos: Vector2)

const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_WARN := Color(1.0, 0.75, 0.35)
const STATE_COLORS := {"open": COLOR_GOOD, "cut": COLOR_BAD, "blocked": COLOR_WARN, "paused": COLOR_DIM}

var game: Node
## Schlüssel der zuletzt gebauten Liste (Neuaufbau nur bei Änderung)
var _key: Array = []
## Weg-id -> {"title", "state", "caravan", "counts", "reopen"}
var _rows: Dictionary = {}
var _foreign_labels: Array = []
var _supply_label: Label
var _supply_jump: Button


func setup(p_game: Node) -> void:
	game = p_game
	add_theme_constant_override("separation", 6)


## Inhalte aktualisieren (vom Fenster alle 0.25 s, solange es offen ist)
func refresh() -> void:
	if game == null:
		return
	var trs: TradeRouteSystem = game.trade_route_system
	var player: Kingdom = game.player
	var own := trs.get_routes(player)
	var foreign: Array = []
	for r in trs.get_visible_routes(player):
		if int((r as Dictionary)["owner_id"]) != player.id:
			foreign.append(r)
	var debug: bool = game.hud.is_debug_visible() if game.hud != null and game.hud.has_method("is_debug_visible") else false
	var key: Array = [debug]
	for r in own:
		key.append(str(r["id"]))
	for r in foreign:
		key.append("f" + str(r["id"]))
	if key != _key:
		_key = key
		_rebuild(own, foreign, debug)
	for r in own:
		_update_row(r)
	var fi := 0
	for r in foreign:
		if fi < _foreign_labels.size():
			(_foreign_labels[fi] as Label).text = _foreign_text(r)
		fi += 1
	var unsupplied: Array = game.supply_system.get_unsupplied(player)
	_supply_label.text = "%d Einheiten ohne Versorgung (keine Erholung)" % unsupplied.size() if not unsupplied.is_empty() \
			else "Alle Truppen versorgt (eigenes Gebiet, Verbündete oder offene Handelswege)."
	_supply_jump.visible = not unsupplied.is_empty()
	if not unsupplied.is_empty():
		_supply_jump.set_meta("pos", (unsupplied[0] as Unit).position)


func _rebuild(own: Array, foreign: Array, debug: bool) -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_foreign_labels.clear()
	add_child(_header("Eigene Handelswege"))
	if own.is_empty():
		add_child(_label("Keine – schliesse einen Handelsvertrag oder ein Bündnis mit einem Dorf (Reiter Dörfer).", COLOR_DIM))
	for r in own:
		var id := str(r["id"])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		add_child(box)
		var row := {"title": _label("", COLOR_TEXT), "state": _label("", COLOR_TEXT), "caravan": _label("", COLOR_DIM),
				"counts": _label("", COLOR_DIM)}
		for k in ["title", "state", "caravan", "counts"]:
			box.add_child(row[k])
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		box.add_child(buttons)
		buttons.add_child(_button("Hinspringen", _on_jump.bind(id)))
		var reopen := _button("Weg freigeben", _on_reopen.bind(id))
		buttons.add_child(reopen)
		row["reopen"] = reopen
		if debug:
			buttons.add_child(_button("Karawane überfallen (Test)", _on_debug_kill.bind(id)))
			buttons.add_child(_button("Abschneiden (Test)", _on_debug_cut.bind(id)))
		_rows[id] = row
	add_child(_header("Fremde Handelswege (gesichtet)"))
	if foreign.is_empty():
		add_child(_label("Noch keine gesichtet.", COLOR_DIM))
	for r in foreign:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		add_child(line)
		var l := _label(_foreign_text(r), COLOR_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		_foreign_labels.append(l)
		line.add_child(_button("Hinspringen", _on_jump.bind(str(r["id"]))))
	add_child(_label("Überfalle Karawanen für Beute – ihre Lieferungen fallen dann aus.", COLOR_DIM))
	add_child(_header("Versorgung"))
	var sl := HBoxContainer.new()
	add_child(sl)
	_supply_label = _label("", COLOR_TEXT)
	_supply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.add_child(_supply_label)
	_supply_jump = _button("Hinspringen", _on_supply_jump)
	sl.add_child(_supply_jump)


func _update_row(r: Dictionary) -> void:
	var row: Dictionary = _rows.get(str(r["id"]), {})
	if row.is_empty():
		return
	var trs: TradeRouteSystem = game.trade_route_system
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	var name_label: Label = row["title"]
	name_label.text = "%s – %s" % [v.display_name if v != null else "?", "Bündnis" if str(r["kind"]) == "alliance" else "Handel"]
	if v != null:
		name_label.add_theme_color_override("font_color", v.color.lightened(0.3))
	var state := str(r["state"])
	var text := "Zustand: %s" % trs.get_state_name(state)
	if not str(r["reason"]).is_empty() and state != "open":
		text += " (%s)" % str(r["reason"])
	if state == "cut":
		var left := maxf(float(DataDB.trade("cut.min_cut_seconds", 180)) - (GameClock.game_time - float(r["state_since"])), 0.0)
		text += " · noch %d:%02d" % [floori(left / 60.0), floori(fmod(left, 60.0))]
	var state_label: Label = row["state"]
	state_label.text = text
	state_label.add_theme_color_override("font_color", STATE_COLORS.get(state, COLOR_TEXT))
	var caravan_text := trs.get_leg_text(r)
	var cargo: Dictionary = r["cargo"]
	if not cargo.is_empty():
		caravan_text += " · " + DataDB.cost_to_text(cargo)
	var u := trs.get_caravan(r)
	if u != null:
		caravan_text += " · %d %% Leben" % roundi(u.hp / maxf(u.max_hp, 1.0) * 100.0)
	(row["caravan"] as Label).text = caravan_text
	var rs: Dictionary = r["stats"]
	(row["counts"] as Label).text = "Lieferungen %d · Verluste %d · ausgefallen %d" % [int(rs["trips"]), int(rs["lost"]), int(r["missed"])]
	var reopen: Button = row["reopen"]
	var reason := trs.can_reopen(game.player, str(r["id"]))
	reopen.disabled = not reason.is_empty()
	reopen.tooltip_text = "Weg sofort wieder öffnen – du übernimmst den Geleitschutz." if reason.is_empty() else reason


func _foreign_text(r: Dictionary) -> String:
	var owner_k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	return "%s ↔ %s · %s" % [owner_k.display_name if owner_k != null else "?", v.display_name if v != null else "?",
			(game.trade_route_system as TradeRouteSystem).get_state_name(str(r["state"]))]


func _on_jump(id: String) -> void:
	var trs: TradeRouteSystem = game.trade_route_system
	var r := trs.get_route(id)
	if r.is_empty():
		return
	var u := trs.get_caravan(r)
	if u != null and u.inside == null:
		jump_requested.emit(u.position)
	else:
		jump_requested.emit(trs.get_midpoint(r))


func _on_reopen(id: String) -> void:
	if not (game.trade_route_system as TradeRouteSystem).reopen(game.player, id):
		Notify.warning((game.trade_route_system as TradeRouteSystem).can_reopen(game.player, id))


func _on_debug_kill(id: String) -> void:
	if not (game.trade_route_system as TradeRouteSystem).debug_kill_caravan(id, game.wild):
		Notify.info("Debug: keine Karawane unterwegs")


func _on_debug_cut(id: String) -> void:
	(game.trade_route_system as TradeRouteSystem).debug_cut(id)


func _on_supply_jump() -> void:
	if _supply_jump.has_meta("pos"):
		jump_requested.emit(_supply_jump.get_meta("pos"))


func _header(text: String) -> Label:
	var l := _label(text, Color(0.95, 0.82, 0.45))
	l.add_theme_font_size_override("font_size", 18)
	return l


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	return b
