extends SceneTree
## PLAYER-WORLD-01B: the courtyard lesson as data. Sound data (stages, links, fallbacks,
## EN/RU keys) and the tracker walks the same transitions the hard-coded lesson had.
const Quest: QuestData = preload("res://data/quests/courtyard_lesson.tres")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("QUEST_DATA_FAIL " + label)

func catalog_keys(path: String) -> Dictionary:
	var keys := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("msgid \""): keys[line.trim_prefix("msgid \"").trim_suffix("\"")] = true
	return keys

func run() -> void:
	var ids := {}
	for stage in Quest.stages:
		check(not ids.has(stage.id), "unique stage " + stage.id)
		ids[stage.id] = true
		if stage.counter != &"":
			check(stage.counter_total > 0 and ids.has(stage.counter_next_stage) or Quest.stage_index(stage.counter_next_stage) >= 0, "counter of %s leads to a stage" % stage.id)
	check(Quest.stages.size() == 7 and Quest.stages[-1].completed, "seven stages, the last one completes the lesson")
	var fallback := {}
	for line in Quest.lines:
		for stage_id in line.stages: check(ids.has(stage_id), "line stage %s exists" % stage_id)
		if line.next_stage != &"": check(ids.has(line.next_stage), "next stage %s exists" % line.next_stage)
		if line.stages.is_empty() and line.requires_flag == &"" and line.forbids_flag == &"": fallback[line.speaker] = true
	for speaker in [&"innkeeper", &"woodpile", &"watchman"]: check(fallback.has(speaker), "%s always has a reply" % speaker)
	for language in ["en", "ru"]:
		var keys := catalog_keys("res://localization/%s.po" % language)
		var needed := [Quest.title_key]
		for stage in Quest.stages: needed.append(stage.objective_key)
		for line in Quest.lines:
			needed.append(line.line_key)
			if line.name_key != "": needed.append(line.name_key)
		for key in needed: check(keys.has(key), "%s has %s" % [language, key])
	# The hard-coded lesson (0.24.3): speaker -> line and stage, step by step.
	var t := QuestTracker.new(Quest)
	var walk := [
		[&"woodpile", "COURTYARD_DIALOGUE_WOOD_BEFORE", 0], [&"watchman", "COURTYARD_DIALOGUE_GUARD_OTHER", 0],
		[&"innkeeper", "COURTYARD_DIALOGUE_HOST_JOB", 1], [&"innkeeper", "COURTYARD_DIALOGUE_HOST_REMIND", 1],
		[&"woodpile", "COURTYARD_DIALOGUE_WOOD_TAKEN", 2], [&"woodpile", "COURTYARD_DIALOGUE_WOOD_ALREADY", 2],
		[&"innkeeper", "COURTYARD_DIALOGUE_HOST_REWARD", 3], [&"innkeeper", "COURTYARD_DIALOGUE_HOST_AFTER", 3],
		[&"watchman", "COURTYARD_DIALOGUE_GUARD_LESSON", 4], [&"watchman", "COURTYARD_DIALOGUE_GUARD_REMIND", 4],
	]
	for step in walk:
		var line: DialogueLineData = t.line_for(step[0])
		check(line != null and line.line_key == step[1], "%s says %s" % [step[0], step[1]])
		if line != null: t.apply_line(line)
		check(t.stage_index == step[2], "after %s the stage is %d (got %d)" % [step[1], step[2], t.stage_index])
	check(t.flags[&"reward_claimed"], "the reward is remembered")
	check(t.journal_entry().params == {"hits": 0, "total": 3}, "practice shows hits/total")
	check(not t.add_count(&"other"), "other counters do not count")
	check(not t.add_count(&"dummy_hits") and not t.add_count(&"dummy_hits"), "two strikes are not enough")
	check(t.add_count(&"dummy_hits") and t.finish_counter() and t.stage_index == 5, "the third strike moves to the report")
	check(not t.counts(&"dummy_hits") and not t.add_count(&"dummy_hits") and t.counters[&"dummy_hits"] == 3, "no strikes after practice")
	var report: DialogueLineData = t.line_for(&"watchman")
	check(report.line_key == "COURTYARD_DIALOGUE_GUARD_REPORT" and report.effects == [&"complete_guard_practice"], "the report completes the guard practice")
	t.apply_line(report)
	check(t.stage_index == 6 and t.journal_entry().completed, "the lesson completes")
	check(t.line_for(&"innkeeper").line_key == "COURTYARD_DIALOGUE_HOST_AFTER", "innkeeper after the lesson")
	t.stage_index = 2
	t.flags[&"reward_claimed"] = true
	check(t.line_for(&"innkeeper").line_key == "COURTYARD_DIALOGUE_HOST_ACCEPTED", "a claimed reward is not paid twice")
	t.reset()
	check(t.stage_index == 0 and t.counters[&"dummy_hits"] == 0 and not t.flags[&"reward_claimed"], "reset starts over")
	# Village copy (D-085/086): same stages as the courtyard (saved index), lines that tell the way.
	var village: QuestData = load("res://data/quests/village_lesson.tres")
	# D-092: the village adds the wolves at the barn between the practice report and the end.
	var expected: Array = []
	for stage in Quest.stages: expected.append(stage.id)
	expected.insert(expected.size() - 1, &"wolves")
	expected.insert(expected.size() - 1, &"wolves_report")
	check(village.id == &"village_lesson" and village.stages.size() == expected.size(), "village lesson: the courtyard stages plus the wolves")
	for i in range(mini(village.stages.size(), expected.size())):
		check(village.stages[i].id == expected[i], "village stage %d is %s" % [i, expected[i]])
		if i < Quest.stages.size() - 1:
			check(village.stages[i].counter == Quest.stages[i].counter, "village stage %d counts like the courtyard" % i)
	for language in ["en", "ru"]:
		var keys := catalog_keys("res://localization/%s.po" % language)
		for stage in village.stages: check(keys.has(stage.objective_key), "%s has %s" % [language, stage.objective_key])
		for line in village.lines: check(keys.has(line.line_key), "%s has %s" % [language, line.line_key])
	var v := QuestTracker.new(village)
	check(v.line_for(&"innkeeper").line_key == "VILLAGE_LESSON_HOST_JOB", "the village hostess tells where the woodpile is")
	v.stage_index = 6
	check(v.line_for(&"watchman").line_key == "VILLAGE_LESSON_GUARD_WOLVES_REMIND", "the watchman reminds about the wolves")
	v.stage_index = 7
	var paid: DialogueLineData = v.line_for(&"watchman")
	check(paid.line_key == "VILLAGE_LESSON_GUARD_WOLVES_PAID" and paid.effects == [&"pay_wolf_reward"] and paid.next_stage == &"done", "the watchman pays for the wolves")
	v.stage_index = 8
	check(v.journal_entry().completed and v.line_for(&"watchman").line_key == "VILLAGE_LESSON_GUARD_AFTER", "the watchman points to the forest inn after the lesson")
	print("QUEST_DATA_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
