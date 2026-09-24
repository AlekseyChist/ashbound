# Материалы земли деревни — CC0

24 сентября 2026, VILLAGE-SURFACES-01. Исходные 1K JPG извлечены/скачаны без изменения байт; [прямые URL, авторы и SHA](sources.json).

- **Forest Ground 04** — Rob Tuytel (Photography, Processing), Rico Cilliers (Minor Adjustment), [Poly Haven](https://polyhaven.com/a/forest_ground_04). Diffuse, OpenGL Normal, Roughness. Физический тайл 3.2 м. [Лицензия CC0](https://polyhaven.com/license).
- **Grass001** — Lennart Demes / [ambientCG](https://ambientcg.com/view?id=Grass001). Color, OpenGL Normal, Roughness, из бесплатного Grass001_1K-JPG.zip. Тайловый участок примерно 1.4×1.4 м. [Лицензия CC0](https://docs.ambientcg.com/license/).

CC0 разрешает коммерческое использование и включение в проект; обязательная атрибуция авторами не требуется. Эти добровольные кредиты сохраняются для происхождения материалов. [Полный текст CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en).

Godot: mipmaps, VRAM compression, анизотропная фильтрация. Карты цвета декодируются sRGB; нормали и шероховатость — данные. Shader использует деталь относительно измеренных средних RGB в линейном пространстве и текущую палитру деревни; исходные JPG не перекрашиваются. Это настройка игрового материала, не редактирование изображения. Шесть карт, без displacement/новой геометрии/новых коллизий.

Воспроизведение: файлы из sources.json должны совпадать SHA256; `village_surface_catalog.gd` связывает ресурсы, `village_ground.gdshader` задаёт смешивание и физический масштаб. `detail_enabled=false` — только сравнение с прежним видом в QA. Настройки исходников героя и окружающего света не меняются.
