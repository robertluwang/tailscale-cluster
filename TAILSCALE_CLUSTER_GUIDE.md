# Design Guide: Tailscale Cluster Tools

## 1. Overview and Purpose
The `tailscale-cluster` toolkit provides lightweight, CLI-based utilities designed to simplify SSH/SFTP access (`ts-connect`) and orchestrate parallel command execution (`ts-cluster-run`) across a cluster of small virtual machines connected via Tailscale. 

The primary goal is to eliminate the friction of memorizing Tailscale IP addresses (100.x.y.z), typing repetitive SSH commands, and manually running the same operational checks across multiple edge nodes.

## 2. Architectural Decisions

### 2.1 Language Choice: Bash vs. Golang
**Decision:** Bash was chosen over Go/Python for these utilities.
**Rationale:**
* **Zero Dependencies:** Bash runs natively on almost any Unix-like system. Python would require managing virtual environments, and Go would require compilation for the host architecture. 
* **Native Tooling:** `ssh` and `sftp` are highly optimized for pseudo-terminal (TTY) allocation and stream piping. Wrapping them in Bash is trivial. Implementing interactive SSH clients or managing concurrent background processes in higher-level languages introduces unnecessary complexity for a simple management plane.

### 2.2 Configuration Management
**Decision:** External `.env` file for configuration (`~/.env`).
**Rationale:** 
* **Security:** Keeps sensitive SSH key paths and explicit Tailscale IPs completely out of version control.
* **Centralization:** Both `ts-connect` and `ts-cluster-run` read from the same `TS_VMS` list, ensuring a single source of truth for cluster state.
* **Parsing:** The string format `"name|ip|user name|ip|user"` allows for easy, zero-dependency unpacking using standard Bash Input Field Separator (`IFS`) logic.

## 3. Tool-Specific Designs

### 3.1 `ts-connect` (Interactive UX)
**Decision:** Interactive prompt using the built-in Bash `select` loop.
**Rationale:**
* Prevents the user from having to remember CLI arguments.
* Provides immediate, visually distinct feedback using emojis (🖥️, 🚀, 📁).

### 3.2 `ts-cluster-run` (Parallel Execution)
**Decision:** Background SSH jobs (`&`) combined with `wait`.
**Rationale:**
* For a small cluster, looping and sending `ssh ... &` to the background, followed by a `wait` loop on the PIDs, provides instant parallel execution without needing heavy tools like Ansible or pdsh.
* `-n` flag is explicitly used to prevent SSH from reading from stdin, which would break the parallel loop.

## 4. Security & Connection Handling

### 4.1 SSH Key Enforcement
The tools default the expected SSH key path to `~/.ssh/my-cluster-key.pem` but allow overriding. This prevents accidental login attempts with standard `id_rsa` keys, reducing authentication failures and connection delays.

### 4.2 First-Time Connection UX (`StrictHostKeyChecking=accept-new`)
**Problem:** SSH prompts the user to verify the ECDSA/ED25519 fingerprint on the first connection, which immediately halts automated parallel scripts.
**Solution:** The scripts inject `-o StrictHostKeyChecking=accept-new`.
* **Why not `no`?** Setting it to `no` is a security risk. `accept-new` is a secure compromise: it automatically accepts the key *only* if the host is not in `known_hosts`. If the host key changes later (indicating a VM rebuild or MITM), it safely blocks the connection.

## 5. Future Extensibility Ideas
1. **Dynamic Tailscale Parsing:** Instead of a static `.env` list, the scripts could run `tailscale status --json` (using `jq` to parse) to dynamically build the VM inventory in real-time.
2. **Tmux Integration:** Add an option to open SSH sessions to *all* VMs simultaneously in a synchronized Tmux pane setup.
