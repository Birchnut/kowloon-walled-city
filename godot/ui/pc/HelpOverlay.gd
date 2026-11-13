class_name HelpOverlay
extends Control
## F1 도움말: 마우스·키보드 조작 전부 한 장. F1·Esc·아무 곳 클릭으로 닫는다.

const MOUSE := [
	["왼쪽 클릭", "건물 고르기(오른쪽에 살피기) · 배치 중이면 짓기"],
	["왼쪽 끌기", "주거 칠하기에서 네모 칠하기(Shift = 지나간 칸만)"],
	["오른쪽 클릭", "배치 그만 · 고른 것 풀기"],
	["오른쪽·가운데 끌기", "카메라 이동"],
	["휠", "확대·축소"],
	["마우스 올리기", "모든 버튼·숫자·신호등의 설명"],
]
const KEYS := [
	["W A S D · 방향키", "카메라 이동"],
	["Q / E", "카메라 90° 돌리기"],
	["PgUp / PgDn · [ ]", "보는 층(짓는 층) 올리기·내리기"],
	["Space", "멈춤 / 다시"],
	["1 · 2 · 3", "배속 ×1 · ×2 · ×4"],
	["H", "주거 칠하기"],
	["X · Delete", "철거(고른 건물이 있으면 그것)"],
	["G", "마우스 아래 시설 따라 짓기"],
	["R", "배치 중 돌리기(1×2 시설)"],
	["U", "승급(고른 집, 없으면 일괄)"],
	["Z C V B N M , . / K L", "짓기 분류 열기·닫기"],
	["Tab", "장부"],
	["F2 · F3 · F4 · F6", "돈 · 회상회 · 회색 띠 · 네모청"],
	["F11", "전체 화면"],
	["Ctrl+S", "저장"],
	["Esc", "그만 → 창 닫기 → 고름 풀기 → 렌즈 끄기"],
]


func _init() -> void:
	theme = PcTheme.paper_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.05, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var p := UI.panel("PanelGold")
	cc.add_child(p)
	var v := UI.vbox(10)
	p.add_child(v)
	var h := UI.hbox(10)
	v.add_child(h)
	h.add_child(Picto.make("help", UI.pcol("gold"), 3))
	h.add_child(UI.label("조작", "LabelHead"))
	var sp := UI.label("F1 · Esc · 아무 곳이나 눌러 닫기", "LabelDim")
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(sp)
	var cols := UI.hbox(30)
	v.add_child(cols)
	for part: Array in [["마우스", MOUSE], ["키보드", KEYS]]:
		var cv := UI.vbox(4)
		cols.add_child(cv)
		cv.add_child(UI.label(part[0], "LabelGoldSmall"))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 18)
		cv.add_child(g)
		for row: Array in part[1]:
			var k := UI.label(row[0], "LabelBold")
			k.custom_minimum_size.x = 200
			g.add_child(k)
			g.add_child(UI.label(row[1], "LabelSmall"))
	var foot := UI.label("위 띠의 신호등(물·전기·먹을 것·놀 것·불·병·일손)은 색으로 상태를 말한다: 초록 좋음 · 노랑 주의 · 빨강 위험 · 회색 꺼짐. 누르면 그 자리로.", "LabelDim", true)
	foot.custom_minimum_size.x = 980
	v.add_child(foot)
	for t: String in [
		"끝 목표는 없다. 목표 스물네 개는 길잡이이고, 민력 17년 겨울에 '장부의 마지막 장'이 한 번 펼쳐진 뒤에도 도시는 계속된다(네모청 › 마지막 장).",
		"창고(작은 1칸 · 보통 2칸 · 큰 4칸)는 재고 한도를 늘린다. 창고가 덮지 않는 층의 생산 시설은 조금 느리다. 창고 렌즈로 본다.",
		"조직(십삼요회 · 연우당) 시설은 같은 층과 맞닿은 층에서 서로 둘 수 없다. 가동 수만큼 치안이 오르고, 두 조직이 함께 있으면 갈등이 쌓인다. 장부 오른쪽에서 본다.",
		"금고가 인구에 비해 너무 크면 넘는 몫이 하루마다 샌다. 돈 창과 장부에 '새는 돈'으로 나온다. 치안이 높으면 덜 샌다."]:
		var fl := UI.label(t, "LabelDim", true)
		fl.custom_minimum_size.x = 980
		v.add_child(fl)


func toggle() -> void:
	visible = not visible
	Q.vcall("set_input_enabled", [not visible])   # 도움말이 떠 있는 동안 카메라 키가 도시를 움직이지 않게
	Sfx.play("window_open" if visible else "window_close")


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		toggle()
		accept_event()
