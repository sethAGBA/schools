import 'dart:convert';

import 'package:school_manager/services/api/api_client.dart';
import 'package:school_manager/services/api/token_storage_service.dart';

class RemoteAuthResult {
  const RemoteAuthResult({
    required this.ok,
    this.error,
    this.username,
    this.role,
  });

  final bool ok;
  final String? error;
  final String? username;
  final String? role;
}

class RemoteAuthService {
  RemoteAuthService._();
  static final RemoteAuthService instance = RemoteAuthService._();

  Future<RemoteAuthResult> login({
    required String email,
    required String password,
    required String tenantId,
  }) async {
    await TokenStorageService.instance.saveSession(
      accessToken: '',
      refreshToken: '',
      tenantId: tenantId,
    );

    final response = await ApiClient.instance.post(
      '/api/auth/login',
      withAuth: false,
      body: <String, dynamic>{
        'email': email,
        'password': password,
      },
    );

    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return RemoteAuthResult(ok: false, error: decoded['error']?.toString());
      } catch (_) {
        return const RemoteAuthResult(ok: false, error: 'Login API échoué.');
      }
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = decoded['accessToken']?.toString() ?? '';
    final refreshToken = decoded['refreshToken']?.toString() ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      return const RemoteAuthResult(
        ok: false,
        error: 'Réponse API invalide (tokens manquants).',
      );
    }

    await TokenStorageService.instance.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tenantId: tenantId,
    );

    final claims = _decodeJwtPayload(accessToken);
    final username = (claims['email']?.toString() ?? email).trim();
    final role = _extractRole(claims);
    return RemoteAuthResult(ok: true, username: username, role: role);
  }

  Future<void> logout() async {
    final refreshToken = await TokenStorageService.instance.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await ApiClient.instance.post(
        '/api/auth/logout',
        body: <String, dynamic>{'refreshToken': refreshToken},
      );
    }
    await TokenStorageService.instance.clearSession();
  }

  Map<String, dynamic> _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return <String, dynamic>{};
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map<String, dynamic>) return map;
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _extractRole(Map<String, dynamic> claims) {
    final roleClaim =
        claims['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
        claims['role'];
    final raw = roleClaim?.toString().trim().toLowerCase() ?? '';
    if (raw == 'superadmin' || raw == 'admin') return 'admin';
    if (raw == 'teacher' || raw == 'prof') return 'teacher';
    if (raw == 'staff') return 'staff';
    return 'staff';
  }
}
