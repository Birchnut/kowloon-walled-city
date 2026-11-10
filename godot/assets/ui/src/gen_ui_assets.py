#!/usr/bin/env python3
"""구룡성채 UI 픽셀 에셋 생성기 (전부 자작, CC0).

    python3 godot/assets/ui/src/gen_ui_assets.py

- 9-슬라이스:  godot/assets/ui/nine/*.png
- 아이콘 아틀라스: godot/assets/ui/icons.png + godot/ui/IconIndex.gd (이름 → Rect2)
- 기타 스프라이트: godot/assets/ui/misc/*.png

디자인 격자 1px = 화면 논리 2px. 저장할 때 SCALE(2)배 최근접 확대한다.
색을 바꾸려면 아래 팔레트만 고치고 다시 돌린 뒤 `godot --headless --import`.
(테마 색은 ui/dev/build_theme.gd 의 팔레트와 맞춰 둘 것.)
"""
import os
from PIL import Image

SCALE = 2
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, ".."))


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# ── 팔레트: 남흑(먹) 위에 옻칠 빨강 · 간판 금 · 비취 ──
OUT = rgba("05070d")
INK0 = rgba("0b0f1a")
INK1 = rgba("121829")
INK2 = rgba("1b2338")
INK3 = rgba("27314d")
LINE = rgba("3a4670")
PAPER = rgba("efe6d0")
PAPER_HI = rgba("fffaf0")
PAPER2 = rgba("cfc3a4")
PAPER3 = rgba("a89a78")
DIM = rgba("8d97ad")
RED = rgba("c9362e")
RED_HI = rgba("e2574a")
RED_D = rgba("9a2422")
RED_DD = rgba("561519")
GOLD = rgba("e8b54a")
GOLD_HI = rgba("ffe08a")
GOLD_D = rgba("9c742c")
GOLD_DD = rgba("5c4318")
JADE = rgba("3fb090")
JADE_HI = rgba("7fe0bf")
JADE_D = rgba("1f6e5a")
JADE_DD = rgba("123f36")
BROWN = rgba("b5653a")
BROWN_D = rgba("6e3b22")
BLUE = rgba("7f8aa8")
BLUE_D = rgba("46527a")
CLEAR = (0, 0, 0, 0)

CH = {
    ".": CLEAR, "k": OUT, "K": INK0, "w": PAPER, "W": PAPER_HI, "p": PAPER2, "P": PAPER3,
    "g": GOLD, "G": GOLD_D, "y": GOLD_HI, "d": GOLD_DD,
    "r": RED, "R": RED_D, "h": RED_HI, "D": RED_DD,
    "j": JADE, "J": JADE_D, "i": JADE_HI,
    "b": BLUE, "B": BLUE_D, "o": BROWN, "O": BROWN_D, "n": INK2, "N": INK3, "l": LINE, "m": DIM,
}


def save(img, rel):
    path = os.path.join(OUT_DIR, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    img.save(path)
    return path


# ---------------------------------------------------------------- 9-슬라이스
def _mask(w, h, chamfer, top=0):
    m = [[False] * w for _ in range(h)]
    for y in range(top, h):
        for x in range(w):
            dx = min(x, w - 1 - x)
            dy = min(y - top, h - 1 - y)
            if dx + dy >= chamfer:
                m[y][x] = True
    return m


def _erode(m):
    h, w = len(m), len(m[0])
    o = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not m[y][x]:
                continue
            ok = True
            for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + ax, y + ay
                if nx < 0 or ny < 0 or nx >= w or ny >= h or not m[ny][nx]:
                    ok = False
                    break
            o[y][x] = ok
    return o


def box(w, h, fill, border=None, outline=OUT, chamfer=1, lip=0, lip_col=None, hi=None,
        top=0, inner=None, lo=None):
    """outline → border → (inner) → fill. lip = 아래쪽 두께(눌리는 버튼의 턱)."""
    img = Image.new("RGBA", (w, h), CLEAR)
    px = img.load()
    m0 = _mask(w, h, chamfer, top)
    # 얼굴(face)은 lip 만큼 위로 줄어든다
    face = _mask(w, h - lip, chamfer, top)
    face += [[False] * w for _ in range(lip)]
    e0 = _erode(m0) if outline else m0
    f1 = _erode(face) if outline else face
    f2 = _erode(f1) if border else f1
    f3 = _erode(f2) if inner else f2
    for y in range(h):
        for x in range(w):
            if not m0[y][x]:
                continue
            if outline and not e0[y][x]:
                px[x, y] = outline
            elif not f1[y][x]:
                # 얼굴 바깥 = 턱. (얼굴의 아래 외곽선 자리는 outline)
                px[x, y] = lip_col if (lip and not face[y][x]) else outline
                if lip and face[y][x]:
                    px[x, y] = outline
            elif border and not f2[y][x]:
                px[x, y] = border
            elif inner and not f3[y][x]:
                px[x, y] = inner
            else:
                px[x, y] = fill
    # 턱: 얼굴 아래 lip 줄
    if lip:
        for y in range(h - lip - 1, h - 1):
            for x in range(w):
                if e0[y][x] and not f1[y][x] and y >= h - lip - 1:
                    px[x, y] = lip_col
        # 얼굴의 아래 외곽선
        fy = h - lip - 1
        for x in range(w):
            if m0[fy][x] and e0[fy][x] and face[fy][x] and not f1[fy][x]:
                px[x, fy] = outline
    core = f3
    if hi:
        for x in range(w):
            for y in range(h):
                if core[y][x]:
                    px[x, y] = hi
                    break
    if lo:
        for x in range(w):
            for y in range(h - 1, -1, -1):
                if core[y][x]:
                    px[x, y] = lo
                    break
    return img


def nine():
    n = {}
    n["panel"] = box(12, 12, INK1, border=LINE, hi=INK2)
    n["panel_gold"] = box(12, 12, INK1, border=GOLD_D, hi=INK2, chamfer=2)
    n["panel_deep"] = box(12, 12, INK0, border=INK3)
    n["inset"] = box(12, 12, INK0, border=None, outline=INK3, chamfer=1)
    n["plaque"] = box(12, 12, RED_D, border=GOLD, chamfer=2, hi=RED, lo=RED_DD)
    n["plaque_gold"] = box(12, 12, GOLD, border=GOLD_HI, chamfer=2, lo=GOLD_D)
    n["plaque_jade"] = box(12, 12, JADE_D, border=JADE, chamfer=2, hi=JADE, lo=JADE_DD)
    n["plaque_ink"] = box(12, 12, INK2, border=LINE, chamfer=2, hi=INK3)
    n["paper"] = box(12, 14, PAPER, border=PAPER2, lip=2, lip_col=PAPER3, hi=PAPER_HI)
    n["tag"] = box(8, 8, INK3, outline=None, chamfer=1)
    n["tag_gold"] = box(8, 8, GOLD_DD, outline=None, chamfer=1)
    n["tag_red"] = box(8, 8, RED_DD, outline=None, chamfer=1)
    n["tag_jade"] = box(8, 8, JADE_DD, outline=None, chamfer=1)
    n["tag_paper"] = box(8, 8, PAPER2, outline=None, chamfer=1)
    n["badge"] = box(10, 10, RED, border=None, chamfer=3, hi=RED_HI)
    n["sign"] = box(12, 12, RED_D, border=GOLD, inner=RED_DD, chamfer=1, hi=RED)
    n["sign_off"] = box(12, 12, INK2, border=LINE, inner=INK0, chamfer=1)
    n["sign_gold"] = box(12, 12, GOLD_DD, border=GOLD, inner=OUT, chamfer=1)

    # 버튼류: normal(턱 2) / pressed(1px 내려가고 턱 1)
    def btn(name, fill, border, hi, lip_col, chamfer=1, lo=None):
        n[name] = box(12, 14, fill, border=border, lip=2, lip_col=lip_col, hi=hi, chamfer=chamfer, lo=lo)
        n[name + "_down"] = box(12, 14, fill, border=border, lip=1, lip_col=lip_col, hi=None,
                                chamfer=chamfer, top=1, lo=lo)

    btn("btn", INK2, LINE, INK3, INK0)
    btn("btn_red", RED_D, GOLD_D, RED, RED_DD)
    btn("btn_jade", JADE_D, JADE, JADE, JADE_DD)
    btn("btn_gold", GOLD, GOLD_HI, GOLD_HI, GOLD_DD, lo=GOLD_D)
    btn("tile", PAPER, PAPER2, PAPER_HI, JADE_D)          # 마작패: 상아 앞면 + 비취 등
    btn("tile_red", PAPER, PAPER2, PAPER_HI, RED_D)
    n["btn_off"] = box(12, 14, INK1, border=INK3, lip=1, lip_col=INK0, top=1)
    n["btn_ghost"] = box(12, 12, CLEAR, border=None, outline=LINE, chamfer=1)

    # 시트: 위쪽 금선만. 좌우·아래 테두리 없음(화면 끝까지)
    sh = Image.new("RGBA", (8, 12), INK1)
    p = sh.load()
    for x in range(8):
        p[x, 0] = OUT
        p[x, 1] = GOLD_D
        p[x, 2] = GOLD_DD
        p[x, 3] = INK2
    n["sheet"] = sh
    # 상단 띠: 아래쪽 선만
    st = Image.new("RGBA", (8, 12), INK0)
    p = st.load()
    for x in range(8):
        p[x, 9] = INK1
        p[x, 10] = LINE
        p[x, 11] = OUT
    n["strip"] = st
    # 하단 바: 위쪽 선만
    bb = Image.new("RGBA", (8, 12), INK0)
    p = bb.load()
    for x in range(8):
        p[x, 0] = OUT
        p[x, 1] = LINE
        p[x, 2] = INK1
    n["bar"] = bb

    # 모서리 꺾쇠(튜토리얼 강조·선택 표시): 가운데 투명
    def bracket(col, sh_col):
        b = Image.new("RGBA", (16, 16), CLEAR)
        q = b.load()
        for i in range(6):
            for t in range(2):
                for (x, y) in ((i, t), (t, i), (15 - i, t), (15 - t, i), (i, 15 - t), (t, 15 - i),
                               (15 - i, 15 - t), (15 - t, 15 - i)):
                    q[x, y] = col
        return b

    n["bracket"] = bracket(GOLD_HI, OUT)
    n["bracket_red"] = bracket(RED_HI, OUT)
    n["bracket_jade"] = bracket(JADE_HI, OUT)

    # 도장 테두리(가운데 투명, 살짝 닳은 인주)
    seal = Image.new("RGBA", (16, 16), CLEAR)
    q = seal.load()
    for i in range(16):
        for t in range(2):
            q[i, t] = RED
            q[i, 15 - t] = RED
            q[t, i] = RED
            q[15 - t, i] = RED
    for (x, y) in ((0, 0), (15, 0), (0, 15), (15, 15), (5, 0), (11, 15), (0, 9), (15, 4), (6, 1), (15, 5)):
        q[x, y] = CLEAR
    n["seal"] = seal

    # 미터
    mb = Image.new("RGBA", (6, 5), INK0)
    q = mb.load()
    for x in range(6):
        q[x, 0] = OUT
        q[x, 4] = INK3
    for y in range(5):
        q[0, y] = OUT
        q[5, y] = OUT
    q[0, 0] = q[5, 0] = q[0, 4] = q[5, 4] = CLEAR
    n["meter_bg"] = mb

    for name, img in n.items():
        save(img, "nine/%s.png" % name)
    return sorted(n.keys())


# ---------------------------------------------------------------- 아이콘
ICONS = {}


def icon(name, rows):
    rows = [r for r in rows.strip("\n").split("\n")]
    w = len(rows[0])
    for i, r in enumerate(rows):
        if len(r) != w:
            raise SystemExit("icon %s: row %d has width %d (want %d): %r" % (name, i, len(r), w, r))
    for r in rows:
        for c in r:
            if c not in CH:
                raise SystemExit("icon %s: unknown colour %r" % (name, c))
    ICONS[name] = rows


def flip_h(name, src):
    ICONS[name] = [r[::-1] for r in ICONS[src]]


def flip_v(name, src):
    ICONS[name] = ICONS[src][::-1]


# 12×12 — 재고
icon("coin", """
...kkkkkk...
..kggggggk..
.kgyyggggGk.
kgyggggggGGk
kgggkkkkgGGk
kgggkKKkgGGk
kgggkKKkgGGk
kgggkkkkgGGk
kggggggggGGk
.kggggGGGGk.
..kGGGGGGk..
...kkkkkk...
""")
icon("food", """
....w..w....
...w..w.....
....w..w....
...wwwwww...
.kwwwwwwwwk.
kkkkkkkkkkkk
krhrrrrrrrRk
krrrrrrrrRRk
.krrrrrrRRk.
..krrrrRRk..
...kkkkkk...
...kRRRRk...
""")
icon("mat", """
............
.kkkkkkkkkk.
.koooooooyk.
.kOOOOOOOOk.
kkkkkkkkkkkk
kbbbbkoooook
kBBBBkOOOOOk
kkkkkkkkkkkk
kooookbbbbbk
kOOOOkBBBBBk
kkkkkkkkkkkk
............
""")
icon("pop", """
............
....kkkk....
...kwwwwk...
...kwwwwk...
...kwwpwk...
....kkkk....
..kkkkkkkk..
.kwwwwwwwwk.
kwwwwwwwwpwk
kwwwwwwwwpwk
kwwwwwwwwpwk
kkkkkkkkkkkk
""")
icon("bolt", """
............
......ggg...
.....ggg....
....ggg.....
...gggggg...
...gggggg...
.....ggg....
....ggg.....
...ggg......
...gg.......
............
............
""")
# 12×12 — 단색(틴트용)
icon("up", """
............
............
............
.....ww.....
....wwww....
...wwwwww...
..wwwwwwww..
.wwwwwwwwww.
............
............
............
............
""")
flip_v("down", "up")
icon("chev_r", """
............
....ww......
....www.....
.....www....
......www...
.......www..
.......www..
......www...
.....www....
....www.....
....ww......
............
""")
flip_h("chev_l", "chev_r")
icon("close", """
............
.ww......ww.
.www....www.
..www..www..
...wwwwww...
....wwww....
....wwww....
...wwwwww...
..www..www..
.www....www.
.ww......ww.
............
""")
icon("check", """
............
............
.........ww.
........www.
.......www..
.ww...www...
.www.www....
..wwwww.....
...www......
....w.......
............
............
""")
icon("plus", """
............
............
.....ww.....
.....ww.....
.....ww.....
..wwwwwwww..
..wwwwwwww..
.....ww.....
.....ww.....
.....ww.....
............
............
""")
icon("minus", """
............
............
............
............
............
..wwwwwwww..
..wwwwwwww..
............
............
............
............
............
""")
icon("lock", """
............
....wwww....
...ww..ww...
...w....w...
...w....w...
..wwwwwwww..
..wwwwwwww..
..www..www..
..www..www..
..wwwwwwww..
..wwwwwwww..
............
""")
icon("rot_l", """
............
....wwwww...
...ww...ww..
..ww.....ww.
wwwwww....w.
.wwww.....w.
..ww......w.
.........ww.
........ww..
....wwwww...
............
............
""")
flip_h("rot_r", "rot_l")
icon("pause", """
............
............
..www..www..
..www..www..
..www..www..
..www..www..
..www..www..
..www..www..
..www..www..
..www..www..
............
............
""")
icon("play", """
............
...w........
...www......
...wwwww....
...wwwwww...
...wwwwwww..
...wwwwwww..
...wwwwww...
...wwwww....
...www......
...w........
............
""")
icon("move", """
.....ww.....
....wwww....
.....ww.....
..w..ww..w..
.ww..ww..ww.
wwwwwwwwwwww
wwwwwwwwwwww
.ww..ww..ww.
..w..ww..w..
.....ww.....
....wwww....
.....ww.....
""")
icon("house", """
............
.....ww.....
....wwww....
...wwwwww...
..wwwwwwww..
.wwwwwwwwww.
..wwwwwwww..
..www..www..
..www..www..
..www..www..
..www..www..
............
""")
icon("work", """
............
..wwwwww....
.wwwwwwww...
.wwwwwwww...
..wwwwww....
.....www....
......www...
.......www..
........www.
.........ww.
............
............
""")
icon("keep", """
............
.ww.ww.ww.w.
.w........w.
............
.w........w.
.w........w.
............
.w........w.
.w........w.
............
.w.ww.ww.ww.
............
""")
icon("erase", """
............
......www...
.....wwwww..
....wwwwwww.
...wwwwwwww.
..w.wwwwww..
.w...wwww...
.ww...ww....
..ww.ww.....
...www......
.wwwwwwwww..
............
""")
icon("wreck", """
............
.wwwwwww....
.w....ww....
.w....ww....
.w....ww....
.w...wwww...
.w..wwwwww..
.w..wwwwww..
.w..wwwwww..
.w...wwww...
www.........
............
""")
icon("eye", """
............
............
...wwwwww...
..ww....ww..
.ww..ww..ww.
ww..wwww..ww
ww..wwww..ww
.ww..ww..ww.
..ww....ww..
...wwwwww...
............
............
""")
icon("skip", """
............
............
.w...w...ww.
.ww..ww..ww.
.www.www.ww.
.wwwwwwwwww.
.wwwwwwwwww.
.www.www.ww.
.ww..ww..ww.
.w...w...ww.
............
............
""")
icon("dot", """
............
............
............
....wwww....
...wwwwww...
...wwwwww...
...wwwwww...
...wwwwww...
....wwww....
............
............
............
""")
icon("diamond", """
............
.....ww.....
....wwww....
...wwwwww...
..wwwwwwww..
.wwwwwwwwww.
.wwwwwwwwww.
..wwwwwwww..
...wwwwww...
....wwww....
.....ww.....
............
""")
# 7×7 — 시계
icon("sun", """
...y...
.y...y.
..ggg..
y.ggg.y
..ggg..
.y...y.
...y...
""")
icon("moon", """
..WWw..
.Ww....
Ww.....
Ww.....
Ww.....
.Ww....
..WWw..
""")
# 16×16 — 동사
icon("v_plant", """
................
................
...jj.....jjj...
..jjij...jjijj..
..jiijj.jjiijj..
..jjiijjjiijj...
...jjjJjJjjj....
.....jjJJj......
.......JJ.......
.......JJ.......
.......JJ.......
....ooJJooo.....
...ooooooooo....
..oOOOOOOOOOo...
..OOOOOOOOOOO...
................
""")
icon("v_zone", """
................
.............ww.
............wwp.
...........wwp..
..........wwp...
.........wwp....
........GGp.....
.......GGG......
......rrG.......
.....rrr........
....rrr.........
....rr..........
....r...........
..gggggggggggg..
..GGGGGGGGGGGG..
................
""")
icon("v_policy", """
................
...wwwwwwwwww...
..wwwwwwwwwwww..
..wwBBBBBBBBww..
..wwwwwwwwwwww..
..wwBBBBBBwwww..
..wwwwwwwwwwww..
..wwBBBBwwwwww..
..wwwwwwwrrrww..
..wwBBBwrrrrrw..
..wwwwwwrrWrrw..
..wwwwwwrrrrrw..
..wwwwwwwrrrww..
..pwwwwwwwwwwp..
...pppppppppp...
................
""")
icon("v_cards", """
................
......gggg......
.....gyyggg.....
.....gygggG.....
.....ggggGG.....
......gGGG......
......GGGG......
......gggg......
.....gyggGG.....
....gyggggGG....
....GGGGGGGG....
....rrrrrrrr....
....RRRRRRRR....
................
..rr.rrrrrr.rr..
................
""")
icon("v_record", """
................
..DRRRRRRRRRRR..
..DRrrrrrrrrrr..
..DRrrrrrrrrrr..
..DRrrwwwwwwrr..
..DRrrwBBBBwrr..
..DRrrwwwwwwrr..
..DRrrrrrrrrrr..
..DRrrrrrrrrrr..
..DRrrrrrrrrrr..
..DRrrrrrrrgrr..
..DRRRRRRRRRRR..
..DwwwwwwwwwwP..
..DDDDDDDDDDDD..
................
................
""")


def icons():
    names = list(ICONS.keys())
    cell = 16
    cols = 8
    rows_n = (len(names) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * cell, rows_n * cell), CLEAR)
    index = {}
    for i, name in enumerate(names):
        rows = ICONS[name]
        h = len(rows)
        w = len(rows[0])
        ox = (i % cols) * cell
        oy = (i // cols) * cell
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if CH[c][3]:
                    atlas.putpixel((ox + x, oy + y), CH[c])
        index[name] = [ox * SCALE, oy * SCALE, w * SCALE, h * SCALE]
    save(atlas, "icons.png")
    # 아이콘 색인은 GDScript 상수로 낸다(익스포트 필터와 무관하게 항상 포함되도록).
    lines = ["class_name IconIndex", "extends RefCounted",
             "## gen_ui_assets.py 가 만든다. 손으로 고치지 말 것. 이름 → icons.png 안의 영역(px).", "",
             "const ICONS := {"]
    for name in names:
        r = index[name]
        lines.append('\t"%s": Rect2(%d, %d, %d, %d),' % (name, r[0], r[1], r[2], r[3]))
    lines.append("}")
    with open(os.path.normpath(os.path.join(OUT_DIR, "..", "..", "ui", "IconIndex.gd")), "w") as f:
        f.write("\n".join(lines) + "\n")
    return names


# ---------------------------------------------------------------- 기타
def art(rows):
    rows = rows.strip("\n").split("\n")
    w = len(rows[0])
    img = Image.new("RGBA", (w, len(rows)), CLEAR)
    for y, r in enumerate(rows):
        if len(r) != w:
            raise SystemExit("art row width mismatch: %r" % r)
        for x, c in enumerate(r):
            img.putpixel((x, y), CH[c])
    return img


def misc():
    # 수금 말풍선 22×25 (꼬리 포함). bg = 종이, fill = 금(차오르는 양), hot = 떼이는 중(빨간 테)
    shape = """
......kkkkkkkkkk......
....kkXXXXXXXXXXkk....
...kXXXXXXXXXXXXXXk...
..kXXXXXXXXXXXXXXXXk..
.kXXXXXXXXXXXXXXXXXXk.
.kXXXXXXXXXXXXXXXXXXk.
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
kXXXXXXXXXXXXXXXXXXXXk
.kXXXXXXXXXXXXXXXXXXk.
.kXXXXXXXXXXXXXXXXXXk.
..kXXXXXXXXXXXXXXXXk..
...kXXXXXXXXXXXXXXk...
....kkXXXXXXXXXXkk....
......kkkXXXXkkk......
.........kXXk.........
..........kk..........
......................
"""
    rows = shape.strip("\n").split("\n")

    def bubble(fill_col, line_col, body=True):
        img = Image.new("RGBA", (22, len(rows)), CLEAR)
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == "k" and line_col:
                    img.putpixel((x, y), line_col)
                elif c == "X" and body:
                    img.putpixel((x, y), fill_col)
        return img

    save(bubble(INK2, OUT), "misc/bubble_bg.png")
    save(bubble(GOLD_D, None), "misc/bubble_fill.png")
    save(bubble(GOLD, None), "misc/bubble_fill_ready.png")
    save(bubble(CLEAR, GOLD_HI, body=False), "misc/bubble_ring_ready.png")
    save(bubble(CLEAR, RED_HI, body=False), "misc/bubble_ring_hot.png")

    # 시계 문자판 20×20: 원판(틴트용 흰색) / 테 / 성채 실루엣
    disc = Image.new("RGBA", (20, 20), CLEAR)
    ring = Image.new("RGBA", (20, 20), CLEAR)
    cx = cy = 9.5
    for y in range(20):
        for x in range(20):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= 9.2:
                disc.putpixel((x, y), (255, 255, 255, 255))
            if 8.2 < d <= 10.0:
                ring.putpixel((x, y), OUT)
            elif 7.2 < d <= 8.2:
                ring.putpixel((x, y), LINE)
    save(disc, "misc/dial_disc.png")
    save(ring, "misc/dial_ring.png")
    city = art("""
....................
....................
....................
....................
....................
....................
....................
....................
....................
....................
....................
........KK..........
.....KKKKK..KK......
....KKKKKKKKKKK.K...
...KKKKKKKKKKKKKKK..
...KKKKKKKKKKKKKKK..
....KKKKKKKKKKKKK...
.....KKKKKKKKKKK....
.......KKKKKKK......
....................
""")
    save(city, "misc/dial_city.png")

    # 슬라이더 손잡이(작은 마작패)
    save(box(8, 12, PAPER, border=PAPER2, lip=2, lip_col=JADE_D, hi=PAPER_HI), "misc/grabber.png")
    # 시트 손잡이 홈
    grip = Image.new("RGBA", (24, 3), CLEAR)
    for x in range(24):
        grip.putpixel((x, 0), GOLD_DD)
        grip.putpixel((x, 1), GOLD_D)
        grip.putpixel((x, 2), OUT)
    save(grip, "misc/grip.png")
    # 빗금(잠김 표시용 타일, 반복)
    hatch = Image.new("RGBA", (4, 4), CLEAR)
    for i in range(4):
        hatch.putpixel((i, 3 - i), (5, 7, 13, 150))
    save(hatch, "misc/hatch.png")


if __name__ == "__main__":
    n = nine()
    i = icons()
    misc()
    print("nine:", len(n), "icons:", len(i))
