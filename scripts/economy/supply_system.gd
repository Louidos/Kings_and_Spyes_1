## SupplySystem
##
## Versorgung (Phase 9): Einheiten von Spieler und KI erholen sich nur im oder nahe am
## eigenen bzw. verbündeten Gebiet oder entlang offener eigener Handelswege. Fern davon
## bekommen verletzte Einheiten die Wirkung "supply:regen" (Erholung × 0) über das
## MagicSystem; sie wird alle scan_seconds verlängert und fällt weg, sobald die Einheit
## wieder versorgt ist. Heiler heilen weiter.
##
## Zustand: keiner (abgeleitet). Laufzeit: _chunks (Reich-id -> Array je 8×8-Feld:
## 1 = Gebiet des Reichs im Feld), _corridors (Reich-id -> PackedByteArray:
## Feld nahe einem offenen Handelsweg), _acc.
class_name SupplySystem
extends Node

const EFFECT_ID := "supply:regen"
const NOTIFY_AREA := 20

var game: Node
var world: WorldData

var _chunks: Dictionary = {}
var _corridors: Dictionary = {}
var _chunk := 8
var _cw := 1
var _ch := 1
var _acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_chunk = maxi(int(DataDB.trade("supply.chunk", 8)), 1)
	_cw = ceili(float(world.width) / _chunk)
	_ch = ceili(float(world.height) / _chunk)
	# Vor den ersten Siedlungen verbinden (Gebiet wird beim Gründen berechnet)
	game.territory.changed.connect(_on_territory_changed)
	var trs: Variant = game.get("trade_route_system")
	if trs != null:
		(trs as TradeRouteSystem).routes_changed.connect(_on_routes_changed)
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Ist die Einheit versorgt? (nur Spieler und KI können unversorgt sein)
func is_supplied(u: Unit) -> bool:
	var k := u.kingdom
	if k == null or (k.controller != "player" and k.controller != "ai"):
		return true
	var cell := world.world_to_cell(u.position)
	var owner_id := world.get_owner(cell)
	if owner_id == k.id or (owner_id != 0 and k.relations.get(owner_id, "") == "alliance"):
		return true
	var cx := clampi(floori(float(cell.x) / _chunk), 0, _cw - 1)
	var cy := clampi(floori(float(cell.y) / _chunk), 0, _ch - 1)
	var corridor: PackedByteArray = _corridors.get(k.id, PackedByteArray())
	if not corridor.is_empty() and corridor[cy * _cw + cx] != 0:
		return true
	var ids: Array = [k.id]
	for other_id in k.relations:
		if k.relations[other_id] == "alliance":
			ids.append(int(other_id))
	var r := ceili(float(DataDB.trade("supply.radius_tiles", 12)) / _chunk)
	for kid in ids:
		if not _chunks.has(kid):
			continue
		var chunks: Array = _chunks[kid]
		for y in range(maxi(cy - r, 0), mini(cy + r, _ch - 1) + 1):
			var row := y * _cw
			for x in range(maxi(cx - r, 0), mini(cx + r, _cw - 1) + 1):
				if chunks[row + x] != 0:
					return true
	return false


## Unversorgte (verletzte) Einheiten eines Reichs
func get_unsupplied(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for u in k.units:
		if _has_effect(u):
			list.append(u)
	return list


static func _has_effect(u: Unit) -> bool:
	for e in u.effects:
		if str(e.get("id", "")) == EFFECT_ID:
			return true
	return false


# ---------------------------------------------------------------------------
# Raster
# ---------------------------------------------------------------------------

## Gebiet geändert: alle Felder im geänderten Rechteck neu zählen (alle Reiche dort)
func _on_territory_changed(_kingdom_id: int, _bbox: Rect2i, dirty: Rect2i) -> void:
	_recount(dirty)


func _recount(rect: Rect2i) -> void:
	rect = rect.intersection(Rect2i(0, 0, world.width, world.height))
	if not rect.has_area():
		return
	var x0 := floori(float(rect.position.x) / _chunk)
	var y0 := floori(float(rect.position.y) / _chunk)
	var x1 := floori(float(rect.end.x - 1) / _chunk)
	var y1 := floori(float(rect.end.y - 1) / _chunk)
	var terr := world.territory
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var owners := {}
			for y in range(cy * _chunk, mini((cy + 1) * _chunk, world.height)):
				var row := y * world.width
				for x in range(cx * _chunk, mini((cx + 1) * _chunk, world.width)):
					var o := terr[row + x]
					if o != 0:
						owners[o] = true
			var i := cy * _cw + cx
			for kid in owners:
				_ensure(int(kid))
			for kid in _chunks:
				var arr: Array = _chunks[kid]
				arr[i] = 1 if owners.has(kid) else 0


func _ensure(kid: int) -> void:
	if not _chunks.has(kid):
		var arr: Array = []
		arr.resize(_cw * _ch)
		arr.fill(0)
		_chunks[kid] = arr


## Korridore neben offenen eigenen Handelswegen neu
func _on_routes_changed(k: Kingdom) -> void:
	if k == null:
		return
	var trs: Variant = game.get("trade_route_system")
	if trs == null:
		return
	var arr := PackedByteArray()
	arr.resize(_cw * _ch)
	var r := ceili(float(DataDB.trade("supply.corridor_tiles", 6)) / _chunk)
	var any := false
	for p in (trs as TradeRouteSystem).get_corridor_points(k):
		var c := world.world_to_cell(p)
		var cx := floori(float(c.x) / _chunk)
		var cy := floori(float(c.y) / _chunk)
		for y in range(maxi(cy - r, 0), mini(cy + r, _ch - 1) + 1):
			for x in range(maxi(cx - r, 0), mini(cx + r, _cw - 1) + 1):
				arr[y * _cw + x] = 1
				any = true
	if any:
		_corridors[k.id] = arr
	else:
		_corridors.erase(k.id)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not bool(DataDB.trade("supply.enabled", true)):
		return
	_acc += dt
	var scan := maxf(float(DataDB.trade("supply.scan_seconds", 2)), 0.2)
	if _acc < scan:
		return
	_acc = 0.0
	var now := GameClock.game_time
	var magic: MagicSystem = game.magic_system
	for k in game.kingdoms:
		var kingdom: Kingdom = k
		if kingdom.controller != "player" and kingdom.controller != "ai":
			continue
		var cut_pos := Vector2.ZERO
		var cut_count := 0
		for u in kingdom.units:
			var had := _has_effect(u)
			if u.hp <= 0.0 or u.hp >= u.max_hp or u.inside != null or u.mechanical:
				if had:
					magic.remove_unit_effects(u, "supply")
				continue
			if is_supplied(u):
				if had:
					magic.remove_unit_effects(u, "supply")
				continue
			magic.add_unit_effect(u, {"id": EFFECT_ID, "key": "regen", "mult": 0.0, "until": now + 2.5 * scan,
					"source": "supply"}, true)
			if not had:
				cut_count += 1
				cut_pos = u.position
		if cut_count > 0 and kingdom.is_player:
			_notify(kingdom, cut_pos)


func _notify(k: Kingdom, pos: Vector2) -> void:
	var c := world.world_to_cell(pos)
	var key := "supply_warned:%d:%d" % [floori(float(c.x) / NOTIFY_AREA), floori(float(c.y) / NOTIFY_AREA)]
	var now := GameClock.game_time
	if now - float(k.flags.get(key, -1.0e9)) < float(DataDB.trade("supply.notify_interval", 300)):
		return
	k.flags[key] = now
	var owner_k: Kingdom = game.get_kingdom(world.get_owner(c))
	var where := ("bei %s" % owner_k.display_name) if owner_k != null and owner_k != k else "im Niemandsland"
	k.notify("Truppen %s ohne Versorgung: keine Erholung fern vom eigenen Gebiet (Handelsweg oder Rückzug hilft)." % where,
			"warning", pos)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


## Raster aus TerritorySystem.kingdom_bbox je Reich und Korridore neu
func rebuild_runtime() -> void:
	_chunks.clear()
	_corridors.clear()
	_acc = 0.0
	for k in game.kingdoms:
		var bbox := TerritorySystem.kingdom_bbox(k, world)
		if bbox.has_area():
			_recount(bbox)
		_on_routes_changed(k)
