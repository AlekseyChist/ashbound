extends Node
## INN-BRAWL-01 (D-092, chapter #141 edition 2, D-111/112/113): the morning after the first night in
## the forest inn, in the real world scene with the real combat session. Checks the staging after sleep
## (nobody fights before the words), the lines and the three answers, "I just came down" and the offer
## again at the table, a strike before any word, the fight (enemies on the hero, the brute on the
## daughter, a real hero strike, the first one to give up takes the others along, the ringleader's
## threat), the daughter out until the end, winning and being knocked out (one bed for good, no second
## fight), leaving the hall in the middle (starts over), the inn file (old files, restart), the
## innkeeper's menu without rent, and sleeping in the owned bed.
const Scene = preload("res://scenes/world/world.tscn")
const PATH := "user://inn-brawl-qa.cfg"
var world: Node3D
var inn: Node3D
var lodging: Node
var brawl: Node
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("BRAWL_FAIL ", label)

func settle(seconds: float = .3) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

## Waits until the condition holds or the time is up; returns whether it held.
func wait_for(condition: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()

func put_hero(local: Vector3) -> void:
	world.player.global_position = inn.to_global(local)
	world.player.velocity = Vector3.ZERO
	world.player.stop_input()

## A clean inn file and no scene running; the next night starts the morning anew.
func fresh() -> void:
	if not brawl.men.is_empty():
		for role in brawl.men:
			brawl.session.enemies.erase(brawl.men[role])
			brawl.men[role].queue_free()
		brawl.men.clear()
	brawl.phase = "off"
	if world.choices.is_open:
		world.choices.visible = false
		world.choices.is_open = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	lodging.use_save(PATH)
	world.hud.clear_message()
	await settle(.2)

## Rents the bed, sleeps the night upstairs; the scene is staged downstairs after it.
func sleep_night() -> void:
	lodging.rented = true
	put_hero(Vector3(1.7, 4.0, -3.2))
	await settle(.3)
	world.atmosphere.set_hour(21.0)
	await lodging.sleep()

func run() -> void:
	world = Scene.instantiate()
	add_child(world)
	await settle(.8)
	inn = world.inn
	lodging = world.lodging
	brawl = world.brawl
	check(inn != null and brawl != null, "the inn and the morning scene exist")
	brawl.line_time = 0.15
	var quest: QuestTracker = world.lesson.quest
	var stage_before: int = quest.stage_index
	quest.stage_index = world.lesson.LessonQuest.stage_index(&"done")
	var purse: Node = get_node("/root/Inventory")
	purse.remove_gold(purse.gold)
	purse.add_gold(5)
	await check_old_files()
	await check_staging()
	await check_answers()
	await check_win()
	await check_owned_bed(purse)
	await check_leave_and_first_strike()
	await check_daughter_out_and_knockout()
	quest.stage_index = stage_before
	purse.remove_gold(purse.gold)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var result := "PASS" if failures.is_empty() else "FAIL"
	print("INN_BRAWL_RESULT %s checks=%d failures=%d" % [result, checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func check_old_files() -> void:
	var config := ConfigFile.new()
	config.set_value("inn", "rented", false)
	config.set_value("inn", "nights", 1)
	config.save(PATH)
	lodging.use_save(PATH)
	check(lodging.brawl == "pending" and not lodging.owned, "an old file with a night slept: the morning still waits")
	config.set_value("inn", "nights", 0)
	config.save(PATH)
	lodging.use_save(PATH)
	check(lodging.brawl == "none", "an old file without a night: nothing waits")
	config.set_value("inn", "owned", true)
	config.set_value("inn", "brawl", "pending")
	config.save(PATH)
	lodging.use_save(PATH)
	check(lodging.owned and lodging.brawl == "done", "an owned bed means the scene is over")
	config.set_value("inn", "owned", "yes")
	config.set_value("inn", "brawl", 7)
	config.save(PATH)
	lodging.use_save(PATH)
	check(not lodging.owned and lodging.brawl == "none", "damaged values fall back safely (no night slept: nothing waits)")
	await fresh()

func check_staging() -> void:
	check(lodging.brawl == "none" and brawl.phase == "off", "a fresh file: no scene")
	await sleep_night()
	check(lodging.brawl == "pending" and brawl.phase == "staged", "after the night the scene waits downstairs")
	check(brawl.men.size() == 3 and brawl.daughter != null, "three men and the daughter are in the hall")
	var homes_ok := true
	for role in brawl.men:
		var man: Node3D = brawl.men[role]
		homes_ok = homes_ok and inn.contains(man.global_position) and not man.engaged
	check(homes_ok, "the men stand in the hall, not engaged")
	check(inn.contains(brawl.daughter.global_position), "the daughter stands in the hall")
	var floor_y: float = inn.global_position.y + brawl.FLOOR
	check(absf(brawl.men["leader"].global_position.y - floor_y) < .2, "the men stand on the floor, not on the roof (%.2f)" % (brawl.men["leader"].global_position.y - floor_y))
	world._update_prompt()
	check(world.hud._objective_key == "INN_OBJECTIVE_BRAWL", "the objective sends the hero down")
	var saved := ConfigFile.new()
	check(saved.load(PATH) == OK and saved.get_value("inn", "brawl") == "pending", "the waiting scene is saved")
	# Upstairs nobody moves on the hero.
	await settle(1.0)
	check(brawl.phase == "staged" and brawl.hero_hits == 0 and brawl.men["leader"].state in ["idle", "return"], "upstairs the scene keeps waiting")

func check_answers() -> void:
	put_hero(Vector3(-1.5, .5, 0.5))
	check(await wait_for(func(): return brawl.phase == "intro", 2.0), "coming down into the hall starts the lines")
	check(world.hud._message_key == "INN_BRAWL_LEADER_ASK", "the ringleader asks about the lodgers first (%s)" % world.hud._message_key)
	var menu: CanvasLayer = world.choices
	check(await wait_for(func(): return menu.is_open, 3.0), "after the lines the answers open")
	check(menu._ids == [&"step_in", &"pay_up", &"just_came"], "three answers (%s)" % str(menu._ids))
	check(menu.line.text == Localization.text("INN_BRAWL_DAUGHTER_HINT"), "the daughter's quiet word comes with them")
	check(not world.is_input_available(), "the hero waits while choosing")
	world._update_prompt()
	menu.choose(&"just_came")
	await settle(.2)
	check(brawl.phase == "waiting" and world.hud._message_key == "INN_BRAWL_DAUGHTER_STAIRS", "\"I just came down\": no fight, the daughter's answer")
	check(not brawl.men["leader"].engaged and not lodging.owned, "no fight and no bed for standing by")
	# Standing by the stairs nothing more happens; at the table the answers are offered again.
	var leader: Node3D = brawl.men["leader"]
	await settle(.6)
	check(not menu.is_open and brawl.phase == "waiting", "not offered again while the hero stands back")
	world.player.global_position = leader.global_position - inn.global_basis.x * 1.5 + Vector3.UP * .3
	check(await wait_for(func(): return menu.is_open, 2.0), "back at the table the answers are offered again")
	check(menu.line.text == Localization.text("INN_BRAWL_DAUGHTER_AGAIN"), "with the daughter's second word")
	var gold: int = get_node("/root/Inventory").gold
	menu.choose(&"pay_up")
	await settle(.2)
	check(brawl.phase == "fight" and world.hud._message_key == "INN_BRAWL_LEADER_EVERYONE", "\"Pay and leave\" starts the fight")
	check(get_node("/root/Inventory").gold == gold, "no coins are taken")
	check(brawl.men["brute"].opponent == brawl.daughter and brawl.daughter.target == brawl.men["brute"], "the brute and the daughter take each other on")
	world._update_prompt()
	check(world.interact_button.text != Localization.text("COURTYARD_ACTION_TALK") or not world.inn_keeper_in_reach(), "the innkeeper does not talk during the fight")

func check_win() -> void:
	brawl.ko_hits = 999
	var leader: CharacterBody3D = brawl.men["leader"]
	# The fight runs: the men go for the hero, the daughter strikes the brute.
	check(await wait_for(func(): return leader.state in ["chase", "windup", "recovery"], 3.0), "the ringleader comes at the hero")
	check(await wait_for(func(): return brawl.daughter.strikes > 0, 6.0), "the daughter strikes the brute")
	check(await wait_for(func(): return brawl.hero_hits > 0 or brawl.session._contacts > 0, 6.0), "the men's blows reach the hero")
	# A real strike of the hero: facing the ringleader within reach.
	leader.cancel_attack()
	var to_leader: Vector3 = leader.global_position - world.player.global_position
	to_leader.y = 0
	world.player.global_position = leader.global_position - to_leader.normalized() * 1.1 + Vector3.UP * .05
	world.player.facing_direction = to_leader.normalized()
	await get_tree().physics_frame
	var before: int = leader.hits_received
	brawl.session.hero_strike()
	check(leader.hits_received == before + 1 or leader.state == "flee", "the hero's strike lands on the ringleader")
	# The youngster gives up first and takes the others along.
	var young: CharacterBody3D = brawl.men["young"]
	while young.state != "flee" and young.state != "gone":
		young.receive_hit()
	await settle(.1)
	check(world.hud._message_key == "INN_BRAWL_ENOUGH", "the first one to give up: \"Enough. Let's go.\"")
	var brute: CharacterBody3D = brawl.men["brute"]
	check(brute.flee_after_hits == brute.hits_received + 1 or brute.state in ["flee", "gone"], "the others go after one more blow")
	leader.receive_hit()
	await settle(.1)
	check(leader.state == "flee" and world.hud._message_key == "INN_BRAWL_LEADER_THREAT", "the ringleader leaves with the threat")
	if brute.state != "flee" and brute.state != "gone":
		brute.receive_hit()
	check(await wait_for(func(): return brawl.phase == "after", 6.0), "all three gone: the fight is won")
	check(lodging.owned and lodging.brawl == "done" and brawl.outcome == "won", "the bed is the hero's for good")
	var saved := ConfigFile.new()
	check(saved.load(PATH) == OK and saved.get_value("inn", "owned") == true and saved.get_value("inn", "brawl") == "done", "the owned bed is saved before the closing lines")
	check(await wait_for(func(): return brawl.phase == "done", 4.0), "the closing lines end the scene")
	check(brawl.men.is_empty() and not brawl.session.enemies.any(func(e): return not is_instance_valid(e) or str(e.name).begins_with("Moneylender")), "the men are gone from the world and the combat session")
	check(inn.to_local(brawl.daughter.global_position).distance_to(brawl.DAUGHTER_AFTER) < .6, "the daughter works by the bar afterwards")

func check_owned_bed(purse: Node) -> void:
	lodging.owned = false
	lodging.brawl = "none"
	lodging.load_state()
	check(lodging.owned and lodging.brawl == "done", "after a restart the bed is still the hero's")
	world._update_prompt()
	check(world.hud._objective_key == "INN_OBJECTIVE_MORNING", "the objective moves on after the scene")
	put_hero(Vector3(2.0, .5, -1.5))
	world.player.facing_direction = inn.global_basis.x
	await settle(.3)
	world.inn_talk.flags[&"greeted"] = true
	world.interact()
	await settle(.1)
	var menu: CanvasLayer = world.choices
	check(menu.is_open and not menu._ids.has(&"rent"), "the innkeeper does not rent an owned bed (%s)" % str(menu._ids))
	menu.choose(&"leave")
	await settle(.1)
	var gold: int = purse.gold
	await sleep_night()
	check(lodging.owned and not lodging.rented and lodging.brawl == "done" and brawl.phase == "done", "sleeping keeps the owned bed, no second fight")
	check(purse.gold == gold and brawl.men.is_empty(), "no charge and nobody waits downstairs")

func check_leave_and_first_strike() -> void:
	await fresh()
	await sleep_night()
	put_hero(Vector3(-1.5, .5, 0.5))
	check(await wait_for(func(): return world.choices.is_open, 4.0), "a new morning: the answers open")
	world.choices.choose(&"step_in")
	await settle(.2)
	check(brawl.phase == "fight" and world.hud._message_key == "INN_BRAWL_LEADER_LANDLORD", "\"Step away from her\" starts the fight")
	brawl.men["leader"].receive_hit()
	await settle(.2)
	# Out of the door in the middle of the fight: it starts over from before it.
	put_hero(Vector3(0.0, .5, 14.0))
	check(await wait_for(func(): return brawl.phase == "waiting", 2.0), "leaving the hall puts the scene back before the fight")
	check(brawl.men["leader"].hits_received == 0 and not brawl.men["leader"].engaged and brawl.hero_hits == 0, "the men stand at their table again, unhurt")
	check(not brawl.daughter.down and brawl.daughter.target == null and not lodging.owned, "the daughter is back, no bed yet")
	var saved := ConfigFile.new()
	check(saved.load(PATH) == OK and saved.get_value("inn", "brawl") == "pending", "the file still says the morning waits")
	# A blow before any word is an answer too.
	put_hero(Vector3(-1.5, .5, 0.5))
	await settle(.2)
	brawl.men["young"].receive_hit()
	check(await wait_for(func(): return brawl.phase == "fight", 1.0), "a strike before any word starts the fight")

func check_daughter_out_and_knockout() -> void:
	# The hero keeps out of the brute's way: the brute beats the daughter, she goes to the bar.
	brawl.ko_hits = 999
	var daughter: CharacterBody3D = brawl.daughter
	check(await wait_for(func(): return daughter.down, 25.0), "left alone with the brute the daughter is out (%d blows)" % daughter.landed)
	check(daughter.state == "out" and brawl.men["brute"]._foe() == world.player, "she leaves the fight; the brute turns on the hero")
	check(await wait_for(func(): return inn.to_local(daughter.global_position).distance_to(brawl.DAUGHTER_OUT) < .8, 10.0), "she goes to the bar and stays there")
	check(brawl.phase == "fight", "the fight is not lost because she is out")
	# Knocked out: the hero stands in the open hall, the three leave, he comes to on the bed.
	put_hero(Vector3(1.8, .5, 1.8))
	brawl.ko_hits = brawl.hero_hits + 2
	check(await wait_for(func(): return brawl.phase == "after", 15.0), "enough blows knock the hero out")
	check(await wait_for(func(): return brawl.phase == "done", 8.0), "the scene ends after the hero comes to")
	check(brawl.outcome == "knocked_out" and lodging.owned and lodging.brawl == "done", "knocked out, the bed is still his (D-113)")
	var bed: Vector3 = lodging.bed_position()
	check(Vector2(world.player.global_position.x - bed.x, world.player.global_position.z - bed.z).length() < 1.5 and world.player.global_position.y > bed.y - .5, "the hero comes to on the bed upstairs")
	check(lodging._veil.color.a < .01, "the screen is clear again")
	check(brawl.men.is_empty(), "the three have left")
