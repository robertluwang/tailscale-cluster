# Tailscale Cluster Design & Operations Guide

## 1. Overview and Purpose

The `tailscale-cluster` toolkit provides lightweight, CLI-based utilities designed to simplify SSH/SFTP access (`ts-connect`) and orchestrate parallel command execution (`ts-cluster-run`) across a cluster of small virtual machines connected via Tailscale. 

The primary goal is to eliminate the friction of memorizing Tailscale IP addresses (100.x.y.z), typing repetitive SSH commands, and manually running the same operational checks across multiple edge nodes.

Given the constrained resources of the nodes (1GB RAM), lightweight approaches are prioritized over heavy orchestration engines.

## 2. Prerequisites

* All nodes must be connected to the same Tailscale network (`tailscale status`).
* SSH access must be configured and tested (either via Tailscale SSH or standard SSH with identity keys).
* The control node (where you run these scripts) must have the `ts-connect.sh` and `ts-cluster-run.sh` utilities.

## 3. Operations & Orchestration Strategies

This section outlines various methods for managing and orchestrating tasks across the cluster.

### Option 1: Lightweight Parallel Execution (Bash/SSH) - *Recommended*
For tiny 1GB RAM nodes, avoiding heavy agents is crucial. This approach uses standard `ssh` to map commands across the cluster concurrently.
* **Pros:** Zero overhead on target nodes. No new software to install. Very fast.
* **Cons:** Error handling is manual. Complex state management (e.g., "only run this if file X exists") requires complex bash one-liners.
* **Tool:** `ts-cluster-run.sh`
* **Use Case:** Checking disk space, running `apt update`, checking service status, simple reboots.

### Option 2: Configuration Management (Ansible)
Ansible is an excellent next step if Bash scripts become too complex to maintain. It operates over SSH, meaning it still requires **zero agents** on your 1GB VMs.
* **Pros:** Idempotent (safe to run multiple times). Huge library of built-in modules. Agentless.
* **Cons:** Requires installing Ansible on your *control node*. Slightly slower execution than raw SSH due to Python module transfer.
* **Setup:**
  1. Install on control node: `sudo apt install ansible`
  2. Create an `inventory.ini`:
     ```ini
     [cluster]
     node1 ansible_host=100.x.y.1 ansible_user=ubuntu
     node2 ansible_host=100.x.y.2 ansible_user=admin
     ```
  3. Run ad-hoc commands: `ansible cluster -m command -a "uptime" -i inventory.ini`

### Option 3: Lightweight Container Orchestration (Docker Swarm)
If you need to run applications that restart automatically, or spread workloads across nodes, Docker Swarm is significantly lighter than Kubernetes.
* **Pros:** Built into Docker. Easier to set up than K8s. Low memory footprint compared to Kubernetes.
* **Cons:** Docker itself has overhead. 1GB RAM limits how many containers you can run.
* **Tailscale Integration:** When initializing the Swarm, bind it explicitly to the Tailscale interface:
  * Manager: `docker swarm init --advertise-addr 100.x.y.z:2377`
  * Worker: `docker swarm join --token <token> 100.x.y.z:2377`

### Option 4: Ultra-Lightweight Kubernetes (K3s)
K3s is a certified Kubernetes distribution designed for IoT and Edge computing. It *can* run on 1GB RAM, but it will consume a significant portion of it (~300-500MB just for the agent).
* **Pros:** Full Kubernetes API. Great ecosystem.
* **Cons:** High memory overhead for 1GB nodes. Not recommended unless K8s is strictly required.
* **Tailscale Integration:** K3s has native Tailscale support via the `--vpn-auth` flag, allowing nodes to join the cluster seamlessly over the Tailscale VPN.

## 4. Architectural Decisions (Custom Tooling)

### 4.1 Language Choice: Bash vs. Golang
**Decision:** Bash was chosen over Go/Python for these utilities.
**Rationale:**
* **Zero Dependencies:** Bash runs natively on almost any Unix-like system. Python would require managing virtual environments, and Go would require compilation for the host architecture. 
* **Native Tooling:** `ssh` and `sftp` are highly optimized for pseudo-terminal (TTY) allocation and stream piping. Wrapping them in Bash is trivial. Implementing interactive SSH clients or managing concurrent background processes in higher-level languages introduces unnecessary complexity for a simple management plane.

### 4.2 Configuration Management
**Decision:** External `.env` file for configuration (`~/.env`).
**Rationale:** 
* **Security:** Keeps sensitive SSH key paths and explicit Tailscale IPs completely out of version control.
* **Centralization:** Both `ts-connect` and `ts-cluster-run` read from the same `TS_VMS` list, ensuring a single source of truth for cluster state.
* **Parsing:** The string format `"name|ip|user name|ip|user"` allows for easy, zero-dependency unpacking using standard Bash Input Field Separator (`IFS`) logic.

## 5. Tool-Specific Designs

### 5.1 `ts-connect` (Interactive UX)
**Decision:** Interactive prompt using the built-in Bash `select` loop.
**Rationale:**
* Prevents the user from having to remember CLI arguments.
* Provides immediate, visually distinct feedback using emojis (🖥️, 🚀, 📁).

### 5.2 `ts-cluster-run` (Parallel Execution)
**Decision:** Background SSH jobs (`&`) combined with `wait`.
**Rationale:**
* For a small cluster, looping and sending `ssh ... &` to the background, followed by a `wait` loop on the PIDs, provides instant parallel execution without needing heavy tools like Ansible or pdsh.
* `-n` flag is explicitly used to prevent SSH from reading from stdin, which would break the parallel loop.

## 6. Security & Connection Handling

### 6.1 SSH Key Enforcement
The tools default the expected SSH key path to `~/.ssh/my-cluster-key.pem` but allow overriding. This prevents accidental login attempts with standard `id_rsa` keys, reducing authentication failures and connection delays.

### 6.2 First-Time Connection UX (`StrictHostKeyChecking=accept-new`)
**Problem:** SSH prompts the user to verify the ECDSA/ED25519 fingerprint on the first connection, which immediately halts automated parallel scripts.
**Solution:** The scripts inject `-o StrictHostKeyChecking=accept-new`.
* **Why not `no`?** Setting it to `no` is a security risk. `accept-new` is a secure compromise: it automatically accepts the key *only* if the host is not in `known_hosts`. If the host key changes later (indicating a VM rebuild or MITM), it safely blocks the connection.

## 7. Future Extensibility Ideas
1. **Dynamic Tailscale Parsing:** Instead of a static `.env` list, the scripts could run `tailscale status --json` (using `jq` to parse) to dynamically build the VM inventory in real-time.
2. **Tmux Integration:** Add an option to open SSH sessions to *all* VMs simultaneously in a synchronized Tmux pane setup.
