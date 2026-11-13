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
| upgradable | tier?:int | [{tier, tier_name, count, bids:[int]}] — 지금 승급 가능한 주거 |
| upgrade_preview | bids:[int], material | info.upgrade.preview와 같은 모양의 **합산** 미리보기 + {ok, blockers, cost:{money, qty, extra}} |
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

## 파트 B 추가(SIM, 2026-11-11) — 모두 덧붙이기만(기존 키·명령 이름은 그대로)

**시스템**(config `systems` 순서): progression → goals → space → contracts → expeditions → research → policies → workforce → utilities → production → needs → upgrades → vice → finance → alerts.
**데이터**: `exploration/destinations.json`, `progression/goals.json`, `progression/research.json`, `progression/policies.json`, config `heat.*`, `alerts.*`, `time.offline_step_mult`, `time.offline_min_gap_seconds`, buildings `vice.heat`·`vice.raid_line`.

| 추가 | 내용 |
|---|---|
| 명령 | `expedition_send`/`expedition_claim`(claim 결과 `{ok, rewards:[{good,name,n}], finds:[String], teams}`), `research_start {id}`, `research_cancel {}`(절반 환불), `policy_set {id, on}`, `tutorial {step:int}` → `state.flags.tutorial` |
| can 결과 | `code` 추가 — build/zone: `ok`·`occupied`·`locked_floor`·`money`·`goods`·`locked`·`sky`·`bounds`; 탐험: `busy`·`claim`·`unknown`·`money`·`provision`·`nothing`; 연구: `study`·`busy`·`locked`·`money`; 정책: `slots`·`group` |
| 질의 | `demolish_preview {pos}` → `{ok, title, lines}` · `vice` → `{heat, warn, raid, gain_per_day, decay_per_day, items[]}` · `goals`에 `next, sandbox, done_count, total`, step에 `final, done_day` · `research`에 `done, total`, node에 `tier, affordable` · `policies` item에 `upkeep, group` · `expeditions` team에 `state_name, rewards, provision, retired`, dest에 `per_hour`, `now_unix` |
| hud | `floor_progress.text`, `tutorial`, `heat`, `research{id,name,left_days}`, `next_goal{id,text,progress,rewards}`, `alerts_total` |
| info | 주거 수요 행에 `jump_alt:[{screen,arg,label}]`(원인 "재고 없음"일 때 그 상품을 얻는 곳), 시설에 `size`, `footprint:[Vector3i]`, 원인 `raid` |
| economy | `finance.today.net`, `finance.avg.net`, 장부 줄 `reward`(목표 보상)·`fine`(벌금) |
| offline_summary | 보여 줄 것이 없으면 **null**. 있으면 `{real_hours, econ_days, lines[], clamped}` 한 번 |
| 주거 필드 | `upgradable` = **지금** 승급할 수 있음(만실·수요 + 돈 + 세 계열 중 하나 이상 + 추가 상품) — 뷰의 ▲ 표시용. `ready` = 비용만 빼고 조건 충족. 성능 캐시 `psig`·`nsig`·`sdm`·`sdc`(저장됨, 읽지 말 것) |
| 시설 필드 | `raided`, `raid_until`(단속 폐쇄) |
| 이벤트 | `goal_done{id,text,rewards}`, `research_done{id,name}`, `raid{bid,type,until,fine}`, `raid_end{bid}`, `alert{id,text,tone}`(새로 뜬 알림) |

**알림 jump 화면**(G12): `build[:시설 id|cat]` · `economy[:tab|상품 id]` · `expedition` · `trade` · `keep[:tab]`(성채 화면: goals·policies·research·log) · `upgrade`(일괄 승급 열기) · `inspect:<bid>`(그 건물 정보, arg = bid).
**미접속**: Game이 불러올 때와 앱이 60초 넘게 멈췄다 돌아올 때 `Sim.catch_up(state, now)`을 부른다. `state.last_saved_unix`는 "마지막으로 정산한 실제 시각"으로도 쓰인다.

---

# v4 (PC판) 계약 변경 — 2026-11-13, 디렉터

설계는 `docs/GDD_PC.md`. 아래는 v3 계약에서 **바뀌는 것과 더하는 것**이다. 여기 없는 것은 v3 그대로. 세 층(SIM·VIEW·UI)은 이 절만 보고 서로 맞는다 — 모자라면 가장 단순한 쪽으로 정하고 자기 노트의 "계약 빈 곳"에 적는다.

## 좌표·격자
- `grid.width/height` = 16(데이터). **어느 층도 12를 가정하지 않는다** — `Game.query("hud").grid = {w, h, floors}`에서 읽는다.
- 시설 발자국: 데이터 `footprint:[w,h]`(x방향 w칸, y방향 h칸), `floors:1|2`(쌓이는 층 수), `rot`(0 = 그대로, 1 = 90° — w,h가 바뀐다). `origin` = 발자국의 최소 (x,y,z) 칸.

## 셀 (뷰가 읽는 것) — 더하는 키
```
"origin": Vector3i, "w": int, "h": int, "d": int(층 수), "rot": 0|1,   # 주거는 1,1,1,0
"size": int            # 호환용 = max(w,h). 새 코드는 w,h를 쓴다
"burn": "" | "burning" | "burnt"      # 불(주거·시설 모두). burnt = 수리 전까지 못 씀
"sick": bool                          # 병이 도는 주거
"trash": float 0..1                   # 그 칸 주변에 쌓인 쓰레기(뷰가 더미로 그린다)
```
`kind:"site"`(공사 중)는 발자국 전체 칸에 깔리고 `progress` 0..1, `becomes:{type,w,h,d,rot}`.

## 건물 인스턴스 — 더하는 키
```
house:    + arriving: float(입주 중인 인원의 소수 진행, 표시용) · burn · sick · sick_until(econ_days) · repair:{money, goods, days}|null
facility: + w,h,d,rot · burn · build_left(days) · repair
```

## 범위 (다이아몬드 폐지)
- 데이터 `range: {r:int, up:int, down:int}` 또는 없음. 닿는 칸 = 발자국의 어느 칸에서든 `max(|dx|,|dy|) ≤ r` 이고 `-down ≤ dz ≤ up`(시설의 가장 아래층 기준, 2층짜리는 위층도 자기 층으로 친다).
- `distance.vertical_weight`·`max_floor_delta`는 없앤다.

## 시계
- **실제 시계 의존을 없앤다.** `time.offline_speed = 0` → Game은 불러올 때·긴 공백 뒤에 정산하지 않는다(`offline_summary`는 항상 null). 탐험·연구·계약·건설 전부 `econ_days` 기준.
- `teams[].started_at / completes_at`(econ_days). `started_unix/completes_unix/now_unix/clock_offset`은 남겨 두되 쓰지 않는다. 질의 `expeditions`의 `seconds_left/total_seconds`는 **×1 기준 실제 초**로 환산해 계속 준다(+ `days_left`, `total_days`).
- `Game.speed` ∈ {1,2,4}(디버그 16), `Game.paused`. `hud.speed`, `hud.paused` 추가. 명령은 멈춘 상태에서도 된다.

## 명령 — 바뀜/추가
| name | args | 비고 |
|---|---|---|
| build | type, pos(origin), **rot:0\|1** | 발자국·층 수·골조 포함 원자적. 공사 시간이 있으면 `site`로 시작 |
| repair | bid | 탄 건물 수리 시작(돈·고물, 시간) |
| run_begin | dest | 직접 줍기 시작 표시(팀 하나를 "나감"으로). 결과: `{ok, reason, stock:{good:n}, danger:int, seed:int}` |
| run_result | dest, loot:{good:n}, outcome:"boss"\|"exit"\|"down", finds:[String] | 직접 줍기 결과 반영. 던전 재고에서 빼고, 창고에 넣고, 발견물 처리. `{ok, rewards:[{good,name,n}], finds:[String], lost:[…]}` |
| debug | + start_fire{pos}, start_outbreak{pos}, set_hazard{kind,on} | |
제거: 미접속 관련(`skip_real`은 `skip_days`의 별칭으로 남긴다).

## 질의 — 바뀜/추가 (전부 표시용 문장 포함)
| name | args | 반환 |
|---|---|---|
| hud | — | + `grid:{w,h,floors}`, `speed`, `paused`, `signals:[{id:"water"\|"power"\|"food"\|"fun"\|"fire"\|"disease"\|"labor", name, state:"ok"\|"warn"\|"bad"\|"off", text, jump}]`, `hazards:{fire:{on, burning:int, burnt:int, covered_pct}, disease:{on, sick_houses:int, covered_pct}}` |
| build_menu | — | item에 + `footprint:[w,h]`, `floors`, `rotatable:bool`, `build_days`, `range:{r,up,down}\|null`, `needs_sky:bool`, `min_floor:int`, `effect_text` |
| can | cmd:"build", type, pos, rot | + `cells:[Vector3i]`(발자국 전부), `supports:[Vector3i]`(생길 골조), `code`에 `shape`(자리가 모자람)·`sky`(위가 막힘)·`floor`(층 조건) 추가 |
| range_preview | type, pos, rot | `{cells:[Vector3i](모든 층), by_floor:{z:[Vector3i]}, houses:int, text}` |
| coverage | kind:"market"\|"fun"\|"fire"\|"trash"\|"clinic"\|`service:<id>` | `{covered:[Vector3i], uncovered:[Vector3i](쓰이는 칸 중 밖), pct, text}` — 렌즈용 |
| metrics | — | **현황판**: `{rows:[{id, group:"utility"\|"food"\|"goods"\|"service"\|"hazard", name, supply, demand, unit, ratio, state, days_left\|null, hint, jump:{screen,arg}}], labor:[{tier,name,have,need,spare}], tiers:[{tier,name,pop,houses,full,upgradable,arriving}], finance:{income, cost, net, lines:[{name,amount}]}, hazards:[{id,name,on,covered_pct,active:int,text,jump}]}` |
| hazards | — | `{fire:{on, since_day, grace_left, covered_pct, burning:[{bid,pos}], burnt:[{bid,pos,repair_text}], text}, disease:{on, covered_pct, sick:[{bid,pos,days_left}], trash_pct, text}}` |
| info | pos\|bid | 주거에 + `arriving_text`, `burn`, `sick`, `repair:{ok, cost_text, days}`; 시설에 + `w,h,d,rot`, `footprint`, `build_left_text`, `range:{r,up,down}`, `interior:{staff_ratio, active}` |
| expeditions | — | 팀·목적지에 + `days_left/total_days`, 목적지에 `stock_pct`(던전 재고), `run:{available:bool, danger:int, text}` |
| goals / research / policies / contracts / economy / upgradable / upgrade_preview | | v3 그대로(내용·이름만 바뀜) |

## 이벤트 — 추가
`construction_done{bid,type}` `fire_started{bid,pos}` `fire_spread{bid,pos}` `fire_out{bid,pos,burnt:bool}` `repaired{bid}` `outbreak{bids:[int],pos}` `outbreak_end{bids}` `hazard_on{kind,grace_days}` `speed_changed{speed,paused}`.
알림 jump에 `focus:x,y,z`(카메라를 그 칸으로) · `metrics[:row]` · `lens:<kind>` 추가.

## CityView (view/CityView.tscn) — PC
```
유지: set_floor_cut(n) · rotate_view(dir) · zoom_step(dir)/set_zoom(i) · pick(screen) · pick_floor(screen,z) · project(pos)
      clear_overlay() · set_time_override(t) · get_max_floor() · show_floor_grid(z,on) · show_ghost(cells,ok,supports)
      show_cells(cells,style) · set_lens(name) · set_drag_paint(on) · signals cell_tapped / cell_dragged / view_changed
바뀜: set_bottom_inset(px) → set_insets(left,top,right,bottom)     # UI 패널이 가리는 만큼 중심을 옮긴다
      show_ghost(cells, ok, supports, floors:int=1)                  # 여러 칸·2개 층 미리보기
      set_lens: "" | "needs" | "tier" | "happiness" | "coverage"     # coverage는 set_coverage(covered, uncovered)와 함께
추가: hover(screen) -> info      # pick과 같은 모양. 뷰가 매 프레임 마우스 아래 칸을 강조하고 signal cell_hovered(info)
      set_zone_preview(cells:[Vector3i], ok:[bool])    # 주거 칠하기: 바닥 하이라이트만(입체 상자 금지)
      set_coverage(covered:[Vector3i], uncovered:[Vector3i])
      focus(pos:Vector3i, zoom:int=-1)                 # 카메라를 그 칸으로(부드럽게), 층 자르기도 맞춘다
      set_input_enabled(on)                            # 창이 떠 있을 때 UI가 끈다
      who(screen) -> {ok, text}                        # 마우스 아래 주민 한 줄("굴러온 돌 · 통조림 사러 가는 중")
      signal cell_tapped(info)  # info.button = 1(왼쪽)|2(오른쪽)
```
- **카메라 입력은 뷰가 가진다**: 휠 확대, 가운데·오른쪽 끌기 이동, WASD/방향키 이동, Q/E 회전, PageUp/PageDown·[ ] 층. 그 밖의 키(Space, 숫자, R, Esc, Tab, B, Del…)는 UI.
- 뷰는 `buildings[bid]`의 `staff/eff/active`(시설 안 사람 수·불), `residents/cap`, `burn`, `sick`, 셀의 `trash`, `site.progress`를 읽어 그린다. 주민 동선은 뷰가 상태에서 파생한다(규칙 아님).
- 간판 글자는 `Game.query("build_menu")`의 `sign`(짧은 한글, 4자 이내)을 쓴다. 한자 금지.

## 화면 크기
`project.godot` 표시 설정(1920×1080, canvas_items/expand, 가로)과 `scenes/Main.tscn`은 UI 소유. 뷰는 창 크기에 맞춰 저해상 뷰포트를 정수배로 올린다(1280×720~2560×1440).

## 파일 소유 (v4)
| 영역 | 소유 |
|---|---|
| `sim/**`, `core/Game.gd`, `tools/sim_*`, `tests/**`, `data/`(art·ui 제외), `docs/SIM_NOTES.md`, `docs/BALANCE_CHANGELOG.md`, `docs/data_tables/` | SIM |
| `view/**`, `data/art/**`, `assets/view/**`, `tools/fake_city.gd`, `docs/VIEW_NOTES.md` | VIEW |
| `ui/**`, `data/ui/**`, `assets/ui/**`, `scenes/Main.tscn`, `project.godot`, `tools/DevHarness.gd`, `tools/fixtures/**`, `docs/UI_NOTES.md` | UI |
| `expedition/**`(직접 줍기), `docs/EXPEDITION_RUN.md` | 2단계에서 정함 |
| 이 문서, `docs/GDD_PC.md`, `core/Data.gd`, CityState의 필드 이름 | 디렉터 |

## 시설 외형 이름표 `look` (SIM이 고르고 VIEW가 그린다)
시설 id는 SIM이 바꾸고 늘린다. 그래서 뷰는 id가 아니라 `buildings.json`의 `look`(아래 목록 중 하나)으로 그린다. 셀과 `build_menu` 항목에 `look`이 실린다. 목록에 없는 값·빈 값은 `cat`별 기본 외형.
```
시장:   market_mat · market_alley · market_hall · market_mall
물·전기: water_catcher · water_tank · water_pipe · water_plant · gen_small · power_tap · power_plant · power_waste
먹을 것: food_cans · food_pilgrims · noodle_mill · noodle_stall · rat_farm · burger · sushi · roof_garden · brewery
생활:   oil_collect · candle · soap · rag_collect · tailor · suit · radio · assembly · fake
놀 것·서비스: mahjong · teahouse · karaoke · bathhouse · shrine · study · roof_park · dentist · pharmacy · salon
방재:   fire_bucket · fire_station · trash_guild · clinic
기반:   scrapyard · warehouse · trade_post · expedition_base
음성:   gambling · casino · callcenter · fireworks
명소:   landmark_hall · landmark_generic
기본:   generic_workshop · generic_shop · generic_service
```
시설 안 묘사(가까이 볼 때): `look`마다 소품과 일하는 사람 자리가 있고, 보이는 사람 수 = `staff` 비율, 꺼진 시설은 불이 꺼진다.

---

# v5 계약 변경 — 2026-11-14, SIM (초안: 구현하며 고친다)

기준 기획은 `docs/DESIGN_v0.5.md`. 아래는 v4 계약에서 **더하거나 바뀌는 것**이다. 화면·그림·소리는 이 절만 보고 붙인다. 모든 새 규칙은 config `systems`의 id로 켜고 끈다(꺼지면 질의는 기본값을 돌려준다). 숫자는 임시값(`_status: "임시값(v0.5)"`).

## 새 시스템
config `systems`에 `chronicle`(민력·연표·고요시간·마지막 장)과 `org`(조직·치안·갈등·부랑자)를 더한다. `hazards`·`space`·`finance`·`needs`는 안에서 새 규칙을 읽는다.

## 이름
- 플레이어는 처음부터 `identity.title = "방백"`.
- 분류 `vice`의 표시 이름은 **조직**(`buildings.json cats.vice`). 조직 시설은 데이터 `org`: `"thirteen"`(십삼요회: gambling_den, casino) · `"yeonu"`(연우당: callcenter, fireworks, fake_shop). 이름은 `orgs` 질의로 받는다.
- 일하지 않는 벽틈시민 = **쉬었음시민**(질의 `idle_citizens`).
- 되살린 9종: power_plant 큰 발전기 · power_waste 재 태우는 발전 · oil_collect 폐기름 모으는 집(재화 oil = 폐기름) · suit_shop 양복 짓는 집 · assembly 조립 공방 · scrapyard 고물 뜯는 곳 · warehouse 창고 · fireworks 화약방 · fake_shop 모조품 공방(재화 fakelux = 모조품).

## 질의 — 추가
| name | args | 반환 | 예 |
|---|---|---|---|
| `date_minryeok` | — | `{year:int, season:"장마"\|"봄"\|"여름"\|"가을"\|"겨울", season_idx:0..3, year_day:float(0..3), hour:int, minute:int, text:String}` | `{year:4, season:"장마", text:"민력 4년 장마 06:00"}` |
| `chronicle` | — | `{lines:[{day:int, year:int, season:String, date_text:String, text:String, kind:String}], count:int}` (오래된 것부터) | `{date_text:"민력 4년 봄", text:"첫 불이 났다.", kind:"first_fire"}` |
| `security` | — | `{value:0..100, low:bool, threshold:int, org_active:int, vagrant_risk:bool, text:String}` | `{value:42, low:false, text:"치안 42"}` |
| `conflict` | — | `{value:float, max:100, thirteen:int, yeonu:int, buffer:int, rising:bool, text:String}` (두 조직이 다 있을 때만 `rising`) | |
| `leak_per_day` | — | `{amount:float(₩/경제일), vault:float, safe_cap:float, over:float, rate:float, text:String}` (평소 amount 0) | |
| `covered_depth` | `pos:Vector3i` | `int` — 그 칸(x,y,z)의 위에 덮인 층 수(위 층에 건물·골조가 있는 층 수). args 없이 부르면 `{Vector3i: int}` 전체(0 아닌 칸만) | |
| `warehouse_cover` | `floor:int` | `{covered:bool, size:int(그 층을 덮는 가장 큰 창고 칸수), warehouses:[{bid, size, floors:[int]}], production_mult:float}` — 렌즈용 | |
| `last_page` | — | `{ready:bool, shown:bool, year:int, axes:[{id, name, value:float, text:String}], text:String}` 다섯 축 id: `tiers`·`money_source`·`height`·`updown`·`gaze` | |
| `idle_citizens` | — | `{count:int, t1:int, text:String}` | |
| `orgs` | — | `{items:[{id:"thirteen"\|"yeonu", name, buildings:[String], active:int}]}` | |

hud에 `date`(= `date_minryeok`), `security`(value, low), `conflict`(value), `leak`(amount)를 덧붙인다. `build_menu` 항목에 `org`(id 또는 `""`), `org_name`, `advance_mult`(조직 선금 배수, 아니면 1), `storage_cells`(창고 칸수, 아니면 0)를 더한다. `build_menu` 값 `cost`는 **선금이 얹힌 최종 값**이다.

## 명령·can — 추가
- `build`의 can `code` 추가: `org_zone`(두 조직이 같은 층·맞닿은 층), 이때 `reason`에 어느 조직·어느 층인지가 들어 있다.
- `demolish_preview`에 받침 값이 `lines`에 들어간다(`받침 N층: +값`). 철거 비용은 `base × (1 + 층당 0.5 × 위에 얹힌 층 수)`.
- 새 명령 `last_page_ack {}`: 마지막 장을 한 번 보여 준 것으로 표시(저장됨, 이후 `last_page.shown = true`). 게임은 계속된다.

## 이벤트 — 추가
`quiet_start{}` · `quiet_end{}`(게임 시계 03:12, 조금 뒤 — 길이는 화면·소리 몫) · `chronicle_added{text, date_text, kind}` · `first_fire{bid,pos,card:{title,text}}` · `first_disease{bids,pos,card:{title,text}}` · `vagrant_incident{kind:"rest"\|"loss"\|"fire", bid, pos, text}` · `org_clash{kind:"fire"\|"damage", bid, pos, org, text}` · `last_page_ready{page}` · `security_low{value}`.

## 상태 — 추가 필드
`state.flags`에 들어간다(옛 저장에는 없어도 기본값으로 돈다): `chronicle` · `chron_first` · `quiet_state` · `security` · `conflict` · `last_page` · `leak_total` · `gaze_max`.

## 건물 데이터 — 추가
`org`, `storage_cells`(1|2|4), 새 시설 `warehouse_small`(1×1, look `warehouse_small`)·`warehouse_big`(2×2, look `warehouse_big`). 기존 `warehouse`는 2칸짜리.
