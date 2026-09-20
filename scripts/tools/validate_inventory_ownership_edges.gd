extends SceneTree
## AshBound inventory ownership edge validation (SceneTree --script).
## Drafted by Ollama; reviewed and corrected by Codex under the owner's QA rule.
## Run: godot --headless --script scripts/tools/validate_inventory_ownership_edges.gd

var _errors: Array = []
var _completed_cases: int = 0
var _inv: Node
var _gm: Node
var _probe: Node3D
var _events: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_errors.append(msg)


func _finish() -> void:
	_check(_completed_cases == 5, "expected all 5 cases to complete (got %d) -- a script error aborted a case" % _completed_cases)
	if _errors.is_empty():
		print("ASHBOUND_INVENTORY_OWNERSHIP_EDGES_OK")
		quit(0)
	else:
		for e in _errors:
			push_error(e)
		quit(1)


func _run() -> void:
	_inv = root.get_node('Inventory')
	_gm = root.get_node('GameManager')
	if not is_instance_valid(_inv) or not is_instance_valid(_gm):
		_check(false, "autoloads Inventory/GameManager missing")
		_finish()
		return

	_probe = ProbePlayer.new()
	_probe.inv = _inv
	_inv.connect("item_equipped", _on_equipped)
	_inv.connect("item_unequipped", _on_unequipped)
	_inv.connect("item_removed", _on_item_removed)

	_reset()
	_case1_equipment_ordering()
	_reset()
	_case2_consumption_signals()
	_reset()
	_case3_reentrant_heal()
	_reset()
	_case4_missing_freed_player()
	_reset()
	_case5_ambiguous_handles()

	_inv.disconnect("item_equipped", _on_equipped)
	_inv.disconnect("item_unequipped", _on_unequipped)
	_inv.disconnect("item_removed", _on_item_removed)
	_gm.set('player', null)
	_probe.free()
	_finish()


func _reset() -> void:
	_gm.set('player', _probe)
	_inv.set('items', [])
	var eq := {}
	for slot in ['weapon', 'armor', 'helmet', 'amulet', 'ring']:
		eq[slot] = null
	_inv.set('equipped', eq)
	_inv.set('max_capacity', 50)
	_probe.strength = 10
	_probe.dexterity = 10
	_probe.base_damage = 15
	_probe.defense = 2
	_probe.current_stamina = 95.0
	_probe.max_stamina = 100.0
	_probe.current_health = 0
	_probe.heal_calls = 0
	_probe.retry_handle = {}
	_probe.retry_on_heal = false
	_probe.retry_attempts = 0
	_probe.retry_result = true
	_probe.seen_count = -1
	_events.clear()


func _make(template: String, id: String, qty: int = 1) -> Dictionary:
	var item: Dictionary = (_inv.item_database[template] as Dictionary).duplicate(true)
	item['instance_id'] = id
	item['quantity'] = qty
	return item


func _snapshot() -> Dictionary:
	var snap := {
		'items': (_inv.get('items') as Array).duplicate(true),
		'equipped': (_inv.get('equipped') as Dictionary).duplicate(true),
	}
	if is_instance_valid(_gm) and is_instance_valid(_gm.get('player')):
		var p: Node = _gm.get('player')
		for f in ['defense', 'base_damage', 'current_health', 'current_stamina']:
			if f in p:
				snap[f] = p.get(f)
	return snap


func _on_equipped(_item: Dictionary, _slot: String) -> void:
	_events.append({'type': 'equipped', 'snap': _snapshot()})


func _on_unequipped(_slot: String) -> void:
	_events.append({'type': 'unequipped', 'snap': _snapshot()})


func _on_item_removed(id: String) -> void:
	_events.append({'type': 'removed', 'id': id, 'snap': _snapshot()})


# ---------------------------------------------------------------- Case 1
func _case1_equipment_ordering() -> void:
	_check(_inv.call('get_equipped', 'armor') == {}, "C1 get_equipped armor on empty != {}")
	_check(_inv.call('get_equipped', 'unknown_slot') == {}, "C1 get_equipped unknown slot != {}")
	_check(_inv.call('unequip_slot', 'nope') == false, "C1 unequip unknown != false")
	_check(_inv.call('unequip_slot', 'helmet') == false, "C1 unequip empty slot != false")
	_check(_events.is_empty(), "C1 signals fired on no-op calls")

	var old := _make('leather_armor', 'armor_old')
	var new_item := _make('chain_mail', 'armor_new')
	_inv.set('equipped', {'weapon': null, 'armor': old, 'helmet': null, 'amulet': null, 'ring': null})
	_inv.set('items', [new_item])
	_inv.set('max_capacity', 1)
	_probe.defense = 7

	var req := {'instance_id': 'armor_new'}
	_check(_inv.call('equip_item', req) == true, "C1 equip new armor != true")
	var eq_armor: Variant = _inv.get('equipped')['armor']
	_check(is_same(eq_armor, new_item), "C1 equipped armor is not the new instance")
	_check((_inv.get('items') as Array).size() == 1, "C1 items size != 1 after swap")
	if (_inv.get('items') as Array).size() == 1:
		var bag0: Variant = (_inv.get('items') as Array)[0]
		_check(is_same(bag0, old), "C1 bag[0] is not the old armor instance")
	_check(_probe.defense == 14, "C1 defense != 14 after swap (got %s)" % _probe.defense)

	var eq_ev := _events.filter(func(e): return e['type'] == 'equipped')
	var rm_ev := _events.filter(func(e): return e['type'] == 'unequipped')
	_check(eq_ev.size() == 1, "C1 expected exactly one equipped event (got %d)" % eq_ev.size())
	_check(rm_ev.size() == 1, "C1 expected exactly one unequipped event (got %d)" % rm_ev.size())
	if eq_ev.size() == 1 and rm_ev.size() == 1:
		for ev in [eq_ev[0], rm_ev[0]]:
			var s: Dictionary = ev['snap']
			_check((s['equipped']['armor'] as Dictionary).get('instance_id') == 'armor_new', "C1 event sees old armor, not new")
			_check((s['items'] as Array).size() == 1, "C1 event must see exactly one returned item")
			if (s['items'] as Array).size() == 1:
				_check((s['items'][0] as Dictionary).get('instance_id') == 'armor_old', "C1 event snapshot bag missing old armor")
			_check(s.get('defense') == 14, "C1 event snapshot defense != 14 (sees pre-swap state)")

	var before := _snapshot()
	_check(_inv.call('unequip_slot', 'armor') == false, "C1 unequip into full bag should fail")
	var after := _snapshot()
	_check(before['items'] == after['items'], "C1 failed unequip mutated items")
	_check(before['equipped'] == after['equipped'], "C1 failed unequip mutated equipped")
	_check(_events.size() == 2, "C1 failed unequip emitted events")

	_inv.set('items', [])
	_check(_inv.call('unequip_slot', 'armor') == true, "C1 unequip into empty bag != true")
	var returned: Variant = _inv.get('equipped')['armor']
	_check(returned == null or returned == {}, "C1 armor slot not cleared")
	_check((_inv.get('items') as Array).size() == 1, "C1 items size != 1 after unequip")
	if (_inv.get('items') as Array).size() == 1:
		_check(is_same((_inv.get('items') as Array)[0], new_item), "C1 unequipped item is not the same new instance")
	_check(_probe.defense == 2, "C1 defense != 2 after unequip")
	_completed_cases += 1


# ---------------------------------------------------------------- Case 2
func _case2_consumption_signals() -> void:
	var real := _make('stamina_potion', 'stam_1')
	_probe.current_stamina = 0.0
	_probe.max_stamina = 1000.0
	_inv.set('items', [real])

	var copied := real.duplicate(true)
	copied['effect'] = {'stamina': 999}
	_check(_inv.call('use_item', copied) == true, "C2 use copied request != true")
	_check(_probe.current_stamina == 100.0, "C2 stamina not canonical 100 (got %s)" % _probe.current_stamina)
	var rm := _events.filter(func(e): return e['type'] == 'removed')
	_check(rm.size() == 1, "C2 expected one removed event (got %d)" % rm.size())
	if rm.size() == 1:
		_check(rm[0].get('id') == 'stamina_potion', "C2 removed must identify the item type, not its instance")
		var s: Dictionary = rm[0]['snap']
		_check(s.get('current_stamina') == 100.0, "C2 removed snapshot stamina != 100")
		_check((s['items'] as Array).is_empty(), "C2 removed snapshot items not empty")
	_check(_events.size() == 1, "C2 extra events after first use")

	_check(_inv.call('use_item', copied) == false, "C2 stale request reuse != false")
	_check(_events.size() == 1, "C2 stale reuse emitted a signal")

	var fresh := _make('stamina_potion', 'stam_2')
	_probe.current_stamina = 95.0
	_probe.max_stamina = 100.0
	_inv.set('items', [fresh])
	_check(_inv.call('use_item', fresh) == true, "C2 use fresh potion != true")
	_check(_probe.current_stamina == 100.0, "C2 stamina not clamped to 100 (got %s)" % _probe.current_stamina)
	var rm2 := _events.filter(func(e): return e['type'] == 'removed')
	_check(rm2.size() == 2, "C2 expected two removed events total (got %d)" % rm2.size())
	_check((_inv.get('items') as Array).is_empty(), "C2 items not fully consumed")
	_completed_cases += 1


# ---------------------------------------------------------------- Case 3
func _case3_reentrant_heal() -> void:
	var real := _make('health_potion', 'hp_1')
	_inv.set('items', [real])
	_probe.retry_on_heal = true
	_probe.retry_handle = real

	_check(_inv.call('use_item', real) == true, "C3 use health potion != true")
	_check(_probe.seen_count == 0, "C3 probe did not observe empty bag during heal (got %d)" % _probe.seen_count)
	_check(_probe.retry_attempts == 1, "C3 retry_attempts != 1 (got %d)" % _probe.retry_attempts)
	_check(_probe.retry_result == false, "C3 retry of consumed item should fail")
	_check(_probe.heal_calls == 1, "C3 heal_calls != 1 (got %d)" % _probe.heal_calls)
	_check(_probe.current_health == 50, "C3 health != 50 (got %s)" % _probe.current_health)
	_check((_inv.get('items') as Array).is_empty(), "C3 items not empty after heal")

	var rm := _events.filter(func(e): return e['type'] == 'removed')
	_check(rm.size() == 1, "C3 expected exactly one removed event (got %d)" % rm.size())
	if rm.size() == 1:
		_check(rm[0].get('id') == 'health_potion', "C3 removed must identify the item type, not its instance")
		var s: Dictionary = rm[0]['snap']
		_check(s.get('current_health') == 50, "C3 removed snapshot health != 50")
		_check((s['items'] as Array).is_empty(), "C3 removed snapshot items not empty")
	_completed_cases += 1


# ---------------------------------------------------------------- Case 4
func _case4_missing_freed_player() -> void:
	var plain := Node3D.new()
	_gm.set('player', plain)
	var hp := _make('health_potion', 'hp_x')
	var sp := _make('stamina_potion', 'sp_x')
	_inv.set('items', [hp, sp])
	var before := _snapshot()

	_check(_inv.call('use_item', hp) == false, "C4 use with plain player != false")
	_check(_inv.call('use_item', sp) == false, "C4 use stamina with plain player != false")
	var after := _snapshot()
	_check(before['items'] == after['items'], "C4 inventory changed with plain player")

	plain.free()
	# gm.player still references the freed node.
	_check(_inv.call('use_item', hp) == false, "C4 use with freed player != false")
	var after2 := _snapshot()
	_check(after['items'] == after2['items'], "C4 inventory changed with freed player")

	var armor := _make('leather_armor', 'armor_x')
	_inv.set('items', [hp, sp, armor])
	_check(_inv.call('equip_item', {'instance_id': 'armor_x'}) == true, "C4 equip with freed player != true")
	_check(_inv.call('unequip_slot', 'armor') == true, "C4 unequip with freed player != true")

	_gm.set('player', _probe)

	var bad_potion := _make('health_potion', 'hp_bad')
	bad_potion['quantity'] = 0
	_inv.set('items', [bad_potion])
	var s1 := _snapshot()
	_check(_inv.call('use_item', bad_potion) == false, "C4 qty 0 potion should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 qty 0 mutated inventory")

	bad_potion = _make('health_potion', 'hp_bad2')
	bad_potion['quantity'] = 1.5
	_inv.set('items', [bad_potion])
	s1 = _snapshot()
	_check(_inv.call('use_item', bad_potion) == false, "C4 qty 1.5 potion should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 qty 1.5 mutated inventory")

	bad_potion = _make('health_potion', 'hp_bad3')
	bad_potion['quantity'] = '1'
	_inv.set('items', [bad_potion])
	s1 = _snapshot()
	_check(_inv.call('use_item', bad_potion) == false, "C4 qty '1' potion should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 qty '1' mutated inventory")

	var bad_sword := _make('iron_sword', 'sw_bad')
	bad_sword['quantity'] = 2
	_inv.set('items', [bad_sword])
	s1 = _snapshot()
	_check(_inv.call('equip_item', {'instance_id': 'sw_bad'}) == false, "C4 qty 2 sword should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 sword qty 2 mutated inventory")

	bad_sword = _make('iron_sword', 'sw_bad2')
	bad_sword['quantity'] = 1.5
	_inv.set('items', [bad_sword])
	s1 = _snapshot()
	_check(_inv.call('equip_item', {'instance_id': 'sw_bad2'}) == false, "C4 qty 1.5 sword should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 sword qty 1.5 mutated inventory")

	bad_sword = _make('iron_sword', 'sw_bad3')
	bad_sword['quantity'] = '1'
	_inv.set('items', [bad_sword])
	s1 = _snapshot()
	_check(_inv.call('equip_item', {'instance_id': 'sw_bad3'}) == false, "C4 qty '1' sword should fail")
	_check(s1['items'] == _snapshot()['items'], "C4 sword qty '1' mutated inventory")
	_completed_cases += 1


func _case5_ambiguous_handles() -> void:
	# Both entry points must reject an ambiguous ID without selecting either record.
	for template in ['iron_sword', 'health_potion']:
		_inv.items = [_make(template, 'duplicate'), _make(template, 'duplicate')]
		var before := _snapshot()
		_check(not _inv.equip_item({'instance_id': 'duplicate'}), "C5 ambiguous equip must fail")
		_check(not _inv.use_item({'instance_id': 'duplicate'}), "C5 ambiguous use must fail")
		_check(_snapshot() == before, "C5 ambiguous handle changed inventory, equipment or stats")

	# Do not coerce malformed handle IDs or malformed stored IDs into valid strings.
	for template in ['iron_sword', 'health_potion']:
		_inv.items = [_make(template, '123')]
		for handle in [{}, {'instance_id': ''}, {'instance_id': 123}, {'instance_id': []}]:
			var before := _snapshot()
			_check(not _inv.equip_item(handle), "C5 malformed equip handle must fail")
			_check(not _inv.use_item(handle), "C5 malformed use handle must fail")
			_check(_snapshot() == before, "C5 malformed handle changed state")
		_inv.items[0]['instance_id'] = 123
		var numeric_before := _snapshot()
		_check(not _inv.equip_item({'instance_id': '123'}), "C5 stored numeric ID cannot equip")
		_check(not _inv.use_item({'instance_id': '123'}), "C5 stored numeric ID cannot be used")
		_check(_snapshot() == numeric_before, "C5 numeric stored ID changed state")
	_check(_probe.heal_calls == 0, "C5 rejected handles must not heal")
	_check(_events.is_empty(), "C5 rejected handles must not emit events")
	_completed_cases += 1


class ProbePlayer:
	extends Node3D

	var strength := 10
	var dexterity := 10
	var base_damage := 15
	var defense := 2
	var current_stamina := 95.0
	var max_stamina := 100.0
	var current_health := 0
	var heal_calls := 0

	var inv: Node
	var retry_handle: Dictionary = {}
	var retry_on_heal := false
	var retry_attempts := 0
	var retry_result := true
	var seen_count := -1


	func heal(amount: int) -> void:
		current_health += amount
		heal_calls += 1
		if retry_on_heal and heal_calls == 1:
			seen_count = inv.get_item_count('health_potion')
			retry_attempts += 1
			retry_result = inv.use_item(retry_handle)
