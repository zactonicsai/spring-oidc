# podkit — deploy pods to existing EKS, AKS and GKE clusters

One YAML file per pod (`PodConfig`) → a small Python generator (`podgen`) → ready-to-run
**kubectl scripts** and a **Terraform root module** for AWS, Azure or GCP, plus an in-cluster
**command pod** that runs **Ansible playbooks or shell scripts** to configure the pod before or
after it starts. One CLI, `podkit`, drives every resource; each resource is a plugin you can
extend or replace.

```
PodConfig (YAML)  ──podgen──▶  build/<cloud>/<name>/  ──podkit──▶  cluster + cloud
                                ├── deploy.sh / destroy.sh / configure.sh   wrappers around the CLI
                                ├── pod.env                                 the build's settings
                                ├── k8s/*.yaml                              manifests (kubectl path)
                                ├── terraform/*.tf                          root module (Terraform path)
                                └── ansible/vars.yml, configure.env         config-step inputs
```

New here? Read **[TUTORIAL.md](TUTORIAL.md)** first — it walks through one example step by step
and then explains every part.

## Quick start

```bash
pip install -r requirements.txt                          # PyYAML, Jinja2, jsonschema
make install                                             # symlinks bin/podkit into ~/.local/bin (or PREFIX=/usr/local)

podkit validate examples/*.yaml
podkit generate examples/pg-client.yaml --provider aws   # or azure | gcp | all  -> build/aws/pg-client

podkit cluster login build/aws/pg-client                 # kubeconfig for the EXISTING cluster (from pod.env)
podkit doctor build/aws/pg-client                        # tools, cloud CLI, cluster access
podkit command-pod deploy                                # once per cluster (COMMAND_POD_IMAGE=...)
podkit pod deploy build/aws/pg-client                    # kubectl path
podkit pod deploy build/aws/pg-client -m terraform       # or the Terraform path (creates the cloud identity too)
podkit pod status build/aws/pg-client
podkit destroy build/aws/pg-client --everything          # workload + secrets + TLS + identity + namespace
```

Every command accepts `--dry-run` (print every kubectl/terraform/cloud command instead of running
it), `-y` (no prompts) and `--context CTX`.

## The CLI: one resource per plugin

| Resource | Verbs | What it manages |
| --- | --- | --- |
| `config` | `generate validate schema` | PodConfig files (`podkit generate` / `validate` are shortcuts) |
| `cluster` | `login status contexts` | kubeconfig for the existing EKS/AKS/GKE cluster |
| `doctor` | `check` | local tools, cloud CLI, cluster access |
| `image` | `build push` | the command pod image |
| `command-pod` | `deploy ensure grant revoke scale status shell run sync destroy` | the in-cluster command pod and its namespaced RBAC |
| `namespace` | `create status list destroy` | namespaces (destroy only removes ones podkit created, unless `--force`) |
| `secret` | `sync get set list destroy` | Secrets, including the cloud-store → `<name>-env` sync |
| `identity` | `apply bind status destroy` | the pod's cloud identity (Terraform `module.cloud` only) |
| `tls` | `issue rotate status destroy` | CA, per-pod keystore, shared truststore Secrets |
| `configure` | `run script info` | a build's Ansible/shell step, or any script inside the pods |
| `pod` | `deploy destroy status logs restart scale exec diff list` | the workload (kubectl or Terraform path) |
| `destroy` | `build all plan` | orchestrated teardown: a build with its dependencies, or everything podkit created |
| `status` | `show` | overview of the podkit footprint in the cluster |

`podkit resources` lists them, `podkit help <resource>` shows every verb with its options.
`scripts/deploy.sh`, `scripts/destroy.sh`, `scripts/command-pod.sh` and `scripts/cluster-login.sh`
still work; they are wrappers around the CLI.

### Destroying things

```bash
podkit pod destroy BUILD_DIR [-m terraform] [--purge-tls] [--delete-namespace]   # just the workload
podkit destroy BUILD_DIR --tls --identity --namespace     # pick the dependent resources to remove
podkit destroy BUILD_DIR --everything                     # all of them, one confirmation
podkit destroy plan BUILD_DIR --everything                # show the plan, change nothing
podkit destroy all --builds build --command-pod --namespaces   # every podkit-labelled object in the cluster,
                                                          # `terraform destroy` of every build with state, the command pod, podkit namespaces
podkit tls destroy BUILD_DIR --ca ; podkit secret destroy NS NAME ; podkit identity destroy BUILD_DIR ; podkit namespace destroy NS
```

### Adding a resource (plugin)

A resource is one bash file that only defines things. Drop it in `scripts/resources/`,
`plugins/`, a directory on `$PODKIT_PLUGIN_PATH`, or `~/.podkit/plugins/`; a file with the name
of a built-in replaces it. Start from `scripts/resources/_template.sh`:

```bash
RESOURCE_DESC="Redis cache for a pod build"           # required
RESOURCE_VERBS="deploy status destroy"                # required: one cmd_<verb> per verb
resource_usage() { cat <<'U'
  podkit redis deploy BUILD_DIR
  podkit redis destroy BUILD_DIR
U
}
redis_deploy()  { build_load "$1"; kube -n "$NAMESPACE" apply -f "$PODKIT_ROOT/plugins/redis/redis.yaml"; }
redis_destroy() { build_load "$1"; confirm "Delete redis for $NAME?" || return 0; kube -n "$NAMESPACE" delete -f "$PODKIT_ROOT/plugins/redis/redis.yaml" --ignore-not-found; }
cmd_deploy()  { redis_deploy "$1"; }
cmd_status()  { build_load "$1"; kube -n "$NAMESPACE" get pods -l app=redis; }
cmd_destroy() { redis_destroy "$1"; }
```

Helpers available to plugins (`scripts/lib/common.sh`): `build_load DIR` (exports `pod.env`),
`kube` (kubectl with context and `--dry-run` support), `tf DIR ...` (terraform/tofu), `run CMD`
(any command, dry-run aware), `confirm`, `log/warn/die`, `require_cmd`, `render_template`,
`set_env_value`, `managed_label`. `plugin_source secret tls` loads other plugins as libraries
(`secret_sync_build`, `tls_destroy`, `identity_bind_build`, `configure_run_build`, ...).
`cmd__default` handles calls without a verb (`podkit status`, `podkit destroy BUILD_DIR`).

## What is in the box

| Path | What it is |
| --- | --- |
| `bin/podkit` | The CLI dispatcher (global options, plugin discovery) |
| `scripts/resources/` | One plugin per resource (`_template.sh` to start your own) |
| `scripts/lib/` | `common.sh` (helpers), `plugin.sh` (discovery), `cloud.sh` (secret stores) |
| `scripts/configure.sh` | Low-level runner that executes a playbook/script inside the command pod (or locally) |
| `schema/pod-config.schema.json` | JSON Schema for `PodConfig` (validated on every run) |
| `podgen/` | The generator: `validate`, `generate`, `schema` |
| `examples/` | `pg-client.yaml` (external PostgreSQL), `java-server.yaml` + `java-client.yaml` (pod-to-pod mTLS with Java keystores), `java-mtls/` sources |
| `terraform/modules/pod` | Cloud-agnostic workload (Deployment, Service, ServiceAccount, ConfigMap, NetworkPolicy, HPA) |
| `terraform/modules/{aws,azure,gcp}` | Read the existing cluster, resolve secrets, create the pod's cloud identity, spot hints |
| `terraform/modules/command-pod` | The command pod as a Terraform module |
| `command-pod/` | Dockerfile (kubectl, Ansible, openssl, keytool, psql) and kubectl manifests |
| `ansible/playbooks/` | `java-keystore.yml`, `postgres-client.yml`, `run-script.yml` |
| `configure/` | Shell twins of the playbooks: `java-keystore.sh`, `postgres-client.sh`, `run-script.sh` |
| `tests/` | `pytest`: generator (every example × every cloud) and CLI (discovery, help, dry-run flows) |

## The two examples

1. **Pod that talks to an external PostgreSQL database** (`examples/pg-client.yaml`):
   the password is read from Secrets Manager / Key Vault / Secret Manager at deploy time, the
   NetworkPolicy only allows DNS, cloud APIs and the database subnet, and a post-deploy Ansible
   step checks the connection, runs `bootstrap.sql` and pushes a runtime config into the pods.
2. **Pod-to-pod TLS with a Java keystore** (`examples/java-server.yaml`, `examples/java-client.yaml`,
   `examples/java-mtls/`): a pre-deploy step creates a CA per namespace, issues a certificate per
   pod and publishes `keystore.jks` / `truststore.jks` as Secrets. The server requires a client
   certificate; the client presents one. The server uses the Ansible step, the client the shell
   step, to show both.

## Design in one paragraph

Everything runs against a cluster you already have. Secrets never touch git: they are pulled from
the cloud secret store when you deploy. Each pod gets its own ServiceAccount bound to a cloud
identity (IRSA / Pod Identity, Azure Workload Identity, GKE Workload Identity). Requests and
limits are always set, spot capacity is one flag away, Services are `ClusterIP` unless you ask
otherwise, and the command pod is a 50 mCPU / 128 MiB pod you scale to zero when idle. No
operators, no CRDs, no cluster-wide RBAC. Every mutating command can be previewed with `--dry-run`.

## Development

```bash
make venv && source .venv/bin/activate
make test          # pytest (generator + CLI)
make generate      # all examples, all clouds -> build/
make lint          # bash -n, shellcheck (if installed), terraform fmt -check (if installed)
```
