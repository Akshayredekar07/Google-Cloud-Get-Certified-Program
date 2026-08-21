# Managing Deployments Using Kubernetes Engine  
**Google Cloud Skills Boost Lab – GSP053**  
**Level:** Intermediate | **Duration:** ~25 minutes  

> **Study Note**  
> This lab is excellent for understanding the three classic deployment strategies:  
> **Rolling Update**, **Canary**, and **Blue-Green**.  
> These are fundamental DevOps patterns and appear frequently on the PCA / ACE exams.  
> Pay special attention to how the Service selector controls traffic routing between deployments.

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

Kubernetes Deployments manage the desired state of your application (replicas, image version, labels, etc.).  
This lab teaches you how to use Deployments to implement common production release strategies.

### What you will learn
- Create and manage Deployment objects with YAML
- Scale Deployments
- Perform Rolling Updates (with pause / resume / undo)
- Implement Canary deployments
- Implement Blue-Green deployments
- Control traffic using Service selectors

---

## 2. What This Lab Is Actually Testing

| Concept | How the Lab Exercises It |
|---------|--------------------------|
| Deployment object | Create from YAML, explain structure |
| Scaling | `kubectl scale` |
| Rolling Update | Edit image → Kubernetes gradually replaces pods |
| Rollout history / pause / resume / undo | Full lifecycle of a rolling update |
| Canary | Second Deployment with same labels + Service selector |
| Blue-Green | Two Deployments + switch Service selector |
| Service selector | The key mechanism that routes traffic |

**Key insight:**  
The **Service** is the traffic router. Changing its `selector` instantly switches traffic between Deployments.

---

## 3. Core Concepts

### 3.1 Deployment Strategies Compared

| Strategy | How it works | Downtime | Risk | Use Case |
|----------|--------------|----------|------|----------|
| **Rolling Update** | Gradually replace old pods with new ones | None | Medium | Most common default |
| **Canary** | Run small % of new version alongside old | None | Low | Test new version with real traffic |
| **Blue-Green** | Run full new version in parallel, then switch | None (or very brief) | Low | Instant switch / easy rollback |

### 3.2 How Traffic Routing Works

- A **Service** selects Pods based on **labels**.
- Multiple Deployments can share the same labels → traffic is load-balanced across all matching Pods.
- Changing the Service selector instantly changes which Pods receive traffic.

### 3.3 Useful Labels Pattern (used in this lab)

```yaml
labels:
  app: fortune-app          # common label → matched by Service
  track: stable / canary    # used for Blue-Green / Canary selection
  version: "1.0.0"
```

---

## 4. Hands-on Walkthrough

### Setup

```bash
gcloud config set compute/zone europe-west1-c

gcloud storage cp -r gs://spls/gsp053/kubernetes .
cd kubernetes

gcloud container clusters create bootcamp \
  --machine-type e2-small \
  --num-nodes 3 \
  --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw"
```

### Task 1 – Explore the Deployment Object

```bash
kubectl explain deployment
kubectl explain deployment --recursive
kubectl explain deployment.metadata.name
```

### Task 2 – Create and Scale a Deployment

```bash
# Create blue deployment (v1.0.0)
kubectl create -f deployments/fortune-app-blue.yaml

# Create Service
kubectl create -f services/fortune-app.yaml

# Test
curl http://$(kubectl get svc fortune-app -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")/version

# Scale up / down
kubectl scale deployment fortune-app-blue --replicas=5
kubectl scale deployment fortune-app-blue --replicas=3
```

### Task 3 – Rolling Update

```bash
# Edit the deployment and change image tag 1.0.0 → 2.0.0
kubectl edit deployment fortune-app-blue

# Watch the rollout
kubectl get replicaset
kubectl rollout history deployment/fortune-app-blue

# Pause / Resume
kubectl rollout pause deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue
kubectl rollout resume deployment/fortune-app-blue

# Rollback
kubectl rollout undo deployment/fortune-app-blue
```

### Task 4 – Canary Deployment

```bash
# Create canary (small number of pods running v2.0.0)
kubectl create -f deployments/fortune-app-canary.yaml

# Both deployments share the same Service selector → traffic is mixed
for i in {1..10}; do
  curl -s http://$(kubectl get svc fortune-app -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")/version
  echo
done
```

You will see mostly `1.0.0` and occasionally `2.0.0`.

### Task 5 – Blue-Green Deployment

```bash
# Point Service only to blue
kubectl apply -f services/fortune-app-blue-service.yaml

# Create green deployment (v2.0.0)
kubectl create -f deployments/fortune-app-green.yaml

# Switch traffic to green
kubectl apply -f services/fortune-app-green-service.yaml

# Instant switch – now always serves 2.0.0
curl http://$(kubectl get svc fortune-app -o=jsonpath="{.status.loadBalancer.ingress[0].ip}")/version

# Rollback = switch Service back to blue
kubectl apply -f services/fortune-app-blue-service.yaml
```

---

## 5. Key Terms You Must Know Cold

| Term | Definition |
|------|------------|
| **Deployment** | Declarative object that manages ReplicaSets and Pods |
| **ReplicaSet** | Ensures a specified number of pod replicas are running |
| **Rolling Update** | Gradual replacement of old pods with new ones |
| **Canary Deployment** | Small subset of traffic goes to the new version |
| **Blue-Green Deployment** | Two full environments; traffic is switched all at once |
| **Service selector** | Labels used by a Service to select which Pods receive traffic |
| **Rollout** | The process of updating a Deployment to a new version |
| **kubectl rollout undo** | Rolls back to the previous revision |

---

## 6. Commands & Console Paths Cheat Sheet

```bash
# Create
kubectl create -f file.yaml
kubectl apply -f file.yaml

# Scale
kubectl scale deployment NAME --replicas=N

# Rolling update controls
kubectl edit deployment NAME
kubectl rollout pause / resume / status / history / undo deployment/NAME

# Inspect
kubectl get deployments,replicasets,pods,svc
kubectl explain deployment

# One-liner to get external IP
kubectl get svc fortune-app -o=jsonpath="{.status.loadBalancer.ingress[0].ip}"
```

---

## 7. Exam & Design Perspective

**Maps to PCA / ACE exam domains:**  
- Managing application deployments  
- Implementing progressive delivery strategies

### What this lab covers well
- Rolling Update lifecycle (pause, resume, undo)
- Canary vs Blue-Green trade-offs
- How Service selectors control traffic

### Production recommendations
- Prefer **Rolling Update** for most applications (default strategy).
- Use **Canary** when you want to validate with real traffic before full rollout.
- Use **Blue-Green** when you need instant switch + easy rollback (or when the application cannot run mixed versions).
- Always use meaningful labels (`app`, `version`, `track`).

---

## 8. Quick Revision Summary

1. **Deployment** manages desired state → creates ReplicaSets → creates Pods.
2. **Rolling Update** = gradual replacement (default strategy).
3. **Canary** = second Deployment with same labels → Service automatically load-balances.
4. **Blue-Green** = two Deployments + change Service selector to switch traffic.
5. `kubectl rollout undo` is your instant rollback for rolling updates.
6. Service selector is the traffic switch — changing it is instantaneous.
7. Always test with `/version` endpoint after each strategy change.

