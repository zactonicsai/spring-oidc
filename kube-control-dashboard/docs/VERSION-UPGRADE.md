# Kubernetes Version and Upgrade Guide

Reference snapshot: **2026-09-24**. Always verify current provider documentation before changing a cluster.

## Upstream version-skew rules used by the dashboard

- Kubernetes currently maintains the most recent three minor release branches: 1.37, 1.36, and 1.35.
- `kubectl` is supported within one minor version older or newer than the API server.
- `kubelet` must not be newer than the API server and may be up to three minor versions older.
- Control-plane manager/scheduler components are expected to match the API server and may be one minor older during upgrade.
- Do not skip Kubernetes minor versions during control-plane upgrades.

Official: https://kubernetes.io/releases/version-skew-policy/

## Helm ranges included in the UI

The UI includes current Helm support-table entries for Helm 4.0-4.3 and Helm 3.12-3.22. Helm 4 and Helm 3 use an `n-3` Kubernetes compatibility policy based on the Kubernetes client version Helm was compiled against.

Official: https://helm.sh/docs/topics/version_skew/

## Managed-provider notes

### Amazon EKS

Current AWS documentation lists standard support for Kubernetes 1.36, 1.35, and 1.34, with 1.33, 1.32, and 1.31 in extended support.

Official: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

### Azure AKS

Current Microsoft documentation lists 1.36 GA and 1.37 preview in September 2026, with 1.37 GA scheduled for October 2026. Availability can vary by region.

Official: https://learn.microsoft.com/azure/aks/supported-kubernetes-versions

### Google GKE

GKE maintains its own release channels and regional rollout dates. Kubernetes 1.36 is in the current schedule, but exact versions differ by channel/location.

Official: https://cloud.google.com/kubernetes-engine/docs/release-schedule

### IBM Cloud Kubernetes Service

Current IBM documentation lists 1.36 as default, 1.35 supported, and 1.34/1.33 as deprecated.

Official: https://cloud.ibm.com/docs/containers?topic=containers-cs_versions

### Red Hat OpenShift

OpenShift maps platform releases to Kubernetes versions. OpenShift Container Platform 4.21 uses Kubernetes 1.34; 4.20 uses Kubernetes 1.33. Follow OpenShift-specific lifecycle and upgrade rules instead of treating it as a generic upstream cluster.

Official: https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/release_notes/ocp-4-21-release-notes

## Safe upgrade sequence

1. Inventory versions and add-ons.
2. Read provider release notes and supported paths.
3. Patch the current minor version.
4. Scan manifests, Helm charts, CRDs, and webhooks for removed APIs.
5. Back up application data/configuration; self-managed clusters also need an etcd backup plan.
6. Rehearse in development/staging.
7. Upgrade the control plane one minor version.
8. Upgrade nodes and provider add-ons in the supported order.
9. Validate workloads, networking, DNS, storage, autoscaling, ingress, jobs, logs, and monitoring.
10. Continue monitoring Warning events and application health after the change.
