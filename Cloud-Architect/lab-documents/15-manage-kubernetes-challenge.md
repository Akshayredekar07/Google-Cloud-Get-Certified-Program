# **GSP510 — Manage Kubernetes in Google Cloud: Challenge Lab**

**Duration:** 25 minutes | **Level:** Intermediate | **Cost:** No cost | **Type:** Challenge Lab (no step-by-step instructions — automated scoring)

---

## Overview

A **challenge lab** presents a scenario + tasks with **no walkthrough**. You must apply prior GKE skills independently, debug your own errors, and hit 100% within the time limit.

## Scenario

You've just onboarded at **Cymbal Shops**, gaining experience with Docker, Artifact Registry, and managing GKE deployments (manifests, scaling, monitoring, debugging). Before moving into a new role managing their e-commerce Kubernetes deployments, you must demonstrate your skills in a sandbox environment. A pre-existing Artifact Registry repo **`sandbox-repo`** contains a **containerized version** of the `hello-app` sample code you'll later build and push yourself.

## Your Tasks

1. Create a GKE cluster per given configuration.
2. Enable **Managed Prometheus** on the cluster.
3. Deploy a Kubernetes manifest and **debug** the resulting error.
4. Create a **logs-based metric** and **alerting policy** for pod errors.
5. **Fix** the manifest error, redeploy.
6. **Containerize** app code, push to Artifact Registry, expose via a `LoadBalancer` Service, and verify.

---

## Setup and Requirements

- Use an **Incognito/private browser window** — avoids account conflicts/unwanted billing.
- Labs are **timed and cannot be paused**.
- Use **only the provided student account**.

### Set Up Environment Variables

```bash
export PROJECT_ID="qwiklabs-gcp-02-90fe1db8f438"
export CLUSTER_NAME="hello-world-l5wq"
export REGION="europe-west4"
export ZONE="europe-west4-c"
export NAMESPACE_NAME="gmp-umrb"
export REPO_NAME="sandbox-repo"
export SERVICE_NAME="helloweb-service-c7xh"
```
**Explanation:** Exports lab-specific values (actual project ID, cluster name, region/zone, namespace, Artifact Registry repo, and Service name will differ per lab instance) into shell variables — used throughout every subsequent command so you never hardcode/retype them, and so the script is portable/reusable.

```bash
gcloud config set project "$PROJECT_ID"
gcloud config set compute/zone "$ZONE"
```
**Explanation:**
- `gcloud config set project` — sets the **active project** for all subsequent `gcloud` commands, avoiding the need to pass `--project` every time.
- `gcloud config set compute/zone` — sets a **default Compute zone**, so zone-scoped commands don't require an explicit `--zone` flag (though it's still passed explicitly in several commands below for clarity/safety).

---

## Task 1: Create a GKE Cluster

**Required config:**

| Setting | Value |
|---|---|
| Zone | `europe-west4-c` |
| Release channel | Regular |
| Cluster/Target version | default |
| Cluster autoscaler | Enabled |
| Number of nodes | 3 |
| Minimum nodes | 2 |
| Maximum nodes | 6 |

```bash
gcloud container clusters create "$CLUSTER_NAME" \
  --release-channel regular \
  --num-nodes 3 \
  --enable-autoscaling \
  --min-nodes 2 \
  --max-nodes 6 \
  --no-enable-ip-alias
```
**Explanation:**
- `container clusters create "$CLUSTER_NAME"` — provisions a new GKE cluster with the required name.
- `--release-channel regular` — enrolls the cluster in the **Regular release channel**, which auto-updates the control plane/nodes on Google's "regular" cadence (balances stability vs. newer features — distinct from `rapid` and `stable` channels).
- `--num-nodes 3` — initial/default node pool size of 3 nodes.
- `--enable-autoscaling --min-nodes 2 --max-nodes 6` — turns on the **cluster autoscaler** for the default node pool, letting GKE automatically scale the node count between 2 (minimum) and 6 (maximum) based on workload resource demand.
- `--no-enable-ip-alias` — disables **VPC-native (alias IP) networking**, falling back to routes-based networking. (Used here likely to speed up/simplify creation in the sandbox environment; note this is a divergence from GKE's modern default of VPC-native clusters.)
- Zone is picked up from the `gcloud config set compute/zone` default set earlier.

> ✅ **Check my progress**: *Create a GKE cluster.*

---

## Task 2: Enable Managed Prometheus on the GKE Cluster

**Goal:** Enable **Managed Service for Prometheus** on the existing cluster, create a namespace, deploy a sample Prometheus-instrumented app, and configure `PodMonitoring` to scrape it.

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --enable-managed-prometheus \
  --zone "$ZONE"
```
**Explanation:** Updates the **already-created** cluster to turn on **Managed Prometheus** (in Task 1 of the GSP1026 lab pattern, this flag is instead passed at *creation* time — here it's applied as an **update** to an existing cluster, demonstrating both paths work).

```bash
kubectl create namespace "$NAMESPACE_NAME" --dry-run=client -o yaml | kubectl apply -f -
```
**Explanation:** This is an **idempotent** way to create a namespace:
- `kubectl create namespace ... --dry-run=client -o yaml` — generates the namespace's YAML manifest **without actually sending it to the cluster** (`--dry-run=client`), and outputs it as YAML (`-o yaml`).
- `| kubectl apply -f -` — pipes that generated YAML into `kubectl apply`, which reads from stdin (`-f -`). Unlike `kubectl create namespace` directly, `apply` **won't error if the namespace already exists** — it simply reconciles to the desired state, making the command safe to re-run.

### Download and Deploy the Sample Prometheus App

```bash
gcloud storage cp gs://spls/gsp510/prometheus-app.yaml .
```
**Explanation:** Downloads the starter manifest (with `<todo>` placeholders) from a public Google Cloud Storage bucket into the current directory.

**Required `<todo>` fills (lines 35–38):**
- `containers.image`: `nilebox/prometheus-example-app:latest`
- `containers.name`: `prometheus-test`
- `ports.name`: `metrics`

**Completed manifest (`prometheus-app.yaml`):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-test
  labels:
    app: prometheus-test
spec:
  selector:
    matchLabels:
      app: prometheus-test
  replicas: 3
  template:
    metadata:
      labels:
        app: prometheus-test
    spec:
      nodeSelector:
        kubernetes.io/os: linux
        kubernetes.io/arch: amd64
      containers:
      - name: prometheus-test
        image: nilebox/prometheus-example-app:latest
        ports:
        - name: metrics
          containerPort: 1234
        command:
        - "/main"
        - "--process-metrics"
        - "--go-metrics"
```
**Explanation of key fields:**
- `replicas: 3` — runs 3 pod copies of the sample app.
- `nodeSelector` — constrains scheduling to Linux/amd64 nodes (relevant on clusters with mixed architectures/OSes; a safety constraint here).
- `ports.name: metrics` / `containerPort: 1234` — the app exposes Prometheus-format metrics on port `1234`, and the port is **named** `metrics` so the later `PodMonitoring` resource can reference it by name instead of a hardcoded number.
- `command: ["/main", "--process-metrics", "--go-metrics"]` — overrides the container's entrypoint, launching the app with flags to expose both process-level and Go runtime metrics.

```bash
kubectl apply -n "$NAMESPACE_NAME" -f prometheus-app.yaml
```
**Explanation:** Deploys the completed manifest into the `gmp-umrb` namespace (`-n` = `--namespace`).

### Download and Configure PodMonitoring

```bash
gcloud storage cp gs://spls/gsp510/pod-monitoring.yaml .
```
**Explanation:** Downloads the starter `PodMonitoring` CR template (with `<todo>` placeholders on lines 18–24).

**Required `<todo>` fills:**
- `metadata.name`: `prometheus-test`
- `labels.app.kubernetes.io/name`: `prometheus-test`
- `matchLabels.app`: `prometheus-test`
- `endpoints.interval`: `50s`

**Completed manifest (`pod-monitoring.yaml`):**
```yaml
apiVersion: monitoring.googleapis.com/v1alpha1
kind: PodMonitoring
metadata:
  name: prometheus-test
  labels:
    app.kubernetes.io/name: prometheus-test
spec:
  selector:
    matchLabels:
      app: prometheus-test
  endpoints:
  - port: metrics
    interval: 50s
```
**Explanation:** As with the earlier Managed Prometheus lab pattern (GSP1026), this `PodMonitoring` CR tells the managed collector to scrape any pod labeled `app=prometheus-test`, on the **named** port `metrics` (matches `ports.name: metrics` from the Deployment above), every **50 seconds**.

```bash
kubectl apply -n "$NAMESPACE_NAME" -f pod-monitoring.yaml
```
**Explanation:** Deploys the `PodMonitoring` resource into `gmp-umrb`, activating scraping for the sample app's pods.

> ✅ **Check my progress**: *Enable Managed Prometheus on the GKE cluster.*

---

## Task 3: Deploy an Application onto the GKE Cluster

```bash
gcloud storage cp -r gs://spls/gsp510/hello-app/ .
```
**Explanation:** `-r` (recursive) downloads the **entire** `hello-app` directory tree (source code + manifests folder) from the public bucket into the current directory.

```bash
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"
```
**Explanation:** Fetches cluster auth data/endpoint and merges it into local `kubeconfig`, so `kubectl` commands route to `hello-world-l5wq`. (Needed here since the cluster context wasn't set up before this point in the script.)

```bash
kubectl apply -n "$NAMESPACE_NAME" -f hello-app/manifests/helloweb-deployment.yaml
```
**Explanation:** Deploys the **as-downloaded** (intentionally broken) `helloweb-deployment.yaml` manifest into `gmp-umrb`.

### The Bug: `InvalidImageName`

Navigate to the **Workloads** page → `helloweb` deployment details → a **red notification bar** reads:
```
Pod errors: InvalidImageName
```
Clicking **View details** / checking the **Events** section reveals:
```
Error: InvalidImageName
Failed to apply default image tag "<todo>": couldn't parse image reference "<todo>": invalid reference format
```
**Root cause:** The downloaded manifest still contains a literal, unresolved `<todo>` placeholder string in the `image:` field instead of an actual container image reference — Kubernetes cannot parse `<todo>` as a valid image URI, so the pod cannot even be scheduled/pulled.

> **Task instruction:** Before fixing the image name, first build a **logs-based metric + alerting policy** (Task 4) so the team gets notified if this class of error recurs in production.

> ✅ **Check my progress**: *Deploy an application onto the GKE cluster.*

---

## Task 4: Create a Logs-Based Metric and Alerting Policy

**Goal:** Turn the `InvalidImageName` error pattern into a **counted metric**, then alert when it occurs.

### Logs Explorer Query

**Hint given:** the query should use exactly **one Resource Type** and **one Severity**. Expected matching log lines look like:
```
Error: InvalidImageName
Failed to apply default image tag "<todo>": couldn't parse image reference "<todo>": invalid reference format
```

Equivalent query (used in the automation script):
```
resource.type="k8s_pod" AND severity=WARNING
```
**Explanation:** `resource.type="k8s_pod"` — scopes to logs emitted **about** Kubernetes Pod objects (as opposed to `k8s_container`, which scopes to the container runtime's own logs) — pod scheduling/image-pull errors surface as **pod-level events**, hence `k8s_pod`. `severity=WARNING` — Kubernetes typically logs failed image pulls as `WARNING`-level Events, not `ERROR`, so filtering on `WARNING` (not `ERROR`) is required to actually surface this class of issue — a subtle but important detail.

### Create the Logs-Based Metric

Console path: **Logs Explorer → run query → Actions → Create Metric.**
- **Metric type:** Counter
- **Log Metric Name:** `pod-image-errors`

Equivalent CLI command:
```bash
gcloud logging metrics create pod-image-errors \
  --description="Counts Kubernetes pod image errors" \
  --log-filter='resource.type="k8s_pod" AND severity=WARNING' || true
```
**Explanation:**
- `logging metrics create pod-image-errors` — creates a **counter-type logs-based metric** (the default type) named `pod-image-errors`.
- `--log-filter='...'` — the same filter used in Logs Explorer; every matching log entry increments this metric.
- `--description="..."` — human-readable description shown in the console.
- `|| true` — ensures the script **doesn't halt** (thanks to `set -euo pipefail` at the top) if the metric already exists from a prior run — a defensive scripting pattern for idempotent re-execution.

### Create the Alerting Policy

**Required config:**
| Setting | Value |
|---|---|
| Rolling Window | 10 min |
| Rolling window function | Count |
| Time series aggregation | Sum |
| Condition type | Threshold |
| Alert trigger | Any time series violates |
| Threshold position | Above threshold |
| Threshold value | 0 |
| Use notification channel | Disable |
| Alert policy name | `Pod Error Alert` |

> **Note:** In the metric selector UI, **uncheck "Active"** to surface the newly created logs-based metric (`logging.googleapis.com/user/pod-image-errors`) — new custom metrics have no data yet, so they're hidden by the "Active" filter by default.

Equivalent policy definition (`pod-error-alert.json`):
```json
{
  "displayName": "Pod Error Alert",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "Kubernetes Pod - pod-image-errors",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_pod\" AND metric.type = \"logging.googleapis.com/user/pod-image-errors\"",
        "aggregations": [
          {
            "alignmentPeriod": "600s",
            "crossSeriesReducer": "REDUCE_SUM",
            "perSeriesAligner": "ALIGN_COUNT"
          }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "0s",
        "trigger": { "count": 1 },
        "thresholdValue": 0
      }
    }
  ],
  "alertStrategy": { "autoClose": "604800s" },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
```
**Explanation of key fields:**
- `metric.type = "logging.googleapis.com/user/pod-image-errors"` — targets the custom logs-based metric created above (all user-defined logs-based metrics live under the `logging.googleapis.com/user/` namespace).
- `alignmentPeriod: "600s"` — the **10-minute rolling window** (600 seconds), matching the required config.
- `perSeriesAligner: "ALIGN_COUNT"` — the **"Count"** rolling-window function: counts the number of log entries within each alignment period.
- `crossSeriesReducer: "REDUCE_SUM"` — the **"Sum"** time-series aggregation: sums counts across all matching time series into one.
- `comparison: "COMPARISON_GT"` + `thresholdValue: 0` — fires when the summed count is **strictly greater than 0**, i.e., **any** occurrence of the error triggers the alert ("Above threshold", value `0`).
- `trigger.count: 1` — the condition is considered violated as soon as **any single time series** breaches the threshold ("Any time series violates").
- `notificationChannels: []` — empty list = **notification channel disabled**, per the required config.
- `alertStrategy.autoClose: "604800s"` — auto-closes an open incident after 7 days (604,800 seconds) of no further violations (a default, not explicitly required by the task).

```bash
gcloud alpha monitoring policies create \
  --policy-from-file="pod-error-alert.json"
```
**Explanation:** Creates the alerting policy from the JSON definition file. The `alpha` command group is used because, at the time of this lab, policy management via `gcloud` for this feature set may only be available under the `alpha` track.

> ✅ **Check my progress**: *Create a logs-based metric and alerting policy.*

---

## Task 5: Update and Re-Deploy Your App

**Goal:** Fix the broken `<todo>` image reference, delete the broken deployment, redeploy cleanly.

**Correct image reference to use:**
```
us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
```

**Fixed manifest (`hello-app/manifests/helloweb-deployment.yaml`):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloweb
  labels:
    app: hello
spec:
  selector:
    matchLabels:
      app: hello
      tier: web
  template:
    metadata:
      labels:
        app: hello
        tier: web
    spec:
      containers:
      - name: hello-app
        image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 200m
```
**Explanation of key fields:**
- `image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0` — the corrected, **valid** Artifact Registry image reference (replacing the broken `<todo>` placeholder), pointing to Google's public sample `hello-app` image, tag `1.0`.
- `containerPort: 8080` — the app listens on port 8080 inside the container.
- `resources.requests.cpu: 200m` — requests **200 millicpu** (0.2 vCPU) as a scheduling hint/guarantee for the Kubernetes scheduler.

```bash
kubectl delete deployment helloweb \
  --namespace "$NAMESPACE_NAME" \
  --ignore-not-found
```
**Explanation:**
- `kubectl delete deployment helloweb` — removes the existing (broken) `helloweb` Deployment object and its managed ReplicaSet/Pods.
- `--ignore-not-found` — prevents an error if the deployment somehow doesn't exist (idempotent/safe re-run behavior).

```bash
kubectl apply \
  --namespace "$NAMESPACE_NAME" \
  -f manifests/helloweb-deployment.yaml
```
**Explanation:** Redeploys the now-corrected manifest into `gmp-umrb`. Expect the Workloads page to show `helloweb` running with **no errors** this time.

> ✅ **Check my progress**: *Update and re-deploy your app.*

---

## Task 6: Containerize Your Code and Deploy It onto the Cluster

**Goal:** Bump the app to `Version: 2.0.0`, build a Docker image locally, push it to `sandbox-repo` in Artifact Registry with tag `v2`, update the deployment to use it, and expose it via a public `LoadBalancer` Service.

### Update `main.go` (line 49 → `Version: 2.0.0`)

```go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", hello)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func hello(w http.ResponseWriter, r *http.Request) {
	log.Printf("Serving request: %s", r.URL.Path)
	host, _ := os.Hostname()

	fmt.Fprintf(w, "Hello, world!\n")
	fmt.Fprintf(w, "Version: 2.0.0\n")
	fmt.Fprintf(w, "Hostname: %s\n", host)
}
```
**Explanation of key logic:**
- `port := os.Getenv("PORT")` with a fallback to `"8080"` — reads the listening port from an environment variable if set (12-factor app pattern), otherwise defaults to 8080 (matching the Dockerfile/deployment's expected port).
- The `hello` handler writes three lines: a greeting, the **hardcoded version string** (`2.0.0` — this is the actual code change required), and the pod's hostname (`os.Hostname()`) — which is how the final response shows something like `Hostname: helloweb-6fc7476576-cvv5f`, letting you visually confirm which pod served the request.

### Configure Docker Authentication for Artifact Registry

```bash
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
```
**Explanation:** Configures the local Docker CLI's credential helper to authenticate against the **regional Artifact Registry Docker endpoint** (e.g., `europe-west4-docker.pkg.dev`) using your active `gcloud` credentials — required before `docker push` can succeed against that registry. `--quiet` suppresses the confirmation prompt.

### Build and Push the v2 Image

```bash
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/hello-app:v2"

docker build -t "$IMAGE" .
docker push "$IMAGE"
```
**Explanation:**
- The `IMAGE` variable is constructed following **Artifact Registry's required naming convention**: `LOCATION-docker.pkg.dev/PROJECT_ID/REPOSITORY/IMAGE:TAG`.
- `docker build -t "$IMAGE" .` — builds a Docker image from the `Dockerfile` in the current directory (`hello-app/`), tagging it directly with the full Artifact Registry path so no separate `docker tag` step is needed.
- `docker push "$IMAGE"` — uploads the built image to the `sandbox-repo` repository in Artifact Registry under the `v2` tag.

### Update the Kubernetes Deployment to Use the New Image

```bash
kubectl set image deployment/helloweb \
  --namespace "$NAMESPACE_NAME" \
  hello-app="$IMAGE"
```
**Explanation:** `kubectl set image` performs an **in-place rolling update** of the `helloweb` Deployment, changing the container named `hello-app` (must match the container `name:` field from the manifest) to use the newly pushed `v2` image — triggers a rolling restart of pods without needing to re-apply the whole manifest.

### Expose the Deployment via a LoadBalancer Service

```bash
kubectl expose deployment helloweb \
  --namespace "$NAMESPACE_NAME" \
  --name="$SERVICE_NAME" \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  --dry-run=client -o yaml | kubectl apply -f -
```
**Explanation:**
- `kubectl expose deployment helloweb` — creates a new **Service** object that fronts the `helloweb` Deployment's pods.
- `--name="$SERVICE_NAME"` — names the Service `helloweb-service-c7xh` (per lab requirement).
- `--type=LoadBalancer` — provisions an external **cloud Load Balancer** (with a public IP) in front of the Service — the standard way to expose a GKE workload to the internet.
- `--port=8080` — the port the **Service itself** listens on (what external clients connect to).
- `--target-port=8080` — the port on the **container** that traffic is forwarded to (must match the Dockerfile's `EXPOSE`/listening port).
- `--dry-run=client -o yaml | kubectl apply -f -` — same idempotent pattern as the namespace creation earlier: generates the Service manifest without submitting it, then applies it via `apply` (safe to re-run, won't error if the Service already exists).

### Verify

```bash
kubectl get deployment helloweb -n "$NAMESPACE_NAME"
kubectl get service "$SERVICE_NAME" -n "$NAMESPACE_NAME"
```
**Explanation:** Confirms the Deployment is healthy (correct replica counts) and retrieves the Service's details — specifically its `EXTERNAL-IP`, which may show `<pending>` for a minute or two while the cloud load balancer provisions.

**Navigate to the external IP** in a browser. Expected response:
```
Hello, world!
Version: 2.0.0
Hostname: helloweb-6fc7476576-cvv5f
```
This confirms: the `v2` image was built/pushed correctly, the deployment picked it up, and the `LoadBalancer` Service is correctly routing external traffic to the pod on port 8080.

> ✅ **Check my progress**: *Containerize your code and deploy it onto the cluster.*

---

## Summary / Key Takeaways

| Task | Core Skill Demonstrated |
|---|---|
| 1 | GKE cluster creation with release channel + cluster autoscaler config |
| 2 | Enabling Managed Prometheus **post-creation** via `clusters update`; `PodMonitoring` CR with named ports |
| 3 | Deploying a manifest and reading `InvalidImageName` errors from Workloads/Events UI |
| 4 | Logs-based metric (Counter) + Cloud Monitoring alerting policy (threshold, rolling window, aggregation) tied to a specific error signature |
| 5 | `kubectl delete` + `kubectl apply` cycle to cleanly replace a broken Deployment |
| 6 | Full CI-style loop: edit source → `docker build`/`push` to Artifact Registry → `kubectl set image` rolling update → `kubectl expose` with `LoadBalancer` |

### Debugging Pattern (Exam-Relevant)
`Deploy manifest → Workloads page shows red error banner → View details/Events → identify malformed field (here: literal <todo> in image:) → before fixing, instrument it as a logs-based metric + alert (proactive monitoring) → fix the manifest → delete + reapply → verify clean state.`

### Two Distinct Severity/Resource-Type Filters to Remember
- Pod scheduling/image errors → `resource.type="k8s_pod"`, typically logged at `severity=WARNING`.
- Container runtime/application errors (e.g., the earlier GSP736 lab) → `resource.type="k8s_container"`, typically logged at `severity=ERROR`.

