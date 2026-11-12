#!/usr/bin/env bash
# v0.4 봇 시나리오 전부(두 개씩 나란히 — 이 기계는 2코어) → simulation/reports/<봇>.md/.json → SUMMARY.md
# 사용: simulation/run_all.sh [days=40] [seed=1] [봇…]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
DAYS="${1:-40}"
SEED="${2:-1}"
shift 2 2>/dev/null || true
BOTS=("$@")
if [ ${#BOTS[@]} -eq 0 ]; then
  BOTS=(balanced rush_upgrade export_specialist self_sufficient wood_focus metal_focus concrete_focus space_starved neglect_hazards casual)
fi
export KOWLOON_NOSAVE=1
run() {
  timeout 3600 "$GODOT" --headless --path "$HERE/../godot" -s res://tools/sim_run.gd -- bot="$1" days="$DAYS" seed="$SEED" quiet > "$HERE/reports/$1.log" 2>&1
  echo "$1 done: $(grep -c 'SCRIPT ERROR' "$HERE/reports/$1.log") script errors"
}
i=0
for b in "${BOTS[@]}"; do
  run "$b" &
  i=$((i+1))
  if [ $((i % 2)) -eq 0 ]; then wait; fi
done
wait
python3 "$HERE/make_summary.py"
