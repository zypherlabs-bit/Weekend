import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/qr_invitation_service.dart';
import '../../services/secure_storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../models/models.dart';
import '../auth/auth_screen.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});
  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  MobileScannerController? _controller;
  bool _isScanning = true;
  bool _hasPermission = false;
  String? _errorMessage;
  bool _isProcessing = false;
  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasPermission = status == PermissionStatus.granted;
      if (!_hasPermission) {
        _errorMessage = 'Camera permission is required to scan QR codes';
      }
    });
    if (_hasPermission) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_isScanning || _isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;
    setState(() {
      _isScanning = false;
      _isProcessing = true;
    });
    try {
      final result = await QRInvitationService.validateInvitationServerSide(
        rawValue,
      );
      if (!mounted) return;
      if (!result.isValid) {
        _showInvalidQRDialog(result.errorMessage ?? 'Invalid QR code');
        return;
      }
      final invitation = result.invitation!;
      setState(() {
        _isProcessing = false;
      });
      _showInvitationDialog(invitation);
    } catch (e) {
      if (!mounted) return;
      _showInvalidQRDialog('Failed to process QR code: $e');
    }
  }

  void _showInvalidQRDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.error_rounded,
                color: Colors.red,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Invalid QR Code',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeScanning();
            },
            child: const Text(
              'Try Again',
              style: TextStyle(color: Color(0xFFFF4B72)),
            ),
          ),
        ],
      ),
    );
  }

  void _showInvitationDialog(QRInvitation invitation) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C162E),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF4CAF50),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Valid Invitation',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invited by ${invitation.inviterName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Referral Code: ${invitation.referralCode}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This invitation will be attached to your account when you sign up.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeScanning();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _processInvitation(invitation);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4B72),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processInvitation(QRInvitation invitation) async {
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      final currentUserId = authState.user?.id ?? '';
      if (currentUserId == invitation.inviterId) {
        _showErrorSnackBar('You cannot use your own invitation');
        _resumeScanning();
        return;
      }
      final success = await QRInvitationService.recordReferral(
        referralCode: invitation.referralCode,
        refereeId: currentUserId,
        inviterId: invitation.inviterId,
      );
      if (success) {
        _showSuccessSnackBar('Referral recorded successfully!');
      } else {
        _showErrorSnackBar(
          'Failed to record referral. It may have already been used.',
        );
      }
      _resumeScanning();
    } else {
      await SecureStorageService.setQRInvitePayload(invitation.toPayload());
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  void _resumeScanning() {
    setState(() {
      _isScanning = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (_hasPermission && _controller != null)
            MobileScanner(controller: _controller!, onDetect: _onDetect)
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4B72), Color(0xFFFF9966)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF4B72).withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF4B72),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (!_hasPermission)
                    TextButton(
                      onPressed: _requestCameraPermission,
                      child: const Text(
                        'Grant Camera Permission',
                        style: TextStyle(color: Color(0xFFFF4B72)),
                      ),
                    ),
                ],
              ),
            ),
          if (_hasPermission)
            Positioned.fill(
              child: CustomPaint(painter: _ScannerOverlayPainter()),
            ),
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C162E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_rounded,
                    size: 32,
                    color: Color(0xFFFF4B72),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Position the QR code within the frame',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only Weekend invitation QR codes will be accepted',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B72)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final scanAreaSize = size.width * 0.75;
    final scanAreaRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );
    final path = Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(scanAreaRect, const Radius.circular(20)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
    final borderPaint = Paint()
      ..color = const Color(0xFFFF4B72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final cornerLength = 40.0;
    final rrect = RRect.fromRectAndRadius(
      scanAreaRect,
      const Radius.circular(20),
    );
    final corners = [
      Offset(rrect.left, rrect.top),
      Offset(rrect.right, rrect.top),
      Offset(rrect.left, rrect.bottom),
      Offset(rrect.right, rrect.bottom),
    ];
    for (final corner in corners) {
      final isTopLeft = corner == Offset(rrect.left, rrect.top);
      final isTopRight = corner == Offset(rrect.right, rrect.top);
      final isBottomLeft = corner == Offset(rrect.left, rrect.bottom);
      final isBottomRight = corner == Offset(rrect.right, rrect.bottom);
      if (isTopLeft) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx + 10, corner.dy)
            ..lineTo(corner.dx + cornerLength, corner.dy)
            ..moveTo(corner.dx, corner.dy + 10)
            ..lineTo(corner.dx, corner.dy + cornerLength),
          borderPaint,
        );
      } else if (isTopRight) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx - cornerLength, corner.dy)
            ..lineTo(corner.dx - 10, corner.dy)
            ..moveTo(corner.dx, corner.dy + 10)
            ..lineTo(corner.dx, corner.dy + cornerLength),
          borderPaint,
        );
      } else if (isBottomLeft) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx + 10, corner.dy)
            ..lineTo(corner.dx + cornerLength, corner.dy)
            ..moveTo(corner.dx, corner.dy - cornerLength)
            ..lineTo(corner.dx, corner.dy - 10),
          borderPaint,
        );
      } else if (isBottomRight) {
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx - cornerLength, corner.dy)
            ..lineTo(corner.dx - 10, corner.dy)
            ..moveTo(corner.dx, corner.dy - cornerLength)
            ..lineTo(corner.dx, corner.dy - 10),
          borderPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
