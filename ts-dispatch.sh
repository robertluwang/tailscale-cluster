#!/bin/bash

# ==========================================
# Tailscale Cluster Task Dispatcher
# ==========================================
# Runs different commands on different nodes based on a task file.

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

# Build lookup map: node_name -> "ip|user"
declare -A NODE_MAP
for vm_str in "${vm_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    NODE_MAP["$VM_NAME"]="${VM_IP}|${SSH_USER}"
done

# Parse arguments
TASK_FILE=""
SUMMARY=true

while [ $# -gt 0 ]; do
    case "$1" in
        --no-summary)
            SUMMARY=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] <task-file>"
            echo ""
            echo "Task file format:"
            echo "  # Comments start with #"
            echo "  # Format: node_name: command"
            echo "  node1: sudo apt update"
            echo "  node2: sudo reboot"
            echo "  all: df -h /"
            echo ""
            echo "Options:"
            echo "  --no-summary  Skip the summary report"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Example:"
            echo "  $0 tasks.txt"
            exit 0
            ;;
        *)
            TASK_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$TASK_FILE" ]; then
    echo "Usage: $0 [OPTIONS] <task-file>"
    echo "Run '$0 --help' for full usage."
    exit 1
fi

if [ ! -f "$TASK_FILE" ]; then
    echo "Error: Task file not found: $TASK_FILE"
    exit 1
fi

echo "=========================================="
echo "📋 Dispatching tasks from: $TASK_FILE"
echo "=========================================="
echo ""

# Parse task file and execute
PIDS=()
TMP_DIR=$(mktemp -d)
TASK_NODES=()

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Parse: node_name: command
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*(.+)$ ]]; then
        node_name="${BASH_REMATCH[1]}"
        command="${BASH_REMATCH[2]}"
        
        # Handle "all" keyword
        if [ "$node_name" = "all" ]; then
            for vm_str in "${vm_list[@]}"; do
                IFS='|' read -r NAME IP USER <<< "$vm_str"
                SSH_USER="${USER:-${USER:-ubuntu}}"
                TASK_NODES+=("$NAME")
                
                (
                    ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${IP}" "$command" 2>&1 | sed "s/^/[$NAME] /"
                    exit ${PIPESTATUS[0]}
                ) > "$TMP_DIR/$NAME.output" 2>&1 &
                
                echo "$NAME" > "$TMP_DIR/$!.node"
                PIDS+=($!)
            done
        elif [ -n "${NODE_MAP[$node_name]+x}" ]; then
            IFS='|' read -r IP USER <<< "${NODE_MAP[$node_name]}"
            TASK_NODES+=("$node_name")
            
            (
                ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${USER}@${IP}" "$command" 2>&1 | sed "s/^/[$node_name] /"
                exit ${PIPESTATUS[0]}
            ) > "$TMP_DIR/$node_name.output" 2>&1 &
            
            echo "$node_name" > "$TMP_DIR/$!.node"
            PIDS+=($!)
        else
            echo "⚠️  Unknown node: $node_name (skipping)"
            echo "   Available nodes: ${!NODE_MAP[*]}"
        fi
    else
        echo "⚠️  Invalid format: $line"
        echo "   Expected: node_name: command"
    fi
done < "$TASK_FILE"

# Wait for all processes and collect results
declare -A EXIT_CODES
for pid in "${PIDS[@]}"; do
    wait $pid
    node_name=$(cat "$TMP_DIR/$!.node" 2>/dev/null || echo "unknown")
    EXIT_CODES["$node_name"]=$?
done

# Print output
for node_name in "${TASK_NODES[@]}"; do
    cat "$TMP_DIR/$node_name.output"
done

# Print summary
if [ "$SUMMARY" = true ]; then
    echo ""
    echo "=========================================="
    echo "📊 Summary"
    echo "=========================================="
    printf "%-15s | %-10s\n" "NODE" "STATUS"
    echo "------------------------------------------"
    
    SUCCESS=0
    FAILED=0
    
    for node_name in "${TASK_NODES[@]}"; do
        code=${EXIT_CODES["$node_name"]:-99}
        if [ "$code" -eq 0 ]; then
            printf "%-15s | \e[32m%-10s\e[0m\n" "$node_name" "OK"
            ((SUCCESS++))
        else
            printf "%-15s | \e[31m%-10s\e[0m\n" "$node_name" "FAILED ($code)"
            ((FAILED++))
        fi
    done
    
    echo "------------------------------------------"
    echo "Total: ${#TASK_NODES[@]} | Success: $SUCCESS | Failed: $FAILED"
    echo "=========================================="
fi

rm -rf "$TMP_DIR"
