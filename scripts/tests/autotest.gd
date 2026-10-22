extends SceneTree
## Headless simulation test: runs computer-vs-computer games and prints progress.
## Usage: godot --headless --script res://scripts/tests/autotest.gd -- [seed] [minutes] [players] [map_type] [difficulty]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 1
	var minutes := float(args[1]) if args.size() > 1 else 20.0
	var n := int(args[2]) if args.size() > 2 else 2
	var map_type: String = args[3] if args.size() > 3 else "lakes"
	var diff: String = args[4] if args.size() > 4 else "normal"
	var pl := []
	for i in n:
		pl.append({"team": i, "ai": true, "personality": Defs.PERSONALITIES.keys()[i % 4]})
	var sim := Sim.new({"seed": seed, "players": pl, "map_type": map_type, "map_size": "medium" if n <= 2 else "large", "difficulty": diff, "reveal": true})
	sim.new_game()
	var t0 := Time.get_ticks_msec()
	var last := 0.0
	while sim.time < minutes * 60.0 and not sim.over:
		sim.update(1.0 / 30.0)
		if sim.time - last >= 120.0:
			last = sim.time
			var line := "%dm" % roundi(sim.time / 60.0)
			for p in sim.players:
				var r := ""
				for k in Defs.RES:
					r += "%s%d," % [k[0], p.res[k]]
				var counts := {}
				for u in sim.units:
					if u.owner == p.id:
						counts[u.def.cls] = counts.get(u.def.cls, 0) + 1
				line += " | P%d ep%d pop%d/%d %s techs%d kill%d %s" % [p.id, p.epoch, p.pop, p.pop_cap, r, p.techs.size(), p.stats.killed, str(counts)]
			print(line)
	print("over=%s winner_team=%d how=%s time=%d wall_ms=%d" % [sim.over, sim.winner_team, sim.win_how, sim.time, Time.get_ticks_msec() - t0])
	# save/load round trip
	var d := sim.to_dict()
	var js := JSON.stringify(d)
	var back := Sim.from_dict(JSON.parse_string(js))
	print("save bytes=%d units=%d/%d buildings=%d/%d" % [js.length(), back.units.size(), sim.units.size(), back.buildings.size(), sim.buildings.size()])
	for i in 300:
		back.update(1.0 / 30.0)
	print("loaded game ran ok, time=%d" % back.time)
	quit()
