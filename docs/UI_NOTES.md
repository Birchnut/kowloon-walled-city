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

## 4. 계약 빈틈 (디렉터 → 시뮬)
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
- 탐험·연구·정책·목표 문구·미접속 요약은 B 파트 데이터가 오면 실제 모양으로 다시 봐야 한다(지금은 계약 모양 견본).
- 배치 자리 스캔은 can() 144번 — 느린 기기에서 층 바꿀 때 한 박자 걸릴 수 있다.
- 점령된 자리 위 빨간 고스트가 밝은 낮에 잘 안 보인다(뷰 색). 막대의 이유 문장이 주 신호.
- 들여다보기 시트(50%)를 열면 도시가 위 띠로 밀려 작게 보인다. 고른 집은 select 로 표시되나 줌이 낮으면 찾기 어렵다(뷰 focus_on 이 있으면 좋겠다).
- 토스트와 현수막이 동시에 많으면 겹친다(묶기 없음).
- 소리 없음.
