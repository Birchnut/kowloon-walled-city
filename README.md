# 구룡성채

제한된 12×12 사각 부지에 주거와 산업, 공급시설을 직접 배치하고, 다섯 계층 주민의 수요와 노동력을 관리하며, 탐험에서 가져온 자재로 자기만의 입체 성채를 완성하는 모바일 도시경제 게임. Godot 4.7, 세로 화면.

지금 버전: **v0.3 (Anno식 재편)**. 이전의 자동 성장판(v0.2 "분재")은 브랜치 `backup/v0.2-bonsai`에 보존.

## 돌려 보기
- **PC (Godot)**: 이 저장소를 ZIP으로 받아 풀고 → Godot 4.7 실행 → **가져오기(Import)** → `godot/project.godot` 선택 → 아래 진행 막대가 끝나면 오른쪽 위 ▶.
  이전 버전을 열어둔 적이 있으면 옛 폴더는 지우고 새로 받은 폴더를 가져온다.
- **폰/브라우저**: `gh-pages` 브랜치가 웹 빌드다. 저장소 Settings → Pages → Branch를 `gh-pages`로 저장하면 `https://birchnut.github.io/kowloon-walled-city/`에서 열린다.
- 빨리 감기·디버그: 게임 안 **성채 → 기록**에서 배속(×1/×4/×16), 돈·자재 추가, 하루 건너뛰기, 탐험 시간 건너뛰기.
- 수치·콘텐츠는 전부 `godot/data/**.json`. 고치고 게임 안에서 F5.

## 문서
| 문서 | 내용 |
|---|---|
| `docs/DESIGN_RESET.md` | Jin의 재기획 브리프(원문). [확정] 항목이 최우선 기준 |
| `docs/DECISIONS.md` | Jin이 직접 정한 것(라운드별) |
| `docs/GDD.md` | v0.3 설계: 계층·수요·생산·교역·탐험·진행 (디렉터 제안과 실험값) |
| `docs/ASSUMPTIONS_AND_EXPERIMENTS.md` | 디렉터가 정한 가정 — Jin이 뒤집을 수 있는 것 |
| `docs/ARCHITECTURE.md` | sim / view / ui 3층 구조와 계약 |
| `docs/SIM_NOTES.md` · `VIEW_NOTES.md` · `UI_NOTES.md` | 각 층의 구현 메모와 자체 결정 목록 |
| `docs/BALANCE_CHANGELOG.md` | 숫자를 바꾼 기록과 이유 |
| `docs/data_tables/` | JSON에서 자동 생성한 검토용 표 (손으로 고치지 않는다) |
| `research/ANNO1800_BENCHMARK.md` | Anno 1800 비교 조사 (수치는 미확인 표시) |
| `simulation/reports/` | 봇 시나리오 결과 |
| `docs/shots/` | 화면 모음 |
| `docs/archive/` | 분재 시기 문서 (폐기됨) |

## 개발 도구
```
tools/shot.sh "" out 30 540x960 skiptut load=mid tod=0.9 open=economy   # 실제 화면을 PNG로 (인자: godot/tools/DevHarness.gd)
godot/tests/sim_test.sh                                                  # 시뮬 시험
godot/tools/sim_run.gd                                                   # 봇 시나리오 (헤드리스)
godot/tools/data_tables.py                                               # 검토용 표 재생성
```
