# Operational settings (gke-connect, stack-status, stack-access)
GKE_CLUSTER_NAME := elasticsearch-benchmark
ECK_VERSION := 3.1.0

STACK_ENGINE_LABEL := Elasticsearch

ENGINE_POD_SELECTOR := common.k8s.elastic.co/type=elasticsearch
UI_POD_SELECTOR := common.k8s.elastic.co/type=kibana
SERVICE_LABEL_SELECTOR := common.k8s.elastic.co/type

ENGINE_LOG_POD_SELECTOR := common.k8s.elastic.co/type=elasticsearch
UI_SERVICE_NAME := es-cluster-kb-http
UI_URL_TEMPLATE := URL:      https://$${EXTERNAL_IP}:5601

define ENGINE_CREDENTIALS_UPSERT
	if kubectl get secret es-cluster-es-elastic-user --namespace="$$NS" >/dev/null 2>&1; then \
		ES_PASS=$$(kubectl get secret es-cluster-es-elastic-user --namespace="$$NS" -o jsonpath='{.data.elastic}' | base64 -d); \
		kubectl create secret generic jingra-credentials \
			--from-literal=ENGINE_PASSWORD="$$ES_PASS" \
			--namespace="$$NS" \
			--dry-run=client -o yaml | kubectl apply -f -; \
	else \
		echo >&2 "Note: es-cluster-es-elastic-user not found; jingra-credentials not updated. Run secrets-create again after the cluster exists."; \
	fi; \

endef

define UI_CREDENTIAL_LINES
	ENGINE_PASSWORD=$$(kubectl get secret jingra-credentials -n $(NAMESPACE) -o jsonpath='{.data.ENGINE_PASSWORD}' 2>/dev/null | base64 -d); \
	if [ -z "$$ENGINE_PASSWORD" ]; then \
		ENGINE_PASSWORD=$$(kubectl get secret es-cluster-es-elastic-user -n $(NAMESPACE) -o go-template='{{.data.elastic | base64decode}}{{"\\n"}}' 2>/dev/null); \
	fi; \
	echo "Username: elastic"; \
	echo "Password: $$ENGINE_PASSWORD"; \

endef

.PHONY: k8s-apply k8s-delete logs-ui

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
	kubectl apply -f $(STACK_DIR)k8s/
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=elasticsearch --timeout=600s || true
	kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=kibana --timeout=600s || true

k8s-delete: connect-k8s
	@kubectl delete kibana es-cluster -n $(NAMESPACE) --ignore-not-found
	@kubectl delete elasticsearch es-cluster -n $(NAMESPACE) --ignore-not-found
	@kubectl delete -f $(STACK_DIR)k8s/ --ignore-not-found

logs-ui: connect-k8s
	@POD=$$(kubectl get pods -l common.k8s.elastic.co/type=kibana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo >&2 "ERROR: No UI pods found"; \
		exit 1; \
	fi; \
	kubectl logs -f "$$POD"
