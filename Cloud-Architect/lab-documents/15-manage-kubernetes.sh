#!/bin/bash

set -euo pipefail

# Lab configuration
export PROJECT_ID="qwiklabs-gcp-02-90fe1db8f438"
export CLUSTER_NAME="hello-world-l5wq"
export REGION="europe-west4"
export ZONE="europe-west4-c"
export NAMESPACE_NAME="gmp-umrb"
export REPO_NAME="sandbox-repo"
export SERVICE_NAME="helloweb-service-c7xh"
export INTERVAL="50s"

# Configure the Google Cloud project and zone
gcloud config set project "$PROJECT_ID"
gcloud config set compute/zone "$ZONE"

# Task 1: Create the GKE cluster
gcloud container clusters create "$CLUSTER_NAME" \
  --release-channel regular \
  --num-nodes 3 \
  --enable-autoscaling \
  --min-nodes 2 \
  --max-nodes 6 \
  --no-enable-ip-alias

# Task 2: Enable Managed Prometheus and create the namespace
gcloud container clusters update "$CLUSTER_NAME" \
  --enable-managed-prometheus \
  --zone "$ZONE"

kubectl create namespace "$NAMESPACE_NAME" --dry-run=client -o yaml | kubectl apply -f -

# Download the Prometheus application manifest
gcloud storage cp gs://spls/gsp510/prometheus-app.yaml .

# Configure the Prometheus application
cat > prometheus-app.yaml <<'EOF'
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
EOF

kubectl apply -n "$NAMESPACE_NAME" -f prometheus-app.yaml

# Download and configure PodMonitoring
gcloud storage cp gs://spls/gsp510/pod-monitoring.yaml .

cat > pod-monitoring.yaml <<EOF
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
    interval: $INTERVAL
EOF

kubectl apply -n "$NAMESPACE_NAME" -f pod-monitoring.yaml

# Task 3: Download and deploy the sample application
gcloud storage cp -r gs://spls/gsp510/hello-app/ .

gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"

kubectl apply -n "$NAMESPACE_NAME" \
  -f hello-app/manifests/helloweb-deployment.yaml

# Task 4: Create the logs-based metric
gcloud logging metrics create pod-image-errors \
  --description="Counts Kubernetes pod image errors" \
  --log-filter='resource.type="k8s_pod" AND severity=WARNING' || true

# Create the alerting policy configuration
cat > pod-error-alert.json <<'EOF'
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
        "trigger": {
          "count": 1
        },
        "thresholdValue": 0
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF

gcloud alpha monitoring policies create \
  --policy-from-file="pod-error-alert.json"

# Task 5: Fix the deployment manifest and redeploy
cd hello-app

cat > manifests/helloweb-deployment.yaml <<'EOF'
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
EOF

kubectl delete deployment helloweb \
  --namespace "$NAMESPACE_NAME" \
  --ignore-not-found

kubectl apply \
  --namespace "$NAMESPACE_NAME" \
  -f manifests/helloweb-deployment.yaml

# Task 6: Update the application to version 2.0.0
cat > main.go <<'EOF'
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
EOF

# Configure Docker authentication for Artifact Registry
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

# Build and push the v2 image
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/hello-app:v2"

docker build -t "$IMAGE" .
docker push "$IMAGE"

# Update the Kubernetes deployment
kubectl set image deployment/helloweb \
  --namespace "$NAMESPACE_NAME" \
  hello-app="$IMAGE"

# Expose the application through a LoadBalancer
kubectl expose deployment helloweb \
  --namespace "$NAMESPACE_NAME" \
  --name="$SERVICE_NAME" \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=8080 \
  --dry-run=client -o yaml | kubectl apply -f -

# Show the final deployment and service status
kubectl get deployment helloweb -n "$NAMESPACE_NAME"
kubectl get service "$SERVICE_NAME" -n "$NAMESPACE_NAME"

echo "Lab execution completed."
