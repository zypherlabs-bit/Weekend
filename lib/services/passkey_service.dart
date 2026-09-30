import 'package:credential_manager/credential_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../config/supabase_config.dart';

/// Result of one half of a WebAuthn ceremony.
///
/// There is deliberately no `success: true` reachable without a real credential
/// coming back from the platform: [credential] is produced only by
/// [CredentialManagerPlatform.savePasskeyCredentials] or
/// [CredentialManagerPlatform.getCredentials].
class PasskeyCeremonyResult {
  /// True only when the platform returned a credential.
  ///
  /// This flag alone is NOT authentication. Only a server-issued `Session`
  /// proves the account was actually verified.
  final bool success;

  /// The credential as returned by Android Credential Manager. Null on failure.
  final PublicKeyCredential? credential;

  /// User-facing wording safe to display.
  final String message;

  /// Diagnostic detail for logs and the in-app diagnostics panel.
  /// Contains no key material and is never shown verbatim to a user.
  final String? diagnostic;

  const PasskeyCeremonyResult._({
    required this.success,
    this.credential,
    required this.message,
    this.diagnostic,
  });

  factory PasskeyCeremonyResult.ok({
    required PublicKeyCredential credential,
    String message = 'Passkey verified on this device.',
  }) => PasskeyCeremonyResult._(
    success: true,
    credential: credential,
    message: message,
  );

  factory PasskeyCeremonyResult.failure(
    String message, {
    String? diagnostic,
  }) => PasskeyCeremonyResult._(
    success: false,
    message: message,
    diagnostic: diagnostic,
  );
}

/// Owns the Android Credential Manager side of Weekend's passkey support.
///
/// Why this exists
/// ---------------
/// `credential_manager` 5.x registers its platform implementation inside the
/// `CredentialManager()` CONSTRUCTOR (`registerWith()` is never called from a
/// static member). `CredentialManagerPlatform.instance` is therefore left
/// unset - reading it throws
/// `Assertion failed: CredentialManagerPlatform.instance has not been
/// initialized` - and every ceremony aborts before the Credential Manager
/// sheet is ever shown. That is the real "passkey does nothing" symptom, and
/// it is fixed by constructing the handle in [ensureInitialized] before any
/// `init` / `get` / `save` call.
class PasskeyService {
  PasskeyService._();

  static final PasskeyService instance = PasskeyService._();

  Future<bool>? _initFuture;
  bool _initialized = false;

  /// The plugin's high-level handle.
  ///
  /// Constructing it is what performs platform registration: the constructor
  /// calls `CredentialManagerAndroidPlugin.registerWith()`, which is the ONLY
  /// place `CredentialManagerPlatform.instance` is ever assigned.
  ///
  /// Calling the static-style `CredentialManagerPlatform.instance.init(...)`
  /// directly therefore throws
  /// `CredentialManagerPlatform.instance has not been initialized`, because
  /// nothing ever constructed a [CredentialManager]. That assertion was the
  /// real cause of "the passkey button does nothing": every ceremony aborted
  /// before the Credential Manager sheet was ever requested.
  CredentialManager? _manager;

  /// Whether [init] has completed successfully. Diagnostics only.
  bool get isInitialized => _initialized;

  /// Initialise the platform Credential Manager exactly once.
  ///
  /// Returns false on platforms where a passkey ceremony cannot run, and on a
  /// hard init failure - the caller must then surface an error rather than
  /// pretending the ceremony happened.
  Future<bool> ensureInitialized() => _initFuture ??= _init();

  Future<bool> _init() async {
    if (!isSupportedPlatform) return false;
    try {
      // Registration happens here and ONLY here. `_manager` is cached so the
      // ceremony calls below reuse the same registered instance.
      _manager ??= CredentialManager();
      // `preferImmediatelyAvailableCredentials: false` keeps the system sheet
      // on real user verification. Passing true allows a device with no screen
      // lock to satisfy the request, which is not user verification at all.
      // The Google client id is unused: Weekend uses neither Save nor Autofill.
      await _manager!.init(preferImmediatelyAvailableCredentials: false);
      _initialized = true;
      return true;
    } catch (e) {
      _initialized = false;
      debugPrint('CredentialManager init failed: $e');
      return false;
    }
  }

  /// Whether this platform can run a WebAuthn ceremony at all.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// The RP ID the backend uses, derived from the Supabase project URL.
  ///
  /// Supabase derives the WebAuthn relying-party ID from the project URL (or an
  /// explicit `webauthn_rp_id` in project settings). Surfacing it lets the app
  /// explain an asset-linkage failure precisely instead of showing a generic
  /// "no credential available".
  static String get expectedRpId {
    final uri = Uri.tryParse(SupabaseConfig.url);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host;
  }

  /// Build plugin creation options from GoTrue's
  /// `PublicKeyCredentialCreationOptionsJSON`.
  ///
  /// `userVerification` is forced to `required`. GoTrue asks for `preferred`,
  /// which permits a device with no enrolled biometric and no screen lock to
  /// satisfy the ceremony - weaker than the guarantee the signup screen
  /// promises, so Weekend does not accept the server default here.
  static CredentialCreationOptions creationOptionsFromJson(
    Map<String, dynamic> json,
  ) {
    final selection =
        Map<String, dynamic>.from(json['authenticatorSelection'] as Map? ?? const {});

    // Read the selection criteria from the RAW map rather than through
    // `CredentialCreationOptions.fromJson`. The plugin's
    // `AuthenticatorSelectionCriteria.fromJson` assigns absent keys straight
    // into non-nullable `String` fields, so it throws
    // `type 'Null' is not a subtype of type 'String'` on a real GoTrue payload -
    // which omits `authenticatorAttachment` and `requireResidentKey`.
    return CredentialCreationOptions(
      challenge: (json['challenge'] as String?) ?? '',
      rp: Rp(
        name: ((json['rp'] as Map?)?['name'] as String?) ?? 'Weekend',
        id: ((json['rp'] as Map?)?['id'] as String?) ?? expectedRpId,
      ),
      user: User(
        name: _userName(json),
        // Non-nullable in the plugin: an authenticator always needs something
        // to render, so fall back to the username GoTrue sends.
        displayName:
            (json['user'] as Map?)?['displayName'] as String? ??
                _userName(json),
        id: (json['user'] as Map?)?['id'] as String? ?? '',
      ),
      pubKeyCredParams: (json['pubKeyCredParams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => PublicKeyCredentialParameters(
              type: (m['type'] as String?) ?? 'public-key',
              alg: (m['alg'] as num?)?.toInt() ?? -7,
            ),
          )
          .toList(growable: false),
      timeout: (json['timeout'] as num?)?.toInt() ?? 180000,
      attestation: (json['attestation'] as String?) ?? 'none',
      excludeCredentials: (json['excludeCredentials'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => ExcludeCredential(
              id: (m['id'] as String?) ?? '',
              type: (m['type'] as String?) ?? 'public-key',
            ),
          )
          .toList(growable: false),
      authenticatorSelection: AuthenticatorSelectionCriteria(
        authenticatorAttachment: selection['authenticatorAttachment'] as String?,
        // A discoverable credential is what makes usernameless passkey sign-in
        // possible at all.
        requireResidentKey: true,
        residentKey: (selection['residentKey'] as String?) ?? 'required',
        // GoTrue asks for 'preferred'; see the class doc for why that is
        // rejected.
        userVerification: 'required',
      ),
    );
  }

  /// The `user.name` GoTrue sends, guaranteed non-empty.
  ///
  /// An authenticator refuses to create a credential with a blank user handle,
  /// and GoTrue only guarantees `user.name` for accounts that have one.
  static String _userName(Map<String, dynamic> json) {
    final name = (json['user'] as Map?)?['name'] as String?;
    if (name != null && name.trim().isNotEmpty) return name;
    final display = (json['user'] as Map?)?['displayName'] as String?;
    if (display != null && display.trim().isNotEmpty) return display;
    return 'Weekend member';
  }

  /// Build plugin login options from GoTrue's
  /// `PublicKeyCredentialRequestOptionsJSON`.
  ///
  /// GoTrue sends `rpId` in camelCase and may omit it entirely; an empty rpId
  /// makes Credential Manager throw a type error instead of a useful
  /// diagnostic, so [expectedRpId] is the fallback.
  static CredentialLoginOptions loginOptionsFromJson(
    Map<String, dynamic> json,
  ) {
    final rpId = (json['rpId'] as String?)?.trim();
    return CredentialLoginOptions(
      challenge: (json['challenge'] as String?)?.trim() ?? '',
      rpId: (rpId == null || rpId.isEmpty) ? expectedRpId : rpId,
      userVerification: 'required',
      timeout: (json['timeout'] as num?)?.toInt() ?? 180000,
    );
  }

  /// Serialise a platform credential into the W3C JSON GoTrue verifies.
  ///
  /// Load-bearing rather than cosmetic: the Android plugin returns a browser-
  /// shaped `{id, rawId, response: {...}}` object, and GoTrue reads the
  /// authenticator response fields from inside `response`. Getting this wrong
  /// makes verification fail with a signature error even though the ceremony
  /// itself succeeded.
  static Map<String, dynamic> credentialToJson(PublicKeyCredential credential) {
    final response = credential.response;
    return <String, dynamic>{
      'id': credential.id,
      'rawId': credential.rawId ?? credential.id,
      'type': credential.type ?? 'public-key',
      'authenticatorAttachment': credential.authenticatorAttachment,
      'response': <String, dynamic>{
        'clientDataJSON': response?.clientDataJSON,
        'attestationObject': response?.attestationObject,
        'authenticatorData': response?.authenticatorData,
        'signature': response?.signature,
        'userHandle': response?.userHandle,
      },
      'transports': response?.transports ?? credential.transports,
      'clientExtensionResults': credential.clientExtensionResults?.toJson(),
      if (credential.publicKey != null) 'publicKey': credential.publicKey,
      if (credential.publicKeyAlgorithm != null)
        'publicKeyAlgorithm': credential.publicKeyAlgorithm,
    };
  }

  /// Run the `create()` half of a registration ceremony.
  Future<PasskeyCeremonyResult> createCredential(
    Map<String, dynamic> options,
  ) async {
    if (!isSupportedPlatform) {
      return PasskeyCeremonyResult.failure(
        'Passkeys are not supported on this device.',
        diagnostic: 'unsupported_platform',
      );
    }
    if (!await ensureInitialized()) {
      return PasskeyCeremonyResult.failure(
        'Could not start Android Credential Manager on this device.',
        diagnostic: 'credential_manager_init_failed',
      );
    }
    try {
      final request = creationOptionsFromJson(options);
      // Routed through the cached [CredentialManager] so the registered platform
      // instance is the one used - see the note on [_manager].
      final credential = await _manager!.savePasskeyCredentials(
        request: request,
      );
      return PasskeyCeremonyResult.ok(
        credential: credential,
        message: 'Passkey created on this device.',
      );
    } on CredentialException catch (e) {
      return PasskeyCeremonyResult.failure(
        _messageForCode(e.code.toString()),
        diagnostic: 'credential_exception:${e.code}:${e.message}:${e.details}',
      );
    } on PlatformException catch (e) {
      return PasskeyCeremonyResult.failure(
        _messageForCode(int.tryParse(e.code)?.toString()),
        diagnostic: 'platform_exception:${e.code}:${e.message}',
      );
    } catch (e) {
      // Deliberately does NOT report success. An untyped failure here is what
      // an uninitialised Credential Manager looks like, and reporting it as a
      // successful passkey is exactly the fake authentication the security
      // requirements forbid.
      debugPrint('Passkey creation failed: $e');
      return PasskeyCeremonyResult.failure(
        'Passkey could not be created on this device.',
        diagnostic: 'untyped_error:${e.runtimeType}',
      );
    }
  }

  /// Run the `get()` half of an authentication ceremony.
  Future<PasskeyCeremonyResult> getCredential(
    Map<String, dynamic> options,
  ) async {
    if (!isSupportedPlatform) {
      return PasskeyCeremonyResult.failure(
        'Passkeys are not supported on this device.',
        diagnostic: 'unsupported_platform',
      );
    }
    if (!await ensureInitialized()) {
      return PasskeyCeremonyResult.failure(
        'Could not start Android Credential Manager on this device.',
        diagnostic: 'credential_manager_init_failed',
      );
    }
    try {
      final request = loginOptionsFromJson(options);
      final credentials = await _manager!.getCredentials(
        passKeyOption: request,
        // Passkey ONLY. The plugin's default is FetchOptionsAndroid.all(),
        // which also asks the system for saved passwords and Google IDs;
        // that downgrades the ceremony and can surface a password row
        // instead of the passkey the user is trying to use.
        fetchOptions: FetchOptionsAndroid(
          passKey: true,
          googleCredential: false,
          passwordCredential: false,
        ),
      );
      final publicKey = credentials.publicKeyCredential;
      if (publicKey == null) {
        // Android answers an empty Credentials() when nothing matched. That is
        // NOT a success and must never be treated as one.
        return PasskeyCeremonyResult.failure(
          'No passkey is set up on this device yet.',
          diagnostic: 'no_credential_returned',
        );
      }
      return PasskeyCeremonyResult.ok(
        credential: publicKey,
        message: 'Passkey assertion signed.',
      );
    } on CredentialException catch (e) {
      return PasskeyCeremonyResult.failure(
        _messageForCode(e.code.toString()),
        diagnostic: 'credential_exception:${e.code}:${e.message}:${e.details}',
      );
    } on PlatformException catch (e) {
      return PasskeyCeremonyResult.failure(
        _messageForCode(int.tryParse(e.code)?.toString()),
        diagnostic: 'platform_exception:${e.code}:${e.message}',
      );
    } catch (e) {
      debugPrint('Passkey assertion failed: $e');
      return PasskeyCeremonyResult.failure(
        'Passkey could not be verified on this device.',
        diagnostic: 'untyped_error:${e.runtimeType}',
      );
    }
  }

  /// Translate a Credential Manager error code into actionable wording.
  ///
  /// The code table is the plugin's documented one. Anything unrecognised is
  /// reported generically so a raw driver string never reaches the UI.
  static String _messageForCode(String? code) {
    switch (code) {
      case '201':
      case '601':
        return 'Passkey prompt cancelled.';
      case '602':
        return 'No passkey is set up on this device yet.';
      case '603':
        return 'Passkey could not be read from this device.';
      case '208':
        return 'This device cannot create passkeys. Android 13 or newer with '
            'Google Play services is required.';
      case '205':
        return 'Too many cancelled passkey prompts. Unlock your phone and '
            'try again in a moment.';
      case '401':
      case '402':
        return 'The device credential store could not be read. Unlock your '
            'phone once, then try again.';
      default:
        return 'Passkey could not be completed. Please try again.';
    }
  }
}
