extends SceneTree

var inv: Node
var failures: Array[String] = []
var completed: int = 0
var event_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	inv = root.get_node("Inventory")
	root.get_node("GameManager").player = null
	inv.gold_changed.connect(func(_amount: int): event_count += 1)
	if inv.has_signal("inventory_restored"):
		inv.connect("inventory_restored", func(): event_count += 1)
	_containers()
	_numeric_and_slots()
	_plain_metadata()
	_objects_and_cycles()
	_empty_state()
	_capacity_and_required_fields()
	_check(completed == 6, "six groups completed")
	if failures.is_empty():
		print("ASHBOUND_INVENTORY_SNAPSHOT_EDGES_OK groups=6")
		quit(0)
	else:
		for failure in failures:
			printerr("SNAPSHOT_EDGE_FAIL: " + failure)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _data() -> Dictionary:
	var item: Dictionary = inv.item_database["rusty_sword"].duplicate(true)
	item["instance_id"] = "sword"
	item["quantity"] = 1
	return {"schema_version": 1, "items": [item], "equipped": {"weapon": null, "armor": null, "helmet": null, "ring": null, "amulet": null}, "gold": 50}


func _reset() -> void:
	inv.items = []
	inv.equipped = {"weapon": null, "armor": null, "helmet": null, "ring": null, "amulet": null}
	inv.gold = 73
	inv.max_capacity = 4
	event_count = 0


func _reject(data: Dictionary, label: String) -> void:
	_reset()
	var before: Dictionary = inv.get_save_data().duplicate(true)
	_check(inv.load_save_data(data) == false, label + ": rejected")
	_check(inv.get_save_data() == before, label + ": atomic rejection")
	_check(event_count == 0, label + ": silent rejection")


func _containers() -> void:
	for field in ["items", "equipped"]:
		for value in [null, 3, true, "bad"]:
			var data := _data()
			data[field] = value
			_reject(data, "container " + field)
	var data := _data()
	data["items"] = {}
	_reject(data, "items dictionary")
	data = _data()
	data["equipped"] = []
	_reject(data, "equipped array")
	for entry in [null, 3, "bad", []]:
		data = _data()
		data["items"][0] = entry
		_reject(data, "non-dictionary item")
		data = _data()
		data["equipped"]["weapon"] = entry
		if entry != null:
			_reject(data, "non-dictionary equipped record")
	completed += 1


func _numeric_and_slots() -> void:
	for value in [true, "5", -1, INF, NAN]:
		var data := _data()
		data["items"][0]["stats"]["damage"] = value
		_reject(data, "invalid stat")
	for field in ["name", "description", "icon", "faction_requirement"]:
		var data := _data()
		data["items"][0][field] = 12
		_reject(data, "invalid text field " + field)
	var data := _data()
	data["items"][0]["slot"] = "unknown"
	_reject(data, "invalid carried equipment slot")
	data = _data()
	data["items"][0]["type"] = 1
	_reject(data, "type differs from catalog")
	data = _data()
	data["items"][0]["stackable"] = true
	data["items"][0]["max_stack"] = 10
	_reject(data, "stackability differs from catalog")
	completed += 1


func _plain_metadata() -> void:
	_reset()
	var data := _data()
	data["items"][0]["metadata"] = {"maker": "Тест", "quality": 2, "marks": ["first", {"wear": 0.5}], "bound": false}
	_check(inv.load_save_data(data) == true, "plain nested metadata accepted")
	_check(inv.get_save_data() == data, "metadata retained exactly")
	data["items"][0]["metadata"]["marks"][1]["wear"] = 9.0
	_check(inv.items[0]["metadata"]["marks"][1]["wear"] == 0.5, "metadata deeply isolated")
	completed += 1


func _objects_and_cycles() -> void:
	var object := Node.new()
	for value in [object, Callable(self, "_run"), RID()]:
		var data := _data()
		data["items"][0]["metadata"] = {"nested": [value]}
		_reject(data, "non-data runtime value")
	object.free()
	var cycle: Array = []
	cycle.append(cycle)
	var data := _data()
	data["items"][0]["metadata"] = cycle
	_reject(data, "cyclic metadata")
	cycle.clear()
	var deep: Array = []
	var tail: Array = deep
	for i in range(40):
		var child: Array = []
		tail.append(child)
		tail = child
	data = _data()
	data["items"][0]["metadata"] = deep
	_reject(data, "excessively deep metadata")
	completed += 1


func _empty_state() -> void:
	_reset()
	var data := _data()
	data["items"] = []
	data["gold"] = 0
	_check(inv.load_save_data(data) == true, "empty state with zero gold valid")
	_check(inv.get_save_data() == data and event_count == 2, "empty restore exact with refresh events")
	completed += 1


func _capacity_and_required_fields() -> void:
	_reset()
	inv.max_capacity = 1
	var data := _data()
	var worn: Dictionary = data["items"][0].duplicate(true)
	worn["instance_id"] = "worn"
	data["equipped"]["weapon"] = worn
	_check(inv.load_save_data(data) == true, "full bag plus equipped item accepted")
	_check(inv.items.size() == 1 and inv.equipped["weapon"] != null, "equipment not counted as bag slot")
	_reset()
	inv.max_capacity = 0
	data["items"] = []
	_check(inv.load_save_data(data) == true, "equipped-only state with zero bag capacity")
	for field in ["value", "stackable", "quantity", "type", "id", "instance_id"]:
		data = _data()
		data["items"][0].erase(field)
		_reject(data, "required item field " + field)
	data = _data()
	var food: Dictionary = inv.item_database["bread"].duplicate(true)
	food.merge({"quantity": 1, "instance_id": "food", "slot": "weapon"}, true)
	data["equipped"]["weapon"] = food
	_reject(data, "food cannot become equipment by adding slot")
	data = _data()
	var mutable_key: Array = ["mutable"]
	var metadata: Dictionary = {}
	metadata[mutable_key] = "value"
	data["items"][0]["metadata"] = metadata
	_reject(data, "mutable metadata key cannot keep external alias")
	completed += 1
