#!/bin/bash

# ==========================================
# Tailscale Cluster Shared Folder Setup Tool
# ==========================================
# Sets up an NFS share on a selected server node and mounts it on all other client nodes.

# Load environment variables
if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
else
    echo "Error: ~/.env file not found. Please create it with TS_KEY_PATH and TS_VMS."
    exit 1
fi

KEY_PATH="${TS_KEY_PATH:-$HOME/.ssh/my-cluster-key.pem}"

# Parse TS_VMS string into an array (format: "name|ip|user name|ip|user")
IFS=' ' read -r -a vm_list <<< "$TS_VMS"

# Format the VMS for select menu
VMS_MENU=()
for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    VMS_MENU+=("$VM_NAME ($VM_IP)")
done

echo "=========================================="
echo "    Tailscale NFS Shared Folder Setup     "
echo "=========================================="

echo "🖥️  Select the VM to act as the NFS SERVER (host for the shared folder):"
select vm_choice in "${VMS_MENU[@]}" "Quit"; do
    if [[ "$vm_choice" == "Quit" ]]; then
        echo "Exiting."
        exit 0
    elif [[ -n "$vm_choice" ]]; then
        idx=$((REPLY-1))
        SERVER_STR="${vm_list[$idx]}"
        IFS='|' read -r SERVER_NAME SERVER_IP SERVER_USER <<< "$SERVER_STR"
        break
    else
        echo "Invalid choice. Please pick a number from the list."
    fi
done

SERVER_USER="${SERVER_USER:-${USER:-ubuntu}}"

SHARE_DIR="/srv/cluster-share"
MOUNT_DIR="/mnt/cluster-share"
TAILSCALE_SUBNET="100.0.0.0/8"

echo ""
echo "🚀 Setting up NFS Server on $SERVER_NAME ($SERVER_IP)..."

# SSH Command to setup server
SSH_SERVER_CMD="sudo apt-get update && \
sudo apt-get install -y nfs-kernel-server && \
sudo mkdir -p $SHARE_DIR && \
sudo chown nobody:nogroup $SHARE_DIR && \
sudo chmod 777 $SHARE_DIR && \
if ! grep -qs '$SHARE_DIR' /etc/exports; then echo '$SHARE_DIR $TAILSCALE_SUBNET(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports > /dev/null; fi && \
sudo exportfs -a && \
sudo systemctl restart nfs-kernel-server"

ssh -n -F /dev/null -i "$KEY_PATH" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SERVER_USER}@${SERVER_IP}" "$SSH_SERVER_CMD"

if [ $? -ne 0 ]; then
    echo "❌ Failed to setup NFS Server on $SERVER_NAME."
    exit 1
fi
echo "✅ NFS Server configured on $SERVER_NAME at $SHARE_DIR"

echo ""
echo "🚀 Setting up NFS Clients on remaining nodes..."

PIDS=()
for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    
    # Skip the server node
    if [[ "$VM_IP" == "$SERVER_IP" ]]; then
        continue
    fi
    
    CLIENT_USER="${VM_USER:-${USER:-ubuntu}}"
    
    # Check if we should skip due to iSH limitations
    if [[ "$VM_NAME" == *"ish"* || "$VM_NAME" == *"iphone"* || "$VM_NAME" == *"ipad"* ]]; then
        echo "   ⚠️ Skipping $VM_NAME ($VM_IP) - Native NFS mounting is not supported on iSH/iOS."
        continue
    fi
    
    SSH_CLIENT_CMD="if command -v apt-get >/dev/null; then
    sudo apt-get update && sudo apt-get install -y nfs-common
elif command -v apk >/dev/null; then
    sudo apk add nfs-utils
else
    echo 'Unsupported package manager' && exit 1
fi && \
sudo mkdir -p $MOUNT_DIR && \
if ! grep -qs '$MOUNT_DIR' /proc/mounts; then sudo mount -t nfs ${SERVER_IP}:${SHARE_DIR} $MOUNT_DIR; fi && \
if ! grep -qs '${SERVER_IP}:${SHARE_DIR}' /etc/fstab; then echo '${SERVER_IP}:${SHARE_DIR} $MOUNT_DIR nfs defaults 0 0' | sudo tee -a /etc/fstab > /dev/null; fi && \
echo '✅ Configured and mounted'"
    
    echo "   Configuring $VM_NAME ($VM_IP)..."
    ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${CLIENT_USER}@${VM_IP}" "$SSH_CLIENT_CMD" 2>&1 | sed "s/^/[$VM_NAME] /" &
    
    PIDS+=($!)
done

# Wait for all client background SSH processes to finish
for pid in "${PIDS[@]}"; do
    wait $pid
done

echo ""
echo "=========================================="
echo "🎉 Cluster Shared Folder Setup Complete!"
echo "   Server: $SERVER_NAME ($SHARE_DIR)"
echo "   Clients: Mounted at $MOUNT_DIR"
echo "=========================================="
