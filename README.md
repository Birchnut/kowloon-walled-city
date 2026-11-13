# 구룡성채

16×16 부지에 판잣집과 시설을 직접 놓고, 다섯 계층 주민의 먹을 것·물·놀 것·불·병을 챙기며, 고물을 주워다 10층짜리 성채를 올리는 PC 도시경제 게임. Godot 4.7, 1920×1080 가로 화면, 마우스+키보드. 탐험은 자동 파견과 직접 조작(고물 줍기 한 판 3분) 두 가지.

지금 버전: **v0.4 (PC판)**. 이전 판은 브랜치로 보존 — 모바일 Anno식 `backup/v0.3-mobile`, 자동 성장판 `backup/v0.2-bonsai`.

## 돌려 보기
- **PC (Godot, 권장)**: 이 저장소를 ZIP으로 받아 풀고 → Godot 4.7 실행 → **가져오기(Import)** → `godot/project.godot` 선택 → 아래 진행 막대가 끝나면 오른쪽 위 ▶ (F5).
  이전 버전을 열어둔 적이 있으면 옛 폴더는 지우고 새로 받은 폴더를 가져온다.
- **PC 브라우저**: `gh-pages` 브랜치가 웹 빌드다. 저장소 Settings → Pages → Branch를 `gh-pages`로 저장하면 `https://birchnut.github.io/kowloon-walled-city/`에서 열린다(크롬·엣지, 창을 크게. 폰 화면용이 아니다).
- **직접 줍기만 연습**: Godot에서 `godot/expedition/RunSandbox.tscn`을 열고 F6. 도시와 상관없이 돈다.

## 조작
| 하는 일 | 키·마우스 |
|---|---|
| 화면 옮기기 / 돌리기 / 확대 | 오른쪽 끌기 · Q/E · 휠 |
| 주거 칠하기 / 허물기 / 승급 | H · X(또는 Del) · U |
| 시설 짓기 | 아래 막대(분류 키 Z C V B N M , . / K L) → 왼쪽 클릭, R로 돌리기 |
| 배속 | Space(멈춤) · 1 / 2 / 3 |
| 현황판 / 경제 / 교역 / 탐험 / 성채 / 도움말 | Tab · F2 · F3 · F4 · F6 · F1 |
| 직접 줍기 | WASD · 마우스 조준 · 왼쪽 휘두르기 · 오른쪽 던지기 · Space 구르기 · E 뒤지기 · Tab 배낭 · M 소리 끄기 |

- 빨리 감기·디버그: **성채(F6) → 설정·디버그**에서 돈·자재 추가, 층 채우기, 불·병 내기.
- 수치·콘텐츠는 전부 `godot/data/**.json`. 고치고 게임 안에서 F5.

## 문서
| 문서 | 내용 |
|---|---|
| `docs/REPORT_v0.4.md` | **v0.4(PC판) 작업 보고** — 지금 상태, 확인한 것·못 한 것, 디렉터가 정한 것, Jin이 고를 것 |
| `docs/GDD_PC.md` | v0.4 설계: PC판 규칙·필수 시설·위험·성채식 조달·이름 사전 |
| `docs/EXPEDITION_RUN.md` · `docs/RUN_NOTES.md` | 직접 줍기(탐험 미니게임) 설계와 구현 메모 |
| `docs/AUDIO_NOTES.md` | 합성 효과음·배경음 메모 |
| `docs/REPORT_v0.3.md` | v0.3(모바일판) 작업 보고 |
| `docs/DESIGN_RESET.md` | Jin의 재기획 브리프(원문). [확정] 항목이 최우선 기준 |
| `docs/DECISIONS.md` | Jin이 직접 정한 것(라운드별) |
| `docs/GDD.md` | v0.3(모바일판) 설계 — 옛 문서 |
| `docs/ASSUMPTIONS_AND_EXPERIMENTS.md` | 디렉터가 정한 가정 — Jin이 뒤집을 수 있는 것 |
| `docs/ARCHITECTURE.md` | sim / view / ui 3층 구조와 계약 |
| `docs/SIM_NOTES.md` · `VIEW_NOTES.md` · `UI_NOTES.md` | 각 층의 구현 메모와 자체 결정 목록 |
| `docs/INTEG_NOTES.md` | 통합 점검표, 처음 하는 사람이 막히는 곳, 첫 접속 흐름 다시 돌리기 |
| `docs/BALANCE_CHANGELOG.md` | 숫자를 바꾼 기록과 이유 |
| `docs/data_tables/` | JSON에서 자동 생성한 검토용 표 (손으로 고치지 않는다) |
| `research/ANNO1800_BENCHMARK.md` | Anno 1800 비교 조사 (수치는 미확인 표시) |
| `simulation/reports/` | 봇 시나리오 결과 |
| `docs/shots/` | 화면 모음 |
| `docs/archive/` | 분재 시기 문서 (폐기됨) |

## 개발 도구
```
tools/shot.sh "" out 30 1920x1080 skiptut load=mid                        # 실제 화면을 PNG로 (인자: godot/tools/DevHarness.gd)
tools/shot.sh "" out 4000 1920x1080 script=res://tools/fixtures/pc_first_session.json out=out   # 첫 접속 흐름을 진짜 마우스·키로 (나머지 대본은 docs/INTEG_NOTES.md)
godot/tests/sim_test.sh                                                  # 도시 규칙 시험(캐시 비교 시험 포함)
godot/tests/run_test.sh                                                  # 직접 줍기 시험(자동 플레이어)
simulation/run_all.sh                                                    # 봇 시나리오 → simulation/reports/
tools/deploy_pages.sh push                                               # 웹 빌드 → gh-pages
```
