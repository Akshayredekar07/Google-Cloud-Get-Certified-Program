# Setting up a Private Kubernetes Cluster  
**Google Cloud Skills Boost Lab – GSP178**  
**Level:** Intermediate | **Duration:** ~35 minutes  

> **Study Note**  
> This lab is excellent for understanding **private GKE clusters** and the networking implications of isolating the control plane and nodes.  
> It demonstrates both the **auto-created subnet** pattern and the **custom subnet + secondary ranges** pattern.  
> Master Authorized Networks are critical — without them you cannot reach the private control plane from outside the cluster network.  
> Always remember: private nodes have **no external IP**, so Private Google Access must be enabled for nodes to reach Google APIs.

---

## Table of Contents
1. [Overview & Learning Objectives](#1-overview--learning-objectives)
2. [What This Lab Is Actually Testing](#2-what-this-lab-is-actually-testing)
3. [Core Concepts](#3-core-concepts)
4. [Hands-on Walkthrough](#4-hands-on-walkthrough)
5. [Key Terms You Must Know Cold](#5-key-terms-you-must-know-cold)
6. [Commands & Console Paths Cheat Sheet](#6-commands--console-paths-cheat-sheet)
7. [Exam & Design Perspective](#7-exam--design-perspective)
8. [Quick Revision Summary](#8-quick-revision-summary)

---

## 1. Overview & Learning Objectives

A **private GKE cluster** keeps both the control plane (master) and the nodes off the public internet.  
Nodes have only private IP addresses. The control plane is accessible only from authorized networks (or from within the cluster’s VPC via private endpoint).

### What you will learn
- Create a private GKE cluster with auto-created subnet
- Inspect primary and secondary IP ranges (nodes, pods, services)
- Enable Master Authorized Networks
- Create a custom subnet with secondary ranges for pods and services
- Create a second private cluster that uses the custom subnet
- Verify that nodes have no external IP addresses

### Challenge Lab Relevance
- **Very high.** Private clusters, Master Authorized Networks, and secondary ranges appear frequently in networking and security design questions.
- You must understand the difference between `--enable-private-nodes` and `--enable-private-endpoint`.
- You must know why Private Google Access is required.

---

## 2. What This Lab Is Actually Testing

| Concept | How the Lab Exercises It |
|---------|--------------------------|
| Private nodes | `--enable-private-nodes` → nodes get only internal IPs |
| Master CIDR | `--master-ipv4-cidr` (must be /28) |
| IP aliases | `--enable-ip-alias` (required for private clusters) |
| Auto vs custom subnet | First cluster auto-creates subnet; second uses custom |
| Secondary ranges | Pods and Services ranges |
| Master Authorized Networks | Whitelist external IPs that can reach the control plane |
| Private Google Access | Enabled so private nodes can reach Google APIs |
| Verification | `kubectl get nodes` shows empty EXTERNAL-IP |

**Key insight:**  
Even in a private cluster the control plane still needs a way for authorized clients to reach it → Master Authorized Networks.

---

## 3. Core Concepts

### 3.1 What Makes a Cluster “Private”?

| Component | Public Cluster | Private Cluster |
|-----------|----------------|-----------------|
| Nodes | Have external IPs (by default) | **No external IPs** |
| Control plane | Public endpoint | Private endpoint (optional public endpoint can still exist) |
| Node → Google APIs | Via external IP or Cloud NAT | Requires **Private Google Access** |
| Communication | Public internet | VPC peering / private networking |

### 3.2 Required Flags for Private Clusters

```bash
--enable-private-nodes          # Nodes get only private IPs
--master-ipv4-cidr x.x.x.x/28   # /28 range reserved for the control plane
--enable-ip-alias               # Mandatory for private clusters
```

Optional but important:
- `--enable-private-endpoint` → makes the control plane **completely** private (no public endpoint)
- `--master-authorized-networks` → whitelist who can talk to the control plane

### 3.3 IP Address Ranges in a Private Cluster

| Range | Purpose | Example in Lab |
|-------|---------|----------------|
| Primary range | Nodes | 10.0.0.0/22 or 10.0.4.0/22 |
| Secondary (pods) | Pod IPs | 10.40.0.0/14 or 10.4.0.0/14 |
| Secondary (services) | ClusterIP Services | 10.0.16.0/20 or 10.0.32.0/20 |
| Master CIDR | Control plane VMs | 172.16.0.16/28 or 172.16.0.32/28 |

**Important rules:**
- Master CIDR **must** be /28
- Ranges must not overlap
- Pod and Service ranges are secondary ranges on the subnet

### 3.4 Master Authorized Networks

By default, after creating a private cluster, **only** the node and pod ranges can reach the control plane.  
Any external client (Cloud Shell, your laptop, a bastion VM) must be explicitly authorized:

```bash
--master-authorized-networks <CIDR>
```

Common pattern: authorize a bastion / jump host with `/32`.

### 3.5 Private Google Access

Because nodes have no external IP, they cannot reach `*.googleapis.com` unless:
- Private Google Access is enabled on the subnet, **or**
- Cloud NAT is configured

The lab enables Private Google Access when creating the custom subnet.

---

## 4. Hands-on Walkthrough

### Task 1 – Set Region and Zone

```bash
gcloud config set compute/zone europe-west3-c
export REGION=europe-west3
export ZONE=europe-west3-c
```

### Task 2 – Create First Private Cluster (Auto Subnet)

```bash
gcloud beta container clusters create private-cluster \
    --enable-private-nodes \
    --master-ipv4-cidr 172.16.0.16/28 \
    --enable-ip-alias \
    --create-subnetwork "" \
    --machine-type e2-medium
```

GKE automatically creates a subnet with:
- Primary range for nodes
- Secondary range for pods
- Secondary range for services
- Private Google Access = true

### Task 3 – Inspect the Auto-Created Subnet

```bash
gcloud compute networks subnets list --network default

# Replace [SUBNET_NAME] with the actual name
gcloud compute networks subnets describe [SUBNET_NAME] --region=$REGION
```

Look for:
- `ipCidrRange` (nodes)
- `secondaryIpRanges` (pods + services)
- `privateIpGoogleAccess: true`

### Task 4 – Master Authorized Networks + Verification

```bash
# Create bastion
gcloud compute instances create source-instance \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --scopes 'https://www.googleapis.com/auth/cloud-platform'

# Get its external IP
gcloud compute instances describe source-instance --zone=$ZONE | grep natIP
```

Authorize that IP:

```bash
gcloud container clusters update private-cluster \
    --enable-master-authorized-networks \
    --master-authorized-networks <NAT_IP>/32
```

SSH into bastion and verify:

```bash
gcloud compute ssh source-instance --zone=$ZONE

# Inside the VM
sudo apt-get install kubectl google-cloud-sdk-gke-gcloud-auth-plugin -y
gcloud container clusters get-credentials private-cluster --zone=$ZONE

kubectl get nodes --output wide          # EXTERNAL-IP column is empty
kubectl get nodes --output yaml | grep -A4 addresses
```

### Task 5 – Clean Up First Cluster

```bash
gcloud container clusters delete private-cluster --zone=$ZONE
```

### Task 6 – Custom Subnet + Second Private Cluster

**Create custom subnet with secondary ranges:**

```bash
gcloud compute networks subnets create my-subnet \
    --network default \
    --range 10.0.4.0/22 \
    --enable-private-ip-google-access \
    --region=$REGION \
    --secondary-range my-svc-range=10.0.32.0/20,my-pod-range=10.4.0.0/14
```

**Create private cluster using the custom subnet:**

```bash
gcloud beta container clusters create private-cluster2 \
    --enable-private-nodes \
    --enable-ip-alias \
    --master-ipv4-cidr 172.16.0.32/28 \
    --subnetwork my-subnet \
    --services-secondary-range-name my-svc-range \
    --cluster-secondary-range-name my-pod-range \
    --zone=$ZONE \
    --machine-type e2-medium
```

Authorize the bastion again and verify nodes have no external IP.

---

## 5. Key Terms You Must Know Cold

| Term | Definition |
|------|------------|
| **Private cluster** | GKE cluster where nodes have no public IPs and control plane is restricted |
| **Private nodes** | Nodes that only receive internal IP addresses |
| **Master CIDR** | /28 range reserved exclusively for the control plane |
| **IP aliases** | Secondary ranges used for Pods and Services (required for private clusters) |
| **Master Authorized Networks** | List of CIDRs allowed to reach the Kubernetes API server |
| **Private Google Access** | Allows VMs with only private IPs to reach Google APIs |
| **Primary range** | Used by nodes |
| **Secondary range (pods)** | Used by Pod IPs |
| **Secondary range (services)** | Used by ClusterIP Services |
| **Bastion / Jump host** | VM used to access private resources |

---

## 6. Commands & Console Paths Cheat Sheet

```bash
# Create private cluster (auto subnet)
gcloud beta container clusters create NAME \
  --enable-private-nodes \
  --master-ipv4-cidr x.x.x.x/28 \
  --enable-ip-alias \
  --create-subnetwork ""

# Create private cluster (custom subnet)
gcloud beta container clusters create NAME \
  --enable-private-nodes \
  --enable-ip-alias \
  --master-ipv4-cidr x.x.x.x/28 \
  --subnetwork SUBNET \
  --cluster-secondary-range-name POD_RANGE \
  --services-secondary-range-name SVC_RANGE

# Authorize external access to control plane
gcloud container clusters update NAME \
  --enable-master-authorized-networks \
  --master-authorized-networks CIDR

# Inspect subnet
gcloud compute networks subnets describe SUBNET --region=REGION

# Verify no external IPs
kubectl get nodes -o wide
```

**Console paths**
- Kubernetes Engine → Clusters
- VPC network → VPC networks → Subnets

---

## 7. Exam & Design Perspective

**Maps to PCA / ACE exam domains:**  
- Designing network topologies  
- Security and compliance (isolating workloads)

### What this lab covers well
- Private nodes + Master CIDR
- Auto vs custom subnet patterns
- Master Authorized Networks
- Verification that nodes have no public IPs

### What you still need for the exam
- `--enable-private-endpoint` (fully private control plane)
- Cloud NAT for outbound internet from private nodes
- Shared VPC + private clusters
- Authorized networks with multiple CIDRs
- Private Service Connect / Private Google Access differences
- Network Policies + private clusters

**Production recommendations:**
1. Prefer fully private control plane (`--enable-private-endpoint`) when possible.
2. Use a dedicated bastion or Identity-Aware Proxy + TCP forwarding.
3. Always enable Private Google Access or Cloud NAT.
4. Plan secondary ranges carefully (pods need large ranges).

---

## 8. Quick Revision Summary

1. Private cluster = nodes have **no external IP** + restricted control plane.
2. Must use `--enable-private-nodes` + `--master-ipv4-cidr /28` + `--enable-ip-alias`.
3. Master Authorized Networks are required for any external access to the API server.
4. Private Google Access must be enabled so private nodes can reach Google APIs.
5. Two patterns: auto-created subnet **or** custom subnet with secondary ranges.
6. Verify with `kubectl get nodes -o wide` → EXTERNAL-IP column is empty.
7. Master CIDR must be unique and /28.



*This document combines the official lab content with deeper networking concepts, security implications, and exam-oriented analysis for effective learning and revision.*
