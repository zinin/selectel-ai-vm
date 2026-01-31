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
    └── user/            # Создание пользователя
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
