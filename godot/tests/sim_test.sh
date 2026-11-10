#!/usr/bin/env bash
# 시뮬 시험을 돌린다. 스크립트 오류(SCRIPT ERROR)나 FAIL이 하나라도 있으면 실패(종료 코드 1).
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
export KOWLOON_NOSAVE=1
timeout -k 3 180 "$GODOT" --headless --path "$HERE" --import >/dev/null 2>&1 || true
LOG="$(mktemp)"
timeout -k 3 900 "$GODOT" --headless --path "$HERE" -s res://tests/sim_test.gd >"$LOG" 2>&1
RC=$?
grep -vE "ObjectDB instances|resources still in use|^\s+at: (cleanup|clear)|^Godot Engine|^$" "$LOG"
if grep -qE "SCRIPT ERROR|Parse Error|FAIL" "$LOG" || [ $RC -ne 0 ] || ! grep -q "ALL PASS" "$LOG"; then
  echo "RESULT: FAIL (rc=$RC)"; rm -f "$LOG"; exit 1
fi
# 캐시 차등 퍼즈(짧게): 캐시 켠 시뮬과 sim.no_cache 시뮬이 같은 명령에 같은 상태를 내야 한다. 길게: -- mode=long
timeout -k 3 300 "$GODOT" --headless --path "$HERE" -s res://tests/sim_cache_fuzz.gd -- mode=short seeds=2 days=3 >"$LOG" 2>&1
RC=$?
grep -E "seed|FUZZ|SCRIPT ERROR|Parse Error" "$LOG"
if grep -qE "SCRIPT ERROR|Parse Error" "$LOG" || [ $RC -ne 0 ] || ! grep -q "FUZZ: PASS" "$LOG"; then
  echo "RESULT: FAIL (fuzz rc=$RC)"; rm -f "$LOG"; exit 1
fi
echo "RESULT: PASS"; rm -f "$LOG"
