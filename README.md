# Tailscale Cluster Scripts

A set of lightweight Bash scripts to manage, connect, and run commands across a group of virtual machines connected via Tailscale.

## Setup

These scripts require a `~/.env` file in your home directory to store the configuration. This keeps your SSH keys and VM IPs out of the scripts (and out of version control).

1. Create or edit `~/.env`:

```bash
# ~/.env

# Path to the SSH key used to authenticate with the cluster
export TS_KEY_PATH="$HOME/.ssh/my-cluster-key.pem"

# List of VMs in the format: "name|ip|user name2|ip2|user2"
export TS_VMS="node1|100.x.y.1|ubuntu node2|100.x.y.2|admin node3|100.x.y.3|root"
```

## Scripts

### 1. `ts-connect.sh`
An interactive prompt to quickly SSH or SFTP into any node in your cluster.

```bash
./ts-connect.sh
```

### 2. `ts-cluster-run.sh`
Run a single command across all your VMs concurrently. Great for quick checks like `df -h` or `sudo apt update`.

```bash
./ts-cluster-run.sh "uptime"
```

### 3. `ts-setup-share.sh`
Interactive tool to set up an NFS shared folder across the cluster. It prompts you to select a server node, installs the necessary NFS packages, configures the share, and mounts it automatically on all remaining client nodes.

```bash
./ts-setup-share.sh
```

### 4. `ts-sync.sh`
Uses `rsync` over Tailscale SSH to quickly push a local file or directory to a specific node or all nodes concurrently.

```bash
# Sync a file to a specific node
./ts-sync.sh ./app.js /opt/app/ node2

# Sync a directory to all nodes
./ts-sync.sh ./config/ /etc/myapp/ all
```

### 5. `ts-status.sh`
A quick visual dashboard that pings all nodes and fetches their uptime and system load to verify cluster health.

```bash
./ts-status.sh
```

### 6. `ts-tmux.sh`
Launches a synchronized `tmux` session with split panes for every node in your cluster. Typing in one terminal pane will instantly type the exact same command across all other panes simultaneously. Excellent for real-time interactive debugging across the cluster.

```bash
./ts-tmux.sh
```

## More Info
* See [TAILSCALE_CLUSTER_DESIGN.md](TAILSCALE_CLUSTER_DESIGN.md) for architectural decisions, security considerations, and operational strategies (like using Ansible, Docker Swarm, or K3s over Tailscale).
