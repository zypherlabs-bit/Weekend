import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

/// The official Weekend source repository.
///
/// This is the single constant every open-source surface in the app reads
/// (QR code, share sheet, About row, README link). It is declared once so
/// the QR payload can never drift from the documented destination, and the
/// Python verification suite asserts it against this exact string.
const String kWeekendRepositoryUrl =
    'https://github.com/zypherlabs-bit/Weekend';

/// "Open Source" sheet: shows a QR code that resolves to the official
/// Weekend repository and offers the same link as a tappable URL.
///
/// The QR encodes nothing but the public repository URL — no user id, no
/// referral code, no session token. The referral invite QR lives on its own
/// screen (`/qr-invite`) and is a separate, signed payload.
class AboutOpenSourceScreen extends StatelessWidget {
  const AboutOpenSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Open Source')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Semantics(
                label: 'QR code linking to the Weekend GitHub repository',
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    // Always white regardless of theme: a QR code needs a
                    // high-contrast light quiet zone to scan reliably.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    // The exact repository URL, not a placeholder.
                    data: kWeekendRepositoryUrl,
                    version: QrVersions.auto,
                    // High error correction so the code still scans with a
                    // logo overlay or a slightly dirty camera lens.
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF130E20),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF130E20),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Weekend is open source',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the code or tap the link to read the source, '
              'contribute, or report an issue.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            // The URL is also selectable so it can be verified or copied
            // without scanning.
            SelectableText(
              kWeekendRepositoryUrl,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            _ActionButton(
              label: 'Open repository',
              icon: Icons.open_in_new_rounded,
              filled: true,
              onTap: () => _open(context),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Copy link',
              icon: Icons.copy_rounded,
              onTap: () => _copy(context),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Share Weekend',
              icon: Icons.ios_share_rounded,
              onTap: () => _share(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(kWeekendRepositoryUrl);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open a browser. Copy the link instead.'),
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: kWeekendRepositoryUrl));
    messenger.showSnackBar(
      const SnackBar(content: Text('Repository link copied')),
    );
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Share.share(
        'Weekend - Make Every Weekend Brighter.\n'
        'Open source dating & discovery: $kWeekendRepositoryUrl',
        subject: 'Weekend on GitHub',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet.')),
      );
    }
  }
}

/// Consistent 50dp-tall action button used across the sheet.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.sunsetCoral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
    );
  }
}
