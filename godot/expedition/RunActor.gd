extends RefCounted
## 줍는 이·적·두목이 공유하는 순수 데이터. 행동은 RunWorld, 그림은 RunView.

var id: int = 0
var kind: String = ""          # player rat dog guard rival boss
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var knock: Vector2 = Vector2.ZERO
var radius: float = 5.0
var hp: int = 1
var max_hp: int = 1
var state: String = "idle"
var st: float = 0.0            # 지금 상태에 머문 시간
var timer: float = 0.0         # 상태별 목표 시간
var face: Vector2 = Vector2.DOWN
var target: Vector2 = Vector2.ZERO
var lock_dir: Vector2 = Vector2.RIGHT
var room: int = -1
var home: Vector2 = Vector2.ZERO
var flash: float = 0.0
var inv: float = 0.0
var stun: float = 0.0
var alert: float = 0.0
var aware: bool = false
var dead: bool = false
var hit_done: bool = false
var anim: float = 0.0
var path: PackedVector2Array = PackedVector2Array()
var path_i: int = 0
var path_t: float = 0.0
var stuck_t: float = 0.0
var last_seen: Vector2 = Vector2.ZERO
var seen_t: float = 0.0
var data: Dictionary = {}


func set_state(s: String, t: float = 0.0) -> void:
	state = s
	st = 0.0
	timer = t
	hit_done = false
