# SIM 노트 — 도시경제(파트 A 코어 + 파트 B 시간·탐험·진행)

기준: `docs/GDD.md` v0.3 + 디렉터 수정 · 브랜치 `simb`. 수치 변경 이력은 `docs/BALANCE_CHANGELOG.md`, 검토용 표는 `docs/data_tables/`(자동 생성, `python3 godot/tools/data_tables.py`),
시나리오 결과는 `simulation/reports/SUMMARY.md`(+ 봇마다 `<봇>.md`), 파트 A의 계속 접속 리포트는 `simulation/reports/core_balanced.md`.
UI 계약에 덧붙인 것(키 이름 변경 없음)은 `docs/ARCHITECTURE.md` 끝 "파트 B 추가" 절.

## 1. 구조 한눈에

- **순수 규칙 층**: `godot/sim/**`는 노드·오토로드·`Time.*`를 쓰지 않는다. 경제 시간은 `Sim.tick(state, dt_경제일)`로만, 실제 시간은 `sim.now_unix`(Game이 매 프레임 = 시스템 시각 + `state.clock_offset`)로만 들어온다.
- **고정 스텝**: `config time.step_days` = 1/48 경제일(실제 12.5초). 미접속 빨리감기는 그 12배(1/4경제일) 큰 스텝 — 경제 시계 격자는 그대로(`econ_days`는 늘 1/48의 배수).
- **RNG**: xorshift32 하나, 상태는 `state.rng_state`(외형 씨앗, 탐험 보상 굴림, 단속 대상).
- **시스템 = 파일 하나** (`sim/systems/<id>.gd`): `config.json systems` 순서대로 매 스텝. 하나를 빼도 돈다(시험). 시스템끼리 부르지 않고 `CityState`와 Sim의 공용 도우미만 쓴다.
- **공용 도우미(규칙 아님)**: `Cover.gd`(배치 파생 캐시: 주거·시설 목록, 덮임 등급, 우선순위 묶음, 층별 목록 — `layout_rev`가 바뀔 때만), `Queries.gd`, `Metrics.gd`, `Validate.gd`(파트 B 데이터 검사 `check_b` 포함), `Debug.gd`, `Expr.gd`.
- **수정치 접근자 하나**: `sim.mod(state, "키")` = 1 + Σ(켜진 정책 + 끝난 연구의 effects[키]), `sim.mod_sum`은 합만. 연구·정책이 바뀌면 `state.flags.mods_rev` +1 → 캐시 갱신.

### 한 스텝의 실행 순서
`progression → goals → space → contracts → expeditions → research → policies → workforce → utilities → production → needs → upgrades → vice → finance → alerts`
→ (Sim) 상품 흐름 접기 → 시계 전진 → 정시 `hour` → 자정이면 `on_day_end` → `day_ended` → `on_day_start` → `day_started` → `state.settle()`(빨리감기 중에는 끝에서 한 번).
순환이 있는 곳은 직전 스텝 값(전기 비율, 수요의 물·전기 비율). 알림·목표 검사는 2·4스텝 주기의 경계(`sim.every`) — 스텝 크기·저장과 무관하게 econ_days로만 정해진다.

## 2. 시스템과 조절 키

| 시스템 | 하는 일 | 조절 키(데이터) | 끄면 |
|---|---|---|---|
| progression | 해금 단계(영구), 등급·호칭, `unlock`·`milestone` | unlocks.json | 모든 시설이 열림 |
| **goals** | 단계 목표 21개(order), 보상(돈→장부 reward·상품·목적지 공개), `goal_done`, `goals` 질의·`hud.next_goal`, 마지막 뒤 샌드박스, `tutorial` 명령 | goals.json | goals 질의는 해금 단계로 만든 기본 모양 |
| space | 칠하기·짓기·철거·공사·골조·층 해금, `range_preview`, **`demolish_preview`**, can `code` | config zone/floors, buildings cost·size | 못 짓는다 |
| contracts | 정기 계약(경제 시계) | partners.json, config contracts.* | 교역 없음 |
| **expeditions** | 팀(거점당 1, 최대 3) · 출발 때 보상 굴림 · 실제 시계 완료 · 멱등 수령 · 발견(거래처·도면·목적지) | destinations.json, 수정치 exp.yield/exp.time/exp.cost | 탐험 없음(빈 모양) |
| **research** | 3×4 노드, 공부방 필요(가동 중일 때만 진행), 한 번에 하나, 돈은 시작 때, 취소 시 절반 환불 | research.json | 연구 없음, 수정치에서 빠짐 |
| **policies** | 칸 = 열린 policy_slot 수, 같은 group 하나, 유지비(못 내면 저절로 꺼짐) | policies.json | 정책 없음 |
| workforce | 계층별 풀·우선순위 배분(단속 폐쇄 시설은 사람을 받지 않음) | tiers.json, buildings workforce·priority | 인력 100% |
| utilities | 물·전기 공급/수요 | tiers water/power, 수정치 water.demand·power.supply | 늘 충분 |
| production | 가동·생산(처리량 × prod.all), cause raid | buildings recipe | 생산 없음 |
| needs | 수요 선택·소비·충족·입주·퇴거·행복·세수 + **묶음 캐시**(§5) | needs.json, config population.*, 수정치 cons.food·cons.all·happy.base·happy.noise·tax.all·movein | 사람이 안 움직임 |
| upgrades | 승급(묶음 원자적), 비계, 이주·대기(미접속 중 대기 시계 정지) | upgrade_costs.json | 승급 없음 |
| **vice** | 단속 위험(오름·식음), 80에서 하나 2일 폐쇄 + 벌금 + 한 줄, `vice` 질의 | buildings vice.heat·raid_line, config heat.* | 위험 없음 |
| finance | 세수·유지비(× upkeep.all)·파산 정지·장부(줄 reward·fine 추가, net) | buildings upkeep | 돈 흐름 없음 |
| **alerts** | hud.alerts 모음: 1경제시간 유지(깜빡임 방지), 최대 4, 급한 순 | config alerts.* | 다른 시스템이 붙인 알림만 |

수정치 키: `prod.all`, `cons.food`, `cons.all`, `happy.base`(점수 합), `happy.noise`, `tax.all`, `movein`, `water.demand`, `power.supply`, `upkeep.all`, `exp.yield`, `exp.time`, `exp.cost`, `trade.buy`, `trade.sell`, `heat.gain`.

## 3. 파트 B 규칙 요약

- **탐험**: `expedition_send {team, dest, provision, pick?}` — 팀이 쉬는 중·목적지를 앎·출발비·보급(끼니 10, 채소·국수·어묵 중 많은 것부터)을 확인하고, **출발 때** 보장 주력(min~max) + 덤(확률) + 발견을 결정론 RNG로 굴려 팀에 저장. `completes_unix = now + seconds × exp.time`. `now ≥ completes`면 done(`expedition_done` 한 번). 수령은 done인 팀만 정확히 한 번(재고 한도를 넘겨도 넣는다 — "결과는 사라지지 않는다"). 근거리는 처음부터, 중거리는 첫 근거리 수령·목표 `g_claim`, 원거리는 중거리 수령·연구 `지도 제작`으로. 거점을 허물면 쉬는 팀부터 없애고, 나가 있는 팀은 은퇴 표시 → 수령 뒤 해산.
- **목표**: goals.json 순서로 하나씩 보이지만 먼저 이룬 것도 그때 끝난다. 마지막 `g_final`(거물 40 + 성채 회관) 뒤 샌드박스.
- **알림**: 물·전기 부족, 일손 부족(계층별), 재고 하루 안에 바닥/없음, 계약 건너뜀, 탐험 귀환, 승급 가능, 층 해금 12칸 이내, 대기 주민 곧 떠남, 주민 잃는 주거, 파산 정지, 단속 위험 50, 단속 폐쇄. 조건이 꺼져도 1경제시간 남긴다. 4개까지(bad → warn → good, 같은 tone은 고정 순서).
- **미접속**(`Sim.catch_up`): 실제 경과(마지막 정산 → 지금, 음수면 0 + 한 줄, 8시간 상한 + 한 줄) × 0.25 / 600 → 경제일, `fast_forward`(offline 표시) — 유예 시계·대기 시계 정지(아무도 안 떠남), 재고 0이면 그 소비·생산만 멈춤, 계약·연구는 경제 시계, 탐험은 실제 시계로 완료. 요약: 금고 변화, 많이 만든·쓴 것, 처음 모자란 때(떠난 지 몇 시간째), 계약 이행/건너뜀과 이유, 연구 완료, 단속, 돌아온 탐험대. Game은 불러올 때 + 프레임 사이 공백이 60초를 넘을 때(앱 복귀) 부른다. 디버그 `skip_real`은 공백으로 치지 않는다.
- **연구·정책**: §2 표. 연구는 공부방이 하나도 가동하지 않으면 멈춘다.
- **음성·단속**: 가동 중인 음성 시설 vice.heat × 가동률 × heat.gain/경제일, −6/경제일. 80에서 기여만큼의 확률로 하나 골라 2경제일 폐쇄(`raided`, `raid_until`, cause raid, 인력 0), 벌금 max(₩100, 수입 2일치)(금고를 넘지 않음), 위험 −40. 닫힌 동안에도 멈추기·허물기는 된다.
- **승급 표시**: `upgradable` = 지금 바로 승급 가능(조건 + 돈 + 한 계열 이상 자재 + 추가 상품) — 뷰의 ▲가 넘치지 않게(디렉터 요청). 비용을 뺀 조건 충족은 `ready`(봇·UI용). `upgrade` 명령은 `ready`와 실제 비용으로 판정.

## 4. 상태(CityState v3) 추가

필드 이름은 ARCHITECTURE 그대로. 파트 B가 쓰는 것: `teams[]`(id, state, dest, started_unix, completes_unix, provision, reward{상품: float}, finds[], pick, retired?), `dests{id: {known, visits, new}}`, `research{done{}, active{id, left, done_at}}`, `policies{id: true}`, `heat`.
`flags`: `goals{id: econ_days}`, `alerts{id: 알림+off}`, `tutorial`, `mods_rev`. `stats`: `start_unix`, `first_send_unix/day`, `first_claim_unix/day`, `exp_sent(_near/_mid/_far)`, `exp_claims(_band)`, `exp.<상품>`, `goal_<id>_day`, `research_<id>_day`, `raids`, `fines`, `contract_skips`, `policy_upkeep`.
주거: `ready`, 캐시 `psig`(현재 선택 서명), `nsig`(충족 표시 서명), `sdm`/`sdc`(부족 일수 > 0 / 유예에 닿은 수요 비트). 시설: `raided`, `raid_until`. 저장 왕복·결정론 시험 통과.

## 5. 성능

측정: `godot --headless --path godot -s res://tools/sim_perf.gd -- [houses=1000] [steps=96] [topup=1] [offline=1]` — 주거 1,000채(층마다 2×2 시설 자리 여섯 곳, 계층 층마다 다름, 정수장 30·열병합 12), topup=1은 생산 시설 없는 상품을 매 스텝 채움(정상 운영), topup=0은 끼니가 바닥나는 위기 도시.

| | 파트 A | 지금 |
|---|---|---|
| 1,000채 스텝 평균(정상) | **약 120ms**(파트 A 측정) · 이 탐침 267ms(needs 250) | **약 7.7~8.3ms**(중앙값 6.8~7.5, 하루 경계의 settle 포함) |
| 1,000채 스텝(위기: 매 스텝 고르기가 뒤집힘) | — | 약 15ms |
| 하루 경계 settle | 32~37ms | 30ms(한 번의 JSON 왕복) |
| 미접속 8시간(12경제일) 정산 | 약 70초(576스텝) | **약 0.9초**(48 큰 스텝 + 끝 settle 한 번) |
| 시험 묶음 | 13.8초 | 약 17초(시험 수 2배) |

어떻게(결과는 같다 — 균형형 봇 30경제일 결과가 파트 A와 숫자 하나 다르지 않았다, 탐침 지문 동일):
1. **덮임 등급 → 접근 등급**: Cover가 주거마다 (시장 목록, 서비스 목록, 소음)을 등급으로 묶고, needs가 범위 시설의 가동 상태가 바뀔 때만 등급별 "시장 등급·서비스별 원인" 표를 만들어 같은 것끼리 다시 묶는다(1,000채 → 642 → 158).
2. **묶음(Ent)**: (계층, 접근 등급, 현재 선택 서명 psig, prefer 판정 비트)가 같은 주거는 1단계 결과가 같다 → 한 번만 계산하고 주거마다 주민 수만 더한다. 묶음은 기댄 환경 비트(상품 재고 있음·공급률 충분, 물·전기 0.5/충분)가 그대로면 다음 스텝에도 쓴다. 재고 양으로 정렬해 고른 묶음은 그 스텝만.
3. **2단계 결과(P2)** 도 묶음마다(공급률·물·전기 값이 그대로면 재사용). **가라앉은 주거**(같은 묶음·같은 P2·같은 주민 수·부족 일수 변화 없음·입주/퇴거 없음)는 2단계를 통째로 건너뛴다.
4. 소비는 소비 묶음(dem)별 주민 합 × 1인 소비, 상품 순서는 데이터 순서로 고정 — 캐시 이력과 무관하게 결정론. 도시 행복도 묶음 순서로 더한다.
5. Cover의 우선순위 묶음(시설 정보 배열)으로 workforce·utilities가 사전 조회 없이 돌고, Metrics·finance·upgrades·space가 주거·시설 목록만 돈다. `Sim.cfg` 경로 캐시, `bdef/good/tier` 빠른 길.
6. settle은 정수 아닌 float만 모아 JSON 왕복 한 번. 빨리감기 중에는 끝에서 한 번.

휴대폰(5~10배 느림) 예상: 정상 스텝 40~80ms(×16이면 실제 0.78초에 한 번 → 프레임 하나), 미접속 8시간 5~9초 — 로딩 화면이 필요할 수 있다(§9 열린 질문).

## 6. 실행 방법
- 시험: `godot/tests/sim_test.sh` (마지막 줄 `RESULT: PASS`).
- 시나리오 하나: `KOWLOON_NOSAVE=1 godot --headless --path godot -s res://tools/sim_run.gd -- bot=balanced real_days=7 seed=1` → `simulation/reports/balanced.md` + `.json`(약 1~4분).
- 전부 + 요약: 봇 12종을 돌린 뒤 `python3 simulation/make_summary.py` → `simulation/reports/SUMMARY.md`(해석은 `simulation/summary_notes.md`).
- 옛 계속 접속 리포트: `... sim_run.gd -- mode=econ bot=balanced days=30` → `core_balanced.md`.
- 성능: `... -s res://tools/sim_perf.gd`. 검토 표: `python3 godot/tools/data_tables.py`.
- Game 부팅 탐침: `KOWLOON_NOSAVE=1 godot --headless --path godot res://tools/sim_game_probe.tscn`.

## 7. 내가 정한 것(사양 밖) — 번호, 이유

파트 A의 1~19는 그대로 유효(아래는 파트 B, 20부터).

20. **부족 일수(유예 시계)는 유예(3경제일)에서 멈춘다.** 원래는 끝없이 쌓였다. 쌓인 값은 "회복 뒤 다시 끊기면 얼마나 빨리 떠나나"에만 영향을 주는데, 상한이 있어야 오래 굶은 집도 회복 뒤 다시 유예를 온전히 받고(더 너그러움), 묶음 캐시가 "변화 없음"을 알아볼 수 있다.
21. **`upgradable`에 비용을 넣고 `ready`를 따로 둠**(디렉터 요청을 따르되 봇·UI가 "조건은 됐는데 돈/자재가 없음"을 알 수 있게). `upgrade` 명령은 ready + 실제 비용으로 판정.
22. **탐험 보상은 출발 때 굴리고, 발견(거래처·도면·새 목적지)은 수령할 때 적용.** 보상이 미리 정해져 있어야 저장·불러오기·시계 조작으로 다시 굴릴 수 없고, 발견은 플레이어가 짐을 풀 때 보여 주는 게 자연스럽다.
23. **수령은 재고 한도를 넘겨도 넣는다.** "결과는 사라지지 않는다"(확정)를 지키려고. 넘친 만큼 생산·수입이 멈출 뿐.
24. **세 근거리 목적지의 실제 1분당 자재를 같게(2.0)**: 가구 골목 5분·10, 고철 7분·14, 철거 공사장 10분·20(GDD는 10/10/12). 어느 계열도 정답이 아니게(브리프 요구), 대신 짧은 곳은 손이 더 간다.
25. **출발비**: 근거리 0, 중거리 ₩30, 원거리 ₩80. 작은 돈 싱크 + 원거리를 공짜 무한 수확으로 만들지 않으려고.
26. **거점을 허물면 쉬는 팀부터 없애고, 나가 있는 팀은 돌아와 짐을 푼 뒤 해산.** 팀 수 = 거점 수를 지키면서 보상을 잃지 않게.
27. **목표 보상에 돈·설비 부품·목적지 공개**를 넣고, 등급·호칭은 해금 단계(unlocks.json)에 그대로 둠. 목표는 "다음에 할 일" 안내, 등급은 성장 결과.
28. **알림은 상태(flags.alerts)에 기억해 1경제시간 유지**, 최대 4개. 탐험 귀환처럼 실제 시계에 따르는 것만 질의 때 바로.
29. **미접속 큰 스텝 1/4경제일**(접속 중 1/48). 계약 주기(12시간 이상)·공사(0.04일)·입주 속도에서 결과가 거의 같고(시험: 37분씩 나눠도 ±2%), 1,000채 8시간을 1초 안에.
30. **앱이 60초 넘게 멈췄다 돌아와도 미접속 규칙**으로 정산(접속 중 속도로 몇 시간을 몰아 돌리지 않게). `last_saved_unix`를 "마지막 정산 시각"으로도 씀.
31. **연구는 공부방이 하나도 가동하지 않으면 멈추고, 취소하면 절반 환불.** "공부방 필요"를 진행 조건으로 읽었다.
32. **정책 유지비를 못 내면 그 정책이 저절로 꺼진다**(금고 음수 금지 규칙과 맞춤).
33. **단속 대상은 위험 기여만큼의 확률로**(결정론 RNG), 벌금은 금고를 넘지 않는다. "권한을 빼앗지 않는다": 폐쇄 중에도 멈추기·허물기 가능, 위험은 공개(hud.heat, vice 질의, 알림 50).
34. **무면허 치과·짝퉁 공방도 위험을 조금 올린다**(1·4). GDD §11의 음성 여섯 곳을 그대로.
35. **봇 전용: 꼭 필요한 시설 자리가 없으면 낮은 계층 주거(최대 세입자)를 허물어 2×2 자리를 낸다.** 알려진 약점(층이 차면 2×2를 못 놓음)을 플레이어가 하는 방식으로 — 주거 철거는 무료, `can("build")`가 "이 층에는 빈 2×2 자리가 없다 — 주거 한 칸을 허물면…"이라고 말한다.
36. **목표 `g_trade`의 계약 3건, `g_mid`(중거리에서 거래처)** 등 목표 문구·순서는 내가 썼다(goals.json).
37. 초반 현금(시작 ₩1,200, 초반 목표 보상↑), 후반 싱크(세율·승급 돈·연구·회관) — BALANCE_CHANGELOG에 이유와 함께.

## 8. 약한 곳(알고 있는 것)

- **실시간 속도(튜닝 3 뒤)**: 보통 접속 첫 유지 14.6시간·첫 거물 1일·회관 2일·**최종 6일**, 하루 2회 첫 유지 2.5일·첫 거물 3.5일·회관 6일·**최종 12.5일** — 최종은 디렉터 목표 범위 안, 첫 유지·거물은 목표보다 이르다(한 채가 먼저 올라가는 것). 설비 부품은 탐험 50~60%·건재상 40~50%. 근거는 BALANCE_CHANGELOG 튜닝 2·3.
- "첫" 상위 승급은 자재 총량이 아니라 그 계층 승급 수요(라디오·양주·공부방)가 처음 채워지는 때로 정해진다 — 그래서 전파사를 토박이 300 단계로 옮겼다(자재 누적과 묶기).
- 후반 돈은 쌓인다(보통 10일째 ₩535만). 1회성 싱크(연구 ₩17만·회관 ₩2.5만·승급)뿐, 커지는 싱크 없음(디렉터: 이번엔 쫓지 않음).
- 위기(끼니가 도시 전체에서 바닥)에서는 고르기가 매 스텝 뒤집혀 needs가 느려진다(1,000채 15ms).
- 봇은 "괜찮은 플레이어" 흉내다: 접속당 명령이 사람보다 많고(1분마다 손), 가장 높은 계층부터 올린다. 튜닝 2의 short_frequent·long_absence 결과는 "회관 부품 남기기" 수정 전 봇으로 돌렸다(회관이 안 지어짐 — 봇 탓).
- 내부 생산형은 거물이 될 수 없다(양주 수입 전용), 떠돌이 승급도 헌 옷 수입이 필요 — 데이터 사실이고 GDD와 맞다.

## 9. 오너·디렉터 결정과 남은 질문

1. **실시간 속도 — 디렉터 기본안(결정됨)**: 시계 그대로(접속 600초 = 1경제일, 미접속 0.25배·8시간), 실시간 속도는 탐험 자재·설비 부품으로. 측정(튜닝 2): 보통 접속은 실제 하루에 경제 약 45일, 하루 2회는 약 26일. 대안(오너용 비교, 이번엔 돌리지 못함 — 시간 상자): 미접속 0.1배면 하루 2회가 약 12경제일/일로 느려지고 보통 접속과의 격차가 커진다(계산값).
2. **미접속 정산이 휴대폰에서 5~9초**(1,000채, 8시간)일 수 있다: 1) 로딩 화면 + 요약 2) 상한 4시간 3) 큰 도시만 더 거친 스텝.
3. **부품 경로 — 디렉터 결정(튜닝 3)**: 원거리 탐험이 부품 1개를 보장하고 옛 발전소는 3~4개. 거물 승급 부품은 3개 그대로.
