# Tailscale Cluster Operations Guide

This guide outlines various methods for managing and orchestrating tasks across a cluster of lightweight VMs connected securely via Tailscale. 

Given the constrained resources of the nodes (1GB RAM), lightweight approaches are prioritized over heavy orchestration engines.

## Prerequisites
* All nodes must be connected to the same Tailscale network (`tailscale status`).
* SSH access must be configured and tested (either via Tailscale SSH or standard SSH with identity keys).
* The control node (where you run these scripts) must have the `ts-connect.sh` and `ts-cluster-run.sh` utilities.

---

## Option 1: Lightweight Parallel Execution (Bash/SSH) - *Recommended*
For tiny 1GB RAM nodes, avoiding heavy agents is crucial. This approach uses standard `ssh` to map commands across the cluster concurrently.

* **Pros:** Zero overhead on target nodes. No new software to install. Very fast.
* **Cons:** Error handling is manual. Complex state management (e.g., "only run this if file X exists") requires complex bash one-liners.
* **Tool:** `ts-cluster-run.sh`
* **Use Case:** Checking disk space, running `apt update`, checking service status, simple reboots.

---

## Option 2: Configuration Management (Ansible)
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

---

## Option 3: Lightweight Container Orchestration (Docker Swarm)
If you need to run applications that restart automatically, or spread workloads across nodes, Docker Swarm is significantly lighter than Kubernetes.

* **Pros:** Built into Docker. Easier to set up than K8s. Low memory footprint compared to Kubernetes.
* **Cons:** Docker itself has overhead. 1GB RAM limits how many containers you can run.
* **Tailscale Integration:** When initializing the Swarm, bind it explicitly to the Tailscale interface:
  * Manager: `docker swarm init --advertise-addr 100.x.y.z:2377`
  * Worker: `docker swarm join --token <token> 100.x.y.z:2377`

---

## Option 4: Ultra-Lightweight Kubernetes (K3s)
K3s is a certified Kubernetes distribution designed for IoT and Edge computing. It *can* run on 1GB RAM, but it will consume a significant portion of it (~300-500MB just for the agent).

* **Pros:** Full Kubernetes API. Great ecosystem.
* **Cons:** High memory overhead for 1GB nodes. Not recommended unless K8s is strictly required.
* **Tailscale Integration:** K3s has native Tailscale support via the `--vpn-auth` flag, allowing nodes to join the cluster seamlessly over the Tailscale VPN.
