import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

class ApiService {
  ApiService({String? baseUrl})
    : baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl());
  final String baseUrl;
  final _storage = const FlutterSecureStorage();
  static const requestTimeout = Duration(seconds: 12);

  static String _defaultBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kReleaseMode) {
      throw StateError(
        'API_BASE_URL es obligatorio en builds de producción. '
        'Usa --dart-define=API_BASE_URL=https://api.tudominio.com',
      );
    }
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'URL de API inválida');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw ArgumentError('La API debe usar HTTPS en producción');
    }
    return normalized;
  }

  String? mediaUrl(dynamic path) {
    if (path == null || path.toString().isEmpty) return null;
    final value = path.toString();
    return value.startsWith('http') ? value : '$baseUrl$value';
  }

  Future<String?> get token => _storage.read(key: 'token');
  Future<String?> get role => _storage.read(key: 'role');

  Future<Map<String, String>> _headers() async {
    final value = await token;
    return {
      'Content-Type': 'application/json',
      if (value != null) 'Authorization': 'Bearer $value',
    };
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body =
          response.body.isEmpty
              ? null
              : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        'El servidor devolvió una respuesta no válida',
        response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiException(
        detail is List
            ? detail
                .map((item) => item is Map ? item['msg'] : item)
                .where((item) => item != null)
                .join('\n')
            : (detail?.toString() ?? 'Ocurrió un error'),
        response.statusCode,
      );
    }
    return body;
  }

  Future<void> register(
    String email,
    String password,
    String selectedRole,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'role': selectedRole,
          }),
        )
        .timeout(requestTimeout);
    final body = _decode(response) as Map<String, dynamic>;
    await _storage.write(key: 'token', value: body['access_token'] as String);
    await _storage.write(key: 'role', value: selectedRole);
  }

  Future<void> login(String identifier, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        )
        .timeout(requestTimeout);
    final body = _decode(response) as Map<String, dynamic>;
    await _storage.write(key: 'token', value: body['access_token'] as String);
    try {
      final me = await get('/api/users/me') as Map<String, dynamic>;
      await _storage.write(key: 'role', value: me['role'] as String);
    } catch (_) {
      await _storage.delete(key: 'token');
      await _storage.delete(key: 'role');
      rethrow;
    }
  }

  Future<String> googleAuth(
    String idToken, {
    required bool createAccount,
    String? selectedRole,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id_token': idToken,
            'create_account': createAccount,
            if (selectedRole != null) 'role': selectedRole,
          }),
        )
        .timeout(requestTimeout);
    final body = _decode(response) as Map<String, dynamic>;
    await _storage.write(key: 'token', value: body['access_token'] as String);
    try {
      final me = await get('/api/users/me') as Map<String, dynamic>;
      final signedInRole = me['role'] as String;
      await _storage.write(key: 'role', value: signedInRole);
      return signedInRole;
    } catch (_) {
      await _storage.delete(key: 'token');
      await _storage.delete(key: 'role');
      rethrow;
    }
  }

  Future<void> logout() => _storage.deleteAll();

  Future<String?> requestPasswordReset(String email) async {
    final body =
        await post('/api/auth/password-reset/request', {'email': email})
            as Map<String, dynamic>;
    return body['dev_code'] as String?;
  }

  Future<void> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    await post('/api/auth/password-reset/confirm', {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
  }

  Future<dynamic> get(String path, {Duration? timeout}) async => _decode(
    await http
        .get(Uri.parse('$baseUrl$path'), headers: await _headers())
        .timeout(timeout ?? requestTimeout),
  );
  Future<dynamic> post(String path, Map<String, dynamic> data) async => _decode(
    await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(data),
        )
        .timeout(requestTimeout),
  );
  Future<dynamic> put(String path, Map<String, dynamic> data) async => _decode(
    await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(data),
        )
        .timeout(requestTimeout),
  );

  Future<void> uploadMedia(File file, String type, int position) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '$baseUrl/api/musicians/me/media?media_type=$type&position=$position',
      ),
    );
    final value = await token;
    request.headers['Authorization'] = 'Bearer $value';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await http.Response.fromStream(
      await request.send().timeout(requestTimeout),
    );
    _decode(response);
  }

  Future<void> uploadClientAvatar(File file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/clients/me/avatar'),
    );
    final value = await token;
    request.headers['Authorization'] = 'Bearer $value';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    _decode(
      await http.Response.fromStream(
        await request.send().timeout(requestTimeout),
      ),
    );
  }

  Future<void> setAvatarPreset(String preset, String color) async {
    await put('/api/users/me/avatar-preset', {
      'preset': preset,
      'color': color,
    });
  }
}
