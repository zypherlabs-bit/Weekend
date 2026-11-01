"""One-off: normalise the Related-documents list at the end of docs/privacy.md."""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATH = ROOT / "docs" / "privacy.md"

TAIL = """## 10. Related documents

- [security.md](security.md) - how access is enforced
- [vpn-and-screenshot-protection.md](vpn-and-screenshot-protection.md) - the two
  on-device protections, their states, their limits and their tests
- [location-discovery.md](location-discovery.md) - discovery and geohashing design
- [qr-invitations.md](qr-invitations.md) - what an invitation payload contains
- [../README.md](../README.md) - feature overview and FAQ
"""


def main() -> int:
    text = PATH.read_text(encoding="utf-8")
    index = text.index("## 10. Related documents")
    PATH.write_text(text[:index] + TAIL, encoding="utf-8", newline="")
    print("privacy.md tail normalised")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
