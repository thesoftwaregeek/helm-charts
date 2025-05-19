.DEFAULT_GOAL := help

# Default values
VALUES ?= values.yaml
RELEASE_NAME ?= ${CHART}
HELM_VERSION ?= 3.12.0
KUBE_VERSION ?= 1.25.0
KIND_CLUSTER_NAME ?= kind-dev
KIND_CONFIG ?= kind.yaml

# Check if required tools are installed
HELM := $(shell command -v helm 2> /dev/null)
CT := $(shell command -v ct 2> /dev/null)
TRIVY := $(shell command -v trivy 2> /dev/null)
KIND := $(shell command -v kind 2> /dev/null)
YAML_LINT := $(shell command -v yamllint 2> /dev/null)
KUBECTL := $(shell command -v kubectl 2> /dev/null)

.PHONY: check-tools
check-tools:
ifndef HELM
	$(error "helm is not installed. Please install helm $(HELM_VERSION) or later")
endif
ifndef CT
	$(error "ct (chart-testing) is not installed. Please install chart-testing")
endif
ifndef TRIVY
	$(error "trivy is not installed. Please install trivy")
endif
ifndef KIND
	$(error "kind is not installed. Please install kind")
endif
ifndef YAML_LINT
	$(error "yamllint is not installed. Please install yamllint")
endif
ifndef KUBECTL
	$(error "kubectl is not installed. Please install kubectl")
endif

.PHONY: check-chart
check-chart:
ifndef CHART
	$(error "CHART is not set. Please specify a chart name")
endif

.PHONY: check-namespace
check-namespace:
ifndef NAMESPACE
	$(error "NAMESPACE is not set. Please specify a namespace")
endif

lint: check-tools check-chart ## Lint the chart
	@echo "Linting chart $(CHART)..."
	helm lint ./charts/${CHART}

deps: check-tools check-chart ## Build chart dependencies
	@echo "Building dependencies for chart $(CHART)..."
	helm dependency build ./charts/${CHART}

create: check-tools check-chart ## Create a new chart
	@echo "Creating new chart $(CHART)..."
	helm create ./charts/${CHART}

template: check-tools check-chart ## Dry run the chart
	@echo "Generating templates for chart $(CHART)..."
	helm template --debug --dry-run ${CHART} ./charts/${CHART} -f ./charts/${CHART}/${VALUES} --output-dir $(pwd)/templates

install: check-tools check-chart check-namespace ## Install/upgrade the chart
	@echo "Installing/upgrading chart $(CHART) in namespace $(NAMESPACE)..."
	helm upgrade ${RELEASE_NAME} ./charts/${CHART} --namespace ${NAMESPACE} -f ./charts/${CHART}/${VALUES} --install --create-namespace

delete: check-tools check-namespace ## Delete the release
	@echo "Deleting release $(RELEASE_NAME) from namespace $(NAMESPACE)..."
	helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

ct-lint: check-tools check-chart ## Run chart-testing lint
	@echo "Running chart-testing lint for chart $(CHART)..."
	ct lint --config .github/linters/ct.yaml

ct-install: check-tools check-chart ## Run chart-testing install
	@echo "Running chart-testing install for chart $(CHART)..."
	ct install --config .github/linters/ct.yaml

trivy-scan: check-tools check-chart ## Run Trivy vulnerability scan
	@echo "Running Trivy scan for chart $(CHART)..."
	trivy config --helm-kube-version ${KUBE_VERSION} ./charts/${CHART}

.PHONY: test
test: lint ct-lint trivy-scan ## Run all tests (lint, chart-testing, and trivy scan)
	@echo "All tests completed successfully!"

.PHONY: clean
clean: ## Clean up generated files
	@echo "Cleaning up generated files..."
	rm -rf ./templates
	rm -rf ./charts/${CHART}/charts
	rm -f ./charts/${CHART}/Chart.lock

.PHONY: version
version: ## Check tool versions
	@echo "Checking tool versions..."
	@echo "Helm version: $$(helm version --short)"
	@echo "Chart-testing version: $$(ct version)"
	@echo "Trivy version: $$(trivy --version | head -n 1)"
	@echo "Kubernetes version: ${KUBE_VERSION}"

.PHONY: kind-create
kind-create: check-tools ## Create a kind cluster for testing
	@echo "Creating kind cluster '$(KIND_CLUSTER_NAME)' using $(KIND_CONFIG)..."
	@if kind get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "Cluster '$(KIND_CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --name $(KIND_CLUSTER_NAME) --config $(KIND_CONFIG) --image kindest/node:v$(KUBE_VERSION); \
		echo "Cluster '$(KIND_CLUSTER_NAME)' created successfully"; \
	fi
	@echo "Waiting for cluster to be ready..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=300s
	@echo "Cluster is ready!"

.PHONY: kind-delete
kind-delete: check-tools ## Delete the kind cluster
	@echo "Deleting kind cluster '$(KIND_CLUSTER_NAME)'..."
	@if kind get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		kind delete cluster --name $(KIND_CLUSTER_NAME); \
		echo "Cluster '$(KIND_CLUSTER_NAME)' deleted successfully"; \
	else \
		echo "Cluster '$(KIND_CLUSTER_NAME)' does not exist"; \
	fi

.PHONY: kind-status
kind-status: check-tools ## Check the status of the kind cluster
	@echo "Checking status of kind cluster '$(KIND_CLUSTER_NAME)'..."
	@if kind get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "Cluster exists"; \
		kubectl cluster-info; \
		kubectl get nodes; \
	else \
		echo "Cluster does not exist"; \
	fi

.PHONY: package	
package: check-tools ## Package the chart
	@echo "Packaging chart $(CHART)..."
	helm package ./charts/${CHART}
	

.PHONY: push
push: check-tools ## Push the chart to a registry
	@echo "Pushing chart $(CHART) to registry..."
	helm push ./charts/${CHART} oci://$(REGISTRY)

help: ## Display this help
	@awk 'BEGIN {FS = ":.*?## "; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  CHART        Chart name (required for most targets)"
	@echo "  NAMESPACE    Kubernetes namespace (required for install/delete)"
	@echo "  VALUES       Values file name (default: values.yaml)"
	@echo "  RELEASE_NAME Release name (default: same as CHART)"
	@echo "  HELM_VERSION Required Helm version (default: 3.12.0)"
	@echo "  KUBE_VERSION Kubernetes version for testing (default: 1.25.0)"
	@echo "  KIND_CLUSTER_NAME Name of the kind cluster (default: kind-dev)"
	@echo "  KIND_CONFIG  Path to kind configuration file (default: kind.yaml)"
	@echo ""
	@echo "Examples:"
	@echo "  make lint CHART=mychart                     Lint the 'mychart' chart"
	@echo "  make install CHART=mychart NAMESPACE=dev    Install 'mychart' into 'dev' namespace"
	@echo "  make delete RELEASE_NAME=myrelease          Delete the 'myrelease' release"
	@echo "  make template CHART=mychart                 Dry run the 'mychart' chart"
	@echo "  make test CHART=mychart                     Run all tests for 'mychart'"
	@echo "  make clean CHART=mychart                    Clean up generated files for 'mychart'"
	@echo "  make kind-create                            Create a kind cluster for testing"
	@echo "  make kind-delete                            Delete the kind cluster"
	@echo "  make kind-status                            Check the status of the kind cluster"

