## EventEffects
##
## Darstellung der Zufallsereignisse auf der Karte (Phase 8): Dürregebiet (ockerfarbener
## Kreis mit gestricheltem Rand und Hitzewellen), Magiesturm (violetter Ring mit
## drehenden Bögen und Wirbelpunkten), Blitze (Zickzack-Linie mit Lichtblitz) und
## kleine grünliche Wolken über Kranken. Optional ersetzt eine Grafik
## res://assets/sprites/effects/event_<art>.png die gezeichnete Fläche.
## Gezeichnet wird nur, wenn ein Gebiet im Kamerarechteck liegt; Animation über
## GameClock.frame_delta (bei Pause still). Reine Darstellung, kein Spielzustand.
class_name EventEffects
extends Node2D

const DROUGHT_COLOR := Color(0.85, 0.64, 0.25)
const STORM_COLOR := Color(0.62, 0.36, 0.85)
const PLAGUE_COLOR := Color(0.5, 0.78, 0.25)
const STRIKE_SECONDS := 0.3
## Höchstens so viele Seuchenwolken
const MAX_CLOUDS := 80

var game: Node
var _time := 0.0
## Blitze: [{"pos", "age", "seed"}]
var _strikes: Array = []
var _textures: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	var es: EventSystem = game.event_system
	es.storm_strike.connect(_on_storm_strike)
	es.event_started.connect(func(_ev: Dictionary) -> void: queue_redraw())
	es.event_ended.connect(func(_ev: Dictionary, _reason: String) -> void: queue_redraw())
	for kind in ["drought", "magic_storm"]:
		var tex: Texture2D = Assets.texture("res://assets/sprites/effects/event_%s.png" % kind)
		if tex != null:
			_textures[kind] = tex


func _on_storm_strike(pos: Vector2) -> void:
	_strikes.append({"pos": pos, "age": 0.0, "seed": randi()})


func _process(_delta: float) -> void:
	if game == null:
		return
	var dt := GameClock.frame_delta
	_time += dt
	for s in _strikes:
		s["age"] = float(s["age"]) + maxf(dt, 0.016)
	_strikes = _strikes.filter(func(s: Dictionary) -> bool: return float(s["age"]) < STRIKE_SECONDS)
	if dt > 0.0 and (not _strikes.is_empty() or _anything_visible()):
		queue_redraw()


func _view_rect() -> Rect2:
	var cam: Camera2D = game.camera
	return cam.get_view_rect() if cam.has_method("get_view_rect") else Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)


func _anything_visible() -> bool:
	var view := _view_rect()
	for ev in game.event_system.active:
		if float(ev["radius"]) > 0.0 and view.grow(float(ev["radius"])).has_point(ev["pos"]):
			return true
		if str(ev["kind"]) == "plague":
			return true
	return false


func _draw() -> void:
	if game == null:
		return
	var view := _view_rect()
	for ev in game.event_system.active:
		var radius := float(ev["radius"])
		var pos: Vector2 = ev["pos"]
		match str(ev["kind"]):
			"drought":
				if view.grow(radius).has_point(pos):
					_draw_drought(pos, radius)
			"magic_storm":
				if view.grow(radius).has_point(pos):
					_draw_storm(pos, radius)
			"plague":
				_draw_plague(ev, view)
	for s in _strikes:
		_draw_strike(s)


func _draw_drought(pos: Vector2, radius: float) -> void:
	if _textures.has("drought"):
		draw_texture_rect(_textures["drought"], Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false,
				Color(1, 1, 1, 0.35))
	else:
		draw_circle(pos, radius, Color(DROUGHT_COLOR, 0.10))
	# Gestrichelter Rand
	var segments := 48
	for i in segments:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		draw_arc(pos, radius, a0, a1, 4, Color(DROUGHT_COLOR, 0.6), 6.0)
	# Hitzewellen
	for i in 12:
		var a := TAU * i / 12.0 + 0.3
		var c := pos + Vector2.from_angle(a) * radius * (0.35 + 0.4 * fmod(i * 0.37, 1.0))
		var pts := PackedVector2Array()
		for j in 7:
			var x := (j - 3) * 18.0
			pts.append(c + Vector2(x, sin(_time * 2.5 + j * 0.9 + i) * 7.0))
		draw_polyline(pts, Color(1.0, 0.8, 0.45, 0.35), 3.0, true)


func _draw_storm(pos: Vector2, radius: float) -> void:
	if _textures.has("magic_storm"):
		draw_texture_rect(_textures["magic_storm"], Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false,
				Color(1, 1, 1, 0.4))
	else:
		draw_circle(pos, radius, Color(STORM_COLOR, 0.08))
	draw_arc(pos, radius, 0.0, TAU, 64, Color(STORM_COLOR, 0.65), 5.0, true)
	for i in 6:
		var start := _time * (0.6 + 0.1 * i) + TAU * i / 6.0
		var r := radius * (0.3 + 0.11 * i)
		draw_arc(pos, r, start, start + 1.2, 16, Color(0.8, 0.6, 1.0, 0.45), 4.0, true)
	for i in 18:
		var a := _time * 0.8 + TAU * i / 18.0
		var r := radius * (0.2 + 0.75 * fmod(i * 0.618, 1.0))
		draw_circle(pos + Vector2.from_angle(a) * r, 6.0, Color(0.85, 0.7, 1.0, 0.55))


func _draw_plague(ev: Dictionary, view: Rect2) -> void:
	var n := 0
	for key in ((ev["data"] as Dictionary).get("infected", {}) as Dictionary):
		if n >= MAX_CLOUDS:
			return
		var u: Variant = game.find_by_uid(int(key))
		if not (u is Unit):
			continue
		var unit: Unit = u
		if unit.inside != null or not view.has_point(unit.position) or not game.can_see(game.player, unit):
			continue
		n += 1
		var c := unit.position + Vector2(0, -unit.get_radius() * 2.2 + sin(_time * 2.0 + unit.uid) * 3.0)
		draw_circle(c, 7.0, Color(PLAGUE_COLOR, 0.55))
		draw_circle(c + Vector2(6, 2), 5.0, Color(PLAGUE_COLOR, 0.5))
		draw_circle(c + Vector2(-6, 2), 5.0, Color(PLAGUE_COLOR, 0.5))


func _draw_strike(s: Dictionary) -> void:
	var pos: Vector2 = s["pos"]
	var t := float(s["age"]) / STRIKE_SECONDS
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"])
	var pts := PackedVector2Array()
	var top := pos + Vector2(rng.randf_range(-40, 40), -420)
	for i in 9:
		var f := i / 8.0
		pts.append(top.lerp(pos, f) + Vector2(rng.randf_range(-22, 22) if i > 0 and i < 8 else 0.0, 0))
	var alpha := 1.0 - t
	draw_polyline(pts, Color(0.75, 0.55, 1.0, alpha * 0.6), 9.0)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, alpha), 3.0)
	draw_circle(pos, 40.0 * (1.0 - t * 0.5), Color(0.9, 0.8, 1.0, alpha * 0.35))
