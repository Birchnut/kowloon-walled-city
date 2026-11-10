#!/usr/bin/env bash
# 봇 전부를 돌리고 비교표를 찍는다.  사용: godot/tools/sim_all.sh [out_dir] [days=30] [seed=1] [bot ...]
# (새 class_name 파일이 생겼으면 먼저 `godot --headless --path godot --import` 로 클래스 캐시를 갱신한다 — 이 스크립트가 해 준다.)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
OUT="${1:-$HERE/../../sim_out}"; DAYS="${2:-30}"; SEED="${3:-1}"
shift $(( $# < 3 ? $# : 3 ))
BOTS=("$@"); [ ${#BOTS[@]} -eq 0 ] && BOTS=(farmer merchant factory absent)
export KOWLOON_NOSAVE=1
timeout -k 3 180 "$GODOT" --headless --path "$HERE" --import >/dev/null 2>&1 || true
mkdir -p "$OUT"
pids=()
for b in "${BOTS[@]}"; do
  rm -rf "${OUT:?}/$b"
  ( timeout -k 3 900 "$GODOT" --headless --path "$HERE" -s res://tools/sim_run.gd -- bot="$b" days="$DAYS" seed="$SEED" out="$OUT/$b" 2>&1 \
      | grep -E "^$b |SCRIPT ERROR|ERROR: \[|at: " | grep -v "resources still in use" || true ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
python3 "$HERE/tools/sim_report.py" "$OUT" "${BOTS[@]}" --maps
