# Проба кулачной техники: цельные кадры

22 сентября 2026. Рисунки подготовлены Codex встроенным ImageGen; игровой сборщик и подключение пишет локальная `qwen3.8-24k:latest`. Это отдельная сцена сравнения стойки и удара COMBAT-01. Художественная приёмка владельца ещё требуется.

Каждый новый PNG — исходный ответ генератора, фактический размер по заголовку файла **1254×1254 RGBA**, четыре клетки 627×627. Порядок: замах, контакт, продолжение движения, возврат. Пиксели после генерации не редактировались. Рюкзак нарисован внутри каждого полного кадра. Боковой вид зеркалируется только в этой безоружной пробе; это не разрешение зеркалить асимметричное оружие.

| Файл | Ответ ImageGen (`exec-….png`) |
| --- | --- |
| novice-side.png | a321fcce-6991-4ffb-b9d5-317c7cf44d25 |
| novice-back.png | 86cc643a-1f1b-4eab-9906-9b264162bb22 |
| novice-front.png | a55c91d1-4e0e-41ab-ac82-80ba7b51b8a4 |
| novice-side-pack.png | e67ddbcf-28ea-4879-a29a-a8ce2320abc3 |
| novice-back-pack.png | 798b8887-a5f8-4581-8ee1-e9f9e7a36d13 |
| novice-front-pack.png | bdf8029c-24af-438c-81ba-ae10c0caaa5f |

Локальные оригиналы: `C:/Users/prost/.codex/generated_images/01a0c777-66ec-7b93-a2f0-b5ed8c8b2466/`.

## Задания генератору

Боковой новичок: за основу личности и стиля взят `../traveler-v1.png`. Новый прозрачный лист 2×2, безопасные поля и четыре полные фигуры, взгляд вправо. Размашистый замах с рукой позади корпуса, широкий удар, избыточный разворот с наклоном, открытый возврат без боксёрской защиты. Вторая рука остаётся низко. Сохранить лицо, волосы, бороду, длинный коричневый жилет, бежевую рубаху, тёмные штаны и сапоги. Без оружия, рюкзака, подписей, направляющих и напольных теней. Запрошено 1024×1024; генератор вернул 1254×1254, ресурсы используют фактический размер.

Спина и лицо: фазы и раскладка из `novice-side.png`, соответствующие `../traveler-back-v1.png` и `../traveler-front-v1.png` — образцы ракурса. Запрошены 1280×1280, четыре клетки 640×640, одинаковая последовательность, нижние опоры около 606/1246 и поля не менее 30 пикселей. Спина строго от камеры, лицо к камере; удар правой рукой и низкая свободная рука. Новые ракурсы не должны менять фазу или превращать новичка в собранного боксёра.

Для каждого варианта рюкзака использовался соответствующий новый лист без рюкзака как точная цель и цельный вариант из `../painted-backpack/` как образец сумки. Передано следующее задание плюс указание целевого ракурса:

> Use case: precise-object-edit, whole-character painted sprite variant. Image 1 is the exact edit target; preserve its 1280x1280 canvas, exact 2x2 four-pose layout, every character's body geometry, feet and foot baselines, head, hairstyle, clothes, arms, hands, punch phases and camera angle. Image 2 is only the backpack design reference: small worn brown leather traveler backpack with flap, brass buckle, shoulder straps and short grey bedroll strapped horizontally along its bottom. Paint that backpack naturally WORN on the back in EACH of the four full-body poses of Image1. Integrate shoulder straps, contact shadows, wrinkles, and occlusion into the entire pose. The pack follows torso rotation and bending; do not paste a floating accessory. At front camera angle only shoulder straps and tiny appropriate edge of pack may be visible behind shoulder; no backpack on chest. Keep every arm and leg and low non-striking hand unchanged, preserve body size even if pack adds width. Never mirror or shift any pose or change phase. Each output cell remains a finished whole-character illustration, not an accessory layer. Genuine alpha transparency, no text, no guides, no floor shadow, no additional figures. Background stays transparent. Do not redesign face, costume or lighting. Save at same dimensions as target.

## Ресурсы

`scripts/tools/build_fist_preview_frames.gd` создаёт четыре SpriteFrames. У новичка новый удар и прежний открытый покой; у обученного — прежний компактный удар, его первая поза используется для стойки. Общие ходьба, бег и жест кармана переиспользованы. Это не законченный набор защиты или боевой работы ног.

Обрезка и выравнивание задаются только `AtlasTexture.region/margin`. Масштаб нового удара рассчитывается один раз для каждого ракурса по телу без рюкзака и применяется ко всем фазам обеих версий. Смена техники не меняет игровые интервалы контакта, восстановления или мастерство героя. Исходные SpriteFrames путешественника сборщик не перезаписывает.
