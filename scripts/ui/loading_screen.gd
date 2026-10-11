## LoadingScreen
##
## Zeigt den Fortschritt, während die Welt im Hintergrund erzeugt wird.
extends CanvasLayer

@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var seed_label: Label = %SeedLabel


func open(seed_text: String) -> void:
	visible = true
	seed_label.text = "Seed: %s" % seed_text
	set_progress(0.0, "Vorbereitung …")


func set_progress(p: float, text: String) -> void:
	progress_bar.value = p * 100.0
	status_label.text = text


func close() -> void:
	visible = false
