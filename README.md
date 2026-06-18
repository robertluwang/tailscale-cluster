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

## More Info
See [TAILSCALE_CLUSTER_GUIDE.md](TAILSCALE_CLUSTER_GUIDE.md) for deeper operational strategies (like using Ansible, Docker Swarm, or K3s over Tailscale).
