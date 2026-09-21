# `app.config.yaml` — Schema Reference

*One file describes the whole application: what runs, on which ports, with what settings, where
images and files come from, how base Linux hosts are set up, and where it all deploys. This page
documents every field. The machine-readable schema is `schema/app-config.schema.json`
(JSON Schema 2020-12); `make validate` checks a file against it, plus cross-field rules the tool
adds (e.g. `allowFrom` must name existing services).*

```
apiVersion: appconfig.demo/v1
kind: AppConfig
metadata:   ...   # who/what
sources:    ...   # where images + files come FROM
services:   ...   # what runs (one entry per container)
kubernetes: ...   # cluster-wide settings
hosts:      ...   # base Linux host setup (VM / docker "host")
targets:    ...   # where it deploys (local, azure)
```

**Placeholders** allowed inside string values anywhere: `${name}` (metadata.name),
`${version}` (metadata.version), `${registry}` (sources.imageRegistry, empty when local).

**Who reads what:** every tool reads this one file — `tools/appconfig.py` (renders `build/`),
`helm/` (via rendered values), `scripts/` (via `build/config.env`), `terraform/` (via the
`app-config` module), `ansible/` (via `include_vars`), `setup/*.sh` (via `host-config.env`).

---

## `metadata` (required)

| Field | Type / rule | Default | Used by |
|---|---|---|---|
| `name` | `^[a-z0-9]([-a-z0-9]{0,38}[a-z0-9])?$` (DNS label) | **required** | everything: namespace, resource names `<name>-<service>`, image names, kind cluster, Azure `rg-<name>`, `aks-<name>`, `vm-<name>`, `/etc/<name>`, `/opt/<name>` |
| `version` | `^[A-Za-z0-9_.-]{1,64}$` | **required** | default image tag; `app.kubernetes.io/version` label; `APP_VERSION` env var |
| `description` | string | — | docs only |
| `owner` | string | — | `owner` tag on Azure resources |
| `labels` | map of string → string | `{}` | extra Kubernetes labels on every object; Azure tags |

## `sources`

| Field | Type / rule | Default | Used by |
|---|---|---|---|
| `imageRegistry` | string, e.g. `myacr.azurecr.io` | `""` (local images) | image prefix everywhere. Azure scripts/Terraform override it with the ACR login server (`--registry`, `image_registry`) |
| `imagePullSecret` | string | `""` | name of an existing Kubernetes Secret of type `dockerconfigjson` for registries that need a password (not needed with AKS ↔ ACR integration) |
| `files[]` | list | `[]` | external files downloaded onto **hosts** (not pods) by `setup/configure.sh`, cloud-init and the Ansible role |
| `files[].name` | `^[A-Za-z0-9_.-]+$` | required | label in logs |
| `files[].url` | `^https?://` | required | download URL |
| `files[].dest` | absolute path | required | where to put it (placeholders allowed: `/etc/${name}/…`) |
| `files[].mode` | `^0[0-7]{3}$` | `0644` | file permissions |
| `files[].owner` | string | `root` | file owner (Ansible) |
| `files[].sha256` | 64 hex chars or `""` | `""` | verify the download; **fill this in for anything you execute** |

## `services[]` (required, ≥ 1)

One entry per container. Kubernetes objects are named `<metadata.name>-<service.name>`.

| Field | Type / rule | Default | What it becomes |
|---|---|---|---|
| `name` | `^[a-z0-9]([-a-z0-9]{0,20}[a-z0-9])?$` | required | Deployment/Service/ConfigMap/Secret/HPA/NetworkPolicy names; DNS name inside the cluster and the docker network; `SERVICE_<NAME>_*` variables |
| `description` | string | — | docs |
| `build.context` | path relative to repo root | required if `build` given | `docker build` / `az acr build` / Terraform `docker_image.build.context` |
| `build.dockerfile` | string | `Dockerfile` | relative to the context |
| `image.repository` | string | required | image name without registry and tag, e.g. `${name}-web` |
| `image.tag` | string | `""` → `metadata.version` | image tag |
| `image.pullPolicy` | `IfNotPresent` \| `Always` \| `Never` | `IfNotPresent` | Deployment `imagePullPolicy` |
| `ports[]` | list, ≥ 1 | required | container + Service ports; the **first** port is the one hosts publish |
| `ports[].name` | `^[a-z0-9-]{1,15}$` | required | port name (`http`) |
| `ports[].containerPort` | 1–65535 | required | port the process listens on |
| `ports[].servicePort` | 1–65535 | = containerPort | Kubernetes Service port; docker host port |
| `ports[].protocol` | `TCP` \| `UDP` | `TCP` | |
| `ports[].expose` | `none` \| `cluster` \| `public` | `cluster` | **`none`**: no ingress allowed (NetworkPolicy has no rules except `allowFrom`); **`cluster`**: reachable inside the cluster/docker network only; **`public`**: NetworkPolicy allows any source, Service becomes `LoadBalancer` on Azure, port published on the docker host |
| `config` | map string → string/number/bool | `{}` | **ConfigMap** → env vars; compose/Terraform/Ansible env; `env/<svc>.env` on hosts |
| `secrets[]` | list | `[]` | **keys only**. Values come from `secrets.env`, `TF_VAR_secrets` or Key Vault. Each becomes a key in Secret `<app>-<svc>-secrets` → env var |
| `secrets[].name` | `^[A-Z][A-Z0-9_]*$` | required | env var name (Key Vault name = with dashes) |
| `secrets[].description` | string | — | docs |
| `health.path` | starts with `/` | `/health` | readiness + liveness HTTP probe; docker healthcheck |
| `health.readinessInitialDelaySeconds` | int ≥ 0 | `2` | |
| `health.livenessInitialDelaySeconds` | int ≥ 0 | `5` | |
| `scale.replicas` | 0–100 | `1` | Deployment replicas (omitted from the Deployment when autoscale is on) |
| `scale.autoscale.enabled` | bool | `false` | create a HorizontalPodAutoscaler |
| `scale.autoscale.minReplicas` | ≥ 1 | `1` | |
| `scale.autoscale.maxReplicas` | ≥ 1, ≥ min | `1` | |
| `scale.autoscale.targetCPUUtilizationPercentage` | 1–100 | `70` | % of the CPU **request** |
| `resources.requests` / `resources.limits` | `{cpu, memory}` strings | `{}` | container resources; **set requests** or the HPA can't work |
| `network.allowFrom[]` | names of other services | `[]` | NetworkPolicy: pods of those services may reach this one on its ports. Unknown names fail validation |

## `kubernetes`

| Field | Type | Default | Used by |
|---|---|---|---|
| `namespace` | DNS label | `""` → `metadata.name` | every object; `--create-namespace` |
| `networkPolicy.enabled` | bool | `true` | generate NetworkPolicy objects at all |
| `networkPolicy.defaultDeny` | bool | `true` | add the namespace-wide deny-all-ingress policy |
| `ingress.enabled` | bool | `false` | create an Ingress for public services (needs an ingress controller) |
| `ingress.className` | string | `""` | `ingressClassName` (`nginx`, `azure-application-gateway`, …) |
| `ingress.host` | hostname | `""` | the host rule |

## `hosts` — base Linux host configuration

Consumed by `setup/setup.sh`, `setup/configure.sh`, the cloud-init renderer, Terraform
(`local-docker` base host, `azure` VM + NSG) and `ansible/roles/base-linux`.

| Field | Type / rule | Default | Used by |
|---|---|---|---|
| `baseImage.docker` | image ref | `ubuntu:24.04` | Terraform local-docker base host container |
| `baseImage.azure.publisher/offer/sku/version` | strings | Canonical / ubuntu-24_04-lts / server / latest | Terraform `source_image_reference` |
| `baseImage.azure.urnAlias` | string | `Ubuntu2404` | `az vm create --image` in `10-create-vm.sh` |
| `adminUser` | `^[a-z_][a-z0-9_-]{0,31}$` | `azureuser` | VM admin user; created + added to `docker` group on any host |
| `packages[]` | apt package names | `[curl, ca-certificates]` | `apt-get install` (setup.sh, cloud-init `packages`, Ansible `apt`) |
| `exposePorts[]` | list | `[]` | **ufw** allow rules (setup.sh, Ansible) + **Azure NSG** inbound rules (`az vm open-port`, Terraform `security_rule`) |
| `exposePorts[].name` | string | required | rule name |
| `exposePorts[].port` | 1–65535 | required | |
| `exposePorts[].protocol` | `TCP` \| `UDP` | `TCP` | |
| `exposePorts[].source` | `*` or CIDR | `*` | NSG source prefix (Terraform); tip: `YOUR_IP/32` for SSH |
| `setupScript` | path | `setup/setup.sh` | runs first on a host (packages, Docker, firewall, users, timezone) |
| `configureScript` | path | `setup/configure.sh` | runs second (files, settings, containers) |
| `ansible.enabled` | bool | `false` | informational + `11-run-ansible.sh` |
| `ansible.playbook` | path | `ansible/site.yml` | |
| `settings` | map string → string | `{}` | → `/etc/<name>/config.env` and `SETTING_*` variables. Special keys: `TIMEZONE` (sets the host timezone), `RUN_DEMO_CONTAINERS` (`"true"` → configure.sh/Ansible run the service containers with docker) |

## `targets`

| Field | Type / rule | Default | Used by |
|---|---|---|---|
| `local.clusterName` | DNS label | `""` → `metadata.name` | kind cluster name (`kind-<name>` context) |
| `local.kindConfig` | path | `kind-config.yaml` | `kind create cluster --config` |
| `azure.location` | region | `eastus` | all Azure resources |
| `azure.resourceGroup` | string | `""` → `rg-<name>` | |
| `azure.acrName` | `^[a-z0-9]{5,50}$` or `""` | `""` → derived unique name | ACR name (global) |
| `azure.aks.nodeCount` | ≥ 1 | `2` | initial node count |
| `azure.aks.nodeVmSize` | VM size | `Standard_B2ms` | |
| `azure.aks.autoscale.enabled/minCount/maxCount` | bool, ≥1, ≥1 | true / 1 / 3 | cluster autoscaler |
| `azure.aks.tier` | `free` \| `standard` | `free` | control-plane SLA tier |
| `azure.aks.kubernetesVersion` | `""` or `1.36` etc. | `""` → AKS default GA | `--kubernetes-version` |
| `azure.aks.networkPolicy` | `cilium` \| `azure` \| `calico` | `cilium` | network policy engine (cilium = Azure CNI Overlay + Cilium dataplane) |
| `azure.vm.enabled` | bool | `false` | create the base Linux VM path |
| `azure.vm.size` | VM size | `Standard_B1s` | |
| `azure.keyVault.enabled` | bool | `false` | create Key Vault, store secrets |

---

## Validation rules beyond the JSON Schema (`tools/appconfig.py validate`)

* service names unique; port names unique within a service
* `network.allowFrom` entries must be existing service names (and not the service itself)
* `autoscale.maxReplicas ≥ minReplicas`
* `secrets[].name` unique per service
* `hosts.setupScript` / `configureScript` files must exist
* warns when a service has secrets but `secrets.env` doesn't provide them (render `secrets`)

## Rendered outputs (`tools/appconfig.py render [what]`)

| Output (`build/`) | From | Consumer |
|---|---|---|
| `helm-values.yaml` | services, kubernetes, sources, metadata | `helm -f` |
| `secrets-values.yaml` (mode 600) | `secrets.env` + `services[].secrets` | `helm -f` (never commit) |
| `config.env` | everything | `scripts/lib/common.sh` (`APP_NAME`, `SERVICES`, `SERVICE_WEB_IMAGE`, `AZ_*`, `HOST_PORTS`, …) |
| `host-config.env`, `host-files.tsv`, `env/<svc>.env` | hosts, sources.files, services | `setup/*.sh` on a host |
| `cloud-init.yaml` | the three above + `setup/*.sh` | `az vm create --custom-data` |
| `docker-compose.yaml` | services | `docker compose -f build/docker-compose.yaml --project-directory . up` |

`tools/appconfig.py get <dotted.path>` prints one value (resolved model first, e.g. `get name`,
then the raw file, e.g. `get targets.azure.aks.nodeVmSize`) — handy in your own scripts.

## Minimal example

```yaml
apiVersion: appconfig.demo/v1
kind: AppConfig
metadata: { name: hello, version: "0.1.0" }
services:
  - name: web
    build: { context: apps/web }
    image: { repository: ${name}-web }
    ports: [{ name: http, containerPort: 8080, servicePort: 80, expose: public }]
```

Everything else takes its default: namespace `hello`, no secrets, 1 replica, no HPA,
default-deny + public allow policy, `ubuntu:24.04` hosts, `eastus`, no VM, no Key Vault.
