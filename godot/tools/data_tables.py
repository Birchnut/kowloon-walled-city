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
    L += ["| id | 이름 | 정원 | 노동 참여 | 세율 ₩/인·일 | 물/인·일 | 전기/인 | 만실 세수/칸 |", "|---|---|---|---|---|---|---|---|"]
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
    L += ["| id | 이름 | 분류 | 시장 등급 | 기준가 ₩ | 계열 |", "|---|---|---|---|---|---|"]
    for gid, g in G.items():
        L.append(f"| {gid} | {g['name']} | {goods['cats'].get(g['cat'], g['cat'])} | {g.get('grade', '')} | {n(g.get('price', ''))} | {g.get('family', '')} |")
    files["goods.md"] = L

    L = header("시설", "buildings/buildings.json", blds.get("status", ""))
    L += ["| id | 이름(간판) | 분류 | 크기 | 비용 | 유지비/일 | 인력 | 생산/공급/서비스 | 물·전기 | 순위 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for bid, b in B.items():
        cost = f"₩{n(b['cost']['money'])}" + "".join(f" + {gname(g)} {n(q)}" for g, q in b["cost"].get("goods", {}).items())
        wf = ", ".join(f"{tname(t)} {q}" for t, q in b.get("workforce", {}).items()) or "–"
        eff = []
        rec = b.get("recipe")
        if rec:
            ins = ", ".join(f"{gname(g)} {n(q)}" for g, q in rec.get("in", {}).items())
            outs = ", ".join(f"{gname(g)} {n(q)}" for g, q in rec.get("out", {}).items())
            eff.append(f"{ins} → {outs}" if ins else outs)
        for u, q in b.get("supply", {}).items():
            eff.append(("물" if u == "water" else "전기") + f" +{n(q)}")
        if "market" in b:
            eff.append(f"시장 {b['market']}등급 범위 {b['range']}")
        elif b.get("services"):
            eff.append(", ".join(b["services"]) + f" 범위 {b['range']}")
        if b.get("storage"):
            eff.append("창고")
        if b.get("contract_slots"):
            eff.append(f"계약 +{b['contract_slots']}")
        if b.get("vice"):
            eff.append(f"음성 ₩{b['vice']['income']}/일")
        ut = " ".join(x for x in [f"물 {n(b['water'])}" if b.get("water") else "", f"전기 {n(b['power'])}" if b.get("power") else ""] if x) or "–"
        L.append(f"| {bid} | {b['name']}({b.get('sign', '')}) | {blds['cats'].get(b['cat'], b['cat'])} | {b['size']} | {cost} | {n(b['upkeep'])} | {wf} | {'; '.join(eff)} | {ut} | {b['priority']} |")
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

    for name, lines in files.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print("wrote", ", ".join(sorted(files)), "->", OUT)


if __name__ == "__main__":
    sys.exit(main())
