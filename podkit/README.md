# podkit — deploy pods to existing EKS, AKS and GKE clusters

One YAML file per pod (`PodConfig`) → a small Python generator (`podgen`) → ready-to-run
**kubectl scripts** and a **Terraform root module** for AWS, Azure or GCP, plus an in-cluster
**command pod** that runs **Ansible playbooks or shell scripts** to configure the pod before or
after it starts.

```
PodConfig (YAML)  ──podgen──▶  build/<cloud>/<name>/
                                ├── deploy.sh / destroy.sh / configure.sh   kubectl path
                                ├── k8s/*.yaml                              manifests
                                ├── terraform/*.tf                          Terraform path
                                ├── ansible/vars.yml, configure.env         config-step inputs
                                └── pod.env                                 cluster settings
```

New here? Read **[TUTORIAL.md](TUTORIAL.md)** first — it walks through one example step by step
and then explains every part.

## Quick start

```bash
pip install -r requirements.txt                      # PyYAML, Jinja2, jsonschema
python -m podgen validate examples/*.yaml
python -m podgen generate examples/pg-client.yaml --provider aws      # or azure | gcp | all

scripts/cluster-login.sh -p aws -c demo-eks -r us-east-1              # kubeconfig for the EXISTING cluster
scripts/command-pod.sh deploy                                         # once per cluster (COMMAND_POD_IMAGE=...)
scripts/deploy.sh build/aws/pg-client                                 # kubectl path
scripts/deploy.sh -m terraform build/aws/pg-client                    # or the Terraform path
scripts/destroy.sh build/aws/pg-client
```

## What is in the box

| Path | What it is |
| --- | --- |
| `schema/pod-config.schema.json` | JSON Schema for `PodConfig` (validated on every run) |
| `podgen/` | The generator: `validate`, `generate`, `schema` sub-commands |
| `examples/` | `pg-client.yaml` (external PostgreSQL), `java-server.yaml` + `java-client.yaml` (pod-to-pod mTLS with Java keystores), `java-mtls/` sources |
| `terraform/modules/pod` | Cloud-agnostic workload (Deployment, Service, ServiceAccount, ConfigMap, NetworkPolicy, HPA) |
| `terraform/modules/{aws,azure,gcp}` | Read the existing cluster, resolve secrets, create the pod's cloud identity, spot hints |
| `terraform/modules/command-pod` | The command pod as a Terraform module |
| `scripts/` | `cluster-login.sh`, `deploy.sh`, `destroy.sh`, `command-pod.sh`, `configure.sh` (+ `lib/`) |
| `command-pod/` | Dockerfile (kubectl, Ansible, openssl, keytool, psql) and kubectl manifests |
| `ansible/playbooks/` | `java-keystore.yml`, `postgres-client.yml`, `run-script.yml` |
| `configure/` | Shell twins of the playbooks: `java-keystore.sh`, `postgres-client.sh`, `run-script.sh` |
| `tests/` | `pytest` suite (generates every example for every cloud) |

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
operators, no CRDs, no cluster-wide RBAC.

## Development

```bash
make venv && source .venv/bin/activate
make test          # pytest
make generate      # all examples, all clouds -> build/
make lint          # bash -n + terraform fmt -check
```
