extends Node
## EventBus (autoload) — 전역 시그널 허브.
## 시스템 간 직접 참조를 피하고, 여기서 선언된 시그널로만 통신한다.
## 새 시그널 추가 시 아래에 한 줄 주석으로 용도 기록.

# --- 데이터 ---
signal data_reloaded                     # DataLoader가 JSON을 (재)로드함
signal data_error(file: String, message: String)  # 로드/검증 실패

# --- 시간 ---
signal hour_changed(hour: int)           # 게임 내 시각 변경 (0..23)
signal day_ended(day: int)               # 하루 끝 (제안 카드 트리거 지점)
signal time_scrubbed(time_of_day: float) # 디버그/감상 모드로 시간 수동 변경

# --- 도시 상태 ---
signal city_changed                      # CityState 요약 수치 변경 (HUD 갱신용)
signal cell_changed(x: int, y: int, z: int)  # 특정 셀 변경 (렌더 갱신용)
signal treasury_changed(amount: int)
signal population_changed(amount: int)
signal prestige_changed(amount: int)
signal harvest_ready(cell: Vector3i)     # 징수 가능
signal harvest_spoiled(cell: Vector3i)   # 방치로 부패

# --- 입력/UI ---
signal cell_selected(cell: Vector3i)     # 탭으로 셀 선택 (단면 보기 진입점)
signal cell_deselected
signal proposal_cards_requested(day: int) # 하루 끝 제안 카드 3장 표시 요청
signal policy_changed(axis: String, value)  # 정책 변경

# --- 저장 ---
signal game_saved(path: String)
signal game_loaded(summary: Dictionary)  # 오프라인 경과 요약 포함
