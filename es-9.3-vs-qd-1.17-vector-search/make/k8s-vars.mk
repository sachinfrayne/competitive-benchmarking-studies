# Renders engines/$(STACK)/k8s/*.yaml with sizing from K8S_VARS, then kubectl apply.
# Reads K8S_VARS via scripts/k8s-read-yaml-value.sh: prefers yq (mikefarah v4), else Ruby YAML, else Python 3.
# Requires: envsubst (gettext).
# Only substitutes known keys from variables/k8s.yml so other ${...} (e.g. ${HOSTNAME} in ConfigMaps) is untouched.

K8S_VARS ?= $(REPO_ROOT)/variables/k8s.yml
K8S_READ_YAML := $(REPO_ROOT)/scripts/k8s-read-yaml-value.sh

# Explicit list so envsubst does not expand unrelated ${...} in manifests.
K8S_ENVSUBST_VARS := $${workerCount} $${storageClassName} $${storageSize} $${memoryRequest} $${cpuRequest} $${memoryLimit} $${cpuLimit} $${elasticsearchVersion} $${qdrantVersion}

define KUBECTL_APPLY_K8S_FROM_VARS
	@set -euo pipefail; \
	command -v envsubst >/dev/null 2>&1 || { echo >&2 "ERROR: envsubst is required for k8s-apply (gettext package)"; exit 1; }; \
	if [[ ! -x '$(K8S_READ_YAML)' ]]; then \
		echo >&2 "ERROR: missing or non-executable: $(K8S_READ_YAML)"; \
		exit 1; \
	fi; \
	K8S_VARS_FILE='$(K8S_VARS)'; \
	if [[ ! -f "$$K8S_VARS_FILE" ]]; then \
		echo >&2 "ERROR: K8S vars file not found: $$K8S_VARS_FILE"; \
		exit 1; \
	fi; \
	export storageClassName="$$( "$(K8S_READ_YAML)" storageClassName "$$K8S_VARS_FILE" )"; \
	export storageSize="$$( "$(K8S_READ_YAML)" storageSize "$$K8S_VARS_FILE" )"; \
	export memoryRequest="$$( "$(K8S_READ_YAML)" memoryRequest "$$K8S_VARS_FILE" )"; \
	export cpuRequest="$$( "$(K8S_READ_YAML)" cpuRequest "$$K8S_VARS_FILE" )"; \
	export memoryLimit="$$( "$(K8S_READ_YAML)" memoryLimit "$$K8S_VARS_FILE" )"; \
	export cpuLimit="$$( "$(K8S_READ_YAML)" cpuLimit "$$K8S_VARS_FILE" )"; \
	export workerCount="$$( "$(K8S_READ_YAML)" workerCount "$$K8S_VARS_FILE" )"; \
	export elasticsearchVersion="$$( "$(K8S_READ_YAML)" elasticsearchVersion "$$K8S_VARS_FILE" )"; \
	export qdrantVersion="$$( "$(K8S_READ_YAML)" qdrantVersion "$$K8S_VARS_FILE" )"; \
	RENDER_DIR="$$(mktemp -d)"; \
	trap 'rm -rf "$$RENDER_DIR"' EXIT; \
	STACK_K8S='$(STACK_DIR)k8s'; \
	shopt -s nullglob; \
	for f in "$$STACK_K8S"/*.yaml; do \
		envsubst '$(K8S_ENVSUBST_VARS)' < "$$f" > "$$RENDER_DIR/$$(basename "$$f")"; \
	done; \
	kubectl apply -f "$$RENDER_DIR/"
endef
