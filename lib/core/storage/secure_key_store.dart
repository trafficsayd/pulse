import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over [FlutterSecureStorage] that pins the platform-specific
/// security options Pulse requires.
///
/// On iOS this maps to the system Keychain with `first_unlock_this_device`
/// accessibility (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
/// On Android it goes through the system keystore-backed
/// `EncryptedSharedPreferences`.
///
/// The key store must never write to plain `SharedPreferences` or the iOS
/// `UserDefaults` — symmetric pair keys live here only.
class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage();

  final FlutterSecureStorage _storage;

  static FlutterSecureStorage _defaultStorage() => const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  Future<void> writeString(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> readString(String key) => _storage.read(key: key);

  Future<void> writeJson(String key, Map<String, Object?> value) =>
      writeString(key, jsonEncode(value));

  Future<Map<String, Object?>?> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();
}

/// Singleton [SecureKeyStore] consumed by every controller that needs to
/// read or write at-rest data (connections, subscription tier, sneak-in
/// quota counters, etc).
///
/// Tests can override this with `ProviderScope(overrides: [...])` to swap
/// in an in-memory store without touching the controllers themselves.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);
