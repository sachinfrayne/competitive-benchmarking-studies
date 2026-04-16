.PHONY: help terraform-init terraform-plan terraform-apply terraform-destroy \
        k8s-deploy k8s-delete secrets-create \
        jingra-load jingra-load-stop logs-load \
        jingra-eval jingra-eval-stop logs-eval logs-eval-head copy-query-dumps \
        status metrics logs-engine logs-ui \
        connect-k8s connect-ui

# Variables
# JINGRA_IMAGE must be provided by the user (no default). Optional: JINGRA_VERSION for pod env (defaults to suffix after last ':' in the image).

# Default target
help:
	@echo "Elasticsearch GCP Benchmark - Available Commands"
	@echo "================================================="
	@echo ""
	@echo "Terraform Infrastructure:"
	@echo "  make terraform-init       Initialize Terraform"
	@echo "  make terraform-plan       Plan Terraform changes"
	@echo "  make terraform-apply      Apply Terraform (create infrastructure)"
	@echo "  make terraform-destroy    Destroy all infrastructure"
	@echo ""
	@echo "Kubernetes Deployment:"
	@echo "  make k8s-deploy           Create secrets then deploy Elasticsearch + Kibana"
	@echo "  make k8s-delete           Delete Elasticsearch + Kibana"
	@echo "  make secrets-create       Sync secrets/.secrets.env to Kubernetes"
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
	@echo "  make logs-ui              Tail UI logs"
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

k8s-deploy: secrets-create
	@echo "🚀 Deploying Elasticsearch cluster..."
	@echo ""
	@echo "1️⃣  GKE credentials (refreshed by connect-k8s before secrets-create)"
	@echo ""
	@echo "2️⃣  Checking for ECK CRDs..."
	@CRD_EXISTS=$$(kubectl get crd elasticsearches.elasticsearch.k8s.elastic.co --ignore-not-found); \
	if [ -z "$$CRD_EXISTS" ]; then \
		echo "   Installing ECK CRDs..."; \
		kubectl create -f https://download.elastic.co/downloads/eck/3.1.0/crds.yaml; \
	else \
		echo "   ✓ ECK CRDs already installed"; \
	fi
	@echo ""
	@echo "3️⃣  Checking for ECK Operator..."
	@OPERATOR_EXISTS=$$(kubectl get po -n elastic-system --no-headers 2>/dev/null | grep '^elastic-operator' || true); \
	if [ -z "$$OPERATOR_EXISTS" ]; then \
		echo "   Installing ECK Operator..."; \
		kubectl apply -f https://download.elastic.co/downloads/eck/3.1.0/operator.yaml; \
		echo "   Waiting for operator to be ready..."; \
		kubectl wait --for=condition=ready pod -l control-plane=elastic-operator -n elastic-system --timeout=120s || true; \
	else \
		echo "   ✓ ECK Operator already running"; \
	fi
	@echo ""
	@echo "4️⃣  Deploying Elasticsearch + Kibana..."
	kubectl apply -f k8s/cluster.yml
	@echo ""
	@echo "⏳ Waiting for Elasticsearch to be ready (this may take 5-10 minutes)..."
	@echo "   - Waiting for Elasticsearch pods to be ready..."
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=elasticsearch --timeout=600s || true
	@echo "   - Waiting for Kibana pods to be ready..."
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=kibana --timeout=600s || true
	@echo ""
	@echo "✅ Elasticsearch cluster deployed!"
	@echo ""
	@$(MAKE) status

k8s-delete: connect-k8s
	@echo "🗑️  Deleting Elasticsearch cluster..."
	kubectl delete -f k8s/cluster.yml --ignore-not-found
	@echo "✅ Elasticsearch cluster deleted"

secrets-create: connect-k8s
	@echo "🔐 Syncing Kubernetes secrets from secrets/.secrets.env"
	cd scripts && ./create-k8s-secrets.sh
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
	kubectl create configmap jingra-schemas --from-file=wiki_dpr_e5_768_knn.json=schemas/wiki_dpr_e5_768_knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-queries --from-file=wiki_dpr_e5_768_knn.json=queries/wiki_dpr_e5_768_knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
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
	kubectl create configmap jingra-schemas --from-file=wiki_dpr_e5_768_knn.json=schemas/wiki_dpr_e5_768_knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
	kubectl create configmap jingra-queries --from-file=wiki_dpr_e5_768_knn.json=queries/wiki_dpr_e5_768_knn.json -n default --dry-run=client -o yaml | kubectl apply -f -
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
	@echo "   Copy query JSON (while Running): make copy-query-dumps"

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
	@echo "Elasticsearch Pods:"
	@kubectl get pods -l common.k8s.elastic.co/type=elasticsearch 2>/dev/null || echo "  No Elasticsearch pods found"
	@echo ""
	@echo "Kibana Pods:"
	@kubectl get pods -l common.k8s.elastic.co/type=kibana 2>/dev/null || echo "  No Kibana pods found"
	@echo ""
	@echo "Jingra Jobs:"
	@kubectl get jobs -l app=jingra 2>/dev/null || echo "  No Jingra jobs found"
	@echo ""
	@echo "Jingra Pods:"
	@kubectl get pods -l app=jingra 2>/dev/null || echo "  No Jingra pods found"
	@echo ""
	@echo "Services:"
	@kubectl get svc -l common.k8s.elastic.co/type=elasticsearch 2>/dev/null || true
	@kubectl get svc -l common.k8s.elastic.co/type=kibana 2>/dev/null || true

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
	echo "🔗 Refreshing GKE credentials (elasticsearch-benchmark)..."; \
	gcloud container clusters get-credentials elasticsearch-benchmark \
		--zone us-central1-a --project $$PROJECT_ID; \
	if ! kubectl cluster-info --request-timeout=20s >/dev/null; then \
		echo ""; \
		echo "❌ Cannot reach the Kubernetes API (timeout or connection failed)."; \
		echo "   Typical causes: master authorized networks (add this machine's public IP),"; \
		echo "   private GKE control plane without VPN, or offline/restrictive network."; \
		echo "   Try: gcloud container clusters describe elasticsearch-benchmark --zone us-central1-a --project $$PROJECT_ID"; \
		exit 1; \
	fi; \
	echo "✅ kubectl context: $$(kubectl config current-context)"

connect-ui: connect-k8s
	@echo "🔗 Getting UI connection info..."
	@echo ""
	@ENGINE_PASSWORD=$$(kubectl get secret jingra-credentials -n default -o jsonpath='{.data.ENGINE_PASSWORD}' 2>/dev/null | base64 -d); \
	if [ -z "$$ENGINE_PASSWORD" ]; then ENGINE_PASSWORD=$$(kubectl get secret es-cluster-es-elastic-user -n default -o go-template='{{.data.elastic | base64decode}}{{"\n"}}' 2>/dev/null); fi; \
	EXTERNAL_IP=$$(kubectl get svc es-cluster-kb-http -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$EXTERNAL_IP" ]; then \
		echo "⚠️  UI LoadBalancer IP not ready yet. Checking status..."; \
		kubectl get svc es-cluster-kb-http -n default; \
		exit 1; \
	fi; \
	echo "=== UI Connection Info ==="; \
	echo "URL:      https://$$EXTERNAL_IP:5601"; \
	echo "Username: elastic"; \
	echo "Password: $$ENGINE_PASSWORD"; \
	echo ""; \
	echo "💡 Note: You may need to accept the self-signed certificate"

# ============================================================================
# Status & Logs
# ============================================================================

logs-engine: connect-k8s
	@echo "📜 Tailing engine logs (Ctrl+C to exit)..."
	@POD=$$(kubectl get pods -l common.k8s.elastic.co/type=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "❌ No engine pods found"; \
		exit 1; \
	fi; \
	kubectl logs -f $$POD

logs-ui: connect-k8s
	@echo "📜 Tailing UI logs (Ctrl+C to exit)..."
	@POD=$$(kubectl get pods -l common.k8s.elastic.co/type=kibana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "❌ No UI pods found"; \
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
# Typical: run in a second terminal while `make jingra-eval` is active, or race before the job finishes.
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
