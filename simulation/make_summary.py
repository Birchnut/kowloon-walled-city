#!/usr/bin/env python3
"""v0.4(PC) 봇 시나리오 요약: simulation/reports/seed<N>/<bot>.json(sim_run.gd가 씀)을 모아 SUMMARY.md를 만든다.
실행: python3 simulation/make_summary.py [보고서 폴더]  (기본 simulation/reports)
씨앗 폴더(seed1, seed2, …)가 있으면 씨앗마다 이정표를 모아 평균·퍼짐((최대−최소)/평균)을 쓰고, 퍼짐이 20%를 넘으면 ⚠.
표: 이정표, 불·병 손실, 빈 구간과 돈, 금고(10·20·30·40일 — 금고 ÷ 그날 앞 3일 평균 세수 = '쌓아 둔 날 수'), 세 자재 집중형 차이, 직접 줍기형."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "reports")
ORDER = ["balanced", "direct_runner", "rush_upgrade", "export_specialist", "self_sufficient", "wood_focus", "metal_focus", "concrete_focus",
         "space_starved", "neglect_hazards", "casual"]
MS = [("first_upgrade_t2_day", "첫 승급", "≤ 1.5"), ("floor_2_day", "2층", "3–6"), ("first_fire_day", "첫 불", ""),
      ("first_upgrade_t3_day", "박힌 돌", "6–12"), ("floor_3_day", "3층", ""), ("first_outbreak_day", "첫 병", ""),
      ("first_upgrade_t4_day", "깡통 귀족", ""), ("goal_g_tower_day", "용탑", ""), ("first_upgrade_t5_day", "옥상 황제", "20–32"),
      ("goal_g_hall_day", "구청", ""), ("goal_g_final_day", "마지막 목표", "32–37")]


def load(d):
    out = {}
    if not os.path.isdir(d):
        return out
    for f in os.listdir(d):
        if f.endswith(".json") and not f.startswith("run_"):
            try:
                j = json.load(open(os.path.join(d, f)))
            except Exception:
                continue
            if "summary" in j:
                out[f[:-5]] = j
    return out


def seeds():
    dirs = sorted([x for x in os.listdir(DIR) if x.startswith("seed") and os.path.isdir(os.path.join(DIR, x))], key=lambda x: int(x[4:] or 0))
    if dirs:
        return [(int(x[4:]), load(os.path.join(DIR, x))) for x in dirs]
    return [(1, load(DIR))]


def stat(vals, days):
    """vals: 씨앗별 값(-1 = 못 함). 반환 (평균 글, 퍼짐 %, 못 한 씨앗 수)."""
    ok = [v for v in vals if v is not None and v > 0]
    miss = len(vals) - len(ok)
    if not ok:
        return "—", None, miss
    m = sum(ok) / len(ok)
    sp = 100.0 * (max(ok) - min(ok)) / m if len(ok) > 1 and m > 0 else 0.0
    return "%.1f" % m, sp, miss


def cell(vals, days):
    m, sp, miss = stat(vals, days)
    if m == "—":
        return "— (%d씨앗 모두 못 함)" % len(vals) if len(vals) > 1 else "—"
    s = m
    if len(vals) > 1:
        s += " ±%.0f%%" % (sp / 2.0)
        if sp > 20.0:
            s += " ⚠"
    if miss:
        s += " (%d씨앗 못 함)" % miss
    return s


def banked(rows, day):
    """day일 끝 금고와 그 앞 3일 평균 세수(₩/일)."""
    if len(rows) < day:
        return None
    r = rows[day - 1]
    taxes = [float(x.get("tax", 0.0)) for x in rows[max(0, day - 3):day]]
    t = sum(taxes) / max(1, len(taxes))
    return int(r["money"]), (float(r["money"]) / t if t > 0 else 0.0), t


def main():
    S = seeds()
    bots = [b for b in ORDER if any(b in s[1] for s in S)] + sorted({b for s in S for b in s[1]} - set(ORDER))
    name = {}
    for _, s in S:
        for b, j in s.items():
            name[b] = j["summary"]["name"]
    days = max((j["summary"]["days"] for _, s in S for j in s.values()), default=40)
    L = ["# v0.4(PC) 봇 시나리오 요약", "",
         "자동 생성: `python3 simulation/make_summary.py` ← `godot/tools/sim_run.gd`(씨앗마다 `seed<N>/<봇>.md`·`.json`, `simulation/run_all.sh`). 단위 = 경제일(×1에서 1일 = 실제 10분).",
         "봇은 경제 1시간마다(느긋한 사람형은 4시간마다) 손을 댄다. 사람은 봇보다 약 2배 느리고 ×1~×2로 시간당 약 6경제일을 플레이한다고 본다.",
         "씨앗: %s, %d경제일. 칸 = 평균 ±(최대−최소)/2를 평균에 대한 %%로. ⚠ = 퍼짐((최대−최소)/평균)이 20%%를 넘음. '못 함' = 그 씨앗에서 %d일 안에 못 이룸(평균에서 뺌)." % (", ".join(str(s[0]) for s in S), days, days), "",
         "## 이정표(경제일, 씨앗 평균) — 목표 범위는 봇 기준", "",
         "| 봇 | " + " | ".join("%s%s" % (m[1], " (%s)" % m[2] if m[2] else "") for m in MS) + " | 목표(평균) | 층 |",
         "|---|" + "---|" * (len(MS) + 2)]
    for b in bots:
        runs = [s[1][b]["summary"] for s in S if b in s[1]]
        row = [cell([r["timeline"].get(m[0], -1) for r in runs], days) for m in MS]
        L.append("| %s | %s | %.1f/24 | %.1f |" % (name[b], " | ".join(row), sum(r["goals_done"] for r in runs) / len(runs), sum(r["floors"] for r in runs) / len(runs)))
    L += ["", "## 불·병 — 잃은 주거-일(탄·타는 집 + 앓는 집 × 0.5) / 전체 주거-일 (씨앗 평균)", "",
          "| 봇 | 손실 % (씨앗별) | 불 | 탄 건물 | 병(발병) | 병으로 떠남 | 불로 떠남 | 불로 흩어짐 | 수리비 | 마지막 인구(5계층) |", "|---|---|---|---|---|---|---|---|---|---|"]
    for b in bots:
        runs = [s[1][b]["summary"] for s in S if b in s[1]]
        n = len(runs)
        av = lambda k: sum(float(r.get(k, 0)) for r in runs) / n
        L.append("| %s | **%.2f%%** (%s) | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | ₩%s | %s |" % (name[b], av("hazard_loss_pct"), " / ".join("%.2f" % r["hazard_loss_pct"] for r in runs),
                 av("fires"), av("burnt"), av("outbreaks"), av("left_sick"), av("left_fire"), av("scattered"), f"{int(av('spent_repair')):,}", "/".join(str(x) for x in runs[0]["pop_end"])))
    L += ["", "## 빈 구간과 돈 (씨앗 평균)", "",
          "가장 긴 빈 구간 = 진전 명령(짓기·승급·칠하기·탐험 수령·직접 줍기·수리·연구·계약) 사이 가장 긴 간격. 지출 = 건설+승급+수리+연구.", "",
          "| 봇 | 가장 긴 빈 구간(일) | 세수 합 | 건설 | 승급 | 수리 | 연구 | 유지비 | 지출 ÷ 세수 | 마지막 금고 | 스텝 ms |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for b in bots:
        runs = [s[1][b]["summary"] for s in S if b in s[1]]
        n = len(runs)
        av = lambda k: sum(float(r.get(k, 0)) for r in runs) / n
        sp = av("spent_build") + av("spent_upgrade") + av("spent_repair") + av("spent_research")
        L.append("| %s | %.2f | ₩%s | ₩%s | ₩%s | ₩%s | ₩%s | ₩%s | %.0f%% | ₩%s | %.1f |" % (name[b], av("longest_gap"), f"{int(av('tax_total')):,}", f"{int(av('spent_build')):,}",
                 f"{int(av('spent_upgrade')):,}", f"{int(av('spent_repair')):,}", f"{int(av('spent_research')):,}", f"{int(av('upkeep_total')):,}", 100.0 * sp / max(1.0, av("tax_total")),
                 f"{int(av('money_end')):,}", av("step_ms")))
    L += ["", "## 금고 — 10·20·30·40일 끝(씨앗 평균). 괄호 = 그 앞 3일 평균 세수로 며칠 치를 쌓아 두었나(10일 치를 넘으면 돈이 남아도는 것)", "",
          "| 봇 | 10일 | 20일 | 30일 | 40일 | 10일 구간 지출 ÷ 세수(0–10 / 10–20 / 20–30 / 30–40) |", "|---|---|---|---|---|---|"]
    for b in bots:
        rs = [s[1][b]["rows"] for s in S if b in s[1]]
        cells = []
        for d in (10, 20, 30, 40):
            v = [banked(r, d) for r in rs]
            v = [x for x in v if x]
            if not v:
                cells.append("—")
                continue
            cells.append("₩%s (%.1f일)" % (f"{int(sum(x[0] for x in v) / len(v)):,}", sum(x[1] for x in v) / len(v)))
        seg = []
        for a, z in ((0, 10), (10, 20), (20, 30), (30, 40)):
            sp = tx = 0.0
            for r in rs:
                for row in r[a:z]:
                    tx += float(row.get("tax", 0.0))
                    led = row.get("ledger", {})
                    sp += -sum(float(led.get(k, 0.0)) for k in ("build", "upgrade", "research") if float(led.get(k, 0.0)) < 0)
            seg.append("%.0f%%" % (100.0 * sp / tx) if tx > 0 else "—")
        L.append("| %s | %s | %s |" % (name[b], " | ".join(cells), " / ".join(seg)))
    fams = ["wood_focus", "metal_focus", "concrete_focus"]
    if all(any(f in s[1] for s in S) for f in fams):
        L += ["", "## 세 자재 집중형 — 이정표마다 평균에서 가장 먼 계열의 차이(목표 ±10%)", "", "| 이정표 | 목재 | 철제 | 콘크리트 | 최대 차이 |", "|---|---|---|---|---|"]
        for m in MS:
            vals = []
            for f in fams:
                ok = [s[1][f]["summary"]["timeline"].get(m[0], -1) for s in S if f in s[1]]
                ok = [x for x in ok if x and x > 0]
                vals.append(sum(ok) / len(ok) if ok else None)
            if any(v is None for v in vals):
                L.append("| %s | %s | — |" % (m[1], " | ".join("—" if v is None else "%.1f" % v for v in vals)))
                continue
            mm = sum(vals) / 3.0
            dev = 100.0 * max(abs(v - mm) for v in vals) / mm if mm > 0 else 0.0
            L.append("| %s | %s | %.1f%%%s |" % (m[1], " | ".join("%.1f" % v for v in vals), dev, " ⚠" if dev > 10.0 else ""))
    if any("direct_runner" in s[1] for s in S):
        runs = [s[1]["direct_runner"]["summary"] for s in S if "direct_runner" in s[1]]
        n = len(runs)
        L += ["", "## 직접 줍기형", "",
              "한 판(미니게임 평균 성격의 결과·길이·짐을 `simulation/reports/run_batch.md`에서 뽑음)을 쉬지 않고 이어 한다(팀 하나를 씀). 씨앗 평균: %.0f판, 들고 나온 것 %.0f개(판당 %.1f개)." % (
                  sum(r.get("bot_runs", 0) for r in runs) / n, sum(r.get("bot_run_units", 0) for r in runs) / n,
                  sum(r.get("bot_run_units", 0) for r in runs) / max(1, sum(r.get("bot_runs", 0) for r in runs)))]
    out = os.path.join(DIR, "SUMMARY.md")
    open(out, "w").write("\n".join(L) + "\n")
    print(out)


main()
