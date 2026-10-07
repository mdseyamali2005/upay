import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Talks to the upay Voice Guard call engine.
class AgentApi {
  /// Last known PC address. The phone also searches its own Wi-Fi, because
  /// this address changes.
  static const _lan = 'http://172.20.10.2:8000';
  static const _live = 'https://upay-voice-guard.onrender.com';
  static const _timeout = Duration(seconds: 20);
  static const _probe = Duration(seconds: 3);
  static String? _base;

  static Future<bool> _healthy(String url, Duration timeout) async {
    try {
      final res = await http.get(Uri.parse('$url/health')).timeout(timeout);
      return res.statusCode == 200 && res.body.contains('upay-voice-guard');
    } catch (_) {
      return false;
    }
  }

  /// Finds the voice server after the PC address changes.
  static Future<String?> _scanLan() async {
    if (kIsWeb) return null;
    final prefixes = <String>{};
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4 || addr.address.startsWith('127.')) continue;
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    } catch (_) {
      return null;
    }
    for (final prefix in prefixes) {
      for (var start = 1; start <= 254; start += 30) {
        final batch = <Future<String?>>[];
        for (var host = start; host < start + 30 && host <= 254; host++) {
          final url = 'http://$prefix.$host:8000';
          batch.add(() async {
            if (await _healthy(url, const Duration(milliseconds: 500))) return url;
            return null;
          }());
        }
        final hits = await Future.wait(batch);
        for (final hit in hits) {
          if (hit != null) return hit;
        }
      }
    }
    return null;
  }

  static Future<String> _server({bool refresh = false}) async {
    final cached = _base;
    if (!refresh && cached != null && cached != _live) {
      if (await _healthy(cached, const Duration(seconds: 2))) return cached;
    }
    _base = null;
    final options = <String>[
      'http://127.0.0.1:8000',
      _lan,
      if (!kIsWeb && Platform.isAndroid) 'http://10.0.2.2:8000',
    ];
    final found = Completer<String?>();
    var pending = options.length;
    for (final url in options) {
      _healthy(url, _probe).then((ok) {
        if (ok && !found.isCompleted) found.complete(url);
        pending--;
        if (pending == 0 && !found.isCompleted) found.complete(null);
      });
    }
    final hit = await found.future;
    if (hit != null) {
      _base = hit;
      return hit;
    }
    final scanned = await _scanLan();
    if (scanned != null) {
      _base = scanned;
      return scanned;
    }
    if (await _healthy(_live, _probe)) return _live;
    throw const AgentException('এজেন্ট এখন সাড়া দিচ্ছে না। ফোন আর পিসি একই ওয়াইফাইতে রাখুন।');
  }

  static Future<String> voiceUrl(String text) async {
    final base = await _server();
    return '$base/tts?text=${Uri.encodeQueryComponent(text)}';
  }

  static Future<AgentTurn> start() async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final baseUrl = await _server(refresh: attempt > 0);
        final res = await http
            .post(Uri.parse('$baseUrl/session/start'))
            .timeout(_timeout);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          return AgentTurn.fromJson(data);
        }
      } catch (error) {
        lastError = error;
      }
      _base = null;
    }
    if (lastError is AgentException) throw lastError;
    throw const AgentException('এজেন্ট এখন সাড়া দিচ্ছে না। ফোন আর পিসি একই ওয়াইফাইতে রাখুন।');
  }

  static Future<AgentTurn> send(String sessionId, String kind, String value) async {
    final baseUrl = await _server();
    final res = await http
        .post(
          Uri.parse('$baseUrl/session/$sessionId/input'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'kind': kind, 'value': value}),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      _base = null;
      throw const AgentException('উত্তর আনা যায়নি');
    }
    return AgentTurn.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Neural Bangla voice. Returns null if the server has no voice yet.
  static Future<Uint8List?> speak(String text) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final baseUrl = await _server(refresh: attempt > 0);
        final res = await http
            .post(
              Uri.parse('$baseUrl/tts'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'text': text}),
            )
            .timeout(const Duration(seconds: 40));
        if (res.statusCode == 200 && res.bodyBytes.length >= 200) return res.bodyBytes;
      } catch (_) {}
      _base = null;
    }
    return null;
  }

  /// Turns a short WAV recording into Bangla text.
  static Future<String?> transcribe(Uint8List audio) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final baseUrl = await _server(refresh: attempt > 0);
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/stt'));
        request.files.add(http.MultipartFile.fromBytes('audio', audio, filename: 'speech.wav'));
        final sent = await request.send().timeout(_timeout);
        final body = await sent.stream.bytesToString();
        if (sent.statusCode != 200) {
          _base = null;
          continue;
        }
        final data = jsonDecode(body) as Map<String, dynamic>;
        final text = (data['text'] as String?)?.trim();
        if (text == null || text.isEmpty) return null;
        return text;
      } catch (_) {
        _base = null;
      }
    }
    return null;
  }

  /// Fetch latest user info (balance + transactions) from the backend.
  /// Returns null if the server is unreachable.
  static Future<Map<String, dynamic>?> fetchUserInfo() async {
    try {
      final baseUrl = await _server();
      final res = await http
          .get(Uri.parse('$baseUrl/user/info'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<dynamic>?> fetchContacts() async {
    try {
      final baseUrl = await _server();
      final res = await http.get(Uri.parse('$baseUrl/contacts')).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['contacts'] as List<dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> addContact(String name, String phoneNumber) async {
    try {
      final baseUrl = await _server();
      final res = await http.post(
        Uri.parse('$baseUrl/contacts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'phone_number': phoneNumber}),
      ).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class AgentTurn {
  final String? sessionId;
  final String say;
  final String expect;
  final int? digits;
  final bool end;

  const AgentTurn({
    this.sessionId,
    required this.say,
    required this.expect,
    this.digits,
    required this.end,
  });

  factory AgentTurn.fromJson(Map<String, dynamic> json) {
    return AgentTurn(
      sessionId: json['session_id'] as String?,
      say: (json['say'] as String?) ?? '',
      expect: (json['expect'] as String?) ?? 'speech',
      digits: json['digits'] as int?,
      end: json['end'] == true,
    );
  }
}

class AgentException implements Exception {
  final String message;
  const AgentException(this.message);
  @override
  String toString() => message;
}
