import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// package:http only (no dart:io), so this works on every platform. Every call
// has a time limit and fails with a sentence meant for people.

const String kOfflineMessage = "You're offline. Check your internet connection and try again.";
const String kNoAnswerMessage = "The PIO website didn't answer. Try again later.";
const String kServerTroubleMessage = 'Something went wrong on the PIO website. Try again later.';

class NetException implements Exception {
  const NetException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class NetFile {
  const NetFile(this.filename, this.contentType, this.bytes);
  final String filename;
  final String contentType;
  final Uint8List bytes;
}

class Net {
  Net({http.Client? client, this.timeout = const Duration(seconds: 15)}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// For streaming downloads (the updater).
  http.Client get client => _client;

  static const _headers = {
    'Accept': 'application/json',
    'Cache-Control': 'no-cache',
    'User-Agent': 'elayout-app',
  };

  Future<Object?> getJson(Uri uri) async {
    final r = await _run(() => _client.get(uri, headers: _headers), timeout);
    return _decode(_check(r));
  }

  Future<Uint8List> getBytes(Uri uri, {int maxBytes = 50 * 1024 * 1024}) async {
    return _run(() async {
      final req = http.Request('GET', uri)..headers.addAll({'User-Agent': 'elayout-app'});
      final res = await _client.send(req);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await res.stream.drain<void>();
        throw _statusError(res.statusCode, null);
      }
      final length = res.contentLength;
      if (length != null && length > maxBytes) {
        await res.stream.drain<void>();
        throw const NetException(kServerTroubleMessage);
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in res.stream) {
        out.add(chunk);
        if (out.length > maxBytes) throw const NetException(kServerTroubleMessage);
      }
      return out.takeBytes();
    }, timeout);
  }

  Future<Object?> postForm(
    Uri uri, {
    Map<String, String> fields = const {},
    Map<String, NetFile> files = const {},
    Duration? timeout,
  }) async {
    final r = await _run(() async {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll({'Accept': 'application/json', 'User-Agent': 'elayout-app'})
        ..fields.addAll(fields);
      files.forEach((field, f) {
        req.files.add(http.MultipartFile.fromBytes(
          field,
          f.bytes,
          filename: f.filename,
          contentType: MediaType.parse(f.contentType),
        ));
      });
      return http.Response.fromStream(await _client.send(req));
    }, timeout ?? this.timeout);
    return _decode(_check(r));
  }

  void close() => _client.close();

  static Future<T> _run<T>(Future<T> Function() call, Duration timeout) async {
    try {
      return await call().timeout(timeout);
    } on NetException {
      rethrow;
    } on TimeoutException {
      throw const NetException(kNoAnswerMessage);
    } catch (_) {
      // A refused connection, a failed name lookup, a dropped link: on every
      // platform these all mean "can't reach the website".
      throw const NetException(kOfflineMessage);
    }
  }

  static http.Response _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return r;
    throw _statusError(r.statusCode, r);
  }

  static NetException _statusError(int status, http.Response? r) {
    if (r != null && status >= 400 && status < 500) {
      try {
        final body = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (body is Map && body['error'] is String && (body['error'] as String).trim().isNotEmpty) {
          return NetException(body['error'] as String, status: status);
        }
      } catch (_) {}
    }
    return NetException(kServerTroubleMessage, status: status);
  }

  static Object? _decode(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    } catch (_) {
      throw NetException(kServerTroubleMessage, status: r.statusCode);
    }
  }
}
