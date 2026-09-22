"""Command line interface: `python -m podgen ...` (or `podgen` once installed)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__, config, render


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="podgen", description="Generate Terraform, manifests and scripts from PodConfig files.")
    p.add_argument("--version", action="version", version=f"podgen {__version__}")
    sub = p.add_subparsers(dest="command", required=True)

    v = sub.add_parser("validate", help="validate PodConfig files against the schema")
    v.add_argument("configs", nargs="+", type=Path)
    v.add_argument("--provider", choices=config.PROVIDERS, help="override spec.provider")

    g = sub.add_parser("generate", help="generate build/<provider>/<name>/ for each config")
    g.add_argument("configs", nargs="+", type=Path)
    g.add_argument("--provider", choices=[*config.PROVIDERS, "all"], help="target provider (default: spec.provider; 'all' = every provider with a cloud block)")
    g.add_argument("--out", type=Path, default=Path("build"), help="output root (default: ./build)")
    g.add_argument("--modules-source", help="Terraform source for the shared modules (default: relative path to ./terraform/modules)")
    g.add_argument("--force", action="store_true", help="overwrite existing output")

    sub.add_parser("schema", help="print the JSON schema")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "schema":
            print(json.dumps(config.load_schema(), indent=2))
            return 0
        if args.command == "validate":
            for path in args.configs:
                raw = config.load(path, args.provider)
                print(f"OK   {path} ({raw['metadata']['name']}, providers: {', '.join(config.providers_in(raw))})")
            return 0
        if args.command == "generate":
            for path in args.configs:
                targets = config.providers_in(config.load(path)) if args.provider == "all" else [args.provider]
                for provider in targets:
                    raw = config.load(path, provider)
                    out_dir = args.out / raw["spec"]["provider"] / raw["metadata"]["name"]
                    ctx = config.build_context(raw, out_dir=out_dir, modules_source=args.modules_source)
                    files = render.generate(ctx, out_dir, force=args.force)
                    print(f"generated {out_dir} ({len(files)} files)")
                    print(f"  deploy:    {out_dir}/deploy.sh   (kubectl)  |  scripts/deploy.sh -m terraform {out_dir}")
                    print(f"  destroy:   {out_dir}/destroy.sh")
                    if ctx["configure"]["method"] != "none":
                        print(f"  configure: {ctx['configure']['method']} {ctx['configure']['target']} ({ctx['configure']['phase']}-deploy, from the command pod)")
            return 0
    except (config.ConfigError, FileExistsError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0
