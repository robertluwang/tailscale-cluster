#!/bin/bash

# ==========================================
# Tailscale Cluster Parallel Execution Tool
# ==========================================
# Runs a specified command concurrently across selected nodes in the Tailscale cluster.

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

# Default values
NODES_FILTER=""
COMMAND=""
SUMMARY=true

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --nodes)
            NODES_FILTER="$2"
            shift 2
            ;;
        --no-summary)
            SUMMARY=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] \"<command>\""
            echo ""
            echo "Options:"
            echo "  --nodes \"node1,node2\"  Run command on specific nodes (comma-separated)"
            echo "  --no-summary          Skip the summary report"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 \"df -h /\"                    # Run on all nodes"
            echo "  $0 --nodes \"node1,node3\" \"uptime\"  # Run on specific nodes"
            echo "  $0 --nodes \"all\" \"sudo apt update\"  # Explicitly target all nodes"
            exit 0
            ;;
        *)
            COMMAND="$1"
            shift
            ;;
    esac
done

# Ensure a command was provided
if [ -z "$COMMAND" ]; then
    echo "Usage: $0 [OPTIONS] \"<command>\""
    echo "Run '$0 --help' for full usage."
    exit 1
fi

# Build filtered node list
filtered_list=()
if [ -n "$NODES_FILTER" ]; then
    IFS=',' read -r -a filter_names <<< "$NODES_FILTER"
    for vm_str in "${vm_list[@]}"; do
        IFS='|' read -r VM_NAME _ _ <<< "$vm_str"
        for filter in "${filter_names[@]}"; do
            if [ "$VM_NAME" = "$filter" ] || [ "$filter" = "all" ]; then
                filtered_list+=("$vm_str")
                break
            fi
        done
    done
    if [ ${#filtered_list[@]} -eq 0 ]; then
        echo "Error: No matching nodes found for filter: $NODES_FILTER"
        echo "Available nodes: $(IFS=','; echo "${vm_list[*]%%|*}")"
        exit 1
    fi
else
    filtered_list=("${vm_list[@]}")
fi

echo "=========================================="
echo "🚀 Executing across ${#filtered_list[@]} of ${#vm_list[@]} nodes:"
echo "   Command: $COMMAND"
if [ -n "$NODES_FILTER" ]; then
    echo "   Nodes: $NODES_FILTER"
fi
echo "=========================================="
echo ""

# Track PIDs and results
PIDS=()
TMP_DIR=$(mktemp -d)
NODE_NAMES=()

for vm_str in "${filtered_list[@]}"; do
    IFS='|' read -r VM_NAME VM_IP VM_USER <<< "$vm_str"
    SSH_USER="${VM_USER:-${USER:-ubuntu}}"
    NODE_NAMES+=("$VM_NAME")
    
    # Run SSH in background, capture exit code
    (
        ssh -n -F /dev/null -i "$KEY_PATH" -o ConnectTimeout=10 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "${SSH_USER}@${VM_IP}" "$COMMAND" 2>&1 | sed "s/^/[$VM_NAME] /"
        exit ${PIPESTATUS[0]}
    ) > "$TMP_DIR/$VM_NAME.output" 2>&1 &
    
    # Store PID and node name mapping
    echo "$VM_NAME" > "$TMP_DIR/$!.node"
    PIDS+=($!)
done

# Wait for all processes and collect results
declare -A EXIT_CODES
for pid in "${PIDS[@]}"; do
    wait $pid
    node_name=$(cat "$TMP_DIR/$!.node" 2>/dev/null || echo "unknown")
    EXIT_CODES["$node_name"]=$?
done

# Print output in order
for vm_str in "${filtered_list[@]}"; do
    IFS='|' read -r VM_NAME _ _ <<< "$vm_str"
    cat "$TMP_DIR/$VM_NAME.output"
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
    
    for vm_str in "${filtered_list[@]}"; do
        IFS='|' read -r VM_NAME _ _ <<< "$vm_str"
        code=${EXIT_CODES["$VM_NAME"]:-99}
        if [ "$code" -eq 0 ]; then
            printf "%-15s | \e[32m%-10s\e[0m\n" "$VM_NAME" "OK"
            ((SUCCESS++))
        else
            printf "%-15s | \e[31m%-10s\e[0m\n" "$VM_NAME" "FAILED ($code)"
            ((FAILED++))
        fi
    done
    
    echo "------------------------------------------"
    echo "Total: ${#filtered_list[@]} | Success: $SUCCESS | Failed: $FAILED"
    echo "=========================================="
fi

rm -rf "$TMP_DIR"
