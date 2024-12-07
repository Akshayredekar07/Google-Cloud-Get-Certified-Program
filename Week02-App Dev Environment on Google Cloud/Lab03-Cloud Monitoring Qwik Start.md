## Cloud Monitoring: Qwik Start

**Set your region and zone**
```bash
gcloud config set compute/zone "europe-west4-c"
export ZONE=$(gcloud config get compute/zone)

gcloud config set compute/region "europe-west4"
export REGION=$(gcloud config get compute/region)
```

### Create a Compute Engine instance
```bash
gcloud compute instances create lamp-1-vm \
    --zone=europe-west4-c \
    --machine-type=e2-medium \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --create-disk=auto-delete=yes \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --boot-disk-device-name=lamp-1-vm
```
