"""One-off: let the shared `WeekendAtmosphere` (installed behind the navigator
in `main.dart`) show through the secondary screens.

Only the Scaffold / AppBar backgrounds are made transparent.  Colours used as
*paint* (QR plates, lock-screen barriers) are deliberately left opaque.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

SCAFFOLD_LITERAL = "backgroundColor: Theme.of(context).scaffoldBackgroundColor,"
LOCAL_LITERAL = "backgroundColor: theme.scaffoldBackgroundColor,"

REPLACE_ALL = [
    "lib/features/safety/safety_center_screen.dart",
    "lib/features/profile/edit_profile_screen.dart",
    "lib/features/auth/mfa_enrollment_screen.dart",
    "lib/features/auth/mfa_challenge_screen.dart",
    "lib/features/auth/confirm_email_screen.dart",
    "lib/features/discovery/location_permission_screen.dart",
    "lib/features/discovery/explore_screen.dart",
    "lib/features/chat/chat_screen.dart",
    "lib/features/profile/profile_screen.dart",
]

# qr_invite_screen uses the token both as a Scaffold background and as the QR
# plate colour, so it is edited by hand.
PAIRED = ["lib/features/qr/qr_invite_screen.dart"]


def main() -> int:
    for rel in REPLACE_ALL:
        path = ROOT / rel
        text = path.read_text(encoding="utf-8")
        hits = text.count(SCAFFOLD_LITERAL) + text.count(LOCAL_LITERAL)
        if not hits:
            print(f"skip (no match): {rel}")
            continue
        text = text.replace(SCAFFOLD_LITERAL, "backgroundColor: Colors.transparent,")
        text = text.replace(LOCAL_LITERAL, "backgroundColor: Colors.transparent,")
        path.write_text(text, encoding="utf-8", newline="")
        print(f"transparent scaffold: {rel} ({hits})")

    for rel in PAIRED:
        path = ROOT / rel
        lines = path.read_text(encoding="utf-8").split("\n")
        for index in (144, 142):  # AppBar (1-based 145) then Scaffold (1-based 143)
            if SCAFFOLD_LITERAL in lines[index]:
                lines[index] = lines[index].replace(
                    SCAFFOLD_LITERAL, "backgroundColor: Colors.transparent,"
                )
                print(f"transparent: {rel}:{index + 1}")
        path.write_text("\n".join(lines), encoding="utf-8", newline="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
