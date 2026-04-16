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

if [[ -f ".qdrant-api-key.env" ]]; then
	echo "Loading Qdrant API key from .qdrant-api-key.env..."
	set -a
	# shellcheck disable=SC1091
	source ".qdrant-api-key.env"
	set +a
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
# Qdrant TLS + API key (required by cluster.yml)
# QDRANT_API_KEY: scripts/.qdrant-api-key.env (preferred) or legacy secrets/.secrets.env — see .qdrant-api-key.env.example
# qdrant-tls is created once; not rotated on every secrets-create.
# ============================================================================

QDRANT_TLS_SECRET="qdrant-tls"
QDRANT_API_KEY_SECRET="qdrant-api-key"
JINGRA_CREDENTIALS_SECRET="jingra-credentials"

if [[ -z "${QDRANT_API_KEY:-}" ]]; then
	echo ""
	echo "ERROR: QDRANT_API_KEY is not set."
	echo "  Add scripts/.qdrant-api-key.env (see .qdrant-api-key.env.example), or run \`make k8s-deploy\` once to create it."
	exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
	echo "ERROR: openssl is required for Qdrant TLS material"
	exit 1
fi

if kubectl get secret "$QDRANT_TLS_SECRET" --namespace="$NAMESPACE" >/dev/null 2>&1; then
	echo "✓ $QDRANT_TLS_SECRET already exists — skipping TLS regeneration (delete the secret manually to rotate)"
else
	TMP_TLS="$(mktemp -d)"
	cleanup_tls() { rm -rf "$TMP_TLS"; }
	trap cleanup_tls EXIT

	OPENSSL_CONF="$TMP_TLS/openssl.cnf"
	cat >"$OPENSSL_CONF" <<'OPENSSL_CONF_EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = qdrant-benchmark.default.svc.cluster.local

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = qdrant-benchmark.default.svc.cluster.local
DNS.2 = qdrant-benchmark.default.svc
DNS.3 = qdrant-service.default.svc.cluster.local
DNS.4 = qdrant-headless.default.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
OPENSSL_CONF_EOF

	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
		-keyout "$TMP_TLS/tls.key" -out "$TMP_TLS/tls.crt" \
		-config "$OPENSSL_CONF" -extensions v3_req

	echo "Creating Qdrant TLS secret (first time only)..."
	kubectl create secret tls "$QDRANT_TLS_SECRET" \
		--cert="$TMP_TLS/tls.crt" \
		--key="$TMP_TLS/tls.key" \
		--namespace="$NAMESPACE"
	echo "✓ Created secret: $QDRANT_TLS_SECRET"

	trap - EXIT
	cleanup_tls
fi

echo "Applying Qdrant API key secrets (upsert, stable key)..."
kubectl create secret generic "$QDRANT_API_KEY_SECRET" \
	--from-literal=api-key="$QDRANT_API_KEY" \
	--namespace="$NAMESPACE" \
	--dry-run=client -o yaml | kubectl apply -f -
echo "✓ Applied secret: $QDRANT_API_KEY_SECRET"

kubectl create secret generic "$JINGRA_CREDENTIALS_SECRET" \
	--from-literal=ENGINE_PASSWORD="$QDRANT_API_KEY" \
	--namespace="$NAMESPACE" \
	--dry-run=client -o yaml | kubectl apply -f -
echo "✓ Applied secret: $JINGRA_CREDENTIALS_SECRET"

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
