# Troubleshooting

*Symptom → cause → fix. Grouped by where you are in the flow. The universal first three moves:*
`kubectl -n python-demo get pods` · `kubectl -n python-demo describe pod <pod>` (read **Events**) ·
`kubectl -n python-demo logs <pod> [--previous]`.

---

## Prerequisites and config

| Symptom | Cause | Fix |
|---|---|---|
| `00-check-prereqs.sh`: *docker is not running* | Docker Desktop/daemon stopped | start Docker; `docker info` |
| `app.config.yaml: ... services/api/network/allowFrom: unknown service 'wbe'` | typo | fix the name; `make validate` |
| `jsonschema not installed — only basic checks` | Python deps missing | `pip install -r tools/requirements.txt` |
| `helm: command not found` / *Helm 3 detected* | Helm missing/old | install Helm 4 (https://helm.sh/docs/intro/install/) |
| `permission denied: ./scripts/...` | not executable | `chmod +x scripts/*.sh scripts/*/*.sh setup/*.sh` |
| `WARNING: no value for secret(s) api.API_TOKEN in secrets.env` | file missing | `cp secrets.env.example secrets.env` |

## kind

| Symptom | Cause | Fix |
|---|---|---|
| `kind create cluster` hangs / `ERROR: failed to create cluster` | Docker low on memory/disk; old node image | give Docker ≥ 4 GB; `docker system prune`; update kind |
| `kubectl` talks to the wrong cluster | context | `kubectl config use-context kind-python-demo` |
| Pods `ImagePullBackOff` right after deploy | image not loaded into kind nodes | `./scripts/03-load-images.sh`; verify with `docker exec python-demo-worker crictl images \| grep python-demo` |
| Rebuilt image but pods run old code | same tag + `IfNotPresent` | `03-load-images.sh` then `kubectl -n python-demo rollout restart deploy/python-demo-api` |
| `port-forward`: *address already in use* | 8080 busy | `lsof -i :8080`; use another local port `8081:80` |
| Cluster slow on Apple Silicon | amd64 images under emulation | build without `--platform` locally (arm64) or accept slower starts |
| `kind load` fails: *image not present locally* | build failed/wrong name | `docker images \| grep python-demo`; rerun `02-build-images.sh` |

## Pods and Deployments

| Symptom | Cause | Fix |
|---|---|---|
| `CrashLoopBackOff` | app exits at start (bad env, missing module) | `logs --previous`; run the image locally: `docker run --rm -it -e API_URL=x python-demo-web:1.0.0` |
| `Running` but `READY 0/1` | readiness probe failing | `curl` `/health` via `port-forward`; check `health.path` and port in the config |
| `Pending` forever | no node fits `resources.requests`; or `maxReplicas` beyond capacity | `describe pod` → *Insufficient cpu*; lower requests or add nodes (AKS autoscaler) |
| `OOMKilled` | memory limit too low | raise `resources.limits.memory` |
| Pods restart every few minutes | liveness too strict / slow start | raise `livenessInitialDelaySeconds` |
| Deployment replicas keep changing back | HPA owns the count | change `scale.autoscale` in the config, not `kubectl scale` |
| `helm upgrade` reset my manual scale | replicas in values | with HPA enabled the chart omits replicas; without it, the config value wins |

## Helm

| Symptom | Cause | Fix |
|---|---|---|
| `Error: UPGRADE FAILED: ... field is immutable` | changed a selector/label or Service `clusterIP` | `helm uninstall` + reinstall (or `kubectl delete` the object) |
| `--wait` times out | pods never became Ready; RBAC lacks `watch` (Helm 4 kstatus) | look at pods first; in CI grant `watch` on the namespace |
| `flag --atomic has been deprecated` | Helm 4 rename | use `--rollback-on-failure` (`--force` → `--force-replace`) |
| `Error: INSTALLATION FAILED: cannot re-use a name that is still in use` | failed release left behind | `helm list -n python-demo -a`; `helm uninstall` or `helm rollback` |
| `helm template` shows empty ConfigMap/no HPA | value missing/false | `helm get values`; check `build/helm-values.yaml` was re-rendered |
| Namespace already exists errors with `04-deploy-kubectl.sh` after Helm | both paths used | `10-cleanup-apps.sh`, then one path only |

## Network policy

| Symptom | Cause | Fix |
|---|---|---|
| `09-network.sh test`: stranger pod **succeeds** | CNI not enforcing: kind < 0.24, or AKS without `--network-policy` | upgrade kind; on AKS check `az aks show … networkProfile.networkPolicy` |
| web → api **blocked** | `allowFrom` missing or labels changed | `network.allowFrom: [web]`; `kubectl describe netpol python-demo-api-allow` |
| Probes fail after enabling policies | kubelet probes come from the node; most CNIs exempt them, some don't | allow ingress from the node CIDR on the health port, or keep default-deny to `Ingress` only (as here) |
| Pods can't resolve DNS after adding egress policies | DNS blocked | allow UDP/TCP 53 to `kube-dns` in `kube-system` first |
| `port-forward` reaches api despite the policy | port-forward bypasses the CNI | expected; test with a pod (the script does) |

## HPA / scaling

| Symptom | Cause | Fix |
|---|---|---|
| `TARGETS <unknown>/70%` | metrics-server missing/unhealthy, or no CPU requests | `kubectl -n kube-system get deploy metrics-server`; `kubectl top pods`; set `resources.requests.cpu` |
| metrics-server `CrashLoopBackOff` on kind | kubelet TLS | it needs `--kubelet-insecure-tls` (script and Terraform set it) |
| HPA never scales up under load | load pod blocked by network policy; target too high | the load pod wears web's labels (script does); watch `kubectl top pods` |
| Scales down slowly | stabilisation window | expected (60 s here; 5 min default) |
| AKS pods `Pending`, nodes don't grow | autoscaler off or at `maxCount` | `./scripts/azure/07-scale.sh status`; raise `maxCount` |

## Secrets

| Symptom | Cause | Fix |
|---|---|---|
| api shows an empty masked token | value missing when rendered | `secrets.env` present? re-run `04-deploy-helm.sh`; on Azure `08-secrets.sh deploy` |
| Rotated secret but pods still show the old value | pods not restarted | the chart's checksum annotation restarts them on `helm upgrade`; check `helm get manifest … \| grep checksum` |
| `az keyvault secret set`: *Forbidden* | RBAC not applied yet / wrong role | wait 1–2 min after `08-secrets.sh create`; you need *Key Vault Secrets Officer* |
| Key Vault name *already exists* after destroy | soft delete | `az keyvault purge --name <kv>` (99-destroy does it) or set `AZ_KEYVAULT_NAME_OVERRIDE` |

## Azure / ACR / AKS

| Symptom | Cause | Fix |
|---|---|---|
| `MissingSubscriptionRegistration` | provider not registered | `./scripts/azure/00-login.sh` (registers them) |
| `ACR name '…' is taken` | global namespace | `.env`: `AZ_ACR_NAME_OVERRIDE=<letters+digits>` |
| `ImagePullBackOff` on AKS, *unauthorized* | ACR not attached / role not propagated | `az aks update -g rg -n aks-python-demo --attach-acr <acr>`; wait 2–5 min; `kubectl rollout restart` |
| `ImagePullBackOff`, *manifest unknown* | wrong tag or images built before `--registry` set | `az acr repository show-tags`; rerun `02-build-push-images.sh` |
| `az aks create`: *quota exceeded* | vCPU quota in region | smaller size / fewer nodes / another region / request quota |
| `az aks create`: version not supported | version list changed | `az aks get-versions -l <region>`; clear `kubernetesVersion` for the default |
| LoadBalancer `EXTERNAL-IP <pending>` for > 5 min | LB creation failing (quota, NSG, subnet) | `kubectl describe svc python-demo-web` → Events |
| `lock-to-me` blocks *you* | NAT/IPv6/VPN changes your IP | `./scripts/azure/09-network.sh unlock`; use your real egress IP |
| Cost keeps ticking after tests | resources left | `./scripts/azure/99-destroy.sh`; check Portal → Resource groups |
| `az aks command invoke` needed | private/no local access | works without kubeconfig; handy on locked-down laptops |

## VM / cloud-init / Ansible

| Symptom | Cause | Fix |
|---|---|---|
| `curl http://<vm ip>/` connection refused | cloud-init still running, or containers didn't start | `ssh … sudo tail -f /var/log/cloud-init-output.log`; `docker ps` |
| cloud-init: *custom data too large* | > 64 KB | trim `sources.files`/settings; scripts are ≈ 15 KB total |
| `configure.sh`: *managed-identity login failed* | AcrPull not assigned or not propagated | `10-create-vm.sh` assigns it; wait, then `sudo bash /opt/python-demo/configure.sh` |
| `ufw` locked me out of SSH | port 22 missing from `hosts.exposePorts` | keep the `ssh` entry; use `az vm run-command invoke … 'ufw allow 22/tcp'` to recover |
| Ansible: *Failed to connect to the host via ssh* | wrong key/user/IP; NSG blocks 22 | `ssh -i ~/.ssh/id_rsa azureuser@<ip>`; `hosts.exposePorts` ssh `source` |
| Ansible: *couldn't resolve module community.docker.*…* | collections missing | `ansible-galaxy collection install -r requirements.yml` |
| Ansible: *The 'community.general.yaml' callback plugin has been removed* | old `stdout_callback = yaml` | use `callback_result_format = yaml` (already set) |
| Ansible `apt_repository` deprecation | ansible-core ≥ 2.19 | the role uses `deb822_repository` |
| Ansible in a container: ufw/timezone skipped | `in_container` detection | expected — no `NET_ADMIN`/systemd in containers |
| Ansible `--check` fails at `get_url` | directory not created in check mode | expected in check mode; the real run creates it first |

## Terraform

| Symptom | Cause | Fix |
|---|---|---|
| `terraform validate`: *Unsupported argument* in `azurerm_*` | provider major renamed a field | check the AzureRM 4/5 upgrade guide; the project targets 4.40–5.x |
| `Error: Unsupported block type "kubernetes"` in the helm provider | Helm provider 3.x syntax | `kubernetes = { … }` (nested attribute), `set = [{ … }]` |
| `subscription_id is a required provider property` | AzureRM 4+ | `export ARM_SUBSCRIPTION_ID=…` or `subscription_id` var |
| Plan wants to recreate the AKS cluster | changed an immutable field (network profile, dns_prefix) | expected; or `terraform state rm` + reimport if you must keep it |
| Helm release fails on first `apply` (*connection refused*) | provider configured from a not-yet-created cluster | apply again; or split infra/apps roots (see 03 Part 5) |
| `az acr build` provisioner fails | not logged in / no `az` | `az login`; or `build_images = false` and push in CI |
| `terraform destroy` stuck on Key Vault | purge protection | `purge_protection_enabled` is false here; otherwise wait or purge manually |
| `local-docker`: *Cannot connect to the Docker daemon* | socket path | set `docker_host` (`npipe:////./pipe/docker_engine` on Windows) |
| `local-kind`: `kind load` errors | kind CLI missing locally | install kind (the provider creates the cluster, `kind load` needs the CLI) |
| State file contains secrets | by design | remote encrypted backend + RBAC; never commit `*.tfstate` |
| OpenTofu users | same files | `tofu init/plan/apply`; registry addresses are the same |

## When all else fails

```bash
kubectl -n python-demo get events --sort-by=.metadata.creationTimestamp | tail -30
kubectl -n python-demo describe deploy python-demo-api
kubectl -n kube-system get pods            # is the cluster itself healthy?
helm -n python-demo history python-demo && helm -n python-demo rollback python-demo <n>
./scripts/10-cleanup-apps.sh && ./scripts/run-all.sh     # local: 5 minutes to a clean slate
```

Still stuck? Open an issue with: the script you ran, its last 30 lines of output,
`kubectl version`, `helm version`, `kind version`/`az version`, and your OS.
