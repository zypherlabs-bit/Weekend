"""Oracle-driven `const` repair.

Reads `flutter analyze` output and, for every invalid-constant diagnostic,
removes the `const` modifier of the innermost constructor that encloses the
reported line.  Iterate until the analyzer reports no such errors.

Usage:
    flutter analyze > analyze.txt
    python tool/fix_invalid_const.py analyze.txt
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIAG = re.compile(r"^\s*error - .* - (?P<path>[^ :]+\.dart):(?P<line>\d+):\d+ - "
                  r"(?P<code>const_eval_method_invocation|invalid_constant)$")
CONST_OPEN = re.compile(r"\bconst\s+(?:[A-Z][A-Za-z0-9_]*(?:\.\w+)?\s*\(|\[|\{)")


def balance(text: str) -> int:
    return (
        text.count("(")
        + text.count("[")
        + text.count("{")
        - text.count(")")
        - text.count("]")
        - text.count("}")
    )


def remove_enclosing_const(lines: list[str], index: int) -> bool:
    open_depth = 0
    for back in range(index, max(-1, index - 60), -1):
        candidate = lines[back]
        matches = list(CONST_OPEN.finditer(candidate))
        trimmed = candidate
        # Ignore matches that are already closed on the same line.
        for match in reversed(matches):
            opened = balance(candidate[match.end() - 1 :]) + open_depth
            if opened > 0:
                lines[back] = (
                    candidate[: match.start()] + candidate[match.start() + 6 :]
                )
                return True
            trimmed = candidate
        open_depth += balance(trimmed)
        if open_depth < 0:
            return False
    return False


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    report = pathlib.Path(argv[1]).read_text(encoding="utf-8", errors="replace")
    targets: dict[pathlib.Path, set[int]] = {}
    for raw in report.splitlines():
        match = DIAG.match(raw.rstrip())
        if not match:
            continue
        path = (ROOT / match.group("path").replace("\\", "/")).resolve()
        targets.setdefault(path, set()).add(int(match.group("line")) - 1)

    fixed = 0
    for path, indexes in sorted(targets.items()):
        lines = path.read_text(encoding="utf-8").split("\n")
        for index in sorted(indexes, reverse=True):
            if remove_enclosing_const(lines, index):
                fixed += 1
        path.write_text("\n".join(lines), encoding="utf-8", newline="")
        print(f"{path.relative_to(ROOT)}: {len(indexes)} diagnostics")
    print(f"{fixed} const modifiers removed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
