## InventorySystem - Система инвентаря ASHBOUND
## Управляет предметами, экипировкой, золотом
extends Node

signal item_added(item: Dictionary)
signal item_removed(item_id: String)
signal item_equipped(item: Dictionary, slot: String)
signal item_unequipped(slot: String)
signal gold_changed(amount: int)
signal inventory_restored()

# Слоты экипировки
const SLOT_WEAPON = "weapon"
const SLOT_ARMOR = "armor"
const SLOT_HELMET = "helmet"
const SLOT_RING = "ring"
const SLOT_AMULET = "amulet"

# Типы предметов
enum ItemType { WEAPON, ARMOR, CONSUMABLE, QUEST, MISC }

# Инвентарь (массив предметов)
var items: Array = []
var max_capacity: int = 50

# Экипировка
var equipped: Dictionary = {
	SLOT_WEAPON: null,
	SLOT_ARMOR: null,
	SLOT_HELMET: null,
	SLOT_RING: null,
	SLOT_AMULET: null,
}

# Золото
var gold: int = 0

# Защита от повторного входа в денежные/торговые операции
var _trade_guard := false

# База предметов
var item_database: Dictionary = {}


func _ready() -> void:
	_init_item_database()
	print("[ASHBOUND] InventorySystem инициализирован")


func _init_item_database() -> void:
	# Оружие
	item_database["rusty_sword"] = {
		"id": "rusty_sword",
		"name": "Ржавый меч",
		"description": "Едва держится вместе, но лучше, чем ничего.",
		"type": ItemType.WEAPON,
		"slot": SLOT_WEAPON,
		"icon": "res://assets/textures/items/rusty_sword.png",
		"stats": {"damage": 8},
		"value": 5,
		"stackable": false,
	}

	item_database["iron_sword"] = {
		"id": "iron_sword",
		"name": "Железный меч",
		"description": "Надёжное оружие простого солдата.",
		"type": ItemType.WEAPON,
		"slot": SLOT_WEAPON,
		"stats": {"damage": 15},
		"value": 50,
		"stackable": false,
	}

	item_database["cultist_blade"] = {
		"id": "cultist_blade",
		"name": "Клинок культиста",
		"description": "Зазубренное лезвие, покрытое странными символами.",
		"type": ItemType.WEAPON,
		"slot": SLOT_WEAPON,
		"stats": {"damage": 18, "fire_damage": 5},
		"value": 80,
		"faction_requirement": FactionManager.FACTION_ASHEN_ORDER,
		"stackable": false,
	}

	# Броня
	item_database["leather_armor"] = {
		"id": "leather_armor",
		"name": "Кожаная броня",
		"description": "Простая защита из дублёной кожи.",
		"type": ItemType.ARMOR,
		"slot": SLOT_ARMOR,
		"stats": {"defense": 5},
		"value": 30,
		"stackable": false,
	}

	item_database["chain_mail"] = {
		"id": "chain_mail",
		"name": "Кольчуга",
		"description": "Плетёная металлическая броня.",
		"type": ItemType.ARMOR,
		"slot": SLOT_ARMOR,
		"stats": {"defense": 12},
		"value": 100,
		"stackable": false,
	}

	# Расходники
	item_database["health_potion"] = {
		"id": "health_potion",
		"name": "Зелье здоровья",
		"description": "Восстанавливает 50 здоровья.",
		"type": ItemType.CONSUMABLE,
		"effect": {"heal": 50},
		"value": 25,
		"stackable": true,
		"max_stack": 10,
	}

	item_database["stamina_potion"] = {
		"id": "stamina_potion",
		"name": "Зелье выносливости",
		"description": "Восстанавливает всю стамину.",
		"type": ItemType.CONSUMABLE,
		"effect": {"stamina": 100},
		"value": 20,
		"stackable": true,
		"max_stack": 10,
	}

	item_database["bread"] = {
		"id": "bread",
		"name": "Хлеб",
		"description": "Чёрствый, но съедобный.",
		"type": ItemType.CONSUMABLE,
		"effect": {"heal": 10},
		"value": 3,
		"stackable": true,
		"max_stack": 20,
	}

	# Квестовые предметы
	item_database["sacred_ash"] = {
		"id": "sacred_ash",
		"name": "Священный пепел",
		"description": "Пепел со священного алтаря Ордена.",
		"type": ItemType.QUEST,
		"quest_id": "order_trial_fire",
		"value": 0,
		"stackable": true,
		"max_stack": 5,
	}


# === ИНВЕНТАРЬ ===

func add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	if not item_database.has(item_id):
		push_error("[ASHBOUND] Предмет не найден: %s" % item_id)
		return false

	var template = item_database[item_id]
	var stackable: bool = template.get("stackable", false)
	var max_stack: int = 0
	if stackable:
		max_stack = int(template.get("max_stack", 0))
		if max_stack <= 0:
			push_error("[ASHBOUND] Некорректный max_stack для предмета: %s" % item_id)
			return false

	# Свободные места в существующих стаках этого предмета
	var free_in_stacks := 0
	for item in items:
		if item["id"] == item_id and stackable:
			free_in_stacks += maxi(0, max_stack - int(item.get("quantity", 1)))

	# Свободные записи инвентаря
	var free_slots := maxi(0, max_capacity - items.size())

	if stackable:
		# Недостаток после существующих стопок
		var remaining := quantity - free_in_stacks
		if remaining > 0:
			# Число необходимых новых стопок (без переполнения умножения)
			var needed_new_stacks := (remaining - 1) / max_stack + 1
			if needed_new_stacks > free_slots:
				print("[ASHBOUND] Инвентарь полон!")
				return false
	else:
		# Нестакуемые: каждый экземпляр — отдельная запись
		if quantity > free_slots:
			print("[ASHBOUND] Инвентарь полон!")
			return false

	var changed_items: Array = []

	if stackable:
		# 1) Добираем существующие стаки до max_stack
		var remaining := quantity
		for item in items:
			if remaining <= 0:
				break
			if item["id"] == item_id:
				var space = maxi(0, max_stack - int(item.get("quantity", 1)))
				if space > 0:
					var take = mini(space, remaining)
					item["quantity"] = int(item.get("quantity", 1)) + take
					remaining -= take
					changed_items.append(item)

		# 2) Остаток — новые записи по max_stack шт.
		while remaining > 0:
			var new_item = template.duplicate(true)
			new_item["quantity"] = mini(max_stack, remaining)
			new_item["instance_id"] = _generate_instance_id()
			items.append(new_item)
			remaining -= int(new_item["quantity"])
			changed_items.append(new_item)
	else:
		# Нестакуемые: каждый экземпляр — отдельная запись с quantity 1
		for i in range(quantity):
			var new_item = template.duplicate(true)
			new_item["quantity"] = 1
			new_item["instance_id"] = _generate_instance_id()
			items.append(new_item)
			changed_items.append(new_item)

	# Сигнал несёт реальные словари предметов из items
	for item in changed_items:
		item_added.emit(item)

	print("[ASHBOUND] Получен предмет: %s x%d" % [template.get("name", item_id), quantity])
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	# Сначала проверяем общее количество
	var total := 0
	for item in items:
		if item["id"] == item_id:
			total += int(item.get("quantity", 1))

	if total < quantity:
		return false

	# Списываем через несколько стаков/экземпляров
	var remaining := quantity
	for i in range(items.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var item = items[i]
		if item["id"] == item_id:
			var have := int(item.get("quantity", 1))
			var take := mini(have, remaining)
			item["quantity"] = have - take
			remaining -= take
			if item["quantity"] <= 0:
				items.remove_at(i)

	item_removed.emit(item_id)
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false

	var total := 0
	for item in items:
		if item["id"] == item_id:
			total += int(item.get("quantity", 1))
	return total >= quantity


func get_item_count(item_id: String) -> int:
	var total = 0
	for item in items:
		if item["id"] == item_id:
			total += item.get("quantity", 1)
	return total


func _generate_instance_id() -> String:
	return str(Time.get_unix_time_from_system()) + str(randi())


# === ЭКИПИРОВКА ===

func equip_item(item: Dictionary) -> bool:
	# item — это HANDLE: используем только instance_id, остальное игнорируем
	var instance_id = _get_handle_instance_id(item)
	if instance_id == "":
		return false

	# Ищем каноническую запись в items (отклоняем неоднозначные дубликаты)
	var carried: Dictionary = {}
	var found := false
	for entry in items:
		if not (entry is Dictionary):
			continue
		var entry_id = entry.get("instance_id", "")
		if entry_id is String and entry_id == instance_id:
			if found:
				return false
			carried = entry
			found = true
	if not found:
		return false

	# Предметы, только что экипированные, не являются инвентарём и не могут быть экипированы повторно
	for slot in equipped:
		if equipped[slot] == carried:
			return false

	# Валидация канонических данных
	var type = carried.get("type", -1)
	if type != ItemType.WEAPON and type != ItemType.ARMOR:
		return false

	var slot = carried.get("slot", "")
	if not (slot is String) or not equipped.has(slot):
		return false

	var raw_quantity = carried.get("quantity", 0)
	if not (raw_quantity is int) or raw_quantity != 1:
		return false

	if bool(carried.get("stackable", false)):
		return false

	# Требование фракции из канонического объекта
	if carried.has("faction_requirement"):
		if FactionManager.player_faction != carried["faction_requirement"]:
			print("[ASHBOUND] Требуется членство в фракции!")
			return false

	# Проверяем, что текущее содержимое слота корректно (чтобы не потерять данные)
	var old_item = equipped[slot]
	if old_item != null and not (old_item is Dictionary):
		push_error("[ASHBOUND] Некорректный предмет в слоте: %s" % slot)
		return false

	# Проверяем, что после замены инвентарь не переполнится:
	# входящий предмет уходит из items, а старый возвращается в items
	var final_size := items.size() - 1
	if old_item != null:
		final_size += 1
	if final_size > max_capacity:
		print("[ASHBOUND] Нет места в инвентаре!")
		return false

	# Применяем изменения: снимаем старый предмет (если есть) и экипируем новый
	var removed_old := false
	if old_item != null:
		items.append(old_item)
		equipped[slot] = null
		removed_old = true

	items.erase(carried)
	equipped[slot] = carried

	# Применяем статы ДО отправки событий
	_apply_equipment_stats()

	# События: сначала снятие (если было), затем экипирование
	if removed_old:
		item_unequipped.emit(slot)
	item_equipped.emit(carried, slot)

	print("[ASHBOUND] Экипировано: %s" % _safe_name(carried))
	return true


func unequip_slot(slot: String) -> bool:
	if not equipped.has(slot):
		return false

	var item = equipped[slot]
	if item == null:
		return false

	if items.size() >= max_capacity:
		print("[ASHBOUND] Нет места в инвентаре!")
		return false

	items.append(item)
	equipped[slot] = null

	_apply_equipment_stats()

	item_unequipped.emit(slot)
	print("[ASHBOUND] Снято: %s" % _safe_name(item))
	return true


func _apply_equipment_stats() -> void:
	if not is_instance_valid(GameManager.player):
		return

	var player = GameManager.player

	# Сбрасываем бонусы (базовые значения уже рассчитаны в player)
	var total_damage_bonus = 0
	var total_defense_bonus = 0

	for slot in equipped:
		var item = equipped[slot]
		if item == null:
			continue

		var stats = item.get("stats", {})
		total_damage_bonus += stats.get("damage", 0)
		total_defense_bonus += stats.get("defense", 0)

	# Применяем бонусы
	player.base_damage = 5 + player.strength + total_damage_bonus
	player.defense = player.dexterity / 5 + total_defense_bonus


func get_equipped(slot: String) -> Dictionary:
	if not equipped.has(slot):
		return {}
	var item = equipped[slot]
	if item == null or not (item is Dictionary):
		return {}
	return item


# === ИСПОЛЬЗОВАНИЕ ПРЕДМЕТОВ ===

func use_item(item: Dictionary) -> bool:
	# item — это HANDLE: используем только instance_id, остальное игнорируем
	var instance_id = _get_handle_instance_id(item)
	if instance_id == "":
		return false

	# Ищем каноническую запись в items (отклоняем неоднозначные дубликаты)
	var carried: Dictionary = {}
	var found := false
	for entry in items:
		if not (entry is Dictionary):
			continue
		var entry_id = entry.get("instance_id", "")
		if entry_id is String and entry_id == instance_id:
			if found:
				return false
			carried = entry
			found = true
	if not found:
		return false

	# Валидация канонических данных
	if carried.get("type", -1) != ItemType.CONSUMABLE:
		return false

	var raw_quantity = carried.get("quantity", 0)
	if not (raw_quantity is int) or raw_quantity <= 0:
		return false
	var quantity: int = raw_quantity

	# Проверяем, что игрок существует
	if not is_instance_valid(GameManager.player):
		return false

	var player = GameManager.player

	# Проверяем эффект и возможности игрока ДО удаления предмета
	var effect = carried.get("effect", {})
	if not (effect is Dictionary):
		return false

	var has_heal := false
	var has_stamina := false
	if effect.has("heal"):
		has_heal = true
		if not player.has_method("heal"):
			return false
	if effect.has("stamina"):
		has_stamina = true
		if not ("current_stamina" in player and "max_stamina" in player):
			return false

	if not has_heal and not has_stamina:
		return false

	# Снимаем снимок информации об эффекте
	var heal_value = 0
	var stamina_value = 0
	if has_heal:
		heal_value = int(effect.get("heal", 0))
	if has_stamina:
		stamina_value = int(effect.get("stamina", 0))

	# Удаляем ровно ОДИН предмет из выбранного стака
	carried["quantity"] = quantity - 1
	if carried["quantity"] <= 0:
		items.erase(carried)

	# Применяем эффект
	if has_heal:
		player.heal(heal_value)
	if has_stamina:
		player.current_stamina = minf(player.current_stamina + stamina_value, player.max_stamina)

	# Отправляем сигнал item_removed один раз после успешного применения эффекта
	item_removed.emit(str(carried.get("id", "")))

	print("[ASHBOUND] Использовано: %s" % _safe_name(carried))
	return true


func _get_handle_instance_id(handle: Dictionary) -> String:
	if not (handle is Dictionary):
		return ""
	var id = handle.get("instance_id", "")
	if not (id is String):
		return ""
	return id


func _safe_name(item: Dictionary) -> String:
	if item is Dictionary:
		return str(item.get("name", "неизвестный предмет"))
	return "неизвестный предмет"


# === ЗОЛОТО ===

func add_gold(amount: int) -> void:
	if _trade_guard or amount <= 0 or gold < 0:
		return
	if gold > 9223372036854775807 - amount:
		return
	gold += amount
	gold_changed.emit(gold)
	print("[ASHBOUND] Получено золота: %d (всего: %d)" % [amount, gold])


func remove_gold(amount: int) -> bool:
	if _trade_guard or amount <= 0 or gold < 0:
		return false
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func has_gold(amount: int) -> bool:
	if gold < 0 or amount < 0:
		return false
	return gold >= amount


# === ТОРГОВЛЯ ===

func sell_item(item: Dictionary) -> bool:
	if _trade_guard:
		return false

	var instance_id = _get_handle_instance_id(item)
	if instance_id == "":
		return false

	# Ищем единственную каноническую запись в items
	var carried: Dictionary = {}
	var found := false
	for entry in items:
		if not (entry is Dictionary):
			continue
		var entry_id = entry.get("instance_id", "")
		if entry_id is String and entry_id == instance_id:
			if found:
				return false
			carried = entry
			found = true
	if not found:
		return false

	# Предмет, присутствующий в equipped, продавать нельзя.
	# Конфликт identity определяется по корректному непустому instance_id,
	# а не сравнением словарей целиком (поддельное имя не делает дубликат другой вещью).
	for slot in equipped:
		var eq = equipped[slot]
		if not (eq is Dictionary):
			continue
		var eq_id = eq.get("instance_id", "")
		if eq_id is String and eq_id != "" and eq_id == instance_id:
			return false

	# Валидация канонических данных
	var item_id = carried.get("id", "")
	if not (item_id is String) or item_id == "":
		return false

	var raw_quantity = carried.get("quantity", 0)
	if not (raw_quantity is int) or raw_quantity <= 0:
		return false

	# Нестакуемый предмет нельзя продать с quantity != 1
	var stackable = carried.get("stackable", false)
	if not (stackable is bool) or not stackable:
		if raw_quantity != 1:
			return false

	var raw_value = carried.get("value", 0)
	if not (raw_value is int) or raw_value <= 0:
		return false

	# Проверяем переполнение баланса до списания
	if gold < 0 or gold > 9223372036854775807 - raw_value:
		return false

	# Блокируем реентерабельные вызовы на время commit + обоих сигналов
	_trade_guard = true

	# Применяем изменения атомарно
	carried["quantity"] = raw_quantity - 1
	if carried["quantity"] <= 0:
		items.erase(carried)

	gold += raw_value

	# Сигналы: сначала item_removed, затем gold_changed
	item_removed.emit(item_id)
	gold_changed.emit(gold)

	_trade_guard = false

	print("[ASHBOUND] Продано: %s (получено: %d)" % [item_id, raw_value])
	return true


func buy_item(item_id: String, price: int) -> bool:
	if _trade_guard:
		return false

	if not (item_id is String) or item_id == "":
		return false
	if price <= 0:
		return false
	if gold < 0 or gold < price:
		print("[ASHBOUND] Недостаточно золота!")
		return false

	if not item_database.has(item_id):
		# Неизвестный id — тихий отказ без push_error и без изменений
		return false

	var template = item_database[item_id]
	if not (template is Dictionary):
		return false
	var stackable: bool = template.get("stackable", false)
	var max_stack: int = 0
	if stackable:
		max_stack = int(template.get("max_stack", 0))
		if max_stack <= 0:
			return false

	# Проверяем место
	var free_in_stacks := 0
	for item in items:
		if item["id"] == item_id and stackable:
			free_in_stacks += maxi(0, max_stack - int(item.get("quantity", 1)))

	var free_slots := maxi(0, max_capacity - items.size())

	if stackable:
		if free_in_stacks < 1 and free_slots < 1:
			print("[ASHBOUND] Инвентарь полон!")
			return false
	else:
		if free_slots < 1:
			print("[ASHBOUND] Инвентарь полон!")
			return false

	# Блокируем реентерабельные вызовы на время commit + обоих сигналов
	_trade_guard = true

	# Применяем изменения атомарно; фиксируем реально изменённую запись
	var changed_entry: Dictionary = {}
	if stackable:
		# Пробуем добавить в первый неполный стек
		for item in items:
			if item["id"] == item_id:
				var space = maxi(0, max_stack - int(item.get("quantity", 1)))
				if space > 0:
					item["quantity"] = int(item.get("quantity", 1)) + 1
					changed_entry = item
					break
		if changed_entry.is_empty():
			var new_item = template.duplicate(true)
			new_item["quantity"] = 1
			new_item["instance_id"] = _generate_instance_id()
			items.append(new_item)
			changed_entry = new_item
	else:
		var new_item = template.duplicate(true)
		new_item["quantity"] = 1
		new_item["instance_id"] = _generate_instance_id()
		items.append(new_item)
		changed_entry = new_item

	gold -= price

	# Сигналы: сначала item_added (с реальной записью, без копии), затем gold_changed
	item_added.emit(changed_entry)
	gold_changed.emit(gold)

	_trade_guard = false

	print("[ASHBOUND] Куплено: %s (потрачено: %d)" % [template.get("name", item_id), price])
	return true


# === СОХРАНЕНИЕ/ЗАГРУЗКА ===

func get_save_data() -> Dictionary:
	return {
		"schema_version": 1,
		"items": _deep_copy(items),
		"equipped": _deep_copy(equipped),
		"gold": gold,
	}


func load_save_data(data: Dictionary) -> bool:
	if _trade_guard:
		return false

	var validated := _validate_save_data(data)
	if validated.is_empty():
		return false

	# Все проверки пройдены: фиксируем состояние атомарно
	_trade_guard = true
	items = validated["items"]
	equipped = validated["equipped"]
	gold = validated["gold"]
	_apply_equipment_stats()
	inventory_restored.emit()
	gold_changed.emit(gold)
	_trade_guard = false
	return true


func _validate_save_data(data: Dictionary) -> Dictionary:
	if not data.has("schema_version") or not data.has("items") or not data.has("equipped") or not data.has("gold"):
		return {}

	var version = data["schema_version"]
	if not (version is int) or version != 1:
		return {}

	var raw_items = data["items"]
	if not (raw_items is Array):
		return {}

	var raw_equipped = data["equipped"]
	if not (raw_equipped is Dictionary):
		return {}

	var raw_gold = data["gold"]
	if not (raw_gold is int) or raw_gold < 0:
		return {}

	# Проверяем количество записей до обработки каждой записи
	if raw_items.size() > max_capacity:
		return {}

	var expected_slots := [SLOT_WEAPON, SLOT_ARMOR, SLOT_HELMET, SLOT_RING, SLOT_AMULET]
	for slot in expected_slots:
		if not raw_equipped.has(slot):
			return {}
	if raw_equipped.size() != expected_slots.size():
		return {}

	var seen_ids := {}
	var new_items: Array = []
	for entry in raw_items:
		var validated_entry := _validate_save_item(entry, seen_ids)
		if validated_entry.is_empty():
			return {}
		new_items.append(validated_entry)

	var new_equipped := {}
	for slot in expected_slots:
		var value = raw_equipped[slot]
		if value == null:
			new_equipped[slot] = null
			continue
		var validated_entry := _validate_save_item(value, seen_ids)
		if validated_entry.is_empty():
			return {}
		# Экипировать можно только оружие/броню, нестакующуюся, quantity 1
		var eq_type = validated_entry.get("type", -1)
		if eq_type != ItemType.WEAPON and eq_type != ItemType.ARMOR:
			return {}
		if validated_entry.get("stackable", true):
			return {}
		if validated_entry.get("quantity", 0) != 1:
			return {}
		# Слот записи обязан совпадать со слотом назначения
		if validated_entry.get("slot", "") != slot:
			return {}
		new_equipped[slot] = validated_entry

	return {
		"items": new_items,
		"equipped": new_equipped,
		"gold": raw_gold,
	}


func _validate_save_item(entry: Variant, seen_ids: Dictionary) -> Dictionary:
	if not (entry is Dictionary):
		return {}

	var item_id = entry.get("id", "")
	if not (item_id is String) or item_id == "" or not item_database.has(item_id):
		return {}

	var template = item_database[item_id]
	if not (template is Dictionary):
		return {}

	var instance_id = entry.get("instance_id", "")
	if not (instance_id is String) or instance_id == "":
		return {}
	if seen_ids.has(instance_id):
		return {}
	seen_ids[instance_id] = true

	if not entry.has("quantity") or not entry.has("value") or not entry.has("type") or not entry.has("stackable"):
		return {}

	var quantity = entry["quantity"]
	if not (quantity is int) or quantity <= 0:
		return {}

	var value = entry["value"]
	if not (value is int) or value < 0:
		return {}

	var type = entry["type"]
	if not (type is int) or type < 0 or type >= ItemType.size():
		return {}
	if type != template.get("type", -1):
		return {}

	var stackable = entry["stackable"]
	if not (stackable is bool):
		return {}
	if stackable != template.get("stackable", false):
		return {}

	if stackable:
		# max_stack обязателен в entry, строго int > 0 и равен каталогу
		if not entry.has("max_stack"):
			return {}
		var max_stack = entry["max_stack"]
		if not (max_stack is int) or max_stack <= 0:
			return {}
		if max_stack != template.get("max_stack", -1):
			return {}
		if quantity > max_stack:
			return {}
	else:
		if quantity != 1:
			return {}

	var slot = entry.get("slot", "")
	if type == ItemType.WEAPON or type == ItemType.ARMOR:
		if stackable or quantity != 1:
			return {}
		if not (slot is String) or not equipped.has(slot):
			return {}
		if slot != template.get("slot", ""):
			return {}

	# stats/effect: при явно присутствующем ключе с null — отклоняем;
	# проверяем наличие ключа, а не ненулевое значение
	if entry.has("stats"):
		var stats = entry["stats"]
		if not (stats is Dictionary):
			return {}
		for key in stats:
			var stat_value = stats[key]
			if not _is_finite_number(stat_value) or stat_value < 0:
				return {}

	if entry.has("effect"):
		var effect = entry["effect"]
		if not (effect is Dictionary):
			return {}
		for key in effect:
			var effect_value = effect[key]
			if not _is_finite_number(effect_value) or effect_value < 0:
				return {}

	for string_key in ["name", "description", "icon", "quest_id", "faction_requirement"]:
		if entry.has(string_key) and not (entry[string_key] is String):
			return {}

	var result: Variant = _deep_copy(entry)
	if result == null or not (result is Dictionary):
		return {}
	result["quantity"] = quantity
	result["value"] = value
	result["type"] = type
	result["stackable"] = stackable
	return result


func _is_finite_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value)
	return false


func _deep_copy(value: Variant, depth: int = 0) -> Variant:
	# Отказ без ошибок движка: вход и runtime неизменны
	if depth > 32:
		return null
	if value is Dictionary:
		var result := {}
		for key in value:
			# Только значимые неизменяемые scalar-ключи; Array/Dictionary/Object/Callable/RID отклоняем
			var key_is_scalar := (key is String) or (key is StringName) or (key is int) or (key is float) or (key is bool)
			if not key_is_scalar:
				return null
			var copied_value = _deep_copy(value[key], depth + 1)
			if copied_value == null and value[key] != null:
				return null
			result[key] = copied_value
		return result
	if value is Array:
		var result: Array = []
		for element in value:
			var copied_element = _deep_copy(element, depth + 1)
			if copied_element == null and element != null:
				return null
			result.append(copied_element)
		return result
	if value is Object or value is Callable or value is RID:
		return null
	return value
