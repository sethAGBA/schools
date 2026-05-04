import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:school_manager/config/api_config.dart';
import 'package:school_manager/services/api/token_storage_service.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  Future<void> Function()? onUnauthorized;
  Future<bool>? _ongoingRefresh;
  bool _unauthorizedNotified = false;
  static const Duration _requestTimeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<Map<String, String>> _buildHeaders({bool withAuth = true}) async {
    final tenantId =
        await TokenStorageService.instance.getTenantId() ?? ApiConfig.defaultTenantId;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Tenant-Id': tenantId,
    };

    if (withAuth) {
      final token = await TokenStorageService.instance.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<http.Response> get(String path, {bool withAuth = true}) async {
    return _sendWithRefreshRetry(
      path: path,
      withAuth: withAuth,
      sender: (headers) => http.get(_uri(path), headers: headers),
    );
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    final encoded = jsonEncode(body ?? <String, dynamic>{});
    return _sendWithRefreshRetry(
      path: path,
      withAuth: withAuth,
      sender: (headers) => http.post(_uri(path), headers: headers, body: encoded),
    );
  }

  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
  }) async {
    final encoded = jsonEncode(body ?? <String, dynamic>{});
    return _sendWithRefreshRetry(
      path: path,
      withAuth: withAuth,
      sender: (headers) => http.put(_uri(path), headers: headers, body: encoded),
    );
  }

  Future<http.Response> delete(String path, {bool withAuth = true}) async {
    return _sendWithRefreshRetry(
      path: path,
      withAuth: withAuth,
      sender: (headers) => http.delete(_uri(path), headers: headers),
    );
  }

  Future<http.Response> _sendWithRefreshRetry({
    required String path,
    required bool withAuth,
    required Future<http.Response> Function(Map<String, String> headers) sender,
  }) async {
    final firstHeaders = await _buildHeaders(withAuth: withAuth);
    var response = await _safeRequest(() => sender(firstHeaders));
    if (response.statusCode != 401) {
      _unauthorizedNotified = false;
    }

    if (!withAuth || response.statusCode != 401 || path == '/api/auth/refresh') {
      return response;
    }

    final refreshed = await _refreshAccessTokenSingleFlight();
    if (!refreshed) {
      await _notifyUnauthorized();
      return response;
    }

    final retryHeaders = await _buildHeaders(withAuth: withAuth);
    response = await _safeRequest(() => sender(retryHeaders));
    if (response.statusCode != 401) {
      _unauthorizedNotified = false;
    }
    if (response.statusCode == 401) {
      await _notifyUnauthorized();
    }
    return response;
  }

  Future<bool> _refreshAccessTokenSingleFlight() async {
    final inFlight = _ongoingRefresh;
    if (inFlight != null) {
      return inFlight;
    }
    final refreshFuture = _refreshAccessToken();
    _ongoingRefresh = refreshFuture;
    try {
      return await refreshFuture;
    } finally {
      if (identical(_ongoingRefresh, refreshFuture)) {
        _ongoingRefresh = null;
      }
    }
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await TokenStorageService.instance.getRefreshToken();
    final tenantId = await TokenStorageService.instance.getTenantId();
    if (refreshToken == null ||
        refreshToken.isEmpty ||
        tenantId == null ||
        tenantId.isEmpty) {
      return false;
    }

    final response = await _safeRequest(
      () => http.post(
        _uri('/api/auth/refresh'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-Tenant-Id': tenantId,
        },
        body: jsonEncode(<String, dynamic>{'refreshToken': refreshToken}),
      ),
    );

    if (response.statusCode != 200) {
      return false;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccessToken = decoded['accessToken']?.toString() ?? '';
      final newRefreshToken = decoded['refreshToken']?.toString() ?? '';
      if (newAccessToken.isEmpty || newRefreshToken.isEmpty) {
        return false;
      }
      await TokenStorageService.instance.saveSession(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
        tenantId: tenantId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notifyUnauthorized() async {
    if (_unauthorizedNotified) return;
    _unauthorizedNotified = true;
    final callback = onUnauthorized;
    if (callback == null) return;
    try {
      await callback();
    } catch (_) {}
  }

  Future<http.Response> _safeRequest(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_requestTimeout);
    } on TimeoutException {
      return http.Response(
        jsonEncode(<String, dynamic>{'error': 'Délai de connexion dépassé.'}),
        503,
        headers: <String, String>{'content-type': 'application/json'},
      );
    } on SocketException {
      return http.Response(
        jsonEncode(<String, dynamic>{'error': 'Réseau indisponible.'}),
        503,
        headers: <String, String>{'content-type': 'application/json'},
      );
    } catch (_) {
      return http.Response(
        jsonEncode(<String, dynamic>{'error': 'Erreur réseau inattendue.'}),
        503,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
  }
}
