#!/usr/bin/env python3
# v0.5부터 쓰지 않는다. godot/data/**.json이 원본이고, 이 생성기를 돌리면 v0.5 데이터(조직·창고 세 크기·먹을 것 순서 등)를 v0.4로 덮어쓴다. 돌리지 마라.
"""v0.4(PC) 콘텐츠를 한 번에 쓰는 생성기 — 한 번 돌린 뒤에는 godot/data/**.json이 원본이다(튜닝은 JSON을 직접 고친다).
이름·설명은 docs/GDD_PC.md §8의 결: 주민 = 황무지식, 관직 = 능청 관공서식, 가게 = 간판 농담. 한자 없음.
실행: python3 simulation/gen_v4_data.py  (godot/data/를 덮어쓴다 — 첫 작성용)"""
import json, os, collections

ROOT = os.path.join(os.path.dirname(__file__), "..", "godot", "data")
OD = collections.OrderedDict


def save(rel, d):
    p = os.path.join(ROOT, rel)
    with open(p, "w") as f:
        f.write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


def load(rel):
    with open(os.path.join(ROOT, rel)) as f:
        return json.load(f, object_pairs_hook=OD)


R = lambda r, up=1, down=1: {"r": r, "up": up, "down": down}

# ------------------------------------------------------------------ 상품
goods = OD()
def G(i, name, cat, price, grade=None, desc="", family=None):
    g = OD(name=name, cat=cat, price=price)
    if grade is not None: g["grade"] = grade
    if family: g["family"] = family
    if desc: g["desc"] = desc
    goods[i] = g

G("scrap", "고물", "material", 2, desc="시설을 짓는 데 쓰는 잡동사니. 수리에도 든다.")
G("wood", "목재", "material", 12, family="wood", desc="문짝·장롱·판재. 목조 외관.")
G("metal", "철제", "material", 12, family="metal", desc="프레임·패널. 철제 외관.")
G("concrete", "콘크리트", "material", 12, family="concrete", desc="재사용 블록·부재. 콘크리트 외관.")
G("parts", "설비 부품", "material", 80, desc="상급 설비와 옥상 황제의 집에 드는 부품. 먼 탐험에서.")
G("elec_scrap", "전자 폐품", "raw", 5, desc="뜯어낸 기판과 전선. 탐험에서 줍는다.")
G("noodles", "생면", "raw", 1.0, desc="제면소가 뽑는다. 밀가루의 출처는 묻지 않는다.")
G("ratmeat", "쥐고기", "raw", 1.2, desc="쥐덫 조합의 성과물. 공식 명칭은 '골목 단백질'.")
G("oil", "폐식용유", "raw", 0.8, desc="식당 뒷문에서 모은 기름. 초와 비누가 된다.")
G("rags", "넝마", "raw", 1.0, desc="버린 천. 옷과 양복이 된다.")
G("fish", "생선", "raw", 4.0, desc="부두에서 들여온다. 수입품이다(진짜 사치).")
G("cans", "통조림", "consumer", 1.0, 1, "찌그러진 캔과 마감 세일 폐기 식품. 유통기한은 숫자일 뿐.")
G("oldclothes", "헌 옷", "consumer", 2.0, 1, "수거함에서 나온 옷.")
G("candle", "초", "consumer", 1.5, 1, "폐식용유로 부은 초. 정전의 친구.")
G("moonshine", "밀주", "consumer", 2.0, 1, "부스러기로 빚은 술.")
G("wonton", "완탕면", "consumer", 2.0, 2, "어제 국물에 오늘 면.")
G("clothes", "옷", "consumer", 3.0, 2, "넝마를 꿰매 만든 옷.")
G("soap", "비누", "consumer", 2.5, 2, "기름 냄새가 조금 나는 비누.")
G("burger", "쥐고기 버거", "consumer", 4.0, 3, "패티의 출처는 묻지 않는다.")
G("radio", "라디오", "consumer", 14.0, 3, "고친 라디오. 한 채널은 늘 잡음.")
G("suit", "양복", "consumer", 22.0, 3, "넝마로 지은 빈티지 양복.")
G("sushi", "스시", "consumer", 12.0, 4, "어제 잡은 생선(몇 년 어제인지는 비밀).")
G("liquor", "양주", "consumer", 25.0, 4, "수입만 된다. 병은 진짜다.")
G("appliance", "가전", "consumer", 45.0, 4, "라디오를 뜯어 만든 가전.")
G("fakelux", "짝퉁 명품", "consumer", 30.0, 4, "로고가 진짜보다 크다.")
G("veg", "신선 채소", "consumer", 10.0, 4, "옥상 텃밭에서 딴 채소. 성채 최고의 사치.")
G("firework", "폭죽", "consumer", 6.0, None, "수출용. 성채 안에서는 안 쓴다.")
save("economy/goods.json", OD(
    _comment="상품(v0.4 PC). cat: material(건축자재) / raw(원료·중간재) / consumer(소비재). grade = 이 상품을 취급할 수 있는 최저 시장 등급(소비재만). family = 승급 외관 자재 계열. price = 기준가 ₩/단위(계약 단가의 기준). 재고는 도시 공유(확정). 성채식 조달: 원료는 성채 안의 수상한 시설이 만들고, 생선·양주만 수입, 전자 폐품·설비 부품은 탐험에서.",
    status="실험값", cats=OD(material="건축자재", raw="원료", consumer="소비재"), items=goods))

# ------------------------------------------------------------------ 시설
B = OD()
def F(i, name, sign, look, cat, prio, fp, cost, upkeep, wf, desc, **kw):
    d = OD(name=name, sign=sign, look=look, cat=cat, priority=prio, footprint=fp)
    if kw.get("floors"): d["floors"] = kw.pop("floors")
    d["cost"] = OD(money=cost[0], goods=OD(cost[1] if len(cost) > 1 else {}))
    d["upkeep"] = upkeep
    d["workforce"] = OD(wf)
    for k, v in kw.items():
        d[k] = v
    d["desc"] = desc
    B[i] = d

# 시장
F("market_mat", "돗자리 장터", "장터", "market_mat", "market", "service", [1, 2], (40,), 2, {"t1": 2},
  "돗자리 한 장이면 가게다. 자릿세는 비공식.", market=1, range=R(4))
F("market_alley", "뒷골목 시장", "골목", "market_alley", "market", "service", [2, 2], (200, {"scrap": 10}), 8, {"t2": 4},
  "골목 하나가 통째로 시장. 길을 잃으면 그냥 산다.", market=2, range=R(5))
F("market_hall", "지붕 있는 시장", "시장", "market_hall", "market", "service", [2, 2], (700, {"scrap": 30}), 20, {"t3": 6},
  "지붕이 있다는 것만으로 동네 자랑거리. 전기가 든다.", market=3, range=R(6), power=6)
F("market_mall", "면세 백화점", "면세", "market_mall", "market", "service", [2, 2], (2500, {"scrap": 60, "parts": 2}), 50, {"t4": 6},
  "세금을 안 낸다. 원래 아무도 안 내지만 여긴 간판에 써 붙였다.", floors=2, market=4, range=R(7, 2, 1), power=12)
# 물
F("rain_catcher", "하늘 수도국", "수도국", "water_catcher", "water", "utility", [1, 1], (20,), 0.5, {},
  "양철 홈통과 드럼통 하나. 비 오는 날엔 국장님이 웃는다.", supply={"water": 20})
F("water_tank", "훔친 물탱크", "물탱크", "water_tank", "water", "utility", [1, 2], (120, {"scrap": 10}), 6, {"t1": 2},
  "어디서 떼어 왔는지는 탱크에 적힌 남의 회사 이름이 말해 준다.", supply={"water": 120})
F("water_pipe", "수도관 몰래 잇기", "수도", "water_pipe", "water", "utility", [1, 1], (300,), 35, {},
  "성채 밖 수도관에 구멍 하나. 요금은 옆 동네가 낸다. 자리는 적게, 돈은 많이.", supply={"water": 250})
F("water_plant", "끓여 거르는 정수장", "정수장", "water_plant", "water", "utility", [2, 2], (1200, {"scrap": 40, "parts": 2}), 50, {"t3": 4},
  "거르고 끓여 보내는 큰 설비. 전기가 든다.", supply={"water": 600}, power=10)
# 전기
F("gen_small", "털털이 발전기", "발전기", "gen_small", "power", "utility", [1, 2], (150, {"scrap": 10}), 25, {"t2": 1},
  "털털거리는 중고 발전기. 옆집은 잠을 못 잔다.", supply={"power": 40}, tags=["noise"])
F("power_tap", "전봇대 문어발", "문어발", "power_tap", "power", "utility", [1, 1], (400,), 140, {},
  "전봇대 하나에 전선 마흔 가닥. 자리는 적게, 돈은 많이.", supply={"power": 150})
F("power_plant", "성채 발전소", "발전소", "power_plant", "power", "utility", [2, 2], (1500, {"scrap": 60, "parts": 3}), 120, {"t3": 6},
  "성채의 심장. 설비 부품이 든다.", supply={"power": 300}, tags=["noise"])
F("power_waste", "쓰레기 화력 발전", "화력", "power_waste", "power", "utility", [2, 2], (3000, {"scrap": 80, "parts": 6}), 200, {"t3": 4, "t4": 2},
  "쓰레기를 태워 불을 켠다. 냄새는 덤. 도면이 있어야 짓는다(옛 발전소 탐험).", supply={"power": 800}, blueprint="power_waste")
# 먹을 것
F("food_cans", "찌그러진 캔 은행", "캔 은행", "food_cans", "food", "food", [1, 2], (80,), 3, {"t1": 4},
  "찌그러진 캔만 받는다. 멀쩡한 캔을 어디서 찌그러뜨려 오는지는 묻지 않는다.", recipe={"in": {}, "out": {"cans": 40}})
F("food_pilgrims", "마감 세일 순례단", "순례단", "food_pilgrims", "food", "food", [1, 2], (50,), 2, {"t1": 6},
  "폐점 30분 전 마트를 순례한다. 계산대를 지났는지는 기도로 해결.", recipe={"in": {}, "out": {"cans": 50}})
F("noodle_mill", "수타 제면소", "제면", "noodle_mill", "food", "food", [1, 2], (100, {"scrap": 5}), 4, {"t1": 4},
  "밀가루는 어디서 났냐고요? 그건 묻지 않는 게 예의다.", recipe={"in": {}, "out": {"noodles": 40}}, water=6, tags=["noise"])
F("noodle_stall", "완탕 한 그릇", "완탕", "noodle_stall", "food", "food", [1, 2], (120,), 4, {"t2": 3},
  "국물은 어제 것에 오늘 것을 붓는다. 깊은 맛의 비결.", recipe={"in": {"noodles": 20}, "out": {"wonton": 30}}, water=4)
F("rat_farm", "쥐덫 조합", "쥐덫", "rat_farm", "food", "food", [1, 2], (150, {"scrap": 10}), 5, {"t2": 3},
  "조합원 모두 덫 놓기 1급. 자격증은 조합장이 손으로 그렸다.", recipe={"in": {}, "out": {"ratmeat": 24}})
F("burger", "출처 묻지 마 버거", "버거", "burger", "food", "food", [1, 2], (400, {"scrap": 15}), 10, {"t3": 4},
  "패티의 출처를 묻는 손님에겐 감자튀김을 하나 더 준다.", recipe={"in": {"ratmeat": 20}, "out": {"burger": 30}})
F("sushi", "어제 잡은 스시", "스시", "sushi", "food", "food", [1, 2], (1200, {"scrap": 20}), 25, {"t4": 3},
  "어제 잡았다. 몇 년 어제인지는 말하지 않았다. 생선은 수입한다.", recipe={"in": {"fish": 10}, "out": {"sushi": 20}}, water=4, power=4)
F("roof_garden", "하늘 텃밭", "텃밭", "roof_garden", "food", "food", [1, 2], (600, {"scrap": 20}), 8, {"t1": 2},
  "옥상 스티로폼 상자 농장. 위가 뚫린 3층 이상에만, 위에 뭘 지으면 해가 안 들어 멈춘다.", recipe={"in": {}, "out": {"veg": 12}},
  water=6, needs_sky=True, min_floor=2)
F("brewery", "부스러기 양조장", "양조장", "brewery", "food", "goods", [1, 2], (100,), 3, {"t1": 3},
  "빵 부스러기와 비스킷을 모아 빚는다. 가끔은 옆 도시 트럭에서 무료로 받아오기도 한다. 받아왔는지는 알 수 없지만요.",
  recipe={"in": {}, "out": {"moonshine": 25}})
# 생활품
F("clothes_bin", "수거함 정리단", "헌 옷", "rag_collect", "goods", "goods", [1, 2], (60,), 2, {"t1": 3},
  "헌 옷 수거함은 기부함이 아니라 공용 옷장이라는 학설을 따른다.", recipe={"in": {}, "out": {"oldclothes": 12}})
F("rag_collect", "넝마 수거단", "넝마", "rag_collect", "goods", "goods", [1, 2], (80,), 3, {"t1": 3},
  "버린 천은 모두 넝마가 된다. 널어 둔 천도 가끔.", recipe={"in": {}, "out": {"rags": 20}})
F("oil_collect", "기름 수거단", "기름", "oil_collect", "goods", "goods", [1, 2], (60,), 2, {"t1": 3},
  "식당 뒷문의 폐식용유를 모은다. 앞문으로 받은 적은 없다.", recipe={"in": {}, "out": {"oil": 20}})
F("candle_shop", "초 공방", "초", "candle", "goods", "goods", [1, 2], (80,), 3, {"t1": 3},
  "폐식용유를 녹여 초를 붓는다. 정전이 대목이다.", recipe={"in": {"oil": 10}, "out": {"candle": 20}})
F("soap_shop", "비누 공방", "비누", "soap", "goods", "goods", [1, 2], (120,), 5, {"t2": 3},
  "같은 기름으로 비누를 굳힌다. 초와 비누의 차이는 심지 하나.", recipe={"in": {"oil": 10}, "out": {"soap": 20}})
F("tailor", "봉제방", "봉제", "tailor", "goods", "goods", [1, 2], (120, {"scrap": 10}), 5, {"t2": 4},
  "재봉틀 여섯 대가 쉬지 않는다. 넝마가 옷이 된다.", recipe={"in": {"rags": 12}, "out": {"clothes": 12}})
F("suit_shop", "맞춤 양복점", "양복", "suit", "goods", "goods", [1, 2], (500, {"scrap": 20}), 15, {"t3": 4},
  "넝마로 지은 양복. 재단사는 '빈티지'라고 부른다.", recipe={"in": {"rags": 12}, "out": {"suit": 6}})
F("radio_shop", "전파사", "전파사", "radio", "electronics", "goods", [1, 2], (400, {"scrap": 20}), 12, {"t3": 4},
  "고장 난 라디오 세 대로 멀쩡한 한 대를 만든다. 전기가 든다.", recipe={"in": {"elec_scrap": 4}, "out": {"radio": 4}}, power=6)
F("assembly", "조립소", "조립", "assembly", "electronics", "goods", [2, 2], (1500, {"scrap": 40, "parts": 2}), 40, {"t3": 4, "t4": 2},
  "라디오를 뜯어 가전을 만든다. 남는 나사는 다음 가전에.", recipe={"in": {"radio": 2, "elec_scrap": 6}, "out": {"appliance": 4}}, power=12)
# 놀 것·서비스
F("mahjong", "패가망신 클럽", "마작", "mahjong", "service", "service", [1, 2], (100,), 3, {"t1": 2},
  "패 섞는 소리에 잠드는 동네. 가산 탕진은 셀프 서비스.", services=["mahjong"], range=R(4))
F("teahouse", "하루 종일 한 잔", "찻집", "teahouse", "service", "service", [1, 2], (120,), 4, {"t2": 2},
  "차 한 잔 시키고 하루를 앉아 있는다. 주인도 같이 앉아 있다.", services=["teahouse"], range=R(4))
F("karaoke", "음치 해방구", "노래방", "karaoke", "service", "service", [1, 2], (350,), 10, {"t2": 3},
  "음정은 자유. 이웃의 수면권은 협의 중. 전기가 든다.", services=["karaoke"], range=R(5), power=8)
F("shrine", "아무 신이나 사당", "사당", "shrine", "service", "service", [1, 1], (40,), 1, {"t1": 1},
  "누구 신인지는 모른다. 향은 일단 피운다.", services=["shrine"], range=R(4))
F("study", "족보 공부방", "공부방", "study", "service", "service", [1, 2], (350,), 10, {"t3": 3},
  "족보로 공부해 족보를 만든다. 연구도 여기서 한다.", services=["study"], range=R(5))
F("bathhouse", "때밀이 성전", "목욕탕", "bathhouse", "service", "service", [2, 2], (900, {"scrap": 20}), 15, {"t2": 4},
  "때를 밀면 업보도 밀린다고 믿는 곳. 행복한 동네에만 문을 연다.", services=["bath"], range=R(5), water=30, luxury=True)
F("dentist", "발치 전문", "치과", "dentist", "service", "service", [1, 2], (900,), 12, {"t3": 2},
  "발치 전문. 마취는 별도, 면허는 본토에.", services=["dentist"], range=R(5), luxury=True,
  vice={"income": 0, "heat": 1, "raid_line": "발치 전문에 단속. 면허는 여전히 본토에 있다고 한다."})
F("pharmacy", "약 비슷한 것 약국", "약국", "pharmacy", "service", "service", [1, 2], (900,), 12, {"t3": 2},
  "약과 비슷하게 생겼다. 효과도 비슷할지 모른다.", services=["pharmacy"], range=R(5), luxury=True)
F("salon", "가위손 이모", "미용실", "salon", "service", "service", [1, 2], (1500,), 18, {"t4": 2},
  "이모의 가위는 자비가 없다. 대신 수다는 공짜.", services=["salon"], range=R(5), luxury=True)
F("roof_park", "하늘 공원", "공원", "roof_park", "service", "service", [2, 2], (1200, {"scrap": 20}), 8, {"t1": 1},
  "빨래 줄 사이에 벤치 둘. 성채에서 하늘이 제일 넓게 보인다. 위가 뚫린 3층 이상.", services=["roof"], range=R(5, 0, 2),
  water=4, needs_sky=True, min_floor=2, luxury=True)
# 방재
F("fire_bucket", "양동이 소방대", "소방대", "fire_bucket", "safety", "utility", [1, 2], (80,), 3, {"t1": 2},
  "양동이 서른 개와 목청 큰 대장. 불보다 먼저 소리가 도착한다.", services=["fire"], range=R(4))
F("fire_station", "무허가 소방서", "소방서", "fire_station", "safety", "utility", [2, 2], (900, {"scrap": 30}), 20, {"t2": 4, "t3": 2},
  "소방차는 없다. 대신 지붕 위로 뛰는 사람들이 있다.", services=["fire"], range=R(6, 2, 2))
F("trash_guild", "넝마주이 조합", "넝마주이", "trash_guild", "safety", "utility", [1, 2], (100,), 3, {"t1": 3},
  "쓰레기를 치워 주고 쓸 만한 건 챙겨 간다. 조합 회비는 그걸로 낸다.", services=["trash"], range=R(4))
F("clinic", "무면허 의원", "의원", "clinic", "safety", "utility", [1, 2], (150,), 5, {"t2": 2},
  "면허는 액자 안에. 액자는 빌린 것.", services=["clinic"], range=R(4))
# 기반
F("scrapyard", "고물 분해소", "고물", "scrapyard", "infra", "other", [1, 2], (80,), 2, {"t1": 3},
  "뭐든 뜯으면 고물이 된다. 뜯긴 쪽의 의견은 받지 않는다. 가끔 쓸 만한 기판도 나온다.",
  recipe={"in": {}, "out": {"scrap": 10, "elec_scrap": 0.5}}, tags=["noise"])
F("warehouse", "쌓아 두는 곳", "창고", "warehouse", "infra", "other", [1, 2], (100,), 3, {"t1": 2},
  "물건을 쌓아 두는 곳. 꺼낼 때가 문제다.", storage=True)
F("trade_post", "뒷문 무역관", "무역관", "trade_post", "infra", "other", [1, 2], (200,), 6, {"t2": 2},
  "정문은 없다. 뒷문으로만 거래한다. 정기 계약 2자리.", contract_slots=2)
F("expedition_base", "줍줍 본부", "줍줍", "expedition_base", "infra", "other", [1, 2], (100,), 2, {},
  "탐험대의 집결지. 줍는 사람이 임자다. 탐험대 1팀(최대 3).", teams=1)
# 음성
F("gambling_den", "딱 한 판만", "한 판", "gambling", "vice", "vice", [1, 2], (150,), 4, {"t1": 3},
  "딱 한 판만 하고 간다던 사람이 3년째 앉아 있다. 마작 수요도 채운다.", services=["mahjong"], range=R(4),
  vice={"income": 30, "heat": 3, "raid_line": "'딱 한 판만' 문에 경찰 테이프. 판돈은 증거물이 되었다."}, tags=["vice"])
F("callcenter", "고객님 상담실", "상담실", "callcenter", "vice", "vice", [1, 2], (500,), 15, {"t1": 6, "t2": 4},
  "고객님, 검찰청입니다.", power=15, vice={"income": 160, "heat": 8, "raid_line": "'고객님, 검찰청입니다' — 이번엔 진짜 검찰청이 전화를 받았다."}, tags=["vice"])
F("casino", "돌려막기 카지노", "카지노", "casino", "vice", "vice", [2, 2], (2500, {"scrap": 40}), 60, {"t2": 8, "t3": 4},
  "이번 판으로 지난 판을 막는다. 하우스는 돌려막지 않는다.", floors=2, services=["casino"], range=R(6, 2, 1), power=30,
  vice={"income": 500, "heat": 12, "raid_line": "카지노에 단속. 손님들은 다들 지나가던 길이었다고 한다."}, tags=["vice"])
F("fireworks", "화약 가공소", "폭죽", "fireworks", "vice", "vice", [1, 2], (300,), 8, {"t1": 4},
  "폭죽을 말아 수출한다. 불조심은 표어로만.", recipe={"in": {"scrap": 2}, "out": {"firework": 8}}, tags=["vice", "noise"],
  vice={"income": 0, "heat": 5, "raid_line": "화약 가공소가 봉인됐다. 이웃들은 처음으로 조용한 밤을 보낸다."})
F("fake_shop", "거의 명품 공방", "명품", "fake", "vice", "vice", [1, 2], (400,), 10, {"t2": 4, "t3": 2},
  "로고가 진짜보다 크다. 그게 거의 명품의 '거의'다.", recipe={"in": {"rags": 3, "elec_scrap": 1}, "out": {"fakelux": 4}}, tags=["vice"],
  vice={"income": 0, "heat": 4, "raid_line": "거의 명품 공방 압수. 압수품 목록에 '진짜'라고 적힌 상자가 있었다."})
# 명소
F("neon_tower", "네온 용탑", "용탑", "landmark_generic", "landmark", "service", [2, 2], (8000, {"wood": 40, "metal": 40, "concrete": 40, "parts": 5}), 30, {"t4": 2},
  "용 한 마리가 탑을 감고 있다. 전기 요금도 감고 있다. 두 개 층.", floors=2, services=["landmark"], range=R(8, 3, 3), landmark=True, build_days=2.0)
F("city_hall", "무허가 구청", "구청", "landmark_hall", "landmark", "service", [3, 3], (25000, {"wood": 150, "metal": 150, "concrete": 150, "parts": 20}), 50, {"t4": 4},
  "도장도 서류도 다 있다. 허가만 없다. 세 자재를 모두 쓴다 — 마지막 목표.", services=["landmark"], range=R(12, 4, 4), landmark=True, build_days=3.0)

save("buildings/buildings.json", OD(
    _comment="시설(v0.4 PC). footprint = [w,h](x방향 w칸, y방향 h칸, rot 1이면 바뀜), floors = 쌓이는 층 수(1|2). cost = 돈 + 상품, upkeep = ₩/경제일, workforce = 계층별 인원, priority = 노동·물·전기 배분 순위, build_days = 공사 경제일(없으면 config build.days_by_cells), recipe = 경제일당 입력→출력, water/power = 가동 중 부하, supply = 공급, market = 취급 등급, services = 서비스 태그(fire/trash/clinic은 방재 — hazards가 읽음), range = {r: 가로·세로 칸(체비쇼프), up, down: 층}, needs_sky = 위가 비어야(위에 지으면 멈춤), min_floor = 이 층(z) 이상, luxury = 사치 시설(해금에 행복 유지 조건), look = 뷰 외형 이름표(ARCHITECTURE v4), sign = 간판(한글 4자 이내, 한자 금지), vice = 음성(income, heat, raid_line).",
    status="실험값(v0.4 — 시뮬레이션으로 맞춤)",
    cats=OD(house="주거", market="시장", water="물", power="전기", food="먹을 것", goods="생활품", electronics="전자", service="놀 것·서비스",
            safety="방재", vice="음성", infra="기반", landmark="명소"),
    items=B))

# ------------------------------------------------------------------ 계층
tiers = OD()
for i, (name, desc, cap, labor, tax, water, power) in enumerate([
    ("굴러온 돌", "어디선가 굴러 들어온 사람들. 판자와 양철로 버틴다.", 4, 0.75, 3.0, 1.0, 0.0),
    ("월세 전사", "월세 날마다 전투를 치르는 사람들.", 8, 1.0, 3.2, 1.5, 0.0),
    ("박힌 돌", "성채에 뿌리내린 사람들. 굴러온 돌을 빼려 한다. 전기 없이는 못 산다.", 12, 1.0, 4.8, 2.0, 1.0),
    ("깡통 귀족", "깡통 위에 앉은 귀족. 체면이 반, 허세가 반.", 8, 1.0, 10.0, 3.0, 2.0),
    ("옥상 황제", "성채 꼭대기에서 아래를 내려다보는 사람들.", 6, 1.0, 24.0, 4.0, 3.5)], start=1):
    tiers["t%d" % i] = OD(index=i, name=name, desc=desc, cap=cap, labor=labor, tax=tax, water=water, power=power)
save("population/tiers.json", OD(_comment="다섯 계층(v0.4 이름). cap = 정원(확정 4-8-12-8-6), labor = 노동 참여(확정: 굴러온 돌만 0.75), tax = ₩/인·경제일, water = 물/인·경제일, power = 전기/인.",
                                 status="cap·labor 확정 / tax·water·power 실험값", items=tiers))

# ------------------------------------------------------------------ 수요
needs = OD()
def N(i, tier, role, name, opts, share=None, amount=None, count=None, food=False):
    n = OD(tier=tier, role=role)
    if share is not None: n["share"] = share
    n["name"] = name
    if amount is not None: n["amount"] = amount
    if count is not None: n["count"] = count
    if food: n["food"] = True
    n["options"] = opts
    needs[i] = n
W = [{"utility": "water"}]
P = [{"utility": "power"}]
g = lambda x: {"good": x}
s = lambda x: {"service": x}
# 굴러온 돌 (4)
N("t1_water", 1, "basic", "식수", W, 1)
N("t1_food", 1, "basic", "끼니(통조림)", [g("cans")], 2, 0.30, food=True)
N("t1_fun", 1, "basic", "놀 거리", [s("mahjong")], 1)
N("t1_clothes", 1, "advance", "헌 옷", [g("oldclothes")], amount=0.03)
N("t1_light", 1, "advance", "등불", [g("candle")], amount=0.04)
N("t1_booze", 1, "luxury", "밀주", [g("moonshine")], amount=0.05)
N("t1_shrine", 1, "luxury", "사당", [s("shrine")])
# 월세 전사 (8)
N("t2_water", 2, "basic", "식수", W, 2)
N("t2_food", 2, "basic", "끼니(통조림)", [g("cans")], 2, 0.20, food=True)
N("t2_wonton", 2, "basic", "완탕면", [g("wonton")], 1, 0.15, food=True)
N("t2_clothes", 2, "basic", "옷", [g("clothes")], 1, 0.05)
N("t2_light", 2, "basic", "등불 또는 전기", [{"utility": "power", "amount": 0.5, "prefer": True}, g("candle")], 1, 0.05)
N("t2_fun", 2, "basic", "놀 거리", [s("mahjong"), s("teahouse")], 1, count=1)
N("t2_soap", 2, "advance", "비누", [g("soap")], amount=0.04)
N("t2_booze", 2, "advance", "밀주", [g("moonshine")], amount=0.06)
N("t2_shrine", 2, "luxury", "사당", [s("shrine")])
N("t2_bath", 2, "luxury", "목욕탕", [s("bath")])
# 박힌 돌 (12)
N("t3_water", 3, "basic", "식수", W, 2)
N("t3_wonton", 3, "basic", "완탕면", [g("wonton")], 2, 0.20, food=True)
N("t3_burger", 3, "basic", "쥐고기 버거", [g("burger")], 2, 0.15, food=True)
N("t3_clothes", 3, "basic", "옷", [g("clothes")], 1, 0.06)
N("t3_soap", 3, "basic", "비누", [g("soap")], 1, 0.04)
N("t3_power", 3, "basic", "전기", P, 2)
N("t3_fun", 3, "basic", "놀 거리", [s("karaoke"), s("teahouse"), s("mahjong")], 1, count=1)
N("t3_booze", 3, "basic", "밀주", [g("moonshine")], 1, 0.06)
N("t3_radio", 3, "advance", "라디오", [g("radio")], amount=0.010)
N("t3_study", 3, "advance", "공부방", [s("study")])
N("t3_bath", 3, "luxury", "목욕탕", [s("bath")])
N("t3_dentist", 3, "luxury", "치과", [s("dentist")])
N("t3_pharmacy", 3, "luxury", "약국", [s("pharmacy")])
# 깡통 귀족 (8)
N("t4_water", 4, "basic", "식수", W, 1)
N("t4_burger", 4, "basic", "쥐고기 버거", [g("burger")], 1, 0.10, food=True)
N("t4_sushi", 4, "basic", "스시", [g("sushi")], 1, 0.10, food=True)
N("t4_suit", 4, "basic", "양복", [g("suit")], 1, 0.02)
N("t4_power", 4, "basic", "전기", P, 2)
N("t4_appl", 4, "basic", "가전", [g("appliance")], 1, 0.010)
N("t4_fun", 4, "basic", "놀 거리", [s("karaoke"), s("casino")], 1, count=1)
N("t4_liquor", 4, "advance", "양주", [g("liquor")], amount=0.02)
N("t4_fake", 4, "advance", "짝퉁 명품", [g("fakelux")], amount=0.010)
N("t4_salon", 4, "luxury", "미용실", [s("salon")])
N("t4_pharmacy", 4, "luxury", "약국", [s("pharmacy")])
N("t4_roof", 4, "luxury", "하늘 공원", [s("roof")])
# 옥상 황제 (6)
N("t5_water", 5, "basic", "식수", W, 1)
N("t5_sushi", 5, "basic", "스시", [g("sushi")], 1, 0.10, food=True)
N("t5_veg", 5, "basic", "신선 채소", [g("veg")], 1, 0.10, food=True)
N("t5_suit", 5, "basic", "양복", [g("suit")], 1, 0.03)
N("t5_power", 5, "basic", "전기", P, 1)
N("t5_liquor", 5, "basic", "양주", [g("liquor")], 1, 0.03)
N("t5_fake", 5, "luxury", "짝퉁 명품", [g("fakelux")], amount=0.015)
N("t5_casino", 5, "luxury", "카지노", [s("casino")])
N("t5_landmark", 5, "luxury", "명소", [s("landmark")])
N("t5_salon", 5, "luxury", "미용실", [s("salon")])
save("population/needs.json", OD(
    _comment="계층별 수요(v0.4). role: basic(정원 몫 share — 계층마다 합 = 정원) / advance(승급 조건) / luxury(행복·세수). options = 대체 묶음({good}|{service}|{utility}), count = 그중 몇 종을 동시에. amount = 상품 소비량/인·경제일. food = 끼니(연구·정책의 cons.food가 닿는다). 1층부터 필수 셋: 먹을 것(시장 + 통조림) · 물 · 놀 거리(마작방). 먹을 것 사다리: 통조림 → 완탕면 → 쥐고기 버거 → 스시 → 신선 채소.",
    status="실험값", items=needs))

# ------------------------------------------------------------------ 해금
U = OD()
def UL(i, order, cond, unlocks, grade=None, title=None, features=None, final=False):
    u = OD(order=order, cond=cond, unlocks=unlocks)
    if features: u["features"] = features
    if grade: u["grade_name"] = grade
    if title: u["title"] = title
    if final: u["final"] = True
    U[i] = u
UL("start", 0, [], ["house", "market_mat", "food_cans", "rain_catcher", "mahjong", "expedition_base"], "공터", "무단 점유 대표")
UL("t1_20", 1, [["pop.t1", ">=", 20]], ["food_pilgrims", "clothes_bin", "oil_collect", "candle_shop", "shrine", "warehouse", "scrapyard"], "판자촌", "자칭 반장")
UL("t1_60", 2, [["pop.t1", ">=", 60]], ["brewery", "water_tank", "noodle_mill"])
UL("t2_1", 3, [["pop.t2", ">=", 1]], ["market_alley", "noodle_stall", "rag_collect", "tailor", "soap_shop", "teahouse", "gambling_den"], "골목", "비공식 통장")
UL("floor2", 4, [["floors", ">=", 2]], ["fire_bucket"])
UL("t2_40", 5, [["pop.t2", ">=", 40]], ["trade_post", "gen_small", "power_tap", "rat_farm", "study"], features=["policy_slot_1"])
UL("floor3", 6, [["floors", ">=", 3]], ["trash_guild", "clinic"])
UL("t3_1", 7, [["pop.t3", ">=", 1]], ["market_hall", "burger", "karaoke", "radio_shop", "suit_shop", "water_pipe"], "성채", "무허가 구청장")
UL("lux_bath", 8, [["pop.t2", ">=", 80], ["happy_held.60", ">=", 1.0]], ["bathhouse"])
UL("t3_80", 9, [["pop.t3", ">=", 80]], ["power_plant", "water_plant", "fire_station", "fake_shop", "callcenter", "fireworks"], features=["policy_slot_2"])
UL("lux_health", 10, [["pop.t3", ">=", 60], ["happy_held.60", ">=", 1.5]], ["dentist", "pharmacy"])
UL("t4_1", 11, [["pop.t4", ">=", 1]], ["market_mall", "sushi", "assembly", "casino", "roof_garden"], "구룡", "세금 안 내는 시장님")
UL("lux_top", 12, [["pop.t4", ">=", 40], ["happy_held.65", ">=", 2.0]], ["salon", "roof_park"])
UL("t4_60", 13, [["pop.t4", ">=", 60]], ["neon_tower", "power_waste"], features=["policy_slot_3"])
UL("t4_100", 14, [["pop.t4", ">=", 100]], ["city_hall"])
UL("final", 15, [["pop.t5", ">=", 120], ["count.city_hall", ">=", 1]], [], "구룡성채", "지도에 없는 곳의 따거", final=True)
save("progression/unlocks.json", OD(
    _comment="해금 단계(v0.4). cond = Expr 조건(지표: pop.tN = 계층 인구(대기 포함), count.<시설>, floors, happy_held.<n> = 도시 행복도가 n 이상으로 이어진 경제일, money, day). 한 번 열리면 닫히지 않는다. grade_name/title = 성채 등급·호칭(§8). features = 정책 칸 등. 사치 시설(luxury)은 '행복도 n을 m일 유지' 조건을 함께 쓴다.",
    status="실험값", items=U))

# ------------------------------------------------------------------ 목표
goals = OD()
def GO(i, order, text, cond, rewards=None, unlock=None, final=False):
    x = OD(order=order, text=text, cond=cond)
    if unlock: x["unlock"] = unlock
    if final: x["final"] = True
    x["rewards"] = rewards or {}
    goals[i] = x
GO("g_zone", 1, "판잣집 8채를 칠해 굴러온 돌을 받아라", [["houses.t1", ">=", 8]], {"money": 250})
GO("g_basics", 2, "1층의 필수 셋 — 돗자리 장터·캔 은행(먹을 것), 하늘 수도국(물), 패가망신 클럽(놀 것)",
   [["count.market_mat", ">=", 1], ["count.food_cans", ">=", 1], ["count.rain_catcher", ">=", 1], ["count.mahjong", ">=", 1]], {"money": 300})
GO("g_t1_20", 3, "굴러온 돌 20명", [["pop.t1", ">=", 20]], {"money": 200}, unlock="t1_20")
GO("g_exp", 4, "줍줍 본부를 짓고 탐험대를 고물 야적장에 보내라", [["stat.exp_sent", ">=", 1]], {"money": 150})
GO("g_claim", 5, "돌아온 탐험대의 짐을 풀어라", [["stat.exp_claims", ">=", 1]], {"reveal": ["old_factory", "back_docks"]})
GO("g_t2_1", 6, "첫 월세 전사 — 헌 옷·초를 갖춘 만실 판잣집을 올려라(목재·철제·콘크리트 중 하나를 고르면 그게 외관이 된다)",
   [["pop.t2", ">=", 1]], {"money": 300}, unlock="t2_1")
GO("g_wonton", 7, "수타 제면소에서 생면을 뽑고 '완탕 한 그릇'을 끓여라(첫 2단 사슬)", [["stat.prod.wonton", ">=", 10]], {"money": 300})
GO("g_floor2", 8, "1층의 80%를 쓰이는 칸으로 채워 2층을 열어라 — 2층부터는 불이 난다", [["floors", ">=", 2]], {"money": 400}, unlock="floor2")
GO("g_fire", 9, "양동이 소방대로 쓰이는 칸을 덮어라(위아래 한 층까지 닿는다)", [["count.fire_bucket", ">=", 2]], {"money": 300})
GO("g_t2_40", 10, "월세 전사 40명", [["pop.t2", ">=", 40]], {"money": 300}, unlock="t2_40")
GO("g_power", 11, "털털이 발전기를 돌려 성채에 첫 전기를 들여라", [["power.supply", ">=", 1]], {"money": 300})
GO("g_t3_1", 12, "첫 박힌 돌 — 비누·밀주를 갖춘 만실 월세 전사 집을 올려라", [["pop.t3", ">=", 1]], {"money": 400}, unlock="t3_1")
GO("g_mid", 13, "중거리(폐공장·부두 뒷골목)에 다녀와 거래처를 찾아라", [["stat.exp_claims_mid", ">=", 1]], {"money": 300})
GO("g_floor3", 14, "2층의 80%를 채워 3층을 열어라 — 3층부터는 쓰레기가 병을 부른다", [["floors", ">=", 3]], {"money": 600}, unlock="floor3")
GO("g_disease", 15, "넝마주이 조합(쓰레기)과 무면허 의원(병)을 세워라", [["count.trash_guild", ">=", 1], ["count.clinic", ">=", 1]], {"money": 400})
GO("g_trade", 16, "뒷문 무역관을 짓고 계약을 하나 맺어라(남는 것을 팔고 사치품을 들인다)", [["count.trade_post", ">=", 1], ["contracts", ">=", 1]], {"money": 300})
GO("g_t3_80", 17, "박힌 돌 80명", [["pop.t3", ">=", 80]], {"money": 800}, unlock="t3_80")
GO("g_lux", 18, "행복한 동네를 지켜 사치 시설(목욕탕·치과·약국…)을 하나 열고 지어라", [["lux_built", ">=", 1]], {"money": 800})
GO("g_t4_1", 19, "첫 깡통 귀족 — 라디오·공부방을 갖춘 만실 박힌 돌 집을 올려라", [["pop.t4", ">=", 1]], {"money": 1000}, unlock="t4_1")
GO("g_far", 20, "원거리 탐험에서 설비 부품을 들여라", [["stat.exp_claims_far", ">=", 1]], {"stock": {"parts": 2}})
GO("g_tower", 21, "네온 용탑을 세워라(첫 명소, 두 개 층)", [["count.neon_tower", ">=", 1]], {"money": 2000}, unlock="t4_60")
GO("g_t5_1", 22, "첫 옥상 황제 — 양주·짝퉁 명품을 갖춘 만실 깡통 귀족 집을 설비 부품으로 올려라", [["pop.t5", ">=", 1]], {"money": 2000})
GO("g_hall", 23, "무허가 구청을 세워라(3×3, 세 자재 각 150 + 설비 부품 20)", [["count.city_hall", ">=", 1]], {"money": 3000}, unlock="t4_100")
GO("g_final", 24, "옥상 황제 120명과 무허가 구청 — 지도에 없는 곳의 따거가 되어라", [["pop.t5", ">=", 120], ["count.city_hall", ">=", 1]], {}, unlock="final", final=True)
save("progression/goals.json", OD(
    _comment="단계 목표(v0.4 PC, 24단계). order 순서로 hud.next_goal에 하나씩 보인다(먼저 이룬 것은 그때 끝난다). cond = Expr 조건(Metrics 지표: pop.tN, houses.tN, count.<시설>, floors, contracts, lux_built(사치 시설 완공 수), stat.<통계>…). rewards: money, stock{상품:n}, reveal[목적지]. unlock = 같은 순간 열리는 해금 단계 id(보상 문구용). final = 마지막(이후 샌드박스).",
    status="제안(문구) / 실험값(보상)", items=goals))

# ------------------------------------------------------------------ 목적지(던전)
D = OD()
def DS(i, name, band, days, mp, known, desc, primary, bonus, stock, cost, danger, reveals=None, finds=None, picks=None, hint=None, run=None):
    d = OD(name=name, band=band, days=days, map=mp, known=known)
    if hint: d["reveal_hint"] = hint
    d["desc"] = desc
    if picks: d["picks"] = picks
    d["primary"] = primary
    d["bonus"] = bonus
    if finds: d["finds"] = finds
    if reveals: d["reveals"] = reveals
    d["stock"] = stock
    d["regen"] = 0.5
    d["danger"] = danger
    d["cost"] = {"money": cost}
    if run: d["run"] = run
    D[i] = d
P1 = lambda gd, lo, hi: OD(good=gd, min=lo, max=hi)
BO = lambda gd, lo, hi, ch=1.0: OD(good=gd, min=lo, max=hi, chance=ch)
DS("junk_yard", "고물 야적장", "near", 0.3, [0.64, 0.6], True, "녹슨 프레임과 패널이 쌓인 야적장. 들개가 주인 행세를 한다.",
   P1("metal", 8, 8), [BO("scrap", 3, 6)], {"metal": 60, "scrap": 40}, 0, 1, reveals=["old_factory", "back_docks"])
DS("landfill", "쓰레기 매립지", "near", 0.3, [0.36, 0.62], True, "문짝과 장롱이 묻힌 매립지. 파면 나온다. 냄새도 나온다.",
   P1("wood", 8, 8), [BO("scrap", 3, 6)], {"wood": 60, "scrap": 40}, 0, 1, reveals=["old_factory", "back_docks"])
DS("demo_site", "철거 현장", "near", 0.3, [0.5, 0.33], True, "헐다 만 아파트. 쓸 만한 블록을 추린다. 남은 벽이 언제 무너질지는 모른다.",
   P1("concrete", 8, 8), [BO("scrap", 3, 6)], {"concrete": 60, "scrap": 40}, 0, 1, reveals=["old_factory", "back_docks"])
DS("old_factory", "폐공장", "mid", 1.0, [0.18, 0.4], False, "문 닫은 공장. 자재를 골라 실어 오고, 본토 보따리상과 줄이 닿는다.",
   P1("", 26, 30), [BO("elec_scrap", 4, 8), BO("scrap", 10, 20), BO("parts", 1, 1, 0.1)], {"wood": 120, "metal": 120, "concrete": 120, "elec_scrap": 40, "scrap": 80},
   30, 2, reveals=["waste_plant", "ghost_town"], finds=[OD(type="partner", id="mainland", once=True)], picks=["wood", "metal", "concrete"],
   hint="근거리 탐험에서 처음 돌아오면 알게 된다")
DS("back_docks", "부두 뒷골목", "mid", 1.0, [0.84, 0.36], False, "밤에만 열리는 부두. 고물과 전자 폐품, 그리고 암시장 사람들.",
   P1("elec_scrap", 10, 14), [BO("scrap", 20, 30), BO("parts", 1, 1, 0.15)], {"elec_scrap": 80, "scrap": 120},
   30, 2, reveals=["old_plant"], finds=[OD(type="partner", id="docks", once=True)], hint="근거리 탐험에서 처음 돌아오면 알게 된다")
DS("waste_plant", "폐기물 처리장", "far", 3.0, [0.92, 0.1], False, "아무도 처리하지 않는 처리장. 철골을 뜯고 설비 부품을 챙긴다. 두목은 덩치 큰 집게차.",
   P1("metal", 70, 75), [BO("parts", 1, 1), BO("scrap", 20, 30), BO("elec_scrap", 4, 8)], {"metal": 250, "parts": 6, "scrap": 100, "elec_scrap": 30},
   80, 3, hint="폐공장을 다녀오거나 연구 '약도 그리기'")
DS("ghost_town", "버려진 신도시", "far", 3.0, [0.06, 0.12], False, "짓다 만 고층 단지. 목재·콘크리트를 골라 온다.",
   P1("", 70, 75), [BO("parts", 1, 1), BO("scrap", 20, 30)], {"wood": 250, "concrete": 250, "metal": 250, "parts": 6, "scrap": 100},
   80, 3, picks=["wood", "concrete", "metal"], hint="폐공장을 다녀오거나 연구 '약도 그리기'")
DS("old_plant", "옛 발전소", "far", 4.0, [0.9, 0.86], False, "녹슨 터빈이 서 있는 발전소. 처음 가면 쓰레기 화력 발전 도면을 찾는다.",
   P1("parts", 3, 4), [BO("scrap", 30, 50), BO("metal", 20, 30), BO("elec_scrap", 6, 10)], {"parts": 12, "scrap": 150, "metal": 90, "elec_scrap": 30},
   80, 4, finds=[OD(type="blueprint", id="power_waste", once=True)], hint="부두 뒷골목을 다녀오거나 연구 '약도 그리기'",
   run={"boss": {"parts": 2}})
dest = load("exploration/destinations.json")
dest["_comment"] = "탐험 목적지(던전, v0.4 PC). days = 게임 시계 경제일(왕복, 배속을 따른다). primary = 보장 주력(min~max, 출발 때 굴림), picks가 있으면 그중 고른 자재가 주력. bonus = 덤(chance 확률). finds = 발견(partner/blueprint, once = 첫 방문만). reveals = 처음 다녀오면 알게 되는 목적지. stock = 던전 재고(털면 줄고 하루에 최대치 × regen만큼 다시 찬다 — 자동 파견도 직접 줍기도 여기서 뺀다). danger = 직접 줍기 위험. run = 직접 줍기 설정(carry 배낭 칸, boss 두목 덤) — 전역 run을 덮어쓴다. cost = 출발 비용."
dest["provision"] = OD(goods=["cans", "wonton", "burger"], n=10, bonus=0.25, _status="실험값: 끼니 10(통조림·완탕면·버거 중 재고 많은 것부터)을 실으면 주력·덤 +25%")
dest["items"] = D
save("exploration/destinations.json", dest)

# ------------------------------------------------------------------ 거래처 — 중반 시스템: 사치품 수입 + 남는 것 팔기 + 비싼 건재
def sizes_import(base, unit_qty):
    return [OD(qty=unit_qty, interval_h=24, price=round(base * 1.1, 2)), OD(qty=unit_qty * 2, interval_h=12, price=base),
            OD(qty=unit_qty * 4, interval_h=12, price=base), OD(qty=unit_qty * 8, interval_h=12, price=round(base * 0.95, 2))]
def sizes_export(base, unit_qty):
    return [OD(qty=unit_qty, interval_h=24, price=round(base * 0.77, 2)), OD(qty=unit_qty * 2, interval_h=12, price=round(base * 0.7, 2)),
            OD(qty=unit_qty * 4, interval_h=12, price=round(base * 0.7, 2)), OD(qty=unit_qty * 8, interval_h=12, price=round(base * 0.7, 2))]
offers = OD()
def O(i, partner, good, d, sizes):
    offers[i] = OD(partner=partner, good=good, dir=d, transport=0, sizes=sizes)
O("ws_fish", "wholesaler", "fish", "import", sizes_import(6.0, 5))
O("ws_liquor", "wholesaler", "liquor", "import", sizes_import(34.0, 1))
for gd, q in [("cans", 20), ("moonshine", 10), ("wonton", 10), ("clothes", 6), ("candle", 8), ("soap", 8), ("burger", 6), ("radio", 2), ("suit", 2), ("appliance", 1)]:
    O("ws_%s_sell" % gd, "wholesaler", gd, "export", sizes_export(goods[gd]["price"], q))
O("bd_wood", "builder", "wood", "import", [OD(qty=1, interval_h=24, price=30.0), OD(qty=2, interval_h=24, price=36.0), OD(qty=3, interval_h=24, price=44.0)])
O("bd_metal", "builder", "metal", "import", [OD(qty=1, interval_h=24, price=30.0), OD(qty=2, interval_h=24, price=36.0), OD(qty=3, interval_h=24, price=44.0)])
O("bd_concrete", "builder", "concrete", "import", [OD(qty=1, interval_h=24, price=30.0), OD(qty=2, interval_h=24, price=36.0), OD(qty=3, interval_h=24, price=44.0)])
O("bd_parts", "builder", "parts", "import", [OD(qty=1, interval_h=120, price=500.0), OD(qty=1, interval_h=96, price=700.0)])
O("bd_scrap", "builder", "scrap", "import", [OD(qty=10, interval_h=12, price=3.0), OD(qty=20, interval_h=12, price=3.0), OD(qty=40, interval_h=12, price=3.0)])
O("dk_fish", "docks", "fish", "import", sizes_import(4.0, 5))
O("dk_liquor", "docks", "liquor", "import", sizes_import(22.0, 2))
O("dk_fake_sell", "docks", "fakelux", "export", sizes_export(44.0, 1))
O("dk_fw_sell", "docks", "firework", "export", sizes_export(8.6, 4))
O("ml_liquor", "mainland", "liquor", "import", sizes_import(26.0, 2))
O("ml_fake_sell", "mainland", "fakelux", "export", sizes_export(52.0, 1))
O("ml_fw_sell", "mainland", "firework", "export", sizes_export(11.4, 4))
save("economy/partners.json", OD(
    _comment="거래처와 계약 제안(v0.4: 중반 시스템 — 뒷문 무역관이 있어야 계약 자리가 생긴다). 수입은 진짜 사치품(생선·양주)과 비싼 건재뿐, 수출은 남는 것. dir = import/export. sizes = 수량 단계 {qty, interval_h 경제시간, price ₩/단위}. known = 처음부터 아는 거래처.",
    status="실험값",
    partners=OD(wholesaler=OD(name="길 건너 도매상", known=True, desc="남는 것을 사 준다. 생선·양주는 비싸게 판다."),
                builder=OD(name="건재상", known=True, desc="목재·철제·콘크리트·설비 부품을 비싸게, 조금씩(확정: 탐험 주력 + 교역은 비싸게 소량)."),
                docks=OD(name="부두 암시장", known=False, desc="생선과 양주가 싸다. 짝퉁·폭죽을 산다.", reveal_hint="부두 뒷골목 탐험에서 발견"),
                mainland=OD(name="본토 보따리상", known=False, desc="양주를 들고 온다. 짝퉁·폭죽을 비싸게 산다.", reveal_hint="폐공장 탐험에서 발견")),
    items=offers))

# ------------------------------------------------------------------ 승급 비용(구조 그대로)
uc = load("buildings/upgrade_costs.json")
uc["material_names"] = OD(common="판자·양철", wood="목재", metal="철제", concrete="콘크리트")
save("buildings/upgrade_costs.json", uc)

# ------------------------------------------------------------------ 연구·정책 이름(효과는 그대로)
rs = load("progression/research.json")
rs["branches"] = OD(living="살림", work="일", road="길")
names = {"rationing": ("솥 돌리기", "골목마다 솥을 건다. 끼니 소비 −15%."),
         "soundproof": ("솜 넣은 벽", "공장 벽에 솜을 채운다. 소음으로 깎이는 행복이 사라진다."),
         "greening": ("화분 대작전", "지붕마다 화분. 모든 주거 행복 +5."),
         "high_water": ("층마다 물탱크", "물탱크와 펌프를 층마다. 주민 물 수요 −20%."),
         "workflow": ("공구 벽에 걸기", "공구를 벽에 건다. 생산 시설 처리량 +10%."),
         "night_shift": ("불 안 끄는 공장", "불이 꺼지지 않는 작업장. 처리량 +15% 더."),
         "waste_heat": ("발전기 열로 목욕물", "발전기 열로 물을 데운다. 전기 공급 +20%."),
         "precision": ("덜 버리기 운동", "덜 버리고 덜 고친다. 시설 유지비 −15%."),
         "handcart": ("바퀴 달린 탐험", "탐험대에 바퀴를. 탐험 날짜 −15%."),
         "mapping": ("약도 그리기", "다녀온 길을 그려 둔다. 원거리 던전을 모두 알게 되고 수확 +5%."),
         "truck": ("고물 트럭", "고물 트럭 한 대. 탐험 수확 +20%."),
         "regulars": ("얼굴 아는 사이", "얼굴을 아는 거래처. 수입 단가 −10%, 수출 단가 +10%.")}
for k, (n, ds) in names.items():
    rs["items"][k]["name"] = n
    rs["items"][k]["desc"] = ds
rs["items"]["mapping"]["reveals"] = ["waste_plant", "ghost_town", "old_plant"]
save("progression/research.json", rs)
po = load("progression/policies.json")
pn = {"rations": ("반 공기 운동", "끼니를 줄여 나눈다. 끼니 소비 −20%, 행복 −8."),
      "overtime": ("퇴근은 내일", "밤까지 돌린다. 생산 처리량 +20%, 행복 −10."),
      "tax_cut": ("세금 깜빡하기", "걷는 걸 깜빡한다(일부러). 세수 −20%, 행복 +8."),
      "tax_hike": ("골목마다 수금", "골목마다 걷는다. 세수 +25%, 행복 −12."),
      "bribes": ("봉투 문화", "경찰서에 봉투를 돌린다. 단속 위험이 쌓이는 속도 −70%, 음성 시설 하나당 유지비 {upkeep_per_vice}/일."),
      "welcome": ("이삿짐 수레 지원", "이삿짐 수레를 보낸다. 입주 속도 2배, 유지비 {upkeep}/일.")}
for k, (n, ds) in pn.items():
    po["items"][k]["name"] = n
    po["items"][k]["desc"] = ds
save("progression/policies.json", po)

# ------------------------------------------------------------------ 설정
c = load("rules/config.json")
c["start"] = OD(_status="실험값(v0.4): 세 자재 12씩 + 고물 30 + 통조림 40 + 헌 옷 8·초 10(첫 승급을 맛보게 — 떨어지면 수거함 정리단·초 공방으로 이어진다)",
                money=1200, stock=OD(wood=12, metal=12, concrete=12, scrap=30, cans=40, oldclothes=8, candle=10))
c["contracts"]["base_slots"] = 0
c["contracts"]["_status"] = "실험값(v0.4): 뒷문 무역관이 있어야 계약(중반 시스템). 무역관 하나당 2자리"
save("rules/config.json", c)
print("ok")
