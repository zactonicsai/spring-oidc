"""Render Python values as HCL literals for the generated Terraform."""

from __future__ import annotations

import json
import re

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


def _escape(text: str) -> str:
    # Terraform would try to interpolate ${...} and %{...}; keep them literal.
    return text.replace("${", "$${").replace("%{", "%%{")


def to_hcl(value, indent: int = 0) -> str:
    """Return `value` as an HCL literal. `indent` is the column where the literal starts."""
    inner = " " * (indent + 2)
    outer = " " * indent
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        if "\n" in value:
            body = _escape(value)
            if not body.endswith("\n"):
                body += "\n"
            lines = "".join(f"{inner}{line}\n" for line in body.splitlines())
            return f"<<-EOT\n{lines}{outer}EOT"
        return json.dumps(_escape(value))
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for key, item in value.items():
            k = key if _IDENT.match(str(key)) else json.dumps(str(key))
            rows.append(f"{inner}{k} = {to_hcl(item, indent + 2)}")
        return "{\n" + "\n".join(rows) + f"\n{outer}}}"
    if isinstance(value, (list, tuple)):
        if not value:
            return "[]"
        rows = [f"{inner}{to_hcl(item, indent + 2)}," for item in value]
        return "[\n" + "\n".join(rows) + f"\n{outer}]"
    raise TypeError(f"cannot render {type(value).__name__} as HCL")
