import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:otp/otp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_manager/models/user.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/services/permission_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _currentUserKey = 'current_username';
  static const String _currentSessionIdKey = 'current_session_id';
  static const String _deviceIdKey = 'device_id';
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const int _lockAfterAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 15);
  static const Duration _trustedDeviceDuration = Duration(days: 30);

  int get lockAfterAttempts => _lockAfterAttempts;

  Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_currentUserKey);
    if (username == null) return null;
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return null;
    return AppUser.fromMap(row);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt(_currentSessionIdKey);
    if (sessionId != null) {
      try {
        await DatabaseService().endUserSession(sessionId);
      } catch (_) {}
      try {
        await prefs.remove(_currentSessionIdKey);
      } catch (_) {}
    }
    await prefs.remove(_currentUserKey);
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = _generateSalt(length: 24);
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  String _trusted2faKey(String username, String deviceId) =>
      'trusted_2fa_${username}_$deviceId';

  Future<bool> isCurrentDeviceTrustedFor2FA(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await getOrCreateDeviceId();
    final raw = prefs.getString(_trusted2faKey(username, deviceId));
    if (raw == null || raw.trim().isEmpty) return false;
    final until = DateTime.tryParse(raw.trim());
    if (until == null) return false;
    if (until.isBefore(DateTime.now())) {
      try {
        await prefs.remove(_trusted2faKey(username, deviceId));
      } catch (_) {}
      return false;
    }
    return true;
  }

  Future<void> trustCurrentDeviceFor2FA(
    String username, {
    Duration duration = _trustedDeviceDuration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await getOrCreateDeviceId();
    final until = DateTime.now().add(duration).toIso8601String();
    await prefs.setString(_trusted2faKey(username, deviceId), until);
  }

  Future<void> untrustCurrentDeviceFor2FA(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await getOrCreateDeviceId();
    await prefs.remove(_trusted2faKey(username, deviceId));
  }

  String _generateSalt({int length = 16}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _generateTotpSecret({int length = 32}) {
    String fromOtpLib() => OTP.randomSecret();

    try {
      return fromOtpLib().trim();
    } catch (_) {
      // Fallback for platforms where OTP.randomSecret / Random.secure might fail.
    }

    Random r;
    try {
      r = Random.secure();
    } catch (_) {
      r = Random();
    }

    final chars = List.generate(
      length,
      (_) => _base32Alphabet[r.nextInt(_base32Alphabet.length)],
    );
    return chars.join();
  }

  String _normalizeTotpSecret(String secret) {
    return secret.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<AppUser> createOrUpdateUser({
    required String username,
    required String displayName,
    required String role,
    required String password,
    bool enable2FA = false,
    Set<String>? permissions,
    String? secret2FA, // Add this parameter
    String? staffId,
  }) async {
    final salt = _generateSalt();
    final passwordHash = _hashPassword(password, salt);
    final String? secret = enable2FA
        ? _normalizeTotpSecret(secret2FA ?? _generateTotpSecret())
        : null; // Use provided secret2FA or generate new

    final user = AppUser(
      username: username,
      displayName: displayName,
      role: role,
      passwordHash: passwordHash,
      salt: salt,
      isTwoFactorEnabled: enable2FA,
      totpSecret: secret,
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
      lastLoginAt: null,
      permissions: PermissionService.encodePermissions(
        permissions ?? PermissionService.defaultForRole(role),
      ),
      staffId: (staffId ?? '').trim().isEmpty ? null : staffId!.trim(),
    );

    await DatabaseService().upsertUser(user.toMap());
    return user;
  }

  Future<AppUser?> updateUser({
    required String username,
    String? displayName,
    String? role,
    String? newPassword,
    bool? enable2FA,
    Set<String>? permissions,
    String? staffId,
  }) async {
    final existing = await DatabaseService().getUserRowByUsername(username);
    if (existing == null) return null;

    final currentUser = AppUser.fromMap(existing);

    final bool next2FA = enable2FA ?? currentUser.isTwoFactorEnabled;
    String? nextSecret;
    if (next2FA) {
      nextSecret = _normalizeTotpSecret(
        currentUser.totpSecret ?? _generateTotpSecret(),
      );
    } else {
      nextSecret = null;
    }

    String nextSalt = currentUser.salt;
    String nextPasswordHash = currentUser.passwordHash;
    if (newPassword != null && newPassword.isNotEmpty) {
      nextSalt = _generateSalt();
      nextPasswordHash = _hashPassword(newPassword, nextSalt);
    }

    final updated = AppUser(
      username: currentUser.username,
      displayName: displayName ?? currentUser.displayName,
      role: role ?? currentUser.role,
      passwordHash: nextPasswordHash,
      salt: nextSalt,
      isTwoFactorEnabled: next2FA,
      totpSecret: nextSecret,
      isActive: currentUser.isActive,
      createdAt: currentUser.createdAt,
      lastLoginAt: currentUser.lastLoginAt,
      permissions: PermissionService.encodePermissions(
        permissions ??
            PermissionService.decodePermissions(
              currentUser.permissions,
              role: currentUser.role,
            ),
      ),
      staffId: staffId != null
          ? (staffId.trim().isEmpty ? null : staffId.trim())
          : currentUser.staffId,
    );

    await DatabaseService().upsertUser(updated.toMap());
    return updated;
  }

  Future<({bool ok, bool requires2FA})> authenticatePassword(
    String username,
    String password,
  ) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return (ok: false, requires2FA: false);
    if ((row['isActive'] as int? ?? 1) == 0)
      return (ok: false, requires2FA: false);
    final lockedUntil = row['lockedUntil']?.toString();
    if (lockedUntil != null && lockedUntil.trim().isNotEmpty) {
      final until = DateTime.tryParse(lockedUntil.trim());
      if (until != null && until.isAfter(DateTime.now())) {
        return (ok: false, requires2FA: false);
      }
    }
    final salt = row['salt'] as String;
    final expected = row['passwordHash'] as String;
    final provided = _hashPassword(password, salt);
    if (provided != expected) {
      try {
        await DatabaseService().recordFailedLoginAttempt(
          username: username,
          lockAfter: _lockAfterAttempts,
          lockDuration: _lockDuration,
        );
      } catch (_) {}
      return (ok: false, requires2FA: false);
    }
    try {
      await DatabaseService().resetFailedLoginAttempts(username);
    } catch (_) {}
    final requires2FA = (row['isTwoFactorEnabled'] as int? ?? 0) == 1;
    return (ok: true, requires2FA: requires2FA);
  }

  Future<bool> finalizeLogin(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, username);
    await DatabaseService().updateUserLastLoginAt(username);
    try {
      final sessionId = await DatabaseService().startUserSession(
        username: username,
      );
      await prefs.setInt(_currentSessionIdKey, sessionId);
    } catch (_) {}
    return true;
  }

  Future<void> touchCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt(_currentSessionIdKey);
    if (sessionId == null) return;
    try {
      await DatabaseService().touchUserSession(sessionId);
    } catch (_) {}
  }

  bool isTwoFactorRequired(Map<String, dynamic> userRow) {
    return (userRow['isTwoFactorEnabled'] as int? ?? 0) == 1;
  }

  Future<bool> verifyTotpCode(String username, String code) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return false;
    final secret = row['totpSecret'] as String?;
    if (secret == null || secret.isEmpty) return false;
    final normalizedSecret = _normalizeTotpSecret(secret);
    final trimmed = code.replaceAll(' ', '');
    // The OTP package expects current time in milliseconds
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    for (int offset = -2; offset <= 2; offset++) {
      try {
        final generated = OTP.generateTOTPCodeString(
          normalizedSecret,
          nowMillis + (offset * 30000), // +/- 30s windows
          interval: 30,
          length: 6,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
        if (generated == trimmed) return true;
      } catch (_) {
        // ignore and continue
      }
    }
    return false;
  }

  Future<String?> getTotpProvisioningUri(
    String username, {
    String issuer = 'EcoleManager',
  }) async {
    final row = await DatabaseService().getUserRowByUsername(username);
    if (row == null) return null;
    final secret = row['totpSecret'] as String?;
    if (secret == null) return null;
    final account = Uri.encodeComponent(username);
    final iss = Uri.encodeComponent(issuer);
    final s = Uri.encodeQueryComponent(_normalizeTotpSecret(secret));
    return 'otpauth://totp/$iss:$account?secret=$s&issuer=$iss&algorithm=SHA1&digits=6&period=30';
  }
}
