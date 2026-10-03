extends Node
## D-115/D-116 (owner 3 Oct): spoken lines - English only, whatever the subtitle language.
## A line's voice is res://assets/voice/en/<KEY>@<SPEAKER_KEY>.ogg (a line several characters say) or
## <KEY>.ogg. One voice at a time; a new line or a cleared one stops it; the game's pause stops it too.
## No file: the line stays text only (Codex 137, p.7). Plays on the sound bus, not positional: speech
## stays clear in a conversation.
const FOLDER := "res://assets/voice/en/"

var world: Node
var player: AudioStreamPlayer
## Checks turn the voice off to keep their own timing.
var enabled := true
var current := ""

func configure(host: Node) -> void:
	world = host
	player = AudioStreamPlayer.new()
	player.name = "Voice"
	player.bus = host.audio.SOUND_BUS if host.get("audio") != null else &"Master"
	add_child(player)

## The voice file of a line, or "" when it has none.
func path_for(key: String, speaker_key: String = "") -> String:
	if not speaker_key.is_empty():
		var own := FOLDER + "%s@%s.ogg" % [key, speaker_key]
		if ResourceLoader.exists(own):
			return own
	var shared := FOLDER + key + ".ogg"
	return shared if ResourceLoader.exists(shared) else ""

## Seconds the line's voice lasts (0 when it has none or the voice is off).
func length_of(key: String, speaker_key: String = "") -> float:
	if not enabled:
		return 0.0
	var path := path_for(key, speaker_key)
	if path.is_empty():
		return 0.0
	var stream := load(path) as AudioStream
	return stream.get_length() if stream != null else 0.0

## Speaks the line; returns how long it lasts (0 = no voice, the line is text only).
func play(key: String, speaker_key: String = "") -> float:
	stop()
	if not enabled:
		return 0.0
	var path := path_for(key, speaker_key)
	if path.is_empty():
		return 0.0
	var stream := load(path) as AudioStream
	if stream == null:
		return 0.0
	player.stream = stream
	player.play()
	current = path
	return stream.get_length()

func stop() -> void:
	if player != null and player.playing:
		player.stop()
	current = ""

func is_speaking() -> bool:
	return player != null and player.playing

func _process(_delta: float) -> void:
	if world == null or player == null:
		return
	# Out of the window or app in the background: the voice waits with the game.
	var foreground: bool = world.get("focus_ok") != false and world.get("window_focus_ok") != false and world.get("app_active") != false
	player.stream_paused = not foreground
