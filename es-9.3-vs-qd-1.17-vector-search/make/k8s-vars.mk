# Renders engines/$(STACK)/k8s/*.yaml with sizing from K8S_VARS, then kubectl apply.
# Requires: mikefarah yq v4 (https://github.com/mikefarah/yq), envsubst (gettext).
# Only substitutes known keys from variables/k8s.yml so other ${...} (e.g. ${HOSTNAME} in ConfigMaps) is untouched.

K8S_VARS ?= $(REPO_ROOT)/variables/k8s.yml

# Explicit list so envsubst does not expand unrelated ${...} in manifests.
K8S_ENVSUBST_VARS := $${workerCount} $${storageClassName} $${storageSize} $${memoryRequest} $${cpuRequest} $${memoryLimit} $${cpuLimit} $${elasticsearchVersion} $${qdrantVersion}

define KUBECTL_APPLY_K8S_FROM_VARS
	@set -euo pipefail; \
	command -v yq >/dev/null 2>&1 || { echo >&2 "ERROR: yq is required for k8s-apply (https://github.com/mikefarah/yq)"; exit 1; }; \
	command -v envsubst >/dev/null 2>&1 || { echo >&2 "ERROR: envsubst is required for k8s-apply (gettext package)"; exit 1; }; \
	K8S_VARS_FILE='$(K8S_VARS)'; \
	if [[ ! -f "$$K8S_VARS_FILE" ]]; then \
		echo >&2 "ERROR: K8S vars file not found: $$K8S_VARS_FILE"; \
		exit 1; \
	fi; \
	export storageClassName="$$(yq '.storageClassName' "$$K8S_VARS_FILE")"; \
	export storageSize="$$(yq '.storageSize' "$$K8S_VARS_FILE")"; \
	export memoryRequest="$$(yq '.memoryRequest' "$$K8S_VARS_FILE")"; \
	export cpuRequest="$$(yq '.cpuRequest' "$$K8S_VARS_FILE")"; \
	export memoryLimit="$$(yq '.memoryLimit' "$$K8S_VARS_FILE")"; \
	export cpuLimit="$$(yq '.cpuLimit' "$$K8S_VARS_FILE")"; \
	export workerCount="$$(yq '.workerCount' "$$K8S_VARS_FILE")"; \
	export elasticsearchVersion="$$(yq '.elasticsearchVersion' "$$K8S_VARS_FILE")"; \
	export qdrantVersion="$$(yq '.qdrantVersion' "$$K8S_VARS_FILE")"; \
	RENDER_DIR="$$(mktemp -d)"; \
	trap 'rm -rf "$$RENDER_DIR"' EXIT; \
	STACK_K8S='$(STACK_DIR)k8s'; \
	shopt -s nullglob; \
	for f in "$$STACK_K8S"/*.yaml; do \
		envsubst '$(K8S_ENVSUBST_VARS)' < "$$f" > "$$RENDER_DIR/$$(basename "$$f")"; \
	done; \
	kubectl apply -f "$$RENDER_DIR/"
endef
