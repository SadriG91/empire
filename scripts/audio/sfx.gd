class_name Sfx
extends Node
## Procedurally synthesised sound effects (no audio files) with simple distance attenuation.

const RATE := 22050
const HEAR_RANGE := 80.0

var streams := {}
var _players: Array = []
var _last := {}
var muted := false
var master := 0.8
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7
	for i in 14:
		var p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func _buf(sec: float) -> PackedFloat32Array:
	var b = PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b

func _noise(sec: float, decay: float, lp: float, gain := 1.0, attack := 0.002) -> PackedFloat32Array:
	var b = _buf(sec)
	var y = 0.0
	for i in b.size():
		var t = float(i) / RATE
		var env = minf(1.0, t / attack) * exp(-t * decay)
		y += (_rng.randf_range(-1, 1) - y) * lp
		b[i] = y * env * gain
	return b

func _tone(b: PackedFloat32Array, freq: float, decay: float, gain: float, start := 0.0, saw := false, sweep := 0.0) -> void:
	var s0 = int(start * RATE)
	var ph = 0.0
	for i in range(s0, b.size()):
		var t = float(i - s0) / RATE
		var f = freq + sweep * t
		ph += f / RATE
		var w = (fmod(ph, 1.0) * 2.0 - 1.0) if saw else sin(ph * TAU)
		b[i] += w * exp(-t * decay) * gain * minf(1.0, t / 0.005)

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out = a.duplicate() if a.size() >= b.size() else b.duplicate()
	var o = b if a.size() >= b.size() else a
	for i in o.size():
		out[i] += o[i]
	return out

func _build() -> void:
	var s: PackedFloat32Array
	s = _noise(0.18, 30.0, 0.9, 0.3)
	_tone(s, 2300, 25, 0.25); _tone(s, 3400, 30, 0.18); _tone(s, 5200, 40, 0.1)
	streams.sword = _wav(s)
	streams.hit = _wav(_noise(0.1, 40.0, 0.25, 0.7))
	streams.bow = _wav(_noise(0.28, 12.0, 0.35, 0.35, 0.05))
	s = _noise(0.25, 22.0, 0.8, 0.8)
	_tone(s, 90, 25, 0.5)
	streams.gun = _wav(s)
	s = _noise(0.9, 5.0, 0.12, 1.2)
	_tone(s, 55, 6, 0.6)
	streams.cannon = _wav(s)
	s = _noise(1.3, 3.5, 0.08, 1.6)
	_tone(s, 40, 4, 0.7)
	streams.boom = _wav(s)
	streams.rocket = _wav(_noise(0.7, 4.0, 0.6, 0.35, 0.15))
	streams.throw = _wav(_noise(0.3, 10.0, 0.2, 0.4, 0.06))
	s = _buf(0.3)
	_tone(s, 220, 10, 0.4, 0.0, false, -300)
	streams.die = _wav(_mix(s, _noise(0.2, 15.0, 0.2, 0.3)))
	streams.collapse = _wav(_noise(1.8, 2.0, 0.05, 1.8, 0.05))
	s = _noise(0.08, 50.0, 0.5, 0.25)
	_tone(s, 650, 45, 0.45)
	streams.hammer = _wav(s)
	s = _buf(0.8)
	_tone(s, 784, 5, 0.25); _tone(s, 1175, 5, 0.22, 0.12)
	streams.complete = _wav(s)
	s = _buf(0.25)
	_tone(s, 880, 14, 0.25)
	streams.ready = _wav(s)
	s = _buf(1.6)
	var notes = [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_tone(s, notes[i], 3.0 if i == 3 else 7.0, 0.16, i * 0.14, true)
		_tone(s, notes[i] * 0.5, 3.0 if i == 3 else 7.0, 0.1, i * 0.14)
	streams.fanfare = _wav(s)
	s = _buf(0.9)
	_tone(s, 440, 2.5, 0.18, 0.0, true); _tone(s, 330, 2.5, 0.18, 0.45, true)
	streams.alarm = _wav(s)
	s = _buf(0.7)
	_tone(s, 600, 4, 0.18, 0.0, false, 900); _tone(s, 900, 4, 0.12, 0.05, false, 1200)
	streams.convert = _wav(s)
	s = _buf(0.04)
	_tone(s, 1500, 80, 0.3)
	streams.click = _wav(s)
	s = _buf(3.0)
	var vic = [[523.25, 0.0], [659.25, 0.2], [783.99, 0.4], [1046.5, 0.6], [783.99, 1.0], [1046.5, 1.2]]
	for nt in vic:
		_tone(s, nt[0], 2.0, 0.15, nt[1], true)
		_tone(s, nt[0] * 0.5, 2.0, 0.1, nt[1])
	streams.victory = _wav(s)
	s = _buf(3.0)
	var dft = [[392.0, 0.0], [349.2, 0.4], [311.1, 0.8], [261.6, 1.3]]
	for nt in dft:
		_tone(s, nt[0], 1.5, 0.15, nt[1], true)
	streams.defeat = _wav(s)

func play(name: String, gain := 1.0) -> void:
	if muted or not streams.has(name) or gain <= 0.02:
		return
	var now = Time.get_ticks_msec()
	if now - _last.get(name, 0) < 45:
		return
	_last[name] = now
	for p in _players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = linear_to_db(gain * master)
			p.pitch_scale = _rng.randf_range(0.93, 1.07)
			p.play()
			return

## Plays sound events emitted by the simulation; positional ones fade with distance from the camera focus.
func handle_fx(events: Array, focus: Vector3) -> void:
	for f in events:
		if f.k != "sfx":
			continue
		if f.g:
			play(f.s, 0.9)
		else:
			var p: Vector2 = f.p
			var d = Vector2(p.x * 2.0 - focus.x, p.y * 2.0 - focus.z).length()
			if d < HEAR_RANGE:
				play(f.s, 0.75 * (1.0 - d / HEAR_RANGE))
