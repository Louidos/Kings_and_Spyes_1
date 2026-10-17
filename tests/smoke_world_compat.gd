## Rauchtest Weltgenerator und alte Spielstände: Spielstände speichern nur die Änderungen an der
## Welt und erzeugen sie beim Laden aus dem Seed neu (WorldData.compute_fingerprint). Gleicher Seed
## muss deshalb dieselbe Welt wie in 1.1.0 ergeben, sonst laden alte Spielstände nicht mehr. Ändert
## sich die Welt absichtlich, WorldGenerator.VERSION erhöhen und die Werte hier erneuern.
extends RefCounted

const TOPIC := "Welt"

## Fingerabdrücke aus Version 1.1.0 (Seed, Kartengrösse)
const EXPECTED := {
	"4242:256": {"biomes": "b700654b8b9086d0fd362aa1299bc84e", "deposit_amount": "1460d49c5a0d7bdaac1ce51e689d0023",
			"deposit_type": "c6911efa097f1bac7afd39eb2e75c8f6", "sites": 14, "size": 256, "start_cell": Vector2i(216, 216)},
}


func run(r: Node) -> void:
	for key in EXPECTED:
		var parts := str(key).split(":")
		var w: WorldData = WorldGenerator.new().generate(int(parts[0]), int(parts[1]))
		var fp := w.compute_fingerprint()
		var want: Dictionary = EXPECTED[key]
		var diff := PackedStringArray()
		for k in want:
			if str(fp.get(k)) != str(want[k]):
				diff.append(str(k))
		r.check(TOPIC, diff.is_empty(), "Welt aus Seed %s wie in 1.1.0 (alte Spielstände laden)%s" % [key,
				"" if diff.is_empty() else " – abweichend: " + ", ".join(diff)])
