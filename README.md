# 구룡성채

도시를 짓지 않는다. 기른다. — 단칸방에서 시작해 한 달 동안 키우는 성채 분재(盆栽) 게임. Godot 4.7, 모바일 세로 화면.

## 돌려 보기
- **Godot**: Godot 4.7.x로 `godot/project.godot`을 열고 ▶. (처음 한 번은 가져오기가 끝날 때까지 기다린다.)
- **웹**: `gh-pages` 브랜치가 빌드다. 저장소 Settings → Pages에서 `gh-pages` 브랜치를 켜면 폰 브라우저로 열 수 있다.
- 수치·콘텐츠는 전부 `godot/data/*.json`. 고치고 게임 안에서 F5.

## 문서
| 문서 | 내용 |
|---|---|
| `docs/DECISIONS.md` | Jin이 직접 정한 것 |
| `docs/DIRECTION.md` | 디렉터가 정한 방향과 이유, 뒤집는 비용 |
| `docs/ARCHITECTURE.md` | sim / view / ui 3층 구조와 계약 |
| `docs/SIM_NOTES.md` | 시뮬 규칙 13종, 봇 비교표, 자체 결정 31건 |
| `docs/VIEW_NOTES.md` | 3D 픽셀 렌더러, 외형 추가법, 자체 결정 19건 |
| `docs/UI_NOTES.md` | UI 컴포넌트, 다시 꾸미는 법, 자체 결정 29건 |
| `docs/shots/` | 화면 모음 |
| `docs/GDD.md` | v0.1 기획 초안(일부 낡음 — DIRECTION이 우선) |

## 개발 도구
```
tools/shot.sh "" out 30 540x960 skiptut load=<state.json> tod=0.9 cut=2   # 실제 화면을 PNG로
godot/tools/sim_all.sh                                                    # 봇 4종 30일 + 일별 스냅샷
godot/tests/sim_test.sh                                                   # 시뮬 시험
```
`tools/shot.sh`의 인자(`skiptut bot= load= tod= cut= zoom= angle= open= speed=`)는 `godot/tools/DevHarness.gd` 참고.
