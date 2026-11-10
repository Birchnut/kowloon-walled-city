#!/usr/bin/env python3
"""sim_report — 봇별 30일 결과를 나란히 놓고 본다 (합격 기준 D7: "서로 다르게 생겼는가").

사용:  python3 godot/tools/sim_report.py <out_dir> [bot ...] [--days 1,7,15,30] [--maps] [--md]
  <out_dir>/<bot>/daily.csv, heightmap_day_XX.txt, summary.json 을 읽는다 (tools/sim_run.gd 가 만든 것).
  --maps  마지막 날 높이 지도를 봇별로 나란히 출력
  --md    마지막 날 비교표를 마크다운으로 출력 (SIM_NOTES.md 붙여넣기용)
"""
import csv, json, os, sys, unicodedata


def width(s):
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in str(s))


def pad(s, n):
    s = str(s)
    return s + " " * max(0, n - width(s))


def load(out_dir, bot):
    path = os.path.join(out_dir, bot, "daily.csv")
    with open(path, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def profile(row):
    """한 줄 요약용 파생값."""
    cells = max(1, int(row["cells"]))
    groups = {g: int(row[g]) for g in ("farm", "make", "fun", "vice")}
    mats = {m: int(row[m]) for m in ("scrap", "wood", "sheet", "brick", "concrete")}
    top_g = max(groups, key=groups.get)
    top_m = max(mats, key=mats.get)
    return {
        "업종 1위": "%s %d" % (top_g, groups[top_g]),
        "업종 분포 f/m/u/v": "/".join(str(groups[g]) for g in ("farm", "make", "fun", "vice")),
        "자재 1위": "%s %d%%" % (top_m, round(100 * mats[top_m] / cells)),
        "자재 s/w/sh/b/c": "/".join(str(mats[m]) for m in ("scrap", "wood", "sheet", "brick", "concrete")),
        "주거 판/단/살/쪽": "/".join(row[h] for h in ("shack", "room", "flat", "cage")),
    }


ROWS = [("인구", "population"), ("가구", "households"), ("대문 앞", "waiting"), ("칸 수", "cells"), ("최고 층", "max_height"),
        ("평균 층", "avg_height"), ("바닥 면적", "footprint"), ("비운 터", "keep_columns"), ("돈", "money"), ("식량", "food"),
        ("자재", "materials"), ("위신", "prestige"), ("악명", "notoriety"), ("민심", "morale"), ("뒷골목 금고", "alley_fund"),
        ("전기", "power"), ("쌓인 결재", "cards_pending"), ("호칭", "title"), ("별명", "epithet")]


def table(header, lines, md=False):
    cols = len(header)
    w = [max(width(header[i]), *(width(l[i]) for l in lines)) for i in range(cols)]
    if md:
        print("| " + " | ".join(pad(header[i], w[i]) for i in range(cols)) + " |")
        print("|" + "|".join("-" * (w[i] + 2) for i in range(cols)) + "|")
        for l in lines:
            print("| " + " | ".join(pad(l[i], w[i]) for i in range(cols)) + " |")
    else:
        print("  ".join(pad(header[i], w[i]) for i in range(cols)))
        print("  ".join("-" * w[i] for i in range(cols)))
        for l in lines:
            print("  ".join(pad(l[i], w[i]) for i in range(cols)))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if not args:
        print(__doc__)
        return 1
    out_dir = args[0]
    bots = args[1:] or sorted(d for d in os.listdir(out_dir) if os.path.exists(os.path.join(out_dir, d, "daily.csv")))
    days = [1, 7, 15, 30]
    for i, a in enumerate(sys.argv):
        if a == "--days" and i + 1 < len(sys.argv):
            days = [int(x) for x in sys.argv[i + 1].split(",")]
    md = "--md" in flags
    data = {b: load(out_dir, b) for b in bots}
    last = {b: data[b][-1] for b in bots}

    if not md:
        print("== 성장 곡선 (칸 수 / 인구 / 최고 층) ==")
        lines = []
        for d in days:
            line = ["%d일" % d]
            for b in bots:
                r = next((r for r in data[b] if int(r["day"]) == d), None)
                line.append("%s칸 %s명 %s층" % (r["cells"], r["population"], r["max_height"]) if r else "-")
            lines.append(line)
        table(["날"] + bots, lines)
        print()

    print("== 마지막 날 비교 (%s일) ==" % last[bots[0]]["day"] if not md else "")
    lines = [[label] + [last[b][key] for b in bots] for label, key in ROWS]
    prof = {b: profile(last[b]) for b in bots}
    for key in prof[bots[0]]:
        lines.insert(8, [key] + [prof[b][key] for b in bots])
    table(["항목"] + bots, lines, md)

    if "--maps" in flags and not md:
        print()
        print("== 마지막 날 높이 지도 (숫자 = 층, _ = 비운 터) | 맨 위 칸 용도 ==")
        maps = {}
        for b in bots:
            day = int(last[b]["day"])
            path = os.path.join(out_dir, b, "heightmap_day_%02d.txt" % day)
            maps[b] = open(path, encoding="utf-8").read().splitlines()[1:] if os.path.exists(path) else []
        n = max(len(m) for m in maps.values())
        print("   ".join(pad(b, 27) for b in bots))
        for i in range(n):
            print("   ".join(pad(maps[b][i] if i < len(maps[b]) else "", 27) for b in bots))

    # 서로 얼마나 다른가: 간단한 거리(업종 분포·자재 분포·높이·지표)
    if not md and len(bots) > 1:
        print()
        print("== 서로 다른 정도 (0 = 같음, 1 = 완전히 다름; 업종·자재 분포, 높이, 위신/악명 평균) ==")

        def vec(r):
            cells = max(1, int(r["cells"]))
            biz = max(1, sum(int(r[g]) for g in ("farm", "make", "fun", "vice")))
            return ([int(r[g]) / biz for g in ("farm", "make", "fun", "vice")],
                    [int(r[m]) / cells for m in ("scrap", "wood", "sheet", "brick", "concrete")],
                    [float(r["avg_height"]) / 10, int(r["footprint"]) / 144, int(r["cells"]) / 1440],
                    [float(r["prestige"]) / 100, float(r["notoriety"]) / 100])

        def dist(a, b):
            parts = []
            for x, y in zip(vec(a), vec(b)):
                parts.append(min(1.0, sum(abs(p - q) for p, q in zip(x, y)) / (2 if len(x) > 3 else 1)))
            return sum(parts) / len(parts)

        lines = [[a] + ["%.2f" % dist(last[a], last[b]) if a != b else "-" for b in bots] for a in bots]
        table([""] + bots, lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
