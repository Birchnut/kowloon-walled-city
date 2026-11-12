#!/usr/bin/env bash
# 직접 줍기 화면을 실제 창 크기 PNG로 뽑는다(tools/shot.sh의 무비는 이 프로젝트에서 540x960로 고정이라 따로 둔다).
# 사용: godot/tests/run_shot.sh <out_dir> <frames> [WxH=1920x1080] [key=value ...]
#   10fps 고정 시간. png_every=N(기본 5) 또는 png_at=3,10,40 로 저장할 프레임을 고른다.
#   예: godot/tests/run_shot.sh /tmp/r 300 1920x1080 seed=3 auto=average png_every=20 mute
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
OUT="${1:?out_dir}"; FRAMES="${2:-100}"; RES="${3:-1920x1080}"
shift $(( $# < 3 ? $# : 3 ))
mkdir -p "$OUT"; rm -f "$OUT"/f*.png
EXTRA=("$@")
has_every=0; for a in "${EXTRA[@]:-}"; do case "$a" in png_every=*|png_at=*) has_every=1;; esac; done
[ $has_every = 0 ] && EXTRA+=(png_every=5)
timeout 900 xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path "$HERE/godot" --rendering-driver opengl3 \
  --resolution "$RES" --fixed-fps 10 --quit-after "$FRAMES" res://expedition/RunSandbox.tscn \
  -- nosave png_dir="$OUT" "${EXTRA[@]}" 2>&1 \
  | grep -vE "^(Godot Engine|OpenGL API|$)|V-Sync|set_use_vsync|leaked at exit|resources still in use|at: (cleanup|clear) " || true
ls "$OUT" | tail -1
