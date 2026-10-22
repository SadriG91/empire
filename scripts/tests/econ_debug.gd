extends SceneTree
func _initialize() -> void:
	var pl := [{"team": 0, "ai": true, "personality": "balanced"}, {"team": 1, "ai": true, "personality": "conqueror"}]
	var sim := Sim.new({"seed": 3, "players": pl, "map_type": "lakes", "map_size": "medium", "difficulty": "normal", "reveal": true})
	sim.new_game()
	var last := 0.0
	while sim.time < 1500:
		sim.update(1.0 / 30.0)
		if sim.time - last >= 90:
			last = sim.time
			for p in sim.players:
				var st := {}
				for u in sim.units:
					if u.owner == p.id and u.def.cls == "citizen":
						var k: String = u.state + ":" + u.gather_type
						st[k] = st.get(k, 0) + 1
				var farms := 0
				for b in sim.buildings:
					if b.owner == p.id and b.type == "farm":
						farms += 1
				print("%d P%d ep%d pop%d/%d res=%s farms=%d lost=%d %s" % [sim.time, p.id, p.epoch, p.pop, p.pop_cap, str(p.res.values().map(func(v): return int(v))), farms, p.stats.lost, str(st)])
	quit()
