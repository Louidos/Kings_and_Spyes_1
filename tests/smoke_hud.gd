## Rauchtest übersichtliches HUD: jedes Gebäude des Baumenüs steht in einem der fünf Reiter
## (buildings.json category) und ist in zwei Klicks erreichbar; gesperrte Gebäude nennen den Grund;
## gleiche Meldungen werden gebündelt („3× …“), höchstens 4 sind sichtbar; die Abschnitte des
## Auswahlfensters klappen ein und bleiben eingeklappt; „Kompaktes HUD“ kürzt die Texte; bei
## UI-Grösse 0,8–1,5 überlappt nichts und die obere Leiste zeigt alle Ressourcen (nur mit Fenster, xvfb-run).
extends RefCounted

const TOPIC := "HUD"


func run(r: Node) -> void:
	var g: Node = r.game
	var hud: Node = g.hud
	var menu: BuildMenu = hud.build_menu
	var k: Kingdom = g.player
	# Baumenü: jedes Gebäude in genau einem Reiter, sichtbar nach einem Klick auf den Reiter
	var tabs := {}
	for entry in BuildMenu.TABS:
		tabs[str(entry[0])] = true
	var missing: PackedStringArray = []
	for id in menu._buttons:
		if id == BuildMenu.DEMOLISH_ID:
			continue
		var def := DataDB.get_building(str(id))
		var cat := BuildMenu.category_of(def)
		if tabs.has(cat):
			(menu._tab_buttons[cat] as Button).pressed.emit()
		if not tabs.has(cat) or menu.get_tab() != cat or not (menu._buttons[id] as Button).visible:
			missing.append("%s (%s)" % [id, cat])
	r.check(TOPIC, missing.is_empty() and menu._buttons.size() > 20,
			"Baumenü: %d Gebäude in %d Reitern, jedes in zwei Klicks%s" % [menu._buttons.size() - 1, tabs.size(),
			"" if missing.is_empty() else ": fehlt " + ", ".join(missing)])
	# Gesperrtes Gebäude: Grund im Tooltip
	var locked_tip := ""
	for id in menu._buttons:
		if id != BuildMenu.DEMOLISH_ID and not BuildMenu.lock_reason(DataDB.get_building(str(id)), k).is_empty():
			locked_tip = menu._build_tip(str(id))
			r.check(TOPIC, bool((menu._buttons[id] as Button).get("locked")) and (locked_tip.contains("Benötigt") or locked_tip.contains("Braucht")),
					"Gesperrt (%s): Grund im Tooltip" % id)
			break
	menu.select_tab("economy")
	# Meldungen: gleiche bündeln, höchstens vier sichtbar
	var np: NotificationPanel = hud.notification_panel
	for i in 3:
		Notify.posted.emit("Angriff auf das Lager", "danger", Vector2(100, 100))
	var top: Button = np._entries[0]["button"]
	r.check(TOPIC, top.text == "3× Angriff auf das Lager", "Meldungen gebündelt: „%s“" % top.text)
	for i in 6:
		Notify.posted.emit("Testmeldung %d" % i, "info", null)
	await r.get_tree().process_frame
	var shown := 0
	for c in np.get_children():
		if not (c as Node).is_queued_for_deletion():
			shown += 1
	r.check(TOPIC, np._entries.size() <= NotificationPanel.MAX_ENTRIES and shown <= NotificationPanel.MAX_ENTRIES,
			"Höchstens %d Meldungen sichtbar (%d)" % [NotificationPanel.MAX_ENTRIES, shown])
	# Auswahlfenster: Abschnitte einklappen, Zustand bleibt beim Wechsel der Auswahl
	var sp: SelectionPanel = hud.selection_panel
	var soldiers: Array = r.spawn_tier(k, "fighter", 2)
	if soldiers.size() == 2:
		g.selection.select([soldiers[0]])
		sp._refresh()
		var sec: Dictionary = sp._sections
		var heads := true
		for key in ["stats", "stance", "actions"]:
			heads = heads and (sec[key]["header"] as Button).visible and (sec[key]["body"] as Control).visible
		(sec["stats"]["header"] as Button).pressed.emit()
		(sec["actions"]["header"] as Button).pressed.emit()
		g.selection.select([soldiers[1]])
		sp._refresh()
		var closed: bool = not (sec["stats"]["body"] as Control).visible and not (sec["actions"]["body"] as Control).visible \
				and (sec["stats"]["header"] as Button).visible and (sec["stance"]["body"] as Control).visible
		sp.set_section_open("stats", true)
		sp.set_section_open("actions", true)
		r.check(TOPIC, heads and closed and (sec["stats"]["body"] as Control).visible,
				"Auswahlfenster: Werte und Befehle eingeklappt, bleiben es bei einer anderen Einheit")
	# Kompaktes HUD: Fenster-Knöpfe nur mit Symbol, Baumenü mit Kurznamen
	Settings.compact_hud = true
	Settings.apply()
	await r.get_tree().process_frame
	var research_button: Button = hud.get("_research_button")
	var kingdom_button: Button = hud.get("_kingdom_button")
	var compact_ok: bool = research_button.text.is_empty() and kingdom_button.text.is_empty() and research_button.icon != null \
			and not hud.hint_label.visible and (menu._buttons[BuildMenu.DEMOLISH_ID] as Button).text == "Abreissen"
	Settings.compact_hud = false
	Settings.apply()
	await r.get_tree().process_frame
	r.check(TOPIC, compact_ok and not kingdom_button.text.is_empty() and hud.hint_label.visible, "Kompaktes HUD: Fenster-Knöpfe nur als Symbol, aus = wieder mit Namen")
	# Nichts überlappt bei UI-Grösse 0,8–1,5, obere Leiste zeigt alle Ressourcen. Nur mit echtem Fenster
	# (z. B. xvfb-run): ohne Fenster (--headless) liefert Godot keine echten Schriftmasse.
	if DisplayServer.get_name() == "headless":
		g.selection.clear()
		print("[smoke] %s: Überlappungsprüfung übersprungen (ohne Fenster; mit xvfb-run ausführen)" % TOPIC)
		return
	if soldiers.size() == 2:
		g.selection.select(soldiers)
	var bad: PackedStringArray = []
	var old_scale := Settings.ui_scale
	for compact in [false, true]:
		Settings.compact_hud = compact
		for s in [0.8, 1.0, 1.25, 1.5]:
			Settings.ui_scale = s
			Settings.apply()
			for tab in ["economy", "military"]:
				menu.select_tab(tab)
				for i in 4:
					await r.get_tree().process_frame
				bad.append_array(_layout_problems(hud, "%d %%%s %s" % [roundi(s * 100.0), " kompakt" if compact else "", tab]))
	Settings.compact_hud = false
	Settings.ui_scale = old_scale
	Settings.apply()
	menu.select_tab("economy")
	g.selection.clear()
	r.check(TOPIC, bad.is_empty(), "Bei UI-Grösse 80–150 %% überlappt nichts, alle Ressourcen oben sichtbar%s" % (
			"" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 6))))


## Bildschirm-Rechteck eines Steuerelements (mit UI-Grösse und Verkleinerung der Leiste)
static func _rect(c: Control) -> Rect2:
	var t := c.get_global_transform_with_canvas()
	return Rect2(t.origin, c.size * t.get_scale())


static func _layout_problems(hud: Node, label: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var vp: Rect2 = (hud.top_bar as Control).get_viewport().get_visible_rect()
	var screen := Rect2(Vector2.ZERO, vp.size).grow(1.0)
	# Obere Leiste: die drei Gruppen auf dem Bildschirm und ohne Überlappung, jede Ressource sichtbar
	var hbox: Control = hud.top_bar.get_node("HBox")
	var groups: Array = []
	for n in ["ResourceGroup", "WindowGroup", "TimeGroup"]:
		var c: Control = hbox.get_node_or_null(n)
		if c != null:
			groups.append([n, _rect(c)])
	for e in (hud.resource_bar as ResourceBar)._entries.values():
		var c: Control = e
		if not c.is_visible_in_tree():
			out.append("%s: Ressource ausgeblendet" % label)
		elif not screen.encloses(_rect(c)):
			out.append("%s: Ressource ausserhalb %s" % [label, str(_rect(c))])
	# Grosse Bereiche: dürfen sich nicht überdecken und nicht über den Rand ragen
	var areas: Array = groups.duplicate()
	for pair in [["Auswahl", hud.bottom_left], ["Baumenü", hud.build_menu], ["Minikarte", hud.get_node("Root/MinimapPanel")],
			["Meldungen", hud.notification_panel], ["Arbeit", hud.job_panel]]:
		var c: Control = pair[1]
		if c.is_visible_in_tree() and c.size.x > 1.0 and c.size.y > 1.0:
			areas.append([pair[0], _rect(c)])
	for a in areas:
		if not screen.encloses(a[1] as Rect2):
			out.append("%s: %s ragt über den Rand %s" % [label, a[0], str(a[1])])
	for i in areas.size():
		for j in range(i + 1, areas.size()):
			var ra: Rect2 = (areas[i][1] as Rect2).grow(-1.0)
			var rb: Rect2 = (areas[j][1] as Rect2).grow(-1.0)
			if ra.intersects(rb):
				out.append("%s: %s überdeckt %s" % [label, areas[i][0], areas[j][0]])
	return out
