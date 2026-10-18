#!/usr/bin/env bash
# =============================================================================
# Log in to Google Cloud from CI WITHOUT a long-lived service-account key,
# using Workload Identity Federation (WIF).
#
# How it works:
#   1. The CI system (GitLab) issues a short-lived, signed OIDC token (JWT)
#      that says "this is project X, branch main, pipeline Y".
#   2. Google's STS verifies the signature against GitLab's public keys and
#      checks the WIF provider's attribute conditions (e.g. only this project,
#      only protected branches).
#   3. Google returns a ~1h access token impersonating GCP_SERVICE_ACCOUNT.
# Nothing secret is stored in CI variables - only resource names.
#
# Required env:
#   GCP_ID_TOKEN          OIDC token (GitLab `id_tokens:` keyword)
#   GCP_PROJECT_ID        e.g. my-voice-dev-project
#   GCP_PROJECT_NUMBER    numeric project number that owns the WIF pool
#   GCP_WIF_POOL          workload identity pool id, e.g. gitlab
#   GCP_WIF_PROVIDER      provider id, e.g. gitlab-com
#   GCP_SERVICE_ACCOUNT   e.g. ci-deployer@my-voice-dev-project.iam.gserviceaccount.com
# Optional (to also fetch kubectl credentials):
#   GKE_CLUSTER, GKE_LOCATION
# =============================================================================
set -euo pipefail

: "${GCP_ID_TOKEN:?GCP_ID_TOKEN missing - add id_tokens to the job}"
: "${GCP_PROJECT_ID:?}" "${GCP_PROJECT_NUMBER:?}" "${GCP_WIF_POOL:?}" "${GCP_WIF_PROVIDER:?}" "${GCP_SERVICE_ACCOUNT:?}"

workdir="${CI_PROJECT_DIR:-$PWD}/.gcp"
mkdir -p "$workdir"
chmod 700 "$workdir"
printf '%s' "$GCP_ID_TOKEN" > "$workdir/oidc-token.jwt"

# Build an "external account" credential config: tells gcloud/Google client
# libraries to exchange the OIDC token file for Google credentials.
gcloud iam workload-identity-pools create-cred-config \
  "projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${GCP_WIF_POOL}/providers/${GCP_WIF_PROVIDER}" \
  --service-account="$GCP_SERVICE_ACCOUNT" \
  --credential-source-file="$workdir/oidc-token.jwt" \
  --output-file="$workdir/credentials.json"

gcloud auth login --cred-file="$workdir/credentials.json" --quiet
gcloud config set project "$GCP_PROJECT_ID" --quiet
export GOOGLE_APPLICATION_CREDENTIALS="$workdir/credentials.json"

if [ -n "${GKE_CLUSTER:-}" ]; then
  gcloud container clusters get-credentials "$GKE_CLUSTER" \
    --location "${GKE_LOCATION:?GKE_LOCATION required with GKE_CLUSTER}" --project "$GCP_PROJECT_ID"
fi
echo "[gcp-auth] authenticated as $GCP_SERVICE_ACCOUNT (project $GCP_PROJECT_ID)"
