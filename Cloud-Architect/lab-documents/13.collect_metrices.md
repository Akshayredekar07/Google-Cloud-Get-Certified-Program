# GSP1026 — Collect Metrics from Exporters using the Managed Service for Prometheus

**Duration:** 20 minutes (self-paced) | **Level:** Intermediate | **Cost:** No cost

---

## Overview

In this lab, you use **Managed Service for Prometheus (GMP)** to collect metrics from external/infrastructure sources via **exporters** — specifically, you configure the built-in **example app** exporter (via a `PodMonitoring` CR) and then a standalone **node_exporter** running in Cloud Shell, ingested by a locally-run Prometheus binary configured to export into GMP.

## Objectives

- Deploy a GKE instance.
- Configure the **PodMonitoring** custom resource and the **node-exporter** tool.
- Build the **GMP binary** locally and deploy it (run it) against the GKE instance/project.
- Apply a Prometheus configuration to begin collecting metrics.

---

## Setup and Requirements

- Use an **Incognito/private browser window** — avoids account conflicts and unwanted billing on your personal account.
- Labs are **timed and cannot be paused**.
- Use **only the provided student account** — never your personal Google Cloud account.

### Steps to Start

1. Click **Start Lab** (pay if required).
2. Click **Open Google Cloud console** (or *Open Link in Incognito Window* in Chrome).
3. If prompted, click **Use Another Account**.
4. Enter provided **Username** → **Next**.
5. Enter provided **Password** → **Next**.
6. Accept terms & conditions. **Do not** add recovery options, 2FA, or free trials.
7. Console opens, authenticated as the temporary lab account.

---

## Activate Cloud Shell

**Cloud Shell** is a browser-based VM preloaded with dev tools:
- **Persistent 5 GB home directory.**
- Pre-installed `gcloud` CLI with tab-completion.
- Command-line access to your Google Cloud resources, no local install needed.

### Steps

1. Click the **Activate Cloud Shell** icon at the top of the console.
2. Continue through the info window, then **Authorize** Cloud Shell.

### Useful Commands

```bash
gcloud auth list
```
**Explanation:** Lists authenticated accounts in the current Cloud Shell session and marks the `ACTIVE` one with `*`. Confirms you're operating under the correct lab identity.

```bash
gcloud config list project
```
**Explanation:** Prints the current `gcloud` CLI config, specifically the active `project` value — confirms all commands will target the correct lab project.

---

## Task 1: Deploy GKE Cluster

```bash
gcloud beta container clusters create gmp-cluster --num-nodes=1 --zone Zone --enable-managed-prometheus
```
**Explanation:**
- `gcloud beta container clusters create` — creates a new GKE cluster (using the `beta` command track, needed for some newer/preview flags).
- `gmp-cluster` — the name given to the new cluster.
- `--num-nodes=1` — provisions a single-node cluster (minimal footprint, sufficient for this lab).
- `--zone Zone` — replace `Zone` with the actual zone provided for the lab (e.g., `us-central1-a`).
- `--enable-managed-prometheus` — turns on **Google Cloud Managed Service for Prometheus** at the cluster level, so GKE automatically deploys the managed collector components needed to scrape and export Prometheus-format metrics.

```bash
gcloud container clusters get-credentials gmp-cluster --zone=Zone
```
**Explanation:** Fetches the cluster's authentication data/endpoint and merges it into your local `kubeconfig`, so subsequent `kubectl` commands are automatically routed to `gmp-cluster`. Replace `Zone` with the actual lab zone.

---

## Task 2: Set Up a Namespace

```bash
kubectl create ns gmp-test
```
**Explanation:** Creates a new Kubernetes **namespace** called `gmp-test`. Namespaces logically isolate resources within a cluster — all example-app and monitoring resources for this lab will live inside this namespace, keeping them separate from other workloads.

> Verify: check whether Prometheus components have been deployed (e.g., via `kubectl get pods -n gmp-system` or similar, to confirm the managed collector is running as a result of `--enable-managed-prometheus`).

---

## Task 3: Deploy the Example Application

The managed service ships a reference manifest for an example app that **emits Prometheus-format metrics** on a metrics port, running as **3 replicas**.

```bash
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.2.3/examples/example-app.yaml
```
**Explanation:**
- `-n gmp-test` — targets the `gmp-test` namespace created earlier, so all objects in the manifest (Deployment, Service, etc.) are created there.
- `apply -f <URL>` — `kubectl` fetches the manifest directly from the given raw GitHub URL and applies it to the cluster, deploying the example application's 3 replica pods.

---

## Task 4: Configure a PodMonitoring Resource

**Concept:** Managed Service for Prometheus uses **target scraping** to pull metrics from applications. This is configured declaratively via **Kubernetes Custom Resources (CRs)** — specifically the **PodMonitoring** CR.

- A `PodMonitoring` CR only scrapes targets **within its own namespace**. To scrape across multiple namespaces, the same CR must be deployed in each one.
- To scrape **across all namespaces** with one resource, use the **`ClusterPodMonitoring`** CR instead (same interface, but not namespace-restricted).
- Verify installed PodMonitoring resources across the cluster with:
  ```bash
  kubectl get podmonitoring -A
  ```
  **Explanation:** `-A` (`--all-namespaces`) lists `PodMonitoring` custom resources across every namespace, confirming where scraping is configured.

### Example PodMonitoring Manifest (`prom-example`, in `gmp-test`)

```yaml
apiVersion: monitoring.googleapis.com/v1alpha1
kind: PodMonitoring
metadata:
  name: prom-example
spec:
  selector:
    matchLabels:
      app: prom-example
  endpoints:
  - port: metrics
    interval: 30s
```
**Explanation of fields:**
- `selector.matchLabels.app: prom-example` — uses a Kubernetes **label selector** to find all pods in the namespace carrying the label `app=prom-example` (the example app deployed in Task 3).
- `endpoints.port: metrics` — scrapes the port **named** `metrics` on each matching pod (not a raw port number — must match a named port in the pod spec).
- `endpoints.interval: 30s` — scrapes each matched target's `/metrics` HTTP path every **30 seconds**.

```bash
kubectl -n gmp-test apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/v0.2.3/examples/pod-monitoring.yaml
```
**Explanation:** Applies the above `PodMonitoring` manifest (hosted on GitHub) into the `gmp-test` namespace. Once applied, the **managed collector** immediately starts scraping the matching pods on the defined interval — no manual Prometheus server configuration required.

> **Note:** An additional `targetLabels` field (not used in this basic example) provides Prometheus-style relabeling — letting you promote pod labels into ingested time-series labels. Mandatory target labels cannot be overwritten this way.

> **Follow-up (optional, referenced only):** Query ingested metrics via *Query data from the Prometheus service*, and explore *Additional topics for managed collection* for filtering exported metrics and adapting existing `prom-operator` resources.

---

## Task 5: Download the Prometheus Binary

```bash
git clone https://github.com/GoogleCloudPlatform/prometheus && cd prometheus
```
**Explanation:** Clones Google Cloud's fork of the Prometheus source repository (which includes GMP-specific export flags) into Cloud Shell, then `cd`'s into it.

```bash
git checkout v2.28.1-gmp.4
```
**Explanation:** Checks out a specific **tagged release** (`v2.28.1-gmp.4`) of the repo — pinning to a known-compatible version of Prometheus that includes the Google Cloud Managed Service for Prometheus export patches, ensuring reproducible/expected behavior.

```bash
wget https://storage.googleapis.com/kochasoft/gsp1026/prometheus
```
**Explanation:** Downloads a **prebuilt Prometheus binary** (with GMP export support already compiled in) from a Google Cloud Storage bucket — avoids having to compile from source manually inside the lab.

```bash
chmod a+x prometheus
```
**Explanation:** `chmod a+x` grants **execute permission** to **a**ll users (owner, group, others) on the `prometheus` binary file, since downloaded files aren't executable by default. Required before it can be run with `./prometheus`.

---

## Task 6: Run the Prometheus Binary

```bash
export PROJECT_ID=$(gcloud config get-value project)
```
**Explanation:** Runs `gcloud config get-value project` to fetch the active project ID, and stores it in the shell variable `PROJECT_ID` for reuse in later commands (needed so exported metrics are tagged/routed to the correct Google Cloud project).

```bash
export ZONE=Zone
```
**Explanation:** Sets the shell variable `ZONE` to the lab's actual zone value (replace the placeholder `Zone`, e.g., `us-central1-a`). Used to label exported metrics with their originating location.

```bash
./prometheus \
  --config.file=documentation/examples/prometheus.yml --export.label.project-id=$PROJECT_ID --export.label.location=$ZONE
```
**Explanation:**
- `./prometheus` — runs the local binary directly.
- `--config.file=documentation/examples/prometheus.yml` — points Prometheus at a **default example scrape configuration** bundled in the repo (defines what targets to scrape and how).
- `--export.label.project-id=$PROJECT_ID` — attaches the project ID as a **label** on every metric exported to GMP, so metrics are correctly associated with your Google Cloud project.
- `--export.label.location=$ZONE` — attaches the zone as a label on exported metrics, providing location context for the time series.

**Verification:** Open **Managed Prometheus** in the Console UI and run the PromQL query:
```
up
```
**Explanation:** The `up` metric is a built-in Prometheus metric that is `1` if a scrape target is successfully reachable, `0` otherwise. Seeing a result (with `instance="localhost..."`) confirms the locally-run Prometheus binary is successfully exporting data into GMP.

---

## Task 7: Download and Run the Node Exporter

**Concept:** `node_exporter` is a standard Prometheus exporter that exposes **host/OS-level metrics** (CPU, memory, disk, network) on port `9100` by default — a classic example of "collecting metrics from other infrastructure sources via exporters," the lab's stated theme.

> Open a **new/second tab** in Cloud Shell to run the node_exporter commands (keep the first tab's Prometheus process, or stop it as instructed below, without losing your session).

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
```
**Explanation:** Downloads the **node_exporter v1.3.1** release tarball (Linux, amd64 architecture) from its official GitHub Releases page.

```bash
tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
```
**Explanation:** Extracts the downloaded tarball. Flags: `x` = extract, `v` = verbose (list files as they're extracted), `f` = read from the specified file, `z` = the archive is gzip-compressed.

```bash
cd node_exporter-1.3.1.linux-amd64
```
**Explanation:** Changes into the extracted directory containing the `node_exporter` executable.

```bash
./node_exporter
```
**Explanation:** Runs the node_exporter binary directly, which starts an HTTP server exposing host metrics at `/metrics` on **port 9100** by default. This is the port referenced later when configuring Prometheus's scrape target.

Expected output confirming it's running:
```
ts=... caller=node_exporter.go:199 level=info msg="Listening on" address=:9100
ts=... caller=tls_config.go:195 level=info msg="TLS is disabled." http2=false
```

### Create a `config.yaml` File

> First, **stop** the currently running Prometheus process in the **first** Cloud Shell tab (e.g., `Ctrl+C`) — a new config pointing at node_exporter will replace the old one.

```bash
vi config.yaml
```
**Explanation:** Opens the `vi` text editor to create a new file named `config.yaml` in the current directory.

Contents to add:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
```
**Explanation of fields:**
- `global.scrape_interval: 15s` — sets the **default** interval (every 15 seconds) at which Prometheus scrapes all configured targets, unless overridden per-job.
- `scrape_configs` — the list of scrape jobs Prometheus should run.
- `job_name: node` — a label identifying this scrape job as `node` (will tag all resulting metrics with `job="node"`).
- `static_configs.targets: ['localhost:9100']` — a **hardcoded (static)** list of scrape targets; here, it points at the `node_exporter` process running locally on port `9100`.

### Upload `config.yaml` for Verification

```bash
export PROJECT=$(gcloud config get-value project)
```
**Explanation:** Fetches and stores the active project ID into the `PROJECT` shell variable (used for bucket naming and export labeling below).

```bash
gcloud storage buckets create -p $PROJECT gs://$PROJECT
```
**Explanation:**
- `gcloud storage buckets create` — creates a new **Cloud Storage bucket**.
- `-p $PROJECT` — specifies which project the bucket belongs to (billing/ownership).
- `gs://$PROJECT` — names the bucket identically to the project ID (a common convention to guarantee a globally-unique bucket name, since project IDs are globally unique).

```bash
gcloud storage cp config.yaml gs://$PROJECT
```
**Explanation:** Copies (`cp`) the local `config.yaml` file up into the newly created Cloud Storage bucket — used here simply as a way to persist/verify the config file (e.g., for review or backup), not strictly required for Prometheus to function locally.

```bash
gsutil -m acl set -R -a public-read gs://$PROJECT
```
**Explanation:**
- `gsutil` — the legacy Cloud Storage CLI tool (still used here alongside the newer `gcloud storage` commands).
- `-m` — performs the operation with **parallel/multi-threaded** processing for speed.
- `acl set -R -a public-read` — sets the **Access Control List** recursively (`-R`, applying to all objects in the bucket) to grant **`public-read`** access — making the bucket's contents publicly readable (used here purely to demonstrate/verify the upload; not a production security best practice).

### Re-run Prometheus with the New Config

```bash
./prometheus --config.file=config.yaml --export.label.project-id=$PROJECT --export.label.location=$ZONE
```
**Explanation:** Restarts the Prometheus binary, now pointing at the **custom `config.yaml`** (instead of the earlier example config), so it scrapes `node_exporter` on `localhost:9100` every 15 seconds and exports the resulting metrics into GMP, labeled with the project ID and zone.

### View Node Exporter Metrics via PromQL

1. In Cloud Shell, click the **Web Preview** icon.
2. Click **Change Preview Port**, set it to **`9090`** (Prometheus's default UI/API port), then **Change and Preview**.
3. In the PromQL query editor, type a query prefixed with **`node_`** — this autocompletes/suggests all available node-exporter metric names.
4. Example query:
   ```
   node_cpu_seconds_total
   ```
   **Explanation:** A cumulative counter metric reporting total CPU time (in seconds) spent by the host CPU(s) in each mode (user, system, idle, etc.) since node_exporter started — plotted as a graph in the Prometheus UI, confirming metrics are actively flowing from the exporter through Prometheus into GMP.
5. Explore other `node_*` metrics (memory, disk I/O, network, filesystem, etc.) to further confirm data collection.

---

## Summary / Key Takeaways

| Step | Tool / Resource | Purpose |
|---|---|---|
| Cluster creation | `gcloud container clusters create --enable-managed-prometheus` | Spin up GKE with GMP collector auto-deployed |
| Namespace + example app | `kubectl create ns` + manifest apply | Isolated app that emits Prometheus metrics |
| Scrape config (in-cluster) | `PodMonitoring` CR | Declaratively tells GMP's managed collector what/how to scrape inside the cluster |
| Scrape config (multi-namespace) | `ClusterPodMonitoring` CR | Same as PodMonitoring but not namespace-scoped |
| External binary collection | Prometheus binary + `--export.label.*` flags | Lets a self-run Prometheus instance (outside GKE's managed collector) export into GMP |
| Host-level metrics | `node_exporter` on port `9100` | Classic OS/infra exporter pattern — target added via `static_configs` in `config.yaml` |
| Verification | PromQL `up` and `node_*` queries in Console/Web Preview (port 9090) | Confirms scrape targets are live and data is flowing |

**Core concept for exam recall:** Managed Service for Prometheus (GMP) supports **two collection patterns**:
1. **Managed/in-cluster collection** — via `PodMonitoring` / `ClusterPodMonitoring` CRs, scraped automatically by GKE's built-in collector (no manual Prometheus server needed).
2. **Self-deployed Prometheus with GMP export** — a standalone Prometheus binary (built/run with `--export.label.*` flags) that scrapes arbitrary targets (like `node_exporter`) and **exports** results into GMP as the storage/query backend, useful for infrastructure outside the managed collector's automatic reach.

---

## Reference Links

- Google Cloud Managed Service for Prometheus documentation.

**Lab ID:** GSP1026