"""List every PostgREST RPC the Flutter client calls, with parameters.

Read-only source scan: finds `.rpc(` followed by an RPC name (on the same or the
next line) and, when the call spans lines, the `params: { ... }` keys.

Usage: python tool/extract_client_rpcs.py [--json]
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

RPC = re.compile(r"\.rpc\(\s*\n?\s*['\"]([a-z_0-9]+)['\"]")
PARAM = re.compile(r"['\"](p_[a-z_0-9]+)['\"]\s*:")


def main() -> int:
    calls: dict[str, dict] = {}
    for path in sorted(pathlib.Path("lib").rglob("*.dart")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in RPC.finditer(text):
            name = m.group(1)
            # params: { ... } window following the call
            window = text[m.end():m.end() + 900]
            if "params:" not in window.split(");", 1)[0]:
                params = []
            else:
                seg = window.split("params:", 1)[1]
                # cut at the end of the call's argument list
                depth, out, i = 0, [], 0
                while i < len(seg):
                    ch = seg[i]
                    if ch in "({[":
                        depth += 1
                    elif ch in ")}]":
                        if depth == 0:
                            break
                        depth -= 1
                    out.append(ch)
                    i += 1
                params = sorted(set(PARAM.findall("".join(out))))
            entry = calls.setdefault(name, {"params": set(), "files": set()})
            entry["params"].update(params)
            entry["files"].add(str(path).replace("\\", "/").split("lib/")[-1])

    out = {n: {"params": sorted(v["params"]), "files": sorted(v["files"])}
           for n, v in sorted(calls.items())}
    if "--json" in sys.argv:
        print(json.dumps(out, indent=2))
    else:
        for n, v in out.items():
            print(f"{n:34s} {len(v['files'])}x  params={','.join(v['params']) or '-'}")
        print()
        print(f"distinct client RPCs: {len(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
