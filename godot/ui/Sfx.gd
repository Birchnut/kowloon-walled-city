extends Node
## Sfx — 효과음 자리(오토로드). 지금은 소리를 내지 않는다(no-op). 소리 담당이 play() 안만 채우면 된다.
## UI는 알맞은 순간에 Sfx.play("<이름>")만 부른다. 이름 목록은 NAMES(그리고 docs/UI_NOTES.md v4 '소리 자리').
## 규칙 없음. 게임 상태를 읽지 않는다.

const NAMES := {
	"click": "버튼·탭 누름",
	"hover": "짓기 카드 위로 마우스(아주 작게, 아직 부르지 않음)",
	"build": "시설을 놓았다(공사 시작)",
	"zone": "판잣집을 칠해 지었다",
	"place_fail": "놓을 수 없는 자리에 눌렀다",
	"rotate": "배치 중 R로 돌렸다",
	"demolish": "철거 확정",
	"upgrade": "승급 시작",
	"money": "큰 돈이 들어왔다(목표 보상·수출)",
	"alert": "새 경고 알림",
	"fire": "불이 났다",
	"disease": "병이 돌기 시작했다",
	"hazard_on": "불·병 시스템이 처음 켜졌다",
	"goal": "목표 달성",
	"unlock": "새 시설이 열렸다",
	"floor": "새 층이 열렸다",
	"window_open": "창 열기",
	"window_close": "창 닫기",
	"speed": "배속·멈춤 바꿈",
	"expedition": "탐험대 출발/귀환 수령",
}

var muted: bool = false
var last: String = ""          # 개발 확인용(DevHarness trace)
var count: Dictionary = {}     # 이름 -> 부른 횟수


func play(sfx_name: String, _volume: float = 1.0) -> void:
	last = sfx_name
	count[sfx_name] = int(count.get(sfx_name, 0)) + 1
	if muted:
		return
	# 소리 담당: 여기에서 sfx_name 에 맞는 소리를 낸다.
