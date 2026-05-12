SHELL    := /bin/bash
REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

ENGINE_MK_FILES := $(sort $(wildcard $(REPO_ROOT)*/engine.mk))
ALL_ENGINES     := $(filter-out analyze,$(notdir $(patsubst %/engine.mk,%,$(ENGINE_MK_FILES))))
$(if $(strip $(ALL_ENGINES)),,$(error No stacks found: add <name>/engine.mk at repo root))

ENGINE  ?=
ENGINES ?=

ENGINE_TARGETS := \
	k8s-apply k8s-delete secrets-create \
	jingra-load jingra-load-stop jingra-load-logs \
	jingra-eval jingra-eval-stop jingra-eval-logs copy-query-dumps \
	status metrics logs-engine connect-ui logs-ui

-include $(REPO_ROOT)shared/secrets/.secrets.env

ifdef ENGINE

# ── Engine context (recursive invocation) ────────────────────────────────────

STACK_DIR := $(REPO_ROOT)$(ENGINE)/
ifeq ($(wildcard $(STACK_DIR)engine.mk),)
$(error Unknown engine '$(ENGINE)': missing $(STACK_DIR)engine.mk)
endif

REQUIRED_TOOLS := kubectl gcloud yq envsubst
$(foreach tool,$(REQUIRED_TOOLS),\
  $(if $(shell which $(tool)),,$(error "$(tool)" not found in PATH)))

NAMESPACE          ?= default
JINGRA_CONFIG      ?= $(STACK_DIR)jingra.yml
JINGRA_SCHEMAS_DIR ?= $(STACK_DIR)schemas
JINGRA_QUERIES_DIR ?= $(STACK_DIR)queries

include $(STACK_DIR)engine.mk

.PHONY: connect-k8s k8s-delete confirm-k8s-delete secrets-create \
	terraform-init terraform-plan terraform-apply terraform-destroy terraform-import \
	jingra-load jingra-load-stop jingra-eval jingra-eval-stop \
	status metrics logs-engine connect-ui jingra-load-logs jingra-eval-logs copy-query-dumps

# Terraform / GKE zone (single source for connect-k8s and Terraform location)

GKE_ZONE ?= us-central1-a

TF_CLI_VAR_FILES := -var-file=$(REPO_ROOT)shared/secrets/terraform.tfvars -var-file=$(REPO_ROOT)shared/variables/terraform.tfvars
TF_CLI_VARS      := -var=location=$(GKE_ZONE)

terraform-init:
	cp "$(REPO_ROOT)shared/infra/terraform/modules/gke-benchmark/gke-engine-root-variables.tf" "$(STACK_DIR)terraform/gke-engine-root-variables.tf"
	cd $(STACK_DIR)terraform && terraform init

terraform-plan: terraform-init
	cd $(STACK_DIR)terraform && terraform plan $(TF_CLI_VAR_FILES) $(TF_CLI_VARS)

terraform-apply: terraform-init
	cd $(STACK_DIR)terraform && terraform apply $(TF_CLI_VAR_FILES) $(TF_CLI_VARS)

terraform-destroy: terraform-init
	@echo >&2 "WARNING: This will delete ALL resources."
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	cd $(STACK_DIR)terraform && terraform destroy $(TF_CLI_VAR_FILES) $(TF_CLI_VARS)

terraform-import: terraform-init
	@[ -n "$${ADDR:-}" ] || { echo >&2 "ERROR: ADDR is required."; exit 1; }; \
	[ -n "$${ID:-}" ]   || { echo >&2 "ERROR: ID is required."; exit 1; }; \
	cd "$(STACK_DIR)terraform" && { \
		printf '+ terraform import %q %q\n' "$$ADDR" "$$ID"; \
		terraform import $(TF_CLI_VAR_FILES) $(TF_CLI_VARS) "$$ADDR" "$$ID"; \
	}

# Kubernetes

K8S_VARS                ?= $(REPO_ROOT)shared/variables/k8s.yml
K8S_VARS_EXTRA_SHELL    ?=
K8S_ENVSUBST_EXTRA_VARS ?=

K8S_ENVSUBST_VARS := $${workerCount} $${storageClassName} $${storageSize} $${memoryRequest} $${cpuRequest} $${memoryLimit} $${cpuLimit} $${engineVersion}

connect-k8s:
	@PROJECT_ID=$$(grep '^project_id' $(REPO_ROOT)shared/secrets/terraform.tfvars | awk -F'=' '{print $$2}' | tr -d ' "'); \
	gcloud container clusters get-credentials $(GKE_CLUSTER_NAME) --zone $(GKE_ZONE) --project $$PROJECT_ID; \
	if ! kubectl cluster-info --request-timeout=20s >/dev/null; then \
		echo >&2 "ERROR: Cannot reach the Kubernetes API."; \
		echo >&2 "  Check master authorized networks, VPN, or run:"; \
		echo >&2 "  gcloud container clusters describe $(GKE_CLUSTER_NAME) --zone $(GKE_ZONE) --project $$PROJECT_ID"; \
		exit 1; \
	fi; \
	:

define KUBECTL_APPLY_K8S_FROM_VARS
	@set -euo pipefail; \
	k8s_read_yaml_value() { \
		local key="$$1" file="$$2"; \
		[[ -f "$$file" ]] || { echo >&2 "ERROR: file not found: $$file"; exit 1; }; \
		yq ".$$key" "$$file"; \
	}; \
	K8S_VARS_FILE='$(K8S_VARS)'; \
	STACK_VERSION_FILE='$(REPO_ROOT)shared/variables/versions/.$(ENGINE)'; \
	[[ -f "$$K8S_VARS_FILE" ]]      || { echo >&2 "ERROR: K8S vars file not found: $$K8S_VARS_FILE"; exit 1; }; \
	[[ -f "$$STACK_VERSION_FILE" ]] || { echo >&2 "ERROR: version file not found: $$STACK_VERSION_FILE"; exit 1; }; \
	export storageClassName="$$( k8s_read_yaml_value storageClassName "$$K8S_VARS_FILE" )"; \
	export storageSize="$$(      k8s_read_yaml_value storageSize      "$$K8S_VARS_FILE" )"; \
	export memoryRequest="$$(    k8s_read_yaml_value memoryRequest    "$$K8S_VARS_FILE" )"; \
	export cpuRequest="$$(       k8s_read_yaml_value cpuRequest       "$$K8S_VARS_FILE" )"; \
	export memoryLimit="$$(      k8s_read_yaml_value memoryLimit      "$$K8S_VARS_FILE" )"; \
	export cpuLimit="$$(         k8s_read_yaml_value cpuLimit         "$$K8S_VARS_FILE" )"; \
	export workerCount="$$(      k8s_read_yaml_value workerCount      "$$K8S_VARS_FILE" )"; \
	engineVersion="$$(head -n1 "$$STACK_VERSION_FILE" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//')"; \
	[[ -n "$$engineVersion" && "$$engineVersion" != \#* ]] || { echo >&2 "ERROR: invalid version in $$STACK_VERSION_FILE"; exit 1; }; \
	export engineVersion; \
	$(K8S_VARS_EXTRA_SHELL) \
	[[ ! -f '$(REPO_ROOT)shared/infra/k8s/storage-class.yml' ]] || kubectl apply -f '$(REPO_ROOT)shared/infra/k8s/storage-class.yml'; \
	RENDER_DIR="$$(mktemp -d)"; \
	trap 'rm -rf "$$RENDER_DIR"' EXIT; \
	shopt -s nullglob; \
	for f in '$(STACK_DIR)k8s'/*.yaml '$(STACK_DIR)k8s'/*.yml; do \
		envsubst '$(K8S_ENVSUBST_VARS) $(K8S_ENVSUBST_EXTRA_VARS)' < "$$f" > "$$RENDER_DIR/$$(basename "$$f")"; \
	done; \
	kubectl apply -f "$$RENDER_DIR/"
endef

confirm-k8s-delete:
	@echo >&2 "WARNING: This will delete Kubernetes workloads and persistent data."
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ]

k8s-delete: connect-k8s confirm-k8s-delete k8s-delete-impl
	@[[ ! -f '$(REPO_ROOT)shared/infra/k8s/storage-class.yml' ]] || \
		kubectl delete -f '$(REPO_ROOT)shared/infra/k8s/storage-class.yml' --ignore-not-found

# Jingra

define MERGE_RUN_ID_TO_FILE
command -v yq >/dev/null 2>&1 || { echo >&2 "ERROR: yq is required"; exit 1; }; \
if [ -n "$(RUN_ID)" ]; then rid="$(RUN_ID)"; else rid="$$(yq eval '.run_id' "$(REPO_ROOT)shared/variables/benchmark.yml")"; fi; \
yq eval '$(3) = "'"$$rid"'"' "$(1)" >"$(2)"
endef

define APPLY_JINGRA_CONFIG
	@NS="$(or $(NAMESPACE),default)"; \
	TMP="$$(mktemp)"; \
	trap 'rm -f "$$TMP"' EXIT; \
	$(call MERGE_RUN_ID_TO_FILE,$(JINGRA_CONFIG),$$TMP,.evaluation.run_id); \
	kubectl create configmap jingra-config   --from-file=jingra.yaml="$$TMP"     -n "$$NS" --dry-run=client -o yaml | kubectl apply -f -; \
	kubectl create configmap jingra-schemas  --from-file="$(JINGRA_SCHEMAS_DIR)"  -n "$$NS" --dry-run=client -o yaml | kubectl apply -f -; \
	kubectl create configmap jingra-queries  --from-file="$(JINGRA_QUERIES_DIR)"  -n "$$NS" --dry-run=client -o yaml | kubectl apply -f -; \
	kubectl apply -f $(REPO_ROOT)shared/infra/k8s/jingra-datasets-pvc.yml
endef

define jingra_submit
	@[ -n "$(JINGRA_IMAGE)" ] || { echo >&2 "ERROR: JINGRA_IMAGE is required. Usage: make $(1) JINGRA_IMAGE=<ref> ENGINE=<stack>"; exit 1; }
	$(APPLY_JINGRA_CONFIG)
	@export JINGRA_IMAGE="$(JINGRA_IMAGE)"; \
	JINGRA_VER="$(strip $(JINGRA_VERSION))"; \
	[ -n "$$JINGRA_VER" ] || JINGRA_VER=$$(echo "$$JINGRA_IMAGE" | sed 's/^.*://'); \
	[ -n "$$JINGRA_VER" ] || JINGRA_VER=unknown; \
	export JINGRA_VERSION="$$JINGRA_VER"; \
	cat $(REPO_ROOT)shared/infra/k8s/jingra-$(1)-job.yml | envsubst '$${JINGRA_IMAGE} $${JINGRA_VERSION}' | kubectl apply -f -
endef

jingra-load: secrets-create connect-k8s jingra-load-stop
	$(call jingra_submit,load)

jingra-load-stop: connect-k8s
	kubectl delete job jingra-load --ignore-not-found

jingra-eval: secrets-create connect-k8s jingra-eval-stop
	$(call jingra_submit,eval)

jingra-eval-stop: connect-k8s
	kubectl delete job jingra-eval --ignore-not-found

# Secrets

ENGINE_SECRET_PREREQS     ?=
ENGINE_SOURCE_ENV         ?=
ENGINE_EXTRA_SECRETS      ?=
ENGINE_CREDENTIALS_UPSERT ?=

define JINGRA_CREDENTIALS_SHELL_FUNCTIONS
	jingra_credentials_apply_once() { \
		local pwd="$$1"; \
		kubectl create secret generic jingra-credentials \
			--from-literal=ENGINE_PASSWORD="$$pwd" \
			--namespace="$$NS" \
			--dry-run=client -o yaml | kubectl apply -f -; \
	}; \

endef

secrets-create: connect-k8s $(ENGINE_SECRET_PREREQS)
	@set -euo pipefail; \
	NS="$(or $(NAMESPACE),default)"; \
	SECRETS_ENV="$(REPO_ROOT)shared/secrets/.secrets.env"; \
	[[ ! -f "$$SECRETS_ENV" ]] || { set -a; source "$$SECRETS_ENV"; set +a; }; \
	BENCHMARK_YML="$(REPO_ROOT)shared/variables/benchmark.yml"; \
	DATASET_DATA_URL=$$(yq eval '.dataset_data_url' "$$BENCHMARK_YML"); \
	DATASET_QUERIES_URL=$$(yq eval '.dataset_queries_url' "$$BENCHMARK_YML"); \
	[[ -n "$$DATASET_DATA_URL"    && "$$DATASET_DATA_URL"    != "null" ]] || { echo >&2 "ERROR: dataset_data_url missing in $$BENCHMARK_YML"; exit 1; }; \
	[[ -n "$$DATASET_QUERIES_URL" && "$$DATASET_QUERIES_URL" != "null" ]] || { echo >&2 "ERROR: dataset_queries_url missing in $$BENCHMARK_YML"; exit 1; }; \
	$(ENGINE_SOURCE_ENV) \
	for var in DOCKER_USERNAME DOCKER_PASSWORD DOCKER_EMAIL; do \
		[[ -n "$${!var:-}" ]] || { echo >&2 "ERROR: $$var not set"; exit 1; }; \
	done; \
	kubectl delete secret regcred --namespace="$$NS" --ignore-not-found; \
	kubectl create secret docker-registry regcred \
		--docker-server="$$DOCKER_REGISTRY" \
		--docker-username="$$DOCKER_USERNAME" \
		--docker-password="$$DOCKER_PASSWORD" \
		--docker-email="$$DOCKER_EMAIL" \
		--namespace="$$NS"; \
	if [[ -n "$${RESULTS_ES_PASSWORD:-}" ]]; then \
		kubectl delete secret jingra-results-cluster --namespace="$$NS" --ignore-not-found; \
		kubectl create secret generic jingra-results-cluster \
			--from-literal=RESULTS_ES_URL="$$RESULTS_ES_URL" \
			--from-literal=RESULTS_ES_USER="$$RESULTS_ES_USER" \
			--from-literal=RESULTS_ES_PASSWORD="$$RESULTS_ES_PASSWORD" \
			--namespace="$$NS"; \
	fi; \
	$(ENGINE_EXTRA_SECRETS) \
	$(ENGINE_CREDENTIALS_UPSERT) \
	kubectl delete secret jingra-dataset-urls --namespace="$$NS" --ignore-not-found; \
	kubectl create secret generic jingra-dataset-urls \
		--from-literal=DATASET_DATA_URL="$$DATASET_DATA_URL" \
		--from-literal=DATASET_QUERIES_URL="$$DATASET_QUERIES_URL" \
		--namespace="$$NS"

# Observability

STACK_ENGINE_LABEL     ?= Engine
ENGINE_POD_SELECTOR    ?=
UI_POD_SELECTOR        ?=
SERVICE_LABEL_SELECTOR ?=
SERVICE_NAMES          ?=
ENGINE_LOG_POD_SELECTOR ?=
UI_SERVICE_NAME        ?=
UI_URL_TEMPLATE        ?=
UI_CREDENTIAL_LINES    ?=
UI_NAMESPACE           ?= $(or $(NAMESPACE),default)

status: connect-k8s
	@echo "$(STACK_ENGINE_LABEL) pods:"; \
	if [ -n "$(strip $(ENGINE_POD_SELECTOR))" ]; then \
		kubectl get pods -n "$(NAMESPACE)" -l "$(ENGINE_POD_SELECTOR)" 2>/dev/null || echo "  (none)"; \
	else \
		echo "  (not configured)"; \
	fi; \
	if [ -n "$(strip $(UI_POD_SELECTOR))" ]; then \
		echo ""; echo "UI pods:"; \
		kubectl get pods -n "$(NAMESPACE)" -l "$(UI_POD_SELECTOR)" 2>/dev/null || echo "  (none)"; \
	fi; \
	echo ""; echo "Jingra jobs:"; \
	kubectl get jobs -n "$(NAMESPACE)" jingra-load jingra-eval --ignore-not-found 2>/dev/null || echo "  (none)"; \
	echo ""; echo "Jingra pods:"; \
	kubectl get pods -n "$(NAMESPACE)" -l 'job-name in (jingra-load,jingra-eval)' 2>/dev/null || echo "  (none)"; \
	echo ""; echo "Services:"; \
	if [ -n "$(strip $(SERVICE_LABEL_SELECTOR))" ]; then \
		kubectl get svc -n "$(NAMESPACE)" -l "$(SERVICE_LABEL_SELECTOR)" 2>/dev/null || true; \
	elif [ -n "$(strip $(SERVICE_NAMES))" ]; then \
		kubectl get svc -n "$(NAMESPACE)" $(SERVICE_NAMES) 2>/dev/null || true; \
	else \
		echo "  (not configured)"; \
	fi

metrics: connect-k8s
	@kubectl top pods --all-namespaces 2>/dev/null || true
	@kubectl top nodes 2>/dev/null || true

logs-engine: connect-k8s
	@POD=$$(kubectl get pods -l "$(ENGINE_LOG_POD_SELECTOR)" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	[ -n "$$POD" ] || { echo >&2 "ERROR: No engine pods found"; exit 1; }; \
	kubectl logs -f "$$POD"

connect-ui: connect-k8s
	@[ -n "$(strip $(UI_SERVICE_NAME))" ] || { echo >&2 "ERROR: UI_SERVICE_NAME is not set"; exit 1; }; \
	[ -n "$(strip $(UI_URL_TEMPLATE))"  ] || { echo >&2 "ERROR: UI_URL_TEMPLATE is not set";  exit 1; }; \
	NS="$(UI_NAMESPACE)"; \
	EXTERNAL_IP=$$(kubectl get svc "$(UI_SERVICE_NAME)" -n "$$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$EXTERNAL_IP" ]; then \
		echo >&2 "LoadBalancer IP not ready."; \
		kubectl get svc "$(UI_SERVICE_NAME)" -n "$$NS" >&2; \
		exit 1; \
	fi; \
	eval "echo \"$(UI_URL_TEMPLATE)\""; \
	$(UI_CREDENTIAL_LINES)

define FOLLOW_JOB_LOGS
	@POD=$$(kubectl get pods -l job-name=$(1) --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	[ -n "$$POD" ] || POD=$$(kubectl get pods -l job-name=$(1) --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null); \
	[ -n "$$POD" ] || { echo >&2 "ERROR: No pods found for job $(1)"; exit 1; }; \
	if [ -n "$(LINES)" ]; then kubectl logs -f --tail=$(LINES) $$POD; else kubectl logs -f $$POD; fi
endef

jingra-load-logs: connect-k8s
	$(call FOLLOW_JOB_LOGS,jingra-load)

jingra-eval-logs: connect-k8s
	$(call FOLLOW_JOB_LOGS,jingra-eval)

copy-query-dumps: connect-k8s
	@NS="$(or $(NAMESPACE),default)"; \
	REMOTE="$(or $(QUERY_DUMP_REMOTE),/app/query-dumps/)"; \
	LOCAL="$(or $(QUERY_DUMP_LOCAL),./query-dumps)"; \
	POD="$(strip $(EVAL_POD))"; \
	[ -n "$$POD" ] || POD=$$(kubectl get pods -n "$$NS" -l job-name=jingra-eval --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo >&2 "ERROR: No Running jingra-eval pod in namespace $$NS."; \
		echo >&2 "  Set EVAL_POD=<name> or run this while eval is in progress."; \
		exit 1; \
	fi; \
	mkdir -p "$$LOCAL"; \
	kubectl cp "$$NS/$$POD:$$REMOTE" "$$LOCAL"

else

# ── Root context ──────────────────────────────────────────────────────────────

ANALYZE_DIR       := $(REPO_ROOT)analyze
ANALYZE_OUTPUT_DIR := $(ANALYZE_DIR)/output
ANALYZE_CONFIG    ?= $(ANALYZE_DIR)/jingra.yml

.PHONY: help analyze analyze-clean $(ALL_ENGINES) \
	terraform-plan terraform-apply terraform-destroy terraform-import \
	$(ENGINE_TARGETS)

.DEFAULT_GOAL := help

define MERGE_RUN_ID_TO_FILE
command -v yq >/dev/null 2>&1 || { echo >&2 "ERROR: yq is required"; exit 1; }; \
if [ -n "$(RUN_ID)" ]; then rid="$(RUN_ID)"; else rid="$$(yq eval '.run_id' "$(REPO_ROOT)shared/variables/benchmark.yml")"; fi; \
yq eval '$(3) = "'"$$rid"'"' "$(1)" >"$(2)"
endef

help:
	@echo "Vector search benchmark — run from repo root"
	@echo "============================================="
	@echo ""
	@echo "Pattern:  make <target> ENGINE=<stack>"
	@echo "Stacks:   $(ALL_ENGINES)"
	@echo ""
	@echo "Terraform:"
	@echo "  make terraform-plan    [ENGINE=<stack> | ENGINES=a,b]"
	@echo "  make terraform-apply   [ENGINE=<stack> | ENGINES=a,b]"
	@echo "  make terraform-destroy [ENGINE=<stack> | ENGINES=a,b]"
	@echo "  make terraform-import  ENGINE=<stack> ADDR='...' ID='...'"
	@echo ""
	@echo "Cluster:"
	@echo "  make k8s-apply      ENGINE=<stack>"
	@echo "  make k8s-delete     ENGINE=<stack>"
	@echo "  make secrets-create ENGINE=<stack>"
	@echo ""
	@echo "Jingra:"
	@echo "  make jingra-load      JINGRA_IMAGE=<ref> ENGINE=<stack>"
	@echo "  make jingra-load-stop                    ENGINE=<stack>"
	@echo "  make jingra-load-logs                    ENGINE=<stack>"
	@echo "  make jingra-eval      JINGRA_IMAGE=<ref> ENGINE=<stack>"
	@echo "  make jingra-eval-stop                    ENGINE=<stack>"
	@echo "  make jingra-eval-logs                    ENGINE=<stack>"
	@echo "  make copy-query-dumps                    ENGINE=<stack>"
	@echo ""
	@echo "Observability:"
	@echo "  make status      ENGINE=<stack>"
	@echo "  make metrics     ENGINE=<stack>"
	@echo "  make logs-engine ENGINE=<stack>"
	@echo "  make connect-ui  ENGINE=<stack>"
	@echo "  make logs-ui     ENGINE=<stack>"
	@echo ""
	@echo "Analysis:"
	@echo "  make analyze       JINGRA_IMAGE=<ref> [ENGINES=a,b]"
	@echo "  make analyze-clean"
	@echo ""
	@echo "Variables:"
	@echo "  ENGINE=<stack>         required for cluster / jingra / observability targets"
	@echo "  ENGINES=<csv>          stacks for analyze / terraform (default: all)"
	@echo "  JINGRA_IMAGE=<ref>     required for jingra-load, jingra-eval, analyze"
	@echo "  JINGRA_VERSION=<text>  optional; defaults to image tag after last ':'"
	@echo "  NAMESPACE=<ns>         Kubernetes namespace (default: default)"
	@echo "  LINES=<n>              tail limit for log targets"
	@echo "  GKE_ZONE=<zone>        GKE zone for connect-k8s and Terraform location (default: us-central1-a)"
	@echo "  K8S_VARS=<path>        sizing YAML override (default: shared/variables/k8s.yml)"
	@echo "  QUERY_DUMP_REMOTE=<p>  path in pod for copy-query-dumps"
	@echo "  QUERY_DUMP_LOCAL=<p>   host directory for copy-query-dumps"
	@echo "  EVAL_POD=<name>        pod override for copy-query-dumps"
	@echo "  ADDR='...' ID='...'    required for terraform-import"
	@echo "  ANALYZE_CONFIG=<path>  config override (default: analyze/jingra.yml)"
	@echo ""

analyze-clean:
	@rm -rf "$(ANALYZE_OUTPUT_DIR)"

$(ANALYZE_OUTPUT_DIR):
	@mkdir -p "$@"

analyze: analyze-clean | $(ANALYZE_OUTPUT_DIR)
	@set -euo pipefail; \
	if [ -f "$(REPO_ROOT)shared/secrets/.secrets.env" ]; then \
		set -a; source "$(REPO_ROOT)shared/secrets/.secrets.env"; set +a; \
	fi; \
	for var in RESULTS_ES_URL RESULTS_ES_USER RESULTS_ES_PASSWORD JINGRA_IMAGE; do \
		[ -n "$${!var:-}" ] || { echo >&2 "ERROR: $$var not set"; exit 1; }; \
	done; \
	TMP="$$(mktemp)"; \
	trap 'rm -f "$$TMP"' EXIT; \
	$(call MERGE_RUN_ID_TO_FILE,$(ANALYZE_CONFIG),$$TMP,.analysis.run_id); \
	if [ -n "$(strip $(ENGINES))" ]; then \
		engines_csv='$(subst ','\'',$(strip $(ENGINES)))'; \
	else \
		engines_csv=$$(echo '$(strip $(ALL_ENGINES))' | tr ' ' ','); \
	fi; \
	export _ENGINES_CSV_YQ="$$engines_csv"; \
	yq eval '.analysis.engines = (strenv(_ENGINES_CSV_YQ) | split(",") | map(trim))' "$$TMP" > "$$TMP.eng" && mv "$$TMP.eng" "$$TMP"; \
	unset _ENGINES_CSV_YQ; \
	VERSIONS_DIR="$(REPO_ROOT)shared/variables/versions"; \
	while IFS= read -r engine; do \
		vfile="$$VERSIONS_DIR/.$$engine"; \
		[[ -f "$$vfile" ]] || { echo >&2 "ERROR: version file not found: $$vfile"; exit 1; }; \
		version="$$(head -n1 "$$vfile" | tr -d '[:space:]')"; \
		TMP2="$$(mktemp)"; \
		yq eval ".analysis.engine_versions.$$engine = \"$$version\"" "$$TMP" > "$$TMP2" && mv "$$TMP2" "$$TMP"; \
	done < <(yq eval '.analysis.engines[]' "$$TMP"); \
	docker run --rm \
		-v "$$TMP:/config/jingra.yml:ro" \
		-v "$(ANALYZE_OUTPUT_DIR):/output" \
		-e RESULTS_ES_URL \
		-e RESULTS_ES_USER \
		-e RESULTS_ES_PASSWORD \
		"$(JINGRA_IMAGE)" \
		analyze /config/jingra.yml

terraform-plan terraform-apply terraform-destroy:
ifdef ENGINE
	$(MAKE) --no-print-directory ENGINE=$(ENGINE) $@
else
	@set -euo pipefail; \
	if [ -n "$(ENGINES)" ]; then IFS=',' read -ra stacks <<< "$(ENGINES)"; else stacks=($(ALL_ENGINES)); fi; \
	for s in "$${stacks[@]}"; do \
		$(MAKE) --no-print-directory ENGINE=$$s $@; \
	done
endif

terraform-import:
ifndef ENGINE
	@echo >&2 "ERROR: ENGINE=<stack> is required for terraform-import." && exit 1
else
	@[ -n "$${ADDR:-}" ] || { echo >&2 "ERROR: ADDR is required."; exit 1; }; \
	[ -n "$${ID:-}" ]   || { echo >&2 "ERROR: ID is required."; exit 1; }
	$(MAKE) --no-print-directory ENGINE=$(ENGINE) $@
endif

$(ENGINE_TARGETS):
	@[ -n "$(ENGINE)" ] || { \
		echo >&2 "ERROR: ENGINE=<stack> is required. Usage: make $@ ENGINE=<stack>"; \
		echo >&2 "Stacks: $(ALL_ENGINES)"; \
		exit 1; \
	}
	@$(MAKE) --no-print-directory ENGINE=$(ENGINE) $@

$(ALL_ENGINES):
	@echo >&2 "ERROR: Use: make <target> ENGINE=$@  (e.g. make k8s-apply ENGINE=$@)"
	@exit 1

endif
