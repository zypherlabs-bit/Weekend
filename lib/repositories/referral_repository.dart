import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class ReferralRepository {
  ReferralData _data = const ReferralData(code: 'WEEKEND-MX07');
  
  ReferralData get referralData => _data;

  Future<ReferralData> fetchReferralData(String userId) async {
    try {
      final referral = await Supabase.instance.client
          .from('referrals')
          .select()
          .eq('referrer_id', userId)
          .maybeSingle();
      
      if (referral != null) {
        final count = await Supabase.instance.client
            .from('referrals')
            .select()
            .eq('referrer_id', userId);
        
        _data = ReferralData(
          code: referral['referral_code'] ?? 'WEEKEND-MX07',
          invitedCount: (count as List).length,
          verifiedCount: (count as List).where((r) => r['status'] == 'successful').length,
        );
      }
    } catch (e) {
      // ignore
    }
    
    return _data;
  }

  Future<void> createReferral(String referrerId, String refereeId, String code) async {
    await Supabase.instance.client.from('referrals').insert({
      'referrer_id': referrerId,
      'referee_id': refereeId,
      'referral_code': code,
      'status': 'pending',
    });
  }
}
