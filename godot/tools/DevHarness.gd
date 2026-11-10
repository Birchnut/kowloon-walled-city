extends Node
## DevHarness — 개발용: 사용자 인자로 메인 씬을 몰아 본다(통합 확인·스크린샷·타임랩스).
## Main이 인자를 보고 붙인다. 게임 규칙 없음.
##   skiptut            오프닝 건너뛰기
##   bot=<id>           data/bots.json 의 봇이 매 도시 시간마다 한 번 손을 댄다
##   speed=<n>          배속
##   load=<state.json>  CityState.to_json 스냅샷으로 시작
##   tod=<0..1>  cut=<n>  zoom=<i>  angle=<0..3>   뷰 고정
##   open=<plant|zone|policy|cards|record>          도구 열기
##   at=<초>            위의 뷰/도구 인자를 적용할 시각(기본 0.6초 — 첫 프레임 뒤)

var args: Dictionary = {}
var ui: Node = null
var view: Node = null
var _bot: Bot = null
var _applied := false
var _t := 0.0


static func wanted() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	for k: String in ["skiptut", "bot", "speed", "load", "tod", "cut", "zoom", "angle", "open"]:
		if out.has(k):
			return out
	return {}


func _ready() -> void:
	if args.has("load"):
		var text := FileAccess.get_file_as_string(str(args["load"]))
		if text != "":
			var s := CityState.new()
			s.from_json(text)
			Game.replace_state(s)
	if args.has("speed"):
		Game.speed = float(args["speed"])
	if args.has("bot"):
		_bot = Bot.new(Game.sim, str(args["bot"]))
		Game.event.connect(_on_event)


func _on_event(n: String, _p: Dictionary) -> void:
	if n == "hour" and _bot != null:
		_bot.act(Game.state)


func _process(delta: float) -> void:
	_t += delta
	if _applied or _t < float(args.get("at", 0.6)):
		return
	_applied = true
	if args.has("skiptut") and ui != null and ui.get("tutorial") != null:
		ui.tutorial.skip()
	if args.has("speed"):
		Game.speed = float(args["speed"])      # 튜토리얼이 배속을 되돌렸을 수 있다
	if view != null:
		if args.has("angle"):
			for i: int in int(args["angle"]):
				view.rotate_view(1)
		if args.has("zoom"):
			view.set_zoom(int(args["zoom"]))
		if args.has("cut"):
			view.set_floor_cut(int(args["cut"]))
		if args.has("tod"):
			view.set_time_override(float(args["tod"]))
	if args.has("open") and ui != null:
		ui.set_tool(str(args["open"]))
