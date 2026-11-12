extends RefCounted
## 한 프레임의 조작. 사람(RunSandbox가 키보드·마우스에서 채움)과 자동 플레이어(AutoPlayer)가 같은 통로를 쓴다.

var move: Vector2 = Vector2.ZERO     # 길이 ≤ 1
var aim: Vector2 = Vector2.ZERO      # 월드 좌표(마우스가 가리키는 곳)
var attack: bool = false             # 이번 프레임에 눌림(왼쪽 클릭)
var throw: bool = false              # 이번 프레임에 던짐(오른쪽 버튼을 뗀 순간)
var throw_hold: bool = false         # 오른쪽 버튼을 누르고 있음(날아갈 길 미리 보기)
var roll: bool = false               # 이번 프레임에 눌림(Space)
var interact: bool = false           # 누르고 있음(E)
var pack_toggle: bool = false        # 이번 프레임에 눌림(Tab)
var slot_action: int = -1            # 배낭 칸 버리기/바꾸기(배낭이 열렸을 때 클릭·숫자키)


func clear_edges() -> void:
	attack = false
	throw = false
	roll = false
	pack_toggle = false
	slot_action = -1
