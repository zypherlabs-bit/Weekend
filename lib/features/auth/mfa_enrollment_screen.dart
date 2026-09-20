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

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _codeController.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final factors = await _repo.listFactors();
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

  Future<void> _disable() async {
    if (_existingFactorId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: const Text('Disable 2FA?', style: TextStyle(color: Colors.white)),
        content: const Text('Your account will be protected by password only.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disable', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() { _working = true; _error = null; });
    try {
      await _repo.unenrollFactor(_existingFactorId!);
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Could not disable 2FA: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
                else
                  OutlinedButton(
                    onPressed: _working ? null : _disable,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), minimumSize: const Size.fromHeight(52)),
                    child: const Text('Disable 2FA'),
                  ),
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
