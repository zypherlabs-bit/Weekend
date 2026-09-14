import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricTypeKey = 'biometric_type';
  static const String _sessionTokenKey = 'session_token';
  static const String _referralCodeKey = 'referral_code';
  static const String _qrInvitePayloadKey = 'qr_invite_payload';
  static const String _deviceIdKey = 'device_id';
  static const String _encryptionKeyKey = 'encryption_key';
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
  }

  static Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  static Future<void> setBiometricType(String type) async {
    await _storage.write(key: _biometricTypeKey, value: type);
  }

  static Future<String?> getBiometricType() async {
    return await _storage.read(key: _biometricTypeKey);
  }

  static Future<void> setSessionToken(String token) async {
    await _storage.write(key: _sessionTokenKey, value: token);
  }

  static Future<String?> getSessionToken() async {
    return await _storage.read(key: _sessionTokenKey);
  }

  static Future<void> clearSessionToken() async {
    await _storage.delete(key: _sessionTokenKey);
  }

  static Future<void> setReferralCode(String code) async {
    await _storage.write(key: _referralCodeKey, value: code);
  }

  static Future<String?> getReferralCode() async {
    return await _storage.read(key: _referralCodeKey);
  }

  static Future<void> setQRInvitePayload(String payload) async {
    await _storage.write(key: _qrInvitePayloadKey, value: payload);
  }

  static Future<String?> getQRInvitePayload() async {
    return await _storage.read(key: _qrInvitePayloadKey);
  }

  static Future<void> setDeviceId(String deviceId) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  static Future<String?> getDeviceId() async {
    return await _storage.read(key: _deviceIdKey);
  }

  static Future<void> setEncryptionKey(String key) async {
    await _storage.write(key: _encryptionKeyKey, value: key);
  }

  static Future<String?> getEncryptionKey() async {
    return await _storage.read(key: _encryptionKeyKey);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  static Future<bool> containsKey(String key) async {
    return await _storage.containsKey(key: key);
  }
}
