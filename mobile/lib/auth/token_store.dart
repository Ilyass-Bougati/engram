import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the refresh token is kept between launches.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The OS keystore: the Keychain on iOS, Keystore-backed encryption on Android. The token
/// stays on this device: it is left out of iCloud and Android backups.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const _key = 'engram_refresh_token';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Keeps the token in memory only. For tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}
