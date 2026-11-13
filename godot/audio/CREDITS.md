# 소리 출처와 라이선스 (v0.5)

전부 CC0(퍼블릭 도메인 헌정)이거나 직접 만든 합성음이다. 출처 표기는 의무가 아니지만 적어 둔다.
셸은 GitHub 에만 닿았다. 원본 사이트(OpenGameArt·Freesound·Kenney)는 셸·페이지 읽기 모두 막혀 있어서, **원본 페이지를 직접 보지 못한 것은 '확인 수준'에 적어 두었다.**
파일은 모두 ffmpeg 로 다시 인코딩했거나(곡: 음량 -19 LUFS 로 맞춘 ogg q4) 그대로 복사했다(Kenney WAV).

확인 수준: **A** = 받은 저장소가 원본 OGA 페이지 사본(저장된 HTML 의 CC0 표시·파일 이름·바이트 수)과 SHA-256 을 갖고 있고 내가 해시·크기가 맞는 것을 확인 · **B** = 받은 저장소의 LICENSE 가 작가·CC0 를 밝히고 작가 이름이 곡 파일에 있음 · **C** = 팩 이름에 CC0 가 들어 있고 저장소 전체가 CC0 라고만 적힘, 작가 표기 없음(임시 — 확인 필요) · **K** = Kenney 공식 팩(폴더에 License.txt 의 CC0 전문).

## 음악 (`godot/audio/music/`)

| 파일 | 곡 | 작가 | 원본 페이지 | 받은 곳 | 라이선스 | 확인 |
|---|---|---|---|---|---|---|
| moil.ogg | Moil (밤) | Ruskerdax | https://opengameart.org/content/moil (파일 `ruskerdax_-_moil.mp3`, 7,403,151 B) | github.com/devartblake/VoxelVenture `apps/web/public/audio/music/moil.mp3` (SHA-256 d496edaf…dc25, 저장된 OGA 페이지 `docs/licences/music/moil.html` 의 CC0·바이트 수와 일치) | CC0 | A |
| sideways_city.ogg | Sideways City | Zane Little Music | https://opengameart.org/content/sideways-city | 같은 저장소 `sideways-city.ogg`(원본 WAV 를 그 저장소가 ogg 로 줄인 것) | CC0 | A |
| wednesday_night.ogg | Wednesday Night [Funk Fusion] | Zane Little Music | https://opengameart.org/content/wednesday-night-funk-fusion | 같은 저장소 `wednesday-night.ogg` (SHA-256 514f0665…18f3, 원본과 같음) | CC0 | A |
| fusion_jazz.ogg | (Basically not) Fusion Jazz | Spring Spring | https://opengameart.org/content/basically-not-fusion-jazz | 같은 저장소 `fusion-jazz.ogg` (SHA-256 645f7cd6…4af4) | CC0 | A |
| holizna_2_hour_delay.ogg | 2 Hour Delay (Winter Lofi) | HoliznaCC0 | https://freemusicarchive.org/music/holiznacc0/ | github.com/C-C-Minetest-Server/phonograph_albumm_holiznacc0 `phonographs/002-winter-lofi/…002-01-2-hour-delay.ogg` | CC0 (저장소 LICENSE.md: "All media files are authored by HoliznaCC0 … released under CC0") | B |
| holizna_winter_blues.ogg | Winter Blues | HoliznaCC0 | 같음 | 같은 저장소 `…002-05-winter-blues.ogg` | CC0 | B |

Jin 목록의 **Chills(Holizna)**·**Shop Theme(Cleyton Kauffman)**·**Oriented(yd)**·**Factory Ambiance(yd)** 는 원본 페이지를 읽을 수 없고 믿을 만한 사본도 못 찾아서 **넣지 않았다**(`docs/audio_missing.md`). Holizna 의 다른 CC0 곡(2 Hour Delay·Winter Blues)을 '낮·저녁 로파이' 자리 대역으로 넣었다. 귀로 듣고 시대감이 맞는지 정해야 한다.

## UI 효과음 (`godot/audio/sfx/`) — Kenney Interface Sounds 1.0

작가 Kenney (www.kenney.nl) · CC0 · 원본 https://kenney.nl/assets/interface-sounds · 받은 곳 github.com/Calinou/kenney-interface-sounds `addons/kenney_interface_sounds/*.wav`(Ogg 를 WAV 로 무손실 변환한 것, 폴더에 LICENSE.txt CC0 전문) · 확인 K.
쓴 파일 24 개: select_007 · select_008 · tick_001 · tick_002 · toggle_001~004 · maximize_003 · maximize_005 · minimize_003 · drop_001~004 · error_004 · error_007 · scratch_004 · scratch_005 · confirmation_002~004 · glass_004 · question_003. 이름 → 파일 대응은 `godot/data/audio/audio_map.json` 의 `sfx_files`.

## 환경음 (`godot/audio/amb/`)

| 파일 | 설명 | 작가·원본 | 받은 곳 | 라이선스 | 확인 |
|---|---|---|---|---|---|
| tiles_1~4.ogg | 마작패 딸깍의 대역 — 칩 부딪힘(`chipsCollide1~4`) | Kenney, Casino Audio https://kenney.nl/assets/casino-audio | github.com/lavenderdotpet/CC0-Public-Domain-Sounds `kenney_casinoaudio/Audio/` (폴더에 License.txt) | CC0 | K |


## 직접 만든 소리 (코드 합성, 라이선스 문제 없음)

`Synth.gd` 이하 — 효과음 10 개(tier_up · hazard_on · fire · fire_out · disease · expedition · construction_done · repair_done · contract_done · research_done), 배경 루프(웅웅·바람·웅성·장터·귀뚜라미·불·**배관 떨림**), 배경 한 번짜리(참새·비둘기·개·종·주전자·마작·라디오·망치·뱃고동·물방울·웍·셔터, 고요시간의 **물방울·머리 위 발소리·균열**), 악기·바탕 화음·합성 음악(불 났을 때의 긴장 구절 포함).
