#!/usr/bin/env bash
# Deploy the local S3 backup store (SeaweedFS, namespace "backup") and hand
# its credentials to the namespaces that write backups.
#
#   scripts/backup-store-up.sh [namespace ...]   # default: voice
#
# The access key is random and generated once; it lives only in Kubernetes
# Secrets, never in git. Re-running is safe (idempotent).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE_NS=backup
log() { printf '[backup-store] %s\n' "$*"; }

kubectl apply -f - <<YAML >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${STORE_NS}
YAML

if ! kubectl -n "$STORE_NS" get secret seaweedfs-s3 >/dev/null 2>&1; then
  log "generating a new S3 key pair"
  key="backup-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  secret="$(head -c 30 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)"
  cfg=$(printf '{"identities":[{"name":"backup","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":["Admin","Read","List","Tagging","Write"]}]}' "$key" "$secret")
  kubectl -n "$STORE_NS" create secret generic seaweedfs-s3 \
    --from-literal=ACCESS_KEY_ID="$key" \
    --from-literal=ACCESS_SECRET_KEY="$secret" \
    --from-literal=s3.json="$cfg" >/dev/null
fi

kubectl apply -f "$ROOT/deploy/backup-store/seaweedfs.yaml" >/dev/null
kubectl -n "$STORE_NS" rollout status deploy/seaweedfs --timeout=180s >/dev/null
log "SeaweedFS S3 ready at http://seaweedfs.${STORE_NS}.svc:8333 (bucket: backups)"

# Copy just the key pair (not the server config) to each consumer namespace.
key=$(kubectl -n "$STORE_NS" get secret seaweedfs-s3 -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)
secret=$(kubectl -n "$STORE_NS" get secret seaweedfs-s3 -o jsonpath='{.data.ACCESS_SECRET_KEY}' | base64 -d)
for ns in "${@:-voice}"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" create secret generic backup-s3-credentials \
    --from-literal=ACCESS_KEY_ID="$key" --from-literal=ACCESS_SECRET_KEY="$secret" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "credentials -> secret/backup-s3-credentials in namespace $ns"
done
