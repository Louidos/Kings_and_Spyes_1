#!/usr/bin/env bash
# Rauchtest für beide Fraktionen: startet je eine Partie ohne Fenster und lässt sie
# im Zeitraffer laufen. Schlägt fehl, wenn ein Skriptfehler auftritt.
# Aufruf im Projektordner:  GODOT=/pfad/zu/godot tests/run_smoke.sh [Spielsekunden] [weitere key=value]
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
SECONDS_SIM="${1:-600}"
shift || true
fail=0
for faction in good evil; do
	out=$(timeout 900 "$GODOT" --headless res://tests/smoke_test.tscn -- faction=$faction seconds=$SECONDS_SIM "$@" 2>&1)
	code=$?
	echo "$out" | grep -E "^\[smoke\]|SCRIPT ERROR|ERROR:|at: " | head -250
	if [ $code -ne 0 ] || echo "$out" | grep -qE "SCRIPT ERROR|^ERROR:"; then
		echo "FEHLER im Rauchtest ($faction, Code $code)"
		fail=1
	fi
done
[ $fail -eq 0 ] && echo "OK: Rauchtest ohne Fehler"
exit $fail
