#!/bin/bash

# ==========================================
# Tailscale Cluster Status Dashboard
# ==========================================
# Quickly checks the health, uptime, and load of all nodes.

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

echo "========================================================================"
printf "%-15s | %-15s | %-10s | %-20s\n" "NODE" "IP" "STATUS" "LOAD/UPTIME"
echo "========================================================================"

PIDS=()
TMP_DIR=$(mktemp -d)

for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    
    # Run ping and basic uptime check in background, save to temp file
    (
        if ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
            # Node is reachable via ICMP (Tailscale is up)
            UPTIME_LOAD=$(ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}" "uptime | awk -F'( |,|:)+' '{print \$6\"h \"\$7\"m, Load: \"\$14}'" 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                printf "%-15s | %-15s | \e[32m%-10s\e[0m | %-20s\n" "$VM_NAME" "$VM_IP" "ONLINE" "$UPTIME_LOAD" > "$TMP_DIR/$VM_NAME"
            else
                printf "%-15s | %-15s | \e[33m%-10s\e[0m | %-20s\n" "$VM_NAME" "$VM_IP" "SSH FAIL" "Tailscale up, SSH down" > "$TMP_DIR/$VM_NAME"
            fi
        else
            printf "%-15s | %-15s | \e[31m%-10s\e[0m | %-20s\n" "$VM_NAME" "$VM_IP" "OFFLINE" "Unreachable" > "$TMP_DIR/$VM_NAME"
        fi
    ) &
    PIDS+=($!)
done

# Wait for all checks
for pid in "${PIDS[@]}"; do
    wait $pid
done

# Print results in order
for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME _ _ <<< "$vm_str"
    cat "$TMP_DIR/$VM_NAME"
done

echo "========================================================================"
rm -rf "$TMP_DIR"
