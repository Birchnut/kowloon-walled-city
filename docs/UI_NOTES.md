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
