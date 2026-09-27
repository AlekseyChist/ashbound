# Реквизит трактира (TAVERN-03)

14 моделей и ткань для ковров с [Poly Haven](https://polyhaven.com), лицензия [CC0](https://polyhaven.com/license). Скачаны 25 сентября 2026 в glTF 1K. [Источники и MD5 оригиналов](sources.json).

Для телефона модели облегчены скриптом `art/blender/optimize_props.py`: сетка сокращена примерно до 1500 треугольников, текстуры уменьшены до 512 пикселей, результат сохранён в `.glb`. JPG/PNG рядом с моделями извлекает импорт Godot. Оригиналы хранятся локально в `local/assets-src/polyhaven/`, в Git их нет.

Расстановка: `scripts/world/inn_dressing.gd`. Ковры — плоскости с тонированной `fabric_pattern_05`. Каждый источник света в трактире и домах деревни висит или стоит в виде `wooden_lantern_01`.

Каркас крыши изнутри (ROOF-FRAME-01, 27 сентября): обшивка — текстура [brown_planks_04](https://polyhaven.com/a/brown_planks_04) (Poly Haven, CC0, 1K) в `roof/`; стропила, коньковый брус, затяжки, бабки и подкосы — брусья из дуба самого трактира (`inn_dressing.gd`, `_roof_frame`).
