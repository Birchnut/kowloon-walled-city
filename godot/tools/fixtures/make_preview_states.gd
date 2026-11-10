extends SceneTree
## 승급 창의 외관 미리보기(계층 T2~T5 × 목재/철제/콘크리트 = 12장)를 찍기 위한 가짜 상태를 만든다.
## 가운데에 2×2×3 주거 탑 하나. tools/ui_house_previews.sh가 부른다(UI 담당, 규칙 없음).

const CAP := {1: 4, 2: 8, 3: 12, 4: 8, 5: 6}


func _init() -> void:
	var out := str(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	for fam: String in ["wood", "metal", "concrete"]:
		for t: int in range(2, 6):
			var s := CityState.new()
			s.day = 30
			s.hour = 11.0
			s.econ_days = 29.0 + 11.0 / 24.0
			s.floors_unlocked = 4
			var bid := 1
			for dx: int in 2:
				for dy: int in 2:
					for z: int in 3:
						var p := Vector3i(5 + dx, 5 + dy, z)
						s.cells[p] = {"kind": "house", "bid": bid, "type": "house", "tier": t, "material": fam, "seed": 1000 + bid * 7, "origin": p, "size": 1, "scaffold": false}
						s.buildings[bid] = {"id": bid, "kind": "house", "pos": p, "tier": t, "material": fam, "residents": CAP[t], "cap": CAP[t],
							"happiness": 60.0, "need_state": "ok", "upgradable": false, "upgrading": null, "needs": {}}
						bid += 1
			var f := FileAccess.open("%s/t%d_%s.json" % [out, t, fam], FileAccess.WRITE)
			f.store_string(s.to_json())
			f.close()
	quit(0)
