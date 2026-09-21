# Changelog

## 2.2.0 — developer pod, OIDC clients, monitoring

### Added
- `images/devbox/`, `k8s/devbox/`, `scripts/devbox.sh`: Java/C++/Go developer pod (Temurin 25, Maven,
  Gradle 9.6, gcc/clang/cmake/gdb/valgrind, Go 1.27, kubectl/helm) with non-root sshd on 2222,
  persistent home, SSH exposed via LoadBalancer/NodePort + port-forward.
- `k8s/keycloak/realm-demo.json` + `keycloak.sh realm|url`: demo realm (groups, users, clients
  `cli-java` device grant, `cli-go` code+PKCE/device), imported with `--import-realm`.
- `examples/oidc-java-cli` (Nimbus JOSE+JWT, device flow, JWKS verification, group check) and
  `examples/oidc-go-cli` (go-oidc + x/oauth2, code+PKCE loopback or device flow, group check).
- `k8s/monitoring/`, `scripts/monitoring.sh`: kube-prometheus-stack values, ServiceMonitors
  (Keycloak, python-demo), PrometheusRule alerts, Grafana dashboard, scrape network policies.
- Flask apps expose `/metrics` (prometheus-flask-exporter, gunicorn multiprocess mode); Keycloak
  HTTP histograms + user-event metrics enabled; port 9000 on the internal headless Service.
- Tutorials `docs/10`, `docs/11`, `docs/12`; `make devbox*`, `oidc-*`, `monitoring*`.

## 2.1.0 — Keycloak

### Added
- `k8s/keycloak/` + `scripts/keycloak.sh`: Keycloak 26.7 with Postgres 17, 2+ replicas (HPA min 2,
  PodDisruptionBudget, topology spread, zero-unavailable rolling updates), JGroups DNS_PING clustering,
  default-deny network policies, port 80 → 8080 exposed as LoadBalancer (AKS) or NodePort + port-forward (kind).
- `docs/09-keycloak.md`, `make keycloak`.

## 2.0.0 — template + Azure + Terraform + Ansible expansion

### Added
- `app.config.yaml` + `schema/app-config.schema.json`: one schema-validated file describing services,
  ports (`expose: none|cluster|public`), config settings, secret keys, image/file sources, scaling,
  network rules, base-Linux host setup and deployment targets.
- `tools/appconfig.py`: validate / show / render (Helm values, `config.env`, host config,
  per-service env files, cloud-init, docker-compose, secrets values).
- `scripts/azure/`: complete `az` CLI path — login, RG + ACR, `az acr build`, AKS (Cilium network
  policy, autoscaler, ACR attach, workload identity, Key Vault CSI addon), credentials, Helm deploy
  with LoadBalancer, tests, pod/node scaling, Key Vault secrets, NSG/LB lockdown, base Linux VM via
  cloud-init, Ansible run, status, destroy.
- `terraform/`: shared `modules/app-config`; roots `local-docker` (plain Docker + base host
  container), `local-kind` (kind + metrics-server + Helm), `azure` (ACR, AKS, Key Vault, VM with
  NSG rules from the schema, Helm release, Ansible inventory).
- `setup/setup.sh` + `setup/configure.sh`: idempotent base-Linux host configuration (packages,
  Docker, ufw, users, timezone, downloaded files with sha256 checks, settings, containers with
  password-less ACR pull via managed identity).
- `ansible/`: playbook + `base-linux` role that reads `app.config.yaml` directly.
- Local scripts 07 (scaling), 08 (secrets), 09 (network), 10 (cleanup), template bootstrap script,
  metrics-server install for HPA demos, network-policy negative test.
- `docs/`: middle-school-level tutorial with grocery-store/school analogies, phase-by-phase
  walkthroughs, Azure, Terraform, schema, host-setup, best-practices/pros-cons, cheat sheet,
  troubleshooting.
- `Makefile`, `.env.example`, `secrets.env.example`, CI workflow, `TEMPLATE.md`.

### Changed
- Helm chart rewritten as a generic loop over `services`; adds ConfigMap, Secret, HPA,
  NetworkPolicy (default-deny + allow-lists), Ingress, ServiceAccount, `helm test`,
  checksum annotations, `loadBalancerSourceRanges`, stricter pod security.
- Kubernetes resource names are now `<app>-<service>` (`python-demo-web`) instead of `python-web`.
- The chart no longer creates the Namespace (use `--create-namespace`, the standard practice).
- Apps: web calls the api over the cluster network, both expose `/config`, api exposes
  `/api/work` (CPU burn for HPA demos); images are multi-stage, non-root, run gunicorn.
- Raw `k8s/` manifests extended with namespace, ConfigMaps, example Secret, HPA, NetworkPolicies.
- Scripts are schema-driven (no hard-coded names) and Helm-4 aware.

## 1.0.0
- Original kind + Helm + two Flask apps demo.
