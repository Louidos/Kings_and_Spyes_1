## SaveCodec
##
## Wandelt Spielstand-Daten verlustfrei in JSON und zurück. Reines JSON verliert
## Typen (int/float, Vector2, Dictionaries mit int-Schlüsseln, gepackte Arrays,
## 64-Bit-Zahlen wie den Zufallszustand). Deshalb werden solche Werte als kleine
## Objekte mit genau einem Schlüssel "#…" abgelegt (Tabelle in der README,
## Abschnitt "Speichern und Laden"):
##   {"#i": "123…"}   int ausserhalb ±2^53
##   {"#f": 3}        ganzzahliger float (auch "inf", "-inf", "nan")
##   {"#v2": [x, y]}, {"#v2i": [x, y]}, {"#v3i": …}, {"#r2": …}, {"#r2i": [x, y, w, h]}, {"#col": [r, g, b, a]}
##   {"#pb": base64}, {"#pi32"/"#pi64"/"#pf32"/"#pf64"/"#pv2": base64}, {"#ps": [...]}
##   {"#d": [[k, v], …]}  Dictionary mit Schlüsseln, die keine Texte sind (oder mit "#" beginnen)
## Bewusst nicht JSON.from_native: dessen Format ist engine-intern.
## Läuft auch im Hintergrund-Thread (nur statische Funktionen, keine Nodes).
class_name SaveCodec
extends RefCounted

## Grösste ganze Zahl, die ein JSON-Leser (double) noch genau darstellt
const MAX_SAFE_INT := 9007199254740991

## Pfade nicht speicherbarer Werte (der Rauchtest prüft: leer)
static var errors: PackedStringArray = PackedStringArray()


## Wert in JSON-taugliche Form bringen (rekursiv)
static func encode(v: Variant, path: String = "") -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return str(v)
		TYPE_INT:
			var i: int = v
			if i > MAX_SAFE_INT or i < -MAX_SAFE_INT:
				return {"#i": str(i)}
			return i
		TYPE_FLOAT:
			var f: float = v
			if is_nan(f):
				return {"#f": "nan"}
			if is_inf(f):
				return {"#f": "inf" if f > 0.0 else "-inf"}
			if f == floorf(f):
				if absf(f) <= float(MAX_SAFE_INT):
					return {"#f": int(f)}
				return {"#f": f}
			# Fast ganzzahlig (z. B. 1.9999999999999998): der JSON-Leser könnte daraus eine
			# ganze Zahl machen – deshalb ausdrücklich als float markieren
			if absf(f - roundf(f)) < 0.000001:
				return {"#f": f}
			return f
		TYPE_VECTOR2:
			var p: Vector2 = v
			return {"#v2": [_num(p.x), _num(p.y)]}
		TYPE_VECTOR2I:
			var pi: Vector2i = v
			return {"#v2i": [pi.x, pi.y]}
		TYPE_VECTOR3I:
			var p3: Vector3i = v
			return {"#v3i": [p3.x, p3.y, p3.z]}
		TYPE_RECT2:
			var r: Rect2 = v
			return {"#r2": [_num(r.position.x), _num(r.position.y), _num(r.size.x), _num(r.size.y)]}
		TYPE_RECT2I:
			var ri: Rect2i = v
			return {"#r2i": [ri.position.x, ri.position.y, ri.size.x, ri.size.y]}
		TYPE_COLOR:
			var c: Color = v
			return {"#col": [_num(c.r), _num(c.g), _num(c.b), _num(c.a)]}
		TYPE_PACKED_BYTE_ARRAY:
			return {"#pb": _b64(v)}
		TYPE_PACKED_INT32_ARRAY:
			return {"#pi32": _b64((v as PackedInt32Array).to_byte_array())}
		TYPE_PACKED_INT64_ARRAY:
			return {"#pi64": _b64((v as PackedInt64Array).to_byte_array())}
		TYPE_PACKED_FLOAT32_ARRAY:
			return {"#pf32": _b64((v as PackedFloat32Array).to_byte_array())}
		TYPE_PACKED_FLOAT64_ARRAY:
			return {"#pf64": _b64((v as PackedFloat64Array).to_byte_array())}
		TYPE_PACKED_VECTOR2_ARRAY:
			return {"#pv2": _b64((v as PackedVector2Array).to_byte_array())}
		TYPE_PACKED_STRING_ARRAY:
			return {"#ps": Array(v as PackedStringArray)}
		TYPE_ARRAY:
			var out: Array = []
			var arr: Array = v
			for i in arr.size():
				out.append(encode(arr[i], "%s[%d]" % [path, i]))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var plain := true
			for key in d:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					plain = false
					break
				if str(key).begins_with("#"):
					plain = false
					break
			if plain:
				var obj := {}
				for key in d:
					obj[str(key)] = encode(d[key], "%s.%s" % [path, str(key)])
				return obj
			var pairs: Array = []
			for key in d:
				pairs.append([encode(key, path + ".<key>"), encode(d[key], "%s.%s" % [path, str(key)])])
			return {"#d": pairs}
	push_error("SaveCodec: nicht speicherbar: %s (%s)" % [path, type_string(typeof(v))])
	errors.append(path)
	return null


## Rückweg von encode (rekursiv)
static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			# JSON kennt nur double: ganzzahlige Werte waren ints (floats stehen als {"#f"})
			var f: float = v
			if f == floorf(f) and absf(f) <= float(MAX_SAFE_INT):
				return int(f)
			return f
		TYPE_ARRAY:
			var out: Array = []
			for item in v:
				out.append(decode(item))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.size() == 1:
				var key := str(d.keys()[0])
				if key.begins_with("#"):
					return _decode_tag(key, d[key])
			var obj := {}
			for key in d:
				obj[key] = decode(d[key])
			return obj
	return v


static func _decode_tag(tag: String, val: Variant) -> Variant:
	match tag:
		"#i":
			return str(val).to_int()
		"#f":
			if val is String:
				match str(val):
					"nan":
						return NAN
					"inf":
						return INF
					"-inf":
						return -INF
				return str(val).to_float()
			return float(val)
		"#v2":
			return Vector2(float(val[0]), float(val[1]))
		"#v2i":
			return Vector2i(int(val[0]), int(val[1]))
		"#v3i":
			return Vector3i(int(val[0]), int(val[1]), int(val[2]))
		"#r2":
			return Rect2(float(val[0]), float(val[1]), float(val[2]), float(val[3]))
		"#r2i":
			return Rect2i(int(val[0]), int(val[1]), int(val[2]), int(val[3]))
		"#col":
			return Color(float(val[0]), float(val[1]), float(val[2]), float(val[3]))
		"#pb":
			return _raw(str(val))
		"#pi32":
			return _raw(str(val)).to_int32_array()
		"#pi64":
			return _raw(str(val)).to_int64_array()
		"#pf32":
			return _raw(str(val)).to_float32_array()
		"#pf64":
			return _raw(str(val)).to_float64_array()
		"#pv2":
			var floats := _raw(str(val)).to_float32_array()
			var out := PackedVector2Array()
			out.resize(floats.size() >> 1)
			for i in out.size():
				out[i] = Vector2(floats[i * 2], floats[i * 2 + 1])
			return out
		"#ps":
			return PackedStringArray(val as Array)
		"#d":
			var d := {}
			for pair in val:
				d[decode(pair[0])] = decode(pair[1])
			return d
	# Unbekanntes Schlüsselwort: als gewöhnliches Objekt behandeln
	return {tag: decode(val)}


static func _b64(bytes: PackedByteArray) -> String:
	return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)


static func _raw(text: String) -> PackedByteArray:
	return PackedByteArray() if text.is_empty() else Marshalls.base64_to_raw(text)


## Daten -> JSON-Text (volle Genauigkeit)
static func to_json(data: Dictionary) -> String:
	return JSON.stringify(encode(data), "", false, true)


## JSON-Text -> Daten ({} bei einem Fehler)
static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("SaveCodec: JSON-Fehler in Zeile %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	var result: Variant = decode(json.data)
	return result if result is Dictionary else {}


## float für Vektoren: ganzzahlige Werte als int-Zahl (spart Platz), decode liest float()
static func _num(f: float) -> Variant:
	if f == floorf(f) and absf(f) < 1e15:
		return int(f)
	return f


## Tiefer Vergleich inklusive Typen (für den Rauchtest). Leeres Ergebnis = gleich.
## tolerance: erlaubte Abweichung bei Kommazahlen (relativ, mindestens absolut).
static func deep_diff(a: Variant, b: Variant, path: String, out: PackedStringArray, max_items: int = 40,
		tolerance: float = 0.0, ignore: PackedStringArray = PackedStringArray()) -> void:
	if out.size() >= max_items:
		return
	for pattern in ignore:
		if path.match(pattern):
			return
	if typeof(a) != typeof(b):
		# int/float-Mischungen gelten bei Toleranz als gleich, wenn der Wert passt
		if tolerance > 0.0 and (a is int or a is float) and (b is int or b is float):
			if absf(float(a) - float(b)) <= maxf(tolerance, absf(float(a)) * tolerance):
				return
		out.append("%s: Typ %s ≠ %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			for key in da:
				if not db.has(key):
					out.append("%s.%s fehlt" % [path, str(key)])
				else:
					deep_diff(da[key], db[key], "%s.%s" % [path, str(key)], out, max_items, tolerance, ignore)
				if out.size() >= max_items:
					return
			for key in db:
				if not da.has(key):
					out.append("%s.%s zu viel" % [path, str(key)])
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				out.append("%s: Länge %d ≠ %d" % [path, aa.size(), ab.size()])
				return
			for i in aa.size():
				deep_diff(aa[i], ab[i], "%s[%d]" % [path, i], out, max_items, tolerance, ignore)
		TYPE_FLOAT:
			var fa: float = a
			var fb: float = b
			if is_nan(fa) and is_nan(fb):
				return
			if fa != fb and absf(fa - fb) > maxf(tolerance, absf(fa) * tolerance):
				out.append("%s: %s ≠ %s" % [path, str(fa), str(fb)])
		TYPE_VECTOR2:
			var va: Vector2 = a
			var vb: Vector2 = b
			if va.distance_to(vb) > maxf(tolerance, 0.0) and va != vb:
				out.append("%s: %s ≠ %s" % [path, str(va), str(vb)])
		_:
			if a != b:
				out.append("%s: %s ≠ %s" % [path, str(a).left(80), str(b).left(80)])
