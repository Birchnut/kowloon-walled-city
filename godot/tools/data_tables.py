#!/usr/bin/env python3
"""JSON 원본(godot/data/**)에서 사람이 검토할 표(docs/data_tables/*.md)를 다시 만든다. 표는 손으로 고치지 않는다.
사용: python3 godot/tools/data_tables.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.normpath(os.path.join(HERE, "..", "data"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "docs", "data_tables"))


def load(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        return json.load(f)


def n(x):
    if isinstance(x, float) and x.is_integer():
        return str(int(x))
    return str(x)


def header(title, src, status):
    return [f"# {title}", "", f"자동 생성 — 원본 `godot/data/{src}` (상태: {status}). 고치려면 JSON을 고치고 `python3 godot/tools/data_tables.py`.", ""]


def main():
    os.makedirs(OUT, exist_ok=True)
    cfg = load("rules/config.json")
    tiers = load("population/tiers.json")
    needs = load("population/needs.json")
    goods = load("economy/goods.json")
    partners = load("economy/partners.json")
    blds = load("buildings/buildings.json")
    upg = load("buildings/upgrade_costs.json")
    unl = load("progression/unlocks.json")
    G = goods["items"]
    B = blds["items"]
    T = tiers["items"]
    gname = lambda g: G.get(g, {}).get("name", g)
    tname = lambda t: T.get(t, {}).get("name", t)
    svc = {}
    for bid, b in B.items():
        for s in b.get("services", []):
            svc.setdefault(s, b["name"])

    def opt_name(o):
        if "good" in o:
            return gname(o["good"])
        if "service" in o:
            return svc.get(o["service"], o["service"])
        if "utility" in o:
            return ("물" if o["utility"] == "water" else "전기") + (f" (+{n(o['amount'])}/인)" if "amount" in o else "")
        return f"시장 {o['market']}등급"

    files = {}
    L = header("계층과 수요", "population/tiers.json, needs.json", tiers.get("status", "") + " / " + needs.get("status", ""))
    L += ["| id | 이름 | 정원 | 노동 참여 | 세율 달러/인·일 | 물/인·일 | 전기/인 | 만실 세수/칸 |", "|---|---|---|---|---|---|---|---|"]
    for tid, t in T.items():
        L.append(f"| {tid} | {t['name']} | {t['cap']} | {n(t['labor'])} | {n(t['tax'])} | {n(t['water'])} | {n(t['power'])} | {n(round(t['cap'] * t['tax'], 1))} |")
    L += ["", "| 계층 | 수요 | 역할 | 정원 몫 | 소비/인·일 | 선택지(몇 종) |", "|---|---|---|---|---|---|"]
    role = {"basic": "기본", "advance": "승급 조건", "luxury": "여유"}
    for nid, nd in needs["items"].items():
        opts = " / ".join(opt_name(o) for o in nd["options"])
        cnt = nd.get("count", 1)
        L.append(f"| {tname('t%d' % nd['tier'])} | {nd['name']} (`{nid}`) | {role[nd['role']]} | {nd.get('share', '')} | {n(nd.get('amount', ''))} | {opts}{' — %d종' % cnt if cnt > 1 else ''} |")
    files["tiers_needs.md"] = L

    L = header("상품", "economy/goods.json", goods.get("status", ""))
    L += ["| id | 이름 | 분류 | 시장 등급 | 기준가 달러 | 계열 |", "|---|---|---|---|---|---|"]
    for gid, g in G.items():
        L.append(f"| {gid} | {g['name']} | {goods['cats'].get(g['cat'], g['cat'])} | {g.get('grade', '')} | {n(g.get('price', ''))} | {g.get('family', '')} |")
    files["goods.md"] = L

    L = header("시설", "buildings/buildings.json", blds.get("status", ""))
    L += ["| id | 이름(간판) | 외형(look) | 분류 | 모양(w×h×층) | 공사(일) | 비용 | 유지비/일 | 인력 | 생산/공급/서비스 | 물·전기 | 순위 |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for bid, b in B.items():
        cost = f"{n(b['cost']['money'])}달러" + "".join(f" + {gname(g)} {n(q)}" for g, q in b["cost"].get("goods", {}).items())
        wf = ", ".join(f"{tname(t)} {q}" for t, q in b.get("workforce", {}).items()) or "–"
        eff = []
        rec = b.get("recipe")
        if rec:
            ins = ", ".join(f"{gname(g)} {n(q)}" for g, q in rec.get("in", {}).items())
            outs = ", ".join(f"{gname(g)} {n(q)}" for g, q in rec.get("out", {}).items())
            eff.append(f"{ins} → {outs}" if ins else outs)
        for u, q in b.get("supply", {}).items():
            eff.append(("물" if u == "water" else "전기") + f" +{n(q)}")
        rg = b.get("range")
        rgt = f"범위 {rg['r']}칸·위{rg['up']}/아래{rg['down']}층" if isinstance(rg, dict) else ""
        if "market" in b:
            eff.append(f"시장 {b['market']}등급 {rgt}")
        elif b.get("services"):
            eff.append(", ".join(b["services"]) + f" {rgt}")
        if b.get("needs_sky"):
            eff.append("위가 뚫린 자리")
        if b.get("min_floor"):
            eff.append(f"{b['min_floor'] + 1}층 이상")
        if b.get("luxury"):
            eff.append("사치(행복 유지 해금)")
        if b.get("storage"):
            eff.append("창고")
        if b.get("contract_slots"):
            eff.append(f"계약 +{b['contract_slots']}")
        if b.get("vice"):
            eff.append(f"층세 {b['vice']['income']}달러/일")
        ut = " ".join(x for x in [f"물 {n(b['water'])}" if b.get("water") else "", f"전기 {n(b['power'])}" if b.get("power") else ""] if x) or "–"
        fp = b.get("footprint", [b.get("size", 1), b.get("size", 1)])
        cells = fp[0] * fp[1] * b.get("floors", 1)
        days = b.get("build_days") or max([v for k, v in cfg.get("build", {}).get("days_by_cells", {"1": 0.1}).items() if cells >= int(k)] or [0.1])
        L.append(f"| {bid} | {b['name']}({b.get('sign', '')}) | {b.get('look', '')} | {blds['cats'].get(b['cat'], b['cat'])} | {fp[0]}×{fp[1]}×{b.get('floors', 1)} | {n(days)} | {cost} | {n(b['upkeep'])} | {wf} | {'; '.join(eff)} | {ut} | {b['priority']} |")
    files["buildings.md"] = L

    L = header("승급 비용", "buildings/upgrade_costs.json", upg.get("status", ""))
    L += [f"자재는 {' · '.join(upg['material_names'][m] for m in upg['materials'])} 중 **하나**, 같은 수량(확정).", "",
          "| 승급 | 돈 | 자재 수량(셋 중 하나) | 추가 | 공사(경제일) | 정원 변화 |", "|---|---|---|---|---|---|"]
    for uid, u in upg["items"].items():
        ex = ", ".join(f"{gname(g)} {n(q)}" for g, q in u.get("extra", {}).items()) or "–"
        L.append(f"| {tname('t%d' % u['from'])}→{tname('t%d' % u['to'])} | {n(u['money'])} | {u['qty']} | {ex} | {n(u['days'])} | {T['t%d' % u['from']]['cap']}→{T['t%d' % u['to']]['cap']} |")
    L += ["", "누적 자재(떠돌이에서 출발한 주거 한 채): " + ", ".join(
        f"{tname('t%d' % u['to'])} {sum(v['qty'] for v in upg['items'].values() if v['to'] <= u['to'])}" for u in upg["items"].values())]
    files["upgrade_costs.md"] = L

    L = header("해금", "progression/unlocks.json", unl.get("status", ""))
    L += ["| 순서 | 조건 | 열리는 시설 | 기능 | 등급·호칭 |", "|---|---|---|---|---|"]
    for uid, u in sorted(unl["items"].items(), key=lambda kv: kv[1].get("order", 0)):
        cond = " + ".join(
            (f"{tname(c[0][4:])} {c[2]}명" if c[0].startswith("pop.") else f"{B.get(c[0][6:], {}).get('name', c[0])} {c[2]}" if c[0].startswith("count.") else f"{c[0]} {c[1]} {c[2]}")
            for c in u.get("cond", [])) or "처음부터"
        bl = ", ".join("주거" if b == "house" else B[b]["name"] for b in u.get("unlocks", []))
        L.append(f"| {u.get('order', 0)} | {cond} | {bl} | {', '.join(u.get('features', []))} | {u.get('grade_name', '')} {('· ' + u['title']) if 'title' in u else ''} |")
    files["unlocks.md"] = L

    L = header("거래처와 계약 제안", "economy/partners.json", partners.get("status", ""))
    L += ["| 거래처 | 처음부터 앎 | 설명 |", "|---|---|---|"]
    for pid, p in partners["partners"].items():
        L.append(f"| {p['name']} (`{pid}`) | {'예' if p['known'] else '아니오 — ' + p.get('reveal_hint', '')} | {p['desc']} |")
    L += ["", "| 제안 | 거래처 | 상품 | 방향 | 단계(수량/주기h @단가) | 운송비 |", "|---|---|---|---|---|---|"]
    for oid, o in partners["items"].items():
        sz = " · ".join(f"{s['qty']}/{s['interval_h']}h @{n(s['price'])}" for s in o["sizes"])
        L.append(f"| {oid} | {partners['partners'][o['partner']]['name']} | {gname(o['good'])} | {'수입' if o['dir'] == 'import' else '수출'} | {sz} | {n(o.get('transport', 0))} |")
    files["offers.md"] = L

    # ---- 파트 B: 탐험·목표·연구·정책
    dest = load("exploration/destinations.json")
    band = {"near": "근", "mid": "중", "far": "원"}
    L = header("탐험 목적지", "exploration/destinations.json", dest.get("status", ""))
    pv = dest.get("provision", {})
    L += [f"팀: 탐험 거점 하나당 1팀, 최대 {dest.get('teams', {}).get('max', 3)}. 보급: 끼니 {pv.get('n', 10)}({'·'.join(gname(g) for g in pv.get('goods', []))}) → 수확 +{int(pv.get('bonus', 0.25) * 100)}%.", ""]
    L += ["| id | 이름 | 거리 | 경제일(×1 실제) | 비용 달러 | 보장 주력 | 주력/경제일 | 덤 | 던전 재고(최대, 하루 회복) | 위험 | 발견 | 처음부터 앎 |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for did, d in dest["items"].items():
        pr = d.get("primary", {})
        pg = pr.get("good", "")
        pname = gname(pg) if pg else "고른 자재(" + "·".join(gname(g) for g in d.get("picks", [])) + ")"
        days = d.get("days", 1)
        tm = f"{n(days)}일({int(days * 10)}분)"
        per_h = (pr.get("min", 0) + pr.get("max", 0)) / 2 / max(0.01, days)
        stk = ", ".join(f"{gname(g)} {q}" for g, q in d.get("stock", {}).items()) + f" ({int(d.get('regen', 0.5) * 100)}%/일)"
        bon = ", ".join(f"{gname(b['good'])} {b['min']}~{b['max']}" + (f"({int(b.get('chance', 1) * 100)}%)" if b.get("chance", 1) < 1 else "") for b in d.get("bonus", []))
        finds = ", ".join(f"{f['type']}:{f['id']}" for f in d.get("finds", [])) + ((" / 공개: " + ", ".join(dest["items"][r]["name"] for r in d.get("reveals", []))) if d.get("reveals") else "")
        L.append(f"| {did} | {d['name']} | {band.get(d.get('band'), d.get('band'))} | {tm} | {n(d.get('cost', {}).get('money', 0))} | {pname} {pr.get('min', 0)}~{pr.get('max', 0)} | {per_h:.1f} | {bon} | {stk} | {d.get('danger', 1)} | {finds} | {'예' if d.get('known') else '아니오 — ' + d.get('reveal_hint', '')} |")
    files["destinations.md"] = L

    goals = load("progression/goals.json")
    L = header("단계 목표", "progression/goals.json", goals.get("status", ""))
    L += ["| 순서 | id | 문구 | 조건 | 보상 | 해금 단계 |", "|---|---|---|---|---|---|"]
    for gid, g in sorted(goals["items"].items(), key=lambda kv: kv[1].get("order", 0)):
        cond = " + ".join(f"{c[0]} {c[1]} {c[2]}" for c in g.get("cond", []))
        rw = g.get("rewards", {})
        parts = []
        if rw.get("money"):
            parts.append(f"{rw['money']}달러")
        for k, v in rw.get("stock", {}).items():
            parts.append(f"{gname(k)} {v}")
        for r in rw.get("reveal", []):
            parts.append("목적지 " + dest["items"].get(r, {}).get("name", r))
        L.append(f"| {g.get('order', 0)} | {gid} | {g['text']} | {cond} | {', '.join(parts)} | {g.get('unlock', '')}{' (최종)' if g.get('final') else ''} |")
    files["goals.md"] = L

    res = load("progression/research.json")
    br = res.get("branches", {})
    L = header("연구", "progression/research.json", res.get("status", ""))
    L += ["| 갈래 | 단계 | id | 이름 | 비용 달러 | 경제일 | 앞 단계 | 효과 | 설명 |", "|---|---|---|---|---|---|---|---|---|"]
    tot = 0
    for rid, r in sorted(res["items"].items(), key=lambda kv: (list(br).index(kv[1]["branch"]), kv[1].get("tier", 0))):
        tot += r.get("cost", 0)
        fx = ", ".join(f"{k} {'+' if v >= 0 else ''}{n(v)}" for k, v in r.get("effects", {}).items())
        if r.get("reveals"):
            fx += " · 목적지 공개 " + ", ".join(dest["items"][x]["name"] for x in r["reveals"])
        L.append(f"| {br.get(r['branch'], r['branch'])} | {r.get('tier', 0)} | {rid} | {r['name']} | {n(r.get('cost', 0))} | {n(r.get('days', 0))} | {res['items'].get(r.get('requires', ''), {}).get('name', '')} | {fx} | {r.get('desc', '')} |")
    L += ["", f"전부 합계 {tot}달러."]
    files["research.md"] = L

    pol = load("progression/policies.json")
    L = header("정책", "progression/policies.json", pol.get("status", ""))
    L += ["칸 수 = 열린 `feature:policy_slot_N`(해금 표 참고).", "", "| id | 이름 | 효과 | 유지비 달러/일 | 두 우산 시설당 달러/일 | 같이 못 켬 | 설명 |", "|---|---|---|---|---|---|---|"]
    for pid, p in pol["items"].items():
        fx = ", ".join(f"{k} {'+' if v >= 0 else ''}{n(v)}" for k, v in p.get("effects", {}).items())
        L.append(f"| {pid} | {p['name']} | {fx} | {n(p.get('upkeep', 0))} | {n(p.get('upkeep_per_vice', 0))} | {p.get('group', '')} | {p.get('desc', '')} |")
    files["policies.md"] = L

    L = header("음성 시설과 단속 위험", "buildings/buildings.json(vice), rules/config.json(heat)", "실험값")
    cfg = load("rules/config.json")
    h = cfg.get("heat", {})
    L += [f"위험은 가동 중인 음성 시설마다 하루 heat만큼 오르고 하루 {h.get('decay_per_day')}씩 식는다. {h.get('warn')}에서 알림, {h.get('raid')}에서 단속(하나 {h.get('close_days')}일 폐쇄, 벌금 = max({h.get('fine_min')}, 수입 × {h.get('fine_days_income')}), 위험 −{h.get('after_raid_drop')}).", ""]
    L += ["| 시설 | 층세 달러/일 | 위험/일 | 단속 문구 |", "|---|---|---|---|"]
    for bid, b in B.items():
        v = b.get("vice")
        if v:
            L.append(f"| {b['name']} | {n(v.get('income', 0))} | {n(v.get('heat', 0))} | {v.get('raid_line', '')} |")
    files["vice.md"] = L

    for name, lines in files.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print("wrote", ", ".join(sorted(files)), "->", OUT)


if __name__ == "__main__":
    sys.exit(main())
