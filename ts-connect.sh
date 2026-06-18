#!/bin/bash

# ==========================================
# Tailscale Cluster Connection Tool
# ==========================================

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

# Format the VMS for select menu: "Name IP user"
VMS_MENU=()
for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    VMS_MENU+=("$VM_NAME ($VM_IP) - $VM_USER")
done

echo "=========================================="
echo "    Tailscale SSH/SFTP Cluster Tool       "
echo "=========================================="

# 1. Select the VM
echo "🖥️  Select a VM to connect to:"
select vm_choice in "${VMS_MENU[@]}" "Quit"; do
    if [[ "$vm_choice" == "Quit" ]]; then
        echo "Exiting."
        exit 0
    elif [[ -n "$vm_choice" ]]; then
        # Map the choice back to the original values
        # Index of selected item is REPLAY-1 ($REPLY is 1-based)
        idx=$((REPLY-1))
        selected_str="${vm_list[$idx]}"
        IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$selected_str"
        break
    else
        echo "Invalid choice. Please pick a number from the list."
    fi
done

# 2. Select the Operation (SSH or SFTP)
echo ""
echo "🛠️  What would you like to do with $VM_NAME ($VM_IP)?"
select op_choice in "SSH" "SFTP" "Quit"; do
    case $op_choice in
        SSH|SFTP)
            # Default fallback if VM_USER is not defined in the array
            DEFAULT_USER="${VM_USER:-${USER:-ubuntu}}"
            
            # Ask for username
            read -p "👤 Enter username (default: $DEFAULT_USER): " input_user
            SSH_USER="${input_user:-$DEFAULT_USER}"
            
            if [[ "$op_choice" == "SSH" ]]; then
                echo "🚀 Starting SSH session to $VM_NAME as $SSH_USER..."
                # Use standard SSH with explicit IdentityFile, disabling agent & user config
                ssh -F /dev/null -i "$KEY_PATH" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}"
            else
                echo "📁 Starting SFTP session to $VM_NAME as $SSH_USER..."
                # Use standard SFTP with explicit IdentityFile, disabling agent & user config
                sftp -F /dev/null -i "$KEY_PATH" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}"
            fi
            break
            ;;
        Quit)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
done
