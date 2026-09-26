import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import '../models/models.dart';

class QRInvitationService {
  static const String _invitePrefix = 'WEEKEND_INVITE';
  static const int _currentVersion = 1;
  static const int _expiryDays = 30;
  static final Random _random = Random.secure();
  static String _generateInviteId() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      16,
      (index) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  static String _generateSignature(String payload, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String _getSigningSecret() {
    return SupabaseConfig.anonKey;
  }

  static Future<QRInvitation> generateInvitation({
    required String referralCode,
    required String inviterId,
    required String inviterName,
  }) async {
    final inviteId = _generateInviteId();
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: _expiryDays));
    final payload =
        '$_invitePrefix|$inviteId|$referralCode|$inviterId|$inviterName|$_currentVersion|${now.millisecondsSinceEpoch}|${expiresAt.millisecondsSinceEpoch}';
    final signature = _generateSignature(payload, _getSigningSecret());
    return QRInvitation(
      inviteId: inviteId,
      referralCode: referralCode,
      inviterId: inviterId,
      inviterName: inviterName,
      version: _currentVersion,
      createdAt: now,
      expiresAt: expiresAt,
      signature: signature,
    );
  }

  static QRInvitationResult validateInvitation(String payload) {
    final QRInvitation invitation;
    try {
      invitation = QRInvitation.fromPayload(payload);
    } on FormatException catch (e) {
      return QRInvitationResult.invalid('Invalid invitation format: $e');
    }
    if (invitation.version != _currentVersion) {
      return QRInvitationResult.invalid('Unsupported invitation version');
    }
    if (invitation.isExpired) {
      return QRInvitationResult.invalid('Invitation has expired');
    }
    final expectedPayload =
        '$_invitePrefix|${invitation.inviteId}|${invitation.referralCode}|${invitation.inviterId}|${invitation.inviterName}|${invitation.version}|${invitation.createdAt.millisecondsSinceEpoch}|${invitation.expiresAt.millisecondsSinceEpoch}';
    final expectedSignature = _generateSignature(
      expectedPayload,
      _getSigningSecret(),
    );
    if (invitation.signature != expectedSignature) {
      return QRInvitationResult.invalid('Invalid invitation signature');
    }
    return QRInvitationResult.valid(invitation);
  }

  /// Server-side confirmation that a scanned code is real and unredeemed.
  ///
  /// The inviter is resolved from `profiles.referral_code` via the
  /// `lookup_referral_inviter` RPC. The previous implementation queried
  /// `referrals`, which only holds one row per *redeemed* referral — so a
  /// freshly issued code always looked "not found" and no invitation could
  /// ever be redeemed.
  static Future<QRInvitationResult> validateInvitationServerSide(
    String payload,
  ) async {
    final client = SupabaseConfig.client;
    if (client == null) {
      return validateInvitation(payload);
    }
    final localResult = validateInvitation(payload);
    if (!localResult.isValid) {
      return localResult;
    }
    final invitation = localResult.invitation!;
    try {
      final inviterId = await client.rpc<String?>(
        'lookup_referral_inviter',
        params: {'p_referral_code': invitation.referralCode},
      );
      if (inviterId == null || inviterId.isEmpty) {
        return QRInvitationResult.invalid('Referral code not found');
      }
      // The code must belong to the inviter the QR payload claims. Without
      // this a validly signed payload could name one user and carry another
      // user's code.
      if (inviterId != invitation.inviterId) {
        return QRInvitationResult.invalid('Referral code does not match');
      }
      // Already credited to this account? A repeat scan is not an error.
      final existing = await client
          .from('referrals')
          .select('id, status')
          .eq('referrer_id', inviterId)
          .eq('referee_id', client.auth.currentUser?.id ?? '')
          .maybeSingle();
      if (existing != null && existing['status'] == 'successful') {
        return QRInvitationResult.invalid(
          'This referral has already been used',
        );
      }
      return QRInvitationResult.valid(invitation);
    } catch (e) {
      return QRInvitationResult.invalid('Server validation failed: $e');
    }
  }

  /// Credit a scanned referral. Returns `true` when the referral is on record.
  ///
  /// The RPC is `record_referral` (migration 017). It re-derives the inviter
  /// from the code and requires `p_referee_id = auth.uid()`, so the client
  /// cannot credit a referral to another account.
  static Future<bool> recordReferral({
    required String referralCode,
    required String refereeId,
    required String inviterId,
  }) async {
    final client = SupabaseConfig.client;
    if (client == null) return false;
    try {
      final result = await client.rpc(
        'record_referral',
        params: {
          'p_referral_code': referralCode,
          'p_referee_id': refereeId,
          'p_inviter_id': inviterId,
        },
      );
      return result == true;
    } catch (e) {
      debugPrint('Failed to record referral: $e');
      return false;
    }
  }

  static Future<bool> isSelfReferral(
    String referralCode,
    String currentUserId,
  ) async {
    final client = SupabaseConfig.client;
    if (client == null) return false;
    try {
      final response = await client
          .from('profiles')
          .select('referral_code')
          .eq('id', currentUserId)
          .maybeSingle();
      if (response == null) return false;
      return response['referral_code'] == referralCode;
    } catch (e) {
      return false;
    }
  }
}
