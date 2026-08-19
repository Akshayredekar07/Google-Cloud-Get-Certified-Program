# User Authentication: Identity-Aware Proxy  
**Google Cloud Skills Boost Lab – GSP499**  
**Level:** Introductory | **Duration:** ~30 minutes  

> **Study Note**  
> This lab is excellent for understanding **how IAP works as a zero-trust front door**.  
> It deliberately demonstrates the **danger of trusting unsigned headers**.  
> Task 2 shows the *convenient but insecure* pattern; Task 3 shows the **production-grade, cryptographically safe** pattern.  
> Always treat unsigned IAP headers as untrusted unless you also verify the JWT.

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

Identity-Aware Proxy (IAP) sits in front of your application and acts as a **centralized authentication and authorization gate**.  
It authenticates users via Google Identity, decides whether they are allowed, and (optionally) injects verified identity information into the request.

### What you will learn
- Deploy a simple Python Flask app to Cloud Run
- Enable/disable IAP to restrict access without changing application code
- Extract user identity from IAP-provided headers
- Understand why unsigned headers can be spoofed
- Cryptographically verify the IAP JWT assertion to prevent spoofing

### Challenge Lab Relevance
- **High.** IAP appears frequently in security design and zero-trust questions.
- You must know the difference between **convenience headers** vs **signed JWT**.
- You must know that the IAP service agent needs `roles/run.invoker` on Cloud Run.

---

## 2. What This Lab Is Actually Testing

| Concept | How the Lab Exercises It |
|---------|--------------------------|
| IAP as **access control layer** | Toggle IAP on/off → access is granted/denied without code changes |
| Identity propagation | Unsigned headers (`X-Goog-Authenticated-User-*`) |
| **Spoofing risk** | Demonstrated with `curl` when IAP is off |
| Cryptographic verification | JWT in `X-Goog-IAP-JWT-Assertion` header |
| Audience validation | `IAP_AUDIENCE` environment variable |
| Cloud Run + IAP integration | Granting `roles/run.invoker` to the IAP service agent |

**Key insight the lab builds toward:**  
Unsigned headers are convenient for demos but **cannot be trusted for security decisions**. Only the cryptographically signed JWT can be trusted.

---

## 3. Core Concepts

### 3.1 What is Identity-Aware Proxy?

IAP intercepts HTTP(S) requests **before** they reach your application.  
It:
1. Authenticates the user (Google Identity / OAuth)
2. Checks IAM policy (`IAP-secured Web App User` role)
3. Either blocks the request or forwards it (optionally with identity headers)

**Zero-trust principle:** Never trust the network. Authenticate every request.

### 3.2 The Three Important Headers

| Header | Purpose | Trustworthy? |
|--------|---------|--------------|
| `X-Goog-Authenticated-User-Email` | User’s email (prefixed with `accounts.google.com:`) | **No** – can be spoofed |
| `X-Goog-Authenticated-User-ID` | Persistent unique user ID | **No** – can be spoofed |
| `X-Goog-IAP-JWT-Assertion` | Cryptographically signed JWT containing identity | **Yes** – only this is safe |

> Official Google guidance:  
> “These headers should have the namespace prefix `accounts.google.com`.  
> These headers are available for compatibility, but you **shouldn’t rely on them as a security mechanism**.”

### 3.3 JWT Verification Requirements

When verifying the JWT you must check:

- **Algorithm**: `ES256`
- **Issuer (`iss`)**: `https://cloud.google.com/iap`
- **Audience (`aud`)**: The specific “Signed Header JWT Audience” Client ID for your resource
- **Expiration (`exp`)** and **Issued-at (`iat`)** with small clock skew tolerance
- Signature against Google’s public keys (fetched from `https://www.gstatic.com/iap/verify/public_key-jwk`)

### 3.4 Cloud Run + IAP Special Requirement

When IAP is enabled in front of Cloud Run, the **IAP service agent** must be allowed to invoke the service:

```
service-[PROJECT_NUMBER]@gcp-sa-iap.iam.gserviceaccount.com
```

Role required: `roles/run.invoker`

Without this binding, even authenticated users will receive 403.

### 3.5 IAP vs Application-Level Authentication

| Approach | Code Changes | Centralized Control | Best For |
|----------|--------------|---------------------|----------|
| IAP only | None (or minimal) | Yes | Internal tools, admin apps |
| App-level auth (Firebase Auth, Auth0, etc.) | Significant | No | Public SaaS products |
| Hybrid (IAP + app checks) | Moderate | Yes | High-security internal apps |

---

## 4. Hands-on Walkthrough

### Task 1 – Deploy the Application and Protect it with IAP

**Goal:** Show that access control can be added **without changing application code**.

#### 1.1 Deploy unprotected Cloud Run service

```bash
cd 1-HelloWorld

gcloud run deploy user-auth-lab \
  --source . \
  --allow-unauthenticated \
  --region="REGION"
```

Open the Service URL → you see the Hello World page (no authentication).

#### 1.2 Enable IAP

1. Navigation menu → **Security → Identity-Aware Proxy**
2. Enable the API if prompted
3. Toggle **IAP** on for `user-auth-lab`
4. Confirm **Turn On**

→ Access is now blocked for everyone.

#### 1.3 Grant access to yourself

1. Select the checkbox next to `user-auth-lab`
2. **Add Principal**
3. New principal: your student email
4. Role: **Cloud IAP → IAP-secured Web App User**
5. Save

After ~1 minute, refresh the app → you can access it.

> Tip: If stuck on “You don’t have access”, append `/_gcp_iap/clear_login_cookie` to the URL and re-authenticate.

---

### Task 2 – Access User Identity Information (Unsigned Headers)

**Goal:** Demonstrate convenient identity propagation **and** its security weakness.

#### 2.1 Deploy updated code

```bash
cd ~/user-authentication-with-iap/2-HelloUser

gcloud run deploy user-auth-lab \
  --source . \
  --region="REGION"
```

#### 2.2 Key code changes

```python
user_email = request.headers.get('X-Goog-Authenticated-User-Email')
user_id   = request.headers.get('X-Goog-Authenticated-User-ID')
```

Template displays:
```
Hello, {{ email }}! Your persistent ID is {{ id }}.
```

#### 2.3 Observe the prefix

The values appear as:
```
accounts.google.com:you@example.com
accounts.google.com:1234567890...
```

#### 2.4 Demonstrate spoofing risk

1. Turn **IAP off** and allow public access
2. Run:

```bash
curl -X GET YOUR_SERVICE_URL \
  -H "X-Goog-Authenticated-User-Email: totally fake email"
```

→ The application happily displays the fake email.  
**There is no way for the app to know IAP was bypassed.**

---

### Task 3 – Cryptographic Verification (Production Pattern)

**Goal:** Make identity information **unforgeable**.

#### 3.1 Get the JWT Audience

1. Go to **Identity-Aware Proxy**
2. Find `user-auth-lab` → Actions (⋮) → **Get JWT audience code**
3. Copy the Client ID string

#### 3.2 Deploy with audience

```bash
cd ~/user-authentication-with-iap/3-HelloVerifiedUser

gcloud run deploy user-auth-lab \
  --source . \
  --set-env-vars IAP_AUDIENCE="YOUR_CLIENT_ID" \
  --region="REGION"
```

#### 3.3 Core verification logic (`auth.py`)

```python
def user():
    assertion = request.headers.get('X-Goog-IAP-JWT-Assertion')
    if assertion is None:
        return None, None

    info = jwt.decode(
        assertion,
        keys(),                    # Google public keys
        algorithms=['ES256'],
        audience=audience()        # from IAP_AUDIENCE env var
    )
    return info['email'], info['sub']
```

- Verified email has **no** `accounts.google.com:` prefix
- If JWT is missing or invalid → returns `None`

#### 3.4 Re-enable IAP + grant invoker role

```bash
# After turning IAP back on
gcloud run services add-iam-policy-binding user-auth-lab \
  --member="serviceAccount:service-$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@gcp-sa-iap.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region="REGION"
```

Refresh the page → verified email and ID appear correctly.  
If IAP is turned off again, verified values become `None` (cannot be spoofed).

---

## 5. Key Terms You Must Know Cold

| Term | Definition |
|------|------------|
| **Identity-Aware Proxy (IAP)** | Google Cloud service that authenticates users and enforces access before traffic reaches the application |
| **IAP-secured Web App User** | IAM role that grants a principal permission to access an IAP-protected resource |
| **Unsigned identity headers** | `X-Goog-Authenticated-User-Email` and `X-Goog-Authenticated-User-ID` – convenient but spoofable |
| **X-Goog-IAP-JWT-Assertion** | Cryptographically signed JWT that proves the request passed through IAP |
| **JWT Audience (aud)** | Specific identifier of the protected resource; must match exactly |
| **IAP Service Agent** | `service-[PROJECT_NUMBER]@gcp-sa-iap.iam.gserviceaccount.com` – needs `roles/run.invoker` on Cloud Run |
| **ES256** | Elliptic Curve algorithm used to sign IAP JWTs |
| **Zero Trust** | Security model where every request is authenticated and authorized regardless of network location |

---

## 6. Commands & Console Paths Cheat Sheet

```bash
# Deploy Cloud Run (source-based)
gcloud run deploy SERVICE_NAME --source . --region=REGION

# Allow unauthenticated (initial deploy only)
gcloud run deploy SERVICE_NAME --source . --allow-unauthenticated --region=REGION

# Get service URL
gcloud run services describe SERVICE_NAME --region=REGION --format='value(status.url)'

# Grant IAP service agent invoker role
gcloud run services add-iam-policy-binding SERVICE_NAME \
  --member="serviceAccount:service-$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')@gcp-sa-iap.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --region=REGION
```

**Console paths**
- Enable / manage IAP → **Security → Identity-Aware Proxy**
- Get JWT Audience → IAP page → Actions (⋮) → **Get JWT audience code**
- Clear login cookie → append `/_gcp_iap/clear_login_cookie` to service URL

---

## 7. Exam & Design Perspective

**Maps to PCA / ACE exam domains:**  
- Designing for security and compliance  
- Identity and Access Management  
- Zero-trust architectures

### What this lab covers well
- IAP as a centralized authentication layer
- Difference between convenience headers and signed JWT
- Cloud Run + IAP integration requirements
- Practical demonstration of header spoofing

### What you still need for the exam
- IAP with Load Balancer + backend services (classic pattern)
- Context-aware access (BeyondCorp Enterprise features)
- Programmatic access to IAP-protected resources (service accounts + ID tokens)
- Organization Policy constraints related to IAP
- Combining IAP with VPC Service Controls

**Production recommendation:**  
Always verify the JWT (`X-Goog-IAP-JWT-Assertion`). Treat the unsigned email/ID headers as informational only.

---

## 8. Quick Revision Summary

1. IAP authenticates and authorizes **before** the request reaches your code.
2. Unsigned headers (`X-Goog-Authenticated-User-*`) are **spoofable** → never trust them for security decisions.
3. Always verify the JWT in `X-Goog-IAP-JWT-Assertion` (ES256 + correct audience).
4. For Cloud Run you must grant `roles/run.invoker` to the IAP service agent.
5. IAP can protect an application with **zero code changes** if you only need access control.
6. When you need identity inside the app, prefer the verified JWT path.
7. Audience mismatch or missing JWT → treat the request as unauthenticated.

---

*This document combines the official lab content with deeper security analysis, official documentation guidance, and exam-oriented insights for effective learning and revision.*
