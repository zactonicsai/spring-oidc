# Architecture

## Goal

Give an operator one simple web page for common Kubernetes questions and actions across local and hosted clusters.

## Design

```text
Browser
  |
  | same-origin HTTP
  v
Local Node API proxy
  |
  | fixed kubectl/helm argument lists
  v
kubectl + kubeconfig + cloud authentication
  |
  | HTTPS to Kubernetes API server
  v
Kubernetes / managed provider control plane
```

The browser never receives kubeconfig credentials. The Node server invokes `kubectl` using argument arrays (`shell: false`) instead of concatenating a raw shell command. That blocks a large class of command-injection mistakes.

## Why kubeconfig is the portability layer

All supported platforms eventually give `kubectl` a cluster endpoint plus credentials/context. This keeps provider-specific authentication outside the dashboard:

- Docker Desktop: local `docker-desktop` context.
- kind/minikube: local contexts.
- Amazon EKS: `aws eks update-kubeconfig`.
- Google GKE: `gcloud container clusters get-credentials`.
- Azure AKS: `az aks get-credentials`.
- Red Hat OpenShift: `oc login` creates/updates usable context information.
- IBM Cloud Kubernetes Service: `ibmcloud ks cluster config`.
- VMware/Rancher/generic: use the kubeconfig supplied by the platform.

## Security boundaries

1. Server binds to `127.0.0.1` by default.
2. Write operations are disabled by default.
3. The browser stores only UI preferences in `localStorage`; no Kubernetes tokens are stored there.
4. Backend routes only expose specific operations; there is no arbitrary shell endpoint.
5. Kubernetes RBAC remains the final authorization layer.
6. For shared/team deployment, add real SSO, TLS, CSRF protection, audit logging, authorization mapping, and per-user Kubernetes impersonation before exposing this beyond localhost.

## Production extensions

- OIDC/SSO using Keycloak, Entra ID, or another enterprise IdP.
- Kubernetes impersonation headers and per-user RBAC.
- Audit table for every mutating action.
- WebSockets or Server-Sent Events for live watches/log streaming.
- Prometheus/OpenTelemetry metrics and alerts.
- Helm release details and chart upgrade planner.
- CRD discovery and dynamic resource browsing.
- Policy integrations (Kyverno/OPA Gatekeeper).
- GitOps mode where changes create commits/PRs instead of direct API writes.
