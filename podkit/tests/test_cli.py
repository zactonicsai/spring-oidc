"""CLI tests: plugin discovery, help, and dry-run flows (no kubectl or cloud CLI needed)."""

from __future__ import annotations

import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PODKIT = ROOT / "bin" / "podkit"
PROVIDERS = ("aws", "azure", "gcp")
BUILTIN_RESOURCES = {
    "cluster", "command-pod", "config", "configure", "destroy", "doctor", "identity",
    "image", "namespace", "pod", "secret", "status", "tls",
}


def run(*args: str, env: dict | None = None, check: bool = True) -> subprocess.CompletedProcess:
    full_env = {**os.environ, "PATH": "/usr/bin:/bin", "PODKIT_YES": "1", **(env or {})}
    return subprocess.run([str(PODKIT), *args], cwd=ROOT, env=full_env, check=check,
                          capture_output=True, text=True)


def strip(text: str) -> str:
    import re
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


@pytest.fixture(scope="module")
def builds(tmp_path_factory: pytest.TempPathFactory) -> Path:
    out = tmp_path_factory.mktemp("build")
    subprocess.run([sys.executable, "-m", "podgen", "generate", *sorted(map(str, (ROOT / "examples").glob("*.yaml"))),
                    "--provider", "all", "--out", str(out), "--force"], cwd=ROOT, check=True, capture_output=True)
    return out


def test_resources_listed() -> None:
    out = run("resources").stdout
    names = {line.split()[0] for line in out.splitlines() if line and not line.startswith(" ")}
    assert BUILTIN_RESOURCES <= names
    assert "_template" not in names


@pytest.mark.parametrize("resource", sorted(BUILTIN_RESOURCES))
def test_help_per_resource(resource: str) -> None:
    out = run("help", resource).stdout
    assert out.startswith(f"podkit {resource} —")
    assert "podkit " in out.splitlines()[2]


def test_unknown_resource_and_verb() -> None:
    assert "unknown resource" in strip(run("nope", check=False).stderr)
    assert "unknown verb" in strip(run("pod", "bogus", check=False).stderr)


@pytest.mark.parametrize("provider", PROVIDERS)
def test_dry_run_deploy_and_destroy(builds: Path, provider: str) -> None:
    build = builds / provider / "pg-client"
    out = strip(run("--dry-run", "pod", "deploy", str(build)).stderr)
    assert "read secret orders-pg-password" in out
    assert "kubectl -n apps create secret generic pg-client-env" in out
    assert "rollout status deployment/pg-client" in out
    assert "would run ansible step playbooks/postgres-client.yml (post-deploy)" in out
    assert out.index("serviceaccount.yaml") < out.index("applying workload manifests")

    out = strip(run("--dry-run", "destroy", str(build), "--everything").stderr)
    assert "teardown plan for pg-client" in out
    assert "kubectl delete --ignore-not-found --wait=true -f -" in out
    assert "terraform destroy -input=false -target=module.cloud" in out   # identity is enabled in this example
    assert "kubectl delete namespace apps" in out


def test_dry_run_tls_flow(builds: Path) -> None:
    server = builds / "gcp" / "java-server"
    out = strip(run("--dry-run", "pod", "deploy", str(server)).stderr)
    # pre-deploy step runs before the workload is applied
    assert out.index("would run ansible step playbooks/java-keystore.yml (pre-deploy)") < out.index("applying workload manifests")
    out = strip(run("--dry-run", "tls", "rotate", str(builds / "gcp" / "java-client")).stderr)
    assert "ROTATE=true" in out
    out = strip(run("--dry-run", "tls", "destroy", str(server), "--ca").stderr)
    assert "delete secret podkit-mtls-ca podkit-mtls-truststore" in out


def test_dry_run_has_no_side_effects(builds: Path) -> None:
    build = builds / "azure" / "pg-client"
    before = (build / "pod.env").read_text()
    run("--dry-run", "identity", "apply", str(build))
    run("--dry-run", "pod", "deploy", str(build), "-m", "terraform")
    assert (build / "pod.env").read_text() == before


def test_generated_wrappers_route_to_cli(builds: Path) -> None:
    build = builds / "aws" / "java-client"
    for name in ("deploy.sh", "destroy.sh", "configure.sh"):
        script = build / name
        assert script.stat().st_mode & stat.S_IXUSR
        assert 'bin/podkit"' in script.read_text()
    out = strip(subprocess.run([str(build / "deploy.sh"), "--dry-run"], cwd=ROOT, check=True, capture_output=True,
                               text=True, env={**os.environ, "PATH": "/usr/bin:/bin"}).stderr)
    assert "deploying java-client to namespace apps" in out


def test_plugin_discovery(tmp_path: Path) -> None:
    plugin = tmp_path / "hello.sh"
    plugin.write_text(
        'RESOURCE_DESC="Example plugin"\nRESOURCE_VERBS="greet"\n'
        'cmd_greet() { echo "hello ${1:-world} from $RESOURCE_NAME"; }\n'
    )
    env = {"PODKIT_PLUGIN_PATH": str(tmp_path)}
    assert "hello" in run("resources", env=env).stdout
    assert run("hello", "greet", "podkit", env=env).stdout.strip() == "hello podkit from hello"
    # a plugin with the name of a built-in overrides it
    (tmp_path / "doctor.sh").write_text('RESOURCE_DESC="mine"\nRESOURCE_VERBS="check"\ncmd_check() { echo overridden; }\n')
    assert run("doctor", "check", env=env).stdout.strip() == "overridden"


def test_broken_plugin_is_reported(tmp_path: Path) -> None:
    (tmp_path / "broken.sh").write_text('RESOURCE_DESC="x"\nRESOURCE_VERBS="go"\n')  # no cmd_go
    result = run("broken", "go", env={"PODKIT_PLUGIN_PATH": str(tmp_path)}, check=False)
    assert result.returncode != 0 and "defines no cmd_go" in strip(result.stderr)
