# Kube Control Dashboard

A simple IBM-inspired Kubernetes operations dashboard built with HTML, Tailwind CSS, JavaScript, and a small Node.js API proxy. It works with any cluster that your local `kubectl` can reach.

## What it does

- Shows deployments, pods, services, nodes, Kubernetes versions, and Warning events.
- Pulls pod logs.
- Switches kubeconfig contexts.
- Supports namespace filtering.
- Provides safe operations for rollout status, scaling, rollout restart, pod deletion, image updates, YAML diff, and YAML apply.
- Supports local Docker Desktop/kind plus EKS, GKE, AKS, Red Hat OpenShift, IBM Cloud Kubernetes Service, VMware/Rancher/generic kubeconfig clusters.
- Includes Kubernetes/kubectl/kubelet/Helm version-skew checks.
- Includes a lightweight removed-API manifest checker.
- Includes a provider version reference and upgrade checklist.
- Dark/light mode.
- Adjustable UI font size from 14px through 36px.
- Mobile-friendly layout.
- Built-in beginner explanations and links to official documentation.

## The important safety idea

Do **not** put a Kubernetes bearer token or kubeconfig into browser JavaScript. A browser page is the wrong place for cluster-admin credentials.

This project uses a tiny local API proxy:

```text
Browser -> Node proxy -> kubectl -> Kubernetes API
```

The Node process uses your normal kubeconfig and cloud login. Write actions are disabled by default.

## 1. Requirements

Install:

- Node.js 20 or newer (no npm packages are required).
- `kubectl`.
- `helm` if you want Helm checks/listing.
- The provider CLI you use (AWS CLI, `gcloud`, Azure CLI, `oc`, or IBM Cloud CLI).

Check:

```bash
node --version
kubectl version --client
kubectl config get-contexts
kubectl get nodes
```

If `kubectl get nodes` does not work, fix login/context access before starting the dashboard.

## 2. Provider login examples

### Docker Desktop

```bash
kubectl config use-context docker-desktop
kubectl get nodes
```

### kind

```bash
kind create cluster --name lab
kubectl cluster-info --context kind-lab
```

### AWS EKS

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name MY_CLUSTER

kubectl get nodes
```

### Google GKE

```bash
gcloud container clusters get-credentials MY_CLUSTER \
  --region MY_REGION \
  --project MY_PROJECT

kubectl get nodes
```

### Azure AKS

```bash
az aks get-credentials \
  --resource-group MY_RESOURCE_GROUP \
  --name MY_CLUSTER

kubectl get nodes
```

### Red Hat OpenShift

```bash
oc login https://api.example.com:6443 --token='YOUR_TOKEN'
oc whoami
kubectl get nodes
```

Do not paste the token into this dashboard.

### IBM Cloud Kubernetes Service

```bash
ibmcloud login
ibmcloud ks cluster config --cluster MY_CLUSTER
kubectl get nodes
```

### Generic / VMware / Rancher

```bash
export KUBECONFIG=/path/to/kubeconfig
kubectl config get-contexts
kubectl get nodes
```

## 3. Start in read-only mode

```bash
cd kube-control-dashboard
npm start
```

Open:

```text
http://127.0.0.1:8787
```

Or use:

```bash
./scripts/start.sh
```

## 4. Enable write actions

Read-only mode is the safer default. When you intentionally want to scale/restart/delete/apply:

```bash
DASHBOARD_WRITE_ENABLED=true npm start
```

The Kubernetes identity in your kubeconfig still needs RBAC permission. The dashboard cannot bypass Kubernetes authorization.

## 5. Dashboard pages explained

### Overview

Think of this as the school front office. It answers: “Is the campus open and are the classrooms working?” It summarizes node readiness, deployment availability, pod health, and Warning events.

### Workloads

Deployments are instructions that say how many copies of an application should exist. Pods are the actual running copies.

### Services

A Service is like a stable school phone number. Pods may be replaced, but the Service keeps a stable network identity.

### Nodes

Nodes are the computers that run pods. A node should normally report `Ready`.

### Logs

Logs are the application’s diary. Select a pod and fetch its recent lines. For a multi-container pod, type the container name.

### Command Center

This intentionally does not provide a raw operating-system shell. It exposes a small set of Kubernetes operations with validated arguments so the dashboard is less likely to become a command-injection endpoint.

### Compatibility

Checks common version-skew rules and a small list of removed Kubernetes API versions. It is a helper, not a complete certification tool.

### Upgrades

Walks through inventory, release notes, deprecated APIs, backups, staging tests, control-plane upgrade, node/add-on upgrade, and post-upgrade validation.

## 6. Useful command-line checks

```bash
./scripts/check-cluster.sh
```

Or run the pieces yourself:

```bash
kubectl version -o yaml
kubectl get nodes -o wide
kubectl get deployments -A
kubectl get pods -A -o wide
kubectl get services -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp
helm list -A
```

## 7. RBAC

`manifests/dashboard-reader-rbac.yaml` is a sample read-only ClusterRole and ServiceAccount.

`manifests/dashboard-operator-example-rbac.yaml` is only an example starting point for change permissions. Review it and narrow it for your environment. Avoid giving this dashboard `cluster-admin` just because it is convenient.

## 8. Production gotchas

This project is designed as a local/admin prototype. Before putting it on a shared network, add:

- TLS.
- Real user authentication (OIDC/SSO).
- Per-user authorization and/or Kubernetes impersonation.
- CSRF protection.
- Strong session management.
- Audit logging for mutating operations.
- Network policy/firewall restrictions.
- Secret management.
- Rate limits and request size limits.
- A GitOps workflow for production changes when possible.
- Built/locked Tailwind assets instead of relying on a CDN.

## 9. Version rules included

As of the 2026-09-24 reference snapshot:

- Upstream Kubernetes maintains 1.37, 1.36, and 1.35 release branches.
- `kubectl` should be within ±1 minor version of the API server.
- `kubelet` should not be newer than the API server and may be up to 3 minors older.
- Helm 4.3.x supports Kubernetes 1.37-1.34; Helm 4.2.x supports 1.36-1.33.
- Helm 3.22.x supports Kubernetes 1.37-1.34; Helm 3.21.x supports 1.36-1.33.

Provider support windows differ, so use the links in the dashboard and `docs/VERSION-UPGRADE.md` before upgrading.

## 10. Project structure

```text
kube-control-dashboard/
├── public/
│   ├── index.html
│   └── app.js
├── docs/
│   ├── ARCHITECTURE.md
│   └── VERSION-UPGRADE.md
├── manifests/
│   ├── dashboard-reader-rbac.yaml
│   └── dashboard-operator-example-rbac.yaml
├── scripts/
│   ├── start.sh
│   └── check-cluster.sh
├── .env.example
├── package.json
├── server.js
└── README.md
```

## Official references

- Kubernetes: https://kubernetes.io/docs/
- Kubernetes version skew: https://kubernetes.io/releases/version-skew-policy/
- Helm support: https://helm.sh/docs/topics/version_skew/
- EKS versions: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- AKS versions: https://learn.microsoft.com/azure/aks/supported-kubernetes-versions
- GKE schedule: https://cloud.google.com/kubernetes-engine/docs/release-schedule
- OpenShift: https://docs.redhat.com/en/documentation/openshift_container_platform/
- IBM Cloud Kubernetes: https://cloud.ibm.com/docs/containers

## 9. Helm examples: Keycloak + OIDC web app

Hands-on examples are in [`helm-examples/`](helm-examples/README.md).

They include:

- Bitnami Keycloak Helm installation for a small local lab.
- A production-oriented Keycloak values example using ingress/TLS and an external PostgreSQL database.
- A script that creates a `k8s-demo` realm and public `k8s-webapp` OIDC client.
- A tiny custom Helm chart that deploys an Nginx web app and performs OIDC Authorization Code + PKCE login without putting a client secret in browser code.

Fast path:

```bash
./helm-examples/keycloak/install-local.sh
kubectl -n keycloak port-forward svc/keycloak 8080:80
KEYCLOAK_ADMIN_PASSWORD='change-me-now' ./helm-examples/keycloak/configure-demo-realm.sh
helm upgrade --install oidc-webapp ./helm-examples/oidc-webapp --namespace oidc-demo --create-namespace
kubectl -n oidc-demo port-forward svc/oidc-webapp 8088:80
```

Then open `http://localhost:8088/`.
