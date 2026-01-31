# Bootstrap Script и OLLAMA_MODELS в .env

## Цель

Вынести список моделей Ollama из `roles/ollama/defaults/main.yml` в `.env` для удобства конфигурации. Создать скрипт `bootstrap.sh` для провижена VM.

## Изменения

### 1. `.env.example`

Добавить секцию Ollama:

```bash
# === Ollama ===
# Список моделей через запятую (пусто = не ставить модели)
# Пример: OLLAMA_MODELS=qwen3-coder:30b,glm-4.7-flash
OLLAMA_MODELS=
```

### 2. `bootstrap.sh`

Новый скрипт в корне проекта:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Загружаем .env
if [[ -f .env ]]; then
    source .env
else
    echo "Error: .env not found. Copy from .env.example" >&2
    exit 1
fi

# Преобразуем OLLAMA_MODELS из "a,b,c" в JSON-список ["a","b","c"]
if [[ -n "${OLLAMA_MODELS:-}" ]]; then
    OLLAMA_MODELS_JSON=$(echo "$OLLAMA_MODELS" | tr ',' '\n' | jq -R . | jq -s .)
else
    OLLAMA_MODELS_JSON="[]"
fi

# Запускаем ansible-playbook с переменными из .env
ansible-playbook playbooks/site.yml \
    -e "ollama_models=${OLLAMA_MODELS_JSON}"
```

### 3. `roles/ollama/defaults/main.yml`

Заменить жёсткий список на пустой:

```yaml
---
ollama_models: []
```

## Поведение

- Если `OLLAMA_MODELS` не задан или пустой → модели не ставятся
- Если задан (например `qwen3-coder:30b,glm-4.7-flash`) → ставятся указанные модели
- Прямой запуск `ansible-playbook` без `bootstrap.sh` использует пустой список из defaults
