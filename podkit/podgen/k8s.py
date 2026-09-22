"""Build the Kubernetes manifests used by the kubectl deploy path.

Mirrors terraform/modules/pod so both paths produce the same workload.
"""

from __future__ import annotations


def _meta(ctx: dict, name: str, extra_labels: dict | None = None) -> dict:
    meta = {"name": name, "namespace": ctx["namespace"], "labels": {**ctx["labels"], **(extra_labels or {})}}
    if ctx["annotations"]:
        meta["annotations"] = dict(ctx["annotations"])
    return meta


def file_key(path: str) -> str:
    """ConfigMap keys cannot contain '/', so /app/config/x.properties -> app__config__x.properties."""
    return path.lstrip("/").replace("/", "__")


def service_account(ctx: dict) -> dict:
    # The cloud identity annotation is added by deploy.sh (IDENTITY_ID) because the
    # role/identity is created by Terraform and unknown at generation time.
    return {
        "apiVersion": "v1",
        "kind": "ServiceAccount",
        "metadata": _meta(ctx, ctx["name"]),
        "automountServiceAccountToken": False,
    }


def config_map(ctx: dict) -> dict:
    return {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": _meta(ctx, f'{ctx["name"]}-files'),
        "data": {file_key(p): c for p, c in ctx["files"].items()},
    }


def _env(ctx: dict) -> list[dict]:
    env = [{"name": k, "value": v} for k, v in ctx["env"].items()]
    for k, ref in sorted(ctx["k8s_secret_env"].items()):
        env.append({"name": k, "valueFrom": {"secretKeyRef": {"name": ref["secret"], "key": ref["key"]}}})
    return env


def _probe(ctx: dict) -> dict | None:
    p = ctx["probe"]
    if p["type"] == "none":
        return None
    port = p["port"]
    port = int(port) if isinstance(port, str) and port.isdigit() else port
    handler = {"httpGet": {"path": p["path"], "port": port}} if p["type"] == "http" else {"tcpSocket": {"port": port}}
    return {**handler, "initialDelaySeconds": p["initialDelaySeconds"], "periodSeconds": p["periodSeconds"]}


def deployment(ctx: dict) -> dict:
    sec = ctx["security"]
    container = {
        "name": ctx["name"],
        "image": ctx["image"],
        "imagePullPolicy": ctx["image_pull_policy"],
    }
    if ctx["command"]:
        container["command"] = list(ctx["command"])
    if ctx["args"]:
        container["args"] = list(ctx["args"])
    if ctx["ports"]:
        container["ports"] = [{"name": p["name"], "containerPort": p["containerPort"], "protocol": p["protocol"]} for p in ctx["ports"]]
    env = _env(ctx)
    if env:
        container["env"] = env
    if ctx["cloud_secrets"]:
        container["envFrom"] = [{"secretRef": {"name": f'{ctx["name"]}-env'}}]
    container["resources"] = ctx["resources"]
    probe = _probe(ctx)
    if probe:
        container["livenessProbe"] = probe
        container["readinessProbe"] = probe
    mounts, volumes = [], []
    if ctx["files"]:
        for path in ctx["files"]:
            mounts.append({"name": "files", "mountPath": path, "subPath": file_key(path), "readOnly": True})
        volumes.append({"name": "files", "configMap": {"name": f'{ctx["name"]}-files', "defaultMode": 0o444}})
    for m in ctx["mounts"]:
        mounts.append({"name": m["name"], "mountPath": m["path"], "readOnly": m["read_only"]})
        source = {"secret": {"secretName": m["secret"], "defaultMode": 0o400}} if m.get("secret") else {"configMap": {"name": m["config_map"]}}
        volumes.append({"name": m["name"], **source})
    if mounts:
        container["volumeMounts"] = mounts
    container["securityContext"] = {
        "allowPrivilegeEscalation": False,
        "readOnlyRootFilesystem": sec["read_only_root_filesystem"],
        "capabilities": {"drop": ["ALL"]},
    }

    pod_security = {"runAsNonRoot": sec["run_as_non_root"], "seccompProfile": {"type": "RuntimeDefault"}}
    for key in ("run_as_user", "run_as_group", "fs_group"):
        if sec.get(key) is not None:
            camel = {"run_as_user": "runAsUser", "run_as_group": "runAsGroup", "fs_group": "fsGroup"}[key]
            pod_security[camel] = sec[key]

    pod_spec = {
        "serviceAccountName": ctx["name"],
        "automountServiceAccountToken": False,
        "securityContext": pod_security,
        "containers": [container],
    }
    if ctx["node_selector"]:
        pod_spec["nodeSelector"] = ctx["node_selector"]
    if ctx["tolerations"]:
        pod_spec["tolerations"] = [{k: v for k, v in t.items() if v is not None} for t in ctx["tolerations"]]
    if volumes:
        pod_spec["volumes"] = volumes

    annotations = {"podkit.dev/files-checksum": ctx["files_checksum"]}
    if ctx["cloud_secrets"]:
        # Substituted by deploy.sh with a hash of the synced Secret so rotated secrets roll the pods.
        annotations["podkit.dev/secret-checksum"] = "${SECRET_CHECKSUM}"

    spec = {}
    if not ctx["autoscaling"]["enabled"]:
        spec["replicas"] = ctx["replicas"]  # omitted when the HPA owns the replica count
    spec.update({
        "revisionHistoryLimit": 2,
        "selector": {"matchLabels": {"app.kubernetes.io/name": ctx["name"]}},
        "strategy": {"type": "RollingUpdate", "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0}},
        "template": {"metadata": {"labels": ctx["pod_labels"], "annotations": annotations}, "spec": pod_spec},
    })
    return {"apiVersion": "apps/v1", "kind": "Deployment", "metadata": _meta(ctx, ctx["name"]), "spec": spec}


def service(ctx: dict) -> dict:
    ports = []
    for i, p in enumerate(ctx["ports"]):
        port = ctx["service"]["port"] if i == 0 and ctx["service"]["port"] else p["containerPort"]
        ports.append({"name": p["name"], "port": port, "targetPort": p["name"], "protocol": p["protocol"]})
    return {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": _meta(ctx, ctx["name"]),
        "spec": {"type": ctx["service"]["type"], "selector": {"app.kubernetes.io/name": ctx["name"]}, "ports": ports},
    }


def network_policy(ctx: dict) -> dict:
    np = ctx["network_policy"]
    ingress, egress = [], []
    port_list = [{"port": p["containerPort"], "protocol": p["protocol"]} for p in ctx["ports"]]
    for labels in np["ingress_from"]:
        rule = {"from": [{"podSelector": {"matchLabels": labels}}]}
        if port_list:
            rule["ports"] = port_list
        ingress.append(rule)
    if np["allow_dns"]:
        egress.append({
            "to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "kube-system"}}}],
            "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}],
        })
    if np["egress_https_any"]:
        egress.append({"to": [{"ipBlock": {"cidr": "0.0.0.0/0"}}], "ports": [{"port": 443, "protocol": "TCP"}]})
    for rule in np["egress"]:
        egress.append({"to": [{"ipBlock": {"cidr": rule["cidr"]}}], "ports": [{"port": rule["port"], "protocol": rule["protocol"]}]})
    for labels in np["egress_to"]:
        egress.append({"to": [{"podSelector": {"matchLabels": labels}}]})
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "NetworkPolicy",
        "metadata": _meta(ctx, ctx["name"]),
        "spec": {
            "podSelector": {"matchLabels": {"app.kubernetes.io/name": ctx["name"]}},
            "policyTypes": ["Ingress", "Egress"],
            "ingress": ingress,
            "egress": egress,
        },
    }


def hpa(ctx: dict) -> dict:
    a = ctx["autoscaling"]
    return {
        "apiVersion": "autoscaling/v2",
        "kind": "HorizontalPodAutoscaler",
        "metadata": _meta(ctx, ctx["name"]),
        "spec": {
            "scaleTargetRef": {"apiVersion": "apps/v1", "kind": "Deployment", "name": ctx["name"]},
            "minReplicas": a["min_replicas"],
            "maxReplicas": a["max_replicas"],
            "metrics": [{"type": "Resource", "resource": {"name": "cpu", "target": {"type": "Utilization", "averageUtilization": a["target_cpu"]}}}],
        },
    }


def workload_manifests(ctx: dict) -> list[dict]:
    objs = []
    if ctx["files"]:
        objs.append(config_map(ctx))
    objs.append(deployment(ctx))
    if ctx["service"]["enabled"]:
        objs.append(service(ctx))
    if ctx["network_policy"]["enabled"]:
        objs.append(network_policy(ctx))
    if ctx["autoscaling"]["enabled"]:
        objs.append(hpa(ctx))
    return objs
