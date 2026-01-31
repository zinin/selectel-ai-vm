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
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Run: sudo apt install jq"
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
    --image <name>      Base image (default: BASE_IMAGE_NAME from .env)
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
        IMAGE_NAME="${BASE_IMAGE_NAME:-}"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --name) VM_NAME="$2"; shift 2 ;;
                --image) IMAGE_NAME="$2"; shift 2 ;;
                *) echo "Unknown option: $1"; exit 1 ;;
            esac
        done
        EXTRA_VARS="{}"
        [[ -n "$VM_NAME" ]] && EXTRA_VARS=$(echo "$EXTRA_VARS" | jq --arg v "$VM_NAME" '. + {vm_name: $v}')
        [[ -n "$IMAGE_NAME" ]] && EXTRA_VARS=$(echo "$EXTRA_VARS" | jq --arg v "$IMAGE_NAME" '. + {base_image: $v}')
        ansible-playbook "$SCRIPT_DIR/playbooks/infra/setup-start.yml" -e "$EXTRA_VARS"
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
