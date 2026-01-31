# Selectel AI VM

Ansible playbooks + CLI для GPU VM в Selectel (Ubuntu 24.04).

## Quick Start

```bash
# Инфраструктура
./selectel.sh gpu-start --image "base-image"  # Запуск GPU VM
./selectel.sh gpu-stop --name "gpu-vm-..."    # Остановка

# Настройка VM
ansible-playbook playbooks/site.yml           # Применить роли
ansible gpu_vms -m ping                       # Проверка связи

# Провижен VM
./bootstrap.sh                                # Применить роли (читает .env)
```

## Architecture

| Path | Purpose |
|------|---------|
| `selectel.sh` | CLI обёртка для управления инфраструктурой |
| `playbooks/site.yml` | Основной playbook для настройки VM |
| `playbooks/infra/` | Ansible playbooks для Selectel API |
| `roles/` | base, user, ollama, claude_code |
| `inventory/hosts.yml` | Хосты (группа `gpu_vms`) |
| `.env` | Credentials для Selectel (из `.env.example`) |

## Key Patterns

**Подключение**: root по SSH ключу, host_key_checking отключен.

**Роли**: `roles/<name>/tasks/main.yml` + опционально `defaults/` и `handlers/`.

**Infra playbooks**: localhost, используют `openstack.cloud` collection.

## Adding New Roles

1. Создать `roles/<name>/tasks/main.yml`
2. Добавить роль в `playbooks/site.yml`

## Adding New Infra Commands

1. Создать `playbooks/infra/<command>.yml`
2. Добавить case в `selectel.sh`

## Tech Stack

Ansible 2.9+, OpenStack SDK, Ubuntu 24.04
