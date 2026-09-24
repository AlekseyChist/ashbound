# Лесной набор для тестовой деревни

24 сентября 2026, VILLAGE-FOREST-KIT-01. Три хвойных дерева 10/8/4,5 м, валун, пень, папоротник и трава. [Сравнение с H01 в Godot](../../previews/village-forest-v1/kit-with-house.png). Это первый проверенный набор для игровой пробы, художественная приёмка владельцем впереди.

Исходная геометрия/скрипты — локальная Qwen. После одного возврата для каждого скрипта Codex исправил остаточную принадлежность ветвей/ветровые веса, отверг угловатые кроны и конический папоротник, заменил кроны пересекающимися изогнутыми плоскостями с RGBA-хвоей и исправил геометрию папоротника. Дополнение scope: мелкие растения/камень вынесены в `art/blender/village_understory.py`, чтобы избежать обрезания ответа. Самостоятельный QA и экспорт — Codex.

Хвоя создана встроенным image_gen; [точный prompt](pine-texture-prompt.txt). Исходная RGBA 1254×1254 скопирована без правки пикселей в `assets/environment/village-forest-v1/textures/pine-spray-v1.png`. Кора/камень используют сохранённые `oak.png`/`stone.png` семейства домов. Новая генерация не воспроизводится бит-в-бит; сохранённая текстура и скрипты воспроизводят набор.

Повторить из корня проекта в Blender 5.2.2:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/village_forest_kit.py
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/village_understory.py
```

`-- --no-render` пропускает PNG. Сборщики перезаписывают только собственный набор; перед ручной работой сохранить копию BLEND. BLEND исходники здесь, игровые GLB в `assets/environment/village-forest-v1`, рендеры в `art/previews/village-forest-v1`. Начало — на земле, метры, glTF конвертирует Z-up в Y-up. Деревья: Bark/Foliage, две поверхности/материала, alpha MASK 0.4, двухсторонняя хвоя; её вершинная alpha хранит вес ветра, RGB белый. Маска хвои идёт из текстуры, не из веса ветра.

QA: `python art/blender/village-forest-v1/check_kit.py` проверяет GLB/лимиты и пишет `checks.json`. Для Godot создать `qa/models`, скопировать семь GLB и H01 туда, выполнить headless import, затем `--script check.gd`; `--script compare.gd` с графическим рендером создаёт сравнение. Требуются код 0, все семь записей и отсутствие ошибок движка. Проверено Godot 4.7.2 Mobile; журнал `qa/import-check.log`. Все семь GLB повторно собраны с теми же SHA. BLEND побитовую идентичность не обещаем. 40 файлов принятого путешественника прошли прежнюю проверку целостности.

Треугольники: pine_tall 3314, spruce 3580, pine_young 2326, boulder 80, stump 44, fern 400, grass 96. Нужны группировка повторов, дистанция теней/растений и замеры прозрачного перекрытия в реальном лесу; один рендер не доказывает бюджет S23. Игровая интеграция, освещение и новая APK — следующие отдельные шаги.
