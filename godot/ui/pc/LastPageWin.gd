class_name LastPageWin
extends PcWindow
## 장부의 마지막 장 — 종이 창 하나. last_page_ready 사건이 오면 UIRoot 가 연다. 단추는 "계속 적는다" 하나.
## 끝이 아니다: 닫아도 게임은 그대로 간다(last_page_ack 로 '보여 줬다'만 적는다). 다시 보기는 네모청 › 마지막 장.

var _list: VBoxContainer


func _init() -> void:
	super._init()
	win_id = "last_page"
	title_text = "장부의 마지막 장"
	want_size = Vector2(1100, 840)
	poll = 5.0


func _build(b: VBoxContainer) -> void:
	_list = PcWindow.scroll_list(b)
	var row := UI.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	b.add_child(row)
	var go := PcButton.make("계속 적는다", "right", "", "ButtonGold")
	go.pressed.connect(close)
	row.add_child(go)


func _refresh() -> void:
	if body == null:
		return
	PcWindow.clear(_list)
	var pg := Q.dict("last_page")
	set_subtitle(str(pg.get("date_text", "")))
	LastPageView.build(_list, pg, Q.dict("chronicle"))


func close() -> void:
	if not visible:
		return
	ui.cmd("last_page_ack", {})
	super.close()
