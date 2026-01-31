# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible playbooks для настройки виртуальных машин с GPU в Selectel (Ubuntu 24.04).

## Commands

```bash
# Проверка синтаксиса
ansible-playbook playbooks/site.yml --syntax-check

# Запуск playbook
ansible-playbook playbooks/site.yml

# Dry-run (без изменений)
ansible-playbook playbooks/site.yml --check

# Запуск конкретной роли через тег (если добавлены теги)
ansible-playbook playbooks/site.yml --tags "base"
```

## Architecture

- **Подключение**: root по SSH ключу (host_key_checking отключен)
- **Роли**: `roles/` — каждая роль имеет `tasks/main.yml` и опционально `defaults/main.yml`
- **Playbooks**: `playbooks/site.yml` — основной playbook, применяет роли к группе `gpu_vms`
- **Inventory**: `inventory/hosts.yml` — группа `gpu_vms` с хостами

## Adding New Roles

1. Создать `roles/<role_name>/tasks/main.yml`
2. Опционально: `roles/<role_name>/defaults/main.yml` для переменных
3. Добавить роль в `playbooks/site.yml`
