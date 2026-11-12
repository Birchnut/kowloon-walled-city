#!/usr/bin/env bash
# v0.4 봇 시나리오 전부를 씨앗 여러 개로(두 개씩 나란히 — 이 기계는 2코어) → simulation/reports/seed<N>/<봇>.md/.json → SUMMARY.md
# 사용: simulation/run_all.sh [days=40] ["씨앗들"="1 2 3"] [봇…]
#   SET="floors.threshold:0.7" simulation/run_all.sh …  → config 덮어쓰기 실험(결과 폴더는 OUT=… 로 따로 두는 것을 권함)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
DAYS="${1:-40}"
SEEDS="${2:-1 2 3}"
shift 2 2>/dev/null || true
BOTS=("$@")
if [ ${#BOTS[@]} -eq 0 ]; then
  BOTS=(balanced direct_runner rush_upgrade export_specialist self_sufficient wood_focus metal_focus concrete_focus space_starved neglect_hazards casual)
fi
OUT="${OUT:-$HERE/reports}"
SET="${SET:-}"
export KOWLOON_NOSAVE=1
run() {
  local b="$1" s="$2"
  mkdir -p "$OUT/seed$s"
  timeout 5400 "$GODOT" --headless --path "$HERE/../godot" -s res://tools/sim_run.gd -- bot="$b" days="$DAYS" seed="$s" out="$OUT/seed$s/$b.md" set="$SET" quiet > "$OUT/seed$s/$b.log" 2>&1
  echo "seed$s $b done: $(grep -c 'SCRIPT ERROR' "$OUT/seed$s/$b.log") script errors"
}
i=0
for s in $SEEDS; do
  for b in "${BOTS[@]}"; do
    run "$b" "$s" &
    i=$((i+1))
    if [ $((i % 2)) -eq 0 ]; then wait; fi
  done
done
wait
python3 "$HERE/make_summary.py" "$OUT"
