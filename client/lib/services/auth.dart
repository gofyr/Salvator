import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert' as conv;

class ServerProfile {
  String id;
  String name;
  String baseUrl;
  String? username;
  String? clientKey;
  String? accessToken;
  String? refreshToken;

  ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.username,
    this.clientKey,
    this.accessToken,
    this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'username': username,
    'clientKey': clientKey,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  static ServerProfile fromJson(Map<String, dynamic> m) => ServerProfile(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    baseUrl: (m['baseUrl'] ?? '') as String,
    username: m['username'] as String?,
    clientKey: m['clientKey'] as String?,
    accessToken: m['accessToken'] as String?,
    refreshToken: m['refreshToken'] as String?,
  );
}

class AuthService extends ChangeNotifier {
  AuthService();

  static const _storage = FlutterSecureStorage();

  List<ServerProfile> _profiles = [];
  int? _activeIndex;

  List<ServerProfile> get profiles => List.unmodifiable(_profiles);
  ServerProfile? get active =>
      (_activeIndex != null &&
          _activeIndex! >= 0 &&
          _activeIndex! < _profiles.length)
      ? _profiles[_activeIndex!]
      : null;

  String? get baseUrl => active?.baseUrl;
  String? get clientKey => active?.clientKey;
  String? get accessToken => active?.accessToken;
  String? get refreshToken => active?.refreshToken;

  Future<void> load() async {
    final raw = await _storage.read(key: 'profiles');
    if (raw != null && raw.isNotEmpty) {
      final list = conv.jsonDecode(raw) as List<dynamic>;
      _profiles = list
          .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final ai = await _storage.read(key: 'activeIndex');
    if (ai != null) {
      _activeIndex = int.tryParse(ai);
    }
    notifyListeners();
  }

  bool get isLoggedIn =>
      (active?.accessToken != null && active?.refreshToken != null);

  Future<void> clear() async {
    await _storage.deleteAll();
    _profiles = [];
    _activeIndex = null;
    notifyListeners();
  }

  Future<void> deleteProfile(int index) async {
    if (index < 0 || index >= _profiles.length) return;
    _profiles.removeAt(index);
    if (_profiles.isEmpty) {
      _activeIndex = null;
    } else if (_activeIndex != null) {
      if (_activeIndex! >= _profiles.length) {
        _activeIndex = _profiles.length - 1;
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> saveBase(String baseUrl, {String? clientKey}) async {
    final idx = _profiles.indexWhere((p) => p.baseUrl == baseUrl);
    if (idx >= 0) {
      final p = _profiles[idx];
      if (clientKey != null && clientKey.trim().isNotEmpty) {
        p.clientKey = clientKey.trim();
      }
      _activeIndex = idx;
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final name = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      _profiles.add(
        ServerProfile(
          id: id,
          name: name,
          baseUrl: baseUrl,
          clientKey: clientKey?.trim(),
        ),
      );
      _activeIndex = _profiles.length - 1;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(int index) async {
    if (index >= 0 && index < _profiles.length) {
      _activeIndex = index;
      await _persist();
      notifyListeners();
    }
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    if (active == null) throw StateError('No active server');
    final client = _createInsecureHttpClient();
    final uri = Uri.parse('${active!.baseUrl}/api/auth/login');
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    if (active!.clientKey != null)
      req.headers.add('X-Client-Key', active!.clientKey!);
    req.write(jsonEncode({'username': username, 'password': password}));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      return false;
    }
    final body = await resp.transform(utf8.decoder).join();
    final map = jsonDecode(body) as Map<String, dynamic>;
    active!.accessToken = map['access_token'] as String?;
    active!.refreshToken = map['refresh_token'] as String?;
    if (active!.accessToken == null || active!.refreshToken == null)
      return false;
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> refresh() async {
    if (active == null) return false;
    // Try refresh normally; if no refresh token, attempt silent re-login using saved creds is not possible, so return false
    if (active!.refreshToken == null) return false;
    final client = _createInsecureHttpClient();
    final uri = Uri.parse('${active!.baseUrl}/api/auth/refresh');
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    if (active!.clientKey != null)
      req.headers.add('X-Client-Key', active!.clientKey!);
    req.write(jsonEncode({'refresh_token': active!.refreshToken}));
    final resp = await req.close();
    if (resp.statusCode != 200) return false;
    final body = await resp.transform(utf8.decoder).join();
    final map = jsonDecode(body) as Map<String, dynamic>;
    active!.accessToken = map['access_token'] as String?;
    active!.refreshToken = map['refresh_token'] as String?;
    if (active!.accessToken == null || active!.refreshToken == null)
      return false;
    await _persist();
    notifyListeners();
    return true;
  }

  Dio createDio() {
    if (active == null) throw StateError('Base URL not set');
    final dio = Dio(
      BaseOptions(
        baseUrl: active!.baseUrl,
        connectTimeout: const Duration(seconds: 10),
      ),
    );
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
        _createInsecureHttpClient;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (active?.clientKey != null)
            options.headers['X-Client-Key'] = active!.clientKey;
          if (active?.accessToken != null) {
            options.headers['Authorization'] = 'Bearer ${active!.accessToken}';
          }
          return handler.next(options);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            if (await refresh()) {
              final req = await dio.request(
                e.requestOptions.path,
                data: e.requestOptions.data,
                options: Options(
                  method: e.requestOptions.method,
                  headers: e.requestOptions.headers,
                  contentType: e.requestOptions.contentType,
                ),
                queryParameters: e.requestOptions.queryParameters,
              );
              return handler.resolve(req);
            }
          }
          return handler.next(e);
        },
      ),
    );
    return dio;
  }

  HttpClient newHttpClient() => _createInsecureHttpClient();

  HttpClient _createInsecureHttpClient([SecurityContext? secContext]) {
    final client = HttpClient(context: secContext);
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  Future<Map<String, dynamic>?> me() async {
    if (active == null) return null;
    final dio = createDio();
    final resp = await dio.get('/api/me');
    if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
    return null;
  }

  Future<bool> changeCredentials({
    required String username,
    required String newPassword,
  }) async {
    if (active == null) return false;
    final dio = createDio();
    final resp = await dio.post(
      '/api/auth/change_credentials',
      data: {'username': username, 'new_password': newPassword},
    );
    return resp.statusCode == 204;
  }

  Future<void> logout() async {
    if (active != null) {
      active!.accessToken = null;
      active!.refreshToken = null;
      await _persist();
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final list = _profiles.map((p) => p.toJson()).toList();
    await _storage.write(key: 'profiles', value: conv.jsonEncode(list));
    await _storage.write(key: 'activeIndex', value: _activeIndex?.toString());
  }
}
