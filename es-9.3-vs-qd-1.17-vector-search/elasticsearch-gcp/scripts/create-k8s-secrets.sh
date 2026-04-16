#TODO move this into the makefile and find somewhere else to store the secrets
#TODO move all the secrets including the terraform secrets into a single secrets file, one file is JSON so not sure if this is possible yet

#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="default"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SECRETS_ENV="${REPO_ROOT}/secrets/.secrets.env"

# Load shared secrets file (repo root secrets/), if it exists
if [[ -f "${SECRETS_ENV}" ]]; then
  echo "Loading credentials from ${SECRETS_ENV}..."
  set -a
  # shellcheck disable=SC1090
  source "${SECRETS_ENV}"
  set +a
else
  echo "Note: ${SECRETS_ENV} not found. Using environment variables only."
  echo "To use secrets file: cp secrets/.secrets.env.example secrets/.secrets.env (then edit it)"
  echo ""
fi

# ============================================================================
# Docker Registry Credentials
# ============================================================================

DOCKER_SECRET_NAME="regcred"

# Validate required Docker credentials
if [[ -z "${DOCKER_USERNAME:-}" ]]; then
  echo "ERROR: DOCKER_USERNAME not set"
  echo ""
  echo "Please either:"
  echo "  1. Create and edit secrets/.secrets.env from template: cp secrets/.secrets.env.example secrets/.secrets.env"
  echo "  2. Set environment variable: export DOCKER_USERNAME='your-username'"
  exit 1
fi

if [[ -z "${DOCKER_PASSWORD:-}" ]]; then
  echo "ERROR: DOCKER_PASSWORD not set"
  echo ""
  echo "Please either:"
  echo "  1. Create and edit secrets/.secrets.env from template: cp secrets/.secrets.env.example secrets/.secrets.env"
  echo "  2. Set environment variable: export DOCKER_PASSWORD='your-password'"
  exit 1
fi

if [[ -z "${DOCKER_EMAIL:-}" ]]; then
  echo "ERROR: DOCKER_EMAIL not set"
  echo ""
  echo "Please either:"
  echo "  1. Create and edit secrets/.secrets.env from template: cp secrets/.secrets.env.example secrets/.secrets.env"
  echo "  2. Set environment variable: export DOCKER_EMAIL='your-email@example.com'"
  exit 1
fi

echo "Creating docker registry secret..."
kubectl delete secret "$DOCKER_SECRET_NAME" --namespace="$NAMESPACE" --ignore-not-found
kubectl create secret docker-registry "$DOCKER_SECRET_NAME" \
  --docker-server="$DOCKER_REGISTRY" \
  --docker-username="$DOCKER_USERNAME" \
  --docker-password="$DOCKER_PASSWORD" \
  --docker-email="$DOCKER_EMAIL" \
  --namespace="$NAMESPACE"
echo "✓ Created secret: $DOCKER_SECRET_NAME"

# ============================================================================
# Elasticsearch Results Cluster Credentials (Optional)
# ============================================================================

RESULTS_SECRET_NAME="jingra-results-cluster"

if [[ -n "${RESULTS_ES_PASSWORD:-}" ]]; then
  echo "Creating results cluster secret..."
  kubectl delete secret "$RESULTS_SECRET_NAME" --namespace="$NAMESPACE" --ignore-not-found
  kubectl create secret generic "$RESULTS_SECRET_NAME" \
    --from-literal=RESULTS_ES_URL="$RESULTS_ES_URL" \
    --from-literal=RESULTS_ES_USER="$RESULTS_ES_USER" \
    --from-literal=RESULTS_ES_PASSWORD="$RESULTS_ES_PASSWORD" \
    --namespace="$NAMESPACE"
  echo "✓ Created secret: $RESULTS_SECRET_NAME"
else
  echo "Note: RESULTS_ES_PASSWORD not set, skipping results cluster secret"
  echo "      (Results upload will be disabled - this is optional)"
fi

# ============================================================================
# Jingra workload credentials (same Secret name as Qdrant stack; key differs)
# ============================================================================

JINGRA_CREDENTIALS_SECRET="jingra-credentials"
ECK_ELASTIC_USER_SECRET="es-cluster-es-elastic-user"

if kubectl get secret "$ECK_ELASTIC_USER_SECRET" --namespace="$NAMESPACE" >/dev/null 2>&1; then
  echo "Syncing ECK elastic user password into $JINGRA_CREDENTIALS_SECRET..."
  ES_PASS=$(kubectl get secret "$ECK_ELASTIC_USER_SECRET" --namespace="$NAMESPACE" -o jsonpath='{.data.elastic}' | base64 -d)
  kubectl create secret generic "$JINGRA_CREDENTIALS_SECRET" \
    --from-literal=ENGINE_PASSWORD="$ES_PASS" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✓ Applied secret: $JINGRA_CREDENTIALS_SECRET"
else
  echo "Note: $ECK_ELASTIC_USER_SECRET not found; skipping $JINGRA_CREDENTIALS_SECRET"
  echo "      (Run secrets-create again after the Elasticsearch cluster exists.)"
fi

# ============================================================================
# Dataset URLs
# ============================================================================

DATASET_SECRET_NAME="jingra-dataset-urls"

echo "Creating dataset URLs secret..."
kubectl delete secret "$DATASET_SECRET_NAME" --namespace="$NAMESPACE" --ignore-not-found
kubectl create secret generic "$DATASET_SECRET_NAME" \
  --from-literal=DATASET_DATA_URL="$DATASET_DATA_URL" \
  --from-literal=DATASET_QUERIES_URL="$DATASET_QUERIES_URL" \
  --namespace="$NAMESPACE"
echo "✓ Created secret: $DATASET_SECRET_NAME"

echo ""
echo "✅ All secrets created successfully!"
