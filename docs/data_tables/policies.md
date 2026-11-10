# 정책

자동 생성 — 원본 `godot/data/progression/policies.json` (상태: 구조 제안 / 수치 실험값). 고치려면 JSON을 고치고 `python3 godot/tools/data_tables.py`.

칸 수 = 열린 `feature:policy_slot_N`(해금 표 참고).

| id | 이름 | 효과 | 유지비 ₩/일 | 음성 시설당 ₩/일 | 같이 못 켬 | 설명 |
|---|---|---|---|---|---|---|
| rations | 배급제 | cons.food -0.2, happy.base -8 | 0 | 0 |  | 끼니를 줄여 나눈다. 끼니 소비 −20%, 행복 −8. |
| overtime | 초과 근무 | prod.all +0.2, happy.base -10 | 0 | 0 |  | 밤까지 돌린다. 생산 처리량 +20%, 행복 −10. |
| tax_cut | 감세 | tax.all -0.2, happy.base +8 | 0 | 0 | tax | 세금을 깎아 준다. 세수 −20%, 행복 +8. |
| tax_hike | 중과세 | tax.all +0.25, happy.base -12 | 0 | 0 | tax | 골목마다 걷는다. 세수 +25%, 행복 −12. |
| bribes | 뒷돈 | heat.gain -0.7 | 0 | 25 |  | 경찰서에 봉투를 돌린다. 단속 위험이 쌓이는 속도 −70%, 음성 시설 하나당 유지비 {upkeep_per_vice}/일. |
| welcome | 입주 장려 | movein +1 | 60 | 0 |  | 이삿짐 수레를 보낸다. 입주 속도 2배, 유지비 {upkeep}/일. |
