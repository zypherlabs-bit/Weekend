import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../services/photo_url_service.dart';

/// Spotlight activation and Photo Insights, both backed by migration 031's
/// server RPCs. No fake counters: insights are only surfaced when the
/// server says a photo's impression sample is large enough to be
/// meaningful, and a Spotlight activation only reports the window the
/// server actually created.
class EngagementRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Activate a Spotlight window (4h, max 3 per rolling 30 days - both
  /// server-enforced). Returns the persisted status.
  ///
  /// The returned [SpotlightStatus] carries the reason string when the
  /// server did NOT activate it:
  /// `already_active`, `monthly_limit`, or `insufficient_privilege`
  /// (the account has no Spotlight entitlement - revocation case).
  Future<(SpotlightStatus, String reason)> activateSpotlight() async {
    final client = _client;
    if (client == null) {
      return (const SpotlightStatus(active: false), 'unavailable');
    }
    try {
      final result = await client.rpc('activate_spotlight');
      final map = Map<String, dynamic>.from(result as Map);
      if (map['activated'] == true) {
        return (
          SpotlightStatus(
            active: true,
            endsAt: DateTime.tryParse(map['ends_at'] as String? ?? ''),
            activationsLast30Days: 0,
          ),
          ''
        );
      }
      final reason = map['reason'] as String? ?? 'unknown';
      // An already-active window still has a live state worth displaying.
      if (reason == 'already_active') {
        final end = DateTime.tryParse(map['ends_at'] as String? ?? '');
        return (SpotlightStatus(active: end != null, endsAt: end), reason);
      }
      return (const SpotlightStatus(active: false), reason);
    } catch (e) {
      final message = e.toString();
      if (message.contains('not available for this account')) {
        return (const SpotlightStatus(active: false), 'insufficient_privilege');
      }
      return (const SpotlightStatus(active: false), 'error');
    }
  }

  /// The user's own Spotlight status (their rows only, server-computed).
  Future<SpotlightStatus> getMySpotlight() async {
    final client = _client;
    if (client == null) return const SpotlightStatus(active: false);
    try {
      final result = await client.rpc('get_my_spotlight');
      return SpotlightStatus.fromJson(
          Map<String, dynamic>.from(result as Map));
    } catch (_) {
      return const SpotlightStatus(active: false);
    }
  }

  /// Photo insights for the signed-in user. Photos with too small a sample
  /// MUST be shown as "not enough data yet" (honesty rule), which the
  /// [PhotoInsightEntry.hasSufficientData] flag reflects - the UI never
  /// invents engagement numbers.
  Future<PhotoInsights?> getMyPhotoInsights() async {
    final client = _client;
    if (client == null) return null;
    try {
      final result = await client.rpc('get_my_photo_insights');
      return PhotoInsights.fromJson(
          Map<String, dynamic>.from(result as Map));
    } catch (_) {
      return null;
    }
  }
}

/// In-app customer support backed by the `support_tickets` table
/// (migration 033). A ticket only lights up in the UI after INSERT has
/// returned its row from the server - never before, so there is no way to
/// show a fabricated success.
class SupportRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Submit a ticket. `safety` and `scam` categories are automatically
  /// prioritised server-side (high priority). Returns the confirmed ticket
  /// or null when the server refused (rate limit, invalid content).
  Future<SupportTicket?> submitTicket({
    required String category,
    required String subject,
    required String details,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      final row = await client
          .from('support_tickets')
          .insert({
            'category': category,
            'subject': subject.trim(),
            'details': details.trim(),
          })
          .select()
          .single();
      return SupportTicket.fromJson(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  /// The caller's tickets (RLS: own rows only), newest first.
  Future<List<SupportTicket>> fetchMyTickets({int limit = 50}) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('support_tickets')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return ((rows as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

/// In-app manual photo verification, implemented against the already
/// deployed `photo-verification` Edge Function.
///
/// The flow:
///   1. upload the chosen selfie into the existing private
///      `profile-photos` bucket path `verification/<uid>/selfie-<ts>.jpg`;
///   2. invoke the function ({userId, photoUrl, storagePath}) with the
///      user's own JWT - the function enforces it can only verify the
///      CALLER;
///   3. report the verdict the function returns. The real state of truth is
///      `profiles.verification_status`, refreshed by [refreshStatus] - a
///      UI can never claim "verified" without the server having written
///      that state.
class VerificationRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  static const _bucket = 'profile-photos';

  /// The bucket's RLS policy files uploads under the signed-in user's id,
  /// so keep the verification selfies inside that first folder.
  String _storagePathForSelfie(String userId) =>
      '$userId/verification/selfie-${DateTime.now().millisecondsSinceEpoch}.jpg';

  /// Submit (pending → verified/rejected). Returns the function's verdict
  /// ('approved' | 'pending' | 'rejected') or an empty string when it
  /// could not run at all.
  Future<String> submitVerification(Uint8List selfieBytes) async {
    final client = _client;
    final me = SupabaseConfig.currentUserId;
    if (client == null || me.isEmpty || selfieBytes.isEmpty) return '';

    final path = _storagePathForSelfie(me);

    try {
      await client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            selfieBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } catch (e) {
      // An upload failure must not fall through to a "verification sent"
      // message: report it as a failure.
      return '';
    }

    final resolved = await PhotoUrlService.resolve([path]);
    final photoUrl = resolved[path] ?? '';

    try {
      final response = await client.functions.invoke(
        'photo-verification',
        body: {'userId': me, 'photoUrl': photoUrl, 'storagePath': path},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final String? status = data['status'] as String?;
      switch (status) {
        case 'approved':
          return 'approved';
        case 'rejected':
          return 'rejected';
        default:
          return 'pending';
      }
    } catch (_) {
      return '';
    }
  }

  /// Read the authoritative verification state for the caller:
  /// `unverified` | `pending` | `verified` | `rejected` | '' (unknown).
  Future<String> refreshStatus() async {
    final client = _client;
    final me = SupabaseConfig.currentUserId;
    if (client == null || me.isEmpty) return '';
    try {
      final row = await client
          .from('profiles')
          .select('verification_status')
          .eq('id', me)
          .maybeSingle();
      final dynamic rowDyn = row;
      final rowMap = rowDyn == null ? null : Map<String, dynamic>.from(rowDyn as Map);
      return rowMap?['verification_status'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }
}

/// Opening Moves: per-user conversation-start prompts, up to 3, backed by
/// the `opening_moves` table (migration 032). CRUD is RLS-own-row; the
/// database validates slot bounds, prompt length and photo ownership.
class OpeningMoveRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  Future<List<OpeningMove>> fetchMine() async {
    final client = _client;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('opening_moves')
          .select()
          .order('sort_order', ascending: true);
      return ((rows as List?) ?? const [])
          .whereType<Map>()
          .map((e) => OpeningMove.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> upsertAll(List<OpeningMove> moves) async {
    final client = _client;
    if (client == null) return false;
    try {
      for (final move in moves) {
        if (move.prompt.trim().isEmpty) {
          // A blank prompt deletes the slot's stored prompt (user cleared it).
          if (move.id.isNotEmpty) {
            await client
                .from('opening_moves')
                .delete()
                .eq('id', move.id)
                .eq('user_id', SupabaseConfig.currentUserId);
          }
          continue;
        }
        await client.from('opening_moves').upsert({
          if (move.id.isNotEmpty) 'id': move.id,
          'sort_order': move.sortOrder,
          'prompt': move.prompt.trim(),
          if (move.photoId.isNotEmpty) 'photo_id': move.photoId,
        }, onConflict: 'user_id, sort_order');
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
