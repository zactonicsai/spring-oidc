# Convenience targets. Every target is a thin wrapper around a script you can read.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

help: ## show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n",$$1,$$2}'

# ---- config -----------------------------------------------------------------
validate: ## validate app.config.yaml against schema/app-config.schema.json
	python3 tools/appconfig.py validate
show: ## print a summary of app.config.yaml
	python3 tools/appconfig.py show
render: ## render build/ (helm values, config.env, host config, cloud-init, compose)
	python3 tools/appconfig.py render all
new-project: ## NAME=my-shop DEST=../my-shop  create a new project from this template
	./scripts/new-project-from-template.sh $(NAME) $(DEST)

# ---- local: docker only ---------------------------------------------------------
compose-up: render ## run web+api with docker compose (no Kubernetes)
	docker compose -f build/docker-compose.yaml --project-directory . up --build -d
compose-down: ## stop the compose stack
	docker compose -f build/docker-compose.yaml --project-directory . down

# ---- local: kind --------------------------------------------------------------
up: ## local kind: check, cluster, build, load, deploy, test
	./scripts/run-all.sh
test: ## run the local test suite against the running app
	./scripts/05-test.sh
open: ## port-forward the public service(s)
	./scripts/06-port-forward.sh
scale-load: ## generate CPU load and watch the HPA scale
	./scripts/07-scale.sh load 60
down: ## remove the app (keep the cluster)
	./scripts/10-cleanup-apps.sh
destroy: ## delete the kind cluster
	./scripts/99-destroy.sh

# ---- keycloak ---------------------------------------------------------------------
keycloak: ## deploy Keycloak (2+ replicas, Postgres) and expose port 80
	./scripts/keycloak.sh deploy
keycloak-open: ## port-forward Keycloak to http://localhost:8080
	./scripts/keycloak.sh open

# ---- devbox / oidc examples / monitoring ---------------------------------------------
devbox-build: ## build the Java/C++/Go developer image (kind load or az acr build)
	./scripts/devbox.sh build
devbox: ## deploy the developer pod and expose SSH (KEY=~/.ssh/id_ed25519.pub)
	./scripts/devbox.sh deploy -k $(or $(KEY),$(HOME)/.ssh/id_ed25519.pub)
devbox-ssh: ## ssh into the developer pod
	./scripts/devbox.sh ssh
oidc-java: ## build the Java OIDC CLI (needs mvn)
	cd examples/oidc-java-cli && mvn -q package && echo "java -jar examples/oidc-java-cli/target/oidc-cli.jar --issuer $$(./scripts/keycloak.sh url)/realms/demo"
oidc-go: ## build the Go OIDC CLI (needs go)
	cd examples/oidc-go-cli && go mod tidy && go build -o oidc-go-cli . && echo "examples/oidc-go-cli/oidc-go-cli --issuer $$(./scripts/keycloak.sh url)/realms/demo"
monitoring: ## deploy Prometheus + Grafana + dashboards/alerts
	./scripts/monitoring.sh deploy
monitoring-open: ## port-forward Grafana :3000, Prometheus :9090, Alertmanager :9093
	./scripts/monitoring.sh open

# ---- azure (az cli) ------------------------------------------------------------
az-up: ## full Azure path: login, ACR, images, AKS, Key Vault, deploy, test
	./scripts/azure/run-all.sh
az-vm: ## create the base Linux VM configured by cloud-init
	./scripts/azure/10-create-vm.sh
az-ansible: ## configure the VM with Ansible
	./scripts/azure/11-run-ansible.sh
az-status: ## list Azure resources
	./scripts/azure/12-status.sh
az-destroy: ## delete the Azure resource group
	./scripts/azure/99-destroy.sh

# ---- terraform -------------------------------------------------------------------
tf-fmt: ## format + validate every terraform root
	terraform fmt -recursive terraform
	for d in terraform/local-docker terraform/local-kind terraform/azure; do (cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate); done
tf-local-docker: ## terraform apply: app on plain docker + base host container
	cd terraform/local-docker && terraform init && terraform apply
tf-local-kind: ## terraform apply: kind cluster + helm release
	cd terraform/local-kind && terraform init && terraform apply
tf-azure: ## terraform apply: ACR + AKS + Key Vault + VM
	cd terraform/azure && terraform init && terraform apply
tf-destroy-%: ## tf-destroy-local-docker | tf-destroy-local-kind | tf-destroy-azure
	cd terraform/$* && terraform destroy

# ---- quality ---------------------------------------------------------------------
lint: validate ## shellcheck, helm lint, kubeconform, ansible-lint, terraform fmt
	shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh scripts/azure/*.sh setup/*.sh
	python3 tools/appconfig.py render helm >/dev/null && helm lint helm/python-demo -f build/helm-values.yaml
	helm template python-demo helm/python-demo -f build/helm-values.yaml | kubeconform -strict -summary
	kubeconform -strict -summary k8s/*.yaml k8s/keycloak/*.yaml k8s/devbox/*.yaml
	kubeconform -strict -summary -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' k8s/monitoring/servicemonitors.yaml k8s/monitoring/rules.yaml k8s/monitoring/netpol-allow-scrape.yaml k8s/monitoring/dashboard-configmap.yaml
	gofmt -l examples/oidc-go-cli | (! grep .)
	cd ansible && ansible-lint --offline site.yml
	terraform fmt -check -recursive terraform
clean: ## remove generated files
	rm -rf build terraform/*/generated terraform/*/.terraform __pycache__ apps/*/__pycache__

.PHONY: devbox-build devbox devbox-ssh oidc-java oidc-go monitoring monitoring-open keycloak keycloak-open help validate show render new-project compose-up compose-down up test open scale-load down destroy \
        az-up az-vm az-ansible az-status az-destroy tf-fmt tf-local-docker tf-local-kind tf-azure lint clean
