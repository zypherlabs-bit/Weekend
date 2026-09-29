// Tests for the Edit Profile save flow: payload construction, orphan
// recovery, ownership, and error classification.
//
// The unit-test environment has no Supabase client, so the save orchestration
// runs against an in-memory [ProfileStore] fake that reproduces the exact
// behaviours seen in production:
//   * a zero-row UPDATE (PostgREST `200 []`) for a missing profile row,
//   * a row that exists (normal path),
//   * RLS / constraint / network rejections,
//   * a concurrent-insert race (unique violation 23505).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:weekend/models/models.dart';
import 'package:weekend/repositories/profile_repository.dart';
import 'package:weekend/repositories/profile_save_error.dart';

/// In-memory stand-in for `public.profiles` scoped to one user.
class FakeProfileStore implements ProfileStore {
  FakeProfileStore({this.row});

  /// Current DB row for the user (null == orphaned auth user).
  Map<String, dynamic>? row;

  int updateCalls = 0;
  int fetchCalls = 0;
  int insertCalls = 0;
  Map<String, dynamic>? lastPayload;
  String? lastAuthId;

  Object? updateError;
  Object? fetchError;
  Object? insertError;

  /// One-shot insert failure; when set, the fake first creates the row (as a
  /// concurrent writer would) and then throws, to model a 23505 race.
  Object? insertErrorOnce;
  bool insertReturnsWrongId = false;

  @override
  Future<List<Map<String, dynamic>>> updateOwn(
    String authId,
    Map<String, dynamic> payload,
  ) async {
    updateCalls++;
    lastAuthId = authId;
    lastPayload = payload;
    if (updateError != null) throw updateError!;
    if (row == null) return []; // PostgREST zero-row UPDATE: 200 []
    return [
      {'id': authId},
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchOwn(String authId) async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    return row;
  }

  @override
  Future<Map<String, dynamic>> insertOwn(
    String authId,
    Map<String, dynamic> payload,
  ) async {
    insertCalls++;
    if (insertErrorOnce != null) {
      final e = insertErrorOnce!;
      insertErrorOnce = null;
      row = {...payload, 'id': authId}; // concurrent writer won the race
      throw e;
    }
    if (insertError != null) throw insertError!;
    final id = insertReturnsWrongId ? 'someone-elses-id' : authId;
    row = {...payload, 'id': id};
    return row!;
  }
}

UserProfile _profile({
  String id = 'auth-user-1',
  String name = 'Ada Lovelace',
  String gender = 'Woman',
  String intent = 'Dating & Weekend Plans',
  String bio = 'I enjoy music, travel, food and relaxed weekends.',
  List<ProfilePrompt> prompts = const [],
}) {
  return UserProfile(
    id: id,
    name: name,
    age: 30,
    gender: gender,
    photos: const [],
    city: 'London',
    bio: bio,
    occupation: 'Mathematician',
    education: 'BSc',
    relationshipIntent: intent,
    favoriteMusic: 'Jazz',
    idealWeekend: 'Hiking',
    prompts: prompts,
  );
}

void main() {
  group('buildProfilePayload', () {
    test('trims text fields and writes only editable columns', () {
      final payload = buildProfilePayload(_profile(name: '  Ada  '));
      expect(payload['display_name'], 'Ada');
      expect(payload['bio'], 'I enjoy music, travel, food and relaxed weekends.');
      expect(payload['city'], 'London');
      expect(payload['gender'], 'Woman');
      expect(payload['relationship_intent'], 'Dating & Weekend Plans');
      expect(payload['occupation'], 'Mathematician');
      expect(payload['education'], 'BSc');
      expect(payload['favorite_music'], 'Jazz');
      expect(payload['ideal_weekend'], 'Hiking');
      // Ownership: the id must never travel in the payload.
      expect(payload.containsKey('id'), isFalse);
      // No privileged columns (verification/trust/completion/photos).
      expect(
        payload.keys.toSet(),
        {
          'display_name',
          'bio',
          'city',
          'gender',
          'relationship_intent',
          'occupation',
          'education',
          'favorite_music',
          'ideal_weekend',
          // Prompt answers, as the jsonb array the `profile_prompts_shape`
          // CHECK constraint validates. Present even when empty so clearing
          // the last answer actually clears the column server-side.
          'prompts',
        },
      );
    });

    test('encodes prompt answers and drops blank ones', () {
      final payload = buildProfilePayload(
        _profile(
          prompts: const [
            ProfilePrompt(
              id: 'simple_pleasures',
              prompt: 'My simple pleasures',
              answer: 'Long walks and bad coffee.',
            ),
            // Blank answer: must not reach the database at all, or the card
            // renders an empty question box.
            ProfilePrompt(
              id: 'hidden_talent',
              prompt: 'My hidden talent',
              answer: '   ',
            ),
          ],
        ),
      );
      final prompts = payload['prompts'] as List;
      expect(prompts, hasLength(1));
      expect((prompts.first as Map)['id'], 'simple_pleasures');
      expect((prompts.first as Map)['answer'], 'Long walks and bad coffee.');
    });

    test('omits lifestyle columns whose value is outside the CHECK set', () {
      final payload = buildProfilePayload(
        _profile().copyWith(
          smoking: 'Vaporises clouds',
          drinking: 'Socially',
        ),
      );
      // Invalid -> omitted entirely, so the constraint can never be violated
      // and good stored data survives.
      expect(payload.containsKey('smoking'), isFalse);
      // Valid -> written.
      expect(payload['drinking'], 'Socially');
    });

    test('omits CHECK-constrained columns when the value is not allowed', () {
      final payload = buildProfilePayload(
        _profile(gender: '', intent: 'New people & Friendsships'),
      );
      // Empty/legacy-typo values are omitted, never written as NULL and never
      // sent as a value the CHECK would reject.
      expect(payload.containsKey('gender'), isFalse);
      expect(payload.containsKey('relationship_intent'), isFalse);
    });
  });

  group('saveProfileWithRecovery', () {
    const authId = 'auth-user-1';

    test('existing row: UPDATE path, no INSERT', () async {
      final store = FakeProfileStore(row: {'id': authId});
      final rows = await saveProfileWithRecovery(
        store: store,
        authId: authId,
        payload: {'display_name': 'Ada'},
      );
      expect(rows, 1);
      expect(store.updateCalls, 1);
      expect(store.insertCalls, 0);
      expect(store.lastAuthId, authId, reason: 'id always from the session');
    });

    test('missing row (the reported bug): INSERT recovery succeeds', () async {
      final store = FakeProfileStore(); // orphan: no profiles row
      final rows = await saveProfileWithRecovery(
        store: store,
        authId: authId,
        payload: {'display_name': 'Ada'},
      );
      expect(rows, 1, reason: 'save must recover, not report "no row saved"');
      expect(store.insertCalls, 1);
      expect(store.row?['id'], authId, reason: 'row filed under own id only');
      expect(store.row?['display_name'], 'Ada');
    });

    test('insert returns another id: rejected, never accepted', () async {
      final store = FakeProfileStore()..insertReturnsWrongId = true;
      await expectLater(
        saveProfileWithRecovery(
          store: store,
          authId: authId,
          payload: {'display_name': 'Ada'},
        ),
        throwsA(
          isA<ProfileSaveException>().having(
            (e) => e.code,
            'code',
            'PROFILE_UPDATE_NO_ROW',
          ),
        ),
      );
    });

    test('concurrent insert race (23505): retries UPDATE once, succeeds',
        () async {
      final store = FakeProfileStore()
        ..insertErrorOnce = const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        );
      final rows = await saveProfileWithRecovery(
        store: store,
        authId: authId,
        payload: {'display_name': 'Ada'},
      );
      expect(rows, 1);
      expect(store.updateCalls, 2, reason: 'initial UPDATE + post-race retry');
    });

    test('update matched nothing but row exists: honest no-row failure',
        () async {
      // Not silently retried or faked: the caller sees a classified error.
      final store = _NoRowUpdateStore(row: {'id': authId});
      await expectLater(
        saveProfileWithRecovery(
          store: store,
          authId: authId,
          payload: {'display_name': 'Ada'},
        ),
        throwsA(
          isA<ProfileSaveException>().having(
            (e) => e.code,
            'code',
            'PROFILE_UPDATE_NO_ROW',
          ),
        ),
      );
    });

    test('RLS rejection on UPDATE is classified, not swallowed', () async {
      final store = FakeProfileStore(row: {'id': authId})
        ..updateError = const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        );
      await expectLater(
        saveProfileWithRecovery(
          store: store,
          authId: authId,
          payload: {'display_name': 'Ada'},
        ),
        throwsA(
          isA<ProfileSaveException>().having(
            (e) => e.code,
            'code',
            'PROFILE_UPDATE_RLS_DENIED',
          ),
        ),
      );
    });

    test('network failure is classified as network', () async {
      final store = FakeProfileStore(row: {'id': authId})
        ..updateError = const SocketExceptionLike('connection timed out');
      await expectLater(
        saveProfileWithRecovery(
          store: store,
          authId: authId,
          payload: {'display_name': 'Ada'},
        ),
        throwsA(
          isA<ProfileSaveException>().having(
            (e) => e.code,
            'code',
            'PROFILE_UPDATE_NETWORK',
          ),
        ),
      );
    });
  });

  group('classifyProfileSaveError', () {
    ProfileSaveFailure classify(Object e) =>
        classifyProfileSaveError(e).failure;

    test('014 bio trigger message -> validation', () {
      expect(
        classify(
          const PostgrestException(
            message:
                'Profile bio contains external social media identifiers or links.',
            code: 'P0001',
          ),
        ),
        ProfileSaveFailure.validation,
      );
      expect(
        classify(
          const PostgrestException(
            message: 'trigger validate_profile_bio rejected the row',
          ),
        ),
        ProfileSaveFailure.validation,
      );
    });

    test('SQLSTATE 23xxx -> constraint', () {
      expect(
        classify(
          const PostgrestException(
            message: 'violates check constraint "profiles_gender_check"',
            code: '23514',
          ),
        ),
        ProfileSaveFailure.constraint,
      );
      expect(
        classify(
          const PostgrestException(
            message: 'foreign key violation',
            code: '23503',
          ),
        ),
        ProfileSaveFailure.constraint,
      );
    });

    test('42501 / row-level security -> rlsDenied', () {
      expect(
        classify(
          const PostgrestException(message: 'permission denied', code: '42501'),
        ),
        ProfileSaveFailure.rlsDenied,
      );
    });

    test('expired JWT -> auth', () {
      expect(
        classify(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        ProfileSaveFailure.auth,
      );
      expect(
        classify(const AuthException('session expired')),
        ProfileSaveFailure.auth,
      );
    });

    test('missing column -> schema (app/database out of sync)', () {
      expect(
        classify(
          const PostgrestException(
            message: 'column "occupation" of relation "profiles" does not exist',
            code: '42703',
          ),
        ),
        ProfileSaveFailure.schema,
      );
    });

    test('transport errors -> network', () {
      expect(
        classify(Exception('ClientException with SocketException')),
        ProfileSaveFailure.network,
      );
      expect(
        classify(Exception('operation timed out')),
        ProfileSaveFailure.network,
      );
    });

    test('unrecognized -> unknown, never a fake success', () {
      expect(classify(Exception('weird')), ProfileSaveFailure.unknown);
    });

    test('already-classified errors pass through untouched', () {
      const original = ProfileSaveException(
        ProfileSaveFailure.noRow,
        stage: 'profiles.update',
      );
      expect(classifyProfileSaveError(original), same(original));
    });

    test('diagnostic codes are stable (log contract)', () {
      expect(ProfileSaveFailure.noRow.code, 'PROFILE_UPDATE_NO_ROW');
      expect(ProfileSaveFailure.rlsDenied.code, 'PROFILE_UPDATE_RLS_DENIED');
      expect(ProfileSaveFailure.constraint.code, 'PROFILE_UPDATE_CONSTRAINT');
      expect(ProfileSaveFailure.validation.code, 'PROFILE_UPDATE_VALIDATION');
      expect(ProfileSaveFailure.network.code, 'PROFILE_UPDATE_NETWORK');
      expect(ProfileSaveFailure.auth.code, 'PROFILE_UPDATE_AUTH');
      expect(ProfileSaveFailure.unknown.code, 'PROFILE_UPDATE_UNKNOWN');
    });

    test('user-facing message never echoes raw error text', () {
      final e = classifyProfileSaveError(
        const PostgrestException(
          message: 'sensitive internal detail with a token abc123',
          code: 'XX000',
        ),
      );
      expect(e.message.contains('abc123'), isFalse);
      expect(e.toString().contains('abc123'), isFalse);
    });
  });
}

/// Store where UPDATE always returns no rows while fetchOwn still finds the
/// row — the "zero rows but not actually missing" case that must fail
/// honestly instead of fabricating a success.
class _NoRowUpdateStore extends FakeProfileStore {
  _NoRowUpdateStore({super.row});

  @override
  Future<List<Map<String, dynamic>>> updateOwn(
    String authId,
    Map<String, dynamic> payload,
  ) async {
    updateCalls++;
    lastAuthId = authId;
    lastPayload = payload;
    return [];
  }
}

/// Stand-in for a transport-level error carrying network wording.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
