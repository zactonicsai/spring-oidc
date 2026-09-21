# Using this repository as a template

This project is built so that **`app.config.yaml` is the only file you must edit** to turn it into
your own application. Everything else — Helm values, scripts, Terraform, Ansible, cloud-init,
docker-compose — is *derived* from it.

## 1. Create your project

```bash
./scripts/new-project-from-template.sh my-shop ../my-shop     # or: make new-project NAME=my-shop DEST=../my-shop
cd ../my-shop
```

The script copies the repo, renames `python-demo` → `my-shop` everywhere (chart, manifests, docs),
renames `helm/python-demo` → `helm/my-shop`, validates the config and makes a first git commit.
(On GitHub you can also click **Use this template** and then run the script inside the new clone.)

## 2. Describe your app in `app.config.yaml`

| Section | What you put there | Who consumes it |
|---|---|---|
| `metadata` | name, version, owner, labels | everything (names, tags, image tags) |
| `sources.imageRegistry` | where images are pulled from (`""` = local, `x.azurecr.io`) | Helm, scripts, Terraform, Ansible |
| `sources.files[]` | external URLs to download onto hosts (+ optional sha256) | `setup/configure.sh`, Ansible, cloud-init |
| `services[]` | one entry per container: build context, image, **ports** (`expose: none/cluster/public`), **config** (→ ConfigMap), **secrets** (keys only → Secret), health, **scale** (+HPA), resources, **network.allowFrom** (→ NetworkPolicy) | Helm chart, compose, Terraform, Ansible |
| `kubernetes` | namespace, network-policy defaults, ingress | Helm chart |
| `hosts` | base Linux image (docker + Azure), packages, **exposePorts** (ufw + NSG), setup/configure scripts, Ansible playbook, host settings | `setup/*.sh`, cloud-init, Terraform VM/NSG, Ansible |
| `targets.local` / `targets.azure` | kind cluster name, Azure region/sizes/tiers/network policy engine | scripts + Terraform |

Run `make validate` after every change; the JSON Schema in `schema/` catches typos, bad ports,
unknown services in `allowFrom`, etc. `make show` prints what will be built.

Placeholders `${name}`, `${version}`, `${registry}` are expanded everywhere, so the name appears
in exactly one place.

## 3. Add a service

```yaml
services:
  - name: worker
    build: { context: apps/worker }
    image: { repository: ${name}-worker }
    ports: [{ name: http, containerPort: 9000, servicePort: 80, expose: none }]   # nothing may call it
    config: { QUEUE: orders }
    secrets: [{ name: DB_PASSWORD }]
    scale: { replicas: 1 }
```

Create `apps/worker/Dockerfile`, add `DB_PASSWORD=...` to `secrets.env`, then `./scripts/02-build-images.sh
&& ./scripts/03-load-images.sh && ./scripts/04-deploy-helm.sh`. No YAML manifests, no Helm edits.

## 4. Provide setup / configure scripts for base Linux hosts

`hosts.setupScript` and `hosts.configureScript` point at bash scripts that receive
`host-config.env` (rendered from the schema) and `host-files.tsv` (the `sources.files` list).
Replace `setup/*.sh` with your own, keep the same inputs, and every path (Azure VM via cloud-init,
Terraform local "host" container, Ansible role) keeps working. See `docs/05-base-linux-setup-and-ansible.md`.

## 5. Things you may want to change

* `helm/<name>/values.yaml` — chart defaults (only if you add new chart features)
* `terraform/*/terraform.tfvars` — per-environment Terraform inputs
* `.env` — per-machine overrides for the scripts (Azure subscription, ACR name)
* `.github/workflows/validate.yml` — CI: schema, shellcheck, helm lint, kubeconform, ansible-lint, terraform validate
