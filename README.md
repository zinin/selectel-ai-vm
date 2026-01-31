# Selectel AI VM

Ansible playbooks для настройки виртуальных машин с GPU в Selectel.

## Требования

- Ansible 2.9+
- SSH доступ к VM по ключу (root)
- Ubuntu 24.04

## Быстрый старт

1. Добавьте IP вашей VM в `inventory/hosts.yml`:

```yaml
gpu_vms:
  hosts:
    gpu-vm-1:
      ansible_host: 1.2.3.4
```

2. Запустите playbook:

```bash
ansible-playbook playbooks/site.yml
```

## Структура

```
├── ansible.cfg          # Конфигурация Ansible
├── inventory/
│   └── hosts.yml        # Inventory с хостами
├── playbooks/
│   └── site.yml         # Основной playbook
└── roles/
    ├── base/            # apt update/upgrade, mc
    ├── user/            # Создание пользователя
    ├── ollama/          # Установка Ollama
    └── claude-code/     # Установка Claude Code
```

## Роли

### base

- Обновление apt кэша
- Обновление всех пакетов (dist-upgrade)
- Установка mc

### user

Создание пользователя с:
- UID 1000
- Группы: sudo, adm, dip, plugdev, video, render
- sudo без пароля
- SSH ключи от root

Параметры (можно переопределить):
- `username` — имя пользователя (по умолчанию: zinin)
- `user_uid` — UID (по умолчанию: 1000)
- `user_groups` — список групп

### ollama

Установка [Ollama](https://ollama.com/) с настройками:
- `OLLAMA_KEEP_ALIVE=-1` — модели остаются в памяти
- `OLLAMA_CONTEXT_LENGTH=30000` — увеличенный контекст

### claude-code

Установка [Claude Code](https://claude.ai/code) для пользователя zinin.

## Подключение к Ollama

Ollama слушает только на localhost для безопасности. Для доступа используйте SSH туннель:

```bash
ssh -L 11434:localhost:11434 zinin@<server-ip>
```

После этого Ollama доступна локально на `http://localhost:11434`.

Для постоянного туннеля добавьте в `~/.ssh/config`:

```
Host gpu-vm
    HostName <server-ip>
    User zinin
    LocalForward 11434 localhost:11434
```

## Локальный запуск образа Selectel

При запуске скачанного образа Selectel локально (без GPU), нужно отключить сервисы nvidia-cdi-refresh, которые пытаются обнаружить отсутствующее оборудование:

```bash
systemctl stop nvidia-cdi-refresh.service
systemctl stop nvidia-cdi-refresh.path
```
