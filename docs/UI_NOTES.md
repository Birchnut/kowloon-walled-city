# UI 노트 — 통합(v4, `integ4`) 덧붙임

V4Shim 은 지웠다(§5 의 S1~S13 전부 진짜로). 통합 때 바뀐 결정·파일은 `docs/INTEG_NOTES.md` v4 절 §3(I1~I14). 새 파일: `ui/pc/RunPanel.gd`(직접 줍기 진입·id 맞추기). 단축키 추가: K(기반)·L(명소). 설정에 소리 막대. 하네스: `save`·`perf=1`. 대본: `tools/fixtures/pc_{first_session,first_upgrade,fire_lesson,disease_lesson,direct_run,jumps}.json`. 뷰(`godot/view/**`)는 고치지 않았다 — VIEW_NOTES 그대로.

# UI 노트 v4 (PC판 v0.4, 브랜치 `ui4`)

모바일 세로판(v0.3)의 화면은 이 브랜치에서 지웠다(`backup/v0.3-mobile`에 있다). 이제 `godot/ui/pc/**` 가 PC 화면 전부다.
기준 1920×1080 가로, 마우스 + 키보드. v4 계약(`docs/ARCHITECTURE.md` "v4 (PC판) 계약 변경")의 이름 그대로 부르고, 이 클론에 아직 없는 v4 조각은 **`godot/ui/dev/V4Shim.gd` 한 곳**이 채운다(§5).
스크린샷: `docs/shots/pc_ui_*.png`(§9). 아래 v3 노트는 역사로 남긴다.

## 0. 다시 보기

```
# 새 도시 300프레임(스크립트 오류 0 확인)
tools/shot.sh "" /tmp/f 300 1920x1080 skiptut
# 첫 접속 전체를 진짜 마우스·키보드로(오프닝 따라: 카메라 → 판잣집 8 → 시장(R로 돌림)·물 둘·먹을 것·놀 것 → 살피기 → 배속 → 현황판 → 일괄 승급 자재 고르기)
SHOT_TIMEOUT=1200 tools/shot.sh "" /tmp/w 6000 1920x1080 script=res://tools/fixtures/pc_first_session.json out=/tmp/w trace=1
# 큐레이션 A(새 도시: 칠하기·고스트·돌리기·거절·두 층 명소·툴팁·철거 확인·도움말·불과 병) / B(load=mid: 살피기·창 전부·승급·렌즈)
SHOT_TIMEOUT=900 tools/shot.sh "" /tmp/a 3000 1920x1080 script=res://tools/fixtures/pc_shots_a.json out=/tmp/a
SHOT_TIMEOUT=900 tools/shot.sh "" /tmp/b 3000 1920x1080 load=mid skiptut script=res://tools/fixtures/pc_shots_b.json out=/tmp/b
# 크기 확인
tools/shot.sh "" /tmp/s 25 1280x720 skiptut load=mid open=metrics
tools/shot.sh "" /tmp/s 25 1920x1080 skiptut load=mid scale=1.5 open=metrics
# 웹(데스크톱 브라우저) — 빌드됨(브라우저 실행은 이번에 못 함)
godot --headless --path godot --export-release "Web" build/web/index.html
```
대본 문법은 `godot/tools/DevHarness.gd`(머리 주석 + `_step`). 누름은 전부 `Input.parse_input_event` 의 **InputEventMouseButton/Motion/Key**(진짜 길). 좌표 대신 이름표·대상으로 쓴다: `{"place": "분류:market", "cell": [x,y,z], "rotate": 1}`, `{"target": "cat:water"}`, `{"press": "시작한다"}`, `{"key": "Tab"}`. 칸 좌표는 시뮬 칸(x,y,z)이라 v4 시뮬(16×16)에서도 그대로 뜻이 있다.

## 1. 화면 지도 (1920×1080 논리 px)

```
┌ 위 띠 TopBar (높이 52) ──────────────────────────────────────────────────────────────────────────────┐
│ ₩돈 +순수입/일 │ 계층 5칩(이름·인구) │ 행복 │ 신호등 7(물 전기 먹을것 놀것 불 병 일손) │      │ 날·시각 │ ❚❚ ×1 ×2 ×4 │
├────────────────┬─────────────────────────────────────────────────────────────────┬──────────────────┤
│ 왼쪽 기둥 340  │                                                                 │ 살피기 420        │
│ ┌ 다음 목표 ┐  │                      도시(뷰) — 가운데                           │ (고른 것 / 마우스  │
│ │글·진행·방법│  │       · 배치 중: 마우스 옆 한 줄(이름·비용·범위 안 집·골조·R / 거절 이유)│  아래 미리보기)   │
│ │가는 버튼   │  │       · 알림·카드(토스트): 위 띠 아래 가운데                      │                  │
│ └───────────┘  │                                                                 │                  │
│ ┌ 알림 n ───┐  │                 창: 현황판·경제·교역·탐험·성채·승급(가운데, 끌어 옮김)   │                  │
│ └───────────┘  │                                                                 │                  │
│ ┌ 보는 층·렌즈┐ │  ┌ 짓기 막대 ───────────────────────────────────────┐            ├──────────────────┤
│ │전체 1F 2F… │ │  │ [주거 칠하기 H][철거 X][따라 짓기 G] │ 분류 탭 Z C V B N M , . / │ │ 현황판Tab 경제F2 교역F3│
│ │3F 열림까지%│ │  │ (분류를 고르면) 시설 카드: 그림·이름·모양·비용      │            │ 탐험F4 성채F6 도움말F1│
│ │렌즈 8개    │ │  └──────────────────────────────────────────────────┘            │                  │
└────────────────┴─────────────────────────────────────────────────────────────────┴──────────────────┘
```
- 뷰에는 `set_insets(왼 360, 위 52, 오른 440 또는 0, 아래 짓기 막대 높이)`를 알린다(살피기가 떠 있을 때만 오른쪽).
- 좁은 창: 논리 폭 < 1800이면 계층 칩은 숫자만(이름은 툴팁), < 1450이면 순수입·날짜도 툴팁으로. 짓기 막대는 폭이 모자라면 분류 탭 이름을 빼고(그림·키), 그래도 모자라면 분류 줄이 둘째 줄로 내려간다.

## 2. 단축키

| 키 | 하는 일 | 키 | 하는 일 |
|---|---|---|---|
| 왼쪽 클릭 | 고르기(살피기) · 배치 중이면 짓기 | 오른쪽 클릭(끌지 않고) | 배치 그만 · 고름 풀기 |
| 왼쪽 끌기(칠하기) | 네모 칠하기 · Shift = 지나간 칸만 | 오른쪽·가운데 끌기 / WASD·방향키 | 카메라 이동(v4 뷰 몫) |
| 휠 | 확대(뷰 몫) | Q / E | 90° 돌리기(뷰 몫) |
| PgUp/PgDn · [ ] | 보는 층 = 짓는 층(뷰 몫) | Space | 멈춤/다시 |
| 1 · 2 · 3 | ×1 · ×2 · ×4 | H | 주거 칠하기 |
| X · Delete | 철거 도구(고른 건물이 있으면 Delete = 그것 철거 확인) | G | 마우스 아래 시설 따라 짓기(없으면 고르기 도구) |
| R | 배치 중 돌리기(1×2) | U | 승급(고른 집, 없으면 일괄) |
| Z C V B N M , . / | 짓기 분류 1~9 열기·닫기 | Tab | 현황판 |
| F2 · F3 · F4 · F6 | 경제 · 교역 · 탐험 · 성채 | F1 | 도움말 |
| F11 | 전체 화면 | Ctrl+S | 저장 |
| Esc | 배치 그만 → 맨 위 창 닫기 → 고름 풀기 → 렌즈 끄기 | Enter | 확인 창·승급·오프닝 '다음' |

## 3. 파일

| 파일 | 하는 일 | 읽는 것(질의) | 보내는 것 |
|---|---|---|---|
| `ui/UIRoot.gd` | 조립·배치·키·뷰 신호·이벤트·jump | hud(0.25초), build_menu(2초) | 모든 명령은 `UIRoot.cmd()` 로(오프닝이 엿듣는다) |
| `ui/pc/TopBar.gd` | 위 띠 | hud: money, net_per_day, pop, labor(계층 이름), happiness, signals, day, hour, speed, paused | `Game.speed/paused` |
| `ui/pc/LeftColumn.gd`, `FloorPanel.gd` | 목표·알림·층·렌즈 | hud.next_goal, alerts, floor_progress, floors_unlocked, grid; coverage{kind} | set_floor_cut, set_lens, set_coverage |
| `ui/pc/BuildBar.gd` | 짓기 막대·시설 툴팁 | build_menu | (Placement 시작) |
| `ui/pc/Placement.gd` | 칠하기·배치·철거·따라 짓기 | can zone/build{rot}, range_preview{rot}, info, demolish_preview | zone, build{type,pos,rot}, demolish; 뷰 show_floor_grid, set_drag_paint, show_ghost(…, floors), set_zone_preview, show_cells range/warn/select, pick_floor, hover |
| `ui/pc/Inspector.gd` | 살피기 | info{pos}(1초), range_preview | pause, repair, demolish(확인), jump |
| `ui/pc/MetricsWin.gd` | 현황판 | metrics | jump(행), 일괄 승급 |
| `ui/pc/EconomyWin.gd` · `TradeWin.gd` · `ExpeditionWin.gd` · `KeepWin.gd` · `UpgradeWin.gd` | 창 | economy · contracts · expeditions · goals/policies/vice/research/log · info.upgrade/upgrade_preview/upgradable | contract_*, expedition_send/claim, run_begin, policy_set, research_start/cancel, upgrade, debug |
| `ui/pc/PcTutorial.gd` + `data/ui/tutorial_pc.json` | 오프닝(마우스·키보드) | hud.tutorial, economy.tiers | tutorial{step} |
| `ui/pc/Toasts.gd` · `Dialog.gd` · `TipLayer.gd` · `HelpOverlay.gd` · `Settings.gd` | 알림·확인·툴팁·도움말·설정 | | |
| `ui/pc/PcTheme.gd` · `Picto.gd` · `PcButton.gd` · `ClickRow.gd` · `RatioBarPc.gd` · `FootprintDraw.gd` · `PcWindow.gd` | 키트 | | |
| `ui/Sfx.gd`(오토로드) | 소리 자리(빈 함수) | | |
| `ui/dev/V4Shim.gd` | **개발용 다리** — §5 | | |

## 4. 내가 정한 것 (승인 필요)

D1. **창 버튼은 오른쪽 아래 3×2 판**(현황판 Tab · 경제 F2 · 교역 F3 / 탐험 F4 · 성채 F6 · 도움말 F1). 위 띠에 다 넣으니 1920에서도 넘쳤다(돈·계층 5·행복·신호등 7·날짜·배속만으로 1730px). 이름과 키를 늘 보이게 하는 쪽을 골랐다. 현황판 버튼만 금색.
D2. **키 배치**: 배속은 과제대로 Space·1·2·3. 그래서 짓기 분류는 숫자 키 대신 **아래 줄 글쇠 Z C V B N M , . /**(짓기 막대가 화면 아래라 손 위치도 아래). H 주거, X/Delete 철거, G 따라 짓기, R 돌리기, U 승급. 창은 F2·F3·F4·F6 — **F5는 Game 이 '데이터 다시 읽기'(state_replaced)로 써서 피했다.**
D3. **UI 크기 = 고른 배율(100/125/150%) × max(창 배율, 0.8)**. 1280×720 창에서 그냥 줄이면 글자가 13px로 뭉개져서, 0.8 밑으로는 줄이지 않는다(논리 1600×900). 그래서 화면은 논리 1280×720(작은 창 + 125~150%)까지 맞췄다.
D4. **글꼴은 정수배만**: 본문 Galmuri9 ×2 = 20px, 값·버튼 Galmuri11 ×2 = 24px, 창 제목 NeoDunggeunmo ×2 = 32px. 반 배율은 픽셀 글꼴이 번진다. 테마는 코드(`PcTheme`, StyleBoxFlat·각진 모서리·아래 턱 2px·마우스 올리면 금테). v0.3 텍스처 테마는 쓰지 않는다(호버 모양이 없었다).
D5. **짓는 층 = 보는 층**. '전체'를 보다가 짓기를 시작하면 가장 위의 열린 층으로 바꿔 그 층 격자를 보이고, 그만두면 '전체'로 되돌린다. PgUp/PgDn·층 버튼으로 짓는 층을 바꾼다. (지면만 짓던 v0.3보다 위층 짓기가 쉽고, 어디에 짓는지 늘 보인다.)
D6. **고스트의 기준 = 마우스 아래 칸이 발자국 가운데**(origin = 칸 − ⌊(w−1)/2⌋). 2×2·3×3이 마우스 왼쪽 위로 치우치지 않게.
D7. **고스트 색 = 자리**: 돈·물건만 모자라면 고스트는 초록, 마우스 옆 글이 노랑으로 이유(can code money/goods). 자리 문제(occupied/shape/sky/floor/bounds)는 빨강. "어디에 놓을지"와 "살 수 있는지"를 나눠 보인다.
D8. **주거 칠하기 = 네모**(누른 칸~지금 칸), Shift = 지나간 칸만. 떼는 순간 zone 한 번. 칠하는 동안 `can zone` 으로 칸마다 되는지 받아 `set_zone_preview(cells, ok)`(바닥만) + "판잣집 n채 · ₩m · 못 짓는 칸 k(이유)". 지우개 획은 없앴다 — 지우기는 철거 도구.
D9. **지은 뒤에도 배치에 남는다**(연달아 짓기). 오른쪽 클릭(8px 안에서 누르고 뗌 — 끌면 카메라)·Esc 로 그만.
D10. **살피기 = 고른 것 우선, 없으면 마우스 아래 건물을 옅게 미리**("마우스 아래 · 눌러서 고정"). 칸이 바뀔 때만 다시 묻는다. 고른 것은 오른쪽 클릭·Esc·×로 푼다.
D11. **현황판**: 묶음(물·전기/먹을 것/물건/서비스·범위/위험) 안에서 빨강 → 노랑 → 초록 순. "문제만" 거르개. 행 = 상태·이름·공급·수요·막대·남은 날·할 일·→, 누르면 그 행의 jump. 수요 0인 행은 옅게(막대 0). 오른쪽에 일손·계층(일괄 승급 버튼)·재정·위험. jump arg 가 행 id·묶음·labor/tiers/finance 면 그 자리를 깜박인다.
D12. **신호등 일곱**(물·전기·먹을 것·놀 것·불·병·일손): 색 = state(초록·노랑·빨강·회색 꺼짐), 아래 짧은 막대, 툴팁 = 한 줄 text, 누르면 jump. 데이터에 없는 신호도 물·먹을 것·놀 것은 칸을 남긴다(자리가 흔들리지 않게).
D13. **불·병이 처음 켜질 때(hazard_on) 카드 한 장 — 누를 때까지** 남는다(그 렌즈 보기 / 알았다). 첫 불(fire_started)은 한 번만 카메라를 그 칸으로. 그 뒤로는 토스트와 알림 줄.
D14. **오프닝 9단계**(카메라 → 판잣집 8 → 시장 → 물 → 놀 것 → 집 살피기 → 배속 → 현황판 → 목표 안내). 시설은 id 가 아니라 **짓기 분류**로 기다린다(`cats`) — SIM 이 시설 id 를 바꿔도 맞는다. 모든 기다림에 timeout. 진행은 시뮬 `tutorial{step}`(끝 1000). 화자는 v0.3 그대로 '춘자 이모'.
D15. **목표 방법 줄** `data/ui/goal_tips.json`: items[목표 id] → patterns(목표 문장에 그 낱말) → 없으면 목표 문장만. 수치·시설 이름은 적지 않고 키·창·분류만 말한다.
D16. **한자 0**: 그림문자는 코드로 그린 10×10 픽셀(`Picto`, 60여 개). `UI.no_hanja()` 가 모든 라벨·토스트·툴팁에서 한자를 걷어 낸다(v3 데이터의 간판 `sign` 이 아직 한자라 안전망). v3 의 한자 탭·현수막 글자는 코드와 함께 사라졌다.
D17. **탐험 창은 목록**(v0.3 의 그린 지도는 버렸다): 탐험대 줄(남은 시간 막대·받기) + 거리 띠별 목적지 + 아래 보내기 판(고를 자재·보급·비용·이유). 목적지마다 **'직접 줍기' 버튼은 보이되 꺼짐**, 옆에 던전 재고 막대와 위험 ■□□. 지도는 직접 줍기와 함께 다시 그리는 게 맞다고 봤다.
D18. **툴팁은 자체 TipLayer**(0.3초). 짓기 카드 툴팁에 모양 그림(발자국 + 사각 범위, 두 층이면 겹친 판)·범위·일손·유지비·공사 시간(×1 분)·자리 조건·잠긴 조건.
D19. **알림**: 토스트는 위 띠 아래 가운데 최대 4줄 4초(같은 글은 다시 띄우지 않고 시간만 늘림). 소식 카드(목표 달성·해금·층·등급·연구·단속·불병 첫 안내)는 한 장씩, 넷째부터 "소식 n가지"로 합침. 목표 달성 카드에 같은 순간 열린 시설과 다음 목표를 싣는다.
D20. **숫자**: 천 단위 쉼표, 100만 이상 만/억(₩1.2억), 하루 미만은 "n시간", 비율은 %, 남은 날 1일 미만은 빨강.
D21. **승급 창**: 기본 자재 = 가장 많이 가진 것(표시 기본값), 다 안 되면 "앞에서부터 n채만"(upgrade_preview 이분 탐색, v0.3 U7), 모자란 자재 + 가장 빠른 탐험 + 탐험 창 버튼(v0.3 P9).
D22. **층 잠금 표시 = "3F 열림까지 36%" + 막대**, 툴팁에 floor_progress.text 와 "쓰이는 칸 = 사는 집 + 다 지은 시설, 빈집·공사장·골조는 세지 않는다"(v0.3 F11·F13).
D23. **렌즈 8개를 하나만**: 수요·시장·놀 곳·소방·수거·의원·계층·행복. 범위 렌즈는 `coverage{kind}` → `set_lens("coverage")` + `set_coverage(covered, uncovered)`, 켤 때 "범위 안 n/m채" 한 줄.
D24. **시작 배속·UI 크기·효과음 끔**은 `user://ui_settings.cfg`(nosave 면 메모리만). 빠른 저장(Ctrl+S)은 nosave 실행에서 막는다.
D25. **창은 가운데(위 띠 아래), 제목 띠로 끌어 옮기고 그 자리를 기억**, 여러 개 열 수 있고 누른 창이 앞으로. 크기 조절은 없다. 도시를 누르면 창은 그대로(Anno처럼).

## 5. 심 목록 — 통합 때 다시 겨눌 것 (`ui/dev/V4Shim.gd`, 지금 ENABLED = true)

모든 채움은 "키가 없을 때만" 한다 → v4 시뮬·뷰가 오면 대부분 저절로 꺼진다. 그래도 아래를 지우거나 확인한다.

| # | 어디서 | 무엇을 흉내 | v4 에서 진짜는 |
|---|---|---|---|
| S1 | `Q.raw` → `V4Shim.query("hud")` | `grid{w,h,floors}`(config), `speed/paused`(Game), `hazards{fire,disease}`, `signals[7]`(물·전기 = supply/demand, 먹을 것 = 식품 상품 state, 놀 것 = coverage fun, 불·병 = hazards, 일손 = labor), hz=1 일 때 견본 알림(focus·lens jump) | hud 그대로 |
| S2 | `query("build_menu")` | `footprint`(size 2 → 2×2, 1칸 시설 중 시장·서비스·식품·생활·전자·음성은 **가짜 1×2**), `floors`(명소 2), `rotatable`, `build_days`, `range{r,up:1,down:1}`, `needs_sky`(텃밭), `min_floor 0`, `sign` 한자 제거 | 데이터 |
| S3 | `query("metrics")` | economy(utilities·goods·labor·tiers·finance) + coverage(market·fun) + hazards 로 행을 조립, 문장 "넉넉하다/만드는 곳을 늘리거나…" | metrics |
| S4 | `query("hazards")` | 2층 열리면 불 켜짐, 3층이면 병. hz=1 이면 첫 집 불남·둘째 탐·셋째·넷째 아픔(수리 ₩120·고물 10) | hazards |
| S5 | `query("coverage")` | v3 상태의 시설 + 데이터 range 로 **v4 사각 규칙**(체비쇼프 r, 위·아래 1층)을 UI에서 계산 | coverage |
| S6 | `query("range_preview")` | 같은 사각 규칙으로 `by_floor`·houses | range_preview{rot} |
| S7 | `query("info")` | 시설 `w,h,d,rot,range(사전),build_left_text,interior`, 집 `arriving_text,burn,sick,repair` | info |
| S8 | `query("expeditions")` | `days_left/total_days`(초 ÷ 600), `stock_pct`(가짜), `run{available:false,danger,text}` | expeditions |
| S9 | `Q.can_full` → `V4Shim.can("build")` | `cells`(발자국 전부·두 층), `supports`, 가짜 1×2 의 남은 칸·두 층 자리 검사(code shape/floor) | can build{rot} |
| S10 | `Q.vcall` → `V4Shim.view_call` | `set_insets`→set_bottom_inset, `hover`→pick, `set_zone_preview`→show_cells valid/warn, `set_coverage`→show_cells range/warn, `focus`→target 옮기기, `set_input_enabled`→mouse_filter, `who`→없음 | CityView v4 |
| S11 | `UIRoot._process/_input` → `V4Shim.camera_process/camera_input` | 옛 뷰에 없는 Q/E·PgUp/PgDn·[ ]·WASD·오른쪽/가운데 끌기. **뷰에 hover + set_zone_preview 가 있으면 스스로 꺼진다** | 뷰 몫 |
| S12 | `Q.vcall` 인자 자르기 | 메서드 인자 수보다 많이 넘기면 자른다(옛 show_ghost 는 3개) | 남겨도 무해 |
| S13 | `KeepWin` 디버그 '불·병 견본(심)' · DevHarness `hz=`·`{"hz":1}`·`{"event":…}` | 견본 켜기·v4 이벤트 흉내 | 진짜 debug start_fire/start_outbreak |

지우는 법: `V4Shim.ENABLED = false` 로 한 번 돌려 본 뒤 → `ui/dev/V4Shim.gd` 삭제, `ui/Q.gd` 의 `V4Shim` 세 줄(주석 표시), `ui/UIRoot.gd` 의 `V4Shim.camera_process/camera_input` 두 줄, `KeepWin._dbg` 의 `shim_hz`, DevHarness 의 `hz` 두 곳.

## 6. 계약 빈 곳 (디렉터·SIM·VIEW 에게)

| # | 무엇 | 지금 UI | 제안 |
|---|---|---|---|
| C1 | 배속 명령이 없다(필드만) | `Game.speed = s; Game.paused = p` 를 직접 쓰고 hud.speed/paused 로 읽는다 | `Game.set_speed(speed, paused)` 가 `speed_changed` 를 내면 좋다 |
| C2 | 칠하기 끌기의 **뗌** 신호가 없다(cell_dragged 는 누름·움직임만) | UI가 `_input` 에서 왼쪽 버튼 뗌을 직접 본다 | `cell_drag_end(info)` |
| C3 | 오른쪽 클릭: 뷰가 끌기 = 카메라, cell_tapped{button:2} 도 낸다 | UI는 8px 안 누름·뗌을 오른쪽 클릭으로 본다. 뷰가 button 2 탭도 보내면 둘 다 '그만'(같은 일 두 번, 무해) | 뷰는 끌지 않은 오른쪽 뗌만 button 2 로 |
| C4 | 계층 이름이 hud 에 따로 없다 | hud.labor[].name 을 쓴다 | `hud.tiers:[{tier,name}]` 또는 그대로 |
| C5 | `metrics.rows[]` 에 재고가 없다 | 있으면(`stock`) 툴팁에 보인다 | `stock` 추가 |
| C6 | 명소·두 층 시설: `can build` 의 cells 에 위층 칸도 드는지 | 드는 것으로 가정(고스트 floors 인자와 같이) | 문서화 |
| C7 | 신호등 jump 의 screen | `build[:cat|id]`·`metrics[:row]`·`lens:<kind>`·`focus:x,y,z` 를 받는다 | 문서의 알림 jump 와 같게 |
| C8 | 방재 시설(소방·수거·의원)의 짓기 분류 id | 모르는 분류는 상자 그림 | `cat:"hazard"` 등 하나로 |
| C9 | `run_begin` 뒤 직접 줍기 화면 | 버튼은 꺼짐(run.available=false), 누르면 이유 토스트 | 3단계에서 |
| C10 | 시설 공사 진행 | info.build_left_text 만 쓴다 | 막대용 `build_progress 0..1` 이 있으면 |
| C11 | `hazard_on` 이 세이브를 다시 열 때 또 오는지 | UI 는 세션마다 한 번만 카드 | 시뮬이 한 번만 내면 그대로 |
| C12 | 디버그 `start_fire/start_outbreak` 의 pos | 고른 칸, 없으면 부지 가운데 1층 | |
| C13 | 집의 `arriving` 이 0..1 소수(표시용)라 했는데 info 는 `arriving_text` | 문장만 쓴다 | 그대로 |

## 7. 소리 자리 (`Sfx.play(이름)`, 지금은 아무 소리 없음)
`click`(모든 버튼·줄) · `build`(시설 공사 시작) · `zone`(판잣집) · `place_fail`(놓을 수 없음) · `rotate`(R) · `demolish` · `upgrade` · `money`(목표 보상) · `alert`(새 빨간 알림, id 마다 한 번) · `fire`(fire_started) · `disease`(outbreak) · `hazard_on` · `goal` · `unlock` · `floor`(새 층) · `window_open` · `window_close` · `speed` · `expedition`(보냄·받음·돌아옴). 목록과 설명은 `ui/Sfx.gd` NAMES. `Sfx.muted` 는 설정의 '효과음 끔'.

## 8. 거친 곳
- **V4Shim 견본으로만 본 것**: 불·병(신호등·카드·살피기·현황판·렌즈), 1×2 돌리기(v3 시뮬은 1칸만 짓는다 — 고스트만 1×2), 두 층 고스트(옛 뷰는 위층 칸을 따로 그리지 않아 한 층처럼 보인다 — v4 뷰 show_ghost(…, floors) 몫), 직접 줍기 버튼, coverage 렌즈 색(옛 뷰 show_cells 로 대신).
- 웹 빌드는 만들어지나(`index.pck` 7.7MB) 브라우저에서 실행해 보지 못했다(이번 작업은 브라우저 금지).
- 1280×720 창: 글자 16px 근처라 약간 무르다. 논리 1280×720(작은 창 + 150%)에서는 위 띠가 빠듯하다(날짜·순수입을 툴팁으로 뺀다).
- 살피기의 마우스 아래 미리보기가 도시를 훑을 때 자주 바뀐다 — 거슬리면 끄는 설정이 필요할 수 있다.
- 창 크기 조절 없음. 소식 카드가 창 제목을 잠깐 가릴 때가 있다(3.5초).
- 오프닝 상자가 짓기 막대 위 가운데라 도시 아래쪽을 가린다.
- 탐험 지도(그림)는 없다(목록만).
- 그림문자는 10×10 손그림이라 몇 개(놀 것=주사위, 병=세균, 철거=금 간 벽)는 툴팁 없이는 뜻이 모호할 수 있다.
- 목표 방법 줄의 patterns 는 낱말 맞추기라 엉뚱한 목표에 걸릴 수 있다(가장 앞의 패턴이 이긴다).

## 9. 스크린샷 `docs/shots/pc_ui_*.png`
01 전체(중반 도시) · 02 신호등 툴팁 · 03 짓기 카드 툴팁(모양 그림) · 04 배치 고스트 + 범위 + 커서 글 · 05 R로 돌린 고스트 · 06 거절 이유 · 06b 두 층 명소(물건 모자람 — 자리는 초록, 이유는 노랑) · 07 주거 칠하기(바닥 하이라이트) · 08 살피기(집) · 09 살피기(시설, 범위 켬) · 10 현황판 · 12 경제 · 13 교역 · 14 탐험(직접 줍기 꺼짐) · 15 성채 목표 · 16 연구 · 17 설정 · 18 일괄 승급(n채만) · 19 도움말 · 20 철거 확인 · 21 불 첫 안내 · 22 불 알림 → 그 자리 · 22b 탄 집 수리 · 23 소방 렌즈 · 23b 현황판 문제만 · 24 오프닝 · 25 1280×720 · 26 2560×1440 · 27 UI 150%(현황판) · 28 시장 렌즈.

---

# UI 노트 v3 (Anno식 도시경제, 브랜치 `ui3`)

이전 분재 시기 문서는 `docs/archive/UI_NOTES_v0.2_bonsai.md`. 키트(테마·Panel9·PixelButton·Chip·Segmented·BottomSheet·Meter·ToastLayer·Banner·DialogBox·SignTile·IconLabel·DragScroll·TimeDial·Modal·Highlight·RainOverlay)는 그대로 쓰고, 분재 화면(PlantSheet·ZoneBar·옛 PolicySheet·CardsSheet·CardView·BubbleLayer·Bubble·VerbBar·ChoiceButton·옛 Inspect/Record·MockSim·MockView·UISandbox)은 지웠다. 이제 진짜 시뮬 + 진짜 뷰로만 돈다.
스크린샷: `docs/shots/ui3_01…07_*.png` (540×960, 07은 360×800 실제 창).

## 1. 화면과 데이터 출처 (규칙 3: UI는 계산하지 않는다)

| 화면 | 파일 | 읽는 것 | 보내는 것 |
|---|---|---|---|
| 상단 띠 | `hud/TopStrip.gd` | `hud`(0.25초): 등급·호칭, 날·시각, 돈·순수지/일, 총인구, 행복, 계층 칩(pop, 이름은 hud.labor), 물·전기(supply/demand), alerts(4초마다 돌림, 없으면 next_goal) | 누르면 jump(알림의 jump, 돈→장부, 칩→노동력, 물·전기→경제) |
| 우측 레일 | `hud/FloorRail.gd` | hud.floors_unlocked, hud.floor_progress("5F 61%") | `set_floor_cut`, `rotate_view`, `zoom_step`, `set_lens("needs")` |
| 하단 바 | `hud/NavBar.gd` | 배지: hud.teams_done, hud.contracts_failed, 성채=새로 끝난 goals 단계 + 연구 끝 | 화면 열기 |
| 들여다보기 | `sheets/InspectSheet.gd` | `info{pos}`(1초·이벤트), `upgradable`, `range_preview`, `build_menu`(시설 크기) | `pause`, `demolish`(확인), 수요 줄 → jump, `show_cells select/range` |
| 승급 창 | `sheets/UpgradeDialog.gd` | 한 채 `info.upgrade`, 여러 채 `upgradable` 묶음 + `upgrade_preview{bids,material}`(없으면 `can upgrade`) | `upgrade{bids,material}` → 성공하면 창·시트를 닫아 비계 연출을 가리지 않음 |
| 짓기 | `sheets/BuildSheet.gd` | `build_menu`, `can zone`(n칸·비용·골조·skipped), `can build`(이유·support_cells), `range_preview`(주거 n채) | `zone`, `build`, `demolish`; 뷰 `show_floor_grid`, `set_drag_paint`, `show_ghost`, `show_cells valid/select/warn/range`, `clear_overlay` |
| 경제 | `sheets/EconomySheet.gd` | `economy`(goods/labor/utilities/finance/tiers), 비면 hud.labor·water·power | 일괄 승급, 짓기로 jump |
| 탐험 | `screens/ExpeditionScreen.gd`, `screens/WorldMap.gd` | `expeditions`(1초 — 남은 시간은 질의 값), `upgradable`(수령 뒤 한 줄), `can expedition_send` | `expedition_send`, `expedition_claim` |
| 교역 | `sheets/ContractsSheet.gd` | `contracts`, `can contract_sign` | `contract_sign/set/cancel` |
| 성채 | `sheets/KeepSheet.gd` | `goals`, `policies`, `research`, `log{n:40}` | `policy_set`, `research_start`, `debug`, `Game.speed/paused`, `set_time_override`, `delete_save+new_game` |
| 피드백 | `UIRoot._on_event` | `log`→토스트, `unlock`→현수막(이름·간판은 build_menu), `milestone`, `floor_unlocked`, `power_changed{on}`(UI 어둡게), `expedition_done`(배지 통통+토스트), `contract_done{ok:false}`(이유 토스트), 시작 때 `offline_summary` 모달 | |
| 오프닝 | `tutorial/Tutorial.gd` + `data/ui/tutorial.json` | 대본 전부 데이터. 단계: say / wait_cmd(match) / wait_event / wait_screen / camera / set(screens, build_only, open, close) | |

공통: `ui/sheets/Screen.gd`(화면 바탕), `components/RatioBar.gd`(막대), `Q.can_full`, `Q.upgradable`, `Q.norm_jump`.

## 2. DevHarness (`godot/tools/DevHarness.gd`) — `tools/shot.sh "" <out> <frames> 540x960 key=value…`
`skiptut` `tut=<n>` `load=<early|mid|late|경로>` `bot=` `speed=` `pause=1` `tod=` `cut=` `zoom=` `angle=` `lens=1`
`dbg=add_money:5000,mats:20,skip_days:1,skip_real:600,unlock_all,reveal_partners` `do=<cmd>|<json>;;…`
`open=<build[:house|id|분류]|economy[:labor|utilities|finance|상품]|expedition|trade[:offers]|keep[:policy|research|log]|upgrade>`
`inspect=x,y,z` `upgrade=x,y,z[,material]` `paint=x,y,z;…` `place=<id>@x,y,z` `confirm=1` `go=1` `tap=x,y`
`fakeexp=expeditions_sample` `fakekeep=keep_sample`(B 파트 전 견본) `offline=1` `toast=1` `banner=unlock|milestone|floor|power`
`png=<절대경로>`(무비 대신 실제 창 크기 한 장 — 360×800 확인용; shot.sh 무비는 늘 540×960로 찍힘).
상태 견본: `godot/tools/fixtures/{early,mid,late}.json` ← `make_fixtures.gd`(봇 balanced, 2·10·30일). 승급 외관 미리보기 12장: `tools/ui_house_previews.sh`(Sandbox 렌더 → 잘라 `assets/ui/house_previews/t<계층>_<자재>.png`).
실제 시뮬로 확인한 명령: zone(칠하기→짓기), build(좌판), upgrade 일괄 96채(go=1), demolish/pause 경로, contract 화면, 디버그.

## 3. 내가 정한 것 (승인 필요)
1. **하단 다섯 버튼은 아이콘 대신 간판 한자**(建 賬 探 行 城) + 한글. 새 아이콘을 그리지 않고 간판 모티프를 잇는다.
2. **상단 띠 3줄**(약 125px=13%): 1줄 등급·호칭/날·시각·돈·순수지·인구·행복 얼굴, 2줄 계층 칩·물·전기, 3줄 알림 한 줄. 계층이 4개 이상이면 칩 이름을 첫 글자로 줄인다(떠/세/토/유/거).
3. **알림 줄이 비면 다음 목표(next_goal)와 %를 보여 준다.** 빈 줄보다 할 일이 보이게.
4. **레일**: 층 3개까지 층마다 버튼, 넘으면 ▲ nF ▼. 다음 층 진행 칩(누르면 80% 규칙 설명 토스트). 레일이 하단 바에 닿으면 회전·줌 버튼을 접는다(두 손가락·휠로 대신).
5. **짓기의 작업 층 = 레일에서 고른 층, '전체'면 지상.** 레일을 바꾸면 격자도 그 층으로 옮긴다.
6. **시설 배치도 칠하기 모드(cell_dragged)로 받는다.** cell_tapped 가 화면 좌표/평면 칸을 주지 않아서다. 덕분에 끌어서 자리 고르기가 된다. 한 손가락 팬은 "이동" 토글.
7. **배치 모드에 들어가면 그 층 144칸에 can("build")를 물어 놓을 수 있는 자리를 "valid"로 칠하고 개수를 말한다.** 0이면 "자리 없음 — 다른 층 또는 [철거]"를 빨갛게, 막대에 철거 버튼을 상시 둔다(2×2가 꽉 찬 층에 안 들어가는 문제).
8. **주거 칠하기: 칠한 칸을 다시 눌러 시작한 획은 지우개.** 못 짓는 칸은 "warn", 지을 칸은 고스트+골조.
9. **시설을 지은 뒤에도 같은 시설 배치에 남는다**(연달아 짓기). 취소 1번 = 후보 지우기, 2번 = 시트 닫기.
10. **승급 창은 아래 64%(여러 계층이면 72%) 판**, 위로 도시가 보이게 하고 성공하면 바로 닫는다. 기본 선택 자재 = 가장 많이 가진 것(표시 기본값일 뿐). 세 자재 같은 값을 한 줄로 못 박는다.
11. **"모두 승급"은 계층 묶음별**(upgradable 의 tier 묶음). 계층이 여럿이면 창 안 칩으로 바꾼다. 알림 jump "upgrade"는 가장 낮은 계층 묶음부터.
12. **외관 미리보기는 실제 뷰 렌더(2×2×3 탑, 정오)를 잘라 136px로.** 다시 그리려면 스크립트 한 번.
13. **들여다보기 수요 줄**: 한 줄(이름·쓰는 것·막대·%·›), 원인이 있을 때만 둘째 줄. 막힌 이유는 첫 하나 + "그 밖에 n가지".
14. **경제 상품 탭은 재고 0·흐름 0인 상품을 접어 둔다**("아직 쓰지 않는 상품 n개"). jump 로 온 상품은 접지 않고 번쩍인다.
15. **장부 '오늘'의 순수지는 질의에 없어서 비워 둔다("—")** — UI가 더하지 않는다.
16. **탐험 지도는 UI가 그린다**: 지형 힌트를 목적지 주력 자재로 고른다(목재=판재 더미, 철제=고철, 콘크리트=블록·기중기, 고물=부두 상자, 설비 부품=굴뚝). 바다는 오른쪽 아래, 언덕은 위. 거리 띠 세 원. 팀은 가는 길 절반/오는 길 절반을 걷는다(질의의 남은 초 비율).
17. **부족 자재 필터 기본값 = 지금 가장 적은 자재**(모두 같으면 없음). 칩으로 바꾼다.
18. **교역 수출 최소 보유량 단계 ±10.** 해지는 확인창.
19. **첫 전기 연출(UI 어둡게)은 1분에 한 번만** — power_changed 가 깜빡여도 시끄럽지 않게.
20. **바깥(도시) 누르면 경제·교역·성채 시트가 닫힌다.** 짓기·들여다보기는 도시 누름이 곧 동작.
21. **오프닝 대본(춘자 이모)과 모든 빈 상태·확인 문구는 내가 썼다** → 톤 검수 필요. 기다림 timeout: 칠하기 180초, 시설 150초, 들여다보기 60초, 파견 120초, 승급 240초, 수령 60초(지나면 다음 단계).
22. **튜토리얼 대화가 시트 위에서 나올 때는 상자를 화면 위쪽에** 둔다(시트 내용을 가리지 않게).
23. **개발용 견본 질의 파일**(fixtures/expeditions_sample.json, keep_sample.json)을 두고 DevHarness 로만 주입. 게임은 언제나 진짜 질의를 쓴다.
24. **디버그 블록**은 성채 › 기록 아래(debug.enabled 일 때): ₩+1000, 세 자재 각 +20, 하루, 탐험 +10분/+1시간(skip_real), 전부 해금, 거래처 공개.

### 통합에서 정한 것 (2026-11-11, 브랜치 `integ` — 승인 필요)
U1. **오프닝은 손 익히기까지만**(칠하기 8칸 → 좌판 → 빗물받이 → 텃밭 → 집 살피기 → "위 줄을 봐"). 탐험·승급은 오프닝에서 뺐다. 이유: 오프닝 대기(240초 승급 등)가 목표 21단계와 같은 일을 다른 목소리로 시켜 두 줄이 겹쳤고, 첫 승급은 교역소·계약·초 공방까지 필요해 오프닝 시간 안에 못 끝난다.
U2. **그다음 안내는 목표 하나**: 위 알림 줄(알림이 없을 때) = 다음 목표, 성채 › 목표의 지금 카드 = 방법 한두 줄 + 그리로 가는 버튼. 방법 문장은 `data/ui/goal_tips.json`(UI 소유, 수치는 적지 않는다).
U3. **목표 달성 = 초록 현수막(보상) + "다음 목표 — [성채]에 방법" 토스트 + 성채 배지.** 같은 말을 하는 기록 토스트(목표 달성·성채 등급·새로 지을 수 있다)는 띄우지 않는다(일지에는 남는다).
U4. **오프닝 진행은 시뮬 `tutorial {step}`에 저장**(세이브와 함께). 끝남/건너뜀 = 1000. 다시 열면 그 단계부터, 이미 해 둔 wait_cmd 는 건너뛴다. 옛 세이브(hud.tutorial 0, 2일 이상)는 본 것으로 친다.
U5. **상단 띠 돈 변화량은 동전 왼쪽 같은 줄**에서 옆으로 사라진다. 하루 순수지의 1/20(최소 ₩10)보다 작은 변화는 띄우지 않는다(숫자만 굴린다). 100만 이상은 만/억(`UI.big`) — 돈·순수지·인구·계층 칩.
U6. **계층이 다섯이면 칩을 더 줄인다**(점 대신 이름 글자에 계층색, 간격 2). 물·전기 막대 40→32px.
U7. **일괄 승급이 다 안 되면 "앞에서부터 n채만"**(upgrade_preview 를 이분 탐색으로 물어 시뮬이 판정). 승급 버튼은 늘 판 맨 아래(줄바꿈 글자는 목록 안으로).
U8. **미접속 10분 미만은 창 대신 토스트 한 줄**(clamped 면 창). 제목은 "8시간"처럼 0분을 뺀다, 1일 미만은 "경제 시간으로 n시간".
U9. **교역 제안 맨 위 '집들이 찾는 것'**: 계층마다 집 한 채의 info 를 물어 비율 < 1인 기본·승급 수요의 상품 이름과 같은 수입 제안을 올린다(판정은 info 그대로).
U10. **성채 목표 순서 = 지금 → 앞으로 n개 → 끝낸 것(최근 먼저, 달성 날)**. 긴 보상(열리는 건물 목록)은 꼬리표 대신 줄바꿈 글자. 새로 끝난 목표가 있으면 성채를 열 때 목표 탭부터.
U11. **단속 위험 판은 성채 › 정책 맨 위**(음성 시설이 있거나 위험 > 0일 때만). 시뮬 알림 heat 의 jump 가 keep:policies 이고 뒷돈 정책이 거기 있어서다. 단속 = 빨간 현수막(벌금·이틀), 풀림 = 토스트.
U12. **연구 판**: 멈춤(공부방 없음)을 빨갛게, 그만두기(절반 환불)는 확인창, 갈래 칸 폭 같게·값 두 줄.
U13. **같은 순간 열린 건물은 현수막 하나**("새로 지을 수 있다 · 4가지"), 탐험 발견도 하나. 토스트 최대 3. 토스트는 위쪽 대화·힌트 아래로 비킨다.
U14. **대화 상자가 위에 있을 때 건너뛰기는 왼쪽 아래**(오른쪽 레일과 겹쳐서).
U15. **탐험 머리 두 줄**(제목·팀 수 / 자재 칩 전체 폭), 자재 칩 이름 줄임(콘크리트·부품). 거점 공사 중이면 "짓는 중".
U16. **배치 자리 스캔은 can 의 code**(`money`/`goods`면 자리는 됨) — 문장 의존 제거(G3).
U17. 개발 도구: DevHarness `script=`(진짜 터치 몰기), `trace=1`, `load_save=`/`load_ago=`/`save_at=`, `dump labels`(화면 밖 글자 찾기). 견본 상태는 실제 시계도 함께 흘려 다시 만들었다(late = 40일, 다섯 계층·5층·연구 8).

### 폴리시에서 정한 것 (2026-11-11, 브랜치 `uip` — 승인 필요)
P1. **오프닝에 빗물받이를 둘** 놓게 했다(두 번째 단계 "하나 더 …", `match.min: 2`). 이유: 판잣집 8채 정원 32명 × 물 1 = 32(+텃밭 3)인데 빗물받이 하나는 20 — 하나만 놓으면 16명에서 멈추고 "주민을 잃고 있다"가 떠서 첫 승급(만실 필요)에 영영 못 간다. 텃밭은 하나 그대로(10/일 ≈ 32명 × 0.3).
P2. **첫 승급은 위 알림 줄("승급할 수 있는 주거 n채", 초록)로 알린다** — 그때 목표 카드는 아직 '수령'(목표 4)이라 목표가 승급을 말하지 않는다. 알림 줄을 누르면 일괄 승급 창, 자재가 모자라면 "n채만 승급"(시작 재고 12로 3채). 목표 순서(goals.json)는 SIM 소유라 건드리지 않았다.
P3. **현수막 → 작은 소식 카드**: 상단 띠 바로 아래 왼쪽(레일 앞까지), 하나씩, 2초(최대 3초), 카드를 누르면 넘김. 카드 밖 터치는 그대로 도시·버튼으로 간다. 기다리는 카드가 셋을 넘으면 넷째부터 "소식 n가지" 한 장으로 합친다. 토스트는 카드 아래로 비킨다.
P4. **목표 달성 카드에 같은 순간 열린 건물을 싣는다**(0.3초 안에 온 unlock 을 모아 "보상 ₩300\n새로 지을 수 있다: 제면소 · 초 공방 …"). 목표 없이 온 해금만 따로 한 장. 등급(milestone)은 드물어서 제 카드(3초). 긴 제목은 한 단계 작은 글자.
P5. **핀치 줌**: 마지막 단계 때 손가락 거리의 1.25배/0.8배마다 한 단계, 단계 사이 최소 0.15초, 두 손가락을 댄 뒤 거리 변화가 24px 이상이고 가운데 이동의 절반보다 커야 줌으로 본다(두 손가락 팬의 떨림 무시). 줌 단계는 3개(1.25·2·4)뿐이라 빠른 핀치 한 번에 끝까지 가던 것이 한 단계씩 간다. 휠·매직마우스는 그대로.
P6. **레일 다음 층 칩 = 자물쇠 + "2F" / 막대 / "11%"**. "열림 81%"는 레일 폭 64px를 넘어서(한글 작은 글씨) 숫자만 남기고 자물쇠로 '잠긴 층'임을 보인다. 누르면 "2F는 아직 잠겼다 — 열림까지 n%. …".
P7. **탐험 보장 덤**: 질의 `bonus_text`에서 확률 표시가 없는 "이름 a~b"(시뮬은 chance 1.0 만 이 꼴로 쓴다)를 보장 줄로 올린다("+ 설비 부품 1 보장", 금색 톱니). 확률 덤만 "덤(운): …". 지도에서 부품을 꼭 주는 곳은 표지 왼쪽 위 금색 톱니 + 왼쪽 아래 범례, 머리의 '부품' 칩을 누르면 그곳들이 맥박. (문장 파싱이다 — 구조화된 `bonus:[{good,name,min,max,chance}]`를 SIM에 요청, INTEG (b) 11.)
P8. **지도 이름표 자리**: 아래 → 위 → 오른쪽 → 왼쪽 → 더 아래/위 중 앞서 놓은 이름표·표지·성채·범례와 안 겹치는 첫 자리. 거리 띠 이름은 원의 왼쪽(큰길과 만나는 곳)부터 빈 자리.
P9. **승급 창의 모자람 줄**: 고른 자재가 모자라면 "목재 20 모자람 — 남은 5채까지 하려면 …(지금 12 / 32). 가장 빠른 곳: 철거된 가구 골목 · 5분" + [탐험 — 목재 주는 곳](지도가 그 자재를 비춘 채 열린다). 부품이 막으면 같은 줄로 부품. "n채만"이 될 때는 빨간 '모자란다' 줄을 숨긴다. 시뮬 문장의 "목재이(가)"는 받침으로 고쳐 보인다.

## 4. 계약 빈틈 (디렉터 → 시뮬)
(통합 후: G1~G12 전부 닫힘 — G5 진짜 질의 확인, G6 보상 배열 `[{good,name,n}]` 처리, G12 `inspect:<bid>`까지 연결. 남은 요청은 `docs/INTEG_NOTES.md` (b).)

| # | 무엇 | 지금 UI | 제안 |
|---|---|---|---|
| G1 | `offline_summary` 가 늘 빈 Dictionary(널 아님) | real_hours>0 또는 lines 가 있을 때만 창 | 없으면 `null` |
| G2 | floor_progress 에 설명 문장 없음 | UI가 "nF가 열리려면 …칸" 문장을 만든다 | `floor_progress.text` |
| G3 | can("build"/"zone") 이유에 코드 없음 | 자리 스캔에서 "모자란다"가 든 이유를 "자리는 됨"으로 본다(문장 의존) | `code: "occupied"/"money"/"goods"/"locked"/"sky"` |
| G4 | 철거 미리보기 없음 | info 의 주민 수·자재 이름으로 확인 문구를 짠다 | `query("demolish_preview",{pos})` → lines |
| G5 | expeditions·research·policies 가 빈 모양(B 파트) | 빈 상태 화면 + 견본으로 확인 | B 파트 |
| G6 | expedition_claim 결과의 보상 모양 미정 | `result.rewards` 또는 `expedition_claimed.rewards` {good:n} | 하나로 확정 |
| G7 | 수요 원인 "재고 없음"의 jump 가 경제 상품 행뿐 | 행으로 감 | 그 상품을 만드는 시설·계약 제안 목록(jump alt) |
| G8 | info(시설)에 size 없음 | build_menu 에서 찾는다 | `info.size`, `info.footprint` |
| G9 | finance.today 에 net 없음 | "—" | `today.net` |
| G10 | build_menu 의 주거 항목 sign 빈칸 | "住" | 데이터에 sign |
| G11 | 튜토리얼 진행을 시뮬에 저장할 곳 없음 | user://ui_settings.cfg(도시 씨앗별) | `flags.tutorial` + cmd |
| G12 | hud.alerts 의 jump screen "upgrade" 는 화면이 아님 | 일괄 승급 창으로 해석 | 문서화 |

## 5. 약한 곳
- 실기기 터치·멀티터치 미검증(데스크톱 마우스·헤드리스로만). 360×800은 논리 540×1200을 0.67배로 그려 작은 글자가 살짝 뭉개진다.
- (통합) 탐험·연구·정책·목표·미접속은 진짜 질의로 다시 봤다. 실기기 터치는 여전히 미검증(웹 Chromium 터치 흉내까지).
- 배치 자리 스캔은 can() 144번 — 느린 기기에서 층 바꿀 때 한 박자 걸릴 수 있다.
- 점령된 자리 위 빨간 고스트가 밝은 낮에 잘 안 보인다(뷰 색). 막대의 이유 문장이 주 신호.
- 들여다보기 시트(50%)를 열면 도시가 위 띠로 밀려 작게 보인다. 고른 집은 select 로 표시되나 줌이 낮으면 찾기 어렵다(뷰 focus_on 이 있으면 좋겠다).
- (폴리시) 소식 카드는 하나씩·2초·요약 합침. 토스트는 카드 아래로 비킨다. 그래도 등급 + 목표가 같은 순간이면 두 장이 이어진다(4~5초, 화면 가운데는 비어 있다).
- 소리 없음.
