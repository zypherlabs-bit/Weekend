import '../config/supabase_config.dart';

/// Resolves private-bucket photo storage paths into short-lived signed URLs.
///
/// The `profile-photos` bucket is private; raw storage paths cannot be turned
/// into usable URLs client-side. This service asks the `get-photo-urls` Edge
/// Function (which enforces that only approved photos - or the caller's own -
/// are signed) and caches the results for the session. Signed URLs live one
/// hour server-side; the cache intentionally matches that lifetime.
class PhotoUrlService {
  PhotoUrlService._();

  static final Map<String, String> _cache = {};
  static final Map<String, Future<void>> _inflight = {};

  /// Resolve [paths] to signed URLs. Missing/unauthorized paths are simply
  /// absent from the result.
  static Future<Map<String, String>> resolve(Iterable<String> paths) async {
    final client = SupabaseConfig.client;
    if (client == null) return const {};

    final wanted = paths.where((p) => p.isNotEmpty).toSet();
    if (wanted.isEmpty) return const {};

    final missing =
        wanted.where((p) => !_cache.containsKey(p)).toList(growable: false);

    if (missing.isNotEmpty) {
      // Coalesce concurrent requests for the same missing paths.
      final key = missing.join('\n');
      _inflight.putIfAbsent(key, () => _fetch(missing));
      await _inflight[key]!;
      _inflight.remove(key);
    }

    return {
      for (final p in wanted)
        if (_cache.containsKey(p)) p: _cache[p]!,
    };
  }

  /// Resolve a single path, or `null` when it cannot be signed.
  static Future<String?> resolveOne(String path) async {
    final map = await resolve([path]);
    return map[path];
  }

  static Future<void> _fetch(List<String> paths) async {
    final client = SupabaseConfig.client;
    if (client == null) return;
    try {
      final response = await client.functions.invoke(
        'get-photo-urls',
        body: {'paths': paths},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final urls = data['urls'];
        if (urls is Map) {
          urls.forEach((k, v) {
            if (k is String && v is String && v.isNotEmpty) {
              _cache[k] = v;
            }
          });
        }
      }
    } catch (_) {
      // Network/authorization failures leave paths unresolved; callers
      // render their placeholder instead of a broken image.
    }
  }
}