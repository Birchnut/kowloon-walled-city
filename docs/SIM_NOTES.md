# SIM 노트 — 코어 도시경제(파트 A)

기준: `docs/GDD.md` v0.3 + 디렉터 수정 4건(아래 §6) · 브랜치 `sim3`. 수치 변경 이력은 `docs/BALANCE_CHANGELOG.md`, 검토용 표는 `docs/data_tables/`(자동 생성), 봇 결과는 `simulation/reports/core_balanced.md`.

## 1. 구조 한눈에

- **순수 규칙 층**: `godot/sim/**`는 노드·오토로드·`Time.*`를 쓰지 않는다. 경제 시간은 `Sim.tick(state, dt_경제일)`로만, 실제 시간은 `sim.now_unix`(Game이 매 프레임 = 시스템 시각 + `state.clock_offset`)로만 들어온다.
- **고정 스텝**: `config time.step_days` = 1/48 경제일(실제 12.5초). `tick`은 남는 조각을 `state.flags.step_acc`에 쌓고 스텝 단위로만 규칙을 돌린다. `econ_days`는 스텝 격자로 반올림 → 결정론·저장 왕복.
- **RNG**: xorshift32 하나, 상태는 `state.rng_state`(지금은 외형 씨앗에만 쓰임).
- **시스템 = 파일 하나** (`sim/systems/<id>.gd`, 공통 `SimSystem`): `config.json systems`의 순서대로 매 스텝 실행. 하나를 빼도 게임이 돈다(시험으로 확인). 시스템끼리 직접 부르지 않고 `CityState`로만 말한다.
- **공용 도우미(규칙 아님)**: `Cover.gd`(배치 파생 캐시: 주거별 시장·서비스 접근 목록, 소음 이웃, 창고·교역소 수, 시설 우선순위 순서 — `state.layout_rev`가 바뀔 때만 다시 계산, 저장 안 함), `Queries.gd`(hud·info·economy·build_menu 등의 뼈대, 시스템은 `augment()`로 보탬), `Metrics.gd`(조건식용 지표), `Validate.gd`(데이터 검증 + 순환 잠금 정적 검사), `Debug.gd`, `Expr.gd`(조건식).
- **성능(측정)**: 매 스텝 O(주거 × 수요 수), 시장·서비스 범위는 배치가 바뀔 때만 다시 계산. 데스크톱 헤드리스에서 주거 1,008채 = **스텝당 약 120ms**(그중 needs 110ms), 300채면 약 40ms. 접속 중엔 12.5초에 한 번이라 평균 부하는 작지만 큰 도시에선 한 프레임 끊김이 생길 수 있다. 미접속 8시간(=12경제일=576스텝)은 1,000채에서 약 70초 → **B 파트 과제**: 오프라인 전용 큰 스텝(예: 1/12일), 또는 needs의 1단계(선택) 결과를 여러 스텝 재사용. needs.gd의 남은 비용은 수요마다 만드는 작은 배열·딕셔너리(GDScript 할당)다.

### 한 스텝의 실행 순서
`progression → space → contracts → workforce → utilities → production → upgrades → needs → finance` → (Sim) 상품 흐름 접기 → 시계 전진 → 정시 `hour` → 자정이면 `on_day_end`(장부 마감·떠남 요약) → `day_ended` → `on_day_start` → `day_started` → `state.settle()`.

순환이 있는 곳은 **직전 스텝 값**을 쓴다: 공급 시설이 전기를 쓰면 직전 `p_ratio`, 수요의 물·전기 비율은 직전 `state.util`, 시장 가동 여부는 같은 스텝의 production 결과.

## 2. 시스템과 조절 키

| 시스템 | 하는 일 | 조절 키(데이터) | 끄면 |
|---|---|---|---|
| progression | `unlocks.json` 단계를 순서대로 검사(Expr 조건), 시설을 영구 해금, 등급·호칭, `unlock`·`milestone` 이벤트 | unlocks.json cond/unlocks/features/grade_name/title | 모든 시설이 처음부터 열림 |
| space | zone/build/demolish/pause, 공사(site) 진행, 자동 골조, 80% 층 해금, `range_preview` | config zone.shack_cost, floors.*, buildings.json cost·size·build_days·open_sky·blueprint | 못 짓고 층이 안 열림 |
| contracts | 서명·변경·취소, 경제 시계 `next_at`에 원자적 실행(부분 이행), `contract_done`, `contracts` 질의 | partners.json, config contracts.* | 교역 없음 |
| workforce | 계층별 풀(T1 = floor(합×0.75)), 순위별·비율 배분 → `b.staff`, `state.labor` | tiers.json labor, buildings.json workforce·priority, config workforce.priority | 모든 시설 인력 100% |
| utilities | 물·전기 공급/수요(주민 몫 먼저 → 시설 순위별), `state.util`, `b.w_ratio/p_ratio`, `power_changed` | tiers.json water/power, buildings.json supply/water/power | 늘 충분 |
| production | 가동 판정(x = min(인력, 물, 전기)), 생산식(원료·저장 한도), 시장·서비스 켜짐 이력(60%/50%), 음성 수입률 | buildings.json recipe·vice, config workforce.service_on/off, storage.* | 생산·시장 없음 |
| upgrades | `upgrade` 명령(묶음 원자적), 비계 공사, 완공 시 계층 전환, 정원 감소 이주·대기·떠남, `upgradable`·`upgrade_preview` 질의, info 미리보기 | upgrade_costs.json, config upgrade.waiting_days | 승급 없음 |
| needs | 수요 선택(대체 묶음 sticky), 도시 재고 공평 배분·소비, 충족도, 입주·퇴거(유예), 행복, 세수율 | needs.json, tiers.json, config population.* | 사람이 안 움직이고 세수 0 |
| finance | 세수·음성 수입 적립, 유지비, 파산 정지(우선순위 낮은 것부터)·재가동, 장부 마감(14일) | buildings.json upkeep, config finance.* | 세수·유지비 없음 |

## 3. 핵심 규칙 요약(구현 기준)

- **거리** `|dx|+|dy|+2|dz|`, 층 차 ≤ 2, 2×2는 가장 가까운 칸.
- **상품 수요**: (1) 범위 안에 그 상품 등급 이상을 취급하는 **가동 중** 시장 (2) 도시 재고. 원인 코드: `range` 시장 범위 밖 / `grade` 취급 등급 부족 / `staff` 인력 부족 / `power` 전기 부족 / `stock` 재고 없음 / `water`. 도시 전체 수요를 먼저 모으고 재고/수요 비율로 모두에게 같은 비율을 준다 → 시장이 겹쳐도 한 번, 시장별 상한 없음, 재고 음수 없음.
- **대체 묶음**: 고른 품목(`needs[id].pick`, 여러 종이면 쉼표)을 유지. 바꾸는 때: 그 품목이 끊김(접근·재고 0) 또는 **지난 스텝 공급률 < 0.9이고 넉넉한 대체품이 있을 때**(`state.flags.fill`). 새로 고를 땐 재고가 가장 많은 것부터. `prefer` 유틸리티(세입자 등불 → 전기)는 남는 전기가 그 집 몫만큼 있을 때만 갈아탐(같은 스텝 안에서 남는 양을 깎아 쏠림 방지).
- **N-of-M**(끼니 2종): 충족도 = 고른 종류 각각의 공급률 합 / N. 한 종류만 있으면 50%.
- **목표 인원** = Σ 기본 수요 몫 × min(1, 충족도/0.9). 모자라면 `move_in_per_day × (0.5 + 행복/100)`로 차고, 넘치면 **기본 수요 하나라도 부족 일수 ≥ 3경제일**일 때만 `move_out_per_day`로 떠난다. 부족 일수는 충족되면 2배 속도로 줄어든다.
- **승급 가능(upgradable)** = 만실 + 기본·승급 수요 전부 충족 + 공사 중 아님 + 다음 단계 비용 데이터 있음.
- **세수**/일 = 주민 × 세율 × (1 + 0.10×충족 승급 수요 + 0.15×충족 여유 수요) × 행복 배수(0.85~1.15).
- **층 해금**: 맨 위 열린 층의 쓰이는 칸 ≥ ceil(0.8×144)=116 → 다음 층. 쓰이는 칸 = 주민 ≥1 주거 + 완공 시설(2×2 = 4). 순차·영구.
- **골조**: 짓는 칸 아래로 첫 셀/골조/땅까지 빈 칸마다 생성(명령과 함께 원자적, 비용 config). 골조는 그 칸의 건설을 막지 않는다. 철거 시 위에 셀·골조가 있으면 그 칸에 골조를 남기고, 위에 셀이 하나도 없는 골조는 정리한다.
- **파산**: 유지비를 낼 수 없으면 순위가 낮은 시설부터 `money_stop`(원인 "money", 유지비 0)으로 멈춤. 멈춘 것 포함 유지비 1일치가 모이면 모두 재가동.
- **계약**: 수입 = min(qty, 저장 자리, 살 수 있는 수), 수출 = min(qty, 재고 − reserve). 0이면 건너뜀(벌금 없음, 이유 기록). 회차는 `next_at += interval`. 장부 import/export에 한 번.

## 4. 상태(CityState v3)

ARCHITECTURE.md의 필드 이름 그대로. **SIM이 보탠 필드**(저장됨): `util`(물·전기 공급/수요/비율), `labor`(계층별 have/need/used), `next_id`. 건물 인스턴스에 보탠 키: 주거 `grow, leave, target, tax(₩/일), util_extra`, 시설 `w_ratio, p_ratio, money_stop, vice_rate, built`. 공사 중 건물은 `buildings[bid].kind == "site"`(`type, pos, size, progress`). `flags`에 쓰는 키: `step_acc, layout_rev, fill, unlock_steps, left_today, power_on, power_seen, blueprints, bot`.
`needs[id]`에는 계약의 `{ratio, short_days, pick}` 외에 `cause`가 있다. 저장 버전 3(`user://save_v3.json`, 옛 파일은 건드리지 않음). `to_json/from_json` 왕복이 글자 단위로 같고, 저장 후 이어 돌린 결과가 비트 단위로 같다(시험).

## 5. B 파트가 할 일과 이음새

| 할 일 | 이음새 |
|---|---|
| 탐험(팀·목적지·실제 시간·보상 수령) | `state.teams`, `state.dests`, `sim.now_unix`(실제 시간), 시설 `expedition_base`의 `teams` 수는 `Cover.build()`의 `teams`. `expeditions` 질의는 지금 빈 모양(`Queries.gd`) — 새 시스템이 `query("expeditions")`를 소유하면 그쪽이 먼저 답한다. 보상은 `state.stock`에 넣고 `sim.flow_add(g, "imp", n)` 대신 별도 키를 원하면 `flow` 키를 추가해도 된다. 발견: `state.partners[id] = true`(계약 제안이 바로 열림), 도면 `state.flags.blueprints[id] = true`(열병합). |
| 연구·정책 | `state.research`, `state.policies`. 정책 칸 해금은 `state.unlocked["feature:policy_slot_N"]`. 효과를 넣을 자리: 세율·소비량·생산량은 지금 데이터에서 직접 읽으므로, 정책 시스템이 `state.flags.mods = {key: 배수}`를 쓰고 needs/production/finance에서 곱하는 한 줄씩 추가하는 방식을 권한다(지금은 없음). |
| 음성 산업·단속(heat) | 음성 시설은 `vice.income`만 번다(`b.vice_rate` → 장부 vice). `tags`에 `vice`, `stub`. 단속 폐쇄는 `b.cause = "raid"` 문구가 이미 있다 — 폐쇄를 `b.paused`와 다른 플래그(예: `b.raid_until`)로 두고 production에서 `eff = 0`, `cause = "raid"`로 처리하면 된다. `state.heat` 필드 있음. |
| 목표 문구(milestones) | `goals` 질의는 해금 단계로 임시 채움(`Queries._goals`). 등급 이벤트는 progression이 이미 낸다. |
| 미접속 정산 | `Game._offline_catch_up()`(표시된 스텁): 실제 경과 ≤ 8시간 × 0.25 → `sim.fast_forward`. 할 일: 유예 시계 정지(needs의 `short_days` 증가를 `sim.offline`일 때 막기), 재고 0이면 그 소비만 정지(이미 그렇다), 요약 줄(`SimSystem.fast_forward` 훅), 음수·과도 도약 방어. `fast_forward`는 지금 같은 고정 스텝을 그대로 돈다(오프라인 = 온라인 결과 동일). |
| 시나리오 묶음(브리프 §20.1) | `tools/sim_run.gd`(봇 이름 인자) + `data/sim/bots.json`. `Bot.gd`는 균형형 하나 — 설정값으로 다른 봇을 만들 수 있다(자재 집중형: 자재 선택 규칙만 바꾸면 됨). |
| 일괄 승급 UI | `upgradable {tier?}` → [{tier, tier_name, count, bids}], `upgrade_preview {bids, material}` → info.upgrade.preview와 같은 키(합산) + {ok, blockers, cost{money, qty, extra}} 구현됨. |

## 6. 내가 정한 것(사양 밖) — 번호, 이유

1. **공사 중 건물을 `buildings`에 kind "site"로 둔다.** 계약은 house/facility만 적었지만 진행률을 셀 넷에 따로 두면 2×2가 어긋난다. 완공 시 같은 bid로 facility가 된다.
2. **주거 승급도 짧은 공사(0.05~0.1경제일, 30~60초)**: 브리프의 "비계(scaffold) 동안 주민은 그대로" 연출을 경제 상태로 보여 주려고. 계층 전환과 이주는 완공 순간에 일어난다. 데이터 `days`를 0으로 하면 즉시.
3. **물·전기를 쓰는 생산식의 물은 재고 상품이 아니라 유틸리티 부하**(GDD 표의 "물 6"). 물 저장 개념을 만들지 않기 위해.
4. **"헌 옷"은 생산 시설 없이 수입 전용**: GDD 표에 떠돌이 승급 수요로만 있고 만드는 곳이 없었다. 봉제방은 세입자 인력이 필요해 떠돌이 승급 전에 못 돌리므로(순환 잠금) 도매상 수입으로 해결.
5. **교역소 인력 세입자 2 → 떠돌이 2**: 떠돌이 승급 수요(헌 옷·초 원료)가 계약을 필요로 하는데 교역소가 세입자를 요구하면 순환 잠금.
6. **기본 계약 자리 2**(교역소 없이 길 건너 도매상과 둘, `contracts.base_slots`): 첫 접속에서 헌 옷·유지(떠돌이 승급)를 바로 사게. 교역소는 자리 +2. 계약 자리는 완공 교역소 수로만 세고 교역소 인력과는 무관.
7. **도매상이 전자 부품·양주를 비싸게 판다**, **건재상이 설비 부품·고물도 판다**: 순환 잠금 검사 규칙("아는 거래처나 해금된 시설로 얻을 수 있어야")을 지키려고. 부두 암시장이 더 싸다(탐험 발견의 가치).
8. **고물 작업장 해금 떠돌이 50 → 20**: 시설 건설 재료(고물)가 시작 30개로 막혔다.
9. **세입자 등불: 전기가 남으면 전기로 갈아탄다(prefer)**: GDD "등불은 전기가 닿으면 전기로 대체". 남는 전기 몫 확인으로 쏠림·깜빡임 방지.
10. **바닥나는 상품에서 대체품으로 갈아타기**(지난 스텝 공급률 < 0.9 + 넉넉한 대체품): 순수 sticky는 "조금씩 들어와 매 스텝 0이 되는" 채소에 모든 집이 묶여 국수가 남아도는데도 굶는 버그를 만들었다.
11. **시장·서비스는 전기도 켜짐 이력에 포함**(x = min(인력, 전기) ≥ 0.6이면 켜짐, 0.5 밑이면 꺼짐). 전기 필요 시장이 비율만큼 "부분 가동"하는 모델은 범위 서비스에 어울리지 않아 이진 가동.
12. **공급 시설(발전기 등)의 출력 = 정격 × 인력 비율**, 전기를 쓰는 공급 시설(정수장)은 × 직전 전기 비율.
13. **철거는 환불 없음**, 주거 철거 시 주민은 대기 주민(3일)으로 — 사라지지 않게.
14. **창고 한도는 상품마다**(공유 총량이 아니라 상품별 한도). 디렉터 수정 2의 "3일치"를 상품별로 맞추기 쉬움.
15. **세 계열 자재 이외 '설비 부품'은 승급 추가 상품과 상급 시설 비용에만** — 탐험 원거리 보상(B)과 건재상 소량 구매.
16. **`offline_summary`는 없을 때 null 대신 빈 모양**(작업 지시: UI가 null을 받지 않게). Game이 정산 직후 한 번 실제 요약을 돌려준다.
17. **봇 전용**: 탐험이 없어 세 계열 자재를 하루 30개 `debug add_stock`으로 넣는다(근거리 2팀 상시 가동 가정). 리포트 첫머리에 명시.
18. **해금 조건의 계층 인구에는 대기 주민도 포함**(노동력과 같은 기준).
19. **소음 이웃**: 같은 층 거리 1(옆 칸, 위아래 아님)의 `noise` 태그 시설 하나당 행복 −6.

## 7. 약한 곳(알고 있는 것)

- 행복은 단순식(기본 50 + 여유 ×12 − 기본 부족 ×5 − 소음 ×6). 명소·정원 범위 보너스, 정책은 아직 없음.
- 시장·서비스는 이진 가동 — 인력 55%인 시장은 이전 상태에 따라 켜져 있거나 꺼져 있다(의도한 이력).
- 생산식 처리 순서(우선순위 → bid 순)대로 원료를 먼저 가져간다. 원료가 모자라면 앞 순위 시설이 먼저 쓴다(같은 순위 안 비율 배분은 아님).
- 봇은 "괜찮은 플레이어" 흉내일 뿐이다: 서비스 과잉 건설, 자리 선정이 단순. 리포트의 "막힌 것"은 봇의 한계와 게임의 병목이 섞여 있다.
- 계약 회차는 스텝 경계에서 실행된다(최대 1/48일 늦음). 한 스텝에 한 계약은 한 번만.
- 2층 이상 2×2 시설 자리는 플레이어가 비워 둬야 한다(봇은 층마다 2×2 자리 네 곳을 남긴다).
- `Data.gd`는 디렉터 소유라 바꾸지 않았다. 데이터 검증 오류는 Sim.setup에서 `push_error` + `sim.errors`로 나온다(UI가 보여 주면 좋다).

## 8. 실행 방법
- 시험: `godot/tests/sim_test.sh` (헤드리스, 약 15초, 마지막 줄 `RESULT: PASS`).
- 봇 리포트: `KOWLOON_NOSAVE=1 godot --headless --path godot -s res://tools/sim_run.gd -- bot=balanced days=30 seed=1` → `simulation/reports/core_balanced.md` + `.json`(약 45초).
- 검토 표: `python3 godot/tools/data_tables.py` → `docs/data_tables/*.md`.
- Game 부팅 탐침(UI 없이 오토로드만): `KOWLOON_NOSAVE=1 godot --headless --path godot res://tools/sim_game_probe.tscn`.
- 컴파일 확인: `godot --headless --path godot -s res://tools/sim_check.gd` (core/Game.gd는 -s 모드에서 Data 오토로드가 없어 실패로 나오는 게 정상 — 탐침으로 확인).
