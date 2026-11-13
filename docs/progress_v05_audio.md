# 진행 기록 — v0.5 audio (`wip/v05-audio`)

## 한 것
- 음원 확보: Kenney Interface Sounds 24 파일, 곡 6(Moil·Sideways City·Wednesday Night·Fusion Jazz·Holizna 2), 환경음(비 루프·마작 대역 칩 소리·망치·발소리). 출처는 `godot/audio/CREDITS.md`.
- 연결: `data/audio/audio_map.json`, `RecordedMusic.gd`(재생 목록·교차), AudioDirector(파일 대응·확대 곡선·고요시간), AmbienceBank(배관 루프·고요 소리 3).
- 검사 `audio/audio_v05_test.gd`(PASS), 기존 audio_test(기준 2.3 s 로), sim_test·run_test 통과.

## 남은 것
- Shop Theme·Oriented·Chills·Factory Ambiance 와 Freesound 환경음(`docs/audio_missing.md`) — Jin 의 PC 에서 받아야 한다.
- 귀로 듣고 곡·크기 고르기(AUDIO_NOTES §11.5). C 등급 출처(비·망치·발소리) 확인.
- 규칙 쪽이 quiet_start/quiet_end 를 실제로 내는지 통합 때 확인.

## 다음에 이어 할 사람이 알아야 할 것
- 새 음원을 넣으면 `--import` 를 두 번 돌리고 `.import` 파일도 커밋한다. WAV 는 `compress/mode=0`(QOA 로 압축되면 PCM 을 못 읽는다).
- 고요시간 직접 시험: `Sfx.director.quiet_start()` / `quiet_end()`. 확대 시험: `set_state_override({"zoom_out":x,"zoom_i":n,...})`.

## 정한 것 (스스로 정한 것 — 이유)
1. 효과음 17 개만 Kenney 로 바꾸고 월드 사건 10 개(불·병·등급·공사 끝 등)는 합성 유지 — 어울리는 UI 음이 없고 시대감(전자 UI 음 아님)을 해치기 때문.
2. 마작패 대역으로 Kenney 칩 소리를 씀, 빈도 ×2 — 마작패 파일을 못 구했고 칩 딸깍이 가장 가까워서.
3. Holizna 의 Chills 대신 같은 작가 다른 CC0 곡 2 개(2 Hour Delay·Winter Blues)를 낮·저녁 목록에 — 사본이 없고 시대감은 귀로 정해야 함(Jin 확인).
4. 비·망치·발소리를 C 등급 출처(작가 표기 없는 CC0 팩)로 넣음 — 대안이 합성뿐이라 일단 넣고 CREDITS 에 임시로 표시. 싫으면 JSON 줄 삭제.
5. 곡 분위기 전환은 곡이 끝날 때, 단 지금 곡이 새 목록에 없으면 즉시 6 초 교차 — 밤 곡이 낮까지 이어지지 않게.
6. 확대 곡선(음악 0 … -15 dB, 생활 ×0.35 … ×1.3)·고요시간 시간(1 s/2 s)·고요 소리 크기와 간격은 임시값(JSON `_status`).
7. 곡 음량 -19 LUFS 로 맞추고 Music 버스 0.4 는 그대로.
8. WAV 가져오기를 압축 없음으로(QOA 는 PCM 을 못 읽어 검사가 안 됨, 파일이 작아 용량 문제 없음).
9. audio_test 의 만들기 시간 기준 1.5 → 2.3 s(고요 소리·배관 루프 추가분).
