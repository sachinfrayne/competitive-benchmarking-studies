SHELL := /bin/bash

STACK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)/..)
OUTPUT_DIR := $(CURDIR)/output

.DEFAULT_GOAL := analyze

-include $(REPO_ROOT)/secrets/.secrets.env

.PHONY: analyze clean check-vars

define require_var
	@if [ -z "$(strip $($1))" ]; then \
		echo "ERROR: $1 not set" >&2; \
		exit 1; \
	fi
endef

check-vars:
	$(call require_var,RESULTS_ES_URL)
	$(call require_var,RESULTS_ES_USER)
	$(call require_var,RESULTS_ES_PASSWORD)
	$(call require_var,JINGRA_IMAGE)

$(OUTPUT_DIR):
	@mkdir -p "$@"

analyze: check-vars | $(OUTPUT_DIR)
	@docker run --rm \
		-v "$(CURDIR)/jingra.yml:/config/jingra.yml:ro" \
		-v "$(OUTPUT_DIR):/output" \
		-e RESULTS_ES_URL="$(RESULTS_ES_URL)" \
		-e RESULTS_ES_USER="$(RESULTS_ES_USER)" \
		-e RESULTS_ES_PASSWORD="$(RESULTS_ES_PASSWORD)" \
		"$(JINGRA_IMAGE)" \
		analyze /config/jingra.yml

clean:
	@rm -rf "$(OUTPUT_DIR)"
