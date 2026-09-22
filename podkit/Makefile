# Convenience targets. PROVIDER=aws|azure|gcp|all, CONFIG=examples/pg-client.yaml
PYTHON   ?= python3
PROVIDER ?= all
CONFIG   ?= examples/pg-client.yaml examples/java-server.yaml examples/java-client.yaml
VENV     ?= .venv
IMAGE    ?= ghcr.io/your-org/podkit-command-pod:latest

.PHONY: help venv validate generate test lint command-pod-image clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-20s %s\n", $$1, $$2}'

venv:                 ## create a virtualenv with the generator dependencies
	$(PYTHON) -m venv $(VENV) && $(VENV)/bin/pip install -q -r requirements-dev.txt
	@echo "activate with: source $(VENV)/bin/activate"

validate:             ## validate the example configs against the schema
	$(PYTHON) -m podgen validate $(CONFIG)

generate:             ## generate build/<provider>/<name> for CONFIG (PROVIDER=aws|azure|gcp|all)
	$(PYTHON) -m podgen generate $(CONFIG) --provider $(PROVIDER) --force

test:                 ## run the generator tests
	$(PYTHON) -m pytest -q tests

lint:                 ## bash -n on every script, terraform fmt check when terraform is installed
	@for f in scripts/*.sh scripts/lib/*.sh configure/*.sh build/*/*/*.sh; do [ -f "$$f" ] && bash -n "$$f" || true; done; echo "shell syntax ok"
	@command -v terraform >/dev/null && terraform fmt -check -recursive terraform || echo "terraform not installed; skipped fmt check"

command-pod-image:    ## build the command pod image (IMAGE=...)
	docker build -t $(IMAGE) -f command-pod/Dockerfile .

clean:                ## remove generated output
	rm -rf build
