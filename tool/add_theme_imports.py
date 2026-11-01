"""One-off: add the AppTheme import to files the palette sweep touched."""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

FILES = {
    "lib/features/discovery/location_settings_screen.dart": "../../theme/app_theme.dart",
    "lib/features/profile/edit_profile_screen.dart": "../../theme/app_theme.dart",
    "lib/features/profile/opening_moves_dialog.dart": "../../theme/app_theme.dart",
    "lib/features/profile/verification_dialog.dart": "../../theme/app_theme.dart",
    "lib/features/qr/qr_invite_screen.dart": "../../theme/app_theme.dart",
    "lib/features/safety/safety_center_screen.dart": "../../theme/app_theme.dart",
    "lib/features/settings/privacy_modes_dialog.dart": "../../theme/app_theme.dart",
    "lib/features/settings/support_dialog.dart": "../../theme/app_theme.dart",
    "lib/widgets/icebreaker_widget.dart": "../theme/app_theme.dart",
    "lib/widgets/safety_dialogs.dart": "../theme/app_theme.dart",
}


def main() -> int:
    for rel, target in FILES.items():
        path = ROOT / rel
        lines = path.read_text(encoding="utf-8").split("\n")
        if any("theme/app_theme.dart" in line for line in lines[:60]):
            print(f"skip (has import): {rel}")
            continue
        last = 0
        for i, line in enumerate(lines[:60]):
            if line.startswith("import "):
                last = i
        lines.insert(last + 1, "import '" + target + "';")
        path.write_text("\n".join(lines), encoding="utf-8", newline="")
        print(f"added import: {rel}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
