## SelectionController
##
## Auswahl und Befehle mit Maus und Zifferntasten:
## - Linksklick: Einheit nahe der Maus (jedes sichtbare Reich), sonst das
##   Gebäude auf der Kachel, sonst Auswahl aufheben. Umschalt: eigene
##   Einheiten hinzufügen/entfernen. Doppelklick: alle eigenen Einheiten
##   dieses Typs im Bild.
## - Linke Maustaste ziehen: Rahmenauswahl eigener Einheiten. Sind Kämpfer
##   oder Heiler ohne Beruf im Rahmen, werden nur diese gewählt – so greift
##   man beim Auswählen einer Armee keine Bewohner mit.
## - Rechtsklick: eigene Einheiten bewegen bzw. einen Feind angreifen (mit
##   Strg oder "Angriff-Vorrücken": kampfbereit marschieren); bei einem
##   eigenen Beschwörungsgebäude den Sammelpunkt setzen. Rechtsklick auf
##   eine Einheit oder ein Gebäude eines friedlichen Dorfs: erst Hinweis (die
##   Truppen gehen nur hin), ein zweiter Rechtsklick auf dasselbe Dorf
##   innerhalb von 3 s erklärt den Krieg und greift an.
## - 1–9: Armee wählen (zweimal schnell: Kamera hin), Strg+Zahl: speichern,
##   Umschalt+Zahl: hinzufügen. Strg+A: alle Krieger (select_all_warriors).
## - Zielmodus (arm_order): der nächste Klick gibt "angreifend vorrücken"
##   (Strg+Rechtsklick, Knopf), "bewegen" oder "Patrouille" (Armeefenster).
## - Helden: der "aktive Held" der Auswahl (erster Held, Tab wechselt) bekommt
##   die Fähigkeitstasten C / V / B – auch in einer gemischten Auswahl (Armee).
## Der König lässt sich nur durch direktes Anklicken auswählen (nicht per
## Rahmen, Doppelklick oder Armee). Fremde Einheiten und Gebäude kann man nur
## ansehen, nicht befehligen.
## Die Simulation wird nur über die öffentlichen Befehle (CommandSystem,
## SummonSystem) verändert.
class_name SelectionController
extends Node

## Neue Auswahl (Liste aus Building/Unit, evtl. leer)
signal selection_changed(objs: Array)
## Angriff-Vorrücken für den nächsten Rechtsklick an/aus
signal attack_move_armed_changed(armed: bool)
## Zielmodus gewechselt: "attack_move", "move", "patrol" oder "" (aus)
signal order_armed_changed(mode: String)
## Ein Befehl wurde gegeben (für Markierungen): kind "move", "attack_move", "attack", "rally"
signal command_issued(pos: Vector2, kind: String)
## Der aktive Held der Auswahl hat gewechselt (Tab, neue Auswahl); null = keiner
signal focus_hero_changed(u: Unit)

## Klickradius für Einheiten in Bildschirmpixeln
const UNIT_PICK_RADIUS := 20.0
## Ab so vielen Bildschirmpixeln Mausweg wird aus dem Klick ein Rahmen
const DRAG_THRESHOLD := 6.0
## Zweimal dieselbe Armee-Taste innerhalb dieser Zeit: Kamera zur Armee
const ARMY_DOUBLE_TAP_MSEC := 350
## Ebene des Auswahlrahmens: über der Welt, unter dem HUD (Ebene 10)
const BOX_LAYER := 5
## Zweiter Rechtsklick auf ein friedliches Dorf innerhalb dieser Zeit: Krieg
const WAR_CONFIRM_MSEC := 3000

var game: Node
var selected: Array = []

var _armed := false
## Befehl des Zielmodus: "attack_move", "move" oder "patrol"
var _arm_mode := "attack_move"
## Linke Taste in der Welt gedrückt (Klick oder Rahmen läuft)
var _pressing := false
## Maus weit genug bewegt: Rahmen wird gezeigt
var _dragging := false
var _press_screen := Vector2.ZERO
## Startpunkt in Weltkoordinaten: bewegt sich die Kamera während des Ziehens
## (Bildschirmrand, Tasten), wächst der Rahmen mit
var _press_world := Vector2.ZERO
var _cur_screen := Vector2.ZERO
var _press_shift := false
var _box: SelectionBox
## uid des aktiven Helden der Auswahl (0 = keiner; nur Laufzeit)
var _focus_hero_uid := 0
var _last_army := 0
var _last_army_msec := -100000
## Kriegsbestätigung: Dorf (Kingdom.id) und Zeitpunkt des ersten Rechtsklicks
var _war_confirm_id := 0
var _war_confirm_msec := 0
## Entfernte Objekte: Signal einmal pro Frame statt einmal pro Einheit
## (in grossen Schlachten sterben viele ausgewählte Einheiten auf einmal)
var _removal_pending := false


func _ready() -> void:
	set_process(false)


func setup(p_game: Node) -> void:
	game = p_game
	game.unit_system.unit_removed.connect(_on_object_removed)
	game.building_system.building_removed.connect(_on_object_removed)
	var layer := CanvasLayer.new()
	layer.name = "SelectionBoxLayer"
	layer.layer = BOX_LAYER
	add_child(layer)
	_box = SelectionBox.new()
	layer.add_child(_box)


# ---------------------------------------------------------------------------
# Öffentliche Schnittstelle
# ---------------------------------------------------------------------------

## Erstes (noch vorhandenes) ausgewähltes Objekt oder null
func get_primary() -> Object:
	for o in selected:
		if is_instance_valid(o):
			return o
	return null


func select(objs: Array, additive: bool = false) -> void:
	# Dictionary als Menge: bleibt auch bei 700 Einheiten ein linearer Durchlauf
	var seen := {}
	var new_list: Array = []
	if additive:
		for o in selected:
			if is_instance_valid(o) and not seen.has(o):
				seen[o] = true
				new_list.append(o)
	for o in objs:
		if is_instance_valid(o) and not seen.has(o):
			seen[o] = true
			new_list.append(o)
	for o in selected:
		if is_instance_valid(o) and not seen.has(o):
			o.selected = false
	for o in new_list:
		o.selected = true
	selected = new_list
	if _armed and get_own_units().is_empty():
		cancel_arm()
	_update_focus_hero()
	selection_changed.emit(selected)


func clear() -> void:
	cancel_arm()
	if not selected.is_empty():
		select([])


## Ausgewählte lebende Einheiten (alle Reiche)
func get_selected_units() -> Array:
	var list: Array = []
	for o in selected:
		if is_instance_valid(o) and o is Unit and o.is_alive():
			list.append(o)
	return list


## Ausgewählte lebende Einheiten des Spielers
func get_own_units() -> Array:
	var list: Array = []
	if game == null:
		return list
	for o in selected:
		if is_instance_valid(o) and o is Unit and o.is_alive() and o.kingdom == game.player:
			list.append(o)
	return list


## Eigene lebende Helden der Auswahl (in Auswahlreihenfolge)
func get_selected_heroes() -> Array:
	var list: Array = []
	for u in get_own_units():
		if (u as Unit).hero_id != 0:
			list.append(u)
	return list


## Aktiver Held der Auswahl (bekommt C / V / B) oder null
func get_focus_hero() -> Unit:
	if _focus_hero_uid == 0:
		return null
	for u in get_selected_heroes():
		if (u as Unit).uid == _focus_hero_uid:
			return u
	return null


## Tab: nächster Held der Auswahl wird aktiv
func cycle_hero() -> void:
	var heroes := get_selected_heroes()
	if heroes.is_empty():
		return
	var index := 0
	for i in heroes.size():
		if (heroes[i] as Unit).uid == _focus_hero_uid:
			index = (i + 1) % heroes.size()
			break
	_set_focus_hero(heroes[index])


## Aktiven Helden prüfen: bleibt er ausgewählt, bleibt er aktiv, sonst der erste Held
func _update_focus_hero() -> void:
	var heroes := get_selected_heroes()
	for u in heroes:
		if (u as Unit).uid == _focus_hero_uid:
			return
	_set_focus_hero(heroes[0] if not heroes.is_empty() else null)


func _set_focus_hero(u: Unit) -> void:
	var uid := u.uid if u != null else 0
	if uid == _focus_hero_uid:
		return
	_focus_hero_uid = uid
	# Ein laufender Zielmodus gehört zum bisherigen Helden
	if game != null and not game.spell_targeting.ability_id.is_empty():
		game.spell_targeting.cancel()
	focus_hero_changed.emit(u)


## Nächster Rechtsklick (oder Linksklick) gibt "angreifend vorrücken"
func arm_attack_move() -> void:
	arm_order("attack_move")


## Zielmodus: der nächste Klick in die Welt gibt den Befehl mode an die eigenen
## ausgewählten Einheiten – "attack_move" (angreifend vorrücken), "move" (bewegen,
## ohne Feinde anzugreifen) oder "patrol" (Patrouille zwischen Gruppe und Ziel)
func arm_order(mode: String) -> void:
	if get_own_units().is_empty() or (_armed and _arm_mode == mode):
		return
	var was_attack := is_attack_move_armed()
	game.spell_targeting.cancel()
	_armed = true
	_arm_mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	if was_attack != is_attack_move_armed():
		attack_move_armed_changed.emit(is_attack_move_armed())
	order_armed_changed.emit(mode)


func cancel_arm() -> void:
	if not _armed:
		return
	_armed = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	attack_move_armed_changed.emit(false)
	order_armed_changed.emit("")


func is_attack_move_armed() -> bool:
	return _armed and _arm_mode == "attack_move"


## Laufender Zielmodus ("attack_move", "move", "patrol") oder "" (keiner)
func get_armed_order() -> String:
	return _arm_mode if _armed else ""


## Alle eigenen Krieger auswählen (Strg+A, Armeefenster) – ohne Bewohner und König
func select_all_warriors() -> void:
	var list: Array = game.command_system.get_warriors(game.player)
	if list.is_empty():
		Notify.info("Keine Krieger – in der Kaserne Kämpfer beschwören")
		return
	select(list)


## Armee n (1–9) des Spielers auswählen
func select_army(n: int) -> void:
	select(game.command_system.get_army(game.player, n))


## Kamera auf die Mitte der ausgewählten Einheiten (bzw. das Gebäude)
func center_on_selection() -> void:
	var units := get_selected_units()
	if units.is_empty():
		var p := get_primary()
		if p is Building:
			game.camera.focus_on((p as Building).get_center())
		return
	var c := Vector2.ZERO
	for u in units:
		var pos: Vector2 = u.position
		c += pos
	game.camera.focus_on(c / float(units.size()))


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _accepts_input() -> bool:
	# Kamera gesperrt = Lade-, Pause- oder Endbildschirm ist offen
	return game != null and game.world != null and game.player != null and game.camera.input_enabled


## Bewegung und Loslassen während eines Klicks/Rahmens kommen hier an – auch
## wenn die Maus dabei über ein HUD-Fenster fährt (das sonst die Ereignisse
## schlucken würde).
func _input(event: InputEvent) -> void:
	if not _pressing:
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		_cur_screen = mm.position
		_update_drag()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		_cur_screen = mb.position
		_finish_press(mb.shift_pressed or _press_shift)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		# Beim Bauen gehören die Maustasten dem PlacementController, im Zielmodus dem Zauber
		if not mb.pressed or game.placement.is_active() or game.spell_targeting.is_active():
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_press(mb)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_press(mb)
		return
	var key := event as InputEventKey
	if key != null and key.pressed:
		_on_key(key)


func _process(_delta: float) -> void:
	if not _pressing:
		set_process(false)
		return
	if not _accepts_input() or game.placement.is_active() or game.spell_targeting.is_active():
		_cancel_press()
		return
	# Die Kamera kann sich beim Ziehen bewegen: Rahmen nachführen
	_update_drag()


func _notification(what: int) -> void:
	# Fenster verliert den Fokus: das Loslassen käme nie an
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _pressing:
		_cancel_press()


func _exit_tree() -> void:
	if _armed:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_left_press(mb: InputEventMouseButton) -> void:
	get_viewport().set_input_as_handled()
	var world := _screen_to_world(mb.position)
	if mb.double_click and not _armed and _select_same_type(world, mb.shift_pressed):
		_cancel_press()
		return
	_pressing = true
	_dragging = false
	_press_screen = mb.position
	_cur_screen = mb.position
	_press_world = world
	_press_shift = mb.shift_pressed
	set_process(true)


func _update_drag() -> void:
	# Klick oder Rahmen entscheidet allein der Mausweg (nicht die Kamera)
	if not _dragging and _press_screen.distance_to(_cur_screen) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		_box.show_box(_world_to_screen(_press_world), _cur_screen)


func _finish_press(additive: bool) -> void:
	var was_drag := _dragging
	var end_world := _screen_to_world(_cur_screen)
	_cancel_press()
	if was_drag:
		_select_box(Rect2(_press_world, Vector2.ZERO).expand(end_world), additive)
		return
	var own := get_own_units()
	if _armed and not own.is_empty():
		# Zielmodus ist scharf: auch ein Linksklick gibt den Befehl
		_issue_armed_order(own, _press_world)
	else:
		_click(_press_world, additive)


func _cancel_press() -> void:
	_pressing = false
	_dragging = false
	if _box != null:
		_box.hide_box()
	set_process(false)


func _on_right_press(mb: InputEventMouseButton) -> void:
	if _pressing:
		return
	var world := _screen_to_world(mb.position)
	var own := get_own_units()
	if not own.is_empty():
		if _armed:
			_issue_armed_order(own, world)
		else:
			_issue_order(own, world, mb.ctrl_pressed)
		get_viewport().set_input_as_handled()
		return
	var b := _get_rally_building()
	if b != null:
		game.summon_system.set_rally(b, world)
		command_issued.emit(world, "rally")
		get_viewport().set_input_as_handled()
		return
	if _armed:
		cancel_arm()
		get_viewport().set_input_as_handled()


func _on_key(key: InputEventKey) -> void:
	if key.is_action_pressed("game_menu"):
		# Esc bricht zuerst den Rahmen bzw. Angriff-Vorrücken ab, erst dann
		# hebt die Spielszene die Auswahl auf
		if _pressing:
			_cancel_press()
			get_viewport().set_input_as_handled()
		elif _armed:
			cancel_arm()
			get_viewport().set_input_as_handled()
		return
	var n := _army_digit(key)
	if n == 0 or key.alt_pressed or key.meta_pressed:
		return
	# Schweizer Tastatur: "+" (Spieltempo) liegt auf Umschalt+1 – durchlassen
	if key.shift_pressed and not key.ctrl_pressed and key.unicode == "+".unicode_at(0):
		return
	# Auch gehaltene Tasten verbrauchen, damit Strg+Zahl nie etwas anderes auslöst
	get_viewport().set_input_as_handled()
	if key.echo:
		return
	if key.ctrl_pressed:
		_store_army(n, false)
	elif key.shift_pressed:
		_store_army(n, true)
	else:
		_recall_army(n)


## Ziffer 1–9 der Taste (physische Lage, unabhängig vom Tastaturlayout), sonst 0
func _army_digit(key: InputEventKey) -> int:
	var code := key.physical_keycode
	if code == KEY_NONE:
		code = key.keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code) - int(KEY_1) + 1
	return 0


# ---------------------------------------------------------------------------
# Auswahl
# ---------------------------------------------------------------------------

func _click(world: Vector2, shift: bool) -> void:
	var u := _pick_unit(world)
	if u != null:
		if shift and u.kingdom == game.player and _is_own_unit_selection():
			_toggle(u)
		else:
			select([u])
		return
	var b := _pick_building(world)
	if b != null:
		select([b])
	elif not shift:
		clear()


func _toggle(u: Unit) -> void:
	var list: Array = selected.duplicate()
	if list.has(u):
		list.erase(u)
	else:
		list.append(u)
	select(list)


## Rahmenauswahl: ein Durchlauf über die eigenen Einheiten
func _select_box(rect: Rect2, additive: bool) -> void:
	var army: Array = []
	var all: Array = []
	for o in game.player.units:
		if not is_instance_valid(o):
			continue
		var u: Unit = o
		if u.inside != null or u.role == "king" or not u.is_alive() \
				or not (rect.has_point(u.position) or rect.has_point(u.position + u.pick_offset())):
			continue
		all.append(u)
		if (u.joins_fights or u.can_heal()) and u.job_id == "idle":
			army.append(u)
	var picked := army if not army.is_empty() else all
	if not additive:
		select(picked)
	elif not picked.is_empty():
		select(picked, _is_own_unit_selection())


## Doppelklick auf eine eigene Einheit: alle dieses Typs im Bild.
## Gibt false zurück, wenn dort keine passende Einheit steht.
func _select_same_type(world: Vector2, additive: bool) -> bool:
	var clicked := _pick_unit(world)
	if clicked == null or clicked.kingdom != game.player or clicked.role == "king":
		return false
	var view: Rect2 = game.camera.get_view_rect()
	var list: Array = []
	for o in game.player.units:
		if not is_instance_valid(o):
			continue
		var u: Unit = o
		if u.type_id == clicked.type_id and u.inside == null and u.role != "king" and u.is_alive() \
				and view.has_point(u.position):
			list.append(u)
	select(list, additive and _is_own_unit_selection())
	return true


## Besteht die Auswahl nur aus eigenen Einheiten (oder ist leer)?
func _is_own_unit_selection() -> bool:
	for o in selected:
		if not is_instance_valid(o) or not (o is Unit) or o.kingdom != game.player:
			return false
	return true


## Einheit unter der Maus: die nächste innerhalb des Klickradius (oder ihres
## eigenen Radius bei grossen Einheiten). Nur sichtbare, lebende, nicht in
## Gebäuden; hostile_only: nur Feinde des Spielers.
func _pick_unit(world: Vector2, hostile_only: bool = false) -> Unit:
	var zoom: float = game.camera.zoom.x
	var base := UNIT_PICK_RADIUS / maxf(zoom, 0.05)
	var best: Unit = null
	var best_d := INF
	for o in game.unit_system.units:
		if not is_instance_valid(o):
			continue
		var u: Unit = o
		if u.inside != null or not u.is_alive():
			continue
		# Die Figur steht über der Position: von der Mitte des Bilds aus messen
		var r := maxf(base, u.pick_radius())
		var d := (u.position + u.pick_offset()).distance_squared_to(world)
		if d > r * r or d >= best_d:
			continue
		if hostile_only and not game.are_hostile(game.player, u.kingdom):
			continue
		if not game.can_see(game.player, u):
			continue
		best = u
		best_d = d
	return best


func _pick_building(world: Vector2) -> Building:
	var b: Variant = game.building_system.get_building_at(game.world.world_to_cell(world))
	if not is_instance_valid(b) or not game.can_see(game.player, b):
		return null
	return b


# ---------------------------------------------------------------------------
# Befehle
# ---------------------------------------------------------------------------

## Rechtsklick (bzw. scharfer Linksklick) mit eigenen Einheiten: Feind unter
## der Maus angreifen, sonst dorthin marschieren. Die Zielmarke erscheint nur,
## wenn mindestens eine Einheit den Befehl angenommen hat (der König etwa
## verweigert Ziele ausserhalb seines Reichs).
func _issue_order(units: Array, world: Vector2, attack_move: bool) -> void:
	var target: Node2D = _pick_unit(world, true)
	if target == null:
		var b := _pick_building(world)
		if b != null and b.is_alive() and game.are_hostile(game.player, b.kingdom):
			target = b
	var before := _order_ids(units)
	if target == null:
		# Friedliches Dorf unter der Maus: zweiter Rechtsklick erklärt den Krieg
		var peaceful := _pick_village_target(world)
		if peaceful != null:
			var v: Kingdom = peaceful.get("kingdom")
			var now := Time.get_ticks_msec()
			if not Settings.confirm_war or (v.id == _war_confirm_id and now - _war_confirm_msec <= WAR_CONFIRM_MSEC):
				_war_confirm_id = 0
				game.diplomacy_system.declare_war(game.player, v)
				target = peaceful
			else:
				_war_confirm_id = v.id
				_war_confirm_msec = now
				Notify.warning("%s ist friedlich. Nochmals Rechtsklick: Krieg erklären (Ruf sinkt stark, Verträge enden)." %
						v.display_name, peaceful.position)
	if target != null:
		game.command_system.order_attack(units, target)
		if _any_order_taken(units, before):
			command_issued.emit(target.position, "attack")
	else:
		game.command_system.order_move(units, world, attack_move)
		if _any_order_taken(units, before):
			command_issued.emit(world, "attack_move" if attack_move else "move")
	cancel_arm()


## Befehl des Zielmodus an der Stelle world geben (arm_order), danach Zielmodus aus.
## "attack_move" verhält sich wie Strg+Rechtsklick (Feind unter der Maus: Angriff).
func _issue_armed_order(units: Array, world: Vector2) -> void:
	var before := _order_ids(units)
	match _arm_mode:
		"move":
			game.command_system.order_move(units, world, false)
		"patrol":
			game.command_system.order_patrol(units, world)
		_:
			_issue_order(units, world, true)
			return
	if _any_order_taken(units, before):
		command_issued.emit(world, _arm_mode)
	cancel_arm()


## Einheit oder Gebäude eines selbstständigen, nicht verfeindeten Dorfs an der
## Stelle (null, wenn keins)
func _pick_village_target(world: Vector2) -> Node2D:
	var vs: VillageSystem = game.village_system
	var u := _pick_unit(world, false)
	if u != null and vs.is_village(u.kingdom) and not game.are_hostile(game.player, u.kingdom):
		return u
	var b := _pick_building(world)
	if b != null and b.is_alive() and vs.is_village(b.kingdom) and not game.are_hostile(game.player, b.kingdom):
		return b
	return null


## order_id je Einheit vor einem Befehl (CommandSystem zählt ihn bei jedem
## angenommenen Befehl hoch)
func _order_ids(units: Array) -> Dictionary:
	var ids := {}
	for u in units:
		if is_instance_valid(u) and u is Unit:
			ids[u] = u.order_id
	return ids


## Hat mindestens eine Einheit seit before einen neuen Befehl bekommen?
func _any_order_taken(units: Array, before: Dictionary) -> bool:
	for u in units:
		if is_instance_valid(u) and u is Unit and before.has(u) and u.order_id != before[u]:
			return true
	return false


## Eigenes fertiges Beschwörungsgebäude in der Auswahl (für den Sammelpunkt)
func _get_rally_building() -> Building:
	var p := get_primary()
	if not (p is Building):
		return null
	var b := p as Building
	if b.kingdom != game.player or b.get_summon_tiers().is_empty():
		return null
	return b


func _store_army(n: int, add: bool) -> void:
	var own := get_own_units()
	var units: Array = []
	for u in own:
		if u.role != "king":
			units.append(u)
	if units.is_empty():
		if own.is_empty():
			Notify.info("Armee %d: zuerst eigene Einheiten auswählen" % n)
		else:
			Notify.info("Der König gehört keiner Armee an.")
		return
	var player: Kingdom = game.player
	if add:
		game.command_system.add_to_army(player, n, units)
		var total: int = game.command_system.get_army(player, n).size()
		Notify.info("Armee %d: %s hinzugefügt (jetzt %d)" % [n, _units_text(units.size()), total])
	else:
		game.command_system.set_army(player, n, units)
		Notify.info("Armee %d gespeichert (%s)" % [n, _units_text(units.size())])


func _recall_army(n: int) -> void:
	var units: Array = game.command_system.get_army(game.player, n)
	if units.is_empty():
		_last_army = 0
		Notify.info("Keine Armee %d – Einheiten auswählen und Strg+%d drücken" % [n, n])
		return
	var now := Time.get_ticks_msec()
	var again := n == _last_army and now - _last_army_msec <= ARMY_DOUBLE_TAP_MSEC
	select(units)
	if again:
		center_on_selection()
	_last_army = n
	_last_army_msec = now


static func _units_text(count: int) -> String:
	return "1 Einheit" if count == 1 else "%d Einheiten" % count


# ---------------------------------------------------------------------------

func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func _on_object_removed(obj: Object) -> void:
	var i := selected.find(obj)
	if i < 0:
		return
	selected.remove_at(i)
	if not _removal_pending:
		_removal_pending = true
		_emit_after_removal.call_deferred()


func _emit_after_removal() -> void:
	_removal_pending = false
	if _armed and get_own_units().is_empty():
		cancel_arm()
	_update_focus_hero()
	selection_changed.emit(selected)
