# Bootstrap Script и OLLAMA_MODELS Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Создать скрипт `bootstrap.sh` для провижена VM и вынести список моделей Ollama в `.env`

**Architecture:** Скрипт `bootstrap.sh` читает `.env`, преобразует `OLLAMA_MODELS` из строки с запятыми в JSON-массив и передаёт в `ansible-playbook` через `-e`. Если `OLLAMA_MODELS` пустой — модели не ставятся.

**Tech Stack:** Bash, jq, Ansible

---

### Task 1: Обновить .env.example

**Files:**
- Modify: `.env.example:40-41`

**Step 1: Добавить секцию Ollama в конец файла**

```bash
# === Ollama ===
# Список моделей через запятую (пусто = не ставить модели)
# Пример: OLLAMA_MODELS=qwen3-coder:30b,glm-4.7-flash
OLLAMA_MODELS=
```

**Step 2: Commit**

```bash
git add .env.example
git commit -m "feat: add OLLAMA_MODELS to .env.example"
```

---

### Task 2: Обновить roles/ollama/defaults/main.yml

**Files:**
- Modify: `roles/ollama/defaults/main.yml`

**Step 1: Заменить содержимое файла**

Было:
```yaml
---
ollama_models:
  - qwen3-coder:30b
  - glm-4.7-flash
```

Стало:
```yaml
---
ollama_models: []
```

**Step 2: Commit**

```bash
git add roles/ollama/defaults/main.yml
git commit -m "feat: default ollama_models to empty list"
```

---

### Task 3: Добавить условие в роль ollama (пропуск если список пуст)

**Files:**
- Modify: `roles/ollama/tasks/main.yml:40-44`

**Step 1: Добавить `when` условие к таску Pull Ollama models**

Было:
```yaml
- name: Pull Ollama models
  ansible.builtin.command: ollama pull {{ item }}
  loop: "{{ ollama_models }}"
  register: ollama_pull_result
  changed_when: "'pulling' in ollama_pull_result.stdout"
```

Стало:
```yaml
- name: Pull Ollama models
  ansible.builtin.command: ollama pull {{ item }}
  loop: "{{ ollama_models }}"
  register: ollama_pull_result
  changed_when: "'pulling' in ollama_pull_result.stdout"
  when: ollama_models | length > 0
```

**Step 2: Commit**

```bash
git add roles/ollama/tasks/main.yml
git commit -m "feat: skip model pulling when ollama_models is empty"
```

---

### Task 4: Создать bootstrap.sh

**Files:**
- Create: `bootstrap.sh`

**Step 1: Создать скрипт**

```bash
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
```

**Step 2: Сделать скрипт исполняемым**

```bash
chmod +x bootstrap.sh
```

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add bootstrap.sh for VM provisioning"
```

---

### Task 5: Обновить CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Добавить bootstrap.sh в Quick Start**

В секцию Quick Start добавить:

```markdown
# Провижен VM
./bootstrap.sh                                # Применить роли (читает .env)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add bootstrap.sh to quick start"
```
