# 못 구한 음원 목록 (v0.5)

디렉터가 Jin 의 PC 브라우저로 받아 `godot/audio/music/`·`amb/` 에 넣을 때 쓴다. 이 작업 공간에서는 opengameart.org·freesound.org·kenney.nl 에 셸로 닿지 않고, WebFetch 도 이 사이트들의 robots 에 막혀 **페이지를 읽지 못했다**(그래서 CC0 표시와 파일 이름을 직접 확인한 곳이 없다). 아래 '페이지 주소'는 웹 검색 결과에 나온 것(내용 미확인)이거나 Jin 의 목록에 적힌 곡 이름이다. 직접 받는 파일 주소는 **페이지의 Download 단추에서 찾아야 한다**(추측으로 적지 않았다). 라이선스는 Jin 의 목록이 'CC0 확인'이라고 한 것을 그대로 옮긴 것 — 받을 때 페이지에서 한 번 더 볼 것.

받은 뒤 할 일: ffmpeg 로 `-af loudnorm=I=-19:TP=-2:LRA=11 -c:a libvorbis -q:a 4` ogg 로 바꿔 넣고, `godot/data/audio/audio_map.json` 의 `music.tracks`·`music.lists`(곡) 또는 `loop_files`·`shot_files`(환경음)에 한 줄 추가, `godot/audio/CREDITS.md` 에 한 줄 추가, `--import` 두 번.

## 음악 1차 (곡)

| 곡 | 작가 | 페이지 주소 | 직접 받는 파일 | 라이선스(목록 기준) | 쓸 자리 | 왜 못 구했나 |
|---|---|---|---|---|---|---|
| Shop Theme | Cleyton Kauffman | https://opengameart.org/content/shop-theme (검색 결과, 미확인) | 페이지에서 확인 | CC0 | 낮 목록 또는 가게 안 라디오 | GitHub 사본을 찾지 못함 |
| Oriented | yd | 검색으로 페이지를 못 찾음 — OGA 에서 'Oriented yd' 검색 | 페이지에서 확인 | CC0 | 아래층·특수 지역(밤) | 사본 없음 |
| Chills | Holizna | 검색으로 페이지를 못 찾음 — 작가 FMA https://freemusicarchive.org/music/holiznacc0/ , OGA 에서 'Chills Holizna' 검색 | 페이지에서 확인 | CC0 | 낮·저녁 | 사본 없음(같은 작가의 다른 CC0 곡 2 개를 대역으로 넣음) |
| Factory Ambiance | yd | https://opengameart.org/content/factory-ambiance (검색 결과, 미확인) | 페이지에서 확인 | CC0 | 아래층·기계실 지역 | 사본 없음 |
| (Moil 은 구했다) | | | | | | |

## 음악 2차 (Jin 목록의 후보)

Tyhosi Asian Sparrow 4 Kimono Market Zone(Tozan) · Town in Ruins Loop(Brandon Morris, CC0 선택) · Lo-fi Compilation(A cup of tea · Bartender · Morning rain) · Jazzy Blues · Jazz n' Brass Loop · Orien · School Day / Rain / Sun · Sewer Nightclub(전자음악 — 이벤트 전용) — 전부 OGA. 페이지 주소·파일 이름을 확인하지 못했고 사본도 못 찾았다. 1972년 시대감에는 Orien(동양 현악)·Jazzy Blues·Lo-fi Compilation 이 우선.
중국 전통악기(Freesound): A Ride Through Chinese Valley · Sad-Huqin.wav(merkahz) · Karst Mountains(neolein) — 주소 미확인. Freesound 는 받을 때 로그인이 필요하다.

## 환경음 (Freesound — 전부 주소 미확인, 작가 이름은 Jin 목록 기준)

| 이름 | 작가 | 길이 | 쓸 자리 | 지금 대역 |
|---|---|---|---|---|
| Rain on Tin Roof | camdenavenue | 1:02 | 비 층 | 팩 `loop_rain`(C 등급) |
| Vintage Market Crowd | (목록에 없음) | 1:19 | 시장 웅성 층(`murmur`/`market`) | 합성 |
| Urban Market Crowd | kayaker25 | 4:07 | 밀집 상권 | 합성 |
| Tiles Fall on Corkboard | Detective_Lemons | 0:03 | 마작패(`shot_files.mahjong`) | Kenney 칩 소리 |
| Radio Static | waxsocks | 2:45 | 먼 라디오(`radio`) | 합성 |
| Door Creak | stib | 0:37 | 삐걱 소리(새 한 번짜리) | (없음) |
| Rain on Roof & Window Sills | (목록에 없음) | 1:57 | 벽 틈 빗소리 | |
| Ambient Low Hum (aircon) | TimBahrij | 0:58 | 기계실·환풍기 | 합성 웅웅 |
| Water Dripping (Medium-light) | Sadiquecat | 0:23 | 배수관·고요시간 물방울 | 합성 |
| Frying | karinalarasart | 0:09 | 노점·주방 | 합성 웍 |

검색용 주소(내용 미확인): https://freesound.org/search/?q=<이름>
Freesound 의 홍콩 춘영가 시장 녹음은 CC BY-NC 라 쓸 수 없다.
