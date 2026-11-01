"""Strip `const` from expressions that are no longer compile-time constants.

Run after `tool/theme_sweep.py`.  For every line that mentions a runtime theme
lookup, walk backwards to the nearest `const Foo(` / `const [` whose brackets are
still open at that line, and drop the modifier.  Brackets are tracked so the
right expression is chosen and no unrelated `const` is touched.

The analyzer is the authority: run it afterwards and there must be no
`const_eval_method_invocation` / `invalid_constant` diagnostics left.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONST_OPEN = re.compile(r"\bconst\s+(?:[A-Z][A-Za-z0-9_]*(?:\.\w+)?\s*\(|\[|\{)")
TRIGGER = ("Theme.of(context)", "AppTheme.")


def balance(text: str) -> int:
    return (
        text.count("(")
        + text.count("[")
        + text.count("{")
        - text.count(")")
        - text.count("]")
        - text.count("}")
    )


def strip_enclosing(lines: list[str], index: int) -> bool:
    line = lines[index]

    # 1. Same-line: `child: const Icon(color: Theme.of(context)…)`
    for match in CONST_OPEN.finditer(line):
        if line[match.start() :].count(")") == 0 and balance(
            line[match.end() - 1 :]
        ) > 0:
            lines[index] = line[: match.start()] + line[match.end() - 1 :]
            return True

    # 2. Multi-line: find the innermost still-open `const` before this line.
    open_depth = 0
    for back in range(index - 1, max(-1, index - 40), -1):
        candidate = lines[back]
        matches = list(CONST_OPEN.finditer(candidate))
        if matches:
            opened_at = matches[-1]
            opened = balance(candidate[opened_at.end() - 1 :]) + open_depth
            if opened > 0:
                lines[back] = (
                    candidate[: opened_at.start()]
                    + candidate[opened_at.end() - 1 :]
                )
                return True
        open_depth += balance(candidate)
        if open_depth < 0:
            return False
    return False


def fix_file(path: pathlib.Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    removed = 0
    for index, line in enumerate(lines):
        if not any(token in line for token in TRIGGER):
            continue
        # A single line may hold several nested const widgets.
        while strip_enclosing(lines, index):
            removed += 1
    if removed:
        path.write_text("\n".join(lines), encoding="utf-8", newline="")
    return removed


def main(argv: list[str]) -> int:
    targets = argv[1:] or ["lib"]
    total = 0
    for target in targets:
        base = ROOT / target
        paths = [base] if base.is_file() else sorted(base.rglob("*.dart"))
        for path in paths:
            removed = fix_file(path)
            if removed:
                total += removed
                print(f"{path.relative_to(ROOT)}: -{removed} const")
    print(f"{total} const modifiers removed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
