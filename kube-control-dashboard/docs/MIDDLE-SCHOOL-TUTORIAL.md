# Kube Control Dashboard — Step-by-Step Beginner Tutorial

## Big idea

Think about a school cafeteria.

- **Kubernetes cluster** = the whole cafeteria system.
- **Control plane** = the manager’s office. It decides what should be running.
- **Node** = a kitchen station with a computer and worker capacity.
- **Pod** = one lunch tray holding one or more containers.
- **Deployment** = a rule such as “always keep 3 pizza stations working.”
- **Service** = the counter number students use to reach the right stations.
- **Namespace** = a labeled area that keeps groups organized.
- **kubectl** = the manager’s remote control.
- **Helm** = a recipe book that can install many related Kubernetes objects together.

The dashboard is a friendly screen over the same Kubernetes API that `kubectl` uses.

## Step 1 — Make sure kubectl exists

```bash
kubectl version --client
```

If this fails, install `kubectl` first.

## Step 2 — See your cluster choices

```bash
kubectl config get-contexts
```

A **context** is like an address-book entry. It tells kubectl which cluster, user, and default namespace to use.

## Step 3 — Log in to your provider

Use the provider’s normal command first.

### Docker Desktop

```bash
kubectl config use-context docker-desktop
```

### AWS EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name MY_CLUSTER
```

### Google GKE

```bash
gcloud container clusters get-credentials MY_CLUSTER --region MY_REGION --project MY_PROJECT
```

### Azure AKS

```bash
az aks get-credentials --resource-group MY_GROUP --name MY_CLUSTER
```

### Red Hat OpenShift

```bash
oc login https://api.example.com:6443 --token='REDACTED'
```

### IBM Cloud Kubernetes Service

```bash
ibmcloud ks cluster config --cluster MY_CLUSTER
```

## Step 4 — Prove the cluster works before the dashboard

```bash
kubectl get nodes
kubectl get pods -A
```

If these fail, the dashboard will also fail. Fix login, VPN, DNS, firewall, kubeconfig, or RBAC first.

## Step 5 — Start the dashboard

```bash
cd kube-control-dashboard
npm start
```

Open:

```text
http://127.0.0.1:8787
```

No npm download is required because the server uses only Node built-in modules.

## Step 6 — Read the Overview page

The summary cards answer these basic questions:

1. Are deployments available?
2. Are pods running and ready?
3. How many Services exist?
4. Are nodes Ready?
5. Are there Warning events?
6. Does the API server answer its health checks?

The dashboard asks the API server for `/livez` and `/readyz`. Some managed platforms may limit what you can see; that does not automatically mean the control plane is broken.

## Step 7 — Understand Deployments and Pods

A Deployment says what you **want**.

Example:

```yaml
spec:
  replicas: 3
```

That means “I want three copies.” Kubernetes tries to make reality match that number.

A Pod is one of the actual running copies. If a Pod dies and the Deployment still wants three copies, Kubernetes normally creates another Pod.

## Step 8 — Look at logs

Open **Logs**, select a pod, and click **Load logs**.

This is similar to:

```bash
kubectl logs -n default my-pod --tail=200
```

Logs help answer “What did the application say before it failed?”

## Step 9 — Keep write mode off while learning

By default, the dashboard is read-only.

That means you can inspect things without using the dashboard to change the cluster.

When you really want change controls:

```bash
DASHBOARD_WRITE_ENABLED=true npm start
```

Then Kubernetes RBAC still decides what your identity is allowed to do.

## Step 10 — Try a safe status command

The Command Center can check rollout status without changing anything.

Equivalent command:

```bash
kubectl rollout status deployment/MY_APP -n default
```

## Step 11 — Scale a Deployment

With write mode enabled, choose **Scale deployment** and set the replica count.

Equivalent command:

```bash
kubectl scale deployment MY_APP -n default --replicas=3
```

Kubernetes changes the desired number of Pods.

## Step 12 — Restart a Deployment

A rollout restart tells Kubernetes to recreate the Deployment’s Pods in a controlled rollout.

```bash
kubectl rollout restart deployment/MY_APP -n default
```

This can help when an application needs fresh Pods, but it does not fix a bad image, bad configuration, broken database, or missing secret.

## Step 13 — Delete a Pod carefully

If a Deployment owns the Pod, Kubernetes normally creates a replacement.

```bash
kubectl delete pod MY_POD -n default
```

A standalone Pod may **not** come back, so know who owns it before deleting it.

## Step 14 — Use YAML Diff before Apply

The dashboard includes **Diff** and **Apply**.

Think of Diff as comparing homework before turning it in.

```bash
kubectl diff -n default -f my-file.yaml
```

Then apply:

```bash
kubectl apply -n default -f my-file.yaml
```

For production systems, GitOps is often safer because every change is reviewed and recorded in Git first.

## Step 15 — Check versions before upgrading

Kubernetes components are allowed to differ only by certain amounts.

Important rules in the dashboard:

- `kubectl` should be within **one minor version** of the API server.
- `kubelet` cannot be newer than the API server and can be at most **three minor versions older**.
- Kubernetes control-plane upgrades should move **one minor version at a time**.
- Helm has its own Kubernetes compatibility table.

A minor version is the middle number:

```text
1.36.4
   ^
 minor = 36
```

## Step 16 — Upgrade like crossing stepping stones

Do not jump across the river.

Use this order:

1. Inventory what you have.
2. Read your provider’s release notes.
3. Update to the newest patch of your current minor release.
4. Find removed/deprecated APIs.
5. Back up data and configuration.
6. Test in development/staging.
7. Upgrade the control plane one minor.
8. Upgrade nodes and add-ons in the provider-supported order.
9. Run smoke tests.
10. Watch logs, events, metrics, restarts, and application errors.

## Step 17 — Common troubleshooting

### Dashboard says kubectl is unavailable

```bash
which kubectl
kubectl version --client
```

Make sure `kubectl` is on the `PATH` used by the Node process.

### Dashboard says it cannot connect

```bash
kubectl config current-context
kubectl cluster-info
kubectl get nodes
```

### Access is forbidden

That is usually RBAC.

```bash
kubectl auth can-i get pods -A
kubectl auth can-i get nodes
kubectl auth can-i patch deployments -n default
```

### Pods are Pending

```bash
kubectl describe pod MY_POD -n default
kubectl get events -n default --sort-by=.lastTimestamp
```

Look for not enough CPU/memory, missing storage, taints, node selectors, or scheduling rules.

### Pods are CrashLoopBackOff

```bash
kubectl logs MY_POD -n default --previous
kubectl describe pod MY_POD -n default
```

The previous-container log often shows the error that caused the restart.

### Service is not reachable

```bash
kubectl get service MY_SERVICE -n default -o wide
kubectl get endpointslices -n default -l kubernetes.io/service-name=MY_SERVICE
kubectl get pods -n default --show-labels
```

Check that the Service selector actually matches the Pods.

## Final rule

The dashboard is a helper. Kubernetes and your managed provider are the final authority. Before a production upgrade or major change, verify the current official provider documentation.
