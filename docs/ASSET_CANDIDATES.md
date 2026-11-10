# 구룡성채 — 에셋 후보 조사 (2026-11-10, 작업 배치 A)

> 제약: 쉘에서 GitHub(clone / release URL)만 접근 가능. itch.io·OpenGameArt·kenney.nl 직접 다운로드 불가.
> 라이선스는 전부 **클론한 저장소 안의 LICENSE/README/License.txt를 직접 읽고** 확인함. 웹 검색은 후보 발견용으로만 사용.
> 다운로드 위치: `/home/claude/kowloon/assets_raw/<repo>/` (저장소별 디렉터리 분리, 내부 파일 실행 안 함).

## 0. 한 줄 결론

- **GitHub에는 "구룡성채풍 아이소메트릭 모듈러 건물" CC0 팩이 존재하지 않는다.** 건물 본체(자재 × 층 레이어 합성)는 우리가 직접 그리거나 생성해야 한다.
- 대신 **주민 캐릭터(걷기 애니), 네온·간판·파이프·안테나 등 데칼, 16×16 도시 타일·소품, 픽셀 UI, 한글 픽셀 폰트**는 CC0/OFL로 충분히 확보됨.
- 아이소메트릭 "참고용 지오메트리"(Kenney Isometric Buildings/City/Landscape, 벡터 스타일)는 확보했지만 **픽셀아트가 아니라** 스타일이 맞지 않음 → 프로토타입 플레이스홀더로만 사용 권장.

## 1. 확보한 저장소 (다운로드 완료)

| # | 저장소 | 라이선스 (실제 파일 인용) | 내용 | 용도 |
|---|---|---|---|---|
| R1 | `ETdoFresh/kenney.nl` → `assets_raw/kenney-mirror/` (sparse checkout, 63MB) | README: "**License:** (CC0 1.0 Universal) You're free to use these game assets in any project" + 각 팩 `License.txt`에 "License (Creative Commons Zero, CC0)" | Kenney 129개 팩 미러. 받은 것: 1-bit pack, Roguelike Modern City, Roguelike pack/Indoor, Micro Roguelike, Isometric Blocks/Buildings/City/Landscape, Pixel UI pack, UI pack, Font package, RPG Urban pack, Platformer Industrial, Generic items, Game icons, Emotes | 도시 16×16 타일, 아이소 참고, UI |
| R2 | `sigco3111/assets-2d-pixel` → `assets_raw/assets-2d-pixel/` (클론 626MB, 한국인 수집가) + 릴리스 zip 25개 → `assets_raw/sigco-releases/` | `LICENSE.md`: "이 저장소의 에셋 팩은 각각 CC0(퍼블릭 도메인)로 배포된 원본을 수집한 것" — **단, v8.15~8.17은 CC-BY 팩 포함**(사용 시 저작자 표기). rubberduck 팩들은 원본에 라이선스 파일이 없어 수집가 작성 `LICENSE-SOURCE.txt`(OGA 페이지 CC0 표기 근거) | 613팩. OGA + Kenney + ansimuz 36종 미러. 릴리스 태그가 README에 비어 있는 항목은 태그 순회(v1.0~v8.41)로 찾아 받음 | 캐릭터, 네온 소품, 도시 타일 |
| R3 | `Tiddybub/2d-assets` → `assets_raw/tiddybub-2d-assets/` (sparse, 38MB) | `LICENSE`: "All assets in this repository are CC0 1.0 Universal" + 팩별 `SOURCE.md` | 1101팩(OGA 959 + Kenney 142), `catalog.json`으로 검색 가능. 받은 것: Tiny Town, Sketch Town, Pico-8 City, UI Pack Pixel Adventure, Pixel UI, Roguelike RPG, Input Prompts Pixel, Crimelike furniture(32×32 모던 가구), Town Tiles, Plastic iso stack | UI, 가구, 보조 |
| R4 | `sparklinlabs/superpowers-asset-packs` → `assets_raw/superpowers-asset-packs/` (201MB) | `LICENSE.txt` = CC0 1.0 전문. README: "released under the Creative Commons Zero (CC0) license" | Pixel-boy 제작. Ninja Adventure(16×16 캐릭터 27종, 4방향 걷기, 타일셋, HUD, 아이템), Medieval Fantasy 등 | 주민 캐릭터 대안 |
| R5 | `quiple/galmuri` → `assets_raw/galmuri/` (141MB) | `ofl.md`: "licensed under the SIL Open Font License, Version 1.1" | Galmuri7/9/11/11 Bold/11 Condensed/14, Mono. 완성형 한글 11,172자(Galmuri7은 4,358자), TTF/BDF/WOFF2 | **한글 픽셀 폰트 1순위** |
| R6 | `neodgm/neodgm` → `assets_raw/neodgm/` + 릴리스 `neodgm.ttf` v1.601 → `assets_raw/neodgm-release/` | `LICENSE.txt`: "licensed under the SIL Open Font License, Version 1.1", Reserved Font Name "Neo둥근모" | 둥근모꼴 복원 10×10 픽셀 한글 폰트, 네온 간판 느낌에 적합 | 한글 폰트 2순위 (간판용) |
| R7 | `TakWolf/fusion-pixel-font` → `assets_raw/fusion-pixel-font/` + 릴리스 12px proportional zip → `assets_raw/fusion-pixel-release/` | `LICENSE-OFL`(폰트) + `LICENSE-MIT`(빌드 스크립트). zip 안에 `OFL.txt`와 Galmuri 등 원본 라이선스 동봉 | 8/10/12px, `-ko.ttf` 변형 포함(한·중·일 통합) | 한자(번체) 간판용 — 홍콩 느낌 한자 표기 시 |
| R8 | `godotengine/godot-demo-projects` 2d/isometric → `assets_raw/godot-demo-projects/` | `LICENSE.md`: MIT | 아이소 타일 6종(돌벽·문·바닥, **손그림 HD, 픽셀 아님**), 고블린 2048² 시트 | TileMap 아이소 세팅 레퍼런스 코드만 유용 |
| R9 | `SpriteCook/spritecook-free-game-assets` → `assets_raw/spritecook-free-game-assets/` (91MB) | `LICENSE` = CC0 1.0 | **AI 생성** 에셋(README 명시). 아이소 건물은 중세풍 300px 고해상도, 픽셀 아님 | **비권장**(스타일 불일치 + AI 생성물 저작권 불확실) |

제외/실패: `vaelixd/Assets`(CC-BY 4.0, 저작자 표기 필요 → 후보에서 제외, 클론 안 함). `Papyszoo/CC0-Public-Domain-Sprites`(Kenney 재미러, R1과 중복이라 생략). 0x72 DungeonTileset II, Urizen 등 itch.io 전용 팩은 GitHub 미러를 찾지 못함.

## 2. 요구 항목별 비교표

점수: 1(안 맞음) ~ 5(바로 사용). "퍼스펙티브": TD=탑다운, 3/4=RPG식 3/4뷰, ISO=아이소메트릭, SIDE=횡스크롤.

### 2-1. 아이소/2.5D 모듈러 건물 블록

| 팩 | 위치 | 라이선스 | 규격 | 퍼스펙티브 | 스타일 | 적합도 | 메모 |
|---|---|---|---|---|---|---|---|
| Kenney Isometric Buildings | `kenney-mirror/isometric-buildings/PNG/` (129장, 99×85) | CC0 | 아이소 타일 1칸=약 100×50 | ISO | **벡터·무외곽선·플랫 셰이딩, 픽셀 아님**. 1~2층 상자형, 지붕/벽 분리 X | 2 | 모듈러 아님(완성 건물). 12×12 그리드 프로토타입 플레이스홀더로만 |
| Kenney Isometric City | `kenney-mirror/isometriccity/PNG/` (128장, 132×104) | CC0 | 동일 격자 | ISO | 도로·인도·잔디·주차장 등 도시 지면 | 3 (지면용) | 12×12 부지 **지면 프로토타입**에 사용 가능 |
| Kenney Isometric Landscape | `kenney-mirror/isometriclandscape/PNG/` (131장, 132×83) | CC0 | 동일 격자 | ISO | 흙·잔디·물·언덕 | 3 (지면용) | 황량한 부지(흙/자갈) 표현 가능. 콘크리트/잔해는 없음 |
| Kenney Isometric Blocks | `kenney-mirror/isometric-blocks/PNG/` (Voxel 56 + Platformer 49 + Abstract 33, 111×128) | CC0 | 1칸 큐브 | ISO | 마인크래프트식 큐브. Voxel tiles는 나무/돌/모래/벽돌 재질 큐브 | 3 | **자재 × 블록 합성의 지오메트리 테스트**용으로 가장 쓸만. 외관 최종본으론 부족 |
| Pixel City (VividReality, OGA) | `sigco-releases/pixel-city/` (394×429 1장) | CC0 | 2:1 아이소, 약 48px 폭 | ISO | **진짜 픽셀 아이소 고층건물** 15동 + 지면 타일 + 트럭 | 3 | 유일한 "픽셀+아이소+도시" 후보. 완성 건물이라 모듈러 아님, 회색 사무용 톤. 층 자르기 리터칭 필요 |
| Japanese buildings iso mockup (undesired, OGA) | `sigco-releases/japanese-buildings-isometric-strategy-game-mockup/` (300×200 1장) | CC0 | 약 60px 폭 | ISO | 픽셀 아이소 동양 기와 건물 6동 + 잔디 지면 | 3 | 스타일 레퍼런스로 가치 큼(동양 지붕·파스텔). 수량 너무 적음 |
| Isometric Buildings #1 (Supergeek, OGA) | `sigco-releases/isometric-buildings-1/` | CC0 (zip 안 License.txt는 Kenney 것) | 99×85 | ISO | Kenney Isometric Buildings와 **동일 파일**로 보임(재업로드) | 2 | 중복 |
| Godot demo isotiles | `godot-demo-projects/2d/isometric/tileset/isotiles.png` | MIT | 1153×588 시트 | ISO | 손그림 HD 돌벽 | 1 | 코드 레퍼런스 전용 |

**결론: 조건(픽셀 + 아이소 + 모듈러 벽/지붕/바닥 + 자재 변형)을 만족하는 CC0 팩은 0개.**

### 2-2. 주민 캐릭터 (걷기/대기 애니)

| 팩 | 위치 | 라이선스 | 규격 | 퍼스펙티브 | 애니 | 적합도 | 메모 |
|---|---|---|---|---|---|---|---|
| Tiny Characters Set (SdiviHall, OGA) | `sigco-releases/tiny-characters-set/` (남12·여12, 각 64×51 시트) | **CC0 (수집가 기록). 주의: OGA 페이지 라이선스 필드가 비어 있음(node/70950 확인) → 재검증 필요** | 16×16 스프라이트 ×4방향 ×3프레임 | 3/4 | 4방향 걷기 3프레임 | 4 | GrafxKid RPG 캐릭터 기반. 헤어/의상 다양, 1px 외곽선. 수량·다양성 최고 |
| Customizable Character Pack (rubberduck, OGA) | `sigco-releases/customizable-character-pack/` (샘플 16장 64×96 + `.xcf` 레이어 원본) | CC0 (수집가 `LICENSE-SOURCE.txt`, OGA 페이지 표기 근거) | 16×24 ×4방향 ×3프레임 | 3/4 | 4방향 걷기 3프레임 | 4 | **xcf 레이어(피부/머리/옷) 분리 → 주민 취향·업종별 색 변형 자동 생성에 최적**. 외곽선 없음, 차분한 톤 |
| Kenney Roguelike Characters | `sigco-releases/roguelike-characters/Spritesheet/` (918×203) | CC0 (`License.txt`) | 16×16, 1px 마진 | TD/3/4 | **애니 없음**, 파츠 조합(몸·옷·모자·무기) | 3 | 정적 파츠 조합용. 걷기 없음 |
| Ninja Adventure (Pixel-boy) | `superpowers-asset-packs/ninja-adventure/characters/` (27종, 64×112) | CC0 | 16×16 ×4방향 ×4프레임 + 얼굴셋 | 3/4 | 4방향 걷기 4프레임 | 3 | 둥글고 귀여운 톤(닌자·몬스터). 구룡성채 블랙유머 톤과 이질적. 얼굴셋은 대표인물 카드에 응용 가능 |
| Kenney RPG Urban pack 캐릭터 | `kenney-mirror/kenney_rpgurbanpack/Tiles/` | CC0 | 16×16, 4방향 | 3/4 | 걷기 3프레임 | 3 | 현대 복장. 타일과 같은 팩이라 톤 일치 |
| Fumiko charset (ILIKESCIFI) | `sigco-releases/fumiko-complete-charset/` (864×256) | CC0 | 32×32 | 3/4 | 걷기·점프 등 다수 | 2 | 단일 캐릭터(빨간머리). 대표인물 1명 정도 |
| Simple Character Base 16×16 | `sigco-releases/simple-character-base-16x16/` | CC0 | 16×16 ×4방향 ×4프레임 | 3/4 | 걷기 | 3 | 누드 베이스 → 직접 옷 입히기용 |
| Warped City 플레이어 (ansimuz) | `sigco-releases/warped-city/.../SPRITES/player/` (71×67 프레임) | CC0 (`public-license.txt`) | 약 32×48 | SIDE | idle 4 / walk 16 / run / jump 등 10종 | 2 | 횡스크롤 전용. 아이소 지면에 못 섬 |
| GrafxKid City Mega Pack 시민 | `sigco-releases/city-mega-pack/CITY_MEGA.png` 상단 | CC0 (OGA 페이지 확인). 저자 "Credit me as GrafxKid" 요청(의무 아님) | 16×24 | SIDE/3/4 혼용 | 걷기 4프레임 | 3 | 간호사·경찰·요리사·로봇 등 **직업 변형** 풍부, "Build-a-Bub" 파츠 시스템 |

### 2-3. 소품/데칼 (간판·네온·파이프·에어컨·물탱크·빨래·화분·안테나·등롱·상자·드럼통·환풍구)

| 팩 | 위치 | 라이선스 | 규격 | 있는 것 | 없는 것 | 적합도 |
|---|---|---|---|---|---|---|
| **Warped City (ansimuz)** | `sigco-releases/warped-city/warped city files/ENVIRONMENT/` | CC0 | 16×16 타일셋(384×256) + 개별 PNG | **네온 간판 6종(애니 3~4프레임), HOTEL/SUSHI 간판, 안테나, 제어박스, 모니터, 파이프·덕트 타일, 환풍구, 배경 빌딩 5동(네온·안테나·접시안테나·배관 달린 타워)** | 빨래·화분·에어컨 | **5** (네온/사이버 톤의 핵심 소스) |
| Kenney Roguelike Modern City | `kenney-mirror/roguelike-modern-city-pack/Spritesheet/` (16×16, 1px 마진, 약 37×28칸) | CC0 | 16×16 | 벽돌/콘크리트/유리 벽면, 창문·문 다수, 가로등, 신호등, 쓰레기통, 드럼통, 상자, 콘, 화단, 나무, 차양, 자판기, 차량 | 네온, 파이프, 물탱크 | 4 (벽면 자재 변형: 벽돌/회색/베이지/유리 **4종** 이미 있음 → 자재 축 테스트에 유용) |
| GrafxKid City Mega Pack | `sigco-releases/city-mega-pack/CITY_MEGA.png` (1952×2800) | CC0 | 16px 기준 | 철조망, 전신주+전선, 신호등, 상자, 자판기, 덩굴, 화단, 에어컨 실외기, 간판 달린 건물 파사드(스시·카페·편의점), 실내 가구, 음식 | 아이소 | 4 (SIDE 뷰지만 데칼로 떼어 쓰기 좋음) |
| rubberduck Modern City Extension | `sigco-releases/modern-city-extension/city_extension.png` | CC0 (수집가 기록) | Kenney Roguelike City 호환 | 빨랫줄+빨래, 에어컨, 환풍구, 쓰레기봉투, 콘, 타이어 더미, 차고문 | — | 4 (**빨래·에어컨이 여기 있음**) |
| rubberduck Factory Tileset | `sigco-releases/factory-tileset/factory_tileset.png` (832×512) | CC0 (수집가 기록) | 16×16 | 공장 창·셔터·배관·케이블·모니터·전선 | — | 3 (회색톤, 철판/콘크리트 공장 자재) |
| Kenney Tiny City / Tiny Factory | `sigco-releases/tiny-city/`, `tiny-factory/` (16×16, 132칸) | CC0 | 16×16 | 벽돌/콘크리트 벽면, 가로등, 소화전, 펜스, 파이프, 톱니, 컨베이어 | — | 3 (굵은 외곽선 "Tiny" 스타일, 귀여움) |
| Kenney 1-bit pack | `kenney-mirror/1bitpack_kenney_1.1/Tilesheet/` (16×16, 1000+칸) | CC0 | 16×16 | 거의 모든 아이콘(상자·드럼통·간판·안테나·식물·등불) 단색 | 색 | 3 (**UI 아이콘/정책 카드 픽토그램**으로 최적) |
| Crimelike furniture (OGA) | `tiddybub-2d-assets/modern-urban/oga-crimelike-furniture/` (47장) | CC0 | 32×32, 4방향 | 침대·소파·욕조·제단(피 묻은 버전 포함) | — | 3 (단면 뷰 실내, 범죄 업종 블랙유머에 어울림) |
| Minimal Industrial Tiles (Blarget2) | `sigco-releases/minimal-industrial-tiles/` | CC0 | 16×16 | 공장 실루엣(트러스, 탱크, 사다리) 2색 | — | 2 (실루엣 배경용) |

### 2-4. 12×12 부지 지면 타일

| 팩 | 라이선스 | 메모 | 적합도 |
|---|---|---|---|
| Kenney Isometric Landscape / City | CC0 | 아이소 지면 다수(흙·잔디·도로·인도). 벡터 스타일이지만 **지면은 픽셀 건물과 섞여도 덜 튐**. 콘크리트 잔해·쓰레기 없음 | 3 |
| Kenney Isometric Blocks (Voxel) | CC0 | 흙/자갈/모래/돌 큐브 → 부지 높낮이 표현 | 3 |
| Pixel City 지면 타일 | CC0 | 픽셀 아이소 회색 포장 타일 8종 | 3 |
| Kenney Roguelike Modern City 지면 | CC0 | 탑다운 흙/잔디/아스팔트/인도 — 아이소로 변환 필요 | 2 |

### 2-5. 픽셀 UI

| 팩 | 위치 | 라이선스 | 메모 | 적합도 |
|---|---|---|---|---|
| Kenney Pixel UI Pack | `kenney-mirror/pixeluipack/` (9-slice 폴더 포함) | CC0 | 패널·버튼·슬라이더·화살표 5색, 9-slice 제공 → Godot NinePatchRect 바로 적용 | 4 |
| Kenney UI Pack – Pixel Adventure | `tiddybub-2d-assets/ui/ui-pack-pixel-adventure/` (517파일, Thin/Thick outline) | CC0 | 리본 배너·대화창·경고창(철판 느낌 회색 패널 있음) | 4 |
| Kenney UI Pack RPG Expansion | `sigco-releases/ui-pack-rpg-expansion/` | CC0 | 나무/양피지 톤 | 2 (톤 안 맞음) |
| Kenney Input Prompts Pixel | `tiddybub-2d-assets/ui/input-prompts-pixel/` | CC0 | 터치/버튼 프롬프트 | 3 |
| Kenney 1-bit pack / Micro Roguelike / Game icons | `kenney-mirror/` | CC0 | 아이콘 소스 | 4 |

### 2-6. 한글 픽셀 폰트

| 폰트 | 위치 | 라이선스 | 메모 | 적합도 |
|---|---|---|---|---|
| **Galmuri** 7/9/11/14 (+Bold, Condensed, Mono) | `galmuri/dist/*.ttf` | OFL 1.1 (`ofl.md`) | 한글 11,172자 + 가나 + 한자(JIS 6,355). 사이즈 체계가 모바일 UI에 딱 맞음(본문 11, 제목 14, 라벨 9) | 5 |
| **NeoDunggeunmo** v1.601 | `neodgm-release/neodgm.ttf` | OFL 1.1 | 둥근모꼴 복원, 10px 고정폭 느낌. 레트로 간판/네온 텍스트에 적합 | 4 |
| Fusion Pixel 12px proportional `-ko` | `fusion-pixel-release/12px-proportional/` | OFL 1.1 | 한·중·일 한자 통합(Galmuri 한글 글리프 재사용). **번체 한자 간판**(홍콩 느낌) 쓸 때 | 3 |
| Kenney Fonts | `kenney-mirror/kenney_fontpackage/` | CC0 | 영문만 | 2 |

## 3. 추천 조합 (Jin이 번호로 선택)

세 조합 모두 "건물 본체는 자체 제작" 전제. 차이는 **어느 팩을 기준 팔레트/외곽선 규칙으로 삼느냐**.

### 옵션 1. "네온 슬럼" — Warped City 기준 (어두운 톤, 1px 외곽선 없음)
- 기준: ansimuz Warped City 타일셋 팔레트(짙은 남색·청록·마젠타 네온).
- 주민: rubberduck Customizable Character Pack(외곽선 없음, 차분한 톤 → Warped와 잘 섞임). xcf 레이어로 색 변형 자동화.
- 소품: Warped City 네온/간판/안테나/파이프 + Modern City Extension(빨래·에어컨) + Roguelike Modern City 벽면 4자재.
- UI: Kenney UI Pack Pixel Adventure(회색 철판 패널 변형) + 1-bit 아이콘. 폰트 Galmuri(UI) + NeoDunggeunmo(간판).
- 리스크: Warped City는 **횡스크롤용**이라 아이소 면에 붙이려면 데칼을 45° 벽면에 "그려 넣는" 방식(평면 데칼 → 아이소 벽에 skew)으로 써야 함. 낮 시간대엔 팔레트가 너무 어두워 **낮/밤 2벌 팔레트** 필요. Kenney 16×16 타일은 밝은 톤이라 색 보정(LUT) 없이는 튐.

### 옵션 2. "밝은 Kenney 도시" — Roguelike Modern City 기준 (밝은 톤, 1px 외곽선)
- 기준: Kenney Roguelike Modern City + Modern City Extension(동일 작가 호환) + Tiny City/Factory.
- 주민: Tiny Characters Set(1px 외곽선, 밝은 톤) 또는 Kenney RPG Urban 캐릭터(같은 작가).
- 소품: 위 팩들의 가로등·드럼통·자판기·화단 + GrafxKid 데칼(에어컨·철조망·전선).
- UI: Kenney Pixel UI Pack(같은 작가라 톤 일치). 폰트 Galmuri.
- 장점: **스타일 일관성 최고**(대부분 Kenney). 밝아서 모바일 가독성 좋음.
- 리스크: "기괴함·네온·블랙유머" 톤과 거리 큼(사실상 심시티 느낌). 네온은 Warped City에서 가져와야 하는데 톤 충돌. Tiny Characters Set 라이선스 재검증 필요(아래 §5).

### 옵션 3. "하이브리드 — 지면/UI는 Kenney, 벽면 데칼은 Warped, 캐릭터는 rubberduck" (권장안이지만 작업량 최대)
- 지면: Kenney Isometric Landscape/City(벡터)를 **픽셀화(nearest downscale + 팔레트 양자화)** 해서 12×12 부지 타일 제작.
- 건물: 자체 제작(Pixel City·Japanese buildings mockup을 비례·지붕 레퍼런스로).
- 데칼: Warped City(네온·안테나·파이프) + Modern City Extension(빨래·에어컨) + GrafxKid(철조망·전선·간판 파사드).
- 주민: rubberduck Customizable(기본) + Tiny Characters Set(다양성 보강, 외곽선 제거 리터칭).
- UI/폰트: Kenney Pixel UI + Galmuri/NeoDunggeunmo.
- 리스크: 외곽선 규칙(있음/없음)이 팩마다 달라 **통일 리터칭 필수**. 팔레트 3종 혼합 → 공통 32~48색 팔레트를 정해 전부 재매핑하는 공정이 선행돼야 함.

## 4. 완전히 비어 있는 것 (직접 제작/생성 필요)

1. **아이소메트릭 픽셀 모듈러 건물 블록** — 벽/지붕/바닥 분리, 자재 4종(목재·철판·콘크리트·유리), 층 적층 가능. GitHub CC0에 없음. → 자체 제작. 레퍼런스: Pixel City(비례), Japanese buildings mockup(동양 지붕), Kenney Isometric Blocks(격자 규격).
2. **물탱크, 등롱(홍등), 대나무 비계, 위성접시(아이소 버전)** — Warped City 배경 빌딩에 그려진 것은 있으나 개별 스프라이트로 분리돼 있지 않음.
3. **단면(인테리어) 뷰 타일** — Crimelike furniture와 GrafxKid 실내가 일부 있지만 구룡성채식 "좁은 방 단면"은 없음. Kenney Roguelike Indoor(TD)로 임시 대체 가능.
4. **구룡성채 고유 산업 소품** — 카지노 슬롯, 콜센터 책상, 화약 통, 생체건축 요소 등: 전무.
5. **대표인물 초상** — Ninja Adventure 얼굴셋(6장)과 Kenney Emotes만 있음. 스타일 맞는 초상 생성기 필요.
6. **아이소 지면의 잔해·콘크리트 파편** — 황량한 부지 오프닝용. 없음.

## 5. 라이선스 주의 사항 (솔직하게)

- **Tiny Characters Set**: 수집가(R2)는 CC0로 기록했으나 OGA 노드 페이지(70950)에서 License 필드가 비어 있게 읽힘(OGA가 봇 차단 중이라 본문 전체 확인 불가). 최종 사용 전 Jin이 브라우저로 https://opengameart.org/content/tiny-characters-set 라이선스 표기를 직접 확인 권장. 확인 전까지는 **rubberduck Customizable**을 기본값으로.
- **rubberduck 팩들(Customizable Character, Modern City Extension, Factory Tileset)**: 원본 zip에 라이선스 파일이 없고, 수집가가 OGA 페이지 CC0 표기를 근거로 `LICENSE-SOURCE.txt`를 작성. 신뢰도는 높지만 1차 출처는 OGA 페이지.
- **GrafxKid City Mega Pack**: OGA 페이지 CC0 확인. 다만 저자가 "Credit me as GrafxKid" 요청 → 의무는 아니나 크레딧에 넣는 것을 권장.
- **sigco3111 저장소의 v8.15~8.17 릴리스**: CC-BY 3.0/4.0 팩(Tiny 16, Roguelike Tiles large, Moderna GUI 등) 포함 → **받지 않았고 쓰지 않음**.
- **SpriteCook**: CC0 선언이지만 AI 생성물. 스타일도 안 맞아 비권장. 클론은 남겨뒀으니 삭제 여부 선택.
- Kenney 전 팩: 각 `License.txt`에 CC0 명시. 문제 없음.

## 6. 컨택트 시트 (3배 확대, nearest)

- `/home/claude/kowloon/assets_raw/contact_sheet_kenney_isometric.png` — Isometric Buildings/City/Landscape/Blocks (벡터 스타일 확인용)
- `/home/claude/kowloon/assets_raw/contact_sheet_kenney_city16.png` — Roguelike Modern City 전체 시트, RPG Urban, Tiny City, Tiny Factory
- `/home/claude/kowloon/assets_raw/contact_sheet_characters.png` — Tiny Characters Set / rubberduck Customizable / Kenney Roguelike Chars / Ninja Adventure / 16×16 base / Fumiko
- `/home/claude/kowloon/assets_raw/contact_sheet_warped_citymega.png` — Warped City 타일·네온·안테나·배경 빌딩 + GrafxKid 시민·소품·파사드
- `/home/claude/kowloon/assets_raw/contact_sheet_ui.png` — Kenney Pixel UI / UI Pack Pixel Adventure / UI RPG Expansion (2배)

## 7. Claude가 임의로 정한 것 (승인 요청)

1. 저장소를 통째로 받지 않고 **sparse checkout / 릴리스 zip 선별**로 받음(kenney-mirror 20팩, tiddybub 15팩, sigco 25 zip). 이유: 전체 클론은 수 GB. 필요 시 `git sparse-checkout add <팩>`으로 추가 가능.
2. `sigco3111/assets-2d-pixel`은 README 미리보기 이미지가 필요해 본 저장소를 통째로 클론(626MB). 이유: 454장 미리보기로 후보 스크리닝. 용량 부담이면 `previews/` 외 삭제 가능.
3. 릴리스 태그가 비어 있는 항목은 v1.0~v8.41 **전 태그 HTTP 프로빙**으로 찾음. 이유: GitHub API가 쉘에서 403이라 릴리스 목록 조회 불가.
4. 컨택트 시트 대표 스프라이트 선정(각 팩 처음/중간/끝 인덱스 + 주요 소품). 이유: 전수 표시는 너무 큼.
5. CC-BY 팩은 다운로드 자체를 생략함(DECISIONS "CC0만 사용" 기준).
