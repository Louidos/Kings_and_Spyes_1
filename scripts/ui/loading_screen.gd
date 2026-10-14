## LoadingScreen
##
## Zeigt den Fortschritt, während die Welt im Hintergrund erzeugt (bzw. ein
## Spielstand geladen) wird.
extends CanvasLayer

@onready var title_label: Label = $Center/VBox/Title

@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var seed_label: Label = %SeedLabel


## title: leer = "Die Welt wird erschaffen", sonst z. B. "Lade Spielstand „…“ …"
func open(seed_text: String, title: String = "") -> void:
	visible = true
	title_label.text = title if not title.is_empty() else "Die Welt wird erschaffen"
	seed_label.text = "Seed: %s" % seed_text
	set_progress(0.0, "Vorbereitung …")


func set_progress(p: float, text: String) -> void:
	progress_bar.value = p * 100.0
	status_label.text = text


func close() -> void:
	visible = false
