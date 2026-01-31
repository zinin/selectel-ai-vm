#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загрузка переменных окружения
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "Error: .env file not found. Copy .env.example to .env and fill in values."
    exit 1
fi

# Проверка зависимостей
for cmd in jq ansible-playbook; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Преобразуем OLLAMA_MODELS из "a,b,c" в JSON-список ["a","b","c"]
if [[ -n "${OLLAMA_MODELS:-}" ]]; then
    OLLAMA_MODELS_JSON=$(echo "$OLLAMA_MODELS" | tr ',' '\n' | jq -R . | jq -s .)
else
    OLLAMA_MODELS_JSON="[]"
fi

echo "=== Bootstrap VM ==="
echo "OLLAMA_MODELS: ${OLLAMA_MODELS:-<empty>}"
echo ""

# Запускаем ansible-playbook с переменными из .env
ansible-playbook "$SCRIPT_DIR/playbooks/site.yml" \
    -e "ollama_models=${OLLAMA_MODELS_JSON}"
