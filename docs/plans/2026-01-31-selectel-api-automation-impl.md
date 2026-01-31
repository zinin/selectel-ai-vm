# Selectel API Automation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Реализовать автоматизацию управления GPU VM в Selectel через OpenStack API с помощью Ansible playbooks и shell-обёртки.

**Architecture:** Shell-скрипт `selectel.sh` как точка входа, который загружает переменные из `.env` и вызывает соответствующие Ansible playbooks из `playbooks/infra/`. Playbooks используют модули `openstack.cloud` для взаимодействия с Selectel API (OpenStack Keystone v3).

**Tech Stack:** Ansible 2.15+, openstack.cloud collection 2.x, openstacksdk 1.x, bash

---

## Task 1: Подготовка инфраструктуры проекта

**Files:**
- Create: `.env.example`
- Create: `.gitignore` (обновить)
- Create: `selectel.sh`

**Step 1: Создать .env.example с шаблоном credentials**

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
GPU_FLAVOR_ID=
SETUP_FLAVOR_ID=
DISK_SIZE_GB=10
DISK_TYPE=universal

# === Сеть ===
NETWORK_NAME=net
SUBNET_CIDR=192.168.0.0/24
ALLOCATE_FLOATING_IP=true

# === Опции ===
PREEMPTIBLE=true
SECURITY_GROUP=default

# === SSH ===
SSH_KEY_FILE=~/.ssh/id_ed25519.pub
```

**Step 2: Проверить файл создан**

Run: `cat .env.example | head -5`
Expected: Первые 5 строк файла

**Step 3: Обновить .gitignore**

Добавить в `.gitignore`:
```
.env
*.raw
*.qcow2
```

**Step 4: Создать базовый selectel.sh**

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

# Экспорт переменных для Ansible
export OS_AUTH_URL OS_USER_DOMAIN_NAME OS_PROJECT_DOMAIN_NAME OS_PROJECT_ID
export OS_USERNAME OS_PASSWORD OS_REGION_NAME OS_AVAILABILITY_ZONE

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  list-flavors          List available compute flavors
  list-images           List images in cloud
  list-disks            List volumes/disks
  list-vms              List servers

  gpu-start             Start GPU VM
    --disk <name>       Use existing disk
    --image <name>      Create from image

  gpu-stop              Stop and delete GPU VM (keeps disk)

  setup-start           Start VM without GPU (for initial setup)

  disk-delete           Delete a disk
    --name <name>       Disk name

  image-create-from-disk Create image from disk
    --disk <name>       Source disk name
    --name <name>       Image name

  image-download        Download image locally
    --name <name>       Image name
    --output <path>     Output directory

  image-upload          Upload local image
    --file <path>       Image file path
    --name <name>       Image name

  image-delete          Delete image
    --name <name>       Image name

EOF
    exit 1
}

[[ $# -lt 1 ]] && usage

COMMAND="$1"
shift

case "$COMMAND" in
    list-flavors)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/list-flavors.yml"
        ;;
    list-images)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/list-images.yml"
        ;;
    list-disks)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/list-disks.yml"
        ;;
    list-vms)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/list-vms.yml"
        ;;
    gpu-start)
        DISK_NAME=""
        IMAGE_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --disk) DISK_NAME="$2"; shift 2 ;;
                --image) IMAGE_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        if [[ -n "$DISK_NAME" ]]; then
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-start.yml" \
                -e "boot_disk_name=$DISK_NAME"
        elif [[ -n "$IMAGE_NAME" ]]; then
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-start.yml" \
                -e "boot_image_name=$IMAGE_NAME"
        else
            echo "Error: specify --disk or --image"
            exit 1
        fi
        ;;
    gpu-stop)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-stop.yml"
        ;;
    setup-start)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/setup-start.yml"
        ;;
    disk-delete)
        DISK_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) DISK_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$DISK_NAME" ]] && { echo "Error: --name required"; exit 1; }
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/disk-delete.yml" \
            -e "disk_name=$DISK_NAME"
        ;;
    image-create-from-disk)
        DISK_NAME=""
        IMAGE_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --disk) DISK_NAME="$2"; shift 2 ;;
                --name) IMAGE_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$DISK_NAME" || -z "$IMAGE_NAME" ]] && { echo "Error: --disk and --name required"; exit 1; }
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-create-from-disk.yml" \
            -e "source_disk_name=$DISK_NAME" \
            -e "image_name=$IMAGE_NAME"
        ;;
    image-download)
        IMAGE_NAME=""
        OUTPUT_DIR=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) IMAGE_NAME="$2"; shift 2 ;;
                --output) OUTPUT_DIR="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$IMAGE_NAME" || -z "$OUTPUT_DIR" ]] && { echo "Error: --name and --output required"; exit 1; }
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-download.yml" \
            -e "image_name=$IMAGE_NAME" \
            -e "output_dir=$OUTPUT_DIR"
        ;;
    image-upload)
        FILE_PATH=""
        IMAGE_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --file) FILE_PATH="$2"; shift 2 ;;
                --name) IMAGE_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$FILE_PATH" || -z "$IMAGE_NAME" ]] && { echo "Error: --file and --name required"; exit 1; }
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-upload.yml" \
            -e "image_file=$FILE_PATH" \
            -e "image_name=$IMAGE_NAME"
        ;;
    image-delete)
        IMAGE_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) IMAGE_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$IMAGE_NAME" ]] && { echo "Error: --name required"; exit 1; }
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-delete.yml" \
            -e "image_name=$IMAGE_NAME"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
```

**Step 5: Сделать selectel.sh исполняемым и проверить синтаксис**

Run: `chmod +x selectel.sh && bash -n selectel.sh && echo "Syntax OK"`
Expected: "Syntax OK"

**Step 6: Commit**

```bash
git add .env.example .gitignore selectel.sh
git commit -m "feat: add selectel.sh CLI wrapper and .env template"
```

---

## Task 2: Создать директорию playbooks/infra и базовые переменные

**Files:**
- Create: `playbooks/infra/vars/main.yml`
- Create: `playbooks/infra/.gitkeep`

**Step 1: Создать директорию и vars**

```yaml
# playbooks/infra/vars/main.yml
---
# VM names
gpu_vm_name: gpu-vm-1
setup_vm_name: setup-vm-1

# Disk defaults
default_disk_size: "{{ lookup('env', 'DISK_SIZE_GB') | default(10, true) }}"
default_disk_type: "{{ lookup('env', 'DISK_TYPE') | default('universal', true) }}"

# Network
network_name: "{{ lookup('env', 'NETWORK_NAME') | default('net', true) }}"
allocate_floating_ip: "{{ lookup('env', 'ALLOCATE_FLOATING_IP') | default('true', true) | bool }}"
security_group: "{{ lookup('env', 'SECURITY_GROUP') | default('default', true) }}"

# Flavors
gpu_flavor_id: "{{ lookup('env', 'GPU_FLAVOR_ID') }}"
setup_flavor_id: "{{ lookup('env', 'SETUP_FLAVOR_ID') }}"

# Preemptible
preemptible: "{{ lookup('env', 'PREEMPTIBLE') | default('true', true) | bool }}"

# SSH key
ssh_key_file: "{{ lookup('env', 'SSH_KEY_FILE') | default('~/.ssh/id_ed25519.pub', true) }}"

# Region
availability_zone: "{{ lookup('env', 'OS_AVAILABILITY_ZONE') | default('ru-7a', true) }}"
```

**Step 2: Проверить файл создан**

Run: `cat playbooks/infra/vars/main.yml | head -10`
Expected: Первые 10 строк файла с комментариями

**Step 3: Commit**

```bash
git add playbooks/infra/
git commit -m "feat: add infra playbooks directory with shared vars"
```

---

## Task 3: Реализовать list-flavors playbook

**Files:**
- Create: `playbooks/infra/list-flavors.yml`

**Step 1: Создать playbook для вывода flavors**

```yaml
# playbooks/infra/list-flavors.yml
---
- name: List available compute flavors
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Get all compute flavors
      openstack.cloud.compute_flavor_info:
      register: flavors_result

    - name: Display flavors
      ansible.builtin.debug:
        msg: |

          Available Compute Flavors:
          ==========================
          {% for f in flavors_result.flavors | sort(attribute='vcpus') %}
          {{ "%-40s" | format(f.name) }} | vCPUs: {{ "%2d" | format(f.vcpus) }} | RAM: {{ "%6d" | format(f.ram) }} MB | Disk: {{ "%4d" | format(f.disk) }} GB | ID: {{ f.id }}
          {% endfor %}
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/list-flavors.yml --syntax-check`
Expected: "playbook: playbooks/infra/list-flavors.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/list-flavors.yml
git commit -m "feat: add list-flavors playbook"
```

---

## Task 4: Реализовать list-images playbook

**Files:**
- Create: `playbooks/infra/list-images.yml`

**Step 1: Создать playbook для вывода образов**

```yaml
# playbooks/infra/list-images.yml
---
- name: List available images
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Get all images
      openstack.cloud.image_info:
      register: images_result

    - name: Display images
      ansible.builtin.debug:
        msg: |

          Available Images:
          =================
          {% for img in images_result.images | sort(attribute='name') %}
          {{ "%-50s" | format(img.name) }} | Size: {{ "%10d" | format(img.size | default(0)) }} bytes | Status: {{ img.status }} | ID: {{ img.id }}
          {% endfor %}
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/list-images.yml --syntax-check`
Expected: "playbook: playbooks/infra/list-images.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/list-images.yml
git commit -m "feat: add list-images playbook"
```

---

## Task 5: Реализовать list-disks playbook

**Files:**
- Create: `playbooks/infra/list-disks.yml`

**Step 1: Создать playbook для вывода дисков**

```yaml
# playbooks/infra/list-disks.yml
---
- name: List available volumes/disks
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Get all volumes
      openstack.cloud.volume_info:
        details: true
      register: volumes_result

    - name: Display volumes
      ansible.builtin.debug:
        msg: |

          Available Volumes/Disks:
          ========================
          {% for vol in volumes_result.volumes | sort(attribute='name') %}
          {{ "%-40s" | format(vol.name) }} | Size: {{ "%4d" | format(vol.size) }} GB | Status: {{ "%-10s" | format(vol.status) }} | ID: {{ vol.id }}
          {% endfor %}
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/list-disks.yml --syntax-check`
Expected: "playbook: playbooks/infra/list-disks.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/list-disks.yml
git commit -m "feat: add list-disks playbook"
```

---

## Task 6: Реализовать list-vms playbook

**Files:**
- Create: `playbooks/infra/list-vms.yml`

**Step 1: Создать playbook для вывода серверов**

```yaml
# playbooks/infra/list-vms.yml
---
- name: List servers
  hosts: localhost
  connection: local
  gather_facts: false

  tasks:
    - name: Get all servers
      openstack.cloud.server_info:
      register: servers_result

    - name: Display servers
      ansible.builtin.debug:
        msg: |

          Servers:
          ========
          {% for srv in servers_result.servers | sort(attribute='name') %}
          {{ "%-30s" | format(srv.name) }} | Status: {{ "%-10s" | format(srv.status) }} | Flavor: {{ srv.flavor.original_name | default(srv.flavor.id) }} | IPs: {{ srv.addresses | dict2items | map(attribute='value') | flatten | map(attribute='addr') | join(', ') }} | ID: {{ srv.id }}
          {% endfor %}
          {% if servers_result.servers | length == 0 %}
          No servers found.
          {% endif %}
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/list-vms.yml --syntax-check`
Expected: "playbook: playbooks/infra/list-vms.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/list-vms.yml
git commit -m "feat: add list-vms playbook"
```

---

## Task 7: Реализовать gpu-start playbook

**Files:**
- Create: `playbooks/infra/gpu-start.yml`

**Step 1: Создать playbook для запуска GPU VM**

```yaml
# playbooks/infra/gpu-start.yml
---
- name: Start GPU VM
  hosts: localhost
  connection: local
  gather_facts: false

  vars_files:
    - vars/main.yml

  vars:
    boot_disk_name: ""
    boot_image_name: ""
    vm_name: "{{ gpu_vm_name }}"
    flavor_id: "{{ gpu_flavor_id }}"

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "Specify either boot_disk_name or boot_image_name"
      when: boot_disk_name == "" and boot_image_name == ""

    - name: Read SSH public key
      ansible.builtin.set_fact:
        ssh_public_key: "{{ lookup('file', ssh_key_file | expanduser) }}"

    - name: Ensure keypair exists
      openstack.cloud.keypair:
        state: present
        name: ansible-key
        public_key: "{{ ssh_public_key }}"

    # Boot from existing disk
    - name: Get existing disk info
      openstack.cloud.volume_info:
        name: "{{ boot_disk_name }}"
      register: disk_info
      when: boot_disk_name != ""

    - name: Create server from existing disk
      openstack.cloud.server:
        state: present
        name: "{{ vm_name }}"
        flavor: "{{ flavor_id }}"
        boot_volume: "{{ disk_info.volumes[0].id }}"
        key_name: ansible-key
        security_groups:
          - "{{ security_group }}"
        network: "{{ network_name }}"
        availability_zone: "{{ availability_zone }}"
        auto_ip: "{{ allocate_floating_ip }}"
        timeout: 600
        wait: true
        meta:
          preemptible: "{{ preemptible | string }}"
      register: server_disk
      when: boot_disk_name != "" and disk_info.volumes | length > 0

    # Boot from image (create new disk)
    - name: Get image info
      openstack.cloud.image_info:
        name: "{{ boot_image_name }}"
      register: image_info
      when: boot_image_name != ""

    - name: Create boot volume from image
      openstack.cloud.volume:
        state: present
        name: "{{ vm_name }}-boot"
        size: "{{ default_disk_size }}"
        volume_type: "{{ default_disk_type }}"
        image: "{{ image_info.images[0].id }}"
        availability_zone: "{{ availability_zone }}"
        wait: true
      register: new_volume
      when: boot_image_name != "" and image_info.images | length > 0

    - name: Create server from new volume
      openstack.cloud.server:
        state: present
        name: "{{ vm_name }}"
        flavor: "{{ flavor_id }}"
        boot_volume: "{{ new_volume.volume.id }}"
        key_name: ansible-key
        security_groups:
          - "{{ security_group }}"
        network: "{{ network_name }}"
        availability_zone: "{{ availability_zone }}"
        auto_ip: "{{ allocate_floating_ip }}"
        timeout: 600
        wait: true
        meta:
          preemptible: "{{ preemptible | string }}"
      register: server_image
      when: boot_image_name != "" and new_volume.volume is defined

    - name: Set server result
      ansible.builtin.set_fact:
        server: "{{ server_disk if server_disk is defined and server_disk.server is defined else server_image }}"

    - name: Display server info
      ansible.builtin.debug:
        msg: |

          ========================================
          GPU VM Created Successfully!
          ========================================
          Name: {{ server.server.name }}
          ID: {{ server.server.id }}
          Status: {{ server.server.status }}
          IPs: {{ server.server.addresses | dict2items | map(attribute='value') | flatten | map(attribute='addr') | join(', ') }}

          Connect: ssh root@<floating_ip>
          ========================================
      when: server.server is defined
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/gpu-start.yml --syntax-check`
Expected: "playbook: playbooks/infra/gpu-start.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/gpu-start.yml
git commit -m "feat: add gpu-start playbook"
```

---

## Task 8: Реализовать gpu-stop playbook

**Files:**
- Create: `playbooks/infra/gpu-stop.yml`

**Step 1: Создать playbook для остановки GPU VM**

```yaml
# playbooks/infra/gpu-stop.yml
---
- name: Stop and delete GPU VM (keeps disk)
  hosts: localhost
  connection: local
  gather_facts: false

  vars_files:
    - vars/main.yml

  vars:
    vm_name: "{{ gpu_vm_name }}"

  tasks:
    - name: Get server info
      openstack.cloud.server_info:
        name: "{{ vm_name }}"
      register: server_info

    - name: Display warning if no server found
      ansible.builtin.debug:
        msg: "No server named '{{ vm_name }}' found. Nothing to delete."
      when: server_info.servers | length == 0

    - name: Delete server (keeps attached volumes)
      openstack.cloud.server:
        state: absent
        name: "{{ vm_name }}"
        delete_fip: true
        wait: true
        timeout: 300
      when: server_info.servers | length > 0

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          GPU VM Deleted Successfully!
          ========================================
          Name: {{ vm_name }}
          Note: Boot disk is preserved. Use 'disk-delete' to remove it.
          ========================================
      when: server_info.servers | length > 0
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/gpu-stop.yml --syntax-check`
Expected: "playbook: playbooks/infra/gpu-stop.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/gpu-stop.yml
git commit -m "feat: add gpu-stop playbook"
```

---

## Task 9: Реализовать setup-start playbook

**Files:**
- Create: `playbooks/infra/setup-start.yml`

**Step 1: Создать playbook для запуска VM без GPU**

```yaml
# playbooks/infra/setup-start.yml
---
- name: Start setup VM (without GPU, for initial configuration)
  hosts: localhost
  connection: local
  gather_facts: false

  vars_files:
    - vars/main.yml

  vars:
    vm_name: "{{ setup_vm_name }}"
    flavor_id: "{{ setup_flavor_id }}"
    base_image: "Ubuntu 24.04 LTS 64-bit"

  tasks:
    - name: Validate flavor is set
      ansible.builtin.fail:
        msg: "SETUP_FLAVOR_ID must be set in .env"
      when: flavor_id == ""

    - name: Read SSH public key
      ansible.builtin.set_fact:
        ssh_public_key: "{{ lookup('file', ssh_key_file | expanduser) }}"

    - name: Ensure keypair exists
      openstack.cloud.keypair:
        state: present
        name: ansible-key
        public_key: "{{ ssh_public_key }}"

    - name: Get base image info
      openstack.cloud.image_info:
        name: "{{ base_image }}"
      register: image_info

    - name: Fail if image not found
      ansible.builtin.fail:
        msg: "Base image '{{ base_image }}' not found"
      when: image_info.images | length == 0

    - name: Create boot volume
      openstack.cloud.volume:
        state: present
        name: "{{ vm_name }}-boot"
        size: "{{ default_disk_size }}"
        volume_type: "{{ default_disk_type }}"
        image: "{{ image_info.images[0].id }}"
        availability_zone: "{{ availability_zone }}"
        wait: true
      register: boot_volume

    - name: Create setup server
      openstack.cloud.server:
        state: present
        name: "{{ vm_name }}"
        flavor: "{{ flavor_id }}"
        boot_volume: "{{ boot_volume.volume.id }}"
        key_name: ansible-key
        security_groups:
          - "{{ security_group }}"
        network: "{{ network_name }}"
        availability_zone: "{{ availability_zone }}"
        auto_ip: "{{ allocate_floating_ip }}"
        timeout: 600
        wait: true
      register: server

    - name: Display server info
      ansible.builtin.debug:
        msg: |

          ========================================
          Setup VM Created Successfully!
          ========================================
          Name: {{ server.server.name }}
          ID: {{ server.server.id }}
          Status: {{ server.server.status }}
          IPs: {{ server.server.addresses | dict2items | map(attribute='value') | flatten | map(attribute='addr') | join(', ') }}

          Next steps:
          1. Add IP to inventory/hosts.yml
          2. Run: ansible-playbook playbooks/site.yml
          3. Create image: ./selectel.sh image-create-from-disk --disk "{{ vm_name }}-boot" --name "base-image"
          ========================================
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/setup-start.yml --syntax-check`
Expected: "playbook: playbooks/infra/setup-start.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/setup-start.yml
git commit -m "feat: add setup-start playbook"
```

---

## Task 10: Реализовать disk-delete playbook

**Files:**
- Create: `playbooks/infra/disk-delete.yml`

**Step 1: Создать playbook для удаления диска**

```yaml
# playbooks/infra/disk-delete.yml
---
- name: Delete a volume/disk
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    disk_name: ""

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "disk_name is required"
      when: disk_name == ""

    - name: Get volume info
      openstack.cloud.volume_info:
        name: "{{ disk_name }}"
      register: volume_info

    - name: Display warning if not found
      ansible.builtin.debug:
        msg: "Volume '{{ disk_name }}' not found. Nothing to delete."
      when: volume_info.volumes | length == 0

    - name: Check if volume is attached
      ansible.builtin.fail:
        msg: "Volume '{{ disk_name }}' is attached to a server. Detach or delete the server first."
      when: volume_info.volumes | length > 0 and volume_info.volumes[0].attachments | length > 0

    - name: Delete volume
      openstack.cloud.volume:
        state: absent
        name: "{{ disk_name }}"
        wait: true
      when: volume_info.volumes | length > 0

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Volume Deleted Successfully!
          ========================================
          Name: {{ disk_name }}
          ========================================
      when: volume_info.volumes | length > 0
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/disk-delete.yml --syntax-check`
Expected: "playbook: playbooks/infra/disk-delete.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/disk-delete.yml
git commit -m "feat: add disk-delete playbook"
```

---

## Task 11: Реализовать image-create-from-disk playbook

**Files:**
- Create: `playbooks/infra/image-create-from-disk.yml`

**Step 1: Создать playbook для создания образа из диска**

```yaml
# playbooks/infra/image-create-from-disk.yml
---
- name: Create image from disk
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    source_disk_name: ""
    image_name: ""

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "source_disk_name and image_name are required"
      when: source_disk_name == "" or image_name == ""

    - name: Get volume info
      openstack.cloud.volume_info:
        name: "{{ source_disk_name }}"
      register: volume_info

    - name: Fail if volume not found
      ansible.builtin.fail:
        msg: "Volume '{{ source_disk_name }}' not found"
      when: volume_info.volumes | length == 0

    - name: Check if volume is attached
      ansible.builtin.fail:
        msg: "Volume '{{ source_disk_name }}' is attached to a server. Stop the server first."
      when: volume_info.volumes[0].attachments | length > 0

    - name: Create image from volume (using openstack CLI)
      ansible.builtin.command:
        cmd: >
          openstack image create
          --volume {{ volume_info.volumes[0].id }}
          --disk-format raw
          --container-format bare
          {{ image_name }}
      register: image_create_result

    - name: Wait for image to become active
      openstack.cloud.image_info:
        name: "{{ image_name }}"
      register: image_info
      until: image_info.images | length > 0 and image_info.images[0].status == 'active'
      retries: 60
      delay: 10

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Created Successfully!
          ========================================
          Name: {{ image_name }}
          ID: {{ image_info.images[0].id }}
          Status: {{ image_info.images[0].status }}
          Size: {{ image_info.images[0].size | default(0) }} bytes

          Next: ./selectel.sh image-download --name "{{ image_name }}" --output ~/images/
          ========================================
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/image-create-from-disk.yml --syntax-check`
Expected: "playbook: playbooks/infra/image-create-from-disk.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/image-create-from-disk.yml
git commit -m "feat: add image-create-from-disk playbook"
```

---

## Task 12: Реализовать image-download playbook

**Files:**
- Create: `playbooks/infra/image-download.yml`

**Step 1: Создать playbook для скачивания образа**

```yaml
# playbooks/infra/image-download.yml
---
- name: Download image locally
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    image_name: ""
    output_dir: ""

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "image_name and output_dir are required"
      when: image_name == "" or output_dir == ""

    - name: Get image info
      openstack.cloud.image_info:
        name: "{{ image_name }}"
      register: image_info

    - name: Fail if image not found
      ansible.builtin.fail:
        msg: "Image '{{ image_name }}' not found"
      when: image_info.images | length == 0

    - name: Ensure output directory exists
      ansible.builtin.file:
        path: "{{ output_dir | expanduser }}"
        state: directory
        mode: '0755'

    - name: Set output filename
      ansible.builtin.set_fact:
        output_file: "{{ output_dir | expanduser }}/{{ image_name }}.raw"

    - name: Download image (using openstack CLI)
      ansible.builtin.command:
        cmd: "openstack image save --file {{ output_file }} {{ image_info.images[0].id }}"

    - name: Get file size
      ansible.builtin.stat:
        path: "{{ output_file }}"
      register: file_stat

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Downloaded Successfully!
          ========================================
          Name: {{ image_name }}
          File: {{ output_file }}
          Size: {{ (file_stat.stat.size / 1024 / 1024 / 1024) | round(2) }} GB
          ========================================
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/image-download.yml --syntax-check`
Expected: "playbook: playbooks/infra/image-download.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/image-download.yml
git commit -m "feat: add image-download playbook"
```

---

## Task 13: Реализовать image-upload playbook

**Files:**
- Create: `playbooks/infra/image-upload.yml`

**Step 1: Создать playbook для загрузки образа**

```yaml
# playbooks/infra/image-upload.yml
---
- name: Upload local image to cloud
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    image_file: ""
    image_name: ""

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "image_file and image_name are required"
      when: image_file == "" or image_name == ""

    - name: Check if file exists
      ansible.builtin.stat:
        path: "{{ image_file | expanduser }}"
      register: file_stat

    - name: Fail if file not found
      ansible.builtin.fail:
        msg: "File '{{ image_file }}' not found"
      when: not file_stat.stat.exists

    - name: Determine disk format from extension
      ansible.builtin.set_fact:
        disk_format: "{{ 'qcow2' if image_file.endswith('.qcow2') else 'raw' }}"

    - name: Upload image
      openstack.cloud.image:
        state: present
        name: "{{ image_name }}"
        filename: "{{ image_file | expanduser }}"
        container_format: bare
        disk_format: "{{ disk_format }}"
        wait: true
      register: image_result

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Uploaded Successfully!
          ========================================
          Name: {{ image_name }}
          ID: {{ image_result.image.id }}
          Status: {{ image_result.image.status }}

          Next: ./selectel.sh gpu-start --image "{{ image_name }}"
          ========================================
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/image-upload.yml --syntax-check`
Expected: "playbook: playbooks/infra/image-upload.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/image-upload.yml
git commit -m "feat: add image-upload playbook"
```

---

## Task 14: Реализовать image-delete playbook

**Files:**
- Create: `playbooks/infra/image-delete.yml`

**Step 1: Создать playbook для удаления образа**

```yaml
# playbooks/infra/image-delete.yml
---
- name: Delete image from cloud
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    image_name: ""

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "image_name is required"
      when: image_name == ""

    - name: Get image info
      openstack.cloud.image_info:
        name: "{{ image_name }}"
      register: image_info

    - name: Display warning if not found
      ansible.builtin.debug:
        msg: "Image '{{ image_name }}' not found. Nothing to delete."
      when: image_info.images | length == 0

    - name: Delete image
      openstack.cloud.image:
        state: absent
        name: "{{ image_name }}"
      when: image_info.images | length > 0

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Deleted Successfully!
          ========================================
          Name: {{ image_name }}
          ========================================
      when: image_info.images | length > 0
```

**Step 2: Проверить синтаксис playbook**

Run: `ansible-playbook playbooks/infra/image-delete.yml --syntax-check`
Expected: "playbook: playbooks/infra/image-delete.yml" (без ошибок)

**Step 3: Commit**

```bash
git add playbooks/infra/image-delete.yml
git commit -m "feat: add image-delete playbook"
```

---

## Task 15: Обновить README.md с документацией

**Files:**
- Modify: `README.md`

**Step 1: Добавить секцию про управление инфраструктурой**

Добавить после существующей документации:

```markdown
## Infrastructure Management (Selectel API)

### Prerequisites

1. Install OpenStack SDK and CLI:
   ```bash
   sudo apt install python3-openstacksdk python3-openstackclient ansible
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

# VM Management
./selectel.sh gpu-start --disk "my-disk"     # Start GPU VM with existing disk
./selectel.sh gpu-start --image "my-image"   # Start GPU VM from image
./selectel.sh gpu-stop                        # Stop GPU VM (keeps disk)
./selectel.sh setup-start                     # Start VM without GPU (initial setup)

# Disk Management
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
./selectel.sh image-create-from-disk --disk "setup-vm-1-boot" --name "base-image"
./selectel.sh image-download --name "base-image" --output ~/images/
./selectel.sh gpu-stop
./selectel.sh disk-delete --name "setup-vm-1-boot"
```

**Daily Usage:**
```bash
./selectel.sh gpu-start --image "base-image"
# ... work ...
./selectel.sh gpu-stop
```
```

**Step 2: Проверить что README читаемый**

Run: `head -50 README.md`
Expected: Начало файла с разметкой markdown

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add infrastructure management documentation"
```

---

## Task 16: Финальная проверка синтаксиса всех playbooks

**Files:**
- All playbooks in `playbooks/infra/`

**Step 1: Проверить синтаксис всех infra playbooks**

Run:
```bash
for f in playbooks/infra/*.yml; do
  echo "Checking $f..."
  ansible-playbook "$f" --syntax-check || exit 1
done
echo "All playbooks OK"
```
Expected: "All playbooks OK"

**Step 2: Проверить selectel.sh без .env**

Run: `./selectel.sh 2>&1 | head -2`
Expected: "Error: .env file not found..."

**Step 3: Финальный commit (если есть изменения)**

```bash
git status
# Если есть несохранённые изменения:
git add -A
git commit -m "chore: final cleanup"
```

---

## Summary

После выполнения всех задач будет создана полная инфраструктура:

- **selectel.sh** - CLI обёртка для управления инфраструктурой
- **.env.example** - шаблон конфигурации
- **playbooks/infra/** - 12 Ansible playbooks:
  - `list-flavors.yml` - список конфигураций VM
  - `list-images.yml` - список образов
  - `list-disks.yml` - список дисков
  - `list-vms.yml` - список серверов
  - `gpu-start.yml` - запуск GPU VM
  - `gpu-stop.yml` - остановка GPU VM
  - `setup-start.yml` - запуск VM без GPU для настройки
  - `disk-delete.yml` - удаление диска
  - `image-create-from-disk.yml` - создание образа
  - `image-download.yml` - скачивание образа
  - `image-upload.yml` - загрузка образа
  - `image-delete.yml` - удаление образа
