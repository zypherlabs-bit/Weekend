import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../repositories/auth_repository.dart';

/// Settings -> Security -> Two-Factor Authentication (Supabase MFA TOTP).
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({super.key});
  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _repo = AuthRepository();
  final _codeController = TextEditingController();
  bool _loading = true;
  bool _mfaEnabled = false;
  String? _existingFactorId;
  MfaEnrollment? _pending;
  String? _error;
  bool _verifying = false;
  bool _working = false;
  int _attempts = 0;
  DateTime? _cooldownUntil;
  bool _showSecret = false;
  /// Recovery codes generated during this screen visit, shown exactly once.
  /// Empty means "not generated right now" - the plaintext is never persisted,
  /// so it genuinely cannot be shown again after the user leaves.
  List<MfaRecoveryCode> _recoveryCodes = const [];

  /// Unused recovery codes the server still holds. A count, never the codes.
  int _recoveryCount = 0;

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _codeController.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final factors = await _repo.listFactors();
      // Never derive "2FA is on" from a failed lookup: an exception below leaves
      // the previous state untouched, so a transient error cannot offer a
      // disable button for a factor that is still required.
      _recoveryCount = await _repo.recoveryCodeCount();
      setState(() {
        _mfaEnabled = factors.verifiedTotp.isNotEmpty;
        _existingFactorId = factors.verifiedTotp.isNotEmpty ? factors.verifiedTotp.first.id : null;
      });
    } catch (e) {
      setState(() => _error = 'Could not load 2FA status: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Generate a fresh recovery-code set.
  ///
  /// Regenerating destroys every previous code, so the user is warned first and
  /// told explicitly that only the newest set will work.
  Future<void> _generateRecoveryCodes() async {
    if (_working) return;
    if (_recoveryCount > 0) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1C162E),
          title: const Text('Replace recovery codes?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Your existing recovery codes will stop working immediately. '
            'Only the new set will unlock your account.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() { _working = true; _error = null; });
    try {
      final codes = await _repo.generateRecoveryCodes(count: 8);
      if (!mounted) return;
      if (codes.isEmpty) {
        setState(() =>
            _error = 'Recovery codes could not be generated. Please try again.');
        return;
      }
      setState(() {
        _recoveryCodes = codes;
        _recoveryCount = codes.length;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not generate recovery codes.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _begin() async {
    setState(() { _working = true; _error = null; });
    try {
      final enrollment = await _repo.enrollTotp();
      if (enrollment == null) {
        setState(() => _error = 'Sign-in required before enabling 2FA.');
      } else {
        setState(() { _pending = enrollment; _attempts = 0; });
      }
    } catch (e) {
      setState(() => _error = 'Could not start enrollment: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (_pending == null || code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }
    if (_cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!)) {
      final secs = _cooldownUntil!.difference(DateTime.now()).inSeconds;
      setState(() => _error = 'Too many attempts. Try again in ${secs}s.');
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      await _repo.verifyEnrollment(factorId: _pending!.factorId, code: code);
      if (!mounted) return;
      setState(() { _pending = null; _codeController.clear(); });
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Two-factor authentication enabled.')));
      }
    } catch (e) {
      _attempts++;
      DateTime? cooldown;
      if (_attempts >= 5) { cooldown = DateTime.now().add(const Duration(seconds: 60)); _attempts = 0; }
      final msg = e.toString().toLowerCase();
      String friendly = 'Verification failed. Enter the current code and try again.';
      if (msg.contains('expired')) { friendly = 'That code expired. Enter the current code.'; }
      else if (msg.contains('invalid') || msg.contains('incorrect')) { friendly = 'Incorrect code. Check your authenticator app.'; }
      setState(() { _cooldownUntil = cooldown; _error = friendly; });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Disable 2FA.
  ///
  /// Requires a live code from the authenticator FIRST. GoTrue also enforces an
  /// AAL2 session for unenrolling a verified factor, but relying on the server
  /// alone would leave an attacker with a stolen AAL1 session to discover the
  /// rule by trial. Asking for the code here makes the requirement explicit and
  /// gives the user a clear message either way.
  Future<void> _disable() async {
    final factorId = _existingFactorId;
    if (factorId == null) return;

    final code = await _promptForCode(
      title: 'Confirm it is you',
      reason: 'Enter the current code from your authenticator app to turn '
          'off two-factor authentication.',
    );
    if (code == null || !mounted) return;

    setState(() { _working = true; _error = null; });
    try {
      await _repo.stepUpToAal2(factorId: factorId, code: code);
      await _repo.unenrollFactor(factorId);
      // Recovery codes are meaningless once the factor is gone, and leaving
      // spendable codes behind would be a silent re-entry path.
      await _repo.generateRecoveryCodes(count: 0);
      setState(() {
        _recoveryCodes = const [];
        _recoveryCount = 0;
      });
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Two-factor authentication disabled.'),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = _friendlyDisableError(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyDisableError(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('invalid') || text.contains('expired')) {
      return 'That code was not accepted. 2FA is still on.';
    }
    if (text.contains('insufficient_aal')) {
      return 'Your session could not be verified. Sign out, sign back in and '
          'try again.';
    }
    if (text.contains('401') || text.contains('403')) {
      return '2FA could not be disabled. Sign out, sign back in and try again.';
    }
    return 'Could not disable 2FA. Please try again.';
  }

  /// Ask for a 6-digit code. Returns null when the user cancels.
  Future<String?> _promptForCode({
    required String title,
    required String reason,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '......',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    final code = result;
    if (code == null || code.length != 6) return null;
    return code;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: const Text('Two-Factor Authentication')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                _statusCard(),
                const SizedBox(height: 16),
                if (_pending != null) ...[
                  _enrollCard(),
                  const SizedBox(height: 16),
                  _verifyCard(),
                ] else if (!_mfaEnabled)
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _working ? null : _begin,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4B72), foregroundColor: Colors.white),
                      child: _working
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Enable 2FA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                else ...[
                  OutlinedButton(
                    onPressed: _working ? null : _disable,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Disable 2FA'),
                  ),
                  const SizedBox(height: 24),
                  _recoverySection(),
                ],
              ],
            ),
    );
  }

  /// Recovery-code management.
  ///
  /// The plaintext set exists only in [_recoveryCodes] for as long as this
  /// screen stays open: it is never written to disk, never logged, and the
  /// server only keeps a salted hash. Leaving the screen therefore genuinely
  /// makes the codes unrecoverable, which is why the warning below is explicit.
  Widget _recoverySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recovery codes',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _recoveryCount == 0
                ? 'You have no recovery codes. If you lose your phone you will '
                    'need support to get back in.'
                : '$_recoveryCount unused recovery '
                    '${_recoveryCount == 1 ? 'code' : 'codes'} left.',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _working ? null : _generateRecoveryCodes,
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: Text(
                _recoveryCount == 0
                    ? 'Generate recovery codes'
                    : 'Replace recovery codes',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF9966),
                side: const BorderSide(color: Color(0xFFFF9966)),
              ),
            ),
          ),
          if (_recoveryCodes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in _recoveryCodes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: SelectableText(
                        c.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    'Save these somewhere safe now. They are shown once and '
                    'cannot be displayed again. Each code works only once.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: (_mfaEnabled ? Colors.green : Colors.orange).withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(_mfaEnabled ? Icons.verified_user_rounded : Icons.lock_rounded, color: _mfaEnabled ? Colors.green : Colors.orange),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Authenticator app (TOTP)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 2),
                Text('A code is required after your password when signing in.', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _enrollCard() {
    final pending = _pending!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Scan this QR code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: pending.totpUri.isNotEmpty
                  ? QrImageView(data: pending.totpUri, size: 180)
                  : const Text('QR unavailable - use the secret below.'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Text('Manual secret key:', style: TextStyle(color: Colors.white70, fontSize: 12))),
              TextButton(onPressed: () => setState(() => _showSecret = !_showSecret), child: Text(_showSecret ? 'Hide' : 'Show')),
            ],
          ),
          if (_showSecret && pending.secret.isNotEmpty)
            SelectableText(pending.secret, style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 8),
          const Text('Shown once. Never stored on this device.', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _verifyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('2. Verify your authenticator', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Semantics(
            label: 'Six digit verification code',
            textField: true,
            child: TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                hintText: '......',
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _verifying ? null : _verify,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4B72), foregroundColor: Colors.white),
              child: _verifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify and Enable'),
            ),
          ),
        ],
      ),
    );
  }
}
