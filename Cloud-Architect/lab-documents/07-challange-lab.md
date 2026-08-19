# Implement Cloud Security Fundamentals on Google Cloud: Challenge Lab  
**Google Cloud Skills Boost Lab – GSP342**  
**Level:** Intermediate | **Duration:** ~25 minutes  

> **Study Note**  
> This is a **Challenge Lab** — no step-by-step instructions are given.  
> You must apply knowledge from previous labs (IAM custom roles, service accounts, private GKE clusters).  
> All resources must use the **“orca-”** prefix.  
> Use the least-privilege service account + fully private cluster pattern.  
> Master Authorized Networks must include **only** the internal IP of `orca-jumphost` (with `/32`).

---

## Table of Contents
1. [Overview & Scenario](#1-overview--scenario)
2. [Key Requirements Summary](#2-key-requirements-summary)
3. [Solution Walkthrough](#3-solution-walkthrough)
4. [Important Tips & Common Pitfalls](#4-important-tips--common-pitfalls)
5. [Verification Checklist](#5-verification-checklist)
6. [Quick Command Reference](#6-quick-command-reference)

---

## 1. Overview & Scenario

You are a junior security team member at Jooli Inc. (Orca team).  
You must deploy a **secure private GKE cluster** that follows the organization’s security standards:

- Dedicated least-privilege service account
- Fully private cluster (private nodes + private endpoint)
- Deployed into the existing `orca-build-subnet`
- Master Authorized Networks limited to the internal IP of the management jumphost (`orca-jumphost`)
- Custom IAM role for Cloud Storage object operations
- Test by deploying a simple application from the jumphost

**Region / Zone**: Use the lab’s assigned Region and Zone (check the lab panel).

---

## 2. Key Requirements Summary

| Task | Requirement |
|------|-------------|
| **1** | Create custom IAM role `orca-custom-role` (or similar with “orca-” prefix) with 5 specific Storage permissions |
| **2** | Create service account `orca-sa` (or similar) |
| **3** | Bind 3 built-in roles + the custom role to the service account |
| **4** | Create private GKE cluster named with “orca-” prefix using the SA, in `orca-build-subnet`, with private nodes + private endpoint + Master Authorized Networks |
| **5** | From `orca-jumphost`, get credentials with `--internal-ip` and deploy `hello-server` |

**Required Storage permissions for custom role:**
- `storage.buckets.get`
- `storage.objects.get`
- `storage.objects.list`
- `storage.objects.update`
- `storage.objects.create`

**Required built-in roles for GKE SA:**
- `roles/monitoring.viewer`
- `roles/monitoring.metricWriter`
- `roles/logging.logWriter`

---

## 3. Solution Walkthrough

### Task 1 – Create Custom Security Role

```bash
# Set variables (replace with your lab values)
export REGION=...          # e.g. us-central1
export ZONE=...            # e.g. us-central1-a
export PROJECT_ID=$(gcloud config get-value project)

# Create the custom role
gcloud iam roles create orca_custom_role \
  --project=$PROJECT_ID \
  --title="Orca Custom Role" \
  --description="Custom role for storage object operations" \
  --permissions=storage.buckets.get,storage.objects.get,storage.objects.list,storage.objects.update,storage.objects.create \
  --stage=GA
```

> Note: Role ID cannot contain spaces or special characters (use underscore).

### Task 2 – Create Service Account

```bash
gcloud iam service-accounts create orca-sa \
  --display-name="Orca Service Account"
```

### Task 3 – Bind Roles to the Service Account

```bash
SA_EMAIL=orca-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Bind the three required built-in roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/monitoring.viewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/logging.logWriter"

# Bind the custom role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="projects/$PROJECT_ID/roles/orca_custom_role"
```

### Task 4 – Create the Private GKE Cluster

```bash
# First, get the internal IP of the jumphost
gcloud compute instances describe orca-jumphost \
  --zone=$ZONE \
  --format='get(networkInterfaces[0].networkIP)'
```

Save that internal IP (example: `10.x.x.x`).

```bash
# Create the fully private cluster
gcloud container clusters create orca-cluster \
  --zone=$ZONE \
  --network=orca-build-vpc \
  --subnetwork=orca-build-subnet \
  --service-account=orca-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --enable-ip-alias \
  --enable-private-nodes \
  --enable-private-endpoint \
  --enable-master-authorized-networks \
  --master-authorized-networks <JUMPHOST_INTERNAL_IP>/32 \
  --master-ipv4-cidr=172.16.0.0/28 \
  --num-nodes=2 \
  --machine-type=e2-medium
```

> Important flags:
> - `--enable-private-endpoint` → no public control-plane endpoint
> - `--master-authorized-networks <IP>/32` → only the jumphost
> - Use the exact subnet name `orca-build-subnet`

### Task 5 – Deploy Application from Jumphost

```bash
# SSH into the jumphost
gcloud compute ssh orca-jumphost --zone=$ZONE
```

Inside the jumphost:

```bash
# Install required components
sudo apt-get update
sudo apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin kubectl

# Configure auth plugin
echo "export USE_GKE_GCLOUD_AUTH_PLUGIN=True" >> ~/.bashrc
source ~/.bashrc

# Get credentials using internal IP
gcloud container clusters get-credentials orca-cluster \
  --zone=$ZONE \
  --internal-ip \
  --project=$PROJECT_ID

# Deploy the test application
kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0

# Optional: expose it
kubectl expose deployment hello-server --type=LoadBalancer --port 8080
```

Verify:

```bash
kubectl get pods
kubectl get svc
```

---

## 4. Important Tips & Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Role ID with spaces | Use underscores (`orca_custom_role`) |
| Missing `/32` on authorized network | Always use `IP/32` for a single host |
| Forgetting `--internal-ip` | Required because private endpoint is enabled |
| Wrong network / subnet names | Must use `orca-build-vpc` and `orca-build-subnet` |
| Service account not bound correctly | Bind all 4 roles (3 built-in + 1 custom) |
| Using external IP of jumphost | Use **internal** IP of `orca-jumphost` |
| Cluster creation fails on master CIDR | Choose any unused `/28` (e.g. 172.16.0.0/28) |

---

## 5. Verification Checklist

- [ ] Custom role exists with exactly the 5 storage permissions
- [ ] Service account `orca-sa` (or orca-*) exists
- [ ] Service account has the 3 monitoring/logging roles + custom role
- [ ] Cluster is private (`enable-private-nodes` + `enable-private-endpoint`)
- [ ] Cluster is in `orca-build-subnet`
- [ ] Master Authorized Networks contains only jumphost internal IP `/32`
- [ ] From jumphost you can run `kubectl get nodes` and deploy the hello-server

---

## 6. Quick Command Reference

```bash
# Variables
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=...          # lab zone
export REGION=...        # lab region

# Custom role
gcloud iam roles create orca_custom_role --project=$PROJECT_ID \
  --permissions=storage.buckets.get,storage.objects.get,storage.objects.list,storage.objects.update,storage.objects.create

# Service account
gcloud iam service-accounts create orca-sa --display-name="Orca SA"

# Bind roles
SA=orca-sa@$PROJECT_ID.iam.gserviceaccount.com
for ROLE in roles/monitoring.viewer roles/monitoring.metricWriter roles/logging.logWriter projects/$PROJECT_ID/roles/orca_custom_role; do
  gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$SA --role=$ROLE
done

# Get jumphost internal IP
gcloud compute instances describe orca-jumphost --zone=$ZONE --format='get(networkInterfaces[0].networkIP)'

# Create private cluster
gcloud container clusters create orca-cluster \
  --zone=$ZONE \
  --network=orca-build-vpc \
  --subnetwork=orca-build-subnet \
  --service-account=$SA \
  --enable-ip-alias \
  --enable-private-nodes \
  --enable-private-endpoint \
  --enable-master-authorized-networks \
  --master-authorized-networks <INTERNAL_IP>/32 \
  --master-ipv4-cidr=172.16.0.0/28
```

---

**Good luck!**  
Follow the order of tasks carefully and double-check the “orca-” prefix on all resources.  
Once all checks pass you will score 100%.
