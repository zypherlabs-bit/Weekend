import 'package:credential_manager/credential_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/services/passkey_service.dart';

/// Unit tests for the WebAuthn option shaping and credential serialisation.
///
/// These prove the DATA the app hands to Android Credential Manager and to
/// GoTrue is well-formed and correctly constrained. They do NOT prove a device
/// completes a ceremony: that needs real hardware and is reported separately as
/// NOT VERIFIED.
void main() {
  group('creation options', () {
    test('forces user verification to required', () {
      final options = PasskeyService.creationOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'rp': {'name': 'Weekend', 'id': 'example.supabase.co'},
        'user': {'name': 'ada@example.com', 'displayName': 'Ada'},
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
        ],
        'authenticatorSelection': {'userVerification': 'preferred'},
      });

      expect(
        options.authenticatorSelection.userVerification,
        'required',
        reason:
            'GoTrue asks for "preferred", which a device with no screen lock can '
            'satisfy; Weekend must not accept that weaker guarantee',
      );
    });

    test('requires a discoverable (resident) credential', () {
      final options = PasskeyService.creationOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'rp': {'name': 'Weekend', 'id': 'example.supabase.co'},
        'user': {'name': 'ada@example.com'},
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
        ],
      });
      expect(options.authenticatorSelection.requireResidentKey, isTrue);
      expect(options.authenticatorSelection.residentKey, 'required');
    });

    test('passes the challenge and RP through unchanged', () {
      final options = PasskeyService.creationOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'rp': {'name': 'Weekend', 'id': 'example.supabase.co'},
        'user': {'name': 'ada@example.com'},
        'pubKeyCredParams': [
          {'type': 'public-key', 'alg': -7},
        ],
      });
      expect(options.challenge, 'Y2hhbGxlbmdl');
      expect(options.rp.id, 'example.supabase.co');
    });
  });

  group('login options', () {
    test('forces user verification to required', () {
      final options = PasskeyService.loginOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'rpId': 'example.supabase.co',
        'userVerification': 'preferred',
      });
      expect(options.userVerification, 'required');
      expect(options.rpId, 'example.supabase.co');
    });

    test('falls back to the project host when rpId is absent', () {
      // An empty rpId makes Credential Manager throw a type error instead of a
      // useful diagnostic, so the fallback matters.
      //
      // `String.fromEnvironment` yields '' under `flutter test`, so the derived
      // host is empty here too; what matters is that the fallback is USED
      // rather than the raw missing value being passed through.
      final options = PasskeyService.loginOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'userVerification': 'preferred',
      });
      expect(options.rpId, PasskeyService.expectedRpId);
    });

    test('falls back when rpId is blank', () {
      final options = PasskeyService.loginOptionsFromJson({
        'challenge': 'Y2hhbGxlbmdl',
        'rpId': '   ',
      });
      expect(options.rpId, PasskeyService.expectedRpId);
    });
  });

  group('credential serialisation', () {
    PublicKeyCredential build() => PublicKeyCredential.fromJson({
      'id': 'Y3JlZGVudGlhbA',
      'rawId': 'Y3JlZGVudGlhbA',
      'type': 'public-key',
      'response': {
        'clientDataJSON': 'Y2xpZW50',
        'authenticatorData': 'YXV0aA',
        'signature': 'c2ln',
        'userHandle': 'dXNlcg',
      },
    });

    test('places authenticator fields inside response', () {
      // Load-bearing: GoTrue reads the authenticator response from inside
      // `response`. Sending a flat browser shape fails signature verification
      // even when the ceremony itself succeeded.
      final json = PasskeyService.credentialToJson(build());
      final response = json['response'] as Map<String, dynamic>;
      expect(response['clientDataJSON'], 'Y2xpZW50');
      expect(response['authenticatorData'], 'YXV0aA');
      expect(response['signature'], 'c2ln');
      expect(response['userHandle'], 'dXNlcg');
      expect(json['rawId'], 'Y3JlZGVudGlhbA');
      expect(json['type'], 'public-key');
    });

    test('falls back to id when rawId is absent', () {
      final credential = PublicKeyCredential.fromJson({
        'id': 'abc',
        'type': 'public-key',
        'response': {'clientDataJSON': 'x'},
      });
      expect(PasskeyService.credentialToJson(credential)['rawId'], 'abc');
    });

    test('carries the attestation object for registration', () {
      final credential = PublicKeyCredential.fromJson({
        'id': 'abc',
        'type': 'public-key',
        'response': {
          'clientDataJSON': 'x',
          'attestationObject': 'YXR0',
        },
      });
      final response = PasskeyService.credentialToJson(credential)['response']
          as Map<String, dynamic>;
      expect(response['attestationObject'], 'YXR0');
    });
  });

  group('diagnostics', () {
    test('platform support describes the platform, not the device', () {
      // `flutter test` reports TargetPlatform.android, so this is true. That is
      // the correct answer: it states "a ceremony could be attempted here". It
      // is NOT a claim that a passkey is enrolled or that a device was used.
      expect(
        PasskeyService.isSupportedPlatform,
        isA<bool>(),
        reason: 'isSupportedPlatform must always answer, never throw',
      );
    });

    test('expectedRpId is empty without a Supabase URL', () {
      // String.fromEnvironment yields '' in tests, so the helper must not throw
      // or invent a host.
      expect(PasskeyService.expectedRpId, '');
    });
  });
}
