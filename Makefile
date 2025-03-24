.DEFAULT_GOAL := help

VALUES ?= values.yaml
RELEASE_NAME ?= ${CHART}

lint: ## Lint the chart
	helm lint ./charts/${CHART}

deps: ## Build chart dependencies
	helm dependency build ./charts/${CHART}

create: ## Create a new chart
	helm create ./charts/${CHART}

template: ## Dry run the chart
	helm template --debug --dry-run ${CHART} ./charts/${CHART} -f ./charts/${CHART}/${VALUES} --output-dir $(pwd)templates

install: ## Install/upgrade the chart
	helm upgrade ${RELEASE_NAME} ./charts/${CHART}  --namespace ${NAMESPACE} -f ./charts/${CHART}/${VALUES} --install --create-namespace

delete: ## Delete the release
	helm delete ${RELEASE_NAME} --namespace ${NAMESPACE}

help: ## Display this help
	@awk 'BEGIN {FS = ":.*?## "; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Examples:"
	@echo "  make lint CHART=mychart                     Lint the 'mychart' chart"
	@echo "  make install CHART=mychart NAMESPACE=dev    Install 'mychart' into 'dev' namespace"
	@echo "  make delete RELEASE_NAME=myrelease          Delete the 'myrelease' release"
	@echo "  make template CHART=mychart                 Dry run the 'mychart' chart"

