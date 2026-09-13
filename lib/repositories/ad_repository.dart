import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AdRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<(Advertisement?, AdConfig)> fetchAd(String userId) async {
    try {
      final response = await _client.functions.invoke(
        'serve-ad',
        body: {
          'action': 'fetch',
          'userId': userId,
        },
      );

      if (response.data == null) {
        return (null, const AdConfig());
      }

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> ads = data['ads'] as List<dynamic>? ?? [];

      Advertisement? ad;
      if (ads.isNotEmpty) {
        ad = Advertisement.fromJson(
          Map<String, dynamic>.from(ads.first as Map<String, dynamic>),
        );
      }

      final configData = data['adConfig'] as Map<String, dynamic>?;
      final config = configData != null
          ? AdConfig.fromJson(configData)
          : const AdConfig();

      return (ad, config);
    } catch (e) {
      return (null, const AdConfig());
    }
  }

  Future<void> recordEvent(
    String userId,
    String adId,
    String eventType, {
    Map<String, dynamic>? metadata,
  }) async {
    await _client.functions.invoke(
      'serve-ad',
      body: {
        'action': 'record_$eventType',
        'userId': userId,
        'adId': adId,
        'eventData': metadata,
      },
    );
  }

  Future<void> recordImpression(String userId, String adId) async {
    await recordEvent(userId, adId, 'impression');
  }

  Future<void> recordClick(String userId, String adId) async {
    await recordEvent(userId, adId, 'click');
  }

  Future<void> recordReport(String userId, String adId, {String? reason}) async {
    await recordEvent(userId, adId, 'report',
        metadata: reason != null ? {'reason': reason} : null);
  }

  Future<void> recordHide(String userId, String adId) async {
    await recordEvent(userId, adId, 'hide');
  }
}
