# UI 노트 (v0.2, 브랜치 `ui`)

플레이어가 만지는 층 전체. 가짜 시뮬·가짜 뷰로 전 화면을 돌려 봤고, 진짜 시뮬·진짜 뷰와는 아직 안 붙여 봤다.
스크린샷: `docs/shots/ui_0…5_*.png`.

## 0. 돌려 보기

```
tools/shot.sh res://ui/dev/UISandbox.tscn out 30 540x960 city=mid scn=plant     # 무비 프레임(항상 540x960)
godot --path godot res://ui/dev/UISandbox.tscn -- nosave city=mid scn=policy png=/abs/a.png   # 실제 창 크기 한 장
tools/shot.sh res://ui/dev/Gallery.tscn out 8                                   # 컴포넌트 견본
```
`city=empty|mid|tall`, `tutorial=1`, `offline=1`, `scn=`(UISandbox.gd 의 `_scn_*` : hud plant plant_place plant_bad zone demolish policy policy_change cards cards_choose cards_empty inspect record settings collect collect_all cut toasts unlock identity power cards_ready confirm_new tutorial_play tutorial_to).
`scenes/Main.tscn` = `ui/Main.gd`: `res://view/CityView.tscn` 이 있으면 그것, 없으면 MockView + `ui/UIRoot.tscn`. 스캐폴드 시뮬(질의 대부분 null)로도 죽지 않고 빈 상태를 보여 준다(확인함).

## 1. 컴포넌트 (`godot/ui/components/`)

| 이름 | 하는 일 |
|---|---|
| `UI` (ui/UI.gd) | 정적 도우미: 테마 색·폰트(`UI.col/font`), 아이콘, 라벨·상자 만들기, 숫자·시계 표기, 조사, **`UI.keep()`**(한국어 줄바꿈) |
| `Q` (ui/Q.gd) | Game.query/can 과 뷰 호출의 안전망(null·없는 메서드에 안 죽음) |
| `Panel9` | 9-슬라이스 판. `variant` = 테마의 `Panel<variant>` |
| `PixelButton` | 버튼. 누르면 1px 내려감, 아이콘+글자 가로/세로, 배지(+통통), 길게 누르기 |
| `Chip` / `Segmented` | 토글 칩 / 하나만 켜지는 칩 줄(잠김 옵션, 세로 칩) |
| `BottomSheet` | 아래에서 올라오는 판 + 걸친 제목 간판 + 닫기 꼬리표. 바깥 터치는 도시로 통과 |
| `DragScroll` | 가로/세로 끌기 스크롤(끌면 안쪽 버튼 눌림 취소, 관성) |
| `Meter` | 얇은 지표 막대 |
| `IconLabel` | 아이콘+숫자, 숫자 굴리기, 변화량 번쩍 |
| `SignTile` | 세로 간판 딱지(한자 1~3자) |
| `ToastLayer` / `Banner` | 토스트 줄 / 가로 현수막(대기열) |
| `CardView` / `ChoiceButton` | 결재 서류 한 장(도장 연출) / 두 줄짜리 넓은 버튼 |
| `DialogBox` | 대화 상자(타자기, 탭 진행, 건너뛰기) + 힌트 띠 |
| `Bubble` | 수금 말풍선(차오름·통통·떨림) |
| overlays: `Modal` `Highlight` `RainOverlay` | 확인/알림 창, 튜토리얼 꺾쇠 강조, 오프닝 비·표석 |

조립: `ui/UIRoot.gd`(도구 상태기계·이벤트 라우팅·명령 창구), `ui/hud/*`(TopStrip, TimeDial, FloorRail, VerbBar, BubbleLayer), `ui/sheets/*`(Plant, Zone, Policy, Cards, Inspect, Record), `ui/tutorial/Tutorial.gd`, `ui/dev/*`(MockSim, MockView, UISandbox, Gallery, build_theme).

## 2. 다시 꾸미는 법

- **색·폰트·판 모양** = `assets/themes/main_theme.tres` 하나. 팔레트는 `Kowloon` 타입의 color(ink0~3, paper, red, gold, jade …), 폰트는 같은 타입의 font(body/bold/small/head). 컴포넌트는 색을 하드코딩하지 않고 여기서 읽는다.
- 테마를 통째로 다시 만들기: `ui/dev/build_theme.gd` 의 PAL·치수를 고치고 `godot --headless --path godot -s res://ui/dev/build_theme.gd`.
- **픽셀 그림(9-슬라이스·아이콘·말풍선)** = `assets/ui/src/gen_ui_assets.py`(팔레트 + ASCII 도트). 돌리면 `assets/ui/nine/*.png`, `icons.png`, `ui/IconIndex.gd` 가 다시 나온다 → `godot --headless --import`.
- 동사 추가/삭제: `VerbBar.VERBS`. 긋기 붓: `ZoneBar.BRUSHES`. 배속: `RecordSheet.SPEEDS`.
- 오프닝 대본: `data/tutorial.json`(단계 종류·대상·자리표시자 설명이 파일 머리에 있음).

## 3. 화면별 데이터 출처

| 화면 | 읽는 것 | 보내는 것 |
|---|---|---|
| 상단 띠 | `query("hud")` 0.25초 폴링, `Game.time_of_day()` | — (탭 → 기록) |
| 우측 레일 | hud.floors → 없으면 `view.get_max_floor()` → 없으면 설정 max_floors | `view.set_floor_cut / rotate_view / zoom_step` |
| 말풍선 | `query("collect_points")` 0.5초 + `collect_ready/collected`, 위치 `view.project`, `view_changed` | `cmd("collect",{point})` / `cmd("collect")` |
| 심기 | `query("facilities")`, `query("plant_spots",{facility})`, `can("plant")` | `view.show_spots/show_ghost/clear_overlay`, `cmd("plant")` |
| 긋기 | `view.pick`, `query("cell_info")`, `can("demolish")` | `view.show_zones`, `cmd("zone")`, `cmd("demolish")` |
| 허가 | `query("policies")` | `cmd("policy")` |
| 결재 | `query("cards")`, `cards_ready` | `cmd("card",{uid,choice})` |
| 들여다보기 | `query("cell_info",{pos})` (+actions) | actions 의 cmd |
| 기록 | hud(title, epithet, tags), `query("stats")`(있으면), `query("log",{n:50})` | `Game.speed/paused`, `view.set_time_override`, `delete_save+new_game`, `cmd("debug")` |
| 토스트/현수막 | `log` `unlock` `identity_changed` `power_changed` | — |
| 자리 비운 사이 | `query("offline_summary")`(시작·state_replaced 때 1회) | — |
| 튜토리얼 | `data/tutorial.json`, `Game.event`, UIRoot.cmd 성공 | `Game.paused/speed`, 뷰 힌트 |

## 4. 내가 정한 것 (승인 필요)

1. **UI 1픽셀 = 논리 2px.** Galmuri11@24(본문) / Galmuri9@20(작은 글자) / NeoDunggeunmo@32(간판·제목, 한자는 Galmuri11-Bold 대체). 이유: 540폭에서 12px 글자는 못 읽는다. 전부 정수배.
2. **Galmuri7·Galmuri14·Fusion Pixel 은 안 넣었다.** 이유: 각 3.7~7.3MB, 웹 빌드가 무거워진다. NeoDunggeunmo 는 0.65MB.
3. **Kenney 팩 안 씀. 9-슬라이스·아이콘 전부 자작(CC0).** 이유: 스톡 티가 나지 않게, 색을 스크립트 한 곳에서 바꾸게.
4. **시설 아이콘 = 세로 간판 딱지**(간판 한자, 없으면 이름 첫 글자). 이유: 콘텐츠를 추가해도 아이콘을 그릴 필요가 없다(규칙 4와 같은 방향).
5. **모티프**: 켜진 칩 = 상아 마작패, 결재 = 누런 서류 + 붉은 도장(准), 제목 = 판 위로 걸친 옻칠 간판, 빈 결재함 = 「閑」.
6. **시트는 화면을 덮지 않고 스크림도 없다**(위쪽 도시는 계속 만질 수 있음). 스크림은 확인 창·자리 비운 사이에만.
7. **허가/결재/기록 시트가 열린 채 도시를 누르면 시트가 닫힌다.** 이유: 모바일에서 "바깥 탭 = 닫기"가 자연스럽다.
8. **레일**: 층 ≤ 3 이면 층마다 버튼, 그 이상은 ▲ nF ▼ (nF 를 끌면 훑기). 줌 ± 는 화면 높이 ≥ 900 일 때만. 레일은 상단 띠 바로 아래(엄지 자리 비움).
9. **`set_floor_cut(n)` 의 n 을 z 인덱스(0=지상)로 해석**하고 화면엔 (n+1)F 로 적는다.
10. **긋기: 끄는 동안은 도시가 안 움직인다**(UI가 터치를 받는다). 대신 "이동" 토글을 뒀다. 철거 붓은 탭만(끌기 없음).
11. **철거는 두 군데**: 긋기의 철거 칩, 들여다보기 시트의 actions. 둘 다 잃는 것을 보여 주고 확인받는다.
12. **허가**: 칩 한 줄 + 고른 선택지의 결과 한 줄 + "선택지 설명" 펼침(고르기 전에 전부 읽기). 이유: 옵션 4개에 설명까지 넣으면 칩이 안 읽힌다.
13. **말풍선 판정의 대체값**: 질의에 `ready/skimming` 이 없으면 amount ≥ 1 = 준비, ratio ≥ 1 = 떼이는 중. amount < 1 인 수금함은 말풍선을 안 띄운다. 상단 띠·하단 바에 걸친 말풍선은 숨긴다.
14. **"모두 거두기"는 하단 중앙**(엄지), 준비된 게 3개 이상일 때.
15. **동전이 날아가는 0.6초 동안 돈 숫자를 붙잡는다**(도착할 때 오르게).
16. **`log` 이벤트는 전부 토스트**(최대 4줄, 3초). tone=debug 는 debug.enabled 일 때만. tone 매핑은 `UI.tone_col`.
17. **첫 전기**: UI 알파를 0.08 로 4.2초 내렸다가 되돌리고 현수막. 그동안 도구는 닫는다.
18. **튜토리얼 진행 저장**: 시뮬이 `query("tutorial")` 을 Dictionary 로 주면 그쪽(`cmd("tutorial",{step,done})`), 아니면 `user://ui_settings.cfg` 에 도시 씨앗(`Game.state.rng_seed` 읽기만)별로. 기록이 없는데 2일차 이상이면 본 것으로 친다. nosave 면 파일을 안 건드린다.
19. **튜토리얼이 만지는 것**: 내레이션 동안 `Game.paused=true`, 기다리는 단계에서 `Game.speed` ×4, 감상 시간 0.23(새벽), 아직 안 가르친 동사 잠금. 끝·건너뛰기 때 전부 되돌린다.
20. **오프닝의 비와 표석(九龍城寨)은 UI 층에서 그린다.** 이유: 뷰에 날씨가 없다(MVP 제외).
21. **화자는 "춘자 이모 / 따라온 사람"**(GDD 10.3). 대본 문장은 전부 내가 썼다 → 톤 검수 필요.
22. **기다림의 timeout**: 판잣집 25초(지나면 "판잣집이 섰다" 한 줄만 건너뜀), 자릿세 40초(지나면 거두기 실습을 건너뜀), 심기 180초, 거두기 60초.
23. **한국어 줄바꿈은 띄어쓰기에서만**(글자 사이에 U+2060 삽입). 이유: 기본 줄바꿈은 "아니|다." 처럼 낱말을 자른다.
24. **ScrollContainer 대신 자작 DragScroll.** 이유: 스크롤하다 버튼이 눌리는 것을 확실히 막고, 데스크톱·웹에서 마우스로도 끌리게.
25. **값 숫자를 빨갛게**: 재고 < 값일 때(표시만, 판정은 `can`). 규칙 3의 경계에 있어 적어 둔다.
26. **해금 현수막의 이름**: 이벤트에 name 이 없으면 시설 질의 → 콘텐츠 표의 name/desc/sign 을 읽는다(이름표 읽기, 규칙 계산 아님).
27. **기록 시트 = 일지/설정 두 쪽**, 상단 띠 전체가 기록 버튼. 설정에 "오프닝 다시 보기"를 넣었다.
28. **빈 상태·힌트·확인 문구 전부**(예: "별일 없었다. 그게 제일 수상하다.") 내가 썼다 → 검수 필요.
29. **미터 눈금 25/50/75, 토스트 위치 좌상단, 현수막 위치 화면 20% 높이.**

## 5. 계약에서 빠졌거나 애매한 것 (디렉터에게)

| # | 무엇 | 지금 UI의 임시 처리 | 제안 |
|---|---|---|---|
| A | 지금 최고 층 수 | hud.floors → view.get_max_floor() → 설정 max_floors | `hud.floors` |
| B | 명물 태그 | hud.tags(있으면) | `hud.tags` |
| C | 수금 "준비/떼이는 중" 기준 | ready/skimming 필드, 없으면 amount≥1 / ratio≥1 | collect_points 에 `ready`, `skimming` |
| D | 수금 보너스 발견의 전달 경로 | cmd 결과 `bonus` 또는 collected.bonus 를 토스트 | 한 곳으로 확정 |
| E | 시설 간판 글자 | 질의의 `sign`, 없으면 이름 첫 글자 | facilities 에 `sign` |
| F | 카드의 올린 사람 | speaker 가 String 이든 {name, role} 이든 받음 | 모양 확정 + `role` |
| G | cmd("card") 결과 문장 | `result` 가 있고 log 가 안 왔으면 토스트 | 확정 |
| H | cell_info.actions 모양 | `{label, cmd, args, confirm?, danger?, enabled?, reason?}` 로 가정 | 확정 |
| I | pick() 이 빈 땅·부지 밖에서 주는 값 | col 로 plant_spots 와 맞춰 봄, hit=false 면 무시 | hit/pos/above 의미 명시 |
| J | set_floor_cut(n) 의 n | z 인덱스(0=지상)로 가정 | 명시 |
| K | 긋기 끌기 | UI가 터치를 가로챔 → 긋기 중 핀치줌·팬 불가 | `signal cell_dragged(info)` + `set_pan_enabled(bool)` |
| L | unlock 페이로드 | id 만 → 이름을 UI가 찾아봄 | `{id, kind, name, desc}` |
| M | 통계 | `query("stats")` 가 있으면 [{label,value}] | 질의 추가 |
| N | 튜토리얼 저장 | 4-18 | `query("tutorial")` / `cmd("tutorial")` 또는 flags |
| O | 첫 앵커 무료 + 시작 3종 제한 | UI는 목록만 3개로 줄임. 값은 시뮬이 0으로 줘야 함 | 시뮬 규칙 |
| P | 카메라 힌트 | `view.focus_on(pos)` 가 있으면 부름 | API 추가 여부 |
| Q | log 의 tone 목록 | good/bad/warn/gold/debug/… 를 느슨하게 매핑 | 목록 확정 |
| R | 정책 옵션의 잠김 이유 | `lock_hint`, 없으면 can("policy").reason | 필드 확정 |
| S | 뷰 등록 알림 | 매 프레임 `Game.view` 비교 | `signal view_registered` |
| T | tools/shot.sh | 무비 기록이 항상 540x960 이라 다른 화면비를 못 봄 → UISandbox 의 `png=` 로 우회 | 스크립트에 창 크기 캡처 추가 |

## 6. 약한 곳

- 진짜 CityView·진짜 Sim 과 붙여 본 적이 없다. project()/pick() 의 좌표계(뷰포트 기준이라고 가정), 이벤트 순서가 다르면 손봐야 한다.
- 실기기 터치 미검증. 멀티터치, 안전 영역(`UI.safe_insets` 는 추정 계산), 웹 모바일.
- 긋기 중 핀치줌 불가(5-K).
- 말풍선끼리, 말풍선과 건물의 겹침 처리가 없다. 수금함이 많아지면 붐빈다.
- 시뮬이 log 를 많이 내면 토스트가 시끄럽다(묶기·등급 없음).
- 튜토리얼 중간 재개(앱을 껐다 켰을 때)는 가볍게만 확인했다. 스캐폴드 시뮬에서는 심기가 안 되므로 180초를 기다리거나 건너뛰어야 한다.
- 정수배가 아닌 창(예: 폭 360)에서는 글자 가장자리가 조금 뭉개진다. 폭 1080 기기는 정확히 2배.
- DragScroll 에 고무줄 효과·스냅이 없다. 감상 모드 슬라이더가 세로 스크롤 안에 있다.
- 소리 없음(이번 버전 범위 밖).
