# Автоматизация управления GPU VM через Selectel API

## Цель

Автоматизировать создание/удаление GPU VM в Selectel без использования веб-интерфейса. Экономить деньги за счёт:
- Прерываемых серверов (spot instances)
- Хранения образов локально вместо облака
- Быстрого поднятия/удаления VM по требованию

## Сценарии использования

| Сценарий | Описание | Время |
|----------|----------|-------|
| Быстрый запуск | Образ/диск уже в облаке | ~1-2 мин |
| Экономный запуск | Загрузка образа с локальной машины | ~5-10 мин |
| Сохранение | Создать образ → скачать → удалить ресурсы | ~5-10 мин |
| Первичная настройка | VM без GPU → настроить Ansible → образ | разово |

## Архитектура

```
selectel.sh (shell-обёртка)
       ↓
ansible-playbook playbooks/infra/*.yml
       ↓
модули openstack.cloud → Selectel API (OpenStack Keystone v3)
```

## Структура проекта

```
selectel-ai-vm/
├── selectel.sh                    # Точка входа
├── .env.example                   # Шаблон credentials
├── .env                           # Credentials (в .gitignore)
│
├── playbooks/
│   ├── site.yml                   # Настройка VM (существующий)
│   └── infra/                     # Управление инфраструктурой
│       ├── list-flavors.yml
│       ├── list-images.yml
│       ├── list-disks.yml
│       ├── list-vms.yml
│       ├── gpu-start.yml
│       ├── gpu-stop.yml
│       ├── setup-start.yml
│       ├── disk-delete.yml
│       ├── image-create-from-disk.yml
│       ├── image-download.yml
│       ├── image-upload.yml
│       ├── image-delete.yml
│       ├── network-setup.yml        # создание сети/подсети/роутера/SG
│       └── network-info.yml         # информация о сети
│
├── inventory/
│   ├── hosts.yml                  # Статические хосты
│   └── openstack.yml              # Динамический inventory (опционально)
│
└── roles/                         # Существующие роли настройки
```

## Конфигурация (.env)

```bash
# === OpenStack Auth ===
OS_AUTH_URL=https://cloud.api.selcloud.ru/identity/v3
OS_USER_DOMAIN_NAME=<account_id>
OS_PROJECT_DOMAIN_NAME=<account_id>
OS_PROJECT_ID=<project_id>
OS_USERNAME=<service_user>
OS_PASSWORD=<password>

# === Регион ===
OS_REGION_NAME=ru-7
OS_AVAILABILITY_ZONE=ru-7a

# === VM ===
GPU_FLAVOR_ID=                  # узнать через ./selectel.sh list-flavors
SETUP_FLAVOR_ID=                # для VM без GPU (минимальный)
DISK_SIZE_GB=10
DISK_TYPE=universal             # universal / fast / basic

# === Сеть ===
NETWORK_NAME=net
SUBNET_CIDR=192.168.0.0/24
EXTERNAL_NETWORK=external-network    # внешняя сеть для floating IP
ROUTER_NAME=router
ALLOCATE_FLOATING_IP=true

# === Опции ===
SECURITY_GROUP=default

# === SSH ===
SSH_KEY_FILE=~/.ssh/id_ed25519.pub
SSH_KEY_NAME=ansible-key            # имя keypair в OpenStack
```

## Команды

### Информация

```bash
./selectel.sh list-flavors         # доступные конфигурации серверов
./selectel.sh list-images          # образы в облаке
./selectel.sh list-disks           # диски
./selectel.sh list-vms             # серверы
./selectel.sh network-info         # информация о сети
```

### Управление сетью

```bash
./selectel.sh network-setup        # создать сеть, подсеть, роутер и SG (один раз)
```

### Управление VM

```bash
./selectel.sh gpu-start --disk "my-disk"      # запуск с существующим диском
./selectel.sh gpu-start --image "my-image"    # запуск из образа (создаст новый диск)
./selectel.sh gpu-start --image "my-image" --name "gpu-work-1"  # с кастомным именем
./selectel.sh gpu-stop                         # удалить VM (диск остаётся)
./selectel.sh gpu-stop --name "gpu-work-1"    # удалить конкретную VM
./selectel.sh setup-start                      # VM без GPU для первичной настройки
./selectel.sh setup-start --name "setup-2"    # с кастомным именем
```

После создания VM выводится:
```
VM создана: gpu-vm-20260131-143022
IP: 91.123.45.67
```

### Управление дисками

```bash
./selectel.sh disk-delete --name "my-disk"
```

### Управление образами

```bash
./selectel.sh image-create-from-disk --disk "my-disk" --name "my-image"
./selectel.sh image-download --name "my-image" --output ~/images/
./selectel.sh image-upload --file ~/image.raw --name "my-image"
./selectel.sh image-delete --name "my-image"
```

## Диски vs Образы

| | Диск (volume) | Образ (image) |
|---|---------------|---------------|
| Изменения | Сохраняются | Новый диск каждый раз |
| Скорость запуска | Мгновенно | Копирование образа → диск |
| Параллельные VM | Нет | Да |
| Хранение локально | Нельзя | Можно скачать |

## Зависимости

Ubuntu 24.04+:

```bash
# Системные пакеты
sudo apt install python3-openstacksdk python3-openstackclient ansible

# Проверить Ansible-коллекцию
ansible-galaxy collection list | grep openstack
# Если нет:
ansible-galaxy collection install openstack.cloud
```

## Типичные workflow

### Первичная настройка (один раз)

```bash
# 1. Создать дешёвую VM без GPU
./selectel.sh setup-start

# 2. Настроить через существующий Ansible
ansible-playbook playbooks/site.yml

# 3. Создать образ
./selectel.sh image-create-from-disk --disk "setup-disk" --name "base-image"

# 4. Скачать локально для экономии
./selectel.sh image-download --name "base-image" --output ~/images/

# 5. Удалить ресурсы в облаке
./selectel.sh gpu-stop
./selectel.sh disk-delete --name "setup-disk"
./selectel.sh image-delete --name "base-image"
```

### Ежедневная работа (образ в облаке)

```bash
# Утро: поднять GPU VM
./selectel.sh gpu-start --image "base-image"

# ... работа ...

# Вечер: удалить VM
./selectel.sh gpu-stop
```

### Экономный режим (образ локально)

```bash
# Загрузить образ в облако
./selectel.sh image-upload --file ~/images/base-image.raw --name "base-image"

# Создать GPU VM
./selectel.sh gpu-start --image "base-image"

# ... работа ...

# Сохранить изменения если нужно
./selectel.sh image-create-from-disk --disk "gpu-disk" --name "updated-image"
./selectel.sh image-download --name "updated-image" --output ~/images/

# Очистить облако
./selectel.sh gpu-stop
./selectel.sh disk-delete --name "gpu-disk"
./selectel.sh image-delete --name "base-image"
./selectel.sh image-delete --name "updated-image"
```

## Аутентификация

Selectel VPC использует OpenStack Keystone v3.

Endpoint: `https://cloud.api.selcloud.ru/identity/v3`

Ansible-модули `openstack.cloud` автоматически получают токен через переменные окружения `OS_*`. Ручное получение токена не требуется.

## Особенности Selectel

- **Приватная сеть + Floating IP**: VM в приватной сети 192.168.0.0/24, доступ извне через публичный IP
- **Root доступ**: Selectel-образы Ubuntu поставляются с включённым root-доступом по SSH
- **Прерываемые серверы**: TODO — требует изучения Selectel API для корректной реализации (возможно через scheduler_hints или специальные flavors)

## Важные детали реализации

Эти требования выявлены в ходе design review и должны быть учтены при имплементации:

| Требование | Описание |
|------------|----------|
| **terminate_volume: false** | При создании VM явно указывать `terminate_volume: false`, чтобы boot-диск не удалялся вместе с сервером |
| **Валидация входных данных** | Проверять наличие обязательных переменных (`GPU_FLAVOR_ID`, `SETUP_FLAVOR_ID`), единственность найденных ресурсов (диск, образ) |
| **Размер диска** | Автоматически вычислять `max(DISK_SIZE_GB, image.min_disk)` при создании диска из образа |
| **Генерация имён VM** | При отсутствии `--name` генерировать уникальные имена с timestamp: `gpu-vm-20260131-143022` |
| **Floating IP** | Использовать `openstack.cloud.floating_ip` с явным указанием `EXTERNAL_NETWORK` вместо `auto_ip: true` |
| **SSH keypair** | Перед созданием/обновлением keypair проверять fingerprint существующего ключа |
| **Ожидание образа** | После создания образа ждать по ID, не по имени (избегать коллизий) |
| **Ansible-модули** | Использовать `openstack.cloud` модули вместо CLI (`openstack` команд) где возможно |
| **Валидация уникальности** | При удалении/скачивании ресурса по имени проверять, что найден ровно 1 ресурс |
| **Security group rules** | network-setup добавляет SSH/ICMP правила в указанную SG (включая default) |
| **gpu-stop без --name** | Если --name не указан, показать список VM и попросить выбрать |
| **Откат при ошибке** | При ошибке создания сервера удалять созданный том (block/rescue) |
| **Взаимоисключающие параметры** | gpu-start с --disk и --image одновременно — ошибка |
| **Floating IP fallback** | При ALLOCATE_FLOATING_IP=false использовать default в выводе |
| **set_fact server в ветках** | Выставлять `server` внутри каждой ветки (disk/image) после создания, избегать undefined переменных |
| **networks: список** | Использовать `networks:` (список) вместо `network:` в openstack.cloud.server |
| **Валидация уникальности VM** | При удалении VM по имени проверять, что найдена ровно 1 VM |
| **Проверка статуса тома** | При gpu-start --disk проверять, что том available (не in-use) |
| **block/rescue в setup-start** | Оборачивать создание тома+сервера в block/rescue для отката |
| **JSON для extra-vars** | В selectel.sh передавать extra-vars в JSON для поддержки пробелов в именах |
| **failed_when для SG rules** | Убрать ignore_errors, использовать failed_when для игнорирования только дубликатов |
| **Проверка fingerprint keypair** | Сравнивать fingerprint существующего keypair с локальным ключом |
| **Проверка существования тома** | Перед созданием boot-тома проверять, что том с таким именем не существует |
| **--force для перезаписи** | image-upload и image-download требуют --force для перезаписи существующих ресурсов |
| **Интерактивный выбор образа** | setup-start показывает список образов, если BASE_IMAGE_NAME не задан |
