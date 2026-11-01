"""Oracle-driven `const` repair, v2.

For every analyzer diagnostic that says a constant expression is invalid
(`const_eval_method_invocation`, `invalid_constant`, `const_with_non_const`,
`const_with_undefined_constructor`), find the *nearest enclosing* `const`
modifier around the reported offset and delete it.  Nearest-enclosing is
computed by bracket matching over the real file text, so single-line
expressions (`icon: const Icon(...)`) are handled as well as multi-line ones.

Usage:
    flutter analyze > analyze.txt
    python tool/fix_const_v2.py analyze.txt
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

DIAG = re.compile(
    r"^\s*error - .* - (?P<path>[^ :]+\.dart):(?P<line>\d+):(?P<col>\d+) - "
    r"(?P<code>const_eval_method_invocation|invalid_constant|"
    r"const_with_non_const|const_with_undefined_constructor)$"
)

CODES = {
    "const_eval_method_invocation",
    "invalid_constant",
    "const_with_non_const",
    "const_with_undefined_constructor",
}

CONST = re.compile(r"\bconst\b")


def skip_string(text: str, i: int) -> int:
    """Return the index just past the string literal starting at `i`."""
    quote = text[i]
    triple = text[i : i + 3] in ("'''", '"""')
    if triple:
        end = text.find(quote * 3, i + 3)
        return len(text) if end == -1 else end + 3
    i += 1
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == quote:
            return i + 1
        if c == "\n":
            return i
        i += 1
    return i


def match_bracket(text: str, open_idx: int) -> int:
    """Index of the bracket closing the one at `open_idx`, or -1."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    close = pairs[text[open_idx]]
    depth = 0
    i = open_idx
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = skip_string(text, i)
            continue
        if text.startswith("//", i):
            nl = text.find("\n", i)
            i = len(text) if nl == -1 else nl
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end == -1 else end + 2
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i if c == close else -1
        i += 1
    return -1


def const_span(text: str, start: int) -> tuple[int, int] | None:
    """Span [keyword_start, expression_end) of the `const` at `start`."""
    i = start + len("const")
    while i < len(text) and text[i] in " \t\n\r":
        i += 1
    if i >= len(text):
        return None
    if text[i] in "([{":
        end = match_bracket(text, i)
        return None if end == -1 else (start, end + 1)
    # Identifier (possibly dotted / generic): skip to the first bracket.
    j = i
    while j < len(text) and (text[j].isalnum() or text[j] in "_.<>,"):
        j += 1
    while j < len(text) and text[j] in " \t\n\r":
        j += 1
    if j < len(text) and text[j] in "([{":
        end = match_bracket(text, j)
        return None if end == -1 else (start, end + 1)
    # `const SomeIdentifier` with no brackets: a const variable reference.
    return (start, j)


def remove_nearest_enclosing_const(text: str, pos: int) -> tuple[str, bool]:
    best: tuple[int, int] | None = None
    for match in CONST.finditer(text):
        span = const_span(text, match.start())
        if span is None:
            continue
        start, end = span
        if start < pos < end:
            if best is None or start > best[0]:
                best = span
    if best is None:
        return text, False
    start, _ = best
    end = start + len("const")
    while end < len(text) and text[end] in " \t":
        end += 1
    return text[:start] + text[end:], True


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    report = pathlib.Path(argv[1]).read_text(encoding="utf-8", errors="replace")
    targets: dict[pathlib.Path, list[int]] = {}
    for raw in report.splitlines():
        match = DIAG.match(raw.rstrip())
        if not match or match.group("code") not in CODES:
            continue
        path = (ROOT / match.group("path").replace("\\", "/")).resolve()
        targets.setdefault(path, []).append(
            (int(match.group("line")), int(match.group("col")))
        )

    total = 0
    for path, marks in sorted(targets.items()):
        text = path.read_text(encoding="utf-8")
        # Offsets must be resolved before any edit, then applied back-to-front.
        offsets = []
        for line, col in marks:
            lines = text.split("\n")
            if line > len(lines):
                continue
            offsets.append(len("\n".join(lines[: line - 1])) + (1 if line > 1 else 0) + col - 1)
        fixed = 0
        for offset in sorted(set(offsets), reverse=True):
            text, ok = remove_nearest_enclosing_const(text, offset)
            fixed += 1 if ok else 0
        if fixed:
            path.write_text(text, encoding="utf-8", newline="")
        print(f"{path.relative_to(ROOT)}: {len(marks)} diagnostics, {fixed} fixed")
        total += fixed
    print(f"{total} const modifiers removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
