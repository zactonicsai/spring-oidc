# The Store as Code: Terraform (Local Docker, Local kind, Azure)

*Everything in tutorials 01 and 02 was done with commands you type in order. Terraform turns
the same result into files that describe **what should exist**; Terraform works out the order,
creates it, and later changes or deletes only what differs. Current as of September 2026:
Terraform 1.16, AzureRM provider 5.x, Helm provider 3.x, kind provider 0.11, Docker provider 3.x.
(OpenTofu 1.12 runs the same files — swap `terraform` for `tofu`.)*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step-run-the-three-roots) | Run `terraform/local-docker`, `terraform/local-kind`, `terraform/azure` |
| [2](#part-2--terraform-ideas-you-need) | Providers, resources, state, plan/apply, modules, variables, outputs |
| [3](#part-3--how-this-project-is-wired) | The `app-config` module reads the schema; what each root creates |
| [4](#part-4--file-by-file) | Every `.tf` file explained |
| [5](#part-5--best-practices) | State, secrets, versions, layering, CI |
| [6](#part-6--pros-and-cons) | Terraform vs scripts vs Bicep/Pulumi; one root vs layered roots |

---

## Part 1 — Step by step: run the three roots

### Step 0 — Install

`terraform` ≥ 1.10 (https://developer.hashicorp.com/terraform/install) or `tofu` ≥ 1.9.
Docker Desktop for the local roots; `kind` + `kubectl` for local-kind; `az` CLI logged in for Azure.

### Step 1 — Local Docker (no Kubernetes): the app + a base Linux "host" container

```bash
cd terraform/local-docker
cp terraform.tfvars.example terraform.tfvars      # optional; defaults are fine
export TF_VAR_secrets='{"API_TOKEN":"local-dev-token"}'
terraform init                                     # downloads the docker + local providers
terraform plan                                     # shows: 1 network, 3 images, 3 containers, 4 files, 2 actions
terraform apply                                    # type yes
curl http://localhost/                             # web → api over the docker network
docker exec -it python-demo-host cat /etc/python-demo/config.env   # the base host configured by setup/*.sh
terraform destroy
```

What happened: Terraform built both images from `apps/`, created a network where containers get
the **same DNS names as in Kubernetes** (`python-demo-web`, `python-demo-api`), published only
the `public` port, and started an `ubuntu:24.04` "host" container in which it ran
`setup/setup.sh` + `setup/configure.sh` with files rendered from the schema — the exact scripts
the Azure VM runs at first boot.

### Step 2 — Local kind: cluster + Helm release

```bash
cd terraform/local-kind
export TF_VAR_secrets='{"API_TOKEN":"local-dev-token"}'
terraform init && terraform apply                  # kind cluster (2 nodes), images, kind load, metrics-server, helm release
kubectl config use-context kind-python-demo
kubectl -n python-demo get pods,svc,hpa,netpol
kubectl -n python-demo port-forward svc/python-demo-web 8080:80
terraform destroy                                  # deletes the cluster
```

Same objects as `scripts/run-all.sh`, but described in ~80 lines of HCL and re-runnable: change
`app.config.yaml`, `terraform apply` again, only the Helm release changes.

### Step 3 — Azure: ACR + AKS + Key Vault + VM

```bash
cd terraform/azure
cp terraform.tfvars.example terraform.tfvars       # set ssh key paths; keep build_images = true
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TF_VAR_secrets='{"API_TOKEN":"azure-token-1"}'
terraform init
terraform plan                                     # ~25 resources
terraform apply                                    # ≈ 12 minutes (AKS is the slow part)
terraform output next_steps
az aks get-credentials -g rg-python-demo -n aks-python-demo --overwrite-existing
kubectl -n python-demo get svc -w                  # EXTERNAL-IP of the web service
ssh azureuser@$(terraform output -raw vm_public_ip) sudo tail -f /var/log/cloud-init-output.log
terraform destroy                                  # everything, including the Key Vault (purged)
```

> **Before the first Azure apply**, run `terraform validate` and read the plan. The Azure root
> was written against the AzureRM 4.40–5.x and Helm 3.x provider schemas but could not be
> executed in this project's build environment (no Azure access). If a provider release renamed
> an argument, `terraform validate` tells you exactly where; the AzureRM upgrade guides list renames.

---

## Part 2 — Terraform ideas you need

| Idea | Analogy | Meaning |
|---|---|---|
| **Provider** | a supplier the store orders from | A plugin that knows one API: `azurerm`, `docker`, `kind`, `helm`, `random`, `local`. |
| **Resource** | one item on the order form | `resource "azurerm_resource_group" "rg" { name = ... }` — one thing Terraform creates and owns. |
| **Data source** | looking something up in the catalogue | `data "azurerm_client_config" "current" {}` reads without creating. |
| **State** (`terraform.tfstate`) | the store's inventory ledger | Terraform's record of what it created and the IDs. Lose it and Terraform forgets it owns things. |
| **`plan`** | the shopping list before you go | Compares files ↔ state ↔ reality and prints +create / ~update / −destroy. Nothing changes. |
| **`apply`** | the shopping trip | Executes the plan. `-auto-approve` skips the yes prompt (CI only). |
| **`destroy`** | returning everything | Deletes every resource in the state, in reverse dependency order. |
| **Variable** | a blank on the order form | `variable "secrets" {}` set via `terraform.tfvars`, `TF_VAR_x` or `-var`. |
| **Local** | a note in the margin | `locals { name = ... }` — computed helper values. |
| **Output** | the receipt | `output "vm_public_ip"` printed after apply; `terraform output -raw x`. |
| **Module** | a pre-printed order form you reuse | A folder of `.tf` files called with inputs; here `terraform/modules/app-config`. |
| **Dependency graph** | which aisle first | Terraform orders operations from references (`azurerm_subnet.vm[0].id`) and `depends_on`. |
| **`count` / `for_each`** | "3 of these" / "one per service" | Make zero or many copies of a resource from data. |
| **`terraform_data` + provisioner** | "and while you're there, run this" | Runs a local/remote command (`kind load`, `az acr build`, `ansible-playbook`). Escape hatch, used sparingly. |

The mental model: **files = desired state, state file = last known reality, plan = the diff.**

---

## Part 3 — How this project is wired

```
app.config.yaml ──► terraform/modules/app-config  (yamldecode + placeholder expansion + defaults)
                          │  outputs: name, services{}, hosts{}, azure{}, helm_values{},
                          │           host_config_env, host_files_tsv, host_service_envs{}
        ┌─────────────────┼───────────────────────┐
        ▼                 ▼                       ▼
 terraform/local-docker   terraform/local-kind    terraform/azure
 docker_network           kind_cluster            azurerm_resource_group, _container_registry
 docker_image × svc       docker_image × svc      terraform_data.acr_build × svc (az acr build)
 docker_container × svc   terraform_data.kind_load azurerm_kubernetes_cluster (+ AcrPull role)
 docker_container.base_host  helm_release.metrics_server  azurerm_key_vault (+ secrets, roles)
 terraform_data.configure (setup.sh + configure.sh)  helm_release.app   vnet/subnet/nsg/pip/nic/azurerm_linux_virtual_machine (cloud-init)
 local_file inventory + optional ansible run                            helm_release.app (LoadBalancer)
                                                                        local_file inventory + optional ansible run
```

The module is the key design choice: **no root re-reads YAML**. It exposes the same
`helm_values` structure that `tools/appconfig.py render helm` writes, so Helm sees identical
values whether you deploy with scripts or Terraform. It also builds the same `host-config.env`,
`host-files.tsv` and per-service `env/*.env` that cloud-init/`configure.sh` use — the module was
executed offline during development and its outputs compared with the Python renderer.

Placeholders: HCL can't define functions, so `${name}` etc. are expanded with nested `replace()`
calls; the literal `"$${name}"` in HCL is the text `${name}`.

---

## Part 4 — File by file

### `terraform/modules/app-config/`
* `variables.tf` — `config_path`, `image_registry` (override), `host_settings_override` (e.g. turn
  `RUN_DEMO_CONTAINERS` off inside a container).
* `main.tf` — `locals`: `raw = yamldecode(file(...))`, normalised `services` (defaults via `try()`),
  `files`, `hosts`, `azure`, `helm_values`, `host_config_env`, `host_service_envs`, `host_files_tsv`.
* `outputs.tf` — everything above as outputs.

### `terraform/local-docker/`
* `versions.tf` — `kreuzwerker/docker ~> 3.0`, `hashicorp/local`. Provider `docker { host = var.docker_host }`.
* `main.tf` — network; `docker_image` per service with a `build {}` block and a `triggers.dir_sha1`
  hash of the context folder (rebuild when any file changes); `docker_container` per service with
  env from `config` + declared secrets, `networks_advanced { aliases }`, `dynamic "ports"` for
  public ports only, and the same hardening as the pod (`user 65532`, read-only root, `/tmp` tmpfs,
  drop all capabilities, `no-new-privileges`) plus a healthcheck on the config's health path.
* `base-host.tf` — `local_file` × 3 (host config, files list, env files) into `generated/`;
  `docker_container.base_host` from `hosts.baseImage.docker` with `setup/` and `generated/` mounted
  read-only; `terraform_data.configure_base_host` runs `docker exec … setup.sh && configure.sh`
  and re-runs when the config or scripts change; optional docker-socket mount so `configure.sh`
  can start containers itself; `local_file.ansible_inventory` (docker connection plugin) and an
  optional `ansible-playbook` run.
* `outputs.tf` — public URLs, container names, how to enter the base host.

### `terraform/local-kind/`
* `versions.tf` — `tehcyx/kind ~> 0.11`, docker, `hashicorp/helm ~> 3.1`. Note the Helm 3.x
  provider syntax: `kubernetes = { host = ..., client_certificate = ... }` is a **nested attribute**
  with `=`, not a block, and `set = [{ name = ..., value = ... }]` is a list.
* `main.tf` — `kind_cluster.this` (control-plane + worker, `wait_for_ready`); images as above;
  `terraform_data.kind_load` per service (`kind load docker-image`); `helm_release.metrics_server`
  from the upstream chart with `--kubelet-insecure-tls`; `helm_release.app` from
  `helm/python-demo` with `values = [yamlencode(merge(module.app.helm_values, {...}))]` and the
  secrets mapped per service.
* `outputs.tf` — kubeconfig path and the port-forward/test commands.

### `terraform/azure/`
* `versions.tf` — `azurerm >= 4.40, < 6.0`, helm, random, local.
* `providers.tf` — `azurerm { subscription_id, resource_provider_registrations = "none",
  resource_providers_to_register = [...] , features {...} }`. **AzureRM 5.0 (July 2026) registers
  no resource providers by default** — 4.x registered ~60; listing the six we need is the
  least-privilege pattern and works on both majors. The Helm provider is configured from the AKS
  `kube_config` block (works in one root; see the layering note in Part 5).
* `variables.tf` — subscription, location override, `name_suffix`, `secrets` (sensitive),
  SSH key paths, `build_images`, `deploy_helm`, `create_vm`, `create_keyvault`, `run_ansible`,
  `public_service_source_ranges`, `extra_tags`.
* `locals.tf` — two module instances (`module.app` with the ACR login server as registry, `module.cfg`
  registry-free for names that must exist before the ACR does), `random_string.suffix`, derived names
  (`acr_name` = letters+digits only, `kv_name` ≤ 24 chars), tags, `secrets_by_service`.
* `main.tf` — resource group, ACR (`admin_enabled = false`), `terraform_data.acr_build` per service
  running `az acr build` (triggered by the context hash — Terraform itself doesn't build images).
* `aks.tf` — `azurerm_kubernetes_cluster`: `sku_tier`, `oidc_issuer_enabled`,
  `workload_identity_enabled`, `default_node_pool { auto_scaling_enabled, min_count, max_count }`,
  `identity { SystemAssigned }`, `network_profile { azure / overlay / cilium }`,
  `key_vault_secrets_provider { secret_rotation_enabled }`, `ignore_changes = [node_count]` so the
  autoscaler and Terraform don't fight; `azurerm_role_assignment` AcrPull for the kubelet identity.
* `keyvault.tf` — vault in RBAC mode (`rbac_authorization_enabled = true`), *Secrets Officer* for
  you, *Secrets User* for the AKS CSI identity, one `azurerm_key_vault_secret` per `var.secrets` key
  (`API_TOKEN` → `API-TOKEN`), `depends_on` the role assignment.
* `vm.tf` — `local.cloud_init` built with `yamlencode()` (write_files with base64 content +
  runcmd), VNet, subnet, NSG with a `dynamic "security_rule"` per `hosts.exposePorts` entry
  (priorities 1000, 1010, …; `source` becomes `source_address_prefix`), public IP, NIC,
  NIC↔NSG association, `azurerm_linux_virtual_machine` with `custom_data`, SSH key, system identity;
  AcrPull for the VM identity.
* `helm.tf` — `helm_release.app` with `publicServiceType = LoadBalancer`,
  `publicServiceSourceRanges`, secrets; `depends_on` the AcrPull role and the image builds.
* `ansible.tf` — writes `ansible/inventory/azure.ini`; optional `terraform_data.ansible` with a
  `remote-exec` that waits for `cloud-init status --wait`, then `local-exec ansible-playbook`.
* `outputs.tf` — RG, ACR, AKS name/version, Key Vault, VM IP, next steps.

---

## Part 5 — Best practices

**State**
* Locally, `terraform.tfstate` sits in the root folder and is git-ignored (it contains secrets
  and IDs). For anything shared, use a **remote backend** with locking — on Azure:
  ```hcl
  terraform { backend "azurerm" { resource_group_name = "rg-tfstate", storage_account_name = "sttfstate123", container_name = "tfstate", key = "python-demo.azure.tfstate" } }
  ```
* One state per environment (`dev`, `prod`) — separate folders or workspaces, never one state for both.
* Never edit state by hand; use `terraform state mv/rm` and `import`.

**Secrets**
* Mark variables `sensitive = true` (done). Pass values with `TF_VAR_secrets` or a git-ignored
  `secrets.auto.tfvars`; never commit them. Remember the state file still contains them → remote,
  encrypted, access-controlled backend.
* Better: keep values only in Key Vault and let the CSI driver deliver them (the `08-secrets.sh csi`
  pattern); Terraform then never touches the value.

**Versions**
* Pin providers with `~>`/ranges (done) and commit `.terraform.lock.hcl` in real projects (this
  template git-ignores it only because the roots were never initialised here).
* Read the upgrade guide before crossing a major: AzureRM 4→5 (resource-provider registration,
  removed deprecated arguments), Helm 2→3 (nested-attribute syntax).

**Layering**
* This project configures the Helm provider from the AKS resource in the same root. It works, but
  the recommended production layout is **two roots**: `azure-infra` (RG, ACR, AKS, Key Vault) and
  `azure-apps` (Helm releases) that reads the cluster with `data "azurerm_kubernetes_cluster"`.
  Provider configs that depend on resources in the same root can't be planned when the cluster
  doesn't exist yet and complicate destroys.
* Keep imperative steps (image builds, `kind load`, Ansible) in `terraform_data` provisioners
  with explicit triggers, or move them to CI — Terraform can't diff what a script did.

**Workflow and CI**
* `terraform fmt -check` and `terraform validate` in CI (see `.github/workflows/validate.yml`);
  `tflint` and `checkov`/`tfsec` for policy; `terraform plan` on pull requests, `apply` on merge.
* Use `-target` only for emergencies; prefer small roots.
* Add `prevent_destroy` lifecycle rules to anything with data (databases, storage) — not needed here.

---

## Part 6 — Pros and cons

### Terraform vs the `az`/bash scripts

| | Scripts (`scripts/`, `scripts/azure/`) | Terraform (`terraform/`) |
|---|---|---|
| Readability for beginners | high — linear, prints as it goes | medium — declarative, order is implicit |
| Idempotence | by hand (`if exists` checks) | built in (state + plan) |
| Change detection | none | `plan` shows every difference |
| Partial updates | re-run a phase | Terraform updates only what changed |
| Cleanup | `az group delete` — fine for one RG | `destroy` — exact, in order |
| Secrets | files/env vars | variables + state (must protect state) |
| Cloud lock-in | `az` only | providers for everything (Docker, kind, Helm, Azure, AWS…) |
| Best for | learning, glue, one-off ops | environments you keep, share, or rebuild often |

### Terraform vs Bicep vs Pulumi (Azure)

| | Terraform / OpenTofu | Bicep | Pulumi |
|---|---|---|---|
| Language | HCL | Bicep DSL (compiles to ARM) | real languages (Python, TS, Go) |
| Scope | multi-cloud + Docker/kind/Helm | Azure only | multi-cloud |
| State | your state file (local/remote) | Azure keeps it (deployments) — no state file to manage | Pulumi Cloud or self-managed |
| Day-0 support for new Azure features | days–weeks after GA | day 0 | days–weeks |
| Best for | mixed environments like this template | Azure-only shops | developers who dislike DSLs |

### One root vs many roots

| | One root per target (this template) | Layered roots (infra / apps) |
|---|---|---|
| Simplicity | one `apply` does everything | two `apply`s, two states |
| Blast radius | a mistake can touch everything | infra and apps change independently |
| Provider chicken-and-egg | present (Helm provider ← AKS resource) | avoided (data source) |
| Best for | demos, small projects | teams, production |
