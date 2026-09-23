"""Load a PodConfig, validate it against the schema and turn it into a render context.

The render context is a plain dict consumed by the Terraform/script templates
(`render.py`) and by the Kubernetes manifest builder (`k8s.py`).
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schema" / "pod-config.schema.json"

PROVIDERS = ("aws", "azure", "gcp")

PROVIDER_TITLE = {"aws": "AWS (EKS)", "azure": "Azure (AKS)", "gcp": "GCP (GKE)"}
CLOUD_CLI = {"aws": "aws", "azure": "az", "gcp": "gcloud"}
SECRET_STORE = {"aws": "AWS Secrets Manager", "azure": "Azure Key Vault", "gcp": "Google Secret Manager"}

# ServiceAccount annotation that binds the pod to a cloud identity.
IDENTITY_ANNOTATION = {
    "aws": "eks.amazonaws.com/role-arn",
    "azure": "azure.workload.identity/client-id",
    "gcp": "iam.gke.io/gcp-service-account",
}
IDENTITY_POD_LABELS = {"azure": {"azure.workload.identity/use": "true"}}

# Node selector / toleration that lands the pod on spot capacity.
# EKS: managed node groups label spot nodes; with Karpenter use karpenter.sh/capacity-type=spot instead.
SPOT = {
    "aws": {"nodeSelector": {"eks.amazonaws.com/capacityType": "SPOT"}, "tolerations": []},
    "azure": {
        "nodeSelector": {"kubernetes.azure.com/scalesetpriority": "spot"},
        "tolerations": [{"key": "kubernetes.azure.com/scalesetpriority", "operator": "Equal", "value": "spot", "effect": "NoSchedule"}],
    },
    "gcp": {
        "nodeSelector": {"cloud.google.com/gke-spot": "true"},
        "tolerations": [{"key": "cloud.google.com/gke-spot", "operator": "Equal", "value": "true", "effect": "NoSchedule"}],
    },
}

# (playbook, shell script, default phase) for the built-in configuration flows.
CONFIGURE_FLOWS = {
    "tls": ("playbooks/java-keystore.yml", "configure/java-keystore.sh", "pre"),
    "postgres": ("playbooks/postgres-client.yml", "configure/postgres-client.sh", "post"),
}


class ConfigError(Exception):
    """Raised for invalid or incomplete PodConfig documents."""


# --------------------------------------------------------------------------- loading


def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text())


def load(path: str | Path, provider: str | None = None) -> dict:
    """Read a YAML/JSON PodConfig, optionally override the provider, validate and fill defaults."""
    path = Path(path)
    try:
        raw = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        raise ConfigError(f"{path}: not valid YAML: {exc}") from exc
    if not isinstance(raw, dict):
        raise ConfigError(f"{path}: expected a mapping at the top level")
    if provider:
        raw.setdefault("spec", {})["provider"] = provider
    validate(raw, source=str(path))
    schema = load_schema()
    _apply_defaults(raw, schema, schema)
    raw["_source"] = str(path)
    return raw


def validate(raw: dict, source: str = "<config>") -> None:
    validator = Draft202012Validator(load_schema())
    errors = sorted(validator.iter_errors(raw), key=lambda e: list(e.absolute_path))
    if errors:
        lines = [f"{source}: invalid PodConfig"]
        for err in errors:
            where = "/".join(str(p) for p in err.absolute_path) or "<root>"
            lines.append(f"  {where}: {err.message}")
        raise ConfigError("\n".join(lines))
    spec = raw.get("spec", {})
    if not spec.get("provider"):
        raise ConfigError(f"{source}: spec.provider is not set (or pass --provider)")


def providers_in(raw: dict) -> list[str]:
    """Providers this config can be generated for (those with a `spec.cloud.<provider>` block)."""
    cloud = raw.get("spec", {}).get("cloud", {}) or {}
    return [p for p in PROVIDERS if p in cloud]


def _resolve(schema: dict, root: dict) -> dict:
    ref = schema.get("$ref")
    if not ref:
        return schema
    node = root
    for part in ref.lstrip("#/").split("/"):
        node = node[part]
    return node


def _apply_defaults(instance, schema: dict, root: dict) -> None:
    """Fill schema defaults in place (jsonschema validates but does not apply defaults)."""
    schema = _resolve(schema, root)
    if isinstance(instance, dict) and "properties" in schema:
        for key, sub in schema["properties"].items():
            resolved = _resolve(sub, root)  # a `default` may sit next to the $ref
            if key not in instance:
                if "default" in sub:
                    instance[key] = copy.deepcopy(sub["default"])
                elif "default" in resolved:
                    instance[key] = copy.deepcopy(resolved["default"])
                elif resolved.get("type") == "object" and "properties" in resolved and not resolved.get("required"):
                    instance[key] = {}
            if key in instance:
                _apply_defaults(instance[key], resolved, root)
    elif isinstance(instance, list) and "items" in schema:
        for item in instance:
            _apply_defaults(item, schema["items"], root)


# --------------------------------------------------------------------------- context


def _snake(key: str) -> str:
    out = []
    for ch in key:
        out.append("_" + ch.lower() if ch.isupper() else ch)
    return "".join(out)


def build_context(raw: dict, *, out_dir: Path, modules_source: str | None = None) -> dict:
    """Derive everything the templates need from a validated, defaulted PodConfig."""
    meta = raw["metadata"]
    spec = raw["spec"]
    name = meta["name"]
    namespace = meta["namespace"]
    provider = spec["provider"]
    cloud = spec["cloud"][provider]
    source = raw.get("_source", "pod.yaml")

    labels = {
        "app.kubernetes.io/name": name,
        "app.kubernetes.io/managed-by": "podkit",
        **meta.get("labels", {}),
    }
    env = dict(spec.get("env", {}))
    cloud_secrets: dict[str, str] = {}
    k8s_secret_env: dict[str, dict] = {}
    for item in spec.get("secrets", []):
        if "ref" in item:
            cloud_secrets[item["env"]] = item["ref"]
        else:
            k8s_secret_env[item["env"]] = {"secret": item["secret"], "key": item["key"]}

    files = {f["path"]: f["content"] for f in spec.get("files", [])}
    mounts = []
    for i, m in enumerate(spec.get("mounts", [])):
        mounts.append({
            "name": m.get("name") or f"mount-{i}",
            "path": m["path"],
            "secret": m.get("secret"),
            "config_map": m.get("configMap"),
            "read_only": m.get("readOnly", True),
        })

    network = copy.deepcopy(spec["networkPolicy"])
    identity = spec["identity"]
    if network.get("allowHttpsEgress") is None:
        network["allowHttpsEgress"] = bool(identity["enabled"])

    configure = copy.deepcopy(spec.get("configure") or {})
    configure_vars: dict = {}
    flow = None
    extra_files: dict[str, Path] = {}  # files copied next to the generated output

    # ---- external PostgreSQL -------------------------------------------------
    postgres = spec.get("externalServices", {}).get("postgres")
    if postgres:
        flow = "postgres"
        env.setdefault("PGHOST", postgres["host"])
        env.setdefault("PGPORT", str(postgres["port"]))
        env.setdefault("PGDATABASE", postgres["database"])
        env.setdefault("PGUSER", postgres["user"])
        env.setdefault("PGSSLMODE", postgres["sslMode"])
        if postgres.get("passwordSecretRef"):
            cloud_secrets.setdefault("PGPASSWORD", postgres["passwordSecretRef"])
            password_secret, password_key = f"{name}-env", "PGPASSWORD"
        elif postgres.get("passwordSecret"):
            ps = postgres["passwordSecret"]
            k8s_secret_env.setdefault("PGPASSWORD", {"secret": ps["name"], "key": ps["key"]})
            password_secret, password_key = ps["name"], ps["key"]
        else:
            raise ConfigError(f"{source}: externalServices.postgres needs passwordSecretRef or passwordSecret")
        if postgres.get("networkCidr"):
            network["egress"].append({"cidr": postgres["networkCidr"], "port": postgres["port"], "protocol": "TCP"})
        bootstrap = ""
        if postgres.get("bootstrapSql"):
            src = (Path(source).parent / postgres["bootstrapSql"]).resolve()
            if not src.is_file():
                raise ConfigError(f"{source}: bootstrapSql file not found: {src}")
            extra_files["bootstrap.sql"] = src
            bootstrap = "{{ build_dir }}/bootstrap.sql"
        configure_vars.update({
            "namespace": namespace,
            "app_name": name,
            "target_selector": f"app.kubernetes.io/name={name}",
            "container": name,
            "pg_host": postgres["host"],
            "pg_port": postgres["port"],
            "pg_database": postgres["database"],
            "pg_user": postgres["user"],
            "pg_sslmode": postgres["sslMode"],
            "password_secret": password_secret,
            "password_secret_key": password_key,
            "check_connectivity": True,
            "bootstrap_sql": bootstrap,
            "runtime_config_path": "/tmp/database.conf",
        })

    # ---- pod-to-pod mTLS with Java keystores ------------------------------------
    tls = spec.get("tls")
    tls_ctx = None
    if tls:
        flow = "tls"  # takes precedence: it is a pre-deploy step and creates the secrets first
        keystore_secret = tls.get("keystoreSecret") or f"{name}-keystore"
        truststore_secret = tls["truststoreSecret"]
        mount = tls["mountPath"].rstrip("/")
        mounts.append({"name": "keystore", "path": f"{mount}/keystore", "secret": keystore_secret, "config_map": None, "read_only": True})
        mounts.append({"name": "truststore", "path": f"{mount}/truststore", "secret": truststore_secret, "config_map": None, "read_only": True})
        env.setdefault("KEYSTORE_PATH", f"{mount}/keystore/keystore.jks")
        env.setdefault("TRUSTSTORE_PATH", f"{mount}/truststore/truststore.jks")
        k8s_secret_env.setdefault("KEYSTORE_PASSWORD", {"secret": keystore_secret, "key": "keystore.password"})
        k8s_secret_env.setdefault("TRUSTSTORE_PASSWORD", {"secret": truststore_secret, "key": "truststore.password"})
        dns_names = []
        if tls["role"] == "server":
            dns_names = [name, f"{name}.{namespace}", f"{name}.{namespace}.svc", f"{name}.{namespace}.svc.cluster.local"]
        dns_names += [d for d in tls["dnsNames"] if d not in dns_names]
        tls_ctx = {
            "role": tls["role"],
            "ca_secret": tls["caSecret"],
            "keystore_secret": keystore_secret,
            "truststore_secret": truststore_secret,
            "mount_path": mount,
            "dns_names": dns_names,
        }
        configure_vars.update({
            "namespace": namespace,
            "subject_name": name,
            "dns_names": dns_names,
            "is_server": tls["role"] == "server",
            "ca_secret": tls["caSecret"],
            "keystore_secret": keystore_secret,
            "truststore_secret": truststore_secret,
            "validity_days": tls["validityDays"],
            "rotate": False,
            "restart_deployments": [name],
        })

    # ---- configuration step ------------------------------------------------------
    method = configure.get("method", "ansible" if flow else "none")
    target = None
    if method != "none":
        if method == "ansible":
            target = configure.get("playbook") or (CONFIGURE_FLOWS[flow][0] if flow else None)
        else:
            target = configure.get("script") or (CONFIGURE_FLOWS[flow][1] if flow else None)
        if not target:
            raise ConfigError(f"{source}: configure.method={method} needs configure.playbook or configure.script")
    phase = configure.get("phase") or (CONFIGURE_FLOWS[flow][2] if flow else "post")
    configure_vars.update(configure.get("vars", {}))
    configure_ctx = {"method": method, "phase": phase, "target": target, "vars": configure_vars}

    # ---- scheduling ----------------------------------------------------------------
    sched = spec["scheduling"]
    spot = bool(sched.get("spot"))
    node_selector_user = dict(sched.get("nodeSelector", {}))
    tolerations_user = [dict(t) for t in sched.get("tolerations", [])]
    node_selector = {**(SPOT[provider]["nodeSelector"] if spot else {}), **node_selector_user}
    tolerations = ([*SPOT[provider]["tolerations"]] if spot else []) + tolerations_user

    # ---- ports / service / probe -----------------------------------------------------
    ports = spec.get("ports", [])
    service = spec["service"]
    service_enabled = bool(service.get("enabled", True) and ports)
    service_port = service.get("port") or (ports[0]["containerPort"] if ports else None)
    service_dns = f"{name}.{namespace}.svc.cluster.local" if service_enabled else None
    probe = dict(spec["probe"])
    if probe["type"] != "none" and probe.get("port") is None:
        probe["port"] = ports[0]["name"] if ports else 80
    security = spec["securityContext"]
    identity_ctx = {
        "enabled": bool(identity["enabled"]),
        "mode": cloud.get("identityMode", "irsa") if provider == "aws" else None,
        "annotation_key": IDENTITY_ANNOTATION[provider],
        "pod_labels": IDENTITY_POD_LABELS.get(provider, {}) if identity["enabled"] else {},
        "aws": identity.get("aws", {"policyArns": []}),
        "azure": identity.get("azure", {"roleAssignments": []}),
        "gcp": identity.get("gcp", {"roles": []}),
    }
    pod_labels = {**labels, **identity_ctx["pod_labels"]}
    files_checksum = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()[:16]

    out_dir = Path(out_dir)
    if modules_source is None:
        rel = Path(_relpath(ROOT / "terraform" / "modules", out_dir / "terraform"))
        modules_source = rel.as_posix()

    return {
        "source_file": source,
        "generated_dir": str(out_dir),
        "root_rel": _relpath(ROOT, out_dir),
        "modules_source": modules_source,
        "name": name,
        "namespace": namespace,
        "provider": provider,
        "provider_title": PROVIDER_TITLE[provider],
        "cli": CLOUD_CLI[provider],
        "secret_store": SECRET_STORE[provider],
        "cloud": cloud,
        "labels": labels,
        "pod_labels": pod_labels,
        "annotations": meta.get("annotations", {}),
        "image_repository": spec["image"]["repository"],
        "image_tag": spec["image"]["tag"],
        "image": f'{spec["image"]["repository"]}:{spec["image"]["tag"]}',
        "image_pull_policy": spec["image"]["pullPolicy"],
        "command": spec.get("command"),
        "args": spec.get("args"),
        "replicas": spec["replicas"],
        "resources": {"requests": spec["resources"]["requests"], "limits": spec["resources"]["limits"]},
        "spot": spot,
        "node_selector": node_selector,
        "tolerations": tolerations,
        "node_selector_user": node_selector_user,
        "tolerations_user": tolerations_user,
        "ports": ports,
        "ports_tf": [{"name": p["name"], "container_port": p["containerPort"], "protocol": p["protocol"]} for p in ports],
        "service": {"enabled": service_enabled, "type": service["type"], "port": service_port},
        "service_dns": service_dns,
        "probe": probe,
        "probe_tf": {
            "type": probe["type"],
            "path": probe["path"],
            "port": str(probe["port"]) if probe.get("port") is not None else None,
            "initial_delay": probe["initialDelaySeconds"],
            "period": probe["periodSeconds"],
        },
        "env": dict(sorted(env.items())),
        "cloud_secrets": cloud_secrets,
        "cloud_secrets_csv": ",".join(f"{k}={v}" for k, v in sorted(cloud_secrets.items())),
        "k8s_secret_env": k8s_secret_env,
        "files": files,
        "files_checksum": files_checksum,
        "mounts": mounts,
        "mounts_tf": [{k: v for k, v in m.items() if v is not None} for m in mounts],
        "identity": identity_ctx,
        "security": {_snake(k): v for k, v in security.items()},
        "network_policy": {
            "enabled": bool(network["enabled"]),
            "allow_dns": bool(network["allowDns"]),
            "egress_https_any": bool(network["allowHttpsEgress"]),
            "ingress_from": [r["podLabels"] for r in network["ingressFrom"]],
            "egress_to": [r["podLabels"] for r in network["egressTo"]],
            "egress": network["egress"],
        },
        "autoscaling": {
            "enabled": bool(spec["autoscaling"]["enabled"]),
            "min_replicas": spec["autoscaling"]["minReplicas"],
            "max_replicas": spec["autoscaling"]["maxReplicas"],
            "target_cpu": spec["autoscaling"]["targetCPUUtilizationPercentage"],
        },
        "tls": tls_ctx,
        "postgres": postgres,
        "configure": configure_ctx,
        "extra_files": extra_files,
        "command_pod_namespace": "ops",
    }


def _relpath(target: Path, start: Path) -> str:
    import os

    return os.path.relpath(Path(target).resolve(), Path(start).resolve())
