# Service Accounts and Roles: Fundamentals  
**Google Cloud Skills Boost Lab – GSP199**  
**Level:** Introductory | **Duration:** ~15 minutes  

> **Study Note**  
> This lab is excellent for learning the *mechanics* of service accounts.  
> It is **not** a complete model of production security design.  
> Task 1 deliberately uses an over-privileged role (`roles/editor`) to teach syntax.  
> Always prefer least privilege in real designs and on the exam.

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

Service accounts are special Google accounts that belong to **applications or virtual machines**, not to human users. They are the primary way to give workloads safe, managed access to Google Cloud APIs and resources.

### What you will learn
- Create and manage service accounts
- Attach a service account to a Compute Engine VM
- Use the client libraries to call BigQuery as a service account
- Run a query against a BigQuery public dataset from a VM **without any key file**

### Challenge Lab Relevance
- **Partial only.**
- Correctly teaches SA creation and role-granting mechanics.
- Task 1 grants `roles/editor` — an over-privileged pattern that should **not** be copied into real designs or challenge-lab answers.
- If a challenge lab expects least-privilege SA design, this lab alone under-prepares you.

---

## 2. What This Lab Is Actually Testing

| Concept | How the Lab Exercises It |
|---------|--------------------------|
| SA as **identity** | Grant roles *to* the SA so it can act (Task 1 & Task 2) |
| SA as **resource** | *Not* exercised. The lab never grants `roles/iam.serviceAccountUser` to a human |
| Least privilege | Only partially. Task 2 uses narrower BigQuery roles; Task 1 does not |
| Two-layer restriction | IAM roles + Access scopes on the VM |
| Ambient credentials | `compute_engine.Credentials` — no key file, token from metadata server |
| BigQuery role split | `BigQuery Data Viewer` + `BigQuery User` are both required |

**Key insight the lab builds toward (without stating it clearly):**  
A service account can be treated as an **identity** (you grant it roles) *or* as a **resource** (you control who can use/attach it). This lab only covers the identity side.

---

## 3. Core Concepts

### 3.1 Service Account Types

| Type | Email Format | Notes |
|------|--------------|-------|
| **Default Compute Engine SA** | `PROJECT_NUMBER-compute@developer.gserviceaccount.com` | Auto-created when Compute Engine API is enabled. Historically over-privileged (Editor). Recurring security gotcha. |
| **Default App Engine SA** | `PROJECT_ID@appspot.gserviceaccount.com` | Auto-created with an App Engine app. Same over-privilege concern. |
| **User-managed SA** | `name@PROJECT_ID.iam.gserviceaccount.com` | Explicitly created by you. This is the pattern you should design with. |
| **Google APIs SA** (Google-managed) | `PROJECT_NUMBER@cloudservices.gserviceaccount.com` | Runs internal Google processes. Holds Editor by design. **Not** listed under Service Accounts UI. Do **not** modify its role. Deleted only when the project is deleted. |

You can create up to **100** service accounts per project (including the two defaults).

### 3.2 IAM Role Types

| Type | Description | Exam Relevance |
|------|-------------|----------------|
| **Primitive** | Owner / Editor / Viewer | Project-wide, coarse, pre-IAM. Almost always the **wrong** answer on least-privilege questions. |
| **Predefined** | Per-service, granular, Google-managed | Default correct-answer category for most access-design questions. |
| **Custom** | User-specified list of permissions | Not exercised in this lab. |

### 3.3 SA as Identity vs SA as Resource

- **As identity** → Grant a role *to* the SA on some resource so the SA can act.  
  Example (Task 1): grant `roles/editor` to `my-sa-123` on the project.

- **As resource** → Grant a role *to a user* *on* the SA itself.  
  Relevant role: `roles/iam.serviceAccountUser`. Controls who can attach or impersonate the SA.  
  **This lab never exercises this side.**

### 3.4 Access Scopes vs IAM Roles (Two Layers)

Access scopes are a **legacy VM-level** restriction that limits which Google APIs the attached SA’s credentials can even reach.

- Both layers must allow the action:
  - **IAM** decides *what* the SA is allowed to do.
  - **Access scope** decides *whether the VM is allowed to ask*.
- In Task 2 the lab forces you to set “BigQuery: Enabled” under access scopes.
- **Production / exam best practice:** Use the `cloud-platform` scope and let IAM do all the real restriction. The lab’s per-API scope is teaching mechanics, not the recommended pattern.

### 3.5 BigQuery Role Split (Common Exam Trap)

| Role | What it allows | What happens if missing |
|------|----------------|-------------------------|
| **BigQuery Data Viewer** (`roles/bigquery.dataViewer`) | Read dataset contents and metadata | Query fails to read the table |
| **BigQuery User** (`roles/bigquery.user`) | Create and run jobs (billed to your project) | You can see the data exists but cannot execute a query |

Both roles are required to run `client.query(...).to_dataframe()` against a public dataset.

### 3.6 Ambient Credentials (No Key Files)

```python
from google.auth import compute_engine
credentials = compute_engine.Credentials(service_account_email="...")
```

- No key file, no `GOOGLE_APPLICATION_CREDENTIALS` environment variable.
- The client library obtains a short-lived token from the **VM’s metadata server**, scoped to the service account attached to the instance.
- This is the pattern the exam prefers over long-lived key files.

---

## 4. Hands-on Walkthrough

### Task 1 – Create and Manage Service Accounts (Identity Side)

**Goal:** Show the basic syntax of creating an SA and granting it a role.

```bash
# Create a user-managed service account
gcloud iam service-accounts create my-sa-123 \
  --display-name "my service account"

# Grant a role TO the SA (identity side)
# Note: roles/editor is deliberately over-privileged — used only to teach syntax
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member="serviceAccount:my-sa-123@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/editor"
```

> **Study warning:** Do **not** carry `roles/editor` forward as a real-design template. Prefer the narrowest predefined roles that satisfy the requirement.

### Task 2 – Access BigQuery Using a Service Account

**Goal:** Demonstrate a more realistic (still simplified) pattern:
- Narrow roles
- SA attached to a VM
- Ambient credentials (no key file)
- Both BigQuery roles required

#### 2.1 Create the Service Account (Console)

1. **IAM & Admin → Service accounts → + Create Service Account**
2. Name: `bigquery-qwiklab`
3. Grant:
   - BigQuery Data Viewer
   - BigQuery User
4. Click **Done**

#### 2.2 Create the VM and Attach the SA

**Compute Engine → VM instances → Create Instance**

| Setting | Value |
|---------|-------|
| Name | `bigquery-instance` |
| Region / Zone | `us-west4` / `us-west4-a` |
| Machine type | `e2-medium` |
| Boot disk | Debian GNU/Linux 12 (bookworm) |
| **Service account** | `bigquery-qwiklab` |
| Access scopes | Set access for each API → **BigQuery: Enabled** |

> The Security tab is intentionally shown so you see SA attachment and access scopes side-by-side (the two-layer restriction).

#### 2.3 Prepare the Environment on the VM

```bash
sudo apt install python3 python3-pip python3.11-venv -y
python3 -m venv myvenv
source myvenv/bin/activate

sudo apt-get update
sudo apt-get install -y git python3-pip
pip3 install --upgrade pip
pip3 install google-cloud-bigquery pyarrow pandas db-dtypes
```

#### 2.4 Create and Configure the Query Script

```bash
# Create the file (with placeholders)
cat > query.py << 'EOF'
from google.auth import compute_engine
from google.cloud import bigquery

credentials = compute_engine.Credentials(
    service_account_email="YOUR_SERVICE_ACCOUNT")

query = """
SELECT
  year,
  COUNT(1) as num_babies
FROM
  publicdata.samples.natality
WHERE
  year > 2000
GROUP BY
  year
"""

client = bigquery.Client(
    project="YOUR_PROJECT_ID",
    credentials=credentials)
print(client.query(query).to_dataframe())
EOF

# Replace placeholders
sed -i -e "s/YOUR_PROJECT_ID/$(gcloud config get-value project)/g" query.py
sed -i -e "s/YOUR_SERVICE_ACCOUNT/bigquery-qwiklab@$(gcloud config get-value project).iam.gserviceaccount.com/g" query.py
```

#### 2.5 Run the Query

```bash
python3 query.py
```

Successful output confirms:
- Both BigQuery roles were granted and effective
- Ambient credentials worked (no key file)
- The attached SA’s identity was used correctly

---

## 5. Key Terms You Must Know Cold

| Term | Definition |
|------|------------|
| **Service account** | Non-human identity for an application or VM, identified by a unique email address |
| **User-managed service account** | Explicitly created by you (as opposed to the two Google defaults) |
| **Default Compute Engine SA** | `PROJECT_NUMBER-compute@developer.gserviceaccount.com` |
| **Google APIs (Google-managed) SA** | `PROJECT_NUMBER@cloudservices.gserviceaccount.com` — holds Editor by design, do not modify |
| **Primitive role** | Owner / Editor / Viewer — project-wide, pre-IAM, usually too broad |
| **Predefined role** | Per-service, Google-managed, granular |
| **Custom role** | User-specified permission set |
| **IAM policy binding** | Pairing of a role to a member on a resource |
| **SA as identity** | SA is granted a role *on* a resource so it can act |
| **SA as resource** | A user is granted a role *on* the SA itself (e.g. `serviceAccountUser`) controlling who can use/attach it |
| **Access scope** | Legacy VM-level restriction on which APIs the attached SA’s credentials can reach |
| **BigQuery Data Viewer** | Read access to dataset contents and metadata |
| **BigQuery User** | Permission to create and run query jobs billed to the project |
| **Ambient / metadata-server credentials** | Authentication via the VM’s attached SA with no key file |

---

## 6. Commands & Console Paths Cheat Sheet

```bash
# Create a user-managed service account
gcloud iam service-accounts create SA_NAME --display-name "Description"

# Grant a role to an SA (identity side)
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:EMAIL" \
  --role="roles/ROLE_NAME"

# Useful helpers
gcloud config set compute/region REGION
gcloud auth list
gcloud config list project
gcloud iam service-accounts list
```

**Console paths**
- Create SA + grant roles → **IAM & Admin → Service accounts → + Create Service Account**
- Attach SA to VM + set access scopes → **Compute Engine → VM Instances → Create → Security tab**

---

## 7. Exam & Design Perspective

**Maps to PCA exam guide:**  
“Designing for security and compliance” → Identity and Access Management (IAM)

### What this lab covers well
- SA creation and basic role-granting mechanics
- Difference between identity-side and (theoretically) resource-side use of SAs
- Ambient credentials pattern
- Why two BigQuery roles are needed

### What this lab does **not** cover (and you still need for the exam)
- Role hierarchy / inheritance across organization → folder → project
- Custom role design decisions
- Service account key lifecycle and keyless alternatives (Workload Identity, etc.)
- Audit logging design
- Proper least-privilege design (Task 1 actively works against this)

**Treat this lab as prerequisite scaffolding, not exam-sufficient coverage.**

---

## 8. Quick Revision Summary

1. Prefer **user-managed** service accounts scoped to a single workload.
2. Grant the **narrowest predefined roles** that satisfy the need (avoid primitive roles).
3. Remember the dual nature: SA can be an **identity** *or* a **resource**.
4. On VMs, both **IAM roles** and **access scopes** must allow the action. Prefer `cloud-platform` scope + strong IAM.
5. For BigQuery queries you almost always need both **Data Viewer** and **User**.
6. Prefer **ambient credentials** (metadata server) over downloading key files.
7. Never modify the Google-managed `...@cloudservices.gserviceaccount.com` account.

---

*This document combines the official lab content with deeper conceptual notes, security caveats, and exam-oriented analysis for effective learning and revision.*
