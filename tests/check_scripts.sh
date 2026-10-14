#!/usr/bin/env bash
# Prüft alle GDScript-Dateien auf Fehler UND Warnungen (Warnungen werden dabei
# vorübergehend als Fehler behandelt). Aufruf im Projektordner:
#   GODOT=/pfad/zu/godot tests/check_scripts.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
cleanup() { rm -f override.cfg; }
trap cleanup EXIT
write_override() {
cat > override.cfg <<'CFG'
[debug]

gdscript/warnings/unassigned_variable=2
gdscript/warnings/unassigned_variable_op_assign=2
gdscript/warnings/unused_variable=2
gdscript/warnings/unused_local_constant=2
gdscript/warnings/unused_private_class_variable=2
gdscript/warnings/unused_parameter=2
gdscript/warnings/unused_signal=2
gdscript/warnings/shadowed_variable=2
gdscript/warnings/shadowed_variable_base_class=2
gdscript/warnings/shadowed_global_identifier=2
gdscript/warnings/unreachable_code=2
gdscript/warnings/unreachable_pattern=2
gdscript/warnings/standalone_expression=2
gdscript/warnings/standalone_ternary=2
gdscript/warnings/incompatible_ternary=2
gdscript/warnings/narrowing_conversion=2
gdscript/warnings/integer_division=2
gdscript/warnings/static_called_on_instance=2
gdscript/warnings/redundant_await=2
gdscript/warnings/assert_always_true=2
gdscript/warnings/assert_always_false=2
gdscript/warnings/confusable_identifier=2
gdscript/warnings/confusable_local_declaration=2
gdscript/warnings/confusable_local_usage=2
gdscript/warnings/inference_on_variant=2
gdscript/warnings/native_method_override=2
gdscript/warnings/get_node_default_without_onready=2
gdscript/warnings/onready_with_export=2
gdscript/warnings/int_as_enum_without_cast=2
gdscript/warnings/int_as_enum_without_match=2
gdscript/warnings/deprecated_keyword=2
gdscript/warnings/missing_tool=2
gdscript/warnings/empty_file=2
CFG
}
write_override
# Neue Skripte ohne .uid-Datei: einmal den Editor laufen lassen (erzeugt .uid und Import-Cache)
missing_uid=0
for f in $(find scripts tests -name '*.gd'); do
	[ -f "$f.uid" ] || missing_uid=1
done
if [ $missing_uid -eq 1 ] || [ ! -d .godot ]; then
	rm -f override.cfg
	"$GODOT" --headless --editor --quit >/dev/null 2>&1
	write_override
fi
out=$("$GODOT" --headless res://tests/load_all.tscn 2>&1)
echo "$out" | grep -E "SCRIPT ERROR|ERROR:|at: |\[load_all\]"
if echo "$out" | grep -qE "SCRIPT ERROR|\[load_all\] FEHLER"; then
	exit 1
fi
echo "OK: keine Fehler oder Warnungen"
exit 0
