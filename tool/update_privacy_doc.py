"""One-off: add the on-device security-check section to docs/privacy.md.

The file contains characters the Windows console mangles, so the edit is done
with a regex on the real bytes rather than a copy-pasted literal.
"""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATH = ROOT / "docs" / "privacy.md"

NEW_SECTION = """## 9. On-device security checks

Two protections run locally and add nothing to the list of collected data:

- **VPN-aware access control.** Weekend asks Android whether the active network
  (or any network Android reports) uses a VPN transport, and blocks private
  profiles, likes, matches and messages while one does. The check is local: no IP
  lookup, no third-party service, no VPN provider name and no network identifier
  is collected, stored, logged or sent to Supabase. It uses
  `ACCESS_NETWORK_STATE`, which the Supabase client already required, and adds no
  permission. See
  [vpn-and-screenshot-protection.md](vpn-and-screenshot-protection.md).
- **Screen-capture protection.** The Android activity that hosts the UI sets
  `FLAG_SECURE`, which keeps the app out of screenshots and the recent-apps
  thumbnail. It is a platform flag applied to the app's own window: it collects
  no data and does not inspect other apps.

Neither feature reads the clipboard, contacts, installed apps or usage history.

---

## 10. Related documents

"""


def main() -> int:
    text = PATH.read_text(encoding="utf-8")
    heading = "## 9. Related documents"
    index = text.index(heading)
    # Keep the docs list that followed the old heading, drop the old heading.
    remainder = text[index + len(heading):]
    remainder = remainder.lstrip("\n")
    remainder = remainder.lstrip("-" * 3)
    remainder = remainder.lstrip("\n")
    new_text = text[:index] + NEW_SECTION + remainder
    # Point the related-documents list at the new page.
    new_text = re.sub(
        r"- \[security\.md\]\(security\.md\)[^\n]*",
        "- [security.md](security.md) - how access is enforced\n"
        "- [vpn-and-screenshot-protection.md](vpn-and-screenshot-protection.md)"
        " - the two on-device protections, their states, limits and tests",
        new_text,
        count=1,
    )
    PATH.write_text(new_text, encoding="utf-8", newline="")
    print("privacy.md updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
