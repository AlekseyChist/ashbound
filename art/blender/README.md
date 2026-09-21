# AshBound — здания Blender / Godot

Геометрию и скрипты создаёт установленная локальная модель `qwen3.8-24k:latest` через Ollama. Codex готовит задания, проверяет исходники, запускает Blender и проверяет импорт Godot. Концепты PNG созданы встроенным ImageGen на основе арта владельца.

## Файлы

- `../concepts/buildings/` — отдельные изображения дома, башни и ворот, а также использованные промпты.
- `buildings_common.py` — подготовка материалов, экспорт и студийный рендер.
- `build_house.py`, `build_watchtower.py`, `build_gate.py` — локально созданные генераторы геометрии.
- `output/*.blend` — редактируемые исходники Blender.
- `../../assets/buildings/ashbound/*.glb` — экспорт для Godot.
- `../previews/*.png` и `*-stats.json` — рендеры и фактическая статистика геометрии.

Исходники и концепты в `art/` исключены из импорта Godot через `.gdignore`. В Godot импортируются GLB из `assets/`. Модели используют метрический масштаб: Blender Z вверх, экспорт GLB переводит вертикаль в Godot Y.

## Посмотреть результат

В Godot открыть проект `C:/Users/prost/Documents/AshBound/project.godot`. В панели файлов слева открыть `scenes/environments/building_showcase.tscn` и нажать **F6** (запустить текущую сцену). Здания в этой демонстрации появляются при запуске. **F5** запускает основную игровую сцену проекта.

- ЛКМ и движение мыши — вращать камеру.
- Колесо мыши — приблизить или отдалить.
- **1** — дом, **2** — башня, **3** — ворота.
- **0** или **R** — общий вид.

Для просмотра отдельной модели в редакторе открыть соответствующий файл из `scenes/buildings/`. Редактируемые модели Blender находятся в `art/blender/output/`.

20 сентября 2026 года все три модели собраны в Blender, импортированы в Godot, демонстрационная сцена запущена с реальным графическим выводом. Снимок: `art/previews/buildings-godot.png`. Статистика исходных моделей:

| Модель | Треугольники | Ширина × высота × глубина, м |
| --- | ---: | --- |
| Дом | 22 124 | 6,18 × 7,27 × 7,65 |
| Башня | 11 972 | 4,20 × 8,47 × 4,20 |
| Ворота | 6 028 | 7,60 × 5,11 × 1,67 |

Сцены в `scenes/buildings/` добавляют к моделям простые физические преграды; у ворот оставлен центральный проход. Это отдельный набор для проверки внешнего вида, ещё не размещённый в основном игровом мире.

Проверка Godot `scripts/tools/validate_buildings.gd` завершилась с кодом 0: `ASHBOUND_BUILDINGS_OK house=22124 watchtower=11972 gate=6028`. Проверены суммарная геометрия и размеры моделей, назначенные материалы, активные физические формы, свободный центр ворот и столкновение с опорой, наличие всех трёх зданий, камеры и окружения в демонстрационной сцене. Финальный журнал: `.tools/buildings-validation-final.log`. Снимок и отдельное интерактивное окно проверены в режиме Compatibility.

## Повторная сборка

Запускать из корня AshBound в отдельном фоновом процессе Blender, после проверки сгенерированного скрипта:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/build_house.py
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/build_watchtower.py
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/build_gate.py
```

Генераторы заменяют только свои результаты сборки. Ручные правки моделей сохранять под новым именем перед повторной генерацией. Рендер использует CPU, чтобы не конкурировать с Ollama за видеопамять.

## Следующие правки через локальную модель

Для первого двора добавлен локальный генератор `build_courtyard_props.py`, использующий тот же `buildings_common.py`. Он создаёт пять независимых моделей с пивотом на земле: `courtyard_well` (1 980 треугольников), `courtyard_dummy` (484), `courtyard_fence` (176), `courtyard_woodpile` (1 188), `courtyard_crate` (1 232). Проверены запуск Blender 5.2.2, файлы GLB/BLEND, отчёты размеров и изображения в `art/previews/`. Материалы простые, модели предназначены для первого игрового прототипа.

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python-exit-code 1 --python art/blender/build_courtyard_props.py
```

Концепт двора и исходные запросы: `art/concepts/first-courtyard/`. Как и у зданий, повторная генерация перезаписывает только результаты этого набора; ручную доработку сначала сохранить отдельно.

```powershell
node tools/ollama-godot.mjs --task-file .tools/ollama-godot/tasks/task.txt --write --blender-scripts --files-only --image art/concepts/buildings/house-v1.png --context 24576 --output-tokens 8192
```

`--blender-scripts` разрешает запись Python только внутри `art/blender/`. `--image` передаёт изображение установленной локальной модели. `--files-only` убирает ненужный запуск Godot MCP, когда задача состоит в написании файлов. Исполнитель сам не запускает shell-команды или Blender: координатор сначала читает изменения, затем запускает известный файл. Журнал авторства и вызовов инструментов: `.tools/ollama-godot/runs/`; резервные копии заменённых исходников находятся в журнале соответствующего запуска.

Для этой установленной модели оставлен обычный режим по умолчанию. Проба `--think` израсходовала 10 240 токенов на рассуждение без выдачи скрипта; для текущего процесса этот режим не рекомендуется. Длинные локальные ответы получают отдельный сетевой срок ожидания 15 минут, без прежнего пятиминутного ограничения клиента.

Это первая процедурная версия внешнего вида зданий по рисункам: формы и детали собраны из геометрии, материалы пока используют цвет и шероховатость. Это не автоматическое точное восстановление фотографии и не финальные PBR-ассеты. Интерьеры, открывание дверей, подъём на башню, текстурные атласы и LOD требуют следующих отдельных задач.

Документация: [экспорт glTF из Blender](https://docs.blender.org/api/main/bpy.ops.export_scene.html), [форматы 3D-сцен Godot](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).
