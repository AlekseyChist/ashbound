## HUD - Интерфейс игрока ASHBOUND
## Отображает здоровье, стамину, время суток, подсказки взаимодействия
class_name HUD
extends CanvasLayer

# Ссылки на элементы UI
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/HealthLabel
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/StaminaBar
@onready var stamina_label: Label = $MarginContainer/VBoxContainer/StaminaBar/StaminaLabel

@onready var time_label: Label = $TimeContainer/TimeLabel
@onready var day_label: Label = $TimeContainer/DayLabel

@onready var interaction_hint: Label = $InteractionHint
@onready var level_label: Label = $LevelContainer/LevelLabel
@onready var exp_bar: ProgressBar = $LevelContainer/ExpBar

# Цвета для времени суток
var time_colors = {
	"morning": Color(1.0, 0.9, 0.6),
	"afternoon": Color(1.0, 1.0, 0.9),
	"evening": Color(1.0, 0.6, 0.4),
	"night": Color(0.6, 0.7, 1.0)
}


func _ready() -> void:
	# Скрываем подсказку взаимодействия
	interaction_hint.visible = false

	# Подключаемся к сигналам игрока
	_connect_player_signals()

	# Подключаемся к GameManager для времени
	GameManager.hour_changed.connect(_on_hour_changed)

	# Обновляем время сразу
	_update_time_display()


func _connect_player_signals() -> void:
	# Ждём пока игрок будет доступен
	await get_tree().process_frame

	var player = GameManager.player
	if player:
		player.health_changed.connect(_on_health_changed)
		player.stamina_changed.connect(_on_stamina_changed)
		player.interaction_available.connect(_on_interaction_available)
		player.interaction_unavailable.connect(_on_interaction_unavailable)
		player.experience_gained.connect(_on_experience_gained)
		player.level_up.connect(_on_level_up)

		# Инициализация начальных значений
		_on_health_changed(player.current_health, player.max_health)
		_on_stamina_changed(player.current_stamina, player.max_stamina)
		_update_level_display(player.level, player.experience, player.experience_to_next)


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [current, maximum]

	# Меняем цвет при низком здоровье
	if current < maximum * 0.25:
		health_bar.modulate = Color(1.0, 0.3, 0.3)
	elif current < maximum * 0.5:
		health_bar.modulate = Color(1.0, 0.7, 0.3)
	else:
		health_bar.modulate = Color.WHITE


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_label.text = "%d / %d" % [int(current), int(maximum)]

	# Меняем цвет при низкой стамине
	if current < maximum * 0.2:
		stamina_bar.modulate = Color(0.7, 0.7, 0.7)
	else:
		stamina_bar.modulate = Color.WHITE


func _on_interaction_available(target: Node) -> void:
	if target.has_method("get_interaction_text"):
		interaction_hint.text = "[E] " + target.get_interaction_text()
	else:
		interaction_hint.text = "[E] Взаимодействовать"
	interaction_hint.visible = true


func _on_interaction_unavailable() -> void:
	interaction_hint.visible = false


func _on_hour_changed(new_hour: int) -> void:
	_update_time_display()


func _update_time_display() -> void:
	var hour = GameManager.current_hour
	var minute = int(GameManager.current_minute)
	var day = GameManager.current_day
	var period = GameManager.get_time_period()

	# Формат времени
	time_label.text = "%02d:%02d" % [hour, minute]
	day_label.text = "День %d" % day

	# Цвет по времени суток
	time_label.modulate = time_colors.get(period, Color.WHITE)

	# Иконка времени суток
	match period:
		"morning":
			time_label.text = "☀ " + time_label.text
		"afternoon":
			time_label.text = "☀ " + time_label.text
		"evening":
			time_label.text = "🌅 " + time_label.text
		"night":
			time_label.text = "🌙 " + time_label.text


func _on_experience_gained(amount: int) -> void:
	var player = GameManager.player
	if player:
		_update_level_display(player.level, player.experience, player.experience_to_next)

		# Показываем текст +XP (можно добавить анимацию)
		_show_xp_popup(amount)


func _on_level_up(new_level: int) -> void:
	var player = GameManager.player
	if player:
		_update_level_display(new_level, player.experience, player.experience_to_next)

		# TODO: Показать эффект повышения уровня
		print("[HUD] Уровень повышен до %d!" % new_level)


func _update_level_display(level: int, exp: int, exp_next: int) -> void:
	level_label.text = "Ур. %d" % level
	exp_bar.max_value = exp_next
	exp_bar.value = exp


func _show_xp_popup(amount: int) -> void:
	# Простой popup для XP (можно улучшить анимацией)
	var popup = Label.new()
	popup.text = "+%d XP" % amount
	popup.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	popup.position = Vector2(get_viewport().size.x / 2 - 50, get_viewport().size.y / 2)
	add_child(popup)

	# Анимация исчезновения
	var tween = create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 1.0)
	tween.tween_callback(popup.queue_free)
