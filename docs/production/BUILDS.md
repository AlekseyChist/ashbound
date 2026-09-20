# Локальные сборки первого двора

Настройки экспорта находятся в `export_presets.cfg`. Это отладочные сборки прототипа, не публикация в магазин и не основание обновлять `main`.

## Подготовка

- Godot 4.7.2 и шаблоны **той же версии**, Windows x86_64 и Android.
- Для Android — Android SDK и JDK. На машине владельца есть SDK из Android Studio и встроенный JDK21; Godot поддерживает версии выше рекомендуемого JDK17.
- Пути SDK/JDK и отладочный ключ задаются в локальных Editor Settings Godot; машинные пути и ключи не переносить в репозиторий.
- Исходники Blender, рисунки и документы исключены из импорта через `.gdignore`; экспорт выбирает игровую сцену и её зависимости.

Источники: [шаблоны Godot4.7.2](https://godotengine.org/download/archive/4.7.2-stable/), [экспорт Android](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).

## Экспорт

В Godot: **Проект → Экспорт**, выбрать `Windows Courtyard` или `Android Courtyard`, экспортировать с отладкой. Выходные файлы по умолчанию находятся в `.tools/builds/`, они не хранятся в Git.

Для воспроизводимого запуска из корня проекта:

```powershell
New-Item -ItemType Directory -Force -Path .tools/builds/windows,.tools/builds/android | Out-Null
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-debug 'Windows Courtyard' '.tools/builds/windows/AshBound.exe'
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-debug 'Android Courtyard' '.tools/builds/android/ashbound-courtyard.apk'
```

Android-приложение прототипа имеет отдельный идентификатор `org.ashbound.courtyard`, ARM64. Установка и запуск проверяются на подключённом устройстве; успешный экспорт сам по себе не доказывает работоспособность на телефоне.

## Приёмка

Фактические результаты, версии сборок, устройства и ограничения записывать в [STATUS](STATUS.md). Проверить запуск, весь учебный маршрут, столкновения, недопустимый порядок действий и повторный старт. Для сенсорного управления отдельно проверить удержание движения с одновременным действием, отпускание пальца, уход пальца за пределы управления и возврат приложения из фона.

Первый короткий запуск на OnePlus не заменяет проверку Samsung S23, двадцатиминутный тепловой тест и последующий выбор минимальных требований. Сохранение задания и сменная экипировка находятся в отдельных задачах плана.

20 сентября исходная APK и обновлённая сборка установлены на OnePlus 13T; для одного из обновлений система телефона потребовала подтверждение, владелец его дал. Не отключать защиту установки ради автоматизации. Текущая версия Android: `0.2.0-third-person`, код 2, тот же пакет. Проверенные хэши и результаты новой камеры находятся в [THIRD_PERSON_CHECKS.md](THIRD_PERSON_CHECKS.md); исходного двора — в [COURTYARD_CHECKS.md](COURTYARD_CHECKS.md).
