#!/usr/bin/env bash
# 승급 창 외관 미리보기 12장(T2~T5 × wood/metal/concrete)을 실제 뷰로 찍어 잘라 둔다.
# 결과: godot/assets/ui/house_previews/t<계층>_<자재>.png (UI 담당). 사용: tools/ui_house_previews.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/claude/kowloon/tools/godot/godot}"
TMP="$(mktemp -d)"
KOWLOON_NOSAVE=1 "$GODOT" --headless --path "$HERE/godot" -s res://tools/fixtures/make_preview_states.gd -- "$TMP" >/dev/null 2>&1
OUT="$HERE/godot/assets/ui/house_previews"; mkdir -p "$OUT"
for f in "$TMP"/t*_*.json; do
  n="$(basename "$f" .json)"
  "$HERE/tools/shot.sh" res://view/Sandbox.tscn "$TMP/$n" 6 540x960 "state=$f" zoom=2 pan=6,6,2.4 hud=0 markers=0 tod=0.42 >/dev/null 2>&1 || true
  python3 - "$TMP/$n/f00000005.png" "$OUT/$n.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
s = 272
box = ((w - s)//2, (h - s)//2 + 60, (w + s)//2, (h + s)//2 + 60)
im.crop(box).resize((136, 136), Image.NEAREST).save(sys.argv[2])
PY
  echo "$n"
done
rm -rf "$TMP"
