# docker-kubernetes-python-demo

**A small Python web + API app, packaged so the same `app.config.yaml` runs it on plain Docker,
on a local kind cluster, on Azure AKS, or on a base Linux VM — with bash scripts, `az` CLI
scripts, Terraform, Ansible and cloud-init — plus a complete beginner's tutorial written at a
middle-school reading level.**

Current as of September 2026: Kubernetes 1.34–1.36, Helm 4, kind 0.30, Terraform 1.16 with
AzureRM 5.x / Helm provider 3.x, Ansible 12, AKS with Azure CNI Overlay + Cilium.

```
                       app.config.yaml  ─── schema/app-config.schema.json  (make validate)
                              │
       ┌──────────────────────┼───────────────────────┬───────────────────────┐
       ▼                      ▼                       ▼                       ▼
 tools/appconfig.py      helm/python-demo        terraform/{local-docker,   ansible/site.yml
 renders build/          (generic chart:          local-kind, azure}         (role base-linux)
 helm values, env,        loops over services)    + modules/app-config
 host config, cloud-init,        ▲                       │
 compose, secrets                │                       │
       │                         │                       ▼
       ▼                         │              ACR · AKS · Key Vault · VM+NSG
 scripts/*.sh (kind)  ───────────┘              docker network · kind cluster
 scripts/azure/*.sh (az) ────────┘
 setup/setup.sh + configure.sh  ◄── cloud-init / docker exec / Ansible  (base Linux hosts)
```

## What the app does

* **web** (`apps/web`, Flask + gunicorn, public): renders a page, calls **api** over the cluster
  network, shows which pod answered and its config.
* **api** (`apps/api`, Flask + gunicorn, cluster-only): JSON endpoints, a masked **secret**, and
  `/api/work` to burn CPU for autoscaling demos.
* Kubernetes objects generated for each service: Deployment, Service, ConfigMap, Secret, HPA,
  NetworkPolicy (default-deny + allow-list), ServiceAccount, optional Ingress, `helm test`.

## Quick start — laptop (kind)

```bash
pip install -r tools/requirements.txt
cp secrets.env.example secrets.env && chmod 600 secrets.env
chmod +x scripts/*.sh scripts/*/*.sh setup/*.sh
./scripts/run-all.sh            # check → cluster → build → load → helm deploy → tests   (≈ 5 min)
./scripts/06-port-forward.sh    # open http://localhost:8080
./scripts/07-scale.sh load 60   # watch the HPA;  ./scripts/09-network.sh test  ;  ./scripts/08-secrets.sh show
./scripts/99-destroy.sh
```

Needs Docker, kind, kubectl, Helm 4, python3, curl. Full walkthrough with explanations:
**[docs/01-kubernetes-tutorial-grocery-store-edition.md](docs/01-kubernetes-tutorial-grocery-store-edition.md)**.

## Quick start — Azure (`az` CLI)

```bash
./scripts/azure/run-all.sh      # login → RG + ACR → az acr build → AKS (Cilium, autoscaler) → Key Vault secret → helm → tests
./scripts/azure/10-create-vm.sh # optional: a plain Ubuntu VM configured by cloud-init from the same config
./scripts/azure/99-destroy.sh   # !! deletes the resource group
```

See **[docs/02-azure-cli-tutorial.md](docs/02-azure-cli-tutorial.md)**. Costs ≈ $0.20/hour while running.

## Quick start — Terraform

```bash
export TF_VAR_secrets='{"API_TOKEN":"local-dev-token"}'
cd terraform/local-docker && terraform init && terraform apply    # app on docker + a base Linux "host" container
cd ../local-kind           && terraform init && terraform apply    # kind cluster + metrics-server + helm release
cd ../azure                && terraform init && terraform apply    # ACR + AKS + Key Vault + VM (needs az login)
```

See **[docs/03-terraform-tutorial.md](docs/03-terraform-tutorial.md)**.

## Quick start — Keycloak, developer pod, OIDC CLIs, monitoring

```bash
./scripts/keycloak.sh deploy && ./scripts/keycloak.sh open          # identity server, 2+ replicas, demo realm (alice/bob/carol)
./scripts/devbox.sh build && ./scripts/devbox.sh deploy               # Java/C++/Go dev pod; ssh -p 2222 dev@localhost after `open`
(cd examples/oidc-java-cli && mvn -q package) && java -jar examples/oidc-java-cli/target/oidc-cli.jar --issuer http://localhost:8080/realms/demo --require-group /developers
(cd examples/oidc-go-cli && go mod tidy && go run . --issuer http://localhost:8080/realms/demo --require-group /developers)
./scripts/monitoring.sh deploy && ./scripts/monitoring.sh open       # Grafana :3000 (dashboards + alerts for Keycloak and the apps)
```

Tutorials: docs 09 (Keycloak), 10 (developer pod), 11 (OIDC clients), 12 (monitoring).

## Use it as a template

```bash
./scripts/new-project-from-template.sh my-shop ../my-shop     # copies, renames, validates, first commit
```

Then edit `app.config.yaml` only — services, ports (`expose: none|cluster|public`), config,
secret keys, image/file sources, scaling, network rules, host setup, targets. Details in
[TEMPLATE.md](TEMPLATE.md) and [docs/04-app-config-schema-reference.md](docs/04-app-config-schema-reference.md).

## Repository map

```
app.config.yaml            the single source of truth (validated by schema/app-config.schema.json)
tools/appconfig.py         validate | show | render [helm|env|host|cloudinit|compose|secrets] | get
apps/web, apps/api         Flask apps, multi-stage non-root Dockerfiles
helm/python-demo/          generic chart driven by rendered values (Helm 4 ready)
k8s/                       equivalent hand-written manifests, for reading and `04-deploy-kubectl.sh`
k8s/keycloak/ + scripts/keycloak.sh   Keycloak 26.7 + Postgres: 2+ replicas, HPA min 2, PDB, policies, port 80 exposed, demo realm
k8s/devbox/ + images/devbox/ + scripts/devbox.sh   Java/C++/Go developer pod (JDK 25, Maven, Gradle, clang, gdb, Go), SSH exposed
examples/oidc-java-cli, examples/oidc-go-cli       OIDC CLIs (device flow / code+PKCE) with group-based access control
k8s/monitoring/ + scripts/monitoring.sh            kube-prometheus-stack + Keycloak/app ServiceMonitors, alerts, Grafana dashboard
scripts/                   00 prereqs · 01 kind cluster · 02 build · 03 load · 04 deploy (helm|kubectl) · 05 test
                           06 port-forward · 07 scale · 08 secrets · 09 network · 10 cleanup · 99 destroy · run-all
scripts/azure/             00 login · 01 RG+ACR · 02 acr build · 03 AKS · 04 credentials · 05 deploy · 06 test
                           07 scale · 08 Key Vault secrets · 09 network/NSG/lockdown · 10 VM (cloud-init)
                           11 Ansible · 12 status · 99 destroy · run-all
setup/                     setup.sh + configure.sh: idempotent base-Linux host configuration
ansible/                   playbook + role base-linux (reads app.config.yaml directly)
terraform/                 modules/app-config (reads the schema) · local-docker · local-kind · azure
docs/                      tutorials 01–12 (see docs/README.md)
Makefile                   make help
.github/workflows/         CI: schema, shellcheck, helm lint + kubeconform, ansible-lint, terraform validate
```

## Validation status

Everything in this repository was built and checked as far as the build environment allowed:

| Component | Checked by |
|---|---|
| `app.config.yaml` + schema + renderer | JSON Schema validation, all render targets executed, template bootstrap run end-to-end |
| Flask apps | run under gunicorn and exercised with curl |
| `k8s/` manifests | `kubeconform -strict` (13 resources) |
| Helm chart | hand-reviewed; **run `helm lint` / `helm template … \| kubeconform` before first use** (no Helm binary was available in the build sandbox) |
| bash scripts | `bash -n` + `shellcheck -S warning`; `setup/configure.sh` and the Ansible role executed against a real Ubuntu container |
| Ansible | `ansible-lint` (production profile), syntax check, real run |
| Terraform | `fmt`, HCL parse, and the `app-config` module + Azure locals **executed offline with OpenTofu**; provider-backed roots need `terraform validate` on your machine (no registry/cloud access in the sandbox) |

## Licence

MIT — use it, teach with it, fork it.
