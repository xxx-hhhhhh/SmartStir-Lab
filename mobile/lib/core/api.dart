import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SmartStirApi {
  SmartStirApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;
  String deviceId = 'stirrer-001';
  String labName = '';
  void selectDevice(String id, String lab) { deviceId = id; labName = lab; }
  final http.Client _client = http.Client();

  void close() => _client.close();

  static String validateBaseUrl(String value) {
    final input = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery ||
        uri.path.isNotEmpty) {
      throw ApiError('请输入 HTTPS 服务地址，例如 https://your-api.up.railway.app');
    }
    return input;
  }

  static Future<SmartStirApi> register(String base, String username, String password) async {
    final url = validateBaseUrl(base);
    final client = http.Client();
    try {
      final response = await client.post(Uri.parse('$url/api/v1/register'),
        headers: const {'Content-Type':'application/json'},
        body: jsonEncode({'username': username, 'password': password}))
        .timeout(const Duration(seconds: 12));
      final data = _decodeMap(response);
      if (response.statusCode != 201) {
        throw ApiError(_extractError(data, response.statusCode), response.statusCode);
      }
      final token = data['access_token'];
      if (token is! String || token.isEmpty) throw ApiError('Invalid registration response');
      return SmartStirApi(baseUrl: url, token: token);
    } on TimeoutException {
      throw ApiError('Server timeout');
    } finally { client.close(); }
  }

  static Future<SmartStirApi> login(String base, String username, String password) async {
    final url = validateBaseUrl(base);
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$url/api/v1/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 12));
      final data = _decodeMap(response);
      if (response.statusCode != 200) {
        throw ApiError(_extractError(data, response.statusCode), response.statusCode);
      }
      final token = data['access_token'];
      if (token is! String || token.isEmpty) throw ApiError('服务器没有返回有效登录令牌');
      return SmartStirApi(baseUrl: url, token: token);
    } on TimeoutException {
      throw ApiError('服务器连接超时，请检查 HTTPS 地址及后端部署');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _decodeMap(http.Response r) {
    try {
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is Map<String, dynamic>) return data;
    } catch (_) { /* Keep original HTTP status for the caller. */ }
    return {'detail': '服务器返回的数据格式不正确'};
  }

  static String _extractError(Map<String, dynamic> data, int code) {
    final d = data['detail'];
    if (d is String && d.isNotEmpty) return '$d（HTTP $code）';
    return '网络请求失败：HTTP $code';
  }

  Future<Map<String, dynamic>> _request(String method, String path, [Object? body]) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
      final r = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10))
          : await _client.post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 10));
      final data = _decodeMap(r);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw ApiError(_extractError(data, r.statusCode), r.statusCode);
      }
      return data;
    } on TimeoutException {
      throw ApiError('请求超时：网络不可用或后端未响应');
    }
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl$path'),
        headers: {'Authorization':'Bearer $token'})
        .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiError(_extractError(_decodeMap(response), response.statusCode), response.statusCode);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! List) throw ApiError('Invalid server list response');
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on TimeoutException { throw ApiError('Server timeout'); }
  }

  Future<List<Map<String, dynamic>>> labs() => _getList('/api/v1/labs');
  Future<Map<String, dynamic>> createLab(String name) =>
      _request('POST','/api/v1/labs',{'name':name});
  Future<List<Map<String, dynamic>>> invitations() =>
      _getList('/api/v1/invitations');
  Future<void> respondInvitation(String id, bool accept) async {
    await _request('POST','/api/v1/invitations/$id/${accept ? "accept" : "decline"}',{});
  }
  Future<List<Map<String, dynamic>>> labDevices(String labId) =>
      _getList('/api/v1/labs/$labId/devices');
  Future<Map<String, dynamic>> addDevice(String labId, String id,
      String pairingCode, String label) =>
      _request('POST','/api/v1/labs/$labId/devices',
        {'device_id':id,'pairing_code':pairingCode,'label':label});
  Future<Map<String, dynamic>> inviteMember(String labId, String username) =>
      _request('POST','/api/v1/labs/$labId/invitations',{'username':username});
  Future<List<Map<String,dynamic>>> labMembers(String labId) =>
      _getList('/api/v1/labs/$labId/members');

  Future<void> logout() async {
    await _request('POST', '/api/v1/logout', {});
  }

  Future<Map<String, dynamic>> device() =>
      _request('GET', '/api/v1/devices/${Uri.encodeComponent(deviceId)}');

  Future<Map<String, dynamic>> sendCommand(String command, {int? value}) =>
      _request('POST', '/api/v1/devices/${Uri.encodeComponent(deviceId)}/commands', {
        'command': command,
        if (value != null) 'value': value,
      });

  Future<Map<String, dynamic>> commandStatus(String id) =>
      _request('GET', '/api/v1/devices/${Uri.encodeComponent(deviceId)}/commands/$id');

  Future<List<Map<String, dynamic>>> events() async {
    try {
      final r = await _client.get(Uri.parse('$baseUrl/api/v1/devices/${Uri.encodeComponent(deviceId)}/events'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        throw ApiError(_extractError(_decodeMap(r), r.statusCode), r.statusCode);
      }
      final raw = jsonDecode(utf8.decode(r.bodyBytes));
      if (raw is! List) throw ApiError('事件数据格式不正确');
      return raw.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    } on TimeoutException {
      throw ApiError('事件查询超时');
    }
  }
}
