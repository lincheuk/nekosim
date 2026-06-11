import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nekosim_asset.dart';

/// Cloud reminder bridge speaking the SimJiang reminder-server protocol:
///
///   GET  /api/status
///   POST /api/register                  -> { apiKey }
///   POST /api/sync          X-API-Key   payload { settings, records }
///   POST /api/test-telegram X-API-Key
///   POST /api/test-email    X-API-Key
///   POST /api/check-now     X-API-Key
///
/// Server source: SimJiang server/simjiang-reminder/server.py
class NekoSimCloudConfig {
  bool enabled;
  bool autoSync;
  String serverUrl;
  String apiKey;
  int remindDays;
  bool telegramEnabled;
  String botToken;
  String chatId;
  bool emailEnabled;
  String smtpHost;
  int smtpPort;
  String smtpUser;
  String smtpPass;
  String smtpFrom;
  String smtpTo;

  NekoSimCloudConfig({
    this.enabled = false,
    this.autoSync = false,
    this.serverUrl = '',
    this.apiKey = '',
    this.remindDays = 7,
    this.telegramEnabled = false,
    this.botToken = '',
    this.chatId = '',
    this.emailEnabled = false,
    this.smtpHost = '',
    this.smtpPort = 465,
    this.smtpUser = '',
    this.smtpPass = '',
    this.smtpFrom = '',
    this.smtpTo = '',
  });
}

class CloudResult {
  final bool ok;
  final String message;
  const CloudResult(this.ok, this.message);
}

class NekoSimCloudService extends ChangeNotifier {
  static final NekoSimCloudService _instance = NekoSimCloudService._internal();
  factory NekoSimCloudService() => _instance;
  NekoSimCloudService._internal();

  static final Logger _log = Logger('NekoSimCloudService');
  static const _prefix = 'nekosim.cloud.';

  final NekoSimCloudConfig config = NekoSimCloudConfig();
  SharedPreferences? _prefs;
  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    config
      ..enabled = p.getBool('${_prefix}enabled') ?? false
      ..autoSync = p.getBool('${_prefix}autoSync') ?? false
      ..serverUrl = p.getString('${_prefix}serverUrl') ?? ''
      ..apiKey = p.getString('${_prefix}apiKey') ?? ''
      ..remindDays = p.getInt('${_prefix}remindDays') ?? 7
      ..telegramEnabled = p.getBool('${_prefix}tgEnabled') ?? false
      ..botToken = p.getString('${_prefix}botToken') ?? ''
      ..chatId = p.getString('${_prefix}chatId') ?? ''
      ..emailEnabled = p.getBool('${_prefix}emailEnabled') ?? false
      ..smtpHost = p.getString('${_prefix}smtpHost') ?? ''
      ..smtpPort = p.getInt('${_prefix}smtpPort') ?? 465
      ..smtpUser = p.getString('${_prefix}smtpUser') ?? ''
      ..smtpPass = p.getString('${_prefix}smtpPass') ?? ''
      ..smtpFrom = p.getString('${_prefix}smtpFrom') ?? ''
      ..smtpTo = p.getString('${_prefix}smtpTo') ?? '';
    _loaded = true;
    notifyListeners();
  }

  Future<void> persist() async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    _prefs = p;
    await Future.wait([
      p.setBool('${_prefix}enabled', config.enabled),
      p.setBool('${_prefix}autoSync', config.autoSync),
      p.setString('${_prefix}serverUrl', config.serverUrl),
      p.setString('${_prefix}apiKey', config.apiKey),
      p.setInt('${_prefix}remindDays', config.remindDays),
      p.setBool('${_prefix}tgEnabled', config.telegramEnabled),
      p.setString('${_prefix}botToken', config.botToken),
      p.setString('${_prefix}chatId', config.chatId),
      p.setBool('${_prefix}emailEnabled', config.emailEnabled),
      p.setString('${_prefix}smtpHost', config.smtpHost),
      p.setInt('${_prefix}smtpPort', config.smtpPort),
      p.setString('${_prefix}smtpUser', config.smtpUser),
      p.setString('${_prefix}smtpPass', config.smtpPass),
      p.setString('${_prefix}smtpFrom', config.smtpFrom),
      p.setString('${_prefix}smtpTo', config.smtpTo),
    ]);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------

  static String cleanApiKey(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final matches = RegExp(r'[A-Za-z0-9_-]{24,80}')
        .allMatches(t)
        .map((m) => m.group(0)!)
        .where((s) => s.toUpperCase() != 'API' && s.toUpperCase() != 'KEY')
        .toList();
    if (matches.isNotEmpty) return matches.last;
    return t.replaceAll(RegExp(r'[\r\n\t ]+'), '');
  }

  String get _baseUrl => config.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, dynamic> buildPayload(List<NekoSimAsset> assets) {
    return {
      'settings': {
        'remindDays': config.remindDays,
        'tgEnabled': config.telegramEnabled,
        'botToken': config.botToken,
        'chatId': config.chatId,
        'smtpEnabled': config.emailEnabled,
        'smtpHost': config.smtpHost,
        'smtpPort': config.smtpPort,
        'smtpUser': config.smtpUser,
        'smtpPass': config.smtpPass,
        'smtpFrom': config.smtpFrom,
        'smtpTo': config.smtpTo,
        'cloudTelegramEnabled': config.telegramEnabled,
        'cloudEmailEnabled': config.emailEnabled,
      },
      'records': assets
          .map((a) => {
                'id': a.id,
                'number': a.phoneNumber,
                'countryCode': a.countryCode,
                'countryName': a.countryName,
                'operator': a.operatorName,
                'flag': '',
                'expireDate': a.expireDate == null
                    ? ''
                    : '${a.expireDate!.year.toString().padLeft(4, '0')}-${a.expireDate!.month.toString().padLeft(2, '0')}-${a.expireDate!.day.toString().padLeft(2, '0')}',
                'note': a.note,
                'balance': a.balanceNote,
                'eid': a.eid,
                'cycleDays': a.renewalCycleDays,
              })
          .toList(),
    };
  }

  Future<CloudResult> _post(String path, Map<String, dynamic> body,
      {bool auth = true}) async {
    if (_baseUrl.isEmpty) return const CloudResult(false, 'Server URL empty');
    final key = cleanApiKey(config.apiKey);
    if (auth && key.isEmpty) return const CloudResult(false, 'API key empty');
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (auth) 'X-API-Key': key,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      final text = utf8.decode(resp.bodyBytes);
      if (resp.statusCode != 200) {
        return CloudResult(false, 'HTTP ${resp.statusCode}: ${_short(text)}');
      }
      final json = jsonDecode(text);
      if (json is Map && json['ok'] == true) {
        return CloudResult(true, (json['message'] ?? 'OK').toString());
      }
      return CloudResult(
        json is Map && json['ok'] == true,
        json is Map ? (json['error'] ?? json['message'] ?? text).toString() : text,
      );
    } catch (e) {
      _log.warning('Cloud POST $path failed: $e');
      return CloudResult(false, e.toString());
    }
  }

  static String _short(String s) => s.length > 160 ? s.substring(0, 160) : s;

  // -------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------

  Future<CloudResult> status() async {
    if (_baseUrl.isEmpty) return const CloudResult(false, 'Server URL empty');
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return CloudResult(false, 'HTTP ${resp.statusCode}');
      }
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final ok = json is Map && json['ok'] == true;
      return CloudResult(ok, ok ? 'OK' : _short(resp.body));
    } catch (e) {
      return CloudResult(false, e.toString());
    }
  }

  Future<CloudResult> register() async {
    final existing = cleanApiKey(config.apiKey);
    if (existing.isNotEmpty) {
      return const CloudResult(false, 'key_exists');
    }
    if (_baseUrl.isEmpty) return const CloudResult(false, 'Server URL empty');
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/register'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return CloudResult(false, 'HTTP ${resp.statusCode}');
      }
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      final key = (json is Map ? json['apiKey'] : null)?.toString() ?? '';
      if (key.isEmpty) return const CloudResult(false, 'No apiKey in response');
      config.apiKey = key;
      await persist();
      return const CloudResult(true, 'key_generated');
    } catch (e) {
      return CloudResult(false, e.toString());
    }
  }

  Future<CloudResult> sync(List<NekoSimAsset> assets) {
    return _post('/api/sync', buildPayload(assets));
  }

  Future<CloudResult> testTelegram(List<NekoSimAsset> assets) {
    return _post('/api/test-telegram', buildPayload(assets));
  }

  Future<CloudResult> testEmail(List<NekoSimAsset> assets) {
    return _post('/api/test-email', buildPayload(assets));
  }

  Future<CloudResult> checkNow(List<NekoSimAsset> assets) {
    return _post('/api/check-now', buildPayload(assets));
  }

  /// Fire-and-forget auto sync used by the asset service.
  Future<void> maybeAutoSync(List<NekoSimAsset> assets) async {
    await init();
    if (!config.enabled || !config.autoSync) return;
    if (cleanApiKey(config.apiKey).isEmpty || _baseUrl.isEmpty) return;
    final res = await sync(assets);
    if (!res.ok) _log.fine('Auto sync skipped/failed: ${res.message}');
  }
}
