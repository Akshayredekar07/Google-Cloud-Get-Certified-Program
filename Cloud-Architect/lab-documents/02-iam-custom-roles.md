# GCP Skill Badge: Implement Cloud Security Fundamentals on Google Cloud
## Lab 2 of N — IAM Custom Roles (GSP190)

**Level:** Introductory | **Status:** Lab environment only — building block toward the challenge lab's "create a custom security role" task.

---

### What this lab is actually testing

Lab 1 (GSP064) taught you to grant/revoke *existing* roles (Basic + one Predefined). This lab is where you stop consuming roles Google built and start building your own. This is the direct prerequisite skill for the challenge lab's first task ("create a custom security role") — if you're shaky here, that's where the challenge lab will bite first.

---

## Core Concept: Predefined vs Custom Roles

Two role types now, not one:

| Type | Who maintains it | Auto-updates with new GCP features? | Use when |
|---|---|---|---|
| **Predefined** | Google | Yes | A Google-curated role already matches your need |
| **Custom** | You | No — you own the maintenance burden | You need a permission set no predefined role matches, or you need to enforce least privilege more tightly than predefined roles allow |

**Key tradeoff the lab doesn't say out loud but the exam will test:** custom roles buy you precision, but they cost you maintenance. If Google adds a new permission relevant to your use case, your custom role does NOT get it automatically — you have to notice and add it yourself. This is a real operational liability, not just a lab footnote. Section 3.1 of the PCA exam guide (Designing for security → IAM) expects you to know this tradeoff when choosing predefined vs custom in a design scenario.

---

## Core Concept: Permission Syntax

Every IAM permission follows a fixed grammar:

```
<service>.<resource>.<verb>
```

Examples from the lab:
- `compute.instances.list` — list Compute Engine instances
- `compute.instances.stop` — stop a VM
- `appengine.versions.create` — create an App Engine version
- `storage.buckets.get` — read a bucket's metadata

**Important nuance:** permissions usually map 1:1 to REST API methods — to call a given API method, the caller needs the matching permission. This is *why* the permission strings look like `service.resource.verb` — they mirror the underlying REST surface. Knowing this lets you reverse-engineer what permission you need just by knowing which API call you're trying to make.

Custom roles = you hand-picking a bag of these permission strings and bundling them under one role name.

---

## Prerequisites to Create a Custom Role

- Caller needs `iam.roles.create` permission.
- By default, only the **project owner** has this.
- Anyone else needs to be explicitly given either:
  - `roles/iam.roleAdmin` (IAM Role Administrator) — project-level
  - `roles/iam.organizationRoleAdmin` (Organization Role Administrator) — org-level
- `roles/iam.securityReviewer` can **view** custom roles but not create/manage them — a read-only auditor role. Don't confuse this with actual admin capability.

**Scope constraint:** custom roles can be created at the **organization** or **project** level — NOT at the folder level. This is a specific gotcha worth memorizing; it's an easy multiple-choice trap ("create a custom role at the folder level" as a wrong answer option).

**Portability constraint:** a custom role only works within the project/org that owns it. You cannot take a custom role built in Project A and apply it to a resource in Project B.

---

## What the lab makes you actually do

### Task 1 — Discover what permissions exist for a resource
Before building a role, you need to know what raw permissions are even available to bundle.

```bash
gcloud iam list-testable-permissions //cloudresourcemanager.googleapis.com/projects/$DEVSHELL_PROJECT_ID
```

Returns every permission applicable to that project (and everything below it in the hierarchy), each tagged with a launch stage (GA / BETA / TESTING). This is your palette before you start composing a custom role.

### Task 2 — Inspect role metadata (predefined or custom)
```bash
gcloud iam roles describe [ROLE_NAME]
# e.g. gcloud iam roles describe roles/viewer
```
Returns the role's `includedPermissions` list, its `stage`, and an `etag` (more on that below — it matters later for updates).

### Task 3 — See what roles can even be granted on a resource
```bash
gcloud iam list-grantable-roles //cloudresourcemanager.googleapis.com/projects/$DEVSHELL_PROJECT_ID
```
Different from Task 1 — this lists *roles*, not raw permissions.

### Task 4 — Create a custom role (two methods)

**Method A: YAML file definition**
```yaml
title: "Role Editor"
description: "Edit access for App Versions"
stage: "ALPHA"
includedPermissions:
- appengine.versions.create
- appengine.versions.delete
```
```bash
gcloud iam roles create editor --project $DEVSHELL_PROJECT_ID --file role-definition.yaml
```

**Method B: inline flags**
```bash
gcloud iam roles create viewer --project $DEVSHELL_PROJECT_ID \
  --title "Role Viewer" --description "Custom role description." \
  --permissions compute.instances.get,compute.instances.list --stage ALPHA
```

Both do the same thing — YAML is better for version-controlling role definitions (e.g. storing in a repo alongside Terraform), flags are faster for one-off changes. In real infra-as-code workflows you'd use YAML (or Terraform's own IAM resource) so the role definition is reviewable and diffable — worth remembering for the exam's IaC-adjacent questions (Section 5.2 mentions Terraform explicitly).

**`stage` field values:** `ALPHA`, `BETA`, `GA`, `DEPRECATED`, `DISABLED` — this is a lifecycle marker on the role itself, separate from whether individual permissions inside it are GA/BETA.

### Task 5 — List custom roles
```bash
gcloud iam roles list --project $DEVSHELL_PROJECT_ID     # project-level custom roles
gcloud iam roles list                                     # predefined roles
gcloud iam roles list --project $DEVSHELL_PROJECT_ID --show-deleted   # include deleted
```

### Task 6 — Update a custom role, and the etag concurrency mechanism
This is the most conceptually important part of the lab and the easiest to skim past.

**Problem:** two admins editing the same custom role simultaneously could silently overwrite each other's changes (classic read-modify-write race condition).

**Solution — etag:** every custom role carries an `etag`, a hash representing its current version. The update flow is:
1. `describe` the role → get current definition + its etag
2. Edit the definition locally (add/remove permissions)
3. Submit the update **including the etag you read in step 1**
4. IAM compares your submitted etag against the role's live etag. Match → write succeeds. Mismatch (someone else changed it since your read) → write is rejected.

This is optimistic concurrency control — the same pattern used in HTTP `If-Match` headers, database row versioning, etc. You've likely seen this pattern before in your own backend work (FastAPI/Redis pub-sub context) — same principle, different domain.

Two update methods, mirroring creation:
```bash
# via YAML (must include the etag from `describe`)
gcloud iam roles update editor --project $DEVSHELL_PROJECT_ID --file new-role-definition.yaml

# via flags — additive/subtractive without needing to know the full existing list
gcloud iam roles update viewer --project $DEVSHELL_PROJECT_ID \
  --add-permissions storage.buckets.get,storage.buckets.list
# or --remove-permissions, or --permissions to replace wholesale
```

### Task 7 — Disable a role (soft-off switch)
```bash
gcloud iam roles update viewer --project $DEVSHELL_PROJECT_ID --stage DISABLED
```
Disabling ≠ deleting. Any existing IAM policy bindings that reference this role become **inactive** — the permissions stop being granted — but the role definition and the bindings themselves still exist. This is the safer, reversible first step before deletion (e.g. "we think nobody uses this role anymore, disable it, watch for breakage, delete later").

### Task 8 — Delete a role
```bash
gcloud iam roles delete viewer --project $DEVSHELL_PROJECT_ID
```
**Deletion lifecycle — memorize these numbers, they're a plausible exam detail:**
- Deleted role → immediately enters `DISABLED` state, existing bindings remain but stay inactive
- **7-day window** — role can be restored (`undelete`)
- After 7 days → enters permanent deletion process lasting **30 more days**
- **37 days total** after deletion → the Role ID becomes available for reuse

### Task 9 — Restore a deleted role
```bash
gcloud iam roles undelete viewer --project $DEVSHELL_PROJECT_ID
```
Only works inside the 7-day window from Task 8.

---

## Terms you should walk away able to define cold

- **Custom role** — user-defined bundle of permissions, not auto-maintained by Google, scoped to org or project (never folder)
- **Predefined role** — Google-maintained, auto-updated bundle
- **Permission syntax** — `service.resource.verb`, generally 1:1 with REST methods
- **etag** — version fingerprint used for optimistic concurrency control on role updates
- **Role stage lifecycle** — ALPHA / BETA / GA / DEPRECATED / DISABLED
- **iam.roleAdmin vs iam.organizationRoleAdmin vs iam.securityReviewer** — manage-project / manage-org / view-only respectively
- **Deletion → undelete window** — 7 days soft-deleted, +30 days hard-deletion process, 37 days total until Role ID reuse

---

## Gaps this lab does NOT cover

- Attaching a custom role to a principal via a policy binding (this lab builds/manages the role object itself, never actually grants it to anyone — that's `gcloud projects add-iam-policy-binding` or the Grant Access UI flow from Lab 1, not exercised here)
- IAM Conditions (attribute/time-based access)
- Testing least-privilege in practice against a real workload
- Custom roles at the organization level (this lab only exercises project-level creation, despite org-level being mentioned as valid scope)

---

## Quick Reference

| Action | Command |
|---|---|
| List permissions available on a resource | `gcloud iam list-testable-permissions //cloudresourcemanager.googleapis.com/projects/$DEVSHELL_PROJECT_ID` |
| Describe a role (predefined or custom) | `gcloud iam roles describe [ROLE_NAME]` |
| List grantable roles on a resource | `gcloud iam list-grantable-roles //cloudresourcemanager.googleapis.com/projects/$DEVSHELL_PROJECT_ID` |
| Create custom role (YAML) | `gcloud iam roles create [ID] --project $DEVSHELL_PROJECT_ID --file role-definition.yaml` |
| Create custom role (flags) | `gcloud iam roles create [ID] --project $DEVSHELL_PROJECT_ID --title "..." --permissions p1,p2 --stage ALPHA` |
| List custom roles | `gcloud iam roles list --project $DEVSHELL_PROJECT_ID` |
| Update role (add/remove permissions) | `gcloud iam roles update [ID] --project $DEVSHELL_PROJECT_ID --add-permissions p1,p2` |
| Disable a role | `gcloud iam roles update [ID] --project $DEVSHELL_PROJECT_ID --stage DISABLED` |
| Delete a role | `gcloud iam roles delete [ID] --project $DEVSHELL_PROJECT_ID` |
| Restore a deleted role (within 7 days) | `gcloud iam roles undelete [ID] --project $DEVSHELL_PROJECT_ID` |

**Lab ID for reference:** GSP190