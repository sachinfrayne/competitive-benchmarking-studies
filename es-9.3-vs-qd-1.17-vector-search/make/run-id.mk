# Shared function for merging run_id from variables/run_id.yml into YAML files
# Reads run_id from variables/run_id.yml and merges it into a YAML file
# Args: $(1)=input yaml path, $(2)=output file path, $(3)=yaml path (e.g., ".evaluation.run_id")
# Note: This function is meant to be used with $(call ...) inside recipe blocks
define MERGE_RUN_ID_TO_FILE
command -v yq >/dev/null 2>&1 || { echo >&2 "ERROR: yq (https://github.com/mikefarah/yq) is required"; exit 1; }; \
rid="$$(yq eval '.run_id' "$(REPO_ROOT)/variables/run_id.yml")"; \
yq eval '$(3) = "'"$$rid"'"' "$(1)" >"$(2)"
endef
