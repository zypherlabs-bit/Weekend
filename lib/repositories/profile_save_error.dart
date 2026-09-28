import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Classified failure modes for the profile-save path.
///
/// Every failure surfaces a stable, non-sensitive diagnostic **code** (logged
/// for debugging) plus a user-friendly **message** (shown in the UI). Raw
/// PostgREST/Storage text is never logged or displayed: database error details
/// can embed row data, and URLs/headers can embed tokens.
enum ProfileSaveFailure {
  /// The UPDATE matched no row and the INSERT recovery did not produce one:
  /// the `profiles` row genuinely is not there (orphaned auth user).
  noRow(
    'PROFILE_UPDATE_NO_ROW',
    'The server did not save your profile. Check your connection and try again.',
  ),

  /// RLS or a policy rejected the write (usually a stale session).
  rlsDenied(
    'PROFILE_UPDATE_RLS_DENIED',
    'Your profile could not be saved. Please sign out and sign back in, '
        'then try again.',
  ),

  /// CHECK / FOREIGN KEY / UNIQUE constraint rejected one of the values.
  constraint(
    'PROFILE_UPDATE_CONSTRAINT',
    'Your profile could not be saved because the server rejected one of the '
        'values. Please review your entries and try again.',
  ),

  /// The 014 social-media bio policy (RPC pre-check or DB trigger) rejected
  /// the bio content.
  validation(
    'PROFILE_UPDATE_VALIDATION',
    'Your bio contains a social media handle or link, which is not allowed. '
        'Please remove it and try again.',
  ),

  /// The write never reached the server (offline, DNS, timeout).
  network(
    'PROFILE_UPDATE_NETWORK',
    'Network error. Check your connection and try again.',
  ),

  /// No authenticated user, expired session, or invalid JWT.
  auth(
    'PROFILE_UPDATE_AUTH',
    'Your session has expired. Please sign out and sign back in, then try again.',
  ),

  /// The live database is behind the app (missing column/function).
  schema(
    'PROFILE_UPDATE_SCHEMA',
    'The app and the database are out of sync. Please update to the latest '
        'version and try again.',
  ),

  /// Anything else: still an honest failure, never a fake success.
  unknown(
    'PROFILE_UPDATE_UNKNOWN',
    'Your profile could not be saved. Check your connection and try again.',
  );

  const ProfileSaveFailure(this.code, this.userMessage);

  /// Stable identifier safe to log (no PII, no tokens).
  final String code;

  /// User-facing message; safe to display.
  final String userMessage;
}

/// A profile save (or a step of it) did not happen.
///
/// Thrown instead of reporting success when the database changed nothing, and
/// instead of raw SDK errors so the UI can show actionable text while the
/// diagnostic [code] is logged for debugging.
class ProfileSaveException implements Exception {
  const ProfileSaveException(this.failure, {this.stage});

  final ProfileSaveFailure failure;

  /// Which step failed (e.g. `profiles.update`, `bio.precheck`). Constant
  /// strings only — never user data.
  final String? stage;

  String get code => failure.code;
  String get message => failure.userMessage;

  @override
  String toString() =>
      'ProfileSaveException($code${stage == null ? '' : ' @$stage'})';

  /// Logs only the diagnostic code, stage and error type. Never the raw
  /// error message (it may contain row data) and never any credential.
  void log([String? extraType]) {
    debugPrint(
      '[$code]${stage == null ? '' : ' stage=$stage'} profile save failure'
      '${extraType == null ? '' : ' ($extraType)'}',
    );
  }
}

/// Maps an arbitrary SDK/backend error to a [ProfileSaveException].
///
/// Order matters: the 014 bio policy message is checked before generic
/// constraint codes (the trigger raises `P0001`, but older proxies have
/// surfaced it as `23514`-flavoured text), and network patterns are checked
/// before the unknown fallback because supabase_flutter surfaces transport
/// failures as plain `Exception`s without a code.
ProfileSaveException classifyProfileSaveError(Object error, {String? stage}) {
  if (error is ProfileSaveException) return error;

  final text = error.toString().toLowerCase();

  bool matches(Pattern p) => text.contains(p);

  // --- 1. Social-media bio policy (migration 014) -------------------------
  if (matches('social media') || matches('validate_profile_bio')) {
    return const ProfileSaveException(ProfileSaveFailure.validation);
  }

  // --- 2. Authentication / session ----------------------------------------
  if (error is AuthException) {
    return ProfileSaveException(ProfileSaveFailure.auth, stage: stage);
  }

  // --- 3. RLS / authorization --------------------------------------------
  if (error is PostgrestException) {
    final code = error.code ?? '';
    if (code == '42501' ||
        matches('row-level security') ||
        matches('pgrst101') ||
        matches('not authorized')) {
      return ProfileSaveException(ProfileSaveFailure.rlsDenied, stage: stage);
    }
    if (code == 'PGRST301' || code == '401' || code == '403') {
      return ProfileSaveException(ProfileSaveFailure.auth, stage: stage);
    }
    if (code.startsWith('23')) {
      return ProfileSaveException(ProfileSaveFailure.constraint, stage: stage);
    }
    if (code == '42703' || matches('does not exist')) {
      return ProfileSaveException(ProfileSaveFailure.schema, stage: stage);
    }
  }

  // --- 4. Network / transport ---------------------------------------------
  if (matches('socket') ||
      matches('timeout') ||
      matches('timed out') ||
      matches('connection') ||
      matches('failed host lookup') ||
      matches('network') ||
      matches('clientexception') ||
      matches('fetchrequestexception')) {
    return ProfileSaveException(ProfileSaveFailure.network, stage: stage);
  }

  // --- 5. Session wording on plain errors ---------------------------------
  if (matches('not signed in') || matches('session')) {
    return ProfileSaveException(ProfileSaveFailure.auth, stage: stage);
  }

  return ProfileSaveException(ProfileSaveFailure.unknown, stage: stage);
}
