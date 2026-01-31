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
EXTERNAL_NETWORK=external-network
ROUTER_NAME=router
ALLOCATE_FLOATING_IP=true

# === Опции ===
SECURITY_GROUP=default

# === SSH ===
SSH_KEY_FILE=~/.ssh/id_ed25519.pub
SSH_KEY_NAME=ansible-key
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
  network-info          Show network configuration

  network-setup         Create network, subnet, router and security group (one time)

  gpu-start             Start GPU VM
    --disk <name>       Use existing disk
    --image <name>      Create from image
    --name <name>       VM name (default: gpu-vm-YYYYMMDD-HHMMSS)

  gpu-stop              Stop and delete GPU VM (keeps disk)
    --name <name>       VM name (default: gpu-vm-1)

  setup-start           Start VM without GPU (for initial setup)
    --name <name>       VM name (default: setup-vm-YYYYMMDD-HHMMSS)

  disk-delete           Delete a disk
    --name <name>       Disk name

  image-create-from-disk Create image from disk
    --disk <name>       Source disk name
    --name <name>       Image name

  image-download        Download image locally
    --name <name>       Image name
    --output <path>     Output directory
    --force             Overwrite existing file

  image-upload          Upload local image
    --file <path>       Image file path
    --name <name>       Image name
    --force             Overwrite existing image

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
    network-info)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/network-info.yml"
        ;;
    network-setup)
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/network-setup.yml"
        ;;
    gpu-start)
        DISK_NAME=""
        IMAGE_NAME=""
        VM_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --disk) DISK_NAME="$2"; shift 2 ;;
                --image) IMAGE_NAME="$2"; shift 2 ;;
                --name) VM_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        # Валидация: --disk и --image взаимоисключающие
        if [[ -n "$DISK_NAME" && -n "$IMAGE_NAME" ]]; then
            echo "Error: specify either --disk or --image, not both"
            exit 1
        fi
        # Передаём extra-vars в JSON для поддержки пробелов в именах
        EXTRA_VARS="{}"
        [[ -n "$VM_NAME" ]] && EXTRA_VARS=$(echo "$EXTRA_VARS" | jq --arg v "$VM_NAME" '. + {vm_name: $v}')
        if [[ -n "$DISK_NAME" ]]; then
            EXTRA_VARS=$(echo "$EXTRA_VARS" | jq --arg v "$DISK_NAME" '. + {boot_disk_name: $v}')
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-start.yml" -e "$EXTRA_VARS"
        elif [[ -n "$IMAGE_NAME" ]]; then
            EXTRA_VARS=$(echo "$EXTRA_VARS" | jq --arg v "$IMAGE_NAME" '. + {boot_image_name: $v}')
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-start.yml" -e "$EXTRA_VARS"
        else
            echo "Error: specify --disk or --image"
            exit 1
        fi
        ;;
    gpu-stop)
        VM_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) VM_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        if [[ -n "$VM_NAME" ]]; then
            EXTRA_VARS=$(jq -n --arg v "$VM_NAME" '{vm_name: $v}')
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-stop.yml" -e "$EXTRA_VARS"
        else
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/gpu-stop.yml"
        fi
        ;;
    setup-start)
        VM_NAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) VM_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        if [[ -n "$VM_NAME" ]]; then
            EXTRA_VARS=$(jq -n --arg v "$VM_NAME" '{vm_name: $v}')
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/setup-start.yml" -e "$EXTRA_VARS"
        else
            ansible-playbook "$SCRIPT_DIR/playbooks/infra/setup-start.yml"
        fi
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
        EXTRA_VARS=$(jq -n --arg v "$DISK_NAME" '{disk_name: $v}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/disk-delete.yml" -e "$EXTRA_VARS"
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
        EXTRA_VARS=$(jq -n --arg d "$DISK_NAME" --arg n "$IMAGE_NAME" '{source_disk_name: $d, image_name: $n}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-create-from-disk.yml" -e "$EXTRA_VARS"
        ;;
    image-download)
        IMAGE_NAME=""
        OUTPUT_DIR=""
        FORCE=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) IMAGE_NAME="$2"; shift 2 ;;
                --output) OUTPUT_DIR="$2"; shift 2 ;;
                --force) FORCE=true; shift ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$IMAGE_NAME" || -z "$OUTPUT_DIR" ]] && { echo "Error: --name and --output required"; exit 1; }
        EXTRA_VARS=$(jq -n --arg n "$IMAGE_NAME" --arg o "$OUTPUT_DIR" --argjson f "$FORCE" '{image_name: $n, output_dir: $o, force: $f}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-download.yml" -e "$EXTRA_VARS"
        ;;
    image-upload)
        FILE_PATH=""
        IMAGE_NAME=""
        FORCE=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --file) FILE_PATH="$2"; shift 2 ;;
                --name) IMAGE_NAME="$2"; shift 2 ;;
                --force) FORCE=true; shift ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        [[ -z "$FILE_PATH" || -z "$IMAGE_NAME" ]] && { echo "Error: --file and --name required"; exit 1; }
        EXTRA_VARS=$(jq -n --arg f "$FILE_PATH" --arg n "$IMAGE_NAME" --argjson force "$FORCE" '{image_file: $f, image_name: $n, force: $force}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-upload.yml" -e "$EXTRA_VARS"
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
        EXTRA_VARS=$(jq -n --arg v "$IMAGE_NAME" '{image_name: $v}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/image-delete.yml" -e "$EXTRA_VARS"
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
# VM names (defaults, can be overridden with --name)
gpu_vm_name: "gpu-vm-{{ ansible_date_time.date | replace('-','') }}-{{ ansible_date_time.time | replace(':','') }}"
setup_vm_name: "setup-vm-{{ ansible_date_time.date | replace('-','') }}-{{ ansible_date_time.time | replace(':','') }}"

# Disk defaults
default_disk_size: "{{ lookup('env', 'DISK_SIZE_GB') | default(10, true) | int }}"
default_disk_type: "{{ lookup('env', 'DISK_TYPE') | default('universal', true) }}"

# Network
network_name: "{{ lookup('env', 'NETWORK_NAME') | default('net', true) }}"
subnet_cidr: "{{ lookup('env', 'SUBNET_CIDR') | default('192.168.0.0/24', true) }}"
external_network: "{{ lookup('env', 'EXTERNAL_NETWORK') | default('external-network', true) }}"
router_name: "{{ lookup('env', 'ROUTER_NAME') | default('router', true) }}"
allocate_floating_ip: "{{ lookup('env', 'ALLOCATE_FLOATING_IP') | default('true', true) | bool }}"
security_group: "{{ lookup('env', 'SECURITY_GROUP') | default('default', true) }}"

# Flavors
gpu_flavor_id: "{{ lookup('env', 'GPU_FLAVOR_ID') }}"
setup_flavor_id: "{{ lookup('env', 'SETUP_FLAVOR_ID') }}"

# SSH key
ssh_key_file: "{{ lookup('env', 'SSH_KEY_FILE') | default('~/.ssh/id_ed25519.pub', true) }}"
ssh_key_name: "{{ lookup('env', 'SSH_KEY_NAME') | default('ansible-key', true) }}"

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

## Task 7: Реализовать network-setup и network-info playbooks

**Files:**
- Create: `playbooks/infra/network-setup.yml`
- Create: `playbooks/infra/network-info.yml`

**Step 1: Создать playbook для настройки сети**

```yaml
# playbooks/infra/network-setup.yml
---
- name: Setup network infrastructure
  hosts: localhost
  connection: local
  gather_facts: false

  vars_files:
    - vars/main.yml

  tasks:
    - name: Create network
      openstack.cloud.network:
        state: present
        name: "{{ network_name }}"
      register: network

    - name: Create subnet
      openstack.cloud.subnet:
        state: present
        name: "{{ network_name }}-subnet"
        network_name: "{{ network_name }}"
        cidr: "{{ subnet_cidr }}"
        dns_nameservers:
          - 8.8.8.8
          - 8.8.4.4
      register: subnet

    - name: Create router
      openstack.cloud.router:
        state: present
        name: "{{ router_name }}"
        network: "{{ external_network }}"
        interfaces:
          - "{{ network_name }}-subnet"
      register: router

    - name: Create security group (if not default)
      openstack.cloud.security_group:
        state: present
        name: "{{ security_group }}"
        description: "Security group for Ansible-managed VMs"
      register: sg
      when: security_group != 'default'

    # Добавляем правила всегда — включая default SG
    # Используем failed_when вместо ignore_errors для правильной обработки дубликатов
    - name: Add SSH rule to security group
      openstack.cloud.security_group_rule:
        state: present
        security_group: "{{ security_group }}"
        protocol: tcp
        port_range_min: 22
        port_range_max: 22
        remote_ip_prefix: 0.0.0.0/0
      register: ssh_rule_result
      failed_when: ssh_rule_result.failed and 'already exists' not in (ssh_rule_result.msg | default(''))

    - name: Add ICMP rule to security group
      openstack.cloud.security_group_rule:
        state: present
        security_group: "{{ security_group }}"
        protocol: icmp
        remote_ip_prefix: 0.0.0.0/0
      register: icmp_rule_result
      failed_when: icmp_rule_result.failed and 'already exists' not in (icmp_rule_result.msg | default(''))

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Network Infrastructure Created!
          ========================================
          Network: {{ network.network.name }} ({{ network.network.id }})
          Subnet: {{ subnet.subnet.name }} ({{ subnet.subnet.cidr }})
          Router: {{ router.router.name }} ({{ router.router.id }})
          Security Group: {{ security_group }}
          ========================================
```

**Step 2: Создать playbook для просмотра сети**

```yaml
# playbooks/infra/network-info.yml
---
- name: Show network information
  hosts: localhost
  connection: local
  gather_facts: false

  vars_files:
    - vars/main.yml

  tasks:
    - name: Get network info
      openstack.cloud.networks_info:
        name: "{{ network_name }}"
      register: networks

    - name: Get subnet info
      openstack.cloud.subnets_info:
        name: "{{ network_name }}-subnet"
      register: subnets

    - name: Get router info
      openstack.cloud.routers_info:
        name: "{{ router_name }}"
      register: routers

    - name: Get security group info
      openstack.cloud.security_group_info:
        name: "{{ security_group }}"
      register: sgs

    - name: Display network info
      ansible.builtin.debug:
        msg: |

          Network Configuration:
          ======================
          Network: {{ networks.networks[0].name if networks.networks | length > 0 else 'NOT FOUND' }}
          Subnet: {{ subnets.subnets[0].cidr if subnets.subnets | length > 0 else 'NOT FOUND' }}
          Router: {{ routers.routers[0].name if routers.routers | length > 0 else 'NOT FOUND' }}
          Security Group: {{ sgs.security_groups[0].name if sgs.security_groups | length > 0 else 'NOT FOUND' }}
          External Network: {{ external_network }}
```

**Step 3: Проверить синтаксис playbooks**

Run: `ansible-playbook playbooks/infra/network-setup.yml --syntax-check && ansible-playbook playbooks/infra/network-info.yml --syntax-check`
Expected: Оба playbook без ошибок

**Step 4: Commit**

```bash
git add playbooks/infra/network-setup.yml playbooks/infra/network-info.yml
git commit -m "feat: add network-setup and network-info playbooks"
```

---

## Task 8: Реализовать gpu-start playbook

**Files:**
- Create: `playbooks/infra/gpu-start.yml`

**Step 1: Создать playbook для запуска GPU VM**

```yaml
# playbooks/infra/gpu-start.yml
---
- name: Start GPU VM
  hosts: localhost
  connection: local
  gather_facts: true  # Нужно для ansible_date_time

  vars_files:
    - vars/main.yml

  vars:
    boot_disk_name: ""
    boot_image_name: ""
    # vm_name может быть переопределён через -e, иначе генерируется с timestamp
    flavor_id: "{{ gpu_flavor_id }}"

  tasks:
    # === Валидация входных данных ===
    - name: Validate boot source
      ansible.builtin.fail:
        msg: "Specify either boot_disk_name or boot_image_name"
      when: boot_disk_name == "" and boot_image_name == ""

    - name: Validate GPU_FLAVOR_ID is set
      ansible.builtin.fail:
        msg: "GPU_FLAVOR_ID must be set in .env"
      when: flavor_id == ""

    # === Генерация имени VM если не задано ===
    - name: Set default VM name with timestamp
      ansible.builtin.set_fact:
        vm_name: "{{ vm_name | default('gpu-vm-' + ansible_date_time.date | replace('-','') + '-' + ansible_date_time.time | replace(':','')) }}"

    # === SSH keypair с проверкой fingerprint ===
    - name: Read SSH public key
      ansible.builtin.set_fact:
        ssh_public_key: "{{ lookup('file', ssh_key_file | expanduser) }}"

    - name: Calculate local key fingerprint
      ansible.builtin.shell: |
        ssh-keygen -l -f {{ ssh_key_file | expanduser }} | awk '{print $2}'
      register: local_fingerprint
      changed_when: false

    - name: Get existing keypair info
      openstack.cloud.keypair_info:
        name: "{{ ssh_key_name }}"
      register: existing_keypair

    - name: Fail if keypair exists with different fingerprint
      ansible.builtin.fail:
        msg: "Keypair '{{ ssh_key_name }}' exists with different fingerprint. Cloud: {{ existing_keypair.keypairs[0].fingerprint }}, Local: {{ local_fingerprint.stdout }}"
      when: >
        existing_keypair.keypairs | length > 0 and
        existing_keypair.keypairs[0].fingerprint != local_fingerprint.stdout

    - name: Ensure keypair exists
      openstack.cloud.keypair:
        state: present
        name: "{{ ssh_key_name }}"
        public_key: "{{ ssh_public_key }}"
      when: existing_keypair.keypairs | length == 0

    # === Boot from existing disk ===
    - name: Get existing disk info
      openstack.cloud.volume_info:
        name: "{{ boot_disk_name }}"
      register: disk_info
      when: boot_disk_name != ""

    - name: Validate exactly one disk found
      ansible.builtin.fail:
        msg: "Expected exactly 1 disk named '{{ boot_disk_name }}', found {{ disk_info.volumes | length }}"
      when: boot_disk_name != "" and disk_info.volumes | length != 1

    - name: Validate disk is available (not in-use)
      ansible.builtin.fail:
        msg: "Disk '{{ boot_disk_name }}' is in-use (status: {{ disk_info.volumes[0].status }}). Detach it first."
      when: boot_disk_name != "" and disk_info.volumes | length == 1 and disk_info.volumes[0].status != 'available'

    - name: Create server from existing disk
      openstack.cloud.server:
        state: present
        name: "{{ vm_name }}"
        flavor: "{{ flavor_id }}"
        boot_volume: "{{ disk_info.volumes[0].id }}"
        terminate_volume: false
        key_name: "{{ ssh_key_name }}"
        security_groups:
          - "{{ security_group }}"
        networks:
          - name: "{{ network_name }}"
        availability_zone: "{{ availability_zone }}"
        auto_ip: false
        timeout: 600
        wait: true
      register: server_disk
      when: boot_disk_name != ""

    - name: Set server variable (disk branch)
      ansible.builtin.set_fact:
        server: "{{ server_disk }}"
      when: boot_disk_name != "" and server_disk.server is defined

    # === Boot from image (create new disk) ===
    - name: Get image info
      openstack.cloud.image_info:
        image: "{{ boot_image_name }}"
      register: image_info
      when: boot_image_name != ""

    - name: Validate exactly one image found
      ansible.builtin.fail:
        msg: "Expected exactly 1 image named '{{ boot_image_name }}', found {{ image_info.images | length }}"
      when: boot_image_name != "" and image_info.images | length != 1

    - name: Calculate disk size (max of default and image min_disk)
      ansible.builtin.set_fact:
        actual_disk_size: "{{ [default_disk_size | int, image_info.images[0].min_disk | default(0) | int] | max }}"
      when: boot_image_name != ""

    # Проверяем, что boot volume с таким именем не существует
    - name: Check if boot volume already exists
      openstack.cloud.volume_info:
        name: "{{ vm_name }}-boot"
      register: existing_boot_volume
      when: boot_image_name != ""

    - name: Fail if boot volume already exists
      ansible.builtin.fail:
        msg: "Boot volume '{{ vm_name }}-boot' already exists. Use different --name or delete existing volume."
      when: boot_image_name != "" and existing_boot_volume.volumes | length > 0

    # Используем block/rescue для отката тома при ошибке создания сервера
    - name: Create volume and server from image
      block:
        - name: Create boot volume from image
          openstack.cloud.volume:
            state: present
            name: "{{ vm_name }}-boot"
            size: "{{ actual_disk_size }}"
            volume_type: "{{ default_disk_type }}"
            image: "{{ image_info.images[0].id }}"
            availability_zone: "{{ availability_zone }}"
            wait: true
          register: new_volume

        - name: Create server from new volume
          openstack.cloud.server:
            state: present
            name: "{{ vm_name }}"
            flavor: "{{ flavor_id }}"
            boot_volume: "{{ new_volume.volume.id }}"
            terminate_volume: false
            key_name: "{{ ssh_key_name }}"
            security_groups:
              - "{{ security_group }}"
            networks:
              - name: "{{ network_name }}"
            availability_zone: "{{ availability_zone }}"
            auto_ip: false
            timeout: 600
            wait: true
          register: server_image

        - name: Set server variable (image branch)
          ansible.builtin.set_fact:
            server: "{{ server_image }}"

      rescue:
        - name: Cleanup volume on server creation failure
          openstack.cloud.volume:
            state: absent
            name: "{{ vm_name }}-boot"
          when: new_volume.volume is defined

        - name: Fail with original error
          ansible.builtin.fail:
            msg: "Server creation failed. Volume {{ vm_name }}-boot was cleaned up."
      when: boot_image_name != ""

    # === Floating IP ===
    - name: Allocate floating IP
      openstack.cloud.floating_ip:
        state: present
        server: "{{ server.server.id }}"
        network: "{{ external_network }}"
        wait: true
      register: floating_ip
      when: allocate_floating_ip | bool

    # === Результат ===
    - name: Display server info
      ansible.builtin.debug:
        msg: |

          ========================================
          GPU VM Created Successfully!
          ========================================
          Name: {{ server.server.name }}
          ID: {{ server.server.id }}
          Status: {{ server.server.status }}
          Floating IP: {{ floating_ip.floating_ip.floating_ip_address if floating_ip is defined and floating_ip.floating_ip is defined else 'not allocated' }}

          Connect: ssh root@{{ floating_ip.floating_ip.floating_ip_address if floating_ip is defined and floating_ip.floating_ip is defined else '<floating_ip>' }}
          ========================================
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

## Task 9: Реализовать gpu-stop playbook

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
    # vm_name передаётся через -e или используется default
    vm_name: ""

  tasks:
    # Если vm_name не указан, показать список VM и завершить
    - name: Get all servers (when no vm_name provided)
      openstack.cloud.server_info:
      register: all_servers
      when: vm_name == ""

    - name: Display VM list and exit (when no vm_name provided)
      ansible.builtin.fail:
        msg: |
          vm_name is required. Available VMs:
          {% for srv in all_servers.servers | sort(attribute='created', reverse=true) %}
          - {{ srv.name }} (created: {{ srv.created }})
          {% endfor %}
          Use: ./selectel.sh gpu-stop --name <vm_name>
      when: vm_name == "" and all_servers.servers | length > 0

    - name: No VMs found (when no vm_name provided)
      ansible.builtin.fail:
        msg: "No VMs found. Nothing to delete."
      when: vm_name == "" and all_servers.servers | length == 0

    - name: Get server info
      openstack.cloud.server_info:
        server: "{{ vm_name }}"
      register: server_info

    - name: Display warning if no server found
      ansible.builtin.debug:
        msg: "No server named '{{ vm_name }}' found. Nothing to delete."
      when: server_info.servers | length == 0

    - name: Validate exactly one VM found
      ansible.builtin.fail:
        msg: |
          Expected exactly 1 VM named '{{ vm_name }}', found {{ server_info.servers | length }}:
          {% for srv in server_info.servers %}
          - {{ srv.name }} (ID: {{ srv.id }}, created: {{ srv.created }})
          {% endfor %}
          Use server ID directly or ensure unique VM names.
      when: server_info.servers | length > 1

    - name: Release floating IP
      openstack.cloud.floating_ip:
        state: absent
        server: "{{ server_info.servers[0].id }}"
        floating_ip_address: "{{ item }}"
      loop: "{{ server_info.servers[0].addresses | dict2items | map(attribute='value') | flatten | selectattr('OS-EXT-IPS:type', 'equalto', 'floating') | map(attribute='addr') | list }}"
      when: server_info.servers | length > 0
      ignore_errors: true

    - name: Delete server (keeps attached volumes due to terminate_volume: false at creation)
      openstack.cloud.server:
        state: absent
        name: "{{ vm_name }}"
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
          Note: Boot disk is preserved (terminate_volume: false).
                Use 'disk-delete --name <disk>' to remove it.
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

## Task 10: Реализовать setup-start playbook

**Files:**
- Create: `playbooks/infra/setup-start.yml`

**Step 1: Создать playbook для запуска VM без GPU**

```yaml
# playbooks/infra/setup-start.yml
---
- name: Start setup VM (without GPU, for initial configuration)
  hosts: localhost
  connection: local
  gather_facts: true  # Нужно для ansible_date_time

  vars_files:
    - vars/main.yml

  vars:
    # vm_name может быть переопределён через -e
    flavor_id: "{{ setup_flavor_id }}"
    # base_image задаётся интерактивно если не указан
    base_image: ""

  tasks:
    # === Валидация ===
    - name: Validate flavor is set
      ansible.builtin.fail:
        msg: "SETUP_FLAVOR_ID must be set in .env"
      when: flavor_id == ""

    # === Интерактивный выбор образа если не указан ===
    - name: Get all public images (when base_image not specified)
      openstack.cloud.image_info:
      register: all_images
      when: base_image == ""

    - name: Display available images and fail (when base_image not specified)
      ansible.builtin.fail:
        msg: |
          base_image is required. Available Ubuntu images:
          {% for img in all_images.images | selectattr('name', 'search', 'Ubuntu') | sort(attribute='name') %}
          - {{ img.name }}
          {% endfor %}

          Set BASE_IMAGE_NAME in .env or pass via -e base_image="<name>"
      when: base_image == ""

    # === Генерация имени VM если не задано ===
    - name: Set default VM name with timestamp
      ansible.builtin.set_fact:
        vm_name: "{{ vm_name | default('setup-vm-' + ansible_date_time.date | replace('-','') + '-' + ansible_date_time.time | replace(':','')) }}"

    # === SSH keypair с проверкой fingerprint ===
    - name: Read SSH public key
      ansible.builtin.set_fact:
        ssh_public_key: "{{ lookup('file', ssh_key_file | expanduser) }}"

    - name: Calculate local key fingerprint
      ansible.builtin.shell: |
        ssh-keygen -l -f {{ ssh_key_file | expanduser }} | awk '{print $2}'
      register: local_fingerprint
      changed_when: false

    - name: Get existing keypair info
      openstack.cloud.keypair_info:
        name: "{{ ssh_key_name }}"
      register: existing_keypair

    - name: Fail if keypair exists with different fingerprint
      ansible.builtin.fail:
        msg: "Keypair '{{ ssh_key_name }}' exists with different fingerprint."
      when: >
        existing_keypair.keypairs | length > 0 and
        existing_keypair.keypairs[0].fingerprint != local_fingerprint.stdout

    - name: Ensure keypair exists
      openstack.cloud.keypair:
        state: present
        name: "{{ ssh_key_name }}"
        public_key: "{{ ssh_public_key }}"
      when: existing_keypair.keypairs | length == 0

    # === Image ===
    - name: Get base image info
      openstack.cloud.image_info:
        image: "{{ base_image }}"
      register: image_info

    - name: Validate exactly one image found
      ansible.builtin.fail:
        msg: "Expected exactly 1 image named '{{ base_image }}', found {{ image_info.images | length }}"
      when: image_info.images | length != 1

    # === Disk ===
    - name: Calculate disk size (max of default and image min_disk)
      ansible.builtin.set_fact:
        actual_disk_size: "{{ [default_disk_size | int, image_info.images[0].min_disk | default(0) | int] | max }}"

    # Проверяем, что boot volume не существует
    - name: Check if boot volume already exists
      openstack.cloud.volume_info:
        name: "{{ vm_name }}-boot"
      register: existing_boot_volume

    - name: Fail if boot volume already exists
      ansible.builtin.fail:
        msg: "Boot volume '{{ vm_name }}-boot' already exists. Use different --name or delete existing volume."
      when: existing_boot_volume.volumes | length > 0

    # Используем block/rescue для отката тома при ошибке
    - name: Create volume and server
      block:
        - name: Create boot volume
          openstack.cloud.volume:
            state: present
            name: "{{ vm_name }}-boot"
            size: "{{ actual_disk_size }}"
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
            terminate_volume: false
            key_name: "{{ ssh_key_name }}"
            security_groups:
              - "{{ security_group }}"
            networks:
              - name: "{{ network_name }}"
            availability_zone: "{{ availability_zone }}"
            auto_ip: false
            timeout: 600
            wait: true
          register: server

      rescue:
        - name: Cleanup volume on server creation failure
          openstack.cloud.volume:
            state: absent
            name: "{{ vm_name }}-boot"
          when: boot_volume.volume is defined

        - name: Fail with original error
          ansible.builtin.fail:
            msg: "Server creation failed. Volume {{ vm_name }}-boot was cleaned up."

    # === Floating IP ===
    - name: Allocate floating IP
      openstack.cloud.floating_ip:
        state: present
        server: "{{ server.server.id }}"
        network: "{{ external_network }}"
        wait: true
      register: floating_ip
      when: allocate_floating_ip | bool

    # === Результат ===
    - name: Display server info
      ansible.builtin.debug:
        msg: |

          ========================================
          Setup VM Created Successfully!
          ========================================
          Name: {{ server.server.name }}
          ID: {{ server.server.id }}
          Status: {{ server.server.status }}
          Floating IP: {{ floating_ip.floating_ip.floating_ip_address if floating_ip is defined and floating_ip.floating_ip is defined else 'not allocated' }}

          Next steps:
          1. Add IP to inventory/hosts.yml
          2. Run: ansible-playbook playbooks/site.yml
          3. Create image: ./selectel.sh image-create-from-disk --disk "{{ vm_name }}-boot" --name "base-image"

          Connect: ssh root@{{ floating_ip.floating_ip.floating_ip_address if floating_ip is defined and floating_ip.floating_ip is defined else '<floating_ip>' }}
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

## Task 11: Реализовать disk-delete playbook

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

    - name: Validate exactly one volume found
      ansible.builtin.fail:
        msg: |
          Expected exactly 1 volume named '{{ disk_name }}', found {{ volume_info.volumes | length }}:
          {% for vol in volume_info.volumes %}
          - {{ vol.name }} (ID: {{ vol.id }}, Size: {{ vol.size }}GB)
          {% endfor %}
          Use volume ID directly or use unique names.
      when: volume_info.volumes | length > 1

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

## Task 12: Реализовать image-create-from-disk playbook

**Files:**
- Create: `playbooks/infra/image-create-from-disk.yml`

**Step 1: Создать playbook для создания образа из диска**

> **Примечание**: К сожалению, `openstack.cloud` collection не имеет модуля для создания образа из volume напрямую. Используем `openstack.cloud.image` для upload, но для volume→image нужен CLI. Однако мы можем минимизировать использование CLI и ждать по ID.

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
    # === Валидация ===
    - name: Validate input
      ansible.builtin.fail:
        msg: "source_disk_name and image_name are required"
      when: source_disk_name == "" or image_name == ""

    - name: Check if image with this name already exists
      openstack.cloud.image_info:
        image: "{{ image_name }}"
      register: existing_image

    - name: Fail if image already exists
      ansible.builtin.fail:
        msg: "Image '{{ image_name }}' already exists. Choose a different name or delete the existing image."
      when: existing_image.images | length > 0

    # === Volume info ===
    - name: Get volume info
      openstack.cloud.volume_info:
        name: "{{ source_disk_name }}"
      register: volume_info

    - name: Validate exactly one volume found
      ansible.builtin.fail:
        msg: "Expected exactly 1 volume named '{{ source_disk_name }}', found {{ volume_info.volumes | length }}"
      when: volume_info.volumes | length != 1

    - name: Check if volume is attached
      ansible.builtin.fail:
        msg: "Volume '{{ source_disk_name }}' is attached to a server. Stop the server first."
      when: volume_info.volumes[0].attachments | length > 0

    # === Create image (CLI required for volume→image) ===
    - name: Create image from volume
      ansible.builtin.command:
        cmd: >
          openstack image create
          --volume {{ volume_info.volumes[0].id }}
          --disk-format raw
          --container-format bare
          --format json
          {{ image_name }}
      register: image_create_result

    - name: Parse image ID from result
      ansible.builtin.set_fact:
        created_image_id: "{{ (image_create_result.stdout | from_json).id }}"

    # === Wait by ID (not by name) ===
    - name: Wait for image to become active (by ID)
      openstack.cloud.image_info:
        image: "{{ created_image_id }}"
      register: image_info
      until: image_info.images | length > 0 and image_info.images[0].status == 'active'
      retries: 60
      delay: 10

    # === Результат ===
    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Created Successfully!
          ========================================
          Name: {{ image_name }}
          ID: {{ created_image_id }}
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

## Task 13: Реализовать image-download playbook

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
    force: false  # Требовать --force для перезаписи

  tasks:
    - name: Validate input
      ansible.builtin.fail:
        msg: "image_name and output_dir are required"
      when: image_name == "" or output_dir == ""

    - name: Get image info
      openstack.cloud.image_info:
        image: "{{ image_name }}"
      register: image_info

    - name: Fail if image not found
      ansible.builtin.fail:
        msg: "Image '{{ image_name }}' not found"
      when: image_info.images | length == 0

    - name: Validate exactly one image found
      ansible.builtin.fail:
        msg: |
          Expected exactly 1 image named '{{ image_name }}', found {{ image_info.images | length }}:
          {% for img in image_info.images %}
          - {{ img.name }} (ID: {{ img.id }})
          {% endfor %}
          Use image ID directly or use unique names.
      when: image_info.images | length > 1

    - name: Ensure output directory exists
      ansible.builtin.file:
        path: "{{ output_dir | expanduser }}"
        state: directory
        mode: '0755'

    - name: Set output filename
      ansible.builtin.set_fact:
        output_file: "{{ output_dir | expanduser }}/{{ image_name }}.raw"

    - name: Check if output file already exists
      ansible.builtin.stat:
        path: "{{ output_file }}"
      register: existing_file

    - name: Fail if file exists and force is false
      ansible.builtin.fail:
        msg: "File '{{ output_file }}' already exists. Use --force to overwrite."
      when: existing_file.stat.exists and not force | bool

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

## Task 14: Реализовать image-upload playbook

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
    force: false  # Требовать --force для перезаписи

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

    - name: Check if image with same name already exists
      openstack.cloud.image_info:
        image: "{{ image_name }}"
      register: existing_image

    - name: Fail if image exists and force is false
      ansible.builtin.fail:
        msg: "Image '{{ image_name }}' already exists. Use --force to overwrite."
      when: existing_image.images | length > 0 and not force | bool

    - name: Delete existing image if force is true
      openstack.cloud.image:
        state: absent
        name: "{{ image_name }}"
      when: existing_image.images | length > 0 and force | bool

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

## Task 15: Реализовать image-delete playbook

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
        image: "{{ image_name }}"
      register: image_info

    - name: Display warning if not found
      ansible.builtin.debug:
        msg: "Image '{{ image_name }}' not found. Nothing to delete."
      when: image_info.images | length == 0

    - name: Validate exactly one image found
      ansible.builtin.fail:
        msg: |
          Expected exactly 1 image named '{{ image_name }}', found {{ image_info.images | length }}:
          {% for img in image_info.images %}
          - {{ img.name }} (ID: {{ img.id }})
          {% endfor %}
          Use image ID directly or use unique names.
      when: image_info.images | length > 1

    - name: Delete image
      openstack.cloud.image:
        state: absent
        name: "{{ image_name }}"
      when: image_info.images | length == 1

    - name: Display result
      ansible.builtin.debug:
        msg: |

          ========================================
          Image Deleted Successfully!
          ========================================
          Name: {{ image_name }}
          ========================================
      when: image_info.images | length == 1
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

## Task 16: Обновить README.md с документацией

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
./selectel.sh network-info    # Network configuration

# Network setup (one time)
./selectel.sh network-setup   # Create network, subnet, router, security group

# VM Management
./selectel.sh gpu-start --disk "my-disk"                    # Start GPU VM with existing disk
./selectel.sh gpu-start --image "my-image"                  # Start GPU VM from image
./selectel.sh gpu-start --image "my-image" --name "my-vm"   # With custom VM name
./selectel.sh gpu-stop --name "my-vm"                       # Stop specific GPU VM (keeps disk)
./selectel.sh setup-start                                    # Start VM without GPU
./selectel.sh setup-start --name "my-setup"                 # With custom VM name

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

## Task 17: Финальная проверка синтаксиса всех playbooks

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
- **.env.example** - шаблон конфигурации (с EXTERNAL_NETWORK, ROUTER_NAME, SSH_KEY_NAME)
- **playbooks/infra/** - 14 Ansible playbooks:
  - `list-flavors.yml` - список конфигураций VM
  - `list-images.yml` - список образов
  - `list-disks.yml` - список дисков
  - `list-vms.yml` - список серверов
  - `network-setup.yml` - создание сети, подсети, роутера и SG
  - `network-info.yml` - информация о сети
  - `gpu-start.yml` - запуск GPU VM (с валидацией, terminate_volume: false, floating IP)
  - `gpu-stop.yml` - остановка GPU VM (поддержка --name)
  - `setup-start.yml` - запуск VM без GPU для настройки
  - `disk-delete.yml` - удаление диска
  - `image-create-from-disk.yml` - создание образа (ожидание по ID)
  - `image-download.yml` - скачивание образа
  - `image-upload.yml` - загрузка образа
  - `image-delete.yml` - удаление образа

## Изменения по результатам review

Учтены следующие замечания из design review:

| Замечание | Изменение |
|-----------|-----------|
| ARCH-1 | Добавлены playbooks network-setup, network-info |
| IMPL-2 | Поддержка --name, генерация уникальных имён VM |
| IMPL-4 | terminate_volume: false при создании серверов |
| ERR-1 | Валидация входных переменных и ресурсов |
| EDGE-1 | Автоматический расчёт disk_size = max(default, image.min_disk) |
| IMPL-3 | Где возможно — модули вместо CLI |
| ERR-2 | Ожидание образа по ID |
| SEC-1 | Конфигурируемый SSH_KEY_NAME |
| EDGE-2 | Явный EXTERNAL_NETWORK для floating IP |

### Iteration 2

| Замечание | Изменение |
|-----------|-----------|
| ERR-2 (iter2) | Валидация уникальности в disk-delete, image-download, image-delete |
| SEC-1 (iter2) | network-setup добавляет SSH/ICMP правила в любую SG (включая default) |
| IMPL-1 (iter2) | gpu-stop без --name показывает список VM и просит выбрать |
| IMPL-2 (iter2) | Исправлен параметр name: → image: в image_info |
| ERR-1 (iter2) | Безопасный вывод floating IP при ALLOCATE_FLOATING_IP=false |
| ERR-3 (iter2) | block/rescue для отката тома при ошибке создания сервера |
| EDGE-1 (iter2) | Ошибка при указании --disk и --image одновременно |

### Iteration 3

| Замечание | Изменение |
|-----------|-----------|
| IMPL-1 (iter3) | set_fact server внутри каждой ветки (disk/image) в gpu-start |
| IMPL-2 (iter3) | Заменено network: на networks: (список) в gpu-start, setup-start |
| ERR-1 (iter3) | Валидация уникальности VM в gpu-stop |
| ERR-2 (iter3) | Проверка status == available для boot disk в gpu-start |
| ERR-3 (iter3) | block/rescue для отката тома в setup-start |
| EDGE-1 (iter3) | JSON для extra-vars в selectel.sh (пробелы в именах) |
| SEC-1 (iter3) | failed_when вместо ignore_errors для SG rules в network-setup |
| SEC-2 (iter3) | Проверка fingerprint keypair перед созданием |
| EDGE-2 (iter3) | Проверка существования boot volume перед созданием |
| ERR-4 (iter3) | --force для перезаписи в image-upload и image-download |
| DOC-1 (iter3) | Интерактивный выбор образа в setup-start если base_image не задан |
