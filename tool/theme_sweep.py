"""Palette migration: replace hardcoded dark-theme literals with live theme
lookups so every screen follows Day / Night / Auto.

Colour replacement only.  `const` expressions that become invalid are repaired
afterwards by `tool/fix_invalid_const.py`, which uses the analyzer as its
oracle.  Run the analyzer between the two steps.

    python tool/theme_sweep.py
    flutter analyze > analyze.txt
    python tool/fix_invalid_const.py analyze.txt
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

FILES = [
    "lib/features/profile/edit_profile_screen.dart",
    "lib/features/profile/opening_moves_dialog.dart",
    "lib/features/profile/verification_dialog.dart",
    "lib/features/profile/visibility_dialog.dart",
    "lib/features/safety/safety_center_screen.dart",
    "lib/features/settings/privacy_modes_dialog.dart",
    "lib/features/settings/support_dialog.dart",
    "lib/features/qr/qr_invite_screen.dart",
    "lib/features/qr/about_open_source_screen.dart",
    "lib/features/discovery/location_settings_screen.dart",
    "lib/features/discovery/location_permission_screen.dart",
    "lib/features/auth/confirm_email_screen.dart",
    "lib/features/auth/mfa_enrollment_screen.dart",
    "lib/features/auth/security_setup_screen.dart",
    "lib/features/auth/mfa_challenge_screen.dart",
    "lib/features/auth/biometric_lock_gate.dart",
    "lib/features/likes/likes_screen.dart",
    "lib/widgets/safety_dialogs.dart",
    "lib/widgets/date_ideas_widget.dart",
    "lib/widgets/icebreaker_widget.dart",
    "lib/widgets/filter_controls.dart",
    "lib/widgets/location_radius_filter.dart",
    "lib/widgets/ad_card.dart",
]

# Ordered: longest / most specific first so a shorter key never eats a longer
# one (`Colors.white70` before `Colors.white`).
REPLACEMENTS = [
    ("const Color(0xFF130E20)", "Theme.of(context).scaffoldBackgroundColor"),
    ("const Color(0xFF13101C)", "Theme.of(context).scaffoldBackgroundColor"),
    ("const Color(0xFF0F0B16)", "Theme.of(context).scaffoldBackgroundColor"),
    ("const Color(0xFF0D0818)", "Theme.of(context).scaffoldBackgroundColor"),
    ("const Color(0xFF1C162E)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("const Color(0xFF1E1C24)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("const Color(0xFF23212B)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("const Color(0xFF241C2B)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("const Color(0xFF23201F)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("const Color(0xFF2E244A)", "Theme.of(context).colorScheme.surfaceContainerHighest"),
    ("const Color(0xFFFF4B72)", "Theme.of(context).colorScheme.primary"),
    ("const Color(0xFFFF9966)", "Theme.of(context).colorScheme.tertiary"),
    ("const Color(0xFF6FD08C)", "AppTheme.onlineGreen"),
    ("Color(0xFF4CAF50)", "AppTheme.onlineGreen"),
    ("Colors.white70", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white60", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white54", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white38", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white30", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white24", "Theme.of(context).colorScheme.onSurfaceVariant"),
    ("Colors.white12", "Theme.of(context).colorScheme.outlineVariant"),
    ("Colors.white10", "Theme.of(context).colorScheme.outlineVariant"),
    ("Colors.white", "Theme.of(context).colorScheme.onSurface"),
    # Bare forms that were never wrapped in `const`.
    ("Color(0xFF130E20)", "Theme.of(context).scaffoldBackgroundColor"),
    ("Color(0xFF1C162E)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("Color(0xFF1E1C24)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("Color(0xFF23212B)", "Theme.of(context).colorScheme.surfaceContainerHigh"),
    ("Color(0xFF2E244A)", "Theme.of(context).colorScheme.surfaceContainerHighest"),
    ("Color(0xFFFF4B72)", "Theme.of(context).colorScheme.primary"),
    ("Color(0xFFFF9966)", "Theme.of(context).colorScheme.tertiary"),
]


def main() -> int:
    changed = 0
    for rel in FILES:
        path = ROOT / rel
        if not path.exists():
            print(f"skip (missing): {rel}")
            continue
        original = path.read_text(encoding="utf-8")
        text = original
        for old, new in REPLACEMENTS:
            text = text.replace(old, new)
        if text != original:
            path.write_text(text, encoding="utf-8", newline="")
            changed += 1
            print(f"updated: {rel}")
    print(f"{changed} files changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
