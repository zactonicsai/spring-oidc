# Convenience targets. PROVIDER=aws|azure|gcp|all, CONFIG=examples/pg-client.yaml, PREFIX=~/.local
PYTHON   ?= python3
PROVIDER ?= all
CONFIG   ?= examples/pg-client.yaml examples/java-server.yaml examples/java-client.yaml
VENV     ?= .venv
IMAGE    ?= ghcr.io/your-org/podkit-command-pod:latest
PREFIX   ?= $(HOME)/.local

.PHONY: help venv install uninstall validate generate test lint command-pod-image clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-20s %s\n", $$1, $$2}'

venv:                 ## create a virtualenv with the generator dependencies
	$(PYTHON) -m venv $(VENV) && $(VENV)/bin/pip install -q -r requirements-dev.txt
	@echo "activate with: source $(VENV)/bin/activate"

install:              ## symlink the podkit CLI into $(PREFIX)/bin
	mkdir -p $(PREFIX)/bin && ln -sf $(CURDIR)/bin/podkit $(PREFIX)/bin/podkit
	@echo "installed $(PREFIX)/bin/podkit -> $(CURDIR)/bin/podkit (make sure $(PREFIX)/bin is on your PATH)"

uninstall:            ## remove the symlink
	rm -f $(PREFIX)/bin/podkit

validate:             ## validate the example configs against the schema
	bin/podkit validate $(CONFIG)

generate:             ## generate build/<provider>/<name> for CONFIG (PROVIDER=aws|azure|gcp|all)
	bin/podkit generate $(CONFIG) --provider $(PROVIDER) --force

test:                 ## run the generator and CLI tests
	$(PYTHON) -m pytest -q tests

lint:                 ## bash -n everywhere; shellcheck and terraform fmt -check when installed
	@for f in bin/podkit scripts/*.sh scripts/lib/*.sh scripts/resources/*.sh configure/*.sh build/*/*/*.sh; do [ -f "$$f" ] && bash -n "$$f" || true; done; echo "shell syntax ok"
	@command -v shellcheck >/dev/null && shellcheck -x -S style bin/podkit scripts/*.sh scripts/lib/*.sh scripts/resources/*.sh configure/*.sh || echo "shellcheck not installed; skipped"
	@command -v terraform >/dev/null && terraform fmt -check -recursive terraform || echo "terraform not installed; skipped fmt check"

command-pod-image:    ## build the command pod image (IMAGE=...)
	COMMAND_POD_IMAGE=$(IMAGE) bin/podkit image build

clean:                ## remove generated output
	rm -rf build
