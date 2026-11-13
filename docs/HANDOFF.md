# 인수인계 — 2026-11-14 (v0.5 통합 끝, main 합치기 전)

새 대화에서 이 프로젝트를 이어받는 Claude가 읽는 문서. 옛 인수인계(v0.4 기준, 설정집 읽는 법·소리·그림 방향의 긴 배경)는 `git show backup/v0.4-pc:docs/HANDOFF.md`로 볼 수 있다.

## 1. 한 것
- 브랜치 `v0.5` = 규칙(`wip/v05-sim`) + 화면(`wip/v05-ui`) + 그림(`wip/v05-view`) + 소리(`wip/v05-audio`) + 통합 작업. main은 아직 v0.4다. 합치기 전 백업은 `backup/v0.4-pc`.
- 확정 기획 `docs/DESIGN_v0.5.md`(= 코어 시스템 확정, 숫자는 임시값): 끝 목표 없음·민력·연표·장부의 마지막 장, 먹을 것 순서, 새는 돈, 창고 세 크기, 불·병 밀도, 아래층 어둠, 조직(십삼요회·연우당)·치안·갈등, 쉬었음시민, 고요시간.
- 층 사이 계약: `docs/ARCHITECTURE.md` "v5 계약 변경". 층별 기록: `docs/progress_v05_{sim,ui,view,audio}.md`.
- 통합에서 이은 것: 그림이 규칙의 `covered_depth`를 씀, 고요시간 사건이 그림·소리에 닿음(`tests/integ_v05_test.gd`가 본다), 첫 불·첫 병 카드, 위 띠 민력 날짜, 네모청 연표·마지막 장, 장부의 치안·갈등·쉬었음시민·새는 돈, 창고 렌즈, 안내 문구. C 등급 소리 세 줄 삭제.
- 확인: `sim_test.sh`·`run_test.sh`·소리 시험·통합 시험 통과, 사진 `docs/shots/v05_final_*.png`. 보고 `docs/REPORT_v0.5.md`.

## 2. 남은 것
- **웹 빌드 못 봄**(내보내기 템플릿이 없고 GitHub 릴리스 접근이 막혔었다). 템플릿 `Godot_v4.7.2-stable_export_templates.tpz`를 `~/.local/share/godot/export_templates/4.7.2.stable/`에 풀고 `tools/deploy_pages.sh`(push 없이)로 확인한다.
- **숫자 전부 임시값** — 불·병 밀도, 치안, 갈등, 새는 돈, 창고 배수(−15%), 선금(×1.5), 쉬었음시민 소일. 봇 11종을 새 규칙에 맞추고(Bot.gd는 조직 층 규칙·창고 세 크기를 모른다) 다시 돌려 맞춘다.
- 소리는 귀로 못 들었다. 곡 고르기·크기·빠진 음원(`docs/audio_missing.md`)은 Jin의 PC에서.
- 한자 간판이 확대 ×1~1.5에서 뭉개진다. 고요시간 화면 어둡기(0.14)는 낮에 약하다.
- 비 소리 연결(`Sfx.set_rain`)은 그림에 날씨가 생기면.
- 보류(기획 D): 계층 천장, 정화 시설, 층별 재고, 조직 협상, 물 네 등급, 가스 공급망, 층 이름, 골목 틈 그림, 후반 시설의 벽틈 일손 재배분.

## 3. Jin이 답하지 않은 것
- `docs/REPORT_v0.5.md` §4(승인 필요: A37~A82)와 §5. 특히 치안 해석(조직이 없어도 주민 40명 이상이면 부랑자 사건, A39), 쉬었음시민 정의(A49), 창고 −15%(A44).
- 이어서 v0.4의 §6(A23~A36)·§7(선택지)도 열려 있다.
- 사진을 본 뒤 main에 합칠지(디렉터).

## 4. 다음 일 (제안)
1. 웹 빌드 확인 → 사진 확인 → main 합치기 → gh-pages.
2. 봇을 새 규칙에 맞춰 숫자 조정(경제·치안·갈등·밀도), `_status`를 "임시값"에서 바꾼다.
3. 소리 곡 고르기, 마지막 장 글·막대 눈금 다듬기.

## 5. 읽는 순서
`CLAUDE.md` → 이 문서 → `docs/REPORT_v0.5.md` → `docs/DESIGN_v0.5.md` → `docs/ARCHITECTURE.md`("v5 계약 변경") → 손댈 층의 `docs/progress_v05_*.md`와 `*_NOTES.md`.

## 6. 요령
- Godot: `tools/godot/godot`(.gitignore). 시험은 `GODOT=<경로> godot/tests/sim_test.sh`(경로 기본값이 옛 폴더라 환경 변수로 준다). 새 폴더는 `--import`를 두 번.
- 견본 상태: `godot/tools/fixtures/make_v05.gd`가 `v05_mid/late/last.json`을 만든다(봇 40일 + 조직·창고, 약 2분). 사진은 `godot/tools/DevHarness.gd`의 `load=v05_last dbg=skip_days:0.2 script=…`.
- 층별 하위 에이전트를 따로 띄워 각자 브랜치에서 일하고 `--no-ff`로 합친다. 커밋은 한국어, 무엇을 왜.
