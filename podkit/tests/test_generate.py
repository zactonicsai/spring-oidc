"""End-to-end generator tests: every example, every provider, output must be sane."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from podgen import config, render  # noqa: E402

EXAMPLES = sorted((ROOT / "examples").glob("*.yaml"))
PROVIDERS = ("aws", "azure", "gcp")

EXPECTED_FILES = [
    "pod.env", "deploy.sh", "destroy.sh", "configure.sh", "README.md",
    "k8s/serviceaccount.yaml", "k8s/workload.yaml",
    "terraform/versions.tf", "terraform/providers.tf", "terraform/main.tf",
    "terraform/variables.tf", "terraform/outputs.tf", "terraform/terraform.tfvars",
]


def _generate(tmp_path: Path, example: Path, provider: str) -> Path:
    raw = config.load(example, provider=provider)
    out = tmp_path / provider / raw["metadata"]["name"]
    ctx = config.build_context(raw, out_dir=out)
    render.generate(ctx, out, force=True)
    return out


@pytest.mark.parametrize("provider", PROVIDERS)
@pytest.mark.parametrize("example", EXAMPLES, ids=[e.stem for e in EXAMPLES])
def test_generate_all(tmp_path: Path, example: Path, provider: str) -> None:
    out = _generate(tmp_path, example, provider)
    for rel in EXPECTED_FILES:
        assert (out / rel).is_file(), rel

    # shell scripts must parse and be executable
    for script in out.glob("*.sh"):
        subprocess.run(["bash", "-n", str(script)], check=True)
        assert script.stat().st_mode & 0o111

    # manifests must be valid YAML with the expected kinds
    docs = [d for d in yaml.safe_load_all((out / "k8s/workload.yaml").read_text()) if d]
    kinds = {d["kind"] for d in docs}
    assert "Deployment" in kinds
    deployment = next(d for d in docs if d["kind"] == "Deployment")
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    assert container["resources"]["requests"] and container["resources"]["limits"]
    assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]

    sa = yaml.safe_load((out / "k8s/serviceaccount.yaml").read_text())
    assert sa["kind"] == "ServiceAccount"

    # pod.env is a flat KEY=VALUE file
    env = (out / "pod.env").read_text()
    assert f"PROVIDER={provider}" in env
    assert "NAME=" in env and "NAMESPACE=" in env

    # terraform root references the right cloud module and never leaks secret values
    main_tf = (out / "terraform/main.tf").read_text()
    assert re.search(rf'source\s*=\s*".*terraform/modules/{provider}"', main_tf)
    assert "module.cloud.secret_values" in main_tf


def test_postgres_flow(tmp_path: Path) -> None:
    out = _generate(tmp_path, ROOT / "examples/pg-client.yaml", "aws")
    docs = [d for d in yaml.safe_load_all((out / "k8s/workload.yaml").read_text()) if d]
    kinds = {d["kind"] for d in docs}
    assert {"ConfigMap", "Deployment", "NetworkPolicy"} <= kinds
    deployment = next(d for d in docs if d["kind"] == "Deployment")
    container = deployment["spec"]["template"]["spec"]["containers"][0]
    env = {e["name"]: e.get("value") for e in container["env"]}
    assert env["PGHOST"] == "pg.internal.example.com" and env["PGSSLMODE"] == "require"
    assert container["envFrom"] == [{"secretRef": {"name": "pg-client-env"}}]
    policy = next(d for d in docs if d["kind"] == "NetworkPolicy")
    cidrs = [t["ipBlock"]["cidr"] for rule in policy["spec"]["egress"] for t in rule["to"] if "ipBlock" in t]
    assert "10.50.0.0/16" in cidrs

    vars_yml = yaml.safe_load((out / "ansible/vars.yml").read_text())
    assert vars_yml["password_secret"] == "pg-client-env" and vars_yml["bootstrap_sql"] == "{{ build_dir }}/bootstrap.sql"
    assert (out / "bootstrap.sql").is_file()
    env_file = (out / "configure.env").read_text()
    assert 'BOOTSTRAP_SQL="${BUILD_DIR}/bootstrap.sql"' in env_file
    env_pod = (out / "pod.env").read_text()
    assert "CLOUD_SECRETS=PGPASSWORD=orders-pg-password" in env_pod and "ENV_SECRET=pg-client-env" in env_pod
    assert "CONFIGURE_TARGET=playbooks/postgres-client.yml" in env_pod and "CONFIGURE_PHASE=post" in env_pod


def test_tls_flow(tmp_path: Path) -> None:
    server = _generate(tmp_path, ROOT / "examples/java-server.yaml", "gcp")
    client = _generate(tmp_path, ROOT / "examples/java-client.yaml", "gcp")
    vars_yml = yaml.safe_load((server / "ansible/vars.yml").read_text())
    assert vars_yml["is_server"] is True
    assert "java-server.apps.svc.cluster.local" in vars_yml["dns_names"]
    docs = [d for d in yaml.safe_load_all((server / "k8s/workload.yaml").read_text()) if d]
    deployment = next(d for d in docs if d["kind"] == "Deployment")
    mounts = {m["name"]: m["mountPath"] for m in deployment["spec"]["template"]["spec"]["containers"][0]["volumeMounts"]}
    assert mounts == {"keystore": "/etc/tls/keystore", "truststore": "/etc/tls/truststore"}
    assert "Service" in {d["kind"] for d in docs}
    server_env = (server / "pod.env").read_text()
    assert "CONFIGURE_PHASE=pre" in server_env and "TLS_KEYSTORE_SECRET=java-server-keystore" in server_env
    # the client uses the shell variant
    client_env = (client / "pod.env").read_text()
    assert "CONFIGURE_METHOD=shell" in client_env and "CONFIGURE_TARGET=configure/java-keystore.sh" in client_env
    assert "IS_SERVER=false" in (client / "configure.env").read_text()


def test_invalid_config_is_rejected(tmp_path: Path) -> None:
    bad = tmp_path / "bad.yaml"
    bad.write_text("apiVersion: podkit/v1\nkind: PodConfig\nmetadata: {name: Bad_Name}\nspec: {provider: aws, image: {repository: x}}\n")
    with pytest.raises(config.ConfigError):
        config.load(bad)


def test_cli_roundtrip(tmp_path: Path) -> None:
    cmd = [sys.executable, "-m", "podgen", "generate", str(ROOT / "examples/java-client.yaml"),
           "--provider", "all", "--out", str(tmp_path / "build")]
    subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True)
    for provider in PROVIDERS:
        assert (tmp_path / "build" / provider / "java-client" / "deploy.sh").is_file()
    # refuses to overwrite without --force
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0 and "--force" in (result.stderr + result.stdout)
