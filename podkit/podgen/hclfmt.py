"""Align `key = value` lines the way `terraform fmt` does, so generated files are fmt-clean.

Rules (a subset of hclwrite's formatter, enough for what podgen emits):
* consecutive single-line attributes in the same body are aligned on their `=`;
* an attribute whose value spans several lines (`{`, `[`, `(` or a heredoc) is written with a
  single space around `=` and ends the alignment group;
* blank lines, comments, block openers and closers end the group; heredoc bodies are untouched.
"""

from __future__ import annotations

import re

_ATTR = re.compile(r'^(\s*)("[^"]*"|[A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.*)$')
_HEREDOC = re.compile(r"<<-?([A-Za-z_][A-Za-z0-9_]*)\s*$")


def _is_multiline(value: str) -> bool:
    return value.endswith(("{", "[", "(")) or bool(_HEREDOC.search(value))


def align(text: str) -> str:
    out: list[str] = []
    group: list[tuple[str, str, str]] = []  # (indent, key, value)
    heredoc_end: str | None = None

    def flush() -> None:
        if not group:
            return
        width = max(len(key) for _, key, _ in group)
        for indent, key, value in group:
            out.append(f"{indent}{key.ljust(width)} = {value}")
        group.clear()

    for line in text.splitlines():
        if heredoc_end is not None:
            out.append(line)
            if line.strip() == heredoc_end:
                heredoc_end = None
            continue
        match = _ATTR.match(line)
        if match and not line.lstrip().startswith("#"):
            indent, key, value = match.groups()
            if _is_multiline(value):
                flush()
                out.append(f"{indent}{key} = {value}")
                heredoc = _HEREDOC.search(value)
                if heredoc:
                    heredoc_end = heredoc.group(1)
                continue
            group.append((indent, key, value))
            continue
        flush()
        out.append(line)
    flush()
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")
