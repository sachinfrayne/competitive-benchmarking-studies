.PHONY: help terraform-init terraform-plan terraform-apply terraform-destroy \
        k8s-deploy k8s-delete secrets-create ensure-qdrant-api-key-in-env \
        jingra-load jingra-load-stop logs-load \
        jingra-eval jingra-eval-stop logs-eval logs-eval-head copy-query-dumps \
        status metrics logs-engine \
        connect-k8s connect-ui

SHELL := /bin/bash

STACK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)/..)

# Variables
# JINGRA_IMAGE must be provided by the user (no default). Optional: JINGRA_VERSION for pod env (defaults to suffix after last ':' in the image).

# Default target
help:
	@echo "Qdrant GCP Benchmark - Available Commands"
	@echo "=========================================="
	@echo ""
	@echo "Terraform Infrastructure:"
	@echo "  make terraform-init       Initialize Terraform"
	@echo "  make terraform-plan       Plan Terraform changes"
	@echo "  make terraform-apply      Apply Terraform (create infrastructure)"
	@echo "  make terraform-destroy    Destroy all infrastructure"
	@echo ""
	@echo "Kubernetes Deployment:"
	@echo "  make k8s-deploy           Create .qdrant-api-key.env if missing, then secrets + cluster"
	@echo "  make k8s-delete           Delete Qdrant cluster"
	@echo "  make secrets-create       Sync secrets/.secrets.env + .qdrant-api-key.env to Kubernetes (TLS kept if exists)"
	@echo ""
	@echo "Data Loading:"
	@echo "  make jingra-load          Load data (~7-12 minutes for 20M docs)"
	@echo "  make jingra-load-stop     Stop load job"
	@echo "  make logs-load            Tail load job logs"
	@echo ""
	@echo "Evaluation:"
	@echo "  make jingra-eval          Run evaluation benchmarks"
	@echo "  make jingra-eval-stop     Stop evaluation job"
	@echo "  make logs-eval            Tail evaluation job logs"
	@echo "  make logs-eval-head       Show first 100 lines of eval logs (use LINES=N for custom)"
	@echo "  make copy-query-dumps     Copy /app/query-dumps from a Running eval pod to ./query-dumps (run while eval runs)"
	@echo ""
	@echo "Variables:"
	@echo "  JINGRA_IMAGE=<ref>        Full Jingra container image (REQUIRED)"
	@echo "  JINGRA_VERSION=<text>     Optional; JINGRA_VERSION env in pod (default: tag after last ':' in image)"
	@echo "                            Example: make jingra-load JINGRA_IMAGE=registry.example.com/jingra:36"
	@echo "  LINES=<number>            Limit log output (optional)"
	@echo "                            Example: make logs-load LINES=100"
	@echo "  NAMESPACE=<ns>            Kubernetes namespace (default: default)"
	@echo "  QUERY_DUMP_REMOTE=<path> Path in pod (default: /app/query-dumps/)"
	@echo "  QUERY_DUMP_LOCAL=<path>  Destination dir on this machine (default: ./query-dumps)"
	@echo "  EVAL_POD=<name>           Eval pod name (optional; default: Running jingra-eval pod)"
	@echo ""
	@echo "Status & Logs:"
	@echo "  make status               Show status of all components"
	@echo "  make metrics              Show CPU/RAM metrics for all pods"
	@echo "  make logs-engine          Tail engine logs"
	@echo ""
	@echo "Access:"
	@echo "  make connect-k8s          Connect to GKE cluster"
	@echo "  make connect-ui           Get UI credentials and access info"
	@echo ""

# ============================================================================
# Terraform Targets
# ============================================================================

terraform-init:
	@echo "🔧 Initializing Terraform..."
	cd terraform && terraform init

terraform-plan:
	@echo "📋 Planning Terraform changes..."
	cd terraform && terraform plan -var-file=../../secrets/terraform.tfvars

terraform-apply:
	@echo "🚀 Applying Terraform (creating infrastructure)..."
	cd terraform && terraform apply -var-file=../../secrets/terraform.tfvars

terraform-destroy:
	@echo "💣 Destroying infrastructure..."
	@echo "⚠️  This will delete ALL resources!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	cd terraform && terraform destroy -var-file=../../secrets/terraform.tfvars

# ============================================================================
# Kubernetes Deployment
# ============================================================================

ensure-qdrant-api-key-in-env:
	@set -euo pipefail; \
	GENERAL_SECRETS="$(REPO_ROOT)/secrets/.secrets.env"; \
	QDRANT_KEY_FILE="$(STACK_DIR).qdrant-api-key.env"; \
	if [[ ! -f "$$GENERAL_SECRETS" ]]; then \
		echo "ERROR: $$GENERAL_SECRETS not found."; \
		echo "  cp secrets/.secrets.env.example secrets/.secrets.env  and fill Docker + dataset values first."; \
		exit 1; \
	fi; \
	if [[ -f "$$QDRANT_KEY_FILE" ]] && grep -qE '^QDRANT_API_KEY=[^[:space:]]+' "$$QDRANT_KEY_FILE" 2>/dev/null; then \
		echo "✓ QDRANT_API_KEY already set in .qdrant-api-key.env"; \
		exit 0; \
	fi; \
	if grep -qE '^QDRANT_API_KEY=[^[:space:]]+' "$$GENERAL_SECRETS" 2>/dev/null; then \
		echo "Migrating QDRANT_API_KEY from secrets/.secrets.env → .qdrant-api-key.env ..."; \
		grep -E '^QDRANT_API_KEY=' "$$GENERAL_SECRETS" > "$$QDRANT_KEY_FILE"; \
		echo "✓ Wrote $$QDRANT_KEY_FILE (you may remove the QDRANT_API_KEY line from secrets/.secrets.env)"; \
		exit 0; \
	fi; \
	if ! command -v openssl >/dev/null 2>&1; then \
		echo "ERROR: openssl is required to generate QDRANT_API_KEY"; \
		exit 1; \
	fi; \
	KEY="$$(openssl rand -hex 32)"; \
	{ \
		echo "# Qdrant API key — synced to Kubernetes by make secrets-create"; \
		echo "# (generated by make ensure-qdrant-api-key-in-env; rotate with cluster if you rotate secrets)"; \
		echo "QDRANT_API_KEY=$$KEY"; \
	} > "$$QDRANT_KEY_FILE"; \
	echo "✓ Created $$QDRANT_KEY_FILE (first k8s-deploy for this workspace)"

k8s-deploy: ensure-qdrant-api-key-in-env secrets-create
	@echo "🚀 Deploying Qdrant cluster..."
	@echo ""
	@echo "📦 Applying StatefulSet and services..."
	kubectl apply -f k8s-cluster.yml
	@echo ""
	@echo "⏳ Waiting for Qdrant to be ready (this may take 5-10 minutes)..."
	@echo "   - Waiting for Qdrant pods to be ready..."
	kubectl wait --for=condition=ready pod -l app=qdrant --timeout=600s || true
	@echo ""
	@echo "✅ Qdrant cluster deployed!"
	@echo ""
	@$(MAKE) status

k8s-delete: connect-k8s
	@echo "🗑️  Deleting Qdrant cluster..."
	kubectl delete -f k8s-cluster.yml --ignore-not-found
	@echo "✅ Qdrant cluster deleted"

secrets-create: connect-k8s
	@echo "🔐 Syncing Kubernetes secrets from secrets/.secrets.env and .qdrant-api-key.env..."
	@set -euo pipefail; \
	NAMESPACE=default; \
	SECRETS_ENV="$(REPO_ROOT)/secrets/.secrets.env"; \
	QDRANT_KEY="$(STACK_DIR).qdrant-api-key.env"; \
	if [[ -f "$$SECRETS_ENV" ]]; then \
		echo "Loading credentials from $$SECRETS_ENV..."; \
		set -a; source "$$SECRETS_ENV"; set +a; \
	else \
		echo "Note: $$SECRETS_ENV not found. Using environment variables only."; \
		echo "To use secrets file: cp secrets/.secrets.env.example secrets/.secrets.env (then edit it)"; \
		echo ""; \
	fi; \
	if [[ -f "$$QDRANT_KEY" ]]; then \
		echo "Loading Qdrant API key from $$QDRANT_KEY..."; \
		set -a; source "$$QDRANT_KEY"; set +a; \
	fi; \
	if [[ -z "$${DOCKER_USERNAME:-}" ]]; then echo "ERROR: DOCKER_USERNAME not set"; exit 1; fi; \
	if [[ -z "$${DOCKER_PASSWORD:-}" ]]; then echo "ERROR: DOCKER_PASSWORD not set"; exit 1; fi; \
	if [[ -z "$${DOCKER_EMAIL:-}" ]]; then echo "ERROR: DOCKER_EMAIL not set"; exit 1; fi; \
	echo "Creating docker registry secret..."; \
	kubectl delete secret regcred --namespace="$$NAMESPACE" --ignore-not-found; \
	kubectl create secret docker-registry regcred \
		--docker-server="$$DOCKER_REGISTRY" \
		--docker-username="$$DOCKER_USERNAME" \
		--docker-password="$$DOCKER_PASSWORD" \
		--docker-email="$$DOCKER_EMAIL" \
		--namespace="$$NAMESPACE"; \
	echo "✓ Created secret: regcred"; \
	if [[ -z "$${QDRANT_API_KEY:-}" ]]; then \
		echo ""; echo "ERROR: QDRANT_API_KEY is not set."; \
		echo "  Add qdrant-gcp/.qdrant-api-key.env (see .qdrant-api-key.env.example), or run \`make k8s-deploy\` once to create it."; \
		exit 1; \
	fi; \
	command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl is required for Qdrant TLS material"; exit 1; }; \
	if kubectl get secret qdrant-tls --namespace="$$NAMESPACE" >/dev/null 2>&1; then \
		echo "✓ qdrant-tls already exists — skipping TLS regeneration (delete the secret manually to rotate)"; \
	else \
		TMP_TLS=$$(mktemp -d); \
		trap 'rm -rf "$$TMP_TLS"' EXIT; \
		{ echo '[req]'; echo 'distinguished_name = req_distinguished_name'; echo 'req_extensions = v3_req'; echo 'prompt = no'; echo ''; \
		  echo '[req_distinguished_name]'; echo 'CN = qdrant-benchmark.default.svc.cluster.local'; echo ''; \
		  echo '[v3_req]'; echo 'basicConstraints = CA:FALSE'; echo 'keyUsage = digitalSignature, keyEncipherment'; \
		  echo 'extendedKeyUsage = serverAuth'; echo 'subjectAltName = @alt_names'; echo ''; \
		  echo '[alt_names]'; echo 'DNS.1 = qdrant-benchmark.default.svc.cluster.local'; \
		  echo 'DNS.2 = qdrant-benchmark.default.svc'; echo 'DNS.3 = qdrant-service.default.svc.cluster.local'; \
		  echo 'DNS.4 = qdrant-headless.default.svc.cluster.local'; echo 'DNS.5 = localhost'; echo 'IP.1 = 127.0.0.1'; \
		} > "$$TMP_TLS/openssl.cnf"; \
		openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
			-keyout "$$TMP_TLS/tls.key" -out "$$TMP_TLS/tls.crt" \
			-config "$$TMP_TLS/openssl.cnf" -extensions v3_req; \
		echo "Creating Qdrant TLS secret (first time only)..."; \
		kubectl create secret tls qdrant-tls \
			--cert="$$TMP_TLS/tls.crt" \
			--key="$$TMP_TLS/tls.key" \
			--namespace="$$NAMESPACE"; \
		echo "✓ Created secret: qdrant-tls"; \
		trap - EXIT; \
		rm -rf "$$TMP_TLS"; \
	fi; \
	echo "Applying Qdrant API key secrets (upsert, stable key)..."; \
	kubectl create secret generic qdrant-api-key \
		--from-literal=api-key="$$QDRANT_API_KEY" \
		--namespace="$$NAMESPACE" \
		--dry-run=client -o yaml | kubectl apply -f -; \
	echo "✓ Applied secret: qdrant-api-key"; \
	kubectl create secret generic jingra-credentials \
		--from-literal=ENGINE_PASSWORD="$$QDRANT_API_KEY" \
		--namespace="$$NAMESPACE" \
		--dry-run=client -o yaml | kubectl apply -f -; \
	echo "✓ Applied secret: jingra-credentials"; \
	if [[ -n "$${RESULTS_ES_PASSWORD:-}" ]]; then \
		echo "Creating results cluster secret..."; \
		kubectl delete secret jingra-results-cluster --namespace="$$NAMESPACE" --ignore-not-found; \
		kubectl create secret generic jingra-results-cluster \
			--from-literal=RESULTS_ES_URL="$$RESULTS_ES_URL" \
			--from-literal=RESULTS_ES_USER="$$RESULTS_ES_USER" \
			--from-literal=RESULTS_ES_PASSWORD="$$RESULTS_ES_PASSWORD" \
			--namespace="$$NAMESPACE"; \
		echo "✓ Created secret: jingra-results-cluster"; \
	else \
		echo "Note: RESULTS_ES_PASSWORD not set, skipping results cluster secret"; \
	fi; \
	echo "Creating dataset URLs secret..."; \
	kubectl delete secret jingra-dataset-urls --namespace="$$NAMESPACE" --ignore-not-found; \
	kubectl create secret generic jingra-dataset-urls \
		--from-literal=DATASET_DATA_URL="$$DATASET_DATA_URL" \
		--from-literal=DATASET_QUERIES_URL="$$DATASET_QUERIES_URL" \
		--namespace="$$NAMESPACE"; \
	echo "✓ Created secret: jingra-dataset-urls"; \
	echo ""; \
	echo "✅ All secrets created successfully!"
	@echo "✅ Secrets synced"

# ============================================================================
# Data Loading
# ============================================================================

jingra-load: secrets-create connect-k8s jingra-load-stop
	@if [ -z "$(JINGRA_IMAGE)" ]; then \
		echo "❌ ERROR: JINGRA_IMAGE is required but not set"; \
		echo "   Usage: make jingra-load JINGRA_IMAGE=<registry>/<repo>:<tag>"; \
		exit 1; \
	fi
	@echo "⚡ Starting data load..."
	@echo "   1. Applying Jingra config..."
	kubectl create configmap jingra-config --from-file=jingra.yaml=jingra.yml -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-schemas --from-file=wiki-dpr-es-768-knn.json=schemas/wiki-dpr-es-768-knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-queries --from-file=wiki-dpr-es-768-knn.json=queries/wiki-dpr-es-768-knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f ../k8s/jingra-datasets-pvc.yml
	@echo "   2. Starting load job..."
	@export JINGRA_IMAGE="$(JINGRA_IMAGE)"; \
	JINGRA_VER="$(strip $(JINGRA_VERSION))"; \
	if [ -z "$$JINGRA_VER" ]; then JINGRA_VER=$$(echo "$$JINGRA_IMAGE" | sed 's/^.*://'); fi; \
	if [ -z "$$JINGRA_VER" ]; then JINGRA_VER=unknown; fi; \
	export JINGRA_VERSION="$$JINGRA_VER"; \
	cat ../k8s/jingra-load-job.yml | envsubst '$${JINGRA_IMAGE} $${JINGRA_VERSION}' | kubectl apply -f -
	@echo ""
	@echo "✅ Load job started (image: $(JINGRA_IMAGE))"
	@echo "   Monitor: make logs-load"
	@echo "   Stop:    make jingra-load-stop"

jingra-load-stop: connect-k8s
	@echo "🛑 Stopping load job..."
	kubectl delete job jingra-load --ignore-not-found
	@echo "   Waiting for job to terminate..."
	@sleep 2
	@echo "✅ Load job stopped"

# ============================================================================
# Jingra Evaluation (Benchmarking)
# ============================================================================

jingra-eval: secrets-create connect-k8s jingra-eval-stop
	@if [ -z "$(JINGRA_IMAGE)" ]; then \
		echo "❌ ERROR: JINGRA_IMAGE is required but not set"; \
		echo "   Usage: make jingra-eval JINGRA_IMAGE=<registry>/<repo>:<tag>"; \
		exit 1; \
	fi
	@echo "📊 Starting Jingra evaluation (image: $(JINGRA_IMAGE))..."
	@echo "   1. Applying Jingra config..."
	kubectl create configmap jingra-config --from-file=jingra.yaml=jingra.yml -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-schemas --from-file=wiki-dpr-es-768-knn.json=schemas/wiki-dpr-es-768-knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-queries --from-file=wiki-dpr-es-768-knn.json=queries/wiki-dpr-es-768-knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f ../k8s/jingra-datasets-pvc.yml
	@echo "   2. Starting eval job..."
	@export JINGRA_IMAGE="$(JINGRA_IMAGE)"; \
	JINGRA_VER="$(strip $(JINGRA_VERSION))"; \
	if [ -z "$$JINGRA_VER" ]; then JINGRA_VER=$$(echo "$$JINGRA_IMAGE" | sed 's/^.*://'); fi; \
	if [ -z "$$JINGRA_VER" ]; then JINGRA_VER=unknown; fi; \
	export JINGRA_VERSION="$$JINGRA_VER"; \
	cat ../k8s/jingra-eval-job.yml | envsubst '$${JINGRA_IMAGE} $${JINGRA_VERSION}' | kubectl apply -f -
	@echo ""
	@echo "✅ Eval job started (image: $(JINGRA_IMAGE))"
	@echo "   Monitor: make logs-eval"
	@echo "   Stop:    make jingra-eval-stop"
	@echo "   Query JSON (while Running): make copy-query-dumps"

jingra-eval-stop: connect-k8s
	@echo "🛑 Stopping any existing eval job..."
	kubectl delete job jingra-eval --ignore-not-found
	@echo "   Waiting for job to terminate..."
	@sleep 2
	@echo "✅ Eval job stopped"

# ============================================================================
# Status & Logs
# ============================================================================

status: connect-k8s
	@echo "📊 Component Status"
	@echo "==================="
	@echo ""
	@echo "Qdrant Pods:"
	@kubectl get pods -l app=qdrant 2>/dev/null || echo "  No Qdrant pods found"
	@echo ""
	@echo "Jingra Jobs:"
	@kubectl get jobs -l app=jingra 2>/dev/null || echo "  No Jingra jobs found"
	@echo ""
	@echo "Jingra Pods:"
	@kubectl get pods -l app=jingra 2>/dev/null || echo "  No Jingra pods found"
	@echo ""
	@echo "Services:"
	@kubectl get svc qdrant-service qdrant-benchmark qdrant-headless 2>/dev/null || true

metrics: connect-k8s
	@echo "📊 Resource Metrics"
	@echo "==================="
	@echo ""
	@echo "Pod Metrics (CPU/Memory):"
	@kubectl top pods --all-namespaces 2>/dev/null || echo "  ⚠️  Metrics server not available or pods not ready"
	@echo ""
	@echo "Node Metrics:"
	@kubectl top nodes 2>/dev/null || echo "  ⚠️  Metrics server not available"

# ============================================================================
# Access
# ============================================================================

connect-k8s:
	@PROJECT_ID=$$(grep '^project_id' ../secrets/terraform.tfvars | awk -F'=' '{print $$2}' | tr -d ' "'); \
	echo "🔗 Refreshing GKE credentials (qdrant-benchmark)..."; \
	gcloud container clusters get-credentials qdrant-benchmark \
		--zone us-central1-a --project $$PROJECT_ID; \
	if ! kubectl cluster-info --request-timeout=20s >/dev/null; then \
		echo ""; \
		echo "❌ Cannot reach the Kubernetes API (timeout or connection failed)."; \
		echo "   Typical causes: master authorized networks (add this machine's public IP),"; \
		echo "   private GKE control plane without VPN, or offline/restrictive network."; \
		echo "   Try: gcloud container clusters describe qdrant-benchmark --zone us-central1-a --project $$PROJECT_ID"; \
		exit 1; \
	fi; \
	echo "✅ kubectl context: $$(kubectl config current-context)"

connect-ui: connect-k8s
	@echo "🔗 Getting UI connection info..."
	@echo ""
	@ENGINE_PASSWORD=$$(kubectl get secret jingra-credentials -n default -o jsonpath='{.data.ENGINE_PASSWORD}' 2>/dev/null | base64 -d); \
	EXTERNAL_IP=$$(kubectl get svc qdrant-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$EXTERNAL_IP" ]; then \
		echo "⚠️  LoadBalancer IP not ready yet. Checking status..."; \
		kubectl get svc qdrant-service; \
		exit 1; \
	fi; \
	echo "=== UI Connection Info ==="; \
	echo "URL:      https://$$EXTERNAL_IP:6333/dashboard"; \
	echo "API key:  $$ENGINE_PASSWORD"; \
	echo ""; \
	echo "💡 Note: You may need to accept the self-signed certificate"

# ============================================================================
# Status & Logs
# ============================================================================

logs-engine: connect-k8s
	@echo "📜 Tailing Qdrant logs (Ctrl+C to exit)..."
	@POD=$$(kubectl get pods -l app=qdrant -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "❌ No Qdrant pods found"; \
		exit 1; \
	fi; \
	kubectl logs -f $$POD

logs-load: connect-k8s
	@echo "📜 Tailing load job logs (Ctrl+C to exit)..."
	@POD=$$(kubectl get pods -l job-name=jingra-load --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "⚠️  No running load job found. Showing logs from last run:"; \
		POD=$$(kubectl get pods -l job-name=jingra-load --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null); \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ No load job pods found"; \
		exit 1; \
	fi; \
	if [ -n "$(LINES)" ]; then \
		kubectl logs -f --tail=$(LINES) $$POD; \
	else \
		kubectl logs -f $$POD; \
	fi

logs-eval: connect-k8s
	@echo "📜 Tailing Jingra eval job logs (Ctrl+C to exit)..."
	@POD=$$(kubectl get pods -l job-name=jingra-eval --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "⚠️  No running eval job found. Showing logs from last run:"; \
		POD=$$(kubectl get pods -l job-name=jingra-eval --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null); \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ No eval job pods found"; \
		exit 1; \
	fi; \
	if [ -n "$(LINES)" ]; then \
		kubectl logs -f --tail=$(LINES) $$POD; \
	else \
		kubectl logs -f $$POD; \
	fi

logs-eval-head: connect-k8s
	@echo "📜 Showing first $(or $(LINES),100) lines of eval job logs..."
	@POD=$$(kubectl get pods -l job-name=jingra-eval --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "❌ No eval job pods found"; \
		exit 1; \
	fi; \
	kubectl logs $$POD --tail=-1 | head -n $(or $(LINES),100)

# Copy first-query JSON dumps from the eval pod to this machine.
# Requires a *Running* eval pod (kubectl cp cannot exec into Completed pods).
copy-query-dumps: connect-k8s
	@NS="$(or $(NAMESPACE),default)"; \
	REMOTE="$(or $(QUERY_DUMP_REMOTE),/app/query-dumps/)"; \
	LOCAL="$(or $(QUERY_DUMP_LOCAL),./query-dumps)"; \
	POD="$(strip $(EVAL_POD))"; \
	if [ -z "$$POD" ]; then \
		POD=$$(kubectl get pods -n "$$NS" -l job-name=jingra-eval --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	fi; \
	if [ -z "$$POD" ]; then \
		echo "❌ No Running jingra-eval pod in namespace $$NS."; \
		echo "   kubectl cp needs the eval container running; Completed pods cannot be copied."; \
		echo "   Run \`make copy-query-dumps\` in another terminal while eval is in progress,"; \
		echo "   or set EVAL_POD to a currently Running pod: kubectl get pods -l job-name=jingra-eval"; \
		exit 1; \
	fi; \
	mkdir -p "$$LOCAL"; \
	echo "📋 Copying $$NS/$$POD:$$REMOTE → $$LOCAL"; \
	kubectl cp "$$NS/$$POD:$$REMOTE" "$$LOCAL"
