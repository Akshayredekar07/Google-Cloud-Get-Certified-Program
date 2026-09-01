# GSP313 — Implement Load Balancing on Compute Engine: Challenge Lab

**Duration:** 25 minutes | **Level:** Introductory | **Cost:** No cost | **Type:** Challenge Lab (no step-by-step instructions — skills from prior labs applied independently, scored automatically)

---

## Overview

A **challenge lab** gives a scenario + tasks with **no step-by-step guidance**. You must apply skills from prior labs, read/debug your own error messages, and hit 100% before the timer runs out. No new concepts are taught here.

## Scenario

You're a junior cloud engineer on a team providing network functionality to Compute Engine VM instances on a **VPC network**. Every project starts with a **default VPC network** (required since VMs/containers/App Engine can't exist without one). You need to understand the difference between a **Network Load Balancer** (L4, regional, TCP/UDP-based via target pools) and an **HTTP Load Balancer** (L7, global, HTTP-based via backend services + URL maps) and configure both.

## Objectives (Your Challenge)

1. Create multiple web server instances with firewall rules.
2. Configure a (network) load balancing service.
3. Create an HTTP load balancer.

**Region/Zone standard:** All resources in **`europe-west3`** region, **`europe-west3-b`** zone, unless told otherwise.

---

## Setup and Requirements

- Use an **Incognito/private browser window** — avoids account conflicts and unwanted billing.
- Labs are **timed and cannot be paused**.
- Use **only the provided student account**, never your personal Google Cloud account.

---

## Task 1: Create Multiple Web Server Instances

**Requirement:** 3 VM instances (`web1`, `web2`, `web3`), region `europe-west3`, zone `europe-west3-b`, series **E2**, machine type **`e2-small`**, tag `network-lb-tag`, image family `debian-12`, image project `debian-cloud`. Each runs a startup script installing Apache and serving a page identifying itself. Then create firewall rule **`www-firewall-network-lb`** allowing HTTP (port 80) traffic to reach tagged instances.

### Startup Script (per-instance, `web-number` = web1/web2/web3)
```bash
#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: web-number</h3>" | tee /var/www/html/index.html
```
**Explanation:**
- `apt-get update` — refreshes the package index so the next install pulls the latest available version metadata.
- `apt-get install apache2 -y` — installs the Apache2 web server; `-y` auto-confirms the prompt.
- `service apache2 restart` — (re)starts the Apache service so it's running and picks up any config/content changes.
- `echo "..." | tee /var/www/html/index.html` — writes an HTML snippet identifying the specific server (`web1`/`web2`/`web3`) as Apache's default served page (`/var/www/html/index.html`), so each instance is visibly distinguishable when hit via `curl`/browser. `tee` writes to the file **and** echoes to stdout (useful for startup-script logging).

### Actual Commands Used (from your Cloud Shell session)

**Create instance `web3`** (same pattern repeated for `web1`, `web2` with the metadata `Web Server: web1`/`web2` swapped in):
```bash
gcloud compute instances create web3 \
  --zone=europe-west3-b \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Web Server: web3</h3>" | tee /var/www/html/index.html'
```
**Explanation:**
- `gcloud compute instances create web3` — creates a new Compute Engine VM named `web3`.
- `--zone=europe-west3-b` — places the VM in the required zone.
- `--machine-type=e2-small` — sets the E2-series machine shape.
- `--tags=network-lb-tag` — attaches a **network tag**, which the firewall rule below targets to selectively allow traffic only to tagged instances (not every VM in the project).
- `--image-family=debian-12` / `--image-project=debian-cloud` — selects the OS image: latest Debian 12 image from Google's public `debian-cloud` image project.
- `--metadata startup-script='...'` — embeds a **startup script** that GCE automatically runs on first boot (and every subsequent boot) to provision Apache and the identifying HTML page — no manual SSH/setup required.

**Output confirms:**
```
NAME: web3
ZONE: europe-west3-b
MACHINE_TYPE: e2-small
INTERNAL_IP: 10.156.0.4
EXTERNAL_IP: 34.179.228.60
STATUS: RUNNING
```

**Create the firewall rule:**
```bash
gcloud compute firewall-rules create www-firewall-network-lb \
  --allow=tcp:80 \
  --target-tags=network-lb-tag
```
**Explanation:**
- `firewall-rules create www-firewall-network-lb` — names the new ingress rule.
- `--allow=tcp:80` — permits inbound TCP traffic on port 80 (HTTP) only.
- `--target-tags=network-lb-tag` — scopes the rule to **only** apply to instances carrying the `network-lb-tag` network tag (i.e., `web1`/`web2`/`web3`), rather than opening port 80 project-wide.
- No `--source-ranges` specified → defaults to `0.0.0.0/0` (all sources), i.e., open to the internet on port 80.

Output confirms: `NETWORK: default`, `DIRECTION: INGRESS`, `ALLOW: tcp:80`.

**Verify each instance serves its page:**
```bash
curl http://34.179.228.60   # → <h3>Web Server: web3</h3>
curl http://35.198.162.128  # → <h3>Web Server: web2</h3>
curl http://34.107.116.100  # → <h3>Web Server: web1</h3>
```
**Explanation:** `curl` sends a plain HTTP GET to each VM's **external IP** and prints the raw response body — confirms Apache is running and each instance's startup script correctly wrote its own identifying content. (Lab note: if this fails, try resetting the VM — startup script may not have finished running yet.)

> ✅ **Check my progress**: *Create multiple web server instances* — passed.

---

## Task 2: Configure the Load Balancing Service (Network Load Balancer)

**Requirement:** Static external IP `network-lb-ip-1`, target pool `www-pool`, port 80. This builds a **Layer-4 Network Load Balancer** using a **target pool** + **forwarding rule** — traffic is distributed at the TCP/IP level across the pool's member instances based on a simple hashing algorithm (not HTTP-aware).

### Reserve a static regional external IP
```bash
gcloud compute addresses create network-lb-ip-1 --region=$REGION
```
**Explanation:** Reserves a **static** (i.e., permanent, non-ephemeral) external IPv4 address named `network-lb-ip-1` in the given region (`europe-west3`), so the load balancer's public IP doesn't change even if the underlying forwarding rule is recreated.

### Create an HTTP health check (legacy, used by target pools)
```bash
gcloud compute http-health-checks create basic-check
```
**Explanation:** Creates a **legacy HTTP health check** named `basic-check` with defaults (`PORT: 80`, `REQUEST_PATH: /`). Network Load Balancers (target-pool based) use the older `http-health-checks` API, distinct from the newer generic `health-checks` API used by HTTP(S) Load Balancers (see Task 3).

### Create the target pool
```bash
gcloud compute target-pools create www-pool \
    --region=$REGION \
    --http-health-check=basic-check
```
**Explanation:**
- `target-pools create www-pool` — a **target pool** is a group of instances that receive traffic from a network load balancer's forwarding rule.
- `--region=$REGION` — target pools are **regional** resources.
- `--http-health-check=basic-check` — attaches the health check so unhealthy instances are automatically removed from serving traffic.

### Add instances to the pool
```bash
gcloud compute target-pools add-instances www-pool \
    --instances=web1,web2,web3 \
    --instances-zone=$ZONE \
    --region=$REGION
```
**Explanation:** Registers `web1`, `web2`, `web3` as members of `www-pool` — these are the instances that will actually receive distributed traffic.

### Create the forwarding rule
```bash
gcloud compute forwarding-rules create www-rule \
    --region=$REGION \
    --ports=80 \
    --address=network-lb-ip-1 \
    --target-pool=www-pool
```
**Explanation:**
- `forwarding-rules create www-rule` — creates the actual **entry point** that receives external traffic.
- `--ports=80` — only forwards traffic destined for port 80.
- `--address=network-lb-ip-1` — binds the rule to the static IP reserved earlier (this becomes the load balancer's public-facing IP).
- `--target-pool=www-pool` — directs matched traffic to be load-balanced across the pool's instance members.

> ✅ **Check my progress**: *Configure the load balancing service* — passed.
> After this, hitting `network-lb-ip-1` repeatedly and refreshing should show responses **alternating** between `web1`/`web2`/`web3`.

---

## Task 3: Create an HTTP Load Balancer

**Requirement:** A full **Layer-7 (application-aware) HTTP Load Balancer** using a **Managed Instance Group (MIG)** as the backend, global external IP, backend service, URL map, and target HTTP proxy.

**Values required:**
| Property | Value |
|---|---|
| Backend Template | `lb-backend-template` |
| Tags | `allow-health-check` |
| Managed instance group | `lb-backend-group` |
| Machine type | `e2-medium` |
| Image family/project | same as web1–3 (`debian-12` / `debian-cloud`) |
| Firewall rule | `fw-allow-health-check` |
| Allow source ranges | `130.211.0.0/22, 35.191.0.0/16` (Google's health-check probe IP ranges) |
| Traffic direction | ingress |
| Port | 80 |
| External IP | `lb-ipv4-1` |
| Health check | `http-basic-check` |
| URL map | `web-map-http` |
| Target HTTP proxy | `http-lb-proxy` |

### Firewall rule for health-check probes
```bash
gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80
```
**Explanation:**
- `--source-ranges=130.211.0.0/22,35.191.0.0/16` — these are Google Cloud's **reserved IP ranges specifically used by the health-checking system** to probe backend instances. Without this rule, Google's health checkers can't reach your instances, and the backend service will mark them **unhealthy** even though they're actually fine.
- `--target-tags=allow-health-check` — scopes the rule only to instances tagged `allow-health-check` (the MIG's instances), not the network-LB instances from Task 1/2.
- `--rules=tcp:80` — same as `--allow=tcp:80`, newer flag syntax.

> ⚠️ **Error hit in your session:** `The resource '.../firewalls/fw-allow-health-check' already exists` — happened because the command was re-run after it had already succeeded earlier. **Fix:** this is safe to ignore/skip if the rule already exists; just move on.

### Instance template for the backend
```bash
gcloud compute instance-templates create lb-backend-template \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --tags=allow-health-check \
  --network=default \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
a2ensite default-ssl
a2enmod ssl
vm_hostname="$(curl -H "Metadata-Flavor:Google" http://169.254.169.254/computeMetadata/v1/instance/name)"
echo "Page served from: $vm_hostname" | tee /var/www/html/index.html
systemctl restart apache2'
```
**Explanation:**
- `instance-templates create` — defines a **reusable blueprint** (machine type, image, tags, startup script) that a Managed Instance Group uses to spin up identical instances on demand — you don't hand-create each backend VM.
- `a2ensite default-ssl` / `a2enmod ssl` — enables Apache's default SSL site config and the `ssl` module (prepares HTTPS capability on the instance, even though this lab's LB is HTTP-only).
- `vm_hostname="$(curl -H "Metadata-Flavor:Google" http://169.254.169.254/computeMetadata/v1/instance/name)"` — queries the GCE **instance metadata server** (a special internal-only IP `169.254.169.254`) to fetch the instance's **own auto-generated name** (e.g., `lb-backend-group-xxxx`) at boot time. The `Metadata-Flavor:Google` header is **required** by the metadata server to permit the request (a security/anti-SSRF check).
- `echo "Page served from: $vm_hostname" | tee /var/www/html/index.html` — writes a page showing exactly which backend instance served the request — this is how you visually confirm load balancing is working across the MIG.
- **No `--tags` conflict this time** since `--network=default` was explicit (see error analysis below on why the first attempt failed).

> ⚠️ **Errors hit in your session (this was the main debugging challenge):**
>
> 1. **First attempt** used `--network=default --subnet=default` together, and got:
>    ```
>    Did you mean region [asia-southeast1] for subnetwork: [default] (Y/n)?
>    ```
>    then later:
>    ```
>    Invalid value for field 'instance.networkInterfaces[0]': Scope of the specified subnetwork doesn't match the scope of the instance
>    ```
>    **Root cause:** explicitly specifying `--subnet=default` without a matching `--region` caused `gcloud` to resolve the subnet to the **wrong region** (it guessed `asia-southeast1` instead of `europe-west3`), because on an **auto-mode VPC**, the `default` subnet name exists in *every* region — omitting an explicit, correctly-scoped region reference caused ambiguity.
>    **Fix that worked:** drop `--subnet=default` entirely and only pass `--network=default` (letting `gcloud` auto-resolve the correct regional subnet from the MIG's `--zone` at instance-group creation time), i.e. the final working template creation omits `--subnet`.
>
> 2. **`already exists` errors** for `lb-backend-template`, `fw-allow-health-check`, `lb-ipv4-1`, `web-backend-service`, `http-lb-proxy` — occurred because earlier failed attempts had actually partially succeeded in creating some resources before a later step failed, so re-running the full command block re-triggered "already exists" on those. **Fix:** delete-and-recreate the specific broken resource (see below) rather than the whole chain, or simply skip already-created resources and continue to the next step.
>
> 3. **Deleted and recreated the template** to guarantee a clean state:
>    ```bash
>    gcloud compute instance-templates delete lb-backend-template --quiet
>    ```
>    **Explanation:** `--quiet` suppresses the interactive "are you sure?" confirmation prompt, needed for non-interactive/scripted deletion. After deleting, the template was recreated (successfully, this time) **without** the problematic `--subnet` flag.

### Managed Instance Group (MIG)
```bash
gcloud compute instance-groups managed create lb-backend-group \
  --template=lb-backend-template \
  --size=2 \
  --zone=$ZONE
```
**Explanation:**
- `instance-groups managed create lb-backend-group` — creates a **zonal Managed Instance Group**, which automatically creates and maintains a target number of VM instances from the given template — self-healing (recreates failed instances) and integrates natively as an HTTP(S) load balancer backend.
- `--template=lb-backend-template` — the blueprint used to create each instance.
- `--size=2` — maintains exactly 2 running instances.
- `--zone=$ZONE` — zonal (not regional) MIG, in `europe-west3-b`.

> ⚠️ Note the intermediate failed attempt used `--template=regions/$REGION/instanceTemplates/lb-backend-template`, which errored with `The URL is malformed` — **instance templates are global resources**, not regional; referencing them with a `regions/...` path prefix is invalid. The fix was to pass just the template **name** (`lb-backend-template`), letting `gcloud` resolve it as a global resource automatically.

### Global external IP for the HTTP LB
```bash
gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global
```
**Explanation:** Reserves a **global** static external IPv4 address (as opposed to the **regional** address used for the network LB in Task 2) — HTTP(S) Load Balancers are **global** resources by design (anycast, can route to the nearest healthy backend across regions), so their front-end IP must also be global.

### Modern health check (for the backend service)
```bash
gcloud compute health-checks create http http-basic-check \
  --port 80
```
**Explanation:** Creates a health check using the **newer, generic `health-checks` API** (distinct from the legacy `http-health-checks` used in Task 2) — required by backend services for HTTP(S) Load Balancers. `--port 80` — probes port 80 specifically.

### Backend service
```bash
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global
```
**Explanation:**
- `backend-services create` — a **backend service** is the L7 LB construct that defines how traffic is distributed to one or more backends (here, the MIG), including protocol, health checking, and load-balancing policy.
- `--protocol=HTTP` — backend traffic is plain HTTP.
- `--port-name=http` — references the **named port** `http` (defined on the instance group, defaults to port 80) rather than a raw port number.
- `--health-checks=http-basic-check` — attaches the health check so unhealthy backend instances are automatically excluded from serving traffic.
- `--global` — backend services for HTTP(S) LBs are **global** resources.

### Attach the MIG as a backend
```bash
gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global
```
**Explanation:** Registers `lb-backend-group` (the MIG) as an actual **backend** of `web-backend-service` — this is the step that connects "what should serve traffic" (the MIG) to "how traffic should be distributed to it" (the backend service).

> ⚠️ **Error hit:** `The resource '.../instanceGroups/lb-backend-group' was not found` — occurred because this command was attempted **before** the MIG had actually been successfully created (due to the earlier template/subnet errors blocking MIG creation). **Fix:** resolve the MIG creation error first (see above), confirm with `gcloud compute instance-groups managed list`, **then** retry `add-backend` — which succeeded on retry.

### URL map
```bash
gcloud compute url-maps create web-map-http \
  --default-service web-backend-service
```
**Explanation:** A **URL map** defines HTTP(S) LB routing rules (which backend service handles which URL path/host). `--default-service` sets the fallback/default backend for any request not matched by more specific rules — since this lab has no path-based routing, all traffic simply goes to `web-backend-service`.

### Target HTTP proxy
```bash
gcloud compute target-http-proxies create http-lb-proxy \
  --url-map=web-map-http
```
**Explanation:** A **target HTTP proxy** is the component that actually terminates incoming HTTP connections and consults the attached URL map to decide where to route each request. This is the piece a forwarding rule ultimately points to.

### Global forwarding rule (the LB's public entry point)
```bash
gcloud compute forwarding-rules create http-content-rule \
  --address=lb-ipv4-1 \
  --global \
  --target-http-proxy=http-lb-proxy \
  --ports=80
```
**Explanation:**
- `forwarding-rules create http-content-rule` — creates the **global forwarding rule**, the actual public-facing frontend of the entire HTTP LB stack.
- `--address=lb-ipv4-1` — binds it to the reserved global static IP.
- `--global` — matches the global scope of all the other L7 LB components (target proxy, URL map, backend service).
- `--target-http-proxy=http-lb-proxy` — routes matched traffic to the proxy, which then consults the URL map → backend service → MIG.
- `--ports=80` — listens for HTTP traffic on port 80.

> ✅ **Check my progress**: *Create an HTTP load balancer* — passed.

---

## Test Traffic Sent to the Instances

1. **Console → Navigation menu → Network services → Load balancing.**
2. Click the load balancer just created (**`web-map-http`**).
3. Open a browser to `http://[IP_ADDRESS]/`, replacing `[IP_ADDRESS]` with the LB's IP (i.e., `lb-ipv4-1`'s address).
   - **Note:** May take **3–5 minutes** to become reachable (global LB propagation + MIG instances finishing boot + passing health checks). If it doesn't connect immediately, wait and reload.
4. Expected result: a page showing **`Page served from: lb-backend-group-xxxx`**, confirming traffic reached one of the MIG's backend instances via the full HTTP LB chain.

---

## Summary Table — Network LB vs. HTTP LB (Key Exam Distinction)

| Aspect | Network Load Balancer (Task 2) | HTTP Load Balancer (Task 3) |
|---|---|---|
| OSI Layer | L4 (TCP/UDP) | L7 (HTTP/HTTPS) |
| Scope | **Regional** | **Global** |
| Backend construct | Target pool | Backend service + Managed Instance Group |
| Health check API | Legacy `http-health-checks` | Modern `health-checks` |
| IP address type | Regional static IP | Global static IP |
| Entry point | Forwarding rule → target pool | Forwarding rule → target proxy → URL map → backend service → MIG |
| Routing intelligence | None (IP/port hash) | Path/host-based routing possible via URL map |
| Firewall for probes | Not required for `www-firewall-network-lb` (opened broadly) | **Required**: `130.211.0.0/22, 35.191.0.0/16` for Google's health-check probers |

---

## Key Errors Encountered & Fixes (Exam-Relevant Debugging Patterns)

| Error | Cause | Fix |
|---|---|---|
| `Scope of the specified subnetwork doesn't match the scope of the instance` | Passed `--subnet=default` without a properly scoped region, causing `gcloud` to auto-resolve the wrong region's `default` subnet on an auto-mode VPC | Omit `--subnet` flag; let `gcloud` resolve region/subnet automatically from `--zone` |
| `The URL is malformed` on MIG create | Referenced instance template with an invalid `regions/.../instanceTemplates/...` path | Instance templates are **global** — pass just the template name |
| `resource '...' already exists` | Re-running a command block after a partial earlier success | Skip already-created resources, or delete (`--quiet`) and recreate the specific broken one |
| `instanceGroups/lb-backend-group was not found` (on `add-backend`) | Tried to attach a MIG as a backend before the MIG creation had actually succeeded | Fix the upstream MIG-creation error first, verify with `instance-groups managed list`, then retry |

---

## Reference

**Lab ID:** GSP313 | **Final Score:** 100/100