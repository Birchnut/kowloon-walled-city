# 구조 v3 (Anno식 재편) — sim / view / ui 계약

목표는 그대로다: **기획이 통째로 바뀌어도 한 층만 다시 쓰면 되게.** 규칙은 `docs/GDD.md`, 숫자는 `godot/data/**.json`.

```
godot/
  data/            콘텐츠·수치 원본(JSON, 하위 폴더 가능). 파일 이름(확장자 제외)이 곧 키 — 이름은 폴더가 달라도 겹치면 안 된다.
    rules/config.json            격자·시간·미접속·저장 한도·거리·층 규칙·켜진 시스템 목록
    population/tiers.json needs.json
    economy/goods.json partners.json            (partners = 거래처와 계약 제안)
    buildings/buildings.json upgrade_costs.json
    progression/unlocks.json research.json policies.json
    exploration/destinations.json
    art/render.json visuals.json                (VIEW 소유)
    ui/tutorial.json                            (UI 소유)
    sim/bots.json                               (시나리오 봇)
  core/Data.gd Game.gd          오토로드. Game이 유일한 진입점
  sim/                          규칙. 노드 의존 0. 헤드리스로 돈다
  view/                         3D 픽셀 렌더러. 규칙 0
  ui/                           화면. 규칙 0 — 전부 Game.query()/can()/cmd()
  tools/ tests/
docs/data_tables/               JSON에서 자동 생성한 검토용 표 (손으로 고치지 않는다)
```

## 규칙 6개
1. View·UI는 상태를 못 바꾼다. 오직 `Game.cmd(name, args)`.
2. Sim은 노드를 모른다. 알릴 일은 `state.emit(name, payload)` → `Game.event`.
3. UI는 규칙을 모른다. 값·가능 여부·이유·미리보기는 전부 `Game.query()` / `Game.can()`이 **표시용 한국어 문장까지** 만들어 준다.
4. 콘텐츠 id는 데이터에만. View는 모르는 id를 기본 외형으로 그린다.
5. 시스템은 `config.json`의 `systems` 목록으로 끄고 켠다. 시스템끼리 직접 부르지 않는다.
6. **시계는 주입한다.** 경제 시간은 `tick(dt)`로만, 실제 시간은 `sim.now_unix`로만 들어온다. Sim 안에서 `Time.*`를 부르지 않는다.

## 좌표
`Vector3i(x, y, z)` — x,y = 부지 칸(0..11), z = 층(0 = 지상). 뷰의 3D 위치는 `Vector3(x, z*floor_h, y)`.

## CityState v3 (sim/CityState.gd) — 필드 계약

| 필드 | 타입 | 뜻 |
|---|---|---|
| rng_seed, rng_state | int | 결정론 RNG |
| econ_days | float | 경제 시계(시작부터의 경제일). `day`(int, 1부터)·`hour`(0~24)는 여기서 파생해 같이 저장 |
| money | float | 금고. 음수 불가 |
| stock | {good: float} | 도시 공유 재고 |
| cells | {Vector3i: Dictionary} | 아래 셀 계약 |
| supports | {Vector3i: true} | 골조(구조 상태). 같은 칸에 셀이 있어도 남는다 |
| buildings | {int: Dictionary} | 건물 인스턴스(아래) |
| floors_unlocked | int | 지을 수 있는 층 수(1 = 지상만) |
| waiting | {tier: {count:int, days_left:float}} | 정원 감소로 밀려난 대기 주민 |
| contracts | Array[Dictionary] | id, offer, partner, good, dir("import"/"export"), qty, interval_h, price, next_at(econ_days), paused, reserve, last{ok, reason, at} |
| partners | {id: true} | 알게 된 거래처 |
| teams | Array[Dictionary] | id, state("idle"/"out"/"done"), dest, started_unix, completes_unix, provision(bool), reward{good: n}, finds[] |
| dests | {id: {known:bool, visits:int}} | 목적지 상태 |
| research | {done:{id:true}, active:{id, done_at}} | |
| policies | {id: true} | 켜진 정책 |
| unlocked | {id: econ_day} | 열린 건물·기능 |
| milestone | int | 성채 등급(0부터) |
| heat | float 0~100 | 단속 위험 |
| happiness | float 0~100 | 도시 평균(파생, 저장) |
| ledger | {today:{tax, upkeep, import, export, build, vice}, days: Array} | 경제일 단위 장부. days는 최근 14일 |
| flow | {good: {prod, cons, imp, exp}} | 최근 1경제일 흐름(표시용) |
| clock_offset | int | 디버그: 실제 시계에 더하는 초(탐험 건너뛰기) |
| flags, logbook, stats, identity{title, grade_name}, last_saved_unix | | |
| events | Array (저장 안 함) | |

### 셀 (뷰가 읽는 것)
```
{ "kind": "house" | "facility" | "site",
  "bid": int,                # 건물 인스턴스 id
  "type": "house" | "<buildings.json id>",
  "tier": int,               # house 1..5, 그 밖 0
  "material": "common" | "wood" | "metal" | "concrete" | "",   # house만 의미
  "seed": int,               # 외형 변주. 불변
  "origin": Vector3i, "size": int,     # 2×2면 네 칸이 같은 origin(최소 x,y), size 2
  "scaffold": bool,          # 승급 공사 중인 주거(주민은 그대로 산다)
  "progress": float, "becomes": {...}  # site만
}
```
### 건물 인스턴스
```
house:    {id, kind:"house", pos, tier, material, residents:int, cap:int, happiness:float,
           needs:{need_id:{ratio:float, short_days:float, pick:String}}, need_state:"ok"|"warn"|"bad",
           upgradable:bool, upgrading:{to:int, material:String, done_at:float}|null}
facility: {id, kind:"facility", type, pos(origin), size, active:bool, paused:bool,
           staff:float, eff:float, cause:""|"staff"|"input"|"water"|"power"|"money"|"storage"|"raid"|"paused"}
```
다리·외벽 계단·간판·빨래 등은 셀이 아니다. 뷰가 파생한다.

## Game (core/Game.gd)
```
Game.state / Game.view
signal event(name, payload) · signal state_replaced()
Game.cmd(name, args) -> {ok, reason, ...}   Game.can(name, args) -> {ok, reason, ...}   Game.query(name, args) -> Variant
Game.time_of_day() · Game.speed · Game.paused · new_game / save_game / load_game / delete_save
```
Game은 매 프레임 `sim.now_unix = 시스템 시각 + state.clock_offset`을 넣고 `sim.tick(state, dt_econ_days)`를 부른다.

### 명령
| name | args | 비고 |
|---|---|---|
| zone | cells:[Vector3i] | 판잣집을 짓는다. 되는 칸만 짓고 `{built:n, skipped:[{pos,reason}]}` |
| build | type, pos:Vector3i | 시설(pos = origin). 지지대 포함 원자적 |
| demolish | pos | 그 칸의 건물 전체. 위에 뭔가 있으면 골조를 남긴다 |
| upgrade | bids:[int], material | 여러 주거 일괄. 전부 가능할 때만(원자적) |
| pause | bid, on:bool | 시설 일시 정지 |
| contract_sign | offer, size:int | 제안의 수량 단계 |
| contract_set | id, paused?:bool, reserve?:float | |
| contract_cancel | id | |
| expedition_send | team, dest, provision:bool, pick?:String | pick = 고르는 목적지의 자재 |
| expedition_claim | team (없으면 전부) | 멱등 |
| research_start | id | |
| policy_set | id, on:bool | |
| debug | op, … | add_money, add_stock{good,n}, skip_days{n}, skip_real{seconds}, unlock_all, fill_floor … |

### 질의 — 전부 표시용 문장 포함
| name | args | 반환 |
|---|---|---|
| hud | — | {day, hour, money, net_per_day, pop_total, pop:{t1..t5}, happiness, title, grade_name, floors_unlocked, floor_progress:{z, used, need}, water:{supply,demand}, power:{supply,demand}, labor:[{tier,name,have,need}], alerts:[{id,text,tone,jump}], teams_done:int, teams_idle:int, contracts_failed:int, next_goal:{text, progress:0..1}} |
| build_menu | — | [{cat, cat_name, items:[{id, name, desc, sign, size, cost:{money, goods:{id:n}}, workforce:[{tier,name,n}], upkeep, range, effect_text, locked, lock_hint, affordable}]}] — 첫 항목은 `house` |
| can | "zone"/"build"/… | {ok, reason, supports:int, cost} |
| range_preview | type, pos | {cells:[Vector3i], houses:int, text} |
| info | pos 또는 bid | 주거: {bid, kind, title, tier, tier_name, material, material_name, residents, cap, happiness, tax_per_day, needs:[{id, name, role, role_name, ratio, state, cause, cause_text, jump:{screen, arg}}], upgrade:{ready, blockers:[String], to_tier, to_name, cost:{money, qty, extra:{good:n}}, materials:[{id, name, have, enough}], preview:{cap_from, cap_to, movers, vacancies, labor:[{tier,name,delta}], tax_delta, demand_text:[String]}}} · 시설: {bid, kind, title, type, desc, sign, active, paused, staff:{ratio, lines:[String]}, io_lines:[String], eff, cause, cause_text, upkeep, range, served_houses, actions:[{id,label,enabled,reason}]} · 골조/빈 칸: {kind:"support"|"empty", title, lines} |
| economy | — | {goods:[{id, name, cat, cat_name, stock, cap, prod, cons, imp, exp, net, days_left, state}], labor:[{tier,name,have,need,spare}], utilities:[{id,name,supply,demand,ratio,sources:[String]}], finance:{today:{…}, avg:{…}, lines:[{id,name,amount}], net}, tiers:[{tier,name,pop,houses,full_houses,upgradable}]} |
| expeditions | — | {teams:[{id, name, state, dest, dest_name, seconds_left, total_seconds, reward_text}], slots:{have,max}, dests:[{id, name, desc, map:[x,y] 0..1, band:"near"|"mid"|"far", seconds, primary:{good,name,min,max}, picks:[{good,name}], bonus_text, cost:{money}, known, locked_hint, visits, new:bool}], provision:{good_text, bonus_text, enough:bool}, materials:[{id,name,have}]} |
| contracts | — | {slots:{used,max}, active:[{id, partner_name, good_name, dir, qty, interval_h, price, next_in_h, paused, reserve, last_text, per_day_money}], offers:[{id, partner, partner_name, good, good_name, dir, sizes:[{qty, interval_h, price, per_day_money}], known, lock_hint}], no_post:bool} |
| research | — | {can:bool, hint, active:{id,name,left_days}, nodes:[{id, branch, branch_name, name, desc, cost, days, state:"done"|"ready"|"locked"|"active", lock_hint}]} |
| policies | — | {slots:{used,max}, items:[{id, name, desc, on, locked, lock_hint}]} |
| goals | — | {grade, grade_name, title, steps:[{id, text, done, progress, rewards:[String]}]} |
| log | n | 최근 n줄 |
| offline_summary | — | 불러온 직후 1회 {real_hours, econ_days, lines[]} 또는 null |

### 이벤트
`cell_changed{pos}` `support_changed{pos}` `building_changed{bid}` `floor_unlocked{z}` `house_upgraded{bid,tier,material}` `expedition_done{team}` `expedition_claimed{team,rewards}` `contract_done{id,ok,reason}` `unlock{id,name}` `milestone{grade,grade_name,title}` `alert{id,text,tone}` `power_changed{on}` `hour{hour}` `day_started{day}` `day_ended{day}` `log{text,tone}`

## CityView (view/CityView.tscn) — v2에서 유지 + 추가
```
유지: set_floor_cut(n) · rotate_view(dir) · zoom_step(dir)/set_zoom(i) · pick(screen)->{hit,pos,col,above,…}
      project(pos)->Vector2 · clear_overlay() · set_time_override(t) · set_bottom_inset(px) · get_max_floor()
      signal cell_tapped(info) · signal view_changed()
추가: pick_floor(screen, z) -> {ok, pos:Vector3i}      # z층 평면 위의 칸(비어 있어도). 배치용
      show_floor_grid(z, on)                            # z층 평면 격자(열린 층이면 밝게)
      show_ghost(cells:[Vector3i], ok:bool, supports:[Vector3i]=[])   # 배치 미리보기 + 생길 골조
      show_cells(cells:[Vector3i], style:String)       # "range" | "valid" | "select" | "warn"
      set_lens(name)                                    # "" | "needs" | "tier" | "happiness" — 주거를 색으로
      set_drag_paint(on)                                # 켜면 끌기가 팬이 아니라 signal cell_dragged(info)
      signal cell_dragged(info)
```
뷰는 `buildings[bid]`에서 residents/cap(불 켜진 창 비율), need_state, upgradable(작은 화살표), active(연기·간판 불)를 읽어 그린다.

## 파일 소유
| 영역 | 소유 |
|---|---|
| `sim/**`, `core/Game.gd`, `tools/sim_*`, `tests/sim_*`, `data/`의 rules·population·economy·buildings·progression·exploration·sim | SIM |
| `view/**`, `data/art/**`, `tools/fake_city.gd`, `assets/view/**` | VIEW |
| `ui/**`, `data/ui/**`, `assets/ui/**`, `scenes/Main.tscn` | UI |
| 이 문서, `core/Data.gd`, CityState의 **필드 이름** | 디렉터 |

## 화면 확인
`tools/shot.sh <scene|""> <out_dir> [frames] [WxH] [key=value…]` — 인자는 `godot/tools/DevHarness.gd` 참고.
