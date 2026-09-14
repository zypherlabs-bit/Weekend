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
      final response = await client
          .from('referrals')
          .select('id, status, referrer_id, referral_code')
          .eq('referral_code', invitation.referralCode)
          .eq('referrer_id', invitation.inviterId)
          .maybeSingle();
      if (response == null) {
        return QRInvitationResult.invalid('Referral code not found');
      }
      final status = response['status'] as String?;
      if (status == 'successful') {
        return QRInvitationResult.invalid(
          'This referral has already been used',
        );
      }
      return QRInvitationResult.valid(invitation);
    } catch (e) {
      return QRInvitationResult.invalid('Server validation failed: $e');
    }
  }

  static Future<bool> recordReferral({
    required String referralCode,
    required String refereeId,
    required String inviterId,
  }) async {
    final client = SupabaseConfig.client;
    if (client == null) return false;
    try {
      await client.rpc(
        'record_referral',
        params: {
          'p_referral_code': referralCode,
          'p_referee_id': refereeId,
          'p_inviter_id': inviterId,
        },
      );
      return true;
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
