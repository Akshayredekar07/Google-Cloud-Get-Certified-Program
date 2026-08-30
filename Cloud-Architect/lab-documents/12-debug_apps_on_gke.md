# GSP736 — Debug Apps on Google Kubernetes Engine

**Duration:** 20 minutes (self-paced) | **Level:** Intermediate | **Cost:** No cost

---

## Overview

Cloud Logging and Cloud Monitoring are deeply integrated into Google Kubernetes Engine (GKE). This lab teaches how these two products work together with GKE clusters and applications, using a real microservices demo app to demonstrate a full troubleshooting workflow:

- Generate traffic against the app using a load generator.
- Detect an issue via **Cloud Monitoring** (alert/metric).
- Root-cause the issue using **Cloud Logging**.
- Fix the bug and confirm the fix using both Logging and Monitoring.

## Objectives

- Use **Cloud Monitoring** to detect issues.
- Use **Cloud Logging** to troubleshoot an application running on GKE.

## Demo Application

A sample **microservices demo app** ("Hipster Shop" / Online Boutique) with multiple interdependent services is deployed to a GKE cluster. Traffic is generated with a **loadgenerator (Locust)**, an error is surfaced via alerting/metrics, the root cause is found via Logging, and the fix is verified.

---

## Setup and Requirements

- Use an **Incognito/private browser window** to avoid account conflicts and unintended billing on your personal account.
- Labs are **timed and cannot be paused** — once started, the clock runs continuously.
- Use **only the provided student account** (`student-04-xxxx@qwiklabs.net`), never your personal Google Cloud account.

### Steps to Start

1. Click **Start Lab** (pay if required).
2. Click **Open Google Cloud console** (or right-click → *Open Link in Incognito Window* in Chrome).
3. If prompted, click **Use Another Account**.
4. Enter the provided **Username**, click **Next**.
5. Enter the provided **Password**, click **Next**.
6. Accept terms & conditions. **Do not** add recovery options, 2FA, or sign up for free trials.
7. The Google Cloud Console opens, authenticated as the lab's temporary account.

---

## Activate Cloud Shell

**Cloud Shell** is a browser-based virtual machine preloaded with development tools, giving you:
- A **persistent 5 GB home directory**.
- Pre-installed `gcloud` CLI with tab-completion.
- Command-line access to your Google Cloud resources without local setup.

### Steps

1. Click the **Activate Cloud Shell** icon at the top of the console.
2. Click through the info window, then **Authorize** Cloud Shell to use your credentials for API calls.
3. Once connected, Cloud Shell is already authenticated and scoped to your `Project_ID`.

### Useful Commands

```bash
gcloud auth list
```
**Explanation:** Lists all Google accounts currently authenticated in this Cloud Shell session and shows which one is `ACTIVE` (marked with `*`). Useful to confirm you're operating as the correct lab identity, not your personal account.

```bash
gcloud config list project
```
**Explanation:** Prints the current `gcloud` CLI configuration, specifically the active `project` value. Confirms that all subsequent commands target the correct lab project (`qwiklabs-gcp-...`).

---

## Task 1: Perform Infrastructure Setup

**Goal:** Connect to a pre-provisioned GKE cluster and confirm it is ready.

```bash
gcloud container clusters list
```
**Explanation:** Lists all GKE clusters in the current project along with their `STATUS` (e.g., `PROVISIONING`, `RUNNING`), location, node count, and version. Run repeatedly until status becomes `RUNNING` — cluster creation can take several minutes.

> Verify the cluster name is **`central`**. You can also track progress via **Navigation menu → Kubernetes Engine → Clusters**.

```bash
gcloud container clusters get-credentials central --zone ZONE
```
**Explanation:** Fetches the cluster's authentication data and endpoint, then writes/updates a `kubeconfig` entry so that `kubectl` commands are automatically routed to the `central` cluster. Replace `ZONE` with the actual zone shown in the console (e.g., `us-central1-a`). Without this step, `kubectl` has no cluster context to talk to.

```bash
kubectl get nodes
```
**Explanation:** Queries the Kubernetes API server for all worker nodes in the cluster and their status (`Ready`/`NotReady`), roles, age, and Kubernetes version. Confirms the cluster's compute layer is healthy and ready to schedule pods.

---

## Task 2: Deploy an Application

**Goal:** Deploy the "Hipster Shop" microservices demo app to generate a real workload to monitor.

```bash
git clone https://github.com/xiangshen-dk/microservices-demo.git
```
**Explanation:** Clones the demo application's source repository (Kubernetes manifests + microservice source code) into Cloud Shell's persistent home directory.

```bash
cd microservices-demo
```
**Explanation:** Changes the working directory into the cloned repo so subsequent commands reference files relative to the project root.

```bash
kubectl apply -f release/kubernetes-manifests.yaml
```
**Explanation:** Applies a single YAML manifest file containing **all Kubernetes objects** (Deployments, Services, etc.) needed to run the app — this declaratively creates/updates every microservice's pods and services in one command.

```bash
kubectl get pods
```
**Explanation:** Lists all pods in the current namespace with `READY`, `STATUS`, `RESTARTS`, and `AGE` columns. Re-run until **every** pod shows `1/1 Running` — this confirms the full application stack (adservice, cartservice, checkoutservice, currencyservice, emailservice, frontend, loadgenerator, paymentservice, productcatalogservice, recommendationservice, redis-cart, shippingservice) is healthy.

> ✅ Click **Check my progress** to verify: *Deploy an application*.

```bash
export EXTERNAL_IP=$(kubectl get service frontend-external | awk 'BEGIN { cnt=0; } { cnt+=1; if (cnt > 1) print $4; }')
```
**Explanation:** Runs `kubectl get service frontend-external` to fetch the frontend's `Service` object details, then pipes the output to `awk`, which skips the header row (`cnt > 1`) and extracts the **4th column** (`EXTERNAL-IP`). The result is stored in the shell variable `EXTERNAL_IP` for reuse. May need to be repeated until the LoadBalancer finishes provisioning an external IP.

```bash
echo $EXTERNAL_IP
```
**Explanation:** Prints the stored external IP address to confirm it was captured correctly (not blank or `<pending>`).

```bash
curl -o /dev/null -s -w "%{http_code}\n" http://$EXTERNAL_IP
```
**Explanation:** Sends an HTTP request to the frontend's external IP and prints **only the HTTP status code** (discarding the response body via `-o /dev/null`, running silently via `-s`, and formatting output via `-w`). An output of `200` confirms the web app is reachable and serving successfully.

### Console Verification

- **Kubernetes Engine → Workloads:** confirms all pods show `OK`.
- **Gateways, Services & Ingress → Services tab:** confirms all services show `OK`.

---

## Task 3: Open the Application

1. Scroll to **frontend-external** in the Services tab.
2. Click its **Endpoints IP** to open the storefront in a browser — displays product tiles for the "Online Boutique."

---

## Task 4: Create a Logs-Based Metric

**Concept:** A **logs-based metric** is a custom Cloud Monitoring metric derived from log entries matching a filter. Useful for **counting occurrences** (e.g., error count) or **tracking value distributions** from logs. Once created, it can feed dashboards and alerting policies — exactly what's needed to detect the frontend's error rate.

### Steps

1. Search **"logging"** in the console search bar → open **Logs Explorer**.
2. Enable **Show query**, and enter this filter in the Query builder:
   ```
   resource.type="k8s_container"
   severity=ERROR
   labels."k8s-pod/app": "recommendationservice"
   ```
   **Explanation of filter fields:**
   - `resource.type="k8s_container"` — restricts results to logs emitted by containers running inside GKE.
   - `severity=ERROR` — only includes log entries logged at `ERROR` level or higher.
   - `labels."k8s-pod/app": "recommendationservice"` — filters to logs from pods labeled `app=recommendationservice`.
3. Click **Run Query.** At this point, expect **no results** — no errors have occurred yet since there's no traffic.
4. Click **Actions → Create Metric**.
5. Name the metric **`Error_Rate_SLI`**, then click **Create Metric**.

> The metric now appears under **User-defined Metrics** on the **Logs-based Metrics** page — it will start counting matching log entries as they occur.

> ✅ Click **Check my progress**: *Create a logs-based metric*.

---

## Task 5: Create an Alerting Policy

**Concept:** Alerting policies let Cloud Monitoring **proactively notify/flag** when a metric crosses a defined threshold, creating an **incident** automatically — this is how you'd be alerted to production issues without manually watching dashboards.

### Steps

1. **Navigation menu → Monitoring → Alerting.**
2. Click **Create Policy**. (If prompted, click **Try It!** for the updated flow.)
3. Click **Select a metric**, deselect **Active**.
4. In **Filter by resource and metric name**, type `Error_Rate`.
5. Select **Kubernetes Container → Logs-Based Metric → `logging/user/Error_Rate_SLI`**, click **Apply**.
6. Set **Rolling windows function** to **Rate** — this converts the raw log count into a **rate of errors over time**, which is a more meaningful SLI (Service Level Indicator) than a raw count.
7. Click **Next.**
8. Set **Threshold value** to **0.5**.
   - At this point there's no traffic yet, so the condition isn't met — the app is meeting its availability SLO (Service Level Objective).
9. Click **Next** again.
10. **Disable** "Use notification channel" (skipped for lab purposes; in production you'd wire this to email/SMS/Pub/Sub/webhooks/mobile app).
11. Name the alert **"Error Rate SLI"**, click **Next**.
12. Review, then click **Create Policy**.

> ✅ Click **Check my progress**: *Create an alerting policy*.

---

## Trigger an Application Error

**Goal:** Use a load generator to create enough traffic to trigger a latent bug intentionally built into this lab version of the app.

### Steps

1. **Navigation menu → Kubernetes Engine → Gateways, Services & Ingress → Services tab.**
2. Find **loadgenerator-external**, click its **endpoint link** (or manually browse to `http://[loadgenerator-external-ip]`).
3. This opens the **Locust** load-testing UI.
   - **Locust** is an open-source load generator that simulates many concurrent users hitting a target web app.
4. Configure the swarm:
   - **Number of users:** `300`
   - **Hatch rate:** `30` (Locust ramps up 30 new simulated users per second until it reaches 300)
   - **Host:** the `frontend-external` URL (**excluding the port**)
5. Click **Start swarming.**
6. Click the **Failures** tab — observe a growing number of **HTTP 500 errors**.
7. Manually clicking a product on the storefront also becomes **slow or fails with a 500 error**, confirming the issue is user-visible.

---

## Confirm the Alert and Application Errors

### Steps

1. **Navigation menu → Monitoring → Alerting** — an **incident** for `logging/user/Error_Rate_SLI` should appear (may take up to ~5 minutes; refresh if needed).
2. Click the **incident link** to view details.
3. From the incident page, click **Logs Explorer** (or **View logs**) in the left pane.
4. Filter further by clicking the **Error label**, or manually add `severity=ERROR` to the query builder and click **Add**, then **Run Query.**
   - Result: all errors specifically for the `recommendationservice` pod.
5. **Expand** an error log entry → expand `textPayload` → click the message → **Add field to summary line**.
   - This surfaces the actual error text as a column in the log table for quick scanning.
6. Errors indicate `RecommendationService` **failed to connect to downstream services** to fetch products/recommendations — root cause still unclear at this point.
7. Referencing the architecture diagram: both **Frontend** and **RecommendationService** call **ProductCatalogService**, making it the prime suspect for the underlying failure.

---

## Troubleshoot Using the Kubernetes Dashboard & Logs

### Steps

1. **Navigation menu → Monitoring → Dashboards → GKE**, then view **Workloads.**
2. **Navigation menu → Kubernetes Engine → Workloads → productcatalogservice.**
   - Observe: the pod is **repeatedly crashing and restarting** (`CrashLoopBackOff` pattern).
3. Two ways to reach container logs:
   - Click the **Logs tab** on the Deployment details page for a quick view, then click the **external link icon** to open full Logs Explorer.
   - Or click **Container logs** link directly on the Overview tab.
4. In Logs Explorer, the log histogram + messages show the container **repeatedly parsing the product catalog** in a short time window — clearly inefficient.
5. Near the bottom of results, look for a runtime panic:
   ```
   panic: runtime error: invalid memory address or nil pointer dereference
   [signal SIGSEGV: segmentation violation
   ```
   This is likely the **direct cause of the pod crash**.

### Locate the Source of the Bug

```bash
grep -nri 'successfully parsed product catalog json' src
```
**Explanation:**
- `grep` searches file contents for a matching string.
- `-n` prints the **line number** of each match.
- `-r` searches **recursively** through the `src` directory.
- `-i` makes the search **case-insensitive**.
- Result: pinpoints the exact source file (`src/productcatalogservice/server.go`) and line number (`237`) that logs this message — enabling direct code inspection.

Output:
```
src/productcatalogservice/server.go:237:        log.Info("successfully parsed product catalog json")
```

6. Open the **Cloud Shell Editor** (Open Editor button → Open in New Window if cookies block it).
7. Navigate to `microservices-demo/src/productcatalogservice/server.go`, line 237 — this is inside the `readCatalogFile` method.
8. Discover: if the boolean `reloadCatalog` is `true`, the service **re-parses the entire catalog file on every single request** — a major, unnecessary overhead under load.
9. Search for `reloadCatalog` in the code → find it is controlled by the environment variable **`ENABLE_RELOAD`**, which also logs its enabled/disabled state.

### Confirm Catalog Reloading Is Enabled

In Logs Explorer, add to the existing query:
```
jsonPayload.message:"catalog reloading"
```
**Explanation:** The `:` operator performs a **substring/contains match** on the `jsonPayload.message` field — finds any log message containing the phrase "catalog reloading," regardless of exact wording.

Full query:
```
resource.type="k8s_container"
resource.labels.location="ZONE"
resource.labels.cluster_name="central"
resource.labels.namespace_name="default"
labels.k8s-pod/app="productcatalogservice"
jsonPayload.message:"catalog reloading"
```

Click **Run Query** → find an **"Enable catalog reloading"** log entry, **confirming** the feature is active.

**Root cause identified:** Under load, `productcatalogservice` re-parses the entire catalog file on **every** request (due to `ENABLE_RELOAD=1`), causing excessive CPU/memory overhead, crashes, and cascading 500 errors in dependent services (`frontend`, `recommendationservice`).

---

## Task 6: Fix the Issue and Verify the Result

**Fix strategy:** Remove the `ENABLE_RELOAD` environment variable from the `productcatalogservice` deployment manifest, then redeploy.

### Steps

Return to the **Cloud Shell terminal** (click **Open Terminal** if closed).

```bash
grep -A1 -ni ENABLE_RELOAD release/kubernetes-manifests.yaml
```
**Explanation:**
- `-A1` prints **1 line of context after** each match (so you see both the `name:` and `value:` lines of the env var).
- `-n` shows line numbers, `-i` is case-insensitive.
- Purpose: locate the exact line numbers of the `ENABLE_RELOAD` environment variable block in the manifest so they can be precisely removed.

Output:
```
373:        - name: ENABLE_RELOAD
374-          value: "1"
```

```bash
sed -i -e '373,374d' release/kubernetes-manifests.yaml
```
**Explanation:**
- `sed` is the stream editor for text transformation.
- `-i` edits the file **in place** (overwrites it directly).
- `-e '373,374d'` specifies an edit script: **delete (`d`) lines 373 through 374** — removing the `ENABLE_RELOAD` variable entirely from the manifest.

```bash
kubectl apply -f release/kubernetes-manifests.yaml
```
**Explanation:** Re-applies the modified manifest. Kubernetes performs a **diff** against the live cluster state and updates only what changed — in this case, only `productcatalogservice`'s pod spec (env vars) is modified/rolled out; all other services remain untouched.

### Verify the Fix

1. **Navigation menu → Kubernetes Engine → Workloads → productcatalogservice** — wait 2–3 minutes and confirm the pod **stops crashing/restarting**.
2. Re-open **Container logs** — confirm the repeated *"successfully parsing the catalog json"* messages are **gone**.
3. Revisit the storefront URL, click products — pages load **fast**, with **no HTTP errors**.
4. Return to the **Locust** load generator UI, click **Reset Stats** — failure percentage resets and should **stay at 0%** as traffic continues.

> If a 500 error still appears momentarily, wait a couple more minutes (rollout propagation) and retry.

---

## Summary / Key Takeaways

| Step | Tool Used | Purpose |
|---|---|---|
| Detect issue | Cloud Monitoring (Alerting + logs-based metric) | Get proactively notified of rising error rate |
| Narrow down service | Cloud Logging (Logs Explorer, filters) | Identify which pod/service is failing |
| Root-cause | Logs Explorer + Cloud Shell Editor + `grep` | Trace error back to exact source-code line and env-var trigger |
| Fix | `sed` + `kubectl apply` | Patch the manifest and redeploy only the affected service |
| Confirm fix | Container logs + Monitoring + Locust reset | Validate error is gone and app is stable under load |

**Core workflow pattern for GKE production troubleshooting:**
`Alert fires → Logs Explorer to pinpoint failing service → correlate w/ architecture diagram → inspect GKE Workloads/dashboard metrics → drill into source code via log messages → patch config → redeploy → verify via logs + monitoring + live traffic.`

### Root Cause (One-liner for exam recall)
`ENABLE_RELOAD=1` env var on `productcatalogservice` forced the catalog JSON file to be **re-parsed on every single request**, which under load (300 simulated users) caused a **nil pointer dereference panic**, crashing the pod and cascading 500 errors to `recommendationservice` and `frontend`. Fix = remove the env var → catalog is parsed once at startup, not per-request.

---

## Reference Links

- Blog: *Using Logging for your apps running on GKE*
- Blog: *How DevOps teams can use Cloud Monitoring and Logging to find issues quickly*

**Lab ID:** GSP736