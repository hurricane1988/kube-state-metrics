FLAGS =
TESTENVVAR =
REGISTRY ?= gcr.io/k8s-staging-kube-state-metrics
TAG_PREFIX = v
VERSION = $(shell grep '^version:' data.yaml | grep -oE "[0-9]+.[0-9]+.[0-9]+[^ \"]*")
TAG ?= $(TAG_PREFIX)$(VERSION)
LATEST_RELEASE_BRANCH := release-$(shell echo $(VERSION) | grep -ohE "[0-9]+.[0-9]+")
BRANCH = $(strip $(shell git rev-parse --abbrev-ref HEAD))
PKGS = $(shell go list ./... | grep -v /vendor/ | grep -v /tests/e2e)
ARCH ?= $(shell go env GOARCH)
BUILD_DATE = $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GIT_COMMIT ?= $(shell git rev-parse --short HEAD)
OS ?= $(shell uname -s | tr A-Z a-z)
PKG = github.com/prometheus/common
PROMETHEUS_VERSION = 3.10.1
GO_VERSION = $(shell cat .go-version)
IMAGE = $(REGISTRY)/kube-state-metrics
MULTI_ARCH_IMG = $(IMAGE)-$(ARCH)
USER ?= $(shell id -u -n)
HOST ?= $(shell hostname)
MARKDOWNLINT_CLI2_VERSION = 0.21.0
CLIENT_GO_VERSION = $(shell go list -m -f '{{.Version}}' k8s.io/client-go)
KSM_MODULE = $(shell go list -m)

# CONTAINER_CLI defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_CLI ?= docker

PROMTOOL_CLI ?= promtool
GOMPLATE_CLI ?= go tool github.com/hairyhenderson/gomplate/v4/cmd/gomplate
GOJQ_CLI ?= go tool github.com/itchyny/gojq/cmd/gojq
JSONNET_CLI ?= go tool github.com/google/go-jsonnet/cmd/jsonnet
JB_CLI ?= go tool github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb

export DOCKER_CLI_EXPERIMENTAL=enabled

# Define where to install/build the binaries.
# If the GOBIN environment variable is not set, default to the 'bin' directory in the current working directory.
ifeq (,$(shell go env GOBIN))
# Use $(CURDIR) to ensure an absolute path to the local bin folder.
GOBIN=$(CURDIR)/bin
else
# Otherwise, respect the GOBIN set in the Go environment.
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

LDFLAG_OPTIONS = -ldflags "-s -w \
					  -X ${KSM_MODULE}/version.Version=${TAG} \
                      -X ${KSM_MODULE}/version.Revision=${GIT_COMMIT} \
                      -X ${KSM_MODULE}/version.Branch=${BRANCH} \
                      -X ${KSM_MODULE}/version.BuildUser=${USER}@${HOST} \
                      -X ${KSM_MODULE}/version.BuildDate=${BUILD_DATE}"

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: fix
fix: ## Run go fix against code.
	go fix ./..

.PHONY: validate-modules
validate-modules: ## Verifying that the dependencies and checking for any unused/missing packages in go.mod.
	@echo "- Verifying that the dependencies have expected content..."
	go mod verify
	@echo "- Checking for any unused/missing packages in go.mod..."
	go mod tidy
	@git diff --exit-code -- go.sum go.mod

.PHONY: licensecheck
licensecheck: ## Checking license header.
	@echo ">> checking license header"
	@licRes=$$(for file in $$(find . -type f -iname '*.go' ! -path './vendor/*') ; do \
               awk 'NR<=5' $$file | grep -Eq "(Copyright|generated|GENERATED)" || echo $$file; \
       done); \
       if [ -n "$${licRes}" ]; then \
               echo "license header checking failed:"; echo "$${licRes}"; \
               exit 1; \
       fi

.PHONY: lint
lint: shellcheck licensecheck lint-markdown-format ## Run golangci-lint linter.
	golangci-lint run

.PHONY: lint-fix
lint-fix: fix-markdown-format ## Run golangci-lint linter and perform fixes.
	golangci-lint run --fix -v

.PHONY: doccheck
doccheck: generate validate-template ## Checking if the generated documentation is up to date.
	@echo "- Checking if the generated documentation is up to date..."
	@git diff --exit-code
	@echo "- Checking if the documentation is in sync with the code..."
	@grep -rhoE '\| kube_[^ |]+' docs/metrics/* --exclude=README.md | sed -E 's/\| //g' | sort -u > documented_metrics
	@find internal/store -type f -not -name '*_test.go' -exec sed -nE 's/.*"(kube_[^"]+)".*/\1/p' {} \; | sort -u > code_metrics
	@diff -u0 code_metrics documented_metrics || (echo "ERROR: Metrics with - are present in code but missing in documentation, metrics with + are documented but not found in code."; exit 1)
	@echo OK
	@rm -f code_metrics documented_metrics
	@echo "- Checking for orphan documentation files"
	@cd docs; for doc in $$(find metrics/* -name '*.md' | sed 's/.*\///'); do if [ "$$doc" != "README.md" ] && ! grep -q "$$doc" *.md; then echo "ERROR: No link to documentation file $${doc} detected"; exit 1; fi; done
	@echo OK

.PHONY: clean
clean: ## Clean up build artifacts and temporary files.
	rm -f bin/kube-state-metrics
	git clean -Xfd .

.PHONY: generate
generate: build generate-template ## Generate documentation and templates.
	@echo ">> generating docs"
	@./scripts/generate-help-text.sh
	${GOMPLATE_CLI} --file docs/developer/cli-arguments.md.tpl > docs/developer/cli-arguments.md

.PHONY: shellcheck
shellcheck: ## Run shellcheck against shell scripts (excludes vendor).
	${CONTAINER_CLI} run -v "${PWD}:/mnt" koalaman/shellcheck:stable $(shell find . -type f -name "*.sh" -not -path "*vendor*")

.PHONY: lint-markdown-format
lint-markdown-format: ## Lint markdown files format.
	${CONTAINER_CLI} run -v "${PWD}:/workdir" davidanson/markdownlint-cli2:v${MARKDOWNLINT_CLI2_VERSION} --config .markdownlint-cli2.jsonc

.PHONY: fix-markdown-format
fix-markdown-format: ## Automatically fix markdown formatting issues.
	${CONTAINER_CLI} run -v "${PWD}:/workdir" davidanson/markdownlint-cli2:v${MARKDOWNLINT_CLI2_VERSION} --fix --config .markdownlint-cli2.jsonc

.PHONY: generate-template
generate-template: ## Generate README.md from template.
	${GOMPLATE_CLI} -d config=./data.yaml --file README.md.tpl > README.md

.PHONY: validate-template
validate-template: generate-template ## Validate if README.md is up to date with template.
	git diff --no-ext-diff --quiet --exit-code README.md

##@ Testing

.PHONY: e2e
e2e: ## Run end-to-end tests.
	./tests/e2e.sh

.PHONY: test-unit
test-unit: ## Run unit tests with race detector.
	GOOS=$(shell uname -s | tr A-Z a-z) GOARCH=$(ARCH) $(TESTENVVAR) go test --race $(FLAGS) $(PKGS)

.PHONY: test-rules
test-rules: ## Test Prometheus recording and alerting rules.
	${PROMTOOL_CLI} test rules tests/rules/alerts-test.yaml

.PHONY: test-benchmark-compare
test-benchmark-compare: ## Run and compare benchmarks between current ref and last release.
	$(MAKE) test-benchmark-compare-main test-benchmark-compare-release

.PHONY: test-benchmark-compare-main
test-benchmark-compare-main: ## Run benchmarks on the main branch.
	@git fetch origin main
	./tests/compare_benchmarks.sh main 6

.PHONY: test-benchmark-compare-release
test-benchmark-compare-release: ## Run benchmarks on the latest release branch.
	@git fetch origin ${LATEST_RELEASE_BRANCH}
	./tests/compare_benchmarks.sh ${LATEST_RELEASE_BRANCH} 6

##@ Build

.PHONY: build
build: fmt vet ## ## Build the kube-state-metrics binary locally using host Go toolchain.
	# CGO_ENABLED=0 creates a statically linked binary for compatibility with distroless images.
    # -ldflags "-s -w" strips debug information to reduce binary size.
    # -X injects build-time variables (version, commit, date) into the application metadata.
	GOOS=$(OS) GOARCH=$(ARCH) CGO_ENABLED=0 go build $(LDFLAG_OPTIONS) -a -o $(GOBIN)/kube-state-metrics cmd/main.go

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: ## Build docker image with the kube-state-metrics.
	$(CONTAINER_CLI) build -t $(IMAGE):$(TAG) -f build/Dockerfile \
					--build-arg VERSION=$(TAG) \
					--build-arg BRANCH=$(BRANCH) \
					--build-arg GITCOMMIT=$(GIT_COMMIT) \
					--build-arg BUILDDATE=$(BUILD_DATE) .

.PHONY: docker-push
docker-push: ## Push docker image with the kube-state-metrics.
	$(CONTAINER_CLI) push $(IMAGE):$(TAG)


# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: docker-buildx
docker-buildx: ## Build and push docker image for the kube-state-metrics for cross-platform support.
	- $(CONTAINER_CLI) buildx create --name kube-state-metrics
	$(CONTAINER_CLI) buildx use kube-state-metrics
	- $(CONTAINER_CLI) buildx build --push --platform=$(PLATFORMS) --tag $(IMAGE):$(TAG) -f build/Dockerfile \
  						--build-arg VERSION=$(TAG) \
  						--build-arg BRANCH=$(BRANCH) \
  						--build-arg GITCOMMIT=$(GIT_COMMIT) \
  						--build-arg BUILDDATE=$(BUILD_DATE) .
	- $(CONTAINER_CLI) buildx rm kube-state-metrics

##@ Manifests & Examples

.PHONY: examples
examples: examples/standard examples/autosharding examples/daemonsetsharding mixin ## Generate all example manifests using jsonnet.

validate-manifests: examples ## Validate if generated manifests are up to date.
	@git diff --exit-code

mixin: examples/prometheus-alerting-rules/alerts.yaml ## Build the Prometheus mixin (alerts).

examples/prometheus-alerting-rules/alerts.yaml: jsonnet $(shell find jsonnet | grep ".libsonnet") scripts/mixin.jsonnet scripts/vendor
	mkdir -p examples/prometheus-alerting-rules
	${JSONNET_CLI}  -J scripts/vendor scripts/mixin.jsonnet | ${GOJQ_CLI} --yaml-output > examples/prometheus-alerting-rules/alerts.yaml

examples/standard: jsonnet $(shell find jsonnet | grep ".libsonnet") scripts/standard.jsonnet scripts/vendor
	mkdir -p examples/standard
	${JSONNET_CLI} -J scripts/vendor -m examples/standard --ext-str version="$(VERSION)" scripts/standard.jsonnet | xargs -I{} sh -c 'cat {} | ${GOJQ_CLI} --yaml-output > `echo {} | sed "s/\(.\)\([A-Z]\)/\1-\2/g" | tr "[:upper:]" "[:lower:]"`.yaml' -- {}
	find examples -type f ! -name '*.yaml' -delete

examples/autosharding: jsonnet $(shell find jsonnet | grep ".libsonnet") scripts/autosharding.jsonnet scripts/vendor
	mkdir -p examples/autosharding
	${JSONNET_CLI} -J scripts/vendor -m examples/autosharding --ext-str version="$(VERSION)" scripts/autosharding.jsonnet | xargs -I{} sh -c 'cat {} | ${GOJQ_CLI} --yaml-output > `echo {} | sed "s/\(.\)\([A-Z]\)/\1-\2/g" | tr "[:upper:]" "[:lower:]"`.yaml' -- {}
	find examples -type f ! -name '*.yaml' -delete

examples/daemonsetsharding: jsonnet $(shell find jsonnet | grep ".libsonnet") scripts/daemonsetsharding.jsonnet scripts/vendor
	mkdir -p examples/daemonsetsharding
	${JSONNET_CLI} -J scripts/vendor -m examples/daemonsetsharding --ext-str version="$(VERSION)" scripts/daemonsetsharding.jsonnet | xargs -I{} sh -c 'cat {} | ${GOJQ_CLI} --yaml-output > `echo {} | sed "s/\(.\)\([A-Z]\)/\1-\2/g" | tr "[:upper:]" "[:lower:]"`.yaml' -- {}
	find examples -type f ! -name '*.yaml' -delete

# Note: Other example targets (standard, autosharding, etc.) follow similar pattern
scripts/vendor: scripts/jsonnetfile.json scripts/jsonnetfile.lock.json
	cd scripts && ${JB_CLI} install
##@ Dependencies
.PHONY: install-promtool
install-promtool: ## Download and install promtool binary.
	@echo Installing promtool
	@wget -qO- "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.${OS}-${ARCH}.tar.gz" |\
	tar xvz --strip-components=1 prometheus-${PROMETHEUS_VERSION}.${OS}-${ARCH}/promtool

# List all PHONY targets to prevent file-name conflicts
.PHONY: all build build-local all-push all-container container container-* do-push-* sub-push-* push push-multi-arch test-unit test-rules test-benchmark-compare clean e2e validate-modules shellcheck licensecheck lint lint-fix generate generate-template validate-template
