#!/bin/bash

# ==========================================
# Tailscale Cluster Tmux Multiplexer
# ==========================================
# Opens a synchronized Tmux session with panes for all nodes.

# Load environment variables
if [ -f "$HOME/.env" ]; then
    source "$HOME/.env"
else
    echo "Error: ~/.env file not found. Please create it with TS_KEY_PATH and TS_VMS."
    exit 1
fi

KEY_PATH="${TS_KEY_PATH:-$HOME/.ssh/my-cluster-key.pem}"

# Ensure tmux is installed
if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux is not installed. Please install it (e.g., sudo apt install tmux)."
    exit 1
fi

# Parse TS_VMS string into an array
IFS=' ' read -r -a vm_list <<< "$TS_VMS"

if [ ${#vm_list[@]} -eq 0 ]; then
    echo "Error: No VMs defined in TS_VMS."
    exit 1
fi

SESSION_NAME="ts-cluster-$(date +%s)"

echo "🚀 Launching synchronized Tmux session for ${#vm_list[@]} nodes..."

# Start a new detached tmux session with the first VM
IFS='|' read -r FIRST_VM_NAME FIRST_VM_IP FIRST_VM_USER <<< "${vm_list[0]}"
FIRST_SSH_USER="${FIRST_VM_USER:-${USER:-ubuntu}}"
FIRST_CMD="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new ${FIRST_SSH_USER}@${FIRST_VM_IP}"

tmux new-session -d -s "$SESSION_NAME" "$FIRST_CMD"
# Rename the first window (optional)
tmux rename-window -t "$SESSION_NAME:0" "Cluster"

# Iterate through the rest of the VMs and split the window
for i in "${!vm_list[@]}"; do
    if [ "$i" -eq 0 ]; then continue; fi # Skip the first one as it's already created
    
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "${vm_list[$i]}"
    SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    CMD="ssh -i $KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new ${SSH_USER}@${VM_IP}"
    
    # Split the window and run the SSH command
    tmux split-window -t "$SESSION_NAME" -v "$CMD"
    # Tile the panes evenly
    tmux select-layout -t "$SESSION_NAME" tiled
done

# Turn on synchronize-panes so typing in one pane types in all
tmux set-window-option -t "$SESSION_NAME" synchronize-panes on

echo "✅ Session created. Attaching now."
echo "💡 TIP: What you type will go to ALL nodes simultaneously."
echo "💡 TIP: To stop synchronizing, press: Ctrl+b, then type: :setw synchronize-panes off"

# Attach to the session
tmux attach-session -t "$SESSION_NAME"
