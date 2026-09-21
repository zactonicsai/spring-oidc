Depends on which path you took.

## In-place upgrade → nothing changes

The API server FQDN, cluster CA, and your existing kubeconfig all stay the same. Two things to check anyway:

- **kubectl version skew.** kubectl must be within one minor of the API server, so after landing on 1.36 a 1.27 kubectl will misbehave. Run `az aks install-cli` or update kubectl to 1.35–1.37.
- **kubelogin.** If the cluster uses Entra ID auth (`--enable-aad`), make sure your clients and CI agents have a current `kubelogin`; very old versions can fail against newer AKS token flows. `az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli` still works as before.

## New (blue/green) cluster → yes, re-point everything

Fetch fresh credentials:

```bash
az aks get-credentials -g <rg> -n <new-cluster> --overwrite-existing
kubelogin convert-kubeconfig -l azurecli      # if Entra ID auth
kubectl config get-contexts                   # you'll now have both old and new
```

Then update everything that referenced the old cluster:

- **CI/CD**: Azure DevOps service connections, GitHub Actions `azure/aks-set-context` inputs, Argo CD / Flux cluster secrets, Terraform state — all point at the cluster resource ID or FQDN.
- **RBAC**: Entra ID group assignments (`Azure Kubernetes Service RBAC Admin/Writer`, cluster-admin group) are per cluster; re-assign them. If you disabled local accounts (`--disable-local-accounts`), nobody can connect without those assignments.
- **Network access**: authorized IP ranges, or for a private cluster the private DNS zone link and VPN/ExpressRoute route to the new API server IP. A private cluster gets a new `*.privatelink.<region>.azmk8s.io` record, so DNS-forwarding rules on-prem need updating.
- **Identities**: the new cluster has a new kubelet identity and control-plane identity; re-grant ACR pull (`--attach-acr`), Key Vault access, and any federated credentials for Workload Identity (the OIDC issuer URL is new, so every federated credential in Entra must be recreated with the new issuer).
- **Monitoring/tools**: Log Analytics workspace links, Prometheus/Grafana data sources, Defender, cost tooling, and any `kubectl` contexts on bastion hosts.

The Workload Identity issuer and the RBAC assignments are the two that most often get missed and only show up as "pods can't get tokens" or "CI can't connect" after cutover.

## 1. Live in-cluster events (the closest thing to a progress log)

AKS writes `Surge`, `Drain`, `Upgrade`, and `Cordon`-type events into the `default` namespace against each node as it works through the pool:

```bash
# Follow it live
kubectl get events -n default -w --sort-by=.lastTimestamp \
  --field-selector involvedObject.kind=Node

# Or just the upgrade-related reasons
kubectl get events -A -w | grep -E "Surge|Drain|Upgrade|Cordon|Evict|Soak"
```

You'll see lines like "Created a surge node vmss000005 for agentpool nodepool1", "Draining node: [vmss000001]", "Soak duration 5m0s after draining node ...", then "Delete surge node ...". A node stuck at "Draining" for longer than your `drain-timeout` is the one to inspect:

```bash
kubectl get nodes -o wide -w                       # watch versions flip, SchedulingDisabled appear/clear
kubectl get pods -A -o wide --field-selector spec.nodeName=<draining-node>
kubectl get events -n <ns> --field-selector involvedObject.name=<pod> -w   # eviction errors per pod
kubectl get pdb -A -w                              # ALLOWED DISRUPTIONS ticking down/up
```

Events only live for an hour by default, so if you want them for a post-mortem, ship them out (Container Insights `KubeEvents` table, or `kubectl get events -A -o json > upgrade-events.json` periodically).

## 2. ARM-side operation status

```bash
# Poll the operation (aks-preview extension)
watch -n 30 'az aks operation show-latest -g <rg> -n <cluster> \
  --query "{Status:status, Start:startTime, Error:error}" -o json'

# Per pool: which nodes have moved
watch -n 30 'az aks nodepool show -g <rg> --cluster-name <cluster> -n <pool> \
  --query "{State:provisioningState, Ver:currentOrchestratorVersion, Count:count}" -o table'

# If you started it with --no-wait, block until done
az aks wait -g <rg> -n <cluster> --updated --interval 30 --timeout 7200
```

`az aks operation show-latest` gives status only (`InProgress`/`Succeeded`/`Failed`); it doesn't stream node-by-node progress. That detail is in the events above and the portal.

## 3. Portal

Cluster → **Node pools** → the pool being upgraded shows an "Upgrading (x of y nodes)" style status, and **Activity log** lists the running `Create or Update Agent Pool` operation with its correlation ID. **Diagnose and solve problems → Cluster and Node Pool Upgrade Failures** refreshes while the operation runs and often names the blocking pod before the operation formally fails.

## 4. Control-plane logs in Log Analytics (if diagnostic settings are on)

```kusto
// Evictions the API server rejected during the drain
AKSAudit
| where TimeGenerated > ago(2h)
| where RequestUri has "eviction" and ResponseStatus.code >= 400
| project TimeGenerated, User.username, RequestUri, ResponseStatus.code, ResponseStatus.message

// Upgrade events if Container Insights is enabled
KubeEvents
| where TimeGenerated > ago(2h)
| where Reason in ("Drain","Surge","Upgrade","Cordon") or Message has "evict"
| project TimeGenerated, Name, Reason, Message
```

The `kube-audit-admin` category is enough for eviction failures; `kube-controller-manager` shows the node lifecycle side. Both need to be enabled *before* the upgrade to be useful.

## Tip for auto-upgrades

Since you won't be at a terminal when the maintenance window fires, put an alert on it: an Azure Monitor alert on `KubeEvents | where Reason == "Drain"` firing more than N times for the same node, or a Service Health/Activity Log alert on `Microsoft.ContainerService/managedClusters/agentPools/write` with status `Failed`, plus a Resource Health alert on the cluster. That way you get the in-progress trail even for upgrades you didn't start.

## 1. Find the failed operation and its error

```bash
# Is the cluster or a node pool in Failed state?
az aks show -g <rg> -n <cluster> \
  --query "{State:provisioningState, Power:powerState.code, Ver:currentKubernetesVersion, AutoUpgrade:autoUpgradeProfile}" -o table

az aks nodepool list -g <rg> --cluster-name <cluster> \
  --query "[].{Name:name, State:provisioningState, Ver:currentOrchestratorVersion, Image:nodeImageVersion}" -o table

# The actual error (needs aks-preview extension)
az extension add --name aks-preview --upgrade --yes
az aks operation show-latest -g <rg> -n <cluster> \
  --query "{Id:name, Status:status, Start:startTime, End:endTime, Error:error}" -o json
# add --nodepool-name <pool> for a node-pool operation
```

The `error` block has `code`, often a `subcode`, and a `details[]` array. For upgrades the outer code is usually a wrapper like `UpgradeVMSSAgentPoolFailed`; the real reason is in `details`.

## 2. Pull the full history from the activity log

Auto-upgrader operations that were rejected before starting don't always become the "latest operation," so query the log with a wide window:

```bash
TARGET=$(az aks show -g <rg> -n <cluster> --query id -o tsv)
az monitor activity-log list --resource-id "$TARGET" --offset 14d --status Failed \
  --query "[].{Time:eventTimestamp, Op:operationName.localizedValue, Error:properties.statusMessage, CorrelationId:correlationId}" -o json
```

Repeat with the node pool's resource ID. Keep the correlation IDs; support will ask for them. One caveat: there was a known issue in 2026 where the activity log showed false-positive "upgrade failed" entries for node pool upgrades that actually succeeded, so cross-check against the operation status and the node versions before chasing a ghost.

## 3. In-cluster evidence (drain problems live here)

```bash
kubectl get events -A --sort-by=.lastTimestamp | grep -iE "drain|evict|upgrade|surge|cordon"
kubectl get nodes -o wide                           # mixed versions = stalled mid-pool
kubectl get pdb -A                                  # ALLOWED DISRUPTIONS 0 is the classic blocker
kubectl get pods -A --field-selector spec.nodeName=<stuck-node>
kubectl describe node <stuck-node>                  # look for SchedulingDisabled + remaining pods
```

Also check `kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations` — a webhook whose backing pod died during the drain rejects evictions and everything hangs.

## 4. Control-plane logs and portal tools

- **AKS → Diagnose and solve problems → "Cluster and Node Pool Upgrade Failures"** and **Resource Health** summarize the last failures in plain language.
- If you have diagnostic settings sending `kube-audit-admin`, `kube-controller-manager`, and `cluster-autoscaler` to Log Analytics, `AzureDiagnostics | where Category == "kube-audit-admin" and log_s contains "eviction"` shows every rejected eviction with the PDB name.
- **Azure Advisor** flags `UpgradeBlockedOnDeprecatedAPIUsage` before it bites.

## The error codes you'll see and what they mean

| Code / symptom | Cause | Fix |
|---|---|---|
| `UpgradeFailed` / `PodDrainFailure` / `UnsatisfiablePDB`, "Too Many Requests" on eviction | PDB with 0 allowed disruptions, a pod covered by two PDBs, a pod that ignores SIGTERM, or drain timeout | Loosen the PDB or scale replicas up; delete duplicate PDBs; set `--drain-timeout`, `--undrainable-node-behavior Cordon` |
| `UpgradeBlockedOnDeprecatedAPIUsage` | Manifests still call APIs removed in the target version | Migrate the API; bypass only with `--enable-force-upgrade` + `--upgrade-override-until` as a last resort |
| `QuotaExceeded`, `SubnetIsFull`, `PublicIPCountLimitReached`, `InvalidLoadBalancerProfileAllocatedOutboundPorts` | Surge nodes need extra vCPU, IPs, or SNAT ports | Raise quota / grow subnet / lower `--max-surge` |
| `AllocationFailed`, `ZonalAllocationFailed`, `SkuNotAvailable` | Region or zone out of that VM SKU | Retry later, change SKU, or spread across zones |
| `NodesNotReady`, `UpgradeNodesNotRegistered`, `*VMExtensionError` | New node couldn't bootstrap: outbound firewall, DNS, API server reachability, missing image | Check egress rules (a firewall change since the last upgrade is the usual cause) |
| `AgentPoolUpgradeVersionNotAllowed`, `InvalidParameter` | Version skew or disallowed jump (e.g. the LTS / non-LTS rules from earlier) | Pick a version from `az aks get-upgrades` |
| `OperationNotAllowed`, `AKSOperationPreempted` | Another operation was running, or a delete pre-empted it | Wait; check `operation show-latest` |
| `AgentCountNotMatch` | Something outside AKS (VMSS autoscale, Terraform) changed VMSS capacity mid-surge | Remove the competing scaler |
| `RequestDisallowedByPolicy`, `ResourceLocked`, `AuthorizationFailed` | Azure Policy, a resource lock, or a lost role assignment on the node RG / VNet | Fix the policy, lock, or RBAC |
| `InternalOperationError`, `TimedoutOrCancelled` | Transient | Retry once; open a support case with correlation IDs if it repeats |

## Recover and retry

Once the root cause is fixed, re-run the *same* upgrade to reconcile the Failed state (this is what the auto-upgrader would do on its next window, but you don't have to wait):

```bash
az aks upgrade -g <rg> -n <cluster> --kubernetes-version <same-version>
# or for one pool:
az aks nodepool upgrade -g <rg> --cluster-name <cluster> -n <pool> --kubernetes-version <ver>
```

If an operation is hung rather than failed, `az aks operation-abort` (or `az aks nodepool operation-abort`) cancels it; note that already-upgraded nodes stay upgraded, so you'll have a mixed pool until you retry.

## Auto-upgrade-specific checks

- Verify the channel and window: `az aks show ... --query "{ch:autoUpgradeProfile.upgradeChannel, img:autoUpgradeProfile.nodeOSUpgradeChannel}"` and `az aks maintenanceconfiguration list`. A window that's too short for the pool to finish causes the operation to be cancelled and retried repeatedly, which looks like flapping failures.
- Auto-upgrade will not touch a cluster in `Failed` state until you reconcile it manually, so one failure silently stops all future upgrades.
- Set `--max-surge`, `--drain-timeout`, `--node-soak-duration`, and `--undrainable-node-behavior` on every pool; the auto-upgrader honors them and they turn most "failures" into a cordoned node you can fix at leisure.