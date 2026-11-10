# 구룡성채 — Godot 프로젝트 골격 (v0)

Godot **4.7.2 stable** 기준. GDScript. 모바일 세로(540×960, canvas_items/expand), GL Compatibility 렌더러, 픽셀 스냅·Nearest 필터.

> 이 골격은 "자주 뒤집힐 것"을 전제로 만들었다. 수치·산업·정책·주민·외형 규칙은 전부 `data/*.json`에 있고, 코드는 그걸 읽기만 한다.
> Claude가 임의로 정한 값은 코드에 `# PLACEHOLDER:` 주석, 그리고 `../docs/SKELETON_DECISIONS.md`에 번호 목록으로 정리돼 있다. 거기서 승인/변경해 주면 된다.

---

## 1. 로컬에서 열기

1. Godot 4.x(4.7 권장, 4.4 이상이면 대체로 열림)를 [godotengine.org](https://godotengine.org/download) 에서 받는다. **Standard** 빌드(.NET 아님).
2. Godot 실행 → 프로젝트 매니저 → **Import** → 이 폴더의 `project.godot` 선택.
3. 첫 열기에서 에셋 임포트가 돌고 나면 **F5**(Run Project)로 실행. 메인 씬은 `scenes/Main.tscn`.
4. 모바일 비율로 보려면 에디터 상단 Run 메뉴에서 창을 세로로 늘리거나, Project Settings → Display → Window 에서 테스트 크기를 조정.

### 조작
| 입력 | 동작 |
|---|---|
| 드래그 / 터치 드래그 | 카메라 이동 |
| 휠 / 두 손가락 핀치 | 줌 |
| 탭(클릭 후 거의 움직이지 않고 떼기) | 셀 선택 → 하단 "구역 단면 (스텁)" 패널 |
| **`** (백틱) | 디버그 패널 토글 |
| **F5** | JSON 데이터 핫리로드 |
| **[** / **]** | 시각 스크럽(감상 모드 ±1시간) |
| **N** | 하루 넘기기 (하루 끝 → 제안 카드 3장 스텁 + 자동저장) |

---

## 2. 헤드리스 스모크 테스트

```bash
# 이 저장소에서는 바이너리가 ../tools/godot/godot 에 있음. 로컬에선 PATH의 godot 사용.
cd godot
godot --headless --path . --import            # 첫 1회 (에셋 임포트)
godot --headless --path . -s res://tests/smoke.gd
```

검사 내용: JSON 로드/검증 → 새 게임 → 게임 2일 틱(day_ended 2회, hour_changed 48회) → 징수 → 저장 → 로드 → 상태 일치 → 오프라인 보상 cap → 핫리로드 → v0 세이브 마이그레이션 → 외형 규칙 합성.
마지막 줄 `SMOKE TEST PASSED` + 종료 코드 0 이면 통과.

### 웹 export
```bash
godot --headless --path . --export-release "Web" build/web/index.html
# 결과: build/web/index.html (+ .wasm/.pck/.js). 로컬 확인:
cd build/web && python3 -m http.server 8080
```
프리셋은 **스레드 미지원(nothreads)** 변형이라 COOP/COEP 헤더 없는 평범한 정적 호스팅(GitHub Pages 등)에서도 뜬다. 처음 export 하려면 Editor → Manage Export Templates 에서 4.7.2 템플릿을 받아야 한다.

---

## 3. JSON 편집 & 핫리로드

- 모든 데이터는 `data/*.json`. **키는 영어, 사람이 읽는 이름/설명은 한국어.**
- 게임 실행 중 JSON을 저장하고 **F5**를 누르면 `Data.reload()`가 돈다.
  - 필수 키가 빠지면 `파일명.json > 필수 키 누락: a/b/c` 형식으로 콘솔에 에러가 나고, **기존 데이터는 유지**된다(부분 갱신 없음).
  - 리로드 성공 시 `EventBus.data_reloaded` → 격자 재구성, 낮/밤 그라디언트 재생성, HUD 갱신.
- 필수 키 목록은 `scripts/core/DataLoader.gd` 상단 `REQUIRED_KEYS`. 새 파일/키를 추가하면 여기도 같이 추가.
- 시뮬레이션 수치(경제·성장·위신)는 `CityState`가 틱마다 `eco`/`cfg` 딕셔너리를 **직접 읽으므로** 리로드 즉시 반영된다. `Save`가 `data_reloaded`를 받아 살아있는 도시에 새 데이터를 다시 주입한다(상태는 유지). 단, 격자 크기(`grid.width/height`)를 바꾸면 기존 세이브의 셀과 어긋나므로 "새 게임"이 필요하다.

| 파일 | 내용 |
|---|---|
| `config.json` | 격자 크기, 아이소 타일 크기, 하루 길이(초), 시작 시각, 오프라인 보상 한도, 시드, 카메라 줌, 낮/밤 그라디언트 |
| `industries.json` | 업종 4분류(농업/제조/오락/음성) + 업종 4개 샘플 |
| `policies.json` | 정책 축 4개(산업 허가/입주·돌봄/세금·투자/자재·외관) + 옵션별 effects |
| `materials.json` | 자재 5종 + 임시 색 |
| `residents.json` | 취향, 가구 유형, 대표인물 3명, 플레이어 호칭 규칙 |
| `visual_rules.json` | 레이어 합성 규칙(자재×업종×설비×취향×나이 → 레이어 키), 레이어 순서, 임시 색 |
| `economy.json` | 초기 금고/위신, 세율, 징수 타이머(숙성/부패), 성장 비용, 위신 효과, 노후 기준 |

---

## 4. 파일 맵

```
godot/
├─ project.godot              # 540x960 세로, canvas_items/expand, gl_compatibility, 픽셀 스냅, Nearest
├─ export_presets.cfg         # "Web" 프리셋 (nothreads)
├─ icon.svg
├─ data/*.json                # 위 표
├─ assets/
│  ├─ fonts/Galmuri11.ttf 등  # 한글 픽셀 폰트 (quiple/galmuri, OFL) + 라이선스
│  └─ themes/main_theme.tres  # PLACEHOLDER 테마 (어두운 패널, 네온 보더)
├─ scenes/
│  ├─ Main.tscn               # Sky(ColorRect) / World(CanvasModulate + IsoGrid) / Camera / DayNight / UI(HUD, 단면 스텁) / Debug
│  └─ ui/HUD.tscn             # 상단바, 하단 탭 4개, 탭 패널, 제안 카드 오버레이(3슬롯), 토스트
├─ scripts/
│  ├─ Main.gd                 # 부팅 순서, 탭→셀 선택, 단면 스텁 텍스트, 오프라인 요약 토스트
│  ├─ core/
│  │  ├─ EventBus.gd  (autoload EventBus)  전역 시그널
│  │  ├─ DataLoader.gd (autoload Data)     JSON 로드/검증/핫리로드, 경로 접근 Data.cfg("a/b")
│  │  ├─ GameClock.gd  (autoload Clock)    게임 시계, hour_changed/day_ended, time_of_day, 감상 모드 override, 오프라인 보상 계산
│  │  └─ SaveManager.gd (autoload Save)    user://save.json, schema_version + _migrate, 자동저장(하루 끝/백그라운드/종료), 활성 CityState 보유
│  ├─ world/
│  │  ├─ CityState.gd   순수 시뮬레이션(RefCounted). tick(dt_hours). 가구/일터/정책/금고/위신/징수·부패
│  │  ├─ IsoGrid.gd     12x12 아이소 격자+층. iso↔screen, pick_cell, 정렬, CellRenderer 관리
│  │  ├─ CellRenderer.gd 셀 1개 외형. visual_rules → 레이어 키 → (지금) 색 폴리곤 / (나중) Sprite2D
│  │  ├─ IsoCamera.gd   핀치 줌 + 드래그 팬 + 탭 감지
│  │  └─ DayNight.gd    time_of_day → Gradient → CanvasModulate + 하늘색
│  ├─ ui/HUD.gd
│  └─ debug/DebugPanel.gd   ` 토글. FPS, 시각 스크럽, 배속, 리로드, +₩500, 하루 넘기기, 징수, 저장/로드, 새 게임
└─ tests/smoke.gd            # 헤드리스 스모크 테스트
```

### 데이터 흐름(한 줄)
`Clock._process` → `Clock.advance(dt)` → `ticked` → `Save._on_clock_ticked` → `CityState.tick(dt)` → `changed`/`cell_changed` → HUD / IsoGrid 갱신.
하루 경계: `Clock.day_ended` → `EventBus.day_ended` → `Save`(city.on_day_ended + 자동저장), `HUD`(제안 카드 오버레이).

### 스프라이트로 바꿀 때
`CellRenderer.texture_for_layer(layer_key)` 가 `null` 이 아닌 텍스처를 돌려주면 폴리곤 대신 `Sprite2D`가 쌓인다. 레이어 계산(`resolve_layers`)과 격자/정렬은 그대로.

---

## 5. 알려진 한계 (이번 라운드 범위 밖)
- 단면 보기는 텍스트 스텁. 가려진 셀 선택은 "높은 층부터 검사" 임시 로직.
- 제안 카드 3장은 버튼만 있고 효과 없음.
- 정책 변경 UI 없음(디버그에서 `Save.city.set_policy()` 호출로만 가능).
- 징수 버튼은 디버그 패널의 "전체 징수"만 있음. 셀 탭 징수 UI 미구현.
- 오프닝 튜토리얼 스토리 없음(첫 가옥 1칸 + 로그 1줄만).
