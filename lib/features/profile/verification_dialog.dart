import 'package:flutter/material.dart';

import '../../config/supabase_config.dart';
import '../../repositories/engagement_repository.dart';
import '../../services/image_optimizer.dart';

/// Manual photo verification against the deployed `photo-verification` Edge
/// Function: the user picks a selfie, it is uploaded into the private
/// `profile-photos` bucket under `$userId/verification/` and the function's
/// verdict is reported. All of it server-run — the UI cannot claim verified
/// unless the function (or the refreshed profile row) says so.
class VerificationDialog extends StatefulWidget {
  const VerificationDialog({super.key});

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  final VerificationRepository _repository = VerificationRepository();

  bool _busy = false;
  String _serverStatus = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _repository.refreshStatus();
    if (!mounted) return;
    setState(() => _serverStatus = status);
  }

  Future<void> _submitSelfie() async {
    if (_busy) return;
    final me = SupabaseConfig.currentUserId;
    if (me.isEmpty) {
      _message('You are not signed in.', isError: true);
      return;
    }
    final file = await ImageOptimizer.pickAndOptimizeImage();
    if (file == null) {
      if (mounted && ImageOptimizer.lastError != null) {
        _message(ImageOptimizer.lastError!, isError: true);
      }
      return;
    }
    setState(() => _busy = true);
    final verdict = await _repository.submitVerification(await file.readAsBytes());
    if (!mounted) return;
    setState(() => _busy = false);
    // The authoritative state is re-read either way.
    await _loadStatus();
    switch (verdict) {
      case 'approved':
        _message('Verified! Your profile now carries the verified badge.');
        break;
      case 'pending':
        _message(
          'Selfie received — verification is pending a moderator / model '
          'review on the server.',
        );
        break;
      case 'rejected':
        _message(
          'The photo was rejected. Use a clear selfie showing your face '
          'without others.',
          isError: true,
        );
        break;
      default:
        _message(
          'Verification could not run right now. Check your connection and '
          'try again.',
          isError: true,
        );
        break;
    }
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF4CAF50),
      ),
    );
  }

  String _statusLabel() {
    switch (_serverStatus) {
      case 'verified':
        return 'Your profile is verified.';
      case 'pending':
        return 'Verification is pending on the server.';
      case 'rejected':
        return 'The last submission was rejected — you can try again below.';
      default:
        return 'Your profile is not verified yet.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _serverStatus == 'verified';
    return Dialog(
      backgroundColor: const Color(0xFF1C162E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Photo Verification',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              _statusLabel(),
              style: TextStyle(
                color: verified ? const Color(0xFF4CAF50) : Colors.white70,
                fontSize: 13,
              ),
            ),
            if (!verified) ...[
              const SizedBox(height: 8),
              const Text(
                'Take (or pick) a clear selfie of your face. It is compared '
                'with your profile photos on the server and is not shown to '
                'anyone.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: verified ? null : _submitSelfie,
                      child: Text(
                        verified ? 'Verified' : 'Submit verification selfie',
                        style: TextStyle(
                          color: verified
                              ? Colors.white38
                              : const Color(0xFFFF9966),
                        ),
                      ),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
