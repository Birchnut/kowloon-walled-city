# 구조 (v0.2) — 피봇에 강한 3층 분리

목표: **기획이 통째로 바뀌어도 한 층만 다시 쓰면 되게.** 규칙을 지키는 한 각 층은 서로의 내부를 모른다.

```
godot/
  data/      모든 콘텐츠·수치(JSON). 코드 수정 없이 추가/삭제/튜닝. F5 핫리로드.
  core/      오토로드 2개: Data(로더), Game(유일한 진입점)
  sim/       규칙. 노드·렌더링 의존 0. 헤드리스로 30일 돌릴 수 있다.
    CityState.gd   저장되는 상태 전부(데이터만)
    Sim.gd         시스템들을 순서대로 돌리고 명령을 적용
    systems/*.gd   규칙 묶음 1개 = 파일 1개 (inflow, growth, economy, collection, utilities, meters, cards, unlocks, identity …)
  view/      3D 픽셀 렌더러. 상태를 읽고 이벤트를 듣기만 한다. 규칙 0.
  ui/        HUD·패널·도구. 명령을 보내고 질의 결과를 그리기만 한다. 규칙 0.
  tools/     헤드리스 도구: sim_run(봇 30일), shot(스크린샷), fake_city(아트 테스트용 도시 생성)
  tests/
  scenes/Main.tscn   CityView + UIRoot 조립만
```

## 규칙 5개

1. **View·UI는 상태를 직접 못 바꾼다.** 오직 `Game.cmd(name, args)`.
2. **Sim은 노드를 모른다.** 바깥에 알릴 일은 `state.events`에 쌓고, Game이 `event(name, payload)` 시그널로 내보낸다.
3. **UI는 규칙을 모른다.** 뭘 심을 수 있는지, 얼마인지, 셀이 뭔지는 `Game.query()` / `Game.can()`으로 묻는다. 규칙이 바뀌어도 UI는 안 바뀐다.
4. **콘텐츠 id는 데이터에만 있다.** View는 모르는 id를 만나면 기본 외형으로 그린다(콘텐츠 추가에 뷰 코드 불필요).
5. **시스템은 끄고 켤 수 있다.** `data/config.json`의 `systems` 배열에서 빼면 그 규칙은 없는 게임이 된다. 시스템 간 직접 호출 금지(상태로만 소통).

## 좌표

`Vector3i(x, y, z)` — x,y = 부지 칸(0..11), **z = 층(0 = 지상)**. 기둥 = `Vector2i(x, y)`.
뷰에서의 3D 위치는 `Vector3(x, z * floor_h, y)` (Godot은 Y가 위).

## CityState (sim/CityState.gd) — 필드 계약

| 필드 | 타입 | 뜻 |
|---|---|---|
| rng_seed, rng_state | int | 결정론 RNG |
| day, hour | int(1~), float(0~24) | 도시 시계 |
| money, food, materials | float | 3재고 |
| prestige, notoriety, morale | float 0~100 | 위신·악명·민심 |
| power_level | int | 0 없음 / 1 발전기 / 2 외부 계약 |
| water_cap | int | 물이 감당하는 인구 |
| policies | {axis: value} | data/policies.json의 축 id → 선택 id |
| cells | {Vector3i: Dictionary} | 아래 셀 계약 |
| zones | {Vector2i: String} | "housing" / "work" / "keep"(비움). 없으면 자유 |
| households | {int: Dictionary} | id, type, size, home(Vector3i 또는 null), job(사업체 id 또는 0), named(대표인물 id 또는 "") |
| businesses | {int: Dictionary} | id, type, group, cells[Vector3i], workers[int] |
| collect_points | {int: Dictionary} | id, pos(Vector3i), amount, cap, skimmed |
| alley_fund | float | 뒷골목 금고(떼인 돈 누적) |
| pending_cards | Array[Dictionary] | uid, card(데이터 id), title, body, speaker, choices[{label, hint}] |
| unlocked | {id: day} | 해금된 것 |
| flags | Dictionary | 시스템별 자유 메모(튜토리얼 단계 등) |
| identity | Dictionary | title(호칭), epithet(별명), tags[] |
| logbook | Array[Dictionary] | 최근 기록 {day, hour, text, tone}. `state.add_log(text, tone)`로 추가 |
| events | Array (저장 안 함) | 이번 틱에 일어난 일 [{name, payload}] |

### 셀
```
{ "kind": "housing" | "business" | "facility" | "site",   # site = 공사 중
  "type": "<data id>",        # housing.json / businesses.json / facilities.json
  "material": "<materials.json id>",
  "owner": int,               # 가구 id / 사업체 id / 0(공공)
  "built_day": int,
  "seed": int,                # 외형 변주용, 불변
  "progress": float,          # site만: 0..1
  "becomes": {kind,type,material,owner}   # site만
}
```
다리·외벽 계단·발코니·옥탑·간판·빨래 등은 **셀이 아니다.** 뷰가 셀 배치와 seed에서 결정론적으로 파생한다.

## Game (core/Game.gd, 오토로드)

```
Game.state : CityState
Game.view  : CityView 또는 null
signal event(name: String, payload: Dictionary)
signal state_replaced()                # 새 게임/불러오기 → 뷰는 통째로 다시 그림
Game.cmd(name, args)   -> {ok: bool, reason: String, ...}
Game.can(name, args)   -> {ok: bool, reason: String}        # 적용 없이 검증(고스트·버튼 활성)
Game.query(name, args) -> Variant                           # 표시용 정보
Game.time_of_day() -> float 0..1
Game.new_game(seed=-1) / save_game() / load_game()
Game.speed (배속), Game.paused
```

### 명령 (cmd)
| name | args | 비고 |
|---|---|---|
| plant | facility:String, pos:Vector3i | 앵커 심기. pos는 지상 빈 칸 또는 기존 셀 바로 위 |
| zone | col:Vector2i, zone:String | ""이면 지움 |
| demolish | pos:Vector3i | 위에 얹힌 게 있으면 거부 |
| policy | axis:String, value:String | |
| collect | point:int (없으면 전부) | |
| card | uid:int, choice:int | |
| debug | op:String, … | add_money, skip_hours, unlock_all … |

### 질의 (query)
| name | args | 반환 |
|---|---|---|
| hud | — | {day, hour, money, food, materials, population, prestige, notoriety, morale, title, epithet, power_level, cards} |
| facilities | — | [{id, name, desc, cost:{money,materials}, locked:bool, lock_hint}] |
| plant_spots | facility | [Vector3i] 심을 수 있는 칸 |
| policies | — | [{axis, name, options:[{id,name,desc,locked}], value}] |
| cell_info | pos | {title, subtitle, lines:[String], actions:[…]} |
| collect_points | — | [{id, pos, amount, cap, ratio}] |
| cards | — | pending_cards |
| log | n | 최근 n줄 |
| offline_summary | — | 불러오기 직후 1회: {hours, lines[]} 또는 null |

### 이벤트 (event)
`cell_changed{pos}` `zone_changed{col}` `household_arrived{id}` `household_left{id,reason}` `business_opened{id,pos}` `business_closed{id}`
`collect_ready{point}` `collected{point,amount,skimmed}` `cards_ready{count}` `unlock{id}` `power_changed{level}`
`hour{hour}` `day_started{day}` `day_ended{day}` `identity_changed{title,epithet}` `log{text,tone}`

## CityView (view/CityView.tscn, Control — 화면 전체)

```
set_floor_cut(n)        # -1 = 외관 전체. n = n층까지만, n층 천장을 열고 내부 표시
rotate_view(dir)        # ±1 = 90°씩. 4방향 스냅
zoom_step(dir) / set_zoom(level)
pick(screen_pos) -> {hit, pos:Vector3i, col:Vector2i, above:Vector3i}
project(pos:Vector3i) -> Vector2          # UI 말풍선 위치
show_ghost(pos, facility_id, ok) / show_spots(cells) / clear_overlay()
show_zones(bool)
set_time_override(t)    # -1 해제. 감상 모드
signal cell_tapped(info)        # pick 결과
signal view_changed()           # 카메라 이동 → UI 재배치
```
팬·핀치줌·회전 제스처는 View가 처리. 탭은 `cell_tapped`로 내보내고 의미는 UI의 현재 도구가 정한다.
렌더 설정(내부 해상도, 외곽선, 팔레트, 카메라 각)은 `data/render.json`. 외형 매핑은 `data/visuals.json`.

## 파일 소유 (병렬 작업 시 충돌 방지)

| 영역 | 소유 |
|---|---|
| `sim/**`, `core/Game.gd`, `tools/sim_*`, `tests/sim_*`, `data/`의 콘텐츠·수치 파일 | SIM |
| `view/**`, `data/render.json`, `data/visuals.json`, `tools/fake_city.gd`, `tools/shot*`, `assets/view/**` | VIEW |
| `ui/**`, `data/tutorial.json`, `assets/ui/**`, `scenes/Main.tscn` | UI |
| `core/Data.gd`, `sim/CityState.gd`의 **필드 이름**, 이 문서 | 디렉터(변경 시 이 문서 먼저) |

## 화면 확인 (에이전트·디렉터 공용)

```
tools/shot.sh <scene.tscn> <out_dir> [frames=30] [WxH=540x960]   # xvfb로 실제 렌더 → PNG 프레임
```
