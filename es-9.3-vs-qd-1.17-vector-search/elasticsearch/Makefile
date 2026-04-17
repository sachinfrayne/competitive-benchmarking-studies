SHELL := /bin/bash

STACK_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(STACK_DIR)/..)
GKE_CLUSTER_NAME := elasticsearch-benchmark
NAMESPACE ?= default
ECK_VERSION := 3.1.0

# JINGRA_IMAGE must be provided for load/eval. Optional: JINGRA_VERSION (defaults to image tag).

.DEFAULT_GOAL := status

include $(REPO_ROOT)/make/inc/terraform.mk
include $(REPO_ROOT)/make/inc/gke-connect.mk
include $(REPO_ROOT)/make/inc/jingra-jobs.mk
include $(REPO_ROOT)/make/inc/logs-common.mk

.PHONY: terraform-init terraform-plan terraform-apply terraform-destroy \
        k8s-apply k8s-delete secrets-create \
        jingra-load jingra-load-stop jingra-load-logs \
        jingra-eval jingra-eval-stop logs-eval copy-query-dumps \
        status metrics logs-engine logs-ui \
        connect-k8s connect-ui

k8s-apply: secrets-create
	@CRD_EXISTS=$$(kubectl get crd elasticsearches.elasticsearch.k8s.elastic.co --ignore-not-found); \
	if [ -z "$$CRD_EXISTS" ]; then \
		kubectl create -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/crds.yaml; \
	fi
	@OPERATOR_EXISTS=$$(kubectl get po -n elastic-system --no-headers 2>/dev/null | grep '^elastic-operator' || true); \
	if [ -z "$$OPERATOR_EXISTS" ]; then \
		kubectl apply -f https://download.elastic.co/downloads/eck/$(ECK_VERSION)/operator.yaml; \
		kubectl wait --for=condition=ready pod -l control-plane=elastic-operator -n elastic-system --timeout=120s || true; \
	fi
	kubectl apply -f k8s-cluster.yml
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=elasticsearch --timeout=600s || true
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=kibana --timeout=600s || true
	@$(MAKE) status

k8s-delete: connect-k8s
	kubectl delete -f k8s-cluster.yml --ignore-not-found

secrets-create: connect-k8s
	@set -euo pipefail; \
	NAMESPACE="$(NAMESPACE)"; \
	SECRETS_ENV="$(REPO_ROOT)/secrets/.secrets.env"; \
	if [[ -f "$$SECRETS_ENV" ]]; then \
		set -a; source "$$SECRETS_ENV"; set +a; \
	else \
		echo >&2 "Note: $$SECRETS_ENV not found; using environment only. Copy secrets/.secrets.env.example to secrets/.secrets.env to use a file."; \
	fi; \
	for var in DOCKER_USERNAME DOCKER_PASSWORD DOCKER_EMAIL; do \
		if [[ -z "$${!var:-}" ]]; then \
			echo >&2 "ERROR: $$var not set"; exit 1; \
		fi; \
	done; \
	kubectl delete secret regcred --namespace="$$NAMESPACE" --ignore-not-found; \
	kubectl create secret docker-registry regcred \
		--docker-server="$$DOCKER_REGISTRY" \
		--docker-username="$$DOCKER_USERNAME" \
		--docker-password="$$DOCKER_PASSWORD" \
		--docker-email="$$DOCKER_EMAIL" \
		--namespace="$$NAMESPACE"; \
	if [[ -n "$${RESULTS_ES_PASSWORD:-}" ]]; then \
		kubectl delete secret jingra-results-cluster --namespace="$$NAMESPACE" --ignore-not-found; \
		kubectl create secret generic jingra-results-cluster \
			--from-literal=RESULTS_ES_URL="$$RESULTS_ES_URL" \
			--from-literal=RESULTS_ES_USER="$$RESULTS_ES_USER" \
			--from-literal=RESULTS_ES_PASSWORD="$$RESULTS_ES_PASSWORD" \
			--namespace="$$NAMESPACE"; \
	fi; \
	if kubectl get secret es-cluster-es-elastic-user --namespace="$$NAMESPACE" >/dev/null 2>&1; then \
		ES_PASS=$$(kubectl get secret es-cluster-es-elastic-user --namespace="$$NAMESPACE" -o jsonpath='{.data.elastic}' | base64 -d); \
		kubectl create secret generic jingra-credentials \
			--from-literal=ENGINE_PASSWORD="$$ES_PASS" \
			--namespace="$$NAMESPACE" \
			--dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo >&2 "Note: es-cluster-es-elastic-user not found; jingra-credentials not updated. Run secrets-create again after the cluster exists."; \
	fi; \
	kubectl delete secret jingra-dataset-urls --namespace="$$NAMESPACE" --ignore-not-found; \
	kubectl create secret generic jingra-dataset-urls \
		--from-literal=DATASET_DATA_URL="$$DATASET_DATA_URL" \
		--from-literal=DATASET_QUERIES_URL="$$DATASET_QUERIES_URL" \
		--namespace="$$NAMESPACE"

status: connect-k8s
	@echo "Elasticsearch pods:"
	@kubectl get pods -l common.k8s.elastic.co/type=elasticsearch 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Kibana pods:"
	@kubectl get pods -l common.k8s.elastic.co/type=kibana 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Jingra jobs:"
	@kubectl get jobs -l app=jingra 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Jingra pods:"
	@kubectl get pods -l app=jingra 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Services:"
	@kubectl get svc -l common.k8s.elastic.co/type=elasticsearch 2>/dev/null || true
	@kubectl get svc -l common.k8s.elastic.co/type=kibana 2>/dev/null || true

connect-ui: connect-k8s
	@ENGINE_PASSWORD=$$(kubectl get secret jingra-credentials -n $(NAMESPACE) -o jsonpath='{.data.ENGINE_PASSWORD}' 2>/dev/null | base64 -d); \
	if [ -z "$$ENGINE_PASSWORD" ]; then ENGINE_PASSWORD=$$(kubectl get secret es-cluster-es-elastic-user -n $(NAMESPACE) -o go-template='{{.data.elastic | base64decode}}{{"\n"}}' 2>/dev/null); fi; \
	EXTERNAL_IP=$$(kubectl get svc es-cluster-kb-http -n $(NAMESPACE) -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -z "$$EXTERNAL_IP" ]; then \
		echo >&2 "LoadBalancer IP not ready."; \
		kubectl get svc es-cluster-kb-http -n $(NAMESPACE) >&2; \
		exit 1; \
	fi; \
	echo "URL:      https://$$EXTERNAL_IP:5601"; \
	echo "Username: elastic"; \
	echo "Password: $$ENGINE_PASSWORD"

define tail_pod_logs
	@POD=$$(kubectl get pods -l $(1) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo >&2 "No $(3) pods found"; \
		exit 1; \
	fi; \
	kubectl logs -f $$POD
endef

logs-engine: connect-k8s
	$(call tail_pod_logs,common.k8s.elastic.co/type=elasticsearch,engine,engine)

logs-ui: connect-k8s
	$(call tail_pod_logs,common.k8s.elastic.co/type=kibana,UI,UI)
