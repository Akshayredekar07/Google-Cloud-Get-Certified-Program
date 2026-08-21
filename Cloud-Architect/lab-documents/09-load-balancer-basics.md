# Set Up Network Load Balancers  
**Google Cloud Skills Boost Lab – GSP007**  
**Level:** Introductory | **Duration:** ~15 minutes  

> **Study Note**  
> This lab teaches the classic **passthrough Network Load Balancer (Layer 4)** using the **Target Pool** model.  
> It is a regional, Layer-4 load balancer that does **not** inspect HTTP content and does **not** terminate SSL.  
> All commands below are complete and ready to copy-paste. Do not skip any step.

---

## Table of Contents
1. [Overview & Learning Objectives](#1-overview--learning-objectives)
2. [What This Lab Is Actually Testing](#2-what-this-lab-is-actually-testing)
3. [Core Concepts](#3-core-concepts)
4. [Hands-on Walkthrough (Complete Commands)](#4-hands-on-walkthrough-complete-commands)
5. [Key Terms You Must Know Cold](#5-key-terms-you-must-know-cold)
6. [Commands Cheat Sheet](#6-commands-cheat-sheet)
7. [Exam & Design Perspective](#7-exam--design-perspective)
8. [Quick Revision Summary](#8-quick-revision-summary)

---

## 1. Overview & Learning Objectives

In this lab you will build a complete **Network Load Balancer** that distributes HTTP traffic across three Apache web servers.

### What you will do
- Set default region and zone
- Create three web server VMs with Apache installed via startup script
- Create a firewall rule using network tags
- Reserve a static external IP address
- Create an HTTP health check
- Create a Target Pool and add the three VMs
- Create a Forwarding Rule
- Test that traffic is distributed across all three backends

---

## 2. What This Lab Is Actually Testing

| Concept                        | How the Lab Tests It                                      |
|--------------------------------|-----------------------------------------------------------|
| Network tags                   | One firewall rule applies to all three VMs                |
| Startup scripts                | Apache is installed and unique homepage is set            |
| Static external IP             | Reserved for the load balancer                            |
| HTTP health check              | Used by the Target Pool to mark backends healthy/unhealthy|
| Target Pool                    | Groups the three backend instances                        |
| Forwarding Rule                | Public entry point that clients connect to                |
| Traffic distribution           | Continuous `curl` shows responses from different VMs      |

---

## 3. Core Concepts

### 3.1 Network Load Balancer Characteristics
- **Layer**: 4 (TCP/UDP)
- **Scope**: Regional
- **Type**: Passthrough (original client IP is preserved)
- **SSL termination**: No
- **Content-based routing**: No

### 3.2 Main Components
1. Backend instances (the three VMs)
2. Target Pool (group of backends)
3. Health Check
4. Forwarding Rule (public IP + port)
5. Static External IP (optional but used in this lab)

### 3.3 Network Tags
Instead of listing instance names in firewall rules, you attach a **tag** (`network-lb-tag`) to the VMs.  
The firewall rule then targets that tag.

---

## 4. Hands-on Walkthrough (Complete Commands)

### Task 1 – Set the default region and zone

```bash
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

---

### Task 2 – Create multiple web server instances

#### Create www1

```bash
gcloud compute instances create www1 \
  --zone=us-central1-a \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "<h3>Web Server: www1</h3>" | tee /var/www/html/index.html'
```

#### Create www2

```bash
gcloud compute instances create www2 \
  --zone=us-central1-a \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "<h3>Web Server: www2</h3>" | tee /var/www/html/index.html'
```

#### Create www3

```bash
gcloud compute instances create www3 \
  --zone=us-central1-a \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "<h3>Web Server: www3</h3>" | tee /var/www/html/index.html'
```

#### Create firewall rule (allows HTTP traffic to any VM with the tag)

```bash
gcloud compute firewall-rules create www-firewall-network-lb \
  --target-tags network-lb-tag \
  --allow tcp:80
```

#### List instances and verify each one works

```bash
gcloud compute instances list
```

Replace `[IP_ADDRESS]` with the EXTERNAL_IP of each instance and test:

```bash
curl http://[IP_ADDRESS]
```

You should see:
- `<h3>Web Server: www1</h3>`
- `<h3>Web Server: www2</h3>`
- `<h3>Web Server: www3</h3>`

---

### Task 3 – Configure the load balancing service

#### Reserve a static external IP address

```bash
gcloud compute addresses create network-lb-ip-1 \
  --region us-central1
```

#### Create a legacy HTTP health check

```bash
gcloud compute http-health-checks create basic-check
```

---

### Task 4 – Create the target pool and forwarding rule

#### Create the Target Pool and attach the health check

```bash
gcloud compute target-pools create www-pool \
  --region us-central1 \
  --http-health-check basic-check
```

#### Add the three instances to the Target Pool

```bash
gcloud compute target-pools add-instances www-pool \
  --instances www1,www2,www3
```

#### Create the Forwarding Rule (this is the public entry point)

```bash
gcloud compute forwarding-rules create www-rule \
  --region us-central1 \
  --ports 80 \
  --address network-lb-ip-1 \
  --target-pool www-pool
```

---

### Task 5 – Send traffic to your instances

#### Get the external IP of the Forwarding Rule

```bash
gcloud compute forwarding-rules describe www-rule --region us-central1
```

#### Store the IP in a variable

```bash
IPADDRESS=$(gcloud compute forwarding-rules describe www-rule \
  --region us-central1 \
  --format="json" | jq -r .IPAddress)
```

#### Display the IP

```bash
echo $IPADDRESS
```

#### Continuously send traffic to the load balancer

```bash
while true; do curl -m1 $IPADDRESS; done
```

You will see the responses alternating between the three web servers:

```
<h3>Web Server: www1</h3>
<h3>Web Server: www2</h3>
<h3>Web Server: www3</h3>
```

Press `Ctrl + C` to stop the loop.

---

## 5. Key Terms You Must Know Cold

| Term                    | Definition |
|-------------------------|----------|
| **Network Load Balancer** | Regional Layer-4 passthrough load balancer |
| **Target Pool**         | Group of backend instances in the same region |
| **Forwarding Rule**     | Public IP + port that clients connect to |
| **Health Check**        | Periodically checks if backends are healthy |
| **Network Tag**         | Label used to apply firewall rules to groups of VMs |
| **Static External IP**  | Reserved IP that does not change |
| **Passthrough**         | Load balancer does not terminate the connection |
| **Startup Script**      | Script that runs when a VM first boots |

---

## 6. Commands Cheat Sheet

```bash
# Region & Zone
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a

# Create VM with tag + startup script
gcloud compute instances create NAME \
  --zone=us-central1-a \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata=startup-script='...'

# Firewall rule using tags
gcloud compute firewall-rules create NAME \
  --target-tags network-lb-tag \
  --allow tcp:80

# Static IP
gcloud compute addresses create network-lb-ip-1 --region us-central1

# Health check
gcloud compute http-health-checks create basic-check

# Target Pool
gcloud compute target-pools create www-pool \
  --region us-central1 \
  --http-health-check basic-check

gcloud compute target-pools add-instances www-pool \
  --instances www1,www2,www3

# Forwarding Rule
gcloud compute forwarding-rules create www-rule \
  --region us-central1 \
  --ports 80 \
  --address network-lb-ip-1 \
  --target-pool www-pool

# Get Load Balancer IP
IPADDRESS=$(gcloud compute forwarding-rules describe www-rule \
  --region us-central1 --format="json" | jq -r .IPAddress)
```

---

## 7. Exam & Design Perspective

**Relevant exam topics:**
- Network topologies
- Load balancing options
- Firewall rules with network tags

**When to use Network Load Balancer:**
- Non-HTTP protocols
- You need the original client IP preserved
- Simple regional TCP/UDP load balancing

**Modern alternative:**  
Backend Service-based Network Load Balancer (recommended for new designs).

---

## 8. Quick Revision Summary

1. Network LB = regional, Layer-4, passthrough.
2. Components: VMs → Target Pool → Forwarding Rule + Health Check.
3. Use **network tags** for firewall rules.
4. Reserve a **static IP** for the Forwarding Rule.
5. Health checks keep unhealthy backends out of rotation.
6. Clients only talk to the Forwarding Rule IP.
7. Traffic is automatically distributed across healthy instances.
