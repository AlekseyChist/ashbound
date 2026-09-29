extends Node3D
## AUDIO-TEARDOWN-01: repeat creation/removal of the real inn hearth, including a paused scene.
const Dressing = preload("res://scripts/world/inn_dressing.gd")
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("HEARTH_AUDIO_FAIL ", label)

func run() -> void:
	var empty := Dressing.new()
	add_child(empty)
	empty.queue_free()
	await get_tree().create_timer(.05).timeout
	check(not is_instance_valid(empty), "unbuilt dressing exits safely")
	var capture: AudioEffectCapture
	if OS.get_cmdline_user_args().has("--verify-audio"):
		capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(0, capture)
	var listener := AudioListener3D.new()
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	add_child(listener)
	listener.make_current()
	for cycle in 3:
		var dressing := Dressing.new()
		dressing.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(dressing)
		if capture != null: capture.clear_buffer()
		dressing._hearth_fire()
		var sound := dressing.get_node("HearthSound") as AudioStreamPlayer3D
		await get_tree().create_timer(.5).timeout
		check(sound.playing, "cycle %d: hearth plays" % cycle)
		check(sound.stream is AudioStreamOggVorbis and sound.stream.loop, "looped Ogg remains")
		check(sound.max_distance == 16.0 and sound.unit_size == 2.5 and sound.volume_db == -7.0, "audible settings unchanged")
		if capture != null:
			var samples := capture.get_buffer(capture.get_frames_available())
			var peak := 0.0
			for sample in samples: peak = maxf(peak, sample.length())
			print("HEARTH_AUDIO_PCM cycle=", cycle, " frames=", samples.size(), " peak=", peak)
			check(samples.size() > 0 and peak > .0001, "cycle %d: non-silent PCM output" % cycle)
		var playback: WeakRef = weakref(sound.get_stream_playback())
		get_tree().paused = cycle == 1
		dressing.queue_free()
		await get_tree().create_timer(.5, true).timeout
		get_tree().paused = false
		check(not is_instance_valid(dressing), "cycle %d: scene freed" % cycle)
		check(playback.get_ref() == null, "cycle %d: playback released" % cycle)
	print("HEARTH_AUDIO_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
