extends Node
## Sfx: короткие звуки. Если в res://audio/ лежит <имя>.ogg или <имя>.wav — играется файл,
## иначе — сгенерированный плейсхолдер. Все вызовы идут через шины SFX/UI.

const MIX_RATE := 22050
const POOL_SIZE := 8
## имя -> [частота Гц, длительность с, доля шума 0..1, шина]
const SOUNDS := {
	"hit_wood": [180.0, 0.07, 0.5, "SFX"],
	"hit_stone": [320.0, 0.06, 0.8, "SFX"],
	"hit_metal": [880.0, 0.09, 0.3, "SFX"],
	"hit_soft": [140.0, 0.08, 0.9, "SFX"],
	"break": [120.0, 0.18, 0.9, "SFX"],
	"crit": [1320.0, 0.15, 0.1, "SFX"],
	"craft_done": [660.0, 0.12, 0.0, "UI"],
	"claim": [990.0, 0.25, 0.0, "UI"],
	"unlock": [523.0, 0.35, 0.0, "UI"],
	"click": [700.0, 0.03, 0.2, "UI"],
	"error": [110.0, 0.15, 0.2, "UI"],
	"tool_break": [240.0, 0.3, 0.7, "SFX"],
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch_jitter: float = 0.08) -> void:
	if not SOUNDS.has(sound) or DisplayServer.get_name() == "headless":
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _stream(sound)
	p.bus = SOUNDS[sound][3]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStream = null
	for ext in ["ogg", "wav"]:
		var path := "res://audio/%s.%s" % [sound, ext]
		if ResourceLoader.exists(path):
			s = load(path)
			break
	if s == null:
		s = _generate(SOUNDS[sound])
	_streams[sound] = s
	return s


## Тон с экспоненциальным затуханием, смешанный с шумом. 16 бит моно.
func _generate(spec: Array) -> AudioStreamWAV:
	var freq: float = spec[0]
	var length: float = spec[1]
	var noise: float = spec[2]
	var n := int(MIX_RATE * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 6.0 / length)
		var tone := sin(TAU * freq * t) * (1.0 - noise)
		var v := (tone + rng.randf_range(-1.0, 1.0) * noise) * env * 0.5
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
