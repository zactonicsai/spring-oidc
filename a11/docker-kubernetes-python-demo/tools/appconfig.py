#!/usr/bin/env python3
"""
appconfig.py — validate and render app.config.yaml (apiVersion appconfig.demo/v1).

Usage:
  tools/appconfig.py validate [-c app.config.yaml]
  tools/appconfig.py show     [-c app.config.yaml]
  tools/appconfig.py render   [all|helm|env|host|cloudinit|compose|secrets] [-c app.config.yaml] [-o build]
  tools/appconfig.py get      <dotted.path>          e.g.  get metadata.name

Outputs (default directory: build/ — git-ignored):
  helm-values.yaml     values for helm/<chart>            (helm -f build/helm-values.yaml)
  config.env           bash variables for scripts/        (source build/config.env)
  host-config.env      settings for setup/*.sh + cloud-init
  host-files.tsv       one line per sources.files entry: name url dest mode sha256
  env/<service>.env    docker --env-file per service (config values, may contain spaces)
  cloud-init.yaml      #cloud-config for an Azure VM (embeds setup/*.sh + host config)
  docker-compose.yaml  run the services with plain docker compose
  secrets-values.yaml  helm values built from secrets.env (never commit this)

Requires: PyYAML.  Optional: jsonschema (for full validation).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required:  pip install pyyaml   (or: pip install -r tools/requirements.txt)")

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schema" / "app-config.schema.json"
PLACEHOLDER = re.compile(r"\$\{(name|version|registry)\}")


# ----------------------------------------------------------------------------- loading
def load_config(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        sys.exit(f"{path}: top level must be a mapping")
    return data


def validate(data: dict) -> list[str]:
    """Return a list of human-readable problems (empty list == valid)."""
    problems: list[str] = []
    try:
        import jsonschema  # type: ignore
    except ImportError:
        problems.append("jsonschema not installed — only basic checks were run (pip install jsonschema)")
        if data.get("apiVersion") != "appconfig.demo/v1":
            problems.append("apiVersion must be appconfig.demo/v1")
        if not data.get("services"):
            problems.append("services must contain at least one entry")
        return problems

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    for err in sorted(validator.iter_errors(data), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in err.path) or "<root>"
        problems.append(f"{where}: {err.message}")

    # Cross-field checks the schema language cannot express.
    names = [s["name"] for s in data.get("services", [])]
    if len(names) != len(set(names)):
        problems.append("services: names must be unique")
    for svc in data.get("services", []):
        for other in (svc.get("network") or {}).get("allowFrom", []) or []:
            if other not in names:
                problems.append(f"services/{svc['name']}/network/allowFrom: unknown service '{other}'")
            elif other == svc["name"]:
                problems.append(f"services/{svc['name']}/network/allowFrom: a service cannot allow itself")
        auto = (svc.get("scale") or {}).get("autoscale") or {}
        if auto.get("enabled") and auto.get("minReplicas", 1) > auto.get("maxReplicas", 1):
            problems.append(f"services/{svc['name']}/scale/autoscale: minReplicas > maxReplicas")
        pnames = [p["name"] for p in svc.get("ports", [])]
        if len(pnames) != len(set(pnames)):
            problems.append(f"services/{svc['name']}/ports: port names must be unique")
        snames = [x["name"] for x in svc.get("secrets") or []]
        if len(snames) != len(set(snames)):
            problems.append(f"services/{svc['name']}/secrets: names must be unique")
    hosts = data.get("hosts") or {}
    for key, default in (("setupScript", "setup/setup.sh"), ("configureScript", "setup/configure.sh")):
        script = hosts.get(key, default)
        if not (ROOT / script).is_file():
            problems.append(f"hosts/{key}: file not found: {script}")
    return problems


# ----------------------------------------------------------------------------- resolving
def expand(value, ctx: dict):
    """Recursively replace ${name} ${version} ${registry} inside strings."""
    if isinstance(value, str):
        return PLACEHOLDER.sub(lambda m: ctx[m.group(1)], value)
    if isinstance(value, list):
        return [expand(v, ctx) for v in value]
    if isinstance(value, dict):
        return {k: expand(v, ctx) for k, v in value.items()}
    return value


def resolve(data: dict, registry_override: str | None = None) -> dict:
    """Apply defaults + placeholders and return a fully explicit model."""
    meta = data["metadata"]
    sources = data.get("sources", {}) or {}
    registry = registry_override if registry_override is not None else sources.get("imageRegistry", "") or ""
    ctx = {"name": meta["name"], "version": meta["version"], "registry": registry}
    d = expand(data, ctx)

    name, version = meta["name"], meta["version"]
    sources = d.get("sources", {}) or {}          # re-read AFTER placeholder expansion
    k8s = d.get("kubernetes", {}) or {}
    hosts = d.get("hosts", {}) or {}
    targets = d.get("targets", {}) or {}
    azure = targets.get("azure", {}) or {}

    services = []
    for s in d["services"]:
        img = s["image"]
        ports = []
        for p in s["ports"]:
            ports.append({
                "name": p["name"],
                "containerPort": p["containerPort"],
                "servicePort": p.get("servicePort", p["containerPort"]),
                "protocol": p.get("protocol", "TCP"),
                "expose": p.get("expose", "cluster"),
            })
        scale = s.get("scale", {}) or {}
        auto = scale.get("autoscale", {}) or {}
        health = s.get("health", {}) or {}
        services.append({
            "name": s["name"],
            "description": s.get("description", ""),
            "build": {
                "context": (s.get("build") or {}).get("context", ""),
                "dockerfile": (s.get("build") or {}).get("dockerfile", "Dockerfile"),
            },
            "image": {
                "repository": img["repository"],
                "tag": img.get("tag") or version,
                "pullPolicy": img.get("pullPolicy", "IfNotPresent"),
                "full": f"{registry + '/' if registry else ''}{img['repository']}:{img.get('tag') or version}",
            },
            "ports": ports,
            "config": dict(s.get("config", {}) or {}),
            "secretKeys": [x["name"] for x in (s.get("secrets") or [])],
            "health": {
                "path": health.get("path", "/health"),
                "readinessInitialDelaySeconds": health.get("readinessInitialDelaySeconds", 2),
                "livenessInitialDelaySeconds": health.get("livenessInitialDelaySeconds", 5),
            },
            "replicas": scale.get("replicas", 1),
            "autoscale": {
                "enabled": bool(auto.get("enabled", False)),
                "minReplicas": auto.get("minReplicas", 1),
                "maxReplicas": auto.get("maxReplicas", 1),
                "targetCPUUtilizationPercentage": auto.get("targetCPUUtilizationPercentage", 70),
            },
            "resources": s.get("resources", {}) or {},
            "allowFrom": list((s.get("network") or {}).get("allowFrom", []) or []),
        })

    return {
        "name": name,
        "version": version,
        "description": meta.get("description", ""),
        "owner": meta.get("owner", ""),
        "labels": dict(meta.get("labels", {}) or {}),
        "registry": registry,
        "imagePullSecret": sources.get("imagePullSecret", "") or "",
        "files": list(sources.get("files", []) or []),
        "namespace": k8s.get("namespace") or name,
        "networkPolicy": {
            "enabled": (k8s.get("networkPolicy") or {}).get("enabled", True),
            "defaultDeny": (k8s.get("networkPolicy") or {}).get("defaultDeny", True),
        },
        "ingress": {
            "enabled": (k8s.get("ingress") or {}).get("enabled", False),
            "className": (k8s.get("ingress") or {}).get("className", ""),
            "host": (k8s.get("ingress") or {}).get("host", ""),
        },
        "services": services,
        "hosts": {
            "dockerBaseImage": (hosts.get("baseImage") or {}).get("docker", "ubuntu:24.04"),
            "azureBaseImage": (hosts.get("baseImage") or {}).get("azure", {}),
            "adminUser": hosts.get("adminUser", "azureuser"),
            "packages": list(hosts.get("packages", []) or []),
            "exposePorts": [
                {"name": p["name"], "port": p["port"], "protocol": p.get("protocol", "TCP"), "source": p.get("source", "*")}
                for p in (hosts.get("exposePorts") or [])
            ],
            "setupScript": hosts.get("setupScript", "setup/setup.sh"),
            "configureScript": hosts.get("configureScript", "setup/configure.sh"),
            "ansible": {
                "enabled": (hosts.get("ansible") or {}).get("enabled", False),
                "playbook": (hosts.get("ansible") or {}).get("playbook", "ansible/site.yml"),
            },
            "settings": dict(hosts.get("settings", {}) or {}),
        },
        "targets": {
            "local": {
                "clusterName": (targets.get("local") or {}).get("clusterName") or name,
                "kindConfig": (targets.get("local") or {}).get("kindConfig", "kind-config.yaml"),
            },
            "azure": {
                "location": azure.get("location", "eastus"),
                "resourceGroup": azure.get("resourceGroup") or f"rg-{name}",
                "acrName": azure.get("acrName") or "",
                "aks": {
                    "nodeCount": (azure.get("aks") or {}).get("nodeCount", 2),
                    "nodeVmSize": (azure.get("aks") or {}).get("nodeVmSize", "Standard_B2ms"),
                    "autoscale": {
                        "enabled": ((azure.get("aks") or {}).get("autoscale") or {}).get("enabled", False),
                        "minCount": ((azure.get("aks") or {}).get("autoscale") or {}).get("minCount", 1),
                        "maxCount": ((azure.get("aks") or {}).get("autoscale") or {}).get("maxCount", 3),
                    },
                    "tier": (azure.get("aks") or {}).get("tier", "free"),
                    "kubernetesVersion": (azure.get("aks") or {}).get("kubernetesVersion", ""),
                    "networkPolicy": (azure.get("aks") or {}).get("networkPolicy", "cilium"),
                },
                "vm": {
                    "enabled": (azure.get("vm") or {}).get("enabled", False),
                    "size": (azure.get("vm") or {}).get("size", "Standard_B1s"),
                },
                "keyVault": {"enabled": (azure.get("keyVault") or {}).get("enabled", False)},
            },
        },
    }


# ----------------------------------------------------------------------------- renderers
def render_helm(m: dict) -> str:
    values = {
        "nameOverride": m["name"],
        "namespace": m["namespace"],
        "version": m["version"],
        "global": {
            "imageRegistry": m["registry"],
            "imagePullSecret": m["imagePullSecret"],
            "labels": m["labels"],
        },
        "networkPolicy": m["networkPolicy"],
        "ingress": m["ingress"],
        "services": {
            s["name"]: {
                "image": {"repository": s["image"]["repository"], "tag": s["image"]["tag"], "pullPolicy": s["image"]["pullPolicy"]},
                "ports": s["ports"],
                "config": s["config"],
                "secretKeys": s["secretKeys"],
                "health": s["health"],
                "replicas": s["replicas"],
                "autoscale": s["autoscale"],
                "resources": s["resources"],
                "allowFrom": s["allowFrom"],
            }
            for s in m["services"]
        },
        # secrets are merged in from build/secrets-values.yaml (generated from secrets.env)
        "secrets": {},
    }
    header = "# GENERATED by tools/appconfig.py from app.config.yaml — do not edit, edit app.config.yaml instead.\n"
    return header + yaml.safe_dump(values, sort_keys=False, default_flow_style=False)


def _q(v) -> str:
    return shlex.quote(str(v))


def render_env(m: dict) -> str:
    """Bash-sourceable variables used by scripts/ and scripts/azure/."""
    lines = [
        "# GENERATED by tools/appconfig.py from app.config.yaml — do not edit.",
        f"APP_NAME={_q(m['name'])}",
        f"APP_VERSION={_q(m['version'])}",
        f"APP_NAMESPACE={_q(m['namespace'])}",
        f"IMAGE_REGISTRY={_q(m['registry'])}",
        f"IMAGE_PULL_SECRET={_q(m['imagePullSecret'])}",
        f"KIND_CLUSTER_NAME={_q(m['targets']['local']['clusterName'])}",
        f"KIND_CONFIG={_q(m['targets']['local']['kindConfig'])}",
        f"SERVICES={_q(' '.join(s['name'] for s in m['services']))}",
        f"PUBLIC_SERVICES={_q(' '.join(s['name'] for s in m['services'] if any(p['expose'] == 'public' for p in s['ports'])))}",
        f"NETWORK_POLICY_ENABLED={_q(str(m['networkPolicy']['enabled']).lower())}",
    ]
    for s in m["services"]:
        n = s["name"].upper().replace("-", "_")
        lines += [
            f"SERVICE_{n}_IMAGE={_q(s['image']['full'])}",
            f"SERVICE_{n}_IMAGE_REPO={_q(s['image']['repository'])}",
            f"SERVICE_{n}_IMAGE_TAG={_q(s['image']['tag'])}",
            f"SERVICE_{n}_BUILD_CONTEXT={_q(s['build']['context'])}",
            f"SERVICE_{n}_DOCKERFILE={_q(s['build']['dockerfile'])}",
            f"SERVICE_{n}_K8S_NAME={_q(m['name'] + '-' + s['name'])}",
            f"SERVICE_{n}_PORT={_q(s['ports'][0]['servicePort'])}",
            f"SERVICE_{n}_CONTAINER_PORT={_q(s['ports'][0]['containerPort'])}",
            f"SERVICE_{n}_HEALTH_PATH={_q(s['health']['path'])}",
            f"SERVICE_{n}_REPLICAS={_q(s['replicas'])}",
            f"SERVICE_{n}_HPA_MIN={_q(s['autoscale']['minReplicas'])}",
            f"SERVICE_{n}_HPA_MAX={_q(s['autoscale']['maxReplicas'])}",
            f"SERVICE_{n}_SECRET_KEYS={_q(' '.join(s['secretKeys']))}",
        ]
    az = m["targets"]["azure"]
    acr = az["acrName"] or re.sub(r"[^a-z0-9]", "", m["name"]) + "acr"
    lines += [
        f"AZ_LOCATION={_q(az['location'])}",
        f"AZ_RESOURCE_GROUP={_q(az['resourceGroup'])}",
        f"AZ_ACR_NAME={_q(acr)}",
        f"AZ_AKS_NAME={_q('aks-' + m['name'])}",
        f"AZ_AKS_NODE_COUNT={_q(az['aks']['nodeCount'])}",
        f"AZ_AKS_NODE_VM_SIZE={_q(az['aks']['nodeVmSize'])}",
        f"AZ_AKS_AUTOSCALE={_q(str(az['aks']['autoscale']['enabled']).lower())}",
        f"AZ_AKS_MIN_COUNT={_q(az['aks']['autoscale']['minCount'])}",
        f"AZ_AKS_MAX_COUNT={_q(az['aks']['autoscale']['maxCount'])}",
        f"AZ_AKS_TIER={_q(az['aks']['tier'])}",
        f"AZ_AKS_K8S_VERSION={_q(az['aks']['kubernetesVersion'])}",
        f"AZ_AKS_NETWORK_POLICY={_q(az['aks']['networkPolicy'])}",
        f"AZ_VM_ENABLED={_q(str(az['vm']['enabled']).lower())}",
        f"AZ_VM_NAME={_q('vm-' + m['name'])}",
        f"AZ_VM_SIZE={_q(az['vm']['size'])}",
        f"AZ_VM_IMAGE={_q(m['hosts']['azureBaseImage'].get('urnAlias') or 'Ubuntu2404')}",
        f"AZ_VM_ADMIN_USER={_q(m['hosts']['adminUser'])}",
        f"AZ_KEYVAULT_ENABLED={_q(str(az['keyVault']['enabled']).lower())}",
        f"AZ_KEYVAULT_NAME={_q('kv-' + m['name'])}",
        "HOST_PORTS=" + _q(" ".join(f"{p['port']}/{p['protocol']}" for p in m["hosts"]["exposePorts"])),
    ]
    return "\n".join(lines) + "\n"


def render_service_envs(m: dict) -> dict[str, str]:
    """One docker --env-file per service (KEY=value lines; values may contain spaces)."""
    out = {}
    for s in m["services"]:
        lines = [f"APP_NAME={m['name']}", f"SERVICE_NAME={s['name']}", f"APP_VERSION={m['version']}"]
        lines += [f"{k}={v}" for k, v in s["config"].items()]
        out[s["name"]] = "\n".join(lines) + "\n"
    return out


def render_host(m: dict) -> tuple[str, str]:
    """host-config.env (sourced by setup/*.sh and cloud-init) + host-files.tsv."""
    h = m["hosts"]
    env = [
        "# GENERATED by tools/appconfig.py from app.config.yaml — do not edit.",
        f"APP_NAME={_q(m['name'])}",
        f"APP_VERSION={_q(m['version'])}",
        f"IMAGE_REGISTRY={_q(m['registry'])}",
        f"ADMIN_USER={_q(h['adminUser'])}",
        f"PACKAGES={_q(' '.join(h['packages']))}",
        "EXPOSE_PORTS=" + _q(" ".join(f"{p['port']}/{p['protocol'].lower()}" for p in h["exposePorts"])),
        f"SERVICES={_q(' '.join(s['name'] for s in m['services']))}",
    ]
    for s in m["services"]:
        n = s["name"].upper().replace("-", "_")
        p = s["ports"][0]
        env += [
            f"SERVICE_{n}_IMAGE={_q(s['image']['full'])}",
            f"SERVICE_{n}_HOST_PORT={_q(p['servicePort'])}",
            f"SERVICE_{n}_CONTAINER_PORT={_q(p['containerPort'])}",
            f"SERVICE_{n}_EXPOSE={_q(p['expose'])}",
        ]
    for k, v in h["settings"].items():
        env.append(f"SETTING_{k}={_q(v)}")
    tsv = "\n".join(
        "\t".join([f["name"], f["url"], f["dest"], f.get("mode", "0644"), f.get("sha256", "") or "-"])
        for f in m["files"]
    )
    return "\n".join(env) + "\n", (tsv + "\n" if tsv else "")


def render_compose(m: dict) -> str:
    """docker compose file: same images, ports, config and secrets — no Kubernetes needed."""
    services = {}
    for s in m["services"]:
        svc = {
            "image": s["image"]["full"],
            "environment": {**s["config"], "APP_NAME": m["name"], "SERVICE_NAME": s["name"], "APP_VERSION": m["version"]},
            # alias == the Kubernetes Service name, so http://<name>-api works in compose too
            "networks": {m["name"]: {"aliases": [f"{m['name']}-{s['name']}"]}},
            "restart": "unless-stopped",
        }
        if s["build"]["context"]:
            svc["build"] = {"context": s["build"]["context"], "dockerfile": s["build"]["dockerfile"]}
        pub = [p for p in s["ports"] if p["expose"] == "public"]
        if pub:
            svc["ports"] = [f"{p['servicePort']}:{p['containerPort']}" for p in pub]
        if s["secretKeys"]:
            svc["env_file"] = ["secrets.env"]
        services[s["name"]] = svc
    doc = {"name": m["name"], "services": services, "networks": {m["name"]: {"driver": "bridge"}}}
    header = "# GENERATED by tools/appconfig.py — run:  docker compose -f build/docker-compose.yaml --project-directory . up --build\n"
    return header + yaml.safe_dump(doc, sort_keys=False)


def render_cloudinit(m: dict, host_env: str, host_tsv: str) -> str:
    """#cloud-config for the Azure VM (az vm create --custom-data / terraform custom_data).
    Embeds the host config + setup scripts and runs them once at first boot."""
    import base64

    def b64(text: str) -> str:
        return base64.b64encode(text.encode()).decode()

    app_dir = f"/opt/{m['name']}"
    setup = (ROOT / m["hosts"]["setupScript"]).read_text(encoding="utf-8")
    configure = (ROOT / m["hosts"]["configureScript"]).read_text(encoding="utf-8")
    doc = {
        "package_update": True,
        "packages": m["hosts"]["packages"],
        "write_files": [
            {"path": f"{app_dir}/host-config.env", "permissions": "0640", "encoding": "b64", "content": b64(host_env)},
            {"path": f"{app_dir}/host-files.tsv", "permissions": "0640", "encoding": "b64", "content": b64(host_tsv)},
            {"path": f"{app_dir}/setup.sh", "permissions": "0750", "encoding": "b64", "content": b64(setup)},
            {"path": f"{app_dir}/configure.sh", "permissions": "0750", "encoding": "b64", "content": b64(configure)},
        ] + [
            {"path": f"{app_dir}/env/{svc}.env", "permissions": "0640", "encoding": "b64", "content": b64(text)}
            for svc, text in render_service_envs(m).items()
        ],
        "runcmd": [
            f"bash {app_dir}/setup.sh 2>&1 | tee -a /var/log/{m['name']}-setup.log",
            f"bash {app_dir}/configure.sh 2>&1 | tee -a /var/log/{m['name']}-configure.log",
        ],
        "final_message": f"{m['name']} host setup finished after $UPTIME seconds",
    }
    return "#cloud-config\n# GENERATED by tools/appconfig.py — do not edit\n" + yaml.safe_dump(doc, sort_keys=False, width=1000)


def render_secrets(m: dict, secrets_env: Path) -> str:
    """Turn secrets.env (KEY=value lines) into helm values: secrets.<service>.<KEY>."""
    kv: dict[str, str] = {}
    if secrets_env.exists():
        for raw in secrets_env.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip().strip('"').strip("'")
    out = {"secrets": {}}
    missing = []
    for s in m["services"]:
        if not s["secretKeys"]:
            continue
        out["secrets"][s["name"]] = {}
        for key in s["secretKeys"]:
            if key in kv:
                out["secrets"][s["name"]][key] = kv[key]
            else:
                missing.append(f"{s['name']}.{key}")
    if missing:
        print(f"WARNING: no value for secret(s) {', '.join(missing)} in {secrets_env} — pods will see empty values", file=sys.stderr)
    return "# GENERATED from secrets.env — NEVER COMMIT THIS FILE\n" + yaml.safe_dump(out, sort_keys=False)


# ----------------------------------------------------------------------------- CLI
def cmd_show(m: dict) -> None:
    print(f"App:        {m['name']}  v{m['version']}   namespace={m['namespace']}   registry={m['registry'] or '(local)'}")
    print(f"Files:      {len(m['files'])} external file(s) to download onto hosts")
    print("Services:")
    for s in m["services"]:
        ports = ", ".join(f"{p['servicePort']}->{p['containerPort']}/{p['protocol']} ({p['expose']})" for p in s["ports"])
        hpa = s["autoscale"]
        scale = f"replicas={s['replicas']}" + (f" hpa={hpa['minReplicas']}-{hpa['maxReplicas']}@{hpa['targetCPUUtilizationPercentage']}%cpu" if hpa["enabled"] else "")
        print(f"  - {s['name']:<8} image={s['image']['full']:<32} ports={ports}")
        print(f"    {'':<8} {scale}  config={list(s['config'])}  secrets={s['secretKeys']}  allowFrom={s['allowFrom'] or '-'}")
    h = m["hosts"]
    print(f"Hosts:      base={h['dockerBaseImage']} / azure {h['azureBaseImage'].get('offer', '?')}  ports={[p['port'] for p in h['exposePorts']]}  ansible={h['ansible']['enabled']}")
    az = m["targets"]["azure"]
    print(f"Azure:      {az['location']}  rg={az['resourceGroup']}  aks nodes={az['aks']['nodeCount']} ({az['aks']['nodeVmSize']}, {az['aks']['networkPolicy']} policy)  vm={az['vm']['enabled']}")


def cmd_get(m: dict, raw: dict, path: str) -> None:
    """Look the dotted path up in the resolved model first (get name), then in the raw file (get metadata.name)."""
    for source in (m, raw):
        cur = source
        try:
            for part in path.split("."):
                cur = cur[int(part)] if isinstance(cur, list) else cur[part]
        except (KeyError, IndexError, ValueError, TypeError):
            continue
        print(json.dumps(cur) if isinstance(cur, (dict, list)) else cur)
        return
    sys.exit(f"path not found: {path}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["validate", "show", "render", "get"])
    ap.add_argument("what", nargs="?", default="all", help="render target or dotted path for `get`")
    ap.add_argument("-c", "--config", default=str(ROOT / "app.config.yaml"))
    ap.add_argument("-o", "--out", default=str(ROOT / "build"))
    ap.add_argument("--registry", default=None, help="override sources.imageRegistry (used by scripts/azure)")
    ap.add_argument("--secrets-env", default=str(ROOT / "secrets.env"))
    args = ap.parse_args(argv)

    cfg_path = Path(args.config)
    data = load_config(cfg_path)
    problems = validate(data)
    hard = [p for p in problems if not p.startswith("jsonschema not installed")]

    if args.command == "validate":
        for p in problems:
            print(("WARN  " if p.startswith("jsonschema") else "ERROR ") + p)
        if hard:
            print(f"{cfg_path}: INVALID ({len(hard)} problem(s))")
            return 1
        print(f"{cfg_path}: OK")
        return 0

    if hard:
        for p in hard:
            print("ERROR " + p, file=sys.stderr)
        return 1

    model = resolve(data, args.registry)

    if args.command == "show":
        cmd_show(model)
        return 0
    if args.command == "get":
        cmd_get(model, data, args.what)
        return 0

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    what = args.what
    written = []
    if what in ("all", "helm"):
        (out / "helm-values.yaml").write_text(render_helm(model), encoding="utf-8"); written.append("helm-values.yaml")
    if what in ("all", "env"):
        (out / "config.env").write_text(render_env(model), encoding="utf-8"); written.append("config.env")
    if what in ("all", "host"):
        env, tsv = render_host(model)
        (out / "host-config.env").write_text(env, encoding="utf-8"); written.append("host-config.env")
        (out / "host-files.tsv").write_text(tsv, encoding="utf-8"); written.append("host-files.tsv")
        (out / "env").mkdir(exist_ok=True)
        for svc, text in render_service_envs(model).items():
            (out / "env" / f"{svc}.env").write_text(text, encoding="utf-8"); written.append(f"env/{svc}.env")
    if what in ("all", "cloudinit"):
        env, tsv = render_host(model)
        (out / "cloud-init.yaml").write_text(render_cloudinit(model, env, tsv), encoding="utf-8"); written.append("cloud-init.yaml")
    if what in ("all", "compose"):
        (out / "docker-compose.yaml").write_text(render_compose(model), encoding="utf-8"); written.append("docker-compose.yaml")
    if what in ("all", "secrets"):
        p = out / "secrets-values.yaml"
        p.write_text(render_secrets(model, Path(args.secrets_env)), encoding="utf-8")
        os.chmod(p, 0o600); written.append("secrets-values.yaml")
    if not written:
        sys.exit(f"unknown render target: {what}")
    print("rendered: " + ", ".join(f"{out.name}/{w}" for w in written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
