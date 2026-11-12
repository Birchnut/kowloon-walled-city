#!/usr/bin/env bash
# 직접 줍기 헤드리스 시험: (1) 장면을 띄워 자동 플레이 한 판 — 스크립트 오류 없음, 결과 전송까지
# (2) 성격별 고정 씨앗 5판씩 — 장부·결과 확인(tests/run_test.gd)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
LOG="$(mktemp)"
fail=0
echo "[1/2] 장면 부팅 + 자동 플레이(careless, 8배속)"
KOWLOON_NOSAVE=1 timeout 600 "$GODOT" --headless --path "$HERE/godot" --fixed-fps 30 --quit-after 9000 \
  res://expedition/RunSandbox.tscn -- nosave auto=careless seed=3 speed=8 > "$LOG" 2>&1
if grep -q "SCRIPT ERROR" "$LOG"; then echo "  스크립트 오류:"; grep -A3 "SCRIPT ERROR" "$LOG" | head -20; fail=1; fi
if grep -q "\[CityLink\] run_result" "$LOG"; then echo "  결과 전송 확인: $(grep -o '"outcome":"[a-z]*"' "$LOG" | head -1)"; else echo "  결과 전송 없음(한 판이 안 끝남)"; fail=1; fi
echo "[2/2] 성격별 5판 + 결과 셋"
KOWLOON_NOSAVE=1 timeout 1200 "$GODOT" --headless --path "$HERE/godot" -s res://tests/run_test.gd > "$LOG" 2>&1
code=$?
grep -E "^  |판 수|FAIL|PASS" "$LOG"
if grep -q "SCRIPT ERROR" "$LOG"; then echo "  스크립트 오류:"; grep -A3 "SCRIPT ERROR" "$LOG" | head -20; fail=1; fi
[ $code -ne 0 ] && fail=1
rm -f "$LOG"
if [ $fail -eq 0 ]; then echo "run_test: 통과"; else echo "run_test: 실패"; fi
exit $fail
