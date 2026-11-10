#!/usr/bin/env python3
"""simulation/reports/*.json(시나리오 봇 요약 행)에서 SUMMARY.md를 만든다.
사용: python3 simulation/make_summary.py   (먼저 봇들을 돌린다: godot/tools/sim_run.gd)
손으로 쓰는 해석·바꾼 것은 simulation/summary_notes.md — 그대로 아래에 붙는다.
"""
import json
import os
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
REP = os.path.join(HERE, "reports")
ORDER = ["balanced", "rush_upgrade", "export_specialist", "self_sufficient", "wood_focus", "metal_focus", "concrete_focus",
         "space_starved", "short_frequent", "twice_a_day", "long_absence", "t3_to_t5_rush"]


def hm(s):
    if s is None or s < 0:
        return "—"
    h = int(s // 3600)
    m = int((s % 3600) // 60)
    if h >= 24:
        return f"{h // 24}일{h % 24}h"
    return f"{h}h{m:02d}" if h else f"{m}분"


def main():
    rows = {}
    import sys
    rep = sys.argv[1] if len(sys.argv) > 1 else REP
    for p in glob.glob(os.path.join(rep, "*.json")):
        name = os.path.basename(p)[:-5]
        if name.startswith("core_"):
            continue
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        if "firsts" in d:
            rows[name] = d
    bots = [b for b in ORDER if b in rows] + sorted(b for b in rows if b not in ORDER)
    L = ["# 시나리오 묶음 요약(브리프 §20.1)", "",
         "자동 생성: `python3 simulation/make_summary.py` ← `simulation/reports/<봇>.json`. 봇마다 자세한 리포트는 `simulation/reports/<봇>.md`.",
         "모든 봇: **디버그 자재 없음**(세 계열 자재는 탐험 + 건재상 계약), 접속 중 실제 600초 = 1경제일, 접속 사이는 미접속 규칙(0.25배·최대 8시간·유예 정지), 탐험은 실제 시계.", ""]
    L += ["## 비교표(실제 시간 = 게임 시작부터)", "",
          "| 봇 | 패턴 | 접속(시간) | 경제일 | 인구 T1/T2/T3/T4/T5 | 세수/일 | 금고 끝(최저) | 층 | 목표 | 연구 | 첫 T2 | 첫 T3 | 첫 T4 | 첫 T5 | 2층 | 회관 | 최종 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for b in bots:
        r = rows[b]
        f = r["firsts"]
        L.append(f"| {r['name']} | {r['pattern']} | {r['online_h']} | {r['econ_days']} | {'/'.join(str(x) for x in r['pop'])} | {r['tax_rate']:.0f} | "
                 f"{r['money']:,} ({r['min_money']}) | {r['floors']} | {r['goals']}/21 | {r['research']}/12 | {hm(f.get('first_upgrade_t2_day'))} | {hm(f.get('first_upgrade_t3_day'))} | "
                 f"{hm(f.get('first_upgrade_t4_day'))} | {hm(f.get('first_upgrade_t5_day'))} | {hm(f.get('floor_2_day'))} | {hm(f.get('goal_g_hall_day'))} | {hm(f.get('goal_g_final_day'))} |")
    L += ["", "| 봇 | 첫 주민 | 첫 파견 | 첫 수령 | 첫 전기 | 팀 가동률 | 수령 대기 | 자재 대기(주거·시간) | 접속당 결정 | 접속당 명령 | 목재/철제/콘크리트 획득 | 수입 몫 | 외부 물/전기 | 단속 |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for b in bots:
        r = rows[b]
        f = r["firsts"]
        fg = r["family_got"]
        ex = r["external"]
        L.append(f"| {r['name']} | {hm(f.get('first_resident_day'))} | {hm(f.get('first_send_unix'))} | {hm(f.get('first_claim_unix'))} | {hm(f.get('first_power_day'))} | "
                 f"{int(r['team_util'] * 100)}% | {int(r['team_wait'] * 100)}% | {r['mat_wait_h']} | {r['dec_per_session']} | {r['cmds_per_session']} | "
                 f"{fg['wood']}/{fg['metal']}/{fg['concrete']} | {int(ex['goods_import_share'] * 100)}% | {int(ex['water_ext_share'] * 100)}%/{int(ex['power_ext_share'] * 100)}% | {r['raids']} |")
    # 실제 하루마다 점수(세수/일)
    nd = max(len(rows[b]["rows"]) for b in bots)
    for title, fn in [("세수(₩/경제일, 하루 끝)", lambda row: f"{row['tax_rate']:.0f}"), ("인구(하루 끝)", lambda row: str(sum(row["pop"]))),
                      ("금고(₩, 하루 끝)", lambda row: f"{row['money']:,}"), ("목표 달성 수", lambda row: str(row["goals"]))]:
        L += ["", f"## 실제 하루마다 {title}", "", "| 봇 | " + " | ".join(f"{i}일" for i in range(1, nd + 1)) + " |", "|---|" + "---|" * nd]
        for b in bots:
            r = rows[b]
            vals = [fn(row) for row in r["rows"]]
            L.append(f"| {r['name']} | " + " | ".join(vals) + " |")
    # 패턴 비교
    if "short_frequent" in rows and "twice_a_day" in rows:
        a = rows["short_frequent"]["rows"]
        t = rows["twice_a_day"]["rows"]
        L += ["", "## 짧은 빈번 접속 vs 하루 2회(같은 균형형 전략)", "", "| 실제일 | 짧게 자주 세수 | 하루 2회 세수 | 배수 | 짧게 자주 인구 | 하루 2회 인구 |", "|---|---|---|---|---|---|"]
        for i in range(min(len(a), len(t))):
            ra = a[i]["tax_rate"]
            rt = t[i]["tax_rate"]
            L.append(f"| {i + 1} | {ra:.0f} | {rt:.0f} | {ra / rt if rt else 0:.2f}× | {sum(a[i]['pop'])} | {sum(t[i]['pop'])} |")
    # 자재 집중형
    fam = [b for b in ["wood_focus", "metal_focus", "concrete_focus"] if b in rows]
    if fam:
        L += ["", "## 자재 집중형 비교", "", "| 봇 | 첫 T3 | 첫 T4 | 첫 T5 | 끝 세수/일 | 끝 인구 | 그 자재 획득 | 자재 대기(주거·시간) |", "|---|---|---|---|---|---|---|---|"]
        for b in fam:
            r = rows[b]
            f = r["firsts"]
            m = b.split("_")[0]
            L.append(f"| {r['name']} | {hm(f.get('first_upgrade_t3_day'))} | {hm(f.get('first_upgrade_t4_day'))} | {hm(f.get('first_upgrade_t5_day'))} | {r['tax_rate']:.0f} | {sum(r['pop'])} | {r['family_got'][m]} | {r['mat_wait_h']} |")
    # 장기 부재
    if "long_absence" in rows:
        r = rows["long_absence"]
        L += ["", "## 장기 부재 복귀(2일 접속 → 3일 부재 → 복귀)", "", "| 실제일 | 경제일 | 인구 | 세수/일 | 금고 | 행복 |", "|---|---|---|---|---|---|"]
        for row in r["rows"]:
            L.append(f"| {row['day']} | {row['econ']} | {sum(row['pop'])} | {row['tax_rate']:.0f} | {row['money']:,} | {row['happiness']} |")
    notes = os.path.join(HERE, "summary_notes.md")
    if os.path.exists(notes) and rep == REP:
        with open(notes, encoding="utf-8") as f:
            L += ["", f.read()]
    out = os.path.join(rep, "SUMMARY.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("wrote", out, "bots:", len(bots))


if __name__ == "__main__":
    main()
