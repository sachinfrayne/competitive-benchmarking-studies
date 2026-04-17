SHELL := /bin/bash

REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

STACK_TARGETS := \
	terraform-plan terraform-apply terraform-destroy \
	k8s-apply k8s-delete \
	connect-k8s secrets-create \
	jingra-load jingra-load-stop jingra-load-logs \
	jingra-eval jingra-eval-stop logs-eval copy-query-dumps \
	status metrics logs-engine connect-ui logs-ui

.PHONY: help analyze elasticsearch qdrant $(STACK_TARGETS)

.DEFAULT_GOAL := help

help:
	@echo "Vector search benchmark — run from this directory (repo root)"
	@echo "============================================================="
	@echo ""
	@echo "Pattern:  make <stack> <target>"
	@echo ""
	@echo "Stacks (add a row here when you add an engine under its own directory):"
	@echo "  prefix   directory"
	@echo "  ------   ---------"
	@echo "  elasticsearch elasticsearch/"
	@echo "  qdrant   qdrant/"
	@echo ""
	@echo "Example:  make elasticsearch k8s-apply"
	@echo "          make qdrant jingra-eval JINGRA_IMAGE=registry.example.com/jingra:36"
	@echo ""
	@echo "Terraform (init runs automatically before plan, apply, destroy):"
	@echo "  terraform-plan"
	@echo "  terraform-apply"
	@echo "  terraform-destroy"
	@echo ""
	@echo "Kubernetes cluster:"
	@echo "  k8s-apply"
	@echo "  k8s-delete"
	@echo ""
	@echo "Jingra — data load (needs JINGRA_IMAGE on start):"
	@echo "  jingra-load"
	@echo "  jingra-load-stop"
	@echo "  jingra-load-logs"
	@echo ""
	@echo "Jingra — evaluation (needs JINGRA_IMAGE on start):"
	@echo "  jingra-eval"
	@echo "  jingra-eval-stop"
	@echo "  logs-eval"
	@echo "  copy-query-dumps"
	@echo ""
	@echo "Cluster status and observability:"
	@echo "  status"
	@echo "  metrics"
	@echo "  logs-engine"
	@echo "  connect-ui"
	@echo "  logs-ui                  (Elasticsearch stack only)"
	@echo ""
	@echo "Variables (pass on the make command line with any stack target):"
	@echo "  JINGRA_IMAGE=<ref>        required for jingra-load / jingra-eval"
	@echo "  JINGRA_VERSION=<text>     optional; defaults to image tag after last ':'"
	@echo "  LINES=<n>                 optional; tail limit for jingra-load-logs / logs-eval"
	@echo "  NAMESPACE=<ns>            Kubernetes namespace (default: default)"
	@echo "  QUERY_DUMP_REMOTE=<path>  path in pod for copy-query-dumps"
	@echo "  QUERY_DUMP_LOCAL=<path>   host directory for copy-query-dumps"
	@echo "  EVAL_POD=<name>           pod override for copy-query-dumps"
	@echo ""
	@echo "Post-run analysis (not stack-prefixed):"
	@echo "  make analyze JINGRA_IMAGE=<ref>"
	@echo "    Clears analyze/output, runs Jingra analyze in Docker."
	@echo "    Needs RESULTS_ES_URL, RESULTS_ES_USER, RESULTS_ES_PASSWORD (env or secrets/.secrets.env)."
	@echo "    Writes CSVs under analyze/output/ (recall, summary, throughput comparisons)."
	@echo ""

analyze:
	@$(MAKE) -C analyze clean analyze

elasticsearch:
	@targets="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$targets" ]; then targets="help"; fi; \
	$(MAKE) -C elasticsearch $$targets

qdrant:
	@targets="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$targets" ]; then targets="help"; fi; \
	$(MAKE) -C qdrant $$targets

$(STACK_TARGETS):
	@:
