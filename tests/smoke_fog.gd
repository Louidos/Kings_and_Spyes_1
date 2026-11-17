## Rauchtest Kriegsnebel (FogSystem, FogView, Minikarte, Game.can_see): zu Beginn ist nur die
## Umgebung der Burg sichtbar, der Rest schwarz; ein Späher deckt beim Laufen auf, hinter ihm bleibt
## die Karte erkundet (abgedunkelt); fremde Einheiten ausserhalb der Sicht sind weder in der Welt
## noch auf der Minikarte und lassen sich nicht anklicken; fremde Gebäude bleiben "zuletzt gesehen";
## ein auskundschaftender Spion deckt das Zielgebiet auf; Speichern/Laden behält das Erkundete;
## ein Spielstand ohne Nebel-Daten (1.3.x) gilt rund um das eigene Gebiet als erkundet; mit der
## Option "aus" ist alles sichtbar. Misst die Dauer einer Aktualisierung (docs/balancing.md).
extends RefCounted

const TOPIC := "Nebel"


func run(r: Node) -> void:
	var g: Node = r.game
	var fog: FogSystem = g.fog_system
	var p: Kingdom = g.player
	var w: WorldData = g.world
	var ts := float(w.tile_size)
	r.check(TOPIC, fog.is_enabled() and fog.has_grid(p), "Kriegsnebel ist in einer neuen Partie an")
	# Zu Beginn: nur die Burg-Umgebung sichtbar (diese Partie läuft schon eine Weile: der
	# Startzustand wird mit einem frischen Raster nachgestellt)
	fog.grids.erase(p.id)
	fog.known_buildings.erase(p.id)
	fog._visible_lists.erase(p.id)
	var own_units: Array = []
	for u in p.units:
		own_units.append([u, (u as Unit).position])
		(u as Unit).position = p.castle.get_center()
	fog.update_all()
	var counts := fog.get_counts(p)
	var total := float(w.width * w.height)
	var castle_cell := w.world_to_cell(p.castle.get_center())
	var corner := Vector2i(0, 0) if castle_cell.x > w.width / 2.0 else Vector2i(w.width - 1, w.height - 1)
	r.check(TOPIC, fog.get_state(p, castle_cell) == FogSystem.VISIBLE and fog.get_state(p, corner) == FogSystem.UNEXPLORED
			and float(counts["unexplored"]) > total * 0.8 and int(counts["visible"]) > 0,
			"Start: Burg sichtbar, Ecke %s schwarz, %d %% unerforscht, %d Kacheln sichtbar" % [str(corner),
			roundi(100.0 * float(counts["unexplored"]) / total), int(counts["visible"])])
	for entry in own_units:
		(entry[0] as Unit).position = entry[1]
	# Späher läuft: vorne sichtbar, hinten erkundet (abgedunkelt)
	var scout: Unit = (r.spawn_tier(p, "scout", 1) as Array)[0]
	var dir := Vector2(corner - castle_cell).normalized()
	var a := p.castle.get_center() + dir * 40.0 * ts
	var b := p.castle.get_center() + dir * 70.0 * ts
	scout.position = a
	fog.update_all()
	var seen_a := fog.get_state_at(p, a) == FogSystem.VISIBLE
	scout.position = b
	fog.update_all()
	r.check(TOPIC, seen_a and fog.get_state_at(p, b) == FogSystem.VISIBLE and fog.get_state_at(p, a) == FogSystem.EXPLORED,
			"Späher deckt auf: Weg vorne sichtbar, hinter ihm erkundet (Zustand %d)" % fog.get_state_at(p, a))
	# Fremde Einheit ausserhalb der Sicht: unsichtbar, nicht wählbar, nicht auf der Minikarte
	var far := p.castle.get_center() + dir * 100.0 * ts
	var wolf: Unit = g.unit_system.spawn_unit(g.wild, "wolf", far)
	fog.update_all()
	var mm: Minimap = g.hud.get("minimap")
	mm.call("_rebuild_cache")
	var on_minimap := _wolf_on_minimap(mm, wolf, w)
	var picked: Variant = g.selection.call("_pick_unit", wolf.position + wolf.pick_offset(), false)
	r.check(TOPIC, not g.can_see(p, wolf) and wolf.fog_hidden and not wolf.visible and picked != wolf and not on_minimap,
			"Wolf im Nebel: unsichtbar (%s), nicht wählbar, nicht auf der Minikarte" % str(wolf.visible))
	scout.position = far + Vector2(2.0 * ts, 0)
	fog.update_all()
	mm.call("_rebuild_cache")
	r.check(TOPIC, g.can_see(p, wolf) and wolf.visible and _wolf_on_minimap(mm, wolf, w),
			"Späher beim Wolf: sichtbar und auf der Minikarte")
	g.unit_system.remove_unit(wolf)
	# Fremde Burg: vorher unbekannt, gesehen bleibt sie stehen ("zuletzt gesehen")
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if not ai.is_empty() and is_instance_valid((ai[0] as Kingdom).castle):
		var enemy: Kingdom = ai[0]
		var ec := enemy.castle
		var known_before: bool = g.can_see(p, ec)
		scout.position = ec.get_center() + Vector2(0, 8.0 * ts)
		fog.update_all()
		var known_now: bool = g.can_see(p, ec) and ec.visible
		scout.position = p.castle.get_center()
		fog.update_all()
		var enemy_unit: Unit = enemy.units[0] if not enemy.units.is_empty() else null
		r.check(TOPIC, not known_before and known_now and g.can_see(p, ec) and ec.visible
				and fog.get_state(p, ec.cell) == FogSystem.EXPLORED
				and (enemy_unit == null or enemy_unit.inside != null or not g.can_see(p, enemy_unit)),
				"Fremde Burg: vorher unbekannt, gesehen, danach zuletzt gesehen (abgedunkelt); Truppen dort unsichtbar")
		# Spion beim Auskundschaften deckt das Zielgebiet auf
		var spy_def := DataDB.get_unit_for_tier(p.faction_id, "spy")
		var spy: Unit = g.unit_system.spawn_unit(p, str(spy_def["id"]), ec.get_center() + Vector2(0, 3.0 * ts))
		var rec: Dictionary = g.spy_system.get_record(spy)
		var edge := ec.get_center() + Vector2(12.0 * ts, 0)
		fog.update_all()
		var before_spy := fog.get_state_at(p, edge)
		rec["mission"] = "scout"
		rec["state"] = "active"
		rec["target_id"] = enemy.id
		fog.update_all()
		r.check(TOPIC, before_spy != FogSystem.VISIBLE and fog.get_state_at(p, edge) == FogSystem.VISIBLE,
				"Auskundschaftender Spion deckt das Zielgebiet auf (12 Kacheln von der Burg)")
		rec["mission"] = ""
		rec["state"] = "idle"
		g.unit_system.remove_unit(spy)
	# Leistung: viele eigene Einheiten
	var many: Array = r.spawn_tier(p, "fighter", 150)
	var total_usec := 0
	for i in 10:
		fog.update_all()
		total_usec += fog.last_update_usec
	print("[smoke] Nebel: %.2f ms je Aktualisierung (%d Einheiten, %d Gebäude, Karte %d²)" % [
			total_usec / 10000.0, p.units.size(), p.buildings.size(), w.width])
	for u in many:
		g.unit_system.remove_unit(u)
	# Speichern und Laden behält Erkundetes und zuletzt gesehene Gebäude
	var explored_before := int(fog.get_counts(p)["explored"]) + int(fog.get_counts(p)["visible"])
	var err: String = await r.save_and_reload("smoke_fog")
	g = r.game
	fog = g.fog_system
	p = g.player
	var explored_after := int(fog.get_counts(p)["explored"]) + int(fog.get_counts(p)["visible"])
	r.check(TOPIC, err.is_empty() and fog.has_grid(p) and absi(explored_after - explored_before) < explored_before * 0.05
			and fog.get_state_at(p, b) != FogSystem.UNEXPLORED,
			"Speichern/Laden: %d → %d erkundete Kacheln %s" % [explored_before, explored_after, err])
	# Alter Spielstand (ohne Nebel-Daten): eigenes Gebiet und Umkreis erkundet, Rest schwarz
	fog.from_dict({})
	fog.rebuild_runtime()
	var cc := w.world_to_cell(p.castle.get_center())
	var margin_cell := cc + Vector2i(roundi(FogSystem.building_sight(p.castle) + 8.0), 0)
	r.check(TOPIC, fog.get_state(p, cc) == FogSystem.VISIBLE and fog.get_state(p, margin_cell) != FogSystem.UNEXPLORED
			and fog.get_state_at(p, b) == FogSystem.UNEXPLORED,
			"Spielstand 1.3.x: Burg-Umkreis erkundet, Rest unerforscht")
	# Option "aus": alles sichtbar wie bisher
	GameSession.options["fog"] = "off"
	fog.rebuild_runtime()
	var wolf2: Unit = g.unit_system.spawn_unit(g.wild, "wolf", p.castle.get_center() + dir * 100.0 * ts)
	fog.update_all()
	r.check(TOPIC, not fog.is_enabled() and g.can_see(p, wolf2) and wolf2.visible and not g.fog_view.visible,
			"Option aus: kein Nebel, ferne Einheiten sichtbar")
	g.unit_system.remove_unit(wolf2)
	GameSession.options.erase("fog")
	fog.rebuild_runtime()
	r.check(TOPIC, fog.is_enabled() and fog.has_grid(p), "Option wieder an: Nebel zurück")


## Liegt der Wolf als Punkt auf der Minikarte?
func _wolf_on_minimap(mm: Minimap, wolf: Unit, w: WorldData) -> bool:
	var rect: Rect2 = mm.call("_map_rect")
	var s := rect.size / Vector2(w.width * w.tile_size, w.height * w.tile_size)
	var p := (rect.position + wolf.position * s).floor()
	var fill: PackedVector2Array = mm.get("_monster_fill")
	for q in fill:
		if q.distance_to(p) <= 1.5:
			return true
	return false
