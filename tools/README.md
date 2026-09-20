# Восстановление локальных инструментов AshBound

В Git хранятся исходник исполнителя `ollama-godot.mjs`, документы, генераторы Blender и результаты их работы. Каталог `.tools/` остаётся локальным: в нём установленные программы, зависимости, задания, журналы и резервные копии. Глобальные настройки Codex и веса Ollama не переносятся через Git.

Текущая проверенная конфигурация: Godot 4.7.2 для Windows, Blender 5.2.2, локальный Ollama с уже установленной `qwen3.8-24k:latest`. Переустановка или скачивание модели не происходит автоматически. Машинные пути перечислены в [GODOT_CONNECTION.md](../GODOT_CONNECTION.md).

## Зависимости подключения

В `tools/godot-mcp/` сохранены точные манифест и lock-файл установленного Godot MCP 0.1.1, а также исходник проверки. Это шаблон для восстановления локальной папки, не второй работающий сервер.

После нового клонирования из корня репозитория, при установленном Node.js/npm:

```powershell
New-Item -ItemType Directory -Force -Path .tools/godot-mcp | Out-Null
New-Item -ItemType File -Force -Path .tools/.gdignore | Out-Null
Copy-Item -LiteralPath tools/godot-mcp/package.json,tools/godot-mcp/package-lock.json,tools/godot-mcp/verify-connection.mjs -Destination .tools/godot-mcp/
npm ci --prefix .tools/godot-mcp
```

`npm ci` скачивает зависимости; эти команды в рамках сохранения контрольной точки не переустанавливали текущую рабочую среду. Godot разместить по ожидаемому мостом пути `.tools/godot/Godot_v4.7.2-stable_win64.exe`. Blender и Ollama устанавливаются отдельно. Если путь или версия меняются, обновить конфигурацию подключения явно.

Проверка после восстановления:

```powershell
node .tools/godot-mcp/verify-connection.mjs C:/Users/prost/Documents/AshBound
node tools/ollama-godot.mjs --help
```

Аргумент пути в первой команде заменить на фактическую папку клона. Регистрация MCP-сервера в Codex зависит от локального пути к Node, серверу и Godot; сведения о текущей регистрации находятся в `GODOT_CONNECTION.md`. Изменять чужие глобальные настройки автоматически не нужно.

## Поручение локальной модели

Создать UTF-8 файл задания с целью, разрешёнными файлами и проверкой результата, затем:

```powershell
node tools/ollama-godot.mjs --task-file .tools/ollama-godot/tasks/task.txt --write --files-only --context 24576 --output-tokens 8192
```

Для Blender добавить `--blender-scripts` и при необходимости `--image art/concepts/buildings/house-v1.png`. Флаг `--files-only` исключает запуск сервера MCP, но установленный SDK всё равно требуется для загрузки текущего исходника моста. Без `--write` модель работает только на чтение. Новые модели не скачиваются, облачный вариант не используется, прямого shell/Git у исполнителя нет.

Не запускать ответ модели как команду оболочки. Читать созданные файлы, проверять изменения и запускать известный проверенный скрипт средствами Blender/Godot. Логи авторства и резервные копии: `.tools/ollama-godot/runs/`.
