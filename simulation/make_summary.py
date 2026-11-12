#!/usr/bin/env python3
"""v0.4(PC) 봇 시나리오 요약: simulation/reports/<bot>.json(sim_run.gd가 씀)을 모아 SUMMARY.md를 만든다.
실행: python3 simulation/make_summary.py [보고서 폴더]  (기본 simulation/reports)
표: 이정표(첫 승급·2층·박힌 돌·옥상 황제·마지막 목표), 불·병 손실, 가장 긴 빈 구간, 금고 곡선, 지출 구성, 세 자재 집중형 차이."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "reports")
ORDER = ["balanced", "rush_upgrade", "export_specialist", "self_sufficient", "wood_focus", "metal_focus", "concrete_focus",
         "space_starved", "neglect_hazards", "casual"]
TARGET = {"first_upgrade_t2_day": "≤ 1.5", "floor_2_day": "3–6", "first_upgrade_t3_day": "6–12", "first_upgrade_t5_day": "20–32", "goal_g_final_day": "28–40"}


def d(x):
    return "—" if x is None or x < 0 else "%.1f" % x


def main():
    rows = []
    for b in ORDER + sorted(f[:-5] for f in os.listdir(DIR) if f.endswith(".json") and f[:-5] not in ORDER):
        p = os.path.join(DIR, b + ".json")
        if not os.path.exists(p):
            continue
        try:
            j = json.load(open(p))
        except Exception:
            continue
        if "summary" not in j:
            continue
        rows.append(j["summary"])
    L = ["# v0.4(PC) 봇 시나리오 요약", "",
         "자동 생성: `python3 simulation/make_summary.py` ← `godot/tools/sim_run.gd`(봇마다 `<봇>.md`·`.json`). 단위 = 경제일(×1에서 1일 = 실제 10분).",
         "봇은 경제 1시간마다(느긋한 사람형은 4시간마다) 손을 댄다. 사람은 봇보다 약 2배 느리고 ×1~×2로 시간당 약 6경제일을 플레이한다고 본다.", "",
         "## 이정표(경제일) — 목표 범위는 봇 기준", "",
         "| 봇 | 첫 승급 (%s) | 2층 (%s) | 첫 불 | 박힌 돌 (%s) | 3층 | 깡통 귀족 | 옥상 황제 (%s) | 구청 | 마지막 목표 (%s) | 목표 | 층 |" % tuple(TARGET.values()),
         "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        t = r["timeline"]
        L.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %d/24 | %d |" % (r["name"], d(t.get("first_upgrade_t2_day")), d(t.get("floor_2_day")), d(t.get("first_fire_day")),
                 d(t.get("first_upgrade_t3_day")), d(t.get("floor_3_day")), d(t.get("first_upgrade_t4_day")), d(t.get("first_upgrade_t5_day")),
                 d(t.get("goal_g_hall_day")), d(t.get("goal_g_final_day")), r["goals_done"], r["floors"]))
    L += ["", "## 불·병 — 잃은 주거-일(탄·타는 집 + 앓는 집 × 0.5) / 전체 주거-일", "",
          "| 봇 | 손실 % | 불 | 탄 건물 | 병(발병) | 병으로 떠남 | 불로 흩어짐 | 마지막 인구(5계층) |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        L.append("| %s | **%.2f%%** | %d | %d | %d | %d | %d | %s |" % (r["name"], r["hazard_loss_pct"], r["fires"], r["burnt"], r["outbreaks"], r["left_sick"], r["scattered"],
                 "/".join(str(x) for x in r["pop_end"])))
    L += ["", "## 빈 구간과 돈", "",
          "가장 긴 빈 구간 = 진전 명령(짓기·승급·칠하기·탐험 수령·수리·연구·계약) 사이 가장 긴 간격.", "",
          "| 봇 | 가장 긴 빈 구간(일, 시작) | 세수 합 | 건설 | 승급 | 수리 | 연구 | 지출 ÷ 세수 | 마지막 금고 | 최저 금고 | 스텝 ms |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        tax = max(1, r["tax_total"])
        L.append("| %s | %.2f (%.1f) | ₩%s | ₩%s | ₩%s | ₩%s | ₩%s | %.0f%% | ₩%s | ₩%s | %.1f |" % (r["name"], r["longest_gap"], r["longest_gap_at"], f"{r['tax_total']:,}",
                 f"{r['spent_build']:,}", f"{r['spent_upgrade']:,}", f"{r['spent_repair']:,}", f"{r['spent_research']:,}",
                 100.0 * (r["spent_build"] + r["spent_upgrade"] + r["spent_repair"] + r["spent_research"]) / tax, f"{r['money_end']:,}", f"{r['min_money']:,}", r["step_ms"]))
    L += ["", "## 금고 곡선(5일마다, ₩)", "", "| 봇 | " + " | ".join("%d일" % x for x in range(5, 45, 5)) + " |", "|---|" + "---|" * 8]
    for r in rows:
        mc = r["money_curve"]
        L.append("| %s | %s |" % (r["name"], " | ".join(f"{mc[i - 1]:,}" if i - 1 < len(mc) else "—" for i in range(5, 45, 5))))
    fams = [r for r in rows if r["bot"] in ("wood_focus", "metal_focus", "concrete_focus")]
    fin = [r["timeline"].get("goal_g_final_day", -1) for r in fams]
    if len(fams) == 3 and all(x is not None and x > 0 for x in fin):
        m = sum(fin) / 3.0
        L += ["", "세 자재 집중형 마지막 목표: %s — 평균에서 최대 %.1f%% 차이(목표 ±15%%)." % (", ".join("%s %.1f일" % (r["name"], x) for r, x in zip(fams, fin)),
                                                                          100.0 * max(abs(x - m) for x in fin) / m)]
    elif fams:
        L += ["", "세 자재 집중형 마지막 목표: %s." % ", ".join("%s %s" % (r["name"], d(x)) for r, x in zip(fams, fin))]
    out = os.path.join(DIR, "SUMMARY.md")
    open(out, "w").write("\n".join(L) + "\n")
    print(out)


main()
