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

### Подключение Claude Code к Ollama

```bash
ollama launch claude --model glm-4.7-flash
```

### Подключение OpenCode к Ollama

```bash
ollama launch opencode --model glm-4.7-flash
```

## Infrastructure Management (Selectel API)

### Prerequisites

1. Install OpenStack SDK and CLI:
   ```bash
   sudo apt install python3-openstacksdk python3-openstackclient jq
   ansible-galaxy collection install openstack.cloud
   ```

2. Configure credentials:
   ```bash
   cp .env.example .env
   # Edit .env with your Selectel credentials
   ```

### Commands

```bash
# List resources
./selectel.sh list-flavors    # Available VM configurations
./selectel.sh list-images     # Images in cloud
./selectel.sh list-disks      # Volumes/disks
./selectel.sh list-vms        # Running servers
./selectel.sh network-info    # Network configuration

# Network setup (one time)
./selectel.sh network-setup   # Create network, subnet, router, security group

# VM Management
./selectel.sh gpu-start --disk "my-disk"                    # Start GPU VM with existing disk
./selectel.sh gpu-start --disk "my-disk" --name "my-vm"     # With custom VM name
./selectel.sh gpu-start --image "my-image"                  # Start GPU VM from image (creates new disk)
./selectel.sh gpu-start --image "my-image" --name "my-vm"   # From image with custom VM name
./selectel.sh gpu-stop --name "my-vm"                       # Stop specific GPU VM (keeps disk)
./selectel.sh setup-start                                   # Start VM without GPU
./selectel.sh setup-start --name "my-setup"                 # With custom VM name

# Disk Management
./selectel.sh disk-detach --name "my-disk"                      # Detach disk from server (keeps both)
./selectel.sh disk-delete --name "my-disk"

# Image Management
./selectel.sh image-create-from-disk --disk "my-disk" --name "my-image"
./selectel.sh image-download --name "my-image" --output ~/images/
./selectel.sh image-upload --file ~/image.raw --name "my-image"
./selectel.sh image-delete --name "my-image"
```

### Typical Workflows

**Initial Setup (one time):**
```bash
./selectel.sh setup-start
# Wait for VM, add IP to inventory/hosts.yml
ansible-playbook playbooks/site.yml
./selectel.sh image-create-from-disk --disk "setup-vm-...-boot" --name "base-image"
./selectel.sh image-download --name "base-image" --output ~/images/
./selectel.sh gpu-stop --name "setup-vm-..."
./selectel.sh disk-delete --name "setup-vm-...-boot"
```

**Daily Usage:**
```bash
./selectel.sh gpu-start --image "base-image"
# ... work ...
./selectel.sh gpu-stop --name "gpu-vm-..."
```

## Локальный запуск образа Selectel

При запуске скачанного образа Selectel локально (без GPU), нужно отключить сервисы nvidia-cdi-refresh, которые пытаются обнаружить отсутствующее оборудование:

```bash
systemctl stop nvidia-cdi-refresh.service
systemctl stop nvidia-cdi-refresh.path
```

## Работа с образами Selectel

```bash
# RAW → VMDK (после скачивания из Selectel)
qemu-img convert -p -f raw -O vmdk ubuntu2404gpu ubuntu2404gpu.vmdk

# VMDK → RAW (для загрузки обратно в Selectel)
qemu-img convert -p -f vmdk -O raw ubuntu2404gpu.vmdk ubuntu2404gpu
```
