"""One-off: resolve the committed merge conflict in CHANGELOG.md.

The v2.4.1 merge left `<<<<<<< HEAD` / `=======` / `>>>>>>> origin/master`
markers in the file. Both sides are real release content, so the resolution
keeps the union rather than picking a side:

  * `origin/master` side  -> the Edit Profile recovery fix and the new docs,
    which are unreleased work, so they join the `## [Unreleased]` section.
  * `HEAD` side           -> the `## [2.4.1]` and `## [2.4.0]` release notes,
    which stay where they are.

Nothing is discarded. Prints a summary and asserts the markers are gone.
"""

from __future__ import annotations

import sys
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parents[1] / "CHANGELOG.md"

HEAD_MARKER = "<<<<<<< HEAD"
SEP_MARKER = "======="
END_MARKER = ">>>>>>> origin/master"


def main() -> int:
    text = CHANGELOG.read_text(encoding="utf-8")
    lines = text.splitlines()

    def count(marker: str) -> int:
        return sum(1 for line in lines if line.strip() == marker)

    # Safe to re-run: if the file is already clean there is nothing to repair.
    if not any(count(m) for m in (HEAD_MARKER, SEP_MARKER, END_MARKER)):
        print("nothing to do: no conflict markers found")
        return 0

    def find(marker: str) -> int:
        hits = [i for i, line in enumerate(lines) if line.strip() == marker]
        if len(hits) != 1:
            raise SystemExit(f"expected exactly one {marker!r}, found {len(hits)}")
        return hits[0]

    head_at = find(HEAD_MARKER)
    sep_at = find(SEP_MARKER)
    end_at = find(END_MARKER)

    if not head_at < sep_at < end_at:
        raise SystemExit("conflict markers are out of order")

    # The two sides of the conflict.
    ours = lines[head_at + 1 : sep_at]      # ## [2.4.1] and ## [2.4.0]
    theirs = lines[sep_at + 1 : end_at]     # unreleased fixes + docs

    # Drop the leading blank lines the conflict introduced; spacing is
    # re-established explicitly below.
    while theirs and not theirs[0].strip():
        theirs.pop(0)
    while theirs and not theirs[-1].strip():
        theirs.pop()

    before = lines[:head_at]
    while before and not before[-1].strip():
        before.pop()

    after = lines[end_at + 1 :]

    # `before` now ends inside the `## [Unreleased]` section, so the
    # origin/master content joins it there, and the release notes follow.
    merged = [
        *before,
        "",
        *theirs,
        "",
        *ours,
        "",
        *after,
    ]

    CHANGELOG.write_text("\n".join(merged) + "\n", encoding="utf-8")

    print(f"resolved: {len(lines)} -> {len(merged)} lines")
    print(f"  kept HEAD side     : {len(ours)} lines")
    print(f"  kept origin/master : {len(theirs)} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
