"""One-off: `const AppTheme.x` is invalid Dart (const variables need no `const`
keyword).  Strip it everywhere the palette sweep introduced it."""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> int:
    changed = 0
    for path in ROOT.glob("lib/**/*.dart"):
        text = path.read_text(encoding="utf-8")
        if "const AppTheme." not in text:
            continue
        path.write_text(
            text.replace("const AppTheme.", "AppTheme."),
            encoding="utf-8",
            newline="",
        )
        changed += 1
        print(f"fixed: {path.relative_to(ROOT)}")
    print(f"{changed} files changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
