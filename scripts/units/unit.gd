## Unit
##
## Eine Einheit auf der Karte: Bewohner, König, Späher, Kämpfer, Heiler oder
## Monster. Jede Einheit kann laufen (UnitSystem), kämpfen (CombatSystem),
## Befehle ausführen (CommandSystem) und – wenn ihr Typ es erlaubt – einen
## Beruf ausüben (WorkSystem).
## Die Node hält nur Zustand und Darstellung; die Logik steckt in den Systemen.
## Lebensbalken und Auswahlringe zeichnet das UnitOverlay für alle Einheiten
## gemeinsam (spart Zeichenaufrufe).
class_name Unit
extends Node2D

## Arbeitszustand (vom WorkSystem gesetzt)
enum State { IDLE, MOVING, GATHERING, BUILDING, WORKING, WAITING }

## Getarnt-Zustand hat sich geändert (Tarnzauber begonnen/beendet)
signal stealth_changed(unit: Unit)

## Buchstaben auf Platzhaltern zeichnen? (Die Kamera schaltet sie beim
## Herauszoomen ab.)
static var show_letters := true
## Aus wessen Sicht wird gezeichnet (Reich des Spielers; -1 = alles sichtbar).
## Getarnte eigene/verbündete Einheiten erscheinen halb durchsichtig, fremde gar nicht.
static var viewer_kingdom_id := -1

## Eindeutige Nummer innerhalb der Partie (für Spielstände)
var uid: int = 0
var kingdom: Kingdom
## Daten des Einheitentyps aus units.json
var type_def: Dictionary = {}
var type_id: String = ""

# --- Bewegung (UnitSystem) ---
## Wegpunkte in Weltpixeln; der letzte ist das Ziel
var path := PackedVector2Array()
var path_index := 0
var moving := false
## Wartet auf eine Wegberechnung (Warteschlange im UnitSystem)
var path_pending := false
var path_target := Vector2.ZERO
## Endziel langer Wege, die in Abschnitten berechnet werden (sonst leer)
var path_final := Vector2.ZERO
var has_path_final := false
## Kacheln, die der aktuelle Weg berührt (für Neuplanung bei neuen Gebäuden)
var path_bounds := Rect2i()
## Höchsttempo beim Marsch in der Gruppe (Kacheln/s, 0 = keins)
var speed_cap := 0.0

# --- Befehle (CommandSystem, siehe CommandSystem.COMMANDS) ---
## "" (frei: Arbeit bzw. Wache), "move", "attack_move", "attack", "hold",
## "defend", "flee", "return", "patrol", "retreat", "rest" (alle in CommandSystem.COMMANDS)
var command: String = ""
## Zielpunkt des Befehls (Bewegung, Formationsplatz, Wachposten)
var command_pos := Vector2.ZERO
## Zählt jeden neuen Befehl (für Gruppenmärsche)
var order_id := 0
## Marsch in Formation: Anführer (Unit) und eigener Abstand zu ihm
var follow_leader: Variant = null
var follow_offset := Vector2.ZERO
## Gebäude, in dem sich die Einheit gerade aufhält (dann unsichtbar), sonst null
var inside: Building = null
## Haltung (CommandSystem.STANCES): "aggressive" verfolgt weit, "defensive" (Standard)
## kehrt nach kurzer Verfolgung auf den Posten zurück, "passive" greift nie selbst an
var stance := CommandSystem.DEFAULT_STANCE
## Patrouille: der andere Wendepunkt (command_pos ist der, zu dem sie gerade läuft)
var patrol_from := Vector2.ZERO

# --- Kampfwerte (aus units.json, mit Modifikatoren; refresh_stats) ---
var role := "worker"
var tier := ""
var max_hp := 1.0
var attack := 0.0
var attack_interval := 1.0
## Reichweite in Kacheln
var attack_range := 0.8
var armor := 0.0
## Sichtweite für selbstständige Angriffe in Kacheln (0 = nie)
var aggro_range := 0.0
## Sichtweite in Kacheln (ab Phase 7: Entdeckung)
var sight := 6.0
## Tempo in Kacheln pro Sekunde (auf Gelände mit Kosten 1.0)
var speed := 2.0
var regen := 0.0
var heal := 0.0
var heal_range := 0.0
## Faktor gegen Gebäude
var building_damage := 1.0
## Faktor gegen Einheiten (Belagerungswaffen schwach, Phase 9)
var unit_damage := 1.0
## Zielwahl: "" (normal), "buildings" (nur Gebäude, Rammbock), "buildings_first" (Katapult)
var target_mode := ""
## Flächenschaden: Radius (Felder) und Anteil des Schadens
var splash_radius := 0.0
var splash_factor := 0.0
## Mechanisch (Belagerungswaffen): wird nicht geheilt
var mechanical := false
## Anteil des ausgeteilten Schadens, der die Einheit heilt (Helden, Wirkungen)
var lifesteal := 0.0
## Faktor auf erlittenen Schaden (ausserhalb der Rüstungsgrenze, z. B. Schutzschild)
var damage_taken := 1.0
# Verhalten (units.json, sonst aus der Rolle abgeleitet)
var flee_on_hit := false
var joins_fights := false
var target_priority := 1.0
var formation_rank := 0
## Zeitlich begrenzte oder dauerhafte Wirkungen (Zauber, Helden, Ereignisse):
## Array von {"id", "key", "mult", "add", "until" (Spielzeit, -1 = dauerhaft), "source"}
var effects: Array = []

# --- Kampfzustand (CombatSystem) ---
var hp := 1.0
## Angriffsziel: Unit oder Building (oder null). Kann bereits gelöscht sein –
## immer zuerst mit is_instance_valid prüfen.
var target: Object = null
var attack_cooldown := 0.0
## Spielzeit des letzten erlittenen Schadens (für Erholung)
var last_damaged_at := -1000.0
## Zeitgeber für Zielsuche und Neuplanung der Verfolgung
var think_timer := 0.0
var repath_timer := 0.0
var last_target_pos := Vector2.ZERO
## Monster: Heimat (Höhle) – uid und Punkt, zu dem sie zurückkehren
var home_uid := 0
var has_home := false
var home_pos := Vector2.ZERO
## Ruhendes Monster (niemand in der Nähe): der Kampftakt überspringt es
var dormant := false
## Ziel verloren: nach der nächsten erfolglosen Suche zurück auf den Posten usw.
var regroup_pending := false
## Getarnt: für fremde Reiche unsichtbar (Tarnzauber, ab Phase 7 Spione).
## Nur lesen – abgeleitet in refresh_stats aus type_def.stealth oder einer
## Wirkung mit key "stealth"; eine Wirkung mit key "revealed" (enttarnter Spion,
## zeitlich begrenzt über MagicSystem.add_unit_effect) hebt die Tarnung auf.
var stealthed := false
## Beschworene Zaubereinheit: verschwindet zu dieser Spielzeit (-1 = nie)
var expires_at := -1.0
## Ursprüngliches Angriffsziel während einer Bresche (uid, 0 = keins)
var resume_target_uid := 0
## Laufzeit (nicht speichern): Grund des letzten gescheiterten Weges ("" | "blocked" |
## "pocket" | "nopath" | "gate"), Ring und Kachel dazu; Zahl der Breschen-Versuche
var path_fail := ""
var path_fail_region := 0
var path_fail_cell := Vector2i(-1, -1)
var breach_tries := 0
## Held: id des Heldeneintrags im Reich (Kingdom.heroes), 0 = kein Held
var hero_id := 0
## Held: Zuschläge je Wert aus Stufe, Talenten und passiven Fähigkeiten:
## Schlüssel -> {"add": Zuschlag, "mult": Faktor, "parts": [[Text, add, mult], …]}.
## Vom HeroSystem gesetzt (abgeleitet, nicht speichern); danach refresh_stats.
var hero_mods: Dictionary = {}
## Zusätzliche Kampfpunkte für den Sieger (Helden: je nach Stufe)
var kill_points_bonus := 0
## Eigener Name (Helden), sonst der Typname
var custom_name := ""
## Befehl "cast" (Held läuft zum Ziel und wirkt dann): Fähigkeit, Ziel (uid) bzw. Punkt
var cast_ability := ""
var cast_target_uid := 0
var cast_pos := Vector2.ZERO

# --- Truppen: Klasse, Erfahrung, Wertepunkte, Aussehen (troops.json, TroopSystem) ---
## Truppenklasse ("infantry", "cavalry", "ranged", "mage", "siege" …), aus units.json (setup)
var unit_class := ""
## Schadenszuschlag gegen Klassen (Klassen-Konter + bonus_vs): Klasse -> Zuschlag.
## Gemeinsames, nur lesbares Dictionary aus DataDB – nie verändern.
var counter_vs: Dictionary = {}
## Anteil der gegnerischen Rüstung, der ignoriert wird (Armbrust), abgeleitet
var armor_pierce := 0.0
## Erfahrung (wird gespeichert)
var vet_xp := 0.0
## Rang 0 (Rekrut) … 4 (Held der Truppe), wird gespeichert
var vet_rank := 0
## Noch nicht verteilte Wertepunkte (wird gespeichert; Helden: aus der Stufe, siehe TroopSystem)
var stat_points := 0
## Verteilte Wertepunkte: Wert ("attack", "hp", "armor", "speed") -> Punkte (wird gespeichert)
var stat_alloc: Dictionary = {}
## Eigenes Aussehen dieser Einheit ("" = wie der Typ im Reich, Kingdom.unit_skins), wird gespeichert
var skin := ""
## Zuschläge aus Rang und Wertepunkten (wie hero_mods), abgeleitet in refresh_stats – nicht speichern
var vet_mods: Dictionary = {}
## Laufzeit (nicht speichern): uid der Einheit, die zuletzt getroffen hat (Erfahrung für den Sieg)
var last_hit_by := 0

# --- Zufriedenheit, Volk und Gelände (Phase 8) ---
## Zufriedenheit 0–100 (nur Bewohner; -1 = noch nicht erfasst). SatisfactionSystem, wird gespeichert.
var satisfaction := -1.0
## Faktor auf die Arbeitsleistung (Zufriedenheit, Seuche, aufgehaltener Überläufer). Abgeleitet (SatisfactionSystem), nicht speichern.
var work_mult := 1.0
## Geländeboni des Volks auf dem Biom unter der Einheit: Schlüssel -> Faktor. Abgeleitet (PeopleSystem), nicht speichern.
## Gemeinsame, nur lesbare Dictionaries – nie verändern.
var terrain_mods: Dictionary = {}
## Biom-Index, für den terrain_mods gilt (-1 = neu bestimmen)
var terrain_biome := -1

# --- Arbeit (WorkSystem) ---
var job_id: String = "idle":
	set(value):
		job_id = value
		queue_redraw()
var state: int = State.IDLE
## Was nach der Ankunft passieren soll ("gather", "dropoff", "build", "work", "wander")
var on_arrive: String = ""
var carry_res: String = "":
	set(value):
		carry_res = value
		queue_redraw()
var carry_amount := 0.0
## Reservierte Vorkommen-Kachel (-1,-1 = keine)
var target_cell := Vector2i(-1, -1)
## Gebäude-Baustelle, an der gearbeitet wird (oder null)
var target_building: Building = null
## Strassenbaustelle, an der gearbeitet wird ((-1,-1) = keine)
var target_road := Vector2i(-1, -1)
var dropoff: Building
var work_building: Building
## Zeitgeber in Spielsekunden (Sammeln, Warten, Umherstreifen ...)
var timer := 0.0
## Teilmengen beim Sammeln (bis eine ganze Einheit erreicht ist)
var work_acc := 0.0
## Aktuelle Tätigkeit als Text, z. B. "fällt Bäume"
var activity: String = ""
## Warum die Einheit nicht arbeiten kann (leer = alles in Ordnung)
var problem: String = ""
## Stand der Vorkommen/Gebäude bei der letzten erfolglosen Suche (-1 = keine)
var failed_search_version := -1

## Ausgewählt (der Ring wird vom UnitOverlay gezeichnet)
var selected := false
## Kurzes Aufblitzen nach einem Treffer (Echtzeit-Sekunden)
var hit_flash := 0.0

var _texture: Texture2D
var _token: Texture2D
var _radius := 13.0
## Aussehen: Tönung einer vorhandenen Grafik ohne eigene Skin-Datei und Abzeichen (oder null)
var _tint := Color.WHITE
var _emblem: Texture2D


func setup(p_type_def: Dictionary, p_kingdom: Kingdom, p_uid: int) -> void:
	uid = p_uid
	type_def = p_type_def
	type_id = str(type_def.get("id", ""))
	kingdom = p_kingdom
	role = str(type_def.get("role", "worker"))
	tier = str(type_def.get("tier", ""))
	_radius = float(type_def.get("radius", 13.0))
	flee_on_hit = bool(type_def.get("flee_on_hit", false))
	joins_fights = bool(type_def.get("joins_fights", false))
	target_priority = float(type_def.get("target_priority", 1.0))
	formation_rank = int(type_def.get("formation_rank", 0))
	target_mode = str(type_def.get("targets", ""))
	splash_radius = float(type_def.get("splash_radius", 0.0))
	splash_factor = float(type_def.get("splash_factor", 0.0))
	mechanical = bool(type_def.get("mechanical", false))
	unit_class = str(type_def.get("class", ""))
	counter_vs = type_def.get("counter_vs", {})
	refresh_look()
	refresh_stats()
	hp = max_hp
	set_process(false)
	queue_redraw()


## Grafik bzw. Platzhalter neu bestimmen (beim Aufbau, nach einem Besitzerwechsel und
## wenn sich das Aussehen ändert). Skin: eigene Datei <einheit>_<skin>.png, sonst die
## Grafik des Typs getönt mit Abzeichen, sonst ein Platzhalter in Skin-Farben.
func refresh_look() -> void:
	var skin_id := get_skin()
	var skin_data := {} if skin_id == "standard" else TroopRules.skin_def(skin_id)
	_tint = Color.WHITE
	_emblem = null
	_texture = null
	if not skin_data.is_empty():
		_texture = Assets.texture(TroopRules.skin_sprite(type_id, skin_id))
	var own_skin_file := _texture != null
	if _texture == null:
		_texture = Assets.texture(DataDB.get_unit_sprite(type_def, kingdom.faction_id))
	_token = null
	var shape := "diamond" if role == "monster" else "circle"
	var color: Color = type_def.get("color", kingdom.color)
	if not skin_data.is_empty() and not own_skin_file:
		var mix := float(DataDB.trp("skins.tint_mix", 0.55))
		var tint: Color = skin_data.get("tint", color)
		_emblem = Assets.emblem(str(skin_data.get("emblem", "")), skin_data.get("trim", Color.WHITE))
		if _texture != null:
			_tint = Color.WHITE.lerp(tint, mix * 0.6)
		else:
			_token = Assets.unit_skin_token(color.lerp(tint, mix), shape, skin_data.get("trim", Color.WHITE))
	if _texture == null and _token == null:
		_token = Assets.unit_token(color, shape)
	queue_redraw()


## Wirksames Aussehen: eigenes, sonst das des Typs im Reich, sonst "standard"
## (nur Skins, die zur Fraktion des Reichs und zum Rang passen)
func get_skin() -> String:
	if kingdom == null or not TroopRules.has_skins(type_def):
		return "standard"
	if not skin.is_empty() and TroopRules.skin_allowed(kingdom, skin) \
			and vet_rank >= int(TroopRules.skin_def(skin).get("min_rank", 0)):
		return skin
	var type_skin := str(kingdom.unit_skins.get(type_id, "standard"))
	if TroopRules.skin_allowed(kingdom, type_skin) and int(TroopRules.skin_def(type_skin).get("min_rank", 0)) <= 0:
		return type_skin
	return "standard"


## Berechnet alle Werte neu: Grundwert aus units.json × Modifikatoren des
## Reichs (Schlüssel und Schlüssel.Stufe) × Wirkungen. Der Anteil der
## Lebenspunkte bleibt erhalten.
func refresh_stats() -> void:
	var ratio := 1.0 if max_hp <= 0.0 else hp / max_hp
	# Rang und Wertepunkte (TroopRules) vor den Werten
	vet_mods = {} if vet_rank <= 0 and stat_alloc.is_empty() else TroopRules.build_mods(vet_rank, stat_alloc)
	max_hp = maxf(_stat("hp"), 1.0)
	attack = _stat("attack")
	attack_interval = maxf(_stat("attack_interval"), 0.1)
	attack_range = _stat("range")
	armor = _stat("armor")
	aggro_range = _stat("aggro_range")
	sight = _stat("sight")
	speed = maxf(_stat("speed"), 0.1)
	regen = _stat("regen")
	heal = _stat("heal")
	heal_range = _stat("heal_range")
	building_damage = _stat("building_damage")
	unit_damage = _stat_from(float(type_def.get("unit_damage", 1.0)), "unit_damage")
	lifesteal = maxf(_stat("lifesteal"), 0.0)
	damage_taken = maxf(_stat_from(1.0, "damage_taken"), 0.05)
	armor_pierce = clampf(_stat("armor_pierce"), 0.0, 1.0)
	hp = clampf(ratio, 0.0, 1.0) * max_hp
	var now_stealthed := (bool(type_def.get("stealth", false)) or _has_effect_key("stealth")) \
			and not _has_effect_key("revealed")
	if now_stealthed != stealthed:
		stealthed = now_stealthed
		update_stealth_look()
		stealth_changed.emit(self)


func _stat(key: String) -> float:
	return _stat_from(float(type_def.get(key, 0.0)), key)


## Wert mit Grundwert value: (value + Zuschläge) × Faktoren aus Wirkungen, Reich und Held
func _stat_from(value: float, key: String) -> float:
	var add := 0.0
	var mult := 1.0
	for e in effects:
		if e.get("key", "") == key:
			add += float(e.get("add", 0.0))
			mult *= float(e.get("mult", 1.0))
	if kingdom != null:
		# Schlüssel, Schlüssel je Stufe ("attack.archer"), je Rolle ("hp@combat" = alle Truppen)
		# und je Truppenklasse ("attack#cavalry", Schmiede)
		mult *= kingdom.mod(key) * kingdom.mod(key + "." + tier) * kingdom.mod(key + "@" + role) \
				* kingdom.mod(key + "#" + unit_class)
	if not hero_mods.is_empty() and hero_mods.has(key):
		var m: Dictionary = hero_mods[key]
		add += float(m.get("add", 0.0))
		mult *= float(m.get("mult", 1.0))
	if not vet_mods.is_empty() and vet_mods.has(key):
		var vm: Dictionary = vet_mods[key]
		add += float(vm.get("add", 0.0))
		mult *= float(vm.get("mult", 1.0))
	if not terrain_mods.is_empty():
		mult *= float(terrain_mods.get(key, 1.0))
	return (value + add) * mult


func _has_effect_key(key: String) -> bool:
	for e in effects:
		if e.get("key", "") == key:
			return true
	return false


## Darstellung der Tarnung (nur Optik): eigene/verbündete halb durchsichtig,
## fremde unsichtbar. Läuft bei Änderung der Tarnung.
func update_stealth_look() -> void:
	if not stealthed:
		modulate.a = 1.0
	elif viewer_kingdom_id < 0 or kingdom == null or kingdom.id == viewer_kingdom_id \
			or kingdom.relations.get(viewer_kingdom_id, "") == "alliance":
		modulate.a = 0.45
	else:
		modulate.a = 0.0


## Wirkung hinzufügen (ersetzt eine gleichnamige) und Werte neu berechnen.
## Zeitlich begrenzte Wirkungen bitte über MagicSystem.add_unit_effect (Ablauf).
func add_effect(effect: Dictionary) -> void:
	remove_effect(str(effect.get("id", "")), false)
	effects.append(effect)
	refresh_stats()


func remove_effect(effect_id: String, refresh: bool = true) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if str(effects[i].get("id", "")) == effect_id:
			effects.remove_at(i)
	if refresh:
		refresh_stats()


func can_work() -> bool:
	return bool(type_def.get("can_work", false))


## Rolle aus units.json: worker, king, combat, support, monster
func get_role() -> String:
	return role


func is_alive() -> bool:
	return hp > 0.0


## Kann angreifen (Schaden > 0)
func is_combatant() -> bool:
	return attack > 0.0


func can_heal() -> bool:
	return heal > 0.0


## Radius des Platzhalters in Pixeln (auch für Abstände im Kampf)
func get_radius() -> float:
	return _radius


func get_command_text() -> String:
	return CommandSystem.get_command_text(command)


func get_display_name() -> String:
	if not custom_name.is_empty():
		return custom_name
	return str(type_def.get("name", "Einheit"))


## Beruf in der Einzahl ("Bergmann" statt "Bergleute")
func get_job_name() -> String:
	var job := DataDB.get_job(job_id)
	return str(job.get("singular", job.get("name", job_id)))


func get_status_text() -> String:
	if not command.is_empty() or not can_work():
		var t := get_command_text()
		if is_instance_valid(target) and target != null and target.has_method("get_display_name"):
			t = ("heilt %s" if can_heal() else "kämpft gegen %s") % target.get_display_name()
		return t if not t.is_empty() else "bereit"
	var text := get_job_name()
	if not activity.is_empty():
		text += " – " + activity
	if carry_amount >= 1.0 and not carry_res.is_empty():
		text += "\nTrägt %d %s" % [int(carry_amount), DataDB.get_resource(carry_res).get("name", carry_res)]
	if not problem.is_empty():
		text += "\n(!) " + problem
	return text


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

## Felder späterer Phasen, die gespeichert werden, sofern es sie gibt (Phase 8
## Zufriedenheit, Phase 9 Rammbock-Ziel, Armeefenster: Haltung und Patrouille, Truppen:
## Erfahrung, Rang, Wertepunkte, Aussehen). Wiederhergestellt über UnitSystem.restore_unit.
const SAVE_OPTIONAL := ["satisfaction", "resume_target_uid", "stance", "patrol_from",
		"vet_xp", "vet_rank", "stat_points", "stat_alloc", "skin"]


## Gespeicherter Zustand: einfache Werte, Verweise als uid, Weg nur wenn unterwegs
func to_dict() -> Dictionary:
	var d := {"uid": uid, "type_id": type_id, "kingdom_id": kingdom.id if kingdom != null else 0,
			"pos": position, "hp": hp, "effects": effects.duplicate(true), "expires_at": expires_at,
			"hero_id": hero_id, "custom_name": custom_name, "command": command, "command_pos": command_pos,
			"order_id": order_id, "target_uid": _uid_of(target), "attack_cooldown": attack_cooldown,
			"last_damaged_at": last_damaged_at, "home_uid": home_uid, "has_home": has_home, "home_pos": home_pos,
			"dormant": dormant, "regroup_pending": regroup_pending, "timer": timer,
			"cast_ability": cast_ability, "cast_target_uid": cast_target_uid, "cast_pos": cast_pos,
			"inside_uid": _uid_of(inside), "job_id": job_id, "carry_res": carry_res, "carry_amount": carry_amount,
			"work_acc": work_acc, "work_uid": _uid_of(work_building), "state": state}
	if follow_leader != null and is_instance_valid(follow_leader):
		d["follows"] = true
	if moving or path_pending:
		# Steht die Einheit und wartet nur auf den nächsten Abschnitt, ist der alte Weg verbraucht:
		# leer speichern (das Laden fordert den Weg ohnehin neu an – so bleibt es idempotent)
		d["motion"] = {"path": path.duplicate() if moving else PackedVector2Array(), "i": path_index if moving else 0,
				"moving": moving, "pending": path_pending, "target": path_target, "final": path_final,
				"has_final": has_path_final}
	for prop in SAVE_OPTIONAL:
		var value: Variant = get(prop)
		if value != null:
			d[prop] = value.duplicate(true) if value is Dictionary else value
	return d


static func _uid_of(o: Variant) -> int:
	if o == null or not is_instance_valid(o):
		return 0
	return int(o.get("uid"))


## Kurz aufblitzen lassen (nach einem Treffer). Färbt nur ein, ohne neu zu zeichnen.
func flash() -> void:
	hit_flash = 0.15
	self_modulate = Color(1.8, 1.5, 1.5)
	set_process(true)


func _process(delta: float) -> void:
	# Trefferblitz abklingen lassen (reine Darstellung, Echtzeit)
	hit_flash -= delta
	if hit_flash <= 0.0:
		hit_flash = 0.0
		self_modulate = Color.WHITE
		set_process(false)


func _draw() -> void:
	var r := _radius
	if _texture != null:
		# Grafik etwas grösser als der Platzhalter, Füsse auf der Position
		var tex_size := r * 3.0
		draw_texture_rect(_texture, Rect2(Vector2(-tex_size * 0.5, -tex_size * 0.75), Vector2(tex_size, tex_size)), false, _tint)
	else:
		# Platzhalter: einmal erzeugte Grafik (Kreis bzw. Raute für Monster)
		var size := r * 2.0 + 4.0
		draw_texture_rect(_token, Rect2(Vector2(-size * 0.5, -size * 0.5 + 1.0), Vector2(size, size)), false)
		if show_letters:
			# Buchstabe: Bewohner zeigen ihren Beruf, alle anderen ihren Typ
			var letter := str(type_def.get("letter", ""))
			if letter.is_empty():
				letter = str(DataDB.get_job(job_id).get("letter", ""))
			if not letter.is_empty():
				SpriteDraw.draw_label(self, letter, Vector2.ZERO, clampi(int(r * 1.1), 10, 22))
		if role == "king":
			# Krone über dem König
			var crown := PackedVector2Array([Vector2(-r * 0.6, -r * 1.05), Vector2(-r * 0.6, -r * 1.45),
					Vector2(-r * 0.3, -r * 1.2), Vector2(0, -r * 1.55), Vector2(r * 0.3, -r * 1.2),
					Vector2(r * 0.6, -r * 1.45), Vector2(r * 0.6, -r * 1.05)])
			draw_colored_polygon(crown, Color(1.0, 0.82, 0.25))
	if _emblem != null:
		# Abzeichen des Aussehens (Skin) oben links
		draw_texture_rect(_emblem, Rect2(Vector2(-r * 1.2, -r * 1.2), Vector2(r * 0.85, r * 0.85)), false)
	if carry_amount >= 1.0 and not carry_res.is_empty():
		var c: Color = DataDB.get_resource(carry_res).get("color", Color.WHITE)
		var box := Rect2(Vector2(r * 0.35, -r * 1.05), Vector2(r * 0.8, r * 0.8))
		draw_rect(box, c, true)
		draw_rect(box, Color(0, 0, 0, 0.7), false, 1.5)
