#!/bin/bash

# ==========================================
# Tailscale Cluster Sync Tool
# ==========================================
# Syncs a local file or directory to a specific node or all nodes.

# Load environment variables
if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
else
    echo "Error: ~/.env file not found. Please create it with TS_KEY_PATH and TS_VMS."
    exit 1
fi

KEY_PATH="${TS_KEY_PATH:-$HOME/.ssh/my-cluster-key.pem}"

# Parse TS_VMS string into an array
IFS=' ' read -r -a vm_list <<< "$TS_VMS"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <source_path> <destination_path> [node_name|all]"
    echo "Example (to one node): $0 ./app.py /opt/app/ node1"
    echo "Example (to all nodes): $0 ./config/ /etc/myapp/ all"
    exit 1
fi

SOURCE="$1"
DEST="$2"
TARGET="${3:-all}"

if [ ! -e "$SOURCE" ]; then
    echo "Error: Source path '$SOURCE' does not exist."
    exit 1
fi

sync_to_node() {
    local VM_NAME="$1"
    local VM_IP="$2"
    local VM_USER="$3"
    
    local SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    
    echo "🔄 Syncing to $VM_NAME ($VM_IP)..."
    
    # Use rsync over SSH
    rsync -avz -e "ssh -i $KEY_PATH -o StrictHostKeyChecking=accept-new" "$SOURCE" "${SSH_USER}@${VM_IP}:${DEST}" 2>&1 | sed "s/^/[$VM_NAME] /"
}

if [[ "$TARGET" == "all" ]]; then
    echo "=========================================="
    echo "🚀 Syncing '$SOURCE' to ALL nodes at '$DEST'"
    echo "=========================================="
    
    PIDS=()
    for vm_str in "${vm_list[@]}"; do
        IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
        sync_to_node "$VM_NAME" "$VM_IP" "$VM_USER" &
        PIDS+=($!)
    done
    
    for pid in "${PIDS[@]}"; do
        wait $pid
    done
    echo "✅ Sync to all nodes complete."
else
    # Find the specific node
    FOUND=false
    for vm_str in "${vm_list[@]}"; do
        IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
        if [[ "$VM_NAME" == "$TARGET" ]]; then
            sync_to_node "$VM_NAME" "$VM_IP" "$VM_USER"
            FOUND=true
            break
        fi
    done
    
    if [ "$FOUND" = false ]; then
        echo "❌ Node '$TARGET' not found in TS_VMS."
        exit 1
    fi
fi
