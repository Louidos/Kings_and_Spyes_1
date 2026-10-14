#!/usr/bin/env bash
# Balancing-Läufe (Phase 10): echte KI, passiver Spieler, ohne Fenster im Zeitraffer.
# Je Lauf eine Ausgabedatei im Ausgabeordner, am Ende eine Zusammenfassung der
# "[balance]"-Ergebnisse. Läuft parallel (JOBS, Standard 3).
# Aufruf im Projektordner:
#   GODOT=/pfad/zu/godot tests/run_balance.sh [ausgabeordner] [Spielsekunden] [Karte]
# Standard: 3 Spielstunden (10800 s, 18 Spieltage), Karte medium, gut/böse × normal/schwer.
# Umgebung: JOBS (parallel), DIFFS ("normal hard"), TIME_SCALE (4; höher verwirft Schritte), IMMORTAL=1
# (Burg und König des Spielers unverwundbar: Lauf über die volle Dauer, wiederholte Wellen).
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
OUT="${1:-build/balance}"
SECS="${2:-10800}"
SIZE="${3:-medium}"
JOBS="${JOBS:-3}"
DIFFS="${DIFFS:-normal hard}"
mkdir -p "$OUT"
runs=()
for faction in good evil; do
	for diff in $DIFFS; do
		runs+=("$faction $diff")
	done
done
run_one() {
	local faction=$1 diff=$2
	local file="$OUT/${faction}_${diff}_${SIZE}.txt"
	timeout 5400 "$GODOT" --headless res://tests/smoke_test.tscn -- balance=1 faction=$faction difficulty=$diff \
		size=$SIZE seconds=$SECS ai=2 time_scale=${TIME_SCALE:-4} immortal=${IMMORTAL:-0} > "$file" 2>&1
	echo "fertig: $faction $diff (Code $?)"
}
export -f run_one
export GODOT OUT SECS SIZE TIME_SCALE IMMORTAL
printf '%s\n' "${runs[@]}" | xargs -P "$JOBS" -L 1 bash -c 'run_one $0 $1'
fail=0
for f in "$OUT"/*_"$SIZE".txt; do
	echo "== $(basename "$f")"
	grep -E "^\[balance\] (ERGEBNIS|LEISTUNG|LISTEN|Spieler gefallen)" "$f"
	grep -E "^\[balance\] t=.*KI" "$f" | tail -2
	if grep -qE "SCRIPT ERROR|^ERROR:" "$f"; then
		echo "FEHLER in $f:"
		grep -E "SCRIPT ERROR|^ERROR:" -A2 "$f" | head -20
		fail=1
	fi
done
[ $fail -eq 0 ] && echo "OK: Balancing-Läufe ohne Fehler"
exit $fail
