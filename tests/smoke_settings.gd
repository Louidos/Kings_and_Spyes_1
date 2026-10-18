## Rauchtest Einstellungen (Settings, SettingsForm): fünf Reiter, die neuen Werte wirken sofort (Bildrate,
## Zoomtempo, Lebensbalken, Meldungsdauer, Minikarte, Starttempo, Kriegs-Rückfrage), werden gespeichert und
## wieder geladen, eine alte settings.cfg ohne die neuen Schlüssel lädt mit Standardwerten, "Standard" setzt
## alles zurück, und das Fenster passt bei UI-Grösse 0,8–1,5 auf den Bildschirm. Eigene Datei – die
## Einstellungen des Benutzers bleiben unberührt.
extends RefCounted

const TOPIC := "Einstellungen"
const FILE := "user://settings_smoke_features.cfg"


func run(r: Node) -> void:
	var g: Node = r.game
	var old_path := Settings.file_path
	Settings.file_path = FILE
	Settings.reset_defaults()
	Settings.apply()
	var defaults := Settings.values()
	var pm: Node = g.pause_menu
	pm.call("open", g)
	pm.call("show_page", "settings")
	var form: SettingsForm = pm.get_settings_form()
	await r.get_tree().process_frame
	# Reiter: je einer sichtbar, jeder hat Elemente
	var tabs_ok := true
	for tab in ["graphics", "audio", "controls", "interface", "game"]:
		form.select_tab(tab)
		for other in ["graphics", "audio", "controls", "interface", "game"]:
			tabs_ok = tabs_ok and form.get_page(other).visible == (other == tab)
		tabs_ok = tabs_ok and form.get_page(tab).get_child_count() >= 2
	r.check(TOPIC, tabs_ok, "Fünf Reiter: Grafik, Ton, Steuerung, Oberfläche, Spiel")
	# Neue Werte über das Formular: wirken sofort
	var cam: RTSCamera = g.camera
	form.set_more_values({"vsync": false, "max_fps": 60, "zoom_speed": 1.5, "edge_scroll_speed": 1.7, "hp_bars": "always",
			"notify_seconds": 12.0, "minimap_scale": 1.25, "start_speed_index": 2, "confirm_war": false, "tooltip_delay": 0.8})
	await r.get_tree().process_frame
	var zoom_before: float = cam.get("_target_zoom")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = Vector2(400, 300)
	cam._unhandled_input(wheel)
	var zoom_ratio := zoom_before / maxf(float(cam.get("_target_zoom")), 0.0001)
	var expect_ratio := pow(cam.zoom_step, 1.5)
	var mm: Control = g.hud.minimap
	r.check(TOPIC, Engine.max_fps == 60 and not Settings.vsync and absf(zoom_ratio - expect_ratio) < 0.01 \
			and Settings.shows_hp_bar(false, false) and is_equal_approx(NotificationPanel.lifetime(), 12.0) \
			and is_equal_approx(mm.custom_minimum_size.x, roundf(244.0 * 1.25)) \
			and Settings.get_start_speed_index(1, GameClock.speed_steps.size()) == 2 and is_equal_approx(Settings.edge_scroll_speed, 1.7),
			"Wirken sofort: Bildrate %d, Zoom ×%s je Raste, Lebensbalken immer, Meldungen %d s, Minikarte %d px, Starttempo %d" % [
			Engine.max_fps, String.num(zoom_ratio, 2), roundi(NotificationPanel.lifetime()), roundi(mm.custom_minimum_size.x),
			Settings.get_start_speed_index(1, GameClock.speed_steps.size())])
	# Speichern, verändern, laden: die Werte sind wieder da
	form.save_and_close()
	var saved := Settings.values()
	Settings.reset_defaults()
	Settings.load_settings()
	r.check(TOPIC, _same(Settings.values(), saved), "Gespeichert und geladen: %s" % str(Settings.values()))
	# Alte Datei (1.2.x) ohne die neuen Schlüssel: Standardwerte
	var cf := ConfigFile.new()
	cf.set_value("camera", "edge_scroll", true)
	cf.set_value("camera", "speed", 1.0)
	cf.set_value("display", "ui_scale", 1.0)
	cf.set_value("audio", "master", 0.8)
	cf.set_value("game", "autosave_minutes", 10)
	cf.save(FILE)
	Settings.reset_defaults()
	Settings.vsync = false
	Settings.hp_bars = "selected"
	Settings.reset_defaults()
	Settings.load_settings()
	r.check(TOPIC, _same(Settings.values(), defaults), "Alte settings.cfg ohne neue Schlüssel lädt mit Standardwerten")
	# "Standard" setzt alles zurück
	form.set_more_values({"max_fps": 30, "hp_bars": "selected", "notify_seconds": 20.0, "minimap_scale": 0.75})
	var defaults_button: Button = null
	var stack: Array = [form]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == "Standard":
			defaults_button = n
		stack.append_array(n.get_children())
	if defaults_button != null:
		defaults_button.pressed.emit()
	r.check(TOPIC, defaults_button != null and _same(Settings.values(), defaults) and Engine.max_fps == 0,
			"„Standard“ setzt auch die neuen Werte zurück")
	# Passt bei UI-Grösse 0,8 bis 1,5 auf den Bildschirm (jeder Reiter)
	pm.call("show_page", "settings")
	var bad: PackedStringArray = []
	var panel: Control = pm.get("_panel")
	for s in [0.8, 1.0, 1.25, 1.5]:
		Settings.ui_scale = s
		Settings.apply()
		for tab in ["graphics", "audio", "controls", "interface", "game"]:
			form.select_tab(tab)
			await r.get_tree().process_frame
			await r.get_tree().process_frame
			var t := panel.get_global_transform_with_canvas()
			var rect := Rect2(t.origin, panel.size * t.get_scale())
			var vp: Vector2 = panel.get_viewport().get_visible_rect().size
			if rect.position.x < -1.0 or rect.position.y < -1.0 or rect.end.x > vp.x + 1.0 or rect.end.y > vp.y + 1.0:
				bad.append("%s bei %d %% (%s)" % [tab, roundi(s * 100.0), str(rect)])
	r.check(TOPIC, bad.is_empty(), "Fenster passt bei UI-Grösse 80–150 %% auf den Bildschirm%s" % (
			"" if bad.is_empty() else ": " + ", ".join(bad)))
	# Ohne Rückfrage: ein Rechtsklick auf ein friedliches Dorf erklärt sofort den Krieg
	Settings.confirm_war = false
	var village: Kingdom = g.village_system.get_villages()[0]
	var hall: Building = g.village_system.get_hall(village)
	var soldiers: Array = r.spawn_tier(g.player, "fighter", 1)
	if hall != null and not soldiers.is_empty() and not g.are_hostile(g.player, village):
		g.selection._issue_order(soldiers, hall.get_center(), false)
		r.check(TOPIC, g.are_hostile(g.player, village), "Ohne Rückfrage erklärt der erste Rechtsklick auf %s den Krieg" % village.display_name)
		g.diplomacy_system.debug_set_reputation(village, g.player, 50.0)
		g.set_relation(g.player, village, "peace")
	pm.call("close")
	Settings.reset_defaults()
	Settings.apply()
	Settings.file_path = old_path
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


## Gleiche Werte (Kommazahlen ungefähr, auch in verschachtelten Dictionaries)
static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key in a:
			if not (b as Dictionary).has(key) or not _same(a[key], b[key]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.001
	return a == b
