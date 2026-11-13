#!/usr/bin/env bash
# 웹 빌드를 만들어 gh-pages 브랜치에 올린다(GitHub Pages가 그 브랜치를 그대로 내보낸다).
# 사용: tools/deploy_pages.sh [push]   — push를 붙이지 않으면 빌드만 하고 godot/build/web 에 둔다.
# 주소: https://birchnut.github.io/kowloon-walled-city/  (저장소 Settings → Pages → Branch = gh-pages / root)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HERE/tools/godot/godot}"
OUT="$HERE/godot/build/web"
mkdir -p "$OUT"
rm -f "$OUT"/index.*
KOWLOON_NOSAVE=1 "$GODOT" --headless --path "$HERE/godot" --export-release "Web" build/web/index.html 2>&1 \
  | grep -vE "^(Godot Engine|$)" | tail -5 || true
[ -f "$OUT/index.pck" ] && [ -f "$OUT/index.wasm" ] || { echo "웹 빌드 실패: index.pck/index.wasm 없음"; exit 1; }
REV="$(git -C "$HERE" rev-parse --short HEAD)"
echo "build $REV $(date -u +%Y-%m-%dT%H:%MZ)" > "$OUT/version.txt"
ls -la "$OUT" | awk '{print $5, $9}' | grep -E "index\.(pck|wasm|html|js)|version" || true
[ "${1:-}" = "push" ] || { echo "빌드만 함: $OUT"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pages.XXXXXX")"
for f in "$OUT"/*; do
  case "$f" in *.import) ;; *) cp "$f" "$TMP/";; esac
done
touch "$TMP/.nojekyll"
# 옛 모바일판(v0.3) 웹 빌드는 /mobile/ 아래에 그대로 둔다(브랜치 backup/gh-pages-v0.3 에서 꺼낸다).
if git -C "$HERE" rev-parse -q --verify backup/gh-pages-v0.3 >/dev/null; then
  mkdir -p "$TMP/mobile"
  git -C "$HERE" archive backup/gh-pages-v0.3 | tar -x -C "$TMP/mobile"
fi
git -C "$TMP" init -q -b gh-pages
git -C "$TMP" -c user.name="$(git -C "$HERE" config user.name || echo kowloon)" \
    -c user.email="$(git -C "$HERE" config user.email || echo kowloon@example.invalid)" \
    add -A
git -C "$TMP" -c user.name="$(git -C "$HERE" config user.name || echo kowloon)" \
    -c user.email="$(git -C "$HERE" config user.email || echo kowloon@example.invalid)" \
    commit -q -m "웹 빌드 $REV"
git -C "$HERE" fetch -q -f "$TMP" gh-pages:gh-pages
git -C "$HERE" push -q -f origin gh-pages
rm -rf "$TMP"
echo "올림: gh-pages ← 빌드 $REV"
