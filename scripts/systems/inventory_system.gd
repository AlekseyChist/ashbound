## InventorySystem - Система инвентаря ASHBOUND
## Управляет предметами, экипировкой, золотом
extends Node

signal item_added(item: Dictionary)
signal item_removed(item_id: String)
signal item_equipped(item: Dictionary, slot: String)
signal item_unequipped(slot: String)
signal gold_changed(amount: int)

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
	if not item_database.has(item_id):
		push_error("[ASHBOUND] Предмет не найден: %s" % item_id)
		return false

	var template = item_database[item_id]

	# Проверяем стакающиеся предметы
	if template.get("stackable", false):
		# Ищем существующий стак
		for item in items:
			if item["id"] == item_id:
				var max_stack = template.get("max_stack", 99)
				var can_add = mini(quantity, max_stack - item.get("quantity", 1))
				if can_add > 0:
					item["quantity"] = item.get("quantity", 1) + can_add
					quantity -= can_add
					item_added.emit(item)

				if quantity <= 0:
					return true

	# Проверяем место
	if items.size() >= max_capacity:
		print("[ASHBOUND] Инвентарь полон!")
		return false

	# Создаём новый предмет
	var new_item = template.duplicate(true)
	new_item["quantity"] = quantity
	new_item["instance_id"] = _generate_instance_id()

	items.append(new_item)
	item_added.emit(new_item)

	print("[ASHBOUND] Получен предмет: %s x%d" % [new_item["name"], quantity])
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(items.size() - 1, -1, -1):
		var item = items[i]
		if item["id"] == item_id:
			if item.get("stackable", false):
				item["quantity"] = item.get("quantity", 1) - quantity
				if item["quantity"] <= 0:
					items.remove_at(i)
					item_removed.emit(item_id)
			else:
				items.remove_at(i)
				item_removed.emit(item_id)
			return true
	return false


func has_item(item_id: String, quantity: int = 1) -> bool:
	var total = 0
	for item in items:
		if item["id"] == item_id:
			total += item.get("quantity", 1)
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
	var slot = item.get("slot", "")
	if slot == "":
		return false

	# Проверяем требования
	if item.has("faction_requirement"):
		if FactionManager.player_faction != item["faction_requirement"]:
			print("[ASHBOUND] Требуется членство в фракции!")
			return false

	# Снимаем текущий предмет
	if equipped[slot] != null:
		unequip_slot(slot)

	# Экипируем
	equipped[slot] = item
	items.erase(item)

	# Применяем статы
	_apply_equipment_stats()

	item_equipped.emit(item, slot)
	print("[ASHBOUND] Экипировано: %s" % item["name"])
	return true


func unequip_slot(slot: String) -> bool:
	if equipped[slot] == null:
		return false

	if items.size() >= max_capacity:
		print("[ASHBOUND] Нет места в инвентаре!")
		return false

	var item = equipped[slot]
	items.append(item)
	equipped[slot] = null

	_apply_equipment_stats()

	item_unequipped.emit(slot)
	print("[ASHBOUND] Снято: %s" % item["name"])
	return true


func _apply_equipment_stats() -> void:
	if not GameManager.player:
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
	return equipped.get(slot, {})


# === ИСПОЛЬЗОВАНИЕ ПРЕДМЕТОВ ===

func use_item(item: Dictionary) -> bool:
	if item["type"] != ItemType.CONSUMABLE:
		return false

	if not GameManager.player:
		return false

	var effect = item.get("effect", {})

	if effect.has("heal"):
		GameManager.player.heal(effect["heal"])

	if effect.has("stamina"):
		GameManager.player.current_stamina = minf(
			GameManager.player.current_stamina + effect["stamina"],
			GameManager.player.max_stamina
		)

	# Удаляем использованный предмет
	remove_item(item["id"], 1)

	print("[ASHBOUND] Использовано: %s" % item["name"])
	return true


# === ЗОЛОТО ===

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
	print("[ASHBOUND] Получено золота: %d (всего: %d)" % [amount, gold])


func remove_gold(amount: int) -> bool:
	if gold < amount:
		return false

	gold -= amount
	gold_changed.emit(gold)
	return true


func has_gold(amount: int) -> bool:
	return gold >= amount


# === ТОРГОВЛЯ ===

func sell_item(item: Dictionary) -> bool:
	var value = item.get("value", 0)
	if value <= 0:
		return false

	if remove_item(item["id"], 1):
		add_gold(value)
		return true
	return false


func buy_item(item_id: String, price: int) -> bool:
	if not has_gold(price):
		print("[ASHBOUND] Недостаточно золота!")
		return false

	if add_item(item_id):
		remove_gold(price)
		return true
	return false


# === СОХРАНЕНИЕ/ЗАГРУЗКА ===

func get_save_data() -> Dictionary:
	return {
		"items": items,
		"equipped": equipped,
		"gold": gold,
	}


func load_save_data(data: Dictionary) -> void:
	items = data.get("items", [])
	equipped = data.get("equipped", {
		SLOT_WEAPON: null,
		SLOT_ARMOR: null,
		SLOT_HELMET: null,
		SLOT_RING: null,
		SLOT_AMULET: null,
	})
	gold = data.get("gold", 0)
	_apply_equipment_stats()
