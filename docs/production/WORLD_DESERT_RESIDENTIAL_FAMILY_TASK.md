# WORLD-DESERT-RESIDENTIAL-FAMILY — ограниченная задача

Основание: прямое поручение владельца 14 октября 2026, PDF141/plan_desert.py.
База: dev27c2099; ветка codex/desert-residential-family.
Исполнитель и единственный writer: Codex, прямое разрешение владельца.
Результат: четыре новые самостоятельные модели нативного размера и canonical сцены:
d_home_6x5, d_home_7x6, d_home_6x6, d_poor_home_6x5; масштаб1.
Обычные дома — д/с; бедный саманный вариант — к/пр. Назначения рабочие, geometry only.

Разрешены только12новых файлов: build_desert_residential_family.py;
четыре одноимённых GLB и четыре tscn; desert_residence.gd;
validate_desert_residential_family.gd; эта карточка (до150строк).
QA/BLEND/PNG/JSON/логи: local/qa/desert-residential-family (ignored).
Не менять D-H8×6, старые ассеты/runtime/мир/планировку/лор.
Не запускать Qwen/Ollama/Claude, не коммитить/публиковать/сливать и не писать другим.

Опоры: AGENTS, STYLE_REFERENCE, принятые build_desert_house.py,
d_courtyard_house.tscn/runtime и village_door.gd; D-P/D-baths палитра.
Перед реализацией прочитать фактические сигнатуры дверей, visibility/light guards.
Толстая охристая саманная стена, плоская крыша/парапет, затенённый вход.
Интерьер: деревянная взрослая кровать длиной≥2м, тонкий тюфяк/шерсть;
стол/табурет/кувшин/полка/сундук и открытый проход, двор только при достаточном месте.
Все полы/стены/крыша с настоящими коллизиями; никаких современных белых кушеток.

Проверки Codex независимым проходом: минимальный fixture, импортированные вершины/bounds,
размеры из frozenconstants или GLBextras trackedsource/assets, без старых localfacts.
Капсула≥1.75м/.3м:15legs на вариант; пол модели mask1, внешний groundlayer16.
Дверь с обеих сторон, sweep/occupiedguard, roofcollision, свет/headclearance,
sleep/occupied/openinteriorguards по принятому контракту.
Native фасад/задняя сторона/четыре стороны/интерьер/ночь; D-H с теми же camera/sun.
Лично осмотреть PNG, исправить holes/floating/blockedprops.
Blender5.2/Godotconsole main.tools; фоновые процессы скрытые, остановка толькоownedPID.

Карточка заполнена до реализации. Исходники/интерфейсы прочитаны.
Не готовность города: посадка, весь маршрут/соседи/кампания, APK/S23/FPS отдельно.

## Воспроизведение без прежнего local

Генератор: Blender5.2 --background --factory-startup --python-exit-code 1
--python art/blender/world-architecture-v1/build_desert_residential_family.py.
База размеров заморожена в SPECS валидатора:6×5/7×6/6×6/бедный6×5.
Тест читает реальные vertices, GLBextras и importedcolliders, не JSON-отчёты.
Создать пустой проект в local/qa/desert-residential-family/fixture, безautoload.
project.godot: config_version=5; секция[rendering]: renderer/rendering_method="gl_compatibility";
секция[display]: window/size/viewport_width=1280, window/size/viewport_height=960.
Скопировать с сохранением res-путей только:
- четыре новые GLB/tscn; desert_residence.gd; этот validate_desert_residential_family.gd;
- scripts/world/village_door.gd;
- assets/props/tavern-v1/wooden_lantern_01.glb;
- assets/audio/village-v1/door-creak.ogg и door-close.ogg;
- дляnativeсравнения: d_courtyard_house.glb/.tscn и courtyard_house_surface.gd.
Godot4.7.2console main/.tools/godot: --headless --path FIXTURE --editor --quit.
Проверка: --headless --path FIXTURE --fixed-fps 60
--script res://scripts/tools/validate_desert_residential_family.gd.
Native: убрать --headless, добавить --resolution 1280x960 и после -- указать --native.
Все процессы запускаются скрыто; PID/log сохраняются в локальной папке задачи.
Выход должен быть0, failures=[], без SCRIPT ERROR/ошибок движка в полном журнале.

## Архитектура и интеграционный интерфейс

Стены0.4м, пол0, нижняя опора−0.24м; нижняя поверхность кровли2.82м.
Габарит целиком внутри книжного пятна; верх3.55м, бедный вариант3.52м.
Малые дома однокомнатные, без дополнительного двора за пределами участка.
Вход+Z, створка углублена на0.65м от переднего края; проём1.4×2.35м.
ResidenceContract содержитnativefootprint/variant/entry/bedlength; масштаб1.
Кровати2.1×1.12м, тонкий соломенный тюфяк2м, шерстяное покрывало.
Бедный дом: более грубый/тёмный саман, без каменной крышной обвязки,
одна полка, простой сундук без железных обвязок, узкое окно со ставнями.
Canonicalсцены уже включаютruntime, физику иVillageDoor; не добавлять вторую дверь.
Мир может вызывать set_interior_visible(enabled, occupied=false)
и set_interior_lights_enabled(enabled). Пол/крыша/стены/коллизии не спят.
При открытой/движущейся двери илиoccupied скрытие отклоняется.
Свет спит далее45м; открывание восстанавливает спрятанный интерьер.
Здесь sleep означаетскрытие далёкогоинтерьера; механикисна/торговли/NPC не добавлены.

## Фактическая проверка Codex, 14 октября 2026

Blender5.2.2; Godot4.7.2, Windows, compatibility/NVIDIA RTX4090Laptop.
Минимальныйfixture создан из перечисленных игровых файлов; autoload/старыеlocal не нужны.
60физическихучастков (15накаждый), капсула1.75м/r0.3м PASS; headless exit0.
Пол принадлежитмодели наmask1; внешняяземля layer16. Верхкрыши3.10м,
капсулаопираетсянанеё; контактс потолком2.82м проверен отдельно.
Обе стороныдвери, закрытыйвход, sweptobstacle/actor, возврат, moving/open/occupiedguards PASS.
38collision_shapes на вариант (включая7VillageDoor и1lanterncontact),15visual_meshes вGLB.
Лампа выше2м, подвес достигаетперекрытия; near/far/override/sleep проверены.
42 итоговых PNG: шесть внешних ракурсов, три внутренних и ночь каждого дома;
D-H с теми же camera/sun. Native exit0, полныйstderr пустой, failures[].
Осмотреныnativeкадры: исправленыcoplanarмерцание стены/крыши и опораполок.
Новыеочевидныеholes/floating/blockedprops на итоговыхкадрах не найдены.
Текстуры — уже лицензированные village-house-materials-v1, встроенывGLB безновыхкопий.

| GLB | байт | tri | полныйгабарит X×Y×Z, м |
| --- | ---: | ---: | --- |
| d_home_6x5 | 1739068 | 3724 | 6×3.79×5 |
| d_home_7x6 | 1751820 | 3946 | 7×3.79×6 |
| d_home_6x6 | 1751808 | 3946 | 6×3.79×6 |
| d_poor_home_6x5 | 1729224 | 3576 | 6×3.76×5 |

ПолныеSHA/вершины/bounds/bytes/tri/failures вlocal/qa/desert-residential-family/metrics.json.
Исходныеfailedпрогоны сохраненыlocal: позициявдугедвери, затем устаревшиепутевые
точки послеуглублениявхода и невернаяожидаемаявысотаконтакта с потолком.
Ожидаемые60legs/реальныйпол/roof/guards не ослаблялись; итогfailures[].
Модулинепосаженывгород. Игровойгерой/камера/соседи/ночьвмире/APK/S23/FPS,
производительностьтеневойлампы и художественнаяоценкавладельца остаютсяотдельно.
Новые файлы:12, из них бинарных:4 — четыре непосредственно используемых игровыеGLB.
Старыеигровыефайлы неизменены; коммитов/push/PR/слияний/сообщений нет.
Родитель Codex уточнил арт: тёмная шерсть с фактурой, конструктивная деревянная перемычка заменяет кладку; оконные рамы перенесены внутрь проёмов, устранено совпадение поверхностей. Все исходные габариты сохранены. Собственный свежий минимальный проект local/qa/desert-parent-clean: headless/native оба60legs, failures[]. Осмотрены сводки40кадров и отдельные крупные детали, сравнение с D-H при одинаковых камере/солнце. Актуальные метрики/SHA — parent-native-r2.log иlocal/qa/desert-parent-clean/local/qa/desert-residential-family/metrics.json, прежнийproof.json относится к передаче до этих правок. Точный коммит ещё требует ревью Claude, полный город/APK/FPS не приняты.

Claude177 передал генератор локальной Qwen1bc104b (его поправка: разрыв балок над передней дверью). Codex проверил diff, экспортировал4 GLB в Blender5.2 exit0 и обновил независимые ожидания: бедному циновка без кровати, рельеф≤0,30м, высота навеса4,445м/лестницы3,70м. Изолированные headless и native:60 физических проходов сохранены; оба exit1 по четырём превышениям водостоков (0,32м вместо0,30м), других ошибок сценариев нет. 42 новых native-кадра вlocal/qa/desert-parent-clean/local/qa/desert-residential-family. Арт-возврат Claude: водостоки укоротить; навес должен читаться тростником, а не светлой плитой; прямоугольные тёмные заплаты заменить читаемым облупившимся саманом. Эта промежуточная редакция НЕ принята, PR остаётся draft; повтор после передачи исправленного генератора.
