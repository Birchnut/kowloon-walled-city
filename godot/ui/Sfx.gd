extends Node
## Sfx — 소리 오토로드. UI는 알맞은 순간에 Sfx.play("<이름>")만 부른다. 이름 목록은 NAMES(그리고 docs/UI_NOTES.md v4 '소리 자리').
## 소리는 전부 코드로 합성한다(res://audio/ — docs/AUDIO_NOTES.md). 실제 일은 자식 AudioDirector 가 한다:
## 효과음·배경(도시 상태를 읽어 섞음)·작은 생성 음악·버스·설정(user://audio.cfg).
## 규칙 없음. 게임에 명령을 보내지 않는다(배경은 상태를 읽기만 한다).
##
## 설정 창용 API:
##   Sfx.set_volume(bus, 0..1) / Sfx.get_volume(bus)   bus = "master" | "sfx" | "ambience" | "music"
##   Sfx.mute(on) / Sfx.is_muted()                       전체 소리 끔
##   Sfx.muted = true/false                              효과음만 끔(옛 '효과음 끔' 단추 그대로)
##   Sfx.set_music_enabled(on) / Sfx.music_enabled()
##   Sfx.set_ambience_enabled(on) / Sfx.ambience_enabled()
##   Sfx.set_rain(0..1)                                  비 소리(뷰가 비를 그릴 때 불러 주면 된다)

const AudioDirector := preload("res://audio/AudioDirector.gd")

const NAMES := {
	"click": "버튼·탭 누름",
	"hover": "짓기 카드 위로 마우스(아주 작게, 아직 부르지 않음)",
	"tab": "창 안의 탭 바꿈(아직 부르지 않음 — click 대신 쓰면 된다)",
	"build": "시설을 놓았다(공사 시작)",
	"zone": "판잣집을 칠해 지었다",
	"place_fail": "놓을 수 없는 자리에 눌렀다",
	"rotate": "배치 중 R로 돌렸다",
	"demolish": "철거 확정",
	"upgrade": "승급 시작",
	"money": "큰 돈이 들어왔다(목표 보상·수출)",
	"alert": "새 경고 알림",
	"fire": "불이 났다",
	"fire_out": "불이 꺼졌다(사건 fire_out 에 Sfx 가 스스로 낸다)",
	"disease": "병이 돌기 시작했다",
	"hazard_on": "불·병 시스템이 처음 켜졌다",
	"goal": "목표 달성",
	"unlock": "새 시설이 열렸다",
	"floor": "새 층이 열렸다",
	"tier_up": "성채 등급이 올랐다(사건 milestone 에 Sfx 가 스스로 낸다)",
	"window_open": "창 열기",
	"window_close": "창 닫기",
	"speed": "배속·멈춤 바꿈",
	"expedition": "탐험대 출발/귀환 수령",
	"construction_done": "공사가 끝났다(사건 construction_done 에 Sfx 가 스스로 낸다)",
	"repair_done": "수리가 끝났다(사건 repair_done/repaired 에 Sfx 가 스스로 낸다)",
	"contract_done": "계약 회차 납품(사건 contract_done ok 에 Sfx 가 스스로 낸다)",
	"research_done": "연구가 끝났다(사건 research_done 에 Sfx 가 스스로 낸다)",
}

## 효과음만 끔(설정의 '효과음 끔'). 배경·음악은 그대로.
var muted: bool = false:
	set(v):
		muted = v
		if director != null and director.sfx_muted != v:
			director.set_sfx_muted(v)
var last: String = ""          # 개발 확인용(DevHarness trace)
var count: Dictionary = {}     # 이름 -> 부른 횟수
var director: Node = null


func _ready() -> void:
	director = AudioDirector.new()
	director.name = "AudioDirector"
	add_child(director)
	muted = director.sfx_muted


func play(sfx_name: String, volume: float = 1.0) -> void:
	last = sfx_name
	count[sfx_name] = int(count.get(sfx_name, 0)) + 1
	if muted or director == null:
		return
	director.play(sfx_name, volume)


func set_volume(bus: String, v: float) -> void:
	if director != null:
		director.set_volume(bus, v)


func get_volume(bus: String) -> float:
	return director.get_volume(bus) if director != null else 0.0


func mute(on: bool) -> void:
	if director != null:
		director.mute(on)


func is_muted() -> bool:
	return director != null and director.master_muted


func set_music_enabled(on: bool) -> void:
	if director != null:
		director.set_music_enabled(on)


func music_enabled() -> bool:
	return director != null and director.music_on


func set_ambience_enabled(on: bool) -> void:
	if director != null:
		director.set_ambience_enabled(on)


func ambience_enabled() -> bool:
	return director != null and director.ambience_on


func set_rain(amount: float) -> void:
	if director != null:
		director.rain = clampf(amount, 0.0, 1.0)
