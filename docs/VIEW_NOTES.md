# VIEW 노트 — 3D 픽셀 렌더러 (v0.3, Anno식 재편 대응)

> 뷰 층(`godot/view/**`) 담당이 쓴 문서. 계약은 `ARCHITECTURE.md`. 뷰는 규칙을 모르고 상태를 바꾸지 않는다.
> 읽는 필드는 `cells`, `supports`, `buildings`, `floors_unlocked`, `day`, `hour`(+ 있으면 `rng_seed`, `waiting`, 전기 플래그)뿐이다.
> v0.2 노트의 카메라 수학·조명 설명(§1)은 그대로 유효해서 줄여 옮겼다.

## 0. v3에서 바뀐 것 (한 장 요약)

| 영역 | v0.2(분재) | v0.3(지금) |
|---|---|---|
| 셀 | housing/business/facility + owner·households | `house`/`facility`/`site` + `bid`·`tier`·`material`·`origin`·`size`·`scaffold` |
| 주거 외관 | 자재 5종 무작위 | **계층 × 자재 계열**(visuals.json > `houses`, 13조합). 같은 외관끼리 이어지고 다르면 이음매 |
| 시설 | 업종 레시피 | GDD §4.1의 시설 전부(간판 글자 포함) + 소품 목록 + **2×2는 한 덩어리·큰 간판 하나** |
| 골조 | 없음 | `supports`의 빈 칸 = 콘크리트 기둥 + 철 보 + 철 가새(가끔 대나무). 속이 보인다 |
| 불·전기 | 정점에 박음, 전역 `power_level` | **셀 상태 텍스처**(칸마다 불 켜진 비율·전기·가동). `building_changed`는 메시를 다시 짓지 않는다 |
| 표시 | 없음 | 수요 부족 "!", 승급 가능 "▲"(통통), 멈춘 시설 "z" (`view/Markers.gd`) |
| 오버레이 | 구획(열)·심을 자리·고스트 1칸 | 층 격자·고스트(여러 칸+생길 골조)·칸 표시 4종·렌즈 3종·칠하기 끌기 |
| 사람 | 가구 유형 색 | 계층 색(T1 바랜 색 → T5 짙은 정장·흰 옷) |
| FakeCity | day1~day30 | `early` `mid` `late_wood` `late_metal` `late_concrete` `late_mixed` + 표본 `matrix`, `matrix_<family>` |

## 1. 파이프라인

```
CityState ──▶ CityMesher(층별 ArrayMesh + 골조 + 파생 구조물) ──▶ SubViewport(저해상도 3D, 직교)
   │             │ 정점 UV2.x = 칸 번호 + 난수                     │ city.gdshader: 3단 톤 + 높이맵 그림자 + 복셀 빛
   │             ├ lights[] ─▶ LightGrid / emitters[] ─▶ Fx·People │ + cellstate(불·전기·가동) + lenstex(렌즈 색)
   └ buildings ──▶ CityView._update_cell_tex() ──────────────────┘
                 └▶ Markers(빌보드 MultiMesh, 깊이 무시)
```

| 파일 | 하는 일 |
|---|---|
| `view/CityView.gd` | Control. 카메라·입력·공개 API·이벤트·셀 상태/렌즈 텍스처·오버레이 |
| `view/CityMesher.gd` | 셀 → 메시. 주거(계층×자재)·시설(1×1, 2×2)·골조·공사장·층 컷 |
| `view/Markers.gd` + `shaders/marker.gdshader` | 건물 표시 아이콘 |
| `view/PixelAtlas.gd` | 텍스처를 코드로 그림. v3에서 벽 무늬 9종(boards battens panel clad curtain render mosaic smooth formed)·창 7종 추가 |
| `view/People.gd` `view/Fx.gd` `view/LightGrid.gd` `view/SkyTex.gd` | 그대로(사람 색만 계층으로) |
| `view/Sandbox.gd` | 뷰만 띄우는 씬 — 인자는 §6 |
| `tools/fake_city.gd` | 시뮬 없이 계약 모양 상태 생성 |
| `data/art/render.json` / `visuals.json` | 렌더 수치 / 외형 매핑 |

카메라: 직교, 방위 45°+90°k, 고도 30°, 칸 반폭 8px, 한 층 8px(`floor_h = 0.8165`), 내부 해상도 ≈ 폭 270px을 정수배 확대. 실시간 광원 0개, 그림자는 높이맵 DDA.

## 2. 콘텐츠 추가법 (뷰 코드 수정 없음)

### 2.1 시설 레시피 — `visuals.json > types.<id>`
덮어쓰는 순서: `_default_facility` ← `_cat_<buildings.json의 cat>`(있으면) ← `<id>`. 모르는 id는 기본 상자(미장 벽 + 가게창 + 칠한 간판)로 나온다.

| 키 | 뜻 |
|---|---|
| `form` | `box`(기본) · `open`(텃밭 등, `plot`: crops/flowers/rain/junk/tanks/well) · `shed`(좌판·발전기, `plot`: stall/generator) · `tank` · `shrine` |
| `wall` | 벽 자재 id(`materials`) |
| `window` | `shop` `shutter` `slit` `wide` `std` `small` `full` `none` |
| `sign` | 간판 글자. **시뮬의 `buildings.json`에 `sign`이 있으면 그것이 우선** |
| `sign_style` / `sign_color` | `neon`·`paint`·`lantern`·`none` / 네온 이름 또는 `#색` |
| `props` | 소품 목록: `stack`(굴뚝+연기) `tanks` `pipes` `mast`(탐험 무전탑) `racks`(말리는 시렁) `vats` `jars` `bolts`(옷감) `crates` `transformer` `lanterns` `antennas` `dish` `planters`. 지붕 소품은 위가 비었을 때만, 앞 소품은 디딜 바닥이 있을 때만 |
| `big` | 2×2 형태: `market`(긴 차양+좌판) `plant`(굴뚝 둘) `works` `bath` `casino`(네온 테) `hall`(회관: 겹처마·붉은 기둥) `block` |
| `power` | `true`면 전기 시설(도시 전력 판정·전기 물결의 중심) |
| `fx` `glow` `awning` `busy` `interior` `floor` | 연기·김·불꽃 / 가게 앞 빛 / 차양 색 / 사람의 밤 활동 / 층 컷 가구·바닥 |

### 2.2 주거 외관 — `visuals.json > houses.<family>_<tier>`
T1은 언제나 `common_1`. 없는 조합은 같은 자재의 가까운 계층 → `common_1`로 떨어진다. 새 자재 계열(예: `brick`)은 `brick_2`..`brick_5`만 넣으면 된다(셀의 `material`이 그 이름이면 바로 쓰인다).

| 키 | 뜻 |
|---|---|
| `wall` / `roof` | 벽·지붕 자재 id |
| `win` / `frames` / `win_p` | 창 모양 후보(`small std twin wide band full deep lattice full_warm louvre none`) / 창틀 색 키 / 창이 있을 확률. T2 이상은 **같은 건물·같은 층의 창이 같은 모양**(이어진 건물로 읽히게) |
| `balcony` / `balcony_p` | `cage`(칸마다) · `gallery` `slab` `deck` `glass` `cantilever`(같은 면·같은 층 줄 전체가 함께 → 이어진 발코니) |
| `bay_p` `bay_mats` | 반 칸 증축(T1·T2) |
| `clutter` `awning_p` `awning_c` `equip_p` `plants_p` | 잡동사니(빨래·에어컨·배관)·차양·외부 설비·화분 |
| `frame_posts` `band` `band_c` | 철제 보강 프레임 / 층 띠(바닥판이 보임) |
| `eave` `parapet` | 처마(`wood` `wood_deep` `tile` `metal` `slab`) / 난간벽 높이(텍셀 단위) — 같은 건물의 이어진 지붕에는 안 생긴다 |
| `roofprops` | 꼭대기 소품 가중치: `junk laundry antenna shack tank plants garden pergola penthouse solar equipment canopy` |
| `seam` | 다른 외관과 만나는 모서리의 줄눈 색 |

### 2.3 자재(벽 무늬) — `visuals.json > materials.<id>`
`ramp`(4톤) `pattern` `accent` `roof` `frames` `cage`. 새 **무늬**는 `PixelAtlas._wall()`에 분기 하나(코드). 새 자재 색은 데이터만.

## 3. CityView API (ARCHITECTURE의 이름 그대로)

| 호출 | 동작 |
|---|---|
| `pick(screen)` | 격자 DDA. `{hit, pos, col, above, face, adjacent, in_grid}` |
| `pick_floor(screen, z)` | z층 수평면과 만나는 칸(비어 있어도). `{ok, pos, in_grid, world}` — ok = 부지 안 |
| `project(pos)` / `project_world(v)` | 셀 윗면 중심 / 월드 점 → 이 Control 좌표 |
| `show_floor_grid(z, on)` | 켜면 `set_floor_cut(z)`로 그 층을 작업 평면으로(위는 걷고 아래는 덩어리). 빈 칸 = 밝은 테두리, 찬 칸 = 붉은 칠, 잠긴 층 = 회색. 끄면 이전 층 컷으로 |
| `show_ghost(cells, ok, supports=[])` | 반투명 초록/빨강 덩어리 + 생길 골조(흰 틀). 옛 `show_ghost(pos, id, ok)`도 받는다 |
| `show_cells(cells, style)` | `range`(컷이 없으면 기둥 꼭대기에 칠) · `valid` · `select`(테두리) · `warn`. 같은 style은 바꿔 끼움, 빈 배열은 그 style 지움 |
| `clear_overlay()` | 고스트·칸 표시를 지운다(격자·렌즈는 그대로) |
| `set_lens(name)` | `""` `needs`(괜찮음은 옅은 초록, 주의 주황, 부족 빨강) `tier` `happiness`. 주거 외 나머지는 회색으로 가라앉는다. 셰이더 텍스처만 바꾼다(재메시 없음) |
| `set_drag_paint(on)` | 켜면 한 손가락 누름/끌기가 팬이 아니라 `cell_dragged(info)` — `pick_floor(작업 층)` 결과 + `first`. **칸이 바뀔 때만** 낸다. 이 모드에서 누름은 탭(`cell_tapped`)을 내지 않는다. 두 손가락은 팬·줌·회전 |
| `work_floor()` | 칠하기에 쓰는 층(격자 층 → 없으면 층 컷 → 0) |
| `set_floor_cut` `rotate_view` `zoom_step`/`set_zoom` `set_bottom_inset` `get_max_floor` `set_time_override` | 그대로 |
| 시그널 | `cell_tapped(info)` `cell_dragged(info)` `view_changed()` |
| v2 호환 | `show_spots(cells)` = `show_cells(cells, "valid")`, `show_zones()`는 아무것도 안 함 |

### 이벤트
| 이벤트 | 뷰가 하는 일 |
|---|---|
| `cell_changed{pos}` `support_changed{pos}` | 그 층과 위아래 층만 다시 짓는다(2×2면 네 칸). 공사장이 끝났으면 비계가 떨어지고 먼지 |
| `building_changed{bid}` | 외형 서명(주거: 계층·자재·비계·빈집 여부 / 시설: 가동)이 같으면 **셀 상태 텍스처·표시만** 갱신(≈2–3ms). 다르면 그 층만 재메시 |
| `house_upgraded{bid,…}` | 비계 낙하 + 먼지 + 그 층 재메시(새 외관) |
| `floor_unlocked{z}` | z층 평면 테두리가 빛나고 가운데서 빛 고리가 퍼진다(2.6초) |
| `power_changed{on}` | 꺼짐→켜짐이면 전기 시설에서 퍼지는 점등 물결(전기 판정은 셰이더라 재메시 없음) |
| `expedition_done` `expedition_claimed` | **연출 미구현**(호출 자리만: `people.expedition()`이 있으면 부른다) |

### 전기 판정 — 한 곳
`CityMesher.electric(cell)`: 주거는 `tier ≥ 3` 또는 도시 전력, 시설은 도시 전력. 도시 전력 `CityMesher.city_power(state)`: state에 `power_on` → `flags.power_on` → `power_level > 0` 순으로 찾고, 없으면 **가동 중인 `power: true` 시설이 있는가**. 시뮬의 최종 필드가 생기면 `city_power()`만 고치면 된다. 전기가 없는 창은 밤에 드문 촛불(T1의 작은 촛불)만 켜진다.

## 4. 내가 임의로 정한 것 (승인 요청)

1. **시설 id를 내가 지었다**(시뮬의 `buildings.json`이 아직 없음): `stall market_basic market_general market_luxury rain_catcher water_tower water_main water_works generator grid_power power_plant cogen_plant rooftop_farm/garden roof_garden noodle_works fishball_works moonshine candle_shop sewing_shop soap_shop tailor radio_shop assembly fake_shop shrine teahouse mahjong dentist bathhouse study_hall karaoke gambling_den call_centre casino fireworks scrapyard warehouse trade_post expedition_post landmark_hall`. 이유: 레시피를 미리 채워 두려고. 시뮬 id가 다르면 `visuals.json`의 키 이름만 바꾸면 된다(또는 시뮬이 이 이름을 쓰면 끝). 선택지 — (1) 시뮬이 이 이름을 따른다 (2) 뷰가 시뮬 이름으로 바꾼다.
2. **GDD에 간판 글자가 없는 2×2 시설에 글자를 붙였다**: 정수장 `淨水`, 발전소 `電廠`, 열병합 `熱電`. 빗물받이·텃밭·옥상 정원은 간판 없음.
3. **세 자재 계열의 색 축**: 목재 = 따뜻한 주황·갈색(T4·T5는 옻칠한 짙은 나무 + 초록 기와 처마 + 정원), 철제 = 차가운 청회색(T5 유리 커튼월), 콘크리트 = 중성 크림·분홍 타일(T5 송판 노출 콘크리트 + 내민 판 + 정원). 이유: 폰 크기에서 색상으로 먼저 갈리고, 계층은 모양(창 크기·발코니·지붕)으로 읽히게. T1은 셋 다 같은 판자·양철 조각보.
4. **계층이 오를수록 잡동사니가 준다**(T1 0.95 → T5 0): 빨래·에어컨·배관·안테나·반 칸 증축. 대신 T4·T5에 정원·퍼걸러·펜트하우스·큰 창. 밀도(창·발코니·빨래)는 T3가 가장 높다.
5. **이어짐 규칙**: 같은 `<family>_<tier>`끼리는 벽·지붕 난간·처마·발코니가 이어지고 창 모양이 같다. 다르면 세로 줄눈(+홈통), 아래층이 다르면 수평 띠. 시설은 같은 bid끼리만 이어진다.
6. **골조 = 콘크리트 기둥 + 짙은 철 보 + 철 가새(4면 중 1면쯤 대나무)**. 대나무 비계(공사·승급)와 한눈에 갈리게 했다. 가끔 매달린 전등. 기둥은 모서리를 공유하는 골조 칸 중 하나만 그린다.
7. **2×2 시설은 1층 높이**(네 칸이 같은 층). 큰 간판은 앞면 두 칸 가운데 가로판 하나. 회관만 지붕이 비면 겹처마 지붕을 얹는다.
8. **표시 아이콘은 깊이 무시로 맨 위에**, 다만 사방이 막힌 칸은 건너뛴다. 층 컷이면 그 층 위의 표시는 숨긴다. needs 렌즈가 켜지면 "주의"(노랑)도 보인다. 크기 7×7 텍셀. 선택지 — (1) 지금대로 (2) 기본 줌에서는 "!"만 (3) UI가 켤 때만.
9. **불 켜진 창 = 주민/정원 비율**만큼(창마다 난수로). 빈집은 판자 창(T1)·꺼진 창.
10. **작업 층 표현 = 층 컷**: `show_floor_grid(z, true)`가 `set_floor_cut(z)`를 부른다. 격자를 끄면 이전 컷으로 돌린다.
11. **칠하기 모드의 누름은 탭이 아니다**(`cell_tapped`를 내지 않음) — 한 칸 칠하기가 두 번 들어가지 않게.
12. **range 표시는 층 컷이 없으면 기둥 꼭대기에** 칠한다(칸 자체는 건물 속에 묻혀 안 보이므로).
13. **사람 옷 색 = 계층 팔레트**(`visuals.json > tier_colors`), 사는 사람 수만큼 뽑힐 확률.
14. **FakeCity의 분포 전부**(구역 나누기, 계층 섞기, 시설 위치, 빈틈·주머니 수, 부족·승급 비율)는 아트 판정용 가짜다.
15. 뷰가 쓰는 확장: `pick_floor` 결과의 `world`, `cell_dragged`의 `first`, `work_floor()`, `Markers.show_warn`.

## 5. 성능 (`perf=1`, 소프트웨어 GL)

| 도시 | 셀 | 골조 | 드로콜 | 삼각형 | 도시 정점 | 전체 재생성 | building_changed |
|---|---|---|---|---|---|---|---|
| late_mixed | 431 | 128 | 15 | 43,320 | 81,456 | 123 ms | 2.2 ms |
| late_concrete | 607 | 131 | 16 | 42,234 | 79,256 | 144 ms | 3.1 ms |

- 층당 메시 1개(골조 포함) + 지면 + 하늘 + 외곽선 + 사람 + 입자 + 표시(MultiMesh 1). 재질 1개.
- 정점이 v0.2(최대 46k)보다 많다 — 발코니·처마·정원·골조가 상자로 되어 있어서. 폰에서 문제가 되면 첫 손질은 정원 덤불·퍼걸러 살·골조 가새를 쿼드로 줄이는 것.
- Web `--export-release "Web"` 성공(pck 6.7MB). 설정 파일 변경 없음. **브라우저 실행은 확인하지 못했다.**

## 6. Sandbox 인자

`city=<preset> seed=<n> tod=<0..1> angle=<0..3> cut=<n> zoom=<0..2> pan=<x,y[,높이]> lens=<needs|tier|happiness> grid=<z> state=<JSON> hud=0 markers=0`
오버레이: `ghost=x,y,z;…` `ghostbad=1` `sup=x,y,z;…` `range=x,y,z,r` `select=x,y,z;…`
연출: `wave=<프레임>`(전기 시설을 끈 채 시작했다가 켬) `unlock=<프레임>` `upgrade=<프레임>`(비계 집 하나 승급, 카메라를 그쪽으로) `plane=1`
개발: `apitest=1`(모든 API·이벤트 PASS/FAIL — 지금 15/15) `perf=1` `list=1`(시설 위치) `dbg=<프레임>` `save_state=` `dump_atlas=` `r:<render.json 경로>=<값>`
키: Q/E 회전 · R/F 층 · 휠 줌 · T 시간 · 1-7 프리셋 · N seed · P 전기 · G 격자 · V 렌즈 · D 칠하기

## 7. 컨택트 시트 (`docs/shots/`)

`v3_01` 계층×자재 표본(T1→T5, 낮·밤) · `v3_02` late 4종 낮·밤 · `v3_03` late_mixed 4방향 · `v3_04` 골조(mid 두 각도, late_mixed ×4) · `v3_05` 격자+고스트+골조 / 범위+선택 / needs 렌즈 / tier 렌즈 · `v3_06` 층 컷(낮·밤) · `v3_07` 첫 전기 물결·승급 비계 낙하·층 열림 · `v3_08` 시설 근접(2×2·간판·밤 네온·early)

## 8. 알려진 약점

- **기본 줌(×1.25)에서 표시 아이콘이 많으면 도시를 덮는다.** FakeCity는 부족 3%·승급 5%로 낮췄지만 실제 게임에서 부족이 몰리면 시끄럽다(§4-8 선택지).
- late_wood는 정원·초록 처마 때문에 위에서 보면 초록이 많다. 목재 정체성은 벽(갈색)에서 나온다.
- 금속 T4(밝은 청회색 외장)와 콘크리트 T4(따뜻한 흰색)는 색이 가까워서 지붕 소품(태양판 vs 정원)과 창(띠창 vs 넓은 창)으로 갈린다 — 폰 크기에서 가장 약한 쌍.
- 층 컷 실내는 v0.2 그대로(짙은 단면 벽이 무겁다). 주거 실내는 계층별 가구·바닥만 바꿨다.
- 회관(landmark)은 2×2 1층이라 "최종 목표"치고 작다. 위가 비어야 겹처마가 올라간다.
- 원래 렌즈·격자 색은 반투명 표준 재질이라 낮 모래색 위에서 대비가 약하다(테두리로 보완).
- mid처럼 낮은 도시의 밤은 어둡다(T1·T2는 전기 전엔 촛불만) — 의도지만 첫 화면이 심심할 수 있다.
- 2×2 시설이 위층에 묻히면 큰 간판이 안 보인다(뷰는 배치를 못 바꾼다).
- 탐험 귀환 연출, 표시 아이콘의 탭 판정은 없다. 입력(칠하기)은 합성 이벤트로만 시험했다.
- 정점 수가 v0.2의 두 배 가까이 됐다(§5).

## 9. 그래픽 업그레이드 아이디어 (게임성 확정 뒤)

| 아이디어 | 효과 | 비용 |
|---|---|---|
| **1. 칸 반폭 8→12px(내부 해상도 ×1.5)** + 벽 타일 24×24 | 가장 큰 도약. 창살·간판·사람이 한 단계 세밀해지고 계층 차이가 창 디테일로 읽힌다 | 아틀라스 그림 다시(코드로 그리므로 2–3일), 성능 ×2.25 픽셀 |
| 2. 손으로 그린 벽·창 타일(외부 픽셀 아티스트) → 아틀라스에 PNG로 덮어쓰기 | 코드 그림의 "깔끔하지만 단조로움"이 사라진다 | 계열×계층 13조합 × 4변주 ≈ 60타일, 아트 비용 |
| 3. 계층별 실루엣(T4·T5에 셋백·옥상층·박공지붕을 셀 바깥으로 0.5칸) | 같은 높이에서도 고급 주거가 "더 넓어 보임" | 메셔 1–2일, 이웃 가림 규칙 손질 |
| 4. 밤 창의 실내 실루엣(커튼·사람 그림자) + 네온 반사 웅덩이 | 밤 화면의 생활감 | 셰이더 반나절 |
| 5. 표시 아이콘을 칸이 아닌 건물 단위로 묶고 줌별 크기 | 아이콘 소음 해결 | 반나절 |
| 6. 팔레트 양자화(48–64색) 시험 | 픽셀아트 통일감 | 반나절(옵션은 이미 있음) |
