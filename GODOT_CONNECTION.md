# Подключение Godot к Codex

Настроено 20 сентября 2026 года.

- Движок: Godot `4.7.2.stable.official.ed1daf0bf`.
- Постоянная копия движка: `.tools/godot/Godot_v4.7.2-stable_win64.exe`.
- MCP: пакет `@coding-solo/godot-mcp` версии `0.1.1`, установлен в `.tools/godot-mcp`.
- Имя сервера в Codex: `godot`.
- Настройки: `C:/Users/prost/.codex/config.toml`.

Проверен реальный обмен по MCP: инициализация сервера, список 14 инструментов и успешный запрос версии Godot. Сервер доступен для активации после перезапуска Codex или перезапуска MCP в его настройках.

Подключение позволяет запускать редактор и игру, получать вывод запущенной через MCP игры, читать сведения о проекте, создавать и изменять сцены. Это управление через команды Godot; подключение не предоставляет изображение уже открытого редактора или его несохранённое состояние.

Проект получен из `https://github.com/AlekseyChist/ashbound.git` в `C:/Users/prost/Documents/AshBound`. Локальная ветка `main` отслеживает `origin/main`. Открывать в Godot нужно файл `project.godot` в этой папке.

Git-плагин уже включён в репозиторий: `addons/godot-git-plugin`, включая библиотеку Windows. В `project.godot` заданы `version_control/plugin_name="GitPlugin"` и `version_control/autoload_on_startup=true`. Повторная установка не нужна. Плагин добавляет интерфейс Git в редактор Godot; Codex работает с Git непосредственно.

Папка `.tools` содержит локальные инструменты. Она исключена из импорта Godot и Git. Не перемещайте её без обновления путей в настройках MCP.

Повторная проверка из папки AshBound:

```powershell
node .tools/godot-mcp/verify-connection.mjs C:/Users/prost/Documents/AshBound
codex mcp get godot
```

Источники:

- [Godot MCP — исходный проект](https://github.com/Coding-Solo/godot-mcp)
- [Настройка MCP в Codex](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

## Локальная LLM: Ollama → Godot

По требованию владельца игровой код и сцены выполняет локальная модель, а Codex координирует и проверяет. Это закреплено в `AGENTS.md`.

- Ollama `0.34.0`, адрес `http://127.0.0.1:11434`.
- Установленная модель `qwen3.8-24k:latest`, 27.3B, `Q4_K_S`, поддерживает вызовы инструментов.
- Прямой локальный исполнитель: `tools/ollama-godot.mjs`.
- Контекст запросов по умолчанию 8192 токена: проверен на RTX 4090 Laptop с 16 ГБ VRAM. Это настройка отдельных запросов; исходная модель не изменена.
- Исполнитель использует API Ollama `/api/chat` и установленный Godot MCP. Не требует перезапуска Codex и не зависит от профиля Codex CLI.
- По умолчанию доступ только для чтения. `--write` включает запись игровых файлов и MCP-инструменты создания/изменения сцен в указанном проекте. Команд оболочки, Git и облачного провайдера у исполнителя нет.
- Новые модели автоматически не скачиваются. Ошибка локальной модели не приводит к переходу на облачную.

Проверка подключения:

```powershell
node tools/ollama-godot.mjs --task "Вызови get_godot_version и get_project_info, сообщи результаты"
```

Поручение реализации:

```powershell
node tools/ollama-godot.mjs --task-file .tools/ollama-godot/tasks/task.txt --write
```

Файл задания нужно сначала создать в UTF-8: перечислить цель, разрешённые изменения и проверяемый результат. Логи и резервные копии находятся в `.tools/ollama-godot/runs/`.

Фактически проверено 20 сентября 2026 года:

1. Локальная модель вызвала `get_godot_version` и `get_project_info`, получила Godot `4.7.2.stable.official.ed1daf0bf` и 7 сцен AshBound.
2. В отдельном `.tools/ollama-godot/smoke-project` модель написала `project.godot`, создала `smoke.tscn` через `create_scene`, добавила `LocalLLMProof` через `add_node` и написала `validate_scene.gd`.
3. Координатор прочитал полученный скрипт и выполнил его в Godot. Результат: `OLLAMA_GODOT_SMOKE_OK`, код выхода 0. Существующие игровые сцены этим тестом не изменялись.

В ходе настройки Ollama также создала отдельный профиль `C:/Users/prost/.codex/ollama-launch.config.toml` и каталог моделей `C:/Users/prost/.codex/model.json`. Основной рабочий способ делегирования — прямой исполнитель выше; интеграция через Codex CLI для реализации не проверена.

Документация: [вызов инструментов Ollama](https://docs.ollama.com/capabilities/tool-calling).

## Blender → Godot

Установлен и проверен Blender `5.2.2 LTS`: `C:/Program Files/Blender Foundation/Blender 5.2/blender.exe`. Отдельный MCP-плагин Blender для этого процесса не требуется: локальная Ollama пишет Python через `tools/ollama-godot.mjs`, координатор проверяет файл и запускает его отдельным фоновым процессом Blender.

- Дополнительный флаг `--blender-scripts` разрешает Python-файлы только внутри `art/blender/`.
- `--image art/concepts/buildings/house-v1.png` передаёт рисунок локальной модели.
- `--context 24576 --output-tokens 10240` позволяет вместить рисунок, исходники и полный ответ для исправлений геометрии. Значения задаются только на этот запуск; модель не заменяется.
- Неполный ответ модели завершается ошибкой; он не превращается в запускаемую shell-команду.
- Исходники сохраняются как `.blend` в `art/blender/output/`, экспорт для Godot — `.glb` в `assets/buildings/ashbound/`.

Подробности и команды повторной сборки: [art/blender/README.md](art/blender/README.md).

Созданы дом, башня и ворота: исходники `art/blender/output/*.blend`, импортированные модели `assets/buildings/ashbound/*.glb`, сцены с физическими преградами `scenes/buildings/*.tscn`. Для просмотра открыть `scenes/environments/building_showcase.tscn` в Godot и нажать **F6**. Клавиши **1/2/3** выбирают здание, **0** возвращает общий вид; ЛКМ вращает камеру, колесо меняет масштаб. Здания появляются при запуске сцены.

При написании файлов локальной моделью можно добавить `--files-only`: тогда мост не запускает Godot MCP. Проверенный режим для длинных скриптов: `--context 24576 --output-tokens 8192`; `--think` для этой задачи не требуется. Логи исполнения и резервные копии хранятся локально в `.tools/ollama-godot/runs/`.
