# 이전 계획 — 분재(v0.2) → Anno식(v0.3)

v0.2 전체는 브랜치 `backup/v0.2-bonsai`(커밋 336fc6a)에 보존. 옛 세이브(`user://save.json`, 버전 2)는 새 모델과 맞지 않아 **옮기지 않는다** — 새 버전은 `save_v3.json`을 쓰고 옛 파일은 건드리지 않는다.

| 영역 | v0.2 | 처리 | 이유 |
|---|---|---|---|
| sim/Sim.gd, SimSystem, Expr, Metrics, RNG, SimIO | 시스템 러너·식 평가·헤드리스 입출력 | **유지·개조** | 규칙과 무관한 뼈대 |
| sim/systems: inflow, growth, collection, cards, care, identity, meters, plots, policy, economy, utilities, unlocks | 자동 성장·수금·결재·명물 | **교체** | 새 성장 동력은 수요·승급·노동력 |
| CityState | cells + households + businesses + collect_points | **교체(v3)** | 건물 인스턴스·재고·계약·탐험 |
| sim/Bot, tools/sim_run, tests | 봇 4종, 30일 실행 | **개조** | 시나리오 10종으로 확장 |
| data/* | 분재 콘텐츠 | **교체** | 폴더 구조로 재편 |
| view/ (CityMesher, PixelAtlas, People, Fx, 셰이더, 카메라) | 3D 픽셀 파이프라인 | **유지·개조** | 주거 = 계층×자재, 골조, 2×2 시설, 평면 배치 격자·범위 표시 추가 |
| ui/components, 테마, TopStrip, FloorRail, VerbBar, BottomSheet | 픽셀 UI 부품 | **유지** | |
| ui/sheets (심기·긋기·허가·결재·기록), BubbleLayer, 튜토리얼 대본 | 분재 동사 | **교체** | 짓기·살피기·승급·경제·탐험 지도·교역·성채 |
| core/Data.gd | 평면 폴더 | **개조** | 하위 폴더 재귀 |
| core/Game.gd | 경제 시계만 | **개조** | 실제 시계 주입, 미접속 0.25배·8시간 |

과거 방향서의 "뷰만 바꾸면 된다"는 추정은 틀렸다: 시뮬은 약 70%, UI는 약 60%, 뷰는 약 30%를 다시 쓴다.
