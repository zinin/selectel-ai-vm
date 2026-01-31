# Selectel GPU VM

Автоматизация управления GPU VM в Selectel через CLI. Экономия за счёт:
- Прерываемых серверов (spot instances)
- Хранения образов локально вместо облака
- Быстрого создания/удаления VM по требованию

## Сценарии использования

| Сценарий | Описание |
|----------|----------|
| Быстрый запуск | Образ уже в облаке → запуск VM |
| Экономный запуск | Загрузка образа с локальной машины → запуск VM |
| Сохранение работы | Создать образ → скачать локально → удалить ресурсы |
| Первичная настройка | VM без GPU → настроить через Ansible → создать базовый образ |

## Требования

- Ubuntu/Debian или macOS
- Ansible 2.9+
- Python 3.8+
- SSH ключ для доступа к VM

## Установка

1. Установите зависимости:

```bash
# Ubuntu/Debian
sudo apt install python3-openstacksdk python3-openstackclient jq ansible

# macOS
brew install ansible jq
pip3 install openstacksdk python-openstackclient
```

2. Установите Ansible collection:

```bash
ansible-galaxy collection install openstack.cloud
```

3. Настройте credentials:

```bash
cp .env.example .env
# Заполните .env данными из Selectel панели
```

## Типовые сценарии

### Первичная настройка (один раз)

```bash
# 1. Создать сеть, роутер, security group
./selectel.sh network-setup

# 2. Запустить VM без GPU для настройки
./selectel.sh setup-start

# 3. Применить Ansible роли
./bootstrap.sh

# 4. Остановить VM и отсоединить диск
./selectel.sh gpu-stop --name "setup-vm-..."
./selectel.sh disk-detach --name "setup-vm-...-boot"
```

### Ежедневная работа

```bash
# Запуск GPU VM с существующим диском
./selectel.sh gpu-start --disk "setup-vm-...-boot"

# ... работа ...

# Остановка (диск сохраняется)
./selectel.sh gpu-stop --name "gpu-vm-..."
```

### Работа с образами (для бэкапа или экономии хранения)

```bash
# Создать образ из диска
./selectel.sh image-create-from-disk --disk "my-disk" --name "my-image"

# Скачать образ локально
./selectel.sh image-download --name "my-image" --output ~/images/

# Загрузить образ обратно
./selectel.sh image-upload --file ~/images/my-image --name "my-image"

# Запустить VM из образа (создаст новый диск)
./selectel.sh gpu-start --image "my-image"
```

## CLI команды

### Информация

```bash
./selectel.sh list-flavors       # Доступные конфигурации VM
./selectel.sh list-images        # Образы в облаке
./selectel.sh list-disks         # Диски
./selectel.sh list-vms           # Запущенные VM
./selectel.sh network-info       # Конфигурация сети
```

### Управление VM

```bash
./selectel.sh gpu-start --disk "name"     # Запуск GPU VM с диском
./selectel.sh gpu-start --image "name"    # Запуск GPU VM из образа
./selectel.sh gpu-stop --name "name"      # Остановка VM (диск сохраняется)
./selectel.sh setup-start                 # Запуск VM без GPU (для настройки)
```

### Управление дисками

```bash
./selectel.sh disk-detach --name "name"   # Отсоединить диск от VM
./selectel.sh disk-delete --name "name"   # Удалить диск
```

### Управление образами

```bash
./selectel.sh image-create-from-disk --disk "disk" --name "image"
./selectel.sh image-download --name "image" --output ~/path/
./selectel.sh image-upload --file ~/image.raw --name "image"
./selectel.sh image-delete --name "image"
```

## Подключение к Ollama

Ollama слушает только на localhost. Для доступа используйте SSH туннель:

```bash
ssh -L 11434:localhost:11434 username@<server-ip>
```

После этого Ollama доступна локально: `http://localhost:11434`

## Работа с образами локально

### Конвертация форматов

```bash
# RAW → VMDK (для VMware/VirtualBox)
qemu-img convert -p -f raw -O vmdk image.raw image.vmdk

# VMDK → RAW (для загрузки в Selectel)
qemu-img convert -p -f vmdk -O raw image.vmdk image.raw
```

### Локальный запуск без GPU

При запуске образа локально отключите nvidia сервисы:

```bash
systemctl stop nvidia-cdi-refresh.service
systemctl stop nvidia-cdi-refresh.path
```

## Архитектура

```
selectel.sh                      # CLI обёртка
    ↓
playbooks/infra/*.yml            # Ansible playbooks для Selectel API
    ↓
openstack.cloud                  # Ansible collection
    ↓
Selectel API (OpenStack)
```

### Структура проекта

```
├── selectel.sh          # CLI для управления инфраструктурой
├── bootstrap.sh         # Применение Ansible ролей к VM
├── .env.example         # Шаблон credentials
├── inventory/hosts.yml  # Хосты для Ansible
├── playbooks/
│   ├── site.yml         # Настройка VM (роли)
│   └── infra/           # Управление инфраструктурой
└── roles/
    ├── base/            # apt update, mc
    ├── user/            # Создание пользователя
    ├── ollama/          # Установка Ollama
    └── claude_code/     # Установка Claude Code
```
