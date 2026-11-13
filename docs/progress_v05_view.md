# 진행 기록 — v0.5 view

## 한 것
- 간판 한자 섞기(signs.json, ViewCfg.sign_text, PixelAtlas 한자 허용·11px). 25/55 시설이 한자 간판.
- 덮인 아래층 어둡게(coverstate 텍스처 + city.gdshader, 최대 30%). 층수 세기는 `_covered_depth` 한 함수.
- 고요시간(quiet_start/quiet_end 사건 + debug_quiet, People 정지, screen 셰이더 dim).
- 그림: docs/shots/v05_view_*.png

## 남은 것
- 규칙 쪽이 `covered_depth` 질의·`quiet_*` 사건을 내주면 실제 연결 확인(render.json cover.source = "sim").
- 확대 ×1~1.5에서 한자 간판이 뭉개진다. 필요하면 한자 간판만 확대 단계에서 크게 그리거나 글자 수를 줄인다.

## 다음 사람이 알아야 할 것
- 시험용 후반 도시: 봇 60일 상태를 저장해 `state=<json>`으로 Sandbox에 넣었다(/tmp, 저장소엔 없음).
- origin/wip/v05-sim 은 아직 없었다(fetch 실패).

## 정한 것
- 구룡완탕: Galmuri에 吞이 없어 呑(같은 글자) 사용.
- 한자 간판은 11px 글꼴(9px는 뭉개짐).
- 덮임 최대 0.3, full_depth 3층, 파랑 쪽 색 이동 (0.86,0.95,1.08) — 임시값(v0.5).
- 고요 어둡기 0.14, 들어갈 때 1.5초·나올 때 2.5초 — "약 4초"를 이렇게 나눴다. 임시값(v0.5).
- 고요 중 정지 대상은 walk·gate 주민만(새, 고양이 등 배경 생물은 그대로).
- 셀에 직접 `sign`이 있으면(FakeCity 견본뿐, 실제 규칙 셀에는 없다) 그것이 한자 표보다 먼저다(기존 순서 유지).
