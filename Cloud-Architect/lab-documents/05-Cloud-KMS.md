# Getting Started with Cloud KMS  
**Google Cloud Skills Boost Lab – GSP079**  
**Level:** Introductory | **Duration:** ~15 minutes  

> **Study Note**  
> This lab is excellent for learning the **mechanics** of Cloud KMS (KeyRings, CryptoKeys, encrypt/decrypt API).  
> It deliberately shows **client-side encryption** (you encrypt then upload).  
> In real production, prefer **Cloud Storage Server-Side Encryption with CMEK** (Customer-Managed Encryption Keys) + automatic key rotation.  
> The lab’s manual encryption + upload pattern is for teaching only — do **not** copy it into production designs or challenge labs.

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

Cloud Key Management Service (Cloud KMS) lets you create, manage, and use cryptographic keys in Google Cloud.  
It is tightly integrated with IAM and Cloud Audit Logs, giving you fine-grained control and full visibility over who can use which keys.

### What you will learn
- Create a Cloud Storage bucket for encrypted data
- Enable Cloud KMS and create a KeyRing + CryptoKey
- Encrypt and decrypt data using the KMS REST API
- Assign IAM roles for key management vs. encryption/decryption
- Bulk-encrypt multiple files and upload them
- View Cloud Audit Logs for KMS activity

### Challenge Lab Relevance
- **High for security & encryption questions.**
- You must know the difference between **KeyRing** and **CryptoKey**.
- You must know the two critical IAM roles: `cloudkms.admin` vs `cloudkms.cryptoKeyEncrypterDecrypter`.
- Understand that client-side encryption is **not** the recommended production pattern for Cloud Storage.

---

## 2. What This Lab Is Actually Testing

| Concept | How the Lab Exercises It |
|---------|--------------------------|
| Key hierarchy | KeyRing → CryptoKey → CryptoKey Version |
| Client-side encryption | Base64 → encrypt API → store ciphertext |
| IAM separation of duties | Admin role vs Encrypter/Decrypter role |
| Inheritance | Permissions on KeyRing apply to all CryptoKeys inside it |
| Auditability | Cloud Audit Logs show who created/used keys |
| Practical bulk encryption | Shell loop over files + upload |

**Key insight the lab builds toward:**  
Cloud KMS gives you **cryptographic control** (who can encrypt/decrypt) separate from **storage control** (who can read the bucket).

---

## 3. Core Concepts

### 3.1 Cloud KMS Hierarchy

```
Project
 └── KeyRing (logical grouping – e.g. "prod", "labkey")
      └── CryptoKey (the actual key – e.g. "qwiklab")
           └── CryptoKey Version (rotated versions of the key)
```

- KeyRings and CryptoKeys **cannot be deleted** (only disabled/destroyed versions).
- Location can be `global` or a specific region (lab uses `global`).

### 3.2 Two Critical IAM Roles

| Role | Permissions | Typical Use |
|------|-------------|-------------|
| `roles/cloudkms.admin` | Create/manage KeyRings & CryptoKeys | Key administrators |
| `roles/cloudkms.cryptoKeyEncrypterDecrypter` | Call encrypt & decrypt APIs | Applications / service accounts that need to use the key |

**Separation of duties** is a best practice: the person who manages keys should not necessarily be able to decrypt data.

### 3.3 Client-Side vs Server-Side Encryption

| Type | Who encrypts? | Recommended for Cloud Storage? |
|------|---------------|--------------------------------|
| **Client-side** (this lab) | Your application / script | Rarely — more work, harder key rotation |
| **Server-side with Google-managed keys** | Cloud Storage | Good default |
| **Server-side with CMEK** (Customer-Managed Encryption Keys) | Cloud Storage using your KMS key | **Best practice** for sensitive data |

> Lab note: The manual encrypt-then-upload pattern is for learning only.  
> Production recommendation: Use Cloud Storage CMEK + automatic key rotation.

### 3.4 Encryption Flow in This Lab

1. Read plaintext file
2. Base64-encode it (`base64 -w0`)
3. Call KMS `:encrypt` endpoint → get `ciphertext`
4. Save ciphertext to `.encrypted` file
5. Upload ciphertext to Cloud Storage
6. To decrypt: call `:decrypt` → base64-decode the result

The ciphertext is **different every time** even with the same plaintext + key (because of the encryption algorithm’s randomness).

---

## 4. Hands-on Walkthrough

### Task 1 – Create a Cloud Storage Bucket

```bash
BUCKET_NAME="${DEVSHELL_PROJECT_ID}-kms_lab"
gcloud storage buckets create gs://${BUCKET_NAME}
```

### Task 2 – Review the Sample Data

```bash
gcloud storage cp gs://${GOOGLE_CLOUD_PROJECT}-kms-lab-data/finance-dept/inbox/1.txt .
tail 1.txt
```

### Task 3 – Enable Cloud KMS

```bash
gcloud services enable cloudkms.googleapis.com
```

### Task 4 – Create KeyRing and CryptoKey

```bash
KEYRING_NAME=labkey
CRYPTOKEY_NAME=qwiklab

gcloud kms keyrings create $KEYRING_NAME --location global

gcloud kms keys create $CRYPTOKEY_NAME \
  --location global \
  --keyring $KEYRING_NAME \
  --purpose encryption
```

**Console path:** Navigation menu → **Security → Key Management**

### Task 5 – Encrypt a Single File

```bash
# Base64 encode
PLAINTEXT=$(cat 1.txt | base64 -w0)

# Encrypt and save ciphertext
curl -s "https://cloudkms.googleapis.com/v1/projects/$DEVSHELL_PROJECT_ID/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:encrypt" \
  -d "{\"plaintext\":\"$PLAINTEXT\"}" \
  -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
| jq .ciphertext -r > 1.encrypted

# Verify decryption works
curl -s "https://cloudkms.googleapis.com/v1/projects/$DEVSHELL_PROJECT_ID/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:decrypt" \
  -d "{\"ciphertext\":\"$(cat 1.encrypted)\"}" \
  -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
  -H "Content-Type: application/json" \
| jq .plaintext -r | base64 -d

# Upload encrypted file
gcloud storage cp 1.encrypted gs://${BUCKET_NAME}
```

### Task 6 – Configure IAM Permissions

```bash
USER_EMAIL=$(gcloud auth list --limit=1 2>/dev/null | grep '@' | awk '{print $2}')

# Grant admin on the KeyRing
gcloud kms keyrings add-iam-policy-binding $KEYRING_NAME \
  --location global \
  --member user:$USER_EMAIL \
  --role roles/cloudkms.admin

# Grant encrypt/decrypt on the KeyRing (inherits to all CryptoKeys)
gcloud kms keyrings add-iam-policy-binding $KEYRING_NAME \
  --location global \
  --member user:$USER_EMAIL \
  --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

**Inheritance note:** Permissions granted on a KeyRing automatically apply to all CryptoKeys inside it.

### Task 7 – Bulk Encrypt and Upload

```bash
# Download all sample files
gcloud storage cp -r gs://${GOOGLE_CLOUD_PROJECT}-kms-lab-data/finance-dept .

# Encrypt everything
MYDIR=finance-dept
FILES=$(find $MYDIR -type f -not -name "*.encrypted")
for file in $FILES; do
  PLAINTEXT=$(cat $file | base64 -w0)
  curl -s "https://cloudkms.googleapis.com/v1/projects/$DEVSHELL_PROJECT_ID/locations/global/keyRings/$KEYRING_NAME/cryptoKeys/$CRYPTOKEY_NAME:encrypt" \
    -d "{\"plaintext\":\"$PLAINTEXT\"}" \
    -H "Authorization:Bearer $(gcloud auth application-default print-access-token)" \
    -H "Content-Type: application/json" \
  | jq .ciphertext -r > $file.encrypted
done

# Upload only the encrypted files
gcloud storage cp finance-dept/inbox/*.encrypted gs://${BUCKET_NAME}/finance-dept/inbox
```

### Task 8 – View Cloud Audit Logs

1. Navigation menu → **Cloud Overview → Activity**
2. Click **View in Log Explorer**
3. Filter Resource Type = **Cloud KMS Key Ring**

You will see create operations and IAM policy changes.

---

## 5. Key Terms You Must Know Cold

| Term | Definition |
|------|------------|
| **KeyRing** | Logical container that groups related CryptoKeys |
| **CryptoKey** | The actual encryption key (contains one or more versions) |
| **CryptoKey Version** | A specific version of a key (supports rotation) |
| **CMEK** | Customer-Managed Encryption Key (your KMS key used by a Google service) |
| **Client-side encryption** | Application encrypts data before sending it to storage |
| **Server-side encryption** | Storage service encrypts data for you |
| **roles/cloudkms.admin** | Can create and manage keys |
| **roles/cloudkms.cryptoKeyEncrypterDecrypter** | Can encrypt and decrypt data |
| **Ciphertext** | The encrypted form of the data |
| **Base64 encoding** | Required to send binary data as JSON plaintext to the KMS API |

---

## 6. Commands & Console Paths Cheat Sheet

```bash
# Enable API
gcloud services enable cloudkms.googleapis.com

# Create KeyRing
gcloud kms keyrings create KEYRING_NAME --location global

# Create CryptoKey
gcloud kms keys create CRYPTOKEY_NAME \
  --location global \
  --keyring KEYRING_NAME \
  --purpose encryption

# Grant roles on KeyRing
gcloud kms keyrings add-iam-policy-binding KEYRING_NAME \
  --location global \
  --member user:EMAIL \
  --role roles/cloudkms.admin   # or cryptoKeyEncrypterDecrypter

# Encrypt (REST)
curl .../cryptoKeys/CRYPTOKEY_NAME:encrypt -d '{"plaintext":"..."}'

# Decrypt (REST)
curl .../cryptoKeys/CRYPTOKEY_NAME:decrypt -d '{"ciphertext":"..."}'
```

**Console paths**
- Key Management → **Security → Key Management**
- Audit Logs → **Cloud Overview → Activity → View in Log Explorer**
- Cloud Storage → **Cloud Storage → Buckets**

---

## 7. Exam & Design Perspective

**Maps to PCA / ACE exam guide:**  
“Designing for security and compliance” → Encryption at rest & key management

### What this lab covers well
- KeyRing / CryptoKey hierarchy
- Separation of duties with two IAM roles
- Basic encrypt / decrypt API usage
- Audit logging for key operations

### What this lab does **not** cover (still needed for exam)
- Key rotation and primary version management
- Automatic key rotation schedules
- Using CMEK with Cloud Storage, BigQuery, Compute Engine, etc.
- External Key Manager (EKM) / Cloud HSM
- Envelope encryption pattern
- Asymmetric keys (signing)

**Production best practice reminder:**  
Prefer **Cloud Storage CMEK** over the manual client-side encrypt-then-upload pattern shown in this lab.

---

## 8. Quick Revision Summary

1. Hierarchy: **KeyRing → CryptoKey → CryptoKey Version**
2. Two main roles:  
   - `cloudkms.admin` → manage keys  
   - `cloudkms.cryptoKeyEncrypterDecrypter` → use keys
3. Permissions on a KeyRing inherit to all CryptoKeys inside it.
4. Always base64-encode plaintext before calling the encrypt API.
5. Ciphertext changes every time (even with same key + plaintext).
6. Client-side encryption is for learning; production prefers **CMEK**.
7. Cloud Audit Logs record who created and who used the keys.



*This document combines the official lab content with deeper conceptual notes, security caveats, and exam-oriented analysis for effective learning and revision.*
