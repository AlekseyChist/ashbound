extends SceneTree
## Independent contract QA: reward identity, atomic snapshots and per-hero ownership.
const MAX_POINTS := 2147483647
var failures: Array[String] = []
var groups := 0
var signals := 0
var progress: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("CHARACTER_PROGRESS_FAIL: " + why)

func reject(data: Dictionary, why: String) -> void:
	var before: Dictionary = progress.get_save_data()
	var count := signals
	check(not progress.load_save_data(data), why + " rejected")
	check(progress.get_save_data() == before and signals == count, why + " atomic/no signal")

func _run() -> void:
	var script: Script = load("res://scripts/characters/character_progress.gd")
	if script == null or not script.can_instantiate():
		check(false, "progress component loads")
		quit(1)
		return
	progress = script.new()
	progress.changed.connect(func(): signals += 1)
	check(progress.get_character_data() == {"learning_points":0, "unarmed_mastery":"novice", "guard_practice_completed":false}, "new hero starts untrained/zero")
	check(progress.award_learning_points("qa_reward", 5), "data API works before joining scene")
	check(signals == 1 and progress.get_character_data().learning_points == 5, "one reward once")
	root.add_child(progress)
	for pair in [["qa_reward",5],["qa_reward",50],["",1],["Upper",1],["bad id",1],["quest.reward",1],["bad\n",1],["награда",1],["a".repeat(65),1],["zero",0],["negative",-1],["too_large",MAX_POINTS+1]]:
		var before: Dictionary = progress.get_save_data()
		var count := signals
		check(not progress.award_learning_points(pair[0],pair[1]), "invalid/repeated reward " + str(pair[0]))
		check(progress.get_save_data() == before and signals == count, "rejected award unchanged")
	check(progress.award_learning_points("a".repeat(64), 2), "64-character stable ID")
	groups += 1

	var copy: Dictionary = progress.get_save_data()
	copy.point_awards.qa_reward = 1000
	copy.learning_points = 1002
	var sheet: Dictionary = progress.get_character_data()
	sheet.learning_points = 900
	check(progress.get_character_data().learning_points == 7, "snapshots never alias live state")
	var count := signals
	check(progress.complete_guard_practice(), "practice first completion")
	check(not progress.complete_guard_practice() and signals == count+1, "practice completion idempotent")
	check(progress.get_character_data().unarmed_mastery == "novice" and progress.get_character_data().learning_points == 7, "practice is not rank/point reward")
	progress.reset_guard_practice()
	check(not progress.get_character_data().guard_practice_completed and progress.get_character_data().learning_points == 7, "lesson reset preserves point balance")
	count = signals
	progress.reset_guard_practice()
	check(signals == count, "no-op reset silent")
	groups += 1

	var valid := {"schema_version":1,"learning_points":12,"point_awards":{"quest_one":5,"quest_two":7},"guard_practice_completed":true}
	count = signals
	check(progress.load_save_data(JSON.parse_string(JSON.stringify(valid))), "JSON round trip accepted")
	check(progress.get_save_data() == valid and signals == count+1, "normalized snapshot replaces once")
	check(typeof(progress.get_save_data().learning_points) == TYPE_INT and typeof(progress.get_save_data().point_awards.quest_one) == TYPE_INT, "JSON numbers normalized")
	count = signals
	check(progress.load_save_data(valid) and signals == count, "identical restore silent")
	valid.point_awards.quest_one = 999
	check(progress.get_save_data().point_awards.quest_one == 5, "restore does not alias caller")
	check(not progress.award_learning_points("quest_one",5), "restore preserves deduplication")
	groups += 1

	var base: Dictionary = progress.get_save_data()
	for field in base.keys():
		var missing := base.duplicate(true)
		missing.erase(field)
		reject(missing, "missing " + field)
	var extra := base.duplicate(true)
	extra["mastery"] = "master"
	reject(extra, "unsupported extra mastery")
	for bad in [true,false,"12",-1,-1.0,12.5,NAN,INF,-INF,MAX_POINTS+1,1.0e30]:
		var data := base.duplicate(true)
		data.learning_points = bad
		reject(data, "invalid balance " + str(bad))
	for bad in [0,2,true,"1",1.5,NAN,INF]:
		var data := base.duplicate(true)
		data.schema_version = bad
		reject(data, "invalid version " + str(bad))
	for bad in [0,1,"true",[],{}]:
		var data := base.duplicate(true)
		data.guard_practice_completed = bad
		reject(data, "invalid practice type")
	for bad in [[],null,"ledger"]:
		var data := base.duplicate(true)
		data.point_awards = bad
		reject(data, "invalid ledger type")
	groups += 1

	for bad in [0,-1,1.5,true,"5",NAN,INF,MAX_POINTS+1]:
		var data := base.duplicate(true)
		data.point_awards.quest_one = bad
		reject(data, "invalid award " + str(bad))
	for id in ["", "Upper", "x\n", "bad id", "a".repeat(65), "é", 123]:
		var data := base.duplicate(true)
		data.point_awards = {id:12}
		reject(data, "invalid restored ID " + str(id))
	var mismatch := base.duplicate(true)
	mismatch.learning_points = 100
	reject(mismatch, "ledger total mismatch")
	var overflow := base.duplicate(true)
	overflow.learning_points = MAX_POINTS
	overflow.point_awards = {"first":MAX_POINTS,"second":1}
	reject(overflow, "sum overflow")
	var partly_valid := base.duplicate(true)
	partly_valid.point_awards = {"good":1,"bad":"11"}
	reject(partly_valid, "late validation failure")
	groups += 1

	var boundary := {"schema_version":1.0,"learning_points":float(MAX_POINTS),"point_awards":{"max_reward":float(MAX_POINTS)},"guard_practice_completed":false}
	check(progress.load_save_data(boundary), "maximum safe integer survives JSON-compatible numbers")
	count = signals
	check(not progress.award_learning_points("one_more",1) and signals == count, "overflow award rejected")
	check(progress.get_character_data().learning_points == MAX_POINTS, "maximum balance intact")
	var zero := {"schema_version":1,"learning_points":0,"point_awards":{},"guard_practice_completed":false}
	check(progress.load_save_data(zero), "zero state valid")
	for i in 1024:
		check(progress.award_learning_points("source_%d" % i,1), "bounded ledger grant")
	var full: Dictionary = progress.get_save_data()
	check(progress.load_save_data(JSON.parse_string(JSON.stringify(full))), "maximum source ledger restores")
	check(not progress.award_learning_points("overflow_source",1), "source limit prevents unloadable state")
	full.point_awards["overflow_source"] = 1
	full.learning_points = 1025
	reject(full, "oversize restored ledger")
	groups += 1

	var other: Node = script.new()
	check(other.get_character_data().learning_points == 0 and not other.get_character_data().guard_practice_completed, "distinct hero owns distinct progress")
	check(other.award_learning_points("source_0",4), "reward identity scoped per hero")
	check(progress.get_character_data().learning_points == 1024, "other hero does not change first")
	other.free()
	progress.queue_free()
	await process_frame
	groups += 1
	check(groups == 7, "all contract groups completed")
	if failures.is_empty(): print("ASHBOUND_CHARACTER_PROGRESS_OK groups=",groups)
	else: printerr("ASHBOUND_CHARACTER_PROGRESS_FAILED count=",failures.size())
	quit(0 if failures.is_empty() else 1)
