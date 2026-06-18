#!/bin/bash

# ==========================================
# Tailscale Cluster Parallel Execution Tool
# ==========================================
# Runs a specified command concurrently across all nodes in the Tailscale cluster.

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

# Ensure a command was provided
if [ -z "$1" ]; then
    echo "Usage: $0 \"<command>\""
    echo "Example: $0 \"df -h /\""
    echo "Example: $0 \"sudo apt update\""
    exit 1
fi

COMMAND="$1"

echo "=========================================="
echo "🚀 Executing across ${#vm_list[@]} nodes:"
echo "   Command: $COMMAND"
echo "=========================================="
echo ""

# We will store background process PIDs here to wait for them
PIDS=()

for vm_str in "${vm_list[@]}"; do
    # Extract details using | as delimiter
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    
    # Fallback user if missing
    SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    
    # Run the SSH command in the background
    # -n prevents ssh from reading from stdin (crucial for loops/backgrounding)
    # -o ConnectTimeout=5 ensures we don't hang forever if a node is down
    ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}" "$COMMAND" 2>&1 | sed "s/^/[$VM_NAME] /" &
    
    # Save the Process ID of the background ssh command
    PIDS+=($!)
done

# Wait for all background SSH processes to finish
for pid in "${PIDS[@]}"; do
    wait $pid
done

echo ""
echo "=========================================="
echo "✅ Execution complete on all nodes."
echo "=========================================="
