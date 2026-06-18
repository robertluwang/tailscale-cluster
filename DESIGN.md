# Design Guide: Tailscale Cluster Connection Tool (`ts-connect`)

## 1. Overview and Purpose
`ts-connect` is a lightweight, interactive CLI utility designed to simplify SSH and SFTP access to a cluster of small virtual machines connected via Tailscale. 

The primary goal is to eliminate the friction of memorizing Tailscale IP addresses (100.x.y.z) and typing repetitive, verbose SSH/SFTP commands with specific identity file flags.

## 2. Architectural Decisions

### 2.1 Language Choice: Bash vs. Golang
**Decision:** Bash was chosen over Golang.
**Rationale:**
* **Zero Compilation/Dependencies:** Bash runs natively on almost any Unix-like system. A Go binary would require compilation for the host architecture (e.g., ARM vs AMD64) and distribution.
* **TTY Handling:** `ssh` and `sftp` are highly optimized for pseudo-terminal (TTY) allocation and interactive sessions. Wrapping them in Bash is trivial. Implementing interactive, fully-featured SSH/SFTP clients in Go requires external libraries (`golang.org/x/crypto/ssh`), manual TTY state management, and handling terminal resizing events, which introduces unnecessary complexity for a 4-node cluster.

### 2.2 Configuration Management
**Decision:** Static array configuration at the top of the script.
**Rationale:** 
* Keeps the script portable as a single file without needing external `.json` or `.env` parsing. 
* Easy for the user to modify inline.
* Format `Array("Hostname IP")` allows easy unpacking into variables using Bash string manipulation (`read -r VM_NAME VM_IP <<< "$vm_choice"`).

### 2.3 User Experience (UX)
**Decision:** Interactive prompt using the built-in Bash `select` loop.
**Rationale:**
* Prevents the user from having to remember CLI arguments (e.g., `./ts-connect.sh --vm dclab-m2 --type sftp`).
* Provides immediate, visually distinct feedback using emojis (🖥️, 🚀, 📁) to help visually parse the terminal output quickly.
* Fails gracefully with a "Quit" option.

## 3. Security & Connection Handling

### 3.1 SSH Key Enforcement
The tool defaults the expected SSH key path to (`~/.ssh/my-cluster-key.pem`) and user (`ubuntu`). This prevents accidental login attempts with the default `id_rsa` or `id_ed25519` keys, reducing authentication failures and connection delays.

### 3.2 First-Time Connection UX (`StrictHostKeyChecking=accept-new`)
**Problem:** SSH prompts the user to verify the ECDSA/ED25519 fingerprint on the first connection, which can disrupt automated scripts or confuse users.
**Solution:** The script injects `-o StrictHostKeyChecking=accept-new`.
* **Why not `no`?** Setting it to `no` is a security risk (susceptible to MITM attacks). `accept-new` is a modern, secure compromise: it automatically accepts the key *only* if the host is not in `known_hosts`. If the host key changes later (indicating a potential MITM or VM rebuild), it will safely block the connection.

## 4. Future Extensibility Ideas

If the cluster grows beyond 4-5 VMs, the following features could be implemented to scale the tool:

1. **Dynamic Tailscale Parsing:** Instead of a hardcoded array, the script could run `tailscale status --json` (using `jq` to parse) to dynamically build the VM list.
2. **Argument Parsing:** Add support for skipping the menu entirely via arguments (e.g., `./ts-connect.sh dclab-m2 ssh`).
3. **Tmux Integration:** Add an option to open SSH sessions to *all* VMs simultaneously in a synchronized Tmux pane setup.
