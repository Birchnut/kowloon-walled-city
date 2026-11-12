#!/usr/bin/env bash
# 실제 렌더링 결과를 PNG 프레임으로 뽑는다 (xvfb + 소프트웨어 GL).
# 사용: tools/shot.sh <scene|""> <out_dir> [frames=30] [WxH=540x960] [key=value ...]
#   scene   : res://view/Sandbox.tscn 처럼. ""이면 메인 씬.
#   (항상 `nosave`가 함께 넘어간다 → 세이브 파일을 건드리지 않음)
#   key=value: 씬에 넘기는 사용자 인자(OS.get_cmdline_user_args()). 예: tod=0.9 angle=1 cut=3
# 결과: <out_dir>/f00000000.png ... (10fps 고정). 마지막 프레임이 보통 가장 쓸모 있다.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
SCENE="${1:-}"; OUT="${2:?out_dir}"; FRAMES="${3:-30}"; RES="${4:-540x960}"
shift $(( $# < 4 ? $# : 4 ))
mkdir -p "$OUT"; rm -f "$OUT"/f*.png "$OUT"/f.wav
ARGS=(--path "$HERE/godot" --rendering-driver opengl3 --resolution "$RES"
      --write-movie "$OUT/f.png" --fixed-fps 10 --quit-after "$FRAMES")
[ -n "$SCENE" ] && ARGS+=("$SCENE")
ARGS+=(-- nosave "$@")
timeout "${SHOT_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" "${ARGS[@]}" 2>&1 \
  | grep -vE "^(Movie Maker|Done recording|[0-9]+ frames|CPU render|GPU render|Encoding time|-+$|OpenGL API|Godot Engine|$)" || true
rm -f "$OUT/f.wav"
ls "$OUT" | tail -1
